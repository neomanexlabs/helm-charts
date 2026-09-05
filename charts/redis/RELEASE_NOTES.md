## redis 1.1.0

First public release of the chart. 1.0.0 was a private baseline and was never published.

**What changed**

- External Secrets Operator settings are declared in `values.yaml` (`externalSecrets.*`, disabled by default). The chart now renders and installs with default values on a cluster that has neither External Secrets Operator nor a Prometheus Operator.
- Passwords are generated. With `auth.enabled` and no `auth.password` and no `auth.existingSecret`, the chart creates a 32 character password on the first install and reuses the one already stored in its Secret on every upgrade. No well known credential ships as a default any more.
- `topologySpreadConstraints` renders on the master, replica and Sentinel workloads, from `master.topologySpreadConstraints`, `replica.topologySpreadConstraints` and `sentinel.topologySpreadConstraints`.
- The Sentinel bootstrap builds its replica host list from `replica.replicaCount`, so it waits for every replica instead of a fixed pair.
- `architecture` accepts `standalone` and `replication` only, and the validation now runs on every render: an unsupported value fails instead of installing a release with no Redis in it.
- Values that no template rendered were removed: cluster mode, backups, RBAC, TLS, PodMonitor, PrometheusRule, replica autoscaling, extra manifests, password files and the debug image switch. The README says which of those are simply not implemented.
- Every remaining value carries a description, and `README.md` is generated from them.
- Comments in the packaged templates use plain punctuation, and the chart notes point at this repository.

**Why**

A chart published for other people has to install from its own defaults, and its values reference has to be true. Both were broken: the default render failed on an undeclared key, the defaults carried a publicly known password, and roughly sixty keys documented features no template implemented. The topology spread constraints were the reverse problem: values that operators were already setting, silently dropped.

**Upgrade notes**

- Any upgrade rolls every pod. The chart version is part of the pod template through the `helm.sh/chart` label, so all three StatefulSets restart. Replicas and Sentinels restart without client impact; the master restart triggers one Sentinel failover, followed by the automatic failback that returns the role to the master pod. Pick the moment.
- New keys: `master.topologySpreadConstraints`, `replica.topologySpreadConstraints`, `sentinel.topologySpreadConstraints`, all empty by default. If you were already setting them, they now take effect, so check that the constraints you wrote are satisfiable on your nodes before you upgrade. A `DoNotSchedule` constraint that the cluster cannot satisfy leaves pods pending.
- Removed keys were inert: setting them changed nothing before, and Helm ignores unknown keys, so an existing values file keeps working. Delete them anyway; they promise features the chart does not have.
- `auth.password` and `auth.sentinelPassword` now default to empty. A values file that sets either, or that sets `auth.existingSecret`, is unaffected.
