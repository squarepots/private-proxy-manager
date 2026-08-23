# 常见问题

## RST 解决什么问题？

Route Steward 把一组可通过 SSH 访问的服务器组织成可重复维护的自托管网络路径。它通过一个声明式生命周期统一管理 topology、凭据、客户端输出、远程审计、drift、迁移和恢复。

## 开始前需要什么？

你需要一台安装 PowerShell 7、可供 tool-capable AI agent 操作的本地电脑，一台具备 SSH key 访问的专用、可重建 Ubuntu 24.04 amd64 VPS，以及 Mihomo/Clash Verge 兼容软件或 Shadowrocket。relay route 需要两台 VPS。

## 为什么必须使用专用主机？

首次安装会准备整台主机，改变 UFW defaults、swap/fstab、SSH、sysctl、journald、软件包、unattended-upgrades、SMTP egress 和 vnstat 状态。使用全新的专用主机可以明确这些影响，并把无关生产工作负载留在修改范围之外。

## 可以只把 GitHub 链接交给 AI agent 吗？

可以。使用 [中文快速开始](QUICKSTART.zh-CN.md) 中的提示词。能够调用本地工具的 agent 可以 clone 仓库、阅读说明、检查机器可读 capabilities、运行本地验证、解释使用前提，然后只收集路线需要的最少信息。

## AI 模型会看到服务器信息吗？

可能会。操作参数可能包含服务器地址、SSH 用户名、本地 key path 和选定 ID。RST 会脱敏返回结果，但云端 runtime 仍会处理完成操作所需的输入。建议使用不识别个人信息的 ID；输入必须留在本机时，请使用离线 runtime。

## 私有文件如何保护？

inventory、凭据、生成的客户端文件、observed evidence 和 recovery archive 都留在选定的本地 private 目录，并被 Git 排除。除非操作系统、磁盘或备份层提供加密，否则它们是明文。便携式 recovery archive 通过本地 7-Zip password prompt 加密。

## 路线发生意外变化怎么办？

只读 audit 会记录有限证据，drift 会报告类别。对于 drifted 或 undetermined 的已部署路线，RST 会先阻止覆盖，直到差异得到解释且受支持的操作通过 preflight。

## 替换服务器如何避免中断？

迁移采用 overlap-first：创建并部署替代容量、完成审计、更新客户端输出并确认可用；在整个验证期间保留现有路线。旧的外部容量之后再单独处理。

## 支持哪些主机、topology 和客户端？

见 [Compatibility](COMPATIBILITY.md)。运行时以机器可读 capability response 为准；只有文档明确列出且仓库实现的项目属于支持范围。

## 可选 subscription Worker 做什么？

它通过隔离的 Cloudflare Worker endpoint 交付一个私有 Shadowrocket ClientTarget 配置。bearer token 按 target 隔离，UTF-8 配置正文上限为 5120 bytes；Cloudflare 属于这条交付路径的隐私边界。

## 适用哪些运行条件？

每个部署使用操作者拥有或经资源所有者授权管理的服务器、账户和网络资源。所选 topology 应符合适用法律、运营商要求、服务商条款和组织策略。完整说明见[运行边界](OPERATING-BOUNDARY.md)。
