# Recovery observations

## Idempotent reinstall and gateway reboot, 2026-09-23

The current one-command installer was reapplied to the existing `maplebridge-gateway` stack before the reboot test.

Observed results:

- CloudFormation detected the deployed redacted stack and performed no infrastructure mutation.
- Gateway configuration reapplied successfully through SSM Run Command.
- The client private key, client public key, server public key, and Lightsail static IP were unchanged before and after the reinstall.
- The Clash profile remained unique, passed Mihomo validation, and contained no synthetic traffic or update-time metadata.
- Clash Verge, Mihomo, and the TUN adapter recovered after the profile reload.

The existing Lightsail instance was then rebooted with the Lightsail API. Its operation completed successfully. The SSM `PingStatus` value remained `Online` throughout sampling and therefore was not treated as proof of an observed offline transition; the value can lag actual instance state.

Post-reboot verification used a real SSM Run Command and confirmed:

- the SSM managed node accepted and completed a command;
- `maplebridge-firewall.service` and `wg-quick@wg-maplebridge.service` were active;
- IPv4 forwarding remained enabled;
- the MapleBridge filter and NAT tables were present;
- the Lightsail status check reported no failure;
- the local Clash Verge and Mihomo processes were running and the Mihomo TUN adapter was up.

Finally, an HTTPS request to a Nexon domain was sent through the local Mihomo mixed proxy. It returned HTTP 302, and the next gateway check reported a WireGuard handshake three seconds old. This verified the post-reboot data path rather than only service state.

This test covers an existing-stack idempotent reinstall and a real gateway reboot. It does not cover a Windows reboot.

## Clean-stack deployment and deletion, 2026-09-23

A second, isolated `nano_3_0` gateway was created from an empty AWS state without changing the working `maplebridge-gateway` stack or its local keys and profile.

The first attempt exposed a naming boundary before any Lightsail resource was created: a long CloudFormation stack name made the path-qualified, generated IAM role name exceed the 64-character SSM activation limit. An explicit named-role workaround would have required a wider IAM resource pattern, so it was rejected. Deployment now limits stack names to 20 characters and continues to use the original `/maplebridge/` generated-role model.

The retry used the short `maplebridge-e2e` stack name and verified:

- CloudFormation created the bootstrap role, Lightsail instance, attached static IP, and UDP-only public ingress;
- first-boot user data registered the preinstalled SSM agent without SSH;
- the short-lived activation was deleted and its values were redacted from CloudFormation and Lightsail user data;
- SSM Run Command configured WireGuard, IPv4 forwarding, nftables, and systemd services from an independent client key pair;
- the generated selective Mihomo profile passed the bundled Mihomo validation;
- a loopback-only, non-TUN diagnostic profile sent an HTTPS request to `www.nexon.com` through the new WireGuard gateway and received HTTP 200;
- Mihomo recorded the Nexon connection selecting `MapleBridge-US`, and the gateway reported a WireGuard handshake 30 seconds old.

After verification, the diagnostic Mihomo process was stopped, the hybrid managed node was deregistered, and the temporary CloudFormation stack was deleted. Follow-up checks confirmed that the stack, Lightsail instance, static IP, IAM role, SSM managed node, and SSM activation were all absent. This proves the clean create-configure-use-delete lifecycle; Windows reboot and deliberate gateway-loss behavior remain unverified.
