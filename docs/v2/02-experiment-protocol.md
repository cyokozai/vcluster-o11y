# 実行手順書 (Experiment Protocol)

本ドキュメントは検証の実行手順を**再現可能な粒度**で記述する。`docs/v2/00-design.md` の測定項目をどのコマンドで取得するかを 1:1 で対応させる。

## 0. 前提

- 作業ディレクトリ: `/Users/yusuke/internship/projects/vcluster-o11y`
- ローカルツール: helm v4.2.0 / helmfile v1.5.2 / terraform v1.15.5 / kubectl v1.36.x / vcluster v0.34.2 / aws-cli v2.34.x
- AWS 認証: `aws sts get-caller-identity` で正しい IAM ロール / アクセスキーが取得できること

---

## 1. 環境構築

### 1.1 EKS クラスタ作成（Terraform）

```bash
cd terraform/

# tfvars が現在のアカウントの ARN になっているか確認
cat terraform.tfvars

# 必要なら ARN を再生成
echo "eks_access_entry_principal_arn = $(aws sts get-caller-identity --output json --no-cli-pager | jq '.Arn')" > terraform.tfvars

# Plan
terraform plan -var-file="terraform.tfvars"

# Apply（15-20 分）
terraform apply -var-file="terraform.tfvars" -auto-approve

# kubeconfig 取得
export REGION="ap-northeast-1"
export CLUSTER_NAME="demo-eks-vcluster"
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# 接続確認
kubectl cluster-info
kubectl get nodes
```

### 1.2 StorageClass 作成

```bash
cd ..
kubectl apply -f manifests/storageclass/gp3-storageclass.yaml
kubectl get storageclass
```

### 1.3 helmfile の最新版対応

`docs/v2/00-design.md` のバージョン採用案に従って `helm/helmfile.yaml` を編集（ユーザー作業）:

```diff
- chart: loft/vcluster
- version: "0.32.1"
+ version: "0.34.2"
  ...
- chart: grafana/loki
- version: "6.53.0"
+ version: "6.55.0"
  ...
- chart: grafana/alloy
- version: "1.6.1"
+ version: "1.8.2"
  ...
- chart: prometheus-community/kube-prometheus-stack
- version: "82.10.1"
+ version: "86.2.0"
  ...
- chart: grafana/beyla
- version: "1.14.0"
+ version: "1.16.8"
```

### 1.4 監視スタックのデプロイ

```bash
# Repository 更新
helmfile repos -f helm/helmfile.yaml

# Sync（5-10 分）
helmfile sync -f helm/helmfile.yaml

# Pod 起動確認
kubectl get pods -n monitoring -w
# 全 Pod が Running になるまで待機
```

**トラブルシュート**:
- KPS 82 → 86 で CRD が更新されない場合: `helmfile sync` ログに warning が出たら、`docs/v2/00-design.md` 0.3 節の CRD 手動 apply を実行
- Beyla の eBPF map OOM: `docs/v1/beyla-bpf-map-oom-troubleshooting.md` 参照

### 1.5 Grafana のアラート / ダッシュボード

```bash
kubectl apply -f manifests/monitoring/grafana-alert-rules.yaml
kubectl apply -f manifests/monitoring/grafana-dashboards.yaml
```

### 1.6 仮想クラスタ作成（検証 1/2 用）

```bash
# vcluster-1 (Pattern A)
vcluster create vcluster-1 --namespace vcluster-1 --upgrade \
  --values manifests/vcluster/vcluster-1-config.yaml
kubectl apply -f manifests/pattern-a/deploy.yaml
vcluster disconnect

# vcluster-2 (Pattern B)
vcluster create vcluster-2 --namespace vcluster-2 --upgrade \
  --values manifests/vcluster/vcluster-2-config.yaml
kubectl apply -f manifests/pattern-b/deploy.yaml
vcluster disconnect

# vcluster-3 (Pattern C)
vcluster create vcluster-3 --namespace vcluster-3 --upgrade \
  --values manifests/vcluster/vcluster-3-config.yaml
kubectl apply -f manifests/pattern-c/deploy.yaml
vcluster disconnect

# Beyla が vcluster-3 を検出していることを確認
kubectl logs -l app.kubernetes.io/name=beyla -n beyla-system | grep -i "vcluster-3"
```

---

---

## 2. 検証 1 実行手順

### 2.1 前処理: Pod 再作成 (C-1 対策)

```bash
for vc in vcluster-1 vcluster-2 vcluster-3; do
  vcluster connect $vc -n $vc
  kubectl rollout restart deployment/go-api-server -n default
  kubectl rollout status deployment/go-api-server -n default --timeout=120s
  vcluster disconnect
done

# Pod 再作成によるカウンタリセットを確認
echo "Pod restart timestamp: $(date -Iseconds)" >> "$LOG_MD"
```

### 2.2 Phase 0: scrape 構成の事前記録 (E-3 対策)

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_JSON="docs/v2/logs/verify2-${TIMESTAMP}.json"
LOG_MD="docs/v2/logs/verify2-${TIMESTAMP}.md"

# Prometheus targets API を取得
kubectl exec -n monitoring statefulset/prometheus-kube-prometheus-stack-prometheus -- \
  wget -qO- http://localhost:9090/api/v1/targets | \
  jq '[.data.activeTargets[] | select(.scrapeUrl | test("go-api-server")) | {
    job: .labels.job,
    scrapeUrl: .scrapeUrl,
    scrapeInterval: .scrapeInterval,
    scrapePool: .scrapePool,
    pod: .labels.kubernetes_pod_name,
    namespace: .labels.namespace
  }]' > /tmp/scrape_targets.json

cat /tmp/scrape_targets.json >> "$LOG_MD"

# JSON への登録
jq --argjson targets "$(cat /tmp/scrape_targets.json)" \
  '. + {scrape_targets: $targets}' "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"
```

### 2.3 Phase 1: 負荷生成

```bash
# Port forward
for i in 1 2 3; do
  vcluster connect vcluster-$i -n vcluster-$i
  kubectl port-forward svc/go-api-server 808$i:8080 -n default &
  PF_PIDS+=($!)
done
sleep 5

# 600 秒間リクエスト送信
START_EPOCH=$(date +%s)
END_EPOCH=$((START_EPOCH + 600))
while [[ $(date +%s) -lt $END_EPOCH ]]; do
  curl -sf http://localhost:8081/ > /dev/null
  curl -sf http://localhost:8082/ > /dev/null
  curl -sf http://localhost:8083/ > /dev/null
  sleep 2
done

# エラー注入 (Pattern A/B 各 10 回)
for i in $(seq 1 10); do
  curl -sf http://localhost:8081/status/500 > /dev/null || true
  curl -sf http://localhost:8082/status/500 > /dev/null || true
done

# OTel SDK の PeriodicReader 待ち（60 秒間隔のため）
sleep 90
```

### 2.4 Phase 2-7: 測定項目取得

各測定項目に対応する PromQL / API クエリを実行し、JSON と Markdown 両方に追記。

```bash
# 雛形: PromQL 実行 → JSON にマージ → Markdown に追記
run_promql() {
  local query="$1"
  local label="$2"
  local result=$(curl -sG 'http://localhost:9090/api/v1/query' --data-urlencode "query=$query" | jq -c '.data.result')

  # JSON マージ
  jq --arg label "$label" --argjson result "$result" \
    '.measurements[$label] = $result' "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"

  # Markdown に追記
  echo "" >> "$LOG_MD"
  echo "### $label" >> "$LOG_MD"
  echo "" >> "$LOG_MD"
  echo "**Query:**" >> "$LOG_MD"
  echo '```promql' >> "$LOG_MD"
  echo "$query" >> "$LOG_MD"
  echo '```' >> "$LOG_MD"
  echo "" >> "$LOG_MD"
  echo "**Result:**" >> "$LOG_MD"
  echo '```json' >> "$LOG_MD"
  echo "$result" | jq '.' >> "$LOG_MD"
  echo '```' >> "$LOG_MD"
}

# M1-2: Metrics → Prometheus
run_promql 'count by (service_name) (http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"})' "M1-2_pattern_a_metrics"
run_promql 'count by (service_name) (http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b"})' "M1-2_pattern_b_metrics"
run_promql 'count by (service_name) (http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c"})' "M1-2_pattern_c_beyla_metrics"
run_promql 'count by (service_name) (go_goroutines{service_name="go-api-server-pattern-c"})' "M1-2_pattern_c_scrape_metrics"

# M1-5: service_name 区別可能性
run_promql 'count by (service_name) ({service_name=~"go-api-server-pattern-.*"})' "M1-5_service_name_distinction"

# M1-7: エラーレート (C-1 対策: increase ベース)
run_promql 'increase(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a",http_response_status_code=~"5.."}[10m])' "M1-7_pattern_a_5xx_increase"
run_promql 'increase(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b",http_response_status_code=~"5.."}[10m])' "M1-7_pattern_b_5xx_increase"
run_promql '100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"}[5m]))' "M1-7_pattern_a_error_rate"
run_promql '100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b"}[5m]))' "M1-7_pattern_b_error_rate"
```

### 2.5 M1-3: Tempo Traces 取得

```bash
fetch_traces() {
  local service_name="$1"
  local label="$2"
  local result=$(curl -sG 'http://localhost:3200/api/search' \
    --data-urlencode "tags=service.name=${service_name}" \
    --data-urlencode "limit=10" | jq -c '.traces')

  jq --arg label "$label" --argjson result "$result" \
    '.measurements[$label] = $result' "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"
}

fetch_traces "go-api-server-pattern-a" "M1-3_pattern_a_traces"
fetch_traces "go-api-server-pattern-b" "M1-3_pattern_b_traces"
fetch_traces "go-api-server-pattern-c" "M1-3_pattern_c_traces"
```

### 2.6 M1-4: Loki Logs 取得

```bash
fetch_logs() {
  local service_name="$1"
  local label="$2"
  local start_ns=$(($(date +%s -d "30 min ago") * 1000000000))
  local end_ns=$(($(date +%s) * 1000000000))
  local result=$(curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
    --data-urlencode "query={service_name=\"${service_name}\"}" \
    --data-urlencode "start=${start_ns}" \
    --data-urlencode "end=${end_ns}" \
    --data-urlencode "limit=5" | jq -c '.data.result')

  jq --arg label "$label" --argjson result "$result" \
    '.measurements[$label] = $result' "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"
}

fetch_logs "go-api-server-pattern-a" "M1-4_pattern_a_logs"
fetch_logs "go-api-server-pattern-b" "M1-4_pattern_b_logs"
fetch_logs "go-api-server-pattern-c" "M1-4_pattern_c_logs"  # 期待値: 空
```

### 2.7 M1-6: Trace-Log 相関

```bash
TRACEID_A=$(curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="go-api-server-pattern-a"}' \
  --data-urlencode "start=${start_ns}" --data-urlencode "end=${end_ns}" \
  --data-urlencode 'limit=1' | jq -r '.data.result[0].values[0][1] | fromjson | .traceid')
TEMPO_STATUS_A=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3200/api/traces/${TRACEID_A}")

# 同様に Pattern B
TRACEID_B=...
TEMPO_STATUS_B=...

jq --arg ta "$TRACEID_A" --arg tsa "$TEMPO_STATUS_A" \
   --arg tb "$TRACEID_B" --arg tsb "$TEMPO_STATUS_B" \
  '.measurements["M1-6_trace_log_correlation"] = {pattern_a: {traceid: $ta, tempo_status: $tsa}, pattern_b: {traceid: $tb, tempo_status: $tsb}}' \
  "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"
```

---

## 3. 検証 2 実行手順

### 3.1 前処理（C-1 対策）

```bash
# 検証 2 と同じく Pod 再作成
for vc in vcluster-1 vcluster-2 vcluster-3; do
  vcluster connect $vc -n $vc
  kubectl rollout restart deployment/go-api-server -n default
  kubectl rollout status deployment/go-api-server -n default --timeout=120s
  vcluster disconnect
done

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_JSON="docs/v2/logs/verify3-${TIMESTAMP}.json"
LOG_MD="docs/v2/logs/verify3-${TIMESTAMP}.md"

# JSON 雛形
echo '{"experiment_id":"verify3-'${TIMESTAMP}'","start_time":"'$(date -Iseconds)'","measurements":{}}' > "$LOG_JSON"
```

### 3.2 シナリオ実行

```bash
# Port forward (検証 2 と同じ)
# ...

# ベースライン記録（実験前の Pattern B/C の 5xx カウンタ）
B_BASELINE=$(curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b",http_response_status_code=~"5.."}' \
  | jq -r '[.data.result[].value[1]] | map(tonumber) | add // 0')
C_BASELINE=$(curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c",http_response_status_code=~"5.."}' \
  | jq -r '[.data.result[].value[1]] | map(tonumber) | add // 0')

# 600 秒間: 全 vcluster へ通常リクエスト
START_EPOCH=$(date +%s)
END_EPOCH=$((START_EPOCH + 600))

# 通常リクエスト（背景プロセス）
(
  while [[ $(date +%s) -lt $END_EPOCH ]]; do
    curl -sf http://localhost:8081/ > /dev/null
    curl -sf http://localhost:8082/ > /dev/null
    curl -sf http://localhost:8083/ > /dev/null
    sleep 2
  done
) &
NORMAL_PID=$!

# 障害注入: vcluster-1 のみ（背景プロセス）
(
  while [[ $(date +%s) -lt $END_EPOCH ]]; do
    curl -sf http://localhost:8081/status/500 > /dev/null || true
    sleep 2
  done
) &
ERROR_PID=$!

# 待機
wait $NORMAL_PID $ERROR_PID

# 伝播待ち
sleep 90
```

### 3.3 M2-1〜M2-6: 測定（D-1 対策で avg / max 両方を取得）

```bash
# M2-1: Pattern A エラーレート（avg）
run_promql 'avg_over_time((100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"}[5m])))[10m:30s])' "M2-1_pattern_a_error_rate_avg"

# M2-1: Pattern A エラーレート（max） - D-1 対策
run_promql 'max_over_time((100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"}[5m])))[10m:30s])' "M2-1_pattern_a_error_rate_max"

# M2-2: Pattern B エラーレート（avg / max 両方）
run_promql 'avg_over_time((100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b"}[5m])))[10m:30s])' "M2-2_pattern_b_error_rate_avg"
run_promql 'max_over_time((100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b"}[5m])))[10m:30s])' "M2-2_pattern_b_error_rate_max"

# M2-3: Pattern B の 5xx 増分（C-1 対策で increase 使用）
run_promql 'increase(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b",http_response_status_code=~"5.."}[10m])' "M2-3_pattern_b_5xx_increase"

# M2-4: Pattern C（D-2 対策で明示的に記録）
run_promql 'avg_over_time((100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c"}[5m])))[10m:30s])' "M2-4_pattern_c_error_rate_avg"
run_promql 'max_over_time((100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c",http_response_status_code=~"5.."}[5m])) / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c"}[5m])))[10m:30s])' "M2-4_pattern_c_error_rate_max"
run_promql 'increase(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c",http_response_status_code=~"5.."}[10m])' "M2-4_pattern_c_5xx_increase"
```

### 3.4 M2-5/M2-6: Trace / Log 分離

```bash
# Pattern A エラートレース数
ERR_TRACES_A=$(curl -sG 'http://localhost:3200/api/search' \
  --data-urlencode 'tags=service.name=go-api-server-pattern-a status=error' \
  --data-urlencode 'limit=100' | jq '.traces | length')

# Pattern B / C は 0 件であるべき
ERR_TRACES_B=$(curl -sG 'http://localhost:3200/api/search' \
  --data-urlencode 'tags=service.name=go-api-server-pattern-b status=error' \
  --data-urlencode 'limit=100' | jq '.traces | length')
ERR_TRACES_C=$(curl -sG 'http://localhost:3200/api/search' \
  --data-urlencode 'tags=service.name=go-api-server-pattern-c status=error' \
  --data-urlencode 'limit=100' | jq '.traces | length')

# ログ分離
ERR_LOGS_A=$(curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="go-api-server-pattern-a"} |~ "500"' \
  --data-urlencode "start=$((START_EPOCH * 1000000000))" \
  --data-urlencode "end=$(($(date +%s) * 1000000000))" \
  --data-urlencode "limit=100" | jq '[.data.result[].values | length] | add // 0')
ERR_LOGS_B=$(curl -sG 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="go-api-server-pattern-b"} |~ "500"' \
  --data-urlencode "start=$((START_EPOCH * 1000000000))" \
  --data-urlencode "end=$(($(date +%s) * 1000000000))" \
  --data-urlencode "limit=100" | jq '[.data.result[].values | length] | add // 0')

# JSON 登録
jq --arg eta "$ERR_TRACES_A" --arg etb "$ERR_TRACES_B" --arg etc "$ERR_TRACES_C" \
   --arg ela "$ERR_LOGS_A" --arg elb "$ERR_LOGS_B" \
  '.measurements["M2-5_error_traces"] = {pattern_a: ($eta|tonumber), pattern_b: ($etb|tonumber), pattern_c: ($etc|tonumber)}
   | .measurements["M2-6_error_logs"] = {pattern_a: ($ela|tonumber), pattern_b: ($elb|tonumber)}' \
  "$LOG_JSON" > "$LOG_JSON.tmp" && mv "$LOG_JSON.tmp" "$LOG_JSON"
```

---

## 4. 補助検証: Alloy 自己メトリクス（M4-1）

検証 2 開始時刻〜検証 2 終了時刻を観測期間とする。

```bash
# 観測期間記録
EXP_START_EPOCH=...  # 検証 2 開始時の START_EPOCH
EXP_END_EPOCH=$(date +%s)  # 検証 2 終了時
DURATION_HOURS=$(echo "scale=2; ($EXP_END_EPOCH - $EXP_START_EPOCH) / 3600" | bc)

# Alloy 自己メトリクス
ALLOY_RECEIVED=$(curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode "query=increase(otelcol_receiver_accepted_spans_total[${DURATION_HOURS}h])" \
  | jq -r '[.data.result[].value[1]] | map(tonumber) | add // 0')
ALLOY_SENT=$(curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode "query=increase(otelcol_exporter_sent_spans_total[${DURATION_HOURS}h])" \
  | jq -r '[.data.result[].value[1]] | map(tonumber) | add // 0')
ALLOY_QUEUE=$(curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=otelcol_exporter_queue_size' \
  | jq -r '[.data.result[].value[1]] | map(tonumber) | max')
ALLOY_FAILED=$(curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode "query=increase(otelcol_exporter_send_failed_spans_total[${DURATION_HOURS}h])" \
  | jq -r '[.data.result[].value[1]] | map(tonumber) | add // 0')

cat <<EOF | tee -a docs/v2/logs/alloy-summary-$(date +%Y%m%d-%H%M%S).md
## Alloy 自己メトリクス（観測期間: ${DURATION_HOURS} 時間）

- 観測開始: $(date -d @$EXP_START_EPOCH -Iseconds)
- 観測終了: $(date -d @$EXP_END_EPOCH -Iseconds)
- 受信スパン: ${ALLOY_RECEIVED}
- 送信スパン: ${ALLOY_SENT}
- キュー最大: ${ALLOY_QUEUE}
- 送信失敗: ${ALLOY_FAILED}
EOF
```

---

## 5. 共有ユーティリティ関数（参考）

検証 1/2/3 で共通利用する関数を `scripts/v2/lib.sh` に切り出す想定:

```bash
# scripts/v2/lib.sh
run_promql() { ... }   # 上で示した実装
fetch_traces() { ... }
fetch_logs() { ... }
```

既存の `scripts/verify2.sh` / `verify3.sh` は完全に新版で置き換えるのではなく、上記の追加処理（前処理 / scrape 構成記録 / ログ取得形式変更）を加える方針で進める。

---

## 6. 実行時のチェックポイント

各検証完了時に以下を確認:

| 項目 | 確認方法 |
|---|---|
| ログ markdown が作成されているか | `ls -la docs/v2/logs/` |
| ログ JSON が valid か | `jq '.' docs/v2/logs/verify*.json` |
| 全測定項目が記録されているか | `jq '.measurements | keys' docs/v2/logs/verify2-*.json` |
| 期待値と実測値が一致しているか | `00-design.md` の合格基準と照合 |
