# helmfile

- Set ARN

  ```shell
  export DEV_KUBE_CONTEXT=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query "cluster.arn" --output text)
  echo $DEV_KUBE_CONTEXT
  ```

- Set repositories

  ```shell
  helmfile repos -f helm/helmfile.yaml
  ```

- Update the repositories

  ```shell
  helm repo update
  ```

- Install custom resource

  ```shell
  helmfile apply -f helm/helmfile.yaml
  ```

- Confirm the softwares
  - Prometheus
    - Run the following command

      ```shell
      kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
      ```

    - http://localhost:9090/
  - Grafana
    - Run the following command

      ```shell
      kubectl port-forward svc/kube-prometheus-stack-grafana  -n monitoring 3000:80
      ```

    - http://localhost:3000/
  - vCluster
    - Run the following command

      ```shell
      vcluster list
      ```
