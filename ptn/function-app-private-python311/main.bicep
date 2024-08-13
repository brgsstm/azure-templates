param baseName string
param subnetResourceId string

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.1.8' = {
  name: 'virtualNetworkDeployment'
  params: {
    addressPrefixes: [
      '192.168.1.0/24'
    ]
    name: '${baseName}-vnet'
    subnets: [
      {
        name: 'AppServiceIntegration'
        addressPrefix: '192.168.1.0/26'
        serviceEndpoints: [
          { service: 'Microsoft.Storage' }
        ]
        delegations: [
          {
            name: 'serverFarmsDelegation'
            properties: {
              serviceName: 'Microsoft.Web/serverFarms'
            }
          }
        ]
        networkSecurityGroupResourceId: networkSecurityGroup.outputs.resourceId
      }
    ]
  }
}

module networkSecurityGroup 'br/public:avm/res/network/network-security-group:0.3.1' = {
  name: 'networkSecurityGroupDeployment'
  params: {
    name: '${baseName}-nsg'
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.9.1' = {
  name: 'storageAccountDeployment'
  params: {
    name: toLower('${baseName}')
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          action: 'Allow'
          id: '${virtualNetwork.outputs.resourceId}/subnets/AppServiceIntegration'
        }
      ]
    }
  }
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.2.2' = {
  name: 'appServicePlanDeployment'
  params: {
    kind: 'Linux'
    name: '${baseName}-asp'
    skuCapacity: 1
    skuName: 'P1v3'
    reserved: true
    zoneRedundant: false
  }
}

module functionApp 'br/public:avm/res/web/site:0.3.9' = {
  name: 'siteDeployment'
  params: {
    kind: 'functionapp,linux'
    name: '${baseName}-func'
    serverFarmResourceId: appServicePlan.outputs.resourceId
    publicNetworkAccess: 'Disabled'
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'python|3.11'
      alwaysOn: true
      reserved: true
      cors: {
        // allows this function app to be called from the portal
        // still requires access to the function app in order to retrieve the function key
        // https://docs.microsoft.com/en-us/azure/azure-functions/security-concepts#cors
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    appSettingsKeyValuePairs: {
      AzureWebJobsStorage__blobServiceUri: storageAccount.outputs.primaryBlobEndpoint
      // queus and tables primary endpoint output are not supported in the storage account AVM
      // so we need to manually construct the endpoint
      // PR raised - https://github.com/Azure/bicep-registry-modules/pull/2998
      AzureWebJobsStorage__queueServiceUri: 'https://${storageAccount.outputs.name}.queue.core.windows.net/'
      AzureWebJobsStorage__tableServiceUri: 'https://${storageAccount.outputs.name}.table.core.windows.net/'
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'python'
    }
    virtualNetworkSubnetId: '${virtualNetwork.outputs.resourceId}/subnets/AppServiceIntegration'
    storageAccountResourceId: storageAccount.outputs.resourceId
    storageAccountUseIdentityAuthentication: true
    managedIdentities: {
      systemAssigned: true
    }
  }
}

module functionAppRoleAssignmentBlob 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'functionAppRoleAssignmentBlobDeployment'
  params: {
    principalId: functionApp.outputs.systemAssignedMIPrincipalId
    resourceId: storageAccount.outputs.resourceId
    // Storage Blob Data Owner
    roleDefinitionId: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  }
}

module functionAppRoleAssignmentQueue 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'functionAppRoleAssignmentQueueDeployment'
  params: {
    principalId: functionApp.outputs.systemAssignedMIPrincipalId
    resourceId: storageAccount.outputs.resourceId
    // Storage Queue Data Contributor
    roleDefinitionId: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  }
}

module functionAppRoleAssignmentTable 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'functionAppRoleAssignmentTableDeployment'
  params: {
    principalId: functionApp.outputs.systemAssignedMIPrincipalId
    resourceId: storageAccount.outputs.resourceId
    // Storage Table Data Contributor
    roleDefinitionId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  }
}

module functionAppPrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.7.0' = {
  name: 'funtionAppPrivateEndpointDeployment'
  params: {
    name: '${baseName}-func-pe'
    subnetResourceId: subnetResourceId
    customNetworkInterfaceName: '${baseName}-func-nic'
    privateLinkServiceConnections: [
      {
        name: '${baseName}-func-pe'
        properties: {
          groupIds: [
            'sites'
          ]
          privateLinkServiceId: functionApp.outputs.resourceId
        }
      }
    ]
  }
}
