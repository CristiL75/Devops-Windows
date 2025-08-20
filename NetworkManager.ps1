function Get-NetworkConfiguration {
    [CmdletBinding()]
    param(

        Write-Host "===============================" -ForegroundColor Cyan
        Write-Host "=== Network & Connectivity Monitor Starting ===" -ForegroundColor Cyan
        Write-Host "===============================" -ForegroundColor Cyan

        # 1. Get network configuration
        $networkConfig = Get-NetworkConfiguration
        $activeAdapters = ($networkConfig | Where-Object { $_.Status -eq "Up" }).Count
        $totalAdapters = $networkConfig.Count
        $adaptersNoIP = ($networkConfig | Where-Object { $_.IPAddress -eq "No IP" }).Count

        Write-Host "\n[ Network Adapters ]" -ForegroundColor Yellow
        Write-Host ("Active: {0} / Total: {1}" -f $activeAdapters, $totalAdapters) -ForegroundColor Yellow
        foreach ($adapter in $networkConfig) {
            $color = if ($adapter.Status -eq "Up") { 'Green' } elseif ($adapter.Status -eq "Disconnected") { 'Yellow' } else { 'Red' }
            Write-Host ("  - {0} ({1}) | Status: {2}, IP: {3}, MAC: {4}, GW: {5}, DNS: {6}, DHCP: {7}" -f $adapter.Name, $adapter.InterfaceDescription, $adapter.Status, $adapter.IPAddress, $adapter.MacAddress, $adapter.DefaultGateway, $adapter.DNSServers, $adapter.DHCPEnabled) -ForegroundColor $color
        }
        if ($adaptersNoIP -gt 0) {
            Write-Host ("  Adapters without IP: {0}" -f $adaptersNoIP) -ForegroundColor Red
        }

        # 2. Test connectivity
        $connectivityResults = Test-NetworkConnectivity
        $totalHosts = $connectivityResults.Count
        $failedHosts = ($connectivityResults | Where-Object { $_.PingSuccess -eq $false }).Count
        $totalPorts = ($connectivityResults | Measure-Object TotalPorts -Sum).Sum
        $totalSuccessfulPorts = ($connectivityResults | Measure-Object SuccessfulPorts -Sum).Sum
        $portFailureRate = if ($totalPorts -gt 0) { 1 - ($totalSuccessfulPorts / $totalPorts) } else { 1 }

        Write-Host "\n[ Connectivity Results ]" -ForegroundColor Yellow
        foreach ($result in $connectivityResults) {
            $color = if ($result.PingSuccess -eq $true -and $result.SuccessfulPorts -eq $result.TotalPorts) {
                'Green'
            } elseif ($result.PingSuccess -eq $true -and $result.SuccessfulPorts -gt 0) {
                'Yellow'
            } else {
                'Red'
            }
            Write-Host ("- Host: {0}" -f $result.Host) -ForegroundColor $color
            Write-Host ("    Ping: {0} | Avg Response: {1} ms" -f $result.PingSuccess, $result.AverageResponseTime) -ForegroundColor $color
            Write-Host ("    Ports: {0}/{1} open" -f $result.SuccessfulPorts, $result.TotalPorts) -ForegroundColor $color
            foreach ($p in $result.PortTests) {
                $pColor = if ($p.Success) { 'Green' } else { 'Red' }
                Write-Host ("      - Port {0}: {1}" -f $p.Port, $p.ResponseTime) -ForegroundColor $pColor
            }
        }

        # 3. Firewall status
        $firewallStatus = Get-FirewallStatus
        $disabledFirewalls = ($firewallStatus | Where-Object { $_.Enabled -eq $false }).Count
        $allFirewallsDisabled = ($firewallStatus.Count -gt 0 -and $disabledFirewalls -eq $firewallStatus.Count)

        Write-Host "\n[ Firewall Status ]" -ForegroundColor Yellow
        foreach ($fw in $firewallStatus) {
            $fwColor = if ($fw.Enabled) { 'Green' } else { 'Red' }
            Write-Host ("- Profile: {0} | Status: {1} | Inbound: {2} | Outbound: {3} | Logging: {4}" -f $fw.Profile, $fw.Status, $fw.DefaultInboundAction, $fw.DefaultOutboundAction, $fw.LoggingEnabled) -ForegroundColor $fwColor
        }

        # 4. Calculate health score
        $score = 100
        $recommendations = @()
        if ($activeAdapters -eq 0) {
            $score -= 25
            $recommendations += "No active adapters: Check physical connections or enable adapters."
        }
        $score -= [Math]::Min($adaptersNoIP * 15, 45)
        if ($adaptersNoIP -gt 0) {
            $recommendations += "Some adapters have no IP: Check DHCP or configure static IPs."
        }
        if ($portFailureRate -ge 0.5) {
            $score -= 20
            $recommendations += "Connectivity failures >50%: Check internet connection and DNS."
        } elseif ($portFailureRate -ge 0.2) {
            $score -= 10
            $recommendations += "Connectivity failures 20-50%: Investigate network issues."
        }
        $score -= ($disabledFirewalls * 10)
        if ($disabledFirewalls -gt 0) {
            $recommendations += "Some firewall profiles are disabled: Enable Windows Firewall for security."
        }

        # 5. Color coding summary
        Write-Host "\n===============================" -ForegroundColor Cyan
        if ($activeAdapters -eq 0 -or $portFailureRate -ge 0.5 -or $allFirewallsDisabled) {
            $summaryColor = 'Red'
        } elseif ($adaptersNoIP -gt 0 -or ($portFailureRate -ge 0.2 -and $portFailureRate -lt 0.5) -or $disabledFirewalls -gt 0) {
            $summaryColor = 'Yellow'
        } else {
            $summaryColor = 'Green'
        }
        Write-Host ("Network Health Score: $score/100") -ForegroundColor $summaryColor
        if ($recommendations.Count -gt 0) {
            Write-Host "\n[ Recommendations ]" -ForegroundColor Yellow
            foreach ($rec in $recommendations) {
                Write-Host ("- $rec") -ForegroundColor Magenta
            }
        }
        Write-Host "===============================" -ForegroundColor Cyan
        Write-Host "=== Network & Connectivity Monitor Complete ===" -ForegroundColor Cyan
        Write-Host "===============================" -ForegroundColor Cyan

        return [PSCustomObject]@{
            NetworkHealthScore = $score
            AdapterSummary = $networkConfig
            ConnectivityResults = $connectivityResults
            FirewallStatus = $firewallStatus
            Recommendations = $recommendations
            MonitorTime = Get-Date
        }
    }
        [int[]]$TestPorts = @(80, 443, 53),
        [int]$TimeoutSeconds = 5
    )



    $results = @()
    $hostIndex = 0
    while ($hostIndex -lt $TestHosts.Count) {
        $testHost = $TestHosts[$hostIndex]
        Write-Host "Testing host: $testHost ..." -ForegroundColor Cyan
        $pingSuccess = $false
        $avgResponseTime = -1
        try {
            $pingResult = Test-Connection -ComputerName $testHost -Count 4 -ErrorAction Stop
            $avgResponseTime = ($pingResult | Measure-Object ResponseTime -Average).Average
            $pingSuccess = $true
            Write-Host "  Ping success, avg: $avgResponseTime ms" -ForegroundColor Green
        } catch {
            Write-Host "  Ping failed" -ForegroundColor Red
        }

        $portResults = @()
        $successCount = 0
        $portIndex = 0
        while ($portIndex -lt $TestPorts.Count) {
            $port = $TestPorts[$portIndex]
            Write-Host "    Testing port $port ..." -ForegroundColor Yellow
            $portTest = $null
            $success = $false
            try {
                $portTest = Test-NetConnection -ComputerName $testHost -Port $port -WarningAction SilentlyContinue
                if ($portTest.TcpTestSucceeded) {
                    $success = $true
                    $successCount++
                    Write-Host "      Port $port open" -ForegroundColor Green
                } else {
                    Write-Host "      Port $port closed" -ForegroundColor Red
                }
            } catch {
                Write-Host "      Port $port test error" -ForegroundColor Red
            }
            $portResults += [PSCustomObject]@{
                Port = $port
                Success = $success
                ResponseTime = if ($success) { "Success" } else { "Failed" }
            }
            $portIndex++
        }

        $results += [PSCustomObject]@{
            Host = $testHost
            PingSuccess = $pingSuccess
            AverageResponseTime = $avgResponseTime
            PortTests = $portResults
            SuccessfulPorts = $successCount
            TotalPorts = $TestPorts.Count
        }
        $hostIndex++
    }
    return $results
}
function Get-FirewallStatus {
    param(
        [switch]$IncludeRules,
        [string]$fwprofile = "All"
    )

    try {
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction Stop

        if ($fwprofile -ne "All") {
            $firewallProfiles = $firewallProfiles | Where-Object { $_.Name -eq $fwprofile }
        }

        $firewallStatus = @()

        foreach ($fwprofiles in $firewallProfiles) {
            if ($fwprofiles.Enabled -eq $true) {
                $statusText = "ENABLED"
            } else {
                $statusText = "DISABLED"
            }
            Write-Host "text $fwprofiles.Name"
            $firewallStatus += [PSCustomObject]@{
                Profile              = $fwprofiles.Name
                Enabled              = $fwprofiles.Enabled
                DefaultInboundAction = $fwprofiles.DefaultInboundAction
                DefaultOutboundAction= $fwprofiles.DefaultOutboundAction
                LoggingEnabled       = $fwprofiles.LogFileName -ne $null -and $fwprofiles.LogAllowed -ne "None"
                LogMaxSize           = $fwprofiles.LogMaxSizeKilobytes
                Status               = $statusText
            }
        }

        if ($IncludeRules) {
            $allRules    = Get-NetFirewallRule -ErrorAction Stop
            $enabledRules= $allRules | Where-Object { $_.Enabled -eq $true }

            $rulesSummary = [PSCustomObject]@{
                TotalRules   = $allRules.Count
                EnabledRules = $enabledRules.Count
                InboundRules = ($allRules | Where-Object { $_.Direction -eq "Inbound" }).Count
                OutboundRules= ($allRules | Where-Object { $_.Direction -eq "Outbound" }).Count
                AllowRules   = ($allRules | Where-Object { $_.Action -eq "Allow" }).Count
                BlockRules   = ($allRules | Where-Object { $_.Action -eq "Block" }).Count
            }

            if ($firewallStatus.Count -gt 0) {
                $firewallStatus[0] | Add-Member -MemberType NoteProperty -Name "RulesSummary" -Value $rulesSummary
            }
        }

        return $firewallStatus
    }
    catch {
        Write-Error "Insufficient permissions or another error occurred: $_"
    }
}

function Start-NetworkMonitor {
    Write-Host "=== Network & Connectivity Monitor Starting ===" -ForegroundColor Cyan

    $networkConfig = Get-NetworkConfiguration
    $activeAdapters = ($networkConfig | Where-Object { $_.Status -eq "Up" }).Count
    $totalAdapters = $networkConfig.Count
    $adaptersNoIP = ($networkConfig | Where-Object { $_.IPAddress -eq "No IP" }).Count

    Write-Host "Network Adapters: $activeAdapters active / $totalAdapters total" -ForegroundColor Yellow
    if ($adaptersNoIP -gt 0) {
        Write-Host "Adapters without IP: $adaptersNoIP" -ForegroundColor Red
    }

 
    $connectivityResults = Test-NetworkConnectivity
    $totalHosts = $connectivityResults.Count
    $failedHosts = ($connectivityResults | Where-Object { $_.PingSuccess -eq $false }).Count
    $totalPorts = ($connectivityResults | Measure-Object TotalPorts -Sum).Sum
    $totalSuccessfulPorts = ($connectivityResults | Measure-Object SuccessfulPorts -Sum).Sum
    $portFailureRate = if ($totalPorts -gt 0) { 1 - ($totalSuccessfulPorts / $totalPorts) } else { 1 }

    foreach ($result in $connectivityResults) {
        $color = if ($result.PingSuccess -eq $true -and $result.SuccessfulPorts -eq $result.TotalPorts) {
            'Green'
        } elseif ($result.PingSuccess -eq $true -and $result.SuccessfulPorts -gt 0) {
            'Yellow'
        } else {
            'Red'
        }
        Write-Host ("Host: {0} | Ping: {1} | Ports: {2}/{3}" -f $result.Host, $result.PingSuccess, $result.SuccessfulPorts, $result.TotalPorts) -ForegroundColor $color
    }


    $firewallStatus = Get-FirewallStatus
    $disabledFirewalls = ($firewallStatus | Where-Object { $_.Enabled -eq $false }).Count
    $allFirewallsDisabled = ($firewallStatus.Count -gt 0 -and $disabledFirewalls -eq $firewallStatus.Count)

    foreach ($fw in $firewallStatus) {
        $fwColor = if ($fw.Enabled) { 'Green' } else { 'Red' }
        Write-Host ("Firewall Profile: {0} | Status: {1}" -f $fw.Profile, $fw.Status) -ForegroundColor $fwColor
    }

  
    $score = 100
    $recommendations = @()
    if ($activeAdapters -eq 0) {
        $score -= 25
        $recommendations += "No active adapters: Check physical connections or enable adapters."
    }
    $score -= [Math]::Min($adaptersNoIP * 15, 45)
    if ($adaptersNoIP -gt 0) {
        $recommendations += "Some adapters have no IP: Check DHCP or configure static IPs."
    }
    if ($portFailureRate -ge 0.5) {
        $score -= 20
        $recommendations += "Connectivity failures >50%: Check internet connection and DNS."
    } elseif ($portFailureRate -ge 0.2) {
        $score -= 10
        $recommendations += "Connectivity failures 20-50%: Investigate network issues."
    }
    $score -= ($disabledFirewalls * 10)
    if ($disabledFirewalls -gt 0) {
        $recommendations += "Some firewall profiles are disabled: Enable Windows Firewall for security."
    }


    if ($activeAdapters -eq 0 -or $portFailureRate -ge 0.5 -or $allFirewallsDisabled) {
        $summaryColor = 'Red'
    } elseif ($adaptersNoIP -gt 0 -or ($portFailureRate -ge 0.2 -and $portFailureRate -lt 0.5) -or $disabledFirewalls -gt 0) {
        $summaryColor = 'Yellow'
    } else {
        $summaryColor = 'Green'
    }
    Write-Host ("Network Health Score: $score/100") -ForegroundColor $summaryColor

    Write-Host "=== Network & Connectivity Monitor Complete ===" -ForegroundColor Cyan

    return [PSCustomObject]@{
        NetworkHealthScore = $score
        AdapterSummary = $networkConfig
        ConnectivityResults = $connectivityResults
        FirewallStatus = $firewallStatus
        Recommendations = $recommendations
        MonitorTime = Get-Date
    }
}