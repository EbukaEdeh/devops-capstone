{{/*
Common naming and label helpers.
*/}}

{{- define "voting-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "voting-app.fullname" -}}
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

{{- define "voting-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "voting-app.labels" -}}
helm.sh/chart: {{ include "voting-app.chart" . }}
app.kubernetes.io/name: {{ include "voting-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: voting-app
{{- end }}

{{- define "voting-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "voting-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "voting-app.componentLabels" -}}
{{ include "voting-app.labels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "voting-app.componentSelectorLabels" -}}
{{ include "voting-app.selectorLabels" .context }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "voting-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "voting-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "voting-app.dbSecretName" -}}
{{- .Values.postgresql.auth.existingSecret | required "postgresql.auth.existingSecret is required" }}
{{- end }}

{{- define "voting-app.databaseHost" -}}
{{- if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" (include "voting-app.fullname" .) }}
{{- else }}
{{- required "externalDatabase.host is required when postgresql.enabled=false" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{- define "voting-app.redisUrl" -}}
{{- if .Values.redis.enabled }}
{{- printf "redis://%s-redis:6379/0" (include "voting-app.fullname" .) }}
{{- else }}
{{- required "redis.url is required when redis.enabled=false" .Values.redis.url }}
{{- end }}
{{- end }}

{{- define "voting-app.otelEnv" -}}
- name: OTEL_SERVICE_NAME
  value: {{ .service | quote }}
- name: OTEL_SDK_DISABLED
  value: {{ not .context.Values.otel.enabled | quote }}
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: {{ .context.Values.otel.endpoint | quote }}
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "http/protobuf"
- name: OTEL_METRICS_EXPORTER
  value: "none"
- name: OTEL_LOGS_EXPORTER
  value: "none"
- name: OTEL_RESOURCE_ATTRIBUTES
  value: {{ printf "deployment.environment=%s,service.namespace=voting-app" .context.Values.otel.environment | quote }}
- name: LOG_LEVEL
  value: {{ .context.Values.logLevel | default "INFO" | quote }}
{{- end }}

{{- define "voting-app.dbEnv" -}}
- name: POSTGRES_HOST
  value: {{ include "voting-app.databaseHost" . | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.externalDatabase.port | default 5432 | quote }}
- name: POSTGRES_DB
  value: {{ .Values.postgresql.auth.database | quote }}
- name: POSTGRES_USER
  value: {{ .Values.postgresql.auth.username | quote }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "voting-app.dbSecretName" . }}
      key: {{ .Values.postgresql.auth.passwordKey | quote }}
{{- end }}
