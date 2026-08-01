# Cloudflare Sandboxes container image. Cloudflare requires extending its
# base image, so this backend cannot literally share the Debian base of
# sandbox/Dockerfile; instead it re-applies the same provisioning steps (ant
# CLI and Bun, pinned to the same versions) on top of the Cloudflare base,
# keeping the runtime contents aligned across backends. Bump the base tag
# together with the @cloudflare/sandbox dependency; images must run on
# linux/amd64.

FROM docker.io/cloudflare/sandbox:0.7.18

ARG ANT_VERSION=1.21.0
ARG BUN_VERSION=1.3.14

# The ant CLI, so a sandbox can run Anthropic self-hosted sessions with
# `ant beta:worker poll` exactly like the compose worker does.
RUN curl -fsSL "https://github.com/anthropics/anthropic-cli/releases/download/v${ANT_VERSION}/ant_${ANT_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin ant

# Bun, matching the compose sandbox image.
RUN curl -fsSL https://bun.com/install | BUN_INSTALL=/usr/local/bun bash -s -- "bun-v${BUN_VERSION}" \
    && ln -sf /usr/local/bun/bin/bun /usr/local/bin/bun \
    && ln -sf /usr/local/bun/bin/bunx /usr/local/bin/bunx

# Required for local dev port exposure.
EXPOSE 8080
