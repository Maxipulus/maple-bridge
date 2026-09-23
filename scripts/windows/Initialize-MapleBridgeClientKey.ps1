[CmdletBinding()]
param(
    [string] $PrivateKeyPath,
    [string] $PublicKeyPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ([string]::IsNullOrWhiteSpace($PrivateKeyPath)) {
    $PrivateKeyPath = Join-Path $repositoryRoot 'state\keys\client.key'
}
if ([string]::IsNullOrWhiteSpace($PublicKeyPath)) {
    $PublicKeyPath = Join-Path $repositoryRoot 'state\keys\client.pub'
}

$resolvedPrivatePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PrivateKeyPath)
$resolvedPublicPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PublicKeyPath)
$privateExists = Test-Path -LiteralPath $resolvedPrivatePath -PathType Leaf
$publicExists = Test-Path -LiteralPath $resolvedPublicPath -PathType Leaf

if ($privateExists -xor $publicExists) {
    throw 'The client key pair is incomplete. Restore the missing matching file; normal setup will not rotate an existing key.'
}

if (-not $privateExists) {
    $directory = Split-Path $resolvedPrivatePath -Parent
    if ($directory -ne (Split-Path $resolvedPublicPath -Parent)) {
        throw 'The initial client private and public key files must use the same directory.'
    }
    if (-not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    $curve = [Security.Cryptography.ECCurve]::CreateFromFriendlyName('curve25519')
    $key = [Security.Cryptography.ECDiffieHellman]::Create($curve)
    try {
        $parameters = $key.ExportParameters($true)
        $privateBytes = [byte[]] $parameters.D.Clone()
        $privateBytes[0] = $privateBytes[0] -band 248
        $privateBytes[31] = ($privateBytes[31] -band 127) -bor 64
        $privateKey = [Convert]::ToBase64String($privateBytes)
        $publicKey = [Convert]::ToBase64String($parameters.Q.X)
    }
    finally {
        $key.Dispose()
    }

    $privateTemporaryPath = '{0}.{1}.tmp' -f $resolvedPrivatePath, [Guid]::NewGuid().ToString('N')
    $publicTemporaryPath = '{0}.{1}.tmp' -f $resolvedPublicPath, [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($privateTemporaryPath, $privateKey + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($publicTemporaryPath, $publicKey + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = [Security.AccessControl.FileSecurity]::new()
        $acl.SetOwner($identity)
        $acl.SetAccessRuleProtection($true, $false)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $privateTemporaryPath -AclObject $acl

        Move-Item -LiteralPath $privateTemporaryPath -Destination $resolvedPrivatePath
        Move-Item -LiteralPath $publicTemporaryPath -Destination $resolvedPublicPath
    }
    finally {
        foreach ($temporaryPath in @($privateTemporaryPath, $publicTemporaryPath)) {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
        $privateKey = $null
    }
    Write-Host 'Generated the client WireGuard key pair locally. The private key remains under ignored state/keys.'
}

$storedPrivateKey = (Get-Content -LiteralPath $resolvedPrivatePath -Raw).Trim()
$storedPublicKey = (Get-Content -LiteralPath $resolvedPublicPath -Raw).Trim()
foreach ($value in @($storedPrivateKey, $storedPublicKey)) {
    if ($value -notmatch '^[A-Za-z0-9+/]{43}=$' -or [Convert]::FromBase64String($value).Length -ne 32) {
        throw 'A stored client WireGuard key is invalid.'
    }
}

[pscustomobject] [ordered] @{
    privateKeyPath = $resolvedPrivatePath
    publicKeyPath  = $resolvedPublicPath
    publicKey      = $storedPublicKey
}
