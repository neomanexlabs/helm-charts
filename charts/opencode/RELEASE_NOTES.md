## opencode 1.4.9

**What changed**

- Default `image.tag` is `1.19.0-2`, an immutable build of OpenCode 1.19.0 with kubectl 1.36.5. The image workflow now scans every build with Trivy and pushes only after a clean scan.
- README: new "Image versions" section (tag grammar, package page, digest pinning, per-workspace `image.tag`).
- README: `config.providers` is release-wide, and a rendered config change restarts every workspace.

**Upgrading**

No action needed. Overlays that pin `image.tag` keep their version; the rest move from the floating `1.19.0` tag to `1.19.0-2`.

## opencode 1.4.8

**What changed**

- README: new "Limiting providers and models" section covering `enabledProviders`, provider `whitelist` / `blacklist` and per-workspace `providerModels`, with an example.
- README: upgrade note for 1.4.5 to 1.4.8 (default OpenCode image 1.14.48 to 1.19.0, new optional keys).
- `values.yaml`: the `providerModels` comment example uses a current provider id.

**Upgrading**

No action needed. Documentation only; templates are unchanged and every values file renders the same manifests as 1.4.7.

## opencode 1.4.7

**What changed**

- `workspaces[].providerModels` now also applies to a provider that has no `config.providers` entry. The chart renders a block for it with the model filter only: no `options`, no `apiKey`.

**Why**

In 1.4.6 the filter rendered only inside `config.providers` entries. A provider whose key OpenCode resolves on its own, from an environment variable or from a key saved through the web UI, could be allowed with `enabledProviders` but not narrowed to a subset of its models. Adding a `config.providers` entry to work around that would replace the key the workspace already uses.

**Upgrading**

No action needed. Values that set no `providerModels` render the same `opencode.json` as 1.4.6.

## opencode 1.4.6

**What changed**

- `config.enabledProviders` renders OpenCode's `enabled_providers`. When set, OpenCode loads only the listed providers and ignores every other one, including providers it would otherwise connect on its own (its free built-in provider, a provider whose API key environment variable is present, a key saved through the web UI). `workspaces[].enabledProviders` replaces the global list for one workspace.
- Any entry under `config.providers` accepts `whitelist` or `blacklist`, a list of model ids, which limits the models the model picker shows for that provider. `workspaces[].providerModels.<provider>` replaces that provider's filter for one workspace.
- The default image is OpenCode 1.19.0 (`ghcr.io/neomanexlabs/opencode:1.19.0`).
- `tests/render-check.sh` covers both keys: omitted by default, global values inherited, workspace values replacing the global ones.

**Why**

OpenCode lists every model of every provider it can reach, which is several hundred entries once a router provider is configured. A workspace meant for one model needs a way to show only that model.

**Upgrading**

No action needed. Both keys are off by default and existing values render the same `opencode.json` as 1.4.5. Overlays that pin `image.tag` keep their pinned OpenCode version.

## opencode 1.4.5

**What changed**

- The chart description and the README open with what the chart is for: running the OpenCode web UI and HTTP API as a service in your cluster, reachable from any browser, with one persistent workspace per repository.
- A new section covers what running the agent in a cluster gives you, including the `server.cors` setting a publicly exposed web UI needs and the split between the browser ingress and the machine ingress.

**Why**

The previous text led with the Kubernetes objects the chart creates, so a reader had to work out for themselves why an agent belongs in a cluster at all. No template, value or default changed in this release.

## opencode 1.4.4

**What changed**

- The `helm.sh/chart` label drops semver build metadata instead of rewriting it. A chart version such as `1.4.4+abc123` labels every object `opencode-1.4.4`.
- `tests/render-check.sh` asserts the label on a render with build metadata injected and on the default render.

**Why**

The label sits in the pod template. A suffix that changes per build would restart every workspace on each render even when nothing else moved.

## opencode 1.4.3

**What changed**

- Comments in the packaged templates use plain punctuation only. Every em dash is now a period, comma, colon or parenthesis.
- One template comment referenced a document that does not ship with the chart. It now explains the behaviour in full on its own.
- The pull-request gate and the local `tests/render-check.sh` both reject em dashes and references to an external documentation tree anywhere under `charts/`, so the two agree and neither can regress.

**Why**

Published text is read by people who only have the chart. Punctuation stays plain for readability across terminals and renderers, and a comment that points at a document the reader cannot open explains nothing.

**Upgrade notes**

Comment text only. No template logic, no values, no rendered output changes. `helm upgrade` renders identically to 1.4.2.

**Since 1.4.0**

- 1.4.2: the GitHub Release asset and the OCI artifact at `ghcr.io/neomanexlabs/charts/opencode` are the same package file, packaged once and pushed as is, so checksums match across both install paths. Release notes are hand-written per version and ship inside the package as `RELEASE_NOTES.md`.
- 1.4.1: installs with `externalSecrets.enabled: false`. The SSH key mount, the key copy and `GIT_SSH_COMMAND` render only when External Secrets Operator delivers a key, so `examples/minimal.yaml` installs on a cluster without ESO. Installs with ESO on are unchanged.
