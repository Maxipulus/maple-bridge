[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int] $DurationSeconds = 180,

    [ValidateRange(50, 5000)]
    [int] $PollMilliseconds = 250,

    [ValidateNotNullOrEmpty()]
    [string] $RootProcessNamePattern = '(?i)(maplestory|nexon)',

    [string] $OutputPath,

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $fileName = 'process-trace-{0}.json' -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $OutputPath = Join-Path $repositoryRoot (Join-Path 'state\observations' $fileName)
}

$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outputDirectory = Split-Path $resolvedOutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
}

function ConvertTo-ProcessRecord {
    param(
        [Parameter(Mandatory)]
        [object] $Process
    )

    [pscustomobject] [ordered] @{
        processName    = [string] $Process.Name
        processId      = [uint32] $Process.ProcessId
        parentProcessId = [uint32] $Process.ParentProcessId
        sessionId      = [uint32] $Process.SessionId
        executablePath = if ($null -eq $Process.ExecutablePath) { $null } else { [string] $Process.ExecutablePath }
    }
}

function Add-NetworkObservations {
    param(
        [Parameter(Mandatory)]
        [hashtable] $TrackedProcessIds,

        [Parameter(Mandatory)]
        [hashtable] $ProcessById,

        [Parameter(Mandatory)]
        [hashtable] $TcpByKey,

        [Parameter(Mandatory)]
        [hashtable] $UdpByKey
    )

    if ($TrackedProcessIds.Count -eq 0) {
        return
    }

    $observedAt = [DateTimeOffset]::UtcNow.ToString('o')
    try {
        foreach ($connection in @(Get-NetTCPConnection -ErrorAction Stop)) {
            $processId = [uint32] $connection.OwningProcess
            if (-not $TrackedProcessIds.ContainsKey($processId)) {
                continue
            }

            $key = '{0}|{1}|{2}|{3}|{4}|{5}' -f $processId, $connection.State, $connection.LocalAddress, $connection.LocalPort, $connection.RemoteAddress, $connection.RemotePort
            if ($TcpByKey.ContainsKey($key)) {
                $TcpByKey[$key].lastSeenAtUtc = $observedAt
                continue
            }

            $TcpByKey[$key] = [pscustomobject] [ordered] @{
                processName  = [string] $ProcessById[$processId].processName
                processId    = $processId
                state        = [string] $connection.State
                localAddress = [string] $connection.LocalAddress
                localPort    = [uint16] $connection.LocalPort
                remoteAddress = [string] $connection.RemoteAddress
                remotePort   = [uint16] $connection.RemotePort
                firstSeenAtUtc = $observedAt
                lastSeenAtUtc = $observedAt
            }
        }
    }
    catch {
        Write-Warning ('TCP sampling failed: {0}' -f $_.Exception.Message)
    }

    try {
        foreach ($endpoint in @(Get-NetUDPEndpoint -ErrorAction Stop)) {
            $processId = [uint32] $endpoint.OwningProcess
            if (-not $TrackedProcessIds.ContainsKey($processId)) {
                continue
            }

            $key = '{0}|{1}|{2}' -f $processId, $endpoint.LocalAddress, $endpoint.LocalPort
            if ($UdpByKey.ContainsKey($key)) {
                $UdpByKey[$key].lastSeenAtUtc = $observedAt
                continue
            }

            $UdpByKey[$key] = [pscustomobject] [ordered] @{
                processName  = [string] $ProcessById[$processId].processName
                processId    = $processId
                localAddress = [string] $endpoint.LocalAddress
                localPort    = [uint16] $endpoint.LocalPort
                firstSeenAtUtc = $observedAt
                lastSeenAtUtc = $observedAt
            }
        }
    }
    catch {
        Write-Warning ('UDP sampling failed: {0}' -f $_.Exception.Message)
    }
}

$startedAt = [DateTimeOffset]::UtcNow
$initialProcesses = @(
    Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
        ForEach-Object { ConvertTo-ProcessRecord -Process $_ } |
        Sort-Object -Property processName, processId
)

$processById = @{}
foreach ($process in $initialProcesses) {
    $processById[[uint32] $process.processId] = $process
}

$trackedProcessIds = @{}
$changed = $true
while ($changed) {
    $changed = $false
    foreach ($process in $processById.Values) {
        $processId = [uint32] $process.processId
        $parentProcessId = [uint32] $process.parentProcessId
        if (-not $trackedProcessIds.ContainsKey($processId) -and
            (($process.processName -match $RootProcessNamePattern) -or $trackedProcessIds.ContainsKey($parentProcessId))) {
            $trackedProcessIds[$processId] = $true
            $changed = $true
        }
    }
}

$processEvents = [Collections.Generic.List[object]]::new()
$tcpByKey = @{}
$udpByKey = @{}
$sourcePrefix = 'MapleBridge.ProcessTrace.{0}' -f [Guid]::NewGuid().ToString('N')
$startSource = '{0}.Start' -f $sourcePrefix
$stopSource = '{0}.Stop' -f $sourcePrefix
$eventPollSeconds = [math]::Max(0.1, $PollMilliseconds / 1000.0)
$startQuery = "SELECT * FROM __InstanceCreationEvent WITHIN $eventPollSeconds WHERE TargetInstance ISA 'Win32_Process'"
$stopQuery = "SELECT * FROM __InstanceDeletionEvent WITHIN $eventPollSeconds WHERE TargetInstance ISA 'Win32_Process'"

Write-Host ('Monitoring all process start/stop events for {0} seconds...' -f $DurationSeconds)
Write-Host ('Initial process inventory: {0} processes. Candidate roots/descendants: {1}.' -f $initialProcesses.Count, $trackedProcessIds.Count)

try {
    # Process trace classes require elevated WMI permissions on some Windows systems.
    # Intrinsic instance events work as a standard user and still preserve parent/child data.
    $null = Register-CimIndicationEvent -Query $startQuery -Namespace 'root/cimv2' -SourceIdentifier $startSource
    $null = Register-CimIndicationEvent -Query $stopQuery -Namespace 'root/cimv2' -SourceIdentifier $stopSource

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($DurationSeconds)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $events = @(
            Get-Event -SourceIdentifier "$sourcePrefix.*" -ErrorAction SilentlyContinue |
                Sort-Object -Property TimeGenerated
        )

        foreach ($eventRecord in $events) {
            $eventData = $eventRecord.SourceEventArgs.NewEvent.TargetInstance
            $isStart = $eventRecord.SourceIdentifier -eq $startSource
            $processId = [uint32] $eventData.ProcessID
            $parentProcessId = [uint32] $eventData.ParentProcessID
            $processName = [string] $eventData.Name
            $executablePath = if ($null -eq $eventData.ExecutablePath) { $null } else { [string] $eventData.ExecutablePath }

            if ($isStart) {
                $isCandidate = ($processName -match $RootProcessNamePattern) -or $trackedProcessIds.ContainsKey($parentProcessId)
                $processById[$processId] = [pscustomobject] [ordered] @{
                    processName    = $processName
                    processId      = $processId
                    parentProcessId = $parentProcessId
                    sessionId      = [uint32] $eventData.SessionID
                    executablePath = $executablePath
                }
                if ($isCandidate) {
                    $trackedProcessIds[$processId] = $true
                }
            }
            else {
                $isCandidate = $trackedProcessIds.ContainsKey($processId)
            }

            $processEvents.Add([pscustomobject] [ordered] @{
                observedAtUtc = ([DateTimeOffset] $eventRecord.TimeGenerated).ToUniversalTime().ToString('o')
                eventType     = if ($isStart) { 'start' } else { 'stop' }
                processName   = $processName
                processId     = $processId
                parentProcessId = $parentProcessId
                candidate     = [bool] $isCandidate
                executablePath = if ($isCandidate) { $executablePath } else { $null }
                exitStatus    = $null
            })

            Remove-Event -EventIdentifier $eventRecord.EventIdentifier -ErrorAction SilentlyContinue
        }

        # Creation events from one provider poll can share a timestamp. Reconcile the
        # completed graph so a child is still tracked if it was delivered before its parent.
        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($process in $processById.Values) {
                $processId = [uint32] $process.processId
                $parentProcessId = [uint32] $process.parentProcessId
                if (-not $trackedProcessIds.ContainsKey($processId) -and
                    (($process.processName -match $RootProcessNamePattern) -or $trackedProcessIds.ContainsKey($parentProcessId))) {
                    $trackedProcessIds[$processId] = $true
                    $changed = $true
                }
            }
        }
        foreach ($processEvent in $processEvents) {
            if ($trackedProcessIds.ContainsKey([uint32] $processEvent.processId)) {
                $processEvent.candidate = $true
            }
        }

        Add-NetworkObservations -TrackedProcessIds $trackedProcessIds -ProcessById $processById -TcpByKey $tcpByKey -UdpByKey $udpByKey
        Start-Sleep -Milliseconds $PollMilliseconds
    }
}
finally {
    Unregister-Event -SourceIdentifier $startSource -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stopSource -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier "$sourcePrefix.*" -ErrorAction SilentlyContinue |
        Remove-Event -ErrorAction SilentlyContinue
}

$endedAt = [DateTimeOffset]::UtcNow
$startedNames = @(
    $processEvents |
        Where-Object eventType -eq 'start' |
        Select-Object -ExpandProperty processName -Unique |
        Sort-Object
)
$candidateNames = @(
    $processById.Values |
        Where-Object { $trackedProcessIds.ContainsKey([uint32] $_.processId) } |
        Select-Object -ExpandProperty processName -Unique |
        Sort-Object
)

$result = [pscustomobject] [ordered] @{
    schemaVersion          = 1
    startedAtUtc           = $startedAt.ToString('o')
    endedAtUtc             = $endedAt.ToString('o')
    durationSeconds        = [math]::Round(($endedAt - $startedAt).TotalSeconds, 3)
    pollMilliseconds       = $PollMilliseconds
    rootProcessNamePattern = $RootProcessNamePattern
    initialProcesses       = $initialProcesses
    processEvents          = @($processEvents)
    tcpConnections         = @($tcpByKey.Values | Sort-Object processName, processId, remoteAddress, remotePort)
    udpEndpoints           = @($udpByKey.Values | Sort-Object processName, processId, localAddress, localPort)
    summary                = [pscustomobject] [ordered] @{
        initialProcessCount = $initialProcesses.Count
        eventCount          = $processEvents.Count
        startedProcessNames = $startedNames
        candidateProcessNames = $candidateNames
        tcpConnectionCount  = $tcpByKey.Count
        udpEndpointCount    = $udpByKey.Count
    }
}

$result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8
Write-Host ('Process trace written to {0}' -f $resolvedOutputPath)
$candidateNameText = if ($candidateNames.Count -eq 0) { '(none)' } else { $candidateNames -join ', ' }
Write-Host ('Captured {0} events; candidate names: {1}' -f $processEvents.Count, $candidateNameText)

if ($PassThru) {
    $result
}
