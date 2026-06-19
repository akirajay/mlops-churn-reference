param workspaceName string
param location string
param enableSpot bool
param ciName string = 'ci-akira'

// AmlCompute training cluster — Knowledge §3
resource cluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  name: '${workspaceName}/cpu-cluster'
  location: location
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: 'Standard_DS3_v2'
      vmPriority: enableSpot ? 'LowPriority' : 'Dedicated'   // §3: spot only for training
      scaleSettings: {
        minNodeCount: 0                                       // §3: scale to 0
        maxNodeCount: 4
        nodeIdleTimeBeforeScaleDown: 'PT300S'
      }
      osType: 'Linux'
    }
  }
}

// Compute Instance — single-user dev workstation
resource ci 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  name: '${workspaceName}/${ciName}'
  location: location
  properties: {
    computeType: 'ComputeInstance'
    properties: {
      vmSize: 'Standard_DS3_v2'
    }
  }
}

output clusterName string = 'cpu-cluster'
output ciName string = ciName
