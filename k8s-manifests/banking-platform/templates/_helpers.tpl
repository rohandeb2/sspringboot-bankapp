{{/* Generate a standard name */}}
{{- define "banking.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Standard Labels */}}
{{- define "banking.labels" -}}
app: {{ include "banking.fullname" . }}
env: {{ .Values.environment }}
team: {{ .Values.team }}
managed-by: {{ .Release.Service }}
{{- end -}}