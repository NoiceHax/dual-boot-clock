#!/usr/bin/env bash
# Ubuntu side of the dual-boot time fix.
# Makes sure the hardware clock (RTC) is kept in UTC and NTP sync is on,
# matching Windows once Fix-DualBootTime.ps1 has been applied there.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

echo "==> Keeping the hardware clock in UTC..."
timedatectl set-local-rtc 0

echo "==> Turning on NTP time sync..."
timedatectl set-ntp true

echo
timedatectl
echo
if timedatectl show -p LocalRTC --value | grep -qx no; then
    echo "[OK] RTC in local TZ: no. Ubuntu side is set."
else
    echo "[X] RTC is still in local time. Check the output above." >&2
    exit 1
fi
