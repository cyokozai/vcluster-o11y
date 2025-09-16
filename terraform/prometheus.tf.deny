resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.5.0" # 安定版を指定
  namespace        = "monitoring"
  create_namespace = true

  # 必要に応じて values をカスタマイズ
  values = [
    <<-EOT
    grafana:
      enabled: false # GrafanaはAlloyと組み合わせるのでここでは無効化
    prometheus:
      service:
        type: LoadBalancer
      prometheusSpec:
        retention: 7d
        scrapeInterval: 30s
    alertmanager:
      enabled: true
      service:
        type: ClusterIP
    EOT
  ]
}
