$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MapleBridge\MapleBridge.psm1'
$templatePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'infrastructure\gateway.template.json'
Import-Module $modulePath -Force

Describe 'Test-MapleBridgeAwsReadiness' {
    Mock Invoke-MapleBridgeAwsCli -ModuleName MapleBridge {
        param($AwsExecutable, $Arguments)

        $operation = '{0} {1}' -f $Arguments[0], $Arguments[1]
        switch ($operation) {
            'sts get-caller-identity' {
                [pscustomobject] @{ Account = '123456789012'; Arn = 'arn:aws:iam::123456789012:user/test'; UserId = 'test' }
            }
            'lightsail get-regions' {
                [pscustomobject] @{ regions = @([pscustomobject] @{ name = 'us-west-2'; availabilityZones = @([pscustomobject] @{ zoneName = 'us-west-2a'; state = 'available' }) }) }
            }
            'lightsail get-blueprints' {
                [pscustomobject] @{ blueprints = @([pscustomobject] @{ blueprintId = 'ubuntu_24_04'; name = 'Ubuntu 24.04 LTS'; isActive = $true }) }
            }
            'lightsail get-bundles' {
                [pscustomobject] @{ bundles = @([pscustomobject] @{ bundleId = 'nano_3_0'; name = 'Linux/Unix'; isActive = $true; price = 5.00; cpuCount = 2; ramSizeInGb = 0.5; diskSizeInGb = 20; transferPerMonthInGb = 1024 }) }
            }
            'cloudformation validate-template' {
                [pscustomobject] @{ Parameters = @() }
            }
            default {
                throw ('Unexpected mock operation: {0}' -f $operation)
            }
        }
    }

    It 'returns a sanitized readiness summary with the current bundle price' {
        $result = Test-MapleBridgeAwsReadiness -ProfileName maplebridge-test -TemplatePath $templatePath -AwsExecutable fake-aws

        $result.callerIdentityVerified | Should Be $true
        $result.blueprintId | Should Be 'ubuntu_24_04'
        $result.bundleId | Should Be 'nano_3_0'
        $result.monthlyPriceUsd | Should Be 5.00
        $result.templateValid | Should Be $true
        $result.PSObject.Properties.Name -contains 'accountId' | Should Be $false
        $result.PSObject.Properties.Name -contains 'callerArn' | Should Be $false
    }

    It 'performs only the expected read-only operations' {
        $null = Test-MapleBridgeAwsReadiness -ProfileName maplebridge-test -TemplatePath $templatePath -AwsExecutable fake-aws

        Assert-MockCalled Invoke-MapleBridgeAwsCli -ModuleName MapleBridge -Times 5 -Scope It
        Assert-MockCalled Invoke-MapleBridgeAwsCli -ModuleName MapleBridge -Times 3 -Scope It -ParameterFilter {
            $Arguments[0] -eq 'lightsail' -and $Arguments -contains '--query'
        }
    }

    It 'fails when the requested bundle is inactive' {
        Mock Invoke-MapleBridgeAwsCli -ModuleName MapleBridge -ParameterFilter { $Arguments[0] -eq 'lightsail' -and $Arguments[1] -eq 'get-bundles' } {
            [pscustomobject] @{ bundles = @([pscustomobject] @{ bundleId = 'nano_3_0'; name = 'Linux/Unix'; isActive = $false; price = 5.00 }) }
        }

        { Test-MapleBridgeAwsReadiness -ProfileName maplebridge-test -TemplatePath $templatePath -AwsExecutable fake-aws } | Should Throw
    }

    It 'fails when the requested availability zone is unavailable' {
        Mock Invoke-MapleBridgeAwsCli -ModuleName MapleBridge -ParameterFilter { $Arguments[0] -eq 'lightsail' -and $Arguments[1] -eq 'get-regions' } {
            [pscustomobject] @{ regions = @([pscustomobject] @{ name = 'us-west-2'; availabilityZones = @([pscustomobject] @{ zoneName = 'us-west-2a'; state = 'unavailable' }) }) }
        }

        { Test-MapleBridgeAwsReadiness -ProfileName maplebridge-test -TemplatePath $templatePath -AwsExecutable fake-aws } | Should Throw
    }
}

Describe 'Invoke-MapleBridgeAwsCli process handling' {
    It 'keeps successful stderr diagnostics out of JSON output' {
        $fixturePath = Join-Path $PSScriptRoot 'fixtures\aws-json-with-stderr.cmd'
        $result = & (Get-Module MapleBridge) { param($Executable) Invoke-MapleBridgeAwsCli -AwsExecutable $Executable -Arguments @('probe') } $fixturePath

        $result.ok | Should Be $true
    }

    It 'accepts an explicitly allowed empty successful response' {
        $fixturePath = Join-Path $TestDrive 'empty-success.cmd'
        "@echo off`r`nexit /b 0`r`n" | Set-Content -LiteralPath $fixturePath -Encoding Ascii
        $result = Invoke-MapleBridgeAwsCli -AwsExecutable $fixturePath -Arguments @('cloudformation', 'wait') -AllowEmptyOutput
        $result | Should Be $null
    }
}
