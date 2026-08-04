#!/usr/bin/env bash
#
# ci_status.sh — read or update the repo CI availability signal.
#
# The signal lives at .github/ci_availability.yml (repo root) and tells agents
# and humans whether GitHub Actions can be relied on, or whether local
# validation via run_ci_local.sh is required before merge.
#
# Usage:
#   script/ci_status.sh get
#   script/ci_status.sh set <STATUS> ["message"] [--resets-on YYYY-MM-DD] [--by NAME]
#
# STATUS must be one of: ACTIVE | BUDGET_EXHAUSTED | SELF_HOSTED_ONLY | UNKNOWN
#
# Examples:
#   script/ci_status.sh set ACTIVE "Billing restored; PR checks running again."
#   script/ci_status.sh set BUDGET_EXHAUSTED --resets-on 2026-06-01
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS_FILE="${REPO_ROOT}/.github/ci_availability.yml"
VALID_STATUSES=("ACTIVE" "BUDGET_EXHAUSTED" "SELF_HOSTED_ONLY" "UNKNOWN")

die() {
  echo "ci_status: $*" >&2
  exit 1
}

ruby_yaml_get() {
  # $1 = top-level key; prints value or empty string
  ruby -ryaml -e '
    file = ARGV[0]
    key = ARGV[1]
    data = YAML.safe_load(File.read(file), permitted_classes: [Date]) || {}
    val = data[key]
    print(val.nil? ? "" : val.to_s)
  ' "${STATUS_FILE}" "$1" 2>/dev/null || true
}

cmd_get() {
  [[ -f "${STATUS_FILE}" ]] || die "missing ${STATUS_FILE}"
  local status
  status="$(ruby_yaml_get status)"
  [[ -n "${status}" ]] || die "could not read status from ${STATUS_FILE}"
  echo "${status}"
}

is_valid_status() {
  local candidate="$1"
  local s
  for s in "${VALID_STATUSES[@]}"; do
    [[ "${s}" == "${candidate}" ]] && return 0
  done
  return 1
}

cmd_set() {
  local new_status="${1:-}"
  shift || true
  [[ -n "${new_status}" ]] || die "set requires a STATUS (one of: ${VALID_STATUSES[*]})"
  new_status="$(echo "${new_status}" | tr '[:lower:]' '[:upper:]')"
  is_valid_status "${new_status}" || die "invalid status '${new_status}'. Allowed: ${VALID_STATUSES[*]}"

  local message=""
  local resets_on=""
  local updated_by="manual"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --resets-on)
        resets_on="${2:-}"; shift 2 ;;
      --by)
        updated_by="${2:-manual}"; shift 2 ;;
      --*)
        die "unknown option '$1'" ;;
      *)
        # First positional after status is the message.
        if [[ -z "${message}" ]]; then message="$1"; shift; else die "unexpected argument '$1'"; fi ;;
    esac
  done

  # Preserve existing resets_on when not overridden.
  if [[ -z "${resets_on}" && -f "${STATUS_FILE}" ]]; then
    resets_on="$(ruby_yaml_get resets_on)"
  fi

  # Default message keyed off the status when none supplied.
  if [[ -z "${message}" ]]; then
    case "${new_status}" in
      ACTIVE) message="GitHub Actions available; rely on PR checks." ;;
      BUDGET_EXHAUSTED) message="GitHub-hosted Actions minutes exhausted or PR checks unreliable. Run guildsync/script/run_ci_local.sh and document results in the PR." ;;
      SELF_HOSTED_ONLY) message="Only the self-hosted runner is active; run local validation if you cannot see results." ;;
      UNKNOWN) message="CI availability unknown; run PR-standard local validation before merge." ;;
    esac
  fi

  local updated_at resets_line
  updated_at="$(date +%Y-%m-%d)"
  if [[ -z "${resets_on}" || "${resets_on}" == "null" ]]; then
    resets_line="resets_on: null"
  else
    resets_line="resets_on: \"${resets_on}\""
  fi

  cat > "${STATUS_FILE}" <<YAML
# Machine-readable CI availability signal for agents and local validation.
#
# Agents and humans read this BEFORE marking a task's Validate step complete.
# See .cursor/CI_AND_LOCAL_VALIDATION.md for the full decision hierarchy and tiers.
#
# Update via: guildsync/script/ci_status.sh set <status> "optional message"
# Or edit this file directly (keep the schema/keys stable).

status: ${new_status}  # ACTIVE | BUDGET_EXHAUSTED | SELF_HOSTED_ONLY | UNKNOWN

message: >
  ${message}

updated_at: "${updated_at}"
updated_by: "${updated_by}"

# Optional ISO date when included Actions minutes reset (null if unknown).
${resets_line}

# Decision rules consumed by humans/agents (documented in the canonical doc).
decision_rules:
  trust_green_required_checks: true
  local_required_when_checks_missing: true

local_validation:
  script: guildsync/script/run_ci_local.sh
  canonical_doc: .cursor/CI_AND_LOCAL_VALIDATION.md
  default_tier: PR-standard
YAML

  echo "ci_status: set status=${new_status} updated_at=${updated_at} updated_by=${updated_by}"
}

main() {
  local subcommand="${1:-}"
  case "${subcommand}" in
    get)
      cmd_get ;;
    set)
      shift
      cmd_set "$@" ;;
    ""|-h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
    *)
      die "unknown command '${subcommand}'. Use get or set (see --help)." ;;
  esac
}

main "$@"
