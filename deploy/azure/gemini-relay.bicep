// Gemini relay (Task 124). The Gemini API refuses calls from Azure East Asia
// (Hong Kong). This tiny app runs in Japan East (allowed by the Student
// region policy), holds the Gemini key and forwards generateContent only for
// requests carrying the shared relay token. No Log Analytics (no extra cost).
targetScope = 'resourceGroup'
@allowed(['japaneast', 'koreacentral'])
param location string = 'japaneast'
param environmentName string = 'cae-vinfast-relay-jpe'
param registryServer string
param pullIdentityId string
param image string
param model string
@secure()
param relayToken string
@secure()
param geminiKey string

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
  }
}

resource relay 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'vinfast-gemini-relay'
  location: location
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${pullIdentityId}': {} } }
  properties: {
    managedEnvironmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: { external: true, targetPort: 8080, transport: 'http', allowInsecure: false }
      registries: [{ server: registryServer, identity: pullIdentityId }]
      secrets: [{ name: 'relay-token', value: relayToken }, { name: 'gemini-key', value: geminiKey }]
    }
    template: {
      containers: [{
        name: 'relay'
        image: image
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [
          { name: 'RELAY_TOKEN', secretRef: 'relay-token' }
          { name: 'GEMINI_API_KEY', secretRef: 'gemini-key' }
          { name: 'RELAY_ALLOWED_MODELS', value: model }
        ]
        probes: [{ type: 'Liveness', httpGet: { path: '/healthz', port: 8080 }, periodSeconds: 30 }]
      }]
      // One warm replica: no cold start on the first chat message (idle billing).
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output relayUrl string = 'https://${relay.properties.configuration.ingress.fqdn}'
