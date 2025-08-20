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
