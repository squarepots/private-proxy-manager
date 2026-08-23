# 快速开始

PPM 面向能够打开仓库、读取本地文件并运行 PowerShell 的 AI agent。你描述想要的路线，agent 读取仓库中的能力与安全契约，再调用 PPM 的确定性操作。

## 1. 把仓库交给 agent

把下面的提示词粘贴到 Codex 或其他 tool-capable agent：

> 打开 <https://github.com/squarepots/private-proxy-manager>，帮我建立第一条私人代理路线；需要时先 clone。阅读 AGENTS.md 和 .agents/skills/private-proxy-manager/SKILL.md。在接触任何真实基础设施前，先运行 capability discovery 和快速本地验证。向我解释使用前提和主机级影响，只收集操作必需的事实，把全部私有状态留在被忽略的 private 目录，并且只有 preflight ready 后才执行 mutation。

agent 应运行：

```powershell
pwsh -NoProfile -File .\agent\ppm-agent.ps1 capabilities
pwsh -NoProfile -File .\scripts\Validate-Local.ps1 -Quick
```

这两个命令检查仓库并验证本地 machine surface，不会部署服务器。

## 2. 准备必要信息

第一条路线需要：

- 一台专用、可重建的 Ubuntu 24.04 amd64 VPS；
- 服务器公网地址；
- 有效的 Unix SSH 用户名和本地私钥路径；
- 想配置的客户端：Mihomo/Clash Verge 兼容软件或 Shadowrocket；
- direct 或 single-hop relay topology。

建议使用 `entry-a`、`route-a`、`desktop-a` 这类不识别个人信息的 ID。不要把城市、雇主、客户或家庭网络名称写进 ID。

在接收服务器信息前，agent 应先解释 [README](../README.zh-CN.md#对主机的影响) 中的整机影响。

## 3. 让 PPM 建立计划

正常 machine workflow 是：

```text
capabilities → 状态不存在时 bootstrap → context 和 drift
→ 收集必要事实 → 创建 desired objects
→ preflight → execute → audit 和 render
```

bootstrap 创建中性的 schema-1 状态，不选择地区、Provider、策略、Profile、客户端、订阅或 AI 厂商。

preflight 返回准确的 missing context、conflicts、expected effects 和 authorization class。只有 `ready=true` 时 agent 才继续。

## 4. 检查结果

成功结果应说明：

- 创建了哪个 Server 和 Route；
- 使用了哪种受支持的主机与 topology 契约；
- remote audit 状态；
- ClientTarget 和私有根相对 artifact，例如 `<private>/delivery/desktop-a.yaml`；
- 是否还有 drift 或需要用户决定的事项。

结果不得包含绝对用户目录、key 内容、Provider URL、subscription token、完整 live node URI 或原始 SSH 输出。

## 5. 安全地继续

修改已有路线前，让 agent 先做只读 audit 和 drift。替换服务器时，PPM 会在旧路线仍可用时创建并验证新容量。备份与恢复使用仓库自己的 7-Zip prompt，不要把 archive password 放进聊天或命令参数。

机器语义见 [Operations](../OPERATIONS.md)，已实现支持见 [Compatibility](COMPATIBILITY.md)，授权与 secret 处理见 [Security](../SECURITY.md)，通俗问答见 [中文 FAQ](FAQ.zh-CN.md)。
