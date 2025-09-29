# resource "kubernetes_deployment" "nginx" {
#   metadata {
#     name      = "nginx"
#     namespace = kubernetes_namespace.demo.metadata[0].name
#     labels = {
#       app = "nginx"
#     }
#   }

#   spec {
#     replicas = 1
#     selector {
#       match_labels = {
#         app = "nginx"
#       }
#     }
#     template {
#       metadata {
#         labels = {
#           app = "nginx"
#         }
#       }

#       spec {
#         container {
#           name  = "nginx"
#           image = "nginx:latest"
          
#           port {
#             container_port = 80
#           }

#           volume_mount {
#             name       = "nginx-storage"
#             mount_path = "/usr/share/nginx/html"
#           }
#         }

#         volume {
#           name = "nginx-storage"
#           persistent_volume_claim {
#             claim_name = kubernetes_persistent_volume_claim.nginx.metadata[0].name
#           }
#         }
#       }
#     }
#   }

#   depends_on = [
#     aws_eks_access_policy_association.admin_policy_association,
#     kubernetes_persistent_volume_claim.nginx
#   ]
# }


# resource "kubernetes_service" "nginx" {
#   metadata {
#     name      = "nginx"
#     namespace = kubernetes_namespace.demo.metadata[0].name
#   }

#   spec {
#     selector = {
#       app = "nginx"
#     }
#     port {
#       port        = 80
#       target_port = 80
#     }
#     type = "LoadBalancer"
#   }
#   depends_on = [
#     aws_eks_access_policy_association.admin_policy_association
#   ]
# }

resource "kubernetes_namespace" "vcluster" {
  metadata {
    name = var.vcluster_namespace
  }
  depends_on = [
    module.eks
  ]
}

resource "kubernetes_namespace" "vcluster_system" {
  metadata {
    name = "vcluster-system"
  }
}

resource "kubernetes_persistent_volume_claim" "vcluster_pvc" {
  metadata {
    name      = "vcluster-pvc"
    namespace = var.vcluster_namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "5Gi"
      }
    }

    storage_class_name = "gp2"
  }

  depends_on = [
    kubernetes_namespace.vcluster
  ]
}
