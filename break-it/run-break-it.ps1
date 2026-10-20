<#
.SYNOPSIS
  Runs the checklist against every broken case in break-it/ and confirms each one is caught
  with exactly the documented findings. Offline; needs only the Azure CLI with Bicep.

  Exit 0 = every case is caught as documented (and main.bicep is clean). 1 = a case slipped through.
#>
[CmdletBinding()]
param(
  [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$buildDir = Join-Path $RepoRoot '.build'
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
. (Join-Path $RepoRoot 'verify/controls.ps1')

$cases = [ordered]@{
  'main.bicep'                                    = @()
  'break-it/01-private-endpoint-public-access-on.bicep' = @('PublicAccessDisabled')
  'break-it/02-missing-dns-zone-link.bicep'       = @('DnsVnetLink')
  'break-it/03-nsg-only.bicep'                    = @('PublicAccessDisabled', 'PrivateEndpointBlob', 'DnsZone', 'DnsVnetLink', 'DnsZoneGroup')
  'break-it/04-wildcard-nsg-source.bicep'         = @('NsgAllowIntegration443')
  'break-it/05-empty-nsg.bicep'                   = @('NsgAllowIntegration443', 'NsgDenyOtherVnet')
}

$bad = 0
foreach ($path in $cases.Keys) {
  $actual = Test-Template $path
  $found = @($controlNames | Where-Object { -not $actual[$_] })
  $expected = @($cases[$path])
  $same = ($found -join ',') -eq ($expected -join ',')
  if (-not $same) { $bad++ }
  $label = if ($path -eq 'main.bicep') { if ($same) { 'CLEAN ' } else { 'DIRTY ' } } else { if ($same) { 'CAUGHT' } else { 'MISSED' } }
  Write-Output ('{0}  {1}' -f $label, $path)
  if ($found.Count) { Write-Output ('        findings: {0}' -f ($found -join ', ')) }
  if (-not $same) { Write-Output ('        expected: {0}' -f ($expected -join ', ')) }
}
if ($bad) { Write-Output "RESULT: $bad case(s) not as documented"; exit 1 }
Write-Output 'RESULT: every broken case is caught; main.bicep is clean'