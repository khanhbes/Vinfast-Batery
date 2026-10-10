targetScope = 'resourceGroup'
@allowed(['eastasia'])
param location string
param environmentId string
param registryServer string
param pullIdentityId string
param image string
@secure()
param firebase string
@secure()
param vaultKey string

resource pilot 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'vinfast-worker-pilot'
  location: location
  tags: { purpose: 'read-only-worker-pilot', hardware: 'disabled' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${pullIdentityId}': {} } }
  properties: {
    managedEnvironmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      // No ingress: port 8090 is accessible only to platform health probes.
      registries: [{ server: registryServer, identity: pullIdentityId }]
      secrets: [{ name: 'firebase', value: firebase }, { name: 'vault-key', value: vaultKey }]
    }
    template: {
      containers: [{
        name: 'worker-pilot'
        image: image
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [
          { name: 'AZURE_STAGING_HARDWARE_DISABLED', value: '1' }
          { name: 'SMART_CHARGE_PILOT_SCOPE', value: 'azure-staging-pilot' }
          { name: 'FIREBASE_CREDENTIALS_JSON', secretRef: 'firebase' }
          { name: 'SHELLY_PROFILE_MASTER_KEY', secretRef: 'vault-key' }
        ]
        probes: [
          { type: 'Startup', httpGet: { path: '/health', port: 8090 }, periodSeconds: 10, timeoutSeconds: 5, failureThreshold: 12 }
          { type: 'Liveness', httpGet: { path: '/health', port: 8090 }, periodSeconds: 30, timeoutSeconds: 5, failureThreshold: 3 }
          { type: 'Readiness', httpGet: { path: '/ready', port: 8090 }, periodSeconds: 15, timeoutSeconds: 5, failureThreshold: 3 }
        ]
      }]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}
output appName string = pilot.name
