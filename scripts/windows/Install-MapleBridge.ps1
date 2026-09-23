[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [ValidateSet('Selective', 'DiagnosticFullTunnel')]
    [string] $Mode = 'Selective',

    [string] $AwsExecutable = 'aws',

    [switch] $SkipAutomaticMaintenance,

    [Parameter(Mandatory)]
    [switch] $ConfirmPaidDeployment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$privateKeyPath = Join-Path $PSScriptRoot '..\..\state\keys\client.key'
$publicKeyPath = Join-Path $PSScriptRoot '..\..\state\keys\client.pub'
$statePath = Join-Path $PSScriptRoot '..\..\state\aws-gateway.json'
$profilePath = Join-Path $PSScriptRoot '..\..\state\generated\maplebridge.yaml'

$keys = & (Join-Path $PSScriptRoot 'Initialize-MapleBridgeClientKey.ps1') -PrivateKeyPath $privateKeyPath -PublicKeyPath $publicKeyPath
& (Join-Path $PSScriptRoot 'Deploy-MapleBridgeGateway.ps1') -ProfileName $ProfileName -AwsExecutable $AwsExecutable -ConfirmPaidDeployment
$gateway = & (Join-Path $PSScriptRoot 'Configure-MapleBridgeGateway.ps1') -ProfileName $ProfileName -StatePath $statePath -ClientPublicKeyPath $keys.publicKeyPath -AwsExecutable $AwsExecutable
& (Join-Path $PSScriptRoot 'New-MapleBridgeMihomoConfig.ps1') -Mode $Mode -ServerAddress $gateway.staticIpAddress -ServerPort $gateway.vpnPort -ServerPublicKey $gateway.serverPublicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $keys.privateKeyPath -OutputPath $profilePath
& (Join-Path $PSScriptRoot 'Install-MapleBridgeClashProfile.ps1') -SourceProfilePath $profilePath -ReloadClash
& (Join-Path $PSScriptRoot 'Update-MapleBridgeStatus.ps1') -ProfileName $ProfileName -StatePath $statePath -AwsExecutable $AwsExecutable
if (-not $SkipAutomaticMaintenance) {
    & (Join-Path $PSScriptRoot 'Set-MapleBridgeMaintenance.ps1') -ProfileName $ProfileName -StatePath $statePath -AwsExecutable $AwsExecutable
}

Write-Host 'MapleBridge infrastructure, gateway, Clash profile, diagnostics, and automatic security maintenance are ready.'
