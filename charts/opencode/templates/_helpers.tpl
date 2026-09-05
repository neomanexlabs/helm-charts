{{/*
==============================================================================
OPENCODE HELM CHART - HELPER TEMPLATES
Naming helpers, label generators, and image helpers for the OpenCode server.
==============================================================================
*/}}

{{/*
Chart name.
*/}}
{{- define "opencode.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fullname based on release name.
When release is "opencode-prod" and chart is "opencode", this yields "opencode-prod".
This becomes the Service DNS name that clients connect to.
*/}}
{{- define "opencode.fullname" -}}
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
Chart name and version for chart label.
*/}}
{{- define "opencode.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
==============================================================================
LABEL HELPERS
==============================================================================
*/}}

{{/*
Common labels applied to all resources.
*/}}
{{- define "opencode.labels" -}}
helm.sh/chart: {{ include "opencode.chart" . }}
{{ include "opencode.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (subset used in matchLabels).
*/}}
{{- define "opencode.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opencode.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
==============================================================================
API INGRESS BASIC-AUTH SECRET NAME HELPER
==============================================================================
Name of the K8s Secret holding the nginx htpasswd entry for the machine-only
api ingress. Honors an explicit override, else "<fullname>-api-basic-auth".
*/}}
{{- define "opencode.apiBasicAuthSecretName" -}}
{{- default (printf "%s-api-basic-auth" (include "opencode.fullname" .)) .Values.apiIngress.basicAuth.secretName }}
{{- end }}

{{/*
==============================================================================
WORKSPACE LABEL HELPERS
==============================================================================
*/}}

{{/*
Workspace selector labels — selectorLabels plus a workspace discriminator.
Expects a dict with keys: root (top-level context $) and ws (workspace entry).
*/}}
{{- define "opencode.workspaceSelectorLabels" -}}
{{ include "opencode.selectorLabels" .root }}
opencode.neomanex.com/workspace: {{ .ws.name }}
{{- end }}

{{/*
==============================================================================
IMAGE HELPERS
==============================================================================
*/}}

{{/*
Build full image reference (global).
*/}}
{{- define "opencode.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default "latest") }}
{{- end }}

{{/*
Build full image reference for a workspace.
Expects a dict with keys: root (top-level context $) and ws (workspace entry).
Uses per-workspace image.tag if set, else falls back to global .Values.image.tag.
*/}}
{{- define "opencode.workspaceImage" -}}
{{- $globalTag := .root.Values.image.tag | default "latest" }}
{{- $wsTag := $globalTag }}
{{- if .ws.image }}
  {{- if .ws.image.tag }}
    {{- $wsTag = .ws.image.tag }}
  {{- end }}
{{- end }}
{{- printf "%s:%s" .root.Values.image.repository $wsTag }}
{{- end }}

{{/*
==============================================================================
SERVICE ACCOUNT HELPER
==============================================================================
*/}}

{{/*
ServiceAccount name for CronJob kubectl exec.
*/}}
{{- define "opencode.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opencode.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
