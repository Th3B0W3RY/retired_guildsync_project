#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# GuildSync — Live Production Log Stream
# ==============================================================================
# Streams real-time logs from the production VM to your local terminal via SSH.
#
# Usage:
#   bash deploy/live_logs.sh              # All Rails + Sidekiq logs
#   bash deploy/live_logs.sh --discord    # Only lines containing "discord"
#   bash deploy/live_logs.sh --errors     # Warnings and errors only
#   bash deploy/live_logs.sh --rails      # Rails (Puma) service only
#   bash deploy/live_logs.sh --sidekiq    # Sidekiq service only
#   bash deploy/live_logs.sh --all        # Every systemd log (all services)
#   bash deploy/live_logs.sh -n 100       # Show last 100 lines then follow
#   bash deploy/live_logs.sh --grep "OAuth"  # Custom grep filter
#
# Combine flags:
#   bash deploy/live_logs.sh --rails --grep "OAuth" -n 50
#
# Press Ctrl+C to stop.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ssh_args.sh"

SERVER="${DEPLOY_SERVER:-deploy@guild-sync.net}"
SERVICE="${DEPLOY_SERVICE:-guildsync}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

UNITS="-u ${SERVICE} -u ${SERVICE}-sidekiq"
INITIAL_LINES=50
PRIORITY=""
GREP_PATTERN=""
LABEL="Rails + Sidekiq"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --discord)
      GREP_PATTERN="discord"
      LABEL="$LABEL (filtered: discord)"
      shift
      ;;
    --errors)
      PRIORITY="-p warning"
      LABEL="$LABEL (warnings + errors only)"
      shift
      ;;
    --rails)
      UNITS="-u ${SERVICE}"
      LABEL="Rails only"
      shift
      ;;
    --sidekiq)
      UNITS="-u ${SERVICE}-sidekiq"
      LABEL="Sidekiq only"
      shift
      ;;
    --all)
      UNITS=""
      LABEL="All systemd services"
      shift
      ;;
    -n)
      INITIAL_LINES="$2"
      shift 2
      ;;
    --grep)
      GREP_PATTERN="$2"
      LABEL="$LABEL (filtered: $2)"
      shift 2
      ;;
    -h|--help)
      head -24 "$0" | tail -20
      exit 0
      ;;
    *)
      echo "Unknown option: $1 (use --help for usage)"
      exit 1
      ;;
  esac
done

JOURNAL_CMD="sudo journalctl ${UNITS} ${PRIORITY} -n ${INITIAL_LINES} -f --no-pager -o short-iso"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           GuildSync — Live Production Logs                  ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  Server:  ${YELLOW}${SERVER}${CYAN}                          ║${NC}"
echo -e "${CYAN}║  Source:  ${GREEN}${LABEL}${CYAN}"
echo -e "${CYAN}║  Lines:   ${GREEN}last ${INITIAL_LINES}, then follow${CYAN}"
if [[ -n "$GREP_PATTERN" ]]; then
echo -e "${CYAN}║  Filter:  ${GREEN}${GREP_PATTERN}${CYAN}"
fi
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Connecting... (Ctrl+C to stop)${NC}"
echo ""

build_deploy_ssh_args

if [[ -n "$GREP_PATTERN" ]]; then
  ssh "${DEPLOY_SSH_ARGS[@]}" "$SERVER" "${JOURNAL_CMD}" 2>/dev/null | grep --line-buffered -i "$GREP_PATTERN"
else
  ssh "${DEPLOY_SSH_ARGS[@]}" -t "$SERVER" "${JOURNAL_CMD}" 2>/dev/null
fi
