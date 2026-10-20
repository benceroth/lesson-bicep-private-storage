<#
.SYNOPSIS
  LIVE check, run from OUTSIDE the VNet (your laptop): the storage account's public path
  must be closed.

.DESCRIPTION
  Sends one anonymous request to the account's Blob endpoint. A closed public path is
  expected to be refused at the network layer with HTTP 403 and error code
  "AuthorizationFailure". Any other response (or a 200) means the request reached the
  storage authorization layer, i.e. the public endpoint is reachable. No keys or tokens used.

  The exact status/code for each variant is a hypothesis until confirmed live; see
  verify/expected-results.md.

.PARAMETER StorageAccountName  Name of the deployed account (output storageBlobHostName).
.PARAMETER ResourceGroup       Alternative: discover the account name from the resource group.
#>
[CmdletBinding()]
param(
  [string] $StorageAccountName,
  [string] $ResourceGroup
)

if (-not $StorageAccountName) {
  if (-not $ResourceGroup) { Write-Error 'Pass -StorageAccountName or -ResourceGroup.'; exit 2 }
  $StorageAccountName = (az storage account list -g $ResourceGroup --query "[?starts_with(name,'stharbor')].name | [0]" -o tsv --only-show-errors).Trim()
}
$hostName = "$StorageAccountName.blob.core.windows.net"
Write-Host "Target: https://$hostName/?comp=list (anonymous)"

try { $ips = [System.Net.Dns]::GetHostAddresses($hostName) | ForEach-Object { $_.ToString() } } catch { $ips = @() }
Write-Host "DNS from here: $($ips -join ', ')  (a public IP is normal outside the VNet)"
if ($ips.Count -eq 0) { Write-Host "ERROR: $hostName does not resolve. Wrong account name? Not a valid test result." -ForegroundColor Red; exit 2 }

$status = $null; $body = ''
try {
  $resp = Invoke-WebRequest -Uri "https://$hostName/?comp=list" -SkipHttpErrorCheck -TimeoutSec 20
  $status = [int]$resp.StatusCode; $body = $resp.Content
} catch {
  Write-Host "Connection failed: $($_.Exception.Message)"
}

if ($null -eq $status) { Write-Host 'PASS: no HTTP response (connection refused/timed out).' -ForegroundColor Green; exit 0 }
$code = if ($body -match '<Code>([^<]+)</Code>') { $Matches[1] } else { '(none)' }
Write-Host "HTTP $status, error code: $code"
if ($status -eq 403 -and $code -eq 'AuthorizationFailure') {
  Write-Host 'PASS: refused at the network layer (public path closed).' -ForegroundColor Green; exit 0
}
Write-Host 'FAIL: the request reached storage authorization, so the public endpoint is reachable.' -ForegroundColor Red
exit 1
