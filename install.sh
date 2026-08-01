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

REPO_SLUG="danielbodnar/systemd-claude-sandbox"
CLONE_DIR="${CLAUDE_SANDBOX_DIR:-$HOME/code/systemd-claude-sandbox}"
MODE="${CLAUDE_SANDBOX_MODE:-auto}"
DRY_RUN=no

say()  { printf '%s\n' "$*"; }
note() { printf 'install.sh: %s\n' "$*"; }
die()  { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run()  {
        if [ "$DRY_RUN" = yes ]; then note "[dry-run] $*"; return 0; fi
        "$@"
}
# Post-launch confirmations: suppressed under --dry-run, where announcing
# that something is running would be a lie.
sayr() { [ "$DRY_RUN" = yes ] || printf '%s\n' "$*"; }

usage() {
        cat <<'EOF'
install.sh - clone, prepare, and launch systemd-claude-sandbox

  bash install.sh [--dry-run] [--mode MODE] [--help]

  --dry-run   Probe and report the decision, but launch nothing.
  --mode      compose | devcontainer | bare | wsl  (same as CLAUDE_SANDBOX_MODE)
  --help      This message.

The repository is private: cloning needs an authenticated `gh` CLI or an SSH
key registered with GitHub. Running from an existing checkout needs neither.
EOF
}

while [ $# -gt 0 ]; do
        case "$1" in
                --dry-run|--detect-only) DRY_RUN=yes ;;
                --mode) shift; MODE="${1:-}" ;;
                --mode=*) MODE="${1#*=}" ;;
                --help|-h) usage; exit 0 ;;
                *) die "unknown option: $1 (try --help)" ;;
        esac
        shift
done

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

# Detection only: BatchMode keeps ssh from prompting, and no
# StrictHostKeyChecking override, so probing never writes to known_hosts.
ssh_to_github_works() {
        have ssh || return 1
        ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -T git@github.com 2>&1 |
                grep -q 'successfully authenticated'
}

# The repository is private, so a plain HTTPS clone either hangs on a
# credential prompt or fails outright. Try the credentials that actually
# exist, in order, and say precisely what to do when none do.
clone_repo() {
        if have gh && gh auth status >/dev/null 2>&1; then
                note "cloning ${REPO_SLUG} with gh -> ${CLONE_DIR}"
                run gh repo clone "$REPO_SLUG" "$CLONE_DIR"
        elif ssh_to_github_works; then
                note "cloning ${REPO_SLUG} over SSH -> ${CLONE_DIR}"
                run git clone "git@github.com:${REPO_SLUG}.git" "$CLONE_DIR"
        else
                say ""
                say "${REPO_SLUG} is private and no working GitHub credential was found."
                say "Do one of these, then re-run:"
                say "  gh auth login                                  (recommended)"
                say "  add an SSH key: https://github.com/settings/keys"
                say "Already have a checkout? Run this script from inside it instead."
                die "cannot clone a private repository without credentials"
        fi
}

if git rev-parse --show-toplevel >/dev/null 2>&1 &&
   [ -f "$(git rev-parse --show-toplevel)/compose.yaml" ] &&
   grep -q systemd-claude-sandbox "$(git rev-parse --show-toplevel)/README.md" 2>/dev/null; then
        CLONE_DIR="$(git rev-parse --show-toplevel)"
        note "already inside a clone: ${CLONE_DIR}"
elif [ -d "${CLONE_DIR}/.git" ]; then
        note "existing clone found at ${CLONE_DIR}; leaving it as-is (no auto-pull)"
else
        clone_repo
fi
cd "$CLONE_DIR"

# Docker I/O across the Windows/WSL boundary is slow enough to matter, but
# silently relocating someone's checkout would be worse. Say so and continue.
if [ "$is_wsl" = yes ]; then
        case "$CLONE_DIR" in
                /mnt/*) note "note: checkout is on a Windows drive; container I/O here is markedly slower." ;;
        esac
fi

# --- probes -----------------------------------------------------------------

# `command -v docker` proves nothing: Docker Desktop ships a CLI that exists
# whether or not the engine runs, and `docker info` against an unreachable
# VM can block for a long time. Probe for real, but bounded.
engine_up() {
        have "$1" || return 1
        if have timeout; then
                timeout 20 "$1" info >/dev/null 2>&1
        else
                "$1" info >/dev/null 2>&1
        fi
}

engine=""
if engine_up docker; then
        engine=docker
elif engine_up podman; then
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

# The worker service declares ${ANTHROPIC_ENVIRONMENT_KEY:?...}, so compose
# refuses to build or start until the key is filled in. Detect that here
# rather than letting the stack fail after we have announced a decision.
env_ready=no
if [ -f .env ] && grep -Eq '^[[:space:]]*ANTHROPIC_ENVIRONMENT_KEY=[^[:space:]]+' .env; then
        env_ready=yes
fi

note "probes: engine=${engine:-none} compose=${compose:-none} bun=${has_bun} just=${has_just} vscode=${has_code} devcontainer-cli=${devctl:-none} env=${env_ready}"

# --- launch modes (thin glue over the justfile) -----------------------------

launch_compose() {
        [ -n "$compose" ] || die "no compose-capable engine detected"
        if [ ! -f .env ]; then
                run cp .env.example .env
                note "created .env from .env.example"
        fi
        if [ "$env_ready" = no ]; then
                say ""
                say "The stack cannot start yet: ANTHROPIC_ENVIRONMENT_KEY is empty in"
                say "  ${CLONE_DIR}/.env"
                say "Fill in the environment key and id from the Anthropic console, then:"
                say "  bash install.sh --mode compose"
                die "compose stack needs a populated .env"
        fi
        if [ "$has_just" = yes ]; then
                note "decision: compose stack via just (engine: ${engine})"
                run just build && run just up && run just ps
        else
                note "decision: compose stack via '${compose}' directly (install just for the full workflow)"
                # shellcheck disable=SC2086  # $compose is a command word split on purpose
                run $compose build && run $compose up -d && run $compose ps
        fi
        sayr ""
        sayr "Sandbox stack is up. Tunnel listens on 127.0.0.1:8787; see 'just logs'."
}

launch_devcontainer() {
        [ "$engine" = docker ] || die "the devcontainer requires Docker; detected engine: ${engine:-none}"
        if [ -n "$devctl" ]; then
                note "decision: devcontainer via ${devctl}"
                # shellcheck disable=SC2086  # $devctl is a command word split on purpose
                run $devctl up --workspace-folder .
                sayr ""
                sayr "Devcontainer running. Shell in with: ${devctl} exec --workspace-folder . zsh"
        elif [ "$has_code" = yes ]; then
                note "decision: devcontainer via VS Code"
                run code .
                sayr "VS Code opened. Use 'Reopen in Container' when prompted."
        else
                die "no devcontainer CLI, bun, or VS Code found to launch the devcontainer"
        fi
}

launch_bare() {
        [ "$has_bun" = yes ] || die "bare-metal mode needs bun (https://bun.com)"
        note "decision: bare-metal dev with bun (no container engine involved)"
        run bash -c "cd mcp-tunnel && bun install && bun run typecheck && bun test"
        sayr ""
        sayr "mcp-tunnel is ready. Run it with:"
        sayr "  cd ${CLONE_DIR}/mcp-tunnel && bun run src/index.ts --config ../examples/tunnel.jsonc"
        sayr "The sandbox worker itself needs a container engine; install Docker or Podman for the full stack."
}

launch_wsl() {
        have wsl.exe || die "wsl.exe not found"
        # wsl.exe emits UTF-16LE; without stripping NULs every check below
        # sees byte soup and "succeeds" on an empty distro list.
        wsl.exe -l -q 2>/dev/null | tr -d '\r\0' | grep -q . ||
                die "WSL is present but has no installed distro; run: wsl --install"
        note "decision: re-running inside the default WSL distro"
        if [ "$DRY_RUN" = yes ]; then
                note "[dry-run] would re-exec: wsl.exe -- bash ./install.sh"
                return 0
        fi
        winpath="$(pwd -W 2>/dev/null || pwd)"
        # --cd needs a reasonably current wsl.exe; fall back to a plain
        # re-exec (which starts in the distro's home) when it is rejected.
        exec wsl.exe --cd "$winpath" -- bash ./install.sh ||
                exec wsl.exe -- bash -lc "cd '$winpath' 2>/dev/null || true; bash ./install.sh"
}

prompt_choice() {
        say ""
        say "No launch path could be chosen automatically."
        say ""
        say "What is missing here:"
        case "$engine" in
                "") if have docker || have podman; then
                            say "  container engine  installed but not running - start Docker Desktop or dockerd"
                    else
                            say "  container engine  https://docs.docker.com/get-started/get-docker/"
                    fi ;;
        esac
        [ "$has_bun" = yes ] || say "  bun               https://bun.com/docs/installation"
        [ "$has_code" = yes ] || say "  vscode            https://code.visualstudio.com/download"
        if [ "$platform" = windows ]; then
                say "  wsl               wsl --install  (https://learn.microsoft.com/windows/wsl/install)"
        fi
        say ""
        say "Options:"
        say "  1) Show these links and exit (install something, then re-run)"
        if [ "$has_bun" = yes ]; then
                say "  2) Bare-metal dev with bun now (mcp-tunnel only, no sandbox worker)"
        fi
        if [ "$has_code" = yes ]; then
                say "  3) Open the project in VS Code"
        fi
        say "  q) Quit"

        if [ ! -t 0 ]; then
                die "non-interactive shell; set CLAUDE_SANDBOX_MODE or install one of the tools above"
        fi
        printf 'Choose an option (or q to quit): '
        read -r choice
        case "$choice" in
                1) say "Re-run this script after installing."; exit 0 ;;
                2) if [ "$has_bun" = yes ]; then launch_bare; else die "option 2 requires bun"; fi ;;
                3) if [ "$has_code" = yes ]; then
                           run code .
                           say "VS Code opened. 'Reopen in Container' needs a running Docker engine."
                   else
                           die "option 3 requires VS Code"
                   fi ;;
                *) exit 0 ;;
        esac
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
                        # Linux, macOS, WSL: full stack when compose exists
                        # AND the environment key is filled in, devcontainer
                        # when only docker+tooling exists, bun bare-metal as
                        # the floor. An empty .env is the common first-run
                        # case, and the devcontainer works fine without it.
                        if [ -n "$compose" ] && [ "$env_ready" = yes ]; then
                                launch_compose
                        else
                                if [ -n "$compose" ]; then
                                        note "skipping the compose stack: ANTHROPIC_ENVIRONMENT_KEY is not set in .env"
                                fi
                                if [ "$engine" = docker ] && [ -n "$devctl" ]; then
                                        launch_devcontainer
                                elif [ "$has_bun" = yes ]; then
                                        launch_bare
                                else
                                        prompt_choice
                                fi
                        fi
                fi
                ;;
        *) die "unknown CLAUDE_SANDBOX_MODE: ${MODE} (compose|devcontainer|bare|wsl)" ;;
esac
