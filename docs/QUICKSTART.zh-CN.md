# 快速开始

Route Steward 帮助 AI agent 在你控制的 VPS 上搭建和管理私有代理。正常入口是一个可运行于 Linux、macOS 和 Windows 的原生程序。

## 1. 安装程序

从 [GitHub Releases](https://github.com/squarepots/route-steward/releases) 下载与你的操作系统和架构对应的压缩包，使用 `SHA256SUMS` 校验，然后把 `route-steward`（Windows 为 `route-steward.exe`）放入 `PATH`。

开发者也可以使用 Go 1.27 从源码安装：

```text
go install github.com/squarepots/route-steward/cmd/route-steward@latest
```

正常使用不需要 PowerShell 或 Node.js。只有选择可选的 Cloudflare Worker 订阅发布时才需要 Node.js。

## 2. 把仓库交给 agent

把下面的提示词粘贴到 Codex 或其他能够读取文件并运行本地命令的 agent：

```text
打开 https://github.com/squarepots/route-steward 并帮我在自己的服务器上搭建和管理私有代理。需要时先 clone；阅读 AGENTS.md 和 .agents/skills/route-steward/SKILL.md，然后使用 release binary 或构建 Go CLI。先运行 capabilities，再向我询问基础设施信息。解释专用主机要求和整机影响；把运行状态保存在 private 目录；每次修改前运行 preflight；只返回脱敏结果。
```

agent 应从以下命令开始：

```text
route-steward capabilities
route-steward bootstrap --private-dir ./private
route-steward context --private-dir ./private
route-steward drift --private-dir ./private
```

在源码目录中，也可以使用 `go run ./cmd/route-steward <command>` 调用同一接口。

## 3. 准备第一个私有代理

agent 会按照 capability discovery 声明的字段询问：

- direct route 需要一台专用、可重建的 Ubuntu 24.04 amd64 VPS；relay 需要两台；
- 每台服务器的公网地址、有效 Unix SSH 用户名和本地 private-key path；
- 希望使用 direct 还是单跳 relay 连接；
- Mihomo/Clash Verge 兼容或 Shadowrocket ClientTarget。

使用 `entry-a`、`route-a`、`desktop-a` 这类不识别个人信息的 ID。真实运行值只保存在你选择的 private 目录。

## 4. 让 agent 完成流程

```text
capabilities → 状态不存在时 bootstrap → context 和 drift
→ 创建 Server / Link / Route / Profile / ClientTarget desired objects
→ preflight → execute → audit → render
```

preflight 会返回缺少的事实、conflicts、expected effects 和 authorization class。只有 `ready=true` 时才执行。已部署 Route 的线上状态出现异常或无法确定时，不会被盲目覆盖。

## 5. 检查结果

成功结果会说明代理 Route、服务器审计结果，以及 private-root-relative 客户端文件。服务器 audit 只能证明受管配置和服务一致，还不是真正的客户端端到端流量测试。

```json
{
  "route": "route-a",
  "state": "deployed",
  "audit": { "status": "in-sync" },
  "artifact": { "relative_path": "<private>/delivery/desktop-a.yaml" }
}
```

返回数据不会包含凭据、绝对用户目录、Provider URL、subscription token、完整 node URI 或原始 SSH 输出。

## 6. 继续使用或恢复

修改现有 Route 前先让 agent 运行 audit 和 drift。当前 `migrate-route` capability 会给出 overlap-first 步骤；agent 仍须逐步执行和确认，并保留旧容量。加密恢复使用 `route-steward backup` 和 `route-steward recover`；密码只输入本地 7-Zip prompt。

真实部署前请阅读 [Compatibility](COMPATIBILITY.md)、[Operations](../OPERATIONS.md)、[Privacy](PRIVACY.md)、[Security](../SECURITY.md) 和[运行边界](OPERATING-BOUNDARY.md)。
