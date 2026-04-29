{{/* Generate a standard name */}}
{{- define "banking.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Standard Labels */}}
{{- define "banking.labels" -}}
app: {{ include "banking.fullname" . }}
env: {{ required "environment is required" .Values.environment }}
team: {{ required "team is required" .Values.team }}
managed-by: {{ .Release.Service }}
{{- end -}}