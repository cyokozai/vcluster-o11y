#!/usr/bin/env bash
# scripts/v2/lib.sh - 検証 1/2/3 で共通利用するヘルパー関数
#
# 提供する関数:
#   pass / fail / info / header    : カラー出力
#   start_pf / stop_pfs / wait_http: port-forward 管理
#   run_promql                     : PromQL 実行 + LOG_JSON へ追記 + LOG_MD へ追記
#   fetch_traces                   : Tempo Search API
#   fetch_logs                     : Loki Query Range API
#   record_scrape_targets          : Prometheus /api/v1/targets を JSON に保存 (E-3 対策)
#   restart_pattern_pods           : 各 vcluster の go-api-server を rollout restart (C-1 対策)
#   init_logs                      : LOG_MD / LOG_JSON の雛形作成
#
# 使い方:
#   source scripts/v2/lib.sh
#   init_logs verify2  # LOG_MD / LOG_JSON を自動命名

set -uo pipefail

# ==================== カラー / ユーティリティ ====================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASSED=${PASSED:-0}
FAILED=${FAILED:-0}
RESULTS=()

pass() {
  local msg=$1
  PASSED=$((PASSED + 1))
  RESULTS+=("PASS|${msg}")
  echo -e "  ${GREEN}✅ PASS${NC} ${msg}"
}

fail() {
  local msg=$1
  FAILED=$((FAILED + 1))
  RESULTS+=("FAIL|${msg}")
  echo -e "  ${RED}❌ FAIL${NC} ${msg}"
}

info()   { echo -e "  ${YELLOW}ℹ${NC}  $*"; }
header() { echo -e "\n${BOLD}${CYAN}=== $* ===${NC}"; }

check_deps() {
  for cmd in kubectl curl jq bc; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "エラー: '$cmd' が見つかりません。インストールしてください。" >&2
      exit 1
    fi
  done
}

# ==================== ログ初期化 ====================

# LOG_MD / LOG_JSON / TIMESTAMP を export する
init_logs() {
  local prefix=$1
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LOG_DIR="${LOG_DIR:-docs/v2/logs}"
  mkdir -p "$LOG_DIR"

  LOG_MD="${LOG_DIR}/${prefix}-${TIMESTAMP}.md"
  LOG_JSON="${LOG_DIR}/${prefix}-${TIMESTAMP}.json"

  # JSON 雛形
  cat > "$LOG_JSON" <<EOF
{
  "experiment_id": "${prefix}-${TIMESTAMP}",
  "start_time": "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)",
  "tool_versions": {
    "helm": "$(helm version --short 2>/dev/null | head -1)",
    "vcluster": "$(vcluster --version 2>/dev/null | head -1)",
    "kubectl_client": "$(kubectl version --client -o json 2>/dev/null | jq -r .clientVersion.gitVersion 2>/dev/null || echo unknown)"
  },
  "measurements": {}
}
EOF

  # Markdown 雛形
  cat > "$LOG_MD" <<EOF
# ${prefix} 検証ログ: ${TIMESTAMP}

開始時刻: $(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)

EOF

  export TIMESTAMP LOG_MD LOG_JSON LOG_DIR
  info "LOG_MD=${LOG_MD}"
  info "LOG_JSON=${LOG_JSON}"
}

# JSON の measurements にキー/値を merge
log_json() {
  local key=$1
  local value=$2  # JSON value (string or object as JSON text)

  jq --arg key "$key" --argjson value "$value" \
    '.measurements[$key] = $value' "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"
}

# Markdown にセクションを追記
log_md_section() {
  local title=$1
  local content=$2
  cat >> "$LOG_MD" <<EOF

## ${title}

${content}
EOF
}

# ==================== port-forward 管理 ====================

PF_PIDS=()

cleanup_pfs() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}

start_pf() {
  local resource=$1 local_port=$2 remote_port=$3 ns=${4:-}
  if [[ -n "$ns" ]]; then
    kubectl port-forward "$resource" "${local_port}:${remote_port}" -n "$ns" \
      >/dev/null 2>&1 &
  else
    kubectl port-forward "$resource" "${local_port}:${remote_port}" \
      >/dev/null 2>&1 &
  fi
  PF_PIDS+=($!)
}

wait_http() {
  local url=$1 max=${2:-20}
  local i=0
  while ! curl -sf "$url" >/dev/null 2>&1; do
    sleep 1
    i=$((i + 1))
    if [[ $i -ge $max ]]; then
      return 1
    fi
  done
  return 0
}

# ==================== API クエリ関数 ====================

# Prometheus: instant query を実行し、jq filter で抽出した値を返す
# 引数: $1=query, $2=jq_filter (デフォルト .data.result)
query_prom() {
  local q=$1
  local jq_filter=${2:-.data.result}
  curl -sfG "http://localhost:${PROM_PORT:-9090}/api/v1/query" \
    --data-urlencode "query=${q}" 2>/dev/null | jq -c "$jq_filter" 2>/dev/null || echo "null"
}

# 数値スカラーを抽出 (.data.result[0].value[1])
query_prom_scalar() {
  local q=$1
  curl -sfG "http://localhost:${PROM_PORT:-9090}/api/v1/query" \
    --data-urlencode "query=${q}" 2>/dev/null | \
    jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0"
}

# PromQL を実行し、LOG_JSON / LOG_MD 両方に記録 (00-design.md 形式)
run_promql() {
  local label=$1
  local query=$2

  local result
  result=$(curl -sfG "http://localhost:${PROM_PORT:-9090}/api/v1/query" \
    --data-urlencode "query=${query}" 2>/dev/null || echo '{}')

  # JSON マージ
  log_json "$label" "$(echo "$result" | jq -c '.data.result // []')"

  # Markdown
  {
    echo ""
    echo "### ${label}"
    echo ""
    echo '```promql'
    echo "$query"
    echo '```'
    echo ""
    echo "**Result:**"
    echo ""
    echo '```json'
    echo "$result" | jq -c '.data.result // []'
    echo '```'
  } >> "$LOG_MD"

  # ターミナル表示用に series 数だけ返す
  local n
  n=$(echo "$result" | jq -r '.data.result | length' 2>/dev/null || echo "0")
  info "${label}: ${n} series"
}

# Tempo Search
fetch_traces() {
  local label=$1
  local service_name=$2
  local start_epoch=${3:-$(($(date +%s) - 1800))}
  local end_epoch=${4:-$(date +%s)}

  local result
  result=$(curl -sfG "http://localhost:${TEMPO_PORT:-3200}/api/search" \
    --data-urlencode "tags=service.name=${service_name}" \
    --data-urlencode "start=${start_epoch}" \
    --data-urlencode "end=${end_epoch}" \
    --data-urlencode "limit=10" 2>/dev/null || echo '{}')

  log_json "$label" "$(echo "$result" | jq -c '.traces // []')"
  local n=$(echo "$result" | jq -r '.traces | length' 2>/dev/null || echo "0")
  info "${label}: ${n} traces"
}

# Loki Query Range
fetch_logs() {
  local label=$1
  local selector=$2
  local start_epoch=${3:-$(($(date +%s) - 1800))}
  local end_epoch=${4:-$(date +%s)}

  local start_ns=$((start_epoch * 1000000000))
  local end_ns=$((end_epoch * 1000000000))

  local result
  result=$(curl -sfG "http://localhost:${LOKI_PORT:-3100}/loki/api/v1/query_range" \
    --data-urlencode "query=${selector}" \
    --data-urlencode "start=${start_ns}" \
    --data-urlencode "end=${end_ns}" \
    --data-urlencode "limit=5" 2>/dev/null || echo '{}')

  log_json "$label" "$(echo "$result" | jq -c '.data.result // []')"
  local n=$(echo "$result" | jq -r '.data.result | length' 2>/dev/null || echo "0")
  info "${label}: ${n} streams"
}

# ==================== E-3 対策: Scrape targets 記録 ====================

# Prometheus /api/v1/targets を取得し、go-api-server に関わる scrape job 一覧を LOG_JSON / LOG_MD に保存
record_scrape_targets() {
  local label=${1:-scrape_targets}

  # ローカル port-forward 経由でも、kubectl exec 経由でも取得可能
  local result
  if [[ -n "${PROM_PORT:-}" ]]; then
    result=$(curl -sf "http://localhost:${PROM_PORT}/api/v1/targets" 2>/dev/null || echo '{}')
  else
    result=$(kubectl exec -n monitoring statefulset/prometheus-kube-prometheus-stack-prometheus -- \
      wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null || echo '{}')
  fi

  local targets
  targets=$(echo "$result" | jq -c '[.data.activeTargets[]? | select(.scrapeUrl // "" | test("go-api-server")) | {
    job: .labels.job,
    scrapeUrl: .scrapeUrl,
    scrapeInterval: .scrapeInterval,
    scrapePool: .scrapePool,
    pod: .labels.kubernetes_pod_name // .discoveredLabels.__meta_kubernetes_pod_name,
    namespace: .labels.namespace,
    health: .health
  }]' 2>/dev/null || echo '[]')

  log_json "$label" "$targets"

  {
    echo ""
    echo "## E-3 対策: Scrape targets (go-api-server を対象とする scrape job)"
    echo ""
    echo '```json'
    echo "$targets" | jq '.'
    echo '```'
  } >> "$LOG_MD"

  local n=$(echo "$targets" | jq 'length')
  info "scrape targets for go-api-server: ${n} jobs"
}

# ==================== C-1 対策: Pod 再作成 ====================

# 各 vcluster の go-api-server を rollout restart して累積カウンタをリセット
restart_pattern_pods() {
  header "C-1 対策: go-api-server Pod を再作成してメトリクスカウンタをリセット"
  for vc in vcluster-1 vcluster-2 vcluster-3; do
    info "Restarting ${vc}/go-api-server..."
    vcluster connect "$vc" -n "$vc" >/dev/null 2>&1
    kubectl rollout restart deployment/go-api-server -n default >/dev/null 2>&1 \
      || kubectl rollout restart deployment/go-api-server-pattern-a -n default >/dev/null 2>&1 \
      || kubectl rollout restart deployment/go-api-server-pattern-b -n default >/dev/null 2>&1 \
      || kubectl rollout restart deployment/go-api-server-pattern-c -n default >/dev/null 2>&1 \
      || true
    kubectl rollout status deployment -n default --timeout=120s 2>&1 | head -5 || true
    vcluster disconnect >/dev/null 2>&1
  done
  info "Pod restart completed at: $(date -Iseconds)"

  log_json "pod_restart_completed_at" "\"$(date -Iseconds)\""
}

# ==================== 結果テーブル出力 ====================

print_result_table() {
  echo ""
  header "結果サマリー"
  echo "PASSED: ${PASSED} / FAILED: ${FAILED} / TOTAL: $((PASSED + FAILED))"
  echo ""
  for r in "${RESULTS[@]:-}"; do
    local status=$(echo "$r" | cut -d'|' -f1)
    local msg=$(echo "$r" | cut -d'|' -f2-)
    if [[ "$status" == "PASS" ]]; then
      echo -e "  ${GREEN}✅${NC} ${msg}"
    else
      echo -e "  ${RED}❌${NC} ${msg}"
    fi
  done

  {
    echo ""
    echo "## 結果サマリー"
    echo ""
    echo "- PASSED: ${PASSED}"
    echo "- FAILED: ${FAILED}"
    echo "- TOTAL: $((PASSED + FAILED))"
    echo ""
    for r in "${RESULTS[@]:-}"; do
      local status=$(echo "$r" | cut -d'|' -f1)
      local msg=$(echo "$r" | cut -d'|' -f2-)
      local emoji=$([[ "$status" == "PASS" ]] && echo "✅" || echo "❌")
      echo "- ${emoji} ${msg}"
    done
  } >> "$LOG_MD"

  log_json "summary" "$(jq -nc --arg p "$PASSED" --arg f "$FAILED" '{passed: ($p|tonumber), failed: ($f|tonumber), total: (($p|tonumber) + ($f|tonumber))}')"
}
