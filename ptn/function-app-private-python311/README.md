# Private Azure Function App running Python 3.11

This template deploys a private Python 3.11 Azure Function App running on a Linux App Service Plan.

## Features

- Public access disallowed
- Accessible only via a private endpoint deployed into a pre-existing virtual network
- Access to the requisite storage account is achieved via VNet integration and a Microsoft.Storage service endpoint
- Authenticates against the requisite storage account using a system-assigned managed identity

## Parameters

| Parameter Name        | Description                                                                       | Type   | Required | Limitations    |
|-----------------------|-----------------------------------------------------------------------------------|--------|----------|----------------|
| `baseName`            | A base name for all resources (resource descriptors are appened automatically)    | string | Yes      | max length: 15 |
| `subnetResourceId`    | The subnet resource ID to deploy the function app private endpoint to             | string | Yes      |                |

---

`subnetResourceId` should be formatted:

```bicep
/subscriptions/<subscriptionId>/resourceGroups/<resourceGroupName>/providers/Microsoft.Network/virtualNetworks/<vnetName>/subnets/<subnetName>
```

## Considerations

This template does not cater for the DNS requirements of the included private endpoint.  Suitable automation should exist within the deployment environment in order to ensure DNS resolution of the function app private endpoint.

## Additonal Details

This pattern template is built on top of various [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/).
