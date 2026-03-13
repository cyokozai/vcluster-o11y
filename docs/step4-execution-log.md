# Step 4: 障害注入シナリオ 実行ログ

## 実施環境

| 項目 | 値 |
| --- | --- |
| 実施日 | |
| 実施者 | |
| OTel Demo バージョン | OTel Demo 2.2.0 |
| Grafana URL | http://localhost:3000 |
| flagd-ui URL | http://localhost:8080/feature |

## 事前確認

```bash
# ターミナル 1: Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# ターミナル 2: flagd-ui
kubectl port-forward svc/frontend-proxy-x-otel-demo-x-otel-demo 8080:8080 -n vcluster-otel-demo
```

| チェック項目 | 確認 |
| --- | --- |
| Grafana http://localhost:3000 が開ける | [ ] |
| flagd-ui http://localhost:8080/feature が開ける | [ ] |
| 全 Feature Flag が `off` | [ ] |
| Alerting > Alert rules で全 7 ルールが `Normal` | [ ] |

## 計測対象リソース

各シナリオで以下のリソースを確認する:

| リソース | 場所 |
| --- | --- |
| Error Rate / Request Rate / Latency (P99) | Grafana > Service Overview |
| CPU / Memory 使用率 | Grafana > Infrastructure |
| アラート状態 | Grafana > Alerting > Alert rules |
| エラースパン / Service Map | Grafana > Explore > Tempo |
| エラーログ（TraceID 相関） | Grafana > Explore > Loki |

---

## シナリオ 1: adFailure

| 項目 | 結果 | 時刻 |
| --- | --- | --- |
| 注入: `adFailure` = `on` | | |
| Service Overview > ad Error Rate 上昇 | ○ / × | |
| HighErrorRate アラート Firing | ○ / × | |
| Tempo > ad エラースパン取得 | ○ / × | |
| Loki > TraceID でエラーメッセージ確認 | ○ / × | |
| MTTD（初検知時刻 − 注入時刻） | 分 | |
| 復旧: `adFailure` = `off` | | |

---

## シナリオ 2: paymentFailure

| 項目 | 結果 | 時刻 |
| --- | --- | --- |
| 注入: `paymentFailure` = `50%` | | |
| payment + checkout Error Rate 連動上昇 | ○ / × | |
| Service Map で payment→checkout エッジがエラー色 | ○ / × | |
| HighErrorRate アラート Firing | ○ / × | |
| Tempo > checkout トレースで payment が起点と確認 | ○ / × | |
| MTTD | 分 | |
| 復旧: `paymentFailure` = `off` | | |

---

## シナリオ 3: productCatalogFailure

| 項目 | 結果 | 時刻 |
| --- | --- | --- |
| 注入: `productCatalogFailure` = `on` | | |
| Service Map で product-catalog 起点の伝播が赤表示 | ○ / × | |
| 複数サービスの Error Rate 上昇（時系列順） | ○ / × | |
| HighErrorRate アラート Firing（複数サービス） | ○ / × | |
| frontend トレースで product-catalog を根本原因特定 | ○ / × | |
| MTTD | 分 | |
| 復旧: `productCatalogFailure` = `off` | | |

---

## シナリオ 4: adHighCpu + emailMemoryLeak

| 項目 | 結果 | 時刻 |
| --- | --- | --- |
| 注入①: `adHighCpu` = `on` | | |
| Infrastructure > ad CPU 急上昇 | ○ / × | |
| Service Overview > ad P99 レイテンシ増加 | ○ / × | |
| HighLatencyP99 アラート Firing（ad） | ○ / × | |
| 注入②: `emailMemoryLeak` = `10x` | | |
| Infrastructure > email Memory 上昇トレンド | ○ / × | |
| PodOOMKillRisk アラート Firing（email） | ○ / × | |
| MTTD（ad 検知） | 分 | |
| 復旧: `adHighCpu` = `off`、`emailMemoryLeak` = `off` | | |

---

## シナリオ 5: loadGeneratorFloodHomepage + kafkaQueueProblems

| 項目 | 結果 | 時刻 |
| --- | --- | --- |
| 注入①: `loadGeneratorFloodHomepage` = `on` | | |
| Service Overview > frontend リクエストレート急増 | ○ / × | |
| Infrastructure > Receiver Throughput 増加 | ○ / × | |
| 注入②: `kafkaQueueProblems` = `on` | | |
| accounting / fraud-detection Latency 増加 | ○ / × | |
| HighLatencyP99 アラート Firing | ○ / × | |
| MTTD | 分 | |
| 復旧: `kafkaQueueProblems` → `loadGeneratorFloodHomepage` の順で `off` | | |

---

## シナリオ 6: 複合障害

注入: `paymentFailure`=`25%`、`recommendationCacheFailure`=`on`、`imageSlowLoad`=`5sec`

| 項目 | 結果 | 時刻 |
| --- | --- | --- |
| 注入完了 | | |
| 問題の切り分け（エラー系 / レイテンシ系 / リソース系）を列挙 | ○ / × | |
| Tempo + Loki で payment エラーの根本原因特定 | ○ / × | |
| frontend の遅いトレースで image-provider スパン確認 | ○ / × | |
| Infrastructure で recommendation Memory 上昇確認 | ○ / × | |
| Service Map で 3 問題が独立（非カスケード）と確認 | ○ / × | |
| MTTD（最初の問題） | 分 | |
| 復旧: `paymentFailure` → `imageSlowLoad` → `recommendationCacheFailure` の順で `off` | | |

---

## 総合評価

| シナリオ | MTTD | Alert | Traces | Logs | 評価（○/△/×）|
| --- | --- | --- | --- | --- | --- |
| 1: adFailure | 分 | ○/× | ○/× | ○/× | |
| 2: paymentFailure | 分 | ○/× | ○/× | ○/× | |
| 3: productCatalogFailure | 分 | ○/× | ○/× | ○/× | |
| 4: adHighCpu + emailMemoryLeak | 分 | ○/× | ○/× | ○/× | |
| 5: loadGenerator + kafka | 分 | ○/× | ○/× | ○/× | |
| 6: 複合障害 | 分 | ○/× | ○/× | ○/× | |

### 気づいた改善点

| カテゴリ | 内容 |
| --- | --- |
| ダッシュボード | |
| アラートルール | |
| トレース/ログ相関 | |
