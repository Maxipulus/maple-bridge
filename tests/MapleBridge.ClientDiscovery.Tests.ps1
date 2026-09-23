$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'src\MapleBridge\MapleBridge.psm1'
Import-Module $modulePath -Force

Describe 'Get-MapleBridgeTrafficSnapshot' {
    Mock Get-Process -ModuleName MapleBridge {
        @(
            [pscustomobject] @{ ProcessName = 'NexonLauncher'; Id = 101; Path = 'C:\Games\NexonLauncher.exe' }
            [pscustomobject] @{ ProcessName = 'MapleStory'; Id = 202; Path = 'C:\Games\MapleStory.exe' }
            [pscustomobject] @{ ProcessName = 'Browser'; Id = 303; Path = 'C:\Browser.exe' }
        )
    }

    Mock Get-NetTCPConnection -ModuleName MapleBridge {
        @(
            [pscustomobject] @{ OwningProcess = 101; State = 'Established'; LocalAddress = '10.0.0.2'; LocalPort = 50001; RemoteAddress = '198.51.100.10'; RemotePort = 443 }
            [pscustomobject] @{ OwningProcess = 202; State = 'Established'; LocalAddress = '10.0.0.2'; LocalPort = 50002; RemoteAddress = '203.0.113.20'; RemotePort = 8484 }
            [pscustomobject] @{ OwningProcess = 303; State = 'Established'; LocalAddress = '10.0.0.2'; LocalPort = 50003; RemoteAddress = '192.0.2.30'; RemotePort = 443 }
        )
    }

    Mock Get-NetUDPEndpoint -ModuleName MapleBridge {
        @(
            [pscustomobject] @{ OwningProcess = 202; LocalAddress = '0.0.0.0'; LocalPort = 51000 }
            [pscustomobject] @{ OwningProcess = 303; LocalAddress = '0.0.0.0'; LocalPort = 52000 }
        )
    }

    It 'includes matching processes and excludes unrelated processes and connections' {
        $result = Get-MapleBridgeTrafficSnapshot

        @($result.processes).Count | Should Be 2
        @($result.processes.processName) | Should Be @('MapleStory', 'NexonLauncher')
        @($result.tcpConnections).Count | Should Be 2
        @($result.tcpConnections.processName) -contains 'Browser' | Should Be $false
        @($result.udpEndpoints).Count | Should Be 1
        $result.udpEndpoints[0].processName | Should Be 'MapleStory'
    }

    It 'supports an explicit process pattern' {
        $result = Get-MapleBridgeTrafficSnapshot -ProcessNamePattern '^NexonLauncher$'

        @($result.processes).Count | Should Be 1
        $result.processes[0].processName | Should Be 'NexonLauncher'
        @($result.tcpConnections).Count | Should Be 1
        @($result.udpEndpoints).Count | Should Be 0
    }

    It 'returns empty endpoint collections when no process matches' {
        $result = Get-MapleBridgeTrafficSnapshot -ProcessNamePattern '^MissingProcess$'

        @($result.processes).Count | Should Be 0
        @($result.tcpConnections).Count | Should Be 0
        @($result.udpEndpoints).Count | Should Be 0
        Assert-MockCalled Get-NetTCPConnection -ModuleName MapleBridge -Times 0 -Scope It
        Assert-MockCalled Get-NetUDPEndpoint -ModuleName MapleBridge -Times 0 -Scope It
    }
}
