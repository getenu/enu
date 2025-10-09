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

rem Define required paths for Windows
rem Common paths
set "required_paths=vendor\nim\bin"
set "required_paths=!required_paths!;nimbledeps\bin"
rem Windows-specific paths
set "required_paths=!required_paths!;build_env\mingw64\bin"
set "required_paths=!required_paths!;build_env\python"
set "required_paths=!required_paths!;build_env\python\Scripts"

rem Check each required path
for %%p in ("!required_paths:;=" "!") do (
    set "rel_path=%%~p"
    set "full_path=%PROJECT_ROOT%\!rel_path!"

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
