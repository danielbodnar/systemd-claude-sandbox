#!/bin/bash
# Called once per claimed work item when running the poller in
# spawn-per-session mode:
#
#   ant beta:worker poll --on-work ./spawn.sh
#
# Each session gets a fresh container and a dedicated output directory on
# the host. The container reads session details from the environment
# variables the poller exports, handles that session, and exits.
set -euo pipefail

OUTDIR="${CLAUDE_SANDBOX_OUTPUTS:-/var/lib/claude-sandbox/outputs}/${ANTHROPIC_SESSION_ID}"
mkdir -p "$OUTDIR"

exec docker run --rm \
        -e ANTHROPIC_SESSION_ID -e ANTHROPIC_ENVIRONMENT_KEY \
        -e ANTHROPIC_WORK_ID -e ANTHROPIC_ENVIRONMENT_ID -e ANTHROPIC_BASE_URL \
        -v "$OUTDIR":/workspace \
        --network claude-sandbox_sandbox \
        --memory 3g --cpus 2 --pids-limit 512 \
        --security-opt no-new-privileges \
        claude-sandbox-worker:latest
