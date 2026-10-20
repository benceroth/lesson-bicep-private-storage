<#
.SYNOPSIS
  Offline static check: compiles main.bicep and each variant to ARM JSON and asserts which
  security controls are present in the compiled template.

.DESCRIPTION
  Needs only the Azure CLI with Bicep (az bicep install). No Azure login, no deployment.
  This proves what the TEMPLATE declares, not what Azure does at runtime. Runtime behaviour
  (DNS answers, HTTP status codes, effective NSG evaluation) is verified live; see
  verify/expected-results.md for which cells are offline-checkable.

  Exit code 0 = every template matches its expected control set. 1 = mismatch or build failure.
#>
[CmdletBinding()]
param(
  [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$buildDir = Join-Path $RepoRoot '.build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
. (Join-Path $PSScriptRoot 'controls.ps1')

$controls = @(
  'PublicAccessDisabled', 'BlobPublicAccessOff', 'PrivateEndpointBlob',
  'DnsZone', 'DnsVnetLink', 'DnsZoneGroup',
  'NsgAllowIntegration443', 'NsgDenyOtherVnet', 'NsgAttachedToApp'
)

$all = @{}; foreach ($c in $controls) { $all[$c] = $true }
function Without([string[]] $missing) {
  $h = $all.Clone(); foreach ($m in $missing) { $h[$m] = $false }; $h
}

# Each variant omits exactly one control (some controls travel together).
$expected = [ordered]@{
  'main.bicep'                                = $all
  'variants/no-public-access-disable.bicep'   = Without @('PublicAccessDisabled')
  'variants/no-dns-zone.bicep'                = Without @('DnsZone', 'DnsVnetLink', 'DnsZoneGroup')
  'variants/empty-nsg.bicep'                  = Without @('NsgAllowIntegration443', 'NsgDenyOtherVnet')
}

$failed = $false
$matrix = foreach ($path in $expected.Keys) {
  $actual = Test-Template $path
  $row = [ordered]@{ Template = $path }
  foreach ($c in $controls) {
    $ok = $actual[$c] -eq $expected[$path][$c]
    if (-not $ok) { $failed = $true }
    $mark = if ($actual[$c]) { 'present' } else { 'ABSENT' }
    $row[$c] = if ($ok) { $mark } else { "$mark (UNEXPECTED)" }
  }
  [pscustomobject]$row
}

$matrix | Format-List
if ($failed) {
  Write-Error 'Static check FAILED: a template does not match its expected control set.'
  exit 1
}
Write-Host 'Static check passed: main.bicep has every control; each variant lacks exactly its documented control(s).' -ForegroundColor Green
