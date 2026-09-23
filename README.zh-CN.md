# MapleBridge

[English](README.md) | [简体中文](README.zh-CN.md)

MapleBridge 让 GMS（Global MapleStory）继续在本地 Windows 上运行，只把 GMS、Nexon Launcher 和相关网页流量经由 AWS Lightsail Oregon 的 WireGuard 网关转发，其他流量保持直连。

## 设计

- 复用 Clash Verge Rev 界面和自带的 Mihomo 内核，不另写 GUI。
- Windows 端的安装、状态检查和 AWS 部署编排使用 PowerShell。
- 网关和自动维护基础设施使用 CloudFormation，网关通过 Systems Manager 管理，无需开放公网 SSH。
- 正常更新保留本地和服务器 WireGuard 密钥。
- Mihomo 运行时，匹配流量不会因为规则配置回退到直连；Clash Verge 或 Mihomo 整体停止后不提供系统级 kill switch。

## 安装

先按照 [Windows 前置条件](docs/windows-prerequisites.md) 和 [IAM 引导](docs/iam-bootstrap.md) 安装工具并配置专用 AWS profile，然后运行：

```powershell
.\scripts\windows\Install-MapleBridge.ps1 -ProfileName 'maplebridge' -ConfirmPaidDeployment
```

这个命令会创建或复用客户端密钥和 AWS 资源，通过 SSM 配置网关，生成并校验 Mihomo 配置，备份相关 Clash Verge 文件，激活并重新加载 MapleBridge，运行诊断状态检查，并启用默认的每月安全维护窗口。生成的配置含有私钥，只保存在被忽略的本地状态目录。

以后可以在不重启 Clash Verge 的情况下运行诊断及当月流量快照：

```powershell
.\scripts\windows\Update-MapleBridgeStatus.ps1 -ProfileName 'maplebridge'
```

命令输出及被忽略的 `state/status.json` 会保存当月 Lightsail 流量快照、固定 IP、健康摘要和 WireGuard 握手详情。MapleBridge 不再把这些快照写到 Clash Verge 首页卡片，因为不维护客户端私有构建或常驻 localhost 订阅服务就无法从那里刷新。详见[状态与 Clash 集成](docs/status.md)。

自动补丁状态和卸载方法见[自动安全维护](docs/maintenance.md)与[卸载清理](docs/removal.md)。删除 AWS 或本地密钥始终需要独立的显式开关和精确目标确认。

## 当前状态

选择性分流配置已经在 Windows、Clash Verge Rev 2.5.5、真实 Oregon Lightsail 网关上验证，WireGuard 握手正常，Nexon Launcher 可用，并成功进行了数分钟 GMS 游戏。现有堆栈幂等重装、真实 Lightsail 重启恢复，以及隔离环境的全新创建—配置—使用—删除生命周期也已通过真实 Nexon 请求和新握手验证。面向用户的卸载命令和每月 Ubuntu 自动安全维护已经实现。支付服务商分流仍属实验性规则。作为个人非商业项目，Windows 重启和主动网关故障测试已明确不做。CI 会运行离线 Windows 与 Linux 检查；首次定时补丁执行仍待验证。详见[开发计划](docs/development-plan.md)和[恢复记录](docs/observations/recovery.md)。

开发与离线测试约定见 [AGENTS.md](AGENTS.md) 和 [harness](docs/harness.md)，AWS 费用见[费用说明](docs/costs.md)。
