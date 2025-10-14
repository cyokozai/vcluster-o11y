# helmfile

- ARN を変数に保存

  ```shell
  export DEV_KUBE_CONTEXT=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query "cluster.arn" --output text)
  echo $DEV_KUBE_CONTEXT
  ```

- Set 

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
