# 常见问题

## Route Steward 是做什么的？

Route Steward 帮助 AI agent 在你控制的 VPS 上搭建和管理私有代理。它通过可检查、带 preflight 的流程生成服务器配置和私有客户端配置。

## 开始前需要什么？

你需要在 Linux、macOS 或 Windows 电脑上安装 Route Steward release binary，并使用具备工具能力的 AI agent；还需要一台具备 SSH key 访问的专用、可重建 Ubuntu 24.04 amd64 VPS，以及 Mihomo/Clash Verge 兼容软件或 Shadowrocket。relay route 需要两台 VPS。正常使用不需要 PowerShell 或 Node.js。

## 如何安装？

从 [GitHub Releases](https://github.com/squarepots/route-steward/releases) 下载与你的操作系统和架构对应的压缩包，使用 `SHA256SUMS` 校验，再把程序放入 `PATH`。开发者可以使用 Go 1.27 运行 `go install github.com/squarepots/route-steward/cmd/route-steward@latest`。

## 为什么必须使用专用主机？

首次安装会准备整台主机，改变 UFW defaults、swap/fstab、SSH、sysctl、journald、软件包、unattended-upgrades、SMTP egress 和 vnstat 状态。使用全新的专用主机可以明确这些影响，并把无关生产工作负载留在修改范围之外。

## 可以只把 GitHub 链接交给 AI agent 吗？

可以。使用 [中文快速开始](QUICKSTART.zh-CN.md) 中的提示词。能够调用本地工具的 agent 可以 clone 仓库、阅读说明、获取或构建程序、检查机器可读 capabilities、解释使用前提，然后只收集路线需要的最少信息。

## AI 模型会看到服务器信息吗？

可能会。操作参数可能包含服务器地址、SSH 用户名、本地 key path 和选定 ID。RST 会脱敏返回结果，但云端 runtime 仍会处理完成操作所需的输入。建议使用不识别个人信息的 ID；输入必须留在本机时，请使用离线 runtime。

## 私有文件如何保护？

inventory、凭据、生成的客户端文件、observed evidence 和 recovery archive 都留在选定的本地 private 目录，并被 Git 排除。除非操作系统、磁盘或备份层提供加密，否则它们是明文。便携式 recovery archive 通过本地 7-Zip password prompt 加密。

## 路线发生意外变化怎么办？

只读 audit 会记录有限证据，drift 会报告类别。对于 drifted 或 undetermined 的已部署路线，RST 会先阻止覆盖，直到差异得到解释且受支持的操作通过 preflight。

## audit 能证明代理可以传输互联网流量吗？

不能。audit 会检查受支持的服务器配置、服务、监听端口、relay 状态和服务器侧出口证据。单独的 `health` 操作会运行固定版本的真实 Hysteria2 客户端，通过 Route 发起互联网和 hostname 请求，将观测到的公网出口与 desired state 比较，并在已声明时报告 IPv4/IPv6。配置 audit 与端到端连接 health 是两个不同结果。

## health 会暴露公网 IP 或持续监控吗？

不会。health 是按需检查，不是监控服务。它会通过代理访问 ipify 地址 endpoint 和 Cloudflare trace endpoint，只保存有限的本地证据。普通 agent 结果只报告观测出口是否匹配；只有显式请求时才返回准确公网 IP。由于当前没有稳定、安全的端到端测量方法，packet loss 会明确返回 unsupported，而不是给出不可靠数字。

## 替换服务器如何避免中断？

`migrate-route` 会保存 overlap-first 迁移事务。它创建或复用替代容量，在不改变当前客户端输出的情况下完成部署，要求真实 Hysteria2 流量 health 为 healthy，之后才切换并验证受影响的 ClientTarget。部署、health、渲染或 subscription 发布失败会返回 `workflow-blocked`；以相同旧 Route 和替代 Server 重试即可确定性恢复。旧远端容量绝不会自动退役，销毁仍是之后单独、显式的破坏性操作。

## 支持哪些主机、topology 和客户端？

见 [Compatibility](COMPATIBILITY.md)。运行时以机器可读 capability response 为准；只有文档明确列出且仓库实现的项目属于支持范围。

## 可选 subscription Worker 做什么？

它通过隔离的 Cloudflare Worker endpoint 交付一个私有 Shadowrocket ClientTarget 配置。bearer token 按 target 隔离，UTF-8 配置正文上限为 5120 bytes；Cloudflare 属于这条交付路径的隐私边界。

## 适用哪些运行条件？

每个部署使用操作者拥有或经资源所有者授权管理的服务器、账户和网络资源。所选 topology 应符合适用法律、运营商要求、服务商条款和组织策略。完整说明见[运行边界](OPERATING-BOUNDARY.md)。
