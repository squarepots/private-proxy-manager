# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[快速开始](docs/QUICKSTART.zh-CN.md) · [常见问题](docs/FAQ.zh-CN.md) · [兼容性](docs/COMPATIBILITY.md) · [运行边界](docs/OPERATING-BOUNDARY.md) · [安全](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**用 AI 管理自己的服务器网络。**

Route Steward 帮你部署、检查、迁移和恢复所管理服务器上的网络连接。你提供服务器、账户与管理授权；Route Steward 为具备工具能力的 AI agent 提供一套可重复、经过验证的本地操作方式。

![Synthetic Route Steward 示意图：区分由 AI 操作的控制平面，以及经过 Entry-A、可选 Relay-A 和 WireGuard relay 的 direct/relay 流量路径。](docs/assets/network-path-lifecycle.svg)

## 从 AI agent 开始

把下面的提示词粘贴到 Codex 或其他能够读取文件、运行 PowerShell 的 agent：

```text
打开 https://github.com/squarepots/route-steward 并帮我用 AI 管理自己的服务器网络。需要时先 clone；阅读 AGENTS.md 和 repository Skill，检查 capabilities，并运行快速本地验证。向我索取基础设施信息前，先解释专用主机要求、主机级影响和运行边界。敏感状态保存在 private 目录；修改前运行 preflight；只返回脱敏结果。
```

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

## 需要准备什么

- 一台安装 PowerShell 7、可供具备工具能力的 AI agent 操作的本地电脑；
- 一台或两台专用、可重建的 Ubuntu 24.04 amd64 服务器；
- 获得授权的 SSH 访问、Unix 用户名和私钥路径；
- Mihomo/Clash Verge 兼容软件或 Shadowrocket。

Route Steward 会准备整台服务器，因此每台受管主机必须专用于这套网络配置。

## Route Steward 能做什么

它会生成并验证服务器与客户端配置、检查线上状态、在保留现有连接的同时协助替换基础设施，并创建加密恢复归档。

[Compatibility](docs/COMPATIBILITY.md) 完整列出当前支持的主机、协议、客户端、拓扑和可选 Cloudflare 交付方式。

## 主机影响与隐私

部署会修改整机的防火墙、swap、SSH、系统、日志、更新和监控设置。敏感状态与生成文件保存在选定的本地 private 目录；每次修改都必须先通过 preflight。部署前请阅读 [Operations](OPERATIONS.md)、[Privacy](docs/PRIVACY.md) 和 [Security](SECURITY.md)。

仅使用你拥有或获授权管理的服务器、账户与网络资源。完整政策见[运行边界](docs/OPERATING-BOUNDARY.md)。

Route Steward 使用 [AGPL-3.0-only](LICENSE)。Vendored QR generator 的 MIT attribution 保留在 [client/vendor/NOTICE.md](client/vendor/NOTICE.md)。
