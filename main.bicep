@description('Azure region for the Harbor Ledger production network.')
param location string = 'westeurope'

var vnetName = 'vnet-harbor-prod'

resource appNsg 'Microsoft.Network/networkSecurityGroups@2025-01-01' = {
  name: 'nsg-harbor-app-prod'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Integration-Https-In'
        properties: {
          // The integration tier is the only approved inbound app caller.
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '10.40.1.0/24'
          destinationAddressPrefix: '10.40.2.0/24'
        }
      }
      {
        name: 'Deny-Other-Vnet-In'
        properties: {
          // Override Azure's broad AllowVNetInBound default for the app subnet.
          priority: 4000
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '10.40.2.0/24'
        }
      }
    ]
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
