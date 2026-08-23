# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**AI を使って、自分のサーバーのネットワークを管理する。**

Route Steward は、管理するサーバー上のネットワーク接続をデプロイ、点検、移行、復旧できるようにします。サーバー、アカウント、管理権限は利用者が用意し、Route Steward はツールを使える AI agent に、ローカル PC から反復可能で検証済みの操作手順を提供します。

![AI が操作するコントロールプレーンと、Entry-A および任意の Relay-A を通る direct/relay トラフィックパスを分けて示した synthetic Route Steward 図。](docs/assets/network-path-lifecycle.svg)

## AI agent から始める

次の prompt を、ファイルを読んで PowerShell を実行できる Codex などの agent に貼り付けます。

```text
https://github.com/squarepots/route-steward を開き、AI を使って自分のサーバーのネットワークを管理してください。必要なら clone し、AGENTS.md と repository Skill を読み、capabilities を確認して quick local validation を実行してください。インフラ情報を尋ねる前に、専用ホストの要件、ホスト全体への影響、運用境界を説明してください。機密状態は private ディレクトリに保持し、変更前に preflight を実行し、機密情報を除いた結果だけを返してください。
```

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## 必要なもの

- PowerShell 7 と tool-capable AI agent を利用できるローカル PC
- 専用で再構築可能な Ubuntu 24.04 amd64 サーバー 1 台または 2 台
- 正当な管理権限に基づく SSH アクセス、Unix username、private-key path
- Mihomo/Clash Verge 互換ソフトウェアまたは Shadowrocket

Route Steward はホスト全体を準備するため、管理対象サーバーはこのネットワーク設定専用である必要があります。

## Route Steward が行うこと

サーバーとクライアントの設定を作成・検証し、稼働状態を点検し、既存接続を先に失わずにインフラを置き換え、暗号化された復旧アーカイブを作成します。

[Compatibility](docs/COMPATIBILITY.md) に、現在対応するホスト、プロトコル、クライアント、トポロジー、任意の Cloudflare 配信を記載しています。

## ホストへの影響とプライバシー

セットアップは、ホスト全体の firewall、swap、SSH、system、logging、update、monitoring 設定を変更します。機密状態と生成ファイルは選択したローカル private ディレクトリに保存し、変更前に ready な preflight が必要です。[Operations](OPERATIONS.md)、[Privacy](docs/PRIVACY.md)、[Security](SECURITY.md) を確認してください。

所有するか管理を許可されたサーバー、アカウント、ネットワークリソースだけを使用してください。詳細は [Operating boundary](docs/OPERATING-BOUNDARY.md) にあります。

Route Steward は [AGPL-3.0-only](LICENSE) で提供されます。Vendored QR generator の MIT 表示は [client/vendor/NOTICE.md](client/vendor/NOTICE.md) にあります。
