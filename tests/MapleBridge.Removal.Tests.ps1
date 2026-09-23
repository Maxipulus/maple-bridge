$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\windows\Remove-MapleBridge.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw

Describe 'Remove-MapleBridge safety contract' {
    It 'requires two independent AWS deletion confirmations' {
        $content | Should Match 'if \(-not \$ConfirmDestructiveRemoval\)'
        $content | Should Match 'ConfirmGatewayName must exactly match'
        $content | Should Match '\$stackGateway -cne \[string\] \$state\.gatewayName'
    }

    It 'deregisters the exact managed node before deleting and waiting for the exact stack' {
        $deregister = $content.IndexOf("'deregister-managed-instance'")
        $delete = $content.IndexOf("'cloudformation', 'delete-stack'")
        $wait = $content.IndexOf("'cloudformation', 'wait', 'stack-delete-complete'")
        $deregister | Should BeGreaterThan -1
        $delete | Should BeGreaterThan $deregister
        $wait | Should BeGreaterThan $delete
        $content | Should Match 'AllowEmptyOutput'
        $content | Should Not Match "'delete-maintenance-window'"
    }

    It 'preserves keys unless their separate switch is present' {
        $content | Should Match 'if \(\$RemoveLocalKeys\)'
        $content | Should Match "Key removal requires -ConfirmDestructiveRemoval"
    }
}

Describe 'Remove-MapleBridge local behavior' {
    It 'backs up and removes only MapleBridge-owned profile content' {
        $dataDirectory = Join-Path $TestDrive 'clash-data'
        $profilesDirectory = Join-Path $dataDirectory 'profiles'
        $null = New-Item -ItemType Directory -Path $profilesDirectory -Force
        @"
current: LMapleBridge
- uid: unrelated
  type: local
  file: unrelated.yaml
- uid: LMapleBridge
  type: local
  file: LMapleBridge.yaml
"@ | Set-Content -LiteralPath (Join-Path $dataDirectory 'profiles.yaml') -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profilesDirectory 'unrelated.yaml') -Value 'keep: true' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $profilesDirectory 'LMapleBridge.yaml') -Value 'remove: true' -Encoding UTF8

        $result = & $scriptPath -ClashDataDirectory $dataDirectory

        $result.localProfileRemoved | Should Be $true
        Test-Path -LiteralPath (Join-Path $profilesDirectory 'unrelated.yaml') | Should Be $true
        Test-Path -LiteralPath (Join-Path $profilesDirectory 'LMapleBridge.yaml') | Should Be $false
        Test-Path -LiteralPath (Join-Path $result.backupPath 'profiles.yaml') | Should Be $true
        (Get-Content -LiteralPath (Join-Path $dataDirectory 'profiles.yaml') -Raw) | Should Match '(?m)^current: unrelated\r?$'
    }
}
