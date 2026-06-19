targetScope = 'resourceGroup'

param location string = 'japaneast'
param registryName string = 'mlr-churn-shared-jpe'

resource reg 'Microsoft.MachineLearningServices/registries@2024-04-01' = {
  name: registryName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    publicNetworkAccess: 'Enabled'
    regionDetails: [
      {
        location: location
        storageAccountDetails: [ { systemCreatedStorageAccount: { storageAccountHnsEnabled: false, storageAccountType: 'Standard_LRS' } } ]
        acrDetails: [ { systemCreatedAcrAccount: { acrAccountSku: 'Premium' } } ]
      }
    ]
  }
}

output registryName string = reg.name
