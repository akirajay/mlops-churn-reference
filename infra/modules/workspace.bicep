param name string
param location string
param tags object
param storageId string
param keyVaultId string
param acrId string
param appInsightsId string
param enableManagedVnet bool = true
param deployerPrincipalId string

resource ws 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: name
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }   // Knowledge §14: Managed Identity
  sku: { name: 'Basic', tier: 'Basic' }
  properties: {
    friendlyName: name
    storageAccount: storageId
    keyVault: keyVaultId
    containerRegistry: acrId
    applicationInsights: appInsightsId
    publicNetworkAccess: 'Enabled'        // bootstrap; tighten in §4 lab extension
    managedNetwork: enableManagedVnet ? {
      isolationMode: 'AllowInternetOutbound'
    } : null
  }
}

// RBAC: AzureML Data Scientist + Compute Operator to the deployer SP
var roleDataScientist = 'f6c7c914-8db3-469d-8ca1-694a8f32e121'
var roleComputeOperator = 'e503ece1-11d0-4e8e-8e2c-7a6c3bf38815'

resource raDS 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ws
  name: guid(ws.id, deployerPrincipalId, roleDataScientist)
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDataScientist)
    principalType: 'ServicePrincipal'
  }
}

resource raCO 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ws
  name: guid(ws.id, deployerPrincipalId, roleComputeOperator)
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleComputeOperator)
    principalType: 'ServicePrincipal'
  }
}

output name string = ws.name
output id string = ws.id
output principalId string = ws.identity.principalId
