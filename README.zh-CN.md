# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[快速开始](docs/QUICKSTART.zh-CN.md) · [常见问题](docs/FAQ.zh-CN.md) · [兼容性](docs/COMPATIBILITY.md) · [运行边界](docs/OPERATING-BOUNDARY.md) · [安全](SECURITY.md) · [下载](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**用 AI 管理自己的服务器网络。**

Route Steward 帮你部署、检查、迁移和恢复所管理服务器上的网络连接。把 GitHub 链接交给具备工具能力的 AI agent；它可以检查支持范围、建立计划、运行 preflight、通过原生 `route-steward` 程序执行，并在结果中隐藏凭据和本地路径。

![Route Steward 将 AI 请求转化为经过验证的状态、direct 或 relay 服务器连接、线上审计，以及私有 Mihomo 或 Shadowrocket 客户端配置。](docs/assets/network-path-lifecycle.svg)

## 把链接交给 AI agent

把下面的提示词粘贴到 Codex 或其他能够读取文件并运行本地命令的 agent：

```text
打开 https://github.com/squarepots/route-steward 并帮我用 AI 管理自己的服务器网络。需要时先 clone；阅读 AGENTS.md 和 .agents/skills/route-steward/SKILL.md，然后使用 release binary 或构建 Go CLI。先运行 capabilities，再向我询问基础设施信息。解释专用主机要求和整机影响；把运行状态保存在 private 目录；每次修改前运行 preflight；只返回脱敏结果。
```

agent 会从以下命令开始：

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
```

正常使用不需要 PowerShell 或 Node.js。可以从 [Releases](https://github.com/squarepots/route-steward/releases) 下载并校验 Linux、macOS 或 Windows 二进制，也可以使用 Go 1.27 从源码安装：

```text
go install github.com/squarepots/route-steward/cmd/route-steward@latest
```

只有选择可选的 Cloudflare Worker 订阅交付时才会用到 Node.js。

## 它能交付什么

- 通过一台服务器的 direct route，或通过两台服务器的单跳 WireGuard relay；
- Hysteria2 服务器状态，以及私有 Mihomo 或 Shadowrocket 客户端输出；
- 只读线上审计和明确的 drift 分类，避免盲目覆盖；
- 保留现有连接的服务器替换流程，以及加密本地恢复；
- 同一套机器接口同时用于命令行和本地 stdio MCP。

当前服务器基线是具备授权 SSH key 访问的专用、可重建 Ubuntu 24.04 amd64 VPS。准确的协议、客户端、拓扑和可选交付方式见 [Compatibility](docs/COMPATIBILITY.md)。

## 主机影响与隐私

首次部署会准备整台主机，包括防火墙、swap、SSH、sysctl、日志、更新、软件包和监控。运行状态、密钥、生成的客户端文件和恢复归档都保存在你选择的 private 目录并被 Git 排除。云端 AI runtime 仍可能处理操作参数中的服务器地址、SSH 用户名、key path 和 ID；这些输入必须留在本机时，请使用离线 runtime。

仅使用你拥有或获授权管理的服务器、账户与网络资源。部署前请阅读 [Operations](OPERATIONS.md)、[Privacy](docs/PRIVACY.md) 和 [Security](SECURITY.md)。

Route Steward 使用 [AGPL-3.0-only](LICENSE)。Vendored QR generator 的 MIT attribution 保留在 [client/vendor/NOTICE.md](client/vendor/NOTICE.md)。
