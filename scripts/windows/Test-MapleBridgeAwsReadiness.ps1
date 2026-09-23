[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ProfileName,

    [string] $Region = 'us-west-2',

    [string] $AvailabilityZone = 'us-west-2a',

    [string] $BlueprintId = 'ubuntu_24_04',

    [string] $BundleId = 'nano_3_0',

    [string] $TemplatePath,

    [string] $AwsExecutable = 'aws'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$modulePath = Join-Path $repositoryRoot 'src\MapleBridge\MapleBridge.psm1'
Import-Module $modulePath -Force

if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Join-Path $repositoryRoot 'infrastructure\gateway.template.json'
}

$parameters = @{} + $PSBoundParameters
$parameters.TemplatePath = $TemplatePath

$result = Test-MapleBridgeAwsReadiness @parameters
$result

Write-Host ('AWS readiness passed for profile {0} in {1}.' -f $result.profileName, $result.region)
Write-Host ('Lightsail selection: {0} / {1} at USD {2} per month before taxes and other service charges.' -f $result.blueprintId, $result.bundleId, $result.monthlyPriceUsd)
Write-Warning 'This check does not include Systems Manager hybrid-node usage charges. Recheck current SSM pricing before deployment.'
