$repoRoot = Split-Path -Parent $PSScriptRoot
$keyScript = Join-Path $repoRoot 'scripts\windows\Initialize-MapleBridgeClientKey.ps1'
$configureScript = Join-Path $repoRoot 'scripts\windows\Configure-MapleBridgeGateway.ps1'
$installScript = Join-Path $repoRoot 'scripts\windows\Install-MapleBridge.ps1'

Describe 'MapleBridge end-to-end orchestration' {
    It 'generates a valid local client key pair and preserves it on rerun' {
        $privatePath = Join-Path $TestDrive 'keys\client.key'
        $publicPath = Join-Path $TestDrive 'keys\client.pub'

        $first = & $keyScript -PrivateKeyPath $privatePath -PublicKeyPath $publicPath
        $firstPrivate = (Get-Content -LiteralPath $privatePath -Raw).Trim()
        $firstPublic = (Get-Content -LiteralPath $publicPath -Raw).Trim()
        $second = & $keyScript -PrivateKeyPath $privatePath -PublicKeyPath $publicPath

        $firstPrivate | Should Match '^[A-Za-z0-9+/]{43}=$'
        $firstPublic | Should Match '^[A-Za-z0-9+/]{43}=$'
        [Convert]::FromBase64String($firstPrivate).Length | Should Be 32
        [Convert]::FromBase64String($firstPublic).Length | Should Be 32
        (Get-Content -LiteralPath $privatePath -Raw).Trim() | Should Be $firstPrivate
        $second.publicKey | Should Be $first.publicKey
        (Get-Acl -LiteralPath $privatePath).AreAccessRulesProtected | Should Be $true
    }

    It 'configures the gateway through SSM without transferring the client private key' {
        $content = Get-Content -LiteralPath $configureScript -Raw

        $content | Should Match "'ssm'|ssm send-command"
        $content | Should Match 'AWS-RunShellScript'
        $content | Should Match 'configure-gateway\.sh'
        $content | Should Match 'client\.pub'
        $content | Should Not Match 'client\.key|privateKeyPath'
        $content | Should Match 'gatewayConfigured'
    }

    It 'provides one user-facing command through Clash installation and status refresh' {
        $content = Get-Content -LiteralPath $installScript -Raw
        $keyPosition = $content.IndexOf('Initialize-MapleBridgeClientKey.ps1')
        $deployPosition = $content.IndexOf('Deploy-MapleBridgeGateway.ps1')
        $configurePosition = $content.IndexOf('Configure-MapleBridgeGateway.ps1')
        $profilePosition = $content.IndexOf('New-MapleBridgeMihomoConfig.ps1')
        $clashPosition = $content.IndexOf('Install-MapleBridgeClashProfile.ps1')
        $statusPosition = $content.IndexOf('Update-MapleBridgeStatus.ps1')

        $keyPosition | Should BeGreaterThan -1
        $deployPosition | Should BeGreaterThan $keyPosition
        $configurePosition | Should BeGreaterThan $deployPosition
        $profilePosition | Should BeGreaterThan $configurePosition
        $clashPosition | Should BeGreaterThan $profilePosition
        $statusPosition | Should BeGreaterThan $clashPosition
        $content | Should Match 'Install-MapleBridgeClashProfile\.ps1.+-ReloadClash'
        $content | Should Not Match 'Update-MapleBridgeStatus\.ps1.+-ReloadClash'
    }

    It 'enables automatic security maintenance by default' {
        $content = Get-Content -LiteralPath $installScript -Raw
        $content | Should Match 'Set-MapleBridgeMaintenance\.ps1'
        $content | Should Match 'if \(-not \$SkipAutomaticMaintenance\)'
    }
}
