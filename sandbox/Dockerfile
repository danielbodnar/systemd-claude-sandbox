# One image lineage, two stages.
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

FROM debian:trixie-slim AS sandbox

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

# ---------------------------------------------------------------------------

FROM sandbox AS dev

ARG TZ=America/Chicago
ENV TZ="$TZ"
ENV DEVCONTAINER=true

# Tooling from the upstream Claude Code devcontainer, plus the firewall
# dependencies its init script needs (iptables, ipset, aggregate, dig).
RUN apt-get update && apt-get install -y --no-install-recommends \
        less procps sudo fzf zsh man-db gnupg2 gh wget \
        iptables ipset iproute2 dnsutils aggregate nano vim openssh-client \
    && rm -rf /var/lib/apt/lists/*

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
    wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
    rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Non-root user. The upstream devcontainer inherits the node user from its
# base image; this lineage has none, so create one.
ARG USERNAME=dev
RUN useradd -m -u 1000 -s /bin/zsh "$USERNAME" && \
    mkdir -p /commandhistory "/home/${USERNAME}/.claude" && \
    touch /commandhistory/.bash_history && \
    chown -R "$USERNAME:$USERNAME" /commandhistory "/home/${USERNAME}/.claude" /workspace

# Firewall script from the upstream devcontainer, runnable via sudo only.
COPY .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh && \
    echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/dev-firewall && \
    chmod 0440 /etc/sudoers.d/dev-firewall

# --- additional coding agents ----------------------------------------------
# The dev image is a multi-agent environment, not Claude-specific. Each agent
# is installed by its upstream-documented method and pinned. Auth for every
# agent is a run-later step; see the README's coding agents section.

# Node.js 22 (nodesource): required by @github/copilot and @openchamber/web,
# neither of which runs on Bun alone. Debian trixie ships an older nodejs.
ARG NODE_MAJOR=22
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# jcode (1jehuang/jcode, MIT): single Rust binary from a pinned GitHub
# release, verified against the published SHA256SUMS. Trust note: jcode is a
# young third-party project; the checksum pin means upgrades are deliberate.
ARG JCODE_VERSION=0.64.2
RUN cd /tmp && \
    curl -fsSLO "https://github.com/1jehuang/jcode/releases/download/v${JCODE_VERSION}/jcode-linux-x86_64.tar.gz" && \
    curl -fsSLO "https://github.com/1jehuang/jcode/releases/download/v${JCODE_VERSION}/SHA256SUMS" && \
    grep "jcode-linux-x86_64.tar.gz" SHA256SUMS | sha256sum -c - && \
    tar -xzf jcode-linux-x86_64.tar.gz -C /usr/local/bin jcode && \
    rm -f jcode-linux-x86_64.tar.gz SHA256SUMS

# opencode (sst/opencode) and GitHub Copilot CLI (@github/copilot), plus
# OpenChamber (openchamber/openchamber), the web and desktop interface for
# opencode. All three ship on npm; exact-version pins.
ARG OPENCODE_VERSION=1.18.11
ARG COPILOT_CLI_VERSION=1.0.77
ARG OPENCHAMBER_VERSION=1.17.2
RUN npm install -g --no-fund --no-audit \
        "opencode-ai@${OPENCODE_VERSION}" \
        "@github/copilot@${COPILOT_CLI_VERSION}" \
        "@openchamber/web@${OPENCHAMBER_VERSION}"

USER $USERNAME
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

ARG ZSH_IN_DOCKER_VERSION=1.2.0
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v${ZSH_IN_DOCKER_VERSION}/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x

# Claude Code through the native installer; this lineage carries Bun, not
# Node, so the upstream npm install path does not apply.
ARG CLAUDE_CODE_VERSION=latest
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "$CLAUDE_CODE_VERSION"
ENV PATH="/home/dev/.local/bin:$PATH"
ENV CLAUDE_CONFIG_DIR=/home/dev/.claude

ENTRYPOINT []
CMD ["sleep", "infinity"]
