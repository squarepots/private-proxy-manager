# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[快速开始](docs/QUICKSTART.zh-CN.md) · [常见问题](docs/FAQ.zh-CN.md) · [兼容性](docs/COMPATIBILITY.md) · [运行边界](docs/OPERATING-BOUNDARY.md) · [安全](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**告诉 AI 你希望网络路径如何运行，Route Steward 负责持续维护。**

Route Steward 是一个 local-first 的自托管网络路径生命周期管理工具。具备本地工具能力的 AI agent 可以把你对网络连接的意图转化为经过验证的状态、服务器部署、客户端配置、在线审计、漂移检测、迁移与恢复流程。

Route Steward 以你所选端点之间具备互联网可达性为运行前提。互联网承载数据传输；你提供服务器、账户及网络资源的使用授权；Route Steward 提供可重复、可验证的运维层。

## 从 AI agent 开始

把仓库链接交给 Codex 或其他能够读取本地文件、运行 PowerShell 的 agent，然后使用下面的提示词：

> 打开 <https://github.com/squarepots/route-steward> 并替我操作 Route Steward。需要时先 clone，阅读 AGENTS.md 和 repository Skill，检查 capability surface，并运行快速本地验证。先解释第一条自托管网络路径所需条件和主机级影响，再收集必需上下文；凭据与生成的客户端文件保存在 private 目录；每次修改前运行 preflight；向我返回脱敏结果。

agent 从以下检查开始：

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

capability discovery 是机器可读的能力事实源。Repository Skill 负责指导上下文收集、中性 bootstrap、限定范围的执行、验证与脱敏汇报。

## 你提供的资源

- 一台安装 PowerShell 7、可供 tool-capable AI agent 操作的本地电脑；
- 一台或两台专用、可重建的 Ubuntu 24.04 amd64 服务器；
- 获得授权的 SSH 访问、Unix 用户名和私钥路径；
- Mihomo/Clash Verge 兼容软件或 Shadowrocket。

Node.js 和 Wrangler 用于可选的 Cloudflare 私有配置交付；7-Zip 用于加密备份与恢复。

Route Steward 会准备整台服务器，因此每台受管主机应专用于对应网络路径。

## Route Steward 管理的内容

- direct Hysteria2 path 和单跳 WireGuard relay path；
- Server、Link、Route、Provider、Profile、ClientTarget 的声明式状态；
- Mihomo/Clash 兼容文件和 Shadowrocket 导入内容；
- 每个 Shadowrocket ClientTarget 隔离的可选配置交付；
- 有限远程证据和类型化 desired-versus-observed drift；
- overlap-first 基础设施替换，在切换前验证新容量；
- 独立于聊天记录的加密 recovery archive。

干净 bootstrap 从中性状态开始。agent 根据目标所需上下文添加地区、Provider、策略、客户端、交付方式与基础设施。

## 运行边界

Route Steward 面向操作者拥有或获授权管理的服务器、账户与网络资源。每个部署都应遵循其所在地和使用场景适用的法律、运营商要求、云服务商条款与组织策略。

开源发行版采用 bring-your-own-infrastructure 模式。网络服务商提供连接能力，Route Steward 在选定基础设施上管理配置与生命周期。完整说明见[运行边界](docs/OPERATING-BOUNDARY.md)。

## 对主机的影响

首次部署会准备整台 Ubuntu 主机，可能会：

- 安装 `ufw`、`unattended-upgrades`、`vnstat`、`mtr`、`curl`、`jq`、`openssl` 等软件包；
- 创建 1 GiB `/swapfile` 并写入 `/etc/fstab`；
- 配置 UFW 默认策略、SSH 防护和出站 SMTP 控制；
- 写入 Route Steward 命名的 SSH、sysctl、BBR、journald、unattended-upgrades 和内核模块策略；
- 创建 Route Steward 服务、运行用户、WireGuard 接口、配置与凭据。

卸载流程会移除 Route Steward 管理的服务、接口、文件和命名策略文件。软件包、swap 与既有主机级设置保留给操作者检查。准确 ownership boundary 见 [Operations](OPERATIONS.md)。

## 成功结果示例

```text
path                direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

这个合成结果使用 private-root-relative artifact identity。Agent 与 MCP 输出将本地路径、SSH 材料、Provider URL、交付凭据和原始诊断保留在各自的私有边界中。

## 当前支持的技术栈

- 通过 BYO SSH 访问的 Ubuntu 24.04 amd64 专用主机；
- Hysteria2 ingress；
- direct 与单跳 WireGuard relay topology；
- 可选的通用 Mihomo HTTP Provider；
- Mihomo/Clash Verge 兼容输出和 Shadowrocket 输出；
- 可选的 ClientTarget-scoped Cloudflare Worker 交付。

[Compatibility](docs/COMPATIBILITY.md) 是面向人的能力契约，capability discovery 是对应的运行时事实源。

## 隐私与授权

确定性引擎将 desired state、凭据、生成的客户端文件、observed evidence 和 recovery archive 保存在选定的本地 private 目录。云端 AI runtime 可能处理任务所需的操作参数，例如服务器地址、SSH 用户名、key path 和选定 ID。需要更强本地边界时，可使用不识别个人信息的 ID 与离线 runtime。

每次 mutation 都经过 scoped preflight。凭据轮换采用当前明确授权，远程修改限于 Route Steward 管理的资源，基础设施迁移采用 overlap-first 工作流。详细边界见 [Privacy](docs/PRIVACY.md)、[Security](SECURITY.md) 与 [Threat model](docs/THREAT-MODEL.md)。

## 继续阅读

- [中文快速开始](docs/QUICKSTART.zh-CN.md)：把链接交给 agent，完成第一次安全流程。
- [中文 FAQ](docs/FAQ.zh-CN.md)：主机、AI 可见性、恢复、drift 与客户端。
- [Architecture](ARCHITECTURE.md)：对象模型和确定性边界。
- [Contributing](CONTRIBUTING.md)：开发与验证契约。
- [Releasing](docs/RELEASING.md)：版本与发布流程。

Route Steward 使用 [AGPL-3.0-only](LICENSE)。Vendored QR generator 的 MIT attribution 保留在 [client/vendor/NOTICE.md](client/vendor/NOTICE.md)。
