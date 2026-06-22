# 検証シナリオ・測定項目設計書

本ドキュメントは vCluster × Grafana Alloy × Beyla によるマルチテナント Kubernetes オブザーバビリティ基盤の検証における、シナリオ・測定項目・合格基準を事前に定義するものです。

## 0. 検証の前提条件

### 0.1 環境

| 項目 | 値 |
|---|---|
| クラウド | AWS EKS |
| EKS バージョン | 1.34 |
| リージョン | ap-northeast-1 |
| 仮想クラスタ | vCluster 0.34.2 × 3（vcluster-1, 2, 3） |
| 監視スタック | Grafana Alloy 1.8.2 / kube-prometheus-stack 86.2.0 / Tempo 1.24.4 / Loki 6.55.0 / Beyla 1.16.8 |
| デモアプリ | OpenTelemetry Demo 0.40.9（検証 1）/ 自作 go-api-server（検証 2, 3） |

### 0.2 ログ取得方針

- **ログ保存先**: `docs/v2/logs/verify{1,2,3}-{YYYYMMDD-HHMMSS}.{md,json}`
- **形式**: Markdown（人間が読む）+ JSON（再集計用）の両方
- **タイムスタンプ**: 全 PromQL クエリ・kubectl 実行は実行時刻を秒精度で記録
- **コマンド原文**: 各測定の発行コマンドをそのまま記録
- **生データ**: PromQL の結果は生 JSON のまま保存し、人間用 markdown には集計結果のみ

### 0.3 既存検証（v1）で判明した問題への対策

| 問題 ID | 内容 | 本検証での対策 |
|---|---|---|
| **C-1** | Pattern A の累積カウントが過去実験を含む | 検証 1/2 開始前に `kubectl rollout restart` で Pod を再作成し、メトリクスカウンタを 0 リセット |
| **C-2** | Pattern C が「scrape 由来 Go ランタイム」と「Beyla 由来 HTTP」の 2 系統で曖昧 | 検証では「Pattern C = Beyla eBPF 計装」と一本化し、Go ランタイムメトリクス（scrape 由来）は別軸で取得 |
| **D-1** | エラーレートを `rate[5m]` と「最大」で 2 つの数値が出ていた | `rate(...[5m])` の観測期間平均 と `max_over_time(rate(...[5m])[10m:])` の両方を記録し、両者を併記 |
| **E-3** | Alloy と Prometheus の scrape 二重化が「推測のまま」 | 検証 2 開始時に Prometheus の `/api/v1/targets` を取得して scrape job 一覧を記録 |


---

## 1. 検証 1: 3 パターン比較 + Trace-Log 相関 + エラーレート観測

### 1.1 検証目的

異なるテレメトリ収集方式（OTel SDK + Collector / OTel SDK 直送 / Beyla eBPF）を持つ 3 つの仮想クラスタが、単一の Alloy ハブで集約可能であり、`service_name` で識別できることを実証する。

### 1.2 計装方式の定義（v1 の C-2 問題を解消した整理）

| Pattern | アプリ計装 | バックエンド経路 | 観測される HTTP メトリクスの出所 |
|---|---|---|---|
| **A** (vcluster-1) | OTel SDK + OTel Collector | App → Collector (sidecar) → Alloy → Prometheus | OTel SDK |
| **B** (vcluster-2) | OTel SDK | App → Alloy → Prometheus | OTel SDK |
| **C** (vcluster-3) | なし（コード変更なし） | Beyla eBPF（ホスト側）→ Alloy → Prometheus | Beyla eBPF |
| 参考 (vcluster-3) | アプリの `/metrics` エンドポイント | Alloy `prometheus.scrape` → Prometheus | Go ランタイム scrape |

→ **本検証で「Pattern C のメトリクス」と言うときは、原則として Beyla eBPF 由来の `http_server_request_*` を指す**。Go ランタイム scrape 由来のメトリクスは補助的な存在として記述する。

### 1.3 シナリオ

1. **前処理**: 各 vcluster の go-api-server Pod を `kubectl rollout restart` で再作成し、Prometheus メトリクスカウンタをリセット（C-1 対策）
2. **scrape 構成の記録**: Prometheus `/api/v1/targets` を取得し、Pattern C の go-api-server を scrape している job 一覧を JSON 保存（E-3 対策）
3. **負荷生成**: 600 秒間、`GET /` を 2 秒ごとに 3 vcluster へ並列送信
4. **エラー注入**: 送信完了後、`GET /status/500` を Pattern A/B 各 10 回送信
5. **データ伝播待ち**: OTel SDK の `PeriodicReader` が 60 秒間隔のため、+90 秒待機
6. **データ取得**: 検証項目を全て取得

### 1.4 測定項目

#### M1-0: Scrape 構成の事前記録（E-3 対策）
- **コマンド**:
  ```bash
  kubectl exec -n monitoring statefulset/prometheus-kube-prometheus-stack-prometheus -- \
    wget -qO- http://localhost:9090/api/v1/targets | \
    jq '.data.activeTargets[] | select(.scrapeUrl | contains("go-api-server"))'
  ```
- **記録内容**: scrape job 名、scrape URL、interval、scheme、Pod 識別ラベル
- **目的**: Pattern C の go-api-server が **何個の job** からスクレイプされているかを確定し、考察で推測なしに記述できるようにする

#### M1-1: Pod 稼働確認
- **コマンド**:
  ```bash
  kubectl get pods -n vcluster-{1,2,3} -l "app=go-api-server" --field-selector=status.phase=Running -o json
  ```
- **合格基準**: 各 vcluster で 1 Pod 以上が Running

#### M1-2: Metrics → Prometheus
- **PromQL**（各 Pattern を独立に取得）:
  ```promql
  # Pattern A
  count by (service_name) (
    http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"}
  )
  # Pattern B
  count by (service_name) (
    http_server_request_duration_seconds_count{service_name="go-api-server-pattern-b"}
  )
  # Pattern C (Beyla 由来)
  count by (service_name) (
    http_server_request_duration_seconds_count{service_name="go-api-server-pattern-c"}
  )
  # Pattern C (scrape 由来 Go ランタイム、補助)
  count by (service_name) (
    go_goroutines{service_name="go-api-server-pattern-c"}
  )
  ```
- **合格基準**: 各クエリが 1 以上を返す

#### M1-3: Traces → Tempo
- **コマンド**:
  ```bash
  curl -s 'http://localhost:3200/api/search?tags=service.name%3Dgo-api-server-pattern-a&limit=10' | jq '.traces | length'
  ```
- **合格基準**:
  - Pattern A: 1 以上
  - Pattern B: 1 以上
  - Pattern C: 1 以上（Beyla 由来）

#### M1-4: Logs → Loki
- **コマンド**:
  ```bash
  curl -s 'http://localhost:3100/loki/api/v1/query_range?query={service_name="go-api-server-pattern-a"}&start=...&end=...' | jq '.data.result | length'
  ```
- **合格基準**:
  - Pattern A: 1 以上
  - Pattern B: 1 以上
  - Pattern C: 0（期待値、OTel SDK Log Bridge なし）

#### M1-5: `service_name` 区別可能性
- **PromQL**:
  ```promql
  count by (service_name) ({service_name=~"go-api-server-pattern-.*"})
  ```
- **合格基準**: 3 種類（`go-api-server-pattern-a`/`b`/`c`）が観測される

#### M1-6: Trace-Log 相関（Pattern A/B のみ）
- **手順**: Loki から traceid を抽出 → Tempo でトレース存在確認
- **PromQL/コマンド**:
  ```bash
  # 1. Loki から traceid を取得
  traceid=$(curl -s '...' | jq -r '.data.result[0].values[0][1] | fromjson | .traceid')
  # 2. Tempo でトレース存在確認
  curl -sf "http://localhost:3200/api/traces/${traceid}" -o /dev/null -w "%{http_code}\n"
  ```
- **合格基準**: HTTP 200

#### M1-7: エラーレート（C-1 対策で `increase()` 使用）
- **PromQL**:
  ```promql
  # 実験期間（10 分）の 5xx 増分
  increase(http_server_request_duration_seconds_count{
    service_name="go-api-server-pattern-a",
    http_response_status_code=~"5.."
  }[10m])

  # エラーレート（rate ベース）
  100 * sum(rate(http_server_request_duration_seconds_count{
    service_name="go-api-server-pattern-a",
    http_response_status_code=~"5.."
  }[5m]))
  / sum(rate(http_server_request_duration_seconds_count{
    service_name="go-api-server-pattern-a"
  }[5m]))
  ```
- **合格基準**:
  - Pattern A: 5xx 増分 ≒ 10 件（注入回数と一致）、エラーレート > 0%
  - Pattern B: 5xx 増分 ≒ 10 件、エラーレート > 0%
  - Pattern C: 5xx 増分 0 件、エラーレート 0%（エラー注入していないため）

### 1.5 ログ出力フォーマット

```
docs/v2/logs/verify2-{timestamp}.md
docs/v2/logs/verify2-{timestamp}.json
```

JSON 形式（例）:
```json
{
  "experiment_id": "verify2-20260609-040000",
  "scrape_targets": [
    {"job": "...", "scrapeUrl": "...", "interval": "30s"}
  ],
  "metrics": {
    "pattern_a": { "spans_5xx_increase": 10, "error_rate_percent": 0.52 },
    "pattern_b": { "spans_5xx_increase": 10, "error_rate_percent": 0.52 },
    "pattern_c": { "spans_5xx_increase": 0, "error_rate_percent": 0 }
  },
  "service_names_observed": ["go-api-server-pattern-a", "go-api-server-pattern-b", "go-api-server-pattern-c"],
  "trace_log_correlation": {
    "pattern_a": { "traceid": "...", "tempo_http_status": 200 },
    "pattern_b": { "traceid": "...", "tempo_http_status": 200 }
  }
}
```

---

## 2. 検証 2: テナント障害分離

### 2.1 検証目的

vcluster-1 のみに障害を注入したとき、vcluster-2 / vcluster-3 のメトリクス・トレース・ログに **一切影響が出ない** ことを実証する。

### 2.2 シナリオ

1. **前処理**: C-1 対策で各 Pod を `kubectl rollout restart`
2. **ベースライン記録**: 実験前の Pattern B/C の 5xx 累積カウントを記録
3. **負荷生成**: 600 秒間、`GET /` を 2 秒ごとに 3 vcluster へ並列送信
4. **障害注入（並行）**: 同時間に **vcluster-1 のみ** `GET /status/500` を 2 秒ごとに送信
5. **データ伝播待ち**: +90 秒
6. **データ取得**: 検証項目を全て取得

### 2.3 測定項目

#### M2-1: Pattern A のエラーレート（障害が記録されている）
- **PromQL**（D-1 対策: 平均と最大の両方を記録）:
  ```promql
  # 観測期間平均
  avg_over_time(
    (100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a",http_response_status_code=~"5.."}[5m]))
     / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"}[5m])))[10m:30s]
  )

  # 観測期間最大
  max_over_time(
    (100 * sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a",http_response_status_code=~"5.."}[5m]))
     / sum(rate(http_server_request_duration_seconds_count{service_name="go-api-server-pattern-a"}[5m])))[10m:30s]
  )
  ```
- **合格基準**: 観測期間平均 > 30%、観測期間最大 > 40%（両者が一桁ポイント差で整合）

#### M2-2: Pattern B のエラーレート（障害が波及していない）
- 同上の PromQL を `service_name="go-api-server-pattern-b"` で実行
- **合格基準**: 観測期間平均 = 0%、観測期間最大 = 0%

#### M2-3: Pattern B の 5xx 累積カウント変化
- **PromQL**:
  ```promql
  # 実験前後の差分
  increase(http_server_request_duration_seconds_count{
    service_name="go-api-server-pattern-b",
    http_response_status_code=~"5.."
  }[10m])
  ```
- **合格基準**: 0 件（実験期間中に 5xx が一切増えていない）

#### M2-4: Pattern C のエラーレート確認（D-2 対策: vcluster-3 も明示的に検証）
- **PromQL**: M2-2 と同様、`service_name="go-api-server-pattern-c"` で実行
- **合格基準**: 観測期間平均 = 0%、観測期間最大 = 0%
- **Pattern C の 5xx 増分**: 0 件

#### M2-5: Trace の分離確認
- **コマンド**: Tempo で `service.name=go-api-server-pattern-a status=error` のトレース数 vs Pattern B/C のエラー trace 数
- **合格基準**:
  - Pattern A: > 0 件
  - Pattern B: 0 件
  - Pattern C: 0 件

#### M2-6: Log の分離確認
- **コマンド**: Loki で `service_name="go-api-server-pattern-a"` のログから 5xx エントリ抽出 vs Pattern B のエラーログ
- **合格基準**:
  - Pattern A: エラーログ多数
  - Pattern B: エラーログ 0 件

### 2.4 ログ出力フォーマット

```
docs/v2/logs/verify3-{timestamp}.md
docs/v2/logs/verify3-{timestamp}.json
```

JSON 形式（例）:
```json
{
  "experiment_id": "verify3-20260609-050000",
  "isolation_results": {
    "pattern_a": {
      "error_rate_avg_percent": 42.5,
      "error_rate_max_percent": 45.1,
      "spans_5xx_increase": 300
    },
    "pattern_b": {
      "error_rate_avg_percent": 0,
      "error_rate_max_percent": 0,
      "spans_5xx_increase": 0
    },
    "pattern_c": {
      "error_rate_avg_percent": 0,
      "error_rate_max_percent": 0,
      "spans_5xx_increase": 0
    }
  }
}
```

---

## 3. 補助検証: Alloy ハブの自己メトリクス

### 3.1 検証目的

検証 1/2 を通じて Alloy のキュー積み上がり・送信失敗が発生していないことを記録する。これにより記事の「Alloy 単一ハブの有効性」を裏付ける（観測期間を明示することで E-1 問題を解消）。

### 3.2 測定項目

#### M4-1: Alloy 自己メトリクス（観測期間明示）
- **PromQL**:
  ```promql
  # 観測期間（検証 2 開始から検証 2 終了まで）の差分で取得
  increase(otelcol_receiver_accepted_spans_total[2h])
  increase(otelcol_exporter_sent_spans_total[2h])
  otelcol_exporter_queue_size  # gauge は瞬時値
  increase(otelcol_exporter_send_failed_spans_total[2h])
  ```
- **記録内容**: 観測期間の開始時刻 T_start と終了時刻 T_end を明示

---

## 4. ログ取得自動化

検証 1/2 は同一フォーマットなので、`scripts/verify2.sh` `scripts/verify3.sh` を以下の構造にリファクタリングする想定:

```bash
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_MD="docs/v2/logs/verifyN-${TIMESTAMP}.md"
LOG_JSON="docs/v2/logs/verifyN-${TIMESTAMP}.json"

# 各測定項目を実行し、生 JSON を一時ファイルに保存
# 最後に jq でまとめて LOG_JSON を生成
# 並行で人間用 markdown を LOG_MD に書き出す
```

具体的なスクリプト修正案は `02-experiment-protocol.md` で提示する。
