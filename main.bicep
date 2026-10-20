@description('Azure region for the Harbor Ledger production network.')
param location string = 'westeurope'

var vnetName = 'vnet-harbor-prod'

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
