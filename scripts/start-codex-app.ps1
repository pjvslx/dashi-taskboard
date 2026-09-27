[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$AppUserModelId,

  [Parameter(Mandatory = $true)]
  [AllowEmptyString()]
  [string]$LaunchArguments,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$LogPath
)

$ErrorActionPreference = 'Stop'

if (-not ('DashiTaskboard.PackagedApplicationLauncher' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace DashiTaskboard
{
    [Flags]
    internal enum ActivateOptions
    {
        None = 0
    }

    [ComImport]
    [Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IApplicationActivationManager
    {
        [PreserveSig]
        int ActivateApplication(
            [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string arguments,
            ActivateOptions options,
            out uint processId);
    }

    [ComImport]
    [Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
    internal class ApplicationActivationManager
    {
    }

    public static class PackagedApplicationLauncher
    {
        public static uint Activate(string appUserModelId, string arguments)
        {
            var manager = (IApplicationActivationManager)new ApplicationActivationManager();
            try
            {
                uint processId;
                var result = manager.ActivateApplication(
                    appUserModelId,
                    arguments,
                    ActivateOptions.None,
                    out processId);
                if (result < 0)
                {
                    Marshal.ThrowExceptionForHR(result);
                }
                return processId;
            }
            finally
            {
                Marshal.FinalReleaseComObject(manager);
            }
        }
    }
}
'@
}

try {
  Add-Content -LiteralPath $LogPath -Value "activating: $AppUserModelId $LaunchArguments"
  $launchedProcessId = [DashiTaskboard.PackagedApplicationLauncher]::Activate(
    $AppUserModelId,
    $LaunchArguments
  )
  Add-Content -LiteralPath $LogPath -Value "activated Codex process PID=$launchedProcessId"
  Write-Output $launchedProcessId
} catch {
  Add-Content -LiteralPath $LogPath -Value "failed to activate Codex app: $($_.Exception.Message)"
  Write-Error $_
  exit 1
}
