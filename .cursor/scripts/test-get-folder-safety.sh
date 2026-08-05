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

  mkdir -p "$repo/Demo/secrets" "$repo/Demo/empty" "$repo/Nested/Demo"
  printf 'version-one' >"$repo/Demo/config.txt"
  printf 'CHANGE_ME' >"$repo/Demo/secrets/APP_PASSWORD"
  printf 'nested-source' >"$repo/Nested/Demo/config.txt"
  : >"$repo/Demo/empty/.gitkeep"
  printf '%s\n' '#!/usr/bin/env bash' 'printf '\''fixture-run\n'\''' >"$repo/run.sh"
  chmod 0755 "$repo/run.sh"
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
  [[ -x "$runner/run.sh" ]]
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

  printf 'version-two' >"$repo/Demo/config.txt"
  printf 'upstream-replacement' >"$repo/Demo/secrets/APP_PASSWORD"
  printf 'CHANGE_ME' >"$repo/Demo/secrets/NEW_SECRET"
  "$REAL_GIT" -C "$repo" add Demo
  "$REAL_GIT" -C "$repo" commit -qm refresh

  DOCKER_REPO_URL="$repo" "$runner/get-folder.sh" Demo --force
  [[ "$(<"$runner/Demo/config.txt")" == version-two ]]
  [[ "$(<"$runner/Demo/secrets/APP_PASSWORD")" == configured-secret ]]
  [[ "$(<"$runner/Demo/secrets/NEW_SECRET")" == CHANGE_ME ]]
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
  local attempt

  create_source_repo "$repo"
  create_runner "$runner"
  mkdir -p "$stub_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == clone && "${BLOCK_GIT_CLONE:-false}" == true ]]; then' \
    '  : >"$LOCK_STARTED"' \
    '  while [[ ! -e "$LOCK_RELEASE" ]]; do sleep 0.05; done' \
    'fi' \
    'exec "$REAL_GIT" "$@"' >"$stub_bin/git"
  chmod 0755 "$stub_bin/git"

  LOCK_RELEASE_FILE="$release"
  env PATH="${stub_bin}:${PATH}" REAL_GIT="$REAL_GIT" BLOCK_GIT_CLONE=true \
    LOCK_STARTED="$started" LOCK_RELEASE="$release" DOCKER_REPO_URL="$repo" \
    "$runner/get-folder.sh" Demo --force >"${fixture}/first.out" 2>&1 &
  BACKGROUND_PID=$!

  for attempt in {1..100}; do
    [[ -e "$started" ]] && break
    sleep 0.05
  done
  [[ -e "$started" ]]

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
run_case repository-exclusive-lock test_repository_exclusive_lock

printf '%s\n' "Result: ${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
