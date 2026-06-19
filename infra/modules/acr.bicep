param name string
param location string
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'Premium' }   // Premium needed for PE + Managed VNet
  properties: {
    adminUserEnabled: false
  }
}

output id string = acr.id
output name string = acr.name
