# IAM bootstrap

MapleBridge uses a dedicated IAM user named `maplebridge-deployer` for project automation. Its customer managed policy is [maplebridge-deployer-policy.json](../infrastructure/iam/maplebridge-deployer-policy.json). The policy is intentionally limited to Oregon (`us-west-2`), MapleBridge-prefixed CloudFormation stacks and change sets, roles under `/maplebridge/`, the required Lightsail lifecycle, and Systems Manager gateway operations.

AWS recommends temporary credentials instead of long-lived IAM user access keys. This project uses a dedicated access key as an explicit bootstrap tradeoff for a single-user local automation workflow. Do not enable console access for this user, reuse it for another project, or commit its credentials.

## CloudShell method

Open AWS CloudShell from an administrator session. Upload these two files through **Actions > Upload file**:

- `infrastructure/iam/maplebridge-deployer-policy.json`
- `scripts/aws/create-deployer-user.sh`

Run:

```bash
chmod +x create-deployer-user.sh
./create-deployer-user.sh ./maplebridge-deployer-policy.json
```

The command is repeatable for the user and policy, but deliberately refuses to create a second access key. On its first successful run it writes the only copy of the new secret to `~/maplebridge-access-key.json` with mode `600`; it does not print the secret. Download that file through CloudShell **Actions > Download file**.

On Windows, complete [Windows prerequisites](windows-prerequisites.md), then configure the profile interactively:

```powershell
aws configure --profile maplebridge
```

Enter the access key ID and secret from the downloaded JSON, set the default region to `us-west-2`, and use `json` as the output format. Verify it without printing the account or caller ARN:

```powershell
aws sts get-caller-identity --profile maplebridge --query 'Account' --output text | ForEach-Object { 'AWS profile works.' }
```

After verification, delete the downloaded JSON from Windows and securely remove the CloudShell copy:

```bash
shred -u ~/maplebridge-access-key.json
```

CloudShell cannot directly write credentials into the Windows AWS profile: the browser and local machine are separate trust boundaries. The download and local `aws configure` step is therefore intentional.

## Console method

1. Open **IAM > Policies > Create policy**, choose the JSON editor, paste the contents of `maplebridge-deployer-policy.json`, and create it as `MapleBridgeDeployer`.
2. Open **IAM > Users > Create user**, name it `maplebridge-deployer`, and do not grant AWS Management Console access.
3. Attach the `MapleBridgeDeployer` customer managed policy directly to the user.
4. Open the user's **Security credentials** tab, choose **Create access key**, select the CLI use case, and download the CSV. AWS shows the secret access key only at creation time.
5. Run `aws configure --profile maplebridge` locally, verify the profile as above, and then securely delete the CSV.

## What the policy permits

- Read-only identity, Lightsail availability, pricing metadata, and CloudFormation template checks.
- Create, inspect, update, and delete `maplebridge*` CloudFormation stacks and change sets in `us-west-2`.
- Provision and operate the required Lightsail instance, static IP, tags, and public port configuration in `us-west-2`. Start, stop, and reboot are included because the CloudFormation Lightsail instance provider uses instance lifecycle calls during provisioning and recovery.
- Manage and pass only IAM roles below `/maplebridge/`, pass those roles only to Systems Manager, and attach only the two approved AWS-managed SSM policies. The deployment command supplies the path-qualified role name to SSM activation.
- Create and manage SSM hybrid activations, managed-node commands and sessions, maintenance windows, and patch status in `us-west-2`.

It does not grant IAM user or access-key administration, general IAM role access, public SSH management, or unrestricted administrator permissions. The administrator or CloudShell identity used for bootstrap must separately be allowed to create the user, policy, and first access key.

Live AWS use is opt-in and may incur charges. Review the policy and the exact stack target before deployment.
