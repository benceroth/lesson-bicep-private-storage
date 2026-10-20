<#
.SYNOPSIS
  Offline verification checklist: compiles a Bicep template and checks the compiled ARM for
  the controls that make the Harbor Ledger storage path private.

.PARAMETER Template  Path to a .bicep file (default: main.bicep).

.NOTES
  Needs only the Azure CLI with Bicep. No login. Exit 0 = every control present, 1 = at least one missing.
  It proves what the template declares, not what Azure does at runtime.
#>
[CmdletBinding()]
param(
  [string] $Template = 'main.bicep',
  [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$buildDir = Join-Path $RepoRoot '.build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
. (Join-Path $PSScriptRoot 'controls.ps1')

$result = Test-Template ($Template -replace '\\', '/')
$missing = 0
Write-Output "Checklist for $($Template -replace '\\', '/')"
foreach ($c in $controlText.Keys) {
  $state = if ($result[$c]) { 'PASS' } else { $missing++; 'FAIL' }
  Write-Output ('{0}  {1,-22} {2}' -f $state, $c, $controlText[$c])
}
if ($missing) { Write-Output "RESULT: $missing control(s) missing"; exit 1 }
Write-Output 'RESULT: all controls present'