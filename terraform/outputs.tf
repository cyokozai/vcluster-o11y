output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "nginx_service_url" {
  value = kubernetes_service.nginx.status[0].load_balancer[0].ingress[0].hostname
}
