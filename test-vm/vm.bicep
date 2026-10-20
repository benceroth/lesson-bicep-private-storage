// Optional test VM for the live checks. No public IP: reach it with `az vm run-command`
// (no Bastion cost). Deploy into the SAME resource group as main.bicep (or a variant).
//
// Roles (deploy it up to three times with different vmName/subnetName):
//   - blob client:    subnetName 'snet-integration', grantBlobReader true  -> verify/from-inside.sh
//   - app listener:   subnetName 'snet-app', listenOn443 true              -> NSG target
//   - denied source:  subnetName 'snet-private-endpoints'                  -> must NOT reach the listener
// scripts/run-live.ps1 does all of this for you.

targetScope = 'resourceGroup'

@description('Azure region; must match the VNet.')
param location string = 'westeurope'

@description('VM name.')
param vmName string

@description('Existing subnet in vnet-harbor-prod to attach the VM to.')
@allowed([
  'snet-integration'
  'snet-app'
  'snet-private-endpoints'
])
param subnetName string = 'snet-integration'

@description('Admin user name. Password sign-in is disabled; SSH key only.')
param adminUsername string = 'harboradmin'

@description('SSH PUBLIC key (ssh-ed25519 ... or ssh-rsa ...). Never pass a private key.')
param sshPublicKey string

@description('Grant the VM identity Storage Blob Data Reader on the storage account and create the probe container.')
param grantBlobReader bool = false

@description('Start a throwaway TCP listener on 443 (used as the NSG test target).')
param listenOn443 bool = false

@description('Small, cheap size.')
param vmSize string = 'Standard_B1s'

var vnetName = 'vnet-harbor-prod'
// Same formula as main.bicep, so this resolves the storage account in the same resource group.
var storageAccountName = 'stharbor${uniqueString(resourceGroup().id)}'
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
var listenerCloudInit = '''
#cloud-config
runcmd:
  - [ sh, -c, "nohup python3 -m http.server 443 --bind 0.0.0.0 > /var/log/listener.log 2>&1 &" ]
'''

resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2025-01-01' existing = {
  parent: vnet
  name: subnetName
}

resource storage 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource nic 'Microsoft.Network/networkInterfaces@2025-01-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: listenOn443 ? base64(listenerCloudInit) : null
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' existing = {
  parent: storage
  name: 'default'
}

// Container creation is a management-plane call, so it works while public access is disabled.
resource probeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = if (grantBlobReader) {
  parent: blobService
  name: 'probe'
}

resource blobReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantBlobReader) {
  name: guid(storage.id, vm.id, storageBlobDataReaderRoleId)
  scope: storage
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
  }
}

output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output vmId string = vm.id
