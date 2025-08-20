function Get-NetworkConfiguration {
    [CmdletBinding()]
    param(
        [switch]$IncludeDisabled,
        [switch]$DetailedInfo
    )

    $results = @()

    try {
        $adapters = Get-NetAdapter -ErrorAction Stop | Sort-Object ifIndex
    } catch {
        Write-Warning "Nu pot citi adaptoarele de rețea: $($_.Exception.Message)"
        return @()
    }

    foreach ($adapter in $adapters) {
        if ($adapter.Status -eq "Up" -or $IncludeDisabled) {

            $statusText = if ($adapter.Status -eq "Up") {
                "Up"
            } elseif ($adapter.Status -eq "Disabled") {
                "Down"
            } elseif ($adapter.Status -eq "Disconnected") {
                "Disconnected"
            } else {
                $adapter.Status
            }

            try {
                $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction Stop
            } catch {
                $ipConfig = $null
                if ($DetailedInfo) {
                    Write-Verbose "Nu s-a putut citi IP config pentru $($adapter.Name): $($_.Exception.Message)"
                }
            }

            if ($ipConfig -and $ipConfig.IPv4Address) {
                $ipAddress  = $ipConfig.IPv4Address[0].IPAddress
                $subnetMask = $ipConfig.IPv4Address[0].PrefixLength
            } else {
                $ipAddress  = "No IP"
                $subnetMask = "N/A"
            }

            if ($ipConfig -and $ipConfig.IPv4DefaultGateway) {
                $defaultGw = $ipConfig.IPv4DefaultGateway.NextHop
            } else {
                $defaultGw = "No Gateway"
            }

            if ($ipConfig -and $ipConfig.DnsServer -and $ipConfig.DnsServer.ServerAddresses) {
                $dnsServers = ($ipConfig.DnsServer.ServerAddresses -join ", ")
            } else {
                $dnsServers = "No DNS"
            }

            $dhcpEnabled = $false
            try {
                $ipIf = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop
                if ($ipIf.Dhcp -eq "Enabled") { $dhcpEnabled = $true } else { $dhcpEnabled = $false }
            } catch {
                $dhcpEnabled = $false
            }

            $results += [PSCustomObject]@{
                Name                 = $adapter.Name
                InterfaceDescription = $adapter.InterfaceDescription
                Status               = $statusText
                LinkSpeed            = $adapter.LinkSpeed
                MacAddress           = $adapter.MacAddress
                IPAddress            = $ipAddress
                SubnetMask           = $subnetMask
                DefaultGateway       = $defaultGw
                DNSServers           = $dnsServers
                DHCPEnabled          = $dhcpEnabled
            }
        } else {
            if ($DetailedInfo) { Write-Verbose "Sarit peste adaptorul dezactivat: $($adapter.Name)" }
        }
    }

    return $results
}

function Test-NetworkConnectivity {
    param(
        [string[]]$TestHosts = @("8.8.8.8", "1.1.1.1"),
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
    param(
        [string[]]$TestHosts = @("8.8.8.8", "1.1.1.1", "google.com", "microsoft.com"),
        [int[]]$TestPorts = @(80, 443, 53),
        [int]$TimeoutSeconds = 5
    )

    Write-Host "=== Network & Connectivity Monitor Starting ===" -ForegroundColor Cyan

    $networkConfig = Get-NetworkConfiguration
    $activeAdapters = ($networkConfig | Where-Object { $_.Status -eq "Up" }).Count
    $totalAdapters = $networkConfig.Count
    $adaptersNoIP = ($networkConfig | Where-Object { $_.IPAddress -eq "No IP" }).Count

    Write-Host "Network Adapters: $activeAdapters active / $totalAdapters total" -ForegroundColor Yellow
    if ($adaptersNoIP -gt 0) {
        Write-Host "Adapters without IP: $adaptersNoIP" -ForegroundColor Red
    }

    # Folosește parametrii primiți!
    $connectivityResults = Test-NetworkConnectivity -TestHosts $TestHosts -TestPorts $TestPorts -TimeoutSeconds $TimeoutSeconds
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
        $recommendations += "Check physical connections or enable adapters"
    }
    $score -= [Math]::Min($adaptersNoIP * 15, 45)
    if ($adaptersNoIP -gt 0) {
        $recommendations += "Check DHCP or configure static IPs"
    }
    if ($portFailureRate -ge 0.5) {
        $score -= 20
        $recommendations += "Check internet connection and DNS"
    } elseif ($portFailureRate -ge 0.2) {
        $score -= 10
        $recommendations += "Investigate network issues"
    }
    $score -= ($disabledFirewalls * 10)
    if ($disabledFirewalls -gt 0) {
        $recommendations += "Enable Windows Firewall for security"
    }

    if ($activeAdapters -eq 0 -or $portFailureRate -ge 0.5 -or $allFirewallsDisabled) {
        $summaryColor = 'Red'
    } elseif ($adaptersNoIP -gt 0 -or ($portFailureRate -ge 0.2 -and $portFailureRate -lt 0.5) -or $disabledFirewalls -gt 0) {
        $summaryColor = 'Yellow'
    } else {
        $summaryColor = 'Green'
    }
    Write-Host ("Network Health Score: $score/100") -ForegroundColor $summaryColor

    if ($recommendations.Count -gt 0) {
        Write-Host "Recommendations:" -ForegroundColor Yellow
        foreach ($rec in $recommendations) {
            Write-Host ("- $rec") -ForegroundColor Magenta
        }
    }

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