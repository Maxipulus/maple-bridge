[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Selective', 'DiagnosticFullTunnel')]
    [string] $Mode,

    [Parameter(Mandatory)]
    [string] $ServerAddress,

    [Parameter(Mandatory)]
    [ValidateRange(1, 65535)]
    [int] $ServerPort,

    [Parameter(Mandatory)]
    [string] $ServerPublicKey,

    [Parameter(Mandatory)]
    [string] $ClientAddress,

    [Parameter(Mandatory)]
    [string] $ClientPrivateKeyPath,

    [string] $OutputPath = '.\state\generated\maplebridge.yaml',

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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1'
Import-Module $modulePath -Force

$generationParameters = @{} + $PSBoundParameters
if (-not $generationParameters.ContainsKey('OutputPath')) {
    $generationParameters.OutputPath = $OutputPath
}
if (-not $generationParameters.ContainsKey('ProcessNames')) {
    $generationParameters.ProcessNames = $ProcessNames
}
if (-not $generationParameters.ContainsKey('DomainSuffixes')) {
    $generationParameters.DomainSuffixes = $DomainSuffixes
}

$result = Write-MapleBridgeMihomoConfig @generationParameters
Write-Host ('Generated {0} Mihomo configuration at {1}' -f $result.mode, $result.path)
Write-Warning 'The generated file contains a WireGuard private key. Keep it under ignored state/ and do not share it.'
