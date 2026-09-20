# MapleBridge

[English](README.md) | [简体中文](README.zh-CN.md)

A small, maintainable WireGuard gateway for playing GMS (Global MapleStory) on a Windows PC in Japan through a US internet exit on AWS Lightsail in Oregon. The game runs locally on Windows.

## Design

- PowerShell for client management and deployment orchestration.
- CloudFormation for AWS infrastructure; separate scripts for Linux configuration.
- Official WireGuard clients; planned default routing forwards only traffic for GMS-related domains through the gateway.
- Repeatable deployment, actionable diagnostics, and recovery after reboot.

## Development

This public repository is in initial setup. Deployment and client commands are not implemented yet. See [AGENTS.md](AGENTS.md) and the [development workflow](docs/harness.md) for development guidance.
