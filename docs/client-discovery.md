# Client traffic discovery

This is the first read-only tool for discovering the actual GMS and Nexon Launcher process set and network behavior. It does not change routes, firewall rules, DNS, Clash Verge, or AWS resources.

Sanitized findings from real client runs are recorded in [Windows client observations](observations/windows-client.md). Raw snapshots remain local and ignored.

## Capture a snapshot

Start Nexon Launcher or attempt to start GMS, then run from the repository root:

```powershell
.\scripts\windows\Get-MapleBridgeTrafficSnapshot.ps1
```

The command finds processes whose names contain `MapleStory` or `Nexon`, records their current TCP connections and local UDP endpoints, and writes JSON under the ignored `state/observations/` directory. Use an explicit regular expression if an observed helper process has a different name:

```powershell
.\scripts\windows\Get-MapleBridgeTrafficSnapshot.ps1 `
    -ProcessNamePattern '(?i)(maplestory|nexon|observed-helper)'
```

Use `-PassThru` to also return the snapshot object to the PowerShell pipeline. Use `-OutputPath` to select a different local output file.

## Monitor short-lived helper processes

A point-in-time snapshot can miss launcher helpers that start and exit quickly. Start the event-based monitor before opening Nexon Launcher:

```powershell
.\scripts\windows\Watch-MapleBridgeProcesses.ps1 -DurationSeconds 180
```

During the capture, open the launcher and reproduce the unavailable or launch path. The monitor records every Windows process start and stop event, plus an initial process inventory. It separately tracks processes whose names contain `MapleStory` or `Nexon`, their descendants even when a child has an unexpected name, and sampled TCP/UDP endpoints owned by those candidate processes. The JSON result is written under ignored `state/observations/`.

The monitor intentionally does not record process command lines. Executable paths are retained for the initial inventory and candidate process events only. It uses standard-user Windows process creation/deletion events at the configured polling interval; a process that exists for less than one interval may still escape observation. Use `-RootProcessNamePattern` to extend the root match after an observed process has been confirmed.

## Limitations and data handling

- A snapshot is a point-in-time observation. Before the US route exists, capture the launcher and expected region-error path; this baseline is useful but cannot reveal gameplay traffic. After bootstrap connectivity works, capture additional snapshots during update/download, successful game startup, character selection, and gameplay.
- Process events are captured by Windows instrumentation, but network endpoints are sampled. A process that connects and exits between samples can leave a process event without a corresponding endpoint record.
- TCP records include local and remote addresses and ports. UDP endpoint records available through the Windows cmdlet contain only local bindings, so packet or Mihomo log observation will be needed later to identify UDP destinations.
- The default name pattern is only a starting point. It cannot discover helper processes whose names contain neither `MapleStory` nor `Nexon`.
- The output may contain local installation paths and network addresses. Keep it under ignored `state/` and review it before sharing. Never place credentials or private keys in an observation file.
- This command observes Windows networking only. It does not prove which route or public exit a connection used.

## Offline test

The test uses fixture processes and endpoints; it does not inspect or change live networking:

```powershell
Invoke-Pester -Path .\tests\MapleBridge.ClientDiscovery.Tests.ps1
```
