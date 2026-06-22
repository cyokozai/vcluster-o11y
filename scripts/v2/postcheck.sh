#!/usr/bin/env bash
# scripts/v2/postcheck.sh - 検証 2/3 の実行後に追加で取得する PromQL クエリ
#
# 実施内容:
#   C-2 対策: Pattern C のメトリクスを「Beyla eBPF 由来 (http_server_*)」と
#             「scrape 由来 (go_*)」に分けて取得
#   D-1 対策: エラーレートを avg_over_time と max_over_time の両方で取得
#   D-2 対策: vcluster-3 (Pattern C) の 5xx 増分を明示的に取得
#   E-1 対策: Alloy 自己メトリクスを観測期間明示で取得
#
# 使い方:
#   ./scripts/v2/postcheck.sh             # 標準
#   EXP_START_EPOCH=1234567890 ./scripts/v2/postcheck.sh  # 観測開始時刻を明示

set -uo pipefail
cd "$(dirname "$0")/../.."

source scripts/v2/lib.sh

init_logs postcheck
check_deps

# ==================== Port Forward ====================
header "Port Forward 起動"
PROM_PORT=9090
export PROM_PORT
start_pf statefulset/prometheus-kube-prometheus-stack-prometheus ${PROM_PORT} 9090 monitoring
trap cleanup_pfs EXIT INT TERM
sleep 5

if ! wait_http "http://localhost:${PROM_PORT}/-/healthy" 20; then
  fail "Prometheus 接続失敗"
  exit 1
fi
pass "Prometheus 接続"

# ==================== C-2 対策: Pattern C メトリクス分離 ====================
header "C-2 対策: Pattern C のメトリクスを Beyla 由来 / scrape 由来に分離"

# Beyla eBPF 由来の HTTP メトリクス (http_server_request_duration_seconds_*)
# OBI 3.20+ では service.namespace を prefix した「<namespace>/<service.name>」形式の job 名になる
# annotation resource.opentelemetry.io/service.name で service.name 部分を override しても
# namespace prefix は付与される
run_promql "C-2_pattern_c_beyla_metrics_count" \
  'count by (job, __name__) ({job=~"vcluster-3/.*", __name__=~"http_server_request_.*"})'

# Beyla 由来の P99 レイテンシ (ms 表示)
run_promql "C-2_pattern_c_beyla_p99_latency_ms" \
  '1000 * histogram_quantile(0.99, sum by (le) (rate(http_server_request_duration_seconds_bucket{job=~"vcluster-3/.*"}[5m])))'

# scrape 由来の Go ランタイムメトリクス (Pattern C 専用ラベル付き)
# Alloy の discovery.relabel.vcluster3_metrics で service_name ラベルが付与される
run_promql "C-2_pattern_c_scrape_go_runtime_metrics" \
  'count by (__name__) ({service_name="go-api-server-pattern-c", __name__=~"go_.*"})'

# 参考: Pattern A/B も Beyla で計装されているか確認 (OBI のデフォルト exclude 確認)
run_promql "C-2_pattern_ab_beyla_overlap_check" \
  'count by (job) (http_server_request_duration_seconds_count{job=~"vcluster-1/.*|vcluster-2/.*"})'

# /metrics 混入の調査 (Beyla が /metrics スクレイプを計装してしまう v1 課題の再評価)
run_promql "C-2_pattern_c_metrics_endpoint_traffic" \
  'increase(http_server_request_duration_seconds_count{job=~"vcluster-3/.*", url_path="/metrics"}[10m])'

# ==================== D-1 対策: エラーレートを avg/max 両方で ====================
header "D-1 対策: エラーレートを avg_over_time / max_over_time 両方で取得"

for pattern in a b c; do
  # Pattern A/B (OTel SDK): job ラベル = "go-api-server-pattern-X"
  # Pattern C (Beyla):      job ラベル = "vcluster-3/go-api-server-pattern-c" (namespace prefix 付与)
  if [[ "$pattern" == "c" ]]; then
    job_selector='job=~"vcluster-3/.*"'
  else
    job_selector="job=\"go-api-server-pattern-${pattern}\""
  fi

  # avg
  run_promql "D-1_pattern_${pattern}_error_rate_avg" \
    "avg_over_time((100 * sum(rate(http_server_request_duration_seconds_count{${job_selector},http_response_status_code=~\"5..\"}[5m])) / sum(rate(http_server_request_duration_seconds_count{${job_selector}}[5m])))[10m:30s])"

  # max
  run_promql "D-1_pattern_${pattern}_error_rate_max" \
    "max_over_time((100 * sum(rate(http_server_request_duration_seconds_count{${job_selector},http_response_status_code=~\"5..\"}[5m])) / sum(rate(http_server_request_duration_seconds_count{${job_selector}}[5m])))[10m:30s])"
done

# ==================== D-2 対策: Pattern C の 5xx 増分明示 ====================
header "D-2 対策: 各 Pattern の 5xx 増分を increase() で記録"

for pattern in a b c; do
  if [[ "$pattern" == "c" ]]; then
    job_selector='job=~"vcluster-3/.*"'
  else
    job_selector="job=\"go-api-server-pattern-${pattern}\""
  fi
  run_promql "D-2_pattern_${pattern}_5xx_increase_10m" \
    "increase(http_server_request_duration_seconds_count{${job_selector},http_response_status_code=~\"5..\"}[10m])"
done

# ==================== E-1 対策: Alloy 自己メトリクス (観測期間明示) ====================
header "E-1 対策: Alloy 自己メトリクスを観測期間明示で取得"

EXP_START_EPOCH=${EXP_START_EPOCH:-$(($(date +%s) - 3600))}  # デフォルト: 直近 1 時間
EXP_END_EPOCH=$(date +%s)
DURATION_S=$((EXP_END_EPOCH - EXP_START_EPOCH))
DURATION_H=$(echo "scale=2; $DURATION_S / 3600" | bc)

info "観測期間: ${DURATION_S} 秒 (${DURATION_H} 時間)"
info "  開始: $(date -d @$EXP_START_EPOCH -Iseconds 2>/dev/null || date -r $EXP_START_EPOCH -u +%Y-%m-%dT%H:%M:%SZ)"
info "  終了: $(date -d @$EXP_END_EPOCH -Iseconds 2>/dev/null || date -r $EXP_END_EPOCH -u +%Y-%m-%dT%H:%M:%SZ)"

run_promql "E-1_alloy_received_spans_total_increase" \
  "increase(otelcol_receiver_accepted_spans_total[${DURATION_S}s])"
run_promql "E-1_alloy_sent_spans_total_increase" \
  "increase(otelcol_exporter_sent_spans_total[${DURATION_S}s])"
run_promql "E-1_alloy_queue_size_current" \
  "otelcol_exporter_queue_size"
run_promql "E-1_alloy_send_failed_spans_total_increase" \
  "increase(otelcol_exporter_send_failed_spans_total[${DURATION_S}s])"

# 観測期間メタデータ
log_json "E-1_observation_window" \
  "$(jq -nc --arg s "$EXP_START_EPOCH" --arg e "$EXP_END_EPOCH" --arg d "$DURATION_S" '{start_epoch: ($s|tonumber), end_epoch: ($e|tonumber), duration_seconds: ($d|tonumber)}')"

# ==================== サマリ ====================
print_result_table

echo ""
echo "Post-check 完了。"
echo "ログファイル:"
echo "  ${LOG_MD}"
echo "  ${LOG_JSON}"
