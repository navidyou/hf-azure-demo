// ──────────────────────────────────────────────────────────────────────────────
// Container Apps -- per-environment stack
// Azure resources: ACR (existing) • Log Analytics • App Insights
//                  • Container Apps Environment • Container App
// ──────────────────────────────────────────────────────────────────────────────
param location string = resourceGroup().location
param acrName  string                        // plain ACR name (no FQDN)
param tag      string                        // image tag to deploy
param stage    string = 'dev'                // dev | stage | prod
param modelId  string = 'distilbert-base-uncased-finetuned-sst-2-english'

// ───────────── derived names ─────────────
var envName = 'aca-${stage}-env'
var appName = 'sentiment-api-${stage}'

// ───────────── existing ACR ─────────────
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

// ─────── Application Insights ───────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type   : 'web'
    WorkspaceResourceId: logWS.id
  }
}

// ─── Container Apps managed environment ─
resource env 'Microsoft.App/managedEnvironments@2023-05-01-preview' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination             : 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWS.properties.customerId
        sharedKey : logWS.listKeys().primarySharedKey
      }
    }
  }
}

// ───────────── Container App ────────────
resource app 'Microsoft.App/containerApps@2023-05-01-preview' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: env.id
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
    }
    template: {
      containers: [
        {
          name : 'api'
          image: '${acr.name}.azurecr.io/hf-api:${tag}'
          env: [
            { name: 'HF_MODEL_ID',                           value: modelId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.connectionString }
            { name: 'STAGE',                                 value: stage }
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
