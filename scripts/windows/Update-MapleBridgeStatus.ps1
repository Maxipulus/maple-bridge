[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [string] $StatePath,
    [string] $AwsExecutable = 'aws',
    [switch] $SkipGatewayCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1'
Import-Module $modulePath -Force
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $repositoryRoot 'state\aws-gateway.json' }
$statePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'Gateway state is missing. Run Install-MapleBridge.ps1 first.' }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

if ($AwsExecutable -eq 'aws' -and $null -eq (Get-Command $AwsExecutable -ErrorAction SilentlyContinue)) {
    $installedAws = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
    if (Test-Path -LiteralPath $installedAws -PathType Leaf) { $AwsExecutable = $installedAws }
}
$common = @('--profile', $ProfileName, '--region', [string] $state.region, '--output', 'json', '--no-cli-pager')

$instance = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('lightsail', 'get-instance', '--instance-name', [string] $state.gatewayName) + $common)
$ssm = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'describe-instance-information', '--filters', ('Key=InstanceIds,Values={0}' -f $state.managedNodeId)) + $common)
$bundleQuery = '{bundles: bundles[?bundleId==`__BUNDLE__`].{bundleId:bundleId,transferPerMonthInGb:transferPerMonthInGb}}'.Replace('__BUNDLE__', [string] $state.bundleId)
$bundles = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('lightsail', 'get-bundles', '--include-inactive', '--query', $bundleQuery) + $common)
$bundle = @($bundles.bundles | Where-Object { $_.bundleId -eq $state.bundleId }) | Select-Object -First 1
if ($null -eq $bundle) { throw ('Lightsail bundle {0} was not found.' -f $state.bundleId) }

$now = [DateTimeOffset]::UtcNow
$monthStart = [DateTimeOffset]::new($now.Year, $now.Month, 1, 0, 0, 0, [TimeSpan]::Zero)
function Get-LightsailMetric([string] $MetricName, [string] $Unit, [string] $Statistic, [DateTimeOffset] $Start, [int] $Period) {
    return Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@(
        'lightsail', 'get-instance-metric-data',
        '--instance-name', [string] $state.gatewayName,
        '--metric-name', $MetricName,
        '--period', [string] $Period,
        '--start-time', $Start.ToString('o'),
        '--end-time', $now.ToString('o'),
        '--unit', $Unit,
        '--statistics', $Statistic
    ) + $common)
}

$networkIn = Get-LightsailMetric -MetricName 'NetworkIn' -Unit 'Bytes' -Statistic 'Sum' -Start $monthStart -Period 3600
$networkOut = Get-LightsailMetric -MetricName 'NetworkOut' -Unit 'Bytes' -Statistic 'Sum' -Start $monthStart -Period 3600
$statusStart = $now.AddMinutes(-15)
$statusMetric = Get-LightsailMetric -MetricName 'StatusCheckFailed' -Unit 'Count' -Statistic 'Maximum' -Start $statusStart -Period 300
$downloadBytes = Get-MapleBridgeMetricSum -MetricData @($networkIn.metricData)
$uploadBytes = Get-MapleBridgeMetricSum -MetricData @($networkOut.metricData)
$statusFailures = Get-MapleBridgeMetricMaximum -MetricData @($statusMetric.metricData)
$totalBytes = [long] ([decimal] $bundle.transferPerMonthInGb * 1GB)

$ssmRecord = @($ssm.InstanceInformationList) | Select-Object -First 1
$gatewayCheck = [ordered] @{ performed = $false; firewall = 'unknown'; wireGuard = 'unknown'; ipForward = 'unknown'; latestHandshakeUnix = 0; handshakeAgeSeconds = $null }
if (-not $SkipGatewayCheck) {
    $gatewayCheck.performed = $true
    $commands = @(
        'printf "firewall=%s\n" "$(systemctl is-active maplebridge-firewall.service 2>/dev/null || true)"',
        'printf "wireguard=%s\n" "$(systemctl is-active wg-quick@wg-maplebridge.service 2>/dev/null || true)"',
        'printf "ip_forward=%s\n" "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || true)"',
        'printf "latest_handshake=%s\n" "$(wg show wg-maplebridge latest-handshakes 2>/dev/null | awk ''NR==1 {print $2}'' || true)"'
    )
    $parameterPath = Join-Path ([IO.Path]::GetTempPath()) ('maplebridge-status-{0}.json' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($parameterPath, (@{ commands = $commands } | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
        $sent = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'send-command', '--instance-ids', [string] $state.managedNodeId, '--document-name', 'AWS-RunShellScript', '--comment', 'Read MapleBridge health', '--parameters', ('file://{0}' -f $parameterPath)) + $common)
        $commandId = [string] $sent.Command.CommandId
        $command = Get-Command $AwsExecutable -ErrorAction Stop
        & $command.Source ssm wait command-executed --command-id $commandId --instance-id $state.managedNodeId @common
        if ($LASTEXITCODE -ne 0) { throw 'Timed out waiting for the gateway health check.' }
        $invocation = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'get-command-invocation', '--command-id', $commandId, '--instance-id', [string] $state.managedNodeId) + $common)
        if ($invocation.Status -ne 'Success') { throw ('Gateway health check failed: {0}' -f $invocation.StandardErrorContent) }
        foreach ($line in ([string] $invocation.StandardOutputContent -split "`r?`n")) {
            if ($line -match '^firewall=(.*)$') { $gatewayCheck.firewall = $Matches[1] }
            elseif ($line -match '^wireguard=(.*)$') { $gatewayCheck.wireGuard = $Matches[1] }
            elseif ($line -match '^ip_forward=(.*)$') { $gatewayCheck.ipForward = $Matches[1] }
            elseif ($line -match '^latest_handshake=([0-9]+)$') { $gatewayCheck.latestHandshakeUnix = [long] $Matches[1] }
        }
        if ($gatewayCheck.latestHandshakeUnix -gt 0) { $gatewayCheck.handshakeAgeSeconds = [long] ($now.ToUnixTimeSeconds() - $gatewayCheck.latestHandshakeUnix) }
    }
    finally {
        if (Test-Path -LiteralPath $parameterPath) { Remove-Item -LiteralPath $parameterPath -Force }
    }
}

$clashRunning = $null -ne (Get-Process clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1)
$mihomoRunning = $null -ne (Get-Process verge-mihomo -ErrorAction SilentlyContinue | Select-Object -First 1)
$tunAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)(mihomo|clash|meta)' -or $_.InterfaceDescription -match '(?i)(mihomo|clash|meta)' } | Select-Object -First 1
$tunUp = $null -ne $tunAdapter -and [string] $tunAdapter.Status -eq 'Up'
$awsRunning = [string] $instance.instance.state.name -eq 'running'
$ssmOnline = $null -ne $ssmRecord -and [string] $ssmRecord.PingStatus -eq 'Online'
$deepHealthy = $SkipGatewayCheck -or ($gatewayCheck.firewall -eq 'active' -and $gatewayCheck.wireGuard -eq 'active' -and $gatewayCheck.ipForward -eq '1')
$healthy = $awsRunning -and $ssmOnline -and $statusFailures -eq 0 -and $clashRunning -and $mihomoRunning -and $tunUp -and $deepHealthy
$healthLabel = if ($healthy) { 'Healthy' } else { 'Needs attention' }
$handshakeLabel = if ($null -ne $gatewayCheck.handshakeAgeSeconds) { 'WG {0}s' -f $gatewayCheck.handshakeAgeSeconds } elseif ($SkipGatewayCheck) { 'WG unchecked' } else { 'WG no handshake' }
$status = [pscustomobject] [ordered] @{
    schemaVersion = 1
    refreshedAtUtc = $now.ToString('o')
    monthStartsAtUtc = $monthStart.ToString('o')
    gateway = [ordered] @{ name = [string] $state.gatewayName; staticIpAddress = [string] $state.staticIpAddress; instanceState = [string] $instance.instance.state.name; ssmPingStatus = [string] $ssmRecord.PingStatus; statusCheckFailures = $statusFailures }
    wireGuard = $gatewayCheck
    local = [ordered] @{ clashVergeRunning = $clashRunning; mihomoRunning = $mihomoRunning; tunAdapterName = if ($null -ne $tunAdapter) { [string] $tunAdapter.Name } else { $null }; tunUp = $tunUp }
    traffic = [ordered] @{ scope = 'Lightsail instance NetworkIn + NetworkOut'; uploadBytes = $uploadBytes; downloadBytes = $downloadBytes; usedBytes = $uploadBytes + $downloadBytes; allowanceBytes = $totalBytes; metricDelayMinutes = 5 }
    healthy = $healthy
}
$statusPath = Join-Path $repositoryRoot 'state\status.json'
[IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

$status
Write-Host ('MapleBridge status refreshed: {0}; current-month traffic {1:N2} GiB / {2:N0} GiB.' -f $healthLabel, (($uploadBytes + $downloadBytes) / 1GB), ($totalBytes / 1GB))
Write-Host ('Gateway: {0}; SSM: {1}; status-check failures: {2}; public IP: {3}.' -f $status.gateway.instanceState, $status.gateway.ssmPingStatus, $status.gateway.statusCheckFailures, $status.gateway.staticIpAddress)
Write-Host ('WireGuard: {0}; firewall: {1}; IP forwarding: {2}; handshake: {3}.' -f $status.wireGuard.wireGuard, $status.wireGuard.firewall, $status.wireGuard.ipForward, $handshakeLabel)
Write-Host ('Local: Clash={0}; Mihomo={1}; TUN={2}.' -f $status.local.clashVergeRunning, $status.local.mihomoRunning, $status.local.tunUp)
