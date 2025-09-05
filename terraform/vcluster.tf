resource "helm_release" "vcluster" {
  name       = "vcluster"
  repository = "https://charts.loft.sh"
  chart      = "vcluster"
  namespace  = "vcluster-system"
  create_namespace = true

  values = [
    <<-EOT
    syncer:
      extraArgs:
        - --fake-kubelet-ip=10.0.0.1
    EOT
  ]
}

# vCluster 上に nginx をデモアプリとして配置
resource "kubernetes_namespace" "demo" {
  metadata {
    name = "demo"
  }
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
}
