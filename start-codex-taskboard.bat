@echo off
setlocal EnableDelayedExpansion

set "BASE_PORT=9231"
set "PORT=%BASE_PORT%"
set "CDP_HOST=localhost"
set "TASKBOARD_HOST=127.0.0.1"
set "REPO_DIR=%~dp0"
set "DATA_DIR=%REPO_DIR%.data"
set "LOG_DIR=%DATA_DIR%\logs"
set "LOG_FILE=%LOG_DIR%\start-codex-taskboard.log"
set "CODEX_CLI_CONFIG=%DATA_DIR%\codex-cli-path.txt"
set "CODEX_CLI_ROOT=C:\Users\luy\AppData\Local\OpenAI\Codex\bin"
cd /d "%REPO_DIR%" || exit /b 1
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

echo.
echo Codex Taskboard launcher
echo ------------------------
echo This will start Codex with remote debugging on port %PORT%,
echo then inject the Taskboard panel into the Codex sidebar.
echo.
echo [%date% %time%] launcher started > "%LOG_FILE%"

where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: node was not found on PATH. Please install Node.js 22.5 or newer.
  pause
  exit /b 1
)

set "CODEX_APP_EXE="
set "CODEX_CLI_EXE="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$pkg = Get-AppxPackage OpenAI.Codex; if (-not $pkg) { exit 1 }; Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'"`) do set "CODEX_APP_EXE=%%A"
if "%CODEX_APP_EXE%"=="" (
  echo ERROR: Could not find the installed Codex app package.
  echo See "%LOG_FILE%" for details.
  pause
  exit /b 1
)

for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$cliRoot = '%CODEX_CLI_ROOT%'; if (Test-Path -LiteralPath $cliRoot -PathType Container) { Get-ChildItem -LiteralPath $cliRoot -Recurse -File -Filter codex.exe -ErrorAction SilentlyContinue ^| Sort-Object LastWriteTime -Descending ^| Select-Object -First 1 -ExpandProperty FullName }"`) do set "CODEX_CLI_EXE=%%A"
if not exist "%CODEX_CLI_EXE%" goto ask_codex_cli
goto codex_cli_ready

:ask_codex_cli
echo Could not automatically find a runnable Codex CLI under "%CODEX_CLI_ROOT%".
echo Enter the full path to codex.exe. This launcher will remember it for next time.
echo Press Enter to continue without local AI catalog support.
set /P "CODEX_CLI_EXE=codex.exe path: "
if "%CODEX_CLI_EXE%"=="" (
  echo Continuing without CODEX_EXECUTABLE. Local AI model/skill catalog may be unavailable.
  echo codex executable skipped by user>> "%LOG_FILE%"
  goto after_codex_cli
)
if not exist "%CODEX_CLI_EXE%" (
  echo ERROR: "%CODEX_CLI_EXE%" does not exist.
  goto ask_codex_cli
)
if exist "%CODEX_CLI_EXE%\codex.exe" set "CODEX_CLI_EXE=%CODEX_CLI_EXE%\codex.exe"

:codex_cli_ready
if exist "%CODEX_CLI_EXE%\codex.exe" set "CODEX_CLI_EXE=%CODEX_CLI_EXE%\codex.exe"
set "CODEX_EXECUTABLE=%CODEX_CLI_EXE%"
> "%CODEX_CLI_CONFIG%" echo(%CODEX_EXECUTABLE%
echo Codex CLI: %CODEX_EXECUTABLE%
echo codex executable=%CODEX_EXECUTABLE%>> "%LOG_FILE%"

:after_codex_cli

curl.exe -fsS --max-time 2 "http://%CDP_HOST%:%PORT%/json/version" >nul 2>nul
if not errorlevel 1 goto inject

tasklist /FI "IMAGENAME eq ChatGPT.exe" 2>nul | find /I "ChatGPT.exe" >nul
if not errorlevel 1 (
  echo Existing Codex/ChatGPT windows are running.
  echo This launcher must restart the Codex shell so the debug port is not ignored.
  choice /C YN /M "Restart Codex now"
  if errorlevel 2 (
    echo Please close Codex manually, then run this script again.
    pause
    exit /b 1
  )
)

echo Closing Codex shell processes...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$names = @('ChatGPT.exe','codex.exe'); $isCodex = { param($p) ($names -contains $p.Name) -and (($p.ExecutablePath -like '*OpenAI.Codex*') -or ($p.CommandLine -like '*OpenAI.Codex*')) }; Get-CimInstance Win32_Process | Where-Object { & $isCodex $_ } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; Add-Content -Path '%LOG_FILE%' -Value ('stopped Codex process PID=' + $_.ProcessId + ' NAME=' + $_.Name) } catch { Add-Content -Path '%LOG_FILE%' -Value ('failed to stop PID=' + $_.ProcessId + ': ' + $_.Exception.Message) } }; $deadline = (Get-Date).AddSeconds(20); do { Start-Sleep -Milliseconds 250; $remaining = @(Get-CimInstance Win32_Process | Where-Object { & $isCodex $_ }) } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline); $listeners = @(Get-NetTCPConnection -LocalPort %BASE_PORT% -State Listen -ErrorAction SilentlyContinue); if ($listeners.Count -gt 0) { Add-Content -Path '%LOG_FILE%' -Value ('base debug port still has listeners=' + (($listeners | ForEach-Object { $_.OwningProcess }) -join ',')) }; if ($remaining.Count -gt 0) { Add-Content -Path '%LOG_FILE%' -Value ('remaining Codex processes=' + $remaining.Count); exit 2 } else { exit 0 }"
if errorlevel 2 (
  echo ERROR: Could not close all Codex shell processes.
  echo See "%LOG_FILE%" for details.
  pause
  exit /b 1
)
timeout /T 2 /NOBREAK >nul

set "SELECTED_PORT="
for /f %%P in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "for ($port = %BASE_PORT%; $port -le %BASE_PORT% + 20; $port++) { if (-not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) { Write-Output $port; exit 0 } }; exit 1"') do set "SELECTED_PORT=%%P"
if "%SELECTED_PORT%"=="" (
  echo ERROR: Could not find a free Codex debug port.
  echo See "%LOG_FILE%" for details.
  pause
  exit /b 1
)
set "PORT=%SELECTED_PORT%"
echo Using Codex debug port %PORT%.
echo selected debug port=%PORT%>> "%LOG_FILE%"

echo Starting Codex with debug port %PORT%...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$exe = '%CODEX_APP_EXE%'; $args = @('--remote-debugging-port=%PORT%', '--remote-allow-origins=http://%CDP_HOST%:%PORT%'); Add-Content -Path '%LOG_FILE%' -Value ('starting: ' + $exe + ' ' + ($args -join ' ')); Start-Process -FilePath $exe -ArgumentList $args; exit 0"
if errorlevel 1 (
  echo ERROR: Could not start Codex from the installed Windows app package.
  echo See "%LOG_FILE%" for details.
  pause
  exit /b 1
)

echo Waiting for Codex debug port...
for /L %%I in (1,1,45) do (
  curl.exe -fsS --max-time 2 "http://%CDP_HOST%:%PORT%/json/version" >nul 2>nul
  if not errorlevel 1 goto inject
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$main = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'ChatGPT.exe' -and $_.CommandLine -notmatch '--type=' } | Select-Object -First 1; if ($main) { Add-Content -Path '%LOG_FILE%' -Value ('main process: ' + $main.CommandLine) }"
  timeout /T 1 /NOBREAK >nul
)

echo ERROR: Codex did not open debug port %PORT%.
echo If a "ChatGPT failed to start" window appeared, close it and run this script again.
echo Current process details were written to "%LOG_FILE%".
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Content -Path '%LOG_FILE%' -Value '--- ChatGPT/Codex processes after failed launch ---'; Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'ChatGPT|codex' } | ForEach-Object { Add-Content -Path '%LOG_FILE%' -Value ('PID=' + $_.ProcessId + ' NAME=' + $_.Name); Add-Content -Path '%LOG_FILE%' -Value $_.CommandLine; Add-Content -Path '%LOG_FILE%' -Value '' }"
pause
exit /b 1

:inject
echo Waiting for Codex main window...
for /L %%I in (1,1,45) do (
  node -e "fetch('http://%CDP_HOST%:%PORT%/json/list',{signal:AbortSignal.timeout(2000)}).then(r=>r.json()).then(targets=>process.exit(targets.some(t=>t.type==='page'&&t.url==='app://-/index.html')?0:1)).catch(()=>process.exit(1))"
  if not errorlevel 1 goto runinject
  timeout /T 1 /NOBREAK >nul
)

echo ERROR: Codex debug port is open, but the main window target did not appear.
echo See "%LOG_FILE%" for details.
pause
exit /b 1

:runinject
echo Restarting local Taskboard service if it is already running...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$pids = @(Get-NetTCPConnection -LocalPort 47823 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique); foreach ($processId in $pids) { if ($processId -and $processId -ne $PID) { try { Stop-Process -Id $processId -Force -ErrorAction Stop; Add-Content -Path '%LOG_FILE%' -Value ('stopped Taskboard service PID=' + $processId) } catch { Add-Content -Path '%LOG_FILE%' -Value ('failed to stop Taskboard PID=' + $processId + ': ' + $_.Exception.Message) } } }"
timeout /T 1 /NOBREAK >nul

echo Starting independently hosted Taskboard injector...
set "NODE_EXE="
for /f "delims=" %%A in ('where node') do if not defined NODE_EXE set "NODE_EXE=%%A"
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_DIR%scripts\install-codex-resident-task.ps1" -Port %PORT% -NodePath "%NODE_EXE%" -ProjectRoot "%REPO_DIR%." -LogPath "%LOG_FILE%"
set "INJECT_EXIT=%ERRORLEVEL%"

echo.
if not "%INJECT_EXIT%"=="0" (
  echo Taskboard resident task failed with code %INJECT_EXIT%.
  echo See "%LOG_FILE%" for the registration error.
  pause
  exit /b %INJECT_EXIT%
)
echo Taskboard injector is hosted independently by Windows.
echo It will remain running after a Codex task completes.
pause
