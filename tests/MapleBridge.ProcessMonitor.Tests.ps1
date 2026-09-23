$repositoryRoot = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $repositoryRoot 'scripts\windows\Watch-MapleBridgeProcesses.ps1'
$scriptText = Get-Content -LiteralPath $scriptPath -Raw

Describe 'Watch-MapleBridgeProcesses script' {
    It 'subscribes to process creation and deletion events' {
        $scriptText | Should Match '__InstanceCreationEvent'
        $scriptText | Should Match '__InstanceDeletionEvent'
        $scriptText | Should Match "TargetInstance ISA 'Win32_Process'"
    }

    It 'cleans up both event subscriptions' {
        $scriptText | Should Match 'finally'
        $scriptText | Should Match 'Unregister-Event -SourceIdentifier \$startSource'
        $scriptText | Should Match 'Unregister-Event -SourceIdentifier \$stopSource'
    }

    It 'does not collect process command lines' {
        $scriptText | Should Not Match '\.CommandLine'
    }

    It 'writes observations beneath the ignored state directory by default' {
        $scriptText | Should Match "state\\observations"
        (Get-Content -LiteralPath (Join-Path $repositoryRoot '.gitignore') -Raw) | Should Match '(?m)^/state/'
    }
}
