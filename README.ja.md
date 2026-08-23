# Private Proxy Manager

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[クイックスタート](docs/QUICKSTART.md) · [FAQ](docs/FAQ.md) · [互換性](docs/COMPATIBILITY.md) · [セキュリティ](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager（PPM）は、利用者が管理するサーバー上で AI agent がプライベートなプロキシルートを構築・保守するためのツールです。目的とするネットワーク構成と認証情報をローカルの private ディレクトリに保持し、SSH 経由で対応サーバースタックを配備し、クライアント設定を生成し、稼働中のルートを監査します。サーバー交換時には、動作中のルートを先に停止せずに移行を進めます。

利用者はサーバー、SSH アクセス、対応プロキシクライアントを用意します。PPM は、それらをつなぐ再現可能な運用レイヤーを提供します。

## AI agent から始める

このリポジトリの URL を、ローカルファイルを読み PowerShell を実行できる Codex などの agent に渡し、次のプロンプトを使います。

> <https://github.com/squarepots/private-proxy-manager> を開き、PPM を操作してください。ローカルになければ先に clone してください。作業前に AGENTS.md と repository Skill を読み、capability surface を確認して quick local validation を実行してください。その後、最初のルートに必要なものとホスト全体への影響を説明してから、実際のサーバー情報を尋ねてください。認証情報と生成したクライアントファイルは Git に無視される private ディレクトリに保持し、変更前には必ず preflight を実行し、機密情報を除いた結果だけを示してください。

agent が最初に行う安全な確認は次のとおりです。

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

Capability discovery が機械可読な唯一の能力情報です。Repository Skill は、agent が必要な情報を集め、中立的なローカル状態を初期化し、必要なオブジェクトを作成し、各変更を検証し、secret を露出せずに結果を報告する方法を定めています。

## 用意するもの

- tool-capable AI agent と PowerShell 7 を利用できるローカルコンピューター
- 専用で再構築可能な Ubuntu 24.04 amd64 VPS を 1 台または 2 台
- 有効な Unix username と private-key path による SSH アクセス
- クライアントとして Mihomo/Clash Verge 互換ソフトウェアまたは Shadowrocket

Node.js と Wrangler が必要なのは、Cloudflare による任意の private subscription delivery を使う場合だけです。7-Zip が必要なのは、暗号化バックアップと recovery を使う場合だけです。

PPM はサーバー全体を準備するため、既存の production workload と共有せず、専用ホストを使用してください。

## PPM が行うこと

- direct Hysteria2 route または 1-hop WireGuard relay route を構築する
- Server、Route、Provider、Profile、ClientTarget の目的状態を、検証済みのローカル inventory で管理する
- Mihomo/Clash 互換ファイルと Shadowrocket import を生成する
- 任意で、分離された ClientTarget ごとに private Shadowrocket subscription を公開する
- desired state と範囲を限定した remote evidence を比較し、型付きの drift を報告する
- overlap-first でインフラを交換し、交換先の検証が終わるまで既存 capacity を維持する
- chat history に依存しない暗号化 recovery archive を作成する

クリーンな bootstrap には、地域、Provider、policy、client、subscription、AI vendor の既定値がありません。agent は実際に必要なルートに必要な事実だけを尋ねます。

## ホストへの影響

初回配備では専用 Ubuntu ホストを準備し、次の変更を行う場合があります。

- `ufw`、`unattended-upgrades`、`vnstat`、`mtr`、`curl`、`jq`、`openssl` などの package をインストールする
- 1 GiB の `/swapfile` を作成し、`/etc/fstab` に永続化する
- UFW の既定値を設定して有効化し、SSH を保護し、外向き SMTP port 25、465、587 を遮断する
- PPM 名義の SSH、sysctl、BBR、journald、unattended-upgrades、module configuration を設置する
- PPM service、runtime user、WireGuard interface、設定、認証情報を作成する

uninstall は PPM が所有する service、interface、file、名前付き policy file を削除します。以前のホスト設定を確実に再構築できないため、package、swap、不明な既存の host-wide setting は残します。正確な ownership boundary は [Operations](OPERATIONS.md) を参照してください。

## 成功時の結果

```text
route               direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

これは synthetic な形の例です。Agent と MCP の結果は private root からの相対 artifact identity を返し、Windows drive path、home directory、SSH key、Provider URL、token、未加工の remote diagnostics は返しません。

## 対応スタック

現在テストされている構成は次のとおりです。

- BYO SSH で接続する Ubuntu 24.04 amd64 の専用ホスト
- Hysteria2 ingress
- direct topology と 1-hop WireGuard relay topology
- 任意の汎用 Mihomo HTTP Provider
- Mihomo/Clash Verge 互換および Shadowrocket の rendering
- 任意の ClientTarget-scoped Cloudflare Worker delivery

完全な capability contract は [Compatibility](docs/COMPATIBILITY.md) にあります。protocol、host、renderer、provider type がこの文書にも capability discovery にもなければ、PPM はそれを実装していません。

## プライバシーと権限

PPM の決定論的エンジンは private state をアップロードしません。ただし、クラウドの AI runtime は、server address、SSH username、key path、選択した ID などの operation arguments を受け取る場合があります。個人を特定しない ID を使い、それらの引数を端末外へ出せない場合は offline runtime を選んでください。

Private inventory、credentials、生成済み client file、observed evidence、recovery archive はローカルの機密データです。OS の権限とバックアップで private ディレクトリを保護し、その内容を issue や chat に貼り付けないでください。

すべての mutation はローカル preflight で確認されます。context が不足または矛盾していれば実行を停止します。Subscription-token rotation にはその時点での明示的な承認が必要です。remote change は PPM の ownership boundary 内に限定され、infrastructure migration は overlap-first で行われます。ネットワークプライバシーの限界と compromise response は [Privacy](docs/PRIVACY.md)、[Security](SECURITY.md)、[Threat model](docs/THREAT-MODEL.md) を参照してください。

## 関連資料

- [Quickstart](docs/QUICKSTART.md)：URL を agent に渡し、最初の安全な workflow を完了する
- [FAQ](docs/FAQ.md)：host、AI visibility、recovery、drift、client に関する平易な回答
- [Architecture](ARCHITECTURE.md)：object model と決定論的な境界
- [Contributing](CONTRIBUTING.md)：開発と validation の契約
- [Releasing](docs/RELEASING.md)：version と release の手順

PPM は [AGPL-3.0-only](LICENSE) でライセンスされています。vendored QR generator の MIT attribution は [client/vendor/NOTICE.md](client/vendor/NOTICE.md) に保持されています。
