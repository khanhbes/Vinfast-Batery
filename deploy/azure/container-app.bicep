targetScope = 'resourceGroup'
@allowed(['vinfast-api', 'vinfast-ai'])
param appName string
param location string = 'southeastasia'
param environmentId string
param registryServer string
param pullIdentityId string
param image string
@secure()
param secrets object
param variables object

var isApi = appName == 'vinfast-api'
var port = isApi ? 5000 : 8001
var health = isApi ? '/api/health' : '/healthz'
resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${pullIdentityId}': {} } }
  properties: {
    managedEnvironmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: { external: isApi, targetPort: port, transport: 'auto', allowInsecure: false }
      registries: [{ server: registryServer, identity: pullIdentityId }]
      secrets: secrets.entries
    }
    template: {
      containers: [{
        name: appName
        image: image
        resources: { cpu: isApi ? json('0.25') : 1, memory: isApi ? '0.5Gi' : '2Gi' }
        env: [for item in items(variables): item.value.secret
          ? { name: item.key, secretRef: item.value.value }
          : { name: item.key, value: item.value.value }]
        volumeMounts: [{ volumeName: 'runtime', mountPath: '/app/data' }]
        probes: [
          { type: 'Startup', httpGet: { path: health, port: port }, periodSeconds: 10, timeoutSeconds: 5, failureThreshold: 60 }
          { type: 'Liveness', httpGet: { path: health, port: port }, periodSeconds: 30, timeoutSeconds: 5, failureThreshold: 3 }
          { type: 'Readiness', httpGet: { path: isApi ? '/api/ready' : health, port: port }, periodSeconds: 10, timeoutSeconds: 5, failureThreshold: 3 }
        ]
      }]
      scale: { minReplicas: 0, maxReplicas: 1, rules: [{ name: 'http', http: { metadata: { concurrentRequests: '10' } } }] }
      volumes: [{ name: 'runtime', storageType: 'AzureFile', storageName: 'runtimefiles' }]
    }
  }
}
output url string = 'https://${app.properties.configuration.ingress.fqdn}'
