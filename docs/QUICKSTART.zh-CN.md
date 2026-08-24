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
- Mihomo/Clash Verge 兼容、Karing、Shadowrocket，或无 GUI 的 Hysteria2 ClientTarget。

使用 `entry-a`、`route-a`、`desktop-a` 这类不识别个人信息的 ID。真实运行值只保存在你选择的 private 目录。

如果网络持续对单个 UDP 目标端口限速或过滤，agent 可以创建带 `port_hopping`（例如 `20000-20003`）的 Route。范围必须是从 `listen_port` 开始的连续 2–8 个端口，所有受支持客户端都会得到同一个范围。它不能解决网络整体封锁 UDP 的情况；启用前请阅读[可靠性研究记录](RELIABILITY-RESEARCH.md)。

## 4. 让 agent 完成流程

```text
capabilities → 状态不存在时 bootstrap → context 和 drift
→ 创建 Server / Link / Route / Profile / ClientTarget desired objects
→ preflight → execute → audit → render
```

preflight 会返回缺少的事实、conflicts、expected effects 和 authorization class。只有 `ready=true` 时才执行。已部署 Route 的线上状态出现异常或无法确定时，不会被盲目覆盖。

## 5. 检查结果

成功结果会说明代理 Route、服务器审计结果，以及 private-root-relative 客户端文件。服务器 audit 证明受管配置和服务一致。要验证真实客户端流量，请另外运行按需 health check：

```text
route-steward health --private-dir ./private --target route-a
```

health 会通过该 Route 运行固定版本的 Hysteria2 客户端，检查互联网与 DNS、比较观测出口和 desired state，并返回简短摘要。除非显式加入 `--include-public-ip`，否则不会返回准确公网 IP。

```json
{
  "route": "route-a",
  "state": "deployed",
  "audit": { "status": "in-sync" },
  "health": { "status": "healthy", "latency_ms": 82 },
  "artifact": { "relative_path": "<private>/delivery/desktop-a.yaml" }
}
```

返回数据不会包含凭据、绝对用户目录、Provider URL、subscription token、完整 node URI 或原始 SSH 输出。

使用 Karing 1.2.23.2606 或保持同一导入契约的版本时，在 Route 启用后创建并渲染 Karing target：

```text
route-steward execute --private-dir ./private --operation add-client-target --context-json '{"target_id":"karing-mobile","profile_id":"primary","renderer":"karing"}'
route-steward execute --private-dir ./private --operation render-client --target karing-mobile
```

在 Karing 中选择 Add Profile，通过本地 Clash 文件导入 `<private>/delivery/karing-mobile.yaml`。不要修改证书、混淆或路由字段；生成文件就是受支持的 artifact，并包含真实凭据。

## 6. 让 Linux 服务器或应用使用 Route

选定 Route 部署完成后，agent 可以创建无 GUI target，不需要手工编辑 Hysteria 配置：

```text
route-steward execute --private-dir ./private --operation add-client-target --context-json '{"target_id":"backend-a","profile_id":"primary","renderer":"hysteria2","route_id":"route-a","listen":"127.0.0.1:1080","ingress_family":"auto"}'
route-steward proxy --private-dir ./private --target backend-a --check
route-steward proxy --private-dir ./private --target backend-a
```

检查命令会临时启动固定版本的官方客户端，通过 Route 发起真实 HTTP 请求、核对声明的出口，然后停止。最后一条命令以前台进程运行；需要长期运行时，使用主机现有 service manager 监督。代理运行期间，应用可在同一个本地端口使用任一协议：

```text
HTTP_PROXY=http://127.0.0.1:1080 HTTPS_PROXY=http://127.0.0.1:1080 your-command
curl --proxy socks5h://127.0.0.1:1080 https://example.com/
```

监听地址必须是 IP literal loopback。一个 target 明确选择一个受管 Route；它不会隐含 Provider 组合、GUI policy、对公网/局域网监听或自动安装 system service。

## 7. 继续使用或恢复

修改现有 Route 前先让 agent 运行 audit 和 drift。`migrate-route` 会保存并恢复 overlap-first 替换事务：替代 Route 先部署并通过 health，之后才改变受影响的客户端输出；客户端切换失败会回滚，旧远端容量不会被退役。`workflow-blocked` 可以用相同旧 Route 和替代 Server 安全重试。加密恢复使用 `route-steward backup` 和 `route-steward recover`；密码只输入本地 7-Zip prompt。

进程或 agent 重启后，运行 `route-steward migrations --private-dir ./private` 可读取脱敏 checkpoint 和已记录的下一步。

真实部署前请阅读 [Compatibility](COMPATIBILITY.md)、[Operations](../OPERATIONS.md)、[Privacy](PRIVACY.md)、[Security](../SECURITY.md) 和[运行边界](OPERATING-BOUNDARY.md)。
