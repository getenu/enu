@echo off
rem Verify that paths from .envrc are in PATH
rem This script can be called by both build.bat and nimble tasks

setlocal enabledelayedexpansion

rem Get project root
set "PROJECT_ROOT=%~dp0.."
cd /d "%PROJECT_ROOT%"

if not exist ".envrc" (
    echo *** ERROR: .envrc not found ***
    echo.
    echo Please ensure .envrc exists and has been loaded with direnv.
    echo For direnv installation and setup, see: https://direnv.net/docs/installation.html
    echo.
    exit /b 1
)

set "missing_paths="
set "has_missing=0"

rem Parse .envrc for PATH_add lines
for /f "usebackq tokens=1,2* delims= " %%a in (".envrc") do (
    if "%%a"=="PATH_add" (
        set "path_to_add=%%b"
        set "full_path=%PROJECT_ROOT%\!path_to_add!"

        rem Check if this path is in the current PATH
        echo ;%PATH%; | find /i ";!full_path!;" >nul
        if errorlevel 1 (
            if "!missing_paths!"=="" (
                set "missing_paths=!full_path!"
            ) else (
                set "missing_paths=!missing_paths!;!full_path!"
            )
            set "has_missing=1"
        )
    )
)

if "%has_missing%"=="1" (
    echo.
    echo *** ERROR: Required paths not found in PATH ***
    echo.
    echo The following paths are missing from your PATH:
    for %%p in ("!missing_paths:;=" "!") do (
        echo   - %%~p
    )
    echo.
    echo Please add these paths to your PATH, or use direnv to manage them automatically.
    echo For direnv installation and setup, see: https://direnv.net/docs/installation.html
    echo.
    exit /b 1
)

endlocal
