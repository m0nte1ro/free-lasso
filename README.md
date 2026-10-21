# free-lasso

A small, free replacement for the one Process Lasso trick that fixes PUBG stutter: pinning the game to **one thread per performance core**.

> **PUBG and Windows only, for now.**

On hybrid Intel CPUs (12th gen and newer), PUBG can stutter when Windows schedules it onto E-cores or onto both hyperthreads of the same core. free-lasso watches for `TslGame.exe` and, as soon as it starts, restricts it to the first thread of every P-core. That's the same thing a Process Lasso CPU-affinity rule does, without installing Process Lasso.

Example on an i7-12700KF (8 P-cores with hyperthreading + 4 E-cores = 20 logical CPUs):

| Logical CPUs | What they are | Used by PUBG |
|---|---|---|
| 0, 2, 4, 6, 8, 10, 12, 14 | First thread of each P-core | Yes |
| 1, 3, 5, 7, 9, 11, 13, 15 | Second (hyperthread) of each P-core | No |
| 16, 17, 18, 19 | E-cores | No |

The CPU layout is detected automatically, so it adapts to other CPUs. On a CPU without E-cores it simply uses one thread per core.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built into Windows; nothing to install)
- PUBG (`TslGame.exe`), tested with the Steam version

## Install

1. Download this repo (**Code → Download ZIP** and extract it, or `git clone`) to a folder you'll keep. The startup task runs the script from that folder, so don't delete or move it afterwards.
2. Open PowerShell **as administrator** (Start → type *PowerShell* → right-click → *Run as administrator*).
3. Go to the folder and run the installer:

   ```powershell
   cd "C:\path\to\free-lasso"
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

The installer:

1. Runs a self-test: it pins a throwaway `ping.exe` and checks that it worked.
2. Creates a hidden scheduled task, **PUBG CPU Affinity**, that starts the watcher every time you log in.
3. Starts the watcher right away.

**Admin or not?** Installing from an admin window is recommended: the watcher then sleeps until Windows reports that the game started and uses no CPU while waiting. It also works from a normal window, but then it checks for the game every 3 seconds (well under 1% of one core).

## Check that it's working

Launch PUBG, then either:

- open the log at `%LOCALAPPDATA%\pubg-affinity.log` and look for a line like
  `PID 7100: affinity set, now 0x5555`, or
- open Task Manager → **Details** → right-click `TslGame.exe` → **Set affinity** and check that only the expected CPUs are ticked.

PUBG may start more than one `TslGame.exe` process; each one gets pinned.

## Uninstall

From the same kind of window you installed from (admin if you installed as admin):

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Then delete the folder.

## Custom CPU mask

To pick the CPUs yourself, edit the **PUBG CPU Affinity** task in Task Scheduler and add `-Mask <number>` to the end of the arguments. The number is a bitmask: bit *n* set means logical CPU *n* is allowed. For example, `-Mask 0x5555` means CPUs 0, 2, 4 … 14.

## Notes

- It only changes the game's CPU affinity, the same setting as Task Manager's *Set affinity*. It doesn't read or modify game memory or files. Even so, anti-cheat policies are up to the game, so use it at your own risk.
- The affinity is applied once per game launch: right away in admin mode, within 3 seconds otherwise.
- More games and settings may come later.
