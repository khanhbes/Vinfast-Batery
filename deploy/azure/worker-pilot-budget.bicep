targetScope = 'resourceGroup'
param workerResourceId string
@secure()
param contactEmail string
param startDate string
param endDate string

// Alert only. No action group, shutdown automation or hard spending limit.
resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: 'vinfast-worker-pilot-monthly'
  properties: {
    amount: 20
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: { startDate: startDate, endDate: endDate }
    filter: { dimensions: { name: 'ResourceId', operator: 'In', values: [workerResourceId] } }
    notifications: {
      actual80: { enabled: true, operator: 'GreaterThanOrEqualTo', threshold: 80, thresholdType: 'Actual', contactEmails: [contactEmail] }
      actual100: { enabled: true, operator: 'GreaterThanOrEqualTo', threshold: 100, thresholdType: 'Actual', contactEmails: [contactEmail] }
      forecast100: { enabled: true, operator: 'GreaterThanOrEqualTo', threshold: 100, thresholdType: 'Forecasted', contactEmails: [contactEmail] }
    }
  }
}
