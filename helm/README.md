# helmfile による監視スタックのデプロイ

`helmfile.yaml` 1 ファイルでホストクラスタの全コンポーネントを宣言的に管理します．

## デプロイするコンポーネント

| コンポーネント | Chart | バージョン | Namespace | 役割 |
| --- | --- | --- | --- | --- |
| **Alloy** | grafana/alloy | 1.8.2 | monitoring | OTLP 受信・Tempo / Prometheus / Loki への振り分け |
| **Tempo** | grafana/tempo | 1.24.4 | monitoring | Traces 保存・SpanMetrics 生成 |
| **Loki** | grafana/loki | 6.55.0 | monitoring | Logs 保存・TraceID 相関 |
| **kube-prometheus-stack** | prometheus-community/kube-prometheus-stack | 86.2.0 | monitoring | Metrics 保存・アラート評価・Grafana |
| **vCluster** | loft/vcluster | 0.34.2 | vcluster-system | 仮想クラスタの構築と管理 |
| **Beyla** | grafana/beyla | 1.16.8 | beyla-system | eBPF 計装 DaemonSet |

## デプロイ手順

```bash
# Helm リポジトリを登録・更新
helmfile repos -f helm/helmfile.yaml
helm repo update

# 全コンポーネントをデプロイ (5〜10 分)
helmfile sync -f helm/helmfile.yaml

# Pod 起動確認
kubectl get pods -n monitoring
kubectl get pods -n beyla-system

# Grafana アラートルールとダッシュボードを適用
kubectl apply -f manifests/monitoring/grafana-alert-rules.yaml
kubectl apply -f manifests/monitoring/grafana-dashboards.yaml
```

## アクセス方法

```bash
# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# → http://localhost:3000  (admin / Secret から取得)

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# → http://localhost:9090

# Tempo
kubectl port-forward svc/tempo 3200:3200 -n monitoring

# Loki
kubectl port-forward svc/loki 3100:3100 -n monitoring
```

```bash
# Grafana 管理者パスワードの取得
kubectl get secret kube-prometheus-stack-grafana -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```

## 削除

```bash
helmfile destroy -f helm/helmfile.yaml
```

## 主要な設定ポイント

- **Tempo Metrics Generator**: SpanMetrics と ServiceGraph を有効化し，`http.response.status_code` 等を追加ディメンションとして Prometheus へ remote_write
- **Alloy ServiceMonitor**: `additionalLabels.release: kube-prometheus-stack` を付与することで Alloy 自身の `otelcol_*` メトリクスが Prometheus に自動スクレイプされる
- **Beyla Pod selector**: `k8s_pod_labels: {app: go-api-server, pattern: c}` で Pattern C の Pod のみを計装対象とする (OBI 3.20+ では `namespace` フィールドは Pod selector として機能しない)
- **Loki**: OSS 最終版 6.55.0 を使用 (7.0 以降は GEL 専用化のため)

## リンク

- [Grafana Alloy](https://artifacthub.io/packages/helm/grafana/alloy)
- [Grafana Tempo](https://artifacthub.io/packages/helm/grafana/tempo)
- [Grafana Loki](https://artifacthub.io/packages/helm/grafana/loki)
- [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
- [vCluster](https://artifacthub.io/packages/helm/loft/vcluster)
- [Grafana Beyla](https://artifacthub.io/packages/helm/grafana/beyla)
