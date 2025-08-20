
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