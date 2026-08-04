#!/usr/bin/env bash
set -euo pipefail

# Override: export DEPLOY_SERVER="deploy@your.host"
# Optional TLS on first boot (DNS must point at this host :80):
#   export PROVISION_ISSUE_CERT=1 CERTBOT_EMAIL=ops@example.com
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ssh_args.sh"

SERVER="${DEPLOY_SERVER:-deploy@guild-sync.net}"
RUBY_VERSION="${RUBY_VERSION:-3.3.7}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
PROVISION_ISSUE_CERT="${PROVISION_ISSUE_CERT:-0}"

HTTP_ONLY_SRC="${SCRIPT_DIR}/guildsync-nginx-http-only"
FULL_NGINX_SRC="${SCRIPT_DIR}/guildsync-nginx"

build_deploy_ssh_args

for f in "$HTTP_ONLY_SRC" "$FULL_NGINX_SRC"; do
  if [[ ! -f "$f" ]]; then
    echo "error: missing required file: $f" >&2
    exit 1
  fi
done

echo "== Uploading nginx templates to ${SERVER} =="
scp "${DEPLOY_SSH_ARGS[@]}" "$HTTP_ONLY_SRC" "${SERVER}:/tmp/guildsync-nginx-http-only"
scp "${DEPLOY_SSH_ARGS[@]}" "$FULL_NGINX_SRC" "${SERVER}:/tmp/guildsync-nginx-full"

# CERTBOT_EMAIL and PROVISION_ISSUE_CERT are expanded on the client when this heredoc is sent.
ssh "${DEPLOY_SSH_ARGS[@]}" "$SERVER" bash -s <<EOF
set -eo pipefail

CERTBOT_EMAIL="${CERTBOT_EMAIL}"
PROVISION_ISSUE_CERT="${PROVISION_ISSUE_CERT}"
RUBY_VERSION="${RUBY_VERSION}"
LE_CERT="/etc/letsencrypt/live/guild-sync.net/fullchain.pem"

echo "== Updating system packages =="
sudo apt update

echo "== Installing base dependencies =="
sudo apt install -y \
  git curl build-essential \
  libssl-dev zlib1g-dev libreadline-dev \
  libyaml-dev libxml2-dev libxslt1-dev \
  libffi-dev libgdbm-dev libncurses5-dev \
  libsqlite3-dev \
  software-properties-common \
  ca-certificates gnupg lsb-release

# ------------------------
# Nginx + Certbot (phase 1 HTTP before certs exist)
# ------------------------

echo "== Installing Nginx and Certbot =="
sudo apt install -y nginx certbot

echo "== Preparing ACME webroot and maintenance dir =="
sudo mkdir -p /var/www/certbot
sudo chmod 755 /var/www/certbot
sudo mkdir -p /var/www/maintenance

echo "== Disabling default nginx site =="
sudo rm -f /etc/nginx/sites-enabled/default

echo "== Nginx phase 1 (HTTP only; ACME + redirect to HTTPS) =="
sudo install -m 0644 /tmp/guildsync-nginx-http-only /etc/nginx/sites-available/guildsync
sudo ln -sf /etc/nginx/sites-available/guildsync /etc/nginx/sites-enabled/guildsync
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl reload nginx

if [[ -f "\$LE_CERT" ]]; then
  echo "== TLS certificate already present; skipping certbot certonly =="
elif [[ "\$PROVISION_ISSUE_CERT" == "1" ]] && [[ -n "\$CERTBOT_EMAIL" ]]; then
  echo "== Obtaining TLS certificate (certbot webroot; requires DNS → this host) =="
  sudo certbot certonly --webroot -w /var/www/certbot \
    --non-interactive --agree-tos -m "\$CERTBOT_EMAIL" \
    -d guild-sync.net -d www.guild-sync.net
else
  echo "== Skipping cert issuance: set PROVISION_ISSUE_CERT=1 and CERTBOT_EMAIL to obtain certs =="
fi

if [[ -f "\$LE_CERT" ]]; then
  echo "== Nginx phase 2 (TLS + proxy + assets) =="
  sudo install -m 0644 /tmp/guildsync-nginx-full /etc/nginx/sites-available/guildsync
  sudo nginx -t
  sudo systemctl reload nginx
else
  echo "== Nginx stays on phase 1 until \$LE_CERT exists (re-run with PROVISION_ISSUE_CERT=1 after DNS is ready) =="
fi

echo "== Certbot renewal timer =="
if systemctl cat certbot.timer &>/dev/null; then
  sudo systemctl enable certbot.timer
  sudo systemctl start certbot.timer || true
else
  echo "Note: certbot.timer not found; ensure distro certbot package or configure renew manually."
fi

sudo rm -f /tmp/guildsync-nginx-http-only /tmp/guildsync-nginx-full

# ------------------------
# PostgreSQL 16
# ------------------------

echo "== Installing PostgreSQL 16 =="

if ! command -v psql >/dev/null 2>&1; then
  sudo apt install -y postgresql postgresql-contrib
fi

sudo systemctl enable postgresql
sudo systemctl start postgresql

# ------------------------
# Redis 7
# ------------------------

echo "== Installing Redis =="

if ! command -v redis-server >/dev/null 2>&1; then
  sudo apt install -y redis-server
fi

sudo systemctl enable redis-server
sudo systemctl start redis-server

# ------------------------
# Node.js (LTS) + npm
# ------------------------

echo "== Installing Node.js LTS =="

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt install -y nodejs
fi

echo "== Enabling Corepack (Yarn) =="

sudo corepack enable
sudo corepack prepare yarn@stable --activate

yarn -v
node -v
npm -v

# ------------------------
# rbenv + Ruby
# ------------------------

echo "== Installing rbenv =="

if [ ! -d "\$HOME/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git ~/.rbenv
  echo 'export PATH="\$HOME/.rbenv/bin:\$PATH"' >> ~/.bashrc
  echo 'eval "\$(rbenv init - bash)"' >> ~/.bashrc
fi

export PATH="\$HOME/.rbenv/bin:\$PATH"
eval "\$(rbenv init - bash)"

if [ ! -d "\$HOME/.rbenv/plugins/ruby-build" ]; then
  git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
fi

echo "== Installing Ruby \$RUBY_VERSION =="

if ! rbenv versions | grep -q "\$RUBY_VERSION"; then
  rbenv install "\$RUBY_VERSION"
fi

rbenv global "\$RUBY_VERSION"

echo "== Installing Bundler =="
gem install bundler
rbenv rehash

ruby -v
bundle -v

# ------------------------
# Verify Services
# ------------------------

echo "== Verifying Services =="

sudo systemctl is-active postgresql
sudo systemctl is-active redis-server

echo "== Setting up python dependencies =="
sudo apt install -y python3 python3-venv python3-pip

echo "Provisioning complete."
EOF
