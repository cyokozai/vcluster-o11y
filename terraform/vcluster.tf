resource "kubernetes_namespace" "vcluster" {
  metadata {
    name = var.vcluster_namespace
  }
}

resource "helm_release" "vcluster" {
  name             = var.cluster_name
  namespace        = kubernetes_namespace.vcluster.metadata[0].name
  create_namespace = true

  repository = "https://charts.loft.sh"
  chart      = "vcluster"
  version    = var.vcluster_chart_version
  
  values = [
    file("${path.module}/${var.vcluster_values_file}")
  ]

  timeout = 600
  
  depends_on = [module.eks, kubernetes_namespace.vcluster]
}
