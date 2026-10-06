# CloudNativePG Cluster Helm Chart

Runs a [CloudNativePG](https://cloudnative-pg.io) PostgreSQL cluster on Kubernetes from one values file: the `Cluster`, optional PgBouncer poolers, scheduled backups to GCS, S3 or Azure, PodMonitors, NetworkPolicies and External Secrets Operator integration. Its defaults are tuned for clusters that run on spot or preemptible nodes, where a node can disappear at any minute: immediate failover, PVC reuse, soft anti-affinity, and an optional recovery job that rebuilds replicas a reclaimed node left broken. It is for teams who already run the CloudNativePG operator and want one chart for every database instead of hand-written manifests per cluster. It is published by [Neomanex](https://neomanex.com), an AI-native company, and it is the chart we run our own production PostgreSQL on.

```sh
helm install my-postgres oci://ghcr.io/neomanexlabs/charts/cnpg-cluster --version 1.0.0 -f my-values.yaml
```

## Add the repository

```sh
helm repo add neomanexlabs https://neomanexlabs.github.io/helm-charts
helm repo update
helm install my-postgres neomanexlabs/cnpg-cluster --version 1.0.0 -f my-values.yaml
```

Both install paths serve the identical package.

## Requirements

| Requirement | Detail |
|-------------|--------|
| Kubernetes | 1.25 or newer, with a StorageClass that supports dynamic provisioning |
| CloudNativePG operator | Installed cluster-wide before this chart. The chart renders `postgresql.cnpg.io/v1` resources only and does not install CRDs. Tested with operator 1.28 and 1.29 |
| External Secrets Operator | Optional, only for `externalSecrets.enabled` |
| Prometheus Operator | Optional, only for the PodMonitor that `monitoring.enabled` renders |
| Object storage | Optional, only for backups: a GCS bucket, an S3 (or S3-compatible) bucket, or an Azure Blob Storage container |

## Quick start

[`examples/minimal.yaml`](examples/minimal.yaml) installs a single instance with no backups and no pooler. [`examples/ha-spot.yaml`](examples/ha-spot.yaml) installs the production topology: three instances, a read-write pooler, daily backups to GCS through Workload Identity and the replica recovery job.

```sh
helm template my-postgres neomanexlabs/cnpg-cluster -f examples/ha-spot.yaml
```

Read the render before installing. The high availability example names a placeholder bucket and service account; replace both.

### Credentials

By default CloudNativePG creates the database owner with a generated password and stores it in the `<cluster>-app` secret. To choose the password, supply it through `auth.appUser.password`, `auth.appUser.existingSecret` or `externalSecrets.appUserSecret`, and name that secret in `bootstrap.initdb.secret.name` (`<cluster>-app-user` unless you set `auth.appUser.existingSecret`). `auth.appUser.username` must match `bootstrap.initdb.owner`. When `bootstrap.initdb.secret` is set, the operator uses that secret instead of generating `<cluster>-app`.

Superuser access is off by default, as in CloudNativePG. With `auth.superuser.enabled: true` and nothing else, the operator generates the `<cluster>-superuser` secret. Set `auth.superuser.password`, `auth.superuser.existingSecret` or `externalSecrets.superuserSecret` to supply it yourself.

### Client access

When `postgresql.pg_hba` is empty, the cluster accepts scram-sha-256 password logins from the RFC 1918 private ranges only. Set your own list to replace that rule set entirely.

## How it works

The chart renders one CloudNativePG `Cluster` plus the optional resources you turn on. Four behaviours are worth knowing:

- **Spot-friendly defaults.** `failover.delay: 0` promotes a replica as soon as the primary is lost, `maintenance.reusePVC: true` lets an instance come back on its own volume after a node is reclaimed, and anti-affinity is `preferred` so a smaller node pool still schedules every instance. Set `affinity.tolerations` and `pooler.defaultTolerations` to the taint your spot nodes carry.
- **Replica recovery.** A node reclaimed mid-write can leave a replica in CrashLoopBackOff on a damaged volume, and CloudNativePG keeps restarting it. With `replicaRecovery.enabled`, a CronJob finds replicas past `replicaRecovery.minRestarts` restarts, deletes the pod and its PVCs, and lets the operator rebuild the replica from the primary. It never touches the current primary. The same job deletes instance pods that are Pending, no longer declared by the cluster, and missing their PVC, because those can never schedule. Every run ends with a verdict and fails when the read-write Service has no endpoints, so a broken database shows up as a failed Job.
- **Poolers.** Each entry in `pooler.instances` renders a PgBouncer `Pooler` of type `rw` or `ro`. Pooler pods take their resources, affinity, tolerations, node selector, priority class and topology spread from the `pooler.default*` values unless the entry overrides them. Pooler pods carry the chart version label, so any chart upgrade rolls them; PostgreSQL instance pods are not restarted by a chart upgrade.
- **Backups.** `backup.*` configures the Barman object store on the cluster (WAL archiving plus base backups) and `scheduledBackup.*` renders the `ScheduledBackup`. GCS can authenticate through GKE Workload Identity (`backup.gcs.gkeEnvironment: true` plus the service account annotation), S3 and Azure through a secret the chart can create or one you name.

## Examples

| File | What it installs |
|------|------------------|
| [`examples/minimal.yaml`](examples/minimal.yaml) | One instance, no backups, no pooler, no PodDisruptionBudget |
| [`examples/ha-spot.yaml`](examples/ha-spot.yaml) | Three instances on tainted spot nodes, read-write pooler, daily GCS backups through Workload Identity, replica recovery |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity.additionalPodAffinity | object | `{}` | Additional pod affinity rules |
| affinity.additionalPodAntiAffinity | object | `{}` | Additional pod anti-affinity rules |
| affinity.enablePodAntiAffinity | bool | `true` | Enable pod anti-affinity (spread instances across nodes) REQUIRED for HA on preemptible nodes |
| affinity.nodeAffinity | object | `{}` | Node affinity rules |
| affinity.nodeSelector | object | `{}` | Node selector labels |
| affinity.podAntiAffinityType | string | `"preferred"` | Anti-affinity type preferred = best-effort (allows scheduling even if not perfect) required = strict (pods won't schedule if can't spread) Use 'preferred' for preemptible nodes to avoid scheduling issues |
| affinity.tolerations | list | `[]` | Pod tolerations |
| affinity.topologyKey | string | `"kubernetes.io/hostname"` | Topology key for anti-affinity kubernetes.io/hostname = different nodes (recommended for preemptible) topology.kubernetes.io/zone = different zones |
| auth.appUser | object | `{"enabled":true,"existingSecret":"","password":"","username":"app"}` | Application user configuration |
| auth.appUser.enabled | bool | `true` | Enable application user |
| auth.appUser.existingSecret | string | `""` | Use existing secret for app user credentials |
| auth.appUser.password | string | `""` | Password (use existingSecret or externalSecrets for production) |
| auth.appUser.username | string | `"app"` | Username |
| auth.superuser | object | `{"enabled":false,"existingSecret":"","password":""}` | Superuser (postgres) configuration |
| auth.superuser.enabled | bool | `false` | Enable superuser access. Off by default, as in CloudNativePG. When on and no password, existingSecret or external secret is given, the operator generates the `<cluster>-superuser` secret itself. |
| auth.superuser.existingSecret | string | `""` | Use existing secret for superuser credentials |
| auth.superuser.password | string | `""` | Password (use existingSecret or externalSecrets for production) |
| backup.azure | object | `{"container":"","credentials":{"connectionString":""},"inheritFromAzureAD":false,"path":"","storageAccount":""}` | Azure Blob Storage configuration |
| backup.azure.container | string | `""` | Container name |
| backup.azure.credentials | object | `{"connectionString":""}` | Credentials |
| backup.azure.inheritFromAzureAD | bool | `false` | Use Azure AD authentication |
| backup.azure.path | string | `""` | Path within container |
| backup.azure.storageAccount | string | `""` | Storage account name. Builds the destination https://<storageAccount>.blob.core.windows.net/<container>/<path> |
| backup.credentials | object | `{"createSecret":false,"existingSecret":""}` | Credentials secret configuration |
| backup.credentials.createSecret | bool | `false` | Create secret from values |
| backup.credentials.existingSecret | string | `""` | Use existing secret |
| backup.data | object | `{"compression":"gzip","encryption":"","jobs":2}` | Base backup configuration |
| backup.data.compression | string | `"gzip"` | Compression: gzip, bzip2, snappy |
| backup.data.encryption | string | `""` | Encryption algorithm |
| backup.data.jobs | int | `2` | Number of parallel backup jobs |
| backup.destinationPath | string | `""` | Custom destination path (overrides provider-specific path) |
| backup.enabled | bool | `false` | Enable backups |
| backup.gcs | object | `{"bucket":"","credentials":{"key":"gcp-credentials.json"},"gkeEnvironment":false,"path":""}` | GCS (Google Cloud Storage) configuration |
| backup.gcs.bucket | string | `""` | GCS bucket name |
| backup.gcs.credentials | object | `{"key":"gcp-credentials.json"}` | Explicit credentials (if not using Workload Identity) |
| backup.gcs.gkeEnvironment | bool | `false` | Authenticate with GKE Workload Identity instead of a credentials secret |
| backup.gcs.path | string | `""` | Path within bucket (defaults to cluster name) |
| backup.provider | string | `""` | Backup provider: gcs, s3, or azure |
| backup.retentionPolicy | string | `"30d"` | Retention policy (e.g., "30d", "7d") |
| backup.s3 | object | `{"bucket":"","credentials":{"accessKeyId":"","secretAccessKey":""},"endpoint":"","path":"","region":""}` | S3 configuration |
| backup.s3.bucket | string | `""` | S3 bucket name |
| backup.s3.credentials | object | `{"accessKeyId":"","secretAccessKey":""}` | Credentials (use externalSecrets for production) |
| backup.s3.endpoint | string | `""` | Custom endpoint (for S3-compatible storage) |
| backup.s3.path | string | `""` | Path within bucket |
| backup.s3.region | string | `""` | AWS region |
| backup.target | string | `"prefer-standby"` | Backup target: primary or prefer-standby |
| backup.wal | object | `{"compression":"gzip","encryption":"","maxParallel":8}` | WAL archiving configuration |
| backup.wal.compression | string | `"gzip"` | Compression: gzip, bzip2, snappy |
| backup.wal.encryption | string | `""` | Encryption algorithm |
| backup.wal.maxParallel | int | `8` | Maximum parallel WAL archiving jobs |
| bootstrap.initdb | object | `{"database":"app","options":[],"owner":"app","postInitApplicationSQL":[],"postInitApplicationSQLRefs":{"configMapRefs":[],"secretRefs":[]},"postInitSQL":[],"postInitTemplateSQL":[],"secret":{}}` | initdb configuration (new cluster) |
| bootstrap.initdb.database | string | `"app"` | Default database name |
| bootstrap.initdb.options | list | `[]` | Additional initdb options |
| bootstrap.initdb.owner | string | `"app"` | Default database owner |
| bootstrap.initdb.postInitApplicationSQL | list | `[]` | SQL to run in app database after initdb |
| bootstrap.initdb.postInitApplicationSQLRefs | object | `{"configMapRefs":[],"secretRefs":[]}` | References to ConfigMaps/Secrets with SQL scripts |
| bootstrap.initdb.postInitSQL | list | `[]` | SQL to run after initdb |
| bootstrap.initdb.postInitTemplateSQL | list | `[]` | SQL to run in template1 after initdb |
| bootstrap.initdb.secret | object | `{}` | Secret with the owner credentials (basic-auth, username equal to `owner`). When empty, the operator generates the owner password in `<cluster>-app`. To bootstrap with a secret from auth.appUser or externalSecrets.appUserSecret, name it here: `<cluster>-app-user` unless auth.appUser.existingSecret is set. |
| bootstrap.method | string | `"initdb"` | Bootstrap method: initdb, recovery, or pg_basebackup |
| bootstrap.pg_basebackup | object | `{"database":"","owner":"","source":""}` | pg_basebackup configuration (clone from existing cluster) |
| bootstrap.pg_basebackup.source | string | `""` | Source cluster name |
| bootstrap.recovery | object | `{"backup":{},"recoveryTarget":{},"source":""}` | recovery configuration (restore from backup) |
| bootstrap.recovery.backup | object | `{}` | Backup to restore from |
| bootstrap.recovery.recoveryTarget | object | `{}` | Recovery target configuration |
| bootstrap.recovery.source | string | `""` | Source cluster name (for external cluster recovery) |
| certificates.clientCASecret | string | `""` | Client CA secret name |
| certificates.replicationTLSSecret | string | `""` | Replication TLS secret name |
| certificates.serverCASecret | string | `""` | Server CA secret name |
| certificates.serverTLSSecret | string | `""` | Server TLS secret name |
| cluster | object | `{"description":"","enablePDB":true,"name":"","primaryUpdateMethod":"switchover","primaryUpdateStrategy":"unsupervised","smartShutdownTimeout":180,"startDelay":30,"stopDelay":30}` | Cluster-level settings |
| cluster.description | string | `""` | Cluster description for documentation |
| cluster.enablePDB | bool | `true` | Manage PodDisruptionBudget resources (set false for dev/staging) |
| cluster.name | string | `""` | Custom cluster name (defaults to release name) |
| cluster.primaryUpdateMethod | string | `"switchover"` | Primary update method: switchover (graceful) or restart |
| cluster.primaryUpdateStrategy | string | `"unsupervised"` | Primary update strategy: unsupervised (automatic) or supervised (manual) |
| cluster.smartShutdownTimeout | int | `180` | Smart shutdown timeout in seconds |
| cluster.startDelay | int | `30` | Seconds to wait before starting PostgreSQL |
| cluster.stopDelay | int | `30` | Seconds to wait before stopping PostgreSQL |
| commonAnnotations | object | `{}` | Additional annotations for all resources |
| commonLabels | object | `{}` | Additional labels for all resources |
| env | list | `[]` | Additional environment variables |
| envFrom | list | `[]` | Additional environment variables from ConfigMaps/Secrets |
| ephemeralVolumesSizeLimit | object | `{}` | Ephemeral volume size limits |
| externalClusters | list | `[]` | External cluster definitions (for recovery or replica clusters) |
| externalSecrets.appUserSecret | object | `{}` | App user secret reference |
| externalSecrets.aws | object | `{"auth":{},"region":"","role":"","service":"SecretsManager"}` | AWS Secrets Manager configuration |
| externalSecrets.aws.auth | object | `{}` | Authentication configuration |
| externalSecrets.aws.region | string | `""` | AWS region |
| externalSecrets.aws.role | string | `""` | IAM role ARN |
| externalSecrets.aws.service | string | `"SecretsManager"` | AWS service: SecretsManager or ParameterStore |
| externalSecrets.azure | object | `{"auth":{},"tenantId":"","vaultUrl":""}` | Azure Key Vault configuration |
| externalSecrets.azure.auth | object | `{}` | Authentication configuration |
| externalSecrets.azure.tenantId | string | `""` | Tenant ID |
| externalSecrets.azure.vaultUrl | string | `""` | Key Vault URL |
| externalSecrets.enabled | bool | `false` | Enable External Secrets integration |
| externalSecrets.gcp | object | `{"auth":{},"projectID":""}` | GCP Secret Manager configuration |
| externalSecrets.gcp.auth | object | `{}` | Authentication configuration |
| externalSecrets.gcp.projectID | string | `""` | GCP project ID |
| externalSecrets.provider | string | `""` | Secrets provider: gcpsm, aws, vault or azurekv. Required when enabled. |
| externalSecrets.refreshInterval | string | `"6h"` | Refresh interval for secrets |
| externalSecrets.secretStore | object | `{"annotations":{},"kind":"SecretStore","name":""}` | Use existing SecretStore |
| externalSecrets.secretStore.annotations | object | `{}` | Annotations for SecretStore |
| externalSecrets.secretStore.kind | string | `"SecretStore"` | SecretStore kind |
| externalSecrets.secretStore.name | string | `""` | Existing SecretStore name (if set, won't create new one) |
| externalSecrets.superuserSecret | object | `{}` | Superuser secret reference |
| externalSecrets.vault | object | `{"auth":{},"path":"secret","server":"","version":"v2"}` | HashiCorp Vault configuration |
| externalSecrets.vault.auth | object | `{}` | Authentication configuration |
| externalSecrets.vault.path | string | `"secret"` | Secrets path |
| externalSecrets.vault.server | string | `""` | Vault server URL |
| externalSecrets.vault.version | string | `"v2"` | API version |
| failover.delay | int | `0` | Delay before starting failover (seconds) 0 = immediate failover (recommended for preemptible nodes) |
| failover.switchoverDelay | int | `60` | Switchover delay - time for graceful shutdown Higher = safer for data, but longer RTO |
| fullnameOverride | string | `""` | Override the full resource name |
| image.name | string | `""` | Full image name (overrides repository and tag) |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"ghcr.io/cloudnative-pg/postgresql"` | Image repository |
| image.tag | string | `""` | Image tag (defaults to postgresql.version) |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries |
| instances | int | `3` | Number of PostgreSQL instances (1 = standalone, 3+ = HA) For HA on preemptible nodes, use 3 instances minimum |
| maintenance.inProgress | bool | `false` | Node maintenance in progress |
| maintenance.reusePVC | bool | `true` | Reuse PVCs after node preemption (CRITICAL for preemptible nodes) When true, pods can reattach to existing PVCs on new nodes |
| managed.enabled | bool | `false` | Enable managed roles |
| managed.roles | list | `[]` | Role definitions |
| monitoring.customQueriesConfigMap | list | `[]` | Custom queries ConfigMap reference |
| monitoring.customQueriesSecret | list | `[]` | Custom queries Secret reference |
| monitoring.enabled | bool | `false` | Enable monitoring |
| monitoring.podMonitor | object | `{"annotations":{},"enabled":true,"honorLabels":false,"interval":"30s","labels":{},"metricRelabelings":[],"namespace":"","namespaceSelector":{},"relabelings":[],"scheme":"","scrapeTimeout":"10s","tlsConfig":{},"useClusterSpec":false}` | PodMonitor configuration |
| monitoring.podMonitor.annotations | object | `{}` | Annotations for PodMonitor |
| monitoring.podMonitor.enabled | bool | `true` | Create PodMonitor resource |
| monitoring.podMonitor.honorLabels | bool | `false` | Honor labels from scraped metrics |
| monitoring.podMonitor.interval | string | `"30s"` | Scrape interval |
| monitoring.podMonitor.labels | object | `{}` | Additional labels for PodMonitor |
| monitoring.podMonitor.metricRelabelings | list | `[]` | Metric relabeling rules |
| monitoring.podMonitor.namespace | string | `""` | Namespace for PodMonitor (defaults to release namespace) |
| monitoring.podMonitor.namespaceSelector | object | `{}` | Namespace selector |
| monitoring.podMonitor.relabelings | list | `[]` | Relabeling rules |
| monitoring.podMonitor.scheme | string | `""` | Scheme for scraping |
| monitoring.podMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| monitoring.podMonitor.tlsConfig | object | `{}` | TLS configuration |
| monitoring.podMonitor.useClusterSpec | bool | `false` | Use cluster spec instead of separate PodMonitor |
| monitoring.poolerPodMonitor | object | `{"enabled":true,"interval":"30s","labels":{},"scrapeTimeout":"10s"}` | Pooler PodMonitor configuration |
| monitoring.poolerPodMonitor.enabled | bool | `true` | Create PodMonitor for poolers |
| monitoring.poolerPodMonitor.interval | string | `"30s"` | Scrape interval |
| monitoring.poolerPodMonitor.labels | object | `{}` | Additional labels |
| monitoring.poolerPodMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| nameOverride | string | `""` | Override the chart name |
| networkPolicy.additionalIngress | list | `[]` | Additional ingress rules |
| networkPolicy.allowPrometheus | bool | `true` | Allow Prometheus scraping |
| networkPolicy.allowedCIDRs | list | `[]` | Allow traffic from CIDRs |
| networkPolicy.allowedNamespaces | list | `[]` | Allow traffic from specified namespaces |
| networkPolicy.allowedPodLabels | object | `{}` | Allow traffic from pods with these labels |
| networkPolicy.egress | object | `{"additionalEgress":[],"allowCloudProvider":true,"allowDNS":true,"enabled":true}` | Egress configuration |
| networkPolicy.egress.additionalEgress | list | `[]` | Additional egress rules |
| networkPolicy.egress.allowCloudProvider | bool | `true` | Allow cloud provider access (for backups) |
| networkPolicy.egress.allowDNS | bool | `true` | Allow DNS resolution |
| networkPolicy.egress.enabled | bool | `true` | Enable egress rules |
| networkPolicy.enabled | bool | `false` | Enable NetworkPolicy |
| networkPolicy.poolerEnabled | bool | `true` | Enable NetworkPolicy for pooler |
| networkPolicy.prometheusNamespace | string | `""` | Prometheus namespace |
| networkPolicy.prometheusPodSelector | object | `{}` | Prometheus pod selector |
| podAnnotations | object | `{}` | Annotations added to every PostgreSQL pod (CloudNativePG inheritedMetadata) |
| pooler.defaultAffinity | object | `{}` | Default affinity for pooler pods |
| pooler.defaultNodeSelector | object | `{}` | Default node selector for pooler pods |
| pooler.defaultPodAnnotations | object | `{"cluster-autoscaler.kubernetes.io/safe-to-evict":"true"}` | Default annotations for pooler (pgbouncer) pod templates. safe-to-evict lets the cluster autoscaler drain a pooler off an underutilized autoscaled node (its emptyDir is runtime socket/config, not data). Without it, poolers pin a fallback node and block scale-down. Per-instance `podAnnotations` on an entry overrides this default. |
| pooler.defaultPriorityClassName | string | `""` | Default priorityClassName for pooler pods. Per-instance `priorityClassName` on an entry overrides it. Empty = key not rendered (cluster default priority). Poolers sit on the request path; a cluster that defines a high PriorityClass for request-path workloads sets it here so a pooler replacement never queues behind ordinary workloads after a node loss. |
| pooler.defaultResources | object | `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Default resources for pooler pods |
| pooler.defaultTolerations | list | `[]` | Default tolerations for pooler pods |
| pooler.defaultTopologySpreadConstraints | list | `[]` | Default topologySpreadConstraints for pooler pods, rendered verbatim (no tpl). Per-instance `topologySpreadConstraints` on an entry overrides it. Empty = key not rendered. One default can serve both rw and ro poolers by selecting every pooler pod and splitting by the pod's own poolerName value. Never repeat a matchLabelKeys key inside labelSelector: the apiserver merges matchLabelKeys into the selector at pod creation and rejects the duplicate.   - maxSkew: 1     topologyKey: kubernetes.io/hostname     whenUnsatisfiable: DoNotSchedule     labelSelector:       matchLabels: {cnpg.io/podRole: pooler}     matchLabelKeys: [cnpg.io/poolerName, pod-template-hash] |
| pooler.enabled | bool | `false` | Enable PgBouncer pooler |
| pooler.instances | list | `[]` | Pooler instances configuration |
| postgresql.enableAlterSystem | bool | `false` | Enable ALTER SYSTEM command |
| postgresql.ldap | object | `{}` | LDAP configuration (optional) |
| postgresql.parameters | object | `{"checkpoint_completion_target":"0.9","effective_io_concurrency":"200","log_min_duration_statement":"1000","log_statement":"ddl","maintenance_work_mem":"64MB","max_connections":"100","max_slot_wal_keep_size":"10GB","max_wal_size":"4GB","min_wal_size":"1GB","random_page_cost":"1.1","wal_buffers":"16MB","work_mem":"4MB"}` | PostgreSQL parameters (postgresql.conf) Memory settings are auto-tuned if not specified |
| postgresql.pg_hba | list | `[]` | pg_hba.conf entries (client authentication). When empty, the chart renders three rules that allow scram-sha-256 password logins from the RFC 1918 private ranges (10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16). Set your own list to replace them entirely. |
| postgresql.synchronous | object | `{"dataDurability":"preferred","enabled":false,"failoverQuorum":false,"method":"any","number":1}` | Synchronous replication configuration Recommended for critical workloads requiring zero data loss |
| postgresql.synchronous.dataDurability | string | `"preferred"` | Data durability: required (strict) or preferred (self-healing) Use 'preferred' for preemptible nodes to allow self-healing |
| postgresql.synchronous.enabled | bool | `false` | Enable synchronous replication |
| postgresql.synchronous.failoverQuorum | bool | `false` | Enable failover quorum for enhanced data safety |
| postgresql.synchronous.method | string | `"any"` | Method: any (quorum) or first (priority) |
| postgresql.synchronous.number | int | `1` | Number of synchronous standbys |
| postgresql.version | string | `"17"` | PostgreSQL major version |
| priorityClassName | string | `""` | Priority class for pods |
| replicaRecovery.enabled | bool | `false` | Enable automatic replica recovery |
| replicaRecovery.image | string | `"alpine/k8s:1.33.5"` | Image for the recovery job. It needs the Kubernetes CLI and a POSIX shell. |
| replicaRecovery.minRestarts | int | `5` | Minimum restart count before triggering recovery Prevents recovering pods that are just slow to start |
| replicaRecovery.schedule | string | `"*/5 * * * *"` | CronJob schedule (default: every 5 minutes) |
| replicationSlots.highAvailability.enabled | bool | `true` | Enable HA replication slots (REQUIRED for HA) |
| replicationSlots.highAvailability.slotPrefix | string | `"_cnpg_"` | Slot name prefix |
| replicationSlots.synchronizeReplicas | object | `{"enabled":true,"excludePatterns":[]}` | Synchronize user-defined replication slots |
| replicationSlots.updateInterval | int | `30` | Update interval for slot synchronization (seconds) |
| resources | object | `{"limits":{"cpu":"2000m","memory":"2Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits for PostgreSQL pods |
| scheduledBackup.backupOwnerReference | string | `"self"` | Owner reference: none, self, or cluster |
| scheduledBackup.enabled | bool | `false` | Enable scheduled backups |
| scheduledBackup.immediate | bool | `false` | Take immediate backup on creation |
| scheduledBackup.method | string | `""` | Backup method: barmanObjectStore, volumeSnapshot, or plugin |
| scheduledBackup.online | string | `""` | Online backup (for volumeSnapshot) |
| scheduledBackup.onlineConfiguration | object | `{}` | Online backup settings for volumeSnapshot (immediateCheckpoint, waitForArchive) |
| scheduledBackup.pluginConfiguration | object | `{}` | Plugin configuration |
| scheduledBackup.schedule | string | `"0 0 2 * * *"` | Cron schedule (6-field format with seconds) "0 0 2 * * *" = Daily at 2:00 AM |
| scheduledBackup.suspend | bool | `false` | Suspend scheduling |
| scheduledBackup.target | string | `""` | Backup target: primary or prefer-standby |
| serviceAccount.annotations | object | `{}` | Annotations (e.g., for Workload Identity) |
| serviceAccount.create | bool | `true` | Create service account |
| serviceAccount.name | string | `""` | Service account name |
| storage.pvcTemplate | object | `{}` | Custom PVC template |
| storage.resizeInUseVolumes | bool | `true` | Allow online volume resize |
| storage.size | string | `"10Gi"` | Storage size (required) |
| storage.storageClass | string | `""` | Storage class (empty = cluster default) |
| topologySpreadConstraints | list | `[]` | Topology spread constraints |
| walStorage | object | `{"enabled":false,"resizeInUseVolumes":true,"size":"2Gi","storageClass":""}` | Separate WAL storage (recommended for high-performance workloads) |
| walStorage.enabled | bool | `false` | Enable separate WAL storage |
| walStorage.resizeInUseVolumes | bool | `true` | Allow online volume resize |
| walStorage.size | string | `"2Gi"` | WAL storage size |
| walStorage.storageClass | string | `""` | WAL storage class |

## Support

Issues are the support channel: https://github.com/neomanexlabs/helm-charts/issues. For anything else, including security reports, use https://neomanex.com/contact.

## About Neomanex

Neomanex is an AI-native company. We run our own business on an AI Operating Model,
publish the evidence, and help other companies become AI native: agents, operations,
and the infrastructure underneath them, built and governed in production.

This project is part of that work. It is the same code we run ourselves.

- Website: https://neomanex.com
- Work with us: https://neomanex.com/contact
- Products: [ConvOps](https://convops.app) (AI-first operations) and [Gnosari](https://gnosari.com) (conversational data collection: AI agents that turn conversations into structured data)
