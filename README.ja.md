# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [Releases](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**AI エージェントで、自分のサーバーにプライベートプロキシを構築・管理。**

このリポジトリを AI エージェントに渡し、必要なプロキシを説明してください。Route Steward がコマンド、安全確認、サーバー設定、クライアントファイル、監査、復旧手順を提供します。

## URL を AI エージェントに渡す

```text
https://github.com/squarepots/route-steward を開き、自分が管理するサーバーにプライベートプロキシを構築して管理するのを手伝ってください。AGENTS.md と .agents/skills/route-steward/SKILL.md を読み、このコンピューターに合う Route Steward のリリース版を使い、route-steward capabilities から始めてください。
```

インストール方法と必要条件は [Quickstart](docs/QUICKSTART.md) を参照してください。

## 得られるもの

- 1 台のサーバーを使う Hysteria2 プライベートプロキシ、または 2 台を結ぶ WireGuard 中継
- 特定の UDP ポートを制限するネットワーク向けの、任意のポートホッピング
- Mihomo/Clash Verge 互換アプリ、Karing、Shadowrocket、GUI なしの Hysteria2 用プライベート設定ファイル
- サーバー監査、設定差分レポート、オンデマンドの実通信確認
- クライアントを切り替える前に新しい経路を試験する、再開可能なサーバー交換
- 暗号化されたローカルバックアップと復旧
- コマンドラインまたはローカル標準入出力 MCP から使える JSON コマンド

現在のサーバー基準は、SSH 鍵で接続できる専用かつ再構築可能な Ubuntu 24.04 amd64 VPS です。詳細は [Compatibility](docs/COMPATIBILITY.md) を参照してください。

## ホストへの影響とプライバシー

初期設定では、ホスト全体のファイアウォール、スワップ、SSH、システム設定、ログ、更新、パッケージ、監視を変更します。専用で再構築可能なサーバーを使用してください。

運用状態、鍵、生成ファイル、復旧アーカイブは選択したプライベートディレクトリに保存され、Git から除外されます。クラウド AI サービスには、操作に必要なサーバー情報が送られる場合があります。情報をローカルに限定する必要がある場合はオフライン環境を使用してください。

所有するか管理を許可されたサーバー、アカウント、ネットワークリソースだけを使用してください。Route Steward は [AGPL-3.0-only](LICENSE) で提供されます。QR generator の MIT 表示は [client/vendor/NOTICE.md](client/vendor/NOTICE.md) にあります。
