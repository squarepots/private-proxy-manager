# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**AI を使って、自分のサーバーのネットワークを管理する。**

Route Steward は、管理するサーバー上のネットワーク接続をデプロイ、点検、移行、復旧できるようにします。GitHub URL をツール対応の AI agent に渡すと、対応機能の確認、計画、preflight、ネイティブ `route-steward` 実行、機密情報を除いた結果報告まで進められます。

![AI の依頼から検証済み状態、direct または relay 接続、稼働監査、Mihomo または Shadowrocket の private 出力までを示す Route Steward。](docs/assets/network-path-lifecycle.svg)

## URL を AI agent に渡す

```text
https://github.com/squarepots/route-steward を開き、自分が管理するサーバーのネットワーク管理を手伝ってください。必要なら clone し、AGENTS.md と .agents/skills/route-steward/SKILL.md を読んでから、公開バイナリを使うか Go CLI をビルドしてください。インフラ情報を尋ねる前に capabilities を実行してください。専用ホストの要件とシステムへの影響を説明し、運用状態を非公開に保ち、変更前には毎回 preflight を実行し、機密情報を除いた結果だけを返してください。
```

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
```

通常利用に PowerShell や Node.js は不要です。[Releases](https://github.com/squarepots/route-steward/releases) から Linux、macOS、Windows 用バイナリを取得するか、Go 1.27 でインストールできます。

```text
go install github.com/squarepots/route-steward/cmd/route-steward@latest
```

Node.js は任意の Cloudflare Worker subscription delivery を選ぶ場合だけ必要です。

## 得られるもの

- 1 台のサーバーを使う direct route、または 2 台を使う single-hop WireGuard relay
- Hysteria2 のサーバー状態と private な Mihomo / Shadowrocket 出力
- 盲目的な上書きを防ぐ read-only audit と型付き drift
- 接続を残したまま行うサーバー移行と暗号化ローカル復旧
- CLI と local stdio MCP で共通の machine-readable interface

現在のサーバー基準は、正当な SSH key access を持つ専用で再構築可能な Ubuntu 24.04 amd64 VPS です。詳細は [Compatibility](docs/COMPATIBILITY.md) を参照してください。

## ホストへの影響とプライバシー

初期設定は firewall、swap、SSH、sysctl、logging、updates、packages、monitoring などホスト全体を準備します。運用状態、鍵、生成ファイル、復旧アーカイブは選択した private directory に保存され Git から除外されます。Cloud AI runtime は操作入力の server address、SSH user、key path、ID を処理する場合があります。入力をローカルに限定する必要がある場合は offline runtime を利用してください。

所有するか管理を許可されたサーバー、アカウント、ネットワークリソースだけを使用してください。Route Steward は [AGPL-3.0-only](LICENSE) で提供されます。QR generator の MIT 表示は [client/vendor/NOTICE.md](client/vendor/NOTICE.md) にあります。
