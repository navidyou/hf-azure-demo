// ──────────────────────────────────────────────────────────────────────────────
// Container Apps stack
//   • Azure Container Registry (existing)          • Log Analytics workspace
//   • Application Insights (linked to workspace)   • Container Apps environment
//   • Container App (API)
// ──────────────────────────────────────────────────────────────────────────────

@description('Deployment location; defaults to the RG location')
param location string = resourceGroup().location

@description('Name of an existing Azure Container Registry (no FQDN)')
param acrName string

@description('Docker image tag to deploy')
param tag string

@allowed([ 'dev' 'stage' 'prod' ])
@description('Deployment stage')
param stage string = 'dev'

@description('HF model ID passed to the container')
param modelId string = 'distilbert-base-uncased-finetuned-sst-2-english'

// ─── Derived names ────────────────────────────────────────────────────────────
var envName = 'aca-${stage}-env'
var appName = 'sentiment-api-${stage}'

// ─── Existing ACR ─────────────────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// ─── Log Analytics ────────────────────────────────────────────────────────────
resource logWs 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    retentionInDays: 30
  }
}

// ─── Application Insights (linked to workspace) ──────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type   : 'web'
    WorkspaceResourceId: logWs.id              // link AI ↔ workspace
  }
}

// ─── Container Apps managed environment ──────────────────────────────────────
resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination             : 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWs.properties.customerId
        sharedKey : logWs.listKeys().primarySharedKey
      }
    }
  }
}

// ─── Container App ────────────────────────────────────────────────────────────
resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: env.id

    // ---------- App-level configuration ----------
    configuration: {
      ingress: {
        external  : true
        targetPort: 80
      }

      // Azure Container Registry credentials
      registries: [
        {
          server  : '${acr.name}.azurecr.io'
          username: acr.listCredentials().username
          password: acr.listCredentials().passwords[0].value
        }
      ]

      // Store the AI connection string as a secret so it is never exposed in plain text
      secrets: [
        {
          name : 'ai-connection-string'
          value: appInsights.properties.ConnectionString   // secure value
        }
      ]
    }

    // ---------- Container template ----------
    template: {
      containers: [
        {
          name : 'api'
          image: '${acr.name}.azurecr.io/hf-api:${tag}'
          env: [
            { name: 'HF_MODEL_ID',                           value    : modelId },
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', secretRef: 'ai-connection-string' },
            { name: 'STAGE',                                 value    : stage }
          ]
          resources: {
            cpu   : 0.5
            memory: '1Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [
          {
            name: 'http-auto'
            http: {
              concurrentRequests: 20
            }
          }
        ]
      }
    }
  }
}
