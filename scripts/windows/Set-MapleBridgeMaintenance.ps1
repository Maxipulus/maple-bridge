[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [string] $StatePath,
    [string] $TemplatePath,
    [string] $AwsExecutable = 'aws',

    [ValidatePattern('^cron\(.+\)$')]
    [string] $Schedule = 'cron(0 18 ? * TUE#1 *)',

    [ValidateRange(1, 24)]
    [int] $DurationHours = 2,

    [ValidateRange(0, 23)]
    [int] $CutoffHours = 1,

    [ValidateRange(600, 172800)]
    [int] $TaskTimeoutSeconds = 7200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($CutoffHours -ge $DurationHours) { throw 'CutoffHours must be less than DurationHours.' }
$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1') -Force
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $repositoryRoot 'state\aws-gateway.json' }
if ([string]::IsNullOrWhiteSpace($TemplatePath)) { $TemplatePath = Join-Path $repositoryRoot 'infrastructure\gateway.template.json' }
$statePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
$templatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TemplatePath)
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'Gateway state is missing. Run Install-MapleBridge.ps1 first.' }
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'The CloudFormation template is missing.' }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

if ($AwsExecutable -eq 'aws' -and $null -eq (Get-Command $AwsExecutable -ErrorAction SilentlyContinue)) {
    $installedAws = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
    if (Test-Path -LiteralPath $installedAws -PathType Leaf) { $AwsExecutable = $installedAws }
}
$null = Get-Command $AwsExecutable -ErrorAction Stop
$common = @('--profile', $ProfileName, '--region', [string] $state.region, '--output', 'json', '--no-cli-pager')

function Get-Stack {
    Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'describe-stacks', '--stack-name', [string] $state.stackName) + $common)
}

$stack = (Get-Stack).Stacks[0]
$stackGateway = [string] (@($stack.Parameters | Where-Object ParameterKey -EQ 'GatewayName') | Select-Object -First 1).ParameterValue
if ($stackGateway -cne [string] $state.gatewayName) { throw 'CloudFormation gateway does not match local state.' }
if ([string] $state.managedNodeId -notmatch '^mi-[0-9a-f]{17}$') { throw 'Gateway state does not contain a valid SSM hybrid managed-node ID.' }

$desired = [ordered] @{
    EnableAutomaticMaintenance    = 'true'
    MaintenanceManagedNodeId      = [string] $state.managedNodeId
    MaintenanceSchedule           = $Schedule
    MaintenanceDurationHours      = [string] $DurationHours
    MaintenanceCutoffHours        = [string] $CutoffHours
    MaintenanceTaskTimeoutSeconds = [string] $TaskTimeoutSeconds
}
$parameterArguments = [Collections.Generic.List[string]]::new()
$existingKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($parameter in @($stack.Parameters)) {
    $key = [string] $parameter.ParameterKey
    $null = $existingKeys.Add($key)
    if ($desired.Contains($key)) {
        $parameterArguments.Add(('ParameterKey={0},ParameterValue={1}' -f $key, $desired[$key]))
    }
    else {
        $parameterArguments.Add(('ParameterKey={0},UsePreviousValue=true' -f $key))
    }
}
foreach ($entry in $desired.GetEnumerator()) {
    if (-not $existingKeys.Contains([string] $entry.Key)) {
        $parameterArguments.Add(('ParameterKey={0},ParameterValue={1}' -f $entry.Key, $entry.Value))
    }
}

$updated = $true
try {
    $null = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@(
        'cloudformation', 'update-stack',
        '--stack-name', [string] $state.stackName,
        '--template-body', ('file://{0}' -f $templatePath),
        '--parameters'
    ) + $parameterArguments.ToArray() + @('--capabilities', 'CAPABILITY_IAM') + $common)
}
catch {
    if ($_.Exception.Message -match 'No updates are to be performed') {
        $updated = $false
    }
    else {
        throw
    }
}
if ($updated) {
    $null = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'wait', 'stack-update-complete', '--stack-name', [string] $state.stackName) + $common) -AllowEmptyOutput
}

$stack = (Get-Stack).Stacks[0]
$windowOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'MaintenanceWindowId') | Select-Object -First 1
$targetOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'MaintenanceWindowTargetId') | Select-Object -First 1
$taskOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'MaintenanceWindowTaskId') | Select-Object -First 1
if ($null -eq $windowOutput -or $null -eq $targetOutput -or $null -eq $taskOutput) {
    throw 'CloudFormation did not return all automatic-maintenance resource IDs.'
}

$baseline = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'get-default-patch-baseline', '--operating-system', 'UBUNTU') + $common)
$baselineId = ([string] $baseline.BaselineId -split '/')[-1]
[pscustomobject] [ordered] @{
    enabled = $true
    managedBy = 'CloudFormation'
    windowId = [string] $windowOutput.OutputValue
    targetId = [string] $targetOutput.OutputValue
    taskId = [string] $taskOutput.OutputValue
    managedNodeId = [string] $state.managedNodeId
    schedule = $Schedule
    scheduleTimezone = 'UTC'
    durationHours = $DurationHours
    cutoffHours = $CutoffHours
    rebootOption = 'RebootIfNeeded'
    baselineId = $baselineId
}
Write-Host ('MapleBridge security maintenance is CloudFormation-managed: {0} UTC.' -f $Schedule)
