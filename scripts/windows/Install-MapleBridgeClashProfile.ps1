[CmdletBinding()]
param(
    [string] $SourceProfilePath,
    [string] $ClashDataDirectory = (Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'),
    [string] $ClashInstallDirectory,
    [switch] $ReloadClash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1'
Import-Module $modulePath -Force
if ([string]::IsNullOrWhiteSpace($SourceProfilePath)) {
    $SourceProfilePath = Join-Path $repositoryRoot 'state\generated\maplebridge.yaml'
}
$source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourceProfilePath)
$dataDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ClashDataDirectory)
$profilesDirectory = Join-Path $dataDirectory 'profiles'
$indexPath = Join-Path $dataDirectory 'profiles.yaml'
if ([string]::IsNullOrWhiteSpace($ClashInstallDirectory)) {
    $runningClash = Get-Process clash-verge -ErrorAction SilentlyContinue | Select-Object -First 1
    $runningPath = if ($null -ne $runningClash) { $runningClash.Path } else { $null }
    $candidateDirectories = @(
        $(if (-not [string]::IsNullOrWhiteSpace($runningPath)) { Split-Path $runningPath -Parent }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Clash Verge' }),
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Clash Verge' }),
        'D:\Clash Verge'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) }
    $ClashInstallDirectory = @($candidateDirectories | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'verge-mihomo.exe') -PathType Leaf }) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($ClashInstallDirectory)) { throw 'Clash Verge installation was not found. Pass -ClashInstallDirectory explicitly.' }
}
$mihomoPath = Join-Path $ClashInstallDirectory 'verge-mihomo.exe'
$clashPath = Join-Path $ClashInstallDirectory 'clash-verge.exe'

foreach ($required in @($source, $indexPath, $mihomoPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Required file is missing: {0}' -f $required) }
}

$validationOutput = @(& $mihomoPath -t -f $source 2>&1)
if ($LASTEXITCODE -ne 0) { throw ('Mihomo rejected the generated profile: {0}' -f ($validationOutput -join [Environment]::NewLine)) }

$stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss')
$backupDirectory = Join-Path $dataDirectory ('maplebridge-backup\{0}' -f $stamp)
$null = New-Item -ItemType Directory -Path $backupDirectory -Force
Copy-Item -LiteralPath $indexPath -Destination (Join-Path $backupDirectory 'profiles.yaml')
foreach ($name in @('LMapleBridge.yaml', 'mMapleBridge.yaml', 'sMapleBridge.js', 'rMapleBridge.yaml', 'pMapleBridge.yaml', 'gMapleBridge.yaml')) {
    $existing = Join-Path $profilesDirectory $name
    if (Test-Path -LiteralPath $existing -PathType Leaf) { Copy-Item -LiteralPath $existing -Destination (Join-Path $backupDirectory $name) }
}
$duplicatesRemoved = Repair-MapleBridgeClashProfileIndex -ProfilesYamlPath $indexPath

$null = New-Item -ItemType Directory -Path $profilesDirectory -Force
Copy-Item -LiteralPath $source -Destination (Join-Path $profilesDirectory 'LMapleBridge.yaml') -Force

$helpers = [ordered] @{
    'mMapleBridge.yaml' = "# Profile Enhancement Merge Template for Clash Verge`n"
    'sMapleBridge.js'   = "// Define main function (script entry)`n`nfunction main(config, profileName) {`n  return config;`n}`n"
    'rMapleBridge.yaml' = "# Profile Enhancement Rules Template for Clash Verge`n`nprepend: []`n`nappend: []`n`ndelete: []`n"
    'pMapleBridge.yaml' = "# Profile Enhancement Proxies Template for Clash Verge`n`nprepend: []`n`nappend: []`n`ndelete: []`n"
    'gMapleBridge.yaml' = "# Profile Enhancement Groups Template for Clash Verge`n`nprepend: []`n`nappend: []`n`ndelete: []`n"
}
foreach ($entry in $helpers.GetEnumerator()) {
    $helperPath = Join-Path $profilesDirectory $entry.Key
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        [IO.File]::WriteAllText($helperPath, $entry.Value, [Text.UTF8Encoding]::new($false))
    }
}

$index = [IO.File]::ReadAllText($indexPath)
if ($index -notmatch '(?m)^- uid: LMapleBridge\r?$') {
    $unix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $entries = @(
        @{ uid = 'mMapleBridge'; type = 'merge'; file = 'mMapleBridge.yaml' },
        @{ uid = 'sMapleBridge'; type = 'script'; file = 'sMapleBridge.js' },
        @{ uid = 'rMapleBridge'; type = 'rules'; file = 'rMapleBridge.yaml' },
        @{ uid = 'pMapleBridge'; type = 'proxies'; file = 'pMapleBridge.yaml' },
        @{ uid = 'gMapleBridge'; type = 'groups'; file = 'gMapleBridge.yaml' }
    )
    $addition = [Text.StringBuilder]::new()
    foreach ($entry in $entries) {
        $null = $addition.AppendLine(('- uid: {0}' -f $entry.uid))
        $null = $addition.AppendLine(('  type: {0}' -f $entry.type))
        $null = $addition.AppendLine('  name: null')
        $null = $addition.AppendLine(('  file: {0}' -f $entry.file))
        $null = $addition.AppendLine(('  updated: {0}' -f $unix))
    }
    $null = $addition.AppendLine('- uid: LMapleBridge')
    $null = $addition.AppendLine('  type: local')
    $null = $addition.AppendLine('  name: MapleBridge')
    $null = $addition.AppendLine('  file: LMapleBridge.yaml')
    $null = $addition.AppendLine('  desc: Generated locally by MapleBridge')
    $null = $addition.AppendLine('  option:')
    $null = $addition.AppendLine('    allow_auto_update: true')
    foreach ($entry in $entries) { $null = $addition.AppendLine(('    {0}: {1}' -f $entry.type, $entry.uid)) }
    $index = $index.TrimEnd() + [Environment]::NewLine + $addition.ToString()
}
$index = [regex]::Replace($index, '(?m)^current:.*$', 'current: LMapleBridge', 1)
[IO.File]::WriteAllText($indexPath, $index, [Text.UTF8Encoding]::new($false))
Reset-MapleBridgeClashProfilePresentation -ProfilesYamlPath $indexPath

if ($ReloadClash) {
    if (-not (Test-Path -LiteralPath $clashPath -PathType Leaf)) { throw ('Clash Verge executable is missing: {0}' -f $clashPath) }
    Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 750
    Start-Process -FilePath $clashPath
}

[pscustomobject] [ordered] @{
    profilePath    = Join-Path $profilesDirectory 'LMapleBridge.yaml'
    profilesIndex = $indexPath
    backupPath     = $backupDirectory
    activeProfile  = 'LMapleBridge'
    reloaded       = [bool] $ReloadClash
    duplicatesRemoved = $duplicatesRemoved
}
