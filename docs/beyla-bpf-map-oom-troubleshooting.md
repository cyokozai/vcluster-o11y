# Beyla BPF マップ確保失敗（cannot allocate memory）トラブルシューティング

## 発生した事象

`monitoring` namespace に DaemonSet としてデプロイされた Beyla の一方の pod が起動直後にクラッシュした。

### エラーログ

```
time=2026-03-26T12:00:07.460Z level=WARN msg="couldn't load tracer" component=ebpf.ProcessTracer
  error="loading and assigning BPF objects: field ObiProtocolHttp2GrpcFrames:
  program obi_protocol_http2_grpc_frames: map ongoing_http2_grpc:
  map create: cannot allocate memory" required=true

time=2026-03-26T12:00:07.460Z level=ERROR msg="couldn't trace process. Stopping process tracer"
  component=discover.traceAttacher
  error="loading and assigning BPF objects: field ObiProtocolHttp2GrpcFrames:
  program obi_protocol_http2_grpc_frames: map ongoing_http2_grpc: map create: cannot allocate memory"
```

`ongoing_http2_grpc` BPF マップの作成時に `ENOMEM` が発生し、HTTP/2 gRPC トレーサーのロードに失敗した。

## 環境情報

- Beyla: v3.1.2
- デプロイ形式: DaemonSet（`monitoring` namespace）
- `securityContext`: `privileged: true`, `runAsUser: 0`
- ノード: EKS Worker Node（`i-0b3392cde96900ec5`）

## 原因分析

### エラーの構造

```text
field ObiProtocolHttp2GrpcFrames          ← eBPF プログラムフィールド名
  program obi_protocol_http2_grpc_frames  ← HTTP/2 gRPC トレース用 eBPF プログラム
    map ongoing_http2_grpc                ← インフライト HTTP/2 リクエストを追跡する BPF ハッシュマップ
      map create: cannot allocate memory  ← カーネルの ENOMEM
```

`ongoing_http2_grpc` は HTTP/2 のインフライトリクエストを追跡するための BPF ハッシュマップ。`RLIMIT_MEMLOCK`（locked memory 上限）ではなく、**カーネルの汎用メモリ（kmalloc/vmalloc）の確保失敗**が原因。`privileged: true` で `RLIMIT_MEMLOCK` は無制限になるが、カーネルの物理メモリ自体の不足は別問題。

### 実際の原因：ノード上の BPF リソース競合

DaemonSet の pod が再起動した際、**旧 pod の BPF マップがカーネルから完全に解放される前に新 pod が起動**し、同一ノード上で BPF マップが二重確保されようとしたことで `ENOMEM` が発生した可能性が高い。

| 時刻 | イベント |
|---|---|
| 12:00:05 | 旧 pod 起動 → `ongoing_http2_grpc` BPF マップ確保に失敗 |
| 12:00:07 | `Stopping process tracer` → crash |
| 12:00:44 | 再起動後の pod（beyla-7kwwq）が起動 → 成功 |

再起動時にはノード上の BPF リソースが解放されており、マップ確保が成功した。

### 補足：generic Tracer へのフォールバック

復帰後の pod では `/server`（Go API Server）が "Unsupported Go program" として検出され、`generic.Tracer` にフォールバックしている。generic tracer は `ObiProtocolHttp2GrpcFrames` BPF プログラムを必要としないため、今後は同じ問題が発生しにくい。

```
time=2026-03-26T12:00:48.198Z level=WARN msg="Unsupported Go program detected, using generic instrumentation"
time=2026-03-26T12:00:50.066Z level=INFO msg="Launching p.Tracer" component=generic.Tracer
```

## 対処方法

### 恒久対応：BPF マップの resource quota を増やす

ノードの BPF マップ上限（`/proc/sys/net/core/bpf_jit_limit` や `kernel.bpf_stats_enabled`）を調整する。EKS では Worker Node の起動設定（Launch Template の user-data）で以下を追加する。

```bash
# BPF JIT メモリ上限を拡張（デフォルト: 264MB 程度）
sysctl -w net.core.bpf_jit_limit=1073741824  # 1GB
```

または Beyla DaemonSet の `initContainers` で対応する方法もある。

```yaml
initContainers:
  - name: set-bpf-limit
    image: busybox
    command: ["sysctl", "-w", "net.core.bpf_jit_limit=1073741824"]
    securityContext:
      privileged: true
```

### 確認コマンド

```bash
# Beyla pod が動いているノードを確認
kubectl get pods -n monitoring -l app.kubernetes.io/name=beyla -o wide

# ノード上の BPF マップ数を確認（デバッグ pod 経由）
kubectl debug node/<node-name> -it --image=ubuntu -- bash -c "bpftool map list | wc -l"

# BPF JIT 現在の上限を確認
kubectl debug node/<node-name> -it --image=ubuntu -- bash -c "cat /proc/sys/net/core/bpf_jit_limit"
```

### 一時対応：pod を手動で再起動

BPF リソースが解放されれば自動的に復帰する。急ぎの場合は pod を削除して DaemonSet に再作成させる。

```bash
kubectl delete pod -n monitoring <beyla-pod-name>
```

## 付随して確認された警告

以下の警告は動作に影響しないが、記録として残す。

| 警告 | 意味 | 影響 |
|---|---|---|
| `bpffs not mounted` | `/sys/fs/bpf` が存在しない | log enricher・profile correlation が無効 |
| `can't fetch Kubernetes Cluster Name` | `k8s.cluster.name` 属性なし | Network metrics にクラスタ名が付かない |
| `discovery > services is deprecated` | 設定キー名が旧仕様 | 次期バージョンで削除予定 |

`bpffs` については EKS の AMI 設定に依存するため、必要であれば DaemonSet の `initContainer` で `mount -t bpf bpf /sys/fs/bpf` を実行する対応が必要。
