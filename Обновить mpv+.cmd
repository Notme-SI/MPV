@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0portable_config\maintenance\Update-MPV.ps1" -Mode Interactive
pause
