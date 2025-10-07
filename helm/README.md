# helmfile

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
