# PromQL Queries

## Host Resource

### CPU

- Requests

  ```PromQL
  100 - (
    sum(irate(container_cpu_usage_seconds_total{image!="", pod!=""}[5m])) by (namespace, pod) /
    sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace, pod)
  )
  ```

- Limits

  ```PromQL
  100 - (
    sum(irate(container_cpu_usage_seconds_total{image!="", pod!=""}[5m])) by (namespace, pod) /
    sum(kube_pod_container_resource_limits{resource="cpu"}) by (namespace, pod)
  )
  ```

- CPU 

  <!-- ```PromQL -->
  

### Memory

- Requests

  ```PromQL
  100 - (
    sum(container_memory_working_set_bytes{image!="", pod!=""}) by (namespace, pod) /
    sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace, pod)
  )
  ```

- Limits

  ```PromQL
  100 - (
    sum(container_memory_working_set_bytes{image!="", pod!=""}) by (namespace, pod) /
    sum(kube_pod_container_resource_limits{resource="memory"}) by (namespace, pod)
  )
  ```

### IO

- Disc Read

  ```PromQL
  node_disk_read_bytes_total
  ```

- Disc Write

  ```PromQL
  node_disk_written_bytes_total
  ```

### Network

- Receive

  ```PromQL
  node_network_receive_bytes_total
  ```

### etcd

- etcdが使用するVolume (PV/PVC) の空き容量 (バイト)

  ```PromQL
  kubelet_volume_stats_available_bytes{persistentvolumeclaim="<etcdのPVC名>"}
  ```

- etcdが使用するVolumeの総容量 (バイト)

  ```PromQL
  kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="<etcdのPVC名>"}
  ```

## Application

### NGINX

- https://numasai2025.nekko-lab.dev/

  ```PromQL
  sum(nginx_http_requests_total{job="kubernetes-pods", app="fire", namespace="numasai2025"})
  ```

- https://numasai2025.nekko-lab.dev/dj-live/

  ```PromQL
  sum(nginx_http_requests_total{job="kubernetes-pods", app="cyberrootmusic", namespace="numasai2025"})
  ```

- 合計RPS

  ```PromQL
  sum(nginx_http_requests_total{job="kubernetes-pods", namespace="numasai2025"})
  ```

### 1\. 📊 クラスタ全体の健全性

クラスタ全体のリソース容量と、全体的なPodやNodeの状態を把握します。

- 項目: ノードの総数（Ready状態）

  ```bash
  sum(kube_node_status_condition{condition="Ready", status="true"})
  ```

- 項目: クラスタの総CPUコア数
  - クエリ: `sum(kube_node_status_capacity{resource="cpu"})`
- 項目: クラスタの総メモリ量
  - クエリ: `sum(kube_node_status_capacity{resource="memory"})`
- 項目: Podのステータス別（Running, Pending, Failedなど）の総数
  - クエリ: `count by (phase) (kube_pod_status_phase)`

-----

### 2\. 💻 ノード（ホスト）のリソース監視

各Node（EC2インスタンスなど）のCPU、メモリ、ディスク使用状況を監視します。

- 項目: ノードごとのCPU使用率 (%)

  ```promql
  (1 - sum(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) / sum(rate(node_cpu_seconds_total[5m])) by (instance) - 100
  ```

- 項目: ノードごとのメモリ使用率 (%)

  ```promql
  (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) - 100
  ```

- 項目: ノードごとのディスク使用率 (%) (ルートファイルシステム)
  
  ```promql
  (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) - 100
  ```

-----

### 3\. 📦 Pod（ワークロード）のリソース監視

最も重要な、Pod（コンテナ）単位でのリソース消費を監視します。

  - 項目: NamespaceごとのCPU使用量 (コア数)
      - クエリ:
        ```promql
        sum(rate(container_cpu_usage_seconds_total{container!="", pod!=""}[5m])) by (namespace)
        ```
  - 項目: Namespaceごとのメモリ使用量 (Bytes)
      - クエリ:
        ```promql
        sum(container_memory_working_set_bytes{container!="", pod!=""}) by (namespace)
        ```
  - 項目: PodごとのCPU使用量 (コア数)
      - クエリ:
        ```promql
        sum(rate(container_cpu_usage_seconds_total{container!="", pod!=""}[5m])) by (namespace, pod)
        ```
  - 項目: Podごとのメモリ使用量 (Bytes)
      - クエリ:
        ```promql
        sum(container_memory_working_set_bytes{container!="", pod!=""}) by (namespace, pod)
        ```
  - 項目: コンテナの再起動回数（直近1時間）
      - クエリ:
        ```promql
        sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod, container)
        ```

-----

### 4\. ⚙️ Kubernetesオブジェクトの状態

DeploymentやStatefulSetが意図した通りに動作しているかを監視します。

- 項目: Deploymentの希望レプリカ数と利用可能レプリカ数の比較
  - 希望数: `kube_deployment_spec_replicas`
  - 利用可能数: `kube_deployment_status_replicas_available`
  - （例: 利用可能数が希望数に満たないDeploymentを表示）

    ```promql
    kube_deployment_spec_replicas - kube_deployment_status_replicas_available > 0
    ```

- 項目: StatefulSetの希望レプリカ数とReadyレプリカ数
  - 希望数: `kube_statefulset_spec_replicas`
  - Ready数: `kube_statefulset_status_replicas_ready`

-----

### 5\. 💽 ストレージ（PVC）の状態

PersistentVolumeClaim（PVC）が正しくBound（割り当て済み）されているか、容量は十分か監視します。

- 項目: PVCのステータス別（Bound, Pendingなど）の総数
  - クエリ: `count by (phase) (kube_persistentvolumeclaim_status_phase)`
- 項目: PVCごとの要求容量 (Bytes)
  - クエリ: `kube_persistentvolumeclaim_resource_requests_storage_bytes`

### vClusterへの適用

これらのクエリは、ホストクラスタのメトリクスを対象としています。vClusterの監視を行う場合（以前の会話で設定したServiceMonitorやFederation）、これらのクエリに `namespace` や `vcluster` といったラベルを追加して絞り込む（フィルタリングする）ことで、特定のvClusterのダッシュボードを作成できます。

- 例：`vcluster-foo` というvCluster内のPodのCPU使用量

  ```promql
  sum(rate(container_cpu_usage_seconds_total{container!="", pod!="", vcluster="vcluster-foo"}[5m])) by (namespace, pod)
  ```
