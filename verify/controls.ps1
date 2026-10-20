# Shared by static-check.ps1, checklist.ps1 and break-it/run-break-it.ps1.
# Expects $RepoRoot and $buildDir to be set by the caller.

$controlNames = @(
  'PublicAccessDisabled', 'BlobPublicAccessOff', 'PrivateEndpointBlob',
  'DnsZone', 'DnsVnetLink', 'DnsZoneGroup',
  'NsgAllowIntegration443', 'NsgDenyOtherVnet', 'NsgAttachedToApp'
)

function Get-Resources($arm, [string] $type) {
  $res = $arm.resources
  if ($res -is [System.Array]) { $list = $res } else { $list = $res.PSObject.Properties.Value }
  @($list | Where-Object { $_.type -eq $type })
}

function Test-Template([string] $relPath) {
  $src = Join-Path $RepoRoot $relPath
  $out = Join-Path $buildDir (($relPath -replace '[\\/]', '_') -replace '\.bicep$', '.json')
  az bicep build --file $src --outfile $out 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { throw "az bicep build failed for $relPath" }
  $arm = Get-Content $out -Raw | ConvertFrom-Json

  $storage = Get-Resources $arm 'Microsoft.Storage/storageAccounts'
  $nsgs = Get-Resources $arm 'Microsoft.Network/networkSecurityGroups'
  $rules = @($nsgs | ForEach-Object { $_.properties.securityRules } | Where-Object { $_ })
  $subnets = Get-Resources $arm 'Microsoft.Network/virtualNetworks/subnets'
  $pes = Get-Resources $arm 'Microsoft.Network/privateEndpoints'
  $zones = Get-Resources $arm 'Microsoft.Network/privateDnsZones'
  $links = Get-Resources $arm 'Microsoft.Network/privateDnsZones/virtualNetworkLinks'
  $groups = Get-Resources $arm 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups'

  $allow = $rules | Where-Object {
    $p = $_.properties
    $p.priority -eq 100 -and $p.access -eq 'Allow' -and $p.direction -eq 'Inbound' -and
    $p.protocol -eq 'Tcp' -and $p.destinationPortRange -eq '443' -and
    $p.sourceAddressPrefix -eq '10.40.1.0/24' -and $p.destinationAddressPrefix -eq '10.40.2.0/24'
  }
  $deny = $rules | Where-Object {
    $p = $_.properties
    $p.priority -eq 4000 -and $p.access -eq 'Deny' -and $p.direction -eq 'Inbound' -and
    $p.sourceAddressPrefix -eq 'VirtualNetwork' -and $p.destinationAddressPrefix -eq '10.40.2.0/24'
  }
  $appSubnet = $subnets | Where-Object { $_.name -like '*snet-app*' }

  [ordered]@{
    PublicAccessDisabled   = [bool]($storage | Where-Object { $_.properties.publicNetworkAccess -eq 'Disabled' })
    BlobPublicAccessOff    = [bool]($storage | Where-Object { $_.properties.allowBlobPublicAccess -eq $false })
    PrivateEndpointBlob    = [bool]($pes | Where-Object {
        $_.properties.privateLinkServiceConnections | Where-Object { $_.properties.groupIds -contains 'blob' } })
    # The zone name is a variable reference in the compiled JSON, so match either form.
    DnsZone                = [bool]($zones | Where-Object { $_.name -like '*privatelink.blob.*' -or $_.name -like "*variables('blobPrivateDnsZoneName')*" })
    DnsVnetLink            = [bool]($links | Where-Object { $_.properties.virtualNetwork.id })
    DnsZoneGroup           = [bool]($groups | Where-Object { @($_.properties.privateDnsZoneConfigs).Count -ge 1 })
    NsgAllowIntegration443 = [bool]$allow
    NsgDenyOtherVnet       = [bool]$deny
    NsgAttachedToApp       = [bool]($appSubnet | Where-Object { $_.properties.networkSecurityGroup.id })
  }
}

# Descriptions shared by checklist.ps1 and generate-evidence.ps1.
$controlText = [ordered]@{
  PublicAccessDisabled   = 'storage publicNetworkAccess = Disabled'
  BlobPublicAccessOff    = 'storage allowBlobPublicAccess = false'
  PrivateEndpointBlob    = 'private endpoint targets the blob subresource'
  DnsZone                = 'private DNS zone privatelink.blob.* declared'
  DnsVnetLink            = 'private DNS zone linked to the VNet'
  DnsZoneGroup           = 'private endpoint has a DNS zone group'
  NsgAllowIntegration443 = 'NSG allow 100: 10.40.1.0/24 -> 10.40.2.0/24 TCP 443'
  NsgDenyOtherVnet       = 'NSG deny 4000: VirtualNetwork -> 10.40.2.0/24'
  NsgAttachedToApp       = 'NSG attached to snet-app'
}
