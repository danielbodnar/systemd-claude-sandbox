# systemd-claude-sandbox workflow.
# Requires: just, docker with the compose plugin, bun >= 1.3.
# Remote recipes take the target as an argument (any SSH host alias or
# user@host from your SSH config); no host data is inlined here. Nothing
# connects until you run a deploy or remote recipe yourself.

default:
    @just --list

# --- local stack ------------------------------------------------------------

# Build all images.
build:
    docker compose build

# Bring the stack up locally (worker + mcp-tunnel).
up *args:
    docker compose up -d {{args}}

# Bring the stack up including the proposed cloudflared publisher.
up-cloudflared:
    docker compose --profile cloudflared up -d

down:
    docker compose down

logs *args:
    docker compose logs -f {{args}}

ps:
    docker compose ps

# --- mcp-tunnel development -------------------------------------------------

install:
    cd mcp-tunnel && bun install

typecheck:
    cd mcp-tunnel && bun run typecheck

test:
    cd mcp-tunnel && bun test

# Run the tunnel directly against a config file.
tunnel-dev config="examples/tunnel.jsonc":
    cd mcp-tunnel && bun run src/index.ts --config ../{{config}}

# --- devcontainer -----------------------------------------------------------

# Build and start the Claude Code devcontainer (dev service + features).
devcontainer-up:
    bunx @devcontainers/cli up --workspace-folder .

# Open a shell inside the running devcontainer.
devcontainer-shell:
    bunx @devcontainers/cli exec --workspace-folder . zsh

# Parse and print the resolved devcontainer configuration.
devcontainer-config:
    bunx @devcontainers/cli read-configuration --workspace-folder . --include-merged-configuration

# --- deploy (run manually; connects over SSH) -------------------------------

# Stage the stack on any SSH-reachable Linux host and install it.
# Example: just deploy host=my-server
deploy host:
    rsync -az --exclude node_modules --exclude .attic --exclude .git --exclude .env \
        ./ {{host}}:/tmp/claude-sandbox-stage/stack/
    ssh {{host}} sudo bash /tmp/claude-sandbox-stage/stack/scripts/deploy.sh /tmp/claude-sandbox-stage

remote-up host:
    ssh {{host}} sudo systemctl start claude-sandbox.service

remote-down host:
    ssh {{host}} sudo systemctl stop claude-sandbox.service

remote-status host:
    ssh {{host}} "systemctl status claude-sandbox.service --no-pager; cd /opt/claude-sandbox && docker compose ps"

remote-logs host:
    ssh {{host}} "cd /opt/claude-sandbox && docker compose logs -f --tail 100"

# --- cloudflare backend -----------------------------------------------------

cf-install:
    cd backends/cloudflare && bun install

cf-typecheck:
    cd backends/cloudflare && bun run typecheck

# Run-later recipes: these need an authenticated wrangler and, for cf-dev,
# a local Docker daemon.
cf-dev:
    cd backends/cloudflare && bunx wrangler dev

cf-deploy:
    cd backends/cloudflare && bunx wrangler deploy

# --- documentation ----------------------------------------------------------

# Starlight dev server for the docs site.
docs-dev:
    cd site && bun install && bun run dev

# Production build with link validation.
docs-build:
    cd site && bun install && bun run build

# Render every VHS tape in .tapes/ to GIFs under .tapes/out/.
# Requires charmbracelet/vhs (https://github.com/charmbracelet/vhs).
tapes:
    mkdir -p .tapes/out
    for tape in .tapes/*.tape; do vhs "$tape"; done

# --- repo -------------------------------------------------------------------

# Create the private GitHub repo if missing, push, and enable GitHub Pages
# with the Actions source (idempotent, needs gh auth). If the Pages API call
# fails, enable it manually: Settings -> Pages -> Source: GitHub Actions.
publish:
    gh repo view danielbodnar/systemd-claude-sandbox >/dev/null 2>&1 || \
        gh repo create danielbodnar/systemd-claude-sandbox --private
    git remote get-url origin >/dev/null 2>&1 || \
        git remote add origin https://github.com/danielbodnar/systemd-claude-sandbox.git
    git push -u origin main
    gh api repos/danielbodnar/systemd-claude-sandbox/pages -X POST -f build_type=workflow 2>/dev/null || \
        gh api repos/danielbodnar/systemd-claude-sandbox/pages -X PUT -f build_type=workflow 2>/dev/null || \
        echo "Pages API call failed; enable manually: Settings -> Pages -> Source: GitHub Actions"
