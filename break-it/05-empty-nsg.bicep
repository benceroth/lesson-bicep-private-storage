// BROKEN VARIANT - do not use in production.
// Differs from ../main.bicep in ONE control: the NSG is attached to snet-app but has no
// custom rules, so Azure's default AllowVNetInBound (priority 65000) still lets every
// VNet source reach the app subnet. Private endpoint, DNS and storage settings are intact.
// Expected: storage checks pass, but a VNet source that should be denied can reach the app
// subnet. See verify/expected-results.md.

@description('Azure region for the Harbor Ledger production network.')
param location string = 'westeurope'

var vnetName = 'vnet-harbor-prod'
var storageAccountName = 'stharbor${uniqueString(resourceGroup().id)}'
var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

resource appNsg 'Microsoft.Network/networkSecurityGroups@2025-01-01' = {
  name: 'nsg-harbor-app-prod'
  location: location
  properties: {
    // MISSING CONTROL: the Allow (100) and Deny-Other-Vnet-In (4000) rules.
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
  }
}

resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-01-01' = {
  parent: vnet
  name: 'snet-integration'
  properties: {
    addressPrefix: '10.40.1.0/24'
  }
}

resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-01-01' = {
  parent: vnet
  name: 'snet-app'
  properties: {
    addressPrefix: '10.40.2.0/24'
    networkSecurityGroup: {
      id: appNsg.id
    }
  }
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2025-01-01' = {
  parent: vnet
  name: 'snet-private-endpoints'
  properties: {
    addressPrefix: '10.40.3.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    // A private endpoint alone does not disable the public endpoint.
    publicNetworkAccess: 'Disabled'
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: blobPrivateDnsZoneName
  location: 'global'
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: 'link-harbor-prod'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: 'pe-harbor-blob-prod'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'blob-connection'
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource blobDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob-zone'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}

output storageBlobHostName string = '${storage.name}.blob.${environment().suffixes.storage}'
output privateDnsZone string = blobPrivateDnsZone.name
