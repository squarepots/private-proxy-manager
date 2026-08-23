# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[Quickstart](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [Compatibility](docs/COMPATIBILITY.md) · [Operating boundary](docs/OPERATING-BOUNDARY.md) · [Security](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**AI にネットワークパスの運用方針を伝えると、Route Steward が継続的に管理します。**

Route Steward は、セルフホスト型ネットワークパスのライフサイクルを管理する local-first ツールです。ツールを利用できる AI agent が、オペレーター管理下のインフラに対する接続要件を、検証済み状態、サーバーデプロイ、クライアント設定、監査、drift 検出、移行、復旧へ変換します。

選択したエンドポイント間の Internet 到達性を前提とします。Internet が転送を担い、利用者がサーバー、アカウント、ネットワークリソースの利用権限を用意し、Route Steward が再現可能な運用レイヤーを提供します。

## AI agent から始める

リポジトリ URL を Codex などのローカルファイルと PowerShell を扱える agent に渡し、次のように依頼します。

> Open <https://github.com/squarepots/route-steward> and operate Route Steward for me. Read AGENTS.md and the repository Skill, inspect capabilities, run quick local validation, explain the requirements for my first self-hosted network path, keep sensitive state in the private directory, run preflight before changes, and return sanitized results.

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## 用意するもの

- PowerShell 7 と tool-capable AI agent を利用できるローカル PC
- 専用で再構築可能な Ubuntu 24.04 amd64 サーバー 1 台または 2 台
- 正当な管理権限に基づく SSH アクセス
- Mihomo/Clash Verge 互換ソフトウェアまたは Shadowrocket

## 管理対象

- direct Hysteria2 path と single-hop WireGuard relay path
- Server、Link、Route、Provider、Profile、ClientTarget の desired state
- Mihomo/Clash 互換ファイルと Shadowrocket import
- ClientTarget ごとに分離された任意の設定配信
- remote audit、typed drift、overlap-first migration
- 暗号化された recovery archive

## 運用条件

Route Steward は、オペレーターが所有するか、管理権限を与えられたサーバー、アカウント、ネットワークリソースを対象とします。各デプロイは、適用される法令、通信事業者の要件、クラウド事業者の利用条件、組織のポリシーに従って構成します。詳細は [Operating boundary](docs/OPERATING-BOUNDARY.md) を参照してください。

実装済みのホスト、プロトコル、renderer、Provider は [Compatibility](docs/COMPATIBILITY.md) と capability discovery に記載されています。プライバシーと権限の境界は [Privacy](docs/PRIVACY.md)、[Security](SECURITY.md)、[Threat model](docs/THREAT-MODEL.md) を参照してください。

Route Steward は [AGPL-3.0-only](LICENSE) で提供されます。
