$repoRoot = Split-Path -Parent $PSScriptRoot
$template = Get-Content -LiteralPath (Join-Path $repoRoot 'infrastructure\gateway.template.json') -Raw | ConvertFrom-Json
$scriptContent = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\windows\Set-MapleBridgeMaintenance.ps1') -Raw
$statusContent = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\windows\Get-MapleBridgeMaintenanceStatus.ps1') -Raw

Describe 'MapleBridge maintenance role' {
    It 'allows only the patch document and managed nodes for SendCommand' {
        $role = $template.Resources.MaintenanceWindowRole.Properties
        $role.Path | Should Be '/maplebridge/'
        $role.AssumeRolePolicyDocument.Statement[0].Principal.Service | Should Be 'ssm.amazonaws.com'
        $send = $role.Policies[0].PolicyDocument.Statement | Where-Object Action -EQ 'ssm:SendCommand'
        ($send.Resource | ConvertTo-Json -Depth 8) | Should Match 'AWS-RunPatchBaseline'
        ($send.Resource | ConvertTo-Json -Depth 8) | Should Match 'managed-instance/\*'
        ($role | ConvertTo-Json -Depth 12) | Should Not Match '"Action":\s*"\*"'
    }
}

Describe 'CloudFormation-managed maintenance resources' {
    It 'owns the window, exact managed-node target, and patch task' {
        $window = $template.Resources.SecurityMaintenanceWindow
        $target = $template.Resources.SecurityMaintenanceTarget
        $task = $template.Resources.SecurityMaintenanceTask

        $window.Type | Should Be 'AWS::SSM::MaintenanceWindow'
        $target.Type | Should Be 'AWS::SSM::MaintenanceWindowTarget'
        $task.Type | Should Be 'AWS::SSM::MaintenanceWindowTask'
        $window.Condition | Should Be 'CreateAutomaticMaintenance'
        $window.Properties.ScheduleTimezone | Should Be 'UTC'
        $window.Properties.Schedule.Ref | Should Be 'MaintenanceSchedule'
        $target.Properties.Targets[0].Key | Should Be 'InstanceIds'
        $target.Properties.Targets[0].Values[0].Ref | Should Be 'MaintenanceManagedNodeId'
        $task.Properties.Targets[0].Key | Should Be 'WindowTargetIds'
        $task.Properties.Targets[0].Values[0].Ref | Should Be 'SecurityMaintenanceTarget'
        $task.Properties.TaskArn | Should Be 'AWS-RunPatchBaseline'
        $task.Properties.TaskInvocationParameters.MaintenanceWindowRunCommandParameters.Parameters.Operation[0] | Should Be 'Install'
        $task.Properties.TaskInvocationParameters.MaintenanceWindowRunCommandParameters.Parameters.RebootOption[0] | Should Be 'RebootIfNeeded'
    }

    It 'exports all three CloudFormation-owned resource identifiers' {
        $template.Outputs.MaintenanceWindowId.Value.Ref | Should Be 'SecurityMaintenanceWindow'
        $template.Outputs.MaintenanceWindowTargetId.Value.Ref | Should Be 'SecurityMaintenanceTarget'
        $template.Outputs.MaintenanceWindowTaskId.Value.Ref | Should Be 'SecurityMaintenanceTask'
    }
}

Describe 'Get-MapleBridgeMaintenanceStatus contract' {
    It 'reports executions and patch state for the exact managed node' {
        $statusContent | Should Match "'cloudformation', 'describe-stacks'"
        $statusContent | Should Match "OutputKey -EQ 'MaintenanceWindowId'"
        $statusContent | Should Match 'describe-maintenance-window-executions'
        $statusContent | Should Match "'--max-results', '10'"
        $statusContent | Should Match 'describe-instance-patch-states'
        $statusContent | Should Match ([regex]::Escape("--instance-ids', [string] `$state.managedNodeId"))
        $statusContent | Should Match 'installedPendingReboot'
        $statusContent | Should Match 'missing'
        $statusContent | Should Match 'failed'
    }
}

Describe 'Set-MapleBridgeMaintenance contract' {
    It 'updates the stack with the documented schedule and exact managed node' {
        $scriptContent | Should Match ([regex]::Escape("[string] `$Schedule = 'cron(0 18 ? * TUE#1 *)'"))
        $scriptContent | Should Match "'get-default-patch-baseline'.*'UBUNTU'"
        $scriptContent | Should Match "EnableAutomaticMaintenance\s*= 'true'"
        $scriptContent | Should Match 'MaintenanceManagedNodeId\s*= \[string\] \$state\.managedNodeId'
        $scriptContent | Should Match "'cloudformation', 'update-stack'"
        $scriptContent | Should Match "BaselineId -split '/'"
    }

    It 'does not create or mutate maintenance resources outside CloudFormation' {
        $scriptContent | Should Not Match "'ssm', 'create-maintenance-window'"
        $scriptContent | Should Not Match "'ssm', 'update-maintenance-window'"
        $scriptContent | Should Not Match 'register-target-with-maintenance-window'
        $scriptContent | Should Not Match 'register-task-with-maintenance-window'
    }
}
