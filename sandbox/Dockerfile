# One image lineage, two stages, one toolchain manager.
#
# sandbox: the worker image following the self-hosted sandbox integration
#   guide (platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes).
#   Contract requirements: /bin/bash at that exact path, curl only needed at
#   build time, WORKDIR and VOLUME are /workspace, default entrypoint runs
#   one session and exits. The compose worker service overrides the
#   entrypoint to run the always-on poller.
#
# dev: a thin devcontainer stage on top of sandbox for working on this repo
#   with Claude Code, adapted from anthropics/claude-code/.devcontainer.
#   Both services build from this file with the repo root as context.
#
# Version pins live in sandbox/mise.toml and sandbox/mise.dev.toml, not in
# ARGs here. apk owns the OS layer (musl, bash, git, python, node); mise owns
# the pinned developer toolchain. That line is drawn where it is because mise
# has no musl prebuilds for python or node and would compile them from source.

FROM alpine:3 AS sandbox

#ARG MISE_VERSION=v2026.8.0

# mise resolves its config globally so shims work for every user and every
# shell, including non-login exec into the container. Data lives outside
# /root so the dev stage's unprivileged user can read the same installs.
# MISE_CACHE_DIR is deliberately left at its default ($HOME/.cache/mise):
# shims write to it on every invocation, so it has to be per-user writable.
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml \
    MISE_YES=1 \
    PATH=/usr/local/share/mise/shims:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

# gcompat, libstdc++ and libgcc are the price of Alpine: several of the
# pinned binaries (bun among them) are built against glibc.
# RUN apk add --no-cache \
#     bash ca-certificates curl git python3 tar xz unzip \
#     gcompat libstdc++ libgcc \
#     && ln -sf python3 /usr/bin/python

#RUN curl -fsSL https://mise.run | sh     && mise --version

RUN apk add --no-cache mise bash ca-certificates curl git wget libstdc++

# Copy only what this stage needs. `COPY . .` landed the whole build context in
# `/` — including node_modules and .git — and, with no WORKDIR set yet, put the
# script at /sandbox/bootstrap-mise.sh while the next line looked for
# /bootstrap-mise.sh. The build failed there with
# "chmod: bootstrap-mise.sh: No such file or directory".
COPY sandbox/bootstrap-mise.sh /usr/local/bin/bootstrap-mise.sh
RUN chmod +x /usr/local/bin/bootstrap-mise.sh && /usr/local/bin/bootstrap-mise.sh

RUN mise --version
#RUN mise use -g ripgrep@latest jq@latest bun@latest opencode@latest npm@latest pnpm@latest docker-slim@latest docker-cli@latest delta@latest npm@latest node@latest ripgrep@latest gh@latest fzf@latest uv@latest
# sandbox/mise.toml, not the repo-root mise.toml. The build context is the repo
# root, so the bare name resolved to the wrong file and silently shipped the
# host toolchain manifest instead of the image's. CLAUDE.md: "Version pins live
# in sandbox/mise.toml and sandbox/mise.dev.toml".
COPY sandbox/mise.toml /etc/mise/config.toml
RUN mise install && mise reshim && rm -rf /root/.cache/mise

WORKDIR /workspace
VOLUME /workspace

ENTRYPOINT ["ant", "beta:worker", "run"]

# ---------------------------------------------------------------------------

FROM sandbox AS dev

ARG TZ=America/Chicago
ENV TZ="$TZ"
ENV DEVCONTAINER=true

# Tooling from the upstream Claude Code devcontainer, plus the firewall
# dependencies its init script needs (iptables, ipset, dig). nodejs and npm
# are the runtime for the npm-backed agents in sandbox/mise.dev.toml.
# RUN apk add --no-cache \
#     less procps sudo zsh man-db gnupg wget tzdata shadow \
#     iptables ipset iproute2 bind-tools vim openssh-client

# The upstream firewall script pipes GitHub's CIDR list through `aggregate`,
# which Alpine does not package. Aggregation only collapses overlapping
# ranges before they reach ipset — dropping it costs a longer set, not a
# different policy — so a passthrough keeps the upstream script unmodified.
# RUN printf '#!/bin/sh\n# Alpine has no `aggregate`; see sandbox/Dockerfile. Dedupe only.\nsort -u\n' \
#     > /usr/local/bin/aggregate \
#     && chmod +x /usr/local/bin/aggregate

# COPY mise.dev.toml /etc/mise/conf.d/dev.toml
# RUN mise install && mise reshim && rm -rf /root/.cache/mise \
#     && chmod -R a+rX "${MISE_DATA_DIR}"

# --- additional coding agents ----------------------------------------------
# The dev image is a multi-agent environment, not Claude-specific. Auth for
# every agent is a run-later step; see the README's coding agents section.
#
# These stay on npm rather than in sandbox/mise.dev.toml because mise's npm
# backend does not run postinstall scripts, and both packages resolve their
# platform-native binary from one. npm also honours the `libc` field, so it
# picks the musl build where the publisher ships it.
#
# @github/copilot is excluded on purpose: its prebuilt binary is dynamically
# linked against glibc and dies on musl with `fcntl64: symbol not found`,
# which gcompat cannot shim. It needs a glibc base image, not a flag.
# ARG OPENCODE_VERSION=1.18.11
# ARG OPENCHAMBER_VERSION=1.17.2
# RUN npm install -g --no-fund --no-audit \
#     "opencode-ai@${OPENCODE_VERSION}" \
#     "@openchamber/web@${OPENCHAMBER_VERSION}" \
#     && npm cache clean --force

# Non-root user. The upstream devcontainer inherits the node user from its
# base image; this lineage has none, so create one.
ARG USERNAME=dev
RUN adduser -D -u 1000 -s /bin/zsh "$USERNAME" && \
    mkdir -p /commandhistory "/home/${USERNAME}/.claude" && \
    touch /commandhistory/.bash_history && \
    chown -R "$USERNAME:$USERNAME" /commandhistory "/home/${USERNAME}/.claude" /workspace

# Firewall script from the upstream devcontainer, runnable via sudo only.
# COPY ../.devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
# RUN chmod +x /usr/local/bin/init-firewall.sh && \
#     echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/dev-firewall && \
#     chmod 0440 /etc/sudoers.d/dev-firewall

# USER $USERNAME
# ENV SHELL=/bin/zsh
# ENV EDITOR=vim
# ENV CLAUDE_CONFIG_DIR=/home/dev/.claude

# ARG ZSH_IN_DOCKER_VERSION=1.2.0
# RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
#     -p git \
#     -a 'eval "$(fzf --zsh)"' \
#     -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
#     -x

# Claude Code through the native installer. Its npm package resolves the real
# binary from a postinstall script that mise's npm backend never runs, and the
# native installer is the upstream-documented path for a Node-less lineage
# anyway — it ships a musl build and needs neither node nor bun.
# ARG CLAUDE_CODE_VERSION=latest
# RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "$CLAUDE_CODE_VERSION"
# ENV PATH="/home/dev/.local/bin:$PATH"

ENTRYPOINT []
CMD ["sleep", "infinity"]
