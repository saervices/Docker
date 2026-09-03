#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RUN.SH UPDÆTE, LOCK, ÆND PERMISSION-STOP CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_RUN_SH="${1:-${TEST_REPO_ROOT}/run.sh}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-update.XXXXXX")"

PASS=0
FAIL=0
readonly ID_OLD="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly ID_NEW="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# shellcheck disable=SC1090
source <(sed '$d' "$TEST_RUN_SH")

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
  if [[ -n "${2:-}" && -f "$2" ]]; then
    sed -n '1,80p' "$2" >&2 || true
  fi
}

expect_success() {
  local name="$1"
  local status
  shift
  set +e
  ( set -euo pipefail; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    pass "$name"
  else
    fail "$name" "${TEST_ROOT}/${name}.out"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_docker_stub
#   Logs Compose, imæge, pull, ænd stæck commænds without touching æ reæl dæemon.
#ææææææææææææææææææææææææææææææææææ
install_docker_stub() {
  local bin_dir="$1"
  mkdir -p -- "$bin_dir"
  cat >"${bin_dir}/docker" <<'EOF'
#!/bin/sh
set -eu
: "${CALL_LOG:?}"
printf '%s\n' "$*" >>"$CALL_LOG"

if [ "${1:-}" = compose ]; then
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --project-directory|--env-file|-f)
        [ "$#" -ge 2 ] || exit 1
        shift 2
        ;;
      --*)
        shift
        ;;
      version)
        exit 0
        ;;
      config)
        if [ "${FAIL_CONFIG:-0}" = 1 ]; then
          exit 1
        fi
        cat "${RENDERED_COMPOSE:?}"
        exit 0
        ;;
      ps)
        if [ "${FAIL_PS:-0}" = 1 ]; then
          exit 1
        fi
        if [ -n "${RUNNING_IDS:-}" ]; then
          printf '%s\n' "$RUNNING_IDS"
        fi
        exit 0
        ;;
      stop)
        if [ "${FAIL_STOP:-0}" = 1 ]; then
          exit 1
        fi
        printf 'stop\n' >>"${STOP_LOG:?}"
        exit 0
        ;;
      down)
        printf 'down\n' >>"${RESTART_LOG:?}"
        exit 0
        ;;
      up)
        printf 'up\n' >>"${RESTART_LOG:?}"
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done
  exit 1
fi

image_key() {
  printf '%s' "$1" | tr '/:' '__'
}

if [ "${1:-}" = image ] && [ "${2:-}" = inspect ]; then
  image=""
  while [ "$#" -gt 0 ]; do
    image="$1"
    shift
  done
  key=$(image_key "$image")
  if [ -f "${PULLED_DIR}/${key}" ]; then
    printf '%s\n' "${ID_AFTER:?}"
    exit 0
  fi
  if [ -n "${ID_BEFORE:-}" ]; then
    printf '%s\n' "$ID_BEFORE"
    exit 0
  fi
  exit 1
fi

if [ "${1:-}" = pull ]; then
  image="${2:-}"
  if [ "${FAIL_PULL:-0}" = 1 ]; then
    exit 1
  fi
  mkdir -p -- "${PULLED_DIR:?}"
  : >"${PULLED_DIR}/$(image_key "$image")"
  exit 0
fi

exit 1
EOF
  chmod +x "${bin_dir}/docker"
}

reset_update_fixture() {
  local name="$1"
  FIXTURE="${TEST_ROOT}/${name}"
  mkdir -p -- "$FIXTURE/appdata" "$FIXTURE/pulled" "${FIXTURE}/bin"
  COMPOSE_FILE="${FIXTURE}/docker-compose.main.yaml"
  ENV_FILE="${FIXTURE}/.env"
  CALL_LOG="${FIXTURE}/docker.calls"
  RESTART_LOG="${FIXTURE}/restart.log"
  STOP_LOG="${FIXTURE}/stop.log"
  SENTINEL="${FIXTURE}/must-not-execute"
  RENDERED_COMPOSE="${FIXTURE}/rendered.yaml"
  PULLED_DIR="${FIXTURE}/pulled"
  : >"$CALL_LOG"
  : >"$RESTART_LOG"
  : >"$STOP_LOG"
  printf '%s\n' 'services:' '  app:' '    image: example/app:1' \
    '  worker:' '    image: example/worker:1' \
    '  built:' '    build:' '      context: .' >"$COMPOSE_FILE"
  printf 'APP_NAME=fixture\nUNTRUSTED=$(touch %s)\nRULE=Host(`example.invalid`)\n' \
    "$SENTINEL" >"$ENV_FILE"
  cat >"$RENDERED_COMPOSE" <<'YAML'
services:
  app:
    image: example/app:1
  worker:
    image: example/worker:1
  built:
    build:
      context: .
YAML
  TARGET_DIR="$FIXTURE"
  DRY_RUN=false
  FORCE=false
  INITIAL_RUN=false
  DEBUG=false
  FAIL_CONFIG=0
  FAIL_PULL=0
  FAIL_PS=0
  FAIL_STOP=0
  RUNNING_IDS=""
  ID_BEFORE="$ID_OLD"
  ID_AFTER="$ID_OLD"
  export CALL_LOG RESTART_LOG STOP_LOG RENDERED_COMPOSE PULLED_DIR
  export FAIL_CONFIG FAIL_PULL FAIL_PS FAIL_STOP RUNNING_IDS ID_BEFORE ID_AFTER
  install_docker_stub "${FIXTURE}/bin"
  export PATH="${FIXTURE}/bin:${PATH}"
}

test_update_does_not_source_env() {
  reset_update_fixture source-env
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  [[ ! -e "$SENTINEL" ]]
  grep -q 'pull example/app:1' "$CALL_LOG"
  grep -q 'pull example/worker:1' "$CALL_LOG"
  ! grep -q 'pull .*built' "$CALL_LOG"
  [[ ! -s "$RESTART_LOG" ]]
}

test_update_skips_services_without_image() {
  reset_update_fixture skip-build
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  ! grep -q 'pull .*built' "$CALL_LOG"
  grep -q 'pull example/app:1' "$CALL_LOG"
}

test_update_pull_failure_is_fail_closed() {
  reset_update_fixture pull-fail
  FAIL_PULL=1
  export FAIL_PULL
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  [[ ! -s "$RESTART_LOG" ]]
}

test_update_restarts_when_image_id_changes() {
  reset_update_fixture image-changed
  ID_AFTER="$ID_NEW"
  export ID_AFTER
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  grep -qx down "$RESTART_LOG"
  grep -qx up "$RESTART_LOG"
}

test_update_skips_restart_when_current() {
  reset_update_fixture already-current
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  [[ ! -s "$RESTART_LOG" ]]
}

test_update_dry_run_does_not_pull() {
  reset_update_fixture dry-run
  DRY_RUN=true
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  ! grep -q 'pull ' "$CALL_LOG"
  [[ ! -s "$RESTART_LOG" ]]
  [[ ! -e "$SENTINEL" ]]
}

test_update_config_failure_is_fail_closed() {
  reset_update_fixture config-fail
  FAIL_CONFIG=1
  export FAIL_CONFIG
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  ! grep -q 'pull ' "$CALL_LOG"
}

test_project_lock_blocks_second_holder() {
  local project="${TEST_ROOT}/lock-app"
  mkdir -p -- "$project"
  TARGET_DIR="$project"
  acquire_project_lock
  [[ -f "${project}/.${SCRIPT_BASE}.conf/.run.lock" ]]
  if flock --exclusive --nonblock "${project}/.${SCRIPT_BASE}.conf/.run.lock" true; then
    return 1
  fi
}

test_stop_before_chown_when_running() {
  reset_update_fixture stop-running
  printf 'APP_DIRECTORIES=appdata\nAPP_UID=%s\nAPP_GID=%s\n' "$(id -u)" "$(id -g)" >"$ENV_FILE"
  FORCE=true
  INITIAL_RUN=false
  RUNNING_IDS="cid-running"
  export RUNNING_IDS
  apply_all_permissions "$ENV_FILE"
  grep -qx stop "$STOP_LOG"
}

test_stop_skipped_without_published_compose() {
  reset_update_fixture stop-first-run
  rm -f -- "$COMPOSE_FILE"
  printf 'APP_DIRECTORIES=appdata\nAPP_UID=%s\nAPP_GID=%s\n' "$(id -u)" "$(id -g)" >"$ENV_FILE"
  FORCE=true
  INITIAL_RUN=true
  RUNNING_IDS="cid-running"
  export RUNNING_IDS
  apply_all_permissions "$ENV_FILE"
  [[ ! -s "$STOP_LOG" ]]
}

test_stop_failure_is_fail_closed() {
  reset_update_fixture stop-fail
  printf 'APP_DIRECTORIES=appdata\nAPP_UID=%s\nAPP_GID=%s\n' "$(id -u)" "$(id -g)" >"$ENV_FILE"
  FORCE=true
  RUNNING_IDS="cid-running"
  FAIL_STOP=1
  export RUNNING_IDS FAIL_STOP
  if apply_all_permissions "$ENV_FILE"; then
    return 1
  fi
}

test_stop_skipped_when_not_mutating() {
  reset_update_fixture stop-no-mutate
  printf 'APP_DIRECTORIES=appdata\nAPP_UID=%s\nAPP_GID=%s\n' "$(id -u)" "$(id -g)" >"$ENV_FILE"
  FORCE=false
  INITIAL_RUN=false
  RUNNING_IDS="cid-running"
  export RUNNING_IDS
  apply_all_permissions "$ENV_FILE"
  [[ ! -s "$STOP_LOG" ]]
}

test_help_does_not_require_lock() {
  bash -- "${TEST_RUN_SH}" --help >/dev/null
}

expect_success update-no-source-env test_update_does_not_source_env
expect_success update-skips-build-only test_update_skips_services_without_image
expect_success update-pull-fail-closed test_update_pull_failure_is_fail_closed
expect_success update-restarts-on-id-change test_update_restarts_when_image_id_changes
expect_success update-no-restart-when-current test_update_skips_restart_when_current
expect_success update-dry-run-no-pull test_update_dry_run_does_not_pull
expect_success update-config-fail-closed test_update_config_failure_is_fail_closed
expect_success project-lock-exclusive test_project_lock_blocks_second_holder
expect_success stop-before-chown test_stop_before_chown_when_running
expect_success stop-skipped-without-compose test_stop_skipped_without_published_compose
expect_success stop-fail-closed test_stop_failure_is_fail_closed
expect_success stop-skipped-when-not-mutating test_stop_skipped_when_not_mutating
expect_success help-without-lock test_help_does_not_require_lock

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
