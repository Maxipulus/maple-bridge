# Windows prerequisites

Complete these steps before running AWS readiness or deployment commands. MapleBridge does not install software automatically and does not modify Clash Verge Rev itself.

## 1. Install AWS CLI v2

Use a supported 64-bit Windows release. AWS provides two official MSI packages:

- [Current-user installer](https://awscli.amazonaws.com/AWSCLIV2-User.msi), which does not require administrator rights.
- [All-users installer](https://awscli.amazonaws.com/AWSCLIV2.msi), which requires administrator rights.

Run the selected installer, close all existing PowerShell windows, open a new PowerShell window, and verify:

```powershell
aws --version
```

If `aws` is still not found, confirm the installation path and refresh `PATH`. The usual all-users path is `C:\Program Files\Amazon\AWSCLIV2\aws.exe`. Follow the [official AWS CLI Windows installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) for current options and troubleshooting.

## 2. Install the Session Manager plugin

Interactive `aws ssm start-session` commands require the Session Manager plugin. Non-interactive `aws ssm send-command` automation does not require this local plugin.

1. Download the [official Windows installer](https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe).
2. Run it as an administrator and keep the default installation directory.
3. Close existing terminals, open a new PowerShell window, and verify:

```powershell
session-manager-plugin --version
```

Use version `1.2.764.0` or later. The usual installation path is `C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe`. See the [official plugin installation guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-windows.html) and [current minimum-version notice](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

## 3. Create and configure the project identity

Follow [IAM bootstrap](iam-bootstrap.md) to create the dedicated `maplebridge-deployer` user by either CloudShell or the AWS Console. Configure the downloaded access key only in the named local profile:

```powershell
aws configure --profile maplebridge
```

Enter:

- the project access key ID;
- the project secret access key;
- default region `us-west-2`;
- output format `json`.

Do not paste the secret into repository files, issue reports, logs, or chat. Delete the downloaded credential file after the profile works.

## 4. Run the read-only readiness check

From the repository root:

```powershell
.\scripts\windows\Test-MapleBridgeAwsReadiness.ps1 `
    -ProfileName 'maplebridge' `
    -Region 'us-west-2' `
    -AvailabilityZone 'us-west-2a' `
    -BlueprintId 'ubuntu_24_04' `
    -BundleId 'nano_3_0'
```

This contacts AWS but does not create or modify resources. It verifies the profile, Oregon availability, the selected Lightsail blueprint and bundle, and the CloudFormation template.

## 5. Verify Session Manager after deployment

There is no Session Manager target before the gateway is deployed and registered. A hybrid-activated gateway receives an ID beginning with `mi-`. List managed nodes without starting a session:

```powershell
aws ssm describe-instance-information `
    --profile maplebridge `
    --region us-west-2 `
    --query "InstanceInformationList[].[InstanceId,PingStatus,PlatformName]" `
    --output table
```

After the MapleBridge node reports `Online`, start an interactive shell when needed:

```powershell
aws ssm start-session `
    --target 'mi-xxxxxxxxxxxxxxxxx' `
    --profile maplebridge `
    --region us-west-2
```

Normal deployment and maintenance should use Run Command. Interactive sessions are primarily for diagnosis. MapleBridge does not open public SSH as a fallback.

## Other local prerequisite

Install and launch a supported Clash Verge Rev release separately. MapleBridge will generate and manage only its own profile; it will not install Clash Verge Rev or take ownership of unrelated profiles.
