# AWS read-only readiness check

`Test-MapleBridgeAwsReadiness.ps1` is a read-only diagnostic that must run before any deployment or change-set creation. It does not create, update, or delete AWS resources.

The check performs only these API operations:

- `sts get-caller-identity`, used to verify that the named profile works; the account ID and caller ARN are not returned or printed.
- `lightsail get-regions --include-availability-zones`, used to verify the selected Oregon Availability Zone.
- `lightsail get-blueprints --include-inactive`, used to verify that the selected Ubuntu blueprint is active.
- `lightsail get-bundles --include-inactive`, used to verify the selected bundle and report its current Lightsail monthly price.
- `cloudformation validate-template`, used for AWS-side template validation.

After completing [Windows prerequisites](windows-prerequisites.md) and configuring the named profile outside the repository:

```powershell
.\scripts\windows\Test-MapleBridgeAwsReadiness.ps1 `
    -ProfileName '<profile-name>' `
    -Region 'us-west-2' `
    -AvailabilityZone 'us-west-2a' `
    -BlueprintId 'ubuntu_24_04' `
    -BundleId 'nano_3_0'
```

The result intentionally omits the AWS account ID and caller ARN. The reported bundle price does not include taxes, bandwidth overage, or Systems Manager hybrid-node usage. See the [AWS cost model](costs.md) and recheck official pricing immediately before deployment.

On 2026-09-22, this command passed live read-only validation with AWS CLI v2 in `us-west-2`, using the documented Ubuntu 24.04 and Nano candidates. Default tests still use mocked AWS responses and do not contact AWS.
