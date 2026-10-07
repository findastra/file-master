@echo off
rem Double-click to run a read-only File Master scan and open the report.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$r = & '%~dp0scripts\Invoke-FileMasterScan.ps1'; if ($r) { Start-Process $r.ReportPath }"
pause
