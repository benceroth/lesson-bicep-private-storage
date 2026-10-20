<#
.SYNOPSIS
  Regenerates the committed evidence in evidence/ from the templates (offline, deterministic).
    evidence/checklist-main.txt       checklist output for main.bicep
    evidence/exposed-vs-private.md    control-by-control table: private baseline vs each broken case
    evidence/break-it-results.txt     runner output for break-it/
#>
[CmdletBinding()]
param(
  [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$buildDir = Join-Path $RepoRoot '.build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
. (Join-Path $RepoRoot 'verify/controls.ps1')
$out = Join-Path $RepoRoot 'evidence'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Save([string] $name, $lines) {
  [IO.File]::WriteAllText((Join-Path $out $name), (($lines -join "`n") + "`n"))
}

Save 'checklist-main.txt' (& (Join-Path $RepoRoot 'verify/checklist.ps1') -Template 'main.bicep')
Save 'break-it-results.txt' (& (Join-Path $RepoRoot 'break-it/run-break-it.ps1'))

$columns = [ordered]@{
  'main.bicep'                                          = 'Private baseline'
  'break-it/03-nsg-only.bicep'                          = 'NSG only'
  'break-it/01-private-endpoint-public-access-on.bicep' = 'Endpoint, public on'
  'break-it/02-missing-dns-zone-link.bicep'             = 'No DNS link'
  'break-it/04-wildcard-nsg-source.bicep'               = 'Wildcard source'
  'break-it/05-empty-nsg.bicep'                         = 'Empty NSG'
}
$results = @{}
foreach ($p in $columns.Keys) { $results[$p] = Test-Template $p }

$md = @(
  ('| Control | ' + ($columns.Values -join ' | ') + ' |'),
  ('|---|' + ((1..$columns.Count | ForEach-Object { ':-:' }) -join '|') + '|')
)
foreach ($c in $controlNames) {
  $cells = foreach ($p in $columns.Keys) { if ($results[$p][$c]) { 'yes' } else { '**NO**' } }
  $md += "| $($controlText[$c]) | $($cells -join ' | ') |"
}
Save 'exposed-vs-private.md' $md
Write-Output "Wrote $out"