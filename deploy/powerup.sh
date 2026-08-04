#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ssh_args.sh"

SERVER="${DEPLOY_SERVER:-deploy@guild-sync.net}"
SERVICE="${DEPLOY_SERVICE:-guildsync}"

build_deploy_ssh_args

ssh "${DEPLOY_SSH_ARGS[@]}" "$SERVER" bash -s <<EOF
set -euo pipefail

echo "== Starting Rails service =="
sudo systemctl start "$SERVICE"

echo "== Disabling maintenance mode =="
sudo rm -f /var/www/maintenance/enable

echo "== Verifying service =="
if ! sudo systemctl is-active --quiet "$SERVICE"; then
  echo "Service failed to start"
  exit 1
fi

echo "Server is live again."
EOF
