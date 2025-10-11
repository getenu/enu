@echo off
setlocal enabledelayedexpansion

:: Determine project root (where this script is located)
set "PROJECT_ROOT=%~dp0"
cd /d "%PROJECT_ROOT%"

:: Configuration
set "NIM_DIR=%PROJECT_ROOT%vendor\nim"
set "NIM_BIN=%NIM_DIR%\bin\nim.exe"
set "BUILD_STATE_DIR=%PROJECT_ROOT%.build_state"
set "BUILD_ENV_DIR=%PROJECT_ROOT%build_env"
set "NIM_STATE_FILE=%BUILD_STATE_DIR%\nim_built"

:: MinGW and tool versions (pinned for reproducibility)
set "MINGW_VERSION=13.2.0"
set "MINGW_REV=rt_v11-rev1"
set "MINGW_ARCH=x86_64"
set "MINGW_URL=https://github.com/niXman/mingw-builds-binaries/releases/download/%MINGW_VERSION%-%MINGW_REV%/%MINGW_ARCH%-13.2.0-release-posix-seh-ucrt-%MINGW_REV%.7z"
set "MINGW_DIR=%BUILD_ENV_DIR%\mingw64"

set "PYTHON_VERSION=3.11.9"
set "PYTHON_URL=https://www.python.org/ftp/python/%PYTHON_VERSION%/python-%PYTHON_VERSION%-embed-amd64.zip"
set "PYTHON_DIR=%BUILD_ENV_DIR%\python"

:: Helper functions
call :info "Starting Windows build setup..."

goto :main

:info
    echo [1;34m^=^=^>[0m %~1
    goto :eof

:success
    echo [1;32m✓[0m %~1
    goto :eof

:error
    echo [1;31mERROR:[0m %~1 1>&2
    exit /b 1

:warn
    echo [1;33mWARNING:[0m %~1
    goto :eof

:: Check if nim submodule exists
:check_nim_submodule
    if not exist "%NIM_DIR%\.git" (
        call :info "Nim submodule not initialized, initializing..."
        git submodule update --init --recursive vendor/nim
        if errorlevel 1 call :error "Failed to initialize nim submodule"
        call :success "Nim submodule initialized"
    )
    goto :eof

:: Get current nim submodule commit SHA
:get_nim_sha
    for /f %%i in ('git -C "%NIM_DIR%" rev-parse HEAD') do set "NIM_SHA=%%i"
    goto :eof

:: Check if nim needs to be built
:needs_nim_build
    if not exist "%NIM_BIN%" (
        set "NEEDS_BUILD=1"
        goto :eof
    )

    if not exist "%NIM_STATE_FILE%" (
        set "NEEDS_BUILD=1"
        goto :eof
    )

    call :get_nim_sha
    set /p BUILT_SHA=<"%NIM_STATE_FILE%"

    if not "!NIM_SHA!"=="!BUILT_SHA!" (
        set "NEEDS_BUILD=1"
        goto :eof
    )

    set "NEEDS_BUILD=0"
    goto :eof

:: Download file if not exists
:download_file
    set "url=%~1"
    set "output=%~2"

    if exist "%output%" (
        goto :eof
    )

    call :info "Downloading %output%..."
    powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%url%' -OutFile '%output%'}"
    if errorlevel 1 call :error "Failed to download %url%"
    goto :eof

:: Extract 7z archive
:extract_7z
    set "archive=%~1"
    set "dest=%~2"

    if exist "%dest%" (
        goto :eof
    )

    call :info "Extracting %archive%..."
    powershell -Command "& {Expand-7Zip -ArchiveFileName '%archive%' -TargetPath '%dest%' -ErrorAction Stop}" 2>nul
    if errorlevel 1 (
        :: Fallback to tar which is built into Windows 10+
        tar -xf "%archive%" -C "%dest%"
        if errorlevel 1 (
            call :error "Failed to extract %archive%"
            exit /b 1
        )
    )
    goto :eof

:: Extract zip archive
:extract_zip
    set "archive=%~1"
    set "dest=%~2"

    if exist "%dest%" (
        goto :eof
    )

    call :info "Extracting %archive%..."
    powershell -Command "& {Expand-Archive -Path '%archive%' -DestinationPath '%dest%' -Force}"
    if errorlevel 1 call :error "Failed to extract %archive%"
    goto :eof

:: Download 7zip standalone if needed
:setup_7zip
    set "SEVENZ_EXE=%BUILD_ENV_DIR%\7za.exe"
    if exist "%SEVENZ_EXE%" (
        goto :eof
    )

    mkdir "%BUILD_ENV_DIR%" 2>nul
    call :info "Downloading 7zip standalone..."
    set "SEVENZ_URL=https://www.7-zip.org/a/7za920.zip"
    set "SEVENZ_ZIP=%BUILD_ENV_DIR%\7za.zip"
    call :download_file "%SEVENZ_URL%" "%SEVENZ_ZIP%"

    :: Extract using PowerShell (zip is natively supported)
    powershell -Command "& {Expand-Archive -Path '%SEVENZ_ZIP%' -DestinationPath '%BUILD_ENV_DIR%' -Force}"
    if errorlevel 1 (
        call :error "Failed to extract 7zip"
        exit /b 1
    )
    goto :eof

:: Setup MinGW
:setup_mingw
    if exist "%MINGW_DIR%\bin\gcc.exe" (
        call :success "MinGW already installed"
        goto :eof
    )

    call :info "Setting up MinGW %MINGW_VERSION%..."

    mkdir "%BUILD_ENV_DIR%" 2>nul

    :: Ensure 7zip is available
    call :setup_7zip
    if errorlevel 1 exit /b 1

    set "MINGW_ARCHIVE=%BUILD_ENV_DIR%\mingw.7z"
    call :download_file "%MINGW_URL%" "%MINGW_ARCHIVE%"

    :: Extract using 7zip standalone
    call :info "Extracting MinGW..."
    mkdir "%MINGW_DIR%" 2>nul
    "%SEVENZ_EXE%" x "%MINGW_ARCHIVE%" -o"%BUILD_ENV_DIR%" -y >nul
    if errorlevel 1 (
        call :error "Failed to extract MinGW"
        exit /b 1
    )

    call :success "MinGW installed to %MINGW_DIR%"
    goto :eof

:: Setup Python and scons
:setup_python
    if exist "%PYTHON_DIR%\python.exe" (
        if exist "%PYTHON_DIR%\Scripts\scons.exe" (
            call :success "Python and scons already installed"
            goto :eof
        )
    )

    call :info "Setting up Python %PYTHON_VERSION%..."

    mkdir "%BUILD_ENV_DIR%" 2>nul

    set "PYTHON_ARCHIVE=%BUILD_ENV_DIR%\python.zip"
    call :download_file "%PYTHON_URL%" "%PYTHON_ARCHIVE%"

    call :extract_zip "%PYTHON_ARCHIVE%" "%PYTHON_DIR%"

    :: Enable pip support in embedded Python by uncommenting 'import site' in ._pth file
    for %%f in ("%PYTHON_DIR%\python*._pth") do (
        powershell -Command "(Get-Content '%%f') -replace '^#import site', 'import site' | Set-Content '%%f'"
    )

    :: Install pip and scons
    call :info "Installing scons..."
    powershell -Command "& {Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%PYTHON_DIR%\get-pip.py'}"
    "%PYTHON_DIR%\python.exe" "%PYTHON_DIR%\get-pip.py" --no-warn-script-location
    if errorlevel 1 (
        call :error "Failed to install pip"
        exit /b 1
    )

    "%PYTHON_DIR%\python.exe" -m pip install scons --no-warn-script-location
    if errorlevel 1 (
        call :error "Failed to install scons"
        exit /b 1
    )

    call :success "Python and scons installed"
    goto :eof

:: Build nim from source
:build_nim
    call :info "Building Nim compiler from source..."

    :: Note: We don't clean previous builds automatically to preserve DLLs and certs
    :: If a clean build is needed, manually delete bin/, csources/, and dist/ directories

    :: Build nim using build_all.bat (must be run from nim directory)
    :: We use cmd /c to create a subshell with proper working directory
    cmd /c "cd /d "%NIM_DIR%" && build_all.bat"
    if errorlevel 1 (
        call :error "Failed to build Nim"
        exit /b 1
    )

    :: Download and install Windows DLLs and certificates from nim-lang.org
    call :info "Downloading Windows DLLs and certificates..."
    set "DLLS_URL=https://nim-lang.org/download/dlls.zip"
    set "DLLS_ZIP=%BUILD_ENV_DIR%\dlls.zip"
    call :download_file "%DLLS_URL%" "%DLLS_ZIP%"
    call :info "Extracting DLLs to Nim bin directory..."
    powershell -Command "& {Expand-Archive -Path '%DLLS_ZIP%' -DestinationPath '%NIM_DIR%\bin' -Force}"
    if errorlevel 1 (
        call :error "Failed to extract DLLs"
        exit /b 1
    )
    call :success "Windows DLLs and certificates installed"

    :: Record the built SHA
    if not exist "%BUILD_STATE_DIR%" mkdir "%BUILD_STATE_DIR%"
    call :get_nim_sha
    echo !NIM_SHA!> "%NIM_STATE_FILE%"

    call :success "Nim compiler built successfully"
    goto :eof

:: Main build logic
:main
    set "BUILD_TYPE=%~1"
    if "%BUILD_TYPE%"=="" set "BUILD_TYPE=dev"

    if "%BUILD_TYPE%"=="dev" (
        set "NIMBLE_TASK=build_all"
    ) else if "%BUILD_TYPE%"=="dist" (
        set "NIMBLE_TASK=dist_all"
    ) else (
        call :error "Unknown build type: %BUILD_TYPE%. Usage: %0 [dev|dist]"
    )

    call :info "Starting %BUILD_TYPE% build..."

    :: Verify required paths are in PATH
    call "%PROJECT_ROOT%tools\verify_paths.bat"
    if errorlevel 1 exit /b 1

    :: Setup build environment
    call :setup_mingw
    if errorlevel 1 exit /b 1

    call :setup_python
    if errorlevel 1 exit /b 1

    :: Check and initialize nim submodule
    call :check_nim_submodule
    if errorlevel 1 exit /b 1

    :: Build nim if needed
    call :needs_nim_build
    if "!NEEDS_BUILD!"=="1" (
        call :build_nim
        if errorlevel 1 exit /b 1
    ) else (
        call :get_nim_sha
        call :success "Nim compiler already built (!NIM_SHA:~0,7!)"
    )

    :: Install debug version of nimble with checksum logging
    call :info "Installing debug version of nimble..."
    nimble install -y https://github.com/dsrw/nimble@#f81d5f2949c746ce33cb2ff408f30bf608e421aa
    if errorlevel 1 (
        call :error "Failed to install debug nimble"
        exit /b 1
    )

    :: Use the debug nimble from nimbledeps
    set "DEBUG_NIMBLE=%PROJECT_ROOT%nimbledeps\bin\nimble"

    :: Setup nimble dependencies with debug logging
    call :info "Setting up nimble dependencies (with debug logging)..."
    "%DEBUG_NIMBLE%" setup -y --verbose > "%PROJECT_ROOT%nimble_setup_debug.log" 2>&1
    if errorlevel 1 (
        call :error "Nimble setup failed - see nimble_setup_debug.log"
        type "%PROJECT_ROOT%nimble_setup_debug.log"
        exit /b 1
    )

    :: Also display the log
    type "%PROJECT_ROOT%nimble_setup_debug.log"

    :: Run nimble task
    call :info "Running nimble !NIMBLE_TASK!..."
    "%DEBUG_NIMBLE%" !NIMBLE_TASK! -y
    if errorlevel 1 (
        call :error "Nimble task failed"
        exit /b 1
    )

    call :success "Build completed successfully!"

endlocal
