param(
  [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$Port,
  [Parameter(Mandatory = $true)][string]$NodePath,
  [Parameter(Mandatory = $true)][string]$ProjectRoot,
  [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = 'Stop'

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
  $launcherPath = Join-Path $resolvedProjectRoot 'scripts\codex-resident-task-launcher.vbs'
  $injectorPath = Join-Path $resolvedProjectRoot 'scripts\codex-injector.mjs'
  if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    throw "Resident runner not found: $runnerPath"
  }
  if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw "Resident launcher not found: $launcherPath"
  }
  $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'

  $normalizedRoot = $resolvedProjectRoot.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedRoot))
  } finally {
    $sha.Dispose()
  }
  $hash = ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant().Substring(0, 12)
  $taskName = "DashiTaskboard-$hash-$Port"

  $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existing) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-LauncherLog "removed previous task name=$taskName"
  }

  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.CommandLine.IndexOf($injectorPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
      $_.CommandLine -match '(?:^|\s)--watch(?:\s|$)'
    } |
    ForEach-Object {
      try {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
        Write-LauncherLog "stopped stale injector pid=$($_.ProcessId)"
      } catch {
        Write-LauncherLog "failed to stop stale injector pid=$($_.ProcessId) error=$($_.Exception.Message)"
      }
    }

  $arguments = @(
    '//B', '//NoLogo',
    ('"{0}"' -f $launcherPath),
    ('"{0}"' -f $resolvedNodePath),
    ('"{0}"' -f $runnerPath),
    '--port', [string]$Port,
    '--project-root', ('"{0}"' -f $resolvedProjectRoot),
    '--node-path', ('"{0}"' -f $resolvedNodePath),
    '--log-path', ('"{0}"' -f $LogPath)
  ) -join ' '

  $action = New-ScheduledTaskAction -Execute $wscriptPath -Argument $arguments -WorkingDirectory $resolvedProjectRoot
  $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

  Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
  Start-ScheduledTask -TaskName $taskName
  Write-LauncherLog "registered and started name=$taskName port=$Port"
  Write-Output $taskName
  exit 0
} catch {
  Write-LauncherLog "failure error=$($_.Exception.Message)"
  Write-Error $_
  exit 1
}
