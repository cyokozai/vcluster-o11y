# Step 2: Grafana ダッシュボード構築ガイド

## 前提

- Grafana へのアクセス: `kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring`
- データソース: Prometheus / Tempo / Loki (設定済み)
- SpanMetrics ラベル: `service_name`, `span_name`, `span_kind`, `status_code`
- コンテナメトリクスの namespace: `vcluster-otel-demo` (ホストクラスタ上の実 namespace)

---

## Dashboard 1: Service Overview

**Grafana 操作**: Dashboards > New Dashboard > Add visualization

### Panel 1: リクエストレート (Time Series)

| 設定項目 | 値 |
|---|---|
| Title | Request Rate by Service |
| Data source | Prometheus |
| Panel type | Time series |

**PromQL:**

```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
)
```

| オプション | 値 |
|---|---|
| Legend | `{{service_name}}` |
| Unit | requests/sec (req/s) |
| Fill opacity | 10 |

---

### Panel 2: エラーレート (Time Series)

| 設定項目 | 値 |
|---|---|
| Title | Error Rate by Service |
| Data source | Prometheus |
| Panel type | Time series |

**PromQL:**

```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[5m])
)
/
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
)
```

| オプション | 値 |
|---|---|
| Legend | `{{service_name}}` |
| Unit | Percent (0.0-1.0) |
| Thresholds | 0.05 (yellow), 0.10 (red) |
| Min | 0 |
| Max | 1 |

---

### Panel 3: レイテンシ P50 / P95 / P99 (Time Series)

| 設定項目 | 値 |
|---|---|
| Title | Latency by Service (P50 / P95 / P99) |
| Data source | Prometheus |
| Panel type | Time series |

**PromQL (3 クエリを追加):**

Query A - P99:
```promql
histogram_quantile(0.99,
  sum by (service_name, le) (
    rate(traces_span_metrics_duration_milliseconds_bucket{span_kind="SPAN_KIND_SERVER"}[5m])
  )
)
```

Query B - P95:
```promql
histogram_quantile(0.95,
  sum by (service_name, le) (
    rate(traces_span_metrics_duration_milliseconds_bucket{span_kind="SPAN_KIND_SERVER"}[5m])
  )
)
```

Query C - P50:
```promql
histogram_quantile(0.50,
  sum by (service_name, le) (
    rate(traces_span_metrics_duration_milliseconds_bucket{span_kind="SPAN_KIND_SERVER"}[5m])
  )
)
```

| オプション | 値 |
|---|---|
| Legend | A: `{{service_name}} P99`, B: `{{service_name}} P95`, C: `{{service_name}} P50` |
| Unit | milliseconds (ms) |
| Thresholds | 1000 (yellow), 2000 (red) |

> **Tip**: サービスが多いため、Dashboard Variable で `service_name` を選択できるようにすると見やすくなる。

---

### Panel 4: サービス別エラーレート一覧 (Table)

| 設定項目 | 値 |
|---|---|
| Title | Service Health Summary |
| Data source | Prometheus |
| Panel type | Table |

**PromQL:**

Query A - Total Requests:
```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
)
```

Query B - Error Rate:
```promql
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[5m])
)
/
sum by (service_name) (
  rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
)
```

| Transform | 設定 |
|---|---|
| Format | Table |
| Type | Instant |
| Column rename | A: "Request Rate (req/s)", B: "Error Rate" |

---

### Panel 5: サービスマップ (Node Graph)

| 設定項目 | 値 |
|---|---|
| Title | Service Map |
| Data source | Tempo |
| Panel type | Node Graph |

**設定方法:**
1. Data source で `Tempo` を選択
2. Query type を `Service Graph` に変更
3. パネルタイプを `Node Graph` に設定

> Tempo の Service Graph は自動的にサービス間の呼び出し関係を可視化する。

---

### Dashboard Variable の設定 (推奨)

**Dashboard Settings > Variables > New variable**

| 設定項目 | 値 |
|---|---|
| Name | `service_name` |
| Type | Query |
| Data source | Prometheus |
| Query | `label_values(traces_span_metrics_calls_total, service_name)` |
| Multi-value | Yes |
| Include All option | Yes |
| All value | `.*` |

各パネルのクエリで `{service_name=~"$service_name"}` (正規表現マッチ `=~`) を追加することでフィルタリング可能になる。Multi-value や All 選択時にも正しく動作する。

> **注意**: `service_name="$service_name"` (完全一致) ではなく、必ず `service_name=~"$service_name"` (正規表現マッチ) を使用すること。Grafana は Multi-value 選択時に `service_name=~"ad|cart|frontend"` の形式でクエリを生成するため、`=~` でないと正しく動作しない。

---

## Dashboard 2: RED Metrics Deep Dive

### Panel 1: Request Rate by Endpoint (Time Series)

**PromQL:**

```promql
sum by (span_name) (
  rate(traces_span_metrics_calls_total{
    service_name=~"$service_name",
    span_kind="SPAN_KIND_SERVER"
  }[5m])
)
```

| オプション | 値 |
|---|---|
| Legend | `{{span_name}}` |
| Unit | req/s |

---

### Panel 2: Error Rate by Endpoint (Time Series)

**PromQL:**

```promql
sum by (span_name) (
  rate(traces_span_metrics_calls_total{
    service_name=~"$service_name",
    span_kind="SPAN_KIND_SERVER",
    status_code="STATUS_CODE_ERROR"
  }[5m])
)
```

| オプション | 値 |
|---|---|
| Legend | `{{span_name}}` |
| Unit | req/s |

---

### Panel 3: Duration Heatmap (Heatmap)

**PromQL:**

```promql
sum by (le) (
  increase(traces_span_metrics_duration_milliseconds_bucket{
    service_name=~"$service_name",
    span_kind="SPAN_KIND_SERVER"
  }[5m])
)
```

| オプション | 値 |
|---|---|
| Panel type | Heatmap |
| Format | Heatmap |
| Unit | ms |

---

### Panel 4: Slow Traces (Table + Tempo Link)

| 設定項目 | 値 |
|---|---|
| Data source | Tempo |
| Panel type | Table |
| Query type | Search |

**Tempo Search 設定:**
- Service Name: `$service_name`
- Min Duration: `1s`

> テーブルの TraceID カラムから直接 Tempo のトレース詳細へジャンプ可能。

---

## Dashboard 3: Infrastructure & vCluster

### Panel 1: Pod CPU 使用率 (Time Series)

**PromQL:**

```promql
sum by (pod) (
  rate(container_cpu_usage_seconds_total{
    namespace="vcluster-otel-demo",
    container!="",
    container!="POD"
  }[5m])
)
```

| オプション | 値 |
|---|---|
| Legend | `{{pod}}` |
| Unit | cores |

---

### Panel 2: Pod Memory 使用量 (Time Series)

**PromQL:**

```promql
sum by (pod) (
  container_memory_working_set_bytes{
    namespace="vcluster-otel-demo",
    container!="",
    container!="POD"
  }
)
```

| オプション | 値 |
|---|---|
| Legend | `{{pod}}` |
| Unit | bytes (SI) |

---

### Panel 3: Pod Memory 使用率 vs Limit (Gauge)

**PromQL:**

```promql
sum by (pod) (
  container_memory_working_set_bytes{
    namespace="vcluster-otel-demo",
    container!="",
    container!="POD"
  }
)
/
sum by (pod) (
  kube_pod_container_resource_limits{
    namespace="vcluster-otel-demo",
    resource="memory"
  }
)
```

| オプション | 値 |
|---|---|
| Panel type | Gauge または Bar gauge |
| Unit | Percent (0.0-1.0) |
| Thresholds | 0.7 (yellow), 0.9 (red) |
| Min | 0 |
| Max | 1 |

---

### Panel 4: vCluster Control Plane リソース (Time Series)

**PromQL (CPU):**
```promql
sum(
  rate(container_cpu_usage_seconds_total{
    namespace="vcluster-otel-demo",
    pod=~"otel-demo-0.*"
  }[5m])
)
```

**PromQL (Memory):**
```promql
sum(
  container_memory_working_set_bytes{
    namespace="vcluster-otel-demo",
    pod=~"otel-demo-0.*"
  }
)
```

---

## Dashboard 4: Telemetry Pipeline

### Panel 1: OTel Collector - Spans Sent/Failed (Time Series)

**PromQL:**

Query A - Sent:
```promql
sum(rate(otelcol_exporter_sent_spans_total[5m]))
```

Query B - Failed:
```promql
sum(rate(otelcol_exporter_send_failed_spans_total[5m]))
```

| オプション | 値 |
|---|---|
| Legend | A: "Sent", B: "Failed" |
| Unit | spans/s |

---

### Panel 2: OTel Collector - Log Records (Time Series)

**PromQL:**

Query A - Sent:
```promql
sum(rate(otelcol_exporter_sent_log_records_total[5m]))
```

Query B - Failed:
```promql
sum(rate(otelcol_exporter_send_failed_log_records_total[5m]))
```

---

### Panel 3: OTel Collector - Metrics (Time Series)

**PromQL:**

Query A - Sent:
```promql
sum(rate(otelcol_exporter_sent_metric_points_total[5m]))
```

Query B - Failed:
```promql
sum(rate(otelcol_exporter_send_failed_metric_points_total[5m]))
```

---

### Panel 4: OTel Collector - Queue Size (Gauge)

**PromQL:**

```promql
sum(otelcol_exporter_queue_size) / sum(otelcol_exporter_queue_capacity)
```

| オプション | 値 |
|---|---|
| Panel type | Gauge |
| Unit | Percent (0.0-1.0) |
| Thresholds | 0.7 (yellow), 0.9 (red) |

---

### Panel 5: Receiver Accepted vs Refused (Time Series)

**PromQL:**

Query A - Accepted Spans:
```promql
sum(rate(otelcol_receiver_accepted_spans_total[5m]))
```

Query B - Refused Spans:
```promql
sum(rate(otelcol_receiver_refused_spans_total[5m]))
```

---

## ダッシュボード完成後の作業

1. 各ダッシュボードを作成したら **Dashboard Settings > JSON Model** から JSON をコピー
2. `manifests/monitoring/grafana-dashboards.yaml` 等の ConfigMap リソースとして組み込んで保存します。
