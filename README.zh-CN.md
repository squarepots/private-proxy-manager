# Private Proxy Manager

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[快速开始](docs/QUICKSTART.zh-CN.md) · [常见问题](docs/FAQ.zh-CN.md) · [兼容性](docs/COMPATIBILITY.md) · [安全](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager（PPM）帮助 AI agent 在你控制的服务器上建立并维护私人代理路线。它把网络计划和凭据保存在本地私有目录，通过 SSH 部署受支持的服务端组件，生成客户端配置，审计实际路线，并在替换服务器时先验证新路线，再处理旧路线。

你提供服务器、SSH 访问和受支持的代理客户端；PPM 负责把它们连接成一套可重复、可检查的运维流程。

## 从 AI agent 开始

把这个仓库链接交给 Codex 或其他能够读取本地文件、运行 PowerShell 的 agent，然后使用下面的提示词：

> 打开 <https://github.com/squarepots/private-proxy-manager> 并替我操作 PPM。如果本地没有仓库，先 clone。执行前阅读 AGENTS.md 和 repository Skill，检查 capability surface，并运行快速本地验证。然后先解释第一条路线需要哪些条件、会对主机产生哪些整机影响，再向我索取真实服务器信息。凭据和生成的客户端文件必须留在被忽略的 private 目录；每次修改前运行 preflight；只向我返回脱敏结果。

agent 最先运行的安全检查是：

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

capability discovery 是机器可读的真实能力清单。Repository Skill 告诉 agent 如何收集上下文、创建中性的本地状态、建立需要的对象、验证每一步，并在不暴露 secret 的前提下汇报结果。

## 你需要准备

- 一台安装 PowerShell 7、可供 tool-capable AI agent 操作的本地电脑；
- 一台或两台专用、可重建的 Ubuntu 24.04 amd64 VPS；
- 有效的 Unix SSH 用户名和私钥路径；
- Mihomo/Clash Verge 兼容软件或 Shadowrocket。

只有使用可选的 Cloudflare 私有订阅交付时才需要 Node.js 和 Wrangler；只有加密备份与恢复时才需要 7-Zip。

PPM 会准备整台服务器，因此主机应当专用于这套路由，不应承载现有生产工作负载。

## PPM 替你完成什么

- 建立 direct Hysteria2 route 或单跳 WireGuard relay route；
- 在一个经过验证的本地 inventory 中管理 Server、Route、Provider、Profile 和 ClientTarget；
- 生成 Mihomo/Clash 兼容文件和 Shadowrocket 导入内容；
- 可选地为每个隔离的 ClientTarget 发布一个私有 Shadowrocket 订阅；
- 对比 desired state 与有限的远程证据，报告类型化 drift；
- 以 overlap-first 方式替换基础设施，在新路线验证完成前保留旧容量；
- 创建不依赖聊天记录的加密 recovery archive。

干净 bootstrap 不默认地区、Provider、策略、客户端、订阅或 AI 厂商。agent 只收集你实际路线需要的事实。

## 对主机的影响

首次部署会准备整台 Ubuntu 主机，可能会：

- 安装 `ufw`、`unattended-upgrades`、`vnstat`、`mtr`、`curl`、`jq`、`openssl` 等软件包；
- 创建 1 GiB `/swapfile` 并写入 `/etc/fstab`；
- 设置并启用 UFW、保护 SSH，并阻止出站 SMTP 端口 25、465、587；
- 写入以 PPM 命名的 SSH、sysctl、BBR、journald、unattended-upgrades 和内核模块配置；
- 创建 PPM 服务、运行用户、WireGuard 接口、配置和凭据。

卸载会删除 PPM 拥有的服务、接口、文件和命名策略文件。软件包、swap 和无法可靠还原的旧主机级设置会保留。准确 ownership boundary 见 [Operations](OPERATIONS.md)。

## 成功结果是什么样

```text
route               direct / route-a
server              byo-ssh / Ubuntu 24.04 amd64 / dedicated
client target       mihomo / desktop-a
remote audit        healthy
drift               none
private artifact    <private>/delivery/desktop-a.yaml
```

这是合成示例。Agent 和 MCP 返回私有根相对 artifact identity，不返回 Windows drive path、用户目录、SSH key、Provider URL、token 或原始远程诊断。

## 当前支持的技术栈

- 通过 BYO SSH 访问的 Ubuntu 24.04 amd64 专用主机；
- Hysteria2 ingress；
- direct 和单跳 WireGuard relay topology；
- 可选的通用 Mihomo HTTP Provider；
- Mihomo/Clash Verge 兼容输出和 Shadowrocket 输出；
- 可选的 ClientTarget-scoped Cloudflare Worker 交付。

完整契约见 [Compatibility](docs/COMPATIBILITY.md)。如果协议、主机、renderer 或 Provider 类型没有出现在该文档和 capability discovery 中，PPM 就没有实现它。

## 隐私和授权

PPM 的确定性引擎不会上传私有状态，但云端 AI runtime 可能收到操作所需的服务器地址、SSH 用户名、key path 和选定 ID。建议使用不识别个人信息的 ID；这些参数必须留在本机时，请使用离线 runtime。

private inventory、凭据、生成的客户端文件、observed evidence 和 recovery archive 都是本地敏感数据。请使用操作系统权限和备份保护 private 目录，不要把内容粘贴到 issue 或聊天。

每次 mutation 都要通过本地 preflight；缺少上下文或存在冲突时会阻止执行。subscription token rotation 需要当前明确批准，远程修改只限 PPM ownership boundary，基础设施迁移采用 overlap-first。网络隐私限制和泄露后的处理见 [Privacy](docs/PRIVACY.md)、[Security](SECURITY.md) 和 [Threat model](docs/THREAT-MODEL.md)。

## 继续阅读

- [中文快速开始](docs/QUICKSTART.zh-CN.md)：把链接交给 agent，完成第一次安全流程。
- [中文 FAQ](docs/FAQ.zh-CN.md)：用通俗语言解释主机、AI 可见性、恢复、drift 和客户端。
- [Architecture](ARCHITECTURE.md)：对象模型和确定性边界。
- [Contributing](CONTRIBUTING.md)：开发和验证契约。
- [Releasing](docs/RELEASING.md)：版本与发布流程。

PPM 使用 [AGPL-3.0-only](LICENSE)。Vendored QR generator 的 MIT attribution 保留在 [client/vendor/NOTICE.md](client/vendor/NOTICE.md)。
