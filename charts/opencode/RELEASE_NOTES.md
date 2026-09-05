## opencode 1.4.2

**What changed**

- The GitHub Release asset and the OCI artifact at `ghcr.io/neomanexlabs/charts/opencode` are now the same package file, packaged once by chart-releaser and pushed as is. Checksums match across both install paths.
- Release notes are written by hand for every version and ship inside the package as `RELEASE_NOTES.md`.

**Why**

Two separate `helm package` runs could produce two different archives for one version string. One artifact, two install paths.

**Upgrade notes**

No template or values changes since 1.4.1. `helm upgrade` renders identically.

**Since 1.4.0**

- 1.4.1: installs with `externalSecrets.enabled: false`. The SSH key mount, the key copy and `GIT_SSH_COMMAND` render only when External Secrets Operator delivers a key, so `examples/minimal.yaml` installs on a cluster without ESO. Installs with ESO on are unchanged.
