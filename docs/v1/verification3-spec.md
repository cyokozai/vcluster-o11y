# 検証 3: テナント障害分離の実証

## 目的

検証 2.1 では 3 パターンのテレメトリパイプラインが正しく収集・区別されることを確認した。
検証 3 では「**マルチテナント監視基盤がテナント間の障害を正確に分離・識別できる**」ことを実証する。

具体的には、vcluster-1 にのみ継続的な障害（高エラーレート）を注入しながら通常トラフィックを全テナントに送り続け、
Prometheus・Tempo・Loki の各シグナルで vcluster-1 の異常が vcluster-2/3 に波及しないことを確認する。

---

## 検証 2.1 からの差分

| フェーズ | 検証 2.1 | 検証 3 |
|---|---|---|
| Phase 1 リクエスト送信 | 全パターンに GET /、終了後 A/B 各 10 回 /status/500 | 全パターンに GET /、**vcluster-1 にのみ並行して継続的に /status/500**（実験全体を通じて） |
| Phase 6 | エラーレート > 0 の確認（A/B 両方） | **テナント障害分離確認**（A のみ高エラー、B は 0% を確認） |

---

## 検証項目一覧

### 継続項目（検証 2.1 から引き継ぎ）

| 確認項目 | Pattern A | Pattern B | Pattern C | 確認手段 |
|---|---|---|---|---|
| Metrics → Prometheus | ✅ | ✅ | ✅ | Prometheus API |
| Traces → Tempo | ✅ | ✅ | ✅（0 件） | Tempo Search API |
| Logs → Loki | ✅ | ✅ | ✅（0 件） | Loki Query Range API |
| `service_name` で区別可能 | ✅ | ✅ | ✅ | Prometheus `count by` |
| Trace-Log 相関 | ✅ | ✅ | N/A | Loki traceid → Tempo |

### 新規: Phase 6 テナント障害分離確認

#### シナリオ

- Phase 1 で vcluster-1 に `GET /status/500` を `GET /` と同じ間隔（2 秒ごと）で並行送信
- 実験終了時点での期待エラーレート:
  - Pattern A: `/status/500` と `/` が交互 → **約 50%**
  - Pattern B: 通常リクエストのみ → **0%**
  - Pattern C: OTel SDK なし → **N/A**

#### 確認項目

| 確認項目 | Pattern A | Pattern B | Pattern C |
|---|---|---|---|
| エラーレート > 20%（障害が記録されている） | ✅ | N/A | N/A |
| エラーレート = 0%（障害が波及していない） | N/A | ✅ | N/A |
| 5xx トレースが Tempo に存在 | ✅ | 存在しないことを確認 | N/A |

---

## 確認項目数の内訳

| フェーズ | 項目 | 数 |
|---|---|---|
| Phase 0 | Pod 稼働確認 | 7 |
| Port-Forward | 疎通確認 | 6 |
| Phase 1 | リクエスト送信完了 | 1 |
| Phase 2 | Metrics 存在確認 + service_name 区別 | 4 |
| Phase 3 | Traces 存在確認 (A/B) + Pattern C 0 件確認 | 3 |
| Phase 4 | Logs 存在確認 (A/B) + Pattern C 0 件確認 | 3 |
| Phase 5 | Trace-Log 相関 (A/B) | 2 |
| Phase 6 (新規) | 障害分離確認（A エラーレート > 20%, B = 0%, B の 5xx トレース = 0 件） | 3 |
| **合計** | | **29** |

---

## 比較表: 検証 2.1 vs 検証 3

| 確認項目 | 検証 2.1 | 検証 3 |
|---|---|---|
| テレメトリ到達確認 | ✅ | ✅（継続） |
| Trace-Log 相関 | ✅ | ✅（継続） |
| エラーレート観測 | ✅（A/B 両方に注入） | ✅（A のみ注入） |
| **テナント障害分離** | 未検証 | ✅ **追加** |
