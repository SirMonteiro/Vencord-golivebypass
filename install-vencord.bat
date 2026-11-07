@echo off
setlocal
cd /d "%~dp0"

set "SCRIPT=%~dp0install-vencord.ps1"

if not exist "%SCRIPT%" (
    echo [ERROR] Script not found: "%SCRIPT%"
    pause
    exit /b 1
)

echo Starting Vencord + GoLiveBypass setup...
echo Usage: install-vencord.bat [-Target Discord^|Vesktop^|Both] [-Uninstall]
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo [ERROR] Setup failed with exit code %EXITCODE%.
)
pause
exit /b %EXITCODE%
