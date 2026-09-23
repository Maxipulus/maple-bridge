# Removal

MapleBridge removal is explicit and scoped. The command backs up Clash Verge profile metadata before changing it and preserves client keys unless their separate deletion switch is supplied.

Remove only the MapleBridge-owned Clash Verge profile and helper files:

```powershell
.\scripts\windows\Remove-MapleBridge.ps1 -ReloadClash
```

The command removes only the `LMapleBridge`, `mMapleBridge`, `sMapleBridge`, `rMapleBridge`, `pMapleBridge`, and `gMapleBridge` entries and files. If MapleBridge was current, the first unrelated profile becomes current. A timestamped backup remains under the Clash Verge data directory.

Permanently remove the AWS gateway as well:

```powershell
.\scripts\windows\Remove-MapleBridge.ps1 `
    -ProfileName 'maplebridge' `
    -RemoveAwsResources `
    -ConfirmGatewayName 'maplebridge-gateway' `
    -ConfirmDestructiveRemoval `
    -ReloadClash
```

The command requires the typed gateway name to exactly match ignored local state and independently verifies the CloudFormation `GatewayName` parameter. It deregisters the exact SSM managed node, deletes and waits for the exact CloudFormation stack, and then removes the gateway state file. CloudFormation deletes the Maintenance Window task, target, and window together with the attached Lightsail static IP, instance, and project IAM roles. It does not operate on an arbitrary stack name supplied at the command line.

Add `-RemoveLocalKeys` only when the client key pair and generated profile must also be permanently deleted. This requires `-ConfirmDestructiveRemoval`. Normal removal preserves the keys so a later reinstall can retain client identity.

Removal does not uninstall Clash Verge, AWS CLI, the Session Manager plugin, or unrelated profiles. AWS deletion is irreversible; inspect the displayed/local state target and save anything required before running it.
