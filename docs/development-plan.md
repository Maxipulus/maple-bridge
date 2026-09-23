# Development plan

This plan describes intended work, not implemented or verified capabilities. Keep each milestone small enough to review and add behavioral tests with the feature it introduces.

## Accepted decisions

- Reuse the Clash Verge Rev UI and its bundled Mihomo core. Do not build a MapleBridge GUI.
- Use PowerShell for Windows-side setup, configuration, diagnostics, and deployment orchestration.
- Route GMS, Nexon Launcher, login, update, download, and related web traffic through the US gateway. Keep unrelated traffic direct; Steam is out of scope.
- Prevent configuration-level direct fallback while Mihomo is running. A failed WireGuard gateway or proxy choice must not cause a matching rule to select `DIRECT`.
- Do not implement a system-level kill switch for the case where Mihomo or Clash Verge has stopped. A subsequent connection may be handled directly by Windows or the game. The long-tail leak risk does not justify persistent Windows firewall rules, administrator requirements, accidental blocking, uninstall residue, and greater diagnostic complexity.
- Manage a separate MapleBridge profile and preserve unrelated Clash Verge profiles and settings.
- Generate each WireGuard private key on the machine that owns it. Normal updates must preserve existing keys.
- Use AWS Lightsail in Oregon (`us-west-2`) and manage the host through Systems Manager rather than public SSH.
- Keep offline checks, AWS read-only diagnostics, deployment, live networking changes, and resource deletion as distinct operations.

## First vertical slice

GMS cannot be assumed to reach gameplay from Japan before the US route exists. The first usable slice therefore crosses several component milestones instead of completing client discovery in isolation:

1. Capture the launcher, launch attempt, and expected region-error path as a baseline. Gameplay traffic is not expected yet.
2. Implement the minimum configuration generator, Linux gateway, and AWS provisioning needed for a real US WireGuard endpoint.
3. Try a bootstrap profile using preliminary Nexon/GMS process and domain rules.
4. If incomplete discovery prevents login, use an explicitly selected, temporary diagnostic full-tunnel profile to reach gameplay and collect evidence. This profile is never the default or the final configuration.
5. Replace the diagnostic profile with selective process and domain rules, then verify that unrelated traffic remains direct.

The component milestones below still define their own tests and exit criteria. Live AWS creation remains an explicit, cost-incurring operation and is not part of offline validation.

Current progress:

- Implemented a read-only Windows process and endpoint snapshot command.
- Recorded the launcher-unavailable baseline and confirmed `nexon_client.exe` and `nexon_runtime.exe`.
- Implemented an offline Mihomo generator for selective and explicit diagnostic full-tunnel bootstrap profiles.
- Implemented and offline-tested the Ubuntu gateway renderer and live configuration entry point, including key preservation, forwarding, nftables, and systemd configuration.
- Implemented an offline-tested, opt-in CloudFormation template for the Lightsail instance, static IP, restricted UDP ingress, SSM hybrid-node role, and redacted two-phase SSM bootstrap lifecycle.
- Added a scoped project IAM policy plus CloudShell and Console bootstrap paths for the dedicated deployment identity; the configured profile passed live read-only validation.
- Implemented a separate AWS readiness command with mocked behavioral tests and a successful live read-only check for identity, region/AZ, blueprint, bundle/price, and AWS-side template validation.
- Documented Windows installation and verification for AWS CLI v2 and the Session Manager plugin, plus the current Lightsail and SSM hybrid-node cost model.
- Completed a clean live AWS deployment, SSM hybrid registration and redaction, local client-key generation, server-key generation, WireGuard/nftables service startup, and one-command orchestration through local Mihomo profile generation.
- Automated Clash Verge backup, profile installation and activation, live WireGuard handshake, selective routing, and successful GMS gameplay are complete for the tested environment. A status command reports AWS, SSM, gateway, local TUN, handshake, and current-month instance traffic in ignored state. Snapshot metadata is intentionally not written to the Clash Verge home card because its local-profile refresh action cannot query AWS.
- Profile removal and monthly security-maintenance automation are implemented. Safe offline Windows/Linux CI and a release-safety scan are implemented. Payment-provider routing remains experimental.
- A live Lightsail reboot recovery test now covers SSM command execution, systemd services, forwarding, nftables, local TUN state, a post-reboot Nexon request, and a fresh WireGuard handshake. Windows reboot and deliberate gateway-loss behavior remain unverified.
- An isolated second stack completed the clean create, SSM bootstrap/redaction, gateway configuration, real Nexon data-path, managed-node deregistration, and stack deletion lifecycle. Post-cleanup checks found no stack, instance, static IP, IAM role, managed node, or activation.
- Windows reboot and deliberate gateway-loss testing are intentionally omitted: repeated normal workstation restarts already provide adequate personal-use confidence, and high-availability fault testing is outside this non-commercial project's scope.
- The production stack owns the least-purpose Maintenance Window role, window, exact managed-node target, and patch task. The enabled `maplebridge-security-updates` window runs the AWS default Ubuntu baseline on the first Tuesday of each month at 18:00 UTC with `RebootIfNeeded`; the first scheduled execution has not occurred yet.

## Milestone 1: client feasibility

Record the pre-tunnel failure path, then establish the complete traffic model after the minimum US gateway path exists.

Tasks:

- Record the supported Windows, Clash Verge Rev, and Mihomo versions used for validation.
- Capture the launcher and failed game-start path from Japan before a tunnel is available.
- Build a hand-authored TUN profile once a real temporary WireGuard endpoint is available.
- Discover the game, launcher, updater, authentication, and helper processes.
- Discover required domains and identify direct-IP, DNS bypass, IPv6, TCP, and UDP behavior.
- Start with preliminary process and domain rules for the game and launcher, then refine them from live evidence.
- Use a temporary diagnostic full-tunnel profile only when missing rules prevent gameplay discovery; keep it explicit and separate from the default profile.
- Verify that matching traffic uses the US exit and unrelated traffic uses the local exit.
- Diagnose gateway, WireGuard, and DNS failures when they occur; dedicated high-availability fault injection and Windows reboot testing are intentionally out of scope for this personal deployment.
- Observe and document what happens when Mihomo or Clash Verge stops; this is diagnostic information, not a system-level leak-prevention requirement.

Exit criteria:

- The baseline region-error path and the later successful tunneled path are both documented.
- A documented selective rule set covers observed GMS and Nexon flows.
- While Mihomo is running, an unavailable gateway cannot make matched traffic select `DIRECT`.
- Unrelated traffic remains direct.
- Remaining compatibility gaps are explicit and reproducible.

## Milestone 2: configuration model and offline harness

Turn the validated prototype into deterministic generated configuration.

Tasks:

- Define user configuration, generated state, and secret boundaries.
- Generate Mihomo, WireGuard server, forwarding, and firewall configuration.
- Validate required values and reject ambiguous or unsafe combinations.
- Preserve existing keys and stable identifiers during regeneration.
- Add fixtures for representative process, domain, IPv4, IPv6, and failure cases.
- Add Pester behavioral tests for rule order, proxy selection, direct routing, idempotency, and secret-safe output.
- Add a shared offline check entry point when the repeated checks justify it.

Exit criteria:

- The same inputs produce equivalent configuration on repeated runs.
- Tests demonstrate the intended routing decisions rather than only checking syntax.
- Tests do not access AWS, install software, or change local networking.

## Milestone 3: Windows management commands

Automate the local workflow without taking ownership of Clash Verge itself.

Tasks:

- Detect supported Clash Verge Rev and Mihomo versions and report unsupported states.
- Generate the client private key locally and exchange only the public key.
- Create, update, back up, and remove the MapleBridge profile without altering unrelated profiles.
- Prefer a supported import/update path over editing Clash Verge internal databases or random profile files.
- Add status and diagnostic commands for the core, TUN, DNS, WireGuard handshake, routing choice, and public exit.
- Redact private keys, activation credentials, account identifiers, and other sensitive values from output.
- Make interrupted setup and repeated execution recoverable.

Exit criteria:

- Initial setup leaves normal daily use as opening Clash Verge and selecting or activating MapleBridge.
- Update and removal affect only MapleBridge-owned content.
- Diagnostics distinguish client, DNS, tunnel, gateway, and rule failures.

Installing or upgrading Clash Verge Rev is not part of this milestone. The commands detect prerequisites and provide actionable guidance.

## Milestone 4: Linux gateway configuration

Build an idempotent host configuration independently of AWS provisioning.

Tasks:

- Install and configure WireGuard, IP forwarding, host firewall rules, and NAT.
- Generate the server private key on the gateway and preserve it across normal updates.
- Add and remove client public keys without rewriting unrelated peers.
- Configure services for boot recovery and emit secret-safe health information.
- Register and validate Systems Manager connectivity without exposing public SSH.
- Add syntax, rendering, idempotency, and reboot-recovery tests in an isolated test environment.

Exit criteria:

- Reapplying the same configuration is safe.
- WireGuard, forwarding, firewall rules, and Systems Manager recover after reboot.
- No private key appears in repository content, normal command output, or logs.

## Milestone 5: AWS infrastructure and deployment

Provision the validated gateway design repeatably.

Tasks:

- Define CloudFormation for the Lightsail instance, stable public address, and required UDP ingress only.
- Parameterize instance size, VPN port, and other deployment settings without embedding account-specific data.
- Design a protected, short-lived SSM Hybrid Activation bootstrap flow.
- Separate stack inspection and other read-only checks from create, update, and delete operations.
- Ensure ordinary stack updates do not replace the host, public address, or keys unexpectedly.
- Add explicit target display and confirmation to resource deletion.
- Recheck current SSM hybrid-node and Lightsail pricing before the first live deployment.

Exit criteria:

- A clean deployment reaches a managed, healthy gateway without public SSH.
- A failed or interrupted deployment can be diagnosed and safely retried.
- Normal updates preserve identity and keys.

## Milestone 6: end-to-end orchestration

Join the independently tested client, gateway, and AWS components.

Target flow:

1. Check local prerequisites and configuration.
2. Create or update the AWS gateway.
3. Wait for Systems Manager registration.
4. Configure the gateway and obtain its public key.
5. Register the client public key on the gateway.
6. Generate and install the MapleBridge profile.
7. Run routing and health checks.

Tasks:

- Provide clear progress, stable exit codes, and actionable failure messages.
- Store resumable non-secret state under ignored `state/`.
- Prevent retries from creating duplicate resources or peers.
- Verify the expected US exit for matched traffic and the local exit for unrelated traffic.
- Keep live AWS and networking tests opt-in and separate from default checks.

Exit criteria:

- A fresh setup and an interrupted-then-resumed setup both reach the same healthy state.
- An ordinary update preserves keys, public address, and unrelated Clash Verge configuration.

## Milestone 7: maintenance and recovery

Add production operations after the basic path is stable.

Tasks:

- Maintain the implemented SSM Patch Manager schedule using the AWS default Ubuntu baseline and a Maintenance Window.
- Store the recurrence directly in UTC and show a local-time preview only for convenience.
- Default to the first Tuesday of each month at 18:00 UTC; keep recurrence and duration configurable.
- Keep emergency patching, project configuration updates, and OS release upgrades explicit.
- Report patch failures, pending reboots, WireGuard health, forwarding state, firewall state, and SSM availability.
- Document recovery when SSM or gateway outbound connectivity fails.

Exit criteria:

- Scheduled maintenance and reboot recovery are demonstrated on a test gateway.
- Failures are visible and have a documented recovery path.

## Milestone 8: release readiness

Tasks:

- Keep English documentation and `README.zh-CN.md` aligned as behavior changes.
- Document installation, normal use, update, diagnostics, recovery, and removal.
- Clearly label implemented, tested, experimental, and planned behavior.
- Maintain CI only for safe offline checks.
- Run the release-safety scan and review staged content and commit metadata for credentials, private keys, personal information, local paths, account IDs, and live infrastructure details.
- Use placeholders in examples and a GitHub noreply commit email.

## End-to-end acceptance matrix

| Scenario | Matched GMS/Nexon traffic | Unrelated traffic |
| --- | --- | --- |
| Healthy client and gateway | US gateway | Local direct |
| Gateway unreachable while Mihomo runs | Fails through the selected proxy path; no rule-level direct fallback | Local direct |
| WireGuard handshake failure while Mihomo runs | Fails through the selected proxy path; no rule-level direct fallback | Local direct |
| DNS failure while Mihomo runs | Clear failure or blocked resolution; no rule-level direct fallback | Remains direct where independent of the failed DNS path |
| Windows or gateway reboot | Recovers when the required components are running again | Local direct |
| Mihomo or Clash Verge stopped | No system-level guarantee; document observed Windows/application behavior | Local direct |

Live acceptance requires a real Windows GMS installation, the Nexon Launcher, and a real US gateway. CI cannot establish these behaviors.
