{{- /*
Template for SecretProviderClass.

Arguments to be passed are 
- $ (index 0)
- . (index 1)
- suffix (index 2)
- dictionary (index 3) for annotations used for defining helm hooks.

See https://blog.flant.com/advanced-helm-templating/
*/}}
{{- define "altimanager.secretProviderClass" -}}
{{- $ := index . 0 }}
{{- $suffix := index . 2 }}
{{- $annotations := index . 3 }}
{{- with index . 1 }}
apiVersion: {{ .Values.secretProviderClass.apiVersion }}
kind: SecretProviderClass
metadata:
  name: {{ include "altimanager.fullname" . }}{{ $suffix | default "" }}
  namespace: {{ template "altimanager.namespace" . }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "altimanager.labels" . | nindent 4 }}
spec:
  {{- toYaml .Values.secretProviderClass.spec | nindent 2 }}

{{- end }}
{{- end }}
