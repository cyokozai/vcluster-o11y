output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

# vcluster outputs
output "vcluster_release_name" {
  value = helm_release.vcluster.name
  description = "Name of the vcluster Helm release"
}

output "vcluster_namespace" {
  value = helm_release.vcluster.namespace
  description = "Namespace where vcluster is installed"
}

output "vcluster_status" {
  value = helm_release.vcluster.status
  description = "Status of the vcluster Helm release"
}

output "vcluster_version" {
  value = helm_release.vcluster.version
  description = "Version of the installed vcluster"
}

# output "nginx_service_url" {
#   value = kubernetes_service.nginx.status[0].load_balancer[0].ingress[0].hostname
# }
