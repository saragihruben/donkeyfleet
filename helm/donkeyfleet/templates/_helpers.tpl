{{/* Base name */}}
{{- define "donkeyfleet.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Fully qualified app name */}}
{{- define "donkeyfleet.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart label */}}
{{- define "donkeyfleet.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels */}}
{{- define "donkeyfleet.labels" -}}
helm.sh/chart: {{ include "donkeyfleet.chart" . }}
{{ include "donkeyfleet.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Selector labels (immutable set) */}}
{{- define "donkeyfleet.selectorLabels" -}}
app.kubernetes.io/name: {{ include "donkeyfleet.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* ServiceAccount name */}}
{{- define "donkeyfleet.serviceAccountName" -}}
{{- include "donkeyfleet.fullname" . -}}
{{- end -}}

{{/* Vault-auth ServiceAccount name (Vault's token reviewer). Overridable so it can match the
     reviewer SA your Vault kubernetes auth method is already configured against. */}}
{{- define "donkeyfleet.vaultAuthServiceAccountName" -}}
{{- if .Values.vaultKubernetesAuth.serviceAccountName -}}
{{- .Values.vaultKubernetesAuth.serviceAccountName | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-vault-auth" (include "donkeyfleet.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Bundled Postgres name */}}
{{- define "donkeyfleet.postgres.fullname" -}}
{{- printf "%s-postgres" (include "donkeyfleet.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Secret name — created by the chart or an existing one the operator manages */}}
{{- define "donkeyfleet.secretName" -}}
{{- if .Values.secret.create -}}
{{- printf "%s-secrets" (include "donkeyfleet.fullname" .) -}}
{{- else -}}
{{- required "secret.existingSecret is required when secret.create is false" .Values.secret.existingSecret -}}
{{- end -}}
{{- end -}}

{{/* Database JDBC URL — bundled Postgres unless config.database.url overrides it */}}
{{- define "donkeyfleet.databaseUrl" -}}
{{- if .Values.config.database.url -}}
{{- .Values.config.database.url -}}
{{- else if .Values.postgres.enabled -}}
{{- printf "jdbc:postgresql://%s:5432/%s" (include "donkeyfleet.postgres.fullname" .) .Values.postgres.database -}}
{{- else -}}
{{- required "config.database.url is required when postgres.enabled is false" .Values.config.database.url -}}
{{- end -}}
{{- end -}}
