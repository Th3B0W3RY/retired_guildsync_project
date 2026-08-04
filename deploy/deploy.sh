#!/usr/bin/env bash
set -euo pipefail

# Monorepo: clone root contains `guildsync/` (Rails) and `deploy/`. Override for a new VM:
#   export DEPLOY_SERVER="deploy@your.host" DEPLOY_APP_DIR="/var/www/guildsync" DEPLOY_BRANCH="main"
#   export DEPLOY_IP_FAMILY=4   # force IPv4 when hostname AAAA causes SSH timeouts
# Default deploy branch is `development`; override with DEPLOY_BRANCH when needed.
#
# GitHub: default clone URL is SSH (git@github.com:...) — use a deploy key on the VM (~/.ssh/config).
# Override for HTTPS + token (e.g. no deploy key): DEPLOY_REPO=https://github.com/Th3B0W3RY/GuildSync.git DEPLOY_GITHUB_TOKEN=<github_pat> bash deploy.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ssh_args.sh"

SERVER="${DEPLOY_SERVER:-deploy@guild-sync.net}"
APP_DIR="${DEPLOY_APP_DIR:-/var/www/guildsync}"
BRANCH="${DEPLOY_BRANCH:-development}"
REPO="${DEPLOY_REPO:-git@github.com:Th3B0W3RY/GuildSync.git}"
SERVICE="${DEPLOY_SERVICE:-guildsync}"
GITHUB_TOKEN="${DEPLOY_GITHUB_TOKEN:-}"

build_deploy_ssh_args

ssh "${DEPLOY_SSH_ARGS[@]}" "$SERVER" bash -s <<EOF
set -euo pipefail

APP_DIR="$APP_DIR"
BRANCH="$BRANCH"
REPO="$REPO"
SERVICE="$SERVICE"
GITHUB_TOKEN="$GITHUB_TOKEN"

# Safety net: if anything below fails after services are stopped, restart web + Sidekiq (same .env).
trap 'echo "!! Deploy step failed — restarting \$SERVICE and \${SERVICE}-sidekiq !!"; sudo systemctl start "\$SERVICE" 2>/dev/null || true; sudo systemctl start "\${SERVICE}-sidekiq" 2>/dev/null || true' ERR

echo "== Ensuring app directory exists =="
sudo mkdir -p "\$APP_DIR"
sudo chown -R \$(whoami):\$(whoami) "\$APP_DIR"

# Git over SSH: fresh VMs have no github.com in known_hosts → "Host key verification failed".
mkdir -p "\$HOME/.ssh"
chmod 700 "\$HOME/.ssh"
touch "\$HOME/.ssh/known_hosts"
chmod 600 "\$HOME/.ssh/known_hosts"
export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new'

# Authenticated HTTPS URL when DEPLOY_GITHUB_TOKEN is set (private repos). SSH URLs unchanged (use deploy key on VM).
if [ -n "\${GITHUB_TOKEN:-}" ] && [[ "\$REPO" == https://* ]]; then
  REPO_EFFECTIVE="https://x-access-token:\${GITHUB_TOKEN}@\${REPO#https://}"
elif [ -n "\${GITHUB_TOKEN:-}" ] && [[ "\$REPO" == http://* ]]; then
  REPO_EFFECTIVE="https://x-access-token:\${GITHUB_TOKEN}@\${REPO#http://}"
else
  REPO_EFFECTIVE="\$REPO"
fi

echo "== Checking repository state =="

if [ ! -d "\$APP_DIR/.git" ]; then
  echo "Cloning fresh repository..."
  git clone "\$REPO_EFFECTIVE" "\$APP_DIR"
  chmod -R go-rwx "\$APP_DIR/.git" 2>/dev/null || true
else
  echo "Updating existing repository..."
  cd "\$APP_DIR"
  git remote set-url origin "\$REPO_EFFECTIVE"
  chmod -R go-rwx "\$APP_DIR/.git" 2>/dev/null || true
  git fetch origin
  git reset --hard "origin/\$BRANCH"
fi

cd "\$APP_DIR"

echo "== Stopping services =="
sudo systemctl stop "\$SERVICE" || true
sudo systemctl stop "\${SERVICE}-sidekiq" || true

echo "== Initializing Ruby (rbenv) =="
export RBENV_ROOT="\$HOME/.rbenv"
export PATH="\$RBENV_ROOT/bin:\$RBENV_ROOT/shims:/usr/local/bin:/usr/bin:/bin"
eval "\$(rbenv init - bash)"

export RAILS_ENV=production
export RACK_ENV=production
export RAILS_SERVE_STATIC_FILES=true
# Discord gateway check during deploy is often flaky; skip by default. Set DEPLOY_SKIP_DISCORD_GATEWAY_CHECK=0 on the server to force the check.
export DEPLOY_SKIP_DISCORD_GATEWAY_CHECK="\${DEPLOY_SKIP_DISCORD_GATEWAY_CHECK:-1}"

# Load .env and ensure minimum secrets for production boot (migrations, assets, etc.).
# Without SECRET_KEY_BASE / AR encryption keys, Rails raises before db:migrate. First deploy
# may omit .env: we append stable keys to guildsync/.env so later runs reuse them.
ENV_FILE="\$APP_DIR/guildsync/.env"
mkdir -p "\$(dirname "\$ENV_FILE")"
if [ ! -f "\$ENV_FILE" ]; then
  umask 077
  touch "\$ENV_FILE"
fi
chmod 600 "\$ENV_FILE" 2>/dev/null || true

echo "Loading environment variables from .env (if any)..."
set -a
source "\$ENV_FILE" 2>/dev/null || true
set +a

if [ -z "\${SECRET_KEY_BASE:-}" ]; then
  _skb=\$(openssl rand -hex 64)
  echo "SECRET_KEY_BASE=\$_skb" >> "\$ENV_FILE"
  export SECRET_KEY_BASE="\$_skb"
  echo "== Wrote SECRET_KEY_BASE to \$ENV_FILE (required for production; keep this file) =="
fi
if [ -z "\${ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY:-}" ]; then
  _epk=\$(openssl rand -hex 16)
  _edk=\$(openssl rand -hex 16)
  _esl=\$(openssl rand -hex 16)
  echo "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=\$_epk" >> "\$ENV_FILE"
  echo "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=\$_edk" >> "\$ENV_FILE"
  echo "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=\$_esl" >> "\$ENV_FILE"
  export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="\$_epk"
  export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="\$_edk"
  export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="\$_esl"
  echo "== Wrote Active Record encryption keys to \$ENV_FILE (required for production) =="
fi

set -a
source "\$ENV_FILE" 2>/dev/null || true
set +a

# Production email: GuildSync::ProductionActionMailerSmtp applies Resend-style SMTP from ENV after boot;
# SMTP_PASSWORD is required. systemd units for Puma and Sidekiq must use the same EnvironmentFile
# (deploy/guildsync.service and guildsync-sidekiq.service) so mail jobs do not fall back to localhost:25.
# Add SMTP_* and MAILER_FROM to guildsync/.env on the server, then redeploy and restart both services.
if [ -z "\${SMTP_PASSWORD:-}" ]; then
  echo "ERROR: SMTP_PASSWORD must be set in \$ENV_FILE (Resend API key). Production boot and db:migrate require it."
  exit 1
fi

echo "== Installing gems =="
cd guildsync
bundle config set deployment true
bundle config set without 'development test'
bundle install --jobs 4 --retry 3

echo "== Installing Node dependencies (esbuild, etc.) =="
if [ -f package-lock.json ] && command -v npm >/dev/null 2>&1; then
  npm ci
else
  command -v yarn >/dev/null 2>&1 && yarn install || npm install
fi

echo "== Ensuring builds directory exists =="
mkdir -p app/assets/builds

echo "== Running migrations =="
bundle exec rails db:migrate

echo "== Verifying services =="
bundle exec rails guildsync:service_status

echo "== Cleaning old assets =="
bundle exec rails assets:clobber
bundle exec rails tmp:clear

echo "== Building JS bundle + Tailwind CSS =="
if command -v yarn >/dev/null 2>&1; then
  yarn build
  yarn build:css
else
  npm run build
  npm run build:css
fi

echo "== Precompiling assets =="
bundle exec rails assets:precompile

echo "== Updating maintenance page =="
sudo mkdir -p /var/www/maintenance
sudo cp "\$APP_DIR/deploy/maintenance.html" /var/www/maintenance/index.html
sudo chown -R www-data:www-data /var/www/maintenance 2>/dev/null || true

echo "== Installing systemd units (from repo, if present) =="
for unit in guildsync.service guildsync-sidekiq.service; do
  if [ -f "\$APP_DIR/deploy/\$unit" ]; then
    sudo install -m 644 "\$APP_DIR/deploy/\$unit" "/etc/systemd/system/\$unit"
  fi
done

# Verify SMTP while services are STOPPED. Booting Rails here (rather than after the
# restart) avoids a daily log-roll race between Puma, Sidekiq, and this rake task on
# the shared production.log (logging gem rename of *._copy_ -> *.YYYYMMDD.log).
# Uses the same ENV_FILE that systemd loads via EnvironmentFile for both services.
echo "== Verifying production mailer SMTP (ENV must match systemd EnvironmentFile for Sidekiq) =="
set -a
source "\$ENV_FILE" 2>/dev/null || true
set +a
cd "\$APP_DIR/guildsync"
bundle exec rake guildsync:verify_production_mailer_config

echo "== Restarting services =="
sudo systemctl daemon-reload
sudo systemctl enable "\$SERVICE" "\${SERVICE}-sidekiq" 2>/dev/null || true
sudo systemctl start "\$SERVICE"
sudo systemctl start "\${SERVICE}-sidekiq"

echo "== Verifying services =="
if ! sudo systemctl is-active --quiet "\$SERVICE"; then
  echo "Puma service failed to start"
  exit 1
fi
if ! sudo systemctl is-active --quiet "\${SERVICE}-sidekiq"; then
  echo "Sidekiq service failed to start — background jobs will not process!"
  exit 1
fi

echo "Deploy complete."
EOF
