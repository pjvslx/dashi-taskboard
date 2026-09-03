[CmdletBinding()]
param(
    [string] $DestinationRoot
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceSkillsRoot = Join-Path $repositoryRoot 'skills'
$skillNames = @('manage-taskboard', 'dashi-todolist')

if (-not $DestinationRoot) {
    if ($env:CODEX_HOME) {
        $DestinationRoot = Join-Path $env:CODEX_HOME 'skills'
    }
    else {
        $DestinationRoot = Join-Path $HOME '.agents\skills'
    }
}

$DestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null

foreach ($skillName in $skillNames) {
    $source = Join-Path $sourceSkillsRoot $skillName
    $destination = Join-Path $DestinationRoot $skillName

    if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) {
        throw "Skill source is missing: $source"
    }

    $sameLocation = [System.IO.Path]::GetFullPath($source).Equals(
        [System.IO.Path]::GetFullPath($destination),
        [System.StringComparison]::OrdinalIgnoreCase
    )

    if ((Test-Path -LiteralPath $destination) -and -not $sameLocation) {
        $destinationItem = Get-Item -LiteralPath $destination
        if ($destinationItem.LinkType -and $destinationItem.Target) {
            $linkTarget = [string]($destinationItem.Target | Select-Object -First 1)
            if (-not [System.IO.Path]::IsPathRooted($linkTarget)) {
                $linkTarget = Join-Path $destinationItem.Parent.FullName $linkTarget
            }
            $sameLocation = [System.IO.Path]::GetFullPath($source).Equals(
                [System.IO.Path]::GetFullPath($linkTarget),
                [System.StringComparison]::OrdinalIgnoreCase
            )
        }
    }

    if ($sameLocation) {
        Write-Host "Already linked $skillName -> $source"
    }
    else {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
        Write-Host "Installed $skillName -> $destination"
    }
}

$dashiSkillRoot = Join-Path $DestinationRoot 'dashi-todolist'
$repositoryPathFile = Join-Path $dashiSkillRoot '.taskboard-repo-path'
[System.IO.File]::WriteAllText($repositoryPathFile, $repositoryRoot, [System.Text.UTF8Encoding]::new($false))

Write-Host "Recorded Taskboard clone -> $repositoryRoot"
Write-Host 'Skill installation complete. Start a new Codex task if the $ commands are not refreshed immediately.'
