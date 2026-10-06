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
- An application user secret supplied through `auth.appUser.password`, `auth.appUser.existingSecret` or `externalSecrets.appUserSecret` was created but never passed to `initdb`, so the owner got a generated password. It is now used unless `bootstrap.initdb.secret` names a different one.
- With superuser access on and no secret supplied, the cluster referenced a superuser secret that nothing created. The reference is now rendered only when a secret will exist; otherwise the operator generates `<cluster>-superuser`.
- `podAnnotations` is declared in `values.yaml`.
- The `helm.sh/chart` label drops build metadata from the version instead of rewriting it.

**Defaults to know**

- `auth.superuser.enabled` is `false`, as in CloudNativePG.
- `backup.gcs.gkeEnvironment` is `false`. Set it to `true` to authenticate to GCS through GKE Workload Identity.
- `externalSecrets.provider` has no default. With `externalSecrets.enabled` and no `externalSecrets.secretStore.name`, the render fails until you choose `gcpsm`, `aws`, `vault` or `azurekv`.
- `replicaRecovery.image` is `alpine/k8s:1.33.5`, a pinned image with the Kubernetes CLI and a POSIX shell.
- An empty `postgresql.pg_hba` allows scram-sha-256 password logins from the RFC 1918 private ranges only.

**Upgrade notes**

- Pooler pods carry the chart version label, so upgrading the chart rolls them. PostgreSQL instance pods are not restarted by a chart upgrade.
- When you move an existing cluster onto this chart, compare `helm template` against the live `Cluster` first and set any of the defaults above explicitly where they differ.
- On an existing cluster that supplies an application user secret, the rendered `bootstrap.initdb.secret` may differ from the live spec. Bootstrap runs only when a cluster is created, so the running database is unaffected; run `helm upgrade --dry-run=server` first to confirm your operator accepts the change.
