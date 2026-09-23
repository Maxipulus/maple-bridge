[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$git = Get-Command git -ErrorAction Stop
$gitArguments = @('-c', ('safe.directory={0}' -f $repositoryRoot))

function Invoke-ReleaseGit {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $output = @(& $git.Source @gitArguments @Arguments)
    if ($LASTEXITCODE -ne 0) { throw ('git {0} failed.' -f ($Arguments -join ' ')) }
    return $output
}

$relativePaths = @(Invoke-ReleaseGit -Arguments @('ls-files', '--cached', '--others', '--exclude-standard'))
$failures = [Collections.Generic.List[string]]::new()

if ($relativePaths -contains 'tests/state/aws-gateway.json' -or (Test-Path -LiteralPath (Join-Path $repositoryRoot 'tests\state'))) {
    $failures.Add('Generated runtime data exists under tests/state; move fixtures to TestDrive and remove this directory.')
}

$textExtensions = @('.cmd', '.gitignore', '.gitattributes', '.json', '.md', '.ps1', '.psm1', '.sh', '.yaml', '.yml')
$patterns = [ordered] @{
    AwsManagedNodeId = '\bmi-[0-9a-f]{17}\b'
    AwsMaintenanceWindowId = '\bmw-[0-9a-f]{17}\b'
    AwsAccessKeyId = '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'
    PemPrivateKey = '-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----'
    WindowsUserProfile = '(?i)C:\\Users\\(?!<[^>]+>\\)[^\\\r\n]+\\'
    UnixUserHome = '(?m)/' + 'home/(?!<[^>]+>/)[^/\s]+/'
}

foreach ($relativePath in $relativePaths) {
    $fullPath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
    $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    if ($relativePath -notin @('.gitignore', '.gitattributes') -and $extension -notin $textExtensions) { continue }
    $content = [IO.File]::ReadAllText($fullPath)
    foreach ($pattern in $patterns.GetEnumerator()) {
        if ($content -match $pattern.Value) {
            $failures.Add(('{0}: matched {1}' -f $relativePath, $pattern.Key))
        }
    }
    foreach ($match in [regex]::Matches($content, '(?<![0-9])[0-9]{12}(?![0-9])')) {
        if ($match.Value -ne '123456789012') {
            $failures.Add(('{0}: matched a non-placeholder 12-digit AWS account ID' -f $relativePath))
            break
        }
    }
}

$commitEmails = @(Invoke-ReleaseGit -Arguments @('log', '--format=%ae%n%ce'))
foreach ($email in $commitEmails | Sort-Object -Unique) {
    if ($email -notmatch '^(?:[0-9]+\+)?[A-Za-z0-9-]+@users\.noreply\.github\.com$') {
        $failures.Add('Git history contains an author or committer email that is not a GitHub noreply address.')
    }
}

if ($failures.Count -gt 0) {
    $uniqueFailures = @($failures | Sort-Object -Unique)
    $uniqueFailures | ForEach-Object { Write-Host ('ERROR: {0}' -f $_) -ForegroundColor Red }
    throw ('Release-safety checks failed with {0} finding(s).' -f $uniqueFailures.Count)
}

Write-Host ('Release-safety checks passed for {0} publishable files and commit metadata.' -f $relativePaths.Count)
