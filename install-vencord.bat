@echo off
setlocal
cd /d "%~dp0"

set "SCRIPT=%~dp0install-vencord.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found: "%SCRIPT%"
    pause
    exit /b 1
)

echo Starting Vencord + GoLiveBypass Setup...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
echo.
pause
