param workspaceName string
param virtualNetworkResourceId string
param privateEndpointSubnetName string

module databricksWorkspace 'br/public:avm/res/databricks/workspace:0.6.0' = {
  name: 'databricksWorkspaceDeployment'
  params: {
    name: workspaceName
    tags: {
      saexclude: 'UC6'
    }
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules' // needs lookimg into
    customPrivateSubnetName: 'databricksPrivate'
    customPublicSubnetName: 'databricksPublic'
    customVirtualNetworkResourceId: virtualNetworkResourceId
    disablePublicIp: true
    natGatewayName: 'db-nat-gateway'
    prepareEncryption: false // looks to be associated with the storage account managed identity
    publicIpName: 'db-nat-gw-public-ip'
    storageAccountName: 'dbstorage${uniqueString(resourceGroup().name, subscription().id)}'
  }
}

var privateEndpointName = '${workspaceName}-api-pe'
module databricksPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'databricksPrivateEndpointDeployment'
  params: {
    name: privateEndpointName
    subnetResourceId: '${virtualNetworkResourceId}/subnets/${privateEndpointSubnetName}'
    customNetworkInterfaceName: '${privateEndpointName}-nic'
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          groupIds: [
            'databricks_ui_api'
          ]
          privateLinkServiceId: databricksWorkspace.outputs.resourceId
        }
      }
    ]
  }
}
