## cnpg-cluster 1.1.0

**What changed**

- New `backup.method` value. `barmanObjectStore` (the default) keeps the object store on the `Cluster`, as before. `plugin` uses the [Barman Cloud Plugin](https://cloudnative-pg.io/plugin-barman-cloud/): the chart renders an `ObjectStore` (`barmancloud.cnpg.io/v1`) holding the destination, credentials, WAL and data settings and the retention policy, adds the plugin to `Cluster.spec.plugins` as WAL archiver, and renders the `ScheduledBackup` with `method: plugin`. Every `backup.gcs`, `backup.s3`, `backup.azure`, `backup.wal` and `backup.data` value applies to both methods.
- New `backup.plugin` values: `name`, `objectStoreName` (defaults to the cluster name), `serverName` and `instanceSidecarConfiguration` (sidecar resources, env, log level, retention check interval).

**Upgrading**

No values changes. With `backup.method` left at its default the rendered manifests are identical to 1.0.0 apart from the chart label and one comment.

To move an existing cluster to the plugin, install the plugin in the operator namespace first (it needs cert-manager), then set `backup.method: plugin` and upgrade. Keep the same bucket and path: the plugin reads and writes the same Barman archive, so earlier backups stay usable for recovery. The upgrade adds a sidecar to every instance, so the operator restarts the replicas one by one and then switches the primary over. Workload Identity keeps working because the sidecar runs under the instance service account. Metric names change from `cnpg_collector_*` to `barman_cloud_cloudnative_pg_io_*`; update dashboards and alerts that read the old names.

## cnpg-cluster 1.0.0

First public release of the chart.

**What it does**

- Renders a CloudNativePG `Cluster` from one values file, with optional PgBouncer `Pooler` resources, a `ScheduledBackup`, a `PodMonitor`, NetworkPolicies and External Secrets Operator resources.
- Defaults suit spot and preemptible nodes: immediate failover, PVC reuse after a node is reclaimed, preferred anti-affinity, and tolerations for both instances and poolers.
- An optional replica recovery CronJob rebuilds replicas stuck in CrashLoopBackOff, deletes orphaned instance pods that can never schedule, and fails when the read-write Service has no endpoints.

**Fixed in this release**

- An S3 backup with `backup.s3.region` set rendered the `s3Credentials` key twice. It renders once.
- A `pooler.instances` entry without a `pgbouncer` block failed the render. It now uses the documented defaults.
- Azure backups wrote to an `azure://` destination that Barman does not accept. The destination is now `https://<storageAccount>.blob.core.windows.net/<container>/<path>`, and `backup.azure.storageAccount` is required for the Azure provider.
- With superuser access on and no secret supplied, the cluster referenced a superuser secret that nothing created. The reference is now rendered only when a secret will exist; otherwise the operator generates `<cluster>-superuser`.
- `podAnnotations` is declared in `values.yaml`.
- The `helm.sh/chart` label drops build metadata from the version instead of rewriting it.

**Defaults to know**

- `auth.superuser.enabled` is `false`, as in CloudNativePG.
- `backup.gcs.gkeEnvironment` is `false`. Set it to `true` to authenticate to GCS through GKE Workload Identity.
- `externalSecrets.provider` has no default. With `externalSecrets.enabled` and no `externalSecrets.secretStore.name`, the render fails until you choose `gcpsm`, `aws`, `vault` or `azurekv`.
- `replicaRecovery.image` is `alpine/k8s:1.33.5`, a pinned image with the Kubernetes CLI and a POSIX shell.
- A secret from `auth.appUser` or `externalSecrets.appUserSecret` sets the owner password only when `bootstrap.initdb.secret.name` names it. Otherwise the operator generates the password in `<cluster>-app`.
- An empty `postgresql.pg_hba` allows scram-sha-256 password logins from the RFC 1918 private ranges only.

**Upgrade notes**

- Pooler pods carry the chart version label, so upgrading the chart rolls them. PostgreSQL instance pods are not restarted by a chart upgrade.
- When you move an existing cluster onto this chart, compare `helm template` against the live `Cluster` first and set any of the defaults above explicitly where they differ.
