// Public-read store for approved vehicle catalog photos (Task 122).
// Kept separate from the private runtime storage account. Blobs are readable
// by URL only (no container listing); writes require Entra ID — the API's
// user-assigned identity gets Storage Blob Data Contributor on this container.
targetScope = 'resourceGroup'
param location string = 'eastasia'
param mediaStorageName string
param containerName string = 'vehicle-media'
param apiIdentityName string = 'vinfast-image-pull'

resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: apiIdentityName
}

resource media 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: mediaStorageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: true
    allowSharedKeyAccess: false
    accessTier: 'Hot'
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: media
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: containerName
  properties: { publicAccess: 'Blob' }
}

// Storage Blob Data Contributor, scoped to the media container only.
resource writer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, apiIdentity.id, 'BlobDataContributor')
  scope: container
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Task 123: Shelly Cloud dispatch gate state (lease, 1.1 s spacing, OFF
// priority, 429 cooldown) lives next to the API in East Asia instead of in
// Firestore nam5. Non-secret: RowKey is a SHA-256 credential fingerprint.
param dispatchTableName string = 'shellyDispatch'

resource tables 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: media
  name: 'default'
}

resource dispatchTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tables
  name: dispatchTableName
}

// Storage Table Data Contributor, scoped to the dispatch table only. API and
// worker share this identity, so both use the same gate.
resource dispatchWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dispatchTable.id, apiIdentity.id, 'TableDataContributor')
  scope: dispatchTable
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output dispatchTableName string = dispatchTable.name
output mediaStorageName string = media.name
output containerName string = container.name
output publicBaseUrl string = '${media.properties.primaryEndpoints.blob}${containerName}/'
output apiIdentityClientId string = apiIdentity.properties.clientId
