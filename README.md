# dual-boot-clock

Fixes the wrong clock on a Windows + Linux dual-boot.

Linux stores **UTC** in the hardware clock (RTC). Windows reads it as **local time**. Whichever
OS booted last rewrites the RTC in its own format, so the other one comes up off by your UTC
offset (5h30m in India). Browsers then reject TLS certificates, 2FA codes fail and file
timestamps drift.

This repo has two Windows fixes that work together, plus a check for the Linux side.

| Tool | What it does | Use it when |
|---|---|---|
| `windows/Fix-DualBootTime.ps1` | Sets `RealTimeIsUniversal = 1` so Windows treats the RTC as UTC, then resyncs | You want the root cause fixed, once |
| `windows/install-sync-time.ps1` | Scheduled task that resyncs internet time at boot, logon and resume | You can't or won't change the registry, or want a safety net |
| `linux/fix-dual-boot-time.sh` | Confirms Linux keeps the RTC in UTC and NTP is on | Verifying the Linux side |

## Fix 1: make Windows use UTC (recommended)

Sets this value, then resyncs from NTP:

```
HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation
    RealTimeIsUniversal (DWORD) = 1
```

Double-click `windows/install.bat` and accept the UAC prompt, or from PowerShell:

```powershell
.\windows\Fix-DualBootTime.ps1        # apply the fix
.\windows\Fix-DualBootTime.ps1 -Undo  # revert it
```

If your execution policy blocks scripts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Fix-DualBootTime.ps1
```

The script self-elevates, sets the Windows Time service to Automatic, forces a resync
(`time.windows.com`, `pool.ntp.org`) and prints the result.

## Fix 2: resync Windows clock on every boot

Leaves the registry alone and corrects the clock after each Linux session. From an admin
PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File windows\install-sync-time.ps1
```

This registers a task named **Sync clock on boot** and runs it once. Keep the folder where it is:
the task points at `sync-time.ps1` by its full path.

- **Runs as SYSTEM at startup, at logon and on resume.** Fast Startup boots are technically
  resumes, so a startup trigger alone misses most of them. The resume trigger is event `1` from
  `Microsoft-Windows-Power-Troubleshooter`.
- **Allows big corrections in one step.** The installer sets `MaxPosPhaseCorrection` and
  `MaxNegPhaseCorrection` to unlimited so a 5h30m jump is accepted.
- **Retries for up to three minutes**, every 15 seconds, while the network comes up.
- **Logs each run** to `sync-time.log` next to the script, trimmed to the last 100 lines.

Uninstall:

```powershell
Unregister-ScheduledTask -TaskName 'Sync clock on boot' -Confirm:$false
```

## Linux side

Keep Linux's default. After the next boot, `timedatectl` should show `RTC in local TZ: no`. If
not, run:

```bash
chmod +x linux/fix-dual-boot-time.sh
./linux/fix-dual-boot-time.sh
```

It runs `timedatectl set-local-rtc 0` and `timedatectl set-ntp true`.

> Don't run `timedatectl set-local-rtc 1` on Linux. systemd deprecates it, and daylight-saving
> changes and time zone moves get applied twice when both systems adjust the clock.

## Requirements

- Windows 10 or 11 with administrator rights (UAC prompt)
- Linux that stores the RTC in UTC (Ubuntu and most distros)

## License

MIT
