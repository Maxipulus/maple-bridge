$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MapleBridge\MapleBridge.psm1'
$generatorScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\windows\New-MapleBridgeMihomoConfig.ps1'
Import-Module $modulePath -Force

Describe 'Write-MapleBridgeMihomoConfig' {
    $privateKey = [Convert]::ToBase64String([byte[]] (1..32))
    $publicKey = [Convert]::ToBase64String([byte[]] (33..64))
    $privateKeyPath = Join-Path $TestDrive 'client.key'
    Set-Content -LiteralPath $privateKeyPath -Value $privateKey -Encoding Ascii

    It 'writes a selective configuration with process and final direct rules' {
        $outputPath = Join-Path $TestDrive 'selective.yaml'
        $result = Write-MapleBridgeMihomoConfig -Mode Selective -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $privateKeyPath -OutputPath $outputPath
        $content = Get-Content -LiteralPath $outputPath -Raw

        $content | Should Match 'PROCESS-NAME,nexon_launcher\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,nexon_updater\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,nexon_agent\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,nexon_client\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,nexon_runtime\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,MapleStory\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,BlackXchg\.aes,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,BlackCipher64\.aes,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,DwarfAxe\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,MapleBrowser_WZ2\.exe,MapleBridge-US'
        $content | Should Match 'PROCESS-NAME,CrashReportClient\.exe,MapleBridge-US'
        $content | Should Match 'DOMAIN-SUFFIX,nexonstatic\.com,MapleBridge-US'
        $content | Should Match 'DOMAIN-SUFFIX,xsolla\.com,MapleBridge-US'
        $content | Should Match 'DOMAIN-SUFFIX,xsolla\.net,MapleBridge-US'
        $content | Should Match 'GEOSITE,nexon,MapleBridge-US'
        $content | Should Match 'MATCH,DIRECT'
        $content | Should Match "geosite:nexon.*MapleBridge-US"
        $content | Should Match ([regex]::Escape($privateKey))
        ($result | Out-String) | Should Not Match ([regex]::Escape($privateKey))
        $result.containsSecrets | Should Be $true
    }

    It 'writes an explicit diagnostic full-tunnel configuration without a direct fallback' {
        $outputPath = Join-Path $TestDrive 'diagnostic.yaml'
        Write-MapleBridgeMihomoConfig -Mode DiagnosticFullTunnel -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $privateKeyPath -OutputPath $outputPath
        $content = Get-Content -LiteralPath $outputPath -Raw

        $content | Should Match 'MATCH,MapleBridge-US'
        $content | Should Not Match 'MATCH,DIRECT'
        $content | Should Not Match 'PROCESS-NAME,'
        $content | Should Match "(?s)nameserver:.*https://1\.1\.1\.1/dns-query#MapleBridge-US"
    }

    It 'can generate a loopback-only non-TUN diagnostic profile' {
        $outputPath = Join-Path $TestDrive 'local-proxy-diagnostic.yaml'
        Write-MapleBridgeMihomoConfig -Mode DiagnosticFullTunnel -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $privateKeyPath -OutputPath $outputPath -TunEnabled $false -MixedPort 17897
        $content = Get-Content -LiteralPath $outputPath -Raw

        $content | Should Match '(?m)^mixed-port: 17897\r?$'
        $content | Should Match '(?m)^allow-lan: false\r?$'
        $content | Should Match "(?m)^bind-address: '127\.0\.0\.1'\r?$"
        $content | Should Match '(?m)^  enable: false\r?$'
    }

    It 'rejects an invalid private key without creating output' {
        $invalidKeyPath = Join-Path $TestDrive 'invalid.key'
        $outputPath = Join-Path $TestDrive 'invalid.yaml'
        Set-Content -LiteralPath $invalidKeyPath -Value 'not-a-wireguard-key' -Encoding Ascii

        { Write-MapleBridgeMihomoConfig -Mode Selective -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $invalidKeyPath -OutputPath $outputPath } | Should Throw
        Test-Path -LiteralPath $outputPath | Should Be $false
    }

    It 'rejects invalid domain suffix rules' {
        $outputPath = Join-Path $TestDrive 'invalid-domain.yaml'

        { Write-MapleBridgeMihomoConfig -Mode Selective -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $privateKeyPath -OutputPath $outputPath -DomainSuffixes @('xsolla.com,Match,DIRECT') } | Should Throw
        Test-Path -LiteralPath $outputPath | Should Be $false
    }

    It 'rejects key text containing embedded whitespace' {
        $invalidKeyPath = Join-Path $TestDrive 'key-with-newline.key'
        $outputPath = Join-Path $TestDrive 'key-with-newline.yaml'
        $keyWithNewline = $privateKey.Insert(20, [Environment]::NewLine)
        Set-Content -LiteralPath $invalidKeyPath -Value $keyWithNewline -Encoding Ascii

        { Write-MapleBridgeMihomoConfig -Mode Selective -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $invalidKeyPath -OutputPath $outputPath } | Should Throw
        Test-Path -LiteralPath $outputPath | Should Be $false
    }

    It 'refuses to overwrite the private key file' {
        { Write-MapleBridgeMihomoConfig -Mode Selective -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $privateKeyPath -OutputPath $privateKeyPath } | Should Throw
        (Get-Content -LiteralPath $privateKeyPath -Raw).Trim() | Should Be $privateKey
    }

    It 'uses the documented default output path through the wrapper script' {
        $workingDirectory = Join-Path $TestDrive 'wrapper'
        $null = New-Item -ItemType Directory -Path $workingDirectory

        Push-Location $workingDirectory
        try {
            & $generatorScriptPath -Mode Selective -ServerAddress '203.0.113.10' -ServerPort 51820 -ServerPublicKey $publicKey -ClientAddress '10.88.0.2/32' -ClientPrivateKeyPath $privateKeyPath
            Test-Path -LiteralPath (Join-Path $workingDirectory 'state\generated\maplebridge.yaml') | Should Be $true
        }
        finally {
            Pop-Location
        }
    }
}
