param(
  [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$Port,
  [Parameter(Mandatory = $true)][string]$NodePath,
  [Parameter(Mandatory = $true)][string]$ProjectRoot,
  [Parameter(Mandatory = $true)][string]$LogPath,
  [switch]$ForceRestart
)

$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $LogPath -PathType Container) {
  $LogPath = Join-Path $LogPath 'start-codex-taskboard.log'
}

function Write-LauncherLog {
  param([string]$Message)
  $directory = Split-Path -Parent $LogPath
  if (-not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  Add-Content -LiteralPath $LogPath -Value (('[{0:o}] scheduled-task {1}' -f (Get-Date), $Message)) -Encoding UTF8
}

try {
  $resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
  $resolvedNodePath = (Resolve-Path -LiteralPath $NodePath).Path
  $runnerPath = Join-Path $resolvedProjectRoot 'scripts\codex-resident-task-runner.mjs'
  $hiddenLauncherPath = Join-Path $resolvedProjectRoot 'scripts\start-codex-resident-hidden.ps1'
  $injectorPath = Join-Path $resolvedProjectRoot 'scripts\codex-injector.mjs'
  if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Resident runner not found: $runnerPath"
  }
  if (-not (Test-Path -LiteralPath $hiddenLauncherPath -PathType Leaf)) {
    throw "Hidden resident launcher not found: $hiddenLauncherPath"
  }

  $normalizedRoot = $resolvedProjectRoot.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedRoot))
  } finally {
    $sha.Dispose()
  }
  $hash = ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 12)
  $taskName = "DashiTaskboard-$hash"

  $legacyTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskName -like "$taskName-*"
  })
  foreach ($existing in $legacyTasks) {
    Stop-ScheduledTask -TaskName $existing.TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $existing.TaskName -Confirm:$false
    Write-LauncherLog "removed legacy task name=$($existing.TaskName)"
  }

  $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existingTask -and $existingTask.State -eq 'Running' -and -not $ForceRestart) {
    Write-LauncherLog "reused running task name=$taskName"
    Write-Output $taskName
    exit 0
  }
  if ($existingTask) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-LauncherLog "removed previous task name=$taskName"
  }

  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $commandLine = $_.CommandLine
      $commandLine -and (
        (
          $commandLine.IndexOf($injectorPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
          $commandLine -match '(?:^|\s)--watch(?:\s|$)'
        ) -or $commandLine.IndexOf($runnerPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
      )
    } |
    ForEach-Object {
      try {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
        Write-LauncherLog "stopped stale injector pid=$($_.ProcessId)"
      } catch {
        Write-LauncherLog "failed to stop stale injector pid=$($_.ProcessId) error=$($_.Exception.Message)"
      }
    }

  $powershellPath = Join-Path $PSHOME 'powershell.exe'
  $arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle', 'Hidden',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $hiddenLauncherPath),
    '-NodePath', ('"{0}"' -f $resolvedNodePath),
    '-RunnerPath', ('"{0}"' -f $runnerPath),
    '-PreferredPort', [string]$Port,
    '-ProjectRoot', ('"{0}"' -f $resolvedProjectRoot),
    '-LogPath', ('"{0}"' -f $LogPath)
  ) -join ' '

  $action = New-ScheduledTaskAction -Execute $powershellPath -Argument $arguments -WorkingDirectory $resolvedProjectRoot
  $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
  $recoveryTrigger = New-ScheduledTaskTrigger -Once `
    -At ((Get-Date).AddMinutes(1)) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
  $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logonTrigger, $recoveryTrigger) -Principal $principal -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
  Write-LauncherLog "registered and started name=$taskName port=$Port"
  Write-Output $taskName
  exit 0
} catch {
  Write-LauncherLog "failure error=$($_.Exception.Message)"
  Write-Error $_
  exit 1
}
