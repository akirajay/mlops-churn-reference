param name string
param location string
param tags object

@description('Object ID of the deployer/CI service principal needing blob data-plane access (code snapshot upload)')
param deployerPrincipalId string

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled' // PE will be added; keep enabled for first bootstrap
  }
}

// RBAC: Storage Blob Data Contributor to the deployer/CI SP.
// Required so `az ml job create` can upload the code snapshot to the
// workspace default blob datastore using Entra ID (data-plane) auth.
// Without this the job fails with: AuthorizationFailure.
var roleBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource raBlob 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sa
  name: guid(sa.id, deployerPrincipalId, roleBlobDataContributor)
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleBlobDataContributor)
    principalType: 'ServicePrincipal'
  }
}

output id string = sa.id
output name string = sa.name
