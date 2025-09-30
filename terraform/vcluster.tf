resource "helm_release" "vcluster" {
  name       = "vcluster"
  repository = "https://charts.loft.sh"
  chart      = "vcluster"
  namespace  = kubernetes_namespace.vcluster_system.metadata[0].name
  create_namespace = false

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

  depends_on = [
    kubernetes_config_map.vcluster_config,
    kubernetes_persistent_volume_claim.vcluster_pvc
  ]
}
