@echo off
rem One-click launcher for Fix-DualBootTime.ps1
rem Right-click -> Run as administrator is NOT needed; the script self-elevates.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-DualBootTime.ps1" %*
pause
