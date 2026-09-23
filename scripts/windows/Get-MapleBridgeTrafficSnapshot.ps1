[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string] $ProcessNamePattern = '(?i)(maplestory|nexon)',

    [string] $OutputPath,

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1'
Import-Module $modulePath -Force

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $fileName = 'traffic-{0}.json' -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $OutputPath = Join-Path $repositoryRoot (Join-Path 'state\observations' $fileName)
}

$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outputDirectory = Split-Path $resolvedOutputPath -Parent
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
}

$snapshot = Get-MapleBridgeTrafficSnapshot -ProcessNamePattern $ProcessNamePattern
$snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8

Write-Host ('Traffic snapshot written to {0}' -f $resolvedOutputPath)
if ($PassThru) {
    $snapshot
}
