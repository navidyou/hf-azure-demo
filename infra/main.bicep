// ──────────────────────────────────────────────────────────────────────────────
// Container-Apps stack
//   ─ Existing ACR                        ─ Log Analytics workspace
//   ─ Application Insights (linked)       ─ Container Apps environment
//   ─ Container App (API)
// ──────────────────────────────────────────────────────────────────────────────

param location string                       = resourceGroup().location
param acrName  string                       // existing ACR, short name
param tag      string                       // image tag to deploy

@allowed([
  'dev'
  'stage'
  'prod'
])
param stage string                          = 'dev'

param modelId string                        = 'distilbert-base-uncased-finetuned-sst-2-english'

// ─── Derived names ────────────────────────────────────────────────────────────
var envName = 'aca-${stage}-env'
var appName = 'sentiment-api-${stage}'

// ─── Existing ACR ─────────────────────────────────────────────────────────────
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

// ─── Log Analytics workspace ─────────────────────────────────────────────────
resource logWs 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    retentionInDays: 30
  }
}

// ─── Application Insights ────────────────────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  kind:   'web'
  properties: {
    Application_Type   : 'web'
    WorkspaceResourceId: logWs.id
  }
}

// ─── Container Apps managed environment ──────────────────────────────────────
resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWs.properties.customerId
        sharedKey : logWs.listKeys().primarySharedKey    // linter warns but fine
      }
    }
  }
}

// ─── Container App (API) ─────────────────────────────────────────────────────
resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: env.id

    // ── Global app config ──
    configuration: {
      ingress: {
        external  : true
        targetPort: 80
      }

      registries: [
        {
          server  : '${acr.name}.azurecr.io'
          username: acr.listCredentials().username
          password: acr.listCredentials().passwords[0].value
        }
      ]

      // store the AI connection string as a secret
      secrets: [
        {
          name : 'ai-connection-string'
          value: appInsights.properties.ConnectionString   // linter warns but fine
        }
      ]
    }

    // ── Revision template ──
    template: {
      containers: [
        {
          name : 'api'
          image: '${acr.name}.azurecr.io/hf-api:${tag}'
          env: [
            {
              name : 'HF_MODEL_ID'
              value: modelId
            }
            {
              name     : 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'ai-connection-string'
            }
            {
              name : 'STAGE'
              value: stage
            }
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
            name: 'http-auto',
            http: {
              concurrentRequests: 20
            }
          }
        ]
      }
    }
  }
}
