<#
.SYNOPSIS
  LIVE check (needs `az login` and a deployed resource group): asserts the deployed
  configuration of the Harbor Ledger private storage path.

.PARAMETER ResourceGroup  Resource group that holds the deployment.
.PARAMETER Variant        main (default), no-public-access-disable, no-dns-zone, empty-nsg.
                          For a variant, the documented broken checks are EXPECTED to fail;
                          the script exits 0 only if the outcome matches that expectation.

.NOTES
  Configuration only. It does not prove DNS answers or reachability: use from-inside.sh
  and from-outside.ps1 for that. Reads resource properties; never reads account keys.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ResourceGroup,
  [ValidateSet('main', 'no-public-access-disable', 'no-dns-zone', 'empty-nsg')]
  [string] $Variant = 'main'
)

$vnet = 'vnet-harbor-prod'; $pe = 'pe-harbor-blob-prod'; $nsg = 'nsg-harbor-app-prod'
$expectedFail = @{
  'main'                     = @()
  'no-public-access-disable' = @('C1')
  'no-dns-zone'              = @('C4', 'C5', 'C6', 'C7')
  'empty-nsg'                = @('C8', 'C9')
}[$Variant]

function Invoke-Az {
  $out = & az @args --only-show-errors -o tsv 2>$null
  if ($LASTEXITCODE -ne 0) { return $null }
  ($out | Out-String).Trim()
}

$sa = Invoke-Az storage account list -g $ResourceGroup --query "[?starts_with(name,'stharbor')].name | [0]"
if (-not $sa) { Write-Error "No stharbor* storage account in $ResourceGroup (or not logged in)."; exit 2 }
$zone = "privatelink.blob.core.windows.net"
$peNicId =  Invoke-Az network private-endpoint show -g $ResourceGroup -n $pe --query "networkInterfaces[0].id"
$peIp = if ($peNicId) { Invoke-Az network nic show --ids $peNicId --query "ipConfigurations[0].privateIPAddress" } else { $null }

$results = [ordered]@{}
function Check([string] $id, [string] $name, [bool] $ok) { $script:results[$id] = [pscustomobject]@{ Id = $id; Check = $name; Pass = $ok } }

Check 'C1' 'storage publicNetworkAccess = Disabled' ((Invoke-Az storage account show -g $ResourceGroup -n $sa --query publicNetworkAccess) -eq 'Disabled')
Check 'C2' 'storage allowBlobPublicAccess = false' ((Invoke-Az storage account show -g $ResourceGroup -n $sa --query allowBlobPublicAccess) -eq 'false')
Check 'C3' 'private endpoint to blob exists and is Approved' ((Invoke-Az network private-endpoint show -g $ResourceGroup -n $pe --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status") -eq 'Approved')
Check 'C4' "private DNS zone $zone exists" ((Invoke-Az network private-dns zone show -g $ResourceGroup -n $zone --query name) -eq $zone)
$linkVnet = Invoke-Az network private-dns link vnet list -g $ResourceGroup -z $zone --query "[0].virtualNetwork.id"
Check 'C5' "zone linked to $vnet" ([bool]$linkVnet -and $linkVnet -like "*$vnet")
Check 'C6' 'private endpoint has a DNS zone group' ([bool](Invoke-Az network private-endpoint dns-zone-group list -g $ResourceGroup --endpoint-name $pe --query "[0].name"))
$aRecord = Invoke-Az network private-dns record-set a list -g $ResourceGroup -z $zone --query "[?name=='$sa'].aRecords[0].ipv4Address | [0]"
Check 'C7' 'zone has A record for the account = endpoint private IP' ([bool]$aRecord -and $aRecord -eq $peIp -and $aRecord -like '10.40.3.*')
Check 'C8' 'NSG allow 100: 10.40.1.0/24 -> 10.40.2.0/24 TCP 443' (
  (Invoke-Az network nsg rule list -g $ResourceGroup --nsg-name $nsg --query "[?priority==``100`` && access=='Allow' && direction=='Inbound' && destinationPortRange=='443' && sourceAddressPrefix=='10.40.1.0/24' && destinationAddressPrefix=='10.40.2.0/24'].name | [0]"))
Check 'C9' 'NSG deny 4000: VirtualNetwork -> 10.40.2.0/24' (
  (Invoke-Az network nsg rule list -g $ResourceGroup --nsg-name $nsg --query "[?priority==``4000`` && access=='Deny' && direction=='Inbound' && sourceAddressPrefix=='VirtualNetwork' && destinationAddressPrefix=='10.40.2.0/24'].name | [0]"))
Check 'C10' 'NSG attached to snet-app' ((Invoke-Az network vnet subnet show -g $ResourceGroup --vnet-name $vnet -n snet-app --query "networkSecurityGroup.id") -like "*$nsg")

$sharedKey = Invoke-Az storage account show -g $ResourceGroup -n $sa --query allowSharedKeyAccess
Write-Host "INFO allowSharedKeyAccess = $sharedKey (not set by the post's template; see docs/limits.md)"

$mismatch = $false
foreach ($r in $results.Values) {
  $shouldFail = $expectedFail -contains $r.Id
  $asExpected = ($r.Pass -ne $shouldFail)
  if (-not $asExpected) { $mismatch = $true }
  $state = if ($r.Pass) { 'PASS' } else { 'FAIL' }
  $note = if ($shouldFail) { ' (expected to fail for this variant)' } else { '' }
  $flag = if ($asExpected) { '' } else { '  <-- UNEXPECTED' }
  Write-Host ("{0,-4} {1,-4} {2}{3}{4}" -f $r.Id, $state, $r.Check, $note, $flag)
}
if ($mismatch) { Write-Host "Result for '$Variant': UNEXPECTED" -ForegroundColor Red; exit 1 }
Write-Host "Result for '$Variant': matches expectation" -ForegroundColor Green
