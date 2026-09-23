[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [string] $StatePath,
    [string] $ClientPublicKeyPath,
    [string] $AwsExecutable = 'aws'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $repositoryRoot 'state\aws-gateway.json'
}
if ([string]::IsNullOrWhiteSpace($ClientPublicKeyPath)) {
    $ClientPublicKeyPath = Join-Path $repositoryRoot 'state\keys\client.pub'
}
$statePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
$publicKeyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ClientPublicKeyPath)
$configureScriptPath = Join-Path $repositoryRoot 'scripts\linux\configure-gateway.sh'
$renderScriptPath = Join-Path $repositoryRoot 'scripts\linux\render-gateway-config.sh'

foreach ($requiredPath in @($statePath, $publicKeyPath, $configureScriptPath, $renderScriptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw ('Required file is missing: {0}' -f $requiredPath)
    }
}

$awsCommand = Get-Command $AwsExecutable -ErrorAction SilentlyContinue
if ($null -eq $awsCommand) { throw 'AWS CLI v2 was not found.' }
$awsPath = $awsCommand.Source
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($state.region -ne 'us-west-2' -or [string]::IsNullOrWhiteSpace([string] $state.managedNodeId)) {
    throw 'The gateway state does not identify a managed node in us-west-2.'
}
$clientPublicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()
if ($clientPublicKey -notmatch '^[A-Za-z0-9+/]{43}=$' -or [Convert]::FromBase64String($clientPublicKey).Length -ne 32) {
    throw 'The client public key is invalid.'
}

$instanceInformation = & $awsPath ssm describe-instance-information --profile $ProfileName --region $state.region --filters ('Key=InstanceIds,Values={0}' -f $state.managedNodeId) --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or @($instanceInformation.InstanceInformationList).Count -ne 1 -or $instanceInformation.InstanceInformationList[0].PingStatus -ne 'Online') {
    throw 'The gateway managed node is not online.'
}

$configureBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($configureScriptPath))
$renderBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($renderScriptPath))
$remoteDirectory = '/var/lib/maplebridge/deploy'
$commands = @(
    'set -eu',
    ('install -d -m 0755 {0}' -f $remoteDirectory),
    ("printf '%s' '{0}' | base64 -d > {1}/configure-gateway.sh" -f $configureBase64, $remoteDirectory),
    ("printf '%s' '{0}' | base64 -d > {1}/render-gateway-config.sh" -f $renderBase64, $remoteDirectory),
    ('chmod 0700 {0}/configure-gateway.sh {0}/render-gateway-config.sh' -f $remoteDirectory),
    ('if ! bash {0}/configure-gateway.sh --client-public-key ''{1}'' --vpn-port {2} --server-address ''10.88.0.1/24'' --client-address ''10.88.0.2/32'' > /var/log/maplebridge-configure.log 2>&1; then tail -n 100 /var/log/maplebridge-configure.log; exit 1; fi' -f $remoteDirectory, $clientPublicKey, [int] $state.vpnPort),
    'test "$(systemctl is-active maplebridge-firewall.service)" = active',
    'test "$(systemctl is-active wg-quick@wg-maplebridge.service)" = active',
    'test "$(sysctl -n net.ipv4.ip_forward)" = 1',
    'nft list table inet maplebridge_filter >/dev/null',
    'nft list table ip maplebridge_nat >/dev/null',
    'printf "Server public key: "; wg show wg-maplebridge public-key'
)

$parameterPath = Join-Path ([IO.Path]::GetTempPath()) ('maplebridge-gateway-command-{0}.json' -f [Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllText($parameterPath, (@{ commands = $commands } | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Write-Host 'Configuring WireGuard, forwarding, and nftables through SSM Run Command.'
    $response = & $awsPath ssm send-command --profile $ProfileName --region $state.region --instance-ids $state.managedNodeId --document-name AWS-RunShellScript --comment 'Configure MapleBridge gateway' --parameters ('file://{0}' -f $parameterPath) --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'SSM SendCommand failed.' }
    $commandId = [string] $response.Command.CommandId
    & $awsPath ssm wait command-executed --profile $ProfileName --region $state.region --command-id $commandId --instance-id $state.managedNodeId
    $waitExitCode = $LASTEXITCODE
    $invocation = & $awsPath ssm get-command-invocation --profile $ProfileName --region $state.region --command-id $commandId --instance-id $state.managedNodeId --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the gateway configuration result.' }
    if ($waitExitCode -ne 0 -or $invocation.Status -ne 'Success') {
        $details = @($invocation.StandardOutputContent, $invocation.StandardErrorContent) | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }
        throw ('Gateway configuration failed: {0}' -f ($details -join [Environment]::NewLine))
    }
}
finally {
    if (Test-Path -LiteralPath $parameterPath) {
        Remove-Item -LiteralPath $parameterPath -Force
    }
}

if ($invocation.StandardOutputContent -notmatch 'Server public key: ([A-Za-z0-9+/]{43}=)') {
    throw 'Gateway configuration succeeded but did not return a valid server public key.'
}
$serverPublicKey = $Matches[1]
$state | Add-Member -NotePropertyName clientPublicKey -NotePropertyValue $clientPublicKey -Force
$state | Add-Member -NotePropertyName serverPublicKey -NotePropertyValue $serverPublicKey -Force
$state | Add-Member -NotePropertyName gatewayConfigured -NotePropertyValue $true -Force
$state.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'Gateway configuration and health checks succeeded. Public keys were saved to ignored state.'

[pscustomobject] [ordered] @{
    serverPublicKey = $serverPublicKey
    clientPublicKey = $clientPublicKey
    staticIpAddress = [string] $state.staticIpAddress
    vpnPort         = [int] $state.vpnPort
}
