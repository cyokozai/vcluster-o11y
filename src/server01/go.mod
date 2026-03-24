module github.com/vcluster-o11y/server01

go 1.26

// Beyla (eBPF) 自動計装への移行により OTel SDK 依存を全て除去。
// 標準ライブラリのみで動作する。
