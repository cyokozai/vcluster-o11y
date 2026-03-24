module github.com/vcluster-o11y/server03

go 1.26

// Beyla (eBPF) 自動計装への移行により Prometheus クライアント依存を除去。
// 標準ライブラリのみで動作する。
