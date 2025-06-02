param location string = resourceGroup().location
param acrName   string
param tag       string                                // image tag to deploy
param stage     string = 'dev'                        // dev | stage | prod
param modelId   string = 'distilbert-base-uncased-finetuned-sst-2-english'

var envName     = 'aca-${stage}-env'
var appName     = 'sentiment-api-${stage}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: acrName
}

resource logWS 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  properties: { retentionInDays: 30 }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${stage}-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logWS.id
  }
}

resource env 'Microsoft.App/managedEnvironments@2023-05-01-preview' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logWS.properties.customerId
        sharedKey:  logWS.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2023-05-01-preview' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      ingress: { external: true, targetPort: 80 }
      registries: [{
        server: '${acr.name}.azurecr.io'
        username: acr.listCredentials().username
        password: acr.listCredentials().passwords[0].value
      }]
    }
    template: {
      containers: [{
        name: 'api'
        image: '${acr.name}.azurecr.io/hf-api:${tag}'
        env: [
          { name: 'HF_MODEL_ID', value: modelId }
          { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.connectionString }
          { name: 'STAGE', value: stage }
        ]
        resources: { cpu: 0.5, memory: '1Gi' }
      }]
      scale: {
        minReplicas: 1
        maxReplicas: 10
        rules: [{
          name: 'http-auto'
          http: { concurrentRequests: 20 }
        }]
      }
    }
  }
}
