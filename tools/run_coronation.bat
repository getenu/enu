@echo off
REM Wrapper to run coronation with proper PATH for c2nim
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "NIMBLE_BIN=%PROJECT_ROOT%\nimbledeps\bin"

REM Find c2nim.exe in pkgs2 and add its directory to PATH
for /d %%d in ("%PROJECT_ROOT%\nimbledeps\pkgs2\c2nim-*") do (
    set "C2NIM_DIR=%%d"
)

set "PATH=%NIMBLE_BIN%;%C2NIM_DIR%;%PATH%"
"%NIMBLE_BIN%\coronation.cmd" %*
