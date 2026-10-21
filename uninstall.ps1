# Stops the watcher and removes its logon task. Run from the same kind of window you installed from
# (an admin window if you installed as admin). The log file is left in place.
#   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match 'pubg-affinity\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Unregister-ScheduledTask -TaskName 'PUBG CPU Affinity' -Confirm:$false -ErrorAction SilentlyContinue

if (Get-ScheduledTask -TaskName 'PUBG CPU Affinity' -ErrorAction SilentlyContinue) {
    Write-Host 'Could not remove the task. If you installed as admin, run this from an admin window.' -ForegroundColor Red
} else {
    Write-Host 'Uninstalled. Running games keep their current affinity until they are restarted.' -ForegroundColor Green
}
