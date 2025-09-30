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

  depends_on = [
    module.eks
  ]
}

resource "kubernetes_config_map" "vcluster_config" {
  metadata {
    name      = "vcluster-config"
    namespace = kubernetes_namespace.vcluster_system.metadata[0].name
  }

  data = {
    "vcluster.yaml" = <<EOT
sync:
  fromHost:
    ingressClasses:
      enabled: true
  toHost:
    ingresses:
      enabled: true
EOT
  }

  depends_on = [
    kubernetes_namespace.vcluster_system,
    module.eks
  ]
}

resource "kubernetes_persistent_volume_claim" "vcluster_pvc" {
  metadata {
    name      = "vcluster-pvc"
    namespace = kubernetes_namespace.vcluster_system.metadata[0].name
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

  timeouts {
    create = "10m"
  }

  depends_on = [
    kubernetes_namespace.vcluster_system,
    module.eks
  ]
}
