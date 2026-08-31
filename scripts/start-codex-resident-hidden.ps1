param(
  [Parameter(Mandatory = $true)][string]$NodePath,
  [Parameter(Mandatory = $true)][string]$RunnerPath,
  [Parameter(Mandatory = $true)][ValidateRange(1, 65535)][int]$PreferredPort,
  [Parameter(Mandatory = $true)][string]$ProjectRoot,
  [Parameter(Mandatory = $true)][string]$LogPath
)

$arguments = @(
  ('"{0}"' -f $RunnerPath),
  '--preferred-port', [string]$PreferredPort,
  '--project-root', ('"{0}"' -f $ProjectRoot),
  '--node-path', ('"{0}"' -f $NodePath),
  '--log-path', ('"{0}"' -f $LogPath)
) -join ' '

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $NodePath
$startInfo.Arguments = $arguments
$startInfo.WorkingDirectory = $ProjectRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

while ($true) {
  $process = [System.Diagnostics.Process]::Start($startInfo)
  $process.WaitForExit()
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ParentProcessId -eq $process.Id } |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
  try {
    Add-Content -LiteralPath $LogPath -Value (('[{0:o}] hidden-launcher runner-exit pid={1} code={2}; restarting in 2s' -f (Get-Date), $process.Id, $process.ExitCode)) -Encoding UTF8
  } catch {}
  Start-Sleep -Seconds 2
}
