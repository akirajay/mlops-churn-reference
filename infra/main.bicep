targetScope = 'resourceGroup'

@description('Environment short name: dev or prod')
@allowed(['dev', 'prod'])
param envName string

@description('Project short name used in resource naming')
param projectName string = 'churn'

@description('Azure region')
param location string = resourceGroup().location

@description('Enable spot priority for AmlCompute training cluster (dev=true, prod=false)')
param enableSpot bool = (envName == 'dev')

@description('Object ID of the principal that needs Owner-level access on Workspace (your Entra App SP)')
param deployerPrincipalId string

@description('Resource group of the shared ML Registry (for cross-env model promotion)')
param sharedRgName string = 'rg-churn-shared'

@description('Name of the shared ML Registry')
param registryName string = 'mlr-churn-shared-jpe'

var suffix = '${projectName}-${envName}'
var tags = {
  project: projectName
  env: envName
  owner: 'akira.go'
  managedBy: 'bicep'
}

// ---------- Foundation: Storage, KV, ACR, AppInsights ----------
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: 'st${replace(suffix, '-', '')}${uniqueString(resourceGroup().id)}'
    location: location
    tags: tags
  }
}

module kv 'modules/keyvault.bicep' = {
  name: 'kv'
  params: {
    name: 'kv-${suffix}-${uniqueString(resourceGroup().id)}'
    location: location
    tags: tags
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    name: 'acr${replace(suffix, '-', '')}${uniqueString(resourceGroup().id)}'
    location: location
    tags: tags
  }
}

module ai 'modules/appinsights.bicep' = {
  name: 'ai'
  params: {
    name: 'appi-${suffix}'
    location: location
    tags: tags
  }
}

// ---------- Network: VNet + Subnet + PE DNS zones ----------
module net 'modules/network.bicep' = {
  name: 'net'
  params: {
    vnetName: 'vnet-${suffix}'
    location: location
    tags: tags
  }
}

// ---------- Azure ML Workspace ----------
module ws 'modules/workspace.bicep' = {
  name: 'ws'
  params: {
    name: 'mlw-${suffix}'
    location: location
    tags: tags
    storageId: storage.outputs.id
    keyVaultId: kv.outputs.id
    acrId: acr.outputs.id
    appInsightsId: ai.outputs.id
    enableManagedVnet: true
    deployerPrincipalId: deployerPrincipalId
  }
}

// ---------- Compute ----------
module compute 'modules/compute.bicep' = {
  name: 'compute'
  params: {
    workspaceName: ws.outputs.name
    location: location
    enableSpot: enableSpot
  }
}

output workspaceName string = ws.outputs.name
output workspaceId string = ws.outputs.id
output registryHint string = '${sharedRgName}/${registryName}'
