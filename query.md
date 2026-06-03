# PromQL Queries

## ホストクラスタ リソース監視

### CPU

```promql
# Namespace ごとの CPU 使用率
sum(rate(container_cpu_usage_seconds_total{container!="", pod!=""}[5m])) by (namespace)

# Pod ごとの CPU 使用率
sum(rate(container_cpu_usage_seconds_total{container!="", pod!=""}[5m])) by (namespace, pod)
```

### Memory

```promql
# Namespace ごとのメモリ使用量
sum(container_memory_working_set_bytes{container!="", pod!=""}) by (namespace)

# Pod ごとのメモリ使用量
sum(container_memory_working_set_bytes{container!="", pod!=""}) by (namespace, pod)
```

### コンテナ再起動数

```promql
sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod, container)
```

---

## 計装サンプルサーバー メトリクス (Pattern A / B)

### エラーレート（vCluster 別）

```promql
100 * sum by (vcluster) (
  rate(http_server_request_duration_seconds_count{
    job=~"go-api-server-pattern-[ab]",
    http_response_status_code=~"5.."
  }[5m])
  or
  rate(http_server_request_duration_seconds_count{
    job=~"beyla-.*"
  }[5m]) * 0
)
/
sum by (vcluster) (
  rate(http_server_request_duration_seconds_count{
    job=~"go-api-server-pattern-[ab]"
  }[5m])
)
```

### P99 レイテンシ（OTel SDK）

```promql
histogram_quantile(0.99,
  sum by (job, le) (
    rate(http_server_request_duration_seconds_bucket{
      job=~"go-api-server-pattern-[ab]"
    }[5m])
  )
)
```

### P99 レイテンシ（Beyla / Pattern C）

```promql
histogram_quantile(0.99,
  sum by (k8s_namespace_name, le) (
    rate(http_server_request_duration_seconds_bucket{
      k8s_namespace_name="vcluster-3"
    }[5m])
  )
)
```

### url_path 別リクエスト数（Beyla ノイズ確認）

```promql
increase(http_server_request_duration_seconds_count{
  k8s_namespace_name="vcluster-3"
}[1h])
```

---

## Grafana Alloy 自己メトリクス

> Alloy の自己メトリクスは Prometheus に収集されていないため、kubectl exec で直接取得する。
>
> ```bash
> kubectl exec -n monitoring <alloy-pod> -- \
>   wget -qO- http://localhost:12345/metrics | \
>   grep -E "^otelcol_(receiver_accepted|exporter_sent|exporter_send_failed|exporter_queue)"
> ```

### キューサイズ（0 なら問題なし）

```promql
otelcol_exporter_queue_size
```

### 送信失敗レート（0 なら問題なし）

```promql
rate(otelcol_exporter_send_failed_spans_total[5m])
rate(otelcol_exporter_send_failed_metric_points_total[5m])
```

### 受信 vs 送信の比率（1.0 に近ければデータロスなし）

```promql
rate(otelcol_exporter_sent_spans_total[5m])
/
rate(otelcol_receiver_accepted_spans_total[5m])
```

---

## アラートルール確認

### HighErrorRate（SpanMetrics ベース）

```promql
(
  sum by (service_name) (
    rate(traces_span_metrics_calls_total{
      span_kind="SPAN_KIND_SERVER",
      status_code="STATUS_CODE_ERROR"
    }[5m])
  )
  /
  sum by (service_name) (
    rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
  )
) * 100
```

### StorageNearFull

```promql
kubelet_volume_stats_used_bytes{namespace="monitoring"}
/ kubelet_volume_stats_capacity_bytes{namespace="monitoring"}
```

---

## vCluster リソースクォータ

```promql
# 使用率（80% 超で警告）
kube_resourcequota{type="used"}
/ ignoring(type)
kube_resourcequota{type="hard"}
```
