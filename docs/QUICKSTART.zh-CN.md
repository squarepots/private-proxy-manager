# 快速开始

Route Steward 帮助 AI agent 部署、检查、迁移和恢复你所管理服务器上的网络连接。把仓库交给能够读取本地文件并运行 PowerShell 的 agent，再说明你希望建立的连接。

## 1. 把仓库交给 agent

把下面的提示词粘贴到 Codex 或其他 tool-capable agent：

```text
打开 https://github.com/squarepots/route-steward 并帮我用 AI 管理自己的服务器网络。需要时先 clone。阅读 AGENTS.md 和 .agents/skills/route-steward/SKILL.md。在使用真实基础设施前运行 capability discovery 和快速本地验证。先解释专用主机要求、主机级影响和运行边界，再收集操作必需的事实；把敏感状态保存在被忽略的 private 目录；仅在 preflight 返回 ready=true 后修改。
```

agent 应运行：

```powershell
pwsh -NoProfile -File .\agent\route-steward-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

这两个命令检查仓库并验证本地 machine surface。服务器部署在 scoped preflight ready 后开始。

## 2. 准备必要信息

第一条路线需要：

- 一台专用、可重建的 Ubuntu 24.04 amd64 VPS；
- 服务器公网地址；
- 有效的 Unix SSH 用户名和本地私钥路径；
- 想配置的客户端：Mihomo/Clash Verge 兼容软件或 Shadowrocket；
- direct 或 single-hop relay topology。

建议使用 `entry-a`、`route-a`、`desktop-a` 这类不识别个人信息的 ID。

在接收服务器信息前，agent 应先解释 README 中的[主机影响与隐私边界](../README.zh-CN.md#主机影响与隐私)。

## 3. 让 RST 建立计划

正常 machine workflow 是：

```text
capabilities → 状态不存在时 bootstrap → context 和 drift
→ 收集必要事实 → 创建 desired objects
→ preflight → execute → audit 和 render
```

bootstrap 创建中性的 schema-1 状态。地区、Provider、策略、Profile、客户端、交付方式和 AI 厂商选择只从已建立的上下文进入状态。

preflight 返回准确的 missing context、conflicts、expected effects 和 authorization class。只有 `ready=true` 时 agent 才继续。

## 4. 检查结果

成功结果应说明：

- 创建了哪个 Server 和 Route；
- 使用了哪种受支持的主机与 topology 契约；
- remote audit 状态；
- ClientTarget 和私有根相对 artifact，例如 `<private>/delivery/desktop-a.yaml`；
- 是否还有 drift 或需要用户决定的事项。

脱敏结果使用 private-root-relative artifact，并将绝对用户目录、key 内容、Provider URL、交付 token、完整 live node URI 和原始 SSH 输出保留在各自的私有边界中。

## 5. 安全地继续

修改已有路线前，让 agent 先做只读 audit 和 drift。替换服务器时，RST 会在旧路线仍可用时创建并验证新容量。备份与恢复通过仓库自己的本地 7-Zip prompt 输入 archive password。

部署条件见[运行边界](OPERATING-BOUNDARY.md)，机器语义见 [Operations](../OPERATIONS.md)，已实现支持见 [Compatibility](COMPATIBILITY.md)，授权与 secret 处理见 [Security](../SECURITY.md)，通俗问答见 [中文 FAQ](FAQ.zh-CN.md)。
