#!/usr/bin/env bash
# scripts/v2/preflight.sh - 検証 2/3 の実行前に実施する前処理
#
# 実施内容:
#   C-1 対策: 各 vcluster の go-api-server Pod を rollout restart してメトリクスカウンタをリセット
#   E-3 対策: Prometheus /api/v1/targets を取得し、go-api-server を対象とする scrape job 一覧を記録
#
# 使い方:
#   ./scripts/v2/preflight.sh             # 既定: docs/v2/logs/ に preflight-{timestamp}.{md,json} を保存
#   LOG_DIR=/tmp ./scripts/v2/preflight.sh

set -uo pipefail
cd "$(dirname "$0")/../.."

source scripts/v2/lib.sh

init_logs preflight
check_deps

# ==================== C-1 対策: Pod 再作成 ====================
header "C-1 対策: go-api-server Pod を再作成"

for vc in vcluster-1 vcluster-2 vcluster-3; do
  info "Connecting to ${vc}..."
  if vcluster connect "$vc" -n "$vc" >/dev/null 2>&1; then
    info "Rollout restarting deployment/go-api-server in ${vc}..."
    if kubectl rollout restart deployment/go-api-server -n default 2>&1; then
      kubectl rollout status deployment/go-api-server -n default --timeout=120s 2>&1 | tail -3
      pass "${vc}: go-api-server rollout completed"
    else
      fail "${vc}: rollout restart failed"
    fi

    # Pattern A は otelcol も restart
    if [[ "$vc" == "vcluster-1" ]]; then
      if kubectl get deployment/otelcol -n default >/dev/null 2>&1; then
        info "Pattern A: also restarting otelcol..."
        kubectl rollout restart deployment/otelcol -n default 2>&1 || true
        kubectl rollout status deployment/otelcol -n default --timeout=120s 2>&1 | tail -3
        pass "${vc}: otelcol rollout completed"
      fi
    fi

    vcluster disconnect >/dev/null 2>&1
  else
    fail "${vc}: vcluster connect に失敗"
  fi
done

POD_RESTART_TIME=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)
log_json "pod_restart_completed_at" "\"$POD_RESTART_TIME\""

{
  echo ""
  echo "## C-1 対策: Pod 再作成完了"
  echo ""
  echo "- 完了時刻: ${POD_RESTART_TIME}"
  echo "- 対象: vcluster-1/2/3 の go-api-server, および vcluster-1 の otelcol"
  echo "- 効果: 以降のメトリクス cumulative counter は本時刻以降の値のみを含む"
} >> "$LOG_MD"

# ==================== E-3 対策: Scrape targets 記録 ====================
header "E-3 対策: Prometheus targets API から scrape job 一覧を記録"

# Prometheus に port-forward
PROM_PORT=9090
export PROM_PORT
start_pf statefulset/prometheus-kube-prometheus-stack-prometheus ${PROM_PORT} 9090 monitoring
sleep 5

if wait_http "http://localhost:${PROM_PORT}/-/healthy" 20; then
  pass "Prometheus に接続"
else
  fail "Prometheus への接続失敗"
  exit 1
fi

record_scrape_targets "E-3_scrape_targets_for_go_api_server"

# 全 scrape job の概要も記録
ALL_TARGETS=$(curl -sf "http://localhost:${PROM_PORT}/api/v1/targets" 2>/dev/null | \
  jq -c '[.data.activeTargets[] | {job: .labels.job, health: .health, scrapeUrl: .scrapeUrl}] | group_by(.job) | map({job: .[0].job, count: length, healthy: ([.[] | select(.health == "up")] | length)})')
log_json "E-3_all_scrape_jobs_summary" "$ALL_TARGETS"

{
  echo ""
  echo "## E-3 対策: 全 scrape job サマリ"
  echo ""
  echo '```json'
  echo "$ALL_TARGETS" | jq '.'
  echo '```'
} >> "$LOG_MD"

cleanup_pfs

# ==================== サマリ ====================
print_result_table

echo ""
echo "Pre-flight 完了。次の手順:"
echo "  1. ./scripts/verify2.sh または ./scripts/verify3.sh を実行"
echo "  2. 完了後に ./scripts/v2/postcheck.sh で C-2 / D-1 用の追加 PromQL を取得"
echo ""
echo "ログファイル:"
echo "  ${LOG_MD}"
echo "  ${LOG_JSON}"
