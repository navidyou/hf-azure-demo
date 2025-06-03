// ──────────────────────────────────────────────────────────────────────────────
// Full Bicep: ACR (existing) • Log Analytics • App Insights • Container App Env • Container App
// ──────────────────────────────────────────────────────────────────────────────
param location string = resourceGroup().location
param acrName  string                                     // ACR name (no FQDN)
param stage    string = 'dev'                             // dev | stage | prod
param tag      string                                     // Image tag to deploy

// Derived names
var envName = 'aca-${stage}-env'
var appName = 'sentiment-api-${stage}'
var image   = '${acrName}.azurecr.io/hf-api:${tag}'

// ──────────── Existing ACR ─────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// ─────── Log Analytics workspace ────────
resource logWS 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    retentionInDays: 30
  }
}

// ──────── Application Insights ─────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logWS.id
  }
}

// ──── Container Apps managed environment ────
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

// ─────────── Container App ──────────────
resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
      }
      registries: [
        {
          server: '${acrName}.azurecr.io'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: image
          resources: {
            cpu: 0.5
            memory: '1.0Gi'
          }
        }
      ]
    }
  }
}

// ──────────── Outputs ──────────────
output containerAppsEnvId string = env.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output acrLoginServer string = '${acr.name}.azurecr.io'
