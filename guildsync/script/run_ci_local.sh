#!/usr/bin/env bash
#
# run_ci_local.sh — local validation parity with GitHub Actions CI (when minutes exhausted).
#
# Does NOT modify test DB wiring, .rspec, or spec files. Invokes the same commands developers
# and CI use: db:test:prepare, bundle exec rspec, bin/rubocop, bin/brakeman.
#
# Usage (from repo root or guildsync/):
#   script/run_ci_local.sh              # PR-standard (--full)
#   script/run_ci_local.sh --quick spec/models/foo_spec.rb
#   script/run_ci_local.sh --full --i18n-scoped
#   script/run_ci_local.sh --e2e
#   script/run_ci_local.sh --help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUILDSYNC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GUILDSYNC_DIR}/.." && pwd)"
STATUS_FILE="${REPO_ROOT}/.github/ci_availability.yml"
BOUNDARY_SCRIPT="${REPO_ROOT}/.github/scripts/check_app_repo_artifact_boundary.sh"

MODE="full"
RSPEC_PATHS=()
FAIL_FAST=""
RUN_I18N="no"
RUN_ASSETS=0
RUN_BOUNDARY=1
RUN_E2E=0
E2E_ONLY=0
BOUNDARY_PR_SHAPE=0

STEP_RESULTS=()
FAILED=0
RESOLVED_TEST_DB=""
RUN_LOG_DIR=""

log() { echo "[run_ci_local] $*"; }
die() { echo "[run_ci_local] ERROR: $*" >&2; exit 1; }

record_step() {
  local name="$1" status="$2"
  STEP_RESULTS+=("${name}:${status}")
  [[ "${status}" == "PASS" ]] || FAILED=1
}

# --- Per-step output capture (enables a CI-style failure summary) -------------
# Each step streams to the console AND to a per-step log file. On failure we
# replay the tail of that step's log in one consolidated section, mirroring how
# GitHub surfaces the failing job + its error output. bash 3.2 safe.
init_run_logs() {
  if [[ -z "${RUN_LOG_DIR}" ]]; then
    RUN_LOG_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t run_ci_local)"
    trap 'cleanup_run_logs' EXIT
  fi
}

cleanup_run_logs() {
  if [[ -n "${RUN_LOG_DIR}" && -d "${RUN_LOG_DIR}" ]]; then
    rm -rf "${RUN_LOG_DIR}"
  fi
}

# step_log <name> -> prints the log path for a step (creating the dir if needed).
step_log() {
  if [[ -z "${RUN_LOG_DIR}" || ! -d "${RUN_LOG_DIR}" ]]; then
    RUN_LOG_DIR="$(mktemp -d 2>/dev/null || echo /tmp)"
  fi
  echo "${RUN_LOG_DIR}/$1.log"
}

print_usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Flags:
  --full              PR-standard (default): boundary, db:test:prepare, full rspec, rubocop, brakeman
  --quick PATH...     RSpec on given paths only (skips boundary, linters, e2e)
  --fail-fast         Pass --fail-fast to RSpec
  --no-i18n           Skip i18n checks (default for --full)
  --i18n-scoped       Check missing keys only in locale files changed vs merge base (never health)
  --with-assets       yarn install + build + rails assets:precompile (mirrors CI; slow)
  --boundary          Run artifact boundary check (on by default for --full)
  --boundary-pr       Boundary against merge-base with origin/main or origin/development
  --e2e               After other steps, run Playwright (chromium, inline server)
  --e2e-only          Playwright only
  --help              This help

Environment:
  - Unsets BUNDLE_PATH; sets RAILS_ENV=test. Respects existing DATABASE_*/TEST_DATABASE_*;
    when unset, falls back to config/database.yml defaults (local OS-user auth), same as
    running `bundle exec rspec` directly.
  - Safety guard: refuses to run if the resolved test DB name does not end in "_test"
    (prevents wiping a dev/prod DB when DATABASE_NAME lacks "_development"). Override with
    ALLOW_NON_TEST_DB=1 only if you are certain. See test_database.md.

Output:
  - Each step streams live AND is captured. On failure, a consolidated
    "FAILED: <step>" section replays the tail of that step's output (the local
    analogue of a GitHub failing check + its log), followed by a PASS/FAIL table.
EOF
}

read_ci_status() {
  if [[ ! -f "${STATUS_FILE}" ]]; then
    log "warning: missing ${STATUS_FILE}"
    return
  fi
  local status message
  status="$(ruby -ryaml -e 'd=YAML.safe_load(File.read(ARGV[0]))||{}; print d["status"].to_s' "${STATUS_FILE}" 2>/dev/null || true)"
  message="$(ruby -ryaml -e 'd=YAML.safe_load(File.read(ARGV[0]))||{}; m=d["message"]; print m.to_s.strip' "${STATUS_FILE}" 2>/dev/null || true)"
  log "CI availability status: ${status:-UNKNOWN}"
  if [[ -n "${message}" ]]; then
    log "  ${message}"
  fi
}

export_test_env() {
  unset BUNDLE_PATH
  export RAILS_ENV=test

  # Respect the developer's existing DATABASE_*/TEST_DATABASE_* environment.
  # When unset, leave them unset so config/database.yml falls back to local
  # PostgreSQL peer/OS-user auth — identical to running `bundle exec rspec`
  # directly. CI provides these vars explicitly; do NOT inject a `guildsync`
  # fallback that may not exist on a dev machine (would break parity).
  export DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID:-test_discord_client_id}"
  export DISCORD_CLIENT_SECRET="${DISCORD_CLIENT_SECRET:-test_discord_client_secret}"
  export APP_URL="${APP_URL:-http://localhost:3000}"

  RESOLVED_TEST_DB="$(ruby -e 'require "erb"; require "yaml"; c=YAML.safe_load(ERB.new(File.read("config/database.yml")).result, aliases: true)["test"]; print c["database"]' 2>/dev/null || true)"
  log "Test database: ${RESOLVED_TEST_DB:-<resolved by config/database.yml>} (user: ${TEST_DATABASE_USER:-${DATABASE_USER:-<OS user>}})"
}

# Safety: RSpec wipes/truncates the configured test DB. config/database.yml derives the
# test DB name as DATABASE_NAME.gsub("_development","_test"). If DATABASE_NAME lacks
# "_development" (e.g. DATABASE_NAME=guildsync, the production-style name), the test name
# does NOT get the _test suffix and we could clobber a dev/prod database. Refuse unless the
# resolved name ends in _test, or the operator explicitly opts out.
guard_test_database() {
  if [[ "${ALLOW_NON_TEST_DB:-0}" == "1" ]]; then
    log "WARNING: ALLOW_NON_TEST_DB=1 — skipping test-DB name safety guard (${RESOLVED_TEST_DB:-unknown})"
    return
  fi
  if [[ -z "${RESOLVED_TEST_DB:-}" ]]; then
    log "WARNING: could not resolve test database name; proceeding (config/database.yml parse failed)"
    return
  fi
  if [[ "${RESOLVED_TEST_DB}" != *_test ]]; then
    die "Refusing to run: resolved test database '${RESOLVED_TEST_DB}' does not end in '_test'.
       This usually means DATABASE_NAME has no '_development' suffix (e.g. a production-style
       name like 'guildsync'), so RSpec could wipe a non-test database.
       Fix: set TEST_DATABASE_NAME=guildsync_test (see test_database.md), or, if you are sure,
       re-run with ALLOW_NON_TEST_DB=1."
  fi
}

preflight() {
  [[ -d "${GUILDSYNC_DIR}" ]] || die "guildsync directory not found at ${GUILDSYNC_DIR}"
  cd "${GUILDSYNC_DIR}"
  export_test_env
  guard_test_database

  if ! bundle exec ruby -v 2>/dev/null | grep -qE 'ruby 3\.3\.'; then
    die "Ruby 3.3.x required (see .ruby-version). Run: cd guildsync && bundle exec ruby -v"
  fi

  if command -v redis-cli >/dev/null 2>&1; then
    if ! redis-cli ping 2>/dev/null | grep -q PONG; then
      log "WARNING: Redis not responding on localhost — some job specs may fail. Start Redis or see test_categories_and_types.md."
    fi
  else
    log "WARNING: redis-cli not found — some job specs may fail if Redis is required."
  fi
}

run_boundary() {
  [[ -f "${BOUNDARY_SCRIPT}" ]] || die "missing ${BOUNDARY_SCRIPT}"
  log "Artifact boundary check..."
  if [[ "${BOUNDARY_PR_SHAPE}" -eq 1 ]]; then
    local base
    base="$(git -C "${REPO_ROOT}" merge-base HEAD origin/main 2>/dev/null || git -C "${REPO_ROOT}" merge-base HEAD origin/development 2>/dev/null || echo "")"
    if [[ -z "${base}" ]]; then
      log "WARNING: could not find merge-base; using default boundary (HEAD vs HEAD^)"
      (cd "${REPO_ROOT}" && bash "${BOUNDARY_SCRIPT}") 2>&1 | tee "$(step_log artifact_boundary)" && record_step "artifact_boundary" "PASS" || record_step "artifact_boundary" "FAIL"
      return
    fi
    export KB_BOUNDARY_BASE_SHA="${base}"
    export KB_BOUNDARY_HEAD_SHA="HEAD"
    log "  base=${base} head=HEAD"
  fi
  (cd "${REPO_ROOT}" && bash "${BOUNDARY_SCRIPT}") 2>&1 | tee "$(step_log artifact_boundary)" && record_step "artifact_boundary" "PASS" || record_step "artifact_boundary" "FAIL"
}

run_db_prepare() {
  log "Preparing test database (db:test:prepare)..."
  if bundle exec rails db:test:prepare 2>&1 | tee "$(step_log db_test_prepare)"; then
    record_step "db_test_prepare" "PASS"
  else
    record_step "db_test_prepare" "FAIL"
    die "db:test:prepare failed. See test_database.md at repo root."
  fi
}

run_rspec() {
  local rspec_args=(--format progress)
  if [[ -n "${FAIL_FAST}" ]]; then
    rspec_args+=(--fail-fast)
  fi
  log "Running RSpec..."
  if [[ ${#RSPEC_PATHS[@]} -gt 0 ]]; then
    if bundle exec rspec "${rspec_args[@]}" "${RSPEC_PATHS[@]}" 2>&1 | tee "$(step_log rspec)"; then
      record_step "rspec" "PASS"
    else
      record_step "rspec" "FAIL"
    fi
  else
    if bundle exec rspec "${rspec_args[@]}" 2>&1 | tee "$(step_log rspec)"; then
      record_step "rspec" "PASS"
    else
      record_step "rspec" "FAIL"
    fi
  fi
}

run_rubocop() {
  log "Running RuboCop..."
  if bin/rubocop 2>&1 | tee "$(step_log rubocop)"; then
    record_step "rubocop" "PASS"
  else
    record_step "rubocop" "FAIL"
  fi
}

run_brakeman() {
  log "Running Brakeman..."
  if bin/brakeman --no-pager 2>&1 | tee "$(step_log brakeman)"; then
    record_step "brakeman" "PASS"
  else
    record_step "brakeman" "FAIL"
  fi
}

run_assets() {
  log "Building assets (yarn, mirrors CI)..."
  if command -v yarn >/dev/null 2>&1; then
    if (yarn install --frozen-lockfile && yarn build:css && yarn build && bundle exec rails assets:precompile) 2>&1 | tee "$(step_log assets)"; then
      record_step "assets" "PASS"
    else
      record_step "assets" "FAIL"
    fi
  else
    log "WARNING: yarn not found; skipping asset build"
    record_step "assets" "SKIP"
  fi
}

i18n_merge_base() {
  git -C "${REPO_ROOT}" merge-base HEAD origin/main 2>/dev/null \
    || git -C "${REPO_ROOT}" merge-base HEAD origin/development 2>/dev/null \
    || echo "HEAD~1"
}

run_i18n_scoped() {
  local base
  base="$(i18n_merge_base)"
  log "i18n-scoped: diff locale files vs ${base} (never i18n-tasks health)"

  local i18n_log
  i18n_log="$(step_log i18n_scoped)"
  : > "${i18n_log}"

  # bash 3.2 safe (no mapfile): collect changed locale files into an array.
  local files=()
  local line
  while IFS= read -r line; do
    [[ -n "${line}" ]] && files+=("${line}")
  done < <(git -C "${REPO_ROOT}" diff --name-only "${base}" HEAD -- 'guildsync/config/locales/' 2>/dev/null || true)

  if [[ ${#files[@]} -eq 0 ]]; then
    log "  No locale files changed — i18n N/A"
    record_step "i18n_scoped" "PASS"
    return
  fi
  local f guildsync_rel
  for f in "${files[@]}"; do
    [[ "${f}" == guildsync/* ]] || continue
    guildsync_rel="${f#guildsync/}"
    log "  i18n-tasks missing -f ${guildsync_rel}"
    if ! (cd "${GUILDSYNC_DIR}" && bundle exec i18n-tasks missing -f "${guildsync_rel}") 2>&1 | tee -a "${i18n_log}"; then
      record_step "i18n_scoped" "FAIL"
      return
    fi
  done
  record_step "i18n_scoped" "PASS"
}

run_e2e() {
  local ext_dir="${REPO_ROOT}/external_tests"
  [[ -d "${ext_dir}" ]] || die "external_tests not found"
  export CI=1
  export INTEGRATION_TESTS=1
  export PORT="${PORT:-5000}"
  export BASE_URL="http://127.0.0.1:${PORT}"
  export API_BASE_URL="http://127.0.0.1:${PORT}/api/v1"
  export APP_URL="http://127.0.0.1:${PORT}"
  export GUILDSYNC_SERVER_DIR="${GUILDSYNC_DIR}"
  export PLAYWRIGHT_JUNIT_OUTPUT_FILE="${ext_dir}/test-results/junit.xml"
  export_test_env
  log "Playwright E2E (port ${PORT})..."
  (cd "${ext_dir}" && npm ci && npx playwright install chromium --with-deps \
    && npm run test:with-server -- --yes --inline-server --project=chromium --reporter=line,junit) 2>&1 \
    | tee "$(step_log playwright)" \
    && record_step "playwright" "PASS" || record_step "playwright" "FAIL"
}

# Replay the tail of each failed step's captured output, so the operator gets a
# consolidated "what failed and why" view (the local analogue of GitHub's failing
# check + its log). Display-only: does not change exit status.
print_failures() {
  local entry name status logfile shown=0
  for entry in "${STEP_RESULTS[@]}"; do
    name="${entry%%:*}"
    status="${entry#*:}"
    # Only real failures; SKIP is not an error to display here.
    [[ "${status}" == "FAIL" ]] || continue
    shown=1
    logfile="${RUN_LOG_DIR}/${name}.log"
    echo ""
    echo "----- FAILED: ${name} (last 40 lines of its output) -----"
    if [[ -s "${logfile}" ]]; then
      tail -n 40 "${logfile}"
    else
      echo "  (no captured output for this step)"
    fi
  done
  if [[ "${shown}" -eq 1 ]]; then
    echo ""
    echo "----- end of failure output (full output streamed above) -----"
  fi
}

print_summary() {
  print_failures
  echo ""
  echo "======== run_ci_local summary ========"
  local entry name status
  for entry in "${STEP_RESULTS[@]}"; do
    name="${entry%%:*}"
    status="${entry#*:}"
    printf "  %-20s %s\n" "${name}" "${status}"
  done
  if [[ "${FAILED}" -eq 0 ]]; then
    echo "RESULT: PASS"
  else
    echo "RESULT: FAIL  (see failure details above)"
  fi
  echo "===================================="
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full) MODE="full"; shift ;;
      --quick) MODE="quick"; RUN_BOUNDARY=0; shift; while [[ $# -gt 0 && "$1" != --* ]]; do RSPEC_PATHS+=("$1"); shift; done ;;
      --fail-fast) FAIL_FAST=1; shift ;;
      --no-i18n) RUN_I18N="no"; shift ;;
      --i18n-scoped) RUN_I18N="scoped"; shift ;;
      --with-assets) RUN_ASSETS=1; shift ;;
      --boundary) RUN_BOUNDARY=1; shift ;;
      --boundary-pr) RUN_BOUNDARY=1; BOUNDARY_PR_SHAPE=1; shift ;;
      --e2e) RUN_E2E=1; shift ;;
      --e2e-only) E2E_ONLY=1; RUN_E2E=1; RUN_BOUNDARY=0; shift ;;
      -h|--help) print_usage; exit 0 ;;
      --*) die "unknown flag $1 (see --help)" ;;
      *) RSPEC_PATHS+=("$1"); shift ;;
    esac
  done
  if [[ "${MODE}" == "quick" && ${#RSPEC_PATHS[@]} -eq 0 ]]; then
    die "--quick requires at least one spec path"
  fi
}

main() {
  parse_args "$@"
  init_run_logs
  read_ci_status
  preflight

  if [[ "${E2E_ONLY}" -eq 1 ]]; then
    run_e2e
    print_summary
    exit "${FAILED}"
  fi

  if [[ "${RUN_BOUNDARY}" -eq 1 ]]; then
    run_boundary
    if [[ "${FAILED}" -eq 1 && "${MODE}" != "quick" ]]; then
      print_summary
      exit 1
    fi
  fi

  if [[ "${MODE}" != "quick" ]]; then
    if [[ "${RUN_ASSETS}" -eq 1 ]]; then
      run_assets
    fi
    run_db_prepare
    run_rspec
    run_rubocop
    run_brakeman
    case "${RUN_I18N}" in
      scoped) run_i18n_scoped ;;
      no) log "i18n: skipped (use --i18n-scoped for changed locale files)" ;;
    esac
  else
    run_db_prepare
    run_rspec
  fi

  if [[ "${RUN_E2E}" -eq 1 ]]; then
    run_e2e
  fi

  print_summary
  exit "${FAILED}"
}

main "$@"
