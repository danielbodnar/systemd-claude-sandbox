#!/usr/bin/env bash
# install.sh: clone, prepare, and launch systemd-claude-sandbox using
# whatever tooling the host already has. Probes before it picks, prints its
# decision trail, and delegates real work to the justfile and compose files
# rather than duplicating them.
#
# Supported interpreters: bash on Linux, macOS, WSL, and Git Bash. From
# PowerShell this script does not run directly; invoke it through one of
#   wsl bash ./install.sh          (inside a WSL distro)
#   & 'C:\Program Files\Git\bin\bash.exe' ./install.sh   (Git Bash)
#
# Idempotent: safe to re-run inside an existing clone; it never re-clones,
# never pipes downloads into a shell, and installs nothing system-wide.
#
# Environment overrides:
#   CLAUDE_SANDBOX_DIR   clone destination (default: ~/code/systemd-claude-sandbox)
#   CLAUDE_SANDBOX_MODE  skip detection: compose | devcontainer | bare | wsl

set -euo pipefail

REPO_URL="https://github.com/danielbodnar/systemd-claude-sandbox.git"
CLONE_DIR="${CLAUDE_SANDBOX_DIR:-$HOME/code/systemd-claude-sandbox}"
MODE="${CLAUDE_SANDBOX_MODE:-auto}"

say()  { printf '%s\n' "$*"; }
note() { printf 'install.sh: %s\n' "$*"; }
die()  { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- platform ---------------------------------------------------------------

platform=linux
case "$(uname -s)" in
        Darwin) platform=macos ;;
        MINGW*|MSYS*|CYGWIN*) platform=windows ;;
esac
is_wsl=no
if [ "$platform" = linux ] && grep -qi microsoft /proc/version 2>/dev/null; then
        is_wsl=yes
fi
note "platform: ${platform}$( [ "$is_wsl" = yes ] && printf ' (WSL)')"

# --- clone (idempotent) -----------------------------------------------------

have git || die "git is required; install it and re-run"

if git rev-parse --show-toplevel >/dev/null 2>&1 &&
   [ -f "$(git rev-parse --show-toplevel)/compose.yaml" ] &&
   grep -q systemd-claude-sandbox "$(git rev-parse --show-toplevel)/README.md" 2>/dev/null; then
        CLONE_DIR="$(git rev-parse --show-toplevel)"
        note "already inside a clone: ${CLONE_DIR}"
elif [ -d "${CLONE_DIR}/.git" ]; then
        note "existing clone found at ${CLONE_DIR}; leaving it as-is (no auto-pull)"
else
        note "cloning ${REPO_URL} -> ${CLONE_DIR}"
        git clone "$REPO_URL" "$CLONE_DIR"
fi
cd "$CLONE_DIR"

# --- probes -----------------------------------------------------------------

engine=""
if have docker && docker info >/dev/null 2>&1; then
        engine=docker
elif have podman && podman info >/dev/null 2>&1; then
        engine=podman
fi

compose=""
if [ "$engine" = docker ] && docker compose version >/dev/null 2>&1; then
        compose="docker compose"
elif [ "$engine" = podman ]; then
        if podman compose version >/dev/null 2>&1; then compose="podman compose";
        elif have podman-compose; then compose="podman-compose"; fi
fi

has_bun=no;  have bun  && has_bun=yes
has_just=no; have just && has_just=yes
has_code=no; have code && has_code=yes
devctl=""
if have devcontainer; then devctl="devcontainer";
elif [ "$has_bun" = yes ]; then devctl="bunx @devcontainers/cli"; fi

note "probes: engine=${engine:-none} compose=${compose:-none} bun=${has_bun} just=${has_just} vscode=${has_code} devcontainer-cli=${devctl:-none}"

# --- launch modes (thin glue over the justfile) -----------------------------

launch_compose() {
        [ -n "$compose" ] || die "no compose-capable engine detected"
        [ -f .env ] || { cp .env.example .env; note "created .env from .env.example; fill in the Anthropic environment key before the worker can claim sessions"; }
        if [ "$has_just" = yes ]; then
                note "decision: compose stack via just (engine: ${engine})"
                just build && just up && just ps
        else
                note "decision: compose stack via '${compose}' directly (install just for the full workflow)"
                $compose build && $compose up -d && $compose ps
        fi
        say ""
        say "Sandbox stack is up. Tunnel listens on 127.0.0.1:8787; see 'just logs'."
}

launch_devcontainer() {
        [ "$engine" = docker ] || die "the devcontainer requires Docker; detected engine: ${engine:-none}"
        if [ -n "$devctl" ]; then
                note "decision: devcontainer via ${devctl}"
                $devctl up --workspace-folder .
                say ""
                say "Devcontainer running. Shell in with: ${devctl} exec --workspace-folder . zsh"
        elif [ "$has_code" = yes ]; then
                note "decision: devcontainer via VS Code"
                code .
                say "VS Code opened. Use 'Reopen in Container' when prompted."
        else
                die "no devcontainer CLI, bun, or VS Code found to launch the devcontainer"
        fi
}

launch_bare() {
        [ "$has_bun" = yes ] || die "bare-metal mode needs bun (https://bun.com)"
        note "decision: bare-metal dev with bun (no container engine involved)"
        (cd mcp-tunnel && bun install && bun run typecheck && bun test)
        say ""
        say "mcp-tunnel is ready. Run it with:"
        say "  cd ${CLONE_DIR}/mcp-tunnel && bun run src/index.ts --config ../examples/tunnel.jsonc"
        say "The sandbox worker itself needs a container engine; install Docker or Podman for the full stack."
}

launch_wsl() {
        have wsl.exe || die "wsl.exe not found"
        wsl.exe -l -q 2>/dev/null | tr -d '\r\0' | grep -q . || die "WSL is present but has no installed distro; run: wsl --install"
        note "decision: re-running inside the default WSL distro"
        winpath="$(pwd -W 2>/dev/null || pwd)"
        exec wsl.exe --cd "$winpath" -- bash ./install.sh
}

prompt_choice() {
        say ""
        say "No launch path could be chosen automatically. Available options:"
        say "  1) Install Docker Desktop, then re-run for the compose stack or devcontainer"
        say "  2) Install WSL (wsl --install), then re-run to use the Linux path"
        [ "$has_bun" = yes ] && say "  3) Bare-metal dev with bun (mcp-tunnel only, no sandbox worker)"
        if [ -t 0 ]; then
                printf 'Choose an option number (or q to quit): '
                read -r choice
                case "$choice" in
                        3) if [ "$has_bun" = yes ]; then launch_bare; else die "option 3 requires bun"; fi ;;
                        1|2) say "Re-run this script after installing."; exit 0 ;;
                        *) exit 0 ;;
                esac
        else
                die "non-interactive shell; set CLAUDE_SANDBOX_MODE or install one of the tools above"
        fi
}

# --- decision ---------------------------------------------------------------

case "$MODE" in
        compose)      launch_compose ;;
        devcontainer) launch_devcontainer ;;
        bare)         launch_bare ;;
        wsl)          launch_wsl ;;
        auto)
                if [ "$platform" = windows ]; then
                        # Native Windows (Git Bash). Prefer WSL when installed;
                        # never touch the devcontainer without Docker.
                        if have wsl.exe && wsl.exe -l -q 2>/dev/null | tr -d '\r\0' | grep -q .; then
                                launch_wsl
                        elif [ "$engine" = docker ] && { [ -n "$devctl" ] || [ "$has_code" = yes ]; }; then
                                launch_devcontainer
                        else
                                prompt_choice
                        fi
                else
                        # Linux, macOS, WSL: full stack when compose exists,
                        # devcontainer when only docker+tooling exists, bun
                        # bare-metal as the floor.
                        if [ -n "$compose" ]; then
                                launch_compose
                        elif [ "$engine" = docker ] && [ -n "$devctl" ]; then
                                launch_devcontainer
                        elif [ "$has_bun" = yes ]; then
                                launch_bare
                        else
                                prompt_choice
                        fi
                fi
                ;;
        *) die "unknown CLAUDE_SANDBOX_MODE: ${MODE} (compose|devcontainer|bare|wsl)" ;;
esac
