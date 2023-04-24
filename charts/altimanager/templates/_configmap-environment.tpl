{{- /*
Template for Configmap.

Arguments to be passed are 
- $ (index 0)
- . (index 1)
- suffix (index 2)
- dictionary (index 3) for annotations used for defining helm hooks.

See https://blog.flant.com/advanced-helm-templating/
*/}}
{{- define "altimanager.configmap-environment" -}}
{{- $ := index . 0 }}
{{- $suffix := index . 2 }}
{{- $annotations := index . 3 }}
{{- with index . 1 }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "altimanager.fullname" . }}-environment{{ $suffix | default "" }}
  namespace: {{ template "altimanager.namespace" . }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "altimanager.labels" . | nindent 4 }}
data:
  # https://github.com/pharmaledgerassoc/altimanager-workspace/blob/v1.3.0/trust-loader-config/demiurge-wallet/loader/environment.js
  environment.js: |-
{{- if .Values.config.environmentJs }}
{{ .Values.config.environmentJs | indent 4 }}
{{- else }}
    export default {
      "appName": "Demiurge",
      "vault": "server",
      "agent": "browser",
      "system":   "any",
      "browser":  "any",
      "mode": "autologin",
      "vaultDomain":  {{ required "config.vaultDomain must be set" .Values.config.vaultDomain | quote }},
      "didDomain":  {{ required "config.vaultDomain must be set" .Values.config.vaultDomain | quote }},
      "enclaveType":"WalletDBEnclave",
      "companyName": {{ required "config.companyName must be set" .Values.config.companyName | quote }},
      "sw": false,
      "pwa": false
    }
{{- end }}
{{- end }}
{{- end }}