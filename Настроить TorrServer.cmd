@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0portable_config\maintenance\Configure-TorrServer.ps1"
pause
