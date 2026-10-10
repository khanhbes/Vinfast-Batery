targetScope = 'resourceGroup'
@allowed(['eastasia'])
param location string
param environmentId string
param registryServer string
param pullIdentityId string
param image string
@minLength(1)
@maxLength(64)
param workerScope string
@secure()
param firebase string
@secure()
param vaultKey string

// Reconciliation worker for the vault_cloud provider. It never arms a relay by
// itself: it renews the fenced lease/heartbeat the API requires before ON,
// finalizes sessions and may only switch OFF on safety violations.
resource worker 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'vinfast-worker-control'
  location: location
  tags: { purpose: 'smart-charge-control-worker', hardware: 'reconcile-off-only' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${pullIdentityId}': {} } }
  properties: {
    managedEnvironmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      // No ingress and no HTTP probes: the worker health server binds
      // 127.0.0.1 only. Liveness is the Firestore heartbeat the API checks.
      registries: [{ server: registryServer, identity: pullIdentityId }]
      secrets: [{ name: 'firebase', value: firebase }, { name: 'vault-key', value: vaultKey }]
    }
    template: {
      containers: [{
        name: 'worker-control'
        image: image
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [
          { name: 'SHELLY_PROVIDER', value: 'vault_cloud' }
          { name: 'SMART_CHARGE_WORKER_SCOPE', value: workerScope }
          { name: 'SMART_CHARGE_WORKER_POLL_SECONDS', value: '30' }
          { name: 'FIREBASE_CREDENTIALS_JSON', secretRef: 'firebase' }
          { name: 'SHELLY_PROFILE_MASTER_KEY', secretRef: 'vault-key' }
        ]
      }]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}
output appName string = worker.name
