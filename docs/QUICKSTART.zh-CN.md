# 快速开始

PPM 通过能够读取本地文件、调用本地工具的 agent 使用。下面的命令和 operation 名称主要用于检查与验证，不是要求普通用户学习的第二套产品界面。

## 使用前提

- 一台可重建的专用 Ubuntu 24.04 amd64 VPS；
- 有效的 SSH 用户名和 key；
- 本地 PowerShell 7，用于 PPM machine surface；
- 需要生成客户端文件时，准备受支持的 Mihomo/Clash 兼容客户端或 Shadowrocket；
- 使用可选订阅 Worker 时才需要 Node.js 和 Wrangler；
- 创建或恢复加密 recovery archive 时才需要 7-Zip。

连接服务器前先读 [README 的主机影响说明](../README.zh-CN.md#开始前必须知道它会修改主机)。不要使用共享生产主机。

## 先让 agent 检查

把这句话交给本地 tool-capable agent：

> 检查 PPM capabilities 和当前私有状态。我想在专用 Ubuntu 24.04 amd64 主机上建立 direct route 或 single-hop relay。执行任何 mutation 前，先告诉我缺少的上下文、主机级影响和授权要求。

agent 应使用 `agent/ppm-agent.ps1`，只在私有状态不存在时 bootstrap，并且只有 scoped preflight 返回 `ready=true` 才能执行 mutation。

## 正常流程

```text
capabilities → bootstrap（需要时）→ context/drift
→ 收集服务器/客户端事实 → 创建 desired objects
→ preflight → execute → audit/render → 解释结果
```

建议使用 `entry-a`、`route-a`、`mobile-a` 这类稳定且不识别个人信息的 ID。不要把城市、雇主、客户、家庭网络等私有上下文写入 ID。

## 成功结果

结果应说明服务器契约、Route、ClientTarget、审计状态和 `<private>/delivery/mobile.html` 这样的私有根相对 artifact 名称。不得返回 Windows drive 路径、SSH key 内容、订阅 token、Provider URL 或原始远程诊断。

## 出现问题时

停在 typed drift 或 preflight 结果，不要把 drift 当作自动修复许可。让 agent 解释具体类别并提出最小支持操作。迁移时保留旧路线，直到新路线的访问和渲染都验证成功。

恢复时将内容恢复到新的干净私有目录，使用仓库 recovery workflow，并把 archive 与密码视为同一个敏感组合。详见 [Operations](../OPERATIONS.md)、[Security](../SECURITY.md) 和 [中文 FAQ](FAQ.zh-CN.md)。
