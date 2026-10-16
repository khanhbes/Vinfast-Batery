// Gemini relay as Azure API Management (Consumption), Japan East (Task 124).
// Gemini refuses calls from Azure East Asia (Hong Kong); the Student
// subscription allows Japan East but only one Container Apps environment and
// no App Service plans. APIM Consumption: HTTPS, subscription-key auth, 1M
// calls/month free, no code. Policy injects the Gemini key (named value,
// secret) and only allows generateContent on the configured model.
targetScope = 'resourceGroup'
@allowed(['japaneast', 'koreacentral'])
param location string = 'japaneast'
param serviceName string = 'vinfast-gemini-relay-jpe'
param publisherEmail string
param model string
@secure()
param geminiKey string

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: serviceName
  location: location
  sku: { name: 'Consumption', capacity: 0 }
  properties: { publisherEmail: publisherEmail, publisherName: 'VinFast Battery' }
}

resource key 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'gemini-key'
  properties: { displayName: 'gemini-key', secret: true, value: geminiKey }
}

resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'gemini'
  properties: {
    displayName: 'Gemini relay'
    path: 'gemini'
    protocols: ['https']
    serviceUrl: 'https://generativelanguage.googleapis.com/v1beta/models'
    subscriptionRequired: true
    subscriptionKeyParameterNames: { header: 'X-Relay-Token', query: 'relay-key-unused' }
  }
}

resource operation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'generate'
  properties: {
    displayName: 'generateContent'
    method: 'POST'
    urlTemplate: '/v1/generate/{model}'
    templateParameters: [{ name: 'model', type: 'string', required: true }]
  }
}

resource policy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: operation
  name: 'policy'
  dependsOn: [key]
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><rate-limit calls="60" renewal-period="60" /><choose><when condition="@(context.Request.MatchedParameters["model"] != "${model}")"><return-response><set-status code="400" reason="MODEL_NOT_ALLOWED" /></return-response></when><when condition="@(int.Parse(context.Request.Headers.GetValueOrDefault("Content-Length", "0")) > 524288)"><return-response><set-status code="413" reason="BODY_SIZE" /></return-response></when></choose><set-header name="x-goog-api-key" exists-action="override"><value>{{gemini-key}}</value></set-header><set-header name="X-Relay-Token" exists-action="delete" /><rewrite-uri template="/${model}:generateContent" copy-unmatched-params="false" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  parent: apim
  name: 'vinfast-api'
  properties: { displayName: 'VinFast API', scope: api.id, state: 'active' }
}

output relayUrl string = '${apim.properties.gatewayUrl}/gemini'
