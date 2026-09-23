$repoRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $repoRoot 'infrastructure/iam/maplebridge-deployer-policy.json'
$scriptPath = Join-Path $repoRoot 'scripts/aws/create-deployer-user.sh'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json

Describe 'MapleBridge IAM bootstrap policy' {
    It 'is valid JSON with the IAM policy version' {
        $policy.Version | Should Be '2012-10-17'
    }

    It 'restricts stack resources and project roles to MapleBridge names' {
        $stackStatement = $policy.Statement | Where-Object Sid -EQ 'MapleBridgeStackLifecycle'
        $roleStatement = $policy.Statement | Where-Object Sid -EQ 'MapleBridgeRoleLifecycle'

        foreach ($resource in @($stackStatement.Resource)) {
            $resource | Should Not Be '*'
        }
        @($stackStatement.Resource) -join ' ' | Should Match 'maplebridge'
        $roleStatement.Resource | Should Be 'arn:aws:iam::*:role/maplebridge/*'
    }

    It 'does not let the project user administer IAM users or access keys' {
        $actions = @($policy.Statement.Action) | ForEach-Object { @($_) }

        foreach ($forbiddenAction in @('iam:CreateUser', 'iam:DeleteUser', 'iam:CreateAccessKey', 'iam:*')) {
            @($actions -eq $forbiddenAction).Count | Should Be 0
        }
    }

    It 'limits regional write services to Oregon' {
        foreach ($sid in @('MapleBridgeLightsailWrite', 'MapleBridgeSystemsManagerLifecycle')) {
            $statement = $policy.Statement | Where-Object Sid -EQ $sid
            $statement.Condition.StringEquals.'aws:RequestedRegion' | Should Be 'us-west-2'
        }
    }

    It 'includes the Lightsail instance lifecycle used by the CloudFormation provider' {
        $statement = $policy.Statement | Where-Object Sid -EQ 'MapleBridgeLightsailWrite'
        $actions = @($statement.Action)

        @($actions -eq 'lightsail:StartInstance').Count | Should Be 1
        @($actions -eq 'lightsail:StopInstance').Count | Should Be 1
        @($actions -eq 'lightsail:RebootInstance').Count | Should Be 1
    }

    It 'passes project roles only to Systems Manager' {
        $statement = $policy.Statement | Where-Object Sid -EQ 'PassMapleBridgeRolesToSystemsManager'

        $statement.Resource | Should Be 'arn:aws:iam::*:role/maplebridge/*'
        $statement.Condition.StringEquals.'iam:PassedToService' | Should Be 'ssm.amazonaws.com'
    }
}

Describe 'CloudShell IAM bootstrap script' {
    It 'does not print the generated credential file' {
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should Not Match '(?m)^\s*(cat|jq)\s+.*credential_file'
        $content | Should Match 'chmod 600'
        $content | Should Match 'Refusing to overwrite'
    }
}
