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
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-transaction.XXXXXX")"

PASS=0
FAIL=0

# Loæd functions without executing run.sh's finæl mæin cæll.
# shellcheck disable=SC1090
source <(sed '$d' "$TEST_RUN_SH")

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes every disposæble test fixture unless evidence retention is enabled.
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
#   Ærguments:
#     $1 - test næme
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled regression cæse.
#   Ærguments:
#     $1 - test næme
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_success
#   Runs one cæse in æ strict isolæted subshell ænd records its result.
#   Ærguments:
#     $1 - test næme
#     $@ - test function ænd ærguments
#ææææææææææææææææææææææææææææææææææ
expect_success() {
  local name="$1"
  local status
  shift
  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reset_transaction_globals
#   Resets run.sh stæte for one test project.
#   Ærguments:
#     $1 - project directory
#     $2 - checked-out fixture root
#ææææææææææææææææææææææææææææææææææ
reset_transaction_globals() {
  TARGET_DIR="$1"
  _TMPDIR="$2"
  _TMPDIR_IDENTITY="$(stat -Lc '%d:%i' -- "$_TMPDIR")"
  _TMPDIR_FD=""
  TMPDIR_PRESERVE=false
  REPO_SUBFOLDER=templates
  FORCE=true
  INITIAL_RUN=false
  DRY_RUN=false
  DEBUG=false
  LOGFILE=""
  SKIP_PERMISSIONS=true
  TEMPLATE_LOCKFILE="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.templates.lock"
  TEMPLATE_REVISION="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  TEMPLATE_LOCK_WRITE_PENDING=true
  TEMPLATE_LOCK_STAGED_FILE=""
  PROJECT_LOCK_FD=""
  PROJECT_LOCK_IDENTITY=""
  PROJECT_BOOTSTRAP_LOCK_FD=""
  DEPLOYMENT_TRANSACTION_DIR=""
  DEPLOYMENT_TRANSACTION_DIR_IDENTITY=""
  DEPLOYMENT_TRANSACTION_DIR_FD=""
  DEPLOYMENT_TRANSACTION_STAGE=""
  DEPLOYMENT_TRANSACTION_ROLLBACK=""
  DEPLOYMENT_TRANSACTION_PUBLISHED=false
  DEPLOYMENT_TRANSACTION_PRESERVE=false
  DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
  DEPLOYMENT_TRANSACTION_COMMITTED=false
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
  DEPLOYMENT_TRANSACTION_PATHS=()
  DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS=()
  DEPLOYMENT_TRANSACTION_CREATED_DIRS=()
  DEPLOYMENT_TRANSACTION_MODE_CHANGED_DIRS=()
  DEPLOYMENT_TRANSACTION_OWNERSHIP=()
  DEPLOYMENT_TRANSACTION_ORIGINAL_STATE=()
  DEPLOYMENT_TRANSACTION_ORIGINAL_DIRECTORY_MODES=()
  DEPLOYMENT_TRANSACTION_DIRECTORY_IDENTITIES=()
  PERMISSION_ENV_FILE=""
  PERMISSION_CREATED_IDENTITIES=()
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_top_level_temp_replacement_is_preserved
#   Proves EXIT cleænup removes its unchanged inode but never æ foreign reæl
#   directory thæt replæces the registered top-level temporæry root pæth.
#ææææææææææææææææææææææææææææææææææ
test_top_level_temp_replacement_is_preserved() {
  local root="${TEST_ROOT}/temp-replacement"
  local registered=""
  local displaced=""
  local owned=""

  mkdir -p -- "$root"
  TARGET_DIR="${root}/Project"
  mkdir -- "$TARGET_DIR"
  DEPLOYMENT_TRANSACTION_DIR=""
  DEPLOYMENT_TRANSACTION_DIR_IDENTITY=""
  DEPLOYMENT_TRANSACTION_DIR_FD=""
  DEPLOYMENT_TRANSACTION_PRESERVE=false
  DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
  DEPLOYMENT_TRANSACTION_COMMITTED=false
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
  SOURCE_SYNC_PRESERVE=false
  SOURCE_SYNC_COMMITTED=false
  SOURCE_SYNC_STAGE=""
  SOURCE_SYNC_SEEDS=""
  SOURCE_SYNC_JOURNAL=""
  SYNC_SOURCE=false
  DRY_RUN=false
  HOST_LOGROTATE_PRIVILEGED_TMP=""
  HOST_LOGROTATE_ROLLBACK_TMP=""
  _TMPDIR=""
  _TMPDIR_IDENTITY=""
  _TMPDIR_FD=""
  TMPDIR_PRESERVE=false

  create_owned_temporary_directory "${root}/registered.XXXXXX" "replacement regression"
  registered="$_TMPDIR"
  displaced="${registered}.displaced"
  mv -T -- "$registered" "$displaced"
  mkdir --mode=0700 -- "$registered"
  printf '%s\n' foreign > "${registered}/foreign.marker"

  cleanup_temporary_state

  [[ "$TMPDIR_PRESERVE" == true ]]
  [[ -f "${registered}/foreign.marker" ]]
  [[ -d "$displaced" ]]

  exec {_TMPDIR_FD}<&-
  _TMPDIR=""
  _TMPDIR_IDENTITY=""
  _TMPDIR_FD=""
  TMPDIR_PRESERVE=false
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
  create_owned_temporary_directory "${root}/owned.XXXXXX" "owned cleanup regression"
  owned="$_TMPDIR"
  printf '%s\n' owned > "${owned}/owned.marker"

  cleanup_temporary_state

  [[ "$TMPDIR_PRESERVE" == false ]]
  [[ ! -e "$owned" && ! -L "$owned" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_fake_docker
#   Instælls æ deterministic Compose vælidætion fixture.
#   Ærguments:
#     $1 - bin directory
#ææææææææææææææææææææææææææææææææææ
install_fake_docker() {
  local bin_dir="$1"
  mkdir -p -- "$bin_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'compose_file=""' \
    'while (( $# )); do' \
    '  if [[ "$1" == "-f" ]]; then compose_file="$2"; shift 2; continue; fi' \
    '  shift' \
    'done' \
    'if [[ -n "$compose_file" ]] && rg -q "late_invalid:" "$compose_file"; then exit 61; fi' \
    'exit 0' >"${bin_dir}/docker"
  chmod 0755 -- "${bin_dir}/docker"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_fake_mv
#   Delegætes normæl renæmes but injects one selected publicætion failure.
#   Ærguments:
#     $1 - bin directory
#ææææææææææææææææææææææææææææææææææ
install_fake_mv() {
  local bin_dir="$1"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'source_arg="${@: -2:1}"' \
    'destination_arg="${@: -1}"' \
    'case "${MV_FAIL_KIND:-}" in' \
    '  publish)' \
    '    if [[ "$destination_arg" == */docker-compose.example.yaml && "$source_arg" == *.tmp.* ]]; then exit 72; fi' \
    '    ;;' \
    '  lock)' \
    '    if [[ "$destination_arg" == */.templates.lock && "$source_arg" == *.lock.tmp.* ]]; then exit 73; fi' \
    '    ;;' \
    '  interrupt)' \
    '    if [[ "$destination_arg" == */docker-compose.example.yaml && "$source_arg" == *.tmp.* ]]; then' \
    '      /usr/bin/mv "$@"' \
    '      kill -TERM "${MV_INTERRUPT_PID:?}"' \
    '      exit 0' \
    '    fi' \
    '    ;;' \
    'esac' \
    'exec /usr/bin/mv "$@"' >"${bin_dir}/mv"
  chmod 0755 -- "${bin_dir}/mv"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_fixture
#   Creætes one existing deployment ænd one checked-out templæte source.
#   Ærguments:
#     $1 - fixture root
#     $2 - templæte mode: valid, invalid_yaml, invalid_compose, or invalid_permissions
#ææææææææææææææææææææææææææææææææææ
create_fixture() {
  local root="$1"
  local mode="$2"
  local project="${root}/Project"
  local template="${root}/checkout/templates/example"

  mkdir -p -- "$project/.${SCRIPT_BASE}.conf" "$project/scripts" "$template/scripts" "${root}/bin"
  install_fake_docker "${root}/bin"
  install_fake_mv "${root}/bin"

  printf '%s\n' \
    '---' \
    'x-required-services:' \
    '  - example' \
    'services:' \
    '  app:' \
    '    image: ${APP_IMAGE:?Image required}' \
    '    environment:' \
    '      KEEP: current' \
    'networks:' \
    '  backend:' \
    '    external: true' >"${project}/docker-compose.app.yaml"
  printf '%s\n' \
    'APP_IMAGE=busybox:latest' \
    'APP_NAME=transaction-test' \
    'APP_UID=1000' \
    'APP_GID=1000' >"${project}/app.env"
  printf '%s\n' \
    'APP_IMAGE=busybox:latest' \
    'APP_NAME=transaction-test' \
    'APP_UID=1000' \
    'APP_GID=1000' \
    'STALE_ENV=remove-me' >"${project}/.env"
  printf '%s\n' \
    '---' \
    'services:' \
    '  app:' \
    '    image: busybox:latest' \
    '    environment:' \
    '      STALE_ENV: remove-me' \
    '    security_opt:' \
    '      - stale-option' \
    '  stale_service:' \
    '    image: busybox:latest' \
    'volumes:' \
    '  stale_volume: {}' \
    'secrets:' \
    '  stale_secret:' \
    '    file: ./STALE' \
    'networks:' \
    '  stale_network:' \
    '    external: true' >"${project}/docker-compose.main.yaml"
  printf '%s\n' 'services:' '  example:' '    image: stale:latest' >"${project}/docker-compose.example.yaml"
  printf '%s\n' 'services:' '  example:' '    read_only: true' >"${project}/docker-compose.example.restore.yaml.example"
  printf '%s\n' '#!/usr/bin/env bash' 'printf old-helper' >"${project}/scripts/helper.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'printf local-helper' >"${project}/scripts/local.sh"
  chmod 0644 -- "${project}/scripts/helper.sh" "${project}/scripts/local.sh"
  printf '%s\n' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' >"${project}/.${SCRIPT_BASE}.conf/.templates.lock"

  printf '%s\n' 'EXAMPLE_IMAGE=busybox:latest' >"${template}/.env"
  printf '%s\n' '#!/usr/bin/env bash' 'printf new-helper' >"${template}/scripts/helper.sh"
  printf '%s\n' 'services:' '  example:' '    read_only: false' >"${template}/docker-compose.example.restore.yaml.example"

  case "$mode" in
    valid|invalid_permissions)
      printf '%s\n' \
        '---' \
        'services:' \
        '  example:' \
        '    image: ${EXAMPLE_IMAGE:?Image required}' \
        'networks:' \
        '  backend:' \
        '    external: true' >"${template}/docker-compose.example.yaml"
      if [[ "$mode" == invalid_permissions ]]; then
        printf '%s\n' \
          'BAD_DIRECTORIES=../escape' \
          'BAD_UID=1000' \
          'BAD_GID=1000' >>"${template}/.env"
      fi
      ;;
    invalid_yaml)
      printf '%s\n' 'services:' '  example:' '    image: [unterminated' >"${template}/docker-compose.example.yaml"
      ;;
    invalid_compose)
      printf '%s\n' \
        '---' \
        'services:' \
        '  example:' \
        '    image: ${EXAMPLE_IMAGE:?Image required}' \
        '    late_invalid: true' >"${template}/docker-compose.example.yaml"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: deployment_digest
#   Returns one deterministic digest of every coherence-sensitive deployment file.
#   Ærguments:
#     $1 - project directory
#ææææææææææææææææææææææææææææææææææ
deployment_digest() {
  local project="$1"
  local relative_path
  stat -c '%a %n' -- "${project}/scripts"
  for relative_path in \
    .env \
    docker-compose.main.yaml \
    docker-compose.example.yaml \
    docker-compose.example.restore.yaml.example \
    scripts/helper.sh \
    scripts/local.sh \
    ".${SCRIPT_BASE}.conf/.templates.lock"; do
    stat -c '%a %n' -- "${project}/${relative_path}"
    sha256sum -- "${project}/${relative_path}"
  done | sha256sum | awk '{print $1}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_transaction
#   Builds one prospective refresh ænd returns only æfter complete vælidætion.
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
prepare_transaction() {
  local root="$1"
  export PATH="${root}/bin:${PATH}"
  reset_transaction_globals "${root}/Project" "${root}/checkout"
  acquire_project_lock
  copy_required_services
  stage_existing_script_mode_updates
  make_scripts_executable "${DEPLOYMENT_TRANSACTION_STAGE}/scripts"
  validate_deployment_transaction
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REGRESSION CÆSES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_nested_local_script_directory_modes
#   Proves locæl nested shebæng helpers stæge ænd publish with the
#   complete scripts/** directory-mode contræct under the privæte umæsk.
#ææææææææææææææææææææææææææææææææææ
test_nested_local_script_directory_modes() {
  local root="${TEST_ROOT}/nested-local-script"
  local project="${root}/Project"
  local nested_dir="${project}/scripts/vaultwarden.d"
  local staged_dir=""

  create_fixture "$root" valid
  mkdir -p -- "$nested_dir"
  chmod 0755 -- "$nested_dir"
  printf '%s\n' '#!/bin/sh' 'printf nested-helper' >"${nested_dir}/10-database-url.sh"
  chmod 0644 -- "${nested_dir}/10-database-url.sh"

  prepare_transaction "$root"
  staged_dir="${DEPLOYMENT_TRANSACTION_STAGE}/scripts/vaultwarden.d"
  [[ "$(stat -Lc '%a' -- "$staged_dir")" == 755 ]]
  [[ "$(stat -Lc '%a' -- "${staged_dir}/10-database-url.sh")" == 755 ]]

  publish_deployment_transaction
  finish_deployment_transaction
  [[ "$(stat -Lc '%a' -- "$nested_dir")" == 755 ]]
  [[ "$(stat -Lc '%a' -- "${nested_dir}/10-database-url.sh")" == 755 ]]
}

test_force_drops_stale_keys() {
  local root="${TEST_ROOT}/stale"
  local project="${root}/Project"
  create_fixture "$root" valid
  prepare_transaction "$root"
  publish_deployment_transaction
  finish_deployment_transaction

  ! rg -q '^STALE_ENV=' "${project}/.env"
  yq -e '.services | has("stale_service") | not' "${project}/docker-compose.main.yaml" >/dev/null
  yq -e '.services.app.environment | has("STALE_ENV") | not' "${project}/docker-compose.main.yaml" >/dev/null
  yq -e '.services.app | has("security_opt") | not' "${project}/docker-compose.main.yaml" >/dev/null
  yq -e '.volumes | has("stale_volume") | not' "${project}/docker-compose.main.yaml" >/dev/null
  yq -e '.secrets | has("stale_secret") | not' "${project}/docker-compose.main.yaml" >/dev/null
  yq -e '.networks | has("stale_network") | not' "${project}/docker-compose.main.yaml" >/dev/null
  rg -q 'new-helper' "${project}/scripts/helper.sh"
  rg -q 'local-helper' "${project}/scripts/local.sh"
  [[ "$(stat -c '%a' -- "${project}/scripts")" == 755 ]]
  [[ "$(stat -c '%a' -- "${project}/scripts/local.sh")" == 755 ]]
  yq -e '.services.example.read_only == false' "${project}/docker-compose.example.restore.yaml.example" >/dev/null
  [[ "$(<"${project}/.${SCRIPT_BASE}.conf/.templates.lock")" == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]]
}

test_initial_legacy_env_and_secret_transaction() {
  local root="${TEST_ROOT}/initial"
  local project="${root}/Project"
  local original_env_digest
  local -a exclusions=()

  create_fixture "$root" valid
  rm -f -- "${project}/app.env" "${project}/.${SCRIPT_BASE}.conf/.templates.lock"
  mkdir -p -- "${project}/secrets"
  printf 'CHANGE_ME' >"${project}/secrets/APP_PASSWORD"
  original_env_digest=$(sha256sum -- "${project}/.env" | awk '{print $1}')

  export PATH="${root}/bin:${PATH}"
  reset_transaction_globals "$project" "${root}/checkout"
  INITIAL_RUN=true
  acquire_project_lock
  copy_required_services
  prepare_transaction_secrets
  SECRET_GENERATION_LENGTHS=()
  generate_password "${DEPLOYMENT_TRANSACTION_STAGE}/secrets" "" "" "${exclusions[@]}"
  register_changed_transaction_secrets
  stage_existing_script_mode_updates
  make_scripts_executable "${DEPLOYMENT_TRANSACTION_STAGE}/scripts"
  validate_deployment_transaction
  publish_deployment_transaction
  finish_deployment_transaction

  [[ -f "${project}/app.env" ]]
  [[ "$(sha256sum -- "${project}/app.env" | awk '{print $1}')" == "$original_env_digest" ]]
  [[ "$(stat -c '%s' -- "${project}/secrets/APP_PASSWORD")" == 100 ]]
  [[ "$(<"${project}/secrets/APP_PASSWORD")" != CHANGE_ME ]]
  [[ "$(<"${project}/.${SCRIPT_BASE}.conf/.templates.lock")" == bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ]]
}

test_invalid_yaml_is_nonzero_and_atomic() {
  local root="${TEST_ROOT}/invalid-yaml"
  local before after
  create_fixture "$root" invalid_yaml
  before=$(deployment_digest "${root}/Project")
  export PATH="${root}/bin:${PATH}"
  reset_transaction_globals "${root}/Project" "${root}/checkout"
  acquire_project_lock
  if copy_required_services; then
    return 1
  fi
  after=$(deployment_digest "${root}/Project")
  [[ "$before" == "$after" ]]
}

test_late_compose_failure_is_atomic() {
  local root="${TEST_ROOT}/late-compose"
  local before after
  create_fixture "$root" invalid_compose
  before=$(deployment_digest "${root}/Project")
  export PATH="${root}/bin:${PATH}"
  reset_transaction_globals "${root}/Project" "${root}/checkout"
  acquire_project_lock
  copy_required_services
  if validate_deployment_transaction; then
    return 1
  fi
  after=$(deployment_digest "${root}/Project")
  [[ "$before" == "$after" ]]
}

test_late_permission_failure_is_atomic() {
  local root="${TEST_ROOT}/late-permissions"
  local before after
  create_fixture "$root" invalid_permissions
  before=$(deployment_digest "${root}/Project")
  prepare_transaction "$root"
  if apply_all_permissions \
    "${DEPLOYMENT_TRANSACTION_STAGE}/.env" \
    "${DEPLOYMENT_TRANSACTION_STAGE}/docker-compose.main.yaml"; then
    return 1
  fi
  after=$(deployment_digest "${root}/Project")
  [[ "$before" == "$after" ]]
  [[ ! -e "${root}/escape" ]]
}

test_publish_failure_rolls_back() {
  local root="${TEST_ROOT}/publish-failure"
  local before after
  create_fixture "$root" valid
  prepare_transaction "$root"
  before=$(deployment_digest "${root}/Project")
  export MV_FAIL_KIND=publish
  if publish_deployment_transaction; then
    unset MV_FAIL_KIND
    return 1
  fi
  unset MV_FAIL_KIND
  after=$(deployment_digest "${root}/Project")
  [[ "$before" == "$after" ]]
}

test_lock_failure_rolls_back() {
  local root="${TEST_ROOT}/lock-failure"
  local before after
  create_fixture "$root" valid
  prepare_transaction "$root"
  before=$(deployment_digest "${root}/Project")
  publish_deployment_transaction
  export MV_FAIL_KIND=lock
  if finish_deployment_transaction; then
    unset MV_FAIL_KIND
    return 1
  fi
  unset MV_FAIL_KIND
  after=$(deployment_digest "${root}/Project")
  [[ "$before" == "$after" ]]
}

test_signal_interrupt_rolls_back() {
  local root="${TEST_ROOT}/signal-interrupt"
  local project="${root}/Project"
  local before after status

  create_fixture "$root" valid
  prepare_transaction "$root"
  before=$(deployment_digest "$project")

  set +e
  (
    setup_cleanup_trap
    export MV_FAIL_KIND=interrupt
    export MV_INTERRUPT_PID="$BASHPID"
    publish_deployment_transaction
    finish_deployment_transaction
  )
  status=$?
  set -e

  (( status == 143 ))
  after=$(deployment_digest "$project")
  [[ "$before" == "$after" ]]
  [[ "$(<"${project}/.${SCRIPT_BASE}.conf/.templates.lock")" == aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]]
  [[ -z "$(find "${project}/.${SCRIPT_BASE}.conf" -mindepth 1 -maxdepth 1 -type d -name '.transaction.*' -print -quit)" ]]
}

test_exclusive_project_lock() {
  local root="${TEST_ROOT}/lock"
  local project="${root}/Project"
  local ready="${root}/ready"
  local release="${root}/release"
  local holder_pid status

  mkdir -p -- "$project"
  mkfifo -- "$release"
  (
    TARGET_DIR="$project"
    PROJECT_LOCK_FD=""
    PROJECT_LOCK_IDENTITY=""
    PROJECT_BOOTSTRAP_LOCK_FD=""
    acquire_project_lock
    : > "$ready"
    read -r _ < "$release" || true
  ) &
  holder_pid=$!
  for _ in {1..100}; do
    [[ -e "$ready" ]] && break
    sleep 0.02
  done
  [[ -e "$ready" ]]

  set +e
  (
    TARGET_DIR="$project"
    PROJECT_LOCK_FD=""
    PROJECT_LOCK_IDENTITY=""
    PROJECT_BOOTSTRAP_LOCK_FD=""
    acquire_project_lock
  )
  status=$?
  set -e
  printf 'release\n' > "$release"
  wait "$holder_pid"
  (( status != 0 ))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_dry_run_lock_is_read_only
#   Proves first-use dry-run locking creætes no deployment runtime directory.
#ææææææææææææææææææææææææææææææææææ
test_dry_run_lock_is_read_only() {
  local root="${TEST_ROOT}/dry-lock"
  local project="${root}/Project"

  mkdir -p -- "$project"
  TARGET_DIR="$project"
  DRY_RUN=true
  PROJECT_LOCK_FD=""
  PROJECT_LOCK_IDENTITY=""
  PROJECT_BOOTSTRAP_LOCK_FD=""
  acquire_project_lock
  [[ ! -e "${project}/.${SCRIPT_BASE}.conf" ]]
}

test_mutating_modes_stop_at_lock() {
  local root="${TEST_ROOT}/locked-modes"
  local project="${root}/Project"
  local runtime="${project}/.run.conf"
  local ready="${root}/ready"
  local release="${root}/release"
  local docker_called="${root}/docker-called"
  local holder_pid mode

  mkdir -p -- "$runtime" "${project}/secrets" "${root}/bin"
  cp -- "$TEST_RUN_SH" "${root}/run.sh"
  chmod 0755 -- "${root}/run.sh"
  printf 'CHANGE_ME' >"${project}/secrets/APP_PASSWORD"
  printf '%s\n' 'APP_GID=1000' >"${project}/.env"
  printf '%s\n' 'services:' '  app:' '    image: busybox:latest' >"${project}/docker-compose.app.yaml"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf called > "${DOCKER_CALLED:?}"' \
    'exit 0' >"${root}/bin/docker"
  chmod 0755 -- "${root}/bin/docker"
  mkfifo -- "$release"

  (
    exec 9<"$runtime"
    flock --exclusive 9
    : > "$ready"
    read -r _ < "$release" || true
  ) &
  holder_pid=$!
  for _ in {1..100}; do
    [[ -e "$ready" ]] && break
    sleep 0.02
  done
  [[ -e "$ready" ]]

  for mode in --update --delete_volumes --generate_password; do
    if DOCKER_CALLED="$docker_called" PATH="${root}/bin:${PATH}" \
      "${root}/run.sh" Project "$mode" >"${root}/${mode#--}.out" 2>&1; then
      printf 'release\n' > "$release"
      wait "$holder_pid"
      return 1
    fi
  done
  printf 'release\n' > "$release"
  wait "$holder_pid"

  [[ "$(stat -c '%s' -- "${project}/secrets/APP_PASSWORD")" == 9 ]]
  [[ "$(<"${project}/secrets/APP_PASSWORD")" == CHANGE_ME ]]
  [[ ! -e "$docker_called" ]]
  [[ ! -e "${runtime}/logs" ]]
}

test_full_initial_entrypoint() {
  local root="${TEST_ROOT}/full-entrypoint"
  local project="${root}/Project"
  local remote="${root}/remote"
  local current_yq_tag revision deployed_mode image_copy

  create_fixture "$root" valid
  rm -rf -- "${project}/.${SCRIPT_BASE}.conf"
  mkdir -p -- "${root}/checkout/templates/example/dockerfiles"
  printf '%s\n' '#!/bin/sh' 'printf readable-entrypoint' \
    >"${root}/checkout/templates/example/dockerfiles/readable-entrypoint.sh"
  printf '%s\n' '#!/bin/sh' 'printf executable-helper' \
    >"${root}/checkout/templates/example/dockerfiles/executable-helper.sh"
  printf '%s\n' '0 3 * * * /usr/local/bin/backup.sh' \
    >"${root}/checkout/templates/example/scripts/backup.cron"
  chmod 0644 -- \
    "${root}/checkout/templates/example/dockerfiles/readable-entrypoint.sh" \
    "${root}/checkout/templates/example/scripts/backup.cron"
  chmod 0755 -- "${root}/checkout/templates/example/dockerfiles/executable-helper.sh"
  mkdir -p -- "${remote}/templates"
  cp -a -- "${root}/checkout/templates/example" "${remote}/templates/example"
  git -C "$remote" init --quiet --initial-branch=main
  git -C "$remote" config user.name 'Transaction Test'
  git -C "$remote" config user.email 'transaction@example.invalid'
  git -C "$remote" add templates
  git -C "$remote" commit --quiet -m fixture
  revision=$(git -C "$remote" rev-parse HEAD)

  cp -- "$TEST_RUN_SH" "${root}/run.sh"
  chmod 0755 -- "${root}/run.sh"
  sed -i -E "s|^readonly REPO_URL=.*|readonly REPO_URL=\"${remote}\"|" "${root}/run.sh"
  current_yq_tag=$(yq --version | sed -nE 's/.*version (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  [[ "$current_yq_tag" =~ ^v4\.[0-9]+\.[0-9]+$ ]]
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "https://github.com/mikefarah/yq/releases/tag/%s" "${YQ_TEST_TAG:?}"' >"${root}/bin/curl"
  chmod 0755 -- "${root}/bin/curl"

  (
    umask 022
    YQ_TEST_TAG="$current_yq_tag" PATH="${root}/bin:${PATH}" \
      "${root}/run.sh" Project --skip-permissions
  )

  [[ -f "${project}/app.env" && -f "${project}/.env" ]]
  [[ "$(<"${project}/.run.conf/.templates.lock")" == "$revision" ]]
  [[ "$(stat -Lc '%a' -- "${project}/.run.conf")" == 700 ]]
  [[ "$(stat -Lc '%a' -- "${project}/.run.conf/logs")" == 700 ]]
  [[ "$(stat -Lc '%a' -- "${project}/.run.conf/.templates.lock")" == 600 ]]
  [[ "$(stat -Lc '%a' -- "${project}/scripts")" == 755 ]]
  [[ "$(stat -Lc '%a' -- "${project}/dockerfiles")" == 755 ]]
  [[ "$(stat -Lc '%a' -- "${project}/scripts/helper.sh")" == 755 ]]
  [[ "$(stat -Lc '%a' -- "${project}/scripts/backup.cron")" == 644 ]]
  [[ "$(stat -Lc '%a' -- "${project}/dockerfiles/readable-entrypoint.sh")" == 644 ]]
  [[ "$(stat -Lc '%a' -- "${project}/dockerfiles/executable-helper.sh")" == 755 ]]
  deployed_mode=$(stat -Lc '%a' -- "${project}/dockerfiles/readable-entrypoint.sh")
  (( (8#$deployed_mode & 8#004) == 8#004 ))
  image_copy="${root}/image-entrypoint.sh"
  cp --preserve=mode -- "${project}/dockerfiles/readable-entrypoint.sh" "$image_copy"
  ( umask 022; chmod +x -- "$image_copy" )
  [[ "$(stat -Lc '%a' -- "$image_copy")" == 755 ]]
  while IFS= read -r log_file; do
    [[ "$(stat -Lc '%a' -- "$log_file")" == 600 ]]
  done < <(find -P "${project}/.run.conf/logs" -maxdepth 1 -type f -name '*.log' -print)
  yq -e '.services | (has("app") and has("example") and (has("stale_service") | not))' \
    "${project}/docker-compose.main.yaml" >/dev/null
  [[ -z "$(find "${project}/.run.conf" -mindepth 1 -maxdepth 1 -type d -name '.transaction.*' -print -quit)" ]]
}

expect_success nested-local-script-directory-modes test_nested_local_script_directory_modes
expect_success force-drops-stale-keys test_force_drops_stale_keys
expect_success initial-legacy-env-secret-transaction test_initial_legacy_env_and_secret_transaction
expect_success invalid-yaml-nonzero-atomic test_invalid_yaml_is_nonzero_and_atomic
expect_success late-compose-failure-atomic test_late_compose_failure_is_atomic
expect_success late-permission-failure-atomic test_late_permission_failure_is_atomic
expect_success publish-failure-rolls-back test_publish_failure_rolls_back
expect_success lock-failure-rolls-back test_lock_failure_rolls_back
expect_success signal-interrupt-rolls-back test_signal_interrupt_rolls_back
expect_success exclusive-project-lock test_exclusive_project_lock
expect_success dry-run-lock-is-read-only test_dry_run_lock_is_read_only
expect_success mutating-modes-stop-at-lock test_mutating_modes_stop_at_lock
expect_success top-level-temp-replacement-preserved test_top_level_temp_replacement_is_preserved
expect_success full-initial-entrypoint test_full_initial_entrypoint

printf '\nResult: %d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf 'Evidence retained for failed cases: %s\n' "$TEST_ROOT"
  KEEP_TEST_OUTPUT=true
  exit 1
fi
