# systemd-claude-sandbox workflow.
# Requires: just, docker with the compose plugin, bun >= 1.3.
# Remote recipes use the `bb1` SSH host alias from your SSH config; no host,
# port, or user data is inlined here. Nothing connects until you run a
# deploy or remote recipe yourself.

remote := env_var_or_default("SANDBOX_REMOTE", "bb1")

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

# Stage the stack on the remote and install it. Uses the `bb1` alias.
deploy:
    rsync -az --exclude node_modules --exclude .attic --exclude .git --exclude .env \
        ./ {{remote}}:/tmp/claude-sandbox-stage/stack/
    ssh {{remote}} sudo bash /tmp/claude-sandbox-stage/stack/scripts/deploy-bb1.sh /tmp/claude-sandbox-stage

remote-up:
    ssh {{remote}} sudo systemctl start claude-sandbox.service

remote-down:
    ssh {{remote}} sudo systemctl stop claude-sandbox.service

remote-status:
    ssh {{remote}} "systemctl status claude-sandbox.service --no-pager; cd /opt/claude-sandbox && docker compose ps"

remote-logs:
    ssh {{remote}} "cd /opt/claude-sandbox && docker compose logs -f --tail 100"

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

# --- repo -------------------------------------------------------------------

# Create the private GitHub repo and push (run once, needs gh auth).
publish:
    gh repo create danielbodnar/systemd-claude-sandbox --private --source=. --remote=origin --push
