[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [string] $StatePath,
    [string] $ClashDataDirectory = (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'),
    [string] $AwsExecutable = 'aws',
    [switch] $RemoveAwsResources,
    [string] $ConfirmGatewayName,
    [switch] $ConfirmDestructiveRemoval,
    [switch] $RemoveLocalKeys,
    [switch] $ReloadClash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1') -Force
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $repositoryRoot 'state\aws-gateway.json' }
$resolvedStatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
$dataDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ClashDataDirectory)
$profilesDirectory = Join-Path $dataDirectory 'profiles'
$indexPath = Join-Path $dataDirectory 'profiles.yaml'
$ownedFiles = @('LMapleBridge.yaml', 'mMapleBridge.yaml', 'sMapleBridge.js', 'rMapleBridge.yaml', 'pMapleBridge.yaml', 'gMapleBridge.yaml')

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { throw 'The Clash Verge profiles.yaml file does not exist.' }

$stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
$backupDirectory = Join-Path $dataDirectory ('maplebridge-backup\remove-{0}' -f $stamp)
$null = New-Item -ItemType Directory -Path $backupDirectory -Force
Copy-Item -LiteralPath $indexPath -Destination (Join-Path $backupDirectory 'profiles.yaml')
foreach ($name in $ownedFiles) {
    $path = Join-Path $profilesDirectory $name
    if (Test-Path -LiteralPath $path -PathType Leaf) { Copy-Item -LiteralPath $path -Destination (Join-Path $backupDirectory $name) }
}

$profileResult = Remove-MapleBridgeClashProfileIndex -ProfilesYamlPath $indexPath
foreach ($name in $ownedFiles) {
    $path = Join-Path $profilesDirectory $name
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
}

if ($ReloadClash) {
    $runningClash = Get-Process clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $runningClash) {
        $clashPath = $runningClash.Path
        $runningClash | Stop-Process -Force
        Start-Sleep -Milliseconds 750
        Start-Process -FilePath $clashPath
    }
}

if ($RemoveAwsResources) {
    if (-not $ConfirmDestructiveRemoval) { throw 'AWS removal requires -ConfirmDestructiveRemoval.' }
    if ([string]::IsNullOrWhiteSpace($ProfileName)) { throw 'AWS removal requires -ProfileName.' }
    if (-not (Test-Path -LiteralPath $resolvedStatePath -PathType Leaf)) { throw 'Gateway state is missing; refusing AWS removal without an exact target.' }
    $state = Get-Content -LiteralPath $resolvedStatePath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($ConfirmGatewayName) -or $ConfirmGatewayName -cne [string] $state.gatewayName) {
        throw 'ConfirmGatewayName must exactly match the gateway name in state.'
    }
    if ($AwsExecutable -eq 'aws' -and $null -eq (Get-Command $AwsExecutable -ErrorAction SilentlyContinue)) {
        $installedAws = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
        if (Test-Path -LiteralPath $installedAws -PathType Leaf) { $AwsExecutable = $installedAws }
    }
    $common = @('--profile', $ProfileName, '--region', [string] $state.region, '--no-cli-pager')
    $stack = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'describe-stacks', '--stack-name', [string] $state.stackName, '--output', 'json') + $common)
    $stackGateway = [string] (@($stack.Stacks[0].Parameters | Where-Object ParameterKey -EQ 'GatewayName') | Select-Object -First 1).ParameterValue
    if ($stackGateway -cne [string] $state.gatewayName) { throw 'CloudFormation gateway does not match local state; refusing deletion.' }

    $null = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'deregister-managed-instance', '--instance-id', [string] $state.managedNodeId) + $common) -AllowEmptyOutput
    $null = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'delete-stack', '--stack-name', [string] $state.stackName) + $common) -AllowEmptyOutput
    $null = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'wait', 'stack-delete-complete', '--stack-name', [string] $state.stackName) + $common) -AllowEmptyOutput
    Remove-Item -LiteralPath $resolvedStatePath -Force
}

if ($RemoveLocalKeys) {
    if (-not $ConfirmDestructiveRemoval) { throw 'Key removal requires -ConfirmDestructiveRemoval.' }
    foreach ($path in @(
        (Join-Path $repositoryRoot 'state\keys\client.key'),
        (Join-Path $repositoryRoot 'state\keys\client.pub'),
        (Join-Path $repositoryRoot 'state\generated\maplebridge.yaml')
    )) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}

[pscustomobject] [ordered] @{
    localProfileRemoved = $profileResult.removedEntries -gt 0
    awsResourcesRemoved = [bool] $RemoveAwsResources
    localKeysRemoved     = [bool] $RemoveLocalKeys
    backupPath           = $backupDirectory
    activeProfile        = $profileResult.activeProfile
}
