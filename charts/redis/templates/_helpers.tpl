{{/*
Expand the name of the chart.
*/}}
{{- define "redis.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "redis.fullname" -}}
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
{{- define "redis.chart" -}}
{{- printf "%s-%s" .Chart.Name (regexReplaceAll "\\+.*" .Chart.Version "") | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "redis.labels" -}}
helm.sh/chart: {{ include "redis.chart" . }}
{{ include "redis.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "redis.selectorLabels" -}}
app.kubernetes.io/name: {{ include "redis.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "redis.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "redis.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Redis image name
*/}}
{{- define "redis.image" -}}
{{- $registryName := .Values.image.registry -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.tag | toString -}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- $registryName = .Values.global.imageRegistry -}}
    {{- end -}}
{{- end -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper Redis metrics exporter image name
*/}}
{{- define "redis.metrics.image" -}}
{{- $registryName := .Values.metrics.image.registry -}}
{{- $repositoryName := .Values.metrics.image.repository -}}
{{- $tag := .Values.metrics.image.tag | toString -}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- $registryName = .Values.global.imageRegistry -}}
    {{- end -}}
{{- end -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper Sentinel image name
*/}}
{{- define "redis.sentinel.image" -}}
{{- $registryName := .Values.sentinel.image.registry -}}
{{- $repositoryName := .Values.sentinel.image.repository -}}
{{- $tag := .Values.sentinel.image.tag | toString -}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- $registryName = .Values.global.imageRegistry -}}
    {{- end -}}
{{- end -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "redis.imagePullSecrets" -}}
{{- $pullSecrets := list }}

{{- if .Values.global }}
  {{- range .Values.global.imagePullSecrets }}
    {{- $pullSecrets = append $pullSecrets . }}
  {{- end }}
{{- end }}

{{- range .Values.image.pullSecrets }}
  {{- $pullSecrets = append $pullSecrets . }}
{{- end }}

{{- if (not (empty $pullSecrets)) }}
imagePullSecrets:
{{- range $pullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return the Redis password
*/}}
{{- define "redis.password" -}}
{{- if .Values.global }}
    {{- if .Values.global.redis }}
        {{- if .Values.global.redis.password }}
            {{- .Values.global.redis.password }}
        {{- else if .Values.auth.password }}
            {{- .Values.auth.password }}
        {{- end }}
    {{- else if .Values.auth.password }}
        {{- .Values.auth.password }}
    {{- end }}
{{- else if .Values.auth.password }}
    {{- .Values.auth.password }}
{{- end }}
{{- end }}

{{/*
Get the password secret name
*/}}
{{- define "redis.secretName" -}}
{{- if .Values.auth.existingSecret }}
    {{- .Values.auth.existingSecret }}
{{- else }}
    {{- printf "%s" (include "redis.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Get the password secret key
*/}}
{{- define "redis.secretPasswordKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.existingSecretPasswordKey }}
    {{- .Values.auth.existingSecretPasswordKey }}
{{- else }}
    {{- "redis-password" }}
{{- end }}
{{- end }}

{{/*
Get the Sentinel password secret key
*/}}
{{- define "redis.secretSentinelPasswordKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.existingSecretSentinelPasswordKey }}
    {{- .Values.auth.existingSecretSentinelPasswordKey }}
{{- else }}
    {{- "redis-sentinel-password" }}
{{- end }}
{{- end }}

{{/*
Return whether Redis authentication is enabled
*/}}
{{- define "redis.auth.enabled" -}}
{{- if or .Values.auth.enabled (include "redis.password" .) }}
    {{- true }}
{{- end }}
{{- end }}

{{/*
Return the master service name
*/}}
{{- define "redis.master.serviceName" -}}
{{- printf "%s-master" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the replica service name
*/}}
{{- define "redis.replica.serviceName" -}}
{{- printf "%s-replicas" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the headless service name
*/}}
{{- define "redis.headless.serviceName" -}}
{{- printf "%s-headless" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the Sentinel service name
*/}}
{{- define "redis.sentinel.serviceName" -}}
{{- printf "%s-sentinel" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the master StatefulSet name
*/}}
{{- define "redis.master.statefulsetName" -}}
{{- printf "%s-master" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the replica StatefulSet name
*/}}
{{- define "redis.replica.statefulsetName" -}}
{{- printf "%s-replicas" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the Sentinel StatefulSet name
*/}}
{{- define "redis.sentinel.statefulsetName" -}}
{{- printf "%s-sentinel" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the ConfigMap name for Redis configuration
*/}}
{{- define "redis.configmapName" -}}
{{- if .Values.existingConfigmap }}
    {{- .Values.existingConfigmap }}
{{- else }}
    {{- printf "%s-configuration" (include "redis.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the ConfigMap name for Sentinel configuration
*/}}
{{- define "redis.sentinel.configmapName" -}}
{{- printf "%s-sentinel-configuration" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the storage class for persistence
*/}}
{{- define "redis.storageClass" -}}
{{- if .Values.global }}
    {{- if .Values.global.storageClass }}
        {{- .Values.global.storageClass }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Renders a value that contains template.
Usage:
{{ include "redis.tplValue" (dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "redis.tplValue" -}}
    {{- if typeIs "string" .value }}
        {{- tpl .value .context }}
    {{- else }}
        {{- tpl (.value | toYaml) .context }}
    {{- end }}
{{- end -}}

{{/*
Compile all values validation into a single failure message
*/}}
{{- define "redis.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "redis.validateValues.architecture" .) -}}
{{- $messages := append $messages (include "redis.validateValues.sentinel" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/*
Validate architecture value. The chart implements standalone and replication
only, so any other value fails the render instead of installing a release with
no Redis in it.
*/}}
{{- define "redis.validateValues.architecture" -}}
{{- if and (ne .Values.architecture "standalone") (ne .Values.architecture "replication") -}}
redis: architecture
    Invalid architecture selected. Valid values are "standalone" and "replication".
    Current value: {{ .Values.architecture }}
{{- end -}}
{{- end -}}

{{/*
Validate sentinel configuration
*/}}
{{- define "redis.validateValues.sentinel" -}}
{{- if and .Values.sentinel.enabled (ne .Values.architecture "replication") -}}
redis: sentinel
    Sentinel can only be enabled with architecture: replication
    Current architecture: {{ .Values.architecture }}
{{- end -}}
{{- if and .Values.sentinel.enabled (lt (.Values.sentinel.replicaCount | int) 3) -}}
redis: sentinel.replicaCount
    For reliable failover, use at least 3 Sentinel instances
    Current value: {{ .Values.sentinel.replicaCount }}
{{- end -}}
{{- if and .Values.sentinel.enabled (gt (.Values.sentinel.quorum | int) (.Values.sentinel.replicaCount | int)) -}}
redis: sentinel.quorum
    sentinel.quorum cannot be greater than sentinel.replicaCount
    Current values: quorum {{ .Values.sentinel.quorum }}, replicaCount {{ .Values.sentinel.replicaCount }}
{{- end -}}
{{- end -}}

{{/*
Return Redis container port
*/}}
{{- define "redis.containerPort" -}}
6379
{{- end }}

{{/*
Return Sentinel container port
*/}}
{{- define "redis.sentinel.containerPort" -}}
26379
{{- end }}

{{/*
Return metrics container port
*/}}
{{- define "redis.metrics.containerPort" -}}
9121
{{- end }}

{{/*
Return the scripts ConfigMap name
*/}}
{{- define "redis.scripts.configmapName" -}}
{{- printf "%s-scripts" (include "redis.fullname" .) }}
{{- end }}

{{/*
Return the master host for connection
*/}}
{{- define "redis.masterHost" -}}
{{- if .Values.sentinel.enabled }}
{{- printf "%s-master.%s.svc.cluster.local" (include "redis.fullname" .) .Release.Namespace }}
{{- else }}
{{- printf "%s-master-0.%s.%s.svc.cluster.local" (include "redis.fullname" .) (include "redis.headless.serviceName" .) .Release.Namespace }}
{{- end }}
{{- end }}

{{/*
Return the initial master host for replica bootstrap
*/}}
{{- define "redis.initialMasterHost" -}}
{{- printf "%s-master-0.%s.%s.svc.cluster.local" (include "redis.fullname" .) (include "redis.headless.serviceName" .) .Release.Namespace }}
{{- end }}

{{/*
Return the Sentinel hosts for connection
*/}}
{{- define "redis.sentinelHosts" -}}
{{- $fullname := include "redis.fullname" . }}
{{- $headless := include "redis.headless.serviceName" . }}
{{- $namespace := .Release.Namespace }}
{{- $replicas := .Values.sentinel.replicaCount | int }}
{{- range $i := until $replicas }}
{{- printf "%s-sentinel-%d.%s.%s.svc.cluster.local:26379" $fullname $i $headless $namespace }}
{{- if lt (add $i 1) $replicas }},{{ end }}
{{- end }}
{{- end }}

{{/*
Return Redis connection URL for applications
*/}}
{{- define "redis.connectionUrl" -}}
{{- if .Values.sentinel.enabled }}
redis-sentinel://{{ include "redis.sentinelHosts" . }}/0?sentinelMasterId={{ .Values.sentinel.masterSet }}
{{- else }}
redis://{{ include "redis.masterHost" . }}:6379/0
{{- end }}
{{- end }}
