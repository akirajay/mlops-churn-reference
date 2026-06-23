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
    // Use Entra ID (not account keys) for system datastores. Required because a
    // subscription policy disables shared-key auth on storage accounts.
    systemDatastoresAuthMode: 'Identity'
    managedNetwork: enableManagedVnet ? {
      isolationMode: 'AllowInternetOutbound'
    } : null
  }
}

// Storage account that backs the workspace (existing; same RG) so we can grant
// the workspace MSI blob data access for identity-based datastore operations.
resource storageAcct 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: last(split(storageId, '/'))
}

var roleBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource raWsBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAcct
  name: guid(storageAcct.id, ws.id, roleBlobDataContributor)
  properties: {
    principalId: ws.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleBlobDataContributor)
    principalType: 'ServicePrincipal'
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
