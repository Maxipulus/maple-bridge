$repoRoot = Split-Path -Parent $PSScriptRoot
$prerequisitesPath = Join-Path $repoRoot 'docs\windows-prerequisites.md'
$costsPath = Join-Path $repoRoot 'docs\costs.md'

Describe 'MapleBridge deployment documentation' {
    It 'keeps README documentation links resolvable' {
        foreach ($readmeName in @('README.md', 'README.zh-CN.md')) {
            $readme = Get-Content -LiteralPath (Join-Path $repoRoot $readmeName) -Raw
            $matches = [regex]::Matches($readme, '\((docs/[^)#]+\.md)\)')
            foreach ($match in $matches) {
                $target = Join-Path $repoRoot ($match.Groups[1].Value -replace '/', '\')
                (Test-Path -LiteralPath $target -PathType Leaf) | Should Be $true
            }
        }
    }

    It 'documents installation and verification of both AWS client tools' {
        $content = Get-Content -LiteralPath $prerequisitesPath -Raw

        $content | Should Match 'AWSCLIV2-User\.msi'
        $content | Should Match 'aws --version'
        $content | Should Match 'SessionManagerPluginSetup\.exe'
        $content | Should Match 'session-manager-plugin --version'
        $content | Should Match 'aws ssm start-session'
    }

    It 'documents the dated Lightsail and hybrid-node prices' {
        $content = Get-Content -LiteralPath $costsPath -Raw

        $content | Should Match '2026-09-22'
        $content | Should Match 'USD 5\.00'
        $content | Should Match 'USD 0\.05/session'
        $content | Should Match 'USD 0\.002/invocation'
    }
}
