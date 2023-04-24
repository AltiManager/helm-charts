{{/*
Expand the name of the chart.
*/}}
{{- define "altimanager.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "altimanager.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "altimanager.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Allow the release namespace to be overridden for multi-namespace deployments in combined charts
*/}}
{{- define "altimanager.namespace" -}}
  {{- if .Values.namespaceOverride -}}
    {{- .Values.namespaceOverride -}}
  {{- else -}}
    {{- .Release.Namespace -}}
  {{- end -}}
{{- end -}}


{{/*
Common labels
*/}}
{{- define "altimanager.labels" -}}
helm.sh/chart: {{ include "altimanager.chart" . }}
{{ include "altimanager.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels for runner
*/}}
{{- define "altimanager.selectorLabels" -}}
app.kubernetes.io/name: {{ include "altimanager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for runner used by kubectl --selector=key1=value1,key2=value2
*/}}
{{- define "altimanager.selectorLabelsKubectl" -}}
app.kubernetes.io/name={{ include "altimanager.name" . }},app.kubernetes.io/instance={{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "altimanager.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "altimanager.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
    The full image repository:tag[@sha256:sha] for the runner
*/}}
{{- define "altimanager.image" -}}
{{- if .Values.image.sha -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}@sha256:{{ .Values.image.sha }}
{{- else -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}
{{- end -}}

{{/*
    The full image repository:tag[@sha256:sha] for kubectl
*/}}
{{- define "altimanager.kubectl.image" -}}
{{- if .Values.kubectl.image.sha -}}
{{ .Values.kubectl.image.repository }}:{{ .Values.kubectl.image.tag }}@sha256:{{ .Values.kubectl.image.sha }}
{{- else -}}
{{ .Values.kubectl.image.repository }}:{{ .Values.kubectl.image.tag }}
{{- end -}}
{{- end -}}

{{- define "altimanager.pvc" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- include "altimanager.fullname" . }}
{{- end }}
{{- end }}

{{/*
Configuration env.json
*/}}
{{- define "altimanager.envJson" -}}
{
  "PSK_TMP_WORKING_DIR": "tmp",
  "PSK_CONFIG_LOCATION": "../apihub-root/external-volume/config",
  "DEV": false,
  "VAULT_DOMAIN": {{ required "config.vaultDomain must be set" .Values.config.vaultDomain | quote}},
  "BUILD_SECRET_KEY": {{ required "config.buildSecretKey must be set" .Values.config.buildSecretKey | quote}},
  "BDNS_ROOT_HOSTS": "http://127.0.0.1:8080",
  "OPENDSU_ENABLE_DEBUG": true
}
{{- end }}

{{/*
Configuration apihub.json.
Taken from https://github.com/pharmaledgerassoc/altimanager-workspace/blob/v1.3.1/apihub-root/external-volume/config/apihub.json
*/}}
{{- define "altimanager.apihubJson" -}}
{
  "storage": "../apihub-root",
  "port": 8080,
  "preventRateLimit": true,
  "activeComponents": [
    "virtualMQ",
    "messaging",
    "notifications",
    "filesManager",
    "bdns",
    "bricksLedger",
    "bricksFabric",
    "bricking",
    "anchoring",
    "dsu-wizard",
    "gtin-dsu-wizard",
    "acdc-reporting",
    "debugLogger",
    "mq",
    "secrets",
    "iframe",
    "stream",
    "staticServer"
  ],
  "componentsConfig": {
    "staticServer": {
      "excludedFiles": [
        ".*.secret"
      ]
    },
    "bricking": {},
    "anchoring": {}
  },
  "responseHeaders": {
    "X-Frame-Options": "SAMEORIGIN",
    "X-XSS-Protection": "1; mode=block"
  },
  "enableRequestLogger": true,
  "enableJWTAuthorisation": false,
  "enableOAuth": false,
  "enableLocalhostAuthorization": false,
  "serverAuthentication": false,
  "skipJWTAuthorisation": [
    "/assets",
    "/helloworld-wallet",
    "/resources",
    "/bdns",
    "/anchor/epi",
    "/anchor/default",
    "/anchor/vault",
    "/bricking",
    "/bricksFabric",
    "/bricksledger",
    "/create-channel",
    "/forward-zeromq",
    "/send-message",
    "/receive-message",
    "/files",
    "/notifications",
    "/mq"
  ]

}

{{- end }}

{{/*
The Name of the ConfigMap for the Build Info Data
*/}}
{{- define "altimanager.configMapBuildInfoName" -}}
{{- printf "%s-%s" (include "altimanager.fullname" .) "build-info" }}
{{- end }}

