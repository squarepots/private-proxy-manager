# 常见问题

## PPM 是 VPN 服务吗？

不是。PPM 管理受支持的自建基础设施并生成客户端配置；Mihomo/Clash 兼容客户端或 Shadowrocket 承载流量。

## 可以用共享服务器吗？

当前不支持。支持基线是专用、可重建的 Ubuntu 24.04 amd64 主机，因为安装会改变整机的 UFW、swap/fstab、SSH、sysctl、journald、软件包和 unattended-upgrades 状态。

## PPM 会购买或删除 VPS 吗？

不会。云资源购买和破坏性服务器退役不属于当前确定性核心，需要单独的外部决策和明确授权。

## PPM 会连接银行或移动资金吗？

不会。PPM 是代理基础设施工具，不提供 hosted control plane、计费、流量分析或账户管理。

## AI 模型会看到我的服务器信息吗？

可能会。执行操作需要的工具参数可能包含 IP、SSH 用户名、本地 key 路径和选定 ID。PPM 会脱敏返回的 artifact，但 local-first 不等于云模型完全看不到元数据。需要完全本地的模型边界时，请使用离线 runtime。

## 私有文件默认加密吗？

不是。私有状态默认是本地明文，依靠操作系统权限、备份策略和 recovery 流程保护。PPM 支持创建加密 recovery archive。

## PPM 保证匿名吗？

不保证。ISP、VPS、可选的 Cloudflare 交付层和目标服务都会看到其职责范围内的网络元数据。

## 路线发生 drift 怎么办？

PPM 会返回类型化证据，不会静默自愈或覆盖不确定的远程状态。修复必须对应支持的 operation、通过 preflight，并符合用户授权。

## 支持哪些系统和客户端？

见 [Compatibility](COMPATIBILITY.md)。当前基线是 Ubuntu 24.04 amd64、Hysteria2、单跳 WireGuard、Mihomo/Clash 兼容输出和 Shadowrocket 输出。外部文档不会自动增加 PPM 支持。

## 订阅 Worker 做什么？

它是可选的、面向一个 Shadowrocket ClientTarget 的私有配置交付端点，不是 PPM 数据库或代理数据面。当前 Worker secret payload 的 UTF-8 上限是 5120 bytes，超出会在发布前本地失败。
