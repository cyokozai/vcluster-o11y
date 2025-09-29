resource "kubernetes_config_map" "vcluster_config" {
  metadata {
    name      = "vcluster-config"
    namespace = "vcluster-system"
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
}

resource "helm_release" "vcluster" {
  name       = "vcluster"
  repository = "https://charts.loft.sh"
  chart      = "vcluster"
  namespace  = "vcluster-system"
  create_namespace = true

  values = [<<EOF
persistence:
  enabled: true
  size: 5Gi
  storageClass: gp2

extraVolumeMounts:
  - name: vcluster-config
    mountPath: /data/config
extraVolumes:
  - name: vcluster-config
    configMap:
      name: vcluster-config
EOF
  ]

  set {
    name  = "extraArgs[0]"
    value = "--config=/data/config/vcluster.yaml"
  }
}
