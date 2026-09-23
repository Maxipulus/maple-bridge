# Status and Clash Verge integration

`Install-MapleBridgeClashProfile.ps1` validates the generated profile with the Clash Verge bundled Mihomo core before copying it. It backs up `profiles.yaml` and every MapleBridge-owned profile file beneath the Clash data directory, preserves unrelated profiles, installs the local profile as `LMapleBridge`, and makes it current. Existing enhancement files are preserved.

`Update-MapleBridgeStatus.ps1` prints a live diagnostic summary and refreshes ignored `state/status.json`:

```powershell
.\scripts\windows\Update-MapleBridgeStatus.ps1 -ProfileName 'maplebridge'
```

The command checks:

- Lightsail instance state and recent `StatusCheckFailed` metrics;
- SSM managed-node availability;
- gateway firewall, WireGuard service, IPv4 forwarding, and latest handshake through an SSM read-only shell command;
- local Clash Verge and Mihomo processes and the TUN adapter.

Use `-SkipGatewayCheck` to omit SSM Run Command. The status command does not modify or restart Clash Verge.

## Clash Verge 2.5.5 UI boundary

The home profile card renders only the profile name, remote source when present, update time, traffic values, expiration, and progress. It does not render arbitrary health fields.

The update icon and update-time row on the home card call Clash Verge's internal `update_profile` command. For a local profile such as MapleBridge, that command reloads the profile but cannot launch PowerShell or query AWS. Clash Verge exposes no configuration hook for adding a custom home-card button or command.

Making that click query AWS would require either maintaining a custom Clash Verge build or converting MapleBridge into a remote subscription backed by an always-running localhost HTTP service. MapleBridge deliberately does neither: the extra background process, startup integration, local port, request timeout, and recovery paths are not justified by this convenience feature. Stale traffic, health, and synthetic update-time metadata are removed from the MapleBridge profile rather than displayed as if they were live.

## Traffic accounting

The status output uses the sum of Lightsail `NetworkIn` and `NetworkOut` metric points from 00:00 UTC on the first day of the current month. The comparison total is the selected bundle's `transferPerMonthInGb`. Metrics may lag by about five minutes.

This is instance-wide traffic, not a WireGuard-peer counter. It includes GMS traffic plus SSM, package downloads, and other host traffic. Because a proxy gateway receives and retransmits user data, the sum of both directions is a conservative activity measure and is not identical to AWS billing calculations. Use the Lightsail console as the authority for billed transfer.

The traffic values in `state/status.json` are a snapshot taken when the status command runs; they are not a live counter. MapleBridge does not create a scheduled task by default.

## Privacy and recovery

No IP, health result, traffic snapshot, or WireGuard detail is written to the Clash profile index. Detailed status is stored only in ignored `state/status.json` and printed by the status command. Backups are stored under the Clash data directory in `maplebridge-backup/<timestamp>`.
