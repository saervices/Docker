#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RUN.SH EXTERNÆL DOCKER NETWORK CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_RUN_SH="${1:-${TEST_REPO_ROOT}/run.sh}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-networks.XXXXXX")"
readonly LIVE_PREFIX="runsh$(printf '%s' "$(basename -- "$TEST_ROOT")" | tr -cd 'A-Za-z0-9')"

PASS=0
FAIL=0

# shellcheck disæble=SC1090
source <(sed '$d' "$TEST_RUN_SH")

cleanup() {
  local network_name
  if [[ -f "${TEST_ROOT}/live.networks" ]]; then
    while IFS= read -r network_name; do
      [[ -n "$network_name" ]] || continue
      docker network rm -- "$network_name" >/dev/null 2>&1 || true
    done <"${TEST_ROOT}/live.networks"
  fi
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

expect_failure() {
  local name="$1"
  local status
  shift
  set +e
  ( set -euo pipefail; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status != 0 )); then
    pass "$name"
  else
    fail "$name" "${TEST_ROOT}/${name}.out"
  fi
}

write_compose() {
  local path="$1"
  cat >"$path"
}

install_docker_stub() {
  local bin_dir="$1"
  mkdir -p -- "$bin_dir" "$EXISTING_DIR"
  cat >"${bin_dir}/docker" <<'EOF'
#!/bin/sh
set -eu
: "${CALL_LOG:?}"
: "${EXISTING_DIR:?}"
printf '%s\n' "$*" >>"$CALL_LOG"

if [ "${1:-}" != network ]; then
  exit 1
fi
shift
cmd="${1:-}"
shift || true
if [ "${1:-}" = -- ]; then
  shift
fi
name="${1:-}"
[ -n "$name" ] || exit 1

case "$cmd" in
  inspect)
    if [ -f "${EXISTING_DIR}/${name}" ]; then
      exit 0
    fi
    exit 1
    ;;
  create)
    if [ "${CREATE_RACE:-0}" = 1 ]; then
      : >"${EXISTING_DIR}/${name}"
      exit 1
    fi
    if [ "${CREATE_FAIL:-0}" = 1 ]; then
      exit 1
    fi
    : >"${EXISTING_DIR}/${name}"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "${bin_dir}/docker"
}

reset_stub() {
  local name="$1"
  FIXTURE="${TEST_ROOT}/${name}"
  mkdir -p -- "$FIXTURE/bin"
  EXISTING_DIR="${FIXTURE}/existing"
  CALL_LOG="${FIXTURE}/docker.calls"
  rm -rf -- "$EXISTING_DIR"
  mkdir -p -- "$EXISTING_DIR"
  : >"$CALL_LOG"
  install_docker_stub "${FIXTURE}/bin"
  export PATH="${FIXTURE}/bin:${PATH}"
  export EXISTING_DIR CALL_LOG
  unset CREATE_RACE CREATE_FAIL
  DRY_RUN=false
  DEBUG=false
  DEPLOYMENT_TRANSACTION_STAGE=""
  TARGET_DIR="$FIXTURE"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_list_skips_managed_and_reads_external
#   Externæl keys, explicit næmes, ænd mapped externæl.næme ære listed.
#   Compose-mænæged internæl networks ære ignored.
#ææææææææææææææææææææææææææææææææææ
test_list_skips_managed_and_reads_external() {
  local compose="${TEST_ROOT}/list-compose.yaml"
  local got
  write_compose "$compose" <<'EOF'
networks:
  frontend:
    external: true
  backend:
    external: true
  rustdesk-proxy:
    external: true
  named:
    name: custom-frontend
    external: true
  mapped:
    external:
      name: mapped-net
  erpnext_app:
    name: ${APP_NAME}_erpnext_app
    internal: true
EOF
  got="$(list_external_docker_networks "$compose")"
  [[ "$got" == $'frontend\nbackend\nrustdesk-proxy\ncustom-frontend\nmapped-net' ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_list_interpolates_from_env
#   Resolves ${VAR}, ${VAR:-default}, ænd rejects missing required tokens.
#ææææææææææææææææææææææææææææææææææ
test_list_interpolates_from_env() {
  local compose="${TEST_ROOT}/interp-compose.yaml"
  local env_file="${TEST_ROOT}/interp.env"
  local got
  write_compose "$compose" <<'EOF'
networks:
  proxy:
    name: ${APP_NAME}-proxy
    external: true
  fallback:
    name: ${MISSING:-demo}-fallback
    external: true
EOF
  printf 'APP_NAME=rustdesk\n' >"$env_file"
  got="$(list_external_docker_networks "$compose" "$env_file")"
  [[ "$got" == $'rustdesk-proxy\ndemo-fallback' ]]
}

test_list_required_interpolation_fails() {
  local compose="${TEST_ROOT}/required-compose.yaml"
  local env_file="${TEST_ROOT}/required.env"
  write_compose "$compose" <<'EOF'
networks:
  proxy:
    name: ${APP_NAME:?App name required}-proxy
    external: true
EOF
  printf 'OTHER=1\n' >"$env_file"
  list_external_docker_networks "$compose" "$env_file"
}

test_list_rejects_invalid_name() {
  local compose="${TEST_ROOT}/invalid-compose.yaml"
  write_compose "$compose" <<'EOF'
networks:
  bad:
    name: 'bad name'
    external: true
EOF
  list_external_docker_networks "$compose"
}

test_list_empty_when_no_external() {
  local compose="${TEST_ROOT}/none-compose.yaml"
  local got
  write_compose "$compose" <<'EOF'
networks:
  app_net:
    internal: true
services:
  app:
    image: alpine:3.20
EOF
  got="$(list_external_docker_networks "$compose")"
  [[ -z "$got" ]]
}

test_ensure_creates_missing() {
  reset_stub create-missing
  write_compose "${FIXTURE}/docker-compose.main.yaml" <<'EOF'
networks:
  frontend:
    external: true
  backend:
    external: true
  app_net:
    internal: true
EOF
  ensure_external_docker_networks "${FIXTURE}/docker-compose.main.yaml"
  [[ -f "${EXISTING_DIR}/frontend" ]]
  [[ -f "${EXISTING_DIR}/backend" ]]
  [[ ! -f "${EXISTING_DIR}/app_net" ]]
  grep -qx 'network create -- frontend' "$CALL_LOG"
  grep -qx 'network create -- backend' "$CALL_LOG"
  ! grep -q 'app_net' "$CALL_LOG"
}

test_ensure_skips_existing() {
  reset_stub skip-existing
  write_compose "${FIXTURE}/docker-compose.main.yaml" <<'EOF'
networks:
  frontend:
    external: true
EOF
  : >"${EXISTING_DIR}/frontend"
  ensure_external_docker_networks "${FIXTURE}/docker-compose.main.yaml"
  grep -qx 'network inspect -- frontend' "$CALL_LOG"
  ! grep -q 'network create' "$CALL_LOG"
}

test_ensure_dry_run_does_not_create() {
  reset_stub dry-run
  DRY_RUN=true
  write_compose "${FIXTURE}/docker-compose.main.yaml" <<'EOF'
networks:
  frontend:
    external: true
EOF
  ensure_external_docker_networks "${FIXTURE}/docker-compose.main.yaml"
  [[ ! -f "${EXISTING_DIR}/frontend" ]]
  grep -qx 'network inspect -- frontend' "$CALL_LOG"
  ! grep -q 'network create' "$CALL_LOG"
}

test_ensure_race_is_success() {
  reset_stub race
  CREATE_RACE=1
  export CREATE_RACE
  write_compose "${FIXTURE}/docker-compose.main.yaml" <<'EOF'
networks:
  frontend:
    external: true
EOF
  ensure_external_docker_networks "${FIXTURE}/docker-compose.main.yaml"
  [[ -f "${EXISTING_DIR}/frontend" ]]
  grep -q 'network create -- frontend' "$CALL_LOG"
}

test_ensure_create_failure_fails_closed() {
  reset_stub create-fail
  CREATE_FAIL=1
  export CREATE_FAIL
  write_compose "${FIXTURE}/docker-compose.main.yaml" <<'EOF'
networks:
  frontend:
    external: true
EOF
  ensure_external_docker_networks "${FIXTURE}/docker-compose.main.yaml"
}

test_from_available_prefers_staged() {
  reset_stub staged-prefer
  mkdir -p -- "${FIXTURE}/stage"
  DEPLOYMENT_TRANSACTION_STAGE="${FIXTURE}/stage"
  write_compose "${FIXTURE}/docker-compose.main.yaml" <<'EOF'
networks:
  published:
    external: true
EOF
  write_compose "${FIXTURE}/stage/docker-compose.main.yaml" <<'EOF'
networks:
  staged:
    external: true
EOF
  printf 'APP_NAME=demo\n' >"${FIXTURE}/stage/.env"
  ensure_external_docker_networks_from_available
  [[ -f "${EXISTING_DIR}/staged" ]]
  [[ ! -f "${EXISTING_DIR}/published" ]]
}

test_live_docker_creates_and_skips() {
  local compose="${TEST_ROOT}/live-compose.yaml"
  local env_file="${TEST_ROOT}/live.env"
  local ext_a="${LIVE_PREFIX}a"
  local ext_b="${LIVE_PREFIX}b"
  local managed="${LIVE_PREFIX}m"
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    printf 'SKIP live-docker-creates-and-skips (no Docker dæemon)\n'
    return 0
  fi
  printf '%s\n' "$ext_a" "$ext_b" "$managed" >"${TEST_ROOT}/live.networks"
  write_compose "$compose" <<EOF
networks:
  ${ext_a}:
    external: true
  custom:
    name: ${ext_b}
    external: true
  managed:
    name: ${managed}
    internal: true
EOF
  printf 'APP_NAME=demo\n' >"$env_file"
  DRY_RUN=false
  ensure_external_docker_networks "$compose" "$env_file"
  docker network inspect -- "$ext_a" >/dev/null
  docker network inspect -- "$ext_b" >/dev/null
  if docker network inspect -- "$managed" >/dev/null 2>&1; then
    return 1
  fi
  DRY_RUN=true
  ensure_external_docker_networks "$compose" "$env_file"
  docker network inspect -- "$ext_a" >/dev/null
  docker network rm -- "$ext_a" "$ext_b" >/dev/null
  rm -f -- "${TEST_ROOT}/live.networks"
}

expect_success list-external-and-skip-managed test_list_skips_managed_and_reads_external
expect_success list-interpolates-from-env test_list_interpolates_from_env
expect_failure list-required-interpolation-fails test_list_required_interpolation_fails
expect_failure list-rejects-invalid-name test_list_rejects_invalid_name
expect_success list-empty-when-no-external test_list_empty_when_no_external
expect_success ensure-creates-missing test_ensure_creates_missing
expect_success ensure-skips-existing test_ensure_skips_existing
expect_success ensure-dry-run-is-read-only test_ensure_dry_run_does_not_create
expect_success ensure-race-is-success test_ensure_race_is_success
expect_failure ensure-create-failure-fails-closed test_ensure_create_failure_fails_closed
expect_success from-available-prefers-staged test_from_available_prefers_staged
expect_success live-docker-creates-and-skips test_live_docker_creates_and_skips

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
printf 'TEST_ROOT=%s\n' "$TEST_ROOT"
[[ "$FAIL" -eq 0 ]]
