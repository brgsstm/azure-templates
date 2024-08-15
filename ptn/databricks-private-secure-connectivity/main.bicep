param workspaceName string
param virtualNetworkResourceId string = ''
param databricksPrivateSubnetName string = 'databricksPrivate'
param databricksPublicSubnetName string = 'databricksPublic'
param privateEndpointSubnetName string = 'privateEndpoints'
param privateDnsAutomated bool = false

var virtualNetworkResourceIdInUse = (virtualNetworkResourceId == '')
  ? virtualNetwork.outputs.resourceId
  : existingVirtualNetwork.id

module databricksWorkspace 'br/public:avm/res/databricks/workspace:0.6.0' = {
  name: 'databricksWorkspaceDeployment'
  params: {
    name: workspaceName
    tags: {
      // verify this is correct usage
      saexclude: 'UC6'
    }
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules' // required on no public access workspaces
    customPrivateSubnetName: databricksPrivateSubnetName
    customPublicSubnetName: databricksPublicSubnetName
    customVirtualNetworkResourceId: virtualNetworkResourceIdInUse
    disablePublicIp: true
    natGatewayName: 'db-nat-gw'
    prepareEncryption: false // looks to be associated with the storage account managed identity
    publicIpName: 'db-nat-gw-public-ip'
    storageAccountName: 'dbrix${uniqueString(resourceGroup().name, subscription().id)}'
  }
}

var privateEndpointName = '${workspaceName}-api-pe'
module databricksPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'databricksPrivateEndpointDeployment'
  params: {
    name: privateEndpointName
    // what about passed in vnet?
    subnetResourceId: '${virtualNetworkResourceIdInUse}/subnets/${privateEndpointSubnetName}'
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
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: privateDnsZone.outputs.resourceId
        }
      ]
    }
  }
}

resource existingVirtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = if (virtualNetworkResourceId != '') {
  scope: resourceGroup(split('/', virtualNetworkResourceId)[4])
  name: (virtualNetworkResourceId != '') ? split('/', virtualNetworkResourceId)[8] : ''
}

// resources below this line are only deployed if an existing vnet is not provided

var delegations = [
  {
    name: 'Microsoft.Databricks/workspaces'
    properties: {
      serviceName: 'Microsoft.Databricks/workspaces'
    }
  }
]
module virtualNetwork 'br/public:avm/res/network/virtual-network:0.2.0' = if (virtualNetworkResourceId == '') {
  name: 'virtualNetworkDeployment'
  params: {
    addressPrefixes: [
      '172.16.0.0/12'
    ]
    name: '${workspaceName}-vnet'
    subnets: [
      {
        name: 'databricksPrivate'
        addressPrefix: '172.16.0.0/24'
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
        delegations: delegations
        privateLinkServiceNetworkPolicies: 'Enabled'
      }
      {
        name: 'databricksPublic'
        addressPrefix: '172.16.1.0/24'
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
        delegations: delegations
        privateLinkServiceNetworkPolicies: 'Enabled'
      }
      {
        name: 'privateEndpoints'
        addressPrefix: '172.16.2.0/24'
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
      }
    ]
  }
}

module networkSecurityGroup 'br/public:avm/res/network/network-security-group:0.4.0' = if (virtualNetworkResourceId == '') {
  name: 'networkSecurityGroupDeployment'
  params: {
    name: '${workspaceName}-databricks-nsg'
    // I don't like having to add the security rules here but see here - https://github.com/Azure/bicep/discussions/5839
    securityRules: [
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-worker-inbound'
        properties: {
          access: 'Allow'
          description: 'Required for worker nodes communication within a cluster.'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
          direction: 'Inbound'
          priority: 100
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-worker-outbound'
        properties: {
          access: 'Allow'
          description: 'Required for worker nodes communication within a cluster.'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
          direction: 'Outbound'
          priority: 100
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-sql'
        properties: {
          access: 'Allow'
          description: 'Required for workers communication with Azure SQL services.'
          destinationAddressPrefix: 'Sql'
          destinationPortRange: '3306'
          direction: 'Outbound'
          priority: 101
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-storage'
        properties: {
          access: 'Allow'
          description: 'Required for workers communication with Azure Storage services.'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
          direction: 'Outbound'
          priority: 102
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'Microsoft.Databricks-workspaces_UseOnly_databricks-worker-to-eventhub'
        properties: {
          access: 'Allow'
          description: 'Required for workers communication with Azure Storage services.'
          destinationAddressPrefix: 'EventHub'
          destinationPortRange: '9093'
          direction: 'Outbound'
          priority: 103
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
    ]
  }
}

// double check this logic re. DNS automation
module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.5.0' = if ((virtualNetworkResourceId == '' && !privateDnsAutomated) || (virtualNetworkResourceId != '' && !privateDnsAutomated)) {
  name: 'privateDnsZoneDeployment'
  params: {
    name: 'privatelink.azuredatabricks.net'
    virtualNetworkLinks: [
      {
        name: '${virtualNetwork.outputs.name}-link'
        registrationEnabled: false
        // what if existing and we need to link to it?
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
  }
}
