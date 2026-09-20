# MapleBridge

[English](README.md) | [简体中文](README.zh-CN.md)

一个用于玩 GMS（Global MapleStory）的小型、易维护的 WireGuard 网关，让日本本地 Windows PC 通过 AWS Lightsail Oregon 使用美国网络出口。游戏仍在本地 Windows 上运行。

## 设计

- PowerShell 负责客户端管理和部署编排。
- CloudFormation 管理 AWS 资源，独立脚本负责 Linux 配置。
- 使用官方 WireGuard 客户端；计划默认仅将 GMS 相关域名的流量转发到网关。
- 支持可重复部署、明确的故障诊断和重启恢复。

## 开发

本公开仓库处于初始化阶段，尚未实现部署和客户端命令。开发约定见 [AGENTS.md](AGENTS.md) 和[开发流程](docs/harness.md)。
