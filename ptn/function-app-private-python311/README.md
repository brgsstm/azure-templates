# Private Azure Function App running Python 3.11

This is a private Azure Function App running Python 3.11.

- Public access is disallowed
- Accessible only via a private endpoint deployed into a pre-existing virtual network
- Runs on an App Service Plan
- Accesses the requisite storage account via VNet integration and a service endpoint
- Authenticates against the requisite storage account using a system-assigned managed identity

## Parameters

| Parameter Name | Type | Description |
|----------------|------|-------------|
| `baseName` | string | A base name - resource descriptors are appened automatically |
