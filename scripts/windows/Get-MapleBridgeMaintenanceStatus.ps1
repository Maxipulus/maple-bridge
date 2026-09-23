[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string] $ProfileName,

    [string] $StatePath,
    [string] $AwsExecutable = 'aws'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1') -Force
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = Join-Path $repositoryRoot 'state\aws-gateway.json' }
$statePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw ('Required state is missing: {0}' -f $statePath) }
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
if ($AwsExecutable -eq 'aws' -and $null -eq (Get-Command $AwsExecutable -ErrorAction SilentlyContinue)) {
    $installedAws = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
    if (Test-Path -LiteralPath $installedAws -PathType Leaf) { $AwsExecutable = $installedAws }
}
$common = @('--profile', $ProfileName, '--region', [string] $state.region, '--output', 'json', '--no-cli-pager')
$stackResponse = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('cloudformation', 'describe-stacks', '--stack-name', [string] $state.stackName) + $common)
$stack = $stackResponse.Stacks[0]
$stackGateway = [string] (@($stack.Parameters | Where-Object ParameterKey -EQ 'GatewayName') | Select-Object -First 1).ParameterValue
if ($stackGateway -cne [string] $state.gatewayName) { throw 'CloudFormation gateway does not match local state.' }
$maintenanceNode = [string] (@($stack.Parameters | Where-Object ParameterKey -EQ 'MaintenanceManagedNodeId') | Select-Object -First 1).ParameterValue
if ($maintenanceNode -cne [string] $state.managedNodeId) { throw 'CloudFormation maintenance targets a different managed node.' }
$windowOutput = @($stack.Outputs | Where-Object OutputKey -EQ 'MaintenanceWindowId') | Select-Object -First 1
if ($null -eq $windowOutput -or [string]::IsNullOrWhiteSpace([string] $windowOutput.OutputValue)) { throw 'Automatic maintenance is not enabled in CloudFormation.' }
$windowId = [string] $windowOutput.OutputValue
$window = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'get-maintenance-window', '--window-id', $windowId) + $common)
$executions = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'describe-maintenance-window-executions', '--window-id', $windowId, '--max-results', '10') + $common)
$patchStates = Invoke-MapleBridgeAwsCli -AwsExecutable $AwsExecutable -Arguments (@('ssm', 'describe-instance-patch-states', '--instance-ids', [string] $state.managedNodeId) + $common)
$latestExecution = @($executions.WindowExecutions | Sort-Object StartTime -Descending) | Select-Object -First 1
$patchState = @($patchStates.InstancePatchStates) | Select-Object -First 1
$status = [pscustomobject] [ordered] @{
    refreshedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    managedBy = 'CloudFormation'
    windowId = $windowId
    enabled = [bool] $window.Enabled
    schedule = [string] $window.Schedule
    scheduleTimezone = [string] $window.ScheduleTimezone
    nextExecutionTime = [string] $window.NextExecutionTime
    latestExecution = if ($null -ne $latestExecution) { [ordered] @{ status = [string] $latestExecution.Status; startTime = $latestExecution.StartTime; endTime = $latestExecution.EndTime } } else { $null }
    patchState = if ($null -ne $patchState) { [ordered] @{ installed = [int] $patchState.InstalledCount; installedPendingReboot = [int] $patchState.InstalledPendingRebootCount; missing = [int] $patchState.MissingCount; failed = [int] $patchState.FailedCount; operationEndTime = $patchState.OperationEndTime } } else { $null }
}
$statusPath = Join-Path $repositoryRoot 'state\maintenance-status.json'
[IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$status
Write-Host ('Maintenance: enabled={0}; next={1}; latest={2}.' -f $status.enabled, $status.nextExecutionTime, $(if ($null -ne $status.latestExecution) { $status.latestExecution.status } else { 'not run' }))
