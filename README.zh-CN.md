# Private Proxy Manager（PPM）

[English](README.md) · [快速开始](docs/QUICKSTART.zh-CN.md) · [常见问题](docs/FAQ.zh-CN.md) · [兼容性](docs/COMPATIBILITY.md) · [安全](SECURITY.md) · [AGPL-3.0-only](LICENSE)

[![Validation](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/squarepots/private-proxy-manager/actions/workflows/ci.yml)

Private Proxy Manager（PPM）是一个本地优先的自建代理路由管理层。它把目标状态和凭据保存在本地私有目录，通过 SSH 部署受支持的 Hysteria2/WireGuard 服务端组件，生成客户端配置，并检查实际状态是否偏离计划。

PPM 不是 VPN 服务、代理客户端、网页面板或服务器市场。它负责准备基础设施和客户端文件；Mihomo/Clash 兼容客户端与 Shadowrocket 负责在设备上承载流量。

## 适合谁

PPM 面向已经拥有，或愿意准备一台**专用、可重建的 Ubuntu 24.04 amd64 VPS**并具备 SSH 访问能力的自托管用户。它适合手工配置容易出错、需要维护多条路线或多个设备配置、或者需要替换服务器但不想立即中断现有路线的场景。

PPM 不适合共享生产主机、手机-only 用户、消费级 VPN 订阅、自动购买 VPS、多用户计费、流量统计、匿名保证，或任意协议和任意客户端。

## 开始前必须知道：它会修改主机

当前服务端安装是一次整机准备步骤，只应在可以重建的专用主机上执行。部署可能会：

- 安装 `ufw`、`unattended-upgrades`、`vnstat`、`mtr`、`curl`、`jq`、`openssl` 等软件包；
- 创建 1 GiB `/swapfile` 并写入 `/etc/fstab`；
- 设置并启用 UFW，限制 SSH，并阻止出站 SMTP 端口 25、465、587；
- 写入 SSH、sysctl、BBR、journald、unattended-upgrades 和内核模块配置；
- 创建 PPM 服务、运行用户、WireGuard 接口、配置文件和生成的凭据。

卸载会删除 PPM 自己拥有的文件、服务、接口和命名策略文件，但**不会**恢复原先的 UFW 默认值、删除 swap、撤销软件包安装，或猜测并恢复主机原有状态。使用前请阅读 [Operations](OPERATIONS.md)。

## 给 AI agent 的第一句话

把下面的话交给能够读取本地文件并调用本地工具的 agent：

> 阅读 PPM 仓库和 capability surface。我想在专用 Ubuntu 24.04 amd64 主机上建立 direct route。先告诉我所需上下文和所有主机级影响；在 preflight ready 且我明确确认重要决策前不要部署。凭据和生成的客户端文件必须留在选定的私有目录。

agent 应先检查 capability、在需要时创建 neutral private state、收集服务器和客户端信息、运行 preflight，并解释预期影响。干净 bootstrap 不会默认选择地区、Provider、Profile、客户端、订阅或模型厂商。

下面是合成的成功结果形状，不是真实服务器或用户配置：

```text
目标路线            direct / entry-a
服务器契约          byo-ssh / Ubuntu 24.04 amd64 / dedicated
客户端文件          Mihomo YAML、Shadowrocket 离线导入
远程审计            healthy
漂移                none
私有输出            <private>/delivery/...
```

## PPM 管理什么

- 固定版本和校验值的 Hysteria2 ingress；
- direct route 与单跳 WireGuard entry-to-exit relay route；
- 通过 SSH 接入的自建专用 Ubuntu 服务器；
- 可选的 Mihomo HTTP Provider（URL 只存本地 secret）；
- Mihomo/Clash 兼容输出与 Shadowrocket 输出；
- 按 ClientTarget 隔离的 Cloudflare Worker 私有订阅交付；
- desired state、观察审计、类型化 drift、重叠优先迁移和本地加密恢复。

**Profile** 负责可复用的 Route/Provider/策略选择，**ClientTarget** 负责具体渲染器和交付身份。目标状态使用 inventory schema `1`；`version.txt` 中的产品版本是独立的版本域。

## 隐私和 AI 边界

PPM 的确定性引擎不会主动上传私有状态，但你选择的 AI runtime 可能会收到 prompt 和工具参数。根据操作不同，参数可能包括服务器 IP、SSH 用户名、本地 key 路径和稳定 ID。Agent 输出会把内部绝对 artifact 路径替换为 `<private>/delivery/client.yaml` 这样的私有根相对路径，但“local-first”不等于模型看不到任何元数据。需要更强本地边界时，请使用离线模型/runtime。

inventory、凭据、Provider URL、订阅 token、生成的客户端文件、审计证据和 recovery archive 默认是本地明文/私有状态；请自行管理操作系统权限、备份和恢复。不要提交或粘贴到 issue。PPM 不承诺匿名，也不保证 ISP、VPS、Cloudflare 或目标服务看不到其职责范围内的元数据。

详见 [隐私边界](docs/PRIVACY.md)、[Security](SECURITY.md) 和 [Threat Model](docs/THREAT-MODEL.md)。

## 支持范围

准确的支持矩阵见 [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)。当前基线是专用 Ubuntu 24.04 amd64 主机、Hysteria2 ingress、单跳 WireGuard relay、Mihomo/Clash 兼容输出和 Shadowrocket 输出。多跳、ARM64、任意 Linux 发行版、任意 renderer、自动云资源配置和 hosted PPM control plane 都不在支持范围内。

## 继续阅读

从 [中文快速开始](docs/QUICKSTART.zh-CN.md) 或 [中文 FAQ](docs/FAQ.zh-CN.md) 开始。命令、operation ID、JSON key 和 schema 名称保持英文，以便与机器契约一致。`AGENTS.md`、repository Skill、capability discovery、schema 和确定性代码共同构成技术契约。

PPM 使用 [AGPL-3.0-only](LICENSE)。vendored QR generator 仍保留其 MIT attribution，见 [client/vendor/NOTICE.md](client/vendor/NOTICE.md)。
