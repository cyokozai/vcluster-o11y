# 技術検証 サマリー: アラートルール・シナリオ・期待結果

## 1. アラートルール一覧

[grafana/alert-rules.yaml](../grafana/alert-rules.yaml) に定義された 7 つのアラートルール。

| # | アラート名 | グループ | 評価間隔 | 条件 | `for` | 重要度 | 備考 |
|---|---|---|---|---|---|---|---|
| 1 | **HighErrorRate** | service-health | 5m | エラーレート (SpanMetrics) > **5%** | 5m | critical | |
| 2 | **HighLatencyP99** | service-health | 5m | P99 レイテンシ > **2000ms** | 5m | warning | `flagd`, `image-provider` を除外 |
| 3 | **ServiceDown** | service-health | 5m | 成功リクエストレート < **0.001/s** (直近 3 分) | 5m | critical | `image-provider` を除外 |
| 4 | **PodOOMKillRisk** | service-health | 5m | Memory 使用率 > **90%** of limit | 5m | warning | ns: `vcluster-otel-demo` |
| 5 | **TelemetryPipelineDrop** | pipeline | 1m | 送信失敗スパン + ログ + メトリクスの合計レート > **0** | 3m | warning | |
| 6 | **vClusterQuotaExhaustion** | infrastructure | 5m | ResourceQuota 使用率 > **80%** | 10m | warning | ns: `vcluster-otel-demo` |
| 7 | **StorageNearFull** | infrastructure | 5m | PVC 使用率 > **85%** | 10m | warning | ns: `monitoring` |

### 各ルールの PromQL

```promql
# HighErrorRate
(
  sum by (service_name) (
    rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER", status_code="STATUS_CODE_ERROR"}[5m])
  )
  /
  sum by (service_name) (
    rate(traces_span_metrics_calls_total{span_kind="SPAN_KIND_SERVER"}[5m])
  )
) * 100 > 5

# HighLatencyP99
histogram_quantile(0.99,
  sum by (service_name, le) (
    rate(traces_span_metrics_duration_milliseconds_bucket{
      span_kind="SPAN_KIND_SERVER",
      service_name!~"flagd|image-provider"
    }[5m])
  )
) > 2000

# ServiceDown
sum by (service_name) (
  rate(traces_span_metrics_calls_total{
    span_kind="SPAN_KIND_SERVER",
    status_code!="STATUS_CODE_ERROR",
    service_name!="image-provider"
  }[3m])
) < 0.001

# PodOOMKillRisk
sum by (pod) (
  container_memory_working_set_bytes{namespace="vcluster-otel-demo", container!="", container!="POD"}
)
/
sum by (pod) (
  kube_pod_container_resource_limits{namespace="vcluster-otel-demo", resource="memory"}
) > 0.9

# TelemetryPipelineDrop
sum(rate(otelcol_exporter_send_failed_spans_total[5m]))
+ sum(rate(otelcol_exporter_send_failed_log_records_total[5m]))
+ sum(rate(otelcol_exporter_send_failed_metric_points_total[5m])) > 0

# vClusterQuotaExhaustion
kube_resourcequota{namespace="vcluster-otel-demo", type="used"}
/ ignoring(type)
kube_resourcequota{namespace="vcluster-otel-demo", type="hard"} > 0.8

# StorageNearFull
kubelet_volume_stats_used_bytes{namespace="monitoring"}
/ kubelet_volume_stats_capacity_bytes{namespace="monitoring"} > 0.85
```

> **計画書との差異**: `StorageNearFull` / `vClusterQuotaExhaustion` の `for` は計画書の 5m に対し実装は **10m**。`TelemetryPipelineDrop` の `for` は計画書の 1m に対し実装は **3m**。これらはストレージやリソースクォータの一時的なスパイクによる誤検知を抑制するため、評価時間を延長した意図的な変更である。

---

## 2. 障害注入シナリオ一覧

詳細手順は [step4-fault-injection-scenarios.md](step4-fault-injection-scenarios.md)、実行ログは [step4-execution-log.md](step4-execution-log.md) を参照。

| # | シナリオ名 | Feature Flag | 設定値 | 注入対象サービス | 障害の種類 | 発火期待アラート | 難易度 |
|---|---|---|---|---|---|---|---|
| 1 | **単一サービスのエラー注入** | `adFailure` | on | Ad | 1/10 確率でエラー | HighErrorRate (ad) | 基礎 |
| 2 | **クリティカルパスの障害** | `paymentFailure` | 10% → 50% → 100% | Payment | 確率的エラー（段階的） | HighErrorRate → ServiceDown (payment) | 基礎 |
| 3 | **カスケード障害の発生** | `productCatalogFailure` | on | Product Catalog | 特定商品でサービス障害 | HighErrorRate (複数サービス) | 応用 |
| 4 | **リソース枯渇によるサービス劣化** | `adHighCpu` + `emailMemoryLeak` | on / 10x〜100x | Ad, Email | CPU 高負荷 + メモリリーク | HighLatencyP99 (ad) + PodOOMKillRisk (email) | 応用 |
| 5 | **負荷集中とキュー滞留** | `loadGeneratorFloodHomepage` + `kafkaQueueProblems` | on / on | Frontend, Kafka | リクエスト急増 + コンシューマ遅延 | HighLatencyP99 (関連サービス) + TelemetryPipelineDrop | 応用 |
| 6 | **複合障害（実運用を想定）** | `paymentFailure` + `recommendationCacheFailure` + `imageSlowLoad` | 25% / on / 5sec | Payment, Recommendation, Frontend | 独立した 3 種の障害を同時注入 | HighErrorRate (payment) + HighLatencyP99 (frontend) + PodOOMKillRisk (recommendation) | 総合 |

### 検証テーマとの対応

| シナリオ | テーマ 1: パイプライン | テーマ 2: MTTD・検知精度 | テーマ 3: 3シグナル相関 | テーマ 4: SpanMetrics 精度 |
|---|---|---|---|---|
| 1 (adFailure) | | ◎ 基本動作確認 | ○ Metrics→Trace→Log | ○ |
| 2 (paymentFailure) | | ◎ 段階的検知・閾値適切性 | ◎ カスケード起点の特定 | ◎ |
| 3 (productCatalogFailure) | | ○ | ◎ Service Map の活用 | ○ |
| 4 (adHighCpu + emailMemoryLeak) | | ○ | ○ CPU→レイテンシの因果関係 | △ インフラメトリクスが主 |
| 5 (loadGenerator + kafka) | ◎ ドロップ検知 | ○ | △ | △ 高負荷時の精度 |
| 6 (複合障害) | | ◎ 優先度判断 | ◎ 3 問題の独立性判断 | ◎ |

---

## 3. 期待される結果の考察

### 3.1 テーマ 1: vCluster 環境でのオブザーバビリティパイプラインの実現性

**期待される結論: 実現可能（ただし制約あり）**

[manifests/vcluster/config.yaml](../manifests/vcluster/config.yaml) の `networking.replicateServices` により、vCluster 内の OTel Collector が `otel-demo/otelcol-to-alloy` という仮想サービスを通じてホストの Alloy に到達できる設計になっている。

| 評価指標 | 期待値 | 懸念点 |
|---|---|---|
| データロス率 | 通常時は 0 に近い | シナリオ 5 の負荷集中時に OTel Collector のキューが溢れた場合のみドロップが発生する可能性 |
| 転送遅延 | sub-second 程度 | Alloy Gateway 経由のため数百 ms 程度のオーバーヘッドが生じる |
| ラベル付与 | vCluster namespace のプレフィックスが付く | PromQL のラベルセレクタに影響する可能性があり、ダッシュボードのクエリ調整が必要な場合がある |

---

### 3.2 テーマ 2: Feature Flag による障害注入と検知能力の評価

**MTTD の期待値算出**

Prometheus の評価サイクルを踏まえると、アラートが Firing になるまでの時間は以下のとおり:

```
scrape interval (30s) + evaluation interval (5m) + for 期間 (5m)
= 最短 10〜11 分後に Firing
ダッシュボードでの目視確認: 注入後 1〜2 分で視認可能（期待 MTTD）
```

| シナリオ | 期待 MTTD（目視） | アラート Firing まで | 懸念点 |
|---|---|---|---|
| adFailure | ~1 分 | ~11 分 | 10% エラーは HighErrorRate(>5%) で確実に Firing |
| paymentFailure 10% | ~2 分 | ~11 分 | checkout のエラーが連動するため早期に気づける |
| paymentFailure 100% | ~1 分 | ~6 分 | ServiceDown (for: 5m) が先に Firing の可能性 |
| productCatalogFailure | ~2 分 | ~11 分 | 複数サービスに同時にアラートが発火 |

---

### 3.3 テーマ 3: 3シグナル (Metrics/Traces/Logs) の相関分析

**期待される根本原因特定フロー**

```
[Grafana] メトリクスでエラーレート上昇を検知
  └→ [Tempo] エラーが発生しているスパン・サービスを特定
       └→ [Loki] TraceID を使ってエラーログの詳細を確認
```

| シナリオ | 相関分析が特に有効な理由 |
|---|---|
| シナリオ 2 (paymentFailure) | checkout のエラートレースを開くと payment スパンがエラー起点であることが一目で分かる |
| シナリオ 3 (productCatalogFailure) | Service Map (Node Graph) で放射状にエラーが広がる様子が可視化され、product-catalog が起点であることが即座にわかる |
| シナリオ 6 (複合障害) | 3 つの問題が独立していることをトレースで確認できる（それぞれ異なるスパンにエラーが集中） |

**根本原因特定ステップ数の期待値**: 3〜4 ステップ（メトリクス確認 → Service Map → エラートレース → ログ確認）

---

### 3.4 テーマ 4: SpanMetrics によるトレースベースのメトリクス自動生成

OTel Demo はデフォルトでトレース 100% サンプリングのため、SpanMetrics から生成されるメトリクスとアプリ側のメトリクスはほぼ一致するはず。

| 観点 | 期待 | 懸念点 |
|---|---|---|
| 精度 | 100% サンプリング環境下では高精度 | シナリオ 5 の高負荷時にサンプリングドロップが起きるとエラーレートが過小評価される |
| カバレッジ | SPAN_KIND_SERVER のサーバーサイドスパンを網羅 | クライアントサイドのスパンは対象外のため、一部エンドポイントでカバレッジが落ちる可能性 |
| レイテンシ精度 | 通常時は高精度 | シナリオ 4 の CPU 高負荷時にヒストグラムバケットの設定によっては極端な高レイテンシの精度が低下する可能性 |

---

### 3.5 シナリオ別 期待される具体的な挙動

#### シナリオ 1 (adFailure)

- ad のエラーレート: **~10%**（1/10 の確率でエラー発生）
- 他サービスへの影響: **なし**（広告はクリティカルパスに存在しない）
- Loki のエラーログに `Feature flag 'adFailure' is enabled` などのメッセージが確認できるはず

#### シナリオ 2 (paymentFailure)

payment → checkout のカスケード伝播が Service Map で可視化される。

| Phase | 設定値 | 期待される payment Error Rate | 期待される checkout Error Rate | アラート |
|---|---|---|---|---|
| A | 10% | ~10% | ~10%（連動上昇） | HighErrorRate Pending |
| B | 50% | ~50% | 大幅上昇 | HighErrorRate Firing |
| C | 100% | ~100% | 大幅上昇 | ServiceDown Firing |

> checkout の Error Rate は payment の値と完全一致にはならない。checkout 自体のエラーハンドリングやリトライに依存するため。

#### シナリオ 3 (productCatalogFailure)

```
product-catalog [赤] ─→ recommendation [赤]
                    └─→ frontend       [赤] ─→ checkout [薄赤]
payment  [緑]  ← 影響なし
shipping [緑]  ← 影響なし
```

| サービス | 期待される影響 | 根本原因との関係 |
|---|---|---|
| product-catalog | エラーレート上昇 | 障害元 |
| recommendation | エラーレート上昇 | product-catalog に直接依存 |
| frontend | エラーレート上昇 | product-catalog に直接依存 |
| checkout | 軽微なエラーレート上昇 | 間接依存 |
| payment | **影響なし** | product-catalog を参照しない |
| shipping | **影響なし** | product-catalog を参照しない |

#### シナリオ 4 (adHighCpu + emailMemoryLeak)

- ad: CPU がスロットリングされることでトレースのスパン duration が伸び、P99 レイテンシが 2000ms を超えると `HighLatencyP99` が Firing
- email: Memory limit の 90% 超過が 5 分持続すると `PodOOMKillRisk` が Firing。場合によっては OOM Kill による Pod 再起動が発生する

#### シナリオ 5 (loadGeneratorFloodHomepage + kafkaQueueProblems)

- frontend リクエストレートが急増し、CPU/Memory 使用量も増加
- Kafka downstream の accounting / fraud-detection でレイテンシが増加
- OTel Collector のキューが逼迫した場合に `TelemetryPipelineDrop` が発火する可能性

#### シナリオ 6 (複合障害)

3 つの問題が独立していることが検証の核心。

| 問題 | 最初に気づきやすいシグナル | 根本原因の特定手段 | 対応優先度 |
|---|---|---|---|
| 決済エラー | HighErrorRate アラート | payment のエラートレース → Loki エラーログ | 高（ビジネスインパクト最大） |
| 画像読み込み遅延 | frontend の P99 レイテンシ上昇 | Tempo で image-provider スパンの duration を確認 | 中（UX への影響） |
| レコメンド劣化 | Infrastructure ダッシュボードのメモリ増加傾向 | recommendation の memory 推移グラフ | 低（漸進的な劣化） |

> recommendation のメモリ増加は漸進的なため、初動確認フェーズ（5 分以内）では見落としやすい。

---

### 3.6 検証全体を通した懸念点

| カテゴリ | 懸念点 | 影響シナリオ |
|---|---|---|
| **アラート感度** | HighErrorRate の `for: 5m` の間に断続的なエラーが発生すると Pending のまま Firing にならない可能性がある | シナリオ 1, 2-Phase A |
| **vCluster ラベル** | ホスト Prometheus がスクレイプする際のラベルにプレフィックスが付き、PromQL が機能しない可能性がある | 全シナリオ |
| **ResourceQuota** | `count/pods: 50` の制限下で OOM Kill による Pod 再起動が繰り返された場合に quota に抵触する可能性がある | シナリオ 4 |
| **SpanMetrics ラグ** | トレース → SpanMetrics 変換に Alloy の処理が介在するため、実際のエラー発生から Prometheus 反映まで 30〜60 秒程度のラグがある | 全シナリオ |
| **ServiceDown の誤検知** | 成功リクエストレート < 0.001/s という条件は、トラフィックが少ないサービスで正常時でも発火するリスクがある | 全シナリオ |

---

## 4. 参考リンク

| ドキュメント | 内容 |
|---|---|
| [observability-verification-plan.md](observability-verification-plan.md) | 検証全体の要件定義・実施手順 |
| [step1-baseline.md](step1-baseline.md) | ベースライン計測手順 |
| [step2-dashboard-setup.md](step2-dashboard-setup.md) | ダッシュボード構築手順 |
| [step3-alert-rules-setup.md](step3-alert-rules-setup.md) | アラートルール設定手順 |
| [step4-fault-injection-scenarios.md](step4-fault-injection-scenarios.md) | 障害注入シナリオ詳細手順 |
| [step4-execution-log.md](step4-execution-log.md) | 実行ログ・記録テンプレート |
