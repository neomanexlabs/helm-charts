# Neomanex Helm Charts

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/neomanexlabs)](https://artifacthub.io/packages/search?repo=neomanexlabs)

Public Helm charts published by [Neomanex](https://neomanex.com), an AI-native company that runs its own operations on AI agents and publishes the infrastructure underneath them. These are the charts we run in production ourselves, not demo material. Install them from the GitHub Pages chart repository or pull them as OCI artifacts from GHCR.

## Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [opencode](charts/opencode) | 1.4.4 | Runs the OpenCode AI coding agent on Kubernetes as a StatefulSet, one persistent workspace per git repository. |
| [redis](charts/redis) | 1.1.0 | Runs Redis on Kubernetes with Sentinel high availability, automatic failback of the master role and role-aware readiness. |

## Install

From the chart repository:

```sh
helm repo add neomanexlabs https://neomanexlabs.github.io/helm-charts
helm repo update
helm install opencode neomanexlabs/opencode --version 1.4.4
```

Or directly from the OCI registry:

```sh
helm install opencode oci://ghcr.io/neomanexlabs/charts/opencode --version 1.4.4
```

Both install paths serve the identical package, built once per release.

## Contributing

Issues and pull requests are welcome. Every pull request runs chart linting, the chart's render checks and a documentation sync check; see [.github/workflows/lint-test.yml](.github/workflows/lint-test.yml). Bump the chart's `Chart.yaml` `version` in the same change: a chart edit that reaches `main` without a version bump fails the release workflow on purpose.

## About Neomanex

Neomanex is an AI-native company. We run our own business on an AI Operating Model,
publish the evidence, and help other companies become AI native: agents, operations,
and the infrastructure underneath them, built and governed in production.

This project is part of that work. It is the same code we run ourselves.

- Website: https://neomanex.com
- Work with us: https://neomanex.com/contact
- Products: [ConvOps](https://convops.app) (AI-first operations) and [Gnosari](https://gnosari.com) (conversational data collection: AI agents that turn conversations into structured data)
