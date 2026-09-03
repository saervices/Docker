#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RUN.SH DEPLOYMENT TRÆNSÆCTION CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_RUN_SH="${TEST_REPO_ROOT}/run.sh"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-transaction.XXXXXX")"

PASS=0
FAIL=0

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
    sed -n '1,40p' "${TEST_ROOT}/${name}.out" >&2 || true
    fail "$name"
  fi
}

write_valid_app() {
  local project="$1"
  mkdir -p -- "${project}/.${SCRIPT_BASE}.conf"
  cat >"${project}/docker-compose.app.yaml" <<'EOF'
# SPDX-License-Identifier: MIT
x-required-services:
  - redis
services:
  app:
    image: alpine:3.20
    command: ["true"]
EOF
  printf 'APP_NAME=demo\nTZ=UTC\n' >"${project}/app.env"
}

write_redis_template() {
  local checkout="$1"
  mkdir -p -- "${checkout}/templates/redis"
  cat >"${checkout}/templates/redis/docker-compose.redis.yaml" <<'EOF'
# SPDX-License-Identifier: MIT
services:
  redis:
    image: redis:7
    command: ["redis-server"]
EOF
  printf 'REDIS_MEM_LIMIT=64m\n' >"${checkout}/templates/redis/.env"
}

install_docker_stub() {
  local bin_dir="$1"
  local mode="$2"
  mkdir -p -- "$bin_dir"
  cat >"${bin_dir}/docker" <<EOF
#!/bin/sh
if [ "\${DOCKER_COMPOSE_FAIL:-0}" = 1 ] || [ "$mode" = fail ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "${bin_dir}/docker"
}

reset_globals() {
  local project="$1"
  local checkout="$2"
  TARGET_DIR="$project"
  _TMPDIR="$checkout"
  REPO_SUBFOLDER=templates
  FORCE=true
  INITIAL_RUN=true
  DRY_RUN=false
  DEBUG=false
  SKIP_PERMISSIONS=true
  DEPLOYMENT_TRANSACTION_DIR=""
  DEPLOYMENT_TRANSACTION_STAGE=""
  DEPLOYMENT_TRANSACTION_ROLLBACK=""
  DEPLOYMENT_TRANSACTION_PUBLISHED=false
  DEPLOYMENT_TRANSACTION_COMMITTED=false
  TEMPLATE_LOCK_WRITE_PENDING=true
  TEMPLATE_REVISION="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  TEMPLATE_LOCKFILE="${project}/.${SCRIPT_BASE}.conf/.templates.lock"
  DEPLOYMENT_TRANSACTION_PATHS=()
  DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS=()
  DEPLOYMENT_TRANSACTION_ORIGINAL_STATE=()
  unset DEPLOYMENT_PUBLISH_FAIL
}

test_invalid_yaml_leaves_existing_files() {
  local root="${TEST_ROOT}/invalid-yaml"
  local project="${root}/Project"
  mkdir -p -- "$project" "${root}/checkout"
  write_valid_app "$project"
  write_redis_template "${root}/checkout"
  printf 'KEEP_ENV\n' >"${project}/.env"
  printf 'KEEP_COMPOSE\n' >"${project}/docker-compose.main.yaml"
  printf 'services: [\n' >"${project}/docker-compose.app.yaml"
  reset_globals "$project" "${root}/checkout"
  if copy_required_services; then
    return 1
  fi
  [[ "$(<"${project}/.env")" == KEEP_ENV ]]
  [[ "$(<"${project}/docker-compose.main.yaml")" == KEEP_COMPOSE ]]
}

test_compose_config_failure_is_atomic() {
  local root="${TEST_ROOT}/compose-fail"
  local project="${root}/Project"
  mkdir -p -- "$project" "${root}/checkout" "${root}/bin"
  write_valid_app "$project"
  write_redis_template "${root}/checkout"
  printf 'KEEP_ENV\n' >"${project}/.env"
  printf 'KEEP_COMPOSE\n' >"${project}/docker-compose.main.yaml"
  install_docker_stub "${root}/bin" fail
  export PATH="${root}/bin:${PATH}"
  reset_globals "$project" "${root}/checkout"
  copy_required_services
  if validate_deployment_transaction; then
    return 1
  fi
  [[ "$(<"${project}/.env")" == KEEP_ENV ]]
  [[ "$(<"${project}/docker-compose.main.yaml")" == KEEP_COMPOSE ]]
}

test_publish_failure_rolls_back() {
  local root="${TEST_ROOT}/publish-fail"
  local project="${root}/Project"
  mkdir -p -- "$project" "${root}/checkout" "${root}/bin"
  write_valid_app "$project"
  write_redis_template "${root}/checkout"
  printf 'KEEP_ENV\n' >"${project}/.env"
  printf 'KEEP_COMPOSE\n' >"${project}/docker-compose.main.yaml"
  install_docker_stub "${root}/bin" ok
  export PATH="${root}/bin:${PATH}"
  reset_globals "$project" "${root}/checkout"
  copy_required_services
  validate_deployment_transaction
  DEPLOYMENT_PUBLISH_FAIL="${project}/.env"
  if publish_deployment_transaction; then
    return 1
  fi
  [[ "$(<"${project}/.env")" == KEEP_ENV ]]
  [[ "$(<"${project}/docker-compose.main.yaml")" == KEEP_COMPOSE ]]
}

test_successful_publish_replaces_generated_files() {
  local root="${TEST_ROOT}/publish-ok"
  local project="${root}/Project"
  mkdir -p -- "$project" "${root}/checkout" "${root}/bin"
  write_valid_app "$project"
  write_redis_template "${root}/checkout"
  printf 'KEEP_ENV\n' >"${project}/.env"
  printf 'KEEP_COMPOSE\n' >"${project}/docker-compose.main.yaml"
  install_docker_stub "${root}/bin" ok
  export PATH="${root}/bin:${PATH}"
  reset_globals "$project" "${root}/checkout"
  copy_required_services
  validate_deployment_transaction
  publish_deployment_transaction
  finish_deployment_transaction
  grep -q 'APP_NAME=demo' "${project}/.env"
  grep -q 'services:' "${project}/docker-compose.main.yaml"
  [[ -f "${project}/docker-compose.redis.yaml" ]]
  [[ "$(<"${project}/.${SCRIPT_BASE}.conf/.templates.lock")" == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]]
}

expect_success invalid-yaml-atomic test_invalid_yaml_leaves_existing_files
expect_success compose-config-atomic test_compose_config_failure_is_atomic
expect_success publish-failure-rollback test_publish_failure_rolls_back
expect_success successful-publish test_successful_publish_replaces_generated_files

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
