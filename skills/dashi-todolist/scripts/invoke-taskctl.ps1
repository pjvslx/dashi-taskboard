[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $TaskctlArgs
)

$skillRoot = Split-Path -Parent $PSScriptRoot
$repositoryPathFile = Join-Path $skillRoot '.taskboard-repo-path'
$repositoryCandidates = [System.Collections.Generic.List[string]]::new()

if (Test-Path -LiteralPath $repositoryPathFile -PathType Leaf) {
    $configuredRepository = (Get-Content -LiteralPath $repositoryPathFile -Raw).Trim()
    if ($configuredRepository) {
        $repositoryCandidates.Add((Join-Path $configuredRepository 'cli\taskctl.mjs'))
    }
}

$sourceRepository = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$repositoryCandidates.Add((Join-Path $sourceRepository 'cli\taskctl.mjs'))

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($null -ne $nodeCommand) {
    foreach ($candidate in $repositoryCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            & $nodeCommand.Source $candidate @TaskctlArgs
            exit $LASTEXITCODE
        }
    }
}

$installedCommand = Get-Command taskctl -ErrorAction SilentlyContinue
if ($null -ne $installedCommand) {
    & $installedCommand.Source @TaskctlArgs
    exit $LASTEXITCODE
}

Write-Error 'taskctl was not found. Re-run scripts\install-codex-skills.ps1 from the dashi-taskboard clone, or install taskctl on PATH.'
exit 127
