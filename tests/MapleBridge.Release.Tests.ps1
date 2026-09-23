$repoRoot = Split-Path -Parent $PSScriptRoot
$workflowPath = Join-Path $repoRoot '.github\workflows\ci.yml'
$releaseScriptPath = Join-Path $repoRoot 'scripts\windows\Test-MapleBridgeRelease.ps1'

Describe 'MapleBridge release automation' {
    It 'runs separate Windows and Linux offline checks' {
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should Match 'runs-on: windows-latest'
        $workflow | Should Match 'Import-Module Pester -RequiredVersion 3\.4\.0'
        $workflow | Should Match 'Invoke-Pester'
        $workflow | Should Match 'Test-MapleBridgeRelease\.ps1'
        $workflow | Should Match 'fetch-depth: 0'
        $workflow | Should Match 'runs-on: ubuntu-latest'
        $workflow | Should Match 'GatewayConfig\.Tests\.sh'
        $workflow | Should Match 'bash -n'
    }

    It 'does not install software, use AWS credentials, or invoke AWS' {
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should Not Match '(?im)\b(?:Install-Module|apt-get|choco|winget|brew)\b'
        $workflow | Should Not Match '(?im)\baws\s+(?:cloudformation|iam|lightsail|ssm|sts)\b'
        $workflow | Should Not Match '(?im)AWS_(?:ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN)'
        $workflow | Should Match '(?ms)permissions:\s+contents: read'
    }

    It 'checks publishable files, commit metadata, and accidental test state' {
        $releaseScript = Get-Content -LiteralPath $releaseScriptPath -Raw

        $releaseScript | Should Match "'ls-files', '--cached', '--others', '--exclude-standard'"
        $releaseScript | Should Match "'log', '--format=%ae%n%ce'"
        $releaseScript | Should Match 'tests\\state'
        $releaseScript | Should Match 'AwsAccessKeyId'
        $releaseScript | Should Match 'PemPrivateKey'
        $releaseScript | Should Match 'AWS account ID'
    }
}
