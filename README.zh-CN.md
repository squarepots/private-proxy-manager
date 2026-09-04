# Route Steward

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Español](README.es.md) · [Português (Brasil)](README.pt-BR.md)

[快速开始（英文）](docs/QUICKSTART.md) · [常见问题（英文）](docs/FAQ.md) · [兼容性](docs/COMPATIBILITY.md) · [运行边界](docs/OPERATING-BOUNDARY.md) · [安全](SECURITY.md) · [下载](https://github.com/squarepots/route-steward/releases)

[![Validation](https://github.com/squarepots/route-steward/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/route-steward/actions/workflows/ci.yml)

**用 AI 智能体在自己的服务器上搭建和管理私有代理。**

把这个仓库交给 AI 智能体，再描述你想要的代理。Route Steward 提供命令、安全检查、服务器配置、客户端文件、审计和恢复流程。

## 把链接交给 AI 智能体

把下面的提示词粘贴到 Codex 或其他能够读取文件并运行本地命令的 AI 智能体：

```text
打开仓库 https://github.com/squarepots/route-steward 并帮我在自己控制的服务器上搭建和管理私有代理。阅读 AGENTS.md 和 .agents/skills/route-steward/SKILL.md，使用适合这台电脑的 Route Steward 发布版本，并先运行 route-steward capabilities。
```

安装方法和前提条件见[快速开始](docs/QUICKSTART.md)。

## 它能交付什么

- 通过一台服务器运行 Hysteria2 私有代理，或通过两台服务器组成 WireGuard 中继；
- 可选的端口跳跃，应对网络对个别 UDP 端口的限速或过滤；
- 为 Mihomo/Clash Verge 兼容应用、Karing、Shadowrocket 和无界面 Hysteria2 生成私有客户端文件；
- 服务器审计、配置偏差报告和按需真实流量检查；
- 可恢复的服务器替换流程，在切换客户端前先验证新路径；
- 加密的本地备份与恢复；
- 通过命令行或本地标准输入输出 MCP 使用的 JSON 命令。

当前服务器基线是可通过 SSH 密钥访问的专用、可重建 Ubuntu 24.04 amd64 VPS。支持的协议、客户端、拓扑和交付方式见[兼容性说明](docs/COMPATIBILITY.md)。

## 主机影响与隐私

首次部署会修改整台主机的防火墙、交换空间、SSH、系统参数、日志、更新、软件包和监控配置。请使用专用且可重建的服务器。

密钥、运行状态、生成的客户端文件和恢复归档都保存在你选择的私有目录中，并被 Git 排除。云端 AI 服务仍可能接收执行操作所需的服务器信息；如果这些信息必须留在本机，请使用离线运行环境。

仅使用你拥有或获授权管理的服务器、账户与网络资源。部署前请阅读[操作说明](OPERATIONS.md)、[隐私说明](docs/PRIVACY.md)和[安全说明](SECURITY.md)。

Route Steward 使用 [AGPL-3.0-only](LICENSE) 许可证。内置二维码生成器的 MIT 署名见 [client/vendor/NOTICE.md](client/vendor/NOTICE.md)。
