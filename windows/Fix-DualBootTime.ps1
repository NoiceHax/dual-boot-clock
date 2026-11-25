<#
.SYNOPSIS
    Fixes the dual-boot clock drift between Ubuntu and Windows.

.DESCRIPTION
    Ubuntu stores the hardware clock (RTC) in UTC, while Windows by default
    assumes it holds local time. Whichever OS booted last "wins" and the
    other one shows a wrong clock.

    This script makes Windows read/write the hardware clock as UTC too,
    by setting the RealTimeIsUniversal registry value, then re-syncs the
    system time from an NTP server.

    Both OSes now agree: RTC = UTC, each applies its own timezone offset
    (e.g. UTC+5:30) for display.

.PARAMETER Undo
    Reverts the fix (removes RealTimeIsUniversal) if you ever want the
    old Windows behaviour back.

.EXAMPLE
    .\Fix-DualBootTime.ps1            # apply the fix
    .\Fix-DualBootTime.ps1 -Undo      # revert it

.NOTES
    Requires: Windows 10/11, administrator rights (it self-elevates).
    Ubuntu side must keep its default "RTC in local TZ: no" setting.
#>

[CmdletBinding()]
param(
    [switch]$Undo
)

$ErrorActionPreference = 'Stop'
$regPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
$regValue = 'RealTimeIsUniversal'

function Write-Step  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "  [!] $m"  -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "  [X] $m"  -ForegroundColor Red }

# --- 1. Ensure administrator rights (self-elevate if needed) -----------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Step 'Requesting administrator rights (accept the UAC prompt)...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Undo) { $argList += '-Undo' }
    try {
        Start-Process pwsh -Verb RunAs -ArgumentList $argList -Wait
        exit 0
    } catch [System.ComponentModel.Win32Exception] {
        # Older machines may not ship PowerShell 7; retry with Windows PowerShell 5.1
        try {
            Start-Process powershell -Verb RunAs -ArgumentList $argList -Wait
            exit 0
        } catch {
            Write-Err 'Elevation was declined. Administrator rights are required.'
            exit 1
        }
    }
}

$before = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# --- 2. Apply / revert the registry fix --------------------------------------
if ($Undo) {
    Write-Step 'Reverting: removing RealTimeIsUniversal...'
    if (Get-ItemProperty -Path $regPath -Name $regValue -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $regPath -Name $regValue
        Write-Ok 'RealTimeIsUniversal removed (Windows back to local-time RTC).'
    } else {
        Write-Warn2 'Value was not set - nothing to revert.'
    }
} else {
    Write-Step 'Setting RealTimeIsUniversal = 1 (Windows reads RTC as UTC)...'
    New-ItemProperty -Path $regPath -Name $regValue -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Ok 'Registry value written.'
}

# --- 3. Ensure the time service is running and resync ------------------------
Write-Step 'Configuring and starting the Windows Time service...'
Set-Service w32time -StartupType Automatic
Start-Service w32time -ErrorAction SilentlyContinue
w32tm /config /update /manualpeers 'time.windows.com,0x9 pool.ntp.org,0x9' | Out-Null
w32tm /resync /force | Out-Null
Write-Ok 'Time service configured and resync forced.'

# --- 4. Verify ---------------------------------------------------------------
Write-Step 'Verifying...'
$set = (Get-ItemProperty -Path $regPath -Name $regValue -ErrorAction SilentlyContinue).$regValue
$svc = (Get-Service w32time).Status

$regOk = if ($Undo) { $null -eq $set } else { $set -eq 1 }

if ($regOk -and $svc -eq 'Running') {
    if ($Undo) { Write-Ok 'RealTimeIsUniversal not set' } else { Write-Ok 'RealTimeIsUniversal = 1' }
    Write-Ok "w32time service: $svc"
    Write-Host ''
    w32tm /query /status
    Write-Host ''
    Write-Host "Time before fix : $before"          -ForegroundColor Gray
    Write-Host "Time now        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ''
    if ($Undo) {
        Write-Host 'Fix reverted. Next boot into Ubuntu, re-sync its clock: sudo timedatectl set-ntp true' -ForegroundColor Yellow
    } else {
        Write-Host 'Fix applied! Boot into Ubuntu and verify with: timedatectl' -ForegroundColor Green
        Write-Host '(It should show "RTC in local TZ: no" and the correct local time.)' -ForegroundColor Gray
    }
    exit 0
} else {
    Write-Err "Verification failed (registry=$set, service=$svc)."
    exit 1
}
