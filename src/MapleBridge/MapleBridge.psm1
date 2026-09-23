Set-StrictMode -Version Latest

function Get-MapleBridgeProcessPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Process
    )

    try {
        return [string] $Process.Path
    }
    catch {
        return $null
    }
}

function Get-MapleBridgeTrafficSnapshot {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $ProcessNamePattern = '(?i)(maplestory|nexon)'
    )

    $allProcesses = @(Get-Process -ErrorAction Stop)
    $matchedProcesses = @(
        $allProcesses |
            Where-Object { $_.ProcessName -match $ProcessNamePattern } |
            Sort-Object -Property ProcessName, Id
    )

    $processById = @{}
    $processRecords = @(
        foreach ($process in $matchedProcesses) {
            $processById[[uint32] $process.Id] = [string] $process.ProcessName

            [pscustomobject] [ordered] @{
                processName   = [string] $process.ProcessName
                processId     = [uint32] $process.Id
                executablePath = Get-MapleBridgeProcessPath -Process $process
            }
        }
    )

    $tcpRecords = @(
        if ($processById.Count -gt 0) {
            Get-NetTCPConnection -ErrorAction Stop |
                Where-Object { $processById.ContainsKey([uint32] $_.OwningProcess) } |
                ForEach-Object {
                    [pscustomobject] [ordered] @{
                        processName  = $processById[[uint32] $_.OwningProcess]
                        processId    = [uint32] $_.OwningProcess
                        state        = [string] $_.State
                        localAddress = [string] $_.LocalAddress
                        localPort    = [uint16] $_.LocalPort
                        remoteAddress = [string] $_.RemoteAddress
                        remotePort   = [uint16] $_.RemotePort
                    }
                } |
                Sort-Object -Property processName, processId, remoteAddress, remotePort
        }
    )

    $udpRecords = @(
        if ($processById.Count -gt 0) {
            Get-NetUDPEndpoint -ErrorAction Stop |
                Where-Object { $processById.ContainsKey([uint32] $_.OwningProcess) } |
                ForEach-Object {
                    [pscustomobject] [ordered] @{
                        processName  = $processById[[uint32] $_.OwningProcess]
                        processId    = [uint32] $_.OwningProcess
                        localAddress = [string] $_.LocalAddress
                        localPort    = [uint16] $_.LocalPort
                    }
                } |
                Sort-Object -Property processName, processId, localAddress, localPort
        }
    )

    [pscustomobject] [ordered] @{
        schemaVersion      = 1
        capturedAtUtc      = [DateTimeOffset]::UtcNow.ToString('o')
        processNamePattern = $ProcessNamePattern
        processes          = $processRecords
        tcpConnections     = $tcpRecords
        udpEndpoints       = $udpRecords
    }
}

function ConvertTo-MapleBridgeYamlScalar {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory)]
        [string] $Value
    )

    return "'{0}'" -f $Value.Replace("'", "''")
}

function Test-MapleBridgeWireGuardKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    if ($Value -notmatch '^[A-Za-z0-9+/]{43}=$') {
        return $false
    }

    try {
        $bytes = [Convert]::FromBase64String($Value)
        return $bytes.Length -eq 32
    }
    catch {
        return $false
    }
}

function Test-MapleBridgeIPv4Cidr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    if ($Value -notmatch '^([^/]+)/([0-9]|[12][0-9]|3[0-2])$') {
        return $false
    }

    $address = $null
    if (-not [Net.IPAddress]::TryParse($Matches[1], [ref] $address)) {
        return $false
    }

    return $address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork
}

function Write-MapleBridgeMihomoConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Selective', 'DiagnosticFullTunnel')]
        [string] $Mode,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ServerAddress,

        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int] $ServerPort,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ServerPublicKey,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ClientAddress,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ClientPrivateKeyPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $OutputPath,

        [bool] $TunEnabled = $true,

        [ValidateRange(0, 65535)]
        [int] $MixedPort = 0,

        [string[]] $ProcessNames = @(
            'nexon_launcher.exe',
            'nexon_updater.exe',
            'nexon_agent.exe',
            'nexon_client.exe',
            'nexon_runtime.exe',
            'MapleStory.exe',
            'BlackXchg.aes',
            'BlackCipher64.aes',
            'DwarfAxe.exe',
            'MapleBrowser_WZ2.exe',
            'CrashReportClient.exe'
        ),

        [string[]] $DomainSuffixes = @('nexonstatic.com', 'xsolla.com', 'xsolla.net')
    )

    $serverIp = $null
    if (-not [Net.IPAddress]::TryParse($ServerAddress, [ref] $serverIp) -or
        $serverIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'ServerAddress must be an IPv4 address for the bootstrap configuration.'
    }

    if (-not (Test-MapleBridgeWireGuardKey -Value $ServerPublicKey)) {
        throw 'ServerPublicKey must be a base64-encoded 32-byte WireGuard public key.'
    }

    if (-not (Test-MapleBridgeIPv4Cidr -Value $ClientAddress)) {
        throw 'ClientAddress must be an IPv4 CIDR address.'
    }

    $resolvedPrivateKeyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ClientPrivateKeyPath)
    if (-not (Test-Path -LiteralPath $resolvedPrivateKeyPath -PathType Leaf)) {
        throw 'The client private key file does not exist.'
    }

    $clientPrivateKey = (Get-Content -LiteralPath $resolvedPrivateKeyPath -Raw -ErrorAction Stop).Trim()
    if (-not (Test-MapleBridgeWireGuardKey -Value $clientPrivateKey)) {
        throw 'The client private key file must contain one base64-encoded 32-byte WireGuard private key.'
    }

    $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if ($resolvedOutputPath -eq $resolvedPrivateKeyPath) {
        throw 'OutputPath must not overwrite the client private key file.'
    }

    $normalizedProcessNames = @(
        $ProcessNames |
            ForEach-Object { [string] $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    if ($Mode -eq 'Selective' -and $normalizedProcessNames.Count -eq 0) {
        throw 'Selective mode requires at least one process name.'
    }

    foreach ($processName in $normalizedProcessNames) {
        if ($processName -match '[,\r\n]') {
            throw 'Process names must not contain commas or line breaks.'
        }
    }

    $normalizedDomainSuffixes = @(
        $DomainSuffixes |
            ForEach-Object { ([string] $_).Trim().TrimStart('.').ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
    foreach ($domainSuffix in $normalizedDomainSuffixes) {
        if ($domainSuffix -notmatch '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$') {
            throw 'Domain suffixes must be valid DNS names without commas or line breaks.'
        }
    }

    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Generated by MapleBridge. Contains a private key; do not commit or share.')
    $lines.Add('mode: rule')
    $lines.Add('log-level: info')
    $lines.Add('ipv6: false')
    if ($MixedPort -gt 0) {
        $lines.Add(('mixed-port: {0}' -f $MixedPort))
        $lines.Add('allow-lan: false')
        $lines.Add("bind-address: '127.0.0.1'")
    }
    $lines.Add('')
    $lines.Add('tun:')
    $lines.Add(('  enable: {0}' -f $TunEnabled.ToString().ToLowerInvariant()))
    $lines.Add('  stack: mixed')
    $lines.Add('  auto-route: true')
    $lines.Add('  auto-detect-interface: true')
    $lines.Add('  strict-route: true')
    $lines.Add('  dns-hijack:')
    $lines.Add("    - 'any:53'")
    $lines.Add("    - 'tcp://any:53'")
    $lines.Add('')
    $lines.Add('dns:')
    $lines.Add('  enable: true')
    $lines.Add('  ipv6: false')
    $lines.Add('  enhanced-mode: redir-host')
    $lines.Add('  default-nameserver:')
    $lines.Add('    - 1.1.1.1')
    $lines.Add('  proxy-server-nameserver:')
    $lines.Add('    - system')

    if ($Mode -eq 'DiagnosticFullTunnel') {
        $lines.Add('  nameserver:')
        $lines.Add("    - 'https://1.1.1.1/dns-query#MapleBridge-US'")
    }
    else {
        $lines.Add('  nameserver:')
        $lines.Add('    - system')
        $lines.Add('  nameserver-policy:')
        $lines.Add("    'geosite:nexon': 'https://1.1.1.1/dns-query#MapleBridge-US'")
    }

    $lines.Add('')
    $lines.Add('proxies:')
    $lines.Add("  - name: 'MapleBridge-US'")
    $lines.Add('    type: wireguard')
    $lines.Add(('    server: {0}' -f (ConvertTo-MapleBridgeYamlScalar -Value $ServerAddress)))
    $lines.Add(('    port: {0}' -f $ServerPort))
    $lines.Add(('    ip: {0}' -f (ConvertTo-MapleBridgeYamlScalar -Value $ClientAddress)))
    $lines.Add(('    private-key: {0}' -f (ConvertTo-MapleBridgeYamlScalar -Value $clientPrivateKey)))
    $lines.Add(('    public-key: {0}' -f (ConvertTo-MapleBridgeYamlScalar -Value $ServerPublicKey)))
    $lines.Add("    allowed-ips: ['0.0.0.0/0']")
    $lines.Add('    udp: true')
    $lines.Add('    persistent-keepalive: 25')
    $lines.Add('    remote-dns-resolve: true')
    $lines.Add('    dns: [1.1.1.1]')
    $lines.Add('')
    $lines.Add('rules:')

    if ($Mode -eq 'DiagnosticFullTunnel') {
        $lines.Add('  - MATCH,MapleBridge-US')
    }
    else {
        foreach ($processName in $normalizedProcessNames) {
            $lines.Add(('  - PROCESS-NAME,{0},MapleBridge-US' -f $processName))
        }
        foreach ($domainSuffix in $normalizedDomainSuffixes) {
            $lines.Add(('  - DOMAIN-SUFFIX,{0},MapleBridge-US' -f $domainSuffix))
        }
        $lines.Add('  - GEOSITE,nexon,MapleBridge-US')
        $lines.Add('  - MATCH,DIRECT')
    }

    $outputDirectory = Split-Path $resolvedOutputPath -Parent
    if (-not (Test-Path -LiteralPath $outputDirectory)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }

    $temporaryPath = '{0}.{1}.tmp' -f $resolvedOutputPath, [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllLines($temporaryPath, $lines, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $resolvedOutputPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    [pscustomobject] [ordered] @{
        path            = $resolvedOutputPath
        mode            = $Mode
        processNames    = $normalizedProcessNames
        containsSecrets = $true
    }
}

function Invoke-MapleBridgeAwsCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AwsExecutable,

        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowEmptyOutput
    )

    $command = Get-Command $AwsExecutable -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'AWS CLI v2 was not found. Install it separately before running AWS readiness checks.'
    }

    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ('maplebridge-aws-{0}.stderr' -f [Guid]::NewGuid().ToString('N'))
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $command.Source @Arguments 2> $stderrPath)
        $exitCode = $LASTEXITCODE
        $stderr = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath).Trim() } else { '' }

        if ($exitCode -ne 0) {
            $operation = if ($Arguments.Count -ge 2) { '{0} {1}' -f $Arguments[0], $Arguments[1] } else { 'unknown operation' }
            $details = @($output) + @($stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }
            $detailText = $details -join [Environment]::NewLine
            if ($detailText -match '(?s)(aws: \[ERROR\]:.*)') { $detailText = $Matches[1] }
            $detailText = $detailText -replace '(?<![0-9])[0-9]{12}(?![0-9])', '<account-id>'
            $detailText = $detailText -replace 'authorization-details/[A-Za-z0-9]+', 'authorization-details/<redacted>'
            $detailText = $detailText -replace 'authorization id: [A-Za-z0-9]+', 'authorization id: <redacted>'
            throw ('AWS CLI command failed for {0}: {1}' -f $operation, $detailText.Trim())
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force
        }
    }

    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json) -and $AllowEmptyOutput) { return $null }
    try {
        return $json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'AWS CLI returned output that was not valid JSON.'
    }
}

function Test-MapleBridgeAwsReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_.-]+$')]
        [string] $ProfileName,

        [ValidateSet('us-west-2')]
        [string] $Region = 'us-west-2',

        [ValidatePattern('^us-west-2[a-z]$')]
        [string] $AvailabilityZone = 'us-west-2a',

        [ValidatePattern('^[A-Za-z0-9_.-]+$')]
        [string] $BlueprintId = 'ubuntu_24_04',

        [ValidatePattern('^[A-Za-z0-9_.-]+$')]
        [string] $BundleId = 'nano_3_0',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TemplatePath,

        [ValidateNotNullOrEmpty()]
        [string] $AwsExecutable = 'aws'
    )

    $resolvedTemplatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TemplatePath)
    if (-not (Test-Path -LiteralPath $resolvedTemplatePath -PathType Leaf)) {
        throw 'The CloudFormation template file does not exist.'
    }

    $commonArguments = @('--profile', $ProfileName, '--region', $Region, '--output', 'json', '--no-cli-pager')

    $identity = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('sts', 'get-caller-identity') + $commonArguments)
    if ([string]::IsNullOrWhiteSpace([string] $identity.Account) -or
        [string]::IsNullOrWhiteSpace([string] $identity.Arn)) {
        throw 'AWS STS did not return a usable caller identity.'
    }

    $regionsQuery = '{regions: regions[].{name:name,availabilityZones:availabilityZones[].{zoneName:zoneName,state:state}}}'
    $regionsResponse = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('lightsail', 'get-regions', '--include-availability-zones', '--query', $regionsQuery) + $commonArguments)
    $regionRecord = @($regionsResponse.regions | Where-Object { $_.name -eq $Region }) | Select-Object -First 1
    if ($null -eq $regionRecord) {
        throw ('Lightsail did not report region {0}.' -f $Region)
    }
    $zoneRecord = @($regionRecord.availabilityZones | Where-Object { $_.zoneName -eq $AvailabilityZone -and $_.state -eq 'available' }) | Select-Object -First 1
    if ($null -eq $zoneRecord) {
        throw ('Lightsail availability zone {0} is not available.' -f $AvailabilityZone)
    }

    $blueprintsQuery = '{blueprints: blueprints[?blueprintId==`__BLUEPRINT_ID__`].{blueprintId:blueprintId,name:name,isActive:isActive}}'.Replace('__BLUEPRINT_ID__', $BlueprintId)
    $blueprintsResponse = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('lightsail', 'get-blueprints', '--include-inactive', '--query', $blueprintsQuery) + $commonArguments)
    $blueprint = @($blueprintsResponse.blueprints | Where-Object { $_.blueprintId -eq $BlueprintId }) | Select-Object -First 1
    if ($null -eq $blueprint -or -not [bool] $blueprint.isActive) {
        throw ('Lightsail blueprint {0} is unavailable or inactive.' -f $BlueprintId)
    }

    $bundlesQuery = '{bundles: bundles[?bundleId==`__BUNDLE_ID__`].{bundleId:bundleId,name:name,isActive:isActive,price:price,cpuCount:cpuCount,ramSizeInGb:ramSizeInGb,diskSizeInGb:diskSizeInGb,transferPerMonthInGb:transferPerMonthInGb}}'.Replace('__BUNDLE_ID__', $BundleId)
    $bundlesResponse = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('lightsail', 'get-bundles', '--include-inactive', '--query', $bundlesQuery) + $commonArguments)
    $bundle = @($bundlesResponse.bundles | Where-Object { $_.bundleId -eq $BundleId }) | Select-Object -First 1
    if ($null -eq $bundle -or -not [bool] $bundle.isActive) {
        throw ('Lightsail bundle {0} is unavailable or inactive.' -f $BundleId)
    }

    $templateUri = 'file://{0}' -f $resolvedTemplatePath
    $null = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'validate-template', '--template-body', $templateUri) + $commonArguments)

    [pscustomobject] [ordered] @{
        profileName            = $ProfileName
        region                 = $Region
        availabilityZone       = $AvailabilityZone
        callerIdentityVerified = $true
        blueprintId            = [string] $blueprint.blueprintId
        blueprintName          = [string] $blueprint.name
        bundleId               = [string] $bundle.bundleId
        bundleName             = [string] $bundle.name
        monthlyPriceUsd        = [decimal] $bundle.price
        cpuCount               = [int] $bundle.cpuCount
        ramSizeInGb            = [decimal] $bundle.ramSizeInGb
        diskSizeInGb           = [int] $bundle.diskSizeInGb
        transferPerMonthInGb   = [int] $bundle.transferPerMonthInGb
        templateValid          = $true
    }
}

function Reset-MapleBridgeClashProfilePresentation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProfilesYamlPath,

        [ValidatePattern('^[A-Za-z0-9_.-]+$')]
        [string] $ProfileUid = 'LMapleBridge'
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilesYamlPath)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw 'The Clash Verge profiles.yaml file does not exist.'
    }

    $lines = [Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadAllLines($resolvedPath)) { $lines.Add($line) }

    $start = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -eq ('- uid: {0}' -f $ProfileUid)) { $start = $index; break }
    }
    if ($start -lt 0) { throw ('Clash profile UID {0} was not found.' -f $ProfileUid) }

    $end = $lines.Count
    for ($index = $start + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^- uid: ') { $end = $index; break }
    }

    for ($index = $end - 1; $index -gt $start; $index--) {
        if ($lines[$index] -match '^  (desc|updated):') {
            $lines.RemoveAt($index)
            $end--
            continue
        }
        if ($lines[$index] -match '^  extra:') {
            $removeEnd = $index + 1
            while ($removeEnd -lt $end -and $lines[$removeEnd] -match '^    ') { $removeEnd++ }
            for ($removeIndex = $removeEnd - 1; $removeIndex -ge $index; $removeIndex--) { $lines.RemoveAt($removeIndex) }
            $end -= ($removeEnd - $index)
        }
    }

    $insertAt = $end
    for ($index = $start + 1; $index -lt $end; $index++) {
        if ($lines[$index] -match '^  option:') { $insertAt = $index; break }
    }

    $lines.Insert($insertAt, '  desc: Generated locally by MapleBridge')

    $temporaryPath = '{0}.{1}.tmp' -f $resolvedPath, [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllLines($temporaryPath, $lines, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $resolvedPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
}

function Repair-MapleBridgeClashProfileIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProfilesYamlPath,

        [string[]] $OwnedUids = @('mMapleBridge', 'sMapleBridge', 'rMapleBridge', 'pMapleBridge', 'gMapleBridge', 'LMapleBridge')
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilesYamlPath)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { throw 'The Clash Verge profiles.yaml file does not exist.' }
    $inputLines = [IO.File]::ReadAllLines($resolvedPath)
    $outputLines = [Collections.Generic.List[string]]::new()
    $seen = @{}
    $removed = 0
    $index = 0
    while ($index -lt $inputLines.Count) {
        if ($inputLines[$index] -match '^- uid: (.+)$') {
            $uid = $Matches[1].Trim()
            $blockEnd = $index + 1
            while ($blockEnd -lt $inputLines.Count -and $inputLines[$blockEnd] -notmatch '^- uid: ') { $blockEnd++ }
            if ($OwnedUids -contains $uid -and $seen.ContainsKey($uid)) {
                $removed++
                $index = $blockEnd
                continue
            }
            if ($OwnedUids -contains $uid) { $seen[$uid] = $true }
            while ($index -lt $blockEnd) { $outputLines.Add($inputLines[$index]); $index++ }
            continue
        }
        $outputLines.Add($inputLines[$index])
        $index++
    }

    if ($removed -gt 0) {
        $temporaryPath = '{0}.{1}.tmp' -f $resolvedPath, [Guid]::NewGuid().ToString('N')
        try {
            [IO.File]::WriteAllLines($temporaryPath, $outputLines, [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $temporaryPath -Destination $resolvedPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
    }
    return $removed
}

function Remove-MapleBridgeClashProfileIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProfilesYamlPath,

        [string[]] $OwnedUids = @('mMapleBridge', 'sMapleBridge', 'rMapleBridge', 'pMapleBridge', 'gMapleBridge', 'LMapleBridge')
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilesYamlPath)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) { throw 'The Clash Verge profiles.yaml file does not exist.' }

    $inputLines = [IO.File]::ReadAllLines($resolvedPath)
    $outputLines = [Collections.Generic.List[string]]::new()
    $remainingUids = [Collections.Generic.List[string]]::new()
    $removed = 0
    $index = 0
    while ($index -lt $inputLines.Count) {
        if ($inputLines[$index] -match '^- uid: (.+)$') {
            $uid = $Matches[1].Trim()
            $blockEnd = $index + 1
            while ($blockEnd -lt $inputLines.Count -and $inputLines[$blockEnd] -notmatch '^- uid: ') { $blockEnd++ }
            if ($OwnedUids -contains $uid) {
                $removed++
                $index = $blockEnd
                continue
            }
            $remainingUids.Add($uid)
            while ($index -lt $blockEnd) { $outputLines.Add($inputLines[$index]); $index++ }
            continue
        }
        $outputLines.Add($inputLines[$index])
        $index++
    }

    $fallbackUid = if ($remainingUids.Count -gt 0) { $remainingUids[0] } else { 'null' }
    for ($lineIndex = 0; $lineIndex -lt $outputLines.Count; $lineIndex++) {
        if ($outputLines[$lineIndex] -match '^current:\s*(.+)$' -and $OwnedUids -contains $Matches[1].Trim()) {
            $outputLines[$lineIndex] = 'current: {0}' -f $fallbackUid
            break
        }
    }

    if ($removed -gt 0) {
        $temporaryPath = '{0}.{1}.tmp' -f $resolvedPath, [Guid]::NewGuid().ToString('N')
        try {
            [IO.File]::WriteAllLines($temporaryPath, $outputLines, [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $temporaryPath -Destination $resolvedPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force }
        }
    }

    [pscustomobject] [ordered] @{
        removedEntries = $removed
        activeProfile  = $fallbackUid
    }
}

function Get-MapleBridgeMetricSum {
    [CmdletBinding()]
    param([AllowNull()][object[]] $MetricData)

    [double] $sum = 0
    foreach ($point in @($MetricData)) {
        if ($null -ne $point) {
            $property = $point.PSObject.Properties['sum']
            if ($null -ne $property -and $null -ne $property.Value) { $sum += [double] $property.Value }
        }
    }
    return [long] [Math]::Round($sum)
}

function Get-MapleBridgeMetricMaximum {
    [CmdletBinding()]
    param([AllowNull()][object[]] $MetricData)

    [double] $maximum = 0
    foreach ($point in @($MetricData)) {
        if ($null -ne $point) {
            $property = $point.PSObject.Properties['maximum']
            if ($null -ne $property -and $null -ne $property.Value) {
                $maximum = [Math]::Max($maximum, [double] $property.Value)
            }
        }
    }
    return [long] [Math]::Ceiling($maximum)
}

Export-ModuleMember -Function Get-MapleBridgeTrafficSnapshot, Write-MapleBridgeMihomoConfig, Invoke-MapleBridgeAwsCli, Test-MapleBridgeAwsReadiness, Reset-MapleBridgeClashProfilePresentation, Repair-MapleBridgeClashProfileIndex, Remove-MapleBridgeClashProfileIndex, Get-MapleBridgeMetricSum, Get-MapleBridgeMetricMaximum
