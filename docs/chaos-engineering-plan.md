# カオスエンジニアリング検証計画 - krkn × vCluster

## 1. 概要

オブザーバビリティ技術検証 (observability-verification-plan.md) の次フェーズとして、krkn を用いたカオスエンジニアリングを vCluster 上で実施する。
前フェーズの Feature Flag による**アプリケーションレベル**の障害注入に対し、本フェーズでは krkn による**インフラレベル**の障害注入を行い、オブザーバビリティ基盤の検知能力を多角的に検証する。

### 前フェーズとの関係

```
前フェーズ (Feature Flags)          本フェーズ (krkn)
─────────────────────────         ─────────────────────────
アプリケーションレベル障害            インフラレベル障害
- エラーレート増加                  - Pod 強制終了
- メモリリーク                     - ネットワーク遅延・パケットロス
- レイテンシ増加                   - CPU/Memory 枯渇
- サービス到達不能                  - DNS 障害
                                  - サービス中断
```

### krkn とは

krkn (旧 Kraken) は Red Hat が開発した Kubernetes 向けオープンソースカオスエンジニアリングツール。CNCF Sandbox プロジェクトとして採択されている。YAML ベースのシナリオ定義、Cerberus によるクラスタヘルス監視、PromQL ベースの SLO 検証を特徴とする。

### 検証環境

前フェーズと同一の環境を使用する。

| コンポーネント | 詳細 |
|---|---|
| インフラ | AWS EKS (ap-northeast-1, t3.large x2) |
| 仮想クラスタ | vCluster v0.30.4 (k3s v1.31.4) |
| アプリケーション | OpenTelemetry Demo v0.40.1 (20+ マイクロサービス) |
| 監視スタック | Prometheus / Tempo / Loki / Grafana Alloy / Grafana |
| カオスツール | krkn (krknctl CLI) |

---

## 2. 検証目的

### 目的 1: インフラ障害に対するオブザーバビリティの検知能力評価

前フェーズで構築したダッシュボード・アラートが、インフラレベルの障害を正しく検知できるかを検証する。

### 目的 2: vCluster 環境でのカオスエンジニアリングの実現可能性

vCluster (仮想クラスタ) 上で krkn がどの程度機能するか、制約を含めて明確化する。

### 目的 3: マイクロサービスのレジリエンス評価

Pod 障害やネットワーク障害に対するマイクロサービスの回復力 (自動復旧、グレースフルデグラデーション) を評価する。

### 目的 4: 障害検知から復旧までの End-to-End ワークフロー検証

障害発生 → アラート発火 → ダッシュボード確認 → トレース・ログ相関 → 根本原因特定 → 復旧確認の一連のフローを検証する。

---

## 3. vCluster における krkn の制約

vCluster は仮想クラスタであり、物理ノードを直接管理しない。そのため krkn のシナリオに制約が生じる。

| シナリオカテゴリ | vCluster 対応 | 備考 |
|---|:---:|---|
| Pod Scenarios (Pod Kill) | ○ | Kubernetes API 経由で完全に動作 |
| Container Scenarios | ○ | コンテナレベルの disruption が可能 |
| Pod Network Chaos | ○ | Pod 間のネットワーク障害注入 |
| CPU Hog | ○ | Pod 内での CPU 負荷生成 |
| Memory Hog | ○ | Pod 内での Memory 負荷生成 |
| IO Hog | ○ | Pod 内での IO 負荷生成 |
| Service Disruption | ○ | Kubernetes Service の disruption |
| DNS Outage | △ | vCluster 内 DNS に限定 |
| Node Scenarios | ✕ | 物理ノードへのアクセス不可 |
| Zone Outage | ✕ | AZ 管理は EKS ホスト側の権限 |
| Power Outage | ✕ | 物理インフラへのアクセス不可 |
| ETCD Split Brain | ✕ | vCluster の etcd は直接操作不可 |

---

## 4. 検証シナリオ

前フェーズで構築済みのダッシュボード・アラートの検知能力を、インフラ障害の観点から評価する。
シナリオは**段階的に実行**し、単一障害から複合障害へとエスカレーションする。

### Phase 1: 単一障害シナリオ (基本)

#### シナリオ 1-1: クリティカルサービスの Pod Kill

**概要**: クリティカルパス上のサービス Pod を強制終了し、自動復旧とその間の影響を観測する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `pod-scenarios` |
| 対象 Pod | `checkout`, `payment`, `frontend` (各1つずつ個別実施) |
| Kill シグナル | `SIGKILL` (即時終了) |
| 期待する挙動 | Pod の再起動、一時的なエラーレート上昇、復旧後の正常化 |

**評価ポイント**:
- アラート `ServiceDown` が発火するか (Pending 期間 3 分)
- Pod 再起動までの時間 (MTTR)
- エラーのカスケード範囲 (依存サービスへの影響)
- Grafana ダッシュボードで障害サービスを即座に特定できるか
- トレースにエラースパンが記録されるか

#### シナリオ 1-2: Pod ネットワーク遅延

**概要**: 特定サービスの Pod に対してネットワーク遅延を注入し、レイテンシ上昇の検知能力を検証する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `pod-network-chaos` |
| 対象 Pod | `productcatalog`, `recommendation` |
| 注入する障害 | 遅延 500ms ± 100ms |
| 持続時間 | 5 分 |
| 期待する挙動 | P99 レイテンシの上昇、依存サービスのレイテンシ伝播 |

**評価ポイント**:
- アラート `HighLatencyP99` が発火するか (閾値 2000ms)
- SpanMetrics のレイテンシ分布変化が可視化されるか
- トレースのウォーターフォール表示で遅延箇所を特定できるか
- 遅延の伝播パターン (frontend → checkout → productcatalog)

#### シナリオ 1-3: Pod ネットワークパケットロス

**概要**: パケットロスによるサービス間通信の不安定化を再現する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `pod-network-chaos` |
| 対象 Pod | `cart`, `checkout` |
| 注入する障害 | パケットロス 30% |
| 持続時間 | 5 分 |
| 期待する挙動 | 間欠的なエラー発生、リトライによるレイテンシ増加 |

**評価ポイント**:
- エラーレートの増加パターン (一定ではなく間欠的)
- リトライに起因するレイテンシ増加が可視化されるか
- ログに通信エラーが記録されるか

#### シナリオ 1-4: CPU 負荷注入

**概要**: 特定 Pod の CPU リソースを枯渇させ、パフォーマンス劣化の検知能力を検証する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `cpu-hog` |
| 対象 | otel-demo namespace 内の Pod |
| 負荷レベル | CPU limit の 80-90% |
| 持続時間 | 5 分 |
| 期待する挙動 | レイテンシ上昇、スロットリング発生 |

**評価ポイント**:
- Infrastructure ダッシュボードで CPU 使用率の急上昇が確認できるか
- CPU スロットリングに伴うレイテンシ上昇が SpanMetrics に反映されるか
- `PodOOMKillRisk` (CPU 版の同等アラート) が検知するか

#### シナリオ 1-5: Memory 負荷注入

**概要**: メモリ枯渇による OOM Kill を再現する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `memory-hog` |
| 対象 | otel-demo namespace 内の Pod |
| 負荷レベル | Memory limit の 90-95% |
| 持続時間 | 段階的に増加 |
| 期待する挙動 | OOM Kill → Pod 再起動 |

**評価ポイント**:
- アラート `PodOOMKillRisk` が OOM Kill 前に発火するか
- OOM Kill 後の自動復旧時間
- メモリ使用量の推移がダッシュボードで可視化されるか

### Phase 2: サービス障害シナリオ (中級)

#### シナリオ 2-1: Service Disruption

**概要**: Kubernetes Service オブジェクトを disruption し、サービスディスカバリの障害を再現する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `service-disruption` |
| 対象 Service | `payment`, `productcatalog` |
| 持続時間 | 3 分 |
| 期待する挙動 | 依存サービスからの接続エラー |

**評価ポイント**:
- サービスマップ上で異常が表示されるか
- `ServiceDown` アラートの発火タイミング
- 上流サービス (checkout → payment) のエラートレースが記録されるか

#### シナリオ 2-2: DNS 障害

**概要**: DNS 解決の障害により、サービス間通信が全面的に影響を受ける状況を再現する。

| 項目 | 内容 |
|---|---|
| krkn シナリオ | `dns-outage` (vCluster 内 CoreDNS 対象) |
| 持続時間 | 2 分 |
| 期待する挙動 | 全サービス間通信の失敗 |

**評価ポイント**:
- 全サービスのエラーレート急増が検知されるか
- DNS エラーがログに記録され、Loki で検索可能か
- 複数サービスの同時障害から DNS が根本原因だと特定できるか

### Phase 3: 複合障害シナリオ (上級)

#### シナリオ 3-1: ネットワーク遅延 + Pod Kill

**概要**: ネットワーク遅延が発生している状態でサービス Pod を Kill し、複数障害が同時に発生する状況を再現する。

| 項目 | 内容 |
|---|---|
| 組み合わせ | `pod-network-chaos` (checkout: 300ms 遅延) + `pod-scenarios` (payment: SIGKILL) |
| 実行順序 | ネットワーク遅延を注入 → 2 分後に Pod Kill |
| 期待する挙動 | レイテンシ上昇中にさらにサービス停止 |

**評価ポイント**:
- 2 つの障害を個別に識別できるか (遅延 vs ダウン)
- アラートが 2 つ発火するか (`HighLatencyP99` + `ServiceDown`)
- トレースの相関分析で各障害の影響範囲を分離できるか

#### シナリオ 3-2: 連鎖的 Pod Kill (カスケード障害)

**概要**: 依存関係のある複数サービスを段階的に Kill し、カスケード障害の伝播を観測する。

| 項目 | 内容 |
|---|---|
| 対象 | `productcatalog` → `recommendation` → `frontend` (依存順に Kill) |
| 実行間隔 | 各 Kill の間に 1 分のインターバル |
| 期待する挙動 | 障害の段階的な拡大とエラーの伝播 |

**評価ポイント**:
- 障害の伝播をサービスマップ上で時系列に追跡できるか
- カスケード障害の根本原因 (最初の productcatalog) を特定できるか
- エラーレートの時系列変化から障害順序を推定できるか

---

## 5. 検証の前提条件

本フェーズの実施にあたり、以下の前提条件を満たすこと。

### 必須

- [ ] 前フェーズ Step 1-4 が完了していること
- [ ] 4 つのダッシュボード (Service Overview / RED / Infrastructure / Pipeline) が構築済みであること
- [ ] 7 つのアラートルールが設定済みであること
- [ ] 全 Pod が Running 状態であること (valkey-cart を含む)
- [ ] テレメトリパイプライン (OTel Collector → Alloy → Prometheus/Tempo/Loki) が正常動作していること

### 推奨

- [ ] Feature Flag テスト (Step 4) の結果が文書化されており、正常時ベースラインが確立されていること
- [ ] Grafana ダッシュボードの JSON エクスポートが保存されていること

---

## 6. krkn セットアップ手順

### 6.1 krknctl CLI のインストール

```bash
# macOS (Apple Silicon)
curl -L https://github.com/krkn-chaos/krknctl/releases/latest/download/krknctl-darwin-arm64 -o krknctl
chmod +x krknctl
sudo mv krknctl /usr/local/bin/

# 動作確認
krknctl version
```

### 6.2 kubeconfig の準備

krkn は kubeconfig 経由で Kubernetes API に接続する。vCluster の kubeconfig を使用する。

```bash
# vCluster の kubeconfig を取得
vcluster connect vcluster-demo --namespace vcluster-otel-demo --update-current=false \
  --kube-config ./kubeconfig-vcluster.yaml

# 接続確認
KUBECONFIG=./kubeconfig-vcluster.yaml kubectl get pods -n otel-demo
```

### 6.3 krkn RBAC 設定

krkn が vCluster 内で Pod Kill やネットワーク操作を行うための権限を設定する。

```yaml
# manifests/krkn/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: krkn
  namespace: otel-demo
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: krkn-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: krkn
    namespace: otel-demo
```

---

## 7. 実施手順

### Step 1: 環境準備と事前確認

1. 前フェーズの検証が完了していることを確認
2. krkn (krknctl) をインストール
3. vCluster への接続と RBAC 設定を確認
4. 全 Pod の Running 状態を確認
5. ダッシュボード・アラートの動作を確認
6. **正常時のベースラインメトリクスをスクリーンショットで記録**

### Step 2: Phase 1 - 単一障害シナリオの実行

各シナリオについて以下の手順で実施する:

1. **事前記録**: 実施前のダッシュボード状態をスクリーンショット
2. **障害注入**: krkn シナリオを実行
3. **観測**: ダッシュボードでリアルタイムに変化を監視
4. **アラート確認**: 期待するアラートが発火したかを記録
5. **原因特定**: Traces → Logs の相関分析で根本原因を特定
6. **復旧確認**: 障害終了後、メトリクスが正常値に回復することを確認
7. **結果記録**: MTTD (検知時間)、MTTR (復旧時間)、影響範囲を記録

**実行順序**: 1-1 → 1-2 → 1-3 → 1-4 → 1-5 (影響の小さいものから順に)

**各シナリオ間のクールダウン**: 最低 10 分 (メトリクスの安定化を待つ)

### Step 3: Phase 2 - サービス障害シナリオの実行

Step 2 と同様の手順で 2-1 → 2-2 を実行する。

### Step 4: Phase 3 - 複合障害シナリオの実行

Step 2 と同様の手順で 3-1 → 3-2 を実行する。
複合シナリオではアラートの同時発火、トレースの相関分析に注力する。

### Step 5: 結果の文書化

1. 全シナリオの結果を一覧表にまとめる
2. 前フェーズ (Feature Flag) の結果と比較分析
3. 検知できた障害 / 検知できなかった障害を分類
4. 改善提案 (アラート閾値の調整、新規ダッシュボードパネルの追加等) を記載

---

## 8. 評価基準

### 定量的指標

| 指標 | 目標値 | 測定方法 |
|---|---|---|
| MTTD (平均検知時間) | 5 分以内 | 障害注入時刻からアラート発火までの時間 |
| MTTR (平均復旧時間) | Pod: 1 分以内 / Network: 即時 | 障害終了から正常値復帰までの時間 |
| アラート発火率 | 100% | 期待するアラートが発火した割合 |
| 誤検知率 | 0% | 意図しないアラートが発火した割合 |
| 根本原因特定率 | 100% | 3 シグナル相関で根本原因を特定できた割合 |

### 定性的評価

| 観点 | 評価内容 |
|---|---|
| ダッシュボードの即時性 | 障害がリアルタイムでダッシュボードに反映されるか |
| 障害範囲の可視性 | サービスマップで影響範囲を直感的に把握できるか |
| 根本原因のトレーサビリティ | Metrics → Traces → Logs の相関で原因特定が容易か |
| カスケード障害の追跡性 | 複合障害時に各障害を個別に識別できるか |
| vCluster 固有の課題 | vCluster 環境特有の問題が発生するか |

---

## 9. 結果記録テンプレート

各シナリオの実施結果を以下のテンプレートで記録する。

```markdown
### シナリオ X-X: [シナリオ名]

**実施日時**: YYYY-MM-DD HH:MM

**krkn コマンド**:
(実行したコマンドを記載)

**タイムライン**:
| 時刻 | イベント |
|---|---|
| HH:MM:SS | 障害注入開始 |
| HH:MM:SS | ダッシュボードで異常確認 |
| HH:MM:SS | アラート発火 |
| HH:MM:SS | 根本原因特定 |
| HH:MM:SS | 障害終了 / 復旧確認 |

**MTTD**: X 分 X 秒
**MTTR**: X 分 X 秒

**アラート発火状況**:
| アラート | 発火 | 発火時刻 | 備考 |
|---|---|---|---|
| ServiceDown | Yes/No | HH:MM | |
| HighErrorRate | Yes/No | HH:MM | |
| HighLatencyP99 | Yes/No | HH:MM | |

**ダッシュボード所見**:
(スクリーンショットとともに記載)

**トレース・ログ相関分析**:
(TraceID を用いた分析結果を記載)

**所見・改善提案**:
(気づいた点、改善案を記載)
```

---

## 10. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| Pod Kill 後に Pod が再起動しない | サービス完全停止 | `kubectl rollout restart` で手動復旧。事前に deployment の replicas を確認 |
| ネットワーク障害がテレメトリパイプラインに影響 | 監視データのロス | Alloy / OTel Collector への障害注入は避ける。パイプラインダッシュボードを常時監視 |
| krkn の権限が vCluster で不足 | シナリオ実行失敗 | 事前に RBAC 設定をテスト。必要に応じて ClusterRole を調整 |
| EKS ホストクラスタへの意図しない影響 | 監視基盤の障害 | krkn の kubeconfig は vCluster のみを指定。namespace スコープで実行 |
| 複合障害で環境が不安定化 | 検証続行不能 | Phase 3 は最後に実施。環境復旧手順を事前に準備 |

---

## 11. 参考資料

- [krkn 公式ドキュメント](https://krkn-chaos.dev/docs/)
- [krkn GitHub リポジトリ](https://github.com/krkn-chaos/krkn)
- [krkn-hub (コンテナ化シナリオ)](https://github.com/krkn-chaos/krkn-hub)
- [krknctl CLI](https://github.com/krkn-chaos/krknctl)
- [vCluster × Chaos Mesh の事例](https://www.vcluster.com/blog/chaos-mesh-with-vcluster)
- [本プロジェクトのオブザーバビリティ検証計画](./observability-verification-plan.md)
