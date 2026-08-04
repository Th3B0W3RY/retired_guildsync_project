#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# GuildSync Production Database Wipe
# ==============================================================================
# Run from your LOCAL machine. Connects to the production VM via SSH and
# truncates every data table, then re-seeds pricing plans and games.
#
# Usage:
#   bash deploy/wipe_database.sh
#
# What this does:
#   1. Stops the Rails + Sidekiq services (prevents mid-wipe errors)
#   2. Truncates every data table (CASCADE handles FK ordering)
#   3. Preserves schema_migrations / ar_internal_metadata
#   4. Purges local ActiveStorage files on the server
#   5. Re-seeds pricing_plans, runs PricingPlanInitializer + GameInitializer
#   6. Restarts services
#
# What this does NOT do:
#   - Drop or recreate the database (schema stays intact)
#   - Touch Discord (no AR callbacks fire -- raw SQL truncate)
#   - Modify migrations or schema version
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ssh_args.sh"

SERVER="${DEPLOY_SERVER:-deploy@guild-sync.net}"
APP_DIR="${DEPLOY_APP_DIR:-/var/www/guildsync}"
SERVICE="${DEPLOY_SERVICE:-guildsync}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║       ⚠️  PRODUCTION DATABASE WIPE — DESTRUCTIVE  ⚠️        ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  This will permanently delete ALL production data:          ║${NC}"
echo -e "${RED}║    • All users and accounts                                 ║${NC}"
echo -e "${RED}║    • All guilds, alliances, memberships                     ║${NC}"
echo -e "${RED}║    • All events, polls, loot rolls                          ║${NC}"
echo -e "${RED}║    • All activity logs, audit trails, versions              ║${NC}"
echo -e "${RED}║    • All Discord connections and sync data                  ║${NC}"
echo -e "${RED}║    • All file uploads and documents                         ║${NC}"
echo -e "${RED}║                                                             ║${NC}"
echo -e "${RED}║  Target: ${YELLOW}${SERVER}${RED}                          ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

read -p "Type 'WIPE PRODUCTION' to confirm: " CONFIRM
if [ "$CONFIRM" != "WIPE PRODUCTION" ]; then
  echo -e "${GREEN}Aborted. No changes made.${NC}"
  exit 0
fi

echo ""
echo -e "${YELLOW}== Connecting to ${SERVER} ==${NC}"

build_deploy_ssh_args

ssh "${DEPLOY_SSH_ARGS[@]}" "$SERVER" "export APP_DIR=\"$APP_DIR\"; export SERVICE=\"$SERVICE\"; bash -s" <<'REMOTEOF'
set -euo pipefail

# ---------- rbenv ----------
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:/usr/local/bin:/usr/bin:/bin"
eval "$(rbenv init - bash)"

export RAILS_ENV=production
export RACK_ENV=production

# ---------- load .env ----------
ENV_FILE="$APP_DIR/guildsync/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
fi

cd "$APP_DIR/guildsync"

# ---------- stop services to prevent mid-wipe errors ----------
echo "== Stopping services =="
sudo systemctl stop "${SERVICE}-sidekiq" 2>/dev/null || true
sudo systemctl stop "$SERVICE" 2>/dev/null || true
echo "✓ Services stopped"

# ---------- safety net: always restart services on exit ----------
trap 'echo "== Restarting services (cleanup) =="; sudo systemctl start "$SERVICE" 2>/dev/null || true; sudo systemctl start "${SERVICE}-sidekiq" 2>/dev/null || true' EXIT

# ---------- run the wipe ----------
bundle exec rails runner - <<'RUBYEOF'
puts "\n== Starting production database wipe =="
puts "Environment: #{Rails.env}"
puts "Database:    #{ActiveRecord::Base.connection.current_database}"

KEEP_TABLES = %w[schema_migrations ar_internal_metadata].freeze
all_tables = ActiveRecord::Base.connection.tables - KEEP_TABLES

if all_tables.empty?
  puts "No tables to truncate."
  exit 0
end

puts "\nTruncating #{all_tables.size} tables..."

ActiveRecord::Base.connection.execute(
  "TRUNCATE TABLE #{all_tables.map { |t| %Q["#{t}"] }.join(', ')} RESTART IDENTITY CASCADE"
)

puts "✓ All #{all_tables.size} tables truncated"

# Purge ActiveStorage files from disk
begin
  dir = Rails.root.join("storage")
  if dir.exist? && dir.children.any?
    FileUtils.rm_rf(Dir.glob("#{dir}/**/*"))
    puts "✓ ActiveStorage files purged"
  end
rescue => e
  puts "⚠ ActiveStorage cleanup skipped: #{e.message}"
end

puts "\n== Re-seeding essential data =="

puts "Seeding pricing plans..."
load Rails.root.join("db", "seeds.rb")
puts "✓ Pricing plans seeded"

if defined?(PricingPlanInitializer)
  PricingPlanInitializer.ensure_plans_exist!
  puts "✓ PricingPlanInitializer ran"
end

if defined?(GameInitializer)
  GameInitializer.ensure_games_exist!
  game_count = Game.count rescue 0
  puts "✓ GameInitializer ran (#{game_count} games)"
end

puts "\n== Database wipe complete =="
puts "Tables truncated:   #{all_tables.size}"
puts "Pricing plans:      #{PricingPlan.count rescue '?'}"
puts "Games:              #{Game.count rescue '?'}"
puts "Users:              #{User.count rescue 0}"
puts "Guilds:             #{Guild.count rescue 0}"
puts "Alliances:          #{Alliance.count rescue 0}"
puts ""
RUBYEOF

# Clear the safety-net trap before explicit restart (prevents double-start)
trap - EXIT

echo "== Restarting services =="
sudo systemctl start "$SERVICE"
sudo systemctl start "${SERVICE}-sidekiq"

if sudo systemctl is-active --quiet "$SERVICE"; then
  echo "✓ Rails service is running"
else
  echo "✗ Rails service failed to start — check logs"
  exit 1
fi

if sudo systemctl is-active --quiet "${SERVICE}-sidekiq"; then
  echo "✓ Sidekiq service is running"
else
  echo "⚠ Sidekiq failed to start — background jobs will not process"
fi

echo ""
echo "== Production database wipe complete =="
REMOTEOF

echo ""
echo -e "${GREEN}✓ Done. Production database is clean and services are running.${NC}"
