# OpenCode Helm Chart

Runs the [OpenCode](https://github.com/anomalyco/opencode) coding agent as a long-lived service in your own Kubernetes cluster instead of on a laptop. `opencode serve` carries the web UI and the HTTP API on one port, so behind an ingress you open your agent in a browser from any machine, and the session keeps running after you close the laptop.

One release runs many instances. Each entry in `workspaces` is a separate StatefulSet with its own repository checkout, storage, model providers, MCP servers and ingress, so every repository keeps a warm clone and its own configuration. Credentials come from your cluster secret store, and an instance can be granted scoped RBAC to operate the namespace it runs in.

It is for platform and infrastructure teams who want coding agents living next to the systems those agents work on. It is published by [Neomanex](https://neomanex.com), an AI-native company, and it is the chart our own OpenCode instances run on in production.

```sh
helm repo add neomanexlabs https://neomanexlabs.github.io/helm-charts
helm install opencode neomanexlabs/opencode --version 1.4.5 -f my-values.yaml
```

Or as an OCI artifact:

```sh
helm install opencode oci://ghcr.io/neomanexlabs/charts/opencode --version 1.4.5 -f my-values.yaml
```

## Why run it in a cluster

| Property | What it means |
|----------|---------------|
| Reachable from anywhere | The web UI and the HTTP API are one server on one port, so an ingress makes the agent available from any browser, including a phone. Public exposure needs `server.cors` set to the UI's own origin, because the UI loads its JavaScript modules with the `crossorigin` attribute |
| Humans and machines, separately | `ingress` is the browser host and `apiIngress` is a second host for machine clients, so an SSO gate in front of one does not lock the other out. OpenCode's own HTTP Basic auth is on by default |
| Sessions outlive the laptop | Session history and tool output live on a PersistentVolumeClaim, so closing the browser does not end the work and a pod restart resumes instead of starting over |
| A warm checkout per repository | Each workspace keeps its own clone instead of cloning per session, a git-sync CronJob keeps it current, and `gitSync.autosave` commits and pushes agent-written paths on a schedule |
| Next to the systems it works on | The agent runs inside the cluster, so internal services and private registries are reachable without a hop from a laptop, and `rbac.clusterReader` or `rbac.exposeRole` let it read or expose workloads in its own namespace |
| Credentials stay in the cluster | Provider API keys, the git deploy key and the server password come from your secret store through External Secrets Operator, never from a dotfile on a developer machine |

## Requirements

| Requirement | Detail |
|-------------|--------|
| Kubernetes | 1.25 or newer, with a default StorageClass that supports dynamic provisioning (each workspace gets a PersistentVolumeClaim) |
| [External Secrets Operator](https://external-secrets.io) | Required for any authenticated install: the git SSH deploy key, the provider API keys and the server password are all delivered through ESO. With `externalSecrets.enabled: false` the chart installs without it, but only for public repositories cloned over https and without provider keys. See "Secrets and the ESO requirement" below |
| Ingress controller | Optional. `ingress.enabled` and `ingressApi.enabled` are off by default; without them the service is reachable through a port-forward or from inside the cluster |
| Container image | `ghcr.io/neomanexlabs/opencode` by default. Any image with `git`, `openssh-client` and a shell works; set `image.repository` and `image.tag` to use your own |

## Quick start

[`examples/minimal.yaml`](examples/minimal.yaml) is the smallest set of values that installs: one workspace pointing at a public repository, no External Secrets Operator, no ingress, no server password. It is unauthenticated and meant for a port-forward on a cluster you control.

```sh
helm template opencode neomanexlabs/opencode -f examples/minimal.yaml
```

Read that render before installing anything. It is deliberately unauthenticated and is meant for inspection and for a port-forward on a cluster you control, never for exposure.

### Secrets and the ESO requirement

Every credential the chart handles is delivered by [External Secrets Operator](https://external-secrets.io) from a `ClusterSecretStore` named `gcp-secret-manager`, through two ExternalSecret resources the chart creates when `externalSecrets.enabled` is true:

- `externalSecrets.sshKey` becomes the `opencode-ssh-key` Secret, key `id_ed25519`, the deploy key used to clone and push every workspace repository.
- `externalSecrets.secrets` becomes the `opencode-secrets` Secret, mounted at `/etc/opencode/secrets/` and referenced from `config.provider` through OpenCode's `{file:/etc/opencode/secrets/<key>}` substitution. It also carries `server-password` when `server.passwordAuth.enabled` is on.

With `externalSecrets.enabled: false` nothing secret is mounted: no SSH key, no provider keys, no server password. The workspaces still install and clone, provided every repository is reachable over https without credentials, and the server answers anyone who can reach it. That mode is for trying the chart, not for running it.

A secrets mode that reads plain Kubernetes Secrets you create yourself, without External Secrets Operator, is not implemented yet. Open an issue if you need one.

## How it works

Each entry in `workspaces` becomes its own StatefulSet, Service, ConfigMap and PersistentVolumeClaim, named after the workspace. An init container clones the workspace repository into the volume on first start and repairs permissions on every restart, then the OpenCode server runs as uid 1000 with that checkout mounted at `/workspace/<name>`. A per-workspace ConfigMap renders `opencode.json`: providers, MCP servers, per-workspace instructions, and a permission map folded from the global and per-workspace `tools` filters. A git-sync CronJob keeps each checkout current and, when `gitSync.autosave` is configured, commits and pushes agent-written paths on a schedule. Optional pieces, all off by default: NetworkPolicy, ingress for the web UI and for the API, RBAC roles that let the agent deploy or expose workloads in its own namespace, a session-cleanup CronJob, and a separate MCP deployment.

## Label namespace

The chart labels every workspace-scoped object with `opencode.neomanex.com/workspace: <name>`, and that key is part of the StatefulSet selector. Kubernetes makes selectors immutable, so this key will not be renamed inside a major version: changing it would require deleting and recreating every StatefulSet. Treat `opencode.neomanex.com/*` as the chart's reserved label namespace and do not set those keys yourself.

## Upgrading

### 1.4.0 to 1.4.1

No values changes. With `externalSecrets.enabled: false` the chart now renders an installable StatefulSet (the SSH key mount, the key copy and `GIT_SSH_COMMAND` are only rendered when ESO delivers a key). Installs with ESO on render identically to 1.4.0.

### 1.3 to 1.4

| Change | Action |
|--------|--------|
| Git commit identity is no longer hardcoded | Set `git.user.name` and `git.user.email`. The defaults are `OpenCode` and `opencode@localhost`, which are valid but generic; set your own so agent commits are attributable |
| `gitSync.push` is deprecated | Replace the per-workspace `gitSync.push: true` with `gitSync.autosave: {enabled: true, paths: [...], userName: ..., userEmail: ...}`. The old key is still honored for this release, falls back to `git.user.*` for identity, and is removed in the next minor |
| `rbac.clusterReaderRoleName` is now required when cluster reading is enabled | The default is empty. With `rbac.clusterReader: true` and no name set, the render fails instead of binding a role name the chart guessed |
| `image.repository` default changed | It now points at the public `ghcr.io/neomanexlabs/opencode`. Overlays that already pin `image.repository` are unaffected |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| apiIngress.annotations | object | `{}` | Additional annotations (merged after auto-injected cert-manager + basic-auth) |
| apiIngress.basicAuth | object | `{"enabled":false,"realm":"OpenCode API","secretKey":"server-password","secretName":"","username":"opencode"}` | nginx-level HTTP Basic auth for this host. |
| apiIngress.basicAuth.enabled | bool | `false` | Enable nginx basic-auth annotations on the api ingress. |
| apiIngress.basicAuth.realm | string | `"OpenCode API"` | Realm shown in the WWW-Authenticate challenge. |
| apiIngress.basicAuth.secretKey | string | `"server-password"` | Key inside externalSecrets.secrets.data whose GCP Secret Manager value holds the plaintext basic-auth password. The chart reuses the SAME remote GCP secret already mapped here to render an nginx htpasswd secret via ESO (no separate GCP secret, no out-of-band htpasswd). Must reference an existing entry under externalSecrets.secrets.data. |
| apiIngress.basicAuth.secretName | string | `""` | Name of the K8s Secret holding the rendered htpasswd (key `auth`). Defaults to "<fullname>-api-basic-auth" when empty. |
| apiIngress.basicAuth.username | string | `"opencode"` | Basic-auth username (the htpasswd entry user). |
| apiIngress.className | string | `"nginx"` | Ingress class name |
| apiIngress.enabled | bool | `false` | Enable the second (machine-only) Ingress |
| apiIngress.host | string | `""` | Hostname for the machine-only ingress |
| apiIngress.tls | object | `{"enabled":false,"secretName":""}` | TLS configuration. When tls.enabled, the chart auto-injects the cert-manager.io/cluster-issuer annotation (same pattern as `ingress`). |
| config.autoupdate | string | `nil` | Disable OpenCode's self-update check. Omit (null) to use the built-in default. Set to false for pinned-image deployments. Note: `false` is a valid, intentional value: the chart guards on key presence, not truthiness. autoupdate: false |
| config.mcp | object | `{}` | MCP server configuration. Each key under `mcp` becomes a server name in opencode.json. Use kebab-case server names: OpenCode converts spaces to underscores in tool names, which complicates per-message tool filtering.  Schema (matches OpenCode's opencode.json config shape):   type:    "remote" | "local"             (required)   url:     "https://..."                  (required when type=remote, without deploy)   command: ["npx", "-y", "@foo/mcp"]      (required when type=local)   headers: { Authorization: "...", ... }  (optional; rendered as JSON object)   env:     { BRAVE_API_KEY: "...", ... }  (optional, local only; rendered as JSON object)   enabled: false                          (optional; omit for default=enabled)  Deployable MCP servers: Adding a `deploy` block causes the chart to create a Deployment + ClusterIP Service for the MCP server, and auto-wire its URL in opencode.json. The `opencode-secrets` K8s Secret is mounted at /etc/opencode/secrets/ in deployed MCP pods so {file:...} substitution in command args works.    deploy:     image:     "node:21-alpine"                (required; container image)     command:   ["npx", "-y", "@foo/mcp"]       (required; entrypoint array)     port:      8080                            (required; container + service port)     resources:                                 (required; requests/limits)       requests: { cpu: 50m, memory: 128Mi }       limits:   { cpu: 500m, memory: 512Mi }     env:       { KEY: "value", ... }           (optional; env vars for the container)     replicas:  1                               (optional; default 1)  Secret substitution: OpenCode resolves `{file:/etc/opencode/secrets/<key>}` at runtime by reading the file. The chart emits this literal string verbatim; plaintext token bytes live in the K8s Secret `opencode-secrets` (mounted at /etc/opencode/secrets/<key>), populated by ESO from GCP Secret Manager.  Example (non-deployed remote):   mcp:     my-service:       type: remote       url: https://mcp.example.com       headers:         Authorization: "Bearer {file:/etc/opencode/secrets/my-service-token}"  Example (deployed):   mcp:     brave-search:       type: remote       deploy:         image: node:21-alpine         command: ["npx", "-y", "@brave/brave-search-mcp-server", "--port", "8080"]         port: 8080         resources:           requests: { cpu: 50m, memory: 128Mi }           limits:   { cpu: 500m, memory: 512Mi } |
| config.model | string | `""` | Default model in "provider/model" format (e.g., "deepseek/deepseek-chat"). If empty, OpenCode uses its built-in default (anthropic/claude-sonnet-4-6). |
| config.permission | string | `nil` | Permission policy for autonomous / headless operation. Rendered as the `permission` object in opencode.json. Object form is required: a global `"allow"` string still leaves `doom_loop` and `external_directory` at `"ask"`, which blocks forever in a headless pod. Empty ({}) renders nothing: OpenCode falls back to its built-in defaults. Example (fully autonomous):   permission:     "*": allow     external_directory: allow     doom_loop: allow Default is null (NOT `{}`): opencode also accepts the string shorthand (`permission: allow`), and a map default makes helm's coalesce warn "cannot overwrite table with non table" on every render against a string-form values file. |
| config.providers | object | `{}` | Provider API key configuration. Each entry becomes a provider block in opencode.json. The apiKey is always rendered as a {file:} substitution against /etc/opencode/secrets/<secretKey>.  Built-in providers (resolved from OpenCode's models.dev catalog) need only secretKey:   providers:     anthropic:       secretKey: anthropic-api-key     deepseek:       secretKey: deepseek-api-key  Custom providers NOT in models.dev (e.g. z.ai) additionally need npm, options.baseURL, and an explicit models map:   providers:     zai:       secretKey: zai-api-key       npm: "@ai-sdk/anthropic"          # or @ai-sdk/openai-compatible       options:         baseURL: https://api.z.ai/api/anthropic       models:         glm-4.6:           name: GLM-4.6 |
| config.share | string | `nil` | Session share mode for opencode.json (e.g., "disabled", "manual", "auto"). Omit (empty) to use the built-in default. "disabled" suits headless deploys. share: disabled |
| config.smallModel | string | `""` | Model for lightweight tasks (titles, summaries, compaction). Same format as model. If empty, inherits from model or built-in default. |
| config.tools | object | `{}` | Global MCP tool exposure glob map. Keys are "<server>_<tool>" (exact) or "<server>*" (glob), values are bool; a specific key beats a broader glob on the same server (e.g. {"github*": false, "github_get_issue": true} exposes only get_issue from github). Filters which MCP tool schemas reach the model, the mechanism behind per-workspace token-cost control. Merged with each workspace's own `tools` map (workspace key wins per key, see the `workspaces` example). NOT rendered as opencode.json's own "tools" key: opencode lets a catch-all `permission: {"*": allow}` defeat a tools-map deny (last matching rule wins and the catch-all sorts after), so the chart folds these entries into the rendered `permission` object as allow/deny rules instead. Byte-wise JSON key order ("*" < "srv*" < "srv_tool") makes last-match resolve catch-all < deny-glob < allow-specific. Nothing is rendered when neither this map nor any workspace's map nor config.permission is set (today's behavior: every connected server exposes all its tools). Builtin write/edit/patch belong in config.permission directly, never here. Example:   tools:     "playwright*": false |
| cronJobs.gitSync.enabled | bool | `false` | Enable periodic git pull CronJob |
| cronJobs.gitSync.image | string | `"bitnami/kubectl:latest"` | kubectl image for exec |
| cronJobs.gitSync.schedule | string | `"0 */6 * * *"` | Cron schedule (default: every 6 hours) |
| cronJobs.sessionCleanup.enabled | bool | `false` | Enable session cleanup CronJob |
| cronJobs.sessionCleanup.image | string | `"bitnami/kubectl:latest"` | kubectl image for exec |
| cronJobs.sessionCleanup.retentionDays | int | `7` | Delete session files older than this many days |
| cronJobs.sessionCleanup.schedule | string | `"0 3 * * *"` | Cron schedule (default: daily at 3am) |
| dataVolume.size | string | `"2Gi"` | Size of the OpenCode session data volume (~/.local/share/opencode/) |
| dataVolume.storageClass | string | `""` | Storage class (empty = cluster default) |
| externalSecrets.enabled | bool | `false` | Enable ExternalSecret resources |
| externalSecrets.refreshInterval | string | `"6h"` | Refresh interval for secret sync from GCP |
| externalSecrets.secrets | object | `{"data":{},"secretName":"opencode-secrets"}` | Main secrets (provider API keys + server password) |
| externalSecrets.secrets.data | object | `{}` | Map of secretKey -> GCP Secret Manager key Example:   data:     server-password:       key: opencode-server-password     anthropic-api-key:       key: opencode-anthropic-api-key |
| externalSecrets.sshKey | object | `{"data":{},"secretName":"opencode-ssh-key"}` | SSH key (file mount for git operations) |
| fullnameOverride | string | `""` | Override full release name |
| git.user.email | string | `"opencode@localhost"` | Git commit author email used inside the pod |
| git.user.name | string | `"OpenCode"` | Git commit author name used inside the pod |
| gitlab.enabled | bool | `false` | Inject GITLAB_TOKEN into the agent container from the ESO secret. When true (and externalSecrets.enabled), the chart wires GITLAB_TOKEN via secretKeyRef against externalSecrets.secrets.secretName / key `gitlab-token` so a `gitlab-token` entry MUST exist under externalSecrets.secrets.data. `glab` reads GITLAB_TOKEN natively (MR creation + GitLab REST); it also authenticates private package installs. Disabled by default to keep the chart generic (no token unless a deployment opts in). |
| gitlab.poetrySources | list | `[]` | Poetry private-registry source names this deployment's sessions need auth for. For each entry the chart renders a POETRY_HTTP_BASIC_<UPPER_SNAKE(name)>_USERNAME=__token__ / _PASSWORD (from the `gitlab-token` secret key) env pair, so a runtime `poetry install` can pull that source's private packages. Each name MUST match a pyproject `[[tool.poetry.source]]` name the sessions resolve. Only rendered when externalSecrets.enabled AND gitlab.enabled (same gating as GITLAB_TOKEN). |
| image.pullPolicy | string | `"IfNotPresent"` | Pull policy |
| image.repository | string | `"ghcr.io/neomanexlabs/opencode"` | Container image repository |
| image.tag | string | `"1.14.48"` | Image tag (pin to a published image tag) |
| ingress.annotations | object | `{}` | Additional annotations |
| ingress.className | string | `"nginx"` | Ingress class name |
| ingress.enabled | bool | `false` |  |
| ingress.host | string | `""` | Hostname for ingress |
| ingress.tls | object | `{"enabled":false,"secretName":""}` | TLS configuration |
| nameOverride | string | `""` | Override chart name (used in resource names) |
| networkPolicy.additionalPorts | list | `[]` | Extra ingress ports allowed in addition to server.port (e.g. [3000] for a live-edit dev server running inside the pod). |
| networkPolicy.allowedNamespaces | list | `[]` | Namespaces allowed to reach OpenCode pods Example: [my-app, my-app-sessions] |
| networkPolicy.enabled | bool | `false` | Enable NetworkPolicy restricting ingress |
| podSecurityContext | object | `{"fsGroup":1000,"runAsGroup":1000,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context |
| rbac.clusterReader | bool | `false` | Bind the SA to an existing cluster-wide reader ClusterRole |
| rbac.clusterReaderRoleName | string | `""` | Name of the EXISTING cluster-wide reader ClusterRole to bind to.    No default: the chart fails to render when clusterReader is true and this    is empty, so nobody silently binds to a role that does not exist. |
| rbac.deployerRole | bool | `false` | Create a namespace-scoped deployer Role (full CRUD in the release namespace) |
| rbac.exposeRole | bool | `false` | Create a namespace-scoped expose Role: pods get/list/watch/patch + services/ingresses get/list/watch/create/delete. Lets a script inside the pod expose its own live-edit dev server (label its pod, create the Service + Ingress). Off by default. |
| replicaCount | int | `1` | Number of StatefulSet replicas (multi-replica requires external routing) |
| resources.limits.cpu | string | `"2"` |  |
| resources.limits.memory | string | `"4Gi"` |  |
| resources.requests.cpu | string | `"200m"` |  |
| resources.requests.memory | string | `"512Mi"` |  |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsNonRoot":true,"runAsUser":1000}` | Container-level security context (main container only, init overrides its own) |
| server.cors | list | `[]` |  |
| server.hostname | string | `"0.0.0.0"` | Listen address (0.0.0.0 for container networking) |
| server.passwordAuth | object | `{"enabled":true}` | OpenCode app-layer HTTP Basic auth (the OPENCODE_SERVER_PASSWORD env var). When true (default), the chart injects OPENCODE_SERVER_PASSWORD from the ESO secret and OpenCode enforces HTTP Basic auth (`opencode:<pwd>`). Set to false when an external auth gate (e.g. oauth2-proxy Google SSO at the ingress) already fronts the service. Leaving the env var unset disables OpenCode's built-in Basic auth, so the external gate becomes the sole control. Note: only takes effect when externalSecrets.enabled is also true (that is what provides the server-password secret key). |
| server.port | int | `4096` | OpenCode server port |
| serviceAccount.annotations | object | `{}` | Annotations (e.g., for GCP Workload Identity) |
| serviceAccount.create | bool | `true` | Create a ServiceAccount (needed for CronJob kubectl exec) |
| serviceAccount.name | string | `""` | ServiceAccount name override |
| workspaces | list | `[]` |  |

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
