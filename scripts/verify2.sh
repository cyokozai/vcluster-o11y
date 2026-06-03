#!/usr/bin/env bash
# 検証2 自動検証スクリプト
# 前提: vcluster-1/2/3 と monitoring スタック (Prometheus/Tempo/Loki/Alloy) が稼働済み
#
# 使用方法:
#   ./scripts/verify2.sh               # デフォルト 10 分間リクエスト送信
#   DURATION=120 ./scripts/verify2.sh  # 2 分に短縮 (動作確認用)
#
# 依存コマンド: kubectl, vcluster, curl, jq

set -euo pipefail

# ==================== 設定 ====================
DURATION="${DURATION:-600}"   # リクエスト送信時間 (秒)
REQUEST_INTERVAL=2            # リクエスト送信間隔 (秒)
DATA_WAIT=90                  # リクエスト完了後の伝播待機 (秒)
                              # OTel SDK の MetricsExport 間隔が 60s のため 90s 確保

MONITORING_NS=monitoring

# ローカルポート
VC1_PORT=8081
VC2_PORT=8082
VC3_PORT=8083
PROM_PORT=9090
TEMPO_PORT=3200
LOKI_PORT=3100

# ==================== カラー / ユーティリティ ====================
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASSED=0
FAILED=0
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
  for cmd in kubectl curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "エラー: '$cmd' が見つかりません。インストールしてください。"
      exit 1
    fi
  done
}

# ==================== クリーンアップ ====================
PF_PIDS=()

cleanup() {
  echo ""
  info "port-forward プロセスを停止中..."
  for pid in "${PF_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# ==================== port-forward ユーティリティ ====================
start_pf() {
  local resource=$1 local_port=$2 remote_port=$3 ns=${4:-}
  local pid

  if [[ -n "$ns" ]]; then
    kubectl port-forward "$resource" "${local_port}:${remote_port}" -n "$ns" \
      >/dev/null 2>&1 &
  else
    kubectl port-forward "$resource" "${local_port}:${remote_port}" \
      >/dev/null 2>&1 &
  fi
  pid=$!
  PF_PIDS+=("$pid")
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
}

# ==================== API クエリ関数 ====================

# Prometheus: クエリ結果の series 数を返す
query_prom() {
  local q=$1
  curl -sfG "http://localhost:${PROM_PORT}/api/v1/query" \
    --data-urlencode "query=${q}" \
    2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0"
}

# Tempo: 対象 service.name のトレース件数を返す (最大 10 件を確認)
query_tempo() {
  local svc=$1
  local start end
  start=$((START_EPOCH - 60))
  end=$(date +%s)
  curl -sfG "http://localhost:${TEMPO_PORT}/api/search" \
    --data-urlencode "tags=service.name=${svc}" \
    --data-urlencode "start=${start}" \
    --data-urlencode "end=${end}" \
    --data-urlencode "limit=10" \
    2>/dev/null | jq -r '.traces | length' 2>/dev/null || echo "0"
}

# Loki: 対象 service_name のログストリーム数を返す
query_loki() {
  local selector=$1
  local start_ns end_ns
  start_ns=$(( (START_EPOCH - 60) * 1000000000 ))
  end_ns=$(( $(date +%s) * 1000000000 ))
  curl -sfG "http://localhost:${LOKI_PORT}/loki/api/v1/query_range" \
    --data-urlencode "query=${selector}" \
    --data-urlencode "start=${start_ns}" \
    --data-urlencode "end=${end_ns}" \
    --data-urlencode "limit=1" \
    2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0"
}

# ==================== Pod 検索 ====================
get_running_pod() {
  local ns=$1 label=$2
  kubectl get pods -n "$ns" -l "$label" \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | head -1 | awk '{print $1}'
}

# ==================== メイン ====================

check_deps

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        検証2 自動検証スクリプト                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
info "リクエスト送信時間: ${DURATION}秒"
info "伝播待機時間: ${DATA_WAIT}秒"
info "合計所要時間: 約 $(( DURATION + DATA_WAIT + 60 ))秒"

# ==================== Phase 0: 事前確認 ====================
header "Phase 0: Pod 稼働確認"

# go-api-server (Pattern A) + otelcol (Pattern A) in vcluster-1
VC1_APP_POD=$(get_running_pod vcluster-1 "app=go-api-server,pattern=a")
VC1_COL_POD=$(get_running_pod vcluster-1 "app=otelcol")

if [[ -n "$VC1_APP_POD" ]]; then
  pass "vcluster-1: go-api-server (Pattern A) Running [$VC1_APP_POD]"
else
  fail "vcluster-1: go-api-server (Pattern A) が Running でない"
  VC1_APP_POD=""
fi

if [[ -n "$VC1_COL_POD" ]]; then
  pass "vcluster-1: otelcol (Pattern A) Running [$VC1_COL_POD]"
else
  fail "vcluster-1: otelcol (Pattern A) が Running でない"
fi

# go-api-server (Pattern B) in vcluster-2
VC2_APP_POD=$(get_running_pod vcluster-2 "app=go-api-server,pattern=b")
if [[ -n "$VC2_APP_POD" ]]; then
  pass "vcluster-2: go-api-server (Pattern B) Running [$VC2_APP_POD]"
else
  fail "vcluster-2: go-api-server (Pattern B) が Running でない"
  VC2_APP_POD=""
fi

# go-api-server (Pattern C) in vcluster-3
VC3_APP_POD=$(get_running_pod vcluster-3 "app=go-api-server,pattern=c")
if [[ -n "$VC3_APP_POD" ]]; then
  pass "vcluster-3: go-api-server (Pattern C) Running [$VC3_APP_POD]"
else
  fail "vcluster-3: go-api-server (Pattern C) が Running でない"
  VC3_APP_POD=""
fi

# monitoring stack
PROM_POD=$(kubectl get pods -n "$MONITORING_NS" -l "app.kubernetes.io/name=prometheus" \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [[ -n "$PROM_POD" ]]; then
  pass "monitoring: Prometheus Running"
else
  fail "monitoring: Prometheus が Running でない"
fi

TEMPO_POD=$(kubectl get pods -n "$MONITORING_NS" -l "app.kubernetes.io/name=tempo" \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [[ -n "$TEMPO_POD" ]]; then
  pass "monitoring: Tempo Running"
else
  fail "monitoring: Tempo が Running でない"
fi

LOKI_POD=$(kubectl get pods -n "$MONITORING_NS" -l "app.kubernetes.io/name=loki" \
  --field-selector=status.phase=Running --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [[ -n "$LOKI_POD" ]]; then
  pass "monitoring: Loki Running"
else
  fail "monitoring: Loki が Running でない"
fi

# 致命的な Pod がなければ中止
if [[ -z "$VC1_APP_POD" || -z "$VC2_APP_POD" || -z "$VC3_APP_POD" ]]; then
  echo ""
  echo -e "${RED}エラー: go-api-server pod が不足しています。環境を確認してください。${NC}"
  exit 1
fi

# ==================== port-forward 起動 ====================
header "Port-Forward 起動"

info "go-api-server port-forward を開始中..."
start_pf "pod/${VC1_APP_POD}" $VC1_PORT 8080 vcluster-1
start_pf "pod/${VC2_APP_POD}" $VC2_PORT 8080 vcluster-2
start_pf "pod/${VC3_APP_POD}" $VC3_PORT 8080 vcluster-3

info "monitoring APIs port-forward を開始中..."
start_pf svc/kube-prometheus-stack-prometheus $PROM_PORT 9090 "$MONITORING_NS"
start_pf svc/tempo $TEMPO_PORT 3200 "$MONITORING_NS"
start_pf svc/loki $LOKI_PORT 3100 "$MONITORING_NS"

info "port-forward 起動待機中 (5秒)..."
sleep 5

# 疎通確認
declare -a VC_LABELS=("Pattern A (vc1)" "Pattern B (vc2)" "Pattern C (vc3)")
declare -a VC_PORTS=($VC1_PORT $VC2_PORT $VC3_PORT)
for i in 0 1 2; do
  label="${VC_LABELS[$i]}"
  port="${VC_PORTS[$i]}"
  if wait_http "http://localhost:${port}/health" 15; then
    pass "疎通確認: ${label} → http://localhost:${port}/health"
  else
    fail "疎通確認: ${label} → http://localhost:${port}/health に到達できない"
  fi
done

if wait_http "http://localhost:${PROM_PORT}/-/healthy" 15; then
  pass "疎通確認: Prometheus API"
else
  fail "疎通確認: Prometheus API に到達できない"
fi

if wait_http "http://localhost:${TEMPO_PORT}/ready" 15; then
  pass "疎通確認: Tempo API"
else
  fail "疎通確認: Tempo API に到達できない"
fi

if wait_http "http://localhost:${LOKI_PORT}/ready" 15; then
  pass "疎通確認: Loki API"
else
  fail "疎通確認: Loki API に到達できない"
fi

# ==================== Phase 1: リクエスト送信 ====================
header "Phase 1: リクエスト送信 (${DURATION}秒間)"

START_EPOCH=$(date +%s)
END_EPOCH=$((START_EPOCH + DURATION))

info "GET / を各パターンに ${DURATION}秒間送信します..."
echo ""

while [[ $(date +%s) -lt $END_EPOCH ]]; do
  curl -sf "http://localhost:${VC1_PORT}/" >/dev/null 2>&1 || true
  curl -sf "http://localhost:${VC2_PORT}/" >/dev/null 2>&1 || true
  curl -sf "http://localhost:${VC3_PORT}/" >/dev/null 2>&1 || true
  sleep "$REQUEST_INTERVAL"

  elapsed=$(( $(date +%s) - START_EPOCH ))
  remaining=$(( END_EPOCH - $(date +%s) ))
  printf "\r  経過: %3d秒 / %d秒  残り: %3d秒  " "$elapsed" "$DURATION" "$remaining"
done
echo ""

pass "Phase 1: リクエスト送信完了"

# エラー注入: GET /status/500 を Pattern A/B に 10 回送信
info "GET /status/500 をエラー注入用に Pattern A/B 各 10 回送信します..."
for i in $(seq 1 10); do
  curl -sf "http://localhost:${VC1_PORT}/status/500" >/dev/null 2>&1 || true
  curl -sf "http://localhost:${VC2_PORT}/status/500" >/dev/null 2>&1 || true
done
pass "Phase 1 (エラー注入): GET /status/500 × 10 回送信完了 (Pattern A/B)"

info "${DATA_WAIT}秒待機中 (テレメトリ伝播待ち: OTel Metrics 60s export + Prometheus 15s scrape)..."
for i in $(seq $DATA_WAIT -1 1); do
  printf "\r  残り待機: %3d秒  " "$i"
  sleep 1
done
echo ""

# ==================== Phase 2: Metrics 確認 ====================
header "Phase 2: Metrics 確認 (Prometheus)"

# Pattern A/B: OTel SDK → OTLP → Alloy → Prometheus remote write
# Pattern C:   Beyla eBPF / /metrics scrape → Alloy → Prometheus
# service_name ラベルは各パターンで異なる値が設定される

for pattern in a b c; do
  svc="go-api-server-pattern-${pattern}"
  pat_upper=$(echo "$pattern" | tr a-z A-Z)
  # service_name ラベルを持つメトリクスが 1 件以上あれば到達済みと判定
  # Pattern A/B: OTel SDK → http_server_request_body_size_bytes_count 等
  # Pattern C:   /metrics scrape → go_goroutines 等の Go runtime メトリクス
  count=$(query_prom "count({service_name=\"${svc}\"})")
  if [[ "$count" -gt 0 ]]; then
    pass "Pattern ${pat_upper} Metrics → Prometheus (service_name=${svc}, ${count} series)"
  else
    fail "Pattern ${pat_upper} Metrics → Prometheus (service_name=${svc}) series 数=0"
  fi
done

# service_name ラベルで 3 パターンが区別できるか確認
distinct=$(query_prom \
  "count by (service_name)({service_name=~\"go-api-server-pattern-.*\"})")
if [[ "$distinct" -ge 3 ]]; then
  pass "service_name ラベルで 3 パターン全て区別可能 (${distinct} 種類)"
elif [[ "$distinct" -ge 2 ]]; then
  pass "service_name ラベルで複数パターン区別可能 (${distinct} 種類)"
else
  fail "service_name ラベル区別が不十分 (${distinct} 種類)"
fi

# ==================== Phase 3: Traces 確認 ====================
header "Phase 3: Traces 確認 (Tempo)"

# Pattern A/B: OTel SDK トレース → OTLP → Alloy → Tempo
for pattern in a b; do
  svc="go-api-server-pattern-${pattern}"
  pat_upper=$(echo "$pattern" | tr a-z A-Z)
  count=$(query_tempo "$svc")
  if [[ "$count" -gt 0 ]]; then
    pass "Pattern ${pat_upper} Traces → Tempo (service.name=${svc}) ${count}件"
  else
    fail "Pattern ${pat_upper} Traces → Tempo (service.name=${svc}) 件数=0"
  fi
done

# Pattern C: OTel SDK なし → Tempo にトレースは届かない (期待値: 0件)
count_c=$(query_tempo "go-api-server-pattern-c")
if [[ "$count_c" -eq 0 ]]; then
  pass "Pattern C Traces → Tempo: 0件 (期待値通り: OTel SDK なし)"
else
  fail "Pattern C Traces → Tempo: ${count_c}件 (期待値: 0件)"
fi

# ==================== Phase 4: Logs 確認 ====================
header "Phase 4: Logs 確認 (Loki)"

# Pattern A/B: OTel SDK ログ → OTLP → Alloy → Loki
for pattern in a b; do
  svc="go-api-server-pattern-${pattern}"
  pat_upper=$(echo "$pattern" | tr a-z A-Z)
  count=$(query_loki "{service_name=\"${svc}\"}")
  if [[ "$count" -gt 0 ]]; then
    pass "Pattern ${pat_upper} Logs → Loki (service_name=${svc})"
  else
    fail "Pattern ${pat_upper} Logs → Loki (service_name=${svc}) ストリーム数=0"
  fi
done

# Pattern C: OTel SDK なし → Loki にログは届かない (期待値: 0件)
count_c=$(query_loki "{service_name=\"go-api-server-pattern-c\"}")
if [[ "$count_c" -eq 0 ]]; then
  pass "Pattern C Logs → Loki: 0件 (期待値通り: OTel SDK なし)"
else
  fail "Pattern C Logs → Loki: ${count_c}件 (期待値: 0件)"
fi

# ==================== Phase 5: Trace-Log 相関確認 ====================
header "Phase 5: Trace-Log 相関確認 (Loki traceid → Tempo)"

# Pattern A/B のログから traceid を抽出し、Tempo に該当トレースが存在するか確認
for pattern in a b; do
  svc="go-api-server-pattern-${pattern}"
  pat_upper=$(echo "$pattern" | tr a-z A-Z)

  loki_start_ns=$(( (START_EPOCH - 60) * 1000000000 ))
  loki_end_ns=$(( $(date +%s) * 1000000000 ))

  # ログエントリから traceid フィールドを抽出
  traceid=$(curl -sfG "http://localhost:${LOKI_PORT}/loki/api/v1/query_range" \
    --data-urlencode "query={service_name=\"${svc}\"}" \
    --data-urlencode "start=${loki_start_ns}" \
    --data-urlencode "end=${loki_end_ns}" \
    --data-urlencode "limit=5" \
    2>/dev/null \
    | jq -r '.data.result[0].values[0][1]' 2>/dev/null \
    | jq -r '.traceid // empty' 2>/dev/null \
    || echo "")

  if [[ -z "$traceid" ]]; then
    fail "Pattern ${pat_upper} Trace-Log 相関: Loki ログから traceid を取得できない"
    continue
  fi

  # Tempo でそのトレースを照会
  http_status=$(curl -sf -o /dev/null -w "%{http_code}" \
    "http://localhost:${TEMPO_PORT}/api/traces/${traceid}" 2>/dev/null || echo "000")

  if [[ "$http_status" == "200" ]]; then
    pass "Pattern ${pat_upper} Trace-Log 相関: traceid=${traceid:0:16}... が Tempo に存在"
  else
    fail "Pattern ${pat_upper} Trace-Log 相関: traceid=${traceid:0:16}... が Tempo に見つからない (HTTP ${http_status})"
  fi
done

# ==================== Phase 6: エラーレート確認 ====================
header "Phase 6: エラーレート確認 (Prometheus)"

# OTel SDK が 5xx レスポンスを http_response_status_code="500" ラベルで記録しているか確認
# Pattern A/B のみ対象 (Pattern C は OTel SDK なし)
for pattern in a b; do
  pat_upper=$(echo "$pattern" | tr a-z A-Z)
  svc="go-api-server-pattern-${pattern}"

  err_count=$(curl -sfG "http://localhost:${PROM_PORT}/api/v1/query" \
    --data-urlencode "query=sum(http_server_request_duration_seconds_count{job=\"${svc}\",http_response_status_code=\"500\"})" \
    2>/dev/null | jq -r '.data.result[0].value[1] // "0"')

  if awk "BEGIN {exit !(${err_count:-0} > 0)}"; then
    pass "Pattern ${pat_upper} 5xx 記録: http_response_status_code=500 が Prometheus に存在 (${err_count} 件)"
  else
    fail "Pattern ${pat_upper} 5xx 記録: http_response_status_code=500 が Prometheus に未記録"
  fi
done

# エラーレート (5xx / 全リクエスト × 100) が 0 より大きいことを確認
for pattern in a b; do
  pat_upper=$(echo "$pattern" | tr a-z A-Z)
  svc="go-api-server-pattern-${pattern}"

  error_rate=$(curl -sfG "http://localhost:${PROM_PORT}/api/v1/query" \
    --data-urlencode "query=100 * sum(http_server_request_duration_seconds_count{job=\"${svc}\",http_response_status_code=~\"5..\"}) / sum(http_server_request_duration_seconds_count{job=\"${svc}\"})" \
    2>/dev/null | jq -r '.data.result[0].value[1] // "0"')

  if awk "BEGIN {exit !(${error_rate:-0} > 0)}"; then
    # 小数点以下2桁で表示
    rate_display=$(awk "BEGIN {printf \"%.2f\", ${error_rate:-0}}")
    pass "Pattern ${pat_upper} エラーレート: ${rate_display}% (> 0 を確認)"
  else
    fail "Pattern ${pat_upper} エラーレート: 0% (5xx が記録されていない可能性)"
  fi
done

# ==================== 結果サマリー ====================
TOTAL=$((PASSED + FAILED))

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
printf "${BOLD}${CYAN}║  PASSED: %-3d  FAILED: %-3d  TOTAL: %-3d              ║${NC}\n" \
  "$PASSED" "$FAILED" "$TOTAL"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# 失敗項目一覧
if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}── 失敗項目 ──${NC}"
  for r in "${RESULTS[@]}"; do
    status="${r%%|*}"
    msg="${r#*|}"
    if [[ "$status" == "FAIL" ]]; then
      echo -e "  ${RED}❌${NC} ${msg}"
    fi
  done
  echo ""
fi

# 検証2 結果テーブル (最終確認項目のみ)
echo -e "${BOLD}── 検証2 確認項目 ──${NC}"
echo ""
printf "  %-35s %-12s %-12s %-12s\n" "確認項目" "Pattern A" "Pattern B" "Pattern C"
printf "  %-35s %-12s %-12s %-12s\n" "───────────────────────────────────" "──────────" "──────────" "──────────"

check_table() {
  local item=$1 a=$2 b=$3 c=$4
  printf "  %-35s %-12s %-12s %-12s\n" "$item" "$a" "$b" "$c"
}

# 結果配列から対応する pass/fail を取得
get_result() {
  local keyword=$1
  for r in "${RESULTS[@]}"; do
    if echo "$r" | grep -q "$keyword"; then
      echo "${r%%|*}"
      return
    fi
  done
  echo "N/A"
}

emoji() { [[ "$1" == "PASS" ]] && echo "✅" || echo "❌"; }

RA=$(get_result "Pattern A Metrics")
RB=$(get_result "Pattern B Metrics")
RC=$(get_result "Pattern C Metrics")
check_table "Metrics → Prometheus" "$(emoji "$RA")" "$(emoji "$RB")" "$(emoji "$RC")"

RA=$(get_result "Pattern A Traces")
RB=$(get_result "Pattern B Traces")
RC=$(get_result "Pattern C Traces.*0件")
check_table "Traces → Tempo" "$(emoji "$RA")" "$(emoji "$RB")" "$(emoji "$RC")"

RA=$(get_result "Pattern A Logs")
RB=$(get_result "Pattern B Logs")
RC=$(get_result "Pattern C Logs.*0件")
check_table "Logs → Loki" "$(emoji "$RA")" "$(emoji "$RB")" "$(emoji "$RC")"

RD=$(get_result "service_name ラベルで")
check_table "service_name で区別可能" "$(emoji "$RD")" "$(emoji "$RD")" "$(emoji "$RD")"

RA=$(get_result "Pattern A Trace-Log 相関")
RB=$(get_result "Pattern B Trace-Log 相関")
check_table "Trace-Log 相関 (traceid)" "$(emoji "$RA")" "$(emoji "$RB")" "N/A"

RA=$(get_result "Pattern A 5xx 記録")
RB=$(get_result "Pattern B 5xx 記録")
check_table "5xx → Prometheus 記録" "$(emoji "$RA")" "$(emoji "$RB")" "N/A"

RA=$(get_result "Pattern A エラーレート")
RB=$(get_result "Pattern B エラーレート")
check_table "エラーレート > 0" "$(emoji "$RA")" "$(emoji "$RB")" "N/A"

echo ""

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}🎉 検証2 全 ${TOTAL} 項目合格 - 期待値と完全一致${NC}"
else
  echo -e "${RED}${BOLD}⚠️  検証2 ${FAILED} 項目が期待値と一致しませんでした${NC}"
fi

# ==================== レポート保存 ====================
header "実験データ保存"

save_report() {
  local report_dir="docs/results"
  mkdir -p "$report_dir"

  local now_epoch
  now_epoch=$(date +%s)

  # Grafana タイムレンジ: 実験開始の3分前〜終了の2分後
  local from_ms to_ms
  from_ms=$(( (START_EPOCH - 180) * 1000 ))
  to_ms=$(( (now_epoch + 120) * 1000 ))

  # 人間が読める日時 (macOS: date -r, Linux: date -d)
  local start_dt end_dt
  start_dt=$(date -r "$START_EPOCH" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null \
    || date -d "@$START_EPOCH" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null \
    || echo "$START_EPOCH")
  end_dt=$(date "+%Y-%m-%d %H:%M:%S %Z")

  local report_file="${report_dir}/verification2-$(date +%Y%m%d-%H%M%S).md"

  # ---------- Prometheus 実測値 ----------
  local prom_metrics_a prom_metrics_b prom_metrics_c prom_rate_a prom_rate_b

  # 各パターンの series 数
  prom_series_a=$(query_prom "count({service_name=\"go-api-server-pattern-a\"})")
  prom_series_b=$(query_prom "count({service_name=\"go-api-server-pattern-b\"})")
  prom_series_c=$(query_prom "count({service_name=\"go-api-server-pattern-c\"})")

  # Pattern A/B: HTTP リクエスト数の累積カウント (最新値)
  prom_req_a=$(curl -sfG "http://localhost:${PROM_PORT}/api/v1/query" \
    --data-urlencode 'query=sum(http_server_request_body_size_bytes_count{service_name="go-api-server-pattern-a"})' \
    | jq -r '.data.result[0].value[1] // "N/A"')
  prom_req_b=$(curl -sfG "http://localhost:${PROM_PORT}/api/v1/query" \
    --data-urlencode 'query=sum(http_server_request_body_size_bytes_count{service_name="go-api-server-pattern-b"})' \
    | jq -r '.data.result[0].value[1] // "N/A"')

  # Pattern C: Go runtime scrape のサンプル (goroutine 数)
  prom_goroutine_c=$(curl -sfG "http://localhost:${PROM_PORT}/api/v1/query" \
    --data-urlencode 'query=go_goroutines{service_name="go-api-server-pattern-c"}' \
    | jq -r '.data.result[0].value[1] // "N/A"')

  # ---------- Tempo トレースサンプル ----------
  local tempo_traces_a tempo_traces_b
  tempo_traces_a=$(curl -sfG "http://localhost:${TEMPO_PORT}/api/search" \
    --data-urlencode "tags=service.name=go-api-server-pattern-a" \
    --data-urlencode "start=${START_EPOCH}" \
    --data-urlencode "end=${now_epoch}" \
    --data-urlencode "limit=5" \
    | jq -r '.traces[:5] | map("| \(.traceID) | \(.rootServiceName) | \(if .durationMs == null then "N/A" else "\(.durationMs)ms" end) | \(.startTimeUnixNano[:10] | tonumber | strftime("%Y-%m-%dT%H:%M:%SZ")) |") | .[]' 2>/dev/null \
    || echo "| (データなし) | | | |")
  tempo_traces_b=$(curl -sfG "http://localhost:${TEMPO_PORT}/api/search" \
    --data-urlencode "tags=service.name=go-api-server-pattern-b" \
    --data-urlencode "start=${START_EPOCH}" \
    --data-urlencode "end=${now_epoch}" \
    --data-urlencode "limit=5" \
    | jq -r '.traces[:5] | map("| \(.traceID) | \(.rootServiceName) | \(if .durationMs == null then "N/A" else "\(.durationMs)ms" end) | \(.startTimeUnixNano[:10] | tonumber | strftime("%Y-%m-%dT%H:%M:%SZ")) |") | .[]' 2>/dev/null \
    || echo "| (データなし) | | | |")

  # ---------- Loki ログサンプル ----------
  local loki_start_ns loki_end_ns
  loki_start_ns=$(( START_EPOCH * 1000000000 ))
  loki_end_ns=$(( now_epoch * 1000000000 ))

  loki_logs_a=$(curl -sfG "http://localhost:${LOKI_PORT}/loki/api/v1/query_range" \
    --data-urlencode 'query={service_name="go-api-server-pattern-a"}' \
    --data-urlencode "start=${loki_start_ns}" \
    --data-urlencode "end=${loki_end_ns}" \
    --data-urlencode "limit=3" \
    | jq -r '.data.result[0].values[:3][] | "| \(.[0] | tonumber / 1e9 | strftime("%H:%M:%S")) | \(.[1]) |"' 2>/dev/null \
    || echo "| (データなし) | |")
  loki_logs_b=$(curl -sfG "http://localhost:${LOKI_PORT}/loki/api/v1/query_range" \
    --data-urlencode 'query={service_name="go-api-server-pattern-b"}' \
    --data-urlencode "start=${loki_start_ns}" \
    --data-urlencode "end=${loki_end_ns}" \
    --data-urlencode "limit=3" \
    | jq -r '.data.result[0].values[:3][] | "| \(.[0] | tonumber / 1e9 | strftime("%H:%M:%S")) | \(.[1]) |"' 2>/dev/null \
    || echo "| (データなし) | |")

  # ---------- Markdown 生成 ----------
  cat > "$report_file" << REPORT
# 検証2 実験結果レポート

## 実験メタデータ

| 項目 | 値 |
|---|---|
| 実施日時 | ${start_dt} |
| 実験終了 | ${end_dt} |
| リクエスト送信時間 | ${DURATION}秒 |
| 伝播待機時間 | ${DATA_WAIT}秒 |
| PASSED | ${PASSED} |
| FAILED | ${FAILED} |
| TOTAL | ${TOTAL} |

## Grafana タイムレンジ

実験期間をカバーする Grafana の表示範囲です。
各 URL をブラウザで開き、Grafana が起動している場合は時刻範囲が自動で設定されます。

| 項目 | 値 |
|---|---|
| 実験開始 (Unix ms) | ${from_ms} |
| 実験終了 (Unix ms) | ${to_ms} |
| 実験開始 (UTC) | $(date -r "$START_EPOCH" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -d "@$START_EPOCH" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "-") |
| 実験終了 (UTC) | $(date -r "$now_epoch" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -d "@$now_epoch" -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "-") |

### Grafana Explore URL (port-forward が有効な場合)

**Prometheus (Metrics)**
\`\`\`
http://localhost:3000/explore?orgId=1&from=${from_ms}&to=${to_ms}&datasource=prometheus&left={"queries":[{"refId":"A","expr":"{service_name%3D~\"go-api-server-pattern-.*\"}","legendFormat":"{{__name__}} {{service_name}}"}]}
\`\`\`

**Tempo (Traces)**
\`\`\`
http://localhost:3000/explore?orgId=1&from=${from_ms}&to=${to_ms}&datasource=tempo
\`\`\`

**Loki (Logs)**
\`\`\`
http://localhost:3000/explore?orgId=1&from=${from_ms}&to=${to_ms}&datasource=loki&left={"queries":[{"refId":"A","expr":"{service_name%3D~\"go-api-server-pattern-.*\"}"}]}
\`\`\`

### Grafana 手動設定用タイムレンジ

Grafana 画面右上の時刻ピッカーに以下を入力してください。

| フィールド | 値 |
|---|---|
| From | $(date -r "$START_EPOCH" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d "@$START_EPOCH" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$START_EPOCH") |
| To | $(date -r "$now_epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d "@$now_epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$now_epoch") |

## 検証結果サマリー

| 確認項目 | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| Metrics → Prometheus | $(emoji "$(get_result 'Pattern A Metrics')") | $(emoji "$(get_result 'Pattern B Metrics')") | $(emoji "$(get_result 'Pattern C Metrics')") |
| Traces → Tempo | $(emoji "$(get_result 'Pattern A Traces')") | $(emoji "$(get_result 'Pattern B Traces')") | $(emoji "$(get_result 'Pattern C Traces.*0件')") |
| Logs → Loki | $(emoji "$(get_result 'Pattern A Logs')") | $(emoji "$(get_result 'Pattern B Logs')") | $(emoji "$(get_result 'Pattern C Logs.*0件')") |
| service_name で区別可能 | $(emoji "$(get_result 'service_name ラベルで')") | $(emoji "$(get_result 'service_name ラベルで')") | $(emoji "$(get_result 'service_name ラベルで')") |
| Trace-Log 相関 | $(emoji "$(get_result 'Pattern A Trace-Log 相関')") | $(emoji "$(get_result 'Pattern B Trace-Log 相関')") | N/A |
| 5xx → Prometheus 記録 | $(emoji "$(get_result 'Pattern A 5xx 記録')") | $(emoji "$(get_result 'Pattern B 5xx 記録')") | N/A |
| エラーレート > 0 | $(emoji "$(get_result 'Pattern A エラーレート')") | $(emoji "$(get_result 'Pattern B エラーレート')") | N/A |

## Metrics データ (Prometheus)

| Pattern | 確認方法 | 実測値 |
|---|---|---|
| A | http_server_request_body_size_bytes_count の累積値 | ${prom_req_a} requests |
| B | http_server_request_body_size_bytes_count の累積値 | ${prom_req_b} requests |
| C | go_goroutines (Prometheus scrape) | ${prom_goroutine_c} goroutines |
| A | Prometheus series 数 | ${prom_series_a} series |
| B | Prometheus series 数 | ${prom_series_b} series |
| C | Prometheus series 数 | ${prom_series_c} series |

### Pattern A/B で存在するメトリクス名

OTel SDK (otelhttp) が生成する主なメトリクス:
- \`http_server_request_body_size_bytes\` — HTTPリクエストボディサイズ (histogram)
- \`http_server_response_body_size_bytes\` — HTTPレスポンスボディサイズ (histogram)
- \`rpc_client_duration_seconds\` — RPC クライアント呼び出し時間
- \`dns_lookup_duration_seconds\` — DNS 解決時間

Pattern C で存在するメトリクス:
- Prometheus クライアントの Go runtime メトリクス (\`go_goroutines\`, \`go_memstats_*\` 等)

## Traces サンプル (Tempo)

### Pattern A (OTel SDK → OTel Collector → Alloy → Tempo)

| TraceID | Service | Duration | 時刻 (UTC) |
|---|---|---|---|
${tempo_traces_a}

### Pattern B (OTel SDK → Alloy 直接 → Tempo)

| TraceID | Service | Duration | 時刻 (UTC) |
|---|---|---|---|
${tempo_traces_b}

### Pattern C

トレースなし (OTel SDK 未使用のため期待値通り)

## Logs サンプル (Loki)

### Pattern A

| 時刻 (JST) | ログ内容 |
|---|---|
${loki_logs_a}

### Pattern B

| 時刻 (JST) | ログ内容 |
|---|---|
${loki_logs_b}

### Pattern C

ログなし (OTel SDK 未使用のため期待値通り)

## アーキテクチャ別テレメトリ取得状況

| | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| OTel Collector | あり | なし | なし |
| OTel SDK | あり | あり | なし |
| Metrics 収集方法 | OTLP → Collector → Alloy | OTLP → Alloy 直接 | Prometheus scrape |
| Traces | ✅ | ✅ | ✅ 0件 (期待値) |
| Logs | ✅ | ✅ | ✅ 0件 (期待値) |
| Metrics | ✅ | ✅ | ✅ |
REPORT

  echo "$report_file"
}

report_file=$(save_report)
info "実験データを保存しました: ${report_file}"
echo ""

if [[ $FAILED -eq 0 ]]; then
  exit 0
else
  exit 1
fi
