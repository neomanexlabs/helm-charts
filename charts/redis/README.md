# Redis Helm Chart

Runs [Redis](https://redis.io) on Kubernetes with Sentinel high availability: one master, N replicas, and a Sentinel quorum that promotes a replica when the master stops answering. What sets it apart is what happens next. The master pod reclaims its role once it is healthy again, readiness is role aware so a demoted pod leaves the master Service, and Sentinel keeps its view of the cluster across restarts. It is for teams who want a Sentinel setup that converges back to a known topology without an operator watching it. It is published by [Neomanex](https://neomanex.com), an AI-native company, and it is the chart we run our own production Redis on.

```sh
helm install redis oci://ghcr.io/neomanexlabs/charts/redis --version 1.1.0 -f my-values.yaml
```

## Add the repository

```sh
helm repo add neomanexlabs https://neomanexlabs.github.io/helm-charts
helm repo update
helm install redis neomanexlabs/redis --version 1.1.0 -f my-values.yaml
```

Both install paths serve the identical package.

## Requirements

| Requirement | Detail |
|-------------|--------|
| Kubernetes | 1.25 or newer, with a default StorageClass that supports dynamic provisioning when persistence is enabled |
| External Secrets Operator | Optional. With `externalSecrets.enabled: false` (the default) the chart manages its own Secret. Turn it on to have the passwords delivered from an external store |
| Prometheus Operator | Optional, and only for `metrics.serviceMonitor.enabled`. The exporter sidecar itself needs nothing |
| Container image | `redis:7.4.2-alpine` by default. Any Redis image with `redis-cli`, `redis-sentinel` and a shell works |

## Quick start

[`examples/minimal.yaml`](examples/minimal.yaml) installs a single standalone instance. [`examples/ha-sentinel.yaml`](examples/ha-sentinel.yaml) installs the high availability topology: one master, two replicas, three Sentinels, the metrics exporter, and a configuration that refuses writes while no replica is connected.

```sh
helm template redis neomanexlabs/redis -f examples/ha-sentinel.yaml
```

Read the render before installing. Both examples carry placeholder passwords; replace them, or leave `auth.password` empty and let the chart generate one.

### Passwords

With `auth.enabled: true` and no `auth.password` and no `auth.existingSecret`, the chart generates a 32 character password on the first install and reuses it on every upgrade: it reads the Secret it created last time rather than rotating a credential the running pods still authenticate with. Set `auth.password` to choose your own, or set `auth.existingSecret` to a Secret you manage and the chart renders no Secret at all.

## How it works

The master runs as its own StatefulSet, the replicas as another, and Sentinel as a third. Four behaviours are worth knowing:

- **Automatic failback.** After a failover, the master pod starts as a replica, waits for replication to catch up, and then asks Sentinel to hand the master role back. A watchdog sidecar (`master.watchdog`) repeats that check while the pod runs, so a demotion after boot is corrected too.
- **Role-aware readiness.** The readiness probe checks the Redis role, not just a PING. A master pod that has been demoted fails readiness and leaves the master Service endpoints, so clients are never routed to a node that cannot accept writes. A replica must also have its replication link up.
- **Persisted Sentinel state.** With `sentinel.persistence.enabled` each Sentinel keeps its config file on a volume, so a restarted quorum still knows which node is master. Without it, a simultaneous restart of every Sentinel loses that knowledge.
- **Split-brain guard.** `configuration.min-replicas-to-write` and `min-replicas-max-lag` make the master refuse writes once no replica is acknowledging, so a partitioned master cannot accept writes that the failover would discard. The high availability example sets both.

## Examples

| File | What it installs |
|------|------------------|
| [`examples/minimal.yaml`](examples/minimal.yaml) | One standalone Redis, persistence on, no Sentinel, no metrics |
| [`examples/ha-sentinel.yaml`](examples/ha-sentinel.yaml) | One master, two replicas, three Sentinels, watchdog, metrics exporter, split-brain guard |

## Not implemented

These are deliberately absent rather than half-wired, so the values reference below lists nothing that does nothing:

| Not implemented | Detail |
|-----------------|--------|
| TLS | Redis is not configured to serve or verify TLS. Terminate elsewhere, or open an issue |
| Redis Cluster mode | `architecture` accepts `standalone` and `replication` only. Any other value fails the render instead of installing a release with no Redis in it |
| Scheduled backups | Persistence and RDB or AOF settings are exposed; nothing copies snapshots off the cluster |

If you need one of these, open an issue and say how you would use it. That is more useful than a values key that renders nothing.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| architecture | string | `"standalone"` | Deployment architecture: `standalone` (single instance) or `replication` (master plus replicas, with optional Sentinel). Any other value fails the render. |
| auth.enabled | bool | `true` | Require a password on every Redis and Sentinel connection |
| auth.existingSecret | string | `""` | Name of a Secret you manage yourself that already holds the passwords. When set, the chart renders no Secret of its own. |
| auth.existingSecretPasswordKey | string | `"redis-password"` | Key inside auth.existingSecret that holds the Redis password |
| auth.existingSecretSentinelPasswordKey | string | `"redis-sentinel-password"` | Key inside auth.existingSecret that holds the Sentinel password |
| auth.password | string | `""` | Redis password. Leave empty and the chart generates one on first install and reuses it on every upgrade, so nothing well known ships as a default. Ignored when auth.existingSecret is set. |
| auth.sentinel | bool | `true` | Require a password on Sentinel connections as well (Sentinel only) |
| auth.sentinelPassword | string | `""` | Sentinel password. Same generation rule as auth.password. |
| configuration.active-defrag-cycle-max | int | `25` | Maximum CPU percentage spent on defragmentation |
| configuration.active-defrag-cycle-min | int | `1` | Minimum CPU percentage spent on defragmentation |
| configuration.active-defrag-ignore-bytes | string | `"100mb"` | Fragmentation bytes below which defragmentation stays off |
| configuration.active-defrag-max-scan-fields | int | `1000` | Fields scanned per defragmentation cycle |
| configuration.active-defrag-threshold-lower | int | `10` | Fragmentation percentage that starts defragmentation |
| configuration.active-defrag-threshold-upper | int | `100` | Fragmentation percentage at which defragmentation runs at full effort |
| configuration.activedefrag | string | `"no"` | Enable active defragmentation |
| configuration.aof-load-truncated | string | `"yes"` | Load a truncated append only file instead of refusing to start |
| configuration.aof-use-rdb-preamble | string | `"yes"` | Write an RDB preamble at the head of the append only file |
| configuration.appendfilename | string | `"appendonly.aof"` | Name of the append only file |
| configuration.appendfsync | string | `"everysec"` | How often the append only file is flushed to disk |
| configuration.appendonly | string | `"no"` | Enable the append only file |
| configuration.auto-aof-rewrite-min-size | string | `"64mb"` | Minimum append only file size before a rewrite is considered |
| configuration.auto-aof-rewrite-percentage | int | `100` | Growth percentage that triggers an append only file rewrite |
| configuration.custom | string | `""` | Full redis.conf content. When set, every key below is ignored. |
| configuration.daemonize | string | `"no"` | Run Redis in the background, always no inside a container |
| configuration.databases | int | `16` | Number of logical databases |
| configuration.dbfilename | string | `"dump.rdb"` | Name of the RDB file |
| configuration.dir | string | `"/data"` | Working directory, also where the RDB and AOF files live |
| configuration.enabled | bool | `true` | Render the generated redis.conf. With false the file is left empty. |
| configuration.hash-max-ziplist-entries | int | `512` | Hash entries kept in the compact encoding |
| configuration.hash-max-ziplist-value | int | `64` | Hash value size kept in the compact encoding |
| configuration.hll-sparse-max-bytes | int | `3000` | Bytes below which a HyperLogLog uses the sparse encoding |
| configuration.latency-monitor-threshold | int | `0` | Milliseconds above which an event is recorded by the latency monitor, 0 disables |
| configuration.lazyfree-lazy-eviction | string | `"no"` | Free evicted values in a background thread |
| configuration.lazyfree-lazy-expire | string | `"no"` | Free expired values in a background thread |
| configuration.lazyfree-lazy-server-del | string | `"no"` | Free values replaced by a write in a background thread |
| configuration.list-compress-depth | int | `0` | List nodes left uncompressed at each end |
| configuration.list-max-ziplist-size | int | `-2` | List node sizing for the compact encoding |
| configuration.loglevel | string | `"notice"` | Log level |
| configuration.lua-time-limit | int | `5000` | Milliseconds a Lua script may run before it can be killed |
| configuration.maxmemory | string | `""` | Memory ceiling, for example 384mb. Empty means no limit. |
| configuration.maxmemory-policy | string | `"noeviction"` | Eviction policy once maxmemory is reached |
| configuration.maxmemory-samples | int | `5` | Keys sampled per eviction decision |
| configuration.min-replicas-max-lag | string | `""` | Seconds of replica lag tolerated by min-replicas-to-write |
| configuration.min-replicas-to-write | string | `""` | Replicas that must be connected before the master accepts writes |
| configuration.no-appendfsync-on-rewrite | string | `"no"` | Skip fsync while a rewrite is running |
| configuration.notify-keyspace-events | string | `""` | Keyspace notification classes, empty disables notifications |
| configuration.pidfile | string | `"/var/run/redis.pid"` | Path of the pid file |
| configuration.protected-mode | string | `"no"` | Accept connections from outside localhost |
| configuration.rdbchecksum | string | `"yes"` | Checksum RDB files |
| configuration.rdbcompression | string | `"yes"` | Compress RDB files |
| configuration.repl-disable-tcp-nodelay | string | `"no"` | Disable TCP_NODELAY on the replication link |
| configuration.repl-diskless-sync | string | `"no"` | Send the replication stream straight to the socket instead of a disk file |
| configuration.repl-diskless-sync-delay | int | `5` | Seconds to wait for more replicas before a diskless sync starts |
| configuration.replica-lazy-flush | string | `"no"` | Flush a replica dataset in a background thread on full resync |
| configuration.replica-priority | int | `100` | Promotion preference, lower wins. The chart manages this per pod. |
| configuration.replica-read-only | string | `"yes"` | Refuse writes sent directly to a replica |
| configuration.replica-serve-stale-data | string | `"yes"` | Serve reads from a replica whose link to the master is down |
| configuration.save | string | `"900 1 300 10 60 10000"` | RDB snapshot rules, empty disables snapshots |
| configuration.set-max-intset-entries | int | `512` | Integer set entries kept in the compact encoding |
| configuration.slowlog-log-slower-than | int | `10000` | Microseconds above which a command is logged as slow |
| configuration.slowlog-max-len | int | `128` | Entries kept in the slow log |
| configuration.stop-writes-on-bgsave-error | string | `"yes"` | Refuse writes when the last background save failed |
| configuration.stream-node-max-bytes | int | `4096` | Bytes per stream radix tree node |
| configuration.stream-node-max-entries | int | `100` | Entries per stream radix tree node |
| configuration.tcp-backlog | int | `511` | Pending connection backlog |
| configuration.tcp-keepalive | int | `300` | TCP keepalive interval in seconds |
| configuration.timeout | int | `0` | Seconds before an idle client is closed, 0 disables |
| configuration.zset-max-ziplist-entries | int | `128` | Sorted set entries kept in the compact encoding |
| configuration.zset-max-ziplist-value | int | `64` | Sorted set value size kept in the compact encoding |
| existingConfigmap | string | `""` | Name of a ConfigMap holding your own redis.conf. When set, the chart renders no configuration ConfigMap of its own. |
| externalSecrets.enabled | bool | `false` | Render an ExternalSecret that delivers the Redis and Sentinel passwords |
| externalSecrets.redisPasswordSecret.key | string | `""` | Remote key holding the Redis password |
| externalSecrets.redisPasswordSecret.property | string | `""` | Property inside the remote key, when the remote value is structured |
| externalSecrets.refreshInterval | string | `"6h"` | How often the operator re-reads the remote values |
| externalSecrets.secretStore.kind | string | `"ClusterSecretStore"` | Kind of the store: `ClusterSecretStore` or `SecretStore` |
| externalSecrets.secretStore.name | string | `"cluster-secret-store"` | Name of the SecretStore or ClusterSecretStore to read from |
| externalSecrets.sentinelPasswordSecret.key | string | `""` | Remote key holding the Sentinel password |
| externalSecrets.sentinelPasswordSecret.property | string | `""` | Property inside the remote key, when the remote value is structured |
| fullnameOverride | string | `""` | Override the fully qualified release name used in resource names |
| global.imagePullSecrets | list | `[]` | Image pull secret names added to every pod |
| global.imageRegistry | string | `""` | Image registry applied to every image in the chart (empty uses each image's own registry) |
| global.redis.password | string | `""` | Redis password, takes precedence over auth.password |
| global.storageClass | string | `""` | StorageClass applied to every PersistentVolumeClaim unless a component overrides it |
| image.pullPolicy | string | `"IfNotPresent"` | Redis image pull policy |
| image.pullSecrets | list | `[]` | Image pull secret names for the Redis image |
| image.registry | string | `"docker.io"` | Redis image registry |
| image.repository | string | `"redis"` | Redis image repository |
| image.tag | string | `"7.4.2-alpine"` | Redis image tag |
| master.affinity | object | `{}` | Affinity rules for the master pod |
| master.command | list | `[]` | Replaces the master start command entirely |
| master.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation inside the Redis container |
| master.containerSecurityContext.capabilities.drop | list | `["ALL"]` | Linux capabilities dropped from the Redis container |
| master.containerSecurityContext.enabled | bool | `true` | Apply the master container security context |
| master.containerSecurityContext.readOnlyRootFilesystem | bool | `true` | Mount the Redis container root filesystem read only |
| master.containerSecurityContext.runAsNonRoot | bool | `true` | Refuse to start the Redis container as root |
| master.containerSecurityContext.runAsUser | int | `1001` | User the Redis container runs as |
| master.count | int | `1` | Number of master pods, normally 1 |
| master.customLivenessProbe | object | `{}` | Replaces the built in liveness probe entirely |
| master.customReadinessProbe | object | `{}` | Replaces the built in readiness probe entirely |
| master.customStartupProbe | object | `{}` | Replaces the built in startup probe entirely |
| master.extraEnvVars | list | `[]` | Extra environment variables for the Redis container |
| master.extraEnvVarsCM | string | `""` | Name of a ConfigMap with extra environment variables for the Redis container |
| master.extraEnvVarsSecret | string | `""` | Name of a Secret with extra environment variables for the Redis container |
| master.extraVolumeMounts | list | `[]` | Extra volume mounts on the Redis container |
| master.extraVolumes | list | `[]` | Extra volumes on the master pod |
| master.initContainers | list | `[]` | Extra init containers on the master pod |
| master.lifecycleHooks | object | `{}` | Lifecycle hooks for the Redis container |
| master.livenessProbe.enabled | bool | `true` | Enable the master liveness probe |
| master.livenessProbe.failureThreshold | int | `5` | Failures tolerated before the container restarts |
| master.livenessProbe.initialDelaySeconds | int | `20` | Delay before the first liveness check |
| master.livenessProbe.periodSeconds | int | `5` | Interval between liveness checks |
| master.livenessProbe.successThreshold | int | `1` | Successes needed to pass liveness |
| master.livenessProbe.timeoutSeconds | int | `5` | Liveness check timeout |
| master.nodeSelector | object | `{}` | Node selector for the master pod |
| master.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the master volume |
| master.persistence.annotations | object | `{}` | Annotations on the master volume claim |
| master.persistence.dataSource | object | `{}` | Data source to clone the master volume from |
| master.persistence.enabled | bool | `true` | Give the master a PersistentVolumeClaim. With false the data volume is an emptyDir. |
| master.persistence.selector | object | `{}` | Label selector for a pre-provisioned master volume |
| master.persistence.size | string | `"8Gi"` | Size of the master volume |
| master.persistence.storageClass | string | `""` | StorageClass for the master volume |
| master.podAnnotations | object | `{}` | Extra annotations on the master StatefulSet and its pods |
| master.podDisruptionBudget.enabled | bool | `true` | Create a PodDisruptionBudget for the master |
| master.podDisruptionBudget.maxUnavailable | string | `""` | Maximum unavailable master pods during a voluntary disruption |
| master.podDisruptionBudget.minAvailable | int | `1` | Minimum available master pods during a voluntary disruption |
| master.podLabels | object | `{}` | Extra labels on the master StatefulSet and its pods |
| master.podSecurityContext.enabled | bool | `true` | Apply the master pod security context |
| master.podSecurityContext.fsGroup | int | `1001` | Volume ownership group for the master pod |
| master.podSecurityContext.runAsNonRoot | bool | `true` | Refuse to start the master pod as root |
| master.podSecurityContext.runAsUser | int | `1001` | User the master pod runs as |
| master.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` | Seccomp profile for the master pod |
| master.priorityClassName | string | `""` | PriorityClass for the master pod |
| master.readinessProbe.enabled | bool | `true` | Enable the master readiness probe. It is role aware: a master pod demoted by Sentinel fails readiness and leaves the master Service. |
| master.readinessProbe.failureThreshold | int | `5` | Failures tolerated before the pod leaves the Service endpoints |
| master.readinessProbe.initialDelaySeconds | int | `20` | Delay before the first readiness check |
| master.readinessProbe.periodSeconds | int | `5` | Interval between readiness checks |
| master.readinessProbe.successThreshold | int | `1` | Successes needed to pass readiness |
| master.readinessProbe.timeoutSeconds | int | `1` | Readiness check timeout |
| master.resources | object | `{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource requests and limits for the Redis container |
| master.service.annotations | object | `{}` | Annotations for the master Service |
| master.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy, with type NodePort or LoadBalancer |
| master.service.loadBalancerIP | string | `""` | Load balancer IP for the master Service, with type LoadBalancer |
| master.service.loadBalancerSourceRanges | list | `[]` | Source ranges allowed to reach the master load balancer |
| master.service.nodePort | string | `""` | Node port for the master Service, with type NodePort or LoadBalancer |
| master.service.port | int | `6379` | Master Service port |
| master.service.sessionAffinity | string | `"None"` | Session affinity for the master Service |
| master.service.sessionAffinityConfig | object | `{}` | Session affinity configuration for the master Service |
| master.service.type | string | `"ClusterIP"` | Master Service type |
| master.sidecars | list | `[]` | Extra sidecar containers on the master pod |
| master.startupProbe.enabled | bool | `false` | Enable the master startup probe |
| master.startupProbe.failureThreshold | int | `30` | Failures tolerated before the container restarts |
| master.startupProbe.initialDelaySeconds | int | `0` | Delay before the first startup check |
| master.startupProbe.periodSeconds | int | `10` | Interval between startup checks |
| master.startupProbe.successThreshold | int | `1` | Successes needed to pass startup |
| master.startupProbe.timeoutSeconds | int | `5` | Startup check timeout |
| master.tolerations | list | `[]` | Tolerations for the master pod |
| master.topologySpreadConstraints | list | `[]` | Topology spread constraints for the master pod |
| master.watchdog.cooldownSeconds | int | `60` | Seconds the watchdog waits after requesting a failover |
| master.watchdog.enabled | bool | `true` | Run the watchdog sidecar. It watches the master role and asks Sentinel to hand the role back when this pod has been demoted, so the master Service keeps pointing at a pod that accepts writes. Sentinel only. |
| master.watchdog.intervalSeconds | int | `30` | Seconds between role checks |
| metrics.enabled | bool | `false` | Run a Redis exporter sidecar next to the master and every replica |
| metrics.extraArgs | list | `[]` | Extra command line arguments for the exporter |
| metrics.image.pullPolicy | string | `"IfNotPresent"` | Exporter image pull policy |
| metrics.image.registry | string | `"docker.io"` | Exporter image registry |
| metrics.image.repository | string | `"oliver006/redis_exporter"` | Exporter image repository |
| metrics.image.tag | string | `"v1.62.0-alpine"` | Exporter image tag |
| metrics.port | int | `9121` | Port the exporter listens on and the Services expose |
| metrics.resources | object | `{"limits":{"cpu":"100m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Resource requests and limits for the exporter container |
| metrics.serviceMonitor.enabled | bool | `false` | Create a ServiceMonitor. Needs the Prometheus Operator CRDs. |
| metrics.serviceMonitor.honorLabels | bool | `true` | Keep the labels the exporter sets on conflict |
| metrics.serviceMonitor.interval | string | `"30s"` | Scrape interval |
| metrics.serviceMonitor.labels | object | `{}` | Extra labels so your Prometheus selects this ServiceMonitor |
| metrics.serviceMonitor.metricRelabelings | list | `[]` | Relabeling rules applied to the scraped metrics |
| metrics.serviceMonitor.namespace | string | `""` | Namespace for the ServiceMonitor, defaults to the release namespace |
| metrics.serviceMonitor.relabelings | list | `[]` | Relabeling rules applied before the scrape |
| metrics.serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |
| nameOverride | string | `""` | Override the chart name used in resource names |
| networkPolicy.allowExternal | bool | `true` | Allow ingress from every pod in the cluster |
| networkPolicy.egressRules | list | `[]` | Egress rules for the policy |
| networkPolicy.enabled | bool | `false` | Create a NetworkPolicy for the Redis pods |
| networkPolicy.ingressNSMatchLabels | object | `{}` | Namespace labels allowed to reach Redis |
| networkPolicy.ingressNSPodMatchLabels | object | `{}` | Pod labels, inside the allowed namespaces, allowed to reach Redis |
| networkPolicy.ingressRules | list | `[]` | Extra ingress rules appended to the policy |
| replica.affinity | object | `{}` | Affinity rules for the replica pods |
| replica.command | list | `[]` | Replaces the replica start command entirely |
| replica.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation inside the replica containers |
| replica.containerSecurityContext.capabilities.drop | list | `["ALL"]` | Linux capabilities dropped from the replica containers |
| replica.containerSecurityContext.enabled | bool | `true` | Apply the replica container security context |
| replica.containerSecurityContext.readOnlyRootFilesystem | bool | `true` | Mount the replica container root filesystem read only |
| replica.containerSecurityContext.runAsNonRoot | bool | `true` | Refuse to start a replica container as root |
| replica.containerSecurityContext.runAsUser | int | `1001` | User the replica containers run as |
| replica.customLivenessProbe | object | `{}` | Replaces the built in liveness probe entirely |
| replica.customReadinessProbe | object | `{}` | Replaces the built in readiness probe entirely |
| replica.customStartupProbe | object | `{}` | Replaces the built in startup probe entirely |
| replica.extraEnvVars | list | `[]` | Extra environment variables for the replica containers |
| replica.extraEnvVarsCM | string | `""` | Name of a ConfigMap with extra environment variables for the replica containers |
| replica.extraEnvVarsSecret | string | `""` | Name of a Secret with extra environment variables for the replica containers |
| replica.extraVolumeMounts | list | `[]` | Extra volume mounts on the replica containers |
| replica.extraVolumes | list | `[]` | Extra volumes on the replica pods |
| replica.initContainers | list | `[]` | Extra init containers on the replica pods |
| replica.lifecycleHooks | object | `{}` | Lifecycle hooks for the replica containers |
| replica.livenessProbe.enabled | bool | `true` | Enable the replica liveness probe |
| replica.livenessProbe.failureThreshold | int | `5` | Failures tolerated before the container restarts |
| replica.livenessProbe.initialDelaySeconds | int | `20` | Delay before the first liveness check |
| replica.livenessProbe.periodSeconds | int | `5` | Interval between liveness checks |
| replica.livenessProbe.successThreshold | int | `1` | Successes needed to pass liveness |
| replica.livenessProbe.timeoutSeconds | int | `5` | Liveness check timeout |
| replica.nodeSelector | object | `{}` | Node selector for the replica pods |
| replica.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the replica volumes |
| replica.persistence.annotations | object | `{}` | Annotations on the replica volume claims |
| replica.persistence.dataSource | object | `{}` | Data source to clone the replica volumes from |
| replica.persistence.enabled | bool | `true` | Give each replica a PersistentVolumeClaim |
| replica.persistence.selector | object | `{}` | Label selector for pre-provisioned replica volumes |
| replica.persistence.size | string | `"8Gi"` | Size of each replica volume |
| replica.persistence.storageClass | string | `""` | StorageClass for the replica volumes |
| replica.podAnnotations | object | `{}` | Extra annotations on the replica StatefulSet and its pods |
| replica.podDisruptionBudget.enabled | bool | `true` | Create a PodDisruptionBudget for the replicas |
| replica.podDisruptionBudget.maxUnavailable | string | `""` | Maximum unavailable replica pods during a voluntary disruption |
| replica.podDisruptionBudget.minAvailable | int | `1` | Minimum available replica pods during a voluntary disruption |
| replica.podLabels | object | `{}` | Extra labels on the replica StatefulSet and its pods |
| replica.podSecurityContext.enabled | bool | `true` | Apply the replica pod security context |
| replica.podSecurityContext.fsGroup | int | `1001` | Volume ownership group for the replica pods |
| replica.podSecurityContext.runAsNonRoot | bool | `true` | Refuse to start a replica pod as root |
| replica.podSecurityContext.runAsUser | int | `1001` | User the replica pods run as |
| replica.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` | Seccomp profile for the replica pods |
| replica.priorityClassName | string | `""` | PriorityClass for the replica pods |
| replica.readinessProbe.enabled | bool | `true` | Enable the replica readiness probe. It also checks that replication to the current master is up. |
| replica.readinessProbe.failureThreshold | int | `5` | Failures tolerated before the pod leaves the Service endpoints |
| replica.readinessProbe.initialDelaySeconds | int | `20` | Delay before the first readiness check |
| replica.readinessProbe.periodSeconds | int | `5` | Interval between readiness checks |
| replica.readinessProbe.successThreshold | int | `1` | Successes needed to pass readiness |
| replica.readinessProbe.timeoutSeconds | int | `1` | Readiness check timeout |
| replica.replicaCount | int | `2` | Number of replica pods |
| replica.resources | object | `{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource requests and limits for each replica container |
| replica.service.annotations | object | `{}` | Annotations for the replica Service |
| replica.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy, with type NodePort or LoadBalancer |
| replica.service.labels | object | `{}` | Labels for the replica Service |
| replica.service.loadBalancerIP | string | `""` | Load balancer IP for the replica Service, with type LoadBalancer |
| replica.service.loadBalancerSourceRanges | list | `[]` | Source ranges allowed to reach the replica load balancer |
| replica.service.nodePort | string | `""` | Node port for the replica Service, with type NodePort or LoadBalancer |
| replica.service.port | int | `6379` | Replica Service port |
| replica.service.sessionAffinity | string | `"None"` | Session affinity for the replica Service |
| replica.service.sessionAffinityConfig | object | `{}` | Session affinity configuration for the replica Service |
| replica.service.type | string | `"ClusterIP"` | Replica Service type |
| replica.sidecars | list | `[]` | Extra sidecar containers on the replica pods |
| replica.startupProbe.enabled | bool | `false` | Enable the replica startup probe |
| replica.startupProbe.failureThreshold | int | `30` | Failures tolerated before the container restarts |
| replica.startupProbe.initialDelaySeconds | int | `0` | Delay before the first startup check |
| replica.startupProbe.periodSeconds | int | `10` | Interval between startup checks |
| replica.startupProbe.successThreshold | int | `1` | Successes needed to pass startup |
| replica.startupProbe.timeoutSeconds | int | `5` | Startup check timeout |
| replica.tolerations | list | `[]` | Tolerations for the replica pods |
| replica.topologySpreadConstraints | list | `[]` | Topology spread constraints for the replica pods |
| sentinel.affinity | object | `{}` | Affinity rules for the Sentinel pods |
| sentinel.command | list | `[]` | Replaces the Sentinel start command entirely |
| sentinel.containerSecurityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation inside the Sentinel containers |
| sentinel.containerSecurityContext.capabilities.drop | list | `["ALL"]` | Linux capabilities dropped from the Sentinel containers |
| sentinel.containerSecurityContext.enabled | bool | `true` | Apply the Sentinel container security context |
| sentinel.containerSecurityContext.readOnlyRootFilesystem | bool | `true` | Mount the Sentinel container root filesystem read only. Sentinel rewrites its own config file, so set this to false when the config lives outside a writable volume. |
| sentinel.containerSecurityContext.runAsNonRoot | bool | `true` | Refuse to start a Sentinel container as root |
| sentinel.containerSecurityContext.runAsUser | int | `1001` | User the Sentinel containers run as |
| sentinel.customLivenessProbe | object | `{}` | Replaces the built in liveness probe entirely |
| sentinel.customReadinessProbe | object | `{}` | Replaces the built in readiness probe entirely |
| sentinel.customStartupProbe | object | `{}` | Replaces the built in startup probe entirely |
| sentinel.downAfterMilliseconds | int | `30000` | Milliseconds of silence before Sentinel calls the master down |
| sentinel.enabled | bool | `false` | Run Sentinel and let it fail the master over to a replica |
| sentinel.extraEnvVars | list | `[]` | Extra environment variables for the Sentinel containers |
| sentinel.extraEnvVarsCM | string | `""` | Name of a ConfigMap with extra environment variables for the Sentinel containers |
| sentinel.extraEnvVarsSecret | string | `""` | Name of a Secret with extra environment variables for the Sentinel containers |
| sentinel.extraVolumeMounts | list | `[]` | Extra volume mounts on the Sentinel containers |
| sentinel.extraVolumes | list | `[]` | Extra volumes on the Sentinel pods |
| sentinel.failoverTimeout | int | `180000` | Milliseconds a failover may take before Sentinel starts over |
| sentinel.image.pullPolicy | string | `"IfNotPresent"` | Sentinel image pull policy |
| sentinel.image.registry | string | `"docker.io"` | Sentinel image registry |
| sentinel.image.repository | string | `"redis"` | Sentinel image repository |
| sentinel.image.tag | string | `"7.4.2-alpine"` | Sentinel image tag |
| sentinel.lifecycleHooks | object | `{}` | Lifecycle hooks for the Sentinel containers |
| sentinel.livenessProbe.enabled | bool | `true` | Enable the Sentinel liveness probe |
| sentinel.livenessProbe.failureThreshold | int | `6` | Failures tolerated before the container restarts |
| sentinel.livenessProbe.initialDelaySeconds | int | `20` | Delay before the first liveness check |
| sentinel.livenessProbe.periodSeconds | int | `10` | Interval between liveness checks |
| sentinel.livenessProbe.successThreshold | int | `1` | Successes needed to pass liveness |
| sentinel.livenessProbe.timeoutSeconds | int | `5` | Liveness check timeout |
| sentinel.masterSet | string | `"mymaster"` | Logical name Sentinel uses for the monitored master |
| sentinel.nodeSelector | object | `{}` | Node selector for the Sentinel pods |
| sentinel.parallelSyncs | int | `1` | Replicas re-synchronised in parallel with the new master |
| sentinel.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes for the Sentinel volumes |
| sentinel.persistence.enabled | bool | `false` | Give each Sentinel a PersistentVolumeClaim so its view of the current master survives a restart. Recommended wherever pods are rescheduled often. |
| sentinel.persistence.size | string | `"100Mi"` | Size of each Sentinel volume |
| sentinel.persistence.storageClass | string | `""` | StorageClass for the Sentinel volumes |
| sentinel.podAnnotations | object | `{}` | Extra annotations on the Sentinel StatefulSet and its pods |
| sentinel.podDisruptionBudget.enabled | bool | `true` | Create a PodDisruptionBudget for the Sentinels |
| sentinel.podDisruptionBudget.minAvailable | int | `2` | Minimum available Sentinel pods, keep the quorum during a node drain |
| sentinel.podLabels | object | `{}` | Extra labels on the Sentinel StatefulSet and its pods |
| sentinel.podSecurityContext.enabled | bool | `true` | Apply the Sentinel pod security context |
| sentinel.podSecurityContext.fsGroup | int | `1001` | Volume ownership group for the Sentinel pods |
| sentinel.podSecurityContext.runAsNonRoot | bool | `true` | Refuse to start a Sentinel pod as root |
| sentinel.podSecurityContext.runAsUser | int | `1001` | User the Sentinel pods run as |
| sentinel.podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` | Seccomp profile for the Sentinel pods |
| sentinel.priorityClassName | string | `""` | PriorityClass for the Sentinel pods |
| sentinel.quorum | int | `2` | Sentinels that must agree the master is unreachable before a failover starts |
| sentinel.readinessProbe.enabled | bool | `true` | Enable the Sentinel readiness probe. It also checks that Sentinel knows the current master. |
| sentinel.readinessProbe.failureThreshold | int | `6` | Failures tolerated before the pod leaves the Service endpoints |
| sentinel.readinessProbe.initialDelaySeconds | int | `20` | Delay before the first readiness check |
| sentinel.readinessProbe.periodSeconds | int | `5` | Interval between readiness checks |
| sentinel.readinessProbe.successThreshold | int | `1` | Successes needed to pass readiness |
| sentinel.readinessProbe.timeoutSeconds | int | `1` | Readiness check timeout |
| sentinel.replicaCount | int | `3` | Number of Sentinel pods, 3 or more for a reliable quorum |
| sentinel.resources | object | `{"limits":{"cpu":"200m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}` | Resource requests and limits for each Sentinel container |
| sentinel.service.annotations | object | `{}` | Annotations for the Sentinel Service |
| sentinel.service.externalTrafficPolicy | string | `"Cluster"` | External traffic policy, with type LoadBalancer |
| sentinel.service.labels | object | `{}` | Labels for the Sentinel Service |
| sentinel.service.loadBalancerIP | string | `""` | Load balancer IP for the Sentinel Service, with type LoadBalancer |
| sentinel.service.loadBalancerSourceRanges | list | `[]` | Source ranges allowed to reach the Sentinel load balancer |
| sentinel.service.nodePorts.sentinel | string | `""` | Node port for the Sentinel Service, with type NodePort or LoadBalancer |
| sentinel.service.port | int | `26379` | Sentinel Service port |
| sentinel.service.sessionAffinity | string | `"None"` | Session affinity for the Sentinel Service |
| sentinel.service.type | string | `"ClusterIP"` | Sentinel Service type |
| sentinel.startupProbe.enabled | bool | `false` | Enable the Sentinel startup probe |
| sentinel.startupProbe.failureThreshold | int | `30` | Failures tolerated before the container restarts |
| sentinel.startupProbe.initialDelaySeconds | int | `0` | Delay before the first startup check |
| sentinel.startupProbe.periodSeconds | int | `10` | Interval between startup checks |
| sentinel.startupProbe.successThreshold | int | `1` | Successes needed to pass startup |
| sentinel.startupProbe.timeoutSeconds | int | `5` | Startup check timeout |
| sentinel.tolerations | list | `[]` | Tolerations for the Sentinel pods |
| sentinel.topologySpreadConstraints | list | `[]` | Topology spread constraints for the Sentinel pods |
| serviceAccount.annotations | object | `{}` | Annotations on the ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the ServiceAccount token in the pods. Redis needs no API access. |
| serviceAccount.create | bool | `true` | Create a ServiceAccount for the Redis pods |
| serviceAccount.name | string | `""` | Name of the ServiceAccount, generated from the release when empty |
| sysctl.enabled | bool | `false` | Run a privileged init container that sets kernel parameters |
| sysctl.image.pullPolicy | string | `"IfNotPresent"` | Init container image pull policy |
| sysctl.image.registry | string | `"docker.io"` | Init container image registry |
| sysctl.image.repository | string | `"alpine"` | Init container image repository |
| sysctl.image.tag | string | `"3.19"` | Init container image tag |
| sysctl.resources | object | `{"limits":{"cpu":"50m","memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}` | Resource requests and limits for the init container |
| sysctl.sysctls | object | `{}` | Kernel parameters to set, for example `net.core.somaxconn: 10000` |
| volumePermissions.enabled | bool | `false` | Run an init container that chowns the data volume. Needed on storage that ignores fsGroup. |
| volumePermissions.image.pullPolicy | string | `"IfNotPresent"` | Init container image pull policy |
| volumePermissions.image.registry | string | `"docker.io"` | Init container image registry |
| volumePermissions.image.repository | string | `"alpine"` | Init container image repository |
| volumePermissions.image.tag | string | `"3.19"` | Init container image tag |
| volumePermissions.resources | object | `{"limits":{"cpu":"50m","memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}` | Resource requests and limits for the init container |

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
