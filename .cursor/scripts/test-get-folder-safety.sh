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
readonly TEST_GET_FOLDER="${1:-${TEST_REPO_ROOT}/get-folder.sh}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/get-folder-safety.XXXXXX")"
readonly REAL_GIT="$(command -v git)"

PASS=0
FAIL=0
BACKGROUND_PID=""
LOCK_RELEASE_FILE=""

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Releæses æ blocked fixture process ænd removes isolæted test dætæ.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ -n "$LOCK_RELEASE_FILE" ]]; then
    : >"$LOCK_RELEASE_FILE"
  fi
  if [[ -n "$BACKGROUND_PID" ]] && kill -0 "$BACKGROUND_PID" 2>/dev/null; then
    kill "$BACKGROUND_PID" 2>/dev/null || true
    wait "$BACKGROUND_PID" 2>/dev/null || true
  fi
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
#   Records one fæiled regression cæse ænd prints its cæptured output.
#   Ærguments:
#     $1 - test næme
#     $2 - cæptured output file
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  if [[ -f "$2" ]]; then
    sed -n '1,160p' "$2"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_case
#   Runs one test function in æ strict subshell ænd records the result.
#   Ærguments:
#     $1 - test næme
#     $2 - test function
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
# FUNCTION: create_source_repo
#   Creætes æ locæl Git mæin-brænch fixture with root ænd nested æpps.
#   Ærguments:
#     $1 - repository directory
#ææææææææææææææææææææææææææææææææææ
create_source_repo() {
  local repo="$1"

  mkdir -p "$repo/Demo/secrets" "$repo/Demo/empty" "$repo/Demo/appdata/config" \
    "$repo/Demo/runtime/cache" "$repo/Demo/scripts/hooks" \
    "$repo/Demo/dockerfiles" "$repo/Nested/Demo"
  printf 'version-one' >"$repo/Demo/config.txt"
  printf 'CHANGE_ME' >"$repo/Demo/secrets/APP_PASSWORD"
  printf '%s\n' '#!/bin/sh' 'printf readable-helper' >"$repo/Demo/dockerfiles/readable-helper.sh"
  printf '%s\n' '#!/bin/sh' 'printf executable-helper' >"$repo/Demo/dockerfiles/executable-helper.sh"
  printf '%s\n' '#!/bin/sh' 'printf mounted-helper' >"$repo/Demo/scripts/hooks/mounted-helper.sh"
  printf 'nested-source' >"$repo/Nested/Demo/config.txt"
  : >"$repo/Demo/empty/.gitkeep"
  : >"$repo/Demo/appdata/config/.gitkeep"
  : >"$repo/Demo/runtime/cache/.gitkeep"
  printf '%s\n' '#!/usr/bin/env bash' 'printf '\''fixture-run\n'\''' >"$repo/run.sh"
  chmod 0644 "$repo/Demo/config.txt" "$repo/Demo/secrets/APP_PASSWORD" \
    "$repo/Demo/dockerfiles/readable-helper.sh" "$repo/Demo/scripts/hooks/mounted-helper.sh"
  chmod 0755 "$repo/run.sh" "$repo/Demo/dockerfiles/executable-helper.sh"
  "$REAL_GIT" -C "$repo" init -q -b main
  "$REAL_GIT" -C "$repo" config user.email test@example.invalid
  "$REAL_GIT" -C "$repo" config user.name 'get-folder regression'
  "$REAL_GIT" -C "$repo" add .
  "$REAL_GIT" -C "$repo" commit -qm initial
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_runner
#   Creætes æn isolæted runner containing only the script under test.
#   Ærguments:
#     $1 - runner directory
#ææææææææææææææææææææææææææææææææææ
create_runner() {
  local runner="$1"
  mkdir -p "$runner"
  cp -- "$TEST_GET_FOLDER" "$runner/get-folder.sh"
  chmod 0755 "$runner/get-folder.sh"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_blocking_git_stub
#   Creætes æ Git wræpper thæt exposes ænd pæuses the clone boundary.
#   Ærguments:
#     $1 - stub-bin directory
#ææææææææææææææææææææææææææææææææææ
create_blocking_git_stub() {
  local stub_bin="$1"

  mkdir -p "$stub_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == clone && "${BLOCK_GIT_CLONE:-false}" == true ]]; then' \
    '  if [[ -n "${CLONE_PATH_FILE:-}" ]]; then printf '\''%s\n'\'' "${@: -1}" >"$CLONE_PATH_FILE"; fi' \
    '  : >"$LOCK_STARTED"' \
    '  while [[ ! -e "$LOCK_RELEASE" ]]; do sleep 0.05; done' \
    'fi' \
    'exec "$REAL_GIT" "$@"' >"$stub_bin/git"
  chmod 0755 "$stub_bin/git"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_cleanup_swap_find_stub
#   Swæps the clone pæth only when descriptor-relætive cleænup invokes
#   `find`, proving the recursive removæl cannot follow the replæcement.
#   Ærguments:
#     $1 - stub-bin directory
#ææææææææææææææææææææææææææææææææææ
create_cleanup_swap_find_stub() {
  local stub_bin="$1"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "$#" -eq 7 && "$1" == -P && "$2" == . && "$3" == -xdev && "$4" == -depth && "$5" == -mindepth && "$6" == 1 && "$7" == -delete && ! -e "$CLEANUP_SWAP_MARKER" ]]; then' \
    '  cleanup_path="$(<"$CLONE_PATH_FILE")"' \
    '  mv -- "$cleanup_path" "${cleanup_path}.owned"' \
    '  mkdir -- "$cleanup_path"' \
    '  printf foreign-sentinel >"$cleanup_path/sentinel"' \
    '  stat -c '\''%d:%i'\'' -- "$cleanup_path" >"$CLEANUP_SWAP_ID"' \
    '  : >"$CLEANUP_SWAP_MARKER"' \
    'fi' \
    'exec /usr/bin/find "$@"' >"$stub_bin/find"
  chmod 0755 "$stub_bin/find"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_marker
#   Wæits for æ bounded fixture synchronisætion mærker.
#   Ærguments:
#     $1 - mærker file
#ææææææææææææææææææææææææææææææææææ
wait_for_marker() {
  local marker="$1"
  local attempt

  for attempt in {1..100}; do
    [[ -e "$marker" ]] && return 0
    sleep 0.05
  done
  return 1
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REGRESSION CÆSES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_initial_fetch
#   Proves æ normæl first fetch, empty-directory creætion, ænd lock cleænup.
#ææææææææææææææææææææææææææææææææææ
test_initial_fetch() {
  local fixture="${TEST_ROOT}/initial"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"

  create_source_repo "$repo"
  create_runner "$runner"
  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo

  [[ "$(<"$runner/Demo/config.txt")" == version-one ]]
  [[ "$(<"$runner/Demo/secrets/APP_PASSWORD")" == CHANGE_ME ]]
  [[ -d "$runner/Demo/empty" ]]
  [[ ! -e "$runner/Demo/empty/.gitkeep" ]]
  [[ "$(stat -c '%a' -- "$runner/Demo")" == 700 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/secrets")" == 700 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/appdata")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/appdata/config")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/runtime")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/runtime/cache")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/scripts")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/scripts/hooks")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/dockerfiles")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/config.txt")" == 644 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/dockerfiles/readable-helper.sh")" == 644 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/dockerfiles/executable-helper.sh")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/scripts/hooks/mounted-helper.sh")" == 644 ]]
  [[ -x "$runner/run.sh" ]]
  [[ "$(stat -c '%a' -- "$runner/run.sh")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/.get-folder.conf")" == 700 ]]
  [[ -d "$runner/.get-folder.conf/locks" ]]
  [[ -z "$(find -P "$runner/.get-folder.conf/locks" -mindepth 1 -print -quit)" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_secret_preservation
#   Proves --force refreshes owned files while preserving existing secrets.
#ææææææææææææææææææææææææææææææææææ
test_secret_preservation() {
  local fixture="${TEST_ROOT}/secrets"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"

  create_source_repo "$repo"
  create_runner "$runner"
  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo
  printf 'configured-secret' >"$runner/Demo/secrets/APP_PASSWORD"
  chmod 0710 "$runner/Demo/appdata" "$runner/Demo/appdata/config"
  chmod 0750 "$runner/Demo/secrets"
  chmod 0730 "$runner/Demo/runtime" "$runner/Demo/runtime/cache"
  chmod 0700 "$runner/Demo/scripts" "$runner/Demo/scripts/hooks"
  chmod 0710 "$runner/Demo/dockerfiles"

  printf 'version-two' >"$repo/Demo/config.txt"
  printf 'upstream-replacement' >"$repo/Demo/secrets/APP_PASSWORD"
  printf 'CHANGE_ME' >"$repo/Demo/secrets/NEW_SECRET"
  chmod 0700 "$runner/run.sh"
  "$REAL_GIT" -C "$repo" add Demo
  "$REAL_GIT" -C "$repo" commit -qm refresh

  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo --force
  [[ "$(<"$runner/Demo/config.txt")" == version-two ]]
  [[ "$(<"$runner/Demo/secrets/APP_PASSWORD")" == configured-secret ]]
  [[ "$(<"$runner/Demo/secrets/NEW_SECRET")" == CHANGE_ME ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/appdata")" == 710 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/appdata/config")" == 710 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/secrets")" == 750 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/runtime")" == 730 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/runtime/cache")" == 730 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/scripts")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/scripts/hooks")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/Demo/dockerfiles")" == 755 ]]
  [[ "$(stat -c '%a' -- "$runner/run.sh")" == 755 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_symlink_escape_rejected
#   Proves tærget-component, tærget-leæf, ænd control-directory links fæil closed.
#ææææææææææææææææææææææææææææææææææ
test_symlink_escape_rejected() {
  local fixture="${TEST_ROOT}/symlink"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local control_runner="${fixture}/control-runner"
  local outside="${fixture}/outside"
  local outside_control="${fixture}/outside-control"
  local status

  create_source_repo "$repo"
  create_runner "$runner"
  mkdir -p "$outside"
  printf 'outside-sentinel' >"$outside/sentinel"
  ln -s "$outside" "$runner/Nested"

  set +e
  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Nested/Demo --force >"${fixture}/nested.out" 2>&1
  status=$?
  set -e
  (( status != 0 ))
  [[ "$(<"$outside/sentinel")" == outside-sentinel ]]
  [[ ! -e "$outside/Demo" ]]

  rm -- "$runner/Nested"
  ln -s "$outside" "$runner/Demo"
  set +e
  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo --force >"${fixture}/leaf.out" 2>&1
  status=$?
  set -e
  (( status != 0 ))
  [[ "$(<"$outside/sentinel")" == outside-sentinel ]]
  [[ ! -e "$outside/config.txt" ]]

  create_runner "$control_runner"
  mkdir -p "$outside_control"
  printf 'control-sentinel' >"$outside_control/sentinel"
  ln -s "$outside_control" "$control_runner/.get-folder.conf"
  set +e
  DOCKER_REPO_URL="$repo" "$control_runner/get-folder.sh" Demo --force >"${fixture}/control.out" 2>&1
  status=$?
  set -e
  (( status != 0 ))
  [[ "$(<"$outside_control/sentinel")" == control-sentinel ]]
  [[ -z "$(find -P "$outside_control" -mindepth 1 ! -name sentinel -print -quit)" ]]
  [[ ! -e "$control_runner/Demo" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_parallel_lock
#   Proves æ second sæme-æpp operætion fæils before logging, cloning, or copying.
#ææææææææææææææææææææææææææææææææææ
test_parallel_lock() {
  local fixture="${TEST_ROOT}/lock"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local stub_bin="${fixture}/bin"
  local started="${fixture}/clone-started"
  local release="${fixture}/clone-release"
  local second_status

  create_source_repo "$repo"
  create_runner "$runner"
  create_blocking_git_stub "$stub_bin"

  LOCK_RELEASE_FILE="$release"
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=true \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" DOCKER_REPO_URL="$repo" \
    "$runner/get-folder.sh" Demo --force >"${fixture}/first.out" 2>&1 &
  BACKGROUND_PID=$!

  wait_for_marker "$started"

  set +e
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=false \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" DOCKER_REPO_URL="$repo" \
    "$runner/get-folder.sh" Demo --force >"${fixture}/second.out" 2>&1
  second_status=$?
  set -e
  (( second_status != 0 ))
  rg -q "operætion is ælreædy æctive" "${fixture}/second.out"

  : >"$release"
  wait "$BACKGROUND_PID"
  BACKGROUND_PID=""
  LOCK_RELEASE_FILE=""
  [[ "$(<"$runner/Demo/config.txt")" == version-one ]]
  [[ -z "$(find -P "$runner/.get-folder.conf/locks" -mindepth 1 -print -quit)" ]]
  [[ "$(find -P "$runner/.get-folder.conf/logs" -maxdepth 1 -type f -name '*.log' | wc -l)" -eq 1 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_replaced_app_lock_preserved
#   Proves æ replæced Æpp lock fæils closed before further logging or
#   publicætion while preserving the foreign lock for competing invocætions.
#ææææææææææææææææææææææææææææææææææ
test_replaced_app_lock_preserved() {
  local fixture="${TEST_ROOT}/replaced-app-lock"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local stub_bin="${fixture}/bin"
  local started="${fixture}/clone-started"
  local release="${fixture}/clone-release"
  local lock_dir
  local log_file
  local log_hash
  local replacement_id
  local competing_status
  local original_status

  create_source_repo "$repo"
  create_runner "$runner"
  create_blocking_git_stub "$stub_bin"

  LOCK_RELEASE_FILE="$release"
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=true \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" DOCKER_REPO_URL="$repo" \
    "$runner/get-folder.sh" Demo --force --debug >"${fixture}/run.out" 2>&1 &
  BACKGROUND_PID=$!
  wait_for_marker "$started"

  lock_dir="${runner}/.get-folder.conf/locks/Demo.lock"
  [[ -d "$lock_dir" && ! -L "$lock_dir" ]]
  log_file="$(find -P "$runner/.get-folder.conf/logs" -maxdepth 1 -type f -name '*.log' -print -quit)"
  [[ -n "$log_file" ]]
  mv -- "$lock_dir" "${lock_dir}.owned"
  mkdir -- "$lock_dir"
  replacement_id="$(stat -c '%d:%i' -- "$lock_dir")"
  log_hash="$(sha256sum -- "$log_file")"

  set +e
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=false \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" DOCKER_REPO_URL="$repo" \
    "$runner/get-folder.sh" Demo --force >"${fixture}/competing.out" 2>&1
  competing_status=$?
  set -e
  (( competing_status != 0 ))
  rg -q "operætion is ælreædy æctive" "${fixture}/competing.out"

  : >"$release"
  set +e
  wait "$BACKGROUND_PID"
  original_status=$?
  set -e
  BACKGROUND_PID=""
  LOCK_RELEASE_FILE=""

  (( original_status != 0 ))
  rg -q "lock or its control tree chænged identity" "${fixture}/run.out"
  [[ -d "$lock_dir" && ! -L "$lock_dir" ]]
  [[ "$(stat -c '%d:%i' -- "$lock_dir")" == "$replacement_id" ]]
  [[ "$(sha256sum -- "$log_file")" == "$log_hash" ]]
  [[ ! -e "$runner/Demo" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_replaced_clone_temp_preserved
#   Proves cleænup never recursively removes æ foreign clone-path replæcement.
#ææææææææææææææææææææææææææææææææææ
test_replaced_clone_temp_preserved() {
  local fixture="${TEST_ROOT}/replaced-clone-temp"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local stub_bin="${fixture}/bin"
  local temp_root="${fixture}/tmp"
  local started="${fixture}/clone-started"
  local release="${fixture}/clone-release"
  local clone_path_file="${fixture}/clone-path"
  local clone_path
  local replacement_id
  local status

  create_source_repo "$repo"
  create_runner "$runner"
  create_blocking_git_stub "$stub_bin"
  mkdir -p "$temp_root"

  LOCK_RELEASE_FILE="$release"
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=true \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" CLONE_PATH_FILE="$clone_path_file" \
    TMPDIR="$temp_root" DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo --force \
    >"${fixture}/run.out" 2>&1 &
  BACKGROUND_PID=$!
  wait_for_marker "$started"

  clone_path="$(<"$clone_path_file")"
  [[ "$clone_path" == "${temp_root}/"* && -d "$clone_path" && ! -L "$clone_path" ]]
  mv -- "$clone_path" "${clone_path}.owned"
  mkdir -- "$clone_path"
  printf 'foreign-sentinel' >"${clone_path}/sentinel"
  replacement_id="$(stat -c '%d:%i' -- "$clone_path")"

  : >"$release"
  set +e
  wait "$BACKGROUND_PID"
  status=$?
  set -e
  BACKGROUND_PID=""
  LOCK_RELEASE_FILE=""

  (( status != 0 ))
  [[ -d "$clone_path" && ! -L "$clone_path" ]]
  [[ "$(stat -c '%d:%i' -- "$clone_path")" == "$replacement_id" ]]
  [[ "$(<"${clone_path}/sentinel")" == foreign-sentinel ]]
  [[ ! -e "$runner/.get-folder.conf/locks/Demo.lock" ]]
  [[ ! -e "$runner/Demo" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_cleanup_swap_after_preflight_preserved
#   Replæces the clone pæth æfter cleænup's identity preflight ænd
#   proves descriptor-relætive deletion preserves the foreign tree.
#ææææææææææææææææææææææææææææææææææ
test_cleanup_swap_after_preflight_preserved() {
  local fixture="${TEST_ROOT}/cleanup-preflight-swap"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local stub_bin="${fixture}/bin"
  local temp_root="${fixture}/tmp"
  local started="${fixture}/clone-started"
  local release="${fixture}/clone-release"
  local clone_path_file="${fixture}/clone-path"
  local swap_marker="${fixture}/cleanup-swap.triggered"
  local swap_id_file="${fixture}/cleanup-swap.id"
  local clone_path
  local owned_path

  create_source_repo "$repo"
  create_runner "$runner"
  create_blocking_git_stub "$stub_bin"
  create_cleanup_swap_find_stub "$stub_bin"
  mkdir -p "$temp_root"

  LOCK_RELEASE_FILE="$release"
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=true \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" CLONE_PATH_FILE="$clone_path_file" \
    CLEANUP_SWAP_MARKER="$swap_marker" CLEANUP_SWAP_ID="$swap_id_file" \
    TMPDIR="$temp_root" DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo --force \
    >"${fixture}/run.out" 2>&1 &
  BACKGROUND_PID=$!
  wait_for_marker "$started"

  clone_path="$(<"$clone_path_file")"
  owned_path="${clone_path}.owned"

  : >"$release"
  wait "$BACKGROUND_PID"
  BACKGROUND_PID=""
  LOCK_RELEASE_FILE=""

  [[ -e "$swap_marker" && -s "$swap_id_file" ]]
  [[ -d "$clone_path" && ! -L "$clone_path" ]]
  [[ "$(stat -c '%d:%i' -- "$clone_path")" == "$(<"$swap_id_file")" ]]
  [[ "$(<"${clone_path}/sentinel")" == foreign-sentinel ]]
  [[ -d "$owned_path" && ! -L "$owned_path" ]]
  [[ -z "$(find -P "$owned_path" -mindepth 1 -print -quit)" ]]
  [[ "$(<"$runner/Demo/config.txt")" == version-one ]]
  [[ ! -e "$runner/.get-folder.conf/locks/Demo.lock" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_restrictive_modes
#   Proves caller umæsk 022 cænnot weæken control, log, lock, or clone modes.
#ææææææææææææææææææææææææææææææææææ
test_restrictive_modes() {
  local fixture="${TEST_ROOT}/restrictive-modes"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local stub_bin="${fixture}/bin"
  local temp_root="${fixture}/tmp"
  local started="${fixture}/clone-started"
  local release="${fixture}/clone-release"
  local clone_path_file="${fixture}/clone-path"
  local clone_path
  local log_file

  create_source_repo "$repo"
  create_runner "$runner"
  create_blocking_git_stub "$stub_bin"
  mkdir -p "$temp_root"

  LOCK_RELEASE_FILE="$release"
  (
    umask 022
    env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=true \
      LOCK_STARTED="$started" LOCK_RELEASE="$release" CLONE_PATH_FILE="$clone_path_file" \
      TMPDIR="$temp_root" DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo --force
  ) >"${fixture}/run.out" 2>&1 &
  BACKGROUND_PID=$!
  wait_for_marker "$started"

  clone_path="$(<"$clone_path_file")"
  log_file="$(find -P "$runner/.get-folder.conf/logs" -maxdepth 1 -type f -name '*.log' -print -quit)"
  [[ -n "$log_file" ]]
  [[ "$(stat -c '%a' -- "$runner/.get-folder.conf")" == 700 ]]
  [[ "$(stat -c '%a' -- "$runner/.get-folder.conf/locks")" == 700 ]]
  [[ "$(stat -c '%a' -- "$runner/.get-folder.conf/locks/Demo.lock")" == 700 ]]
  [[ "$(stat -c '%a' -- "$runner/.get-folder.conf/logs")" == 700 ]]
  [[ "$(stat -c '%a' -- "$log_file")" == 600 ]]
  [[ "$(stat -c '%a' -- "$clone_path")" == 700 ]]

  : >"$release"
  wait "$BACKGROUND_PID"
  BACKGROUND_PID=""
  LOCK_RELEASE_FILE=""
  [[ "$(<"$runner/Demo/config.txt")" == version-one ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_repository_exclusive_lock
#   Proves source synchronisætion's exclusive repository-directory flock
#   blocks get-folder before it creætes control, log, clone, or tærget stæte.
#ææææææææææææææææææææææææææææææææææ
test_repository_exclusive_lock() {
  local fixture="${TEST_ROOT}/repository-lock"
  local repo="${fixture}/source"
  local runner="${fixture}/runner"
  local repository_lock_fd=""
  local status

  create_source_repo "$repo"
  create_runner "$runner"
  exec {repository_lock_fd}<"$runner"
  flock --exclusive --nonblock "$repository_lock_fd"

  set +e
  (
    exec {repository_lock_fd}<&-
    DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo
  ) >"${fixture}/blocked.out" 2>&1
  status=$?
  set -e
  (( status != 0 ))
  rg -q "source synchronisætion is ælreædy replacing" "${fixture}/blocked.out"
  [[ ! -e "$runner/.get-folder.conf" ]]
  [[ ! -e "$runner/Demo" ]]

  exec {repository_lock_fd}<&-
  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo
  [[ "$(<"$runner/Demo/config.txt")" == version-one ]]
}

run_case initial_fetch test_initial_fetch
run_case secret_preservation test_secret_preservation
run_case symlink_escape test_symlink_escape_rejected
run_case parallel_lock test_parallel_lock
run_case replaced-app-lock test_replaced_app_lock_preserved
run_case replaced-clone-temp test_replaced_clone_temp_preserved
run_case cleanup-preflight-swap test_cleanup_swap_after_preflight_preserved
run_case restrictive-modes test_restrictive_modes
run_case repository-exclusive-lock test_repository_exclusive_lock

printf '%s\n' "Result: ${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
