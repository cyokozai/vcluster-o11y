
resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
  }
  depends_on = [
    aws_eks_access_policy_association.admin_policy_association
  ]
}

resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
    labels = {
      app = "nginx"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }
      spec {
        container {
          name  = "nginx"
          image = "nginx:latest"
          port {
            container_port = 80
          }
        }
      }
    }
  }
  depends_on = [
    aws_eks_access_policy_association.admin_policy_association
  ]
}

resource "kubernetes_service" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.demo.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx"
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
  depends_on = [
    aws_eks_access_policy_association.admin_policy_association
  ]
}
