resource "helm_release" "vcluster" {
  name             = var.cluster_name
  namespace        = var.vcluster_namespace
  create_namespace = true

  repository = "https://charts.loft.sh"
  chart      = "vcluster"
  version    = var.vcluster_chart_version
  
  values = [
    file("${path.module}/${var.vcluster_values_file}")
  ]
  
  depends_on = [module.eks]
}
