# Automatic security maintenance

MapleBridge uses AWS Systems Manager Patch Manager and the AWS default Ubuntu patch baseline. It does not install a second independent `unattended-upgrades` schedule.

Configure or update the maintenance plan:

```powershell
.\scripts\windows\Set-MapleBridgeMaintenance.ps1 `
    -ProfileName 'maplebridge'
```

The default schedule is `cron(0 18 ? * TUE#1 *)`: the first Tuesday of every month at 18:00 UTC. The authoritative timezone is explicitly `UTC`. The window lasts two hours and stops starting new work during its final hour. The `AWS-RunPatchBaseline` task installs packages approved by the current AWS default Ubuntu baseline and uses `RebootIfNeeded`; service interruption or a host reboot is therefore possible during the window.

The command is repeatable and updates the existing gateway CloudFormation stack. CloudFormation owns the least-purpose service role, the `maplebridge-security-updates` window, its exact managed-node target, and the `AWS-RunPatchBaseline` task. The managed-node ID and schedule are stack parameters, while the window, target, and task IDs are stack outputs. No separate local maintenance-resource state is required.

In the AWS Console, all maintenance infrastructure appears under the `maplebridge-gateway` CloudFormation stack. The window execution history remains available in Systems Manager under **Maintenance Windows** in `us-west-2`.

Inspect the schedule, next execution, latest execution, and patch counters:

```powershell
.\scripts\windows\Get-MapleBridgeMaintenanceStatus.ps1 `
    -ProfileName 'maplebridge'
```

Before the first run, `latestExecution` and `patchState` are empty. After a run, the status includes installed, pending-reboot, missing, and failed package counts. The status command discovers the window ID from the CloudFormation stack output; only the resulting status snapshot remains under ignored `state/`.

The schedule can be changed with `-Schedule`, `-DurationHours`, and `-CutoffHours`. Supply an AWS Maintenance Windows cron expression directly in UTC; the command does not infer or convert the local Windows timezone. Emergency patching and Ubuntu release upgrades remain separate explicit operations.

Maintenance Windows have no additional scheduling charge. Hybrid-node Run Command usage follows the current Systems Manager price described in [AWS costs](costs.md). See the AWS documentation for [Maintenance Windows](https://docs.aws.amazon.com/systems-manager/latest/userguide/maintenance-windows.html), [task registration](https://docs.aws.amazon.com/systems-manager/latest/userguide/mw-cli-register-tasks-examples.html), and [custom service roles](https://docs.aws.amazon.com/systems-manager/latest/userguide/configuring-maintenance-window-permissions-cli.html).
