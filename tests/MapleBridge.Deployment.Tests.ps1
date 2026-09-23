$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts\windows\Deploy-MapleBridgeGateway.ps1'
$content = Get-Content -LiteralPath $scriptPath -Raw

Describe 'Deploy-MapleBridgeGateway safety contract' {
    It 'requires an explicit paid-deployment switch' {
        $content | Should Match '\[Parameter\(Mandatory\)\][\s\S]*\[switch\] \$ConfirmPaidDeployment'
        $content | Should Match 'if \(-not \$ConfirmPaidDeployment\)'
    }

    It 'uses a short-lived one-node activation and always attempts deletion' {
        $content | Should Match "'--registration-limit', '1'"
        $content | Should Match "'ssm', 'delete-activation'"
        $content | Should Match 'finally'
    }

    It 'passes the path-qualified hybrid role name to SSM' {
        $content | Should Match "'iam', 'get-role'"
        $content | Should Match '\$rolePath -ne ''/maplebridge/'''
        $content | Should Match '''--iam-role'', \$activationRoleName'
    }

    It 'limits stack names so the path-qualified generated role fits the SSM limit' {
        $content | Should Match '\[ValidateLength\(1, 20\)\][\s\S]*\[string\] \$StackName'
        $content | Should Match 'CAPABILITY_IAM'
        $content | Should Not Match 'CAPABILITY_NAMED_IAM|ParameterKey=SsmRoleName'
    }

    It 'redacts activation parameters after SSM becomes online' {
        $onlinePosition = $content.IndexOf('$null -eq $managedNode')
        $redactedPosition = $content.IndexOf('ParameterKey=SsmBootstrapMode,ParameterValue=Redacted')

        $onlinePosition | Should BeGreaterThan -1
        $redactedPosition | Should BeGreaterThan $onlinePosition
        $content | Should Match 'ParameterKey=SsmActivationCode,ParameterValue=REDACTED'
    }

    It 'does not write activation credentials to persistent state' {
        $stateStart = $content.IndexOf('$state = [ordered]')
        $stateEnd = $content.IndexOf('[IO.File]::WriteAllText($resolvedStatePath', $stateStart)
        $stateSection = $content.Substring($stateStart, $stateEnd - $stateStart)

        $stateSection | Should Not Match 'activationCode'
        $stateSection | Should Not Match 'activationId'
        $stateSection | Should Match 'bootstrapMode'
    }

    It 'handles expected nonzero AWS probes without PowerShell terminating first' {
        $content | Should Match '\$ErrorActionPreference = ''Continue'''
        $content | Should Match 'if \(\$exitCode -ne 0 -and -not \$AllowFailure\)'
    }

    It 'can resume a clean CloudFormation rollback' {
        $content | Should Match "'UPDATE_ROLLBACK_COMPLETE'"
    }

    It 'redacts account and authorization identifiers from AWS failures' {
        $content | Should Match '\[0-9\]\{12\}'
        $content | Should Match 'authorization id: <redacted>'
    }
}
