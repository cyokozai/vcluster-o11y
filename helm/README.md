# helmfile

## Resources

- Deployment
  - vCluster
    - [GitHub](https://github.com/loft-sh/vcluster)
    - [Artifact Hub](https://artifacthub.io/packages/helm/loft/vcluster)
  - kube prometheus stack
    - [GitHub](http://github.com/prometheus-operator/kube-prometheus)
    - [Artifact Hub](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
  - Grafana/Alloy
    - [GitHub](https://github.com/grafana/alloy)
    - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/alloy)
  - Grafana/Loki
    - [GitHub](https://github.com/grafana/loki)
    - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/loki)
  - Grafana/Tempo
    - [GtiHub](https://github.com/grafana/tempo)
    - [Artifact Hub](https://artifacthub.io/packages/helm/grafana/tempo)
  - Cilium
    - [GitHub](https://github.com/cilium/cilium)
    - [Artifact Hub](https://artifacthub.io/packages/helm/cilium/cilium)
- Demo application
  - Google Microservices Demo
    - [GiHub](https://github.com/GoogleCloudPlatform/microservices-demo)
    - [Google Cloud Docs](https://docs.cloud.google.com/service-mesh/docs/onlineboutique-install-kpt?hl=ja)

## Install

- move `helm` directory

  ```bash
  cd helm
  ```

- Set repositories

  ```bash
  helmfile repos -f helmfile.yaml
  helmfile repos -f demo-otel.yaml
  ```

- Update the repositories

  ```bash
  helm repo update
  ```

- Sync up custom resources to the host cluster

  ```bash
  helmfile sync -f helmfile.yaml
  ```

- Apply custom resources to the host cluster

  ```bash
  helmfile apply -f helmfile.yaml
  ```

## Usage

- Prometheus
  - http://localhost:9090/

    ```bash
    kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
    ```

- Grafana
  - http://localhost:3000/

    ```bash
    kubectl port-forward svc/kube-prometheus-stack-grafana  -n monitoring 3000:80
    ```

- vCluster

  ```bash
  vcluster list
  ```

## Uninstall

- Clean up

  ```bash
  helmfile destroy
  ```
