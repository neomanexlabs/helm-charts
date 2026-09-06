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
