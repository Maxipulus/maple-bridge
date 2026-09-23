[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [ValidatePattern('^maplebridge[A-Za-z0-9_.-]*$')]
    [ValidateLength(1, 20)]
    [string] $StackName = 'maplebridge-gateway',

    [ValidatePattern('^maplebridge[A-Za-z0-9_.-]*$')]
    [string] $GatewayName = 'maplebridge-gateway',

    [ValidateSet('us-west-2')]
    [string] $Region = 'us-west-2',

    [ValidatePattern('^us-west-2[a-z]$')]
    [string] $AvailabilityZone = 'us-west-2a',

    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $BlueprintId = 'ubuntu_24_04',

    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $BundleId = 'nano_3_0',

    [ValidateRange(1, 65535)]
    [int] $VpnPort = 51820,

    [ValidateRange(30, 1440)]
    [int] $ActivationLifetimeMinutes = 120,

    [ValidateRange(1, 60)]
    [int] $RegistrationTimeoutMinutes = 20,

    [ValidateRange(5, 120)]
    [int] $PollSeconds = 15,

    [string] $TemplatePath,

    [string] $StatePath,

    [string] $AwsExecutable = 'aws',

    [Parameter(Mandatory)]
    [switch] $ConfirmPaidDeployment
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ConfirmPaidDeployment) {
    throw 'Paid deployment was not confirmed. Re-run with -ConfirmPaidDeployment after reviewing the target and current prices.'
}

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Join-Path $repositoryRoot 'infrastructure\gateway.template.json'
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $repositoryRoot 'state\aws-gateway.json'
}

$resolvedTemplatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TemplatePath)
$resolvedStatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
if (-not (Test-Path -LiteralPath $resolvedTemplatePath -PathType Leaf)) {
    throw 'The CloudFormation template file does not exist.'
}

$awsCommand = Get-Command $AwsExecutable -ErrorAction SilentlyContinue
if ($null -eq $awsCommand) {
    throw 'AWS CLI v2 was not found. Complete docs/windows-prerequisites.md first.'
}
$awsPath = $awsCommand.Source
$commonArguments = @('--profile', $ProfileName, '--region', $Region, '--no-cli-pager')

function Protect-MapleBridgeAwsError {
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = $Text
    if ($clean -match '(?s)(aws: \[ERROR\]:.*)') {
        $clean = $Matches[1]
    }
    $clean = $clean -replace '(?<![0-9])[0-9]{12}(?![0-9])', '<account-id>'
    $clean = $clean -replace 'authorization-details/[A-Za-z0-9]+', 'authorization-details/<redacted>'
    $clean = $clean -replace 'authorization id: [A-Za-z0-9]+', 'authorization id: <redacted>'
    return $clean.Trim()
}

function Invoke-MapleBridgeAwsProcess {
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ('maplebridge-deploy-{0}.stderr' -f [Guid]::NewGuid().ToString('N'))
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $stdout = @(& $awsPath @Arguments 2> $stderrPath)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Protect-MapleBridgeAwsError -Text ([IO.File]::ReadAllText($stderrPath)) } else { '' }
        $result = [pscustomobject] @{
            ExitCode = $exitCode
            StdOut   = $stdout -join [Environment]::NewLine
            StdErr   = $stderr
        }
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            $operation = if ($Arguments.Count -ge 2) { '{0} {1}' -f $Arguments[0], $Arguments[1] } else { 'unknown operation' }
            $details = @($result.StdOut, $result.StdErr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            throw ('AWS CLI command failed for {0}: {1}' -f $operation, ($details -join [Environment]::NewLine))
        }
        return $result
    }
    finally {
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force
        }
    }
}

function Invoke-MapleBridgeAwsJson {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $result = Invoke-MapleBridgeAwsProcess -Arguments ($Arguments + $commonArguments)
    if ([string]::IsNullOrWhiteSpace($result.StdOut)) {
        return $null
    }
    try {
        return $result.StdOut | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw ('AWS CLI returned invalid JSON for {0} {1}.' -f $Arguments[0], $Arguments[1])
    }
}

function Get-MapleBridgeStack {
    $result = Invoke-MapleBridgeAwsProcess -Arguments (@('cloudformation', 'describe-stacks', '--stack-name', $StackName, '--output', 'json') + $commonArguments) -AllowFailure
    if ($result.ExitCode -eq 0) {
        return ($result.StdOut | ConvertFrom-Json -ErrorAction Stop).Stacks[0]
    }
    if ($result.StdErr -match 'does not exist') {
        return $null
    }
    throw ('Unable to inspect stack {0}: {1}' -f $StackName, $result.StdErr)
}

function Get-StackParameterValue {
    param($Stack, [string] $Name)
    $parameter = @($Stack.Parameters | Where-Object ParameterKey -EQ $Name) | Select-Object -First 1
    if ($null -eq $parameter) { return $null }
    return [string] $parameter.ParameterValue
}

function Wait-MapleBridgeStack {
    param([ValidateSet('stack-create-complete', 'stack-update-complete')][string] $Waiter)
    $null = Invoke-MapleBridgeAwsProcess -Arguments (@('cloudformation', 'wait', $Waiter, '--stack-name', $StackName) + $commonArguments)
}

function Write-SecretParameterFile {
    param([string] $ActivationId, [string] $ActivationCode)

    $path = Join-Path ([IO.Path]::GetTempPath()) ('maplebridge-parameters-{0}.json' -f [Guid]::NewGuid().ToString('N'))
    $parameters = @(
        @{ ParameterKey = 'DeployGateway'; ParameterValue = 'true' },
        @{ ParameterKey = 'GatewayName'; ParameterValue = $GatewayName },
        @{ ParameterKey = 'AvailabilityZone'; ParameterValue = $AvailabilityZone },
        @{ ParameterKey = 'BlueprintId'; ParameterValue = $BlueprintId },
        @{ ParameterKey = 'BundleId'; ParameterValue = $BundleId },
        @{ ParameterKey = 'VpnPort'; ParameterValue = [string] $VpnPort },
        @{ ParameterKey = 'SsmBootstrapMode'; ParameterValue = 'Register' },
        @{ ParameterKey = 'SsmActivationId'; ParameterValue = $ActivationId },
        @{ ParameterKey = 'SsmActivationCode'; ParameterValue = $ActivationCode }
    )
    [IO.File]::WriteAllText($path, ($parameters | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    return $path
}

function Get-OnlineManagedNode {
    param([string] $ActivationId)

    $response = Invoke-MapleBridgeAwsJson -Arguments @('ssm', 'describe-instance-information', '--output', 'json')
    return @($response.InstanceInformationList | Where-Object {
        $_.ActivationId -eq $ActivationId -and $_.PingStatus -eq 'Online'
    }) | Select-Object -First 1
}

Write-Host ('Deployment target: stack={0}, gateway={1}, region={2}, zone={3}, bundle={4}, UDP={5}.' -f $StackName, $GatewayName, $Region, $AvailabilityZone, $BundleId, $VpnPort)
Write-Warning 'This operation creates an always-on Lightsail resource billed up to the current monthly bundle price.'

$readinessScript = Join-Path $PSScriptRoot 'Test-MapleBridgeAwsReadiness.ps1'
$null = & $readinessScript -ProfileName $ProfileName -Region $Region -AvailabilityZone $AvailabilityZone -BlueprintId $BlueprintId -BundleId $BundleId -TemplatePath $resolvedTemplatePath -AwsExecutable $awsPath

$stack = Get-MapleBridgeStack
if ($null -eq $stack) {
    Write-Host 'Creating the non-billable bootstrap stack phase.'
    $null = Invoke-MapleBridgeAwsProcess -Arguments (@(
        'cloudformation', 'create-stack',
        '--stack-name', $StackName,
        '--template-body', ('file://{0}' -f $resolvedTemplatePath),
        '--parameters', 'ParameterKey=DeployGateway,ParameterValue=false',
        '--capabilities', 'CAPABILITY_IAM',
        '--on-failure', 'ROLLBACK',
        '--tags', 'Key=Project,Value=MapleBridge',
        '--output', 'json'
    ) + $commonArguments)
    Wait-MapleBridgeStack -Waiter 'stack-create-complete'
    $stack = Get-MapleBridgeStack
}

if ($stack.StackStatus -notin @('CREATE_COMPLETE', 'UPDATE_COMPLETE', 'UPDATE_ROLLBACK_COMPLETE')) {
    throw ('Stack {0} is in unsupported state {1}; inspect it before retrying.' -f $StackName, $stack.StackStatus)
}

$deployGateway = Get-StackParameterValue -Stack $stack -Name 'DeployGateway'
$bootstrapMode = Get-StackParameterValue -Stack $stack -Name 'SsmBootstrapMode'
if ($deployGateway -eq 'true' -and $bootstrapMode -eq 'Redacted') {
    Write-Host 'The gateway stack is already deployed and redacted; no AWS mutation was performed.'
    return
}
if ($deployGateway -eq 'true') {
    throw 'The stack contains a gateway whose bootstrap is not redacted. Resume requires the original activation context; inspect it before retrying.'
}

$roleOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'SsmHybridNodeRoleName') | Select-Object -First 1
if ($null -eq $roleOutput -or [string]::IsNullOrWhiteSpace([string] $roleOutput.OutputValue)) {
    throw 'The bootstrap stack did not return the SSM hybrid-node role name.'
}
$roleResponse = Invoke-MapleBridgeAwsJson -Arguments @('iam', 'get-role', '--role-name', [string] $roleOutput.OutputValue, '--output', 'json')
$rolePath = [string] $roleResponse.Role.Path
if ($rolePath -ne '/maplebridge/') {
    throw 'The SSM hybrid-node role is not under the expected /maplebridge/ path.'
}
$activationRoleName = '{0}{1}' -f $rolePath.TrimStart('/'), [string] $roleResponse.Role.RoleName

$activationId = $null
$activationParameterFile = $null
try {
    $expiration = [DateTime]::UtcNow.AddMinutes($ActivationLifetimeMinutes).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Host 'Creating a one-node, short-lived SSM activation.'
    $activation = Invoke-MapleBridgeAwsJson -Arguments @(
        'ssm', 'create-activation',
        '--description', 'MapleBridge gateway bootstrap',
        '--default-instance-name', $GatewayName,
        '--iam-role', $activationRoleName,
        '--registration-limit', '1',
        '--expiration-date', $expiration,
        '--tags', 'Key=Project,Value=MapleBridge', ('Key=StackName,Value={0}' -f $StackName),
        '--output', 'json'
    )
    $activationId = [string] $activation.ActivationId
    $activationCode = [string] $activation.ActivationCode
    if ([string]::IsNullOrWhiteSpace($activationId) -or [string]::IsNullOrWhiteSpace($activationCode)) {
        throw 'SSM did not return usable activation credentials.'
    }

    $activationParameterFile = Write-SecretParameterFile -ActivationId $activationId -ActivationCode $activationCode
    $activationCode = $null

    Write-Host 'Creating the Lightsail gateway and attached static IP.'
    $null = Invoke-MapleBridgeAwsProcess -Arguments (@(
        'cloudformation', 'update-stack',
        '--stack-name', $StackName,
        '--template-body', ('file://{0}' -f $resolvedTemplatePath),
        '--parameters', ('file://{0}' -f $activationParameterFile),
        '--capabilities', 'CAPABILITY_IAM',
        '--output', 'json'
    ) + $commonArguments)
    Remove-Item -LiteralPath $activationParameterFile -Force
    $activationParameterFile = $null
    Wait-MapleBridgeStack -Waiter 'stack-update-complete'

    Write-Host 'Waiting for the SSM managed node to become online.'
    $deadline = [DateTime]::UtcNow.AddMinutes($RegistrationTimeoutMinutes)
    $managedNode = $null
    while ([DateTime]::UtcNow -lt $deadline -and $null -eq $managedNode) {
        $managedNode = Get-OnlineManagedNode -ActivationId $activationId
        if ($null -eq $managedNode) {
            Start-Sleep -Seconds $PollSeconds
        }
    }
    if ($null -eq $managedNode) {
        throw ('The gateway did not register with SSM within {0} minutes. The stack remains in Register mode for diagnosis.' -f $RegistrationTimeoutMinutes)
    }

    Write-Host 'SSM is online. Redacting activation data from the CloudFormation stack and Lightsail user data.'
    $null = Invoke-MapleBridgeAwsProcess -Arguments (@(
        'cloudformation', 'update-stack',
        '--stack-name', $StackName,
        '--use-previous-template',
        '--parameters',
        'ParameterKey=DeployGateway,UsePreviousValue=true',
        'ParameterKey=GatewayName,UsePreviousValue=true',
        'ParameterKey=AvailabilityZone,UsePreviousValue=true',
        'ParameterKey=BlueprintId,UsePreviousValue=true',
        'ParameterKey=BundleId,UsePreviousValue=true',
        'ParameterKey=VpnPort,UsePreviousValue=true',
        'ParameterKey=SsmBootstrapMode,ParameterValue=Redacted',
        'ParameterKey=SsmActivationId,ParameterValue=REDACTED',
        'ParameterKey=SsmActivationCode,ParameterValue=REDACTED',
        '--capabilities', 'CAPABILITY_IAM',
        '--output', 'json'
    ) + $commonArguments)
    Wait-MapleBridgeStack -Waiter 'stack-update-complete'

    $stack = Get-MapleBridgeStack
    $gatewayOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'GatewayInstanceName') | Select-Object -First 1
    $ipOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'GatewayStaticIpAddress') | Select-Object -First 1
    $stateDirectory = Split-Path $resolvedStatePath -Parent
    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        $null = New-Item -ItemType Directory -Path $stateDirectory -Force
    }
    $state = [ordered] @{
        stackName        = $StackName
        gatewayName      = [string] $gatewayOutput.OutputValue
        region           = $Region
        availabilityZone = $AvailabilityZone
        bundleId         = $BundleId
        vpnPort          = $VpnPort
        managedNodeId    = [string] $managedNode.InstanceId
        staticIpAddress  = [string] $ipOutput.OutputValue
        bootstrapMode    = 'Redacted'
        updatedAtUtc     = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText($resolvedStatePath, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Write-Host 'Gateway infrastructure is online and redacted. Live identifiers were written only to ignored state/aws-gateway.json.'
}
finally {
    if ($null -ne $activationParameterFile -and (Test-Path -LiteralPath $activationParameterFile)) {
        Remove-Item -LiteralPath $activationParameterFile -Force
    }
    if (-not [string]::IsNullOrWhiteSpace($activationId)) {
        $deleteResult = Invoke-MapleBridgeAwsProcess -Arguments (@('ssm', 'delete-activation', '--activation-id', $activationId) + $commonArguments) -AllowFailure
        if ($deleteResult.ExitCode -ne 0) {
            Write-Warning 'The short-lived SSM activation could not be deleted automatically; it will expire, but should be inspected manually.'
        }
    }
}
