# Development harness

The harness consists of repository context, a development workflow, offline Pester tests, Linux shell tests, release-safety checks, and GitHub Actions CI.

## Design context

These are design directions, not implemented or verified capabilities.

### Scope and traffic routing

- Cover GMS gameplay, Nexon Launcher, login, updates/downloads, and related web access. Steam is out of scope.
- Send related traffic through the US gateway; keep unrelated traffic direct. TUN interception does not imply forwarding all traffic to the US.
- While Mihomo is running, matched GMS traffic must not fall through to a direct route because the gateway or proxy is unavailable; unrelated traffic remains direct. Verify behavior during gateway outages and routing failures.
- Do not add a system-level kill switch for the case where Mihomo or Clash Verge is no longer running. Windows or the application may reconnect directly in that case; this accepted limitation avoids persistent firewall rules, administrator requirements, accidental blocking, uninstall residue, and added diagnostic complexity.
- Reuse the Clash Verge UI and automate configuration generation and setup. After initial setup, opening the client should be sufficient for normal use; preserve unrelated user profiles.
- Use Clash Verge Rev / Mihomo on Windows in TUN mode, with process rules for the game and launcher and domain rules for related websites. Clash Verge Rev 2.5.5 and its bundled Mihomo have been validated; future versions still require compatibility checks. WireGuard is the validated transport to Lightsail in Oregon; the official Windows WireGuard client is not required.
- Let the routing engine handle DNS and changing destination addresses rather than maintaining a static snapshot of resolved IPs. Fake-IP is a candidate mechanism, not a compatibility assumption.
- Community Nexon domain lists are discovery inputs, not complete GMS coverage. Verify helper processes, direct-IP connections, DNS bypass, IPv6, and TCP/UDP behavior against the actual client.

### Access and secrets

- Do not expose public SSH. Use Systems Manager Session Manager for interactive management and Run Command for automation.
- Register Lightsail through SSM Hybrid Activation during bootstrap. Protect activation credentials and managed-node identity; scope IAM permissions and verify required outbound connectivity. Recheck current hybrid-node pricing before deployment.
- WireGuard authenticates peers using public keys and protects tunnel packets. Generate each private key on its owning machine and exchange only public keys; do not implement custom request authentication.
- Keep gateway access separate from AWS administration. Limit public ingress to the required VPN port and constrain host forwarding and management access with firewall rules.
- Plan repeatable recovery if SSM or outbound networking fails; do not assume remote shell access will always be available.

### Updates and recovery

- Use SSM Patch Manager with the AWS default Ubuntu patch baseline as the primary security-update mechanism, scheduled through SSM Maintenance Windows. Do not run an independent unattended-upgrades installation schedule alongside it. EventBridge is not required by default.
- Patch approval and installation time are separate: the Ubuntu default baseline approves eligible security patches immediately, but installation runs on our schedule. Ubuntu does not support release-date-based approval delays.
- Express the maintenance schedule directly in UTC as configurable monthly recurrence fields: ordinal week, weekday, and time. The default is the first Tuesday of each month at 18:00 UTC.
- Let users override the recurrence and window duration through configuration. Do not infer or convert the schedule from the Windows, server, or user timezone. Display a local-time preview for convenience, but keep UTC as the stored and authoritative value.
- Maintenance may include service restarts and system reboots. No logged-in shell users does not mean the gateway is idle.
- Monthly installation is the routine cadence, not an AWS guarantee that waiting a month is safe. Emergency patching outside the window requires a separate explicit operation; do not silently change the schedule.
- Gateway reboot recovery has been verified. Dedicated Windows reboot and high-availability fault-injection testing are intentionally out of scope for this personal deployment. Report failed updates and pending reboots.
- Keep project configuration changes and OS release upgrades explicit; do not mix them into routine automatic security patches.

### Open decisions

- Compatibility of future Clash Verge Rev, Mihomo, Nexon Launcher, and GMS versions; process and domain rules may need refinement when clients change.
- DNS/Fake-IP and IPv6 behavior, including preventing rule-level direct fallback while Mihomo is running.
- Failure notification and the SSM recovery procedure remain open; the Maintenance Window schedule, duration, cutoff, and UTC semantics are implemented.
- Detailed implementation choices within the milestones in the [development plan](development-plan.md).

## References

- [Mihomo routing rules](https://wiki.metacubex.one/en/config/rules/), [DNS](https://wiki.metacubex.one/en/config/dns/), and [WireGuard](https://wiki.metacubex.one/en/config/proxies/wg/).
- [Community Nexon domains](https://github.com/v2fly/domain-list-community/blob/master/data/nexon).
- [Lightsail and Systems Manager](https://repost.aws/knowledge-center/add-lightsail-to-systems-manager), [Hybrid Activations](https://docs.aws.amazon.com/systems-manager/latest/userguide/activations.html), and [current pricing](https://aws.amazon.com/systems-manager/pricing/).
- [Ubuntu automatic updates](https://ubuntu.com/server/docs/how-to/software/automatic-updates/) and [SSM Maintenance Windows](https://docs.aws.amazon.com/systems-manager/latest/userguide/maintenance-windows.html).
- [AWS predefined patch baselines and Ubuntu approval limitations](https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager-predefined-and-custom-patch-baselines.html).

## Workflow

1. Read README.md for scope and AGENTS.md for working rules.
2. Identify the intended behavior and make a small, reviewable change.
3. Check the change using relevant tools directly. Review documentation links and consistency; check script syntax and test affected behavior when code exists.
4. Update affected documentation and local Chinese explanations. Record significant decisions and their reasons.
5. Report what changed, the exact checks and results, and what remains unverified.

## Growing the harness

Add repeatable behavioral tests alongside implemented features. Document the actual commands here when they exist.

Keep offline checks separate from AWS read-only diagnostics and live operations. Default checks must not access AWS or modify networking. Syntax checks alone do not demonstrate that deployment or GMS routing works.

## Current checks

Run the read-only client discovery behavior tests without inspecting live networking:

```powershell
Invoke-Pester -Path .\tests
```

Run the release-safety scan before staging or publishing. It checks publishable files and commit-author metadata without printing matched secret values:

```powershell
.\scripts\windows\Test-MapleBridgeRelease.ps1
```

Run the Linux gateway renderer tests on Linux or WSL:

```bash
bash ./tests/linux/GatewayConfig.Tests.sh
bash -n ./scripts/linux/render-gateway-config.sh
bash -n ./scripts/linux/configure-gateway.sh
```

GitHub Actions runs the Windows tests and release scan on `windows-latest`, plus the gateway renderer and shell syntax checks on `ubuntu-latest`. The workflow does not use AWS credentials, contact AWS, install software, or change networking.
