param vnetName string
param location string
param tags object

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ '10.20.0.0/16' ] }
    subnets: [
      {
        name: 'pe-subnet'
        properties: {
          addressPrefix: '10.20.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'compute-subnet'
        properties: { addressPrefix: '10.20.2.0/24' }
      }
    ]
  }
}

output vnetId string = vnet.id
output peSubnetId string = vnet.properties.subnets[0].id
output computeSubnetId string = vnet.properties.subnets[1].id
