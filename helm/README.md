# helmfile

## Resources

- [vCluster](https://artifacthub.io/packages/helm/loft/vcluster)
- [kube prometheus stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)
- [Grafana/alloy](https://artifacthub.io/packages/helm/grafana/alloy)
- [Grafana/tempo](https://artifacthub.io/packages/helm/grafana/tempo)
- [OpenTelemetry/demo](https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-demo)

## Usage

- Set repositories

  ```bash
  helmfile repos -f helm/helmfile.yaml
  ```

- Update the repositories

  ```bash
  helm repo update
  ```

- Sync up custom resources

  ```bash
  helmfile sync -f helm/helmfile.yaml
  ```

- Apply custom resources

  ```bash
  helmfile apply -f helm/helmfile.yaml
  ```

- Confirm the softwares
  - Prometheus

    ```bash
    kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
    ```

    - http://localhost:9090/
  - Grafana
    - Grafana Dashbord
  
      ```bash
      kubectl port-forward svc/kube-prometheus-stack-grafana  -n monitoring 3000:80
      ```

    - http://localhost:3000/
  - vCluster

    ```bash
    vcluster list
    ```
