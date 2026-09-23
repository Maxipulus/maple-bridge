# AWS bootstrap design

AWS deployment is implemented as an explicit, cost-incurring operation. The CloudFormation template still defaults to creating no gateway resources unless deployment is confirmed.

## Two-phase deployment

The template at `infrastructure/gateway.template.json` supports this sequence:

1. Create the stack with `DeployGateway=false`. This creates only the IAM service role used by a Systems Manager hybrid activation.
2. Read the `SsmHybridNodeRoleName` output.
3. Create a short-lived SSM activation with registration limit `1`, using that role. The AWS CLI default expiration is 24 hours, but deployment automation should set a shorter explicit expiration.
4. Review current Lightsail bundles, blueprint IDs, and the [AWS cost model](costs.md). Select the intended values explicitly.
5. Update the stack with `DeployGateway=true`, `SsmBootstrapMode=Register`, and the activation ID/code. This creates the Lightsail instance and static IP. The Lightsail firewall exposes only the configured WireGuard UDP port; specifying it also prevents default SSH ports from being added.
6. User data first detects and registers a preinstalled Snap or Deb SSM Agent. Only when neither is present does it download the regional AWS `ssm-setup-cli` fallback. It then scrubs activation values from known cloud-init script and bootstrap log files and writes a completion marker.
7. Wait for exactly one matching `mi-` managed node to become online.
8. Update the stack again with `SsmBootstrapMode=Redacted` and both activation parameters set to `REDACTED`, then delete the activation. This replaces stored Lightsail user data with a harmless placeholder. Verify that the instance remains managed.
9. The same user-facing installer uses SSM Run Command to transfer and invoke the gateway configuration. Do not open SSH as a fallback.

The activation code is necessarily present in Lightsail user data during first boot. `NoEcho` masks CloudFormation parameter display but is not treated as complete secret storage. Risk is reduced by the one-node registration limit, short expiry, local cloud-init scrubbing, immediate stack redaction, and activation deletion. Deployment must stop and report a recoverable error if registration does not complete; it must not silently open SSH.

AWS lists Ubuntu 24.04 and Amazon Linux 2023 among operating systems whose AWS-provided EC2 AMIs are likely to contain SSM Agent, while explicitly requiring callers to verify that it is installed and running. That statement is not a guarantee for every Lightsail blueprint revision. MapleBridge therefore keeps the Ubuntu 24.04 blueprint used by its `apt`-based gateway automation, prefers its preinstalled Agent when available, and retains the official regional setup CLI as a narrow fallback. Switching to Amazon Linux solely for SSM would also require changing and retesting the gateway package and patching paths.

Lightsail prepends its own `#!/bin/sh` initialization wrapper to instance user data. A shebang inside the supplied payload is therefore not authoritative. The bootstrap body stays POSIX `sh` compatible and must not use Bash-only options or process substitution. This behavior was confirmed from the generated `part-001` and cloud-init failure logs during the 2026-09-22 live exercise.

The infrastructure-only Windows entry point implements this lifecycle:

```powershell
.\scripts\windows\Deploy-MapleBridgeGateway.ps1 `
    -ProfileName 'maplebridge' `
    -ConfirmPaidDeployment
```

The confirmation switch is mandatory because the command creates a paid Lightsail instance. Stack names are limited to 20 characters so the `/maplebridge/` path plus CloudFormation-generated role name remains within the 64-character SSM activation limit. The command runs readiness first, refuses unrelated stack states, resolves the generated IAM role to its path-qualified `maplebridge/<role-name>` value, keeps activation credentials only in memory and a short-lived local temporary parameter file, deletes that file before waiting, removes the activation in `finally`, and writes only non-secret live identifiers to ignored `state/aws-gateway.json`.

Normal users run `scripts/windows/Install-MapleBridge.ps1` instead. It wraps infrastructure deployment, local client-key initialization, SSM gateway configuration, Mihomo profile generation, Clash Verge installation, and status refresh in one command. The narrower deployment command remains available for infrastructure diagnosis and testing.

## Template defaults

- Region: the stack must be deployed in Oregon (`us-west-2`).
- Availability Zone: `us-west-2a`, configurable.
- Blueprint candidate: `ubuntu_24_04`, configurable and subject to a live availability check.
- Bundle candidate: `nano_3_0`, configurable and subject to live availability and price checks.
- Gateway creation: disabled.
- SSM bootstrap mode: `Redacted`; `Register` must be selected explicitly with real activation values.
- Public ingress: the selected WireGuard UDP port only, IPv4.
- Static IP: attached through a separate `AWS::Lightsail::StaticIp` resource.
- Public SSH/RDP and Lightsail browser-connect ranges: absent.

Blueprint and bundle defaults are candidates, not verified availability promises. CloudFormation replacement-sensitive values such as the instance name, Availability Zone, blueprint, and bundle must not be changed as part of a routine update.

## Current validation boundary

The template is parsed and inspected by offline Pester tests. On 2026-09-22, AWS CLI v2 successfully performed the separate read-only identity, Lightsail availability, and AWS-side `validate-template` checks. A clean live deployment then created the Lightsail instance and static IP, registered the preinstalled Snap SSM Agent as a hybrid managed node, redacted the on-instance and CloudFormation activation values, deleted the activation, and completed an SSM Run Command verification. The stack finished `UPDATE_COMPLETE`, the node was `Online`, and only the WireGuard UDP port was exposed. The single installer then configured and health-checked WireGuard, forwarding, and nftables through SSM and generated a local Mihomo profile. On 2026-09-23 the installed profile completed a live handshake, selective routing, and GMS gameplay validation. A second isolated stack then repeated the complete create, bootstrap, configure, Nexon data-path, deregister, and delete lifecycle; follow-up checks found no AWS resources left behind. No test in the default harness may contact AWS.

## References

- [CloudFormation Lightsail instance](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-lightsail-instance.html)
- [CloudFormation Lightsail networking ports](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-properties-lightsail-instance-port.html)
- [CloudFormation Lightsail static IP](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-lightsail-staticip.html)
- [SSM hybrid activations](https://docs.aws.amazon.com/systems-manager/latest/userguide/activations.html)
- [Installing SSM Agent on hybrid Linux nodes](https://docs.aws.amazon.com/systems-manager/latest/userguide/hybrid-multicloud-ssm-agent-install-linux.html)
- [Find AMIs with SSM Agent preinstalled](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html)
- [AWS CLI `create-activation`](https://docs.aws.amazon.com/cli/latest/reference/ssm/create-activation.html)
