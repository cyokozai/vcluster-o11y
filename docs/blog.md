# vClusterを用いたテスト環境の構築とGrafana Alloyによるオブザーバビリティの導入

## 自己紹介

### **井上 裕介**

千葉工業大学大学院 情報科学研究科 情報科学専攻 修士１年の井上 裕介と申します．

大学では主にメタヒューリスティクスに関する最適化アルゴリズムの研究に従事しております．

2024 年 からSreake 事業部にて技術調査を行っております．

## アジェンダ

- はじめに
    - Kubernetes を中心とした基盤運用の課題
    - 従来のアプローチとその限界
- vCluster
    - アーキテクチャ
    - テナンシーモデル
- オブザーバビリティ
    - Prometheus
    - Grafana
    - Tempo
- 環境構築
    - AWS EKS クラスタの構築
    - 仮想クラスタの作成
- 検証
    - vCluster の基本操作
    - デモアプリを使った仮想クラスタのモニタリング
    - テスト環境のオブザーバビリティについての評価
- 終わりに

## はじめに

### Kubernetes を中心とした基盤運用の課題

近年 Kubernetes は単一プロダクトや単一チームのための基盤から、複数チーム・複数サービスを同時に支える共通基盤へと役割を変えつつあります。

この変化に伴い、以下のような要求が顕在化しています。

- チームやプロジェクト単位での明確な責任分界点の確立
- 環境（開発・検証・本番）を物理的に分離したセキュアな構成
- 顧客・テナント単位での完全な権限分離とリソース隔離

### 従来のアプローチとその限界

ホストクラスタの RBAC や NetworkPolicy を用いた namespace 単位でのリソース分離は一定の効果がありますが、次のような課題があります。

- **完全な隔離の困難性**:
    
    namespace レベルでは API サーバーやコントロールプレーンを共有するため、クラスタ全体に影響を与える変更 (CRD のインストール、クラスタロールの設定など) が制約される
    
- **バージョン管理の硬直性**:
    
    複数チームが異なる Kubernetes バージョンを必要とする場合、物理クラスタを分ける必要がある
    
- **運用コストの増加**:
    
    各チームに専用クラスタを提供すると、クラスタ数に比例して管理コストが増大する
    

これらの課題を解決するために、次のような特性を持つソリューションが求められます。

- **軽量性**:
    
    数十秒で作成・削除できる Kubernetes クラスタ
    
- **テスト環境の柔軟性**:
    
    ブルー/グリーンデプロイやカナリアリリースを安全に検証できる独立した環境
    
- **弾力性**:
    
    ワークロード特性に応じて柔軟にスケールイン/アウトできる仕組み
    
- **コスト効率**:
    
    物理ノードの増設を伴わず運用コストを最小限に抑えられる構成
    
- **障害隔離性**:
    
    インシデント発生時に影響範囲を明確に切り分けられる分離性
    
- **冪等性**:
    
    Infrastructure as Code による再現可能な環境構築
    

vCluster はこれらの要求に対して次のような解決策を提示します。

- **マルチテナンシーの実現**:
    
    単一の物理クラスタ上で分離された複数の仮想クラスタを稼働
    
- **独立したコントロールプレーン**:
    
    各 vCluster が独自の API サーバー、etcd、コントローラーを持ち、真の隔離を実現
    
- **柔軟なバージョン管理**:
    
    ホストクラスタとは独立した Kubernetes バージョンを各 vCluster で選択可能
    
- **リソース効率**:
    
    物理ノードを共有しながら論理的なクラスタ分離を実現し、ハードウェアコストを削減
    
- **迅速なプロビジョニング**:
    
    Helm チャートによる数十秒でのクラスタ作成・削除
    
- **既存ツールとの互換性**:
    
    kubectl や Helm などの標準的な Kubernetes ツールがそのまま利用可能
    

本稿では、便宜的に vCluster コンポーネントがインストールされた Kubernetes クラスタを「ホストクラスタ」、vCluster が作成した仮想の Kubernetes クラスタを「仮想クラスタ」と呼びます。

## vCluster

vCluster は [Loft Lab](https://www.loft.sh/) 社が開発している OSS であり、Kubernetes クラスタ上に、論理的に独立した Kubernetes クラスタ (仮想クラスタ) を構築するためのソリューションです。

現在は OSS のほかに、有償プランとして Enterprise Plan や vCluster Cloud が提供されています。

有償プランの特徴として、Istio や KubeVirt などの OSS との連携機能、クラウドプロバイダーとの統合などがサポートされます。

表 1: vCluster のメリットとデメリット

| 観点 | メリット | デメリット |
| --- | --- | --- |
| **コスト** | • 物理ノードを共有し、インフラコストを大幅削減• 必要時のみ起動する一時環境でリソース効率を最大化 | • 各 vCluster のコントロールプレーンが CPU・メモリを消費• 小規模ワークロードでは相対的なオーバーヘッドが大きい |
| **運用** | • ホストクラスタに管理を集中し、個別クラスタのメンテナンス不要• 統一されたモニタリング・ロギング基盤で一元管理 | • vCluster 固有の概念とベストプラクティスの学習が必要• トラブルシューティング時にホストと vCluster 両方の理解が必要 |
| **開発・テスト** | • 数十秒で環境を作成・削除し、CI/CD パイプラインに容易に統合• ブランチや PR ごとの独立した検証環境を気軽に構築 | • 初期セットアップと CI/CD への組み込みに設計の工夫が必要 |
| **隔離性** | • 独立した API サーバーと etcd により CRD やクラスタリソースを完全分離• テナント間の障害や不正操作の影響を最小化 | • ホストクラスタの Node レベル機能（DaemonSet、特定の Device Plugin）へのアクセスは制限される |
| **柔軟性** | • ホストとは独立した Kubernetes バージョンを選択可能• チームごとに異なるバージョンでの検証を同一基盤上で実現 | • 一部のクラウドプロバイダー固有機能は追加構成や有償プランが必要 |
| **ネットワーク** | • ホストクラスタのネットワークを活用し、柔軟な通信設計が可能• LoadBalancer、Ingress による外部公開に対応 | • vCluster 間やホスト間の通信設計に注意が必要• ネットワークポリシーの設定が複雑になる場合がある |
| **ストレージ** | • ホストクラスタの StorageClass をそのまま利用可能• PV/PVC の管理をホスト側に委譲 | • vCluster 削除時のデータ保持ポリシーを明確に定義する必要• ストレージクラスの設計がホストクラスタに依存 |

### **アーキテクチャ**

vCluster は仮想コントロールプレーンと同期メカニズムの2つの主要コンポーネントで構成されています。

- 仮想コントロールプレーン
    
    各 vCluster は独自の Kubernetes コントロールプレーンを持ちます。
    
    このコントロールプレーンはホストクラスタの namespace 内に通常の Pod として実行され、以下のコンポーネントを含みます。
    
    - **API Server**:
        
        仮想クラスタへの全ての Kubernetes API リクエストを処理
        
    - **Controller Manager**:
        
        ReplicaSet、Deployment などの Kubernetes リソースを管理
        
    - **データストア**:
        
        デフォルトでは組み込みの SQLite を使用し、高可用性構成では etcd や他のデータストアに切り替え可能
        
    - **Syncer**:
        
        ホストクラスタと仮想クラスタ間でリソースを同期する vCluster 固有のコンポーネント
        

### **テナンシーモデル**

vCluster は、コントロールプレーンとワーカーノードの展開方法に応じて、5つの主要なテナンシーモデルを提供しています。

各モデルは、隔離性、コスト効率、運用の複雑さのトレードオフが異なります。

表 2: テナンシーモデルの比較

| **モデル** | **物理ノードの扱い** | **分離** | **リソース効率** | **ユースケース** |
| --- | --- | --- | --- | --- |
| **Shared Nodes** | **共有** | 低（名前空間レベル） | **最高** | 開発環境、CI/CD、コスト最適化 |
| **Dedicated Nodes** | **専有（論理的）** | 中（ノードセレクターによる分離） | 中 | 性能予測が必要な商用、特定チーム用 |
| **Virtual Nodes** | **仮想化** | 中〜高（ノード境界を仮想化） | 高 | セキュリティと効率の両立、SaaS基盤 |
| **Private Nodes** | **専有（物理的）** | **最高**（ハードウェアから分離） | 低 | 高度なコンプライアンス、機密データ |
| **Standalone** | **不要**（VM/単一コンテナ） | 独立（ホストK8sに依存しない） | 調整可能 | ローカル開発、デモ、エアギャップ環境 |

## 環境構築

ここからは検証

### EKS クラスタの作成

ここからは GitHub リポジトリにあるファイルの使用を前提に解説を行います。

本検証では AWS EKS を使用します。

表 3 に検証で使用する各種コンポーネントを掲載します．

表 3: 検証環境

| **Component** | **Version/Info** |
| --- | --- |
| OS | macOS Tahoe 26.1 arm64 |
| Shell (zsh) | 5.9 |
| aws cli | 2.32.29 |
| Terraform | 1.14.3 |
| Helm | 4.0.4 |
| Helmfile | 1.2.3 |
| Go | 1.25.4 |
| kubectl | Client: v1.35 / Kustomize: v5.7.1 / Server: v1.34.1-eks-3025e55 |
| vCluster CLI | v0.30.4 |
| Grafana | 12.3.0 (kube-prometheus-stack chart 80.2.0 同梱) |
| Loki | 3.6.4 (chart 6.52.0) |
| Tempo | 2.9.0 (chart 1.24.3) |
| Alloy | v1.2.0 (chart 0.5.0) |
| Prometheus | v3.8.0 (kube-prometheus-stack chart 80.2.0 同梱) |
1. [GitHub リポジトリ](https://github.com/cyokozai/vcluster-o11y)をローカルに Clone し、ディレクトリを移動する
2. `terraform` ディレクトリへ移動
3. IAM ユーザまたは IAM ロールの ARN を取得する
    
    ```bash
    aws sts get-caller-identity
    ```
    
4. `terraform.tfvars` ファイルを作成し、取得した ARN を作成する
    
    ```hcl
    eks_access_entry_principal_arn = "arn:aws:iam::hogehoge"
    ```
    
5. Terraform の初期化
    
    ```bash
    # 初回
    terraform init
    
    # 2回目以降
    terraform init -reconfigure
    ```
    
6. `terraform plan` を実行
    
    tfファイルが実行可能かテストを行う
    
    ```bash
    terraform plan -var-file="terraform.tfvars"
    ```
    
7. `terraform apply` を実行
    
    インフラを作成
    
    ```bash
    terraform apply -var-file="terraform.tfvars"
    ```
    
    - 結果
        
        ```bash
        Apply complete! Resources: 58 added, 0 changed, 0 destroyed.
        
        Outputs:
        
        cluster_endpoint = "https://0000.xxx.ap-northeast-1.eks.amazonaws.com"
        cluster_name = "demo-eks-vcluster"
        ```
        
8. リージョンとクラスタ名を変数に保存
    
    ```bash
    export REGION="ap-northeast-1" &&\
    export CLUSTER_NAME="demo-eks-vcluster" &&\
    echo "$REGION\n$CLUSTER_NAME"
    ```
    
9. クレデンシャルを取得
    
    ```bash
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
    ```
    
    - クラスタに接続できることを確認
        
        ```bash
        kubectl cluster-info
        ```
        
10. EBS CSI Driverが起動していることを確認
    
    ```bash
    kubectl get pods -n kube-system | grep ebs
    ```
    
    - 結果
        
        ```bash
        ebs-csi-controller-f7cf9bc5f-xsmnd   6/6     Running   0          15h
        ebs-csi-controller-f7cf9bc5f-zszbd   6/6     Running   0          15h
        ebs-csi-node-44g8v                   3/3     Running   0          15h
        ebs-csi-node-bcrm4                   3/3     Running   0          15h
        ```
        
11. `gp3` StorageClassを作成
    
    ```bash
    cd ..
    kubectl apply -f manifests/storageclass/gp3-storageclass.yaml
    ```
    

### helmfile を用いてコンポーネントをインストール

helmfileではホストクラスタと仮想クラスタに別々のコンポーネントをインストールします。

各コンポーネントに関しては以下のリンクからアクセス可能です。

- vCluster
    - [GitHub](https://github.com/loft-sh/vcluster)
    - [Artifact Hub](https://artifacthub.io/packages/helm/loft/vcluster)
- kube-prometheus-stack
    - [GitHub](http://github.com/prometheus-operator/kube-prometheus)
    - [Artifact Hub](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
- Grafana Alloy
    - [GitHub](https://github.com/grafana/alloy)
    - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/alloy)
- Grafana Loki
    - [GitHub](https://github.com/grafana/loki)
    - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/loki)
- Grafana Tempo
    - [GitHub](https://github.com/grafana/tempo)
    - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/tempo)

まずは、ホストクラスタに必要なコンポーネントを Helm 経由でインストールします。

1. **ホストクラスタへの基盤コンポーネントのデプロイ**
    
    ホストクラスタに、監視スタックおよびマルチテナント環境に必要なコンポーネントを Helm 経由でインストールします。
    
    主に 表 4 の監視関連コンポーネントおよび vCluster をデプロイします。
    
    表 4: ホストクラスタにインストールするコンポーネント
    
    | コンポーネント | Chart | バージョン | Namespace |
    | --- | --- | --- | --- |
    | **Alloy** | grafana/alloy | 0.5.0 | monitoring |
    | **Tempo** | grafana/tempo | 1.24.3 | monitoring |
    | **Loki** | grafana/loki | 6.52.0 | monitoring |
    | **kube-prometheus-stack** | prometheus-community/kube-prometheus-stack | 80.2.0 | monitoring |
    | **vCluster** | loft/vcluster | 0.30.4 | vcluster-system |
    1. Helm リポジトリを登録
        
        ```bash
        helmfile repos -f helm/helmfile.yaml
        helm repo update
        ```
        
    2. 監視スタックをデプロイ
        
        ```bash
        helmfile sync -f helm/helmfile.yaml
        ```
        
    3. Grafana にアラートルールを適用
        
        `grafana.sidecar.alerts` が ConfigMap を検知し、Grafana に自動ロードされる
        
        ```bash
        kubectl apply -f manifests/monitoring/grafana-alert-rules.yaml
        ```
        
2. 仮想クラスタの構築とデモアプリのデプロイ
    
    ここからは、vCluster を使用して仮想クラスタを構築し、デモアプリのデプロイを行なっていきます。
    
    今回デモに使用するのは、OpenTelemetry が提供している OpenTelemetry Demo です。
    
    表 5 に本検証で使用するバージョンなどを掲載します。
    
    表 5: 仮想クラスタにインストールするコンポーネント
    
    | コンポーネント | Chart | バージョン | Namespace |
    | --- | --- | --- | --- |
    | **OpenTelemetry Demo** | open-telemetry/opentelemetry-demo | 0.40.1 (app: 2.2.0) | otel-demo |
    
    **仮想クラスタの要点:**
    
    - Demo に同梱の Jaeger, Prometheus, Grafana, OpenSearch は無効化し、ホストクラスタ側のコンポーネント (Alloy, Tempo, Loki, kube-prometheus-stack) を使用
    - Demo 内の OTel Collector は `otelcol-to-alloy:4317` を経由してホスト側の Alloy へテレメトリを転送
    
    1. 仮想クラスタ `otel-demo` を作成
    
    クラスタ作成後、kubectl のコンテキストが自動で仮想クラスタに切り替わる
    
    ```bash
    vcluster create otel-demo \
      --namespace vcluster-otel-demo \
      --upgrade \
      --values manifests/vcluster/config.yaml
    ```
    
    1. 作成した仮想クラスタの確認
        
        ```bash
        vcluster list
        ```
        
        - 結果
            
            ```bash
                  NAME    |     NAMESPACE      | STATUS  | VERSION | CONNECTED | AGE   
              ------------+--------------------+---------+---------+-----------+-------
                otel-demo | vcluster-otel-demo | Running | 0.32.0  | True      | 2m2s  
                vcluster  | vcluster-system    | Running | 0.30.4  |           | 29m   
              
            20:33:42 info Run `vcluster disconnect` to switch back to the parent context
            ```
            
    2. 仮想クラスタのコンテキストを確認
        
        ```bash
        kubectl config current-context
        ```
        
        - 結果
            
            ```bash
            vcluster_otel-demo_vcluster-otel-demo_arn:aws:eks:ap-northeast-1:xxxxxxxxxxxx:cluster/demo-eks-vcluster
            ```
            
    3. Helm リポジトリを登録
        
        ```bash
        helmfile repos -f helm/demo-otel.yaml
        helm repo update
        ```
        
    4. デモアプリ (OpenTelemetry Demo) を仮想クラスタにデプロイ
        
        ```bash
        helmfile sync -f helm/demo-otel.yaml
        ```
        
    5. 仮想クラスタへの接続/切断
        
        ```bash
        # 接続
        vcluster connect otel-demo
        
        # 切断
        vcluster disconnect
        ```
        

以降の検証では、仮想クラスタに接続して作業することはほとんどないので、切断しておくことを推奨します。

## 検証

**ここに書く**

表 6: 

| コンポーネント | 役割 |
| --- | --- |
| **Alloy** | OTLP Receiver (メトリクス・トレース・ログ受信) → Tempo (トレース) / Prometheus Remote Write (メトリクス) / Loki (ログ) へ転送 |
| **Tempo** | Trace データの保存・検索 |
| **Loki** | ログデータの保存・検索 |
| **Prometheus (kube-prometheus-stack)** | メトリクス監視 (エラーレート可視化) |
| **Grafana (kube-prometheus-stack)** | Tempo / Loki の DataSource 追加済み |
1. Grafana とデモアプリ のWeb UI に Port forward 経由でブラウザから接続する
    - Grafana | [http://localhost:3000](http://localhost:3000/)
        
        ```bash
        kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
        ```
        
        - ログイン情報: ユーザー名 `admin`、パスワードは Secret から取得
            
            ```bash
            export PASSWORD=$(kubectl get secret kube-prometheus-stack-grafana -n monitoring \
              -o jsonpath="{.data.admin-password}" | base64 --decode)
            echo $PASSWORD | pbcopy
            ```
            
    - OpenTelemetry Demo | http://localhost:8080/feature
        
        ```bash
        kubectl port-forward svc/frontend-proxy-x-otel-demo-x-otel-demo 8080:8080 -n vcluster-otel-demo
        ```
        
- Infrastructure Overview
    
    ![image.png](attachment:94812712-e7b2-432d-9ade-b3798903143c:image.png)
    
- Service Overview
    
    ![image.png](attachment:79a613c8-9bda-444b-b79e-0bbf8c824d34:image.png)
    
- Flagd Configuratior
    
    ![image.png](attachment:135724af-58d6-4871-bcc1-d16a0b775447:image.png)
    
- 1
    
    ![image.png](attachment:e32f7242-e5a4-470c-8684-2a82d483a365:image.png)
    
1. 10%
    
    ![image.png](attachment:5a509310-e7b9-4503-9e70-a6e905df84c8:image.png)
    
    ![image.png](attachment:6270d15c-2aac-457c-8583-17621f9cc397:image.png)
    
    ![image.png](attachment:a2598d4a-05ec-40da-b9e9-682ed6951f0f:image.png)
    
2. 50%
    
    ![image.png](attachment:e9d1c950-a7a7-4322-bc77-adcbed8fb355:image.png)
    
    ![image.png](attachment:c2401eac-7d43-4887-b72f-8b79b96f248b:image.png)
    
    ![image.png](attachment:fd59460b-f75c-4ba8-9d53-34245495bc1c:image.png)
    
    ![image.png](attachment:f4f9dd69-d49a-4e3c-971b-0d819ecf9c53:image.png)
    
3. 100%
    
    ![image.png](attachment:d39cf2ac-115c-49d4-a9f8-8b9f688fa6f4:image.png)
    
    ![image.png](attachment:a4cd6b7c-bf92-49dc-9567-89954d88d838:image.png)
    
- 3
    
    ![image.png](attachment:44e73e7e-3b3d-471f-ba42-4f1ddc9b695f:image.png)
    
    ![image.png](attachment:0a7c18bc-f3d5-445d-aabb-3a9a0f6562c7:image.png)
    
    ![image.png](attachment:f0789060-315a-4e0c-9c1a-c9373fb42f8b:image.png)
    
- 4
    
    ![image.png](attachment:a60c3701-bbbc-4817-a027-092ac587dd46:image.png)
    
    ![image.png](attachment:dddb844e-1790-4b39-98a6-3e0aaed4dd2d:image.png)
    
- 5
- 
- P50 / P95 / P99 （パーセンタイル）
    
    全リクエストを処理時間の短い順に並べたとき、何番目までのリクエストを何ms以内に処理できているか
    
    - 100件のリクエストがあったとして
        
        
        | 指標 | 意味 | 例 |
        | --- | --- | --- |
        | **P50**（中央値） | 100件中 50番目に遅いリクエストの処理時間 | 「半分のリクエストは 10ms 以内」 |
        | **P95** | 100件中 95番目に遅いリクエストの処理時間 | 「95% のリクエストは 100ms 以内」 |
        | **P99** | 100件中 99番目に遅いリクエストの処理時間 | 「99% のリクエストは 500ms 以内」 |
    - オブザーバビリティではP95 / P99を重視する
        
        
        | P50（平均的体験） | P99（最悪の体験） |
        | --- | --- |
        | ほとんどのユーザーは快適 | 一部のユーザーが極端に遅いと感じる |
        | 問題を見逃しやすい | スパイク・バグを発見しやすい |