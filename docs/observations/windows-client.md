# Windows client observations

This file records sanitized facts observed on a real Windows client. It intentionally excludes local installation paths, local addresses, transient remote addresses, account data, and credentials.

## 2026-09-22: launcher unavailable baseline

Environment state:

- Nexon Launcher opened successfully from Japan.
- The launcher displayed MapleStory as unavailable.
- The game process did not start, so this observation does not cover login or gameplay traffic.

Observed process behavior:

- The launcher uses multiple `nexon_client.exe` processes.
- A separate `nexon_runtime.exe` process was present.
- `nexon_client.exe` held multiple external TCP connections, primarily HTTPS plus at least one non-standard destination port, and several local UDP bindings.
- The observed `nexon_runtime.exe` connections were loopback IPC connections. No external runtime connection was present in this point-in-time snapshot.

Routing implications:

- `nexon_client.exe` is a confirmed preliminary process-rule candidate.
- `nexon_runtime.exe` must remain in discovery coverage, but the baseline does not yet prove that its traffic needs the US route.
- Destination IPs from this snapshot are not suitable as durable routing rules. Domain and successful launch/gameplay observations are still required after bootstrap connectivity exists.

Source data remains local under ignored `state/observations/launcher-open.json`.

## 2026-09-22: launcher recovery and download capture

Environment state:

- A process-event monitor started while Nexon Launcher was closed and continued through launcher startup.
- The launcher initially had been reported unavailable, then became available without an intentional configuration change and began downloading MapleStory.
- At the successful observation point, the generated Mihomo runtime configuration had TUN enabled and Windows reported the `Mihomo Meta Tunnel` adapter as up. Earlier inspection had found TUN disabled and no adapter, so delayed service initialization or configuration reload is the leading explanation; the exact trigger remains unproven.

Observed process behavior:

- `nexon_launcher.exe` started first, made HTTPS connections, launched the main `nexon_client.exe`, and exited after roughly four seconds.
- The main client launched additional `nexon_client.exe` processes and `nexon_runtime.exe`. Several extra client processes existed only briefly, including one observed for less than half a second.
- A `conhost.exe` descendant of `nexon_runtime.exe` was observed, but no network endpoint owned by it was captured. It is not currently a routing-rule candidate.
- Candidate launcher processes used external TCP ports 80, 443, and 8913. `nexon_client.exe` also held local UDP endpoints. Runtime high ports in this capture were loopback communication and are not durable destination-rule inputs.

Routing implications:

- Add `nexon_launcher.exe` to the explicit process rules. Its lifetime is short enough that a point-in-time snapshot can miss it, and relying only on a matching domain is unnecessary risk.
- Retain `nexon_client.exe`, `nexon_runtime.exe`, and `MapleStory.exe` rules. Do not proxy every descendant solely because of ancestry.
- The successful launcher/download state is useful evidence, but gameplay routing remains unverified until the installed game can start.

Raw event and endpoint data remains local under ignored `state/observations/launcher-reopen-trace.json` and `state/observations/launcher-downloading-snapshot.json`.

## 2026-09-23: successful gameplay capture

Environment state:

- MapleStory started successfully and remained playable for several minutes.
- Process and endpoint monitoring covered startup and the running game state.

Observed process behavior:

- `MapleStory.exe` was the main game process and held external TCP connections on ports 80, 443, 8484, 8585, 8913, and another transient high port.
- `BlackXchg.aes` ran as a child of `MapleStory.exe` for roughly two seconds and made an external TCP port 80 connection. Despite its extension, Windows reported it as a process.
- `BlackCipher64.aes` remained running as a child of `MapleStory.exe`. No endpoint owned by it was captured, but it is part of the active game/security process tree.
- Multiple Nexon-signed `DwarfAxe.exe` overlay processes ran beneath `MapleStory.exe` and held external HTTPS connections and local UDP endpoints.
- The installation also contains Nexon-signed `MapleBrowser_WZ2.exe` and `CrashReportClient.exe`. They did not run during this capture but can handle game-related web and crash-report traffic.

Routing implications:

- Explicitly route the main game, observed security/exchange processes, overlay, embedded browser, and crash reporter through `MapleBridge-US`.
- Explicitly route the installed Nexon launcher, updater, agent, client, and runtime executables. This remains selective routing because the rule set is limited to Nexon/MapleStory components, with unrelated processes falling through to `DIRECT`.
- Process routing reduces accidental direct connections caused by incomplete domain coverage. It does not conceal characteristics such as a data-center exit address or guarantee that Nexon cannot identify VPN use.

Raw event and endpoint data remains local under ignored `state/observations/game-first-launch-trace.json`.

## 2026-09-23: payment-route observation

- The Nexon payment entry point matched `GEOSITE,nexon` and used `MapleBridge-US`.
- The checkout then opened in Chrome. Xsolla hosts including `pay.xsolla.com`, `secure.xsolla.com`, API, telemetry, and CDN subdomains matched the final `DIRECT` rule. PayPay was subsequently offered over the direct Japanese route.
- Xsolla's official documentation states that client-side payment-token requests use the client IP to determine country, currency, and available payment methods. Server-generated tokens can instead contain an explicit country, which takes precedence over IP.
- Route the observed Xsolla suffixes through `MapleBridge-US` while keeping unrelated browser traffic direct. A new checkout must be created after the rule change because an existing payment token may already contain a country decision.
- Routing cannot override an explicit country supplied by Nexon, account-region restrictions, card issuer/BIN country, or billing-address checks. Users must provide accurate billing and cardholder information.
