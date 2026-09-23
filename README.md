# MapleBridge

[English](README.md) | [简体中文](README.zh-CN.md)

MapleBridge runs GMS (Global MapleStory) locally on Windows while selectively routing GMS, Nexon Launcher, and related web traffic through a WireGuard gateway on AWS Lightsail in Oregon. Unrelated traffic remains direct.

## Design

- Reuse the Clash Verge Rev UI and bundled Mihomo core; MapleBridge does not ship another GUI.
- Use PowerShell for Windows setup, status, and AWS deployment orchestration.
- Use CloudFormation for the gateway and automatic-maintenance infrastructure, and Systems Manager for gateway management; public SSH is not required.
- Preserve local and server WireGuard keys during ordinary updates.
- Avoid rule-level direct fallback for matched traffic while Mihomo is running. This is not a system-wide kill switch if Clash Verge or Mihomo stops.

## Install

Install the prerequisites and configure the dedicated AWS profile as described in [Windows prerequisites](docs/windows-prerequisites.md) and [IAM bootstrap](docs/iam-bootstrap.md). Then run:

```powershell
.\scripts\windows\Install-MapleBridge.ps1 -ProfileName 'maplebridge' -ConfirmPaidDeployment
```

The command creates or reuses client keys and AWS resources, configures the gateway through SSM, generates and validates the Mihomo profile, backs up the relevant Clash Verge files, activates MapleBridge, reloads Clash Verge, runs a diagnostic status check, and enables the default monthly security-maintenance window. The generated profile contains a private key and remains under ignored local state.

Run the diagnostic and current-month traffic snapshot later without restarting Clash Verge:

```powershell
.\scripts\windows\Update-MapleBridgeStatus.ps1 -ProfileName 'maplebridge'
```

The command output and ignored `state/status.json` contain the current-month Lightsail traffic snapshot, static IP, health summary, and WireGuard handshake details. MapleBridge deliberately does not place these snapshots on the Clash Verge home card because they cannot be refreshed there without a custom client build or a persistent localhost subscription service. See [status and Clash integration](docs/status.md).

Inspect automatic patch status or remove MapleBridge with the commands documented in [automatic security maintenance](docs/maintenance.md) and [removal](docs/removal.md). AWS deletion and local-key deletion always require separate explicit switches and exact target confirmation.

## Project status

The selective profile has been validated on Windows with Clash Verge Rev 2.5.5, a live Oregon Lightsail gateway, a successful WireGuard handshake, Nexon Launcher, and several minutes of GMS gameplay. Existing-stack reinstall, live Lightsail reboot recovery, and an isolated clean create-configure-use-delete lifecycle have also been verified with real Nexon requests and fresh handshakes. A user-facing removal command and automatic monthly Ubuntu security maintenance are implemented. Payment-provider routing remains experimental. Windows reboot and deliberate gateway-loss testing were explicitly omitted for this personal, non-commercial deployment. Offline Windows and Linux checks run in CI; the first scheduled patch execution remains pending. See the [development plan](docs/development-plan.md) and [recovery observations](docs/observations/recovery.md).

Development and offline test rules are in [AGENTS.md](AGENTS.md) and [the harness](docs/harness.md). AWS pricing is described in [costs](docs/costs.md).
