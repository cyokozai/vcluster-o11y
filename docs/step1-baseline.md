# Step 1: Feature Flag 確認とベースライン把握

## 実施日時
2025-02-11

## 1. Feature Flag 確認結果

ConfigMap `flagd-config` (namespace: `otel-demo`) から全 15 フラグを確認。全て `defaultVariant: "off"` (無効)。

| # | Flag 名 | state | defaultVariant | variants |
|---|---|---|---|---|
| 1 | `adFailure` | ENABLED | off | on/off |
| 2 | `adHighCpu` | ENABLED | off | on/off |
| 3 | `adManualGc` | ENABLED | off | on/off |
| 4 | `cartFailure` | ENABLED | off | on/off |
| 5 | `emailMemoryLeak` | ENABLED | off | off/1x/10x/100x/1000x/10000x |
| 6 | `failedReadinessProbe` | ENABLED | off | on/off |
| 7 | `imageSlowLoad` | ENABLED | off | off/5sec/10sec |
| 8 | `kafkaQueueProblems` | ENABLED | off | on(100)/off(0) |
| 9 | `llmInaccurateResponse` | ENABLED | off | on/off |
| 10 | `llmRateLimitError` | ENABLED | off | on/off |
| 11 | `loadGeneratorFloodHomepage` | ENABLED | off | on(100)/off(0) |
| 12 | `paymentFailure` | ENABLED | off | off/10%/25%/50%/75%/90%/100% |
| 13 | `paymentUnreachable` | ENABLED | off | on/off |
| 14 | `productCatalogFailure` | ENABLED | off | on/off |
| 15 | `recommendationCacheFailure` | ENABLED | off | on/off |

> **備考**: `state: ENABLED` はフラグが「評価可能な状態」を意味し、フラグが有効化されているわけではない。`defaultVariant: "off"` により全フラグは無効。

## 2. Grafana データソース接続確認

4 つのデータソースが正常に接続されている。

| データソース | 種類 | URL |
|---|---|---|
| Prometheus | prometheus | `http://kube-prometheus-stack-prometheus.monitoring:9090/` |
| Tempo | tempo | `http://tempo.monitoring:3200` |
| Loki | loki | `http://loki.monitoring:3100` |
| Alertmanager | alertmanager | `http://kube-prometheus-stack-alertmanager.monitoring:9093/` |

## 3. SpanMetrics 確認結果

以下の SpanMetrics が Prometheus に正常に取り込まれている。

- `traces_span_metrics_calls_total` - リクエスト数カウンタ
- `traces_span_metrics_duration_milliseconds_bucket` - レイテンシヒストグラム
- `traces_span_metrics_duration_milliseconds_count` - レイテンシカウント
- `traces_span_metrics_duration_milliseconds_sum` - レイテンシ合計

### 関連 OTel Collector メトリクス

- `otelcol_exporter_sent_spans_total` - エクスポート成功スパン数
- `otelcol_receiver_accepted_spans_total` - 受信成功スパン数
- `processedSpans_total` - 処理済みスパン数

## 4. 正常時ベースライン

### サービス別リクエストレート

| サービス | リクエストレート (req/s) |
|---|---|
| frontend | 1.9125 |
| frontend-proxy | 1.1917 |
| load-generator | 1.0667 |
| product-catalog | 0.7083 |
| product-reviews | 0.3250 |
| flagd | 0.2750 |
| ad | 0.1250 |
| cart | 0.0750 |
| recommendation | 0.0750 |
| checkout | 0.0125 |
| fraud-detection | ~0 |

### サービス別エラーレート

| サービス | エラーレート | 備考 |
|---|---|---|
| checkout | 66.67% | 高エラーレート（要調査） |
| load-generator | 13.28% | 依存先の影響と推測 |
| frontend-proxy | 12.59% | checkout エラーの伝播 |
| cart | 11.11% | valkey-cart が Pending 状態の影響 |
| frontend | 0.87% | 正常範囲 |
| ad | 0.00% | 正常 |
| flagd | 0.00% | 正常 |
| product-catalog | 0.00% | 正常 |
| product-reviews | 0.00% | 正常 |
| recommendation | 0.00% | 正常 |

> **注意**: checkout の高エラーレートは `valkey-cart` Pod が `Pending` 状態であることに起因する可能性がある。Feature Flag を使った検証の前にこの問題を解決する必要がある。

### サービス別 P99 レイテンシ

| サービス | P99 レイテンシ (ms) | 備考 |
|---|---|---|
| cart | 15,000 | タイムアウト (valkey-cart Pending の影響) |
| frontend | 15,000 | 依存先タイムアウトの影響 |
| frontend-proxy | 15,000 | 依存先タイムアウトの影響 |
| load-generator | 15,000 | 依存先タイムアウトの影響 |
| product-reviews | 187.00 | 正常範囲 |
| product-catalog | 43.20 | 正常範囲 |
| checkout | 5.97 | 正常範囲 (失敗が早い) |
| recommendation | 5.96 | 正常範囲 |
| ad | 3.40 | 正常範囲 |
| flagd | 1.98 | 正常範囲 |

## 5. 検出された問題

### valkey-cart Pod が Pending 状態

```
valkey-cart-78bcdd6d-pqct5   0/1   Pending   0   21h
```

この問題により以下の影響が出ている:
- cart サービスのエラーレート: 11.11%
- checkout サービスのエラーレート: 66.67%
- 複数サービスの P99 レイテンシがタイムアウト (15,000ms)

**推奨アクション**: Step 2 に進む前に valkey-cart の Pending 原因を調査・解決する。

## 6. クラスタ状態サマリ

| コンポーネント | 状態 | Pod 数 |
|---|---|---|
| OTEL Demo アプリケーション | 稼働中 (1 Pod Pending) | 24/25 |
| Grafana | 稼働中 | 1/1 |
| Prometheus | 稼働中 | 1/1 |
| Tempo | 稼働中 | 1/1 |
| Loki | 稼働中 | 1/1 |
| Alloy | 稼働中 | 2/2 |
| Alertmanager | 稼働中 | 1/1 |
| vCluster Control Plane | 稼働中 | 1/1 |
