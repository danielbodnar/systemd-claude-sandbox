#!/bin/bash
# Installs the sandbox stack on the target host. Runs ON the host, invoked
# by `just deploy` with the staging directory as the only argument.
# Idempotent. Requires docker with the compose plugin.
set -euo pipefail

STAGE="${1:?usage: deploy-bb1.sh <staging-dir>}"
DEST=/opt/claude-sandbox

echo "==> staging stack into ${DEST}"
mkdir -p "$DEST"
rsync -a --delete --exclude node_modules --exclude .env "${STAGE}/stack/" "$DEST/"

if [[ ! -f "$DEST/.env" ]]; then
        install -m 0640 "$DEST/.env.example" "$DEST/.env"
        echo "NOTE: fill in $DEST/.env (environment key and id) before starting."
fi

echo "==> building images"
(cd "$DEST" && docker compose build)

echo "==> installing systemd unit"
install -Dm0644 "${STAGE}/stack/host/systemd/claude-sandbox.service" \
        /etc/systemd/system/claude-sandbox.service
systemctl daemon-reload

echo "==> done. enable with: systemctl enable --now claude-sandbox.service"
