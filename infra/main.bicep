// ──────────────────────────────────────────────────────────────────────────────
// Container Apps -- per-environment stack (Without Container App)
// Azure resources: ACR (existing) • Log Analytics • App Insights
//                  • Container Apps Environment
// ──────────────────────────────────────────────────────────────────────────────
param location string = resourceGroup().location
param acrName  string
param stage    string = 'dev'

// Derived names
var envName = 'aca-${stage}-env'

// Existing ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// Log Analytics workspace
resource logWS 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logWS.id
  }
}

// Container Apps managed environment
resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWS.properties.customerId
        sharedKey: logWS.listKeys().primarySharedKey
      }
    }
  }
}

// Output to reuse resources in later steps
output containerAppsEnvId string = env.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output acrLoginServer string = '${acr.name}.azurecr.io'
