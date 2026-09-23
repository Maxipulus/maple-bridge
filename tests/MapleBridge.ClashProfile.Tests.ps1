$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'src\MapleBridge\MapleBridge.psm1') -Force

Describe 'Clash Verge profile integration' {
    It 'removes stale card metadata without changing unrelated profiles or enhancements' {
        $path = Join-Path $TestDrive 'profiles.yaml'
        @'
# Profiles Config for Clash Verge

current: LMapleBridge
items:
- uid: Other
  type: local
  name: Keep Me
  file: Other.yaml
- uid: LMapleBridge
  type: local
  name: MapleBridge
  file: LMapleBridge.yaml
  desc: IP 203.0.113.10 | Healthy
  updated: 1
  extra:
    upload: 100
    download: 200
    total: 3000
    expire: 0
  option:
    allow_auto_update: true
    merge: mMapleBridge
'@ | Set-Content -LiteralPath $path -Encoding UTF8

        Reset-MapleBridgeClashProfilePresentation -ProfilesYamlPath $path
        $content = Get-Content -LiteralPath $path -Raw

        $content | Should Match '(?m)^- uid: Other\r?$'
        $content | Should Match '(?m)^  name: Keep Me\r?$'
        $content | Should Match '(?m)^  desc: Generated locally by MapleBridge\r?$'
        $content | Should Not Match '(?m)^  updated:'
        $content | Should Not Match '(?m)^  extra:'
        $content | Should Not Match 'IP 203\.0\.113\.10|upload:|download:|total:'
        $content | Should Match '(?m)^    merge: mMapleBridge\r?$'
    }

    It 'sums metric points and tolerates an empty response' {
        Get-MapleBridgeMetricSum -MetricData @([pscustomobject] @{ sum = 1.4 }, [pscustomobject] @{ sum = 2.6 }) | Should Be 4
        Get-MapleBridgeMetricSum -MetricData @() | Should Be 0
        Get-MapleBridgeMetricSum -MetricData @([pscustomobject] @{ maximum = 99 }) | Should Be 0
        Get-MapleBridgeMetricMaximum -MetricData @([pscustomobject] @{ maximum = 0 }, [pscustomobject] @{ maximum = 1 }) | Should Be 1
    }

    It 'removes duplicate MapleBridge items while preserving unrelated items' {
        $path = Join-Path $TestDrive 'duplicates.yaml'
        @'
current: LMapleBridge
items:
- uid: Other
  type: local
  file: Other.yaml
- uid: mMapleBridge
  type: merge
  file: mMapleBridge.yaml
- uid: LMapleBridge
  type: local
  file: LMapleBridge.yaml
- uid: mMapleBridge
  type: merge
  file: mMapleBridge.yaml
- uid: LMapleBridge
  type: local
  file: LMapleBridge.yaml
'@ | Set-Content -LiteralPath $path -Encoding UTF8

        Repair-MapleBridgeClashProfileIndex -ProfilesYamlPath $path | Should Be 2
        $content = Get-Content -LiteralPath $path -Raw
        ([regex]::Matches($content, '(?m)^- uid: Other\r?$')).Count | Should Be 1
        ([regex]::Matches($content, '(?m)^- uid: mMapleBridge\r?$')).Count | Should Be 1
        ([regex]::Matches($content, '(?m)^- uid: LMapleBridge\r?$')).Count | Should Be 1
    }
}

Describe 'Remove-MapleBridgeClashProfileIndex' {
    It 'removes only MapleBridge entries and selects the first unrelated profile' {
        $path = Join-Path $TestDrive 'remove-profiles.yaml'
        @"
current: LMapleBridge
- uid: unrelated-one
  type: remote
  name: Keep Me
- uid: mMapleBridge
  type: merge
- uid: LMapleBridge
  type: local
- uid: unrelated-two
  type: local
"@ | Set-Content -LiteralPath $path -Encoding UTF8

        $result = Remove-MapleBridgeClashProfileIndex -ProfilesYamlPath $path
        $content = Get-Content -LiteralPath $path -Raw

        $result.removedEntries | Should Be 2
        $result.activeProfile | Should Be 'unrelated-one'
        $content | Should Match '(?m)^current: unrelated-one\r?$'
        $content | Should Match 'uid: unrelated-one'
        $content | Should Match 'uid: unrelated-two'
        $content | Should Not Match 'MapleBridge'
    }
}
