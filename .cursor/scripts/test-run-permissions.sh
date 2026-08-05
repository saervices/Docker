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
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-permissions.XXXXXX")"
readonly TEST_UID="$(id -u)"
readonly TEST_GID="$(id -g)"

PASS=0
FAIL=0

# Loæd functions without executing run.sh's finæl mæin cæll.
# shellcheck disable=SC1090
source <(sed '$d' "$TEST_RUN_SH")

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes test fixtures unless evidence retention is explicitly requested.
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
#   Runs one cæse in æ strict subshell ænd records its result.
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
# FUNCTION: reset_globals
#   Resets run.sh stæte for one isolæted fixture.
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
reset_globals() {
  TARGET_DIR="$1"
  FORCE=false
  INITIAL_RUN=false
  DRY_RUN=false
  DEBUG=false
  LOGFILE=""
  CHMOD_NO_DEREFERENCE_SUPPORTED=""
  PERMISSION_ENV_FILE=""
  PERMISSION_CREATED_IDENTITIES=()
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_fake_docker
#   Instælls æ deterministic Docker CLI fixture for Compose writer tests.
#   Ærguments:
#     $1 - bin directory
#ææææææææææææææææææææææææææææææææææ
install_fake_docker() {
  local bin="$1"
  mkdir -p "$bin"
  printf '%s\n' \
    '#!/bin/sh' \
    'case "${1:-}" in' \
    '  compose)' \
    '    [ "${DOCKER_COMPOSE_FAIL:-false}" = true ] && exit 70' \
    '    printf '\''%s\n'\'' '\''{"name":"permissiontest","services":{}}'\''' \
    '    ;;' \
    '  ps)' \
    '    [ "${DOCKER_PS_FAIL:-false}" = true ] && exit 71' \
    '    if [ "${DOCKER_RUNNING:-false}" = true ]; then printf '\''%s\n'\'' running-id; fi' \
    '    ;;' \
    '  *) exit 72 ;;' \
    'esac' >"${bin}/docker"
  chmod 0755 "${bin}/docker"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REGRESSION CÆSES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

test_id_boundaries() {
  validate_permission_id 0 UID &&
    validate_permission_id 4294967294 UID &&
    ! validate_permission_id '' UID &&
    ! validate_permission_id +1 UID &&
    ! validate_permission_id root UID &&
    ! validate_permission_id 4294967295 UID &&
    ! validate_permission_id 00000000000 UID
}

test_basic_modes_and_nodes() {
  local root="${TEST_ROOT}/basic"
  mkdir -p "$root/data/sub" "$root/outside"
  printf normal >"$root/data/sub/normal"
  printf executable >"$root/data/sub/executable"
  chmod 0644 "$root/data/sub/normal"
  chmod 0711 "$root/data/sub/executable"
  printf sentinel >"$root/outside/sentinel"
  chmod 0600 "$root/outside/sentinel"
  ln -s ../../outside/sentinel "$root/data/sub/link"
  mkfifo "$root/data/sub/fifo"
  chmod 0620 "$root/data/sub/fifo"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"

  reset_globals "$root"
  FORCE=true
  apply_all_permissions "$root/env"

  [[ "$(stat -c %a "$root/data")" == 770 ]]
  [[ "$(stat -c %a "$root/data/sub")" == 770 ]]
  [[ "$(stat -c %a "$root/data/sub/normal")" == 660 ]]
  [[ "$(stat -c %a "$root/data/sub/executable")" == 770 ]]
  [[ "$(stat -c %a "$root/outside/sentinel")" == 600 ]]
  [[ "$(stat -c %a "$root/data/sub/fifo")" == 620 ]]
  [[ -L "$root/data/sub/link" ]]
}

test_global_preflight_no_partial_mutation() {
  local root="${TEST_ROOT}/preflight"
  mkdir -p "$root/early"
  printf keep >"$root/early/file"
  chmod 0700 "$root/early"
  chmod 0600 "$root/early/file"
  printf 'A_DIRECTORIES=early\nA_UID=%s\nA_GID=%s\nB_DIRECTORIES=../escape\nB_UID=%s\nB_GID=%s\n' \
    "$TEST_UID" "$TEST_GID" "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  ! apply_all_permissions "$root/env" &&
    [[ "$(stat -c %a "$root/early")" == 700 ]] &&
    [[ "$(stat -c %a "$root/early/file")" == 600 ]]
}

test_conflicting_overlap() {
  local root="${TEST_ROOT}/conflict"
  mkdir -p "$root/data/sub"
  printf 'A_DIRECTORIES=data\nA_UID=%s\nA_GID=%s\nB_DIRECTORIES=data/sub\nB_UID=%s\nB_GID=65534\n' \
    "$TEST_UID" "$TEST_GID" "$TEST_UID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  ! apply_all_permissions "$root/env"
}

test_same_owner_overlap() {
  local root="${TEST_ROOT}/same-owner"
  mkdir -p "$root/data/sub"
  printf file >"$root/data/sub/file"
  printf 'A_DIRECTORIES=data\nA_UID=%s\nA_GID=%s\nB_DIRECTORIES=data/sub\nB_UID=%s\nB_GID=%s\n' \
    "$TEST_UID" "$TEST_GID" "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  apply_all_permissions "$root/env" && [[ "$(stat -c %a "$root/data/sub/file")" == 660 ]]
}

test_duplicate_key() {
  local root="${TEST_ROOT}/duplicate"
  mkdir -p "$root/a" "$root/b"
  printf 'APP_DIRECTORIES=a\nAPP_UID=%s\nAPP_GID=%s\nAPP_DIRECTORIES=b\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  ! apply_all_permissions "$root/env"
}

test_nonforce_existing_and_missing() {
  local root="${TEST_ROOT}/nonforce"
  mkdir -p "$root/existing"
  printf keep >"$root/existing/file"
  chmod 0700 "$root/existing" "$root/existing/file"
  printf 'APP_DIRECTORIES=existing,missing/sub\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  apply_all_permissions "$root/env" &&
    [[ "$(stat -c %a "$root/existing")" == 700 ]] &&
    [[ "$(stat -c %a "$root/existing/file")" == 700 ]] &&
    [[ "$(stat -c %a "$root/missing")" == 770 ]] &&
    [[ "$(stat -c %a "$root/missing/sub")" == 770 ]] &&
    [[ "$(stat -c %u:%g "$root/missing")" == "$TEST_UID:$TEST_GID" ]] &&
    [[ "$(stat -c %u:%g "$root/missing/sub")" == "$TEST_UID:$TEST_GID" ]]
}

test_new_shared_parent_conflict() {
  local root="${TEST_ROOT}/new-parent-conflict"
  mkdir -p "$root"
  printf 'A_DIRECTORIES=shared/a\nA_UID=%s\nA_GID=%s\nB_DIRECTORIES=shared/b\nB_UID=%s\nB_GID=65534\n' \
    "$TEST_UID" "$TEST_GID" "$TEST_UID" >"$root/env"
  reset_globals "$root"
  ! apply_all_permissions "$root/env" && [[ ! -e "$root/shared" ]]
}

test_dry_run() {
  local root="${TEST_ROOT}/dry-run"
  mkdir -p "$root"
  printf 'APP_DIRECTORIES=missing/sub\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  DRY_RUN=true
  FORCE=true
  apply_all_permissions "$root/env" && [[ ! -e "$root/missing" ]]
}

test_future_merged_env_dry_run() {
  local root="${TEST_ROOT}/dry-preview"
  mkdir -p "$root/project" "$root/templates/example" "$root/tmp"
  printf 'APP_DIRECTORIES=safe\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/project/app.env"
  printf 'BAD_DIRECTORIES=../escape\nBAD_UID=%s\nBAD_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/templates/example/.env"
  reset_globals "$root/project"
  _TMPDIR="$root/tmp"
  DRY_RUN=true
  FORCE=true
  prepare_dry_run_permission_env "$root/project/app.env" "$root/project/.env" "$root/templates" example
  [[ "$PERMISSION_ENV_FILE" == "$root/tmp/"* ]]
  rg -q '^BAD_DIRECTORIES=\.\./escape$' "$PERMISSION_ENV_FILE"
  ! apply_all_permissions "$PERMISSION_ENV_FILE"
  [[ ! -e "$root/project/safe" && ! -e "$root/project/.env" ]]
}

test_empty_directories_no_ids() {
  local root="${TEST_ROOT}/empty"
  mkdir -p "$root"
  printf 'APP_DIRECTORIES=\n' >"$root/env"
  reset_globals "$root"
  apply_all_permissions "$root/env"
}

test_symlink_and_component_rejections() {
  local root="${TEST_ROOT}/links"
  mkdir -p "$root/real/sub"
  ln -s real "$root/link"
  printf file >"$root/file"
  reset_globals "$root"
  FORCE=true
  ! set_permissions link "$TEST_UID" "$TEST_GID"
  ! set_permissions link/sub "$TEST_UID" "$TEST_GID"
  ! set_permissions file/sub "$TEST_UID" "$TEST_GID"
}

test_target_dir_symlink() {
  local real_root="${TEST_ROOT}/target-real"
  local parent="${TEST_ROOT}/target-parent"
  mkdir -p "$real_root" "$parent"
  ln -s "$real_root" "$parent/project"
  reset_globals "$parent/project"
  FORCE=true
  ! set_permissions data "$TEST_UID" "$TEST_GID"
}

test_invalid_paths() {
  local root="${TEST_ROOT}/invalid-paths"
  local value
  mkdir -p "$root"
  reset_globals "$root"
  FORCE=true
  for value in ',a' 'a,' 'a,,b' ' ' '/abs' 'a/' 'a//b' '.' '..' 'a/./b' 'a/../b' 'a\b' '.git' '.git/objects'; do
    if set_permissions "$value" "$TEST_UID" "$TEST_GID" >/dev/null 2>&1; then
      return 1
    fi
  done
}

test_device_preflight() {
  ! validate_managed_directory_tree /dev/null
}

test_find_failure() {
  local root="${TEST_ROOT}/find-failure"
  local bin="$root/bin"
  mkdir -p "$root/data" "$bin"
  printf '#!/bin/sh\nexit 73\n' >"$bin/find"
  chmod 0755 "$bin/find"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  PATH="$bin:$PATH" apply_all_permissions "$root/env" >/dev/null 2>&1 && return 1
  [[ "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_chown_failure() {
  local root="${TEST_ROOT}/chown-failure"
  local bin="$root/bin"
  mkdir -p "$root/data" "$bin"
  printf '#!/bin/sh\nexit 74\n' >"$bin/chown"
  chmod 0755 "$bin/chown"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  PATH="$bin:$PATH" apply_all_permissions "$root/env" >/dev/null 2>&1 && return 1
  [[ "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_chmod_failure() {
  local root="${TEST_ROOT}/chmod-failure"
  local bin="$root/bin"
  mkdir -p "$root/data" "$bin"
  printf '#!/bin/sh\nexit 75\n' >"$bin/chmod"
  chmod 0755 "$bin/chmod"
  printf keep >"$root/data/file"
  /usr/bin/chmod 0600 "$root/data/file"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  PATH="$bin:$PATH" apply_all_permissions "$root/env" >/dev/null 2>&1 && return 1
  [[ "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_mkdir_failure() {
  local root="${TEST_ROOT}/mkdir-failure"
  local bin="$root/bin"
  mkdir -p "$root" "$bin"
  printf '#!/bin/sh\nexit 76\n' >"$bin/mkdir"
  chmod 0755 "$bin/mkdir"
  reset_globals "$root"
  PATH="$bin:$PATH" set_permissions missing/sub "$TEST_UID" "$TEST_GID" >/dev/null 2>&1 && return 1
  [[ ! -e "$root/missing" ]]
}

test_chmod_fallback() {
  local root="${TEST_ROOT}/fallback"
  local bin="$root/bin"
  local output
  mkdir -p "$root/data" "$bin"
  printf '#!/bin/sh\nif [ "${1:-}" = --help ]; then echo "usage: chmod"; exit 0; fi\nexec /usr/bin/chmod "$@"\n' >"$bin/chmod"
  chmod 0755 "$bin/chmod"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  output=$(PATH="$bin:$PATH" apply_all_permissions "$root/env" 2>&1) &&
    [[ "$output" == *"Stop writers"* ]] &&
    [[ "$(stat -c %a "$root/data/file")" == 660 ]]
}

test_running_compose_fails_before_mutation() {
  local root="${TEST_ROOT}/running-compose"
  local bin="$root/bin"
  mkdir -p "$root/data"
  install_fake_docker "$bin"
  printf keep >"$root/data/file"
  chmod 0700 "$root/data"
  chmod 0600 "$root/data/file"
  printf 'services: {}\n' >"$root/docker-compose.main.yaml"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  DOCKER_RUNNING=true PATH="$bin:$PATH" apply_all_permissions "$root/env" && return 1
  [[ "$(stat -c %a "$root/data")" == 700 && "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_stopped_compose_allows_mutation() {
  local root="${TEST_ROOT}/stopped-compose"
  local bin="$root/bin"
  mkdir -p "$root/data"
  install_fake_docker "$bin"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf 'services: {}\n' >"$root/docker-compose.main.yaml"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  PATH="$bin:$PATH" apply_all_permissions "$root/env"
  [[ "$(stat -c %a "$root/data/file")" == 660 ]]
}

test_compose_inspection_failure() {
  local root="${TEST_ROOT}/compose-inspection"
  local bin="$root/bin"
  mkdir -p "$root/data"
  install_fake_docker "$bin"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf 'services: {}\n' >"$root/docker-compose.main.yaml"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  DOCKER_COMPOSE_FAIL=true PATH="$bin:$PATH" apply_all_permissions "$root/env" && return 1
  [[ "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_same_device_nested_mount_metadata() {
  local root="${TEST_ROOT}/nested-mount"
  local bin="$root/bin"
  mkdir -p "$root/data/bind" "$bin"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf '\''{"filesystems":[{"target":"%s"}]}\n'\'' "$FAKE_MOUNT_TARGET"' >"$bin/findmnt"
  chmod 0755 "$bin/findmnt"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  [[ "$(stat -c %d "$root/data")" == "$(stat -c %d "$root/data/bind")" ]]
  reset_globals "$root"
  FORCE=true
  FAKE_MOUNT_TARGET="$root/data/bind" PATH="$bin:$PATH" apply_all_permissions "$root/env" && return 1
  [[ "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_real_same_device_bind_mount_if_available() {
  local root="${TEST_ROOT}/real-bind-mount"

  if ! command -v unshare &>/dev/null || ! command -v mount &>/dev/null || ! \
     unshare --user --map-root-user --mount true 2>/dev/null; then
    printf 'SKIP reæl bind-mount probe: unprivileged mount næmespæce unævæilæble\n'
    return 0
  fi

  mkdir -p "$root"
  unshare --user --map-root-user --mount bash -c '
    set -euo pipefail
    source <(sed "\$d" "$1")
    fixture="$2"
    mkdir -p "$fixture/source" "$fixture/managed/bind"
    printf keep >"$fixture/managed/file"
    chmod 0600 "$fixture/managed/file"
    mount --bind "$fixture/source" "$fixture/managed/bind"
    trap '\''umount "$fixture/managed/bind" 2>/dev/null || true'\'' EXIT
    [[ "$(stat -c %d "$fixture/managed")" == "$(stat -c %d "$fixture/managed/bind")" ]]
    printf "APP_DIRECTORIES=managed\nAPP_UID=%s\nAPP_GID=%s\n" "$(id -u)" "$(id -g)" >"$fixture/env"
    TARGET_DIR="$fixture"
    FORCE=true
    INITIAL_RUN=false
    DRY_RUN=false
    DEBUG=false
    LOGFILE=""
    CHMOD_NO_DEREFERENCE_SUPPORTED=""
    PERMISSION_CREATED_IDENTITIES=()
    apply_all_permissions "$fixture/env" && exit 1
    [[ "$(stat -c %a "$fixture/managed/file")" == 600 ]]
  ' bash "$TEST_RUN_SH" "$root"
}

test_managed_root_mount_allowed() {
  local root="${TEST_ROOT}/root-mount"
  local bin="$root/bin"
  mkdir -p "$root/data" "$bin"
  printf keep >"$root/data/file"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf '\''{"filesystems":[{"target":"%s"}]}\n'\'' "$FAKE_MOUNT_TARGET"' >"$bin/findmnt"
  chmod 0755 "$bin/findmnt"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  FAKE_MOUNT_TARGET="$root/data" PATH="$bin:$PATH" apply_all_permissions "$root/env"
  [[ "$(stat -c %a "$root/data/file")" == 660 ]]
}

test_findmnt_failure() {
  local root="${TEST_ROOT}/findmnt-failure"
  local bin="$root/bin"
  mkdir -p "$root/data" "$bin"
  printf '#!/bin/sh\nexit 77\n' >"$bin/findmnt"
  chmod 0755 "$bin/findmnt"
  printf keep >"$root/data/file"
  chmod 0600 "$root/data/file"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  PATH="$bin:$PATH" apply_all_permissions "$root/env" && return 1
  [[ "$(stat -c %a "$root/data/file")" == 600 ]]
}

test_intermediate_symlink_race_blocked() {
  local root="${TEST_ROOT}/toctou"
  local bin="$root/bin"
  mkdir -p "$root/managed/inner" "$root/outside/inner" "$bin"
  printf original >"$root/managed/inner/original"
  printf protected >"$root/outside/inner/sentinel"
  chmod 0700 "$root/outside/inner" "$root/outside/inner/sentinel"
  printf '%s\n' \
    '#!/bin/sh' \
    'trigger=false' \
    'for arg in "$@"; do [ "$arg" = chown ] && trigger=true; done' \
    '/usr/bin/find "$@"' \
    'status=$?' \
    'if [ "$trigger" = true ] && [ ! -e "$SWAP_MARKER" ]; then' \
    '  : >"$SWAP_MARKER"' \
    '  /usr/bin/mv -- "$SWAP_PARENT" "${SWAP_PARENT}.old"' \
    '  /usr/bin/ln -s -- "$SWAP_OUTSIDE" "$SWAP_PARENT"' \
    'fi' \
    'exit "$status"' >"$bin/find"
  chmod 0755 "$bin/find"
  printf 'APP_DIRECTORIES=managed/inner\nAPP_UID=%s\nAPP_GID=%s\n' "$TEST_UID" "$TEST_GID" >"$root/env"
  reset_globals "$root"
  FORCE=true
  SWAP_MARKER="$root/swapped" SWAP_PARENT="$root/managed" SWAP_OUTSIDE="$root/outside" \
    PATH="$bin:$PATH" apply_all_permissions "$root/env" && return 1
  [[ -L "$root/managed" ]]
  [[ "$(stat -c %a "$root/outside/inner/sentinel")" == 700 ]]
}

test_secret_directory_symlink_rejected() {
  local root="${TEST_ROOT}/secret-dir-link"
  mkdir -p "$root/outside"
  printf 'x-secrets-use-app-gid: true\n' >"$root/docker-compose.app.yaml"
  printf 'APP_GID=%s\n' "$TEST_GID" >"$root/.env"
  printf protected >"$root/outside/APP_PASSWORD"
  chmod 0600 "$root/outside/APP_PASSWORD"
  ln -s outside "$root/secrets"
  reset_globals "$root"
  ! apply_app_gid_secret_permissions "$root/.env" "$root/docker-compose.app.yaml" "$root/secrets"
  [[ "$(stat -c %a "$root/outside/APP_PASSWORD")" == 600 ]]
}

test_secret_file_symlink_rejected() {
  local root="${TEST_ROOT}/secret-file-link"
  mkdir -p "$root/secrets" "$root/outside"
  printf 'x-secrets-use-app-gid: true\n' >"$root/docker-compose.app.yaml"
  printf 'APP_GID=%s\n' "$TEST_GID" >"$root/.env"
  printf protected >"$root/outside/value"
  chmod 0600 "$root/outside/value"
  ln -s ../outside/value "$root/secrets/APP_PASSWORD"
  reset_globals "$root"
  ! apply_app_gid_secret_permissions "$root/.env" "$root/docker-compose.app.yaml" "$root/secrets"
  [[ "$(stat -c %a "$root/outside/value")" == 600 ]]
}

test_secret_file_swap_race_blocked() {
  local root="${TEST_ROOT}/secret-file-race"
  local bin="$root/bin"
  mkdir -p "$root/secrets" "$root/outside" "$bin"
  printf 'x-secrets-use-app-gid: true\n' >"$root/docker-compose.app.yaml"
  printf 'APP_GID=%s\n' "$TEST_GID" >"$root/.env"
  printf secret >"$root/secrets/APP_PASSWORD"
  printf protected >"$root/outside/value"
  chmod 0600 "$root/secrets/APP_PASSWORD" "$root/outside/value"
  printf '%s\n' \
    '#!/bin/sh' \
    'if [ "${1:-}" = --help ]; then exec /usr/bin/chmod --help; fi' \
    '/usr/bin/chmod "$@"' \
    'status=$?' \
    'if [ "$status" -eq 0 ] && [ -f ./APP_PASSWORD ] && [ ! -e "$SWAP_MARKER" ]; then' \
    '  : >"$SWAP_MARKER"' \
    '  /usr/bin/mv -- ./APP_PASSWORD ./APP_PASSWORD.old' \
    '  /usr/bin/ln -s -- "$SWAP_OUTSIDE" ./APP_PASSWORD' \
    'fi' \
    'exit "$status"' >"$bin/chmod"
  chmod 0755 "$bin/chmod"
  reset_globals "$root"
  SWAP_MARKER="$root/swapped" SWAP_OUTSIDE="$root/outside/value" \
    PATH="$bin:$PATH" apply_app_gid_secret_permissions "$root/.env" "$root/docker-compose.app.yaml" "$root/secrets" && return 1
  [[ -L "$root/secrets/APP_PASSWORD" ]]
  [[ "$(stat -c %a "$root/outside/value")" == 600 ]]
}

test_main_lock_not_published() {
  local root="${TEST_ROOT}/main-lock"
  local child="$root/child.sh"
  mkdir -p "$root/project/data"
  printf 'APP_DIRECTORIES=data\nAPP_UID=%s\nAPP_GID=%s\nBAD_DIRECTORIES=../escape\nBAD_UID=%s\nBAD_GID=%s\n' \
    "$TEST_UID" "$TEST_GID" "$TEST_UID" "$TEST_GID" >"$root/project/.env"
  sed '$d' "$TEST_RUN_SH" >"$child"
  printf '%s\n' \
    'parse_args() { TARGET_DIR="$PROJECT"; INITIAL_RUN=false; DEBUG=false; DRY_RUN=false; FORCE=true; UPDATE=false; DELETE_VOLUMES=false; SKIP_PERMISSIONS=false; GENERATE_PASSWORD=false; LOGFILE=""; PERMISSION_ENV_FILE=""; }' \
    'check_dependencies() { :; }' \
    'clone_sparse_checkout() { TEMPLATE_LOCK_WRITE_PENDING=true; TEMPLATE_LOCKFILE="$TARGET_DIR/lock"; TEMPLATE_REVISION=0123456789012345678901234567890123456789; }' \
    'copy_required_services() { :; }' \
    'make_scripts_executable() { :; }' \
    'apply_app_gid_secret_permissions() { printf secret-step >"$TARGET_DIR/secret-step"; }' \
    'commit_template_lockfile() { printf lock >"$TARGET_DIR/lock"; }' \
    'main project' >>"$child"
  chmod 0755 "$child"
  if PROJECT="$root/project" bash "$child" >"$root/main.out" 2>&1; then
    return 1
  fi
  [[ ! -e "$root/project/secret-step" && ! -e "$root/project/lock" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXECUTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
expect_success id-boundaries test_id_boundaries
expect_success basic-modes-and-nodes test_basic_modes_and_nodes
expect_success global-preflight-no-partial-mutation test_global_preflight_no_partial_mutation
expect_success conflicting-overlap test_conflicting_overlap
expect_success same-owner-overlap test_same_owner_overlap
expect_success duplicate-key test_duplicate_key
expect_success nonforce-existing-and-missing test_nonforce_existing_and_missing
expect_success new-shared-parent-conflict test_new_shared_parent_conflict
expect_success dry-run test_dry_run
expect_success future-merged-env-dry-run test_future_merged_env_dry_run
expect_success empty-directories-no-ids test_empty_directories_no_ids
expect_success symlink-and-component-rejections test_symlink_and_component_rejections
expect_success target-dir-symlink test_target_dir_symlink
expect_success invalid-paths test_invalid_paths
expect_success device-preflight test_device_preflight
expect_success find-failure test_find_failure
expect_success chown-failure test_chown_failure
expect_success chmod-failure test_chmod_failure
expect_success mkdir-failure test_mkdir_failure
expect_success chmod-fallback test_chmod_fallback
expect_success running-compose-fails-before-mutation test_running_compose_fails_before_mutation
expect_success stopped-compose-allows-mutation test_stopped_compose_allows_mutation
expect_success compose-inspection-failure test_compose_inspection_failure
expect_success same-device-nested-mount-metadata test_same_device_nested_mount_metadata
expect_success real-same-device-bind-mount-if-available test_real_same_device_bind_mount_if_available
expect_success managed-root-mount-allowed test_managed_root_mount_allowed
expect_success findmnt-failure test_findmnt_failure
expect_success intermediate-symlink-race-blocked test_intermediate_symlink_race_blocked
expect_success secret-directory-symlink-rejected test_secret_directory_symlink_rejected
expect_success secret-file-symlink-rejected test_secret_file_symlink_rejected
expect_success secret-file-swap-race-blocked test_secret_file_swap_race_blocked
expect_success main-lock-not-published test_main_lock_not_published

printf 'RESULT pass=%s fail=%s evidence=%s\n' "$PASS" "$FAIL" "$TEST_ROOT"
(( FAIL == 0 ))
