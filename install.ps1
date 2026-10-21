# Installs pubg-affinity.ps1 as a hidden task that starts at every logon.
# Recommended: run from an ADMIN PowerShell window, so the watcher is event-driven:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# Without admin it still works, but checks for the game every 3 seconds instead.

$ErrorActionPreference = 'Stop'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script   = Join-Path $PSScriptRoot 'pubg-affinity.ps1'
$taskName = 'PUBG CPU Affinity'
$user     = "$env:USERDOMAIN\$env:USERNAME"
$logPath  = Join-Path $env:LOCALAPPDATA 'pubg-affinity.log'

if (-not (Test-Path $script)) { Write-Host "pubg-affinity.ps1 not found next to install.ps1" -ForegroundColor Red; exit 1 }
if ($isAdmin) {
    Write-Host 'Running as admin: the watcher will be event-driven.' -ForegroundColor Green
} else {
    Write-Host 'Not admin: the watcher will check every 3 seconds. Run from an admin window for event-driven mode.' -ForegroundColor Yellow
}

# 1. Stop any running watcher and remove an older install.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'pubg-affinity\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# 2. Self-test: let the watcher pin a throwaway ping.exe.
$testLog = Join-Path $env:TEMP 'pubg-affinity-test.log'
Remove-Item $testLog -ErrorAction SilentlyContinue
$watcher = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -ProcessName PING.EXE -LogPath `"$testLog`""
Start-Sleep -Seconds 6
$ping = Start-Process ping.exe -ArgumentList '-n 20 127.0.0.1' -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 5
$ping.Refresh()
$got = $ping.ProcessorAffinity.ToInt64()
Stop-Process -Id $ping.Id, $watcher.Id -Force -ErrorAction SilentlyContinue
$testLines = @(Get-Content $testLog -ErrorAction SilentlyContinue)
if ($testLines -match 'affinity set') {
    Write-Host "Self-test passed: test process pinned to 0x$('{0:X}' -f $got)." -ForegroundColor Green
} else {
    Write-Host 'Self-test FAILED. Watcher log:' -ForegroundColor Red
    $testLines
    exit 1
}

# 3. Register the logon task and start it now.
$runLevel  = if ($isAdmin) { 'Highest' } else { 'Limited' }
$action    = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $runLevel
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description "free-lasso: pins TslGame.exe to one thread per performance core. Script: $script" | Out-Null
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 4

Write-Host "Installed: task '$taskName' is running and will start at every logon." -ForegroundColor Green
Write-Host "Log ($logPath):"
Get-Content $logPath -Tail 3 -ErrorAction SilentlyContinue
