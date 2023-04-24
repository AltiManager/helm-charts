{{- /*
Template for Configmap.

Arguments to be passed are 
- $ (index 0)
- . (index 1)
- suffix (index 2)
- dictionary (index 3) for annotations used for defining helm hooks.

See https://blog.flant.com/advanced-helm-templating/
*/}}
{{- define "altimanager.configmap-domains" -}}
{{- $ := index . 0 }}
{{- $suffix := index . 2 }}
{{- $annotations := index . 3 }}
{{- with index . 1 }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "altimanager.fullname" . }}-domains{{ $suffix | default "" }}
  namespace: {{ template "altimanager.namespace" . }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "altimanager.labels" . | nindent 4 }}
data:
  # Mapped to https://github.com/pharmaledgerassoc/altimanager-workspace/tree/v1.3.0/apihub-root/external-volume/config/domains
  # e.g. 'vault.companyname.json'
  {{ required "config.vaultDomain must be set" .Values.config.vaultDomain }}.json: |-
{{- if .Values.config.vaultDomainConfigJson }}
{{ .Values.config.vaultDomainConfigJson | indent 4 }}
{{- else }}
    {
      "anchoring": {
        "type": "FS",
         "option": {
           "enableBricksLedger": false
         }
      },
      "skipOAuth": [
        "/bricking/{{ required "config.vaultDomain must be set" .Values.config.vaultDomain }}/get-brick"
      ],
      "enable": ["mq", "enclave"]
    }
{{- end }}

{{- end }}
{{- end }}