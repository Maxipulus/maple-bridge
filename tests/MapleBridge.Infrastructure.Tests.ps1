$templatePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'infrastructure\gateway.template.json'
$templateText = Get-Content -LiteralPath $templatePath -Raw
$template = $templateText | ConvertFrom-Json

Describe 'MapleBridge gateway CloudFormation template' {
    It 'is valid JSON with gateway creation disabled by default' {
        $template.AWSTemplateFormatVersion | Should Be '2010-09-09'
        $template.Parameters.DeployGateway.Default | Should Be 'false'
        $template.Parameters.SsmBootstrapMode.Default | Should Be 'Redacted'
        $template.Resources.GatewayInstance.Condition | Should Be 'CreateGateway'
        $template.Resources.GatewayStaticIp.Condition | Should Be 'CreateGateway'
    }

    It 'marks both activation parameters as sensitive' {
        $template.Parameters.SsmActivationId.NoEcho | Should Be $true
        $template.Parameters.SsmActivationCode.NoEcho | Should Be $true
        $template.Parameters.SsmActivationId.Default | Should Be 'REDACTED'
        $template.Parameters.SsmActivationCode.Default | Should Be 'REDACTED'
    }

    It 'requires activation values to agree with the bootstrap lifecycle mode' {
        $assertion = $template.Rules.ActivationValuesMatchBootstrapMode.Assertions[0]
        $assertion.Assert.'Fn::Or'.Count | Should Be 2
        $assertion.AssertDescription | Should Match 'Register mode requires real activation values'
        $template.Conditions.RegisterSsm.'Fn::Equals'[0].Ref | Should Be 'SsmBootstrapMode'
        $template.Conditions.RegisterSsm.'Fn::Equals'[1] | Should Be 'Register'
    }

    It 'creates a least-purpose SSM hybrid-node role' {
        $role = $template.Resources.SsmHybridNodeRole.Properties
        $role.AssumeRolePolicyDocument.Statement.Count | Should Be 1
        $role.AssumeRolePolicyDocument.Statement[0].Principal.Service | Should Be 'ssm.amazonaws.com'
        $role.AssumeRolePolicyDocument.Statement[0].Action | Should Be 'sts:AssumeRole'
        @($role.ManagedPolicyArns).Count | Should Be 1
        $role.ManagedPolicyArns[0] | Should Be 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'
    }

    It 'opens only the configured WireGuard UDP port at the Lightsail firewall' {
        $instance = $template.Resources.GatewayInstance.Properties
        @($instance.Networking.Ports).Count | Should Be 1
        $port = $instance.Networking.Ports[0]
        $port.Protocol | Should Be 'udp'
        $port.FromPort.Ref | Should Be 'VpnPort'
        $port.ToPort.Ref | Should Be 'VpnPort'
        @($port.Cidrs) | Should Be @('0.0.0.0/0')
        $instance.PSObject.Properties.Name -contains 'KeyPairName' | Should Be $false
        $templateText | Should Not Match '(["'']|\b)(22|ssh)(["'']|\b)'
    }

    It 'prefers a preinstalled SSM Agent, retains the regional setup CLI fallback, and scrubs activation data' {
        $userDataChoice = $template.Resources.GatewayInstance.Properties.UserData.'Fn::If'
        $userDataChoice[0] | Should Be 'RegisterSsm'
        $userData = $userDataChoice[1].'Fn::Sub'
        $redactedUserData = $userDataChoice[2]
        $userData | Should Match '^#!/bin/sh\nset -eu\n'
        $userData | Should Not Match 'pipefail|>\s*>\('
        $snapBranch = $userData.IndexOf('/snap/amazon-ssm-agent/current/amazon-ssm-agent')
        $debBranch = $userData.IndexOf('command -v amazon-ssm-agent')
        $setupCliBranch = $userData.IndexOf('No preinstalled SSM Agent found')
        $snapBranch | Should BeGreaterThan -1
        $debBranch | Should BeGreaterThan $snapBranch
        $setupCliBranch | Should BeGreaterThan $debBranch
        $userData | Should Match 'amazon-ssm-agent -register -code \"\$activation_code\" -id \"\$activation_id\"'
        $userData | Should Match 'amazon-ssm-\$\{AWS::Region\}'
        $userData | Should Match 'ssm-setup-cli -register'
        $userData | Should Match "activation_code='\$\{SsmActivationCode\}'"
        $userData | Should Match "activation_id='\$\{SsmActivationId\}'"
        $userData | Should Match 'user-data\.txt'
        $userData | Should Match 'scripts/part-001'
        $userData | Should Match 'cloud-init-output\.log'
        $userData | Should Match 'maplebridge-bootstrap\.log'
        $userData | Should Match 'content\.replace\(secret, b''REDACTED''\)'
        $userData | Should Match 'REDACTED'
        $userData | Should Not Match 'skip-signature-validation'
        $redactedUserData | Should Match 'credentials were redacted'
        $redactedUserData | Should Not Match 'SsmActivation(Code|Id)'
    }

    It 'does not expose activation values through outputs' {
        $outputs = $template.Outputs | ConvertTo-Json -Depth 10
        $outputs | Should Not Match 'SsmActivation(Code|Id)'
    }

    It 'attaches a stable IP to the conditional instance' {
        $staticIp = $template.Resources.GatewayStaticIp.Properties
        $staticIp.AttachedTo.Ref | Should Be 'GatewayInstance'
        $template.Outputs.GatewayStaticIpAddress.Value.'Fn::GetAtt'[0] | Should Be 'GatewayStaticIp'
        $template.Outputs.GatewayStaticIpAddress.Value.'Fn::GetAtt'[1] | Should Be 'IpAddress'
    }
}
