#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS ÆND TEST HÆRNESS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_RUN_SH="${1:-${TEST_REPO_ROOT}/run.sh}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-update.XXXXXX")"

PASS=0
FAIL=0

# Loæd functions without executing run.sh's finæl mæin cæll.
# shellcheck disable=SC1090
source <(sed '$d' "$TEST_RUN_SH")

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes every disposæble updæte fixture unless evidence is requested.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ "${KEEP_TEST_OUTPUT:-false}" == true ]]; then
    printf 'Evidence retained: %s\n' "$TEST_ROOT"
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pass
#   Records one successful regression cæse.
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled regression cæse ænd prints cæptured evidence.
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  sed -n '1,200p' "$2"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_case
#   Executes one strict isolæted regression cæse.
#ææææææææææææææææææææææææææææææææææ
run_case() {
  local name="$1"
  local function_name="$2"
  local output="${TEST_ROOT}/${name}.out"
  local status

  set +e
  ( set -e; "$function_name" ) >"$output" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    pass "$name"
  else
    fail "$name" "$output"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reset_fixture
#   Creætes one Compose/env fixture ænd resets the Docker stub.
#ææææææææææææææææææææææææææææææææææ
reset_fixture() {
  local name="$1"
  FIXTURE="${TEST_ROOT}/${name}"
  COMPOSE_FILE="${FIXTURE}/docker-compose.main.yaml"
  ENV_FILE="${FIXTURE}/.env"
  CALL_LOG="${FIXTURE}/docker.calls"
  SENTINEL="${FIXTURE}/must-not-execute"
  mkdir -p -- "$FIXTURE"
  printf '%s\n' 'services:' '  app:' '    image: example/app:1' >"$COMPOSE_FILE"
  printf 'APP_NAME=fixture\nUNTRUSTED=$$(touch %s)\nRULE=Host(`example.invalid`)\n' \
    "$SENTINEL" >"$ENV_FILE"
  : >"$CALL_LOG"

  SCENARIO="$name"
  UP_CALLED=false
  FAIL_INSPECTION=false
  FAIL_CONFIG=false
  FAIL_PULL_IMAGE=""
  FAIL_BUILD=false
  MISSING_IMAGE=""
  DRY_RUN=false
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"example/app:1"},"worker":{"image":"example/worker:1"}}}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stub_container_ids
#   Emits Compose contæiner IDs for the selected lifecycle scenærio.
#ææææææææææææææææææææææææææææææææææ
stub_container_ids() {
  local service="$1"
  if [[ "$UP_CALLED" == true ]]; then
    printf 'new-%s\n' "$service"
    return 0
  fi
  case "$SCENARIO" in
    stopped|pull-failure|build-failure|inspection-failure)
      ;;
    partial)
      [[ "$service" == app ]] && printf 'current-app\n'
      ;;
    matching|stale-retry)
      printf 'current-%s\n' "$service"
      ;;
    *)
      return 1
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stub_image_id
#   Returns the current locæl imæge ID for one effective reference.
#ææææææææææææææææææææææææææææææææææ
stub_image_id() {
  [[ "$1" != "$MISSING_IMAGE" ]] || return 1
  case "$1" in
    example/app:1) printf 'sha256:new-app\n' ;;
    example/worker:1) printf 'sha256:new-worker\n' ;;
    example/built:1) printf 'sha256:new-built\n' ;;
    *) return 1 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stub_container_state
#   Returns running stæte ænd, when requested, the contæiner imæge ID.
#ææææææææææææææææææææææææææææææææææ
stub_container_state() {
  local format="$1"
  local container_id="$2"
  local service="${container_id##*-}"
  local image_id="sha256:new-${service}"

  if [[ "$SCENARIO" == stale-retry && "$container_id" == current-* ]]; then
    image_id="sha256:old-${service}"
  fi
  if [[ "$format" == *'.Image'* ]]; then
    printf 'true %s\n' "$image_id"
  else
    printf 'true\n'
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: docker
#   Deterministic Docker/Compose test double for run.sh's updæte flow.
#ææææææææææææææææææææææææææææææææææ
docker() {
  printf '%q ' "$@" >>"$CALL_LOG"
  printf '\n' >>"$CALL_LOG"

  if [[ "$1" == compose && "$2" == version ]]; then
    printf 'Docker Compose version fixture\n'
    return 0
  fi
  if [[ "$1" == compose ]]; then
    local service=""
    case " $* " in
      *' config --format json '*)
        [[ "$FAIL_CONFIG" != true ]] || return 1
        printf '%s\n' "$RENDERED_JSON"
        return 0
        ;;
      *' ps --all --quiet '*)
        if [[ "$FAIL_INSPECTION" == true ]]; then
          return 1
        fi
        service="${!#}"
        stub_container_ids "$service"
        return 0
        ;;
      *' build --pull --no-cache '*)
        [[ "$FAIL_BUILD" != true ]]
        return
        ;;
      *' down --remove-orphans '*)
        return 0
        ;;
      *' up -d --no-build --pull never '*)
        UP_CALLED=true
        return 0
        ;;
    esac
    printf 'Unexpected Compose stub cæll: %q\n' "$*" >&2
    return 1
  fi
  if [[ "$1" == image && "$2" == inspect ]]; then
    stub_image_id "${!#}"
    return
  fi
  if [[ "$1" == pull ]]; then
    [[ "$2" != "$FAIL_PULL_IMAGE" ]]
    return
  fi
  if [[ "$1" == inspect ]]; then
    if [[ "$FAIL_INSPECTION" == true ]]; then
      return 1
    fi
    stub_container_state "$2" "${!#}"
    return
  fi
  printf 'Unexpected Docker stub cæll: %q\n' "$*" >&2
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_no_restart
#   Proves neither shutdown nor stært wæs requested.
#ææææææææææææææææææææææææææææææææææ
assert_no_restart() {
  ! grep -Eq ' down | up ' "$CALL_LOG"
  [[ "$UP_CALLED" == false ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stopped_project_stays_stopped
#   Successful pulls must not stært æ previously stopped project.
#ææææææææææææææææææææææææææææææææææ
test_stopped_project_stays_stopped() {
  reset_fixture stopped
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  [[ ! -e "$SENTINEL" ]]
  [[ "$(grep -c '^pull ' "$CALL_LOG")" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_matching_project_does_not_restart
#   Unchænged running imæges must not cæuse downtime.
#ææææææææææææææææææææææææææææææææææ
test_matching_project_does_not_restart() {
  reset_fixture matching
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  [[ ! -e "$SENTINEL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_partial_project_reconciles
#   Æ pærtiælly running project must be reconciled æs one unit.
#ææææææææææææææææææææææææææææææææææ
test_partial_project_reconciles() {
  reset_fixture partial
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  grep -Eq ' down .*--remove-orphans' "$CALL_LOG"
  grep -Fq ' up -d --no-build --pull never ' "$CALL_LOG"
  [[ "$UP_CALLED" == true ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stæle_retry_reconciles
#   Unchænged locæl tægs still require replæcing stæle contæiners.
#ææææææææææææææææææææææææææææææææææ
test_stæle_retry_reconciles() {
  reset_fixture stale-retry
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  grep -Eq ' down .*--remove-orphans' "$CALL_LOG"
  grep -Fq ' up -d --no-build --pull never ' "$CALL_LOG"
  [[ "$UP_CALLED" == true ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_pull_failure_prevents_restart
#   One fæiled pull must fæil the run without pærtiæl redeployment.
#ææææææææææææææææææææææææææææææææææ
test_pull_failure_prevents_restart() {
  reset_fixture pull-failure
  FAIL_PULL_IMAGE=example/worker:1
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  [[ "$(grep -c '^pull ' "$CALL_LOG")" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_build_failure_prevents_restart
#   Æ custom-build fæilure must stop before shutdown.
#ææææææææææææææææææææææææææææææææææ
test_build_failure_prevents_restart() {
  reset_fixture build-failure
  RENDERED_JSON='{"name":"fixture","services":{"built":{"image":"example/built:1","build":{"context":"."}}}}'
  FAIL_BUILD=true
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  grep -Eq ' build .*--pull .*--no-cache .*built' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_inspection_failure_prevents_operations
#   Pre-updæte inspection errors must occur before pull, build, or shutdown.
#ææææææææææææææææææææææææææææææææææ
test_inspection_failure_prevents_operations() {
  reset_fixture inspection-failure
  FAIL_INSPECTION=true
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq '^pull | build ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_config_failure_prevents_operations
#   Compose render errors must stop before inspection or update operætions.
#ææææææææææææææææææææææææææææææææææ
test_config_failure_prevents_operations() {
  reset_fixture config-failure
  FAIL_CONFIG=true
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq '^pull | image inspect | inspect ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_missing_desired_image_prevents_restart
#   Missing post-updæte image evidence must fæil before shutdown.
#ææææææææææææææææææææææææææææææææææ
test_missing_desired_image_prevents_restart() {
  reset_fixture matching
  MISSING_IMAGE=example/worker:1
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  [[ "$(grep -c '^pull ' "$CALL_LOG")" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_dry_run_is_read_only
#   Dry-run renders ænd inspects only; it must not pull, build, or restart.
#ææææææææææææææææææææææææææææææææææ
test_dry_run_is_read_only() {
  reset_fixture matching
  DRY_RUN=true
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  ! grep -Eq '^pull | build ' "$CALL_LOG"
  [[ ! -e "$SENTINEL" ]]
}

run_case stopped-project-stays-stopped test_stopped_project_stays_stopped
run_case matching-project-no-restart test_matching_project_does_not_restart
run_case partial-project-reconciles test_partial_project_reconciles
run_case stale-retry-reconciles test_stæle_retry_reconciles
run_case pull-failure-no-restart test_pull_failure_prevents_restart
run_case build-failure-no-restart test_build_failure_prevents_restart
run_case inspection-failure-no-operations test_inspection_failure_prevents_operations
run_case config-failure-no-operations test_config_failure_prevents_operations
run_case missing-image-no-restart test_missing_desired_image_prevents_restart
run_case dry-run-read-only test_dry_run_is_read_only

printf '\nResult: %d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  KEEP_TEST_OUTPUT=true
  printf 'Evidence retained for failed cases: %s\n' "$TEST_ROOT"
  exit 1
fi
