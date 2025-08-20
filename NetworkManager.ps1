
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
#### Function 3: Get-FirewallStatus
#- **Input:** IncludeRules (switch, optional), Profile (string, default "All")
#- **Output:** Array of profile objects with properties: Profile, Enabled, DefaultInboundAction, DefaultOutboundAction, LoggingEnabled, Status, plus optional RulesSummary
#- **Required:** Check all firewall profiles (Domain, Private, Public)
#- **Required:** Analyze firewall rules if IncludeRules switch is used
 

function Get-FirewallStatus {
    param(
        [switch]$IncludeRules,
        [string]$Profile = "All"
    )

    try {
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction Stop

        if ($Profile -ne "All") {
            $firewallProfiles = $firewallProfiles | Where-Object { $_.Name -eq $Profile }
        }

        $firewallStatus = @()

        foreach ($profile in $firewallProfiles) {
            if ($profile.Enabled -eq $true) {
                $statusText = "ENABLED"
            } else {
                $statusText = "DISABLED"
            }

            $firewallStatus += [PSCustomObject]@{
                Profile              = $profile.Name
                Enabled              = $profile.Enabled
                DefaultInboundAction = $profile.DefaultInboundAction
                DefaultOutboundAction= $profile.DefaultOutboundAction
                LoggingEnabled       = $profile.LogFileName -ne $null -and $profile.LogAllowed -ne "None"
                LogMaxSize           = $profile.LogMaxSizeKilobytes
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
