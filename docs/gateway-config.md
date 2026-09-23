# Linux gateway configuration

The gateway implementation targets Ubuntu 24.04 LTS. The live configuration command installs packages, changes forwarding and firewall state, and starts services, so the user-facing installer invokes it only after explicit paid-deployment confirmation.

## Files

- `scripts/linux/render-gateway-config.sh` validates inputs and renders WireGuard, nftables, sysctl, and systemd files without requiring root or changing the host.
- `scripts/linux/configure-gateway.sh` is the live Ubuntu entry point. It installs `wireguard-tools` and `nftables`, generates the server private key if absent, installs rendered files, and starts the firewall and WireGuard services.
- `scripts/windows/Configure-MapleBridgeGateway.ps1` transfers both Linux scripts and invokes the configuration through SSM Run Command. It sends only the client public key and records only public keys in ignored state.
- `scripts/windows/Install-MapleBridge.ps1` is the single setup entry point. It creates or reuses local client keys, deploys or reuses the gateway, configures it, generates and validates the Mihomo profile, installs it into Clash Verge, and refreshes health metadata.
- `tests/linux/GatewayConfig.Tests.sh` exercises rendering, permissions, idempotency, private-key preservation, and invalid input rejection in a temporary directory.

## Security and lifecycle behavior

- The server private key is generated on the gateway at `/etc/maplebridge/keys/server.key`, mode `0600`.
- Re-running configuration preserves an existing server private key.
- Only the server public key is printed.
- The WireGuard interface is `wg-maplebridge`; the default tunnel network is `10.88.0.0/24` and the default UDP port is `51820`.
- The host firewall permits established traffic, loopback, ICMP/IPv6 control traffic, DHCP replies, and the configured WireGuard UDP port. New public SSH connections are not permitted by MapleBridge rules.
- Forwarding is limited to traffic from `wg-maplebridge` to the detected external interface plus established return traffic. IPv4 tunnel traffic is masqueraded on the external interface.
- MapleBridge uses dedicated nftables tables and does not flush unrelated tables. The service replaces only `maplebridge_filter` and `maplebridge_nat` during restart.

## User-facing command

```powershell
.\scripts\windows\Install-MapleBridge.ps1 `
    -ProfileName 'maplebridge' `
    -ConfirmPaidDeployment
```

Cloud-init user data is intentionally limited to establishing and protecting the SSM management channel. After the node is online, the same PowerShell entry point uses Run Command for the idempotent WireGuard configuration. Keeping the two remote stages separate makes configuration failures observable and retryable without replacing the instance or rotating either private key.

## Linux command contract

The deployment layer invokes the following command through Systems Manager after the instance is registered:

```bash
sudo bash ./configure-gateway.sh \
  --client-public-key '<client-public-key>' \
  --vpn-port 51820 \
  --server-address '10.88.0.1/24' \
  --client-address '10.88.0.2/32'
```

The external interface is detected from the first default IPv4 route, or can be supplied explicitly. On 2026-09-22 the command completed on the live Lightsail Ubuntu 24.04 gateway, and SSM verified the WireGuard and firewall services, IPv4 forwarding, and both nftables tables. On 2026-09-23 a client handshake, selective forwarding, and GMS gameplay were verified through the gateway.

## Offline check

On Linux or WSL:

```bash
bash ./tests/linux/GatewayConfig.Tests.sh
bash -n ./scripts/linux/render-gateway-config.sh
bash -n ./scripts/linux/configure-gateway.sh
```

When running as root in an isolated test environment, set `MAPLEBRIDGE_NFT_CHECK=1` to add `nft -c` syntax validation. Check mode does not load the ruleset.
