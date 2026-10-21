# free-lasso: pins PUBG (TslGame.exe) to one thread per performance core,
# skipping the second hyperthread of each core and any E-cores.
# Example: on an i7-12700KF that is logical CPUs 0,2,4,...,14 (mask 0x5555).
#
# Run as admin it is event-driven: it sleeps until Windows reports the game started.
# Without admin it falls back to checking for the game every 3 seconds.
# Normally started hidden at logon by the task that install.ps1 creates.

param(
    [string]$ProcessName = 'TslGame.exe',
    [long]$Mask = 0,  # 0 = auto-detect: first thread of every performance core
    [string]$LogPath = (Join-Path $env:LOCALAPPDATA 'pubg-affinity.log')
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CpuTopology {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetLogicalProcessorInformationEx(int relationship, IntPtr buffer, ref int length);

    // One logical CPU (the first thread) per core of the highest efficiency class.
    // Hybrid CPUs: P-cores only. Non-hybrid CPUs: every core.
    public static long PerformanceCoreMask() {
        int len = 0;
        GetLogicalProcessorInformationEx(0, IntPtr.Zero, ref len);  // 0 = RelationProcessorCore
        IntPtr buf = Marshal.AllocHGlobal(len);
        try {
            if (!GetLogicalProcessorInformationEx(0, buf, ref len)) return 0;
            int maxClass = -1;
            for (int pass = 0; pass < 2; pass++) {
                long mask = 0;
                for (int off = 0; off < len; ) {
                    IntPtr p = new IntPtr(buf.ToInt64() + off);
                    int size = Marshal.ReadInt32(p, 4);
                    int effClass = Marshal.ReadByte(p, 9);
                    long coreMask = Marshal.ReadInt64(p, 32);
                    int group = Marshal.ReadInt16(p, 40);
                    if (pass == 0) maxClass = Math.Max(maxClass, effClass);
                    else if (group == 0 && effClass == maxClass) mask |= coreMask & -coreMask;
                    off += size;
                }
                if (pass == 1) return mask;
            }
            return 0;
        } finally {
            Marshal.FreeHGlobal(buf);
        }
    }
}
'@

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Add-Content -Path $LogPath
}

function Set-Affinity([int]$ProcessId) {
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        $p.ProcessorAffinity = [IntPtr]$Mask
        $p.Refresh()
        Write-Log "PID ${ProcessId}: affinity set, now 0x$('{0:X}' -f $p.ProcessorAffinity.ToInt64())"
    } catch {
        Write-Log "PID ${ProcessId}: FAILED - $($_.Exception.Message)"
    }
}

if ($Mask -eq 0) { $Mask = [CpuTopology]::PerformanceCoreMask() }
if ($Mask -eq 0) { Write-Log 'could not detect CPU layout; pass -Mask explicitly'; exit 1 }

# Only one watcher per target at a time, even if the script gets started twice.
$mutex = New-Object System.Threading.Mutex($false, "Local\AffinityWatcher_$ProcessName")
if (-not $mutex.WaitOne(0)) { exit }

$exeBase = [IO.Path]::GetFileNameWithoutExtension($ProcessName)
$useEvents = $true
try {
    Register-CimIndicationEvent -ClassName Win32_ProcessStartTrace -Filter "ProcessName = '$ProcessName'" -SourceIdentifier ProcStart -ErrorAction Stop
} catch {
    $useEvents = $false
}
$mode = if ($useEvents) { 'event-driven' } else { 'polling every 3s, no admin' }
Write-Log "watcher started ($mode, target $ProcessName, mask 0x$('{0:X}' -f $Mask))"

# Catch a game that was already running before the watcher started.
$handled = @{}
foreach ($p in @(Get-Process -Name $exeBase -ErrorAction SilentlyContinue)) {
    Set-Affinity $p.Id
    $handled[$p.Id] = $true
}

if ($useEvents) {
    while ($true) {
        $e = Wait-Event -SourceIdentifier ProcStart
        Remove-Event -EventIdentifier $e.EventIdentifier
        Set-Affinity $e.SourceEventArgs.NewEvent.ProcessID
    }
}

while ($true) {
    $running = @(Get-Process -Name $exeBase -ErrorAction SilentlyContinue)
    foreach ($p in $running) {
        if (-not $handled.ContainsKey($p.Id)) {
            Set-Affinity $p.Id
            $handled[$p.Id] = $true
        }
    }
    # Forget PIDs that have exited so a restarted game gets pinned again.
    foreach ($id in @($handled.Keys)) {
        if ($running.Id -notcontains $id) { $handled.Remove($id) }
    }
    Start-Sleep -Seconds 3
}
