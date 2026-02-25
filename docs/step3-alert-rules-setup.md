# Step 3: Grafana アラートルール設定ガイド

## 前提

- Grafana へのアクセス: `kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring`
- Alertmanager が稼働中 (kube-prometheus-stack 同梱)

---

## 1. Contact Point の設定

本検証では `kube-prometheus-stack` により自動作成される `grafana-default-email` をそのまま使用する。
新規作成は不要。アラートの発火確認は **Alerting > Alert rules** で Firing 状態への変化により行う。

> Slack 等の外部通知が必要な場合は Alerting > Contact points > Add contact point から追加する。

---

## 2. Notification Policy の設定

**Grafana 操作**: Alerting > Notification policies

Root policy（デフォルトポリシー）の編集のみ行う。「Add notification policy」（子ポリシー追加）は使用しない。

Root policy の編集ボタン（鉛筆アイコン）をクリックし、以下を設定する:

| 設定項目 | 値 |
|---|---|
| Default contact point | `grafana-default-email` (自動作成済み) |
| Group by | `alertname` |
| Group wait | 30s |
| Group interval | 5m |
| Repeat interval | 4h |

---

## 3. アラートルール定義

**Grafana 操作**: Alerting > Alert rules > New alert rule

### Alert 1: HighErrorRate

サービスのエラー率が 5% を超えた場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `HighErrorRate` |
| Folder | `OTEL Demo Alerts` (新規作成) |
| Group | `service-health` |
| Evaluation interval | `5m`（service-health グループ共通） |
| Pending period | `5m` |
| Severity label | `critical` |

**Section 1 - Define query and alert condition:**

Query A (Total requests):
```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
)
```

Query B (Error requests):
```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{
    span_kind="SPAN_KIND_SERVER",
    status_code="STATUS_CODE_ERROR"
  }[5m])
)
```

Expression C (Error Rate = B / A):
| 設定 | 値 |
|---|---|
| Operation | Math |
| Expression | `(${Error requests} / ${Total requests}) * 100` |

> Query の Legend に名前を設定している場合は Legend 名で参照する（例: `${Error requests}`）。Legend が未設定の場合は `$B / $A * 100` でも可。分子・分母を逆にすると Infinity になるため注意。
> Expression C の結果は 0〜100 のパーセント値になる。
> アノテーションで Expression の値を参照する場合、refId が文字列名のときは `{{ index $values "refId名" }}` を使用する（例: `{{ index $values "Error Rate" }}`）。

Expression D (Threshold):
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | C |
| IS ABOVE | `5` |

**Alert condition**: D

**Section 3 - Add folder and labels:**

| 設定項目 | 値 |
|---|---|
| Folder | `OTEL Demo Alerts`（「+ New folder」で新規作成） |
| Labels / severity | `critical` |
| Labels / team | `platform` |

**Section 4 - Set evaluation behavior:**

| 設定項目 | 値 |
|---|---|
| Evaluation group | `service-health`（「+ New evaluation group」で新規作成） |
| Evaluation interval | `1m`（グループ作成時に設定。後から変更する場合は Alert rules 一覧でグループの編集アイコンをクリック） |
| Pending period | `5m`（Pending period は Evaluation interval 以上の値を設定すること） |

**Section 6 - Configure notification message:**

| 設定項目 | 値 |
|---|---|
| Summary | `{{ $labels.service_name }} のエラーレートが {{ index $values "Error Rate" }}% を超過` |
| Description | `サービス {{ $labels.service_name }} のエラーレートが閾値 5% を超えています。現在値: {{ index $values "Error Rate" }}%` |

---

### Alert 2: HighLatencyP99

P99 レイテンシが 2 秒を超えた場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `HighLatencyP99` |
| Folder | `OTEL Demo Alerts` |
| Group | `service-health` |
| Evaluation interval | `5m`（service-health グループ共通） |
| Pending period | `5m` |
| Severity label | `warning` |

**Query A:**
```promql
histogram_quantile(0.99,
  sum by (service_name, le) (
    rate(traces_span_metrics_duration_milliseconds_bucket{span_kind="SPAN_KIND_SERVER"}[5m])
  )
)
```

**Expression B (Threshold):**
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | A |
| IS ABOVE | `2000` |

**Alert condition**: B

**Section 3 - Add folder and labels:**

| 設定項目 | 値 |
|---|---|
| Folder | `OTEL Demo Alerts` |
| Labels / severity | `warning` |
| Labels / team | `platform` |

**Section 4 - Set evaluation behavior:**

| 設定項目 | 値 |
|---|---|
| Evaluation group | `service-health` |
| Pending period | `5m` |

**Section 6 - Configure notification message:**

| 設定項目 | 値 |
|---|---|
| Summary | `{{ $labels.service_name }} の P99 レイテンシが 2s を超過` |
| Description | `サービス {{ $labels.service_name }} の P99 レイテンシが閾値 2000ms を超えています。現在値: {{ index $values "HighLatencyP99" }}ms` |

---

### Alert 3: ServiceDown

直近 3 分間の成功リクエストレートがほぼ 0 になった場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `ServiceDown` |
| Folder | `OTEL Demo Alerts` |
| Group | `service-health` |
| Evaluation interval | `5m`（service-health グループ共通） |
| Pending period | `5m`（Evaluation interval が 5m のため 3m 以下は設定不可） |
| Severity label | `critical` |

**Query A:**
```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{
    span_kind="SPAN_KIND_SERVER",
    status_code!="STATUS_CODE_ERROR"
  }[3m])
)
```

> クエリのレンジ `[3m]` と Pending period `3m` を一致させている。

**Expression B (Threshold):**
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | A |
| IS BELOW | `0.001` |

**Alert condition**: B

**Annotations:**
| Key | Value |
|---|---|
| summary | `{{ $labels.service_name }} がダウンしている可能性` |
| description | `サービス {{ $labels.service_name }} の直近 3 分間の成功リクエストレートがほぼ 0 です` |

**Labels:**
| Key | Value |
|---|---|
| severity | `critical` |
| team | `platform` |

---

### Alert 4: PodOOMKillRisk

Pod の Memory 使用率が limit の 90% を超えた場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `PodOOMKillRisk` |
| Folder | `OTEL Demo Alerts` |
| Group | `infrastructure` |
| Evaluation interval | `1m` |
| Pending period | `5m` |
| Severity label | `warning` |

**Query A (Memory usage):**
```promql
sum by (pod) (
  container_memory_working_set_bytes{
    namespace="vcluster-otel-demo",
    container!="",
    container!="POD"
  }
)
```

**Query B (Memory limit):**
```promql
sum by (pod) (
  kube_pod_container_resource_limits{
    namespace="vcluster-otel-demo",
    resource="memory"
  }
)
```

**Expression C (Usage ratio = A / B):**
| 設定 | 値 |
|---|---|
| Operation | Math |
| Expression | `${Memory usage} / ${Memory limit}` |

**Expression D (Threshold):**
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | C |
| IS ABOVE | `0.9` |

**Alert condition**: D

**Section 3 - Add folder and labels:**

| 設定項目 | 値 |
|---|---|
| Folder | `OTEL Demo Alerts` |
| Labels / severity | `warning` |
| Labels / team | `platform` |

**Section 4 - Set evaluation behavior:**

| 設定項目 | 値 |
|---|---|
| Evaluation group | `infrastructure` |
| Pending period | `5m` |

**Section 6 - Configure notification message:**

| 設定項目 | 値 |
|---|---|
| Summary | `Pod {{ $labels.pod }} が OOM Kill のリスク` |
| Description | `Pod {{ $labels.pod }} のメモリ使用率が limit の 90% を超えています。現在値: {{ index $values "Usage ratio = A / B" }}` |

---

### Alert 5: TelemetryPipelineDrop

OTel Collector でのデータ送信失敗が発生した場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `TelemetryPipelineDrop` |
| Folder | `OTEL Demo Alerts` |
| Group | `pipeline` |
| Evaluation interval | `1m` |
| Pending period | `3m` |
| Severity label | `warning` |

**Query A:**
```promql
sum(rate(otelcol_exporter_send_failed_spans_total[5m]))
+
sum(rate(otelcol_exporter_send_failed_log_records_total[5m]))
+
sum(rate(otelcol_exporter_send_failed_metric_points_total[5m]))
```

**Expression B (Threshold):**
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | A |
| IS ABOVE | `0` |

**Alert condition**: B

**Section 3 - Add folder and labels:**

| 設定項目 | 値 |
|---|---|
| Folder | `OTEL Demo Alerts` |
| Labels / severity | `warning` |
| Labels / team | `platform` |

**Section 4 - Set evaluation behavior:**

| 設定項目 | 値 |
|---|---|
| Evaluation group | `pipeline` |
| Pending period | `3m` |

**Section 6 - Configure notification message:**

| 設定項目 | 値 |
|---|---|
| Summary | `テレメトリパイプラインでデータドロップが発生` |
| Description | `OTel Collector でのデータ送信失敗が検出されました。送信失敗レート: {{ index $values "TelemetryPipelineDrop" }}/s` |

---

### Alert 6: StorageNearFull

PVC の使用率が 85% を超えた場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `StorageNearFull` |
| Folder | `OTEL Demo Alerts` |
| Group | `infrastructure` |
| Evaluation interval | `5m` |
| Pending period | `10m` |
| Severity label | `warning` |

**Query A:**
```promql
kubelet_volume_stats_used_bytes{namespace="monitoring"}
/
kubelet_volume_stats_capacity_bytes{namespace="monitoring"}
```

**Expression B (Threshold):**
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | A |
| IS ABOVE | `0.85` |

**Alert condition**: B

**Section 3 - Add folder and labels:**

| 設定項目 | 値 |
|---|---|
| Folder | `OTEL Demo Alerts` |
| Labels / severity | `warning` |
| Labels / team | `platform` |

**Section 4 - Set evaluation behavior:**

| 設定項目 | 値 |
|---|---|
| Evaluation group | `infrastructure` |
| Pending period | `10m` |

**Section 6 - Configure notification message:**

| 設定項目 | 値 |
|---|---|
| Summary | `PVC のストレージが残り少なくなっています` |
| Description | `PVC の使用率が 85% を超えています。現在値: {{ index $values "Storage Near Full" }}` |

---

### Alert 7: vClusterQuotaExhaustion

vCluster の ResourceQuota 使用率が 80% を超えた場合に発火する。

| 設定項目 | 値 |
|---|---|
| Rule name | `vClusterQuotaExhaustion` |
| Folder | `OTEL Demo Alerts` |
| Group | `infrastructure` |
| Evaluation interval | `5m` |
| Pending period | `10m` |
| Severity label | `warning` |

**Query A:**

```promql
kube_resourcequota{namespace="vcluster-otel-demo", type="used"}
/ ignoring(type)
kube_resourcequota{namespace="vcluster-otel-demo", type="hard"}
```

> `type` ラベルの値が `"used"` と `"hard"` で異なるため `ignoring(type)` で結合する。
> Math Expression は使用しない（Grafana の Math は異なる `type` ラベルを持つ系列を結合できないため）。

**Expression B (Threshold):**
| 設定 | 値 |
|---|---|
| Operation | Threshold |
| Input | A |
| IS ABOVE | `0.8` |

**Alert condition**: B

**Section 6 - Configure notification message:**

| 設定項目 | 値 |
|---|---|
| Summary | `vCluster の ResourceQuota 使用率が 80% を超過` |
| Description | `vCluster (vcluster-otel-demo) の ResourceQuota {{ $labels.resource }} の使用率が 80% を超えています。現在値: {{ index $values "Usage ratio" }}` |


---

## 4. アラートルール一覧 (設定後の確認用)

| # | ルール名 | グループ | 条件 | Pending | 重要度 |
|---|---|---|---|---|---|
| 1 | HighErrorRate | service-health | Error Rate > 5% | 5m | critical |
| 2 | HighLatencyP99 | service-health | P99 > 2000ms | 5m | warning |
| 3 | ServiceDown | service-health | 成功リクエスト = 0 | 3m | critical |
| 4 | PodOOMKillRisk | infrastructure | Memory > 90% limit | 5m | warning |
| 5 | TelemetryPipelineDrop | pipeline | Failed exports > 0 | 3m | warning |
| 6 | StorageNearFull | infrastructure | PVC > 85% | 10m | warning |
| 7 | vClusterQuotaExhaustion | infrastructure | ResourceQuota > 80% | 10m | warning |

---

## 5. 動作確認

アラートルール設定後、以下を確認する:

1. **Alerting > Alert rules** で全 7 ルールが `Normal` 状態で表示されること
2. 現在 `valkey-cart` が Pending 状態のため、一部アラート (HighErrorRate, HighLatencyP99) が既に `Firing` になる可能性がある
3. Step 4 で Feature Flag による障害注入を行い、アラートが正しく発火することを検証する
