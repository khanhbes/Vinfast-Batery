// Staging only: no VM, databases, premium/dedicated profile or logging workspace.
targetScope = 'resourceGroup'
param location string = 'southeastasia'
param environmentName string = 'cae-vinfast-battery'
param registryName string
param storageName string
param adminName string = 'vinfast-admin'

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: registryName
  location: location
  sku: { name: 'Standard' }
  properties: { adminUserEnabled: false }
}
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'vinfast-image-pull'
  location: location
}
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, 'AcrPull')
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}
resource files 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storage
  name: 'default'
}
resource runtime 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: files
  name: 'runtime'
  properties: { shareQuota: 20, enabledProtocols: 'SMB' }
}
resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: environmentName
  location: location
  properties: {
    environmentMode: 'WorkloadProfiles'
    // ARM represents disabled log storage as an empty destination, not the
    // Azure CLI's literal --logs-destination none option.
    appLogsConfiguration: { destination: '' }
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
}
resource mount 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: environment
  name: 'runtimefiles'
  properties: {
    azureFile: {
      accountName: storage.name
      accountKey: storage.listKeys().keys[0].value
      shareName: runtime.name
      accessMode: 'ReadWrite'
    }
  }
}
resource admin 'Microsoft.Web/staticSites@2023-12-01' = {
  name: adminName
  // SWA has its own regional availability; verify before Create.
  location: 'eastasia'
  sku: { name: 'Free', tier: 'Free' }
  properties: { stagingEnvironmentPolicy: 'Disabled' }
}
output environmentId string = environment.id
output registryServer string = registry.properties.loginServer
output pullIdentityId string = identity.id
output storageAccount string = storage.name
output adminUrl string = 'https://${admin.properties.defaultHostname}'
