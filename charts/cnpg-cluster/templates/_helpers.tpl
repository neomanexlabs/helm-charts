{{/*
================================================================================
CloudNativePG Cluster Helm Chart - Template Helpers
================================================================================
Enterprise-grade helper functions for PostgreSQL cluster deployment.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "cnpg-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified cluster name.
We truncate at 63 chars because some Kubernetes name fields are limited to this.
*/}}
{{- define "cnpg-cluster.fullname" -}}
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
Create the cluster resource name.
This is the name used for the CloudNativePG Cluster CRD.
*/}}
{{- define "cnpg-cluster.clusterName" -}}
{{- .Values.cluster.name | default (include "cnpg-cluster.fullname" .) }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
Semver build metadata (+...) is dropped, so a chart packaged with a build suffix
never changes the label and never rolls the pooler pods.
*/}}
{{- define "cnpg-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name (.Chart.Version | splitList "+" | first) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels for all resources.
*/}}
{{- define "cnpg-cluster.labels" -}}
helm.sh/chart: {{ include "cnpg-cluster.chart" . }}
{{ include "cnpg-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cloudnative-pg
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels for identifying resources.
*/}}
{{- define "cnpg-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cnpg-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations for all resources.
*/}}
{{- define "cnpg-cluster.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Build the full PostgreSQL image name.
Format: repository:tag
*/}}
{{- define "cnpg-cluster.imageName" -}}
{{- $repository := .Values.image.repository | default "ghcr.io/cloudnative-pg/postgresql" }}
{{- $tag := .Values.image.tag | default (printf "%s" .Values.postgresql.version) }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}

{{/*
Return the service account name to use.
*/}}
{{- define "cnpg-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cnpg-cluster.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the superuser secret name.
*/}}
{{- define "cnpg-cluster.superuserSecretName" -}}
{{- if .Values.auth.superuser.existingSecret }}
{{- .Values.auth.superuser.existingSecret }}
{{- else }}
{{- printf "%s-superuser" (include "cnpg-cluster.clusterName" .) }}
{{- end }}
{{- end }}

{{/*
Non-empty when a superuser secret will exist for the cluster to reference:
an existing secret, a password in values, or an ExternalSecret.
*/}}
{{- define "cnpg-cluster.superuserSecretProvided" -}}
{{- if .Values.auth.superuser.existingSecret }}true
{{- else if and .Values.externalSecrets.enabled .Values.externalSecrets.superuserSecret }}true
{{- else if and (not .Values.externalSecrets.enabled) .Values.auth.superuser.password }}true
{{- end }}
{{- end }}

{{/*
Return the app user secret name.
*/}}
{{- define "cnpg-cluster.appUserSecretName" -}}
{{- if .Values.auth.appUser.existingSecret }}
{{- .Values.auth.appUser.existingSecret }}
{{- else }}
{{- printf "%s-app-user" (include "cnpg-cluster.clusterName" .) }}
{{- end }}
{{- end }}

{{/*
Build the backup destination path.
Supports: s3://, gs:// and Azure Blob Storage (https://<account>.blob.core.windows.net)
*/}}
{{- define "cnpg-cluster.backupDestinationPath" -}}
{{- if .Values.backup.destinationPath }}
{{- .Values.backup.destinationPath }}
{{- else if eq .Values.backup.provider "gcs" }}
{{- printf "gs://%s/%s" .Values.backup.gcs.bucket (.Values.backup.gcs.path | default (include "cnpg-cluster.clusterName" .)) }}
{{- else if eq .Values.backup.provider "s3" }}
{{- printf "s3://%s/%s" .Values.backup.s3.bucket (.Values.backup.s3.path | default (include "cnpg-cluster.clusterName" .)) }}
{{- else if eq .Values.backup.provider "azure" }}
{{- printf "https://%s.blob.core.windows.net/%s/%s" (.Values.backup.azure.storageAccount | required "backup.azure.storageAccount is required for the azure provider") .Values.backup.azure.container (.Values.backup.azure.path | default (include "cnpg-cluster.clusterName" .)) }}
{{- end }}
{{- end }}

{{/*
Return the backup credentials secret name.
*/}}
{{- define "cnpg-cluster.backupSecretName" -}}
{{- if .Values.backup.credentials.existingSecret }}
{{- .Values.backup.credentials.existingSecret }}
{{- else }}
{{- printf "%s-backup-creds" (include "cnpg-cluster.clusterName" .) }}
{{- end }}
{{- end }}

{{/*
Return pooler name with suffix.
*/}}
{{- define "cnpg-cluster.poolerName" -}}
{{- $clusterName := include "cnpg-cluster.clusterName" . }}
{{- printf "%s-%s" $clusterName .type }}
{{- end }}

{{/*
Generate PostgreSQL HBA rules.
*/}}
{{- define "cnpg-cluster.pgHba" -}}
{{- if .Values.postgresql.pg_hba }}
pg_hba:
{{- range .Values.postgresql.pg_hba }}
  - {{ . | quote }}
{{- end }}
{{- else }}
pg_hba:
  - host all all 10.0.0.0/8 scram-sha-256
  - host all all 172.16.0.0/12 scram-sha-256
  - host all all 192.168.0.0/16 scram-sha-256
{{- end }}
{{- end }}

{{/*
Calculate shared_buffers if not explicitly set.
Default: 25% of memory limit, minimum 128MB.
*/}}
{{- define "cnpg-cluster.sharedBuffers" -}}
{{- if .Values.postgresql.parameters.shared_buffers }}
{{- .Values.postgresql.parameters.shared_buffers }}
{{- else if .Values.resources.limits.memory }}
{{- $memoryLimit := .Values.resources.limits.memory }}
{{- $memoryMB := 0 }}
{{- if hasSuffix "Gi" $memoryLimit }}
{{- $memoryMB = mul (trimSuffix "Gi" $memoryLimit | int) 1024 }}
{{- else if hasSuffix "Mi" $memoryLimit }}
{{- $memoryMB = trimSuffix "Mi" $memoryLimit | int }}
{{- end }}
{{- $sharedBuffers := div $memoryMB 4 }}
{{- if lt $sharedBuffers 128 }}
{{- printf "128MB" }}
{{- else }}
{{- printf "%dMB" $sharedBuffers }}
{{- end }}
{{- else }}
{{- printf "256MB" }}
{{- end }}
{{- end }}

{{/*
Calculate effective_cache_size if not explicitly set.
Default: 75% of memory limit.
*/}}
{{- define "cnpg-cluster.effectiveCacheSize" -}}
{{- if .Values.postgresql.parameters.effective_cache_size }}
{{- .Values.postgresql.parameters.effective_cache_size }}
{{- else if .Values.resources.limits.memory }}
{{- $memoryLimit := .Values.resources.limits.memory }}
{{- $memoryMB := 0 }}
{{- if hasSuffix "Gi" $memoryLimit }}
{{- $memoryMB = mul (trimSuffix "Gi" $memoryLimit | int) 1024 }}
{{- else if hasSuffix "Mi" $memoryLimit }}
{{- $memoryMB = trimSuffix "Mi" $memoryLimit | int }}
{{- end }}
{{- $effectiveCache := div (mul $memoryMB 3) 4 }}
{{- printf "%dMB" $effectiveCache }}
{{- else }}
{{- printf "768MB" }}
{{- end }}
{{- end }}

{{/*
Validate values and generate warnings.
*/}}
{{- define "cnpg-cluster.validateValues" -}}
{{- $messages := list -}}

{{/* Validate instances for HA */}}
{{- if and (gt (int .Values.instances) 1) (not .Values.affinity.enablePodAntiAffinity) }}
{{- $messages = append $messages "WARNING: Running multiple instances without pod anti-affinity may result in all instances on the same node" }}
{{- end }}

{{/* Validate backup configuration */}}
{{- if and .Values.backup.enabled (not .Values.backup.provider) (not .Values.backup.destinationPath) }}
{{- $messages = append $messages "ERROR: backup.enabled=true requires either backup.provider or backup.destinationPath" }}
{{- end }}

{{/* Validate synchronous replication */}}
{{- if .Values.postgresql.synchronous.enabled }}
{{- if ge (int .Values.postgresql.synchronous.number) (int .Values.instances) }}
{{- $messages = append $messages "ERROR: synchronous.number must be less than instances count" }}
{{- end }}
{{- end }}

{{/* Output messages */}}
{{- if $messages }}
{{- range $messages }}
{{- if hasPrefix "ERROR:" . }}
{{- fail . }}
{{- else }}
{{- printf "\n# %s" . }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return the appropriate API version for PodMonitor.
*/}}
{{- define "cnpg-cluster.podMonitor.apiVersion" -}}
{{- print "monitoring.coreos.com/v1" }}
{{- end }}

{{/*
Return the appropriate API version for NetworkPolicy.
*/}}
{{- define "cnpg-cluster.networkPolicy.apiVersion" -}}
{{- print "networking.k8s.io/v1" }}
{{- end }}

{{/*
Generate the affinity configuration for the cluster.
Optimized for preemptible nodes with proper anti-affinity.
*/}}
{{- define "cnpg-cluster.affinity" -}}
{{- if or .Values.affinity.enablePodAntiAffinity .Values.affinity.nodeAffinity .Values.affinity.additionalPodAffinity .Values.affinity.additionalPodAntiAffinity }}
affinity:
  enablePodAntiAffinity: {{ .Values.affinity.enablePodAntiAffinity }}
  topologyKey: {{ .Values.affinity.topologyKey | default "kubernetes.io/hostname" }}
  podAntiAffinityType: {{ .Values.affinity.podAntiAffinityType | default "preferred" }}
  {{- with .Values.affinity.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity.nodeAffinity }}
  nodeAffinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity.additionalPodAffinity }}
  additionalPodAffinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity.additionalPodAntiAffinity }}
  additionalPodAntiAffinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Generate topology spread constraints.
*/}}
{{- define "cnpg-cluster.topologySpreadConstraints" -}}
{{- if .Values.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml .Values.topologySpreadConstraints | nindent 2 }}
{{- end }}
{{- end }}
