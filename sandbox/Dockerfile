# Sandbox worker image, following the self-hosted sandbox integration guide
# (platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes).
# Contract requirements: /bin/bash must exist at that exact path, curl is
# only needed at build time, WORKDIR and VOLUME are /workspace, and the
# default entrypoint runs one session and exits (spawn-per-session mode).
# The compose service overrides the entrypoint to run the always-on poller.

FROM debian:trixie-slim

ARG ANT_VERSION=1.21.0
ARG BUN_VERSION=1.3.14
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates curl git python3 ripgrep jq unzip tar xz-utils \
    && rm -rf /var/lib/apt/lists/*

# The ant CLI is the worker runtime.
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo arm64 || echo amd64) && \
    curl -fsSL "https://github.com/anthropics/anthropic-cli/releases/download/v${ANT_VERSION}/ant_${ANT_VERSION}_linux_${ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin ant

# Bun for JS and TS execution inside sessions and for bunx-launched MCP servers.
RUN curl -fsSL https://bun.com/install | BUN_INSTALL=/usr/local/bun bash -s -- "bun-v${BUN_VERSION}" \
    && ln -s /usr/local/bun/bin/bun /usr/local/bin/bun \
    && ln -s /usr/local/bun/bin/bunx /usr/local/bin/bunx

WORKDIR /workspace
VOLUME /workspace

ENTRYPOINT ["ant", "beta:worker", "run"]
