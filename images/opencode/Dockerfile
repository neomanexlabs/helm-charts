# =============================================================================
# OpenCode server container (public image)
# =============================================================================
# Purpose: the image the OpenCode Helm chart in this repository defaults to.
# Upstream ghcr.io/anomalyco/opencode alone is not enough for the chart: the
# init container and the runtime scripts need git and an ssh client, and the
# optional expose/teardown role scripts run kubectl from inside the pod. This
# image adds exactly those, and nothing else.
#
# Base: Alpine. Upstream ships an Alpine image ONLY (there is no Debian-slim
# variant), so the usual Debian-slim base rule cannot apply here without
# forking upstream. Everything layered on top (kubectl is a static Go binary,
# nodejs/npm are packaged by Alpine) is musl-compatible.
#
# The base tag is PINNED through the OPENCODE_VERSION build-arg. Never :latest.
#
# Organization-specific tooling is NOT baked in here. Private derivatives are
# built FROM this image and layer their own CLIs, hooks and toolchains on top,
# so this image and the derivatives never diverge in the shared layers.
# =============================================================================

# Global ARG (before the first FROM) so its value flows into the runtime FROM.
# It must be RE-DECLARED (bare) inside the runtime stage to be visible there.
ARG OPENCODE_VERSION

# -----------------------------------------------------------------------------
# Stage 1: kubectl-fetch -- download + checksum-verify the kubectl binary.
# Isolated so the download toolchain (curl) never lands in the runtime layer.
# -----------------------------------------------------------------------------
FROM alpine:3.21 AS kubectl-fetch

# kubectl v1.33.3 from the official Kubernetes release bucket (static Go
# binary, musl-compatible; linux/amd64 -- this image is Alpine amd64).
# Checksum is the sha256 published by Kubernetes alongside the binary,
# fetched 2026-07-29:
#   https://dl.k8s.io/release/v1.33.3/bin/linux/amd64/kubectl.sha256
ARG KUBECTL_VERSION=1.33.3
ARG KUBECTL_SHA256=2fcf65c64f352742dc253a25a7c95617c2aba79843d1b74e585c69fe4884afb0

RUN apk add --no-cache curl
RUN set -eux; \
    curl -fsSL -o /tmp/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    echo "${KUBECTL_SHA256}  /tmp/kubectl" | sha256sum -c -; \
    install -m 0755 /tmp/kubectl /usr/local/bin/kubectl; \
    /usr/local/bin/kubectl version --client

# -----------------------------------------------------------------------------
# Stage 2: runtime -- upstream opencode + git/ssh + node toolchain + kubectl.
# -----------------------------------------------------------------------------
ARG OPENCODE_VERSION
FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}

ARG OPENCODE_VERSION

LABEL org.opencontainers.image.source="https://github.com/neomanexlabs/helm-charts" \
      org.opencontainers.image.url="https://neomanex.com" \
      org.opencontainers.image.vendor="Neomanex" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.title="opencode" \
      org.opencontainers.image.description="OpenCode server image for the OpenCode Helm chart: upstream OpenCode plus git, openssh-client, node and kubectl, running as a non-root user." \
      org.opencontainers.image.version="${OPENCODE_VERSION}"

# git + openssh-client for repository operations (clone, fetch, push over SSH);
# nodejs/npm for JavaScript project work and MCP tooling launched by the agent;
# bash because the chart's init and lifecycle scripts use bash-only syntax and
# Alpine's busybox ash cannot run them.
RUN apk add --no-cache \
    git \
    openssh-client \
    nodejs \
    npm \
    bash

# kubectl from its fetch stage -- the optional expose/teardown scripts run
# kubectl from inside the pod against the pod's own namespace.
COPY --from=kubectl-fetch /usr/local/bin/kubectl /usr/local/bin/kubectl

# Verify every baked-in tool resolves at build time (fail the build otherwise).
RUN git --version && kubectl version --client && node --version && npm --version && bash --version

# Create non-root user (uid/gid 1000, matching the chart's pod security context).
RUN addgroup -g 1000 opencode && \
    adduser -u 1000 -G opencode -h /home/opencode -s /bin/sh -D opencode

# Create the directories the chart mounts into, owned by the runtime user.
# They must pre-exist owned by uid 1000: kubelet creates any MISSING parent
# directory of a subPath mount as root, which then breaks writes at runtime.
RUN mkdir -p /home/opencode/.ssh \
             /home/opencode/.local/share/opencode \
             /home/opencode/.config \
             /workspace && \
    chown -R opencode:opencode /home/opencode /workspace

USER opencode
WORKDIR /workspace

EXPOSE 4096

ENTRYPOINT ["opencode", "serve", "--port", "4096", "--hostname", "0.0.0.0", "--print-logs"]
