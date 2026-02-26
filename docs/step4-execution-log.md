# Step 4: 障害注入シナリオ 実行ログ

## 実施環境

| 項目 | 値 |
|---|---|
| 実施日 | &nbsp; |
| 実施者 | &nbsp; |
| vCluster バージョン | OTel Demo 2.2.0 |
| Grafana URL | http://localhost:3000 |
| flagd-ui URL | http://localhost:8080/feature |

## 事前セットアップ確認

```bash
# ターミナル 1: Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# ターミナル 2: flagd-ui
kubectl port-forward svc/frontend-proxy-x-otel-demo-x-otel-demo 8080:8080 -n vcluster-otel-demo
```

| チェック項目 | 確認 |
|---|---|
| Grafana http://localhost:3000 が開ける | [ ] |
| flagd-ui http://localhost:8080/feature が開ける | [ ] |
| 全 Feature Flag が `off` | [ ] |
| Alerting > Alert rules で全 7 ルールが `Normal` | [ ] |

---

## ベースライン記録（全シナリオ実施前）

**記録時刻**: ____:____

### Service Overview ダッシュボード > Service Health Summary テーブル

> Grafana > Dashboards > vCluster dashboard - Service Overview

| Service | Request Rate (req/s) | Error Rate |
|---|---|---|
| ad | | |
| cart | | |
| checkout | | |
| frontend | | |
| payment | | |
| product-catalog | | |
| recommendation | | |
| shipping | | |

### Alerting > Alert rules

| アラート名 | 状態 |
|---|---|
| HighErrorRate | Normal / Pending / Firing |
| HighLatencyP99 | Normal / Pending / Firing |
| ServiceDown | Normal / Pending / Firing |
| PodOOMKillRisk | Normal / Pending / Firing |
| TelemetryPipelineDrop | Normal / Pending / Firing |
| StorageNearFull | Normal / Pending / Firing |
| vClusterQuotaExhaustion | Normal / Pending / Firing |

---

## シナリオ 1: 単一サービスのエラー注入（adFailure）

### 1-1. ベースライン記録

**記録時刻**: ____:____

> **確認場所**: Service Overview > **Service Health Summary** テーブル（ad 行）

| 指標 | 値 |
|---|---|
| ad: Request Rate (req/s) | |
| ad: Error Rate | |

> **確認場所**: Service Overview > **Latency by Service (P50 / P95 / P99)** グラフ

| 指標 | 値 |
|---|---|
| ad: P99 レイテンシ (ms) | |

### 1-2. 障害注入

**方法**: http://localhost:8080/feature を開き `adFailure` を `on` に変更

> または ConfigMap を直接編集:
> ```bash
> kubectl edit configmap flagd-config-x-otel-demo-x-otel-demo -n vcluster-otel-demo
> # "adFailure" の "defaultVariant": "off" → "on" に変更して :wq
> ```

**注入時刻**: ____:____

### 1-3. 観察記録

> **主な確認ダッシュボード**: Service Overview

| 経過 | 確認パネル | 期待 | 実際 | 確認時刻 |
|---|---|---|---|---|
| ~1分後 | **Service Health Summary** テーブル > ad 行 Error Rate | 上昇開始（赤色） | | ____:____ |
| ~1分後 | **Error Rate by Service** グラフ > ad の線 | 急上昇 | | ____:____ |
| ~2分後 | Tempo でトレース検索（Service=`ad`, Status=`error`） | エラースパンが出現 | | ____:____ |
| ~5分後 | Alerting > Alert rules > **HighErrorRate** | Pending → Firing | | ____:____ |
| ~5分後 | **Service Map** (Node Graph パネル) | ad ノードがエラー色 | | ____:____ |

### 1-4. 相関分析ワークフロー

**Step 1 - メトリクスで異常を検知**

> Service Overview > **Error Rate by Service** グラフ

- エラーレート上昇を最初に視認した時刻: ____:____
- ad のピーク Error Rate: ____%

**Step 2 - Tempo でエラートレースを確認**

> Grafana > Explore > Tempo
> - Service Name: `ad`
> - Status: `error` (または Tags に `status=error`)

- エラートレースの TraceID（任意の 1 件）: `________________________________`
- エラーが発生しているスパン名: `________________________________`

**Step 3 - Loki でエラーログを確認**

> Grafana > Explore > Loki

```logql
{service_name="ad"} |= "error"
```

または TraceID で検索:
```logql
{service_name="ad"} |= "<上記の TraceID>"
```

- エラーメッセージの内容: `________________________________`

### 1-5. 復旧

**方法**: http://localhost:8080/feature で `adFailure` を `off` に変更

**復旧操作時刻**: ____:____

| 確認項目 | 確認時刻 | 結果 |
|---|---|---|
| Service Health Summary で ad の Error Rate が 0 に戻る | ____:____ | |
| HighErrorRate アラートが `Normal` に戻る | ____:____ | |

### 1-6. 評価サマリー

| 指標 | 値 |
|---|---|
| **MTTD** (最初の視認時刻 - 注入時刻) | ____分 |
| **MTTR** (メトリクス正常化時刻 - 復旧操作時刻) | ____分 |
| アラート Firing までの時間 | ____分 |
| 根本原因特定までのステップ数 | ____ステップ |

| 評価項目 | 結果 (○/△/×) | コメント |
|---|---|---|
| 5分以内にアラート Firing | | |
| ad のみが影響と即座に判断できた | | |
| トレース→ログで根本原因を特定できた | | |
| 復旧後にメトリクスがリアルタイムに回復した | | |

---

## シナリオ 2: クリティカルパスの障害（paymentFailure）

### 2-1. ベースライン記録

**記録時刻**: ____:____

> **確認場所**: Service Overview > **Service Health Summary** テーブル

| Service | Request Rate (req/s) | Error Rate |
|---|---|---|
| payment | | |
| checkout | | |
| frontend | | |

### 2-2. Phase A: 10% エラー注入

**方法**: http://localhost:8080/feature で `paymentFailure` を `10%` に変更

**注入時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 |
|---|---|---|---|
| ~2分後 | **Service Health Summary** > payment Error Rate | ~10% | |
| ~2分後 | **Service Health Summary** > checkout Error Rate | 連動して上昇 | |
| ~5分後 | Alerting > **HighErrorRate** | payment に Pending | |

### 2-3. Phase B: 50% エラー注入

**方法**: `paymentFailure` を `50%` に変更

**変更時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 |
|---|---|---|---|
| ~1分後 | **Service Health Summary** > payment Error Rate | ~50% | |
| ~2分後 | **Service Health Summary** > checkout Error Rate | 大幅に上昇 | |
| ~3分後 | **Service Map** | payment→checkout エッジがエラー色 | |

### 2-4. Phase C: 100% エラー注入

**方法**: `paymentFailure` を `100%` に変更

**変更時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 |
|---|---|---|---|
| ~1分後 | **Service Health Summary** > payment Error Rate | ~100% | |
| ~5分後 | Alerting > **ServiceDown** | payment に Firing | |

### 2-5. 相関分析ワークフロー

**Step 1 - checkout のエラートレースを Tempo で検索**

> Explore > Tempo > Service Name: `checkout`, Status: `error`

- エラートレースを 1 件開き、エラーが発生しているスパンのサービス名: `____________`
- payment が起点であると確認できたか: はい / いいえ

**Step 2 - Loki で payment のエラーログを確認**

```logql
{service_name="payment"} | json | level="error"
```

- エラーメッセージ: `________________________________`

### 2-6. Phase ごとの記録サマリー

| Phase | 設定値 | 実測 payment Error Rate | 実測 checkout Error Rate | アラート | 検知時間 |
|---|---|---|---|---|---|
| A | 10% | | | | ____分 |
| B | 50% | | | | ____分 |
| C | 100% | | | | ____分 |

### 2-7. 復旧

**方法**: `paymentFailure` を `off` に変更

**復旧時刻**: ____:____

| 確認項目 | 結果 |
|---|---|
| payment Error Rate が 0 に戻る | |
| checkout Error Rate が正常化する | |
| アラートが `Normal` に戻る | |

---

## シナリオ 3: カスケード障害（productCatalogFailure）

### 3-1. ベースライン記録

**記録時刻**: ____:____

> **確認場所**: Service Overview > **Service Health Summary** テーブル

| Service | Request Rate (req/s) | Error Rate |
|---|---|---|
| product-catalog | | |
| recommendation | | |
| frontend | | |
| checkout | | |

### 3-2. 障害注入

**方法**: `productCatalogFailure` を `on` に変更

**注入時刻**: ____:____

### 3-3. カスケード影響の記録

> **主な確認ダッシュボード**: Service Overview > **Error Rate by Service** グラフ
> および **Service Map** (Node Graph)

| 経過 | 影響サービス | 確認パネル | 期待 | 実際 | 確認時刻 |
|---|---|---|---|---|---|
| ~1分後 | product-catalog | Service Health Summary | Error Rate 上昇 | | ____:____ |
| ~2分後 | recommendation | Service Health Summary | 連動して上昇 | | ____:____ |
| ~3分後 | frontend | Service Health Summary | 商品ページでエラー | | ____:____ |
| ~5分後 | - | **Service Map** | product-catalog 起点で放射状にエラー | | ____:____ |
| ~5分後 | - | Alerting > **HighErrorRate** | 複数サービスに Firing | | ____:____ |

### 3-4. 影響範囲の記録

| サービス | エラー開始時刻 | ピーク Error Rate | 根本原因との関係 |
|---|---|---|---|
| product-catalog | ____:____ | ____% | 障害元 |
| recommendation | ____:____ | ____% | product-catalog に直接依存 |
| frontend | ____:____ | ____% | product-catalog に直接依存 |
| checkout | ____:____ | ____% | 間接依存 |
| payment | ____:____ | ____% | 影響なし（期待値） |

> **Service Map でのカスケード確認**: Tempo > Service Overview > Service Map パネル
> - product-catalog を起点にしたエラーの伝播パターンをスクリーンショット撮影

### 3-5. 復旧

**方法**: `productCatalogFailure` を `off` に変更

**復旧時刻**: ____:____

---

## シナリオ 4: リソース枯渇によるサービス劣化（adHighCpu + emailMemoryLeak）

### 4-1. ベースライン記録

**記録時刻**: ____:____

> **確認場所**: Infrastructure ダッシュボード > **CPU Usage % | vCluster** グラフ / **Memory Usage % | vCluster** グラフ

| Service / Pod | CPU 使用量 (cores) | Memory 使用量 (Mi) |
|---|---|---|
| ad-* | | |
| email-* | | |

> **確認場所**: Service Overview > **Latency by Service (P50 / P95 / P99)** グラフ

| Service | P99 レイテンシ (ms) |
|---|---|
| ad | |

### 4-2. CPU 高負荷の注入

**方法**: `adHighCpu` を `on` に変更

**注入時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 | 確認時刻 |
|---|---|---|---|---|
| ~1分後 | Infrastructure > **CPU Usage % \| vCluster** > ad pod | CPU 急上昇 | | ____:____ |
| ~2分後 | Service Overview > **Latency by Service** > ad P99 | P99 増加 | | ____:____ |
| ~5分後 | Alerting > **HighLatencyP99** | ad に Firing | | ____:____ |

**ad のピーク CPU 使用量**: ____ cores
**ad のピーク P99 レイテンシ**: ____ ms

### 4-3. メモリリークの注入

**方法**: `emailMemoryLeak` を `10x` に変更（CPU 高負荷を維持したまま）

**注入時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 | 確認時刻 |
|---|---|---|---|---|
| ~2分後 | Infrastructure > **Memory Usage % \| vCluster** > email pod | 緩やかに上昇 | | ____:____ |
| ~10分後 | Alerting > **PodOOMKillRisk** | email に Firing (90%超) | | ____:____ |
| 随時 | `kubectl get pods -n vcluster-otel-demo \| grep email` | RESTARTS 増加の可能性 | | ____:____ |

> メモリリークが遅い場合は `emailMemoryLeak` を `100x` に変更して加速:
> **変更時刻**: ____:____

**email のメモリ推移記録**:

| 確認時刻 | Memory 使用量 (Mi) | 使用率 (vs limit 150Mi) |
|---|---|---|
| 注入直後 | | |
| 5分後 | | |
| 10分後 | | |

### 4-4. 復旧

**方法**:
1. `adHighCpu` を `off` に変更
2. `emailMemoryLeak` を `off` に変更

**復旧時刻**: ____:____

| 確認項目 | 結果 |
|---|---|
| ad の CPU が正常化（Infrastructure ダッシュボードで確認） | |
| email の Memory が正常化（または Pod 再起動後に正常） | |
| HighLatencyP99 / PodOOMKillRisk が `Normal` に戻る | |

---

## シナリオ 5: 負荷集中とキュー滞留（loadGeneratorFloodHomepage + kafkaQueueProblems）

### 5-1. ベースライン記録

**記録時刻**: ____:____

> **確認場所**: Service Overview > **Request Rate by Service** グラフ

| 指標 | 値 |
|---|---|
| frontend リクエストレート (req/s) | |

> **確認場所**: Infrastructure ダッシュボード > **Receiver Throughput** グラフ

| 指標 | 値 |
|---|---|
| OTel Collector 受信スループット | |

### 5-2. 負荷集中の注入

**方法**: `loadGeneratorFloodHomepage` を `on` に変更

**注入時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 | 確認時刻 |
|---|---|---|---|---|
| ~1分後 | Service Overview > **Request Rate by Service** > frontend | 急増 | | ____:____ |
| ~2分後 | Service Overview > **Latency by Service** > frontend | 上昇 | | ____:____ |
| ~3分後 | Infrastructure > **CPU Usage % \| vCluster** > frontend/frontend-proxy | 上昇 | | ____:____ |
| ~5分後 | Infrastructure > **Receiver Throughput** | テレメトリ量増加 | | ____:____ |

**frontend のピークリクエストレート**: ____ req/s

### 5-3. Kafka 問題の追加注入

**方法**: `kafkaQueueProblems` を `on` に変更（負荷集中を維持したまま）

**注入時刻**: ____:____

| 経過 | 確認パネル | 期待 | 実際 | 確認時刻 |
|---|---|---|---|---|
| ~2分後 | Service Overview > **Latency by Service** > accounting / fraud-detection | 増加 | | ____:____ |
| ~5分後 | Alerting > **HighLatencyP99** | 関連サービスに Firing | | ____:____ |

### 5-4. 復旧

**方法**:
1. `kafkaQueueProblems` を `off`
2. `loadGeneratorFloodHomepage` を `off`

**復旧時刻**: ____:____

---

## シナリオ 6: 複合障害（paymentFailure + recommendationCacheFailure + imageSlowLoad）

### 6-1. ベースライン記録

**記録時刻**: ____:____

> 全サービスが Normal であることを確認しスクリーンショットを撮影

| 確認項目 | 値 |
|---|---|
| 全ルール Normal 確認 | [ ] |
| Service Overview スクリーンショット撮影 | [ ] |

### 6-2. 複合障害の注入

以下の 3 フラグを **同時に** 変更（http://localhost:8080/feature）:

| フラグ | 設定値 | 変更確認 |
|---|---|---|
| `paymentFailure` | `25%` | [ ] |
| `recommendationCacheFailure` | `on` | [ ] |
| `imageSlowLoad` | `5sec` | [ ] |

**注入完了時刻**: ____:____

### 6-3. Phase 1: 初動確認（注入後 5 分以内）

> **確認場所**: Service Overview > **Service Health Summary** テーブル（Error Rate 降順ソート済み）

| 確認項目 | 結果 |
|---|---|
| アラートが Firing / Pending のサービス | |
| Error Rate が上昇しているサービス | |
| P99 レイテンシが上昇しているサービス | |

### 6-4. Phase 2: 影響の切り分け（5〜10 分）

> **確認場所**: Service Overview > **Error Rate by Service** + **Latency by Service**
> + Infrastructure > **Memory Usage % | vCluster**

| 問題カテゴリ | 影響サービス | 独立した問題か / カスケードか |
|---|---|---|
| エラー系 | | |
| レイテンシ系 | | |
| リソース系 | | |

### 6-5. Phase 3: 根本原因の特定（10〜20 分）

**問題 A: 決済エラー**

> Explore > Tempo > Service Name: `payment`, Status: `error`

| 項目 | 記録 |
|---|---|
| エラースパン名 | |
| エラーログの内容（Loki: `{service_name="payment"} \| json \| level="error"`） | |
| 根本原因 | paymentFailure フラグ / その他 |

**問題 B: フロントエンドの遅延**

> Service Overview > **Latency by Service** > frontend / image-provider

| 項目 | 記録 |
|---|---|
| レイテンシが高いサービス | |
| Tempo で遅いスパン名 | |
| 根本原因 | imageSlowLoad フラグ / その他 |

**問題 C: レコメンデーションの劣化**

> Infrastructure > **Memory Usage % | vCluster** > recommendation pod

| 項目 | 記録 |
|---|---|
| recommendation の Memory 上昇トレンド | あり / なし |
| 根本原因 | recommendationCacheFailure フラグ / その他 |

### 6-6. 根本原因特定サマリー

| 問題 | 最初に気づいたシグナル | 根本原因の特定方法 | 特定までの時間 | 正しく特定できたか |
|---|---|---|---|---|
| 決済エラー | | | ____分 | はい / いいえ |
| 画像遅延 | | | ____分 | はい / いいえ |
| キャッシュ肥大化 | | | ____分 | はい / いいえ |

### 6-7. 復旧（影響の大きい順）

| 順序 | フラグ | 変更値 | 復旧時刻 | 回復確認 |
|---|---|---|---|---|
| 1 | `paymentFailure` | `off` | ____:____ | |
| 2 | `imageSlowLoad` | `off` | ____:____ | |
| 3 | `recommendationCacheFailure` | `off` | ____:____ | |

---

## 全シナリオ総合評価

| シナリオ | MTTD | MTTR | アラート正確性 | 総合評価 (1-5) |
|---|---|---|---|---|
| 1: adFailure | ____分 | ____分 | 正確 / 誤検知 / 漏れ | |
| 2: paymentFailure | ____分 | ____分 | 正確 / 誤検知 / 漏れ | |
| 3: productCatalogFailure | ____分 | ____分 | 正確 / 誤検知 / 漏れ | |
| 4: adHighCpu + emailMemoryLeak | ____分 | ____分 | 正確 / 誤検知 / 漏れ | |
| 5: loadGenerator + kafka | ____分 | ____分 | 正確 / 誤検知 / 漏れ | |
| 6: 複合障害 | ____分 | ____分 | 正確 / 誤検知 / 漏れ | |

### 気づいた改善点

| カテゴリ | 内容 |
|---|---|
| ダッシュボード | |
| アラートルール | |
| トレース/ログ相関 | |
| その他 | |
