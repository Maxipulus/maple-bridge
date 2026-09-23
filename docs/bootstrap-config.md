# Bootstrap Mihomo configuration

The bootstrap generator produces a standalone Mihomo TUN profile after a WireGuard server endpoint and key exchange exist. Generation is offline and does not install software, change networking, import a Clash Verge profile, or access AWS.

Mihomo supports TUN-based per-application routing, `PROCESS-NAME` and ordered rules, and a WireGuard outbound. The generated profile currently uses IPv4 only while IPv6 behavior remains under evaluation.

## Modes

`Selective` is the normal bootstrap mode. Confirmed or preliminary Nexon/GMS process names and the `nexon` geosite use `MapleBridge-US`; the final rule is `DIRECT`. DNS for the Nexon geosite uses a resolver through the US proxy while other DNS remains direct.

`DiagnosticFullTunnel` sends all captured traffic and DNS through `MapleBridge-US`. It has no `DIRECT` fallback and must be selected explicitly. Use it only if incomplete discovery prevents reaching gameplay, then replace it with a selective profile. It is not the project default.

## Generate a profile

The private key file must contain one base64-encoded 32-byte WireGuard private key. Generate the real key locally in a later key-management step; never copy an example or server private key.

```powershell
.\scripts\windows\New-MapleBridgeMihomoConfig.ps1 `
    -Mode Selective `
    -ServerAddress '203.0.113.10' `
    -ServerPort 51820 `
    -ServerPublicKey '<server-public-key>' `
    -ClientAddress '10.88.0.2/32' `
    -ClientPrivateKeyPath '.\state\keys\client.key'
```

The default output is `state/generated/maplebridge.yaml`. It contains the client private key and must remain ignored and local. The generator validates key shape, IPv4 endpoint and client CIDR, port range, process rule syntax, and prevents overwriting the private key file. It writes through a temporary file to avoid leaving a partial profile.

TUN is enabled by default and no mixed proxy port is opened. For an isolated command-line data-path test, explicitly pass `-TunEnabled $false -MixedPort <loopback-port>` with `DiagnosticFullTunnel`; the resulting listener is bound to `127.0.0.1` and does not require an elevated TUN process. This is a diagnostic option, not the installed profile default.

The selective profile was validated with the Clash Verge Rev 2.5.5 bundled Mihomo core, a live WireGuard endpoint, Nexon Launcher, and several minutes of GMS gameplay on 2026-09-23. The loopback diagnostic mode was also used against an isolated clean gateway to produce a real Nexon HTTPS request and WireGuard handshake. This is evidence for that environment, not a guarantee for future client or game versions. Installation and status-card behavior are documented in [status and Clash Verge integration](status.md).

## References

- [Mihomo TUN configuration](https://wiki.metacubex.one/en/config/inbound/tun/)
- [Mihomo routing rules](https://wiki.metacubex.one/en/config/rules/)
- [Mihomo WireGuard outbound](https://wiki.metacubex.one/en/config/proxies/wg/)
- [Mihomo DNS configuration](https://wiki.metacubex.one/en/config/dns/)
