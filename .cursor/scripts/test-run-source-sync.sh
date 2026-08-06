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
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-source-sync.XXXXXX")"
readonly TEST_RUNNER="${TEST_ROOT}/runner"
readonly TEST_RESULTS="${TEST_ROOT}/results"
readonly TEST_RUN_LIBRARY="${TEST_RUNNER}/run.sh"
readonly TEST_GET_FOLDER_LIBRARY="${TEST_RUNNER}/get-folder.sh"

PASS=0
FAIL=0

mkdir -p -- "$TEST_RUNNER" "$TEST_RESULTS"
cp -- "$TEST_RUN_SH" "$TEST_RUN_LIBRARY"
cp -- "${TEST_REPO_ROOT}/get-folder.sh" "$TEST_GET_FOLDER_LIBRARY"
sed -i '$d' "$TEST_RUN_LIBRARY"
sed -i '/^main "\$@" || {$/,$d' "$TEST_GET_FOLDER_LIBRARY"
# shellcheck disable=SC1091
source "$TEST_RUN_LIBRARY"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_test_root
#   Removes every disposæble fixture unless evidence retention is enæbled.
#ææææææææææææææææææææææææææææææææææ
cleanup_test_root() {
  if [[ "${KEEP_TEST_OUTPUT:-false}" == true ]]; then
    printf 'Evidence retained: %s\n' "$TEST_ROOT"
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup_test_root EXIT

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
    sed -n '1,200p' "$2"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_case
#   Runs one regression in æ strict isolæted subshell.
#   Ærguments:
#     $1 - test næme
#     $2 - test function
#ææææææææææææææææææææææææææææææææææ
run_case() {
  local name="$1"
  local function_name="$2"
  local output="${TEST_RESULTS}/${name}.out"
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
# FUNCTION: write_lines
#   Writes newline-terminæted fixture lines to one file.
#   Ærguments:
#     $1 - output file
#     $@ - lines to write
#ææææææææææææææææææææææææææææææææææ
write_lines() {
  local output_file="$1"
  shift
  mkdir -p -- "$(dirname -- "$output_file")"
  printf '%s\n' "$@" > "$output_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_test_marker
#   Wæits briefly for æ child process to prove thæt it holds its lock.
#   Ærguments:
#     $1 - mærker file
#ææææææææææææææææææææææææææææææææææ
wait_for_test_marker() {
  local marker="$1"
  local attempt

  for (( attempt = 0; attempt < 100; attempt++ )); do
    [[ -f "$marker" ]] && return 0
    sleep 0.02
  done
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: launch_repository_lock_holder
#   Starts one stopped child thæt holds the reæl repository descriptor lock.
#   Ærguments:
#     $1 - stripped script libræry
#     $2 - shæred or exclusive mode
#     $3 - readiness mærker
#     $4 - output PID væriæble
#ææææææææææææææææææææææææææææææææææ
launch_repository_lock_holder() {
  local library="$1"
  local mode="$2"
  local marker="$3"
  local output_name="$4"
  local -n output_ref="$output_name"

  rm -f -- "$marker"
  LOCK_LIBRARY="$library" LOCK_MODE="$mode" LOCK_MARKER="$marker" bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$LOCK_LIBRARY"
    DEBUG=false
    LOGFILE=""
    REPOSITORY_LOCK_FD=""
    if [[ "$LOCK_MODE" == exclusive ]]; then
      SYNC_SOURCE=true
    else
      SYNC_SOURCE=false
    fi
    acquire_repository_lock
    printf "locked\n" > "$LOCK_MARKER"
    kill -STOP "$BASHPID"
  ' &
  output_ref=$!
  wait_for_test_marker "$marker"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: try_repository_lock
#   Attempts one reæl repository descriptor lock in æ fresh process.
#   Ærguments:
#     $1 - stripped script libræry
#     $2 - shæred or exclusive mode
#ææææææææææææææææææææææææææææææææææ
try_repository_lock() {
  local library="$1"
  local mode="$2"

  LOCK_LIBRARY="$library" LOCK_MODE="$mode" bash -c '
    set -euo pipefail
    # shellcheck disable=SC1090
    source "$LOCK_LIBRARY"
    DEBUG=false
    LOGFILE=""
    REPOSITORY_LOCK_FD=""
    if [[ "$LOCK_MODE" == exclusive ]]; then
      SYNC_SOURCE=true
    else
      SYNC_SOURCE=false
    fi
    acquire_repository_lock
  '
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reset_source_sync_globals
#   Resets run.sh source-sync stæte for one disposæble root Æpp.
#   Ærguments:
#     $1 - root Æpp directory næme below the isolæted runner
#ææææææææææææææææææææææææææææææææææ
reset_source_sync_globals() {
  TARGET_RELATIVE_DIR="$1"
  TARGET_DIR="${SCRIPT_DIR}/${TARGET_RELATIVE_DIR}"
  DEBUG=false
  DRY_RUN=false
  FORCE=false
  UPDATE=false
  SYNC_SOURCE=true
  DELETE_VOLUMES=false
  SKIP_PERMISSIONS=false
  GENERATE_PASSWORD=false
  LOGFILE=""
  LOG_FD=""
  _TMPDIR=""
  SOURCE_SYNC_STAGE=""
  SOURCE_SYNC_SEEDS=""
  SOURCE_SYNC_BACKUP=""
  SOURCE_SYNC_JOURNAL=""
  SOURCE_SYNC_REMOTE_COMMIT="1111111111111111111111111111111111111111"
  SOURCE_SYNC_REMOTE_TREE="2222222222222222222222222222222222222222"
  SOURCE_SYNC_PHASE=""
  SOURCE_SYNC_COMMITTED=false
  SOURCE_SYNC_PRESERVE=false
  SOURCE_SYNC_TARGET_IDENTITY=""
  SOURCE_SYNC_STAGE_IDENTITY=""
  SOURCE_SYNC_SEEDS_IDENTITY=""
  SOURCE_SYNC_TARGET_UID=""
  SOURCE_SYNC_TARGET_GID=""
  SOURCE_SYNC_TARGET_MODE=""
  SOURCE_SYNC_RUNTIME_PATHS=()
  SOURCE_SYNC_RUNTIME_IDENTITIES=()
  source_sync_control_paths
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_source_sync_target_metadata
#   Cæptures the journælled inode, owner, group, ænd mode of the old Æpp root.
#   Ærguments:
#     $1 - old Æpp root in its current næme
#ææææææææææææææææææææææææææææææææææ
capture_source_sync_target_metadata() {
  local old_root="$1"

  SOURCE_SYNC_TARGET_IDENTITY=$(stat -Lc '%d:%i' -- "$old_root")
  SOURCE_SYNC_TARGET_UID=$(stat -c '%u' -- "$old_root")
  SOURCE_SYNC_TARGET_GID=$(stat -c '%g' -- "$old_root")
  SOURCE_SYNC_TARGET_MODE=$(stat -c '%a' -- "$old_root")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_source_sync_publication_fixture
#   Creætes one minimæl old/stæged/seed tree with journæl identities ænd æ
#   vælid source lock for publicætion or fæilure-injection regressions.
#   Ærguments:
#     $1 - unique root Æpp næme
#ææææææææææææææææææææææææææææææææææ
prepare_source_sync_publication_fixture() {
  local app="$1"

  reset_source_sync_globals "$app"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.FAULT"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$TARGET_DIR" "${SOURCE_SYNC_STAGE}/.run.conf" "$SOURCE_SYNC_SEEDS"
  write_lines "${TARGET_DIR}/sentinel" "old-active-${app}"
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" "new-active-${app}"
  write_lines "${SOURCE_SYNC_SEEDS}/evidence" "seed-evidence-${app}"
  capture_source_sync_target_metadata "$TARGET_DIR"
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  write_source_sync_lock "$SOURCE_SYNC_STAGE"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: source_sync_transition_child_body
#   Builds one duræble v4 transition in æ fresh process, then self-signæls or
#   stops for æ deterministic SIGKILL. Exported only by the signæl tests.
#ææææææææææææææææææææææææææææææææææ
source_sync_transition_child_body() {
  set -euo pipefail
  # shellcheck disable=SC1090
  source "$TRANSITION_LIBRARY"

  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }

  TARGET_RELATIVE_DIR="$TRANSITION_APP"
  TARGET_DIR="${SCRIPT_DIR}/${TARGET_RELATIVE_DIR}"
  DEBUG=false
  DRY_RUN=false
  SYNC_SOURCE=true
  SOURCE_SYNC_REMOTE_COMMIT="1111111111111111111111111111111111111111"
  SOURCE_SYNC_REMOTE_TREE="2222222222222222222222222222222222222222"
  SOURCE_SYNC_COMMITTED=false
  SOURCE_SYNC_PRESERVE=false
  SOURCE_SYNC_RUNTIME_PATHS=()
  SOURCE_SYNC_RUNTIME_IDENTITIES=()
  _TMPDIR=""
  source_sync_control_paths
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${TARGET_RELATIVE_DIR}.source-sync.SIGNAL"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$TARGET_DIR" "${SOURCE_SYNC_STAGE}/.run.conf" "$SOURCE_SYNC_SEEDS"
  printf '%s\n' "old-active-${TRANSITION_PHASE}" > "${TARGET_DIR}/sentinel"
  printf '%s\n' "new-active-${TRANSITION_PHASE}" > "${SOURCE_SYNC_STAGE}/sentinel"
  SOURCE_SYNC_TARGET_IDENTITY=$(stat -Lc '%d:%i' -- "$TARGET_DIR")
  SOURCE_SYNC_TARGET_UID=$(stat -c '%u' -- "$TARGET_DIR")
  SOURCE_SYNC_TARGET_GID=$(stat -c '%g' -- "$TARGET_DIR")
  SOURCE_SYNC_TARGET_MODE=$(stat -c '%a' -- "$TARGET_DIR")
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  write_source_sync_lock "$SOURCE_SYNC_STAGE"
  setup_cleanup_trap

  case "$TRANSITION_PHASE" in
    renaming_old)
      write_source_sync_journal renaming_old
      command mv -T -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
      sync_source_sync_path "$SCRIPT_DIR"
      ;;
    moving_data)
      mkdir -p -- "${TARGET_DIR}/appdata"
      printf '%s\n' 'runtime-marker' > "${TARGET_DIR}/appdata/runtime.txt"
      SOURCE_SYNC_RUNTIME_PATHS=(appdata)
      SOURCE_SYNC_RUNTIME_IDENTITIES[appdata]=$(stat -Lc '%d:%i' -- "${TARGET_DIR}/appdata")
      command mv -T -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
      write_source_sync_journal moving_data
      command mv -T -- "${SOURCE_SYNC_BACKUP}/appdata" "${SOURCE_SYNC_STAGE}/appdata"
      sync_source_sync_path "$SCRIPT_DIR"
      ;;
    published)
      command mv -T -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
      command mv -T -- "$SOURCE_SYNC_STAGE" "$TARGET_DIR"
      sync_source_sync_path "$SCRIPT_DIR"
      write_source_sync_journal published
      ;;
    *)
      return 64
      ;;
  esac

  if [[ "$TRANSITION_MODE" == soft ]]; then
    kill -s "$TRANSITION_SIGNAL" "$BASHPID"
  elif [[ "$TRANSITION_MODE" == stop ]]; then
    printf '%s\n' ready > "$TRANSITION_READY"
    kill -STOP "$BASHPID"
  else
    return 65
  fi
  return 66
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REPOSITORY DESCRIPTOR-LOCK REGRESSIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_repository_descriptor_locking
#   Proves shæred ordinæry locks, exclusive source-sync exclusion through æ
#   tærget renæme, get-folder exclusion, ænd kernel releæse on SIGKILL.
#ææææææææææææææææææææææææææææææææææ
test_repository_descriptor_locking() {
  local root="${TEST_ROOT}/repository-lock"
  local shared_marker="${root}/shared.ready"
  local exclusive_marker="${root}/exclusive.ready"
  local killed_marker="${root}/killed.ready"
  local shared_pid=""
  local exclusive_pid=""
  local killed_pid=""
  local killed_status=0

  mkdir -p -- "$root" "${TEST_RUNNER}/LockRename"
  trap '
    for lock_pid in "${shared_pid:-}" "${exclusive_pid:-}" "${killed_pid:-}"; do
      if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        kill -KILL "$lock_pid" 2>/dev/null || true
        wait "$lock_pid" 2>/dev/null || true
      fi
    done
  ' EXIT

  launch_repository_lock_holder "$TEST_RUN_LIBRARY" shared "$shared_marker" shared_pid
  try_repository_lock "$TEST_RUN_LIBRARY" shared
  try_repository_lock "$TEST_GET_FOLDER_LIBRARY" shared
  if try_repository_lock "$TEST_RUN_LIBRARY" exclusive; then
    return 1
  fi
  kill -CONT "$shared_pid"
  wait "$shared_pid"
  shared_pid=""

  launch_repository_lock_holder "$TEST_RUN_LIBRARY" exclusive "$exclusive_marker" exclusive_pid
  mv -T -- "${TEST_RUNNER}/LockRename" "${TEST_RUNNER}/LockRename_backup"
  if try_repository_lock "$TEST_RUN_LIBRARY" shared; then
    return 1
  fi
  if try_repository_lock "$TEST_GET_FOLDER_LIBRARY" shared; then
    return 1
  fi
  [[ ! -e "${TEST_RUNNER}/.get-folder.conf" ]]
  kill -CONT "$exclusive_pid"
  wait "$exclusive_pid"
  exclusive_pid=""

  launch_repository_lock_holder "$TEST_RUN_LIBRARY" exclusive "$killed_marker" killed_pid
  kill -KILL "$killed_pid"
  wait "$killed_pid" 2>/dev/null || killed_status=$?
  [[ "$killed_status" == 137 ]]
  killed_pid=""
  try_repository_lock "$TEST_RUN_LIBRARY" exclusive
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_external_source_sync_logging
#   Proves source-sync logs live outside the renæmed Æpp, remæin open through
#   æ tærget renæme, ænd dry-run creætes no externæl logging stæte.
#ææææææææææææææææææææææææææææææææææ
test_external_source_sync_logging() {
  local app="ExternalLog"
  local expected_log_dir=""
  local opened_identity=""
  local before_count=""
  local pending_journal=""

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  expected_log_dir="${SCRIPT_DIR}/.run-source-sync.conf/logs/${app}"
  setup_logging 2
  [[ "$LOGFILE" == "${expected_log_dir}/"*.log ]]
  [[ -f "$LOGFILE" && ! -L "$LOGFILE" ]]
  [[ "$(stat -Lc '%u:%a:%h:%d' -- "$LOGFILE")" == \
    "${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")" ]]
  [[ "$(stat -Lc '%u:%a' -- "${SCRIPT_DIR}/.run-source-sync.conf")" == "${EUID}:700" ]]
  [[ "$(stat -Lc '%u:%a' -- "${SCRIPT_DIR}/.run-source-sync.conf/logs")" == "${EUID}:700" ]]
  [[ "$(stat -Lc '%u:%a' -- "$expected_log_dir")" == "${EUID}:700" ]]
  [[ -n "$LOG_FD" ]]
  opened_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${LOG_FD}")
  [[ "$opened_identity" == "$(stat -Lc '%d:%i' -- "$LOGFILE")" ]]
  [[ ! -e "${expected_log_dir}/latest.log" && ! -L "${expected_log_dir}/latest.log" ]]

  log_info 'source-log-before-rename'
  mv -T -- "$TARGET_DIR" "${TARGET_DIR}_backup"
  log_info 'source-log-after-rename'
  grep -Fq 'source-log-before-rename' "$LOGFILE"
  grep -Fq 'source-log-after-rename' "$LOGFILE"
  [[ -f "$LOGFILE" ]]
  exec {LOG_FD}>&-
  LOG_FD=""

  app="PendingLog"
  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  expected_log_dir="${SCRIPT_DIR}/.run-source-sync.conf/logs/${app}"
  setup_logging 2
  exec {LOG_FD}>&-
  LOG_FD=""
  write_lines "${expected_log_dir}/${app}-20000101-000001.AAAAAA.log" 'old-log-a'
  write_lines "${expected_log_dir}/${app}-20000101-000002.BBBBBB.log" 'old-log-b'
  write_lines "${expected_log_dir}/${app}-20000101-000003.CCCCCC.log" 'old-log-c'
  pending_journal="${SCRIPT_DIR}/.run-source-sync.conf/transactions/${app}.state"
  write_lines "$pending_journal" 'pending-recovery-evidence'
  chmod 0600 -- "$pending_journal"
  before_count=$(command find -P "$expected_log_dir" -mindepth 1 -maxdepth 1 \
    -type f -name "${app}-????????-??????.??????.log" | wc -l)
  setup_logging 2
  [[ "$(command find -P "$expected_log_dir" -mindepth 1 -maxdepth 1 \
    -type f -name "${app}-????????-??????.??????.log" | wc -l)" == "$((before_count + 1))" ]]
  [[ -f "${expected_log_dir}/${app}-20000101-000001.AAAAAA.log" ]]
  [[ -f "${expected_log_dir}/${app}-20000101-000002.BBBBBB.log" ]]
  [[ -f "${expected_log_dir}/${app}-20000101-000003.CCCCCC.log" ]]
  exec {LOG_FD}>&-
  LOG_FD=""

  app="ExternalLogDryRun"
  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  DRY_RUN=true
  setup_logging 2
  [[ -z "$LOGFILE" ]]
  [[ ! -e "${SCRIPT_DIR}/.run-source-sync.conf/logs/${app}" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOCÆL GIT UPSTREÆM REGRESSIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_local_git_source_resolution
#   Proves one clone-resolved origin/mæin snæpshot is used even if the locæl
#   remote moves, ænd rejects missing, mælformed, or symlinked root sources.
#ææææææææææææææææææææææææææææææææææ
test_local_git_source_resolution() {
  local root="${TEST_ROOT}/git-source"
  local work="${root}/work"
  local local_remote="${root}/remote.git"
  local first_commit=""
  local advanced_commit=""
  local advance_remote=true
  local fail_checkout=false

  mkdir -p -- "${work}/ExactApp"
  write_lines "${work}/ExactApp/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:3'
  write_lines "${work}/ExactApp/.env" 'APP_NAME=exact-app'
  write_lines "${work}/ExactApp/README.md" 'version-one'
  command git init --quiet --initial-branch=main "$work"
  command git -C "$work" config user.name 'Source Sync Test'
  command git -C "$work" config user.email 'source-sync@example.invalid'
  command git -C "$work" add -- ExactApp
  command git -C "$work" commit --quiet -m 'initial source'
  first_commit=$(command git -C "$work" rev-parse HEAD)
  command git clone --quiet --bare "$work" "$local_remote"

  setup_cleanup_trap() { return 0; }
  git() {
    if [[ "$fail_checkout" == true && "${1:-}" == -C && "${3:-}" == checkout ]]; then
      fail_checkout=false
      return 75
    fi
    if [[ "${1:-}" == clone ]]; then
      local destination="${@: -1}"
      command git clone --quiet --no-checkout "$local_remote" "$destination" || return 1
      if [[ "$advance_remote" == true ]]; then
        write_lines "${work}/ExactApp/README.md" 'version-two'
        command git -C "$work" add -- ExactApp/README.md
        command git -C "$work" commit --quiet -m 'advance after clone'
        command git -C "$work" push --quiet "$local_remote" main
        advance_remote=false
      fi
      return 0
    fi
    command git "$@"
  }

  reset_source_sync_globals ExactApp
  clone_app_source
  advanced_commit=$(command git --git-dir="$local_remote" rev-parse main)
  [[ "$advanced_commit" != "$first_commit" ]]
  [[ "$SOURCE_SYNC_REMOTE_COMMIT" == "$first_commit" ]]
  [[ "$(<"${_TMPDIR}/ExactApp/README.md")" == version-one ]]

  reset_source_sync_globals MissingRoot
  if clone_app_source; then
    return 1
  fi

  mkdir -p -- "${work}/MalformedApp" "${work}/SymlinkedCompose"
  write_lines "${work}/MalformedApp/docker-compose.app.yaml" 'services: {}'
  write_lines "${work}/SymlinkedCompose/.env" 'APP_NAME=symlinked-compose'
  ln -s -- ../ExactApp/docker-compose.app.yaml \
    "${work}/SymlinkedCompose/docker-compose.app.yaml"
  command git -C "$work" add -- MalformedApp SymlinkedCompose
  command git -C "$work" commit --quiet -m 'unsafe source fixtures'
  command git -C "$work" push --quiet "$local_remote" main

  reset_source_sync_globals MalformedApp
  if clone_app_source; then
    return 1
  fi
  reset_source_sync_globals SymlinkedCompose
  if clone_app_source; then
    return 1
  fi

  reset_source_sync_globals ExactApp
  mkdir -p -- "$TARGET_DIR"
  write_lines "${TARGET_DIR}/sentinel" 'checkout-failure-must-not-mutate'
  fail_checkout=true
  if clone_app_source; then
    return 1
  fi
  [[ "$(<"${TARGET_DIR}/sentinel")" == checkout-failure-must-not-mutate ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_first_normal_merge_uses_source_revision
#   Proves the first normæl templæte merge æfter source synchronisætion uses
#   the exæct .source.lock commit even when origin/main hæs ælreædy ædvænced,
#   then commits the ordinæry .templates.lock æt thæt sæme revision.
#ææææææææææææææææææææææææææææææææææ
test_first_normal_merge_uses_source_revision() {
  local root="${TEST_ROOT}/first-normal-merge"
  local work="${root}/work"
  local local_remote="${root}/remote.git"
  local app="FirstNormalMerge"
  local first_commit=""
  local first_tree=""
  local advanced_commit=""
  local template_lock=""

  mkdir -p -- "${work}/templates/example/scripts" "${work}/${app}"
  write_lines "${work}/templates/example/scripts/revision.txt" 'templates-at-source-sync'
  write_lines "${work}/${app}/docker-compose.app.yaml" 'services: {}'
  write_lines "${work}/${app}/.env" 'APP_NAME=first-normal-merge'
  command git init --quiet --initial-branch=main "$work"
  command git -C "$work" config user.name 'Source Sync Test'
  command git -C "$work" config user.email 'source-sync@example.invalid'
  command git -C "$work" add -- templates "$app"
  command git -C "$work" commit --quiet -m 'source-sync revision'
  first_commit=$(command git -C "$work" rev-parse HEAD)
  first_tree=$(command git -C "$work" rev-parse "HEAD:${app}")
  command git clone --quiet --bare "$work" "$local_remote"

  write_lines "${work}/templates/example/scripts/revision.txt" 'templates-after-source-sync'
  command git -C "$work" add -- templates
  command git -C "$work" commit --quiet -m 'advance templates after source sync'
  advanced_commit=$(command git -C "$work" rev-parse HEAD)
  command git -C "$work" push --quiet "$local_remote" main
  [[ "$advanced_commit" != "$first_commit" ]]

  reset_source_sync_globals "$app"
  mkdir -p -- "${TARGET_DIR}/.run.conf"
  SOURCE_SYNC_REMOTE_COMMIT="$first_commit"
  SOURCE_SYNC_REMOTE_TREE="$first_tree"
  write_source_sync_lock "$TARGET_DIR"
  template_lock="${TARGET_DIR}/.run.conf/.templates.lock"
  [[ ! -e "$template_lock" && ! -L "$template_lock" ]]

  SYNC_SOURCE=false
  INITIAL_RUN=false
  TEMPLATE_LOCKFILE=""
  TEMPLATE_REVISION=""
  TEMPLATE_LOCK_WRITE_PENDING=false
  TEMPLATE_LOCK_STAGED_FILE=""
  setup_cleanup_trap() { return 0; }
  clone_sparse_checkout "$local_remote" origin/main templates

  [[ "$(command git -C "$_TMPDIR" rev-parse HEAD)" == "$first_commit" ]]
  [[ "$(<"${_TMPDIR}/templates/example/scripts/revision.txt")" == \
    templates-at-source-sync ]]
  [[ "$TEMPLATE_REVISION" == "$first_commit" ]]
  [[ "$TEMPLATE_REVISION" != "$advanced_commit" ]]
  [[ "$TEMPLATE_LOCKFILE" == "$template_lock" ]]
  [[ "$TEMPLATE_LOCK_WRITE_PENDING" == true ]]
  [[ "$INITIAL_RUN" == true ]]

  PROJECT_LOCK_IDENTITY=$(stat -Lc '%d:%i' -- "${TARGET_DIR}/.run.conf")
  DEPLOYMENT_TRANSACTION_DIR=""
  commit_template_lockfile
  [[ "$TEMPLATE_LOCK_WRITE_PENDING" == false ]]
  [[ -f "$template_lock" && ! -L "$template_lock" ]]
  [[ "$(<"$template_lock")" == "$first_commit" ]]
  [[ "$(stat -Lc '%u:%a:%h' -- "$template_lock")" == "${EUID}:600:1" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_end_to_end_local_git_sync
#   Runs the sourced mæin CLI flow with æ locæl Git remote, reæl locks,
#   stæging, journælling, publicætion, ænd only Docker runtime inspection stubbed.
#ææææææææææææææææææææææææææææææææææ
test_end_to_end_local_git_sync() {
  local root="${TEST_ROOT}/end-to-end"
  local work="${root}/work"
  local local_remote="${root}/remote.git"
  local runner="${root}/runner"
  local stub_bin="${root}/bin"
  local e2e_run="${runner}/run.sh"
  local docker_calls="${root}/docker-calls.txt"
  local app="EndToEnd"
  local local_secret='configured-end-to-end-secret'
  local yq_release_tag=""

  mkdir -p -- \
    "${work}/${app}/secrets" \
    "${work}/${app}/scripts" \
    "${work}/${app}/dockerfiles"
  write_lines "${work}/${app}/docker-compose.app.yaml" \
    'x-required-services: []' \
    'services:' \
    '  app:' \
    '    image: alpine:4'
  write_lines "${work}/${app}/.env" \
    'APP_NAME=end-to-end' \
    'APP_DIRECTORIES=runtime-data/store'
  write_lines "${work}/${app}/README.md" '# Fresh upstream source'
  write_lines "${work}/${app}/scripts/backup.cron" 'upstream-schedule'
  write_lines "${work}/${app}/scripts/runtime-helper.sh" '#!/bin/sh' 'printf runtime-helper'
  write_lines "${work}/${app}/dockerfiles/readable-entrypoint.sh" '#!/bin/sh' 'printf readable-entrypoint'
  write_lines "${work}/${app}/dockerfiles/executable-helper.sh" '#!/bin/sh' 'printf executable-helper'
  printf '%s' 'CHANGE_ME' > "${work}/${app}/secrets/APP_SECRET"
  chmod 0644 -- \
    "${work}/${app}/scripts/backup.cron" \
    "${work}/${app}/scripts/runtime-helper.sh" \
    "${work}/${app}/dockerfiles/readable-entrypoint.sh" \
    "${work}/${app}/secrets/APP_SECRET"
  chmod 0755 -- "${work}/${app}/dockerfiles/executable-helper.sh"
  command git init --quiet --initial-branch=main "$work"
  command git -C "$work" config user.name 'Source Sync Test'
  command git -C "$work" config user.email 'source-sync@example.invalid'
  command git -C "$work" add -- "$app"
  command git -C "$work" commit --quiet -m 'end-to-end source'
  command git clone --quiet --bare "$work" "$local_remote"

  mkdir -p -- \
    "${runner}/${app}/.run.conf" \
    "${runner}/${app}/runtime-data/store" \
    "${runner}/${app}/secrets" \
    "${runner}/${app}/scripts" \
    "$stub_bin"
  cp -- "$TEST_RUN_SH" "$e2e_run"
  sed -i \
    "s|^readonly REPO_URL=.*|readonly REPO_URL=\"${local_remote}\"|" \
    "$e2e_run"
  chmod 0755 -- "$e2e_run"
  write_lines "${stub_bin}/docker" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf '\''%s\\n'\'' "$*" >> "$DOCKER_CALLS_FILE"' \
    'case "${1:-}" in' \
    '  ps) exit 0 ;;' \
    '  inspect) printf '\''[]\\n'\'' ;;' \
    '  *) exit 75 ;;' \
    'esac'
  chmod 0755 -- "${stub_bin}/docker"
  yq_release_tag=$(command yq --version 2>/dev/null |
    sed -nE 's/.*version (v4\.[0-9]+\.[0-9]+).*/\1/p')
  [[ "$yq_release_tag" =~ ^v4\.[0-9]+\.[0-9]+$ ]]
  write_lines "${stub_bin}/curl" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '[[ "${YQ_RELEASE_TAG:-}" =~ ^v4\.[0-9]+\.[0-9]+$ ]]' \
    'printf '\''https://github.com/mikefarah/yq/releases/tag/%s'\'' "$YQ_RELEASE_TAG"'
  chmod 0755 -- "${stub_bin}/curl"

  write_lines "${runner}/${app}/docker-compose.app.yaml" \
    'x-required-services: []' \
    'services:' \
    '  app:' \
    '    image: alpine:3'
  write_lines "${runner}/${app}/app.env" \
    'APP_NAME=end-to-end' \
    'APP_DIRECTORIES=runtime-data/store'
  write_lines "${runner}/${app}/.env" \
    'APP_NAME=end-to-end' \
    'APP_DIRECTORIES=runtime-data/store'
  write_lines "${runner}/${app}/runtime-data/store/data.txt" 'runtime-marker'
  write_lines "${runner}/${app}/scripts/backup.cron" 'deployment-schedule'
  printf '%s' "$local_secret" > "${runner}/${app}/secrets/APP_SECRET"
  chmod 0750 -- "${runner}/${app}"
  chmod 0640 -- \
    "${runner}/${app}/app.env" \
    "${runner}/${app}/scripts/backup.cron" \
    "${runner}/${app}/secrets/APP_SECRET"

  printf 'SYNC %s\n' "$app" | \
    DOCKER_CALLS_FILE="$docker_calls" YQ_RELEASE_TAG="$yq_release_tag" \
    PATH="${stub_bin}:${PATH}" \
    "$e2e_run" "$app" --sync-source

  [[ "$(<"${runner}/${app}/README.md")" == '# Fresh upstream source' ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}")" == 750 ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}_backup")" == 750 ]]
  [[ "$(<"${runner}/${app}/runtime-data/store/data.txt")" == runtime-marker ]]
  [[ "$(<"${runner}/${app}/secrets/APP_SECRET")" == "$local_secret" ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/app.env")" == 640 ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/scripts")" == 755 ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/dockerfiles")" == 755 ]]
  [[ "$(<"${runner}/${app}/scripts/backup.cron")" == deployment-schedule ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/scripts/backup.cron")" == 640 ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/scripts/runtime-helper.sh")" == 644 ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/dockerfiles/readable-entrypoint.sh")" == 644 ]]
  [[ "$(stat -c '%a' -- "${runner}/${app}/dockerfiles/executable-helper.sh")" == 755 ]]
  [[ ! -e "${runner}/${app}/.env" ]]
  [[ ! -e "${runner}/${app}/docker-compose.main.yaml" ]]
  [[ -d "${runner}/${app}_backup" ]]
  [[ ! -e "${runner}/${app}_backup/runtime-data" ]]
  [[ ! -e "${runner}/.run-source-sync.conf/transactions/${app}.state" ]]
  [[ "$(stat -Lc '%u:%a' -- "${runner}/.run-source-sync.conf")" == "${EUID}:700" ]]
  [[ "$(stat -Lc '%u:%a' -- "${runner}/.run-source-sync.conf/logs/${app}")" == "${EUID}:700" ]]
  [[ "$(command find -P "${runner}/.run-source-sync.conf/logs/${app}" \
    -mindepth 1 -maxdepth 1 -type f -name '*.log' | wc -l)" == 1 ]]
  while IFS= read -r log_file; do
    [[ "$(stat -Lc '%u:%a:%h:%d' -- "$log_file")" == \
      "${EUID}:600:1:$(stat -Lc '%d' -- "$runner")" ]]
  done < <(command find -P "${runner}/.run-source-sync.conf/logs/${app}" \
    -mindepth 1 -maxdepth 1 -type f -name '*.log')
  ! grep -Eq '(^| )(up|start|restart)( |$)' "$docker_calls"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_sync_app_source_noop
#   Runs the complete source-sync decision pæth with æ vælid source lock ænd
#   proves identicæl source ænd exæct locæl Compose æctivætions ære no-ops.
#ææææææææææææææææææææææææææææææææææ
test_sync_app_source_noop() {
  local root="${TEST_ROOT}/full-noop"
  local variant=""
  local app=""
  local remote_root=""
  local decision_log=""
  local before_hash=""
  local after_hash=""
  local dependency_validations=0
  local ensure_calls=0
  local mutation_calls=0

  setup_cleanup_trap() { return 0; }
  validate_source_sync_dependencies() {
    dependency_validations=$((dependency_validations + 1))
    return 0
  }
  clone_app_source() {
    _TMPDIR="${root}/${variant}/clone"
    SOURCE_SYNC_REMOTE_COMMIT="7777777777777777777777777777777777777777"
    SOURCE_SYNC_REMOTE_TREE="8888888888888888888888888888888888888888"
  }
  ensure_latest_yq() {
    ensure_calls=$((ensure_calls + 1))
    return 97
  }
  validate_source_sync_no_mounts() {
    mutation_calls=$((mutation_calls + 1))
    return 98
  }
  validate_source_sync_project_stopped() {
    mutation_calls=$((mutation_calls + 1))
    return 98
  }
  prepare_source_sync_stage() {
    mutation_calls=$((mutation_calls + 1))
    return 98
  }
  publish_source_sync_stage() {
    mutation_calls=$((mutation_calls + 1))
    return 98
  }

  for variant in identical activation; do
    if [[ "$variant" == identical ]]; then
      app="NoopIdentical"
    else
      app="NoopActivation"
    fi
    reset_source_sync_globals "$app"
    remote_root="${root}/${variant}/clone/${app}"
    decision_log="${root}/${variant}/decision.log"
    mkdir -p -- "$TARGET_DIR" "$remote_root"
    write_lines "${remote_root}/docker-compose.app.yaml" \
      'services:' \
      '  app:' \
      '    image: alpine:3' \
      '    # ports:' \
      '    #   - "8080:80"'
    if [[ "$variant" == identical ]]; then
      cp -- "${remote_root}/docker-compose.app.yaml" \
        "${TARGET_DIR}/docker-compose.app.yaml"
    else
      write_lines "${TARGET_DIR}/docker-compose.app.yaml" \
        'services:' \
        '  app:' \
        '    image: alpine:3' \
        '    ports:' \
        '      - "8080:80"'
    fi
    write_lines "${remote_root}/.env" "APP_NAME=${app}"
    write_lines "${TARGET_DIR}/app.env" "APP_NAME=${app}"
    write_lines "${remote_root}/README.md" '# Unchænged source'
    write_lines "${TARGET_DIR}/README.md" '# Unchænged source'
    SOURCE_SYNC_REMOTE_COMMIT="7777777777777777777777777777777777777777"
    SOURCE_SYNC_REMOTE_TREE="8888888888888888888888888888888888888888"
    write_source_sync_lock "$TARGET_DIR"
    before_hash=$(sha256sum -- \
      "${TARGET_DIR}/docker-compose.app.yaml" \
      "${TARGET_DIR}/app.env" \
      "${TARGET_DIR}/README.md" \
      "${TARGET_DIR}/.run.conf/.source.lock")

    sync_app_source </dev/null >"$decision_log" 2>&1

    after_hash=$(sha256sum -- \
      "${TARGET_DIR}/docker-compose.app.yaml" \
      "${TARGET_DIR}/app.env" \
      "${TARGET_DIR}/README.md" \
      "${TARGET_DIR}/.run.conf/.source.lock")
    [[ "$after_hash" == "$before_hash" ]]
    grep -Fq 'ælreædy mætches origin/main' "$decision_log"
    grep -Fq 'locæl Compose æctivætions were ignored æs intended' "$decision_log"
    [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" && \
      -z "$SOURCE_SYNC_STAGE" && -z "$SOURCE_SYNC_SEEDS" ]]
  done

  [[ "$dependency_validations" == 2 ]]
  [[ "$ensure_calls" == 0 && "$mutation_calls" == 0 ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SOURCE COMPÆRISON ÆND ENVIRONMENT REGRESSIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_compose_activation_and_real_drift
#   Proves exæct comment æctivætions compare equælly, survive æ reæl
#   upstreæm chænge, ænd do not hide æ locæl vælue chænge.
#ææææææææææææææææææææææææææææææææææ
test_compose_activation_and_real_drift() {
  local root="${TEST_ROOT}/compose"
  local remote="${root}/remote.yaml"
  local local_file="${root}/local.yaml"
  local output="${root}/output.yaml"
  local activations="${root}/activations.txt"

  write_lines "$remote" \
    'services:' \
    '  app:' \
    '    image: alpine:3' \
    '    # ports:' \
    '    #   - "8080:80"'
  write_lines "$local_file" \
    'services:' \
    '  app:' \
    '    image: alpine:3' \
    '    ports:' \
    '      - "8080:80"'

  render_compose_with_local_activations "$remote" "$local_file" "$output" "$activations"
  cmp -s -- "$output" "$local_file"
  [[ "$(wc -l < "$activations")" == 2 ]]
  grep -Fxq '4' "$activations"
  grep -Fxq '5' "$activations"

  sed -i 's/image: alpine:3/image: alpine:4/' "$remote"
  render_compose_with_local_activations "$remote" "$local_file" "$output" "$activations"
  grep -Fxq '    image: alpine:4' "$output"
  grep -Fxq '    ports:' "$output"
  grep -Fxq '      - "8080:80"' "$output"
  ! cmp -s -- "$output" "$local_file"

  sed -i 's/8080:80/9090:90/' "$local_file"
  render_compose_with_local_activations "$remote" "$local_file" "$output" "$activations"
  grep -Fxq '    #   - "8080:80"' "$output"
  [[ "$(wc -l < "$activations")" == 1 ]]

  write_lines "$remote" \
    'services:' \
    '  first:' \
    '    # ports:' \
    '    #   - "8080:80"' \
    '  second:' \
    '    # ports:' \
    '    #   - "8080:80"'
  write_lines "$local_file" \
    'services:' \
    '  first:' \
    '    # ports:' \
    '    #   - "8080:80"' \
    '  second:' \
    '    ports:' \
    '      - "8080:80"'
  render_compose_with_local_activations "$remote" "$local_file" "$output" "$activations"
  cmp -s -- "$output" "$local_file"
  [[ "$(<"$activations")" == $'6\n7' ]]

}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_env_authority_merge_and_sentinel
#   Proves app.env æuthority, legæcy fællbæck, key clæssificætion,
#   locæl-only preservætion, ænd non-execution/non-disclosure of vælues.
#ææææææææææææææææææææææææææææææææææ
test_env_authority_merge_and_sentinel() {
  local root="${TEST_ROOT}/env"
  local app="EnvAuthority"
  local remote="${root}/remote.env"
  local merged="${root}/merged.env"
  local added="${root}/added.txt"
  local local_only="${root}/local-only.txt"
  local log_file="${root}/merge.log"
  local sentinel="${root}/command-sentinel"
  local selected=""
  local legacy_merged="${root}/legacy-merged.env"
  local legacy_added="${root}/legacy-added.txt"
  local legacy_only="${root}/legacy-only.txt"
  local command_value="OPTIONAL=\$(touch ${sentinel})"

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  write_lines "$remote" \
    '# SPDX-License-Identifier: MIT' \
    'COMMON=remote-default' \
    'ACTIVE_NEW=new-default' \
    '# COMMENTED_NEW=disabled-default' \
    '# OPTIONAL=upstream-disabled'
  write_lines "${TARGET_DIR}/app.env" \
    'COMMON=local-value-secret-marker with spaces # and=equals' \
    "$command_value" \
    'LOCAL_ONLY=local-only-secret-marker=with#hash and spaces'
  write_lines "${TARGET_DIR}/.env" \
    'COMMON=generated-value-must-not-win' \
    'OPTIONAL=generated-value-must-not-win'

  select_local_source_env selected
  [[ "$selected" == "${TARGET_DIR}/app.env" ]]
  merge_source_env "$remote" "$selected" "$merged" "$added" "$local_only" >"$log_file" 2>&1

  grep -Fxq 'COMMON=local-value-secret-marker with spaces # and=equals' "$merged"
  grep -Fxq "$command_value" "$merged"
  grep -Fxq 'LOCAL_ONLY=local-only-secret-marker=with#hash and spaces' "$merged"
  grep -Fxq $'active\tACTIVE_NEW' "$added"
  grep -Fxq $'commented\tCOMMENTED_NEW' "$added"
  grep -Fxq 'LOCAL_ONLY' "$local_only"
  [[ ! -e "$sentinel" ]]
  ! grep -Fq 'local-value-secret-marker' "$log_file"
  ! grep -Fq 'local-only-secret-marker' "$log_file"
  ! grep -Fq "$sentinel" "$log_file"

  rm -- "${TARGET_DIR}/app.env"
  select_local_source_env selected >"${root}/legacy-select.log" 2>&1
  [[ "$selected" == "${TARGET_DIR}/.env" ]]
  merge_source_env "$remote" "$selected" "$legacy_merged" "$legacy_added" "$legacy_only"
  grep -Fxq 'COMMON=generated-value-must-not-win' "$legacy_merged"
  grep -Fxq 'OPTIONAL=generated-value-must-not-win' "$legacy_merged"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_env_alternative_states_and_rejections
#   Proves RustDesk/Seæfile-style æctive/commented ælternætives, state
#   transitions, opæque shell text, ænd fæil-closed input vælidætion.
#ææææææææææææææææææææææææææææææææææ
test_env_alternative_states_and_rejections() {
  local root="${TEST_ROOT}/env-alternatives"
  local remote="${root}/remote.env"
  local local_env="${root}/local.env"
  local merged="${root}/merged.env"
  local added="${root}/added.txt"
  local local_only="${root}/local-only.txt"
  local sentinel="${root}/must-not-execute"
  local valid_remote="${root}/valid-remote.env"
  local duplicate="${root}/duplicate.env"
  local malformed="${root}/malformed.env"
  local nul_file="${root}/nul.env"
  local symlink="${root}/symlink.env"
  local fifo="${root}/special.env"
  local protected_output="${root}/protected-output.env"
  local protected_added="${root}/protected-added.txt"
  local protected_local_only="${root}/protected-local-only.txt"
  local invalid_input
  local opaque_value

  opaque_value="OPAQUE=spaces # equals= quotes \"double\" 'single' \`backtick\` \$dollar \$(touch ${sentinel})"
  write_lines "$remote" \
    'APP_IMAGE=remote.example/oss:1 # Æctive OSS choice' \
    '# APP_IMAGE=remote.example/pro:1 # Optionæl Pro choice' \
    '# REMOTE_COMMENTED=remote-disabled' \
    'BECOMES_ACTIVE=remote-enabled' \
    '# BECOMES_LOCAL_ACTIVE=remote-disabled'
  write_lines "$local_env" \
    'APP_IMAGE=local.example/oss:1 # Deployment choice' \
    '# APP_IMAGE=local.example/pro:1 # Deployment ælternætive' \
    '# BECOMES_ACTIVE=locally-disabled' \
    'BECOMES_LOCAL_ACTIVE=locally-enabled' \
    "$opaque_value" \
    'REMOVED_UPSTREAM=keep-this-local-value'

  merge_source_env "$remote" "$local_env" "$merged" "$added" "$local_only"
  [[ "$(grep -Ec '^[[:space:]]*APP_IMAGE[[:space:]]*=' "$merged")" == 1 ]]
  grep -Fxq 'APP_IMAGE=local.example/oss:1 # Deployment choice' "$merged"
  grep -Fxq '# APP_IMAGE=remote.example/pro:1 # Optionæl Pro choice' "$merged"
  grep -Fxq 'BECOMES_LOCAL_ACTIVE=locally-enabled' "$merged"
  grep -Fxq 'BECOMES_ACTIVE=remote-enabled' "$merged"
  grep -Fxq $'active\tBECOMES_ACTIVE' "$added"
  grep -Fxq "$opaque_value" "$merged"
  grep -Fxq 'REMOVED_UPSTREAM' "$local_only"
  [[ ! -e "$sentinel" ]]

  write_lines "$valid_remote" 'GOOD=remote-default'
  write_lines "$duplicate" 'DUPLICATE=first' 'DUPLICATE=second'
  write_lines "$malformed" 'GOOD=value' 'lowercase=value'
  printf 'GOOD=value\0INJECTED=value\n' > "$nul_file"
  ln -s -- "$remote" "$symlink"
  mkfifo -- "$fifo"
  for invalid_input in "$duplicate" "$malformed" "$nul_file" "$symlink" "$fifo"; do
    write_lines "$protected_output" 'unchanged-output'
    write_lines "$protected_added" 'unchanged-added'
    write_lines "$protected_local_only" 'unchanged-local-only'
    if merge_source_env "$valid_remote" "$invalid_input" "$protected_output" \
      "$protected_added" "$protected_local_only"; then
      return 1
    fi
    [[ "$(<"$protected_output")" == unchanged-output ]]
    [[ "$(<"$protected_added")" == unchanged-added ]]
    [[ "$(<"$protected_local_only")" == unchanged-local-only ]]
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- STOPPED-PROJECT PREFLIGHT REGRESSIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_missing_compose_stopped_preflight
#   Proves æ missing generæted Compose file does not hide æ running contæiner
#   whose Compose working-directory læbel points æt the tærget Æpp.
#ææææææææææææææææææææææææææææææææææ
test_missing_compose_stopped_preflight() {
  local app="StoppedPreflight"
  local docker_fixture="running"

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  write_lines "${TARGET_DIR}/sentinel" 'deployment-must-not-change'

  docker() {
    case "${1:-}" in
      ps)
        if [[ "$docker_fixture" == uninspectable ]]; then
          return 71
        fi
        if [[ "$docker_fixture" == running ]]; then
          printf 'running-container-id\n'
        fi
        ;;
      inspect)
        if [[ "$docker_fixture" == uninspectable ]]; then
          return 72
        fi
        printf '%s\n' "$TARGET_DIR"
        ;;
      compose)
        return 73
        ;;
      *)
        return 74
        ;;
    esac
  }

  if validate_source_sync_project_stopped; then
    return 1
  fi
  [[ "$(<"${TARGET_DIR}/sentinel")" == deployment-must-not-change ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]

  docker_fixture="uninspectable"
  if validate_source_sync_project_stopped; then
    return 1
  fi
  docker_fixture="empty"
  validate_source_sync_project_stopped
  [[ "$(<"${TARGET_DIR}/sentinel")" == deployment-must-not-change ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_source_sync_mount_rejection
#   Proves findmnt mount metædætæ exæctly æt or below the root Æpp blocks
#   source synchronisætion without touching deployment or trænsæction stæte.
#ææææææææææææææææææææææææææææææææææ
test_source_sync_mount_rejection() {
  local app="MountPreflight"
  local mount_target=""

  reset_source_sync_globals "$app"
  mkdir -p -- "${TARGET_DIR}/appdata/bind"
  write_lines "${TARGET_DIR}/sentinel" 'mount-preflight-read-only'
  findmnt() {
    printf '{"filesystems":[{"target":"%s"}]}\n' "$mount_target"
  }

  for mount_target in "$TARGET_DIR" "${TARGET_DIR}/appdata/bind"; do
    if validate_source_sync_no_mounts "$TARGET_DIR"; then
      return 1
    fi
    [[ "$(<"${TARGET_DIR}/sentinel")" == mount-preflight-read-only ]]
    [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" && \
      -z "$SOURCE_SYNC_STAGE" && -z "$SOURCE_SYNC_SEEDS" ]]
  done

  mount_target="${SCRIPT_DIR}/unrelated"
  validate_source_sync_no_mounts "$TARGET_DIR"
  [[ "$(<"${TARGET_DIR}/sentinel")" == mount-preflight-read-only ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_source_sync_dependency_preflight
#   Proves missing supply-chæin tools, invælid yq, ænd æ non-writæble yq
#   without sudo fæil reæd-only before deployment stæte cæn be touched.
#ææææææææææææææææææææææææææææææææææ
test_source_sync_dependency_preflight() {
  local app="DependencyPreflight"
  local missing_dependency=""
  local resolved_yq_override=""
  local hide_sudo=false
  local install_calls=0
  local latest_calls=0

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  write_lines "${TARGET_DIR}/sentinel" 'dependency-preflight-read-only'
  install_dependency() {
    install_calls=$((install_calls + 1))
    return 81
  }
  ensure_latest_yq() {
    latest_calls=$((latest_calls + 1))
    return 82
  }
  command() {
    if [[ "${1:-}" == -v && "${2:-}" == "$missing_dependency" && \
          -n "$missing_dependency" ]]; then
      return 1
    fi
    if [[ "${1:-}" == -v && "${2:-}" == yq && -n "$resolved_yq_override" ]]; then
      printf '%s\n' "$resolved_yq_override"
      return 0
    fi
    if [[ "${1:-}" == -v && "${2:-}" == sudo && "$hide_sudo" == true ]]; then
      return 1
    fi
    builtin command "$@"
  }

  for missing_dependency in curl sha256sum install yq; do
    if validate_source_sync_dependencies; then
      return 1
    fi
    [[ "$(<"${TARGET_DIR}/sentinel")" == dependency-preflight-read-only ]]
    [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" ]]
  done

  missing_dependency=""
  yq() {
    if [[ "${1:-}" == --version ]]; then
      printf '%s\n' 'yq version 3.4.1'
      return 0
    fi
    return 83
  }
  if validate_source_sync_dependencies; then
    return 1
  fi
  [[ "$install_calls" == 0 && "$latest_calls" == 0 ]]
  [[ "$(<"${TARGET_DIR}/sentinel")" == dependency-preflight-read-only ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  resolved_yq_override=/usr/bin/bash
  hide_sudo=true
  [[ -x "$resolved_yq_override" && ! -w "${resolved_yq_override%/*}" ]]
  yq() {
    if [[ "${1:-}" == --version ]]; then
      printf '%s\n' 'yq (https://github.com/mikefarah/yq/) version v4.99.0'
      return 0
    fi
    return 83
  }
  if validate_source_sync_dependencies; then
    return 1
  fi
  [[ "$install_calls" == 0 && "$latest_calls" == 0 ]]
  [[ "$(<"${TARGET_DIR}/sentinel")" == dependency-preflight-read-only ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" && \
    ! -e "${TARGET_DIR}/.run.conf" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_final_preflight_stage_identity_drift
#   Proves the finæl pre-publicætion check rejects æ same-næme foreign stæge
#   inode before the first Æpp-directory renæme.
#ææææææææææææææææææææææææææææææææææ
test_final_preflight_stage_identity_drift() {
  local app="FinalPreflight"

  reset_source_sync_globals "$app"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.PREFLIGHT"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$TARGET_DIR" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS"
  write_lines "${TARGET_DIR}/sentinel" 'stable-deployment'
  capture_source_sync_target_metadata "$TARGET_DIR"
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  REPOSITORY_LOCK_IDENTITY=$(stat -Lc '%d:%i' -- "$SCRIPT_DIR")
  PROJECT_LOCK_IDENTITY=""
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }
  validate_source_sync_project_stopped() { return 0; }

  validate_source_sync_final_preflight
  mv -T -- "$SOURCE_SYNC_STAGE" "${SOURCE_SYNC_STAGE}.original"
  mkdir -- "$SOURCE_SYNC_STAGE"
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" 'foreign-stage'
  if validate_source_sync_final_preflight; then
    return 1
  fi
  [[ "$(<"${TARGET_DIR}/sentinel")" == stable-deployment ]]
  [[ "$(<"${SOURCE_SYNC_STAGE}/sentinel")" == foreign-stage ]]
  [[ -d "${SOURCE_SYNC_STAGE}.original" ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- STÆGING, PUBLICÆTION, ÆND CONFIRMÆTION REGRESSIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_source_sync_prepublication_failure_injection
#   Injects the stæging tree copy ænd Compose render fæilures, then proves
#   cleænup restores zero deployment, bæckup, or journæl mutætion.
#ææææææææææææææææææææææææææææææææææ
test_source_sync_prepublication_failure_injection() {
  local root="${TEST_ROOT}/prepublication-failures"
  local app="CopyFailure"
  local remote="${root}/copy/remote"
  local composed="${root}/copy/composed.yaml"
  local merged_env="${root}/copy/merged.env"
  local added="${root}/copy/added.txt"
  local local_only="${root}/copy/local-only.txt"
  local activations="${root}/copy/activations.txt"
  local changes="${root}/copy/changes.txt"
  local inject_copy_failure=true
  local source_arg=""
  local destination_arg=""
  local render_log="${root}/render.log"

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR" "$remote"
  write_lines "${TARGET_DIR}/sentinel" 'copy-failure-must-not-mutate'
  write_lines "${TARGET_DIR}/app.env" 'APP_NAME=copy-failure'
  write_lines "${remote}/docker-compose.app.yaml" 'services: {}'
  write_lines "${remote}/.env" 'APP_NAME=copy-failure'
  write_lines "${remote}/README.md" 'fresh-source'
  builtin command cp -- "${remote}/docker-compose.app.yaml" "$composed"
  write_lines "$merged_env" 'APP_NAME=copy-failure'
  : > "$added"
  : > "$local_only"
  : > "$activations"
  : > "$changes"
  capture_source_sync_target_metadata "$TARGET_DIR"
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }
  cp() {
    source_arg="${@: -2:1}"
    destination_arg="${@: -1}"
    if [[ "$inject_copy_failure" == true && "$source_arg" == "${remote}/." && \
          "$destination_arg" == "${SOURCE_SYNC_STAGE}/" ]]; then
      inject_copy_failure=false
      return 75
    fi
    builtin command cp "$@"
  }
  if prepare_source_sync_stage "$remote" "$composed" "$merged_env" \
    "$added" "$local_only" "$activations" "$changes"; then
    return 1
  fi
  grep -Fxq 'phase=staging' "$SOURCE_SYNC_JOURNAL"
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
  cleanup_temporary_state
  [[ "$(<"${TARGET_DIR}/sentinel")" == copy-failure-must-not-mutate ]]
  [[ "$(<"${TARGET_DIR}/app.env")" == APP_NAME=copy-failure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  app="RenderFailure"
  remote="${root}/render/clone/${app}"
  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR" "$remote"
  write_lines "${TARGET_DIR}/sentinel" 'render-failure-must-not-mutate'
  write_lines "${TARGET_DIR}/docker-compose.app.yaml" 'services: {}'
  write_lines "${TARGET_DIR}/app.env" 'APP_NAME=render-failure'
  write_lines "${remote}/docker-compose.app.yaml" 'services: {}'
  write_lines "${remote}/.env" 'APP_NAME=render-failure'
  setup_cleanup_trap() { return 0; }
  validate_source_sync_dependencies() { return 0; }
  clone_app_source() {
    _TMPDIR="${root}/render/clone"
    SOURCE_SYNC_REMOTE_COMMIT="9999999999999999999999999999999999999999"
    SOURCE_SYNC_REMOTE_TREE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  render_compose_with_local_activations() { return 76; }
  if sync_app_source </dev/null >"$render_log" 2>&1; then
    return 1
  fi
  [[ "$(<"${TARGET_DIR}/sentinel")" == render-failure-must-not-mutate ]]
  [[ "$(<"${TARGET_DIR}/app.env")" == APP_NAME=render-failure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" && \
    -z "$SOURCE_SYNC_STAGE" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stage_and_successful_publish
#   Proves fresh source stæging, secret/schedule preservætion, runtime moves,
#   ænd æ source/configurætion bæckup thæt retæins env ænd secrets.
#ææææææææææææææææææææææææææææææææææ
test_stage_and_successful_publish() {
  local root="${TEST_ROOT}/publish"
  local app="PublishDemo"
  local remote="${root}/remote"
  local composed="${root}/composed.yaml"
  local merged_env="${root}/merged.env"
  local added="${root}/added.txt"
  local local_only="${root}/local-only.txt"
  local activations="${root}/activations.txt"
  local changes="${root}/changes.txt"
  local symlink_target="${root}/must-not-receive-upstream-seeds"
  local staged_path=""
  local configured_secret='configured-secret-marker'

  reset_source_sync_globals "$app"
  mkdir -p -- \
    "${TARGET_DIR}/.run.conf/logs" \
    "${TARGET_DIR}/secrets" \
    "${TARGET_DIR}/scripts" \
    "${TARGET_DIR}/appdata" \
    "${TARGET_DIR}/backup" \
    "${remote}/secrets" \
    "${remote}/scripts" \
    "${remote}/appdata" \
    "$symlink_target"
  chmod 0750 -- "$TARGET_DIR"
  write_lines "${TARGET_DIR}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:3'
  write_lines "${TARGET_DIR}/app.env" 'APP_NAME=old-app' 'APP_DIRECTORIES=appdata,backup'
  write_lines "${TARGET_DIR}/.env" 'APP_NAME=old-generated' 'APP_DIRECTORIES=appdata,backup'
  write_lines "${TARGET_DIR}/docker-compose.main.yaml" 'services: {} # old generæted Compose'
  write_lines "${TARGET_DIR}/local-only.txt" 'locæl-only rollbæck ærtefæct'
  write_lines "${TARGET_DIR}/scripts/backup.cron" 'old-custom-schedule'
  write_lines "${TARGET_DIR}/appdata/runtime.txt" 'runtime-data-marker'
  write_lines "${TARGET_DIR}/backup/archive.txt" 'backup-data-marker'
  write_lines "${TARGET_DIR}/.run.conf/logs/old.log" 'old-log-marker'
  write_lines "${TARGET_DIR}/.run.conf/.templates.lock" 'stale-template-revision'
  write_lines "${symlink_target}/sentinel" 'outside-stage-marker'
  ln -s -- "$symlink_target" "${TARGET_DIR}/.run.conf/source-sync-upstream-seeds"
  printf '%s' "$configured_secret" > "${TARGET_DIR}/secrets/APP_SECRET"
  chmod 0640 -- "${TARGET_DIR}/secrets/APP_SECRET"

  write_lines "${remote}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:4'
  write_lines "${remote}/.env" 'APP_NAME=upstream-app' 'APP_DIRECTORIES=appdata,backup'
  write_lines "${remote}/README.md" '# New source'
  write_lines "${remote}/scripts/backup.cron" 'upstream-schedule'
  write_lines "${remote}/appdata/upstream-seed.txt" 'upstream-seed-marker'
  printf '%s' 'CHANGE_ME' > "${remote}/secrets/APP_SECRET"
  printf '%s' 'CHANGE_ME' > "${remote}/secrets/NEW_UPSTREAM_SECRET"
  chmod 0644 -- "${remote}/docker-compose.app.yaml" "${remote}/secrets/NEW_UPSTREAM_SECRET"
  chmod 0640 -- "${TARGET_DIR}/app.env" "${TARGET_DIR}/scripts/backup.cron"

  cp -- "${remote}/docker-compose.app.yaml" "$composed"
  chmod 0600 -- "$composed"
  write_lines "$merged_env" 'APP_NAME=preserved-app' 'APP_DIRECTORIES=appdata,backup'
  chmod 0600 -- "$merged_env"
  write_lines "$added" $'active\tNEW_OPTION'
  write_lines "$local_only" 'LOCAL_OPTION'
  write_lines "$activations" '12'
  write_lines "$changes" $'file\tREADME.md' $'secret-path\tsecrets/NEW_UPSTREAM_SECRET'
  SOURCE_SYNC_RUNTIME_PATHS=(appdata backup)
  capture_source_sync_target_metadata "$TARGET_DIR"
  validate_source_sync_final_preflight() { return 0; }
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }

  prepare_source_sync_stage "$remote" "$composed" "$merged_env" \
    "$added" "$local_only" "$activations" "$changes"
  staged_path="$SOURCE_SYNC_STAGE"
  [[ -f "$SOURCE_SYNC_JOURNAL" && ! -L "$SOURCE_SYNC_JOURNAL" ]]
  [[ "$(stat -Lc '%u:%a:%h:%d' -- "$SOURCE_SYNC_JOURNAL")" == \
    "${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")" ]]
  [[ "$(stat -Lc '%u:%a' -- "${SCRIPT_DIR}/.run-source-sync.conf")" == "${EUID}:700" ]]
  [[ "$(stat -Lc '%u:%a' -- "${SCRIPT_DIR}/.run-source-sync.conf/transactions")" == \
    "${EUID}:700" ]]
  grep -Fxq 'version=4' "$SOURCE_SYNC_JOURNAL"
  grep -Fxq 'phase=staging' "$SOURCE_SYNC_JOURNAL"
  grep -Fxq "target_identity=${SOURCE_SYNC_TARGET_IDENTITY}" "$SOURCE_SYNC_JOURNAL"
  grep -Fxq "target_uid=${SOURCE_SYNC_TARGET_UID}" "$SOURCE_SYNC_JOURNAL"
  grep -Fxq "target_gid=${SOURCE_SYNC_TARGET_GID}" "$SOURCE_SYNC_JOURNAL"
  grep -Fxq "target_mode=${SOURCE_SYNC_TARGET_MODE}" "$SOURCE_SYNC_JOURNAL"
  [[ "$SOURCE_SYNC_STAGE_IDENTITY" == "$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")" ]]
  [[ "$SOURCE_SYNC_SEEDS_IDENTITY" == "$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")" ]]
  ! grep -Fq "$configured_secret" "$SOURCE_SYNC_JOURNAL"
  [[ "$(stat -c '%a' -- "$staged_path")" == 700 ]]
  [[ "$(stat -c '%a' -- "${staged_path}/docker-compose.app.yaml")" == 644 ]]
  [[ "$(stat -c '%a' -- "${staged_path}/app.env")" == 640 ]]
  [[ "$(stat -c '%a' -- "${staged_path}/secrets/APP_SECRET")" == 640 ]]
  [[ "$(<"${staged_path}/secrets/APP_SECRET")" == "$configured_secret" ]]
  [[ "$(<"${staged_path}/secrets/NEW_UPSTREAM_SECRET")" == CHANGE_ME ]]
  [[ "$(stat -c '%a' -- "${staged_path}/secrets/NEW_UPSTREAM_SECRET")" == 644 ]]
  [[ "$(<"${staged_path}/scripts/backup.cron")" == old-custom-schedule ]]
  [[ "$(stat -c '%a' -- "${staged_path}/scripts/backup.cron")" == 640 ]]
  [[ -f "${staged_path}/.run.conf/source-sync-upstream-seeds/appdata/upstream-seed.txt" ]]
  [[ ! -L "${staged_path}/.run.conf/source-sync-upstream-seeds" ]]
  [[ ! -e "${staged_path}/.run.conf/.templates.lock" ]]
  [[ ! -e "${staged_path}/.run.conf/logs" ]]
  [[ ! -e "${staged_path}/docker-compose.main.yaml" ]]
  [[ ! -e "${staged_path}/local-only.txt" ]]
  [[ ! -e "${symlink_target}/appdata" ]]
  [[ "$(<"${symlink_target}/sentinel")" == outside-stage-marker ]]
  [[ "$(stat -c '%a' -- "${staged_path}/.run.conf")" == 700 ]]
  [[ -f "${staged_path}/.run.conf/.source.lock" && ! -L "${staged_path}/.run.conf/.source.lock" ]]
  [[ -f "${staged_path}/.run.conf/source-sync-review.txt" && \
    ! -L "${staged_path}/.run.conf/source-sync-review.txt" ]]
  [[ ! -e "${staged_path}/appdata" ]]

  publish_source_sync_stage

  [[ "$(<"${TARGET_DIR}/README.md")" == '# New source' ]]
  [[ "$(stat -c '%a' -- "$TARGET_DIR")" == 750 ]]
  [[ "$(stat -c '%a' -- "$SOURCE_SYNC_BACKUP")" == 750 ]]
  [[ "$(<"${TARGET_DIR}/app.env")" == $'APP_NAME=preserved-app\nAPP_DIRECTORIES=appdata,backup' ]]
  [[ "$(stat -c '%a' -- "${TARGET_DIR}/app.env")" == 640 ]]
  [[ "$(stat -c '%a' -- "${TARGET_DIR}/docker-compose.app.yaml")" == 644 ]]
  [[ ! -e "${TARGET_DIR}/.env" ]]
  [[ ! -e "${TARGET_DIR}/docker-compose.main.yaml" ]]
  [[ ! -e "${TARGET_DIR}/local-only.txt" ]]
  [[ "$(<"${TARGET_DIR}/secrets/APP_SECRET")" == "$configured_secret" ]]
  [[ "$(stat -c '%a' -- "${TARGET_DIR}/secrets/APP_SECRET")" == 640 ]]
  [[ "$(<"${TARGET_DIR}/secrets/NEW_UPSTREAM_SECRET")" == CHANGE_ME ]]
  [[ "$(stat -c '%a' -- "${TARGET_DIR}/secrets/NEW_UPSTREAM_SECRET")" == 644 ]]
  [[ "$(<"${TARGET_DIR}/scripts/backup.cron")" == old-custom-schedule ]]
  [[ "$(stat -c '%a' -- "${TARGET_DIR}/scripts/backup.cron")" == 640 ]]
  [[ "$(<"${TARGET_DIR}/appdata/runtime.txt")" == runtime-data-marker ]]
  [[ "$(<"${TARGET_DIR}/backup/archive.txt")" == backup-data-marker ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/app.env")" == $'APP_NAME=old-app\nAPP_DIRECTORIES=appdata,backup' ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/.env")" == $'APP_NAME=old-generated\nAPP_DIRECTORIES=appdata,backup' ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/docker-compose.main.yaml")" == \
    'services: {} # old generæted Compose' ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/local-only.txt")" == \
    'locæl-only rollbæck ærtefæct' ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/secrets/APP_SECRET")" == "$configured_secret" ]]
  [[ "$(stat -c '%a' -- "${SOURCE_SYNC_BACKUP}/secrets/APP_SECRET")" == 640 ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/scripts/backup.cron")" == old-custom-schedule ]]
  [[ "$(stat -c '%a' -- "${SOURCE_SYNC_BACKUP}/scripts/backup.cron")" == 640 ]]
  [[ "$(stat -c '%a' -- "${SOURCE_SYNC_BACKUP}/app.env")" == 640 ]]
  [[ ! -e "${SOURCE_SYNC_BACKUP}/appdata" ]]
  [[ ! -e "${SOURCE_SYNC_BACKUP}/backup" ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/.run.conf/.templates.lock")" == stale-template-revision ]]
  [[ -L "${SOURCE_SYNC_BACKUP}/.run.conf/source-sync-upstream-seeds" ]]
  [[ ! -e "${TARGET_DIR}/.run.conf/.templates.lock" ]]
  [[ ! -e "${TARGET_DIR}/.run.conf/logs" ]]
  [[ ! -e "$staged_path" ]]
  [[ ! -e "$SOURCE_SYNC_SEEDS" ]]
  [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]
  [[ "$(stat -c '%a' -- "${TARGET_DIR}/.run.conf/source-sync-review.txt")" == 600 ]]
  grep -Fq 'NEW_ENV_ACTIVE=NEW_OPTION' "${TARGET_DIR}/.run.conf/source-sync-review.txt"
  grep -Fq 'LOCAL_ONLY_ENV=LOCAL_OPTION' "${TARGET_DIR}/.run.conf/source-sync-review.txt"
  grep -Fq 'SOURCE_CHANGE_SECRET_PATH=secrets/NEW_UPSTREAM_SECRET' \
    "${TARGET_DIR}/.run.conf/source-sync-review.txt"
  ! grep -Fq "$configured_secret" "${TARGET_DIR}/.run.conf/source-sync-review.txt"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_source_sync_command_failure_injection
#   Injects mv/sync/find/rmdir fæilures æt journælled v4 boundæries ænd proves
#   guarded rollbæck, resumæble rollforwærd, or retained recovery evidence.
#ææææææææææææææææææææææææææææææææææ
test_source_sync_command_failure_injection() {
  local inject_mv_failure=false
  local inject_journal_mv_failure=false
  local inject_runtime_mv_failure=false
  local inject_new_root_mv_failure=false
  local inject_rollback_mv_failure=false
  local inject_sync_failure=false
  local inject_find_failure=false
  local inject_rmdir_failures=0
  local journal_hash=""
  local source_arg=""
  local destination_arg=""
  local flushed_path=""
  local removal_path=""

  validate_source_sync_final_preflight() { return 0; }
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }

  prepare_source_sync_publication_fixture MvFailure
  inject_mv_failure=true
  mv() {
    source_arg="${@: -2:1}"
    destination_arg="${@: -1}"
    if [[ "$inject_journal_mv_failure" == true && \
          "$destination_arg" == "$SOURCE_SYNC_JOURNAL" ]]; then
      inject_journal_mv_failure=false
      return 70
    fi
    if [[ "$inject_mv_failure" == true && "$source_arg" == "$TARGET_DIR" && \
          "$destination_arg" == "$SOURCE_SYNC_BACKUP" ]]; then
      inject_mv_failure=false
      return 71
    fi
    if [[ "$inject_runtime_mv_failure" == true && \
          "$source_arg" == "${SOURCE_SYNC_BACKUP}/appdata" && \
          "$destination_arg" == "${SOURCE_SYNC_STAGE}/appdata" ]]; then
      inject_runtime_mv_failure=false
      return 72
    fi
    if [[ "$inject_new_root_mv_failure" == true && "$source_arg" == "$SOURCE_SYNC_STAGE" && \
          "$destination_arg" == "$TARGET_DIR" ]]; then
      inject_new_root_mv_failure=false
      return 73
    fi
    if [[ "$inject_rollback_mv_failure" == true && "$source_arg" == "$SOURCE_SYNC_BACKUP" && \
          "$destination_arg" == "$TARGET_DIR" ]]; then
      inject_rollback_mv_failure=false
      return 74
    fi
    command mv "$@"
  }
  if publish_source_sync_stage; then
    return 1
  fi
  grep -Fxq 'phase=renaming_old' "$SOURCE_SYNC_JOURNAL"
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-MvFailure ]]
  [[ -d "$SOURCE_SYNC_STAGE" && -d "$SOURCE_SYNC_SEEDS" ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-MvFailure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  prepare_source_sync_publication_fixture JournalMoveFailure
  inject_journal_mv_failure=true
  if publish_source_sync_stage; then
    return 1
  fi
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-JournalMoveFailure ]]
  [[ -d "$SOURCE_SYNC_STAGE" && -d "$SOURCE_SYNC_SEEDS" ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" ]]
  remove_safe_source_sync_tree "$SOURCE_SYNC_STAGE" stage
  remove_safe_source_sync_tree "$SOURCE_SYNC_SEEDS" seeds

  prepare_source_sync_publication_fixture RuntimeMoveFailure
  mkdir -p -- "${TARGET_DIR}/appdata"
  write_lines "${TARGET_DIR}/appdata/runtime.txt" 'runtime-survives-runtime-mv-failure'
  SOURCE_SYNC_RUNTIME_PATHS=(appdata)
  SOURCE_SYNC_RUNTIME_IDENTITIES[appdata]=$(stat -Lc '%d:%i' -- "${TARGET_DIR}/appdata")
  inject_runtime_mv_failure=true
  if publish_source_sync_stage; then
    return 1
  fi
  grep -Fxq 'phase=moving_data' "$SOURCE_SYNC_JOURNAL"
  [[ ! -e "$TARGET_DIR" && -d "${SOURCE_SYNC_BACKUP}/appdata" && \
    ! -e "${SOURCE_SYNC_STAGE}/appdata" ]]
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-RuntimeMoveFailure ]]
  [[ "$(<"${TARGET_DIR}/appdata/runtime.txt")" == runtime-survives-runtime-mv-failure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  prepare_source_sync_publication_fixture NewRootMoveFailure
  inject_new_root_mv_failure=true
  if publish_source_sync_stage; then
    return 1
  fi
  grep -Fxq 'phase=renaming_new' "$SOURCE_SYNC_JOURNAL"
  [[ ! -e "$TARGET_DIR" && -d "$SOURCE_SYNC_BACKUP" && -d "$SOURCE_SYNC_STAGE" ]]
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-NewRootMoveFailure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  prepare_source_sync_publication_fixture RollbackMoveFailure
  write_source_sync_journal moving_data
  command mv -T -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
  inject_rollback_mv_failure=true
  if recover_source_sync_transaction; then
    return 1
  fi
  [[ "$SOURCE_SYNC_PRESERVE" == true ]]
  grep -Fxq 'phase=renaming_old_back' "$SOURCE_SYNC_JOURNAL"
  [[ ! -e "$TARGET_DIR" && -d "$SOURCE_SYNC_BACKUP" && -d "$SOURCE_SYNC_STAGE" && \
    -d "$SOURCE_SYNC_SEEDS" ]]
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-RollbackMoveFailure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  prepare_source_sync_publication_fixture SyncFailure
  inject_sync_failure=true
  sync() {
    flushed_path="${@: -1}"
    if [[ "$inject_sync_failure" == true && "$flushed_path" == "$SCRIPT_DIR" && \
          ! -e "$TARGET_DIR" && -d "$SOURCE_SYNC_BACKUP" && -d "$SOURCE_SYNC_STAGE" ]]; then
      inject_sync_failure=false
      return 72
    fi
    command sync "$@"
  }
  if publish_source_sync_stage; then
    return 1
  fi
  grep -Fxq 'phase=renaming_old' "$SOURCE_SYNC_JOURNAL"
  [[ ! -e "$TARGET_DIR" && -d "$SOURCE_SYNC_BACKUP" && -d "$SOURCE_SYNC_STAGE" ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/sentinel")" == old-active-SyncFailure ]]
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active-SyncFailure ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  prepare_source_sync_publication_fixture FindFailure
  inject_find_failure=true
  find() {
    if [[ "$inject_find_failure" == true && "${1:-}" == -P && \
          "${2:-}" == "$SOURCE_SYNC_SEEDS" ]]; then
      inject_find_failure=false
      return 73
    fi
    command find "$@"
  }
  if publish_source_sync_stage; then
    return 1
  fi
  grep -Fxq 'phase=cleanup_commit' "$SOURCE_SYNC_JOURNAL"
  [[ "$(<"${TARGET_DIR}/sentinel")" == new-active-FindFailure ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/sentinel")" == old-active-FindFailure ]]
  [[ "$(<"${SOURCE_SYNC_SEEDS}/evidence")" == seed-evidence-FindFailure ]]
  recover_source_sync_transaction
  [[ "$SOURCE_SYNC_COMMITTED" == true ]]
  [[ "$(<"${TARGET_DIR}/sentinel")" == new-active-FindFailure ]]
  [[ -d "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]

  prepare_source_sync_publication_fixture RmdirFailure
  inject_rmdir_failures=2
  rmdir() {
    removal_path="${@: -1}"
    if (( inject_rmdir_failures > 0 )) && [[ "$removal_path" == "$SOURCE_SYNC_SEEDS" ]]; then
      inject_rmdir_failures=$((inject_rmdir_failures - 1))
      return 74
    fi
    command rmdir "$@"
  }
  if publish_source_sync_stage; then
    return 1
  fi
  grep -Fxq 'phase=cleanup_commit' "$SOURCE_SYNC_JOURNAL"
  [[ -d "$SOURCE_SYNC_SEEDS" ]]
  [[ -z "$(command find -P "$SOURCE_SYNC_SEEDS" -mindepth 1 -print -quit)" ]]
  journal_hash=$(sha256sum -- "$SOURCE_SYNC_JOURNAL" | awk '{print $1}')
  if recover_source_sync_transaction; then
    return 1
  fi
  [[ "$SOURCE_SYNC_PRESERVE" == true ]]
  [[ "$(sha256sum -- "$SOURCE_SYNC_JOURNAL" | awk '{print $1}')" == "$journal_hash" ]]
  grep -Fxq 'phase=cleanup_commit' "$SOURCE_SYNC_JOURNAL"
  [[ "$(<"${TARGET_DIR}/sentinel")" == new-active-RmdirFailure ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/sentinel")" == old-active-RmdirFailure ]]
  [[ -d "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_STAGE" ]]
  recover_source_sync_transaction
  [[ "$SOURCE_SYNC_COMMITTED" == true ]]
  [[ "$(<"${TARGET_DIR}/sentinel")" == new-active-RmdirFailure ]]
  [[ -d "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_STAGE" && \
    ! -e "$SOURCE_SYNC_SEEDS" && ! -e "$SOURCE_SYNC_JOURNAL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_source_sync_soft_signal_recovery
#   Delivers HUP, INT, ænd TERM æt rollback/rollforwærd v4 transitions ænd
#   proves the EXIT træp completes coherent recovery before signæl exit.
#ææææææææææææææææææææææææææææææææææ
test_source_sync_soft_signal_recovery() {
  local -a signals=(HUP INT TERM)
  local -a phases=(renaming_old moving_data published)
  local -a statuses=(129 130 143)
  local index=""
  local signal_name=""
  local phase=""
  local app=""
  local status=""
  local output=""
  local target=""
  local backup=""
  local stage=""
  local seeds=""
  local journal=""

  export -f source_sync_transition_child_body
  for index in "${!signals[@]}"; do
    signal_name="${signals[$index]}"
    phase="${phases[$index]}"
    app="SoftSignal_${signal_name}"
    output="${TEST_RESULTS}/soft-signal-${signal_name}.child.out"
    target="${SCRIPT_DIR}/${app}"
    backup="${target}_backup"
    stage="${SCRIPT_DIR}/.${app}.source-sync.SIGNAL"
    seeds="${stage}.seeds"
    journal="${SCRIPT_DIR}/.run-source-sync.conf/transactions/${app}.state"

    if TRANSITION_LIBRARY="$TEST_RUN_LIBRARY" TRANSITION_APP="$app" \
      TRANSITION_PHASE="$phase" TRANSITION_MODE=soft TRANSITION_SIGNAL="$signal_name" \
      bash -c 'source_sync_transition_child_body' >"$output" 2>&1; then
      return 1
    else
      status=$?
    fi
    [[ "$status" == "${statuses[$index]}" ]]
    [[ ! -e "$journal" && ! -e "$stage" && ! -e "$seeds" ]]
    if [[ "$phase" == published ]]; then
      [[ "$(<"${target}/sentinel")" == new-active-published ]]
      [[ "$(<"${backup}/sentinel")" == old-active-published ]]
    else
      [[ "$(<"${target}/sentinel")" == "old-active-${phase}" ]]
      [[ ! -e "$backup" ]]
      if [[ "$phase" == moving_data ]]; then
        [[ "$(<"${target}/appdata/runtime.txt")" == runtime-marker ]]
      fi
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_source_sync_sigkill_recovery
#   SIGKILLs stopped children with duræble moving_data or published journæls,
#   proves evidence survives, then performs guarded next-process recovery.
#ææææææææææææææææææææææææææææææææææ
test_source_sync_sigkill_recovery() {
  local phase=""
  local app=""
  local ready=""
  local output=""
  local holder_pid=""
  local killed_status=""
  local target=""
  local backup=""
  local stage=""

  export -f source_sync_transition_child_body
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }

  for phase in moving_data published; do
    app="Sigkill_${phase}"
    ready="${TEST_RESULTS}/sigkill-${phase}.ready"
    output="${TEST_RESULTS}/sigkill-${phase}.child.out"
    target="${SCRIPT_DIR}/${app}"
    backup="${target}_backup"
    stage="${SCRIPT_DIR}/.${app}.source-sync.SIGNAL"
    rm -f -- "$ready"
    TRANSITION_LIBRARY="$TEST_RUN_LIBRARY" TRANSITION_APP="$app" \
      TRANSITION_PHASE="$phase" TRANSITION_MODE=stop TRANSITION_READY="$ready" \
      bash -c 'source_sync_transition_child_body' >"$output" 2>&1 &
    holder_pid=$!
    if ! wait_for_test_marker "$ready"; then
      kill -KILL "$holder_pid" 2>/dev/null || true
      wait "$holder_pid" 2>/dev/null || true
      return 1
    fi
    kill -KILL "$holder_pid"
    if wait "$holder_pid" 2>/dev/null; then
      return 1
    else
      killed_status=$?
    fi
    [[ "$killed_status" == 137 ]]

    reset_source_sync_globals "$app"
    [[ -f "$SOURCE_SYNC_JOURNAL" && ! -L "$SOURCE_SYNC_JOURNAL" ]]
    [[ "$(stat -Lc '%u:%a:%h:%d' -- "$SOURCE_SYNC_JOURNAL")" == \
      "${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")" ]]
    grep -Fxq "phase=${phase}" "$SOURCE_SYNC_JOURNAL"
    if [[ "$phase" == moving_data ]]; then
      [[ ! -e "$target" && -d "$backup" && -d "${stage}/appdata" ]]
    else
      [[ -d "$target" && -d "$backup" && ! -e "$stage" ]]
    fi

    recover_source_sync_transaction
    [[ ! -e "$SOURCE_SYNC_JOURNAL" && ! -e "$SOURCE_SYNC_STAGE" && \
      ! -e "$SOURCE_SYNC_SEEDS" ]]
    if [[ "$phase" == moving_data ]]; then
      [[ "$SOURCE_SYNC_COMMITTED" == false ]]
      [[ "$(<"${target}/sentinel")" == old-active-moving_data ]]
      [[ "$(<"${target}/appdata/runtime.txt")" == runtime-marker ]]
      [[ ! -e "$backup" ]]
    else
      [[ "$SOURCE_SYNC_COMMITTED" == true ]]
      [[ "$(<"${target}/sentinel")" == new-active-published ]]
      [[ "$(<"${backup}/sentinel")" == old-active-published ]]
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_backup_collision_is_non_mutating
#   Proves æ pre-existing _backup directory blocks publicætion without
#   chænging the current, stæged, or bæckup trees.
#ææææææææææææææææææææææææææææææææææ
test_backup_collision_is_non_mutating() {
  local app="CollisionDemo"

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.COLLIDE"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS"
  write_lines "${TARGET_DIR}/sentinel" 'current-tree'
  write_lines "${SOURCE_SYNC_BACKUP}/sentinel" 'backup-tree'
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" 'stage-tree'

  if publish_source_sync_stage; then
    return 1
  fi
  [[ "$(<"${TARGET_DIR}/sentinel")" == current-tree ]]
  [[ "$(<"${SOURCE_SYNC_BACKUP}/sentinel")" == backup-tree ]]
  [[ "$(<"${SOURCE_SYNC_STAGE}/sentinel")" == stage-tree ]]
  [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_dry_run_and_confirmation_rejection
#   Proves dry-run ænd EOF/mismætched confirmætion never enter stæging
#   or publicætion, while no environment vælue is disclosed.
#ææææææææææææææææææææææææææææææææææ
test_dry_run_and_confirmation_rejection() {
  local root="${TEST_ROOT}/confirmation"
  local app="ConfirmationDemo"
  local remote_root="${root}/clone/${app}"
  local mutation_marker="${root}/mutation"
  local dry_log="${root}/dry.log"
  local eof_log="${root}/eof.log"
  local empty_log="${root}/empty.log"
  local mismatch_log="${root}/mismatch.log"
  local exact_log="${root}/exact.log"
  local event_log="${root}/events.log"
  local dependency_validations=0
  local legacy_dependency_calls=0
  local install_dependency_calls=0
  local release_resolver_calls=0
  local yq_installer_calls=0
  local latest_yq_calls=0
  local pre_consent_yq_parses=0
  local post_consent_yq_parses=0
  local prepare_calls=0
  local publish_calls=0
  local latest_verified=false
  local plan_log=""

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR" "$remote_root"
  write_lines "${TARGET_DIR}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:3'
  write_lines "${TARGET_DIR}/app.env" 'TOKEN=do-not-print-env-value'
  write_lines "${remote_root}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:4'
  write_lines "${remote_root}/.env" 'TOKEN=remote-default'

  setup_cleanup_trap() { return 0; }
  check_dependencies() {
    legacy_dependency_calls=$((legacy_dependency_calls + 1))
    return 91
  }
  install_dependency() {
    install_dependency_calls=$((install_dependency_calls + 1))
    return 92
  }
  resolve_latest_yq_tag() {
    release_resolver_calls=$((release_resolver_calls + 1))
    return 93
  }
  install_latest_yq() {
    yq_installer_calls=$((yq_installer_calls + 1))
    return 94
  }
  validate_source_sync_dependencies() {
    dependency_validations=$((dependency_validations + 1))
    return 0
  }
  ensure_latest_yq() {
    latest_yq_calls=$((latest_yq_calls + 1))
    latest_verified=true
    printf '%s\n' 'ensure-latest' >> "$event_log"
    return 0
  }
  yq() {
    if [[ "$latest_verified" == true ]]; then
      post_consent_yq_parses=$((post_consent_yq_parses + 1))
      printf '%s\n' 'post-yq' >> "$event_log"
    else
      pre_consent_yq_parses=$((pre_consent_yq_parses + 1))
      printf '%s\n' 'pre-yq' >> "$event_log"
    fi
    command yq "$@"
  }
  clone_app_source() {
    _TMPDIR="${root}/clone"
    SOURCE_SYNC_REMOTE_COMMIT="3333333333333333333333333333333333333333"
    SOURCE_SYNC_REMOTE_TREE="4444444444444444444444444444444444444444"
  }
  collect_source_path_changes() {
    : > "$2"
  }
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_project_stopped() { return 0; }
  collect_source_sync_runtime_paths() { SOURCE_SYNC_RUNTIME_PATHS=(); }
  prepare_source_sync_stage() {
    prepare_calls=$((prepare_calls + 1))
    printf '%s\n' 'prepare' >> "$event_log"
    : > "$mutation_marker"
  }
  publish_source_sync_stage() {
    publish_calls=$((publish_calls + 1))
    printf '%s\n' 'publish' >> "$event_log"
    : > "$mutation_marker"
  }

  : > "$event_log"
  DRY_RUN=true
  sync_app_source </dev/null >"$dry_log" 2>&1
  [[ "$dependency_validations" == 1 ]]
  [[ "$legacy_dependency_calls" == 0 && "$install_dependency_calls" == 0 && \
    "$release_resolver_calls" == 0 && "$yq_installer_calls" == 0 && \
    "$latest_yq_calls" == 0 && "$post_consent_yq_parses" == 0 ]]
  [[ ! -e "$mutation_marker" ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  ! grep -Fq 'do-not-print-env-value' "$dry_log"

  DRY_RUN=false
  if sync_app_source </dev/null >"$eof_log" 2>&1; then
    return 1
  fi
  [[ "$dependency_validations" == 2 && "$latest_yq_calls" == 0 ]]
  [[ ! -e "$mutation_marker" ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  ! grep -Fq 'do-not-print-env-value' "$eof_log"

  if sync_app_source <<< '' >"$empty_log" 2>&1; then
    return 1
  fi
  [[ "$dependency_validations" == 3 && "$latest_yq_calls" == 0 ]]
  [[ ! -e "$mutation_marker" && ! -e "$SOURCE_SYNC_BACKUP" ]]
  ! grep -Fq 'do-not-print-env-value' "$empty_log"

  if sync_app_source <<< 'NO' >"$mismatch_log" 2>&1; then
    return 1
  fi
  [[ "$dependency_validations" == 4 && "$latest_yq_calls" == 0 ]]
  [[ ! -e "$mutation_marker" ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  ! grep -Fq 'do-not-print-env-value' "$mismatch_log"

  [[ "$legacy_dependency_calls" == 0 && "$install_dependency_calls" == 0 && \
    "$release_resolver_calls" == 0 && "$yq_installer_calls" == 0 && \
    "$prepare_calls" == 0 && "$publish_calls" == 0 ]]
  : > "$event_log"
  sync_app_source <<< "SYNC ${app}" >"$exact_log" 2>&1
  [[ "$dependency_validations" == 5 ]]
  [[ "$latest_yq_calls" == 1 && "$post_consent_yq_parses" == 1 ]]
  [[ "$legacy_dependency_calls" == 0 && "$install_dependency_calls" == 0 && \
    "$release_resolver_calls" == 0 && "$yq_installer_calls" == 0 ]]
  [[ "$prepare_calls" == 1 && "$publish_calls" == 1 && -f "$mutation_marker" ]]
  [[ "$(<"$event_log")" == $'pre-yq\nensure-latest\npost-yq\nprepare\npublish' ]]
  [[ "$pre_consent_yq_parses" == 5 ]]
  for plan_log in "$dry_log" "$eof_log" "$empty_log" "$mismatch_log" "$exact_log"; do
    grep -Fq "Bæckup plæn: renæme '${app}' to '${app}_backup'" "$plan_log"
    grep -Fq "Environment plæn: publish the structurælly migræted app.env only" "$plan_log"
    grep -Fq "generæted Compose stæy in '${app}_backup'" "$plan_log"
    grep -Fq "Regenerætion plæn: keep the fresh Æpp without generæted .env/Compose" "$plan_log"
    grep -Fq "Lifecycle plæn: preserve secrets/schedule" "$plan_log"
    grep -Fq "leæve the Compose project stopped" "$plan_log"
    ! grep -Fq 'do-not-print-env-value' "$plan_log"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_exact_confirmation_refreshes_yq
#   Proves exæct SYNC consent runs the reæl ensure_latest_yq control flow,
#   invokes its resolver/instæller, then re-pærses before deployment mutætion.
#ææææææææææææææææææææææææææææææææææ
test_exact_confirmation_refreshes_yq() {
  local root="${TEST_ROOT}/exact-yq-refresh"
  local app="ExactYqRefresh"
  local remote_root="${root}/clone/${app}"
  local fake_bin="${root}/bin"
  local fake_yq="${fake_bin}/yq"
  local version_file="${root}/yq-version"
  local installed_marker="${root}/yq-installed"
  local event_log="${root}/events.log"
  local decision_log="${root}/decision.log"
  local real_yq_path=""
  local installer_calls=0
  local prepare_calls=0
  local publish_calls=0

  real_yq_path=$(command -v yq)
  [[ -n "$real_yq_path" && -x "$real_yq_path" ]]
  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR" "$remote_root" "$fake_bin"
  write_lines "${TARGET_DIR}/docker-compose.app.yaml" \
    'services:' '  app:' '    image: alpine:3'
  write_lines "${TARGET_DIR}/app.env" 'APP_NAME=exact-yq-refresh'
  write_lines "${remote_root}/docker-compose.app.yaml" \
    'services:' '  app:' '    image: alpine:4'
  write_lines "${remote_root}/.env" 'APP_NAME=exact-yq-refresh'
  write_lines "$version_file" 'v4.1.0'
  : > "$event_log"
  write_lines "$fake_yq" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == --version ]]; then' \
    '  printf "yq (https://github.com/mikefarah/yq/) version %s\n" "$(<"$SOURCE_SYNC_YQ_VERSION_FILE")"' \
    '  exit 0' \
    'fi' \
    'if [[ -e "$SOURCE_SYNC_YQ_INSTALLED_MARKER" ]]; then' \
    '  printf "%s\n" post-yq >> "$SOURCE_SYNC_YQ_EVENT_LOG"' \
    'else' \
    '  printf "%s\n" pre-yq >> "$SOURCE_SYNC_YQ_EVENT_LOG"' \
    'fi' \
    'exec "$SOURCE_SYNC_REAL_YQ" "$@"'
  chmod 0755 -- "$fake_yq"
  export SOURCE_SYNC_YQ_VERSION_FILE="$version_file"
  export SOURCE_SYNC_YQ_INSTALLED_MARKER="$installed_marker"
  export SOURCE_SYNC_YQ_EVENT_LOG="$event_log"
  export SOURCE_SYNC_REAL_YQ="$real_yq_path"
  PATH="${fake_bin}:${PATH}"
  export PATH
  hash -r

  setup_cleanup_trap() { return 0; }
  validate_source_sync_dependencies() { return 0; }
  clone_app_source() {
    _TMPDIR="${root}/clone"
    SOURCE_SYNC_REMOTE_COMMIT="9999999999999999999999999999999999999999"
    SOURCE_SYNC_REMOTE_TREE="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  collect_source_path_changes() { : > "$2"; }
  collect_source_sync_runtime_paths() { SOURCE_SYNC_RUNTIME_PATHS=(); }
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_project_stopped() { return 0; }
  resolve_latest_yq_tag() {
    printf '%s\n' resolve-latest >> "$event_log"
    printf '%s\n' 'v4.99.0'
  }
  install_latest_yq() {
    installer_calls=$((installer_calls + 1))
    [[ "$1" == "$fake_yq" && "$2" == v4.99.0 ]]
    printf '%s\n' install-yq >> "$event_log"
    write_lines "$version_file" 'v4.99.0'
    : > "$installed_marker"
  }
  install_dependency() { return 91; }
  prepare_source_sync_stage() {
    prepare_calls=$((prepare_calls + 1))
    printf '%s\n' prepare >> "$event_log"
  }
  publish_source_sync_stage() {
    publish_calls=$((publish_calls + 1))
    printf '%s\n' publish >> "$event_log"
  }

  sync_app_source <<< "SYNC ${app}" >"$decision_log" 2>&1

  [[ "$installer_calls" == 1 && "$prepare_calls" == 1 && "$publish_calls" == 1 ]]
  [[ "$(<"$version_file")" == v4.99.0 && -f "$installed_marker" ]]
  [[ "$(<"$event_log")" == \
    $'pre-yq\nresolve-latest\ninstall-yq\npost-yq\nprepare\npublish' ]]
  grep -Fq 'Mike Færæh yq is current (v4.99.0)' "$decision_log"
  [[ ! -e "$SOURCE_SYNC_BACKUP" && ! -e "$SOURCE_SYNC_JOURNAL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_initial_local_only_key_requires_review
#   Proves æ missing source baseline plus æ locæl-only key cænnot be reported
#   æs æn origin/mæin mætch before the first source synchronisætion.
#ææææææææææææææææææææææææææææææææææ
test_initial_local_only_key_requires_review() {
  local root="${TEST_ROOT}/initial-local-only"
  local app="InitialLocalOnly"
  local remote_root="${root}/clone/${app}"
  local decision_log="${root}/decision.log"

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR" "$remote_root"
  write_lines "${TARGET_DIR}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:3'
  write_lines "${TARGET_DIR}/app.env" \
    'COMMON=deployment-value' \
    'REMOVED_UPSTREAM=do-not-print-removed-value'
  write_lines "${remote_root}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:3'
  write_lines "${remote_root}/.env" 'COMMON=remote-default'

  setup_cleanup_trap() { return 0; }
  check_dependencies() { return 0; }
  validate_source_sync_dependencies() { return 0; }
  clone_app_source() {
    _TMPDIR="${root}/clone"
    SOURCE_SYNC_REMOTE_COMMIT="5555555555555555555555555555555555555555"
    SOURCE_SYNC_REMOTE_TREE="6666666666666666666666666666666666666666"
  }
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_project_stopped() { return 0; }

  DRY_RUN=true
  sync_app_source </dev/null >"$decision_log" 2>&1
  grep -Fq "would require 'SYNC ${app}'" "$decision_log"
  ! grep -Fq 'ælreædy mætches origin/main' "$decision_log"
  ! grep -Fq 'do-not-print-removed-value' "$decision_log"
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  [[ ! -e "${TARGET_DIR}/.run.conf" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_runtime_roots_union_from_both_env_files
#   Proves runtime discovery unions æuthoritætive app.env with æ stæle
#   generæted .env so neither declæred top-level dætæ root is omitted.
#ææææææææææææææææææææææææææææææææææ
test_runtime_roots_union_from_both_env_files() {
  local root="${TEST_ROOT}/runtime-union"
  local app="RuntimeUnion"
  local remote_root="${root}/clone/${app}"
  local captured="${root}/captured-runtime-roots.txt"

  reset_source_sync_globals "$app"
  mkdir -p -- \
    "${TARGET_DIR}/primary-data/app" \
    "${TARGET_DIR}/database-data/db" \
    "$remote_root"
  write_lines "${TARGET_DIR}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:3'
  write_lines "${TARGET_DIR}/app.env" \
    'APP_NAME=runtime-union' \
    'APP_DIRECTORIES=primary-data/app'
  write_lines "${TARGET_DIR}/.env" \
    'APP_NAME=runtime-union' \
    'DATABASE_DIRECTORIES=database-data/db'
  write_lines "${remote_root}/docker-compose.app.yaml" 'services:' '  app:' '    image: alpine:4'
  write_lines "${remote_root}/.env" \
    'APP_NAME=runtime-union' \
    'APP_DIRECTORIES=primary-data/app'

  setup_cleanup_trap() { return 0; }
  check_dependencies() { return 0; }
  validate_source_sync_dependencies() { return 0; }
  ensure_latest_yq() { return 0; }
  clone_app_source() {
    _TMPDIR="${root}/clone"
    SOURCE_SYNC_REMOTE_COMMIT="7777777777777777777777777777777777777777"
    SOURCE_SYNC_REMOTE_TREE="8888888888888888888888888888888888888888"
  }
  collect_source_path_changes() { : > "$2"; }
  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_project_stopped() { return 0; }
  prepare_source_sync_stage() {
    printf '%s\n' "${SOURCE_SYNC_RUNTIME_PATHS[@]}" | LC_ALL=C sort > "$captured"
  }
  publish_source_sync_stage() { return 0; }

  printf 'SYNC %s\n' "$app" | sync_app_source >"${root}/sync.log" 2>&1
  [[ "$(<"$captured")" == $'database-data\nprimary-data' ]]
  [[ -d "${TARGET_DIR}/primary-data" ]]
  [[ -d "${TARGET_DIR}/database-data" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- JOURNÆL ROLLBÆCK ÆND RECOVERY REGRESSIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_recovery_state_matrix
#   Proves pre-renæme cleænup, rollbæck between renæmes with runtime
#   restorætion, ænd every duræble v4 rollforwærd/rollbæck phæse.
#ææææææææææææææææææææææææææææææææææ
test_recovery_state_matrix() {
  local app="PreparedRecovery"
  local journal_hash=""
  local phase=""

  validate_source_sync_no_mounts() { return 0; }
  validate_source_sync_no_running_writers() { return 0; }

  reset_source_sync_globals "$app"
  mkdir -p -- "$TARGET_DIR"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.PREPARED"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS"
  write_lines "${TARGET_DIR}/sentinel" 'old-active'
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" 'new-staged'
  capture_source_sync_target_metadata "$TARGET_DIR"
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  write_source_sync_journal prepared
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active ]]
  [[ ! -e "$SOURCE_SYNC_STAGE" ]]
  [[ ! -e "$SOURCE_SYNC_SEEDS" ]]
  [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]

  app="BetweenRenameRecovery"
  reset_source_sync_globals "$app"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.BETWEEN"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  SOURCE_SYNC_RUNTIME_PATHS=(appdata)
  mkdir -p -- \
    "$SOURCE_SYNC_BACKUP/secrets" \
    "$SOURCE_SYNC_STAGE/appdata" \
    "$SOURCE_SYNC_SEEDS"
  write_lines "${SOURCE_SYNC_BACKUP}/app.env" 'APP_NAME=old-source'
  write_lines "${SOURCE_SYNC_BACKUP}/secrets/APP_SECRET" 'old-secret'
  write_lines "${SOURCE_SYNC_STAGE}/new-source" 'new-source'
  write_lines "${SOURCE_SYNC_STAGE}/appdata/runtime.txt" 'runtime-return-marker'
  capture_source_sync_target_metadata "$SOURCE_SYNC_BACKUP"
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  write_source_sync_journal moving_data
  recover_source_sync_transaction
  [[ "$(<"${TARGET_DIR}/app.env")" == APP_NAME=old-source ]]
  [[ "$(<"${TARGET_DIR}/secrets/APP_SECRET")" == old-secret ]]
  [[ "$(<"${TARGET_DIR}/appdata/runtime.txt")" == runtime-return-marker ]]
  [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
  [[ ! -e "$SOURCE_SYNC_STAGE" ]]
  [[ ! -e "$SOURCE_SYNC_SEEDS" ]]
  [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]

  for phase in renaming_new published cleanup_commit committed; do
    app="Rollforward_${phase}"
    reset_source_sync_globals "$app"
    SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.ROLLFORWARD"
    SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
    mkdir -p -- "$TARGET_DIR" "${SOURCE_SYNC_STAGE}/.run.conf" "$SOURCE_SYNC_SEEDS"
    write_lines "${TARGET_DIR}/sentinel" "old-backup-${phase}"
    write_lines "${SOURCE_SYNC_STAGE}/sentinel" "new-active-${phase}"
    capture_source_sync_target_metadata "$TARGET_DIR"
    SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
    SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
    write_source_sync_lock "$SOURCE_SYNC_STAGE"
    mv -T -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
    mv -T -- "$SOURCE_SYNC_STAGE" "$TARGET_DIR"
    if [[ "$phase" == cleanup_commit || "$phase" == committed ]]; then
      rmdir -- "$SOURCE_SYNC_SEEDS"
    fi
    write_source_sync_journal "$phase"
    recover_source_sync_transaction
    [[ "$SOURCE_SYNC_COMMITTED" == true ]]
    [[ "$(<"${TARGET_DIR}/sentinel")" == "new-active-${phase}" ]]
    [[ "$(<"${SOURCE_SYNC_BACKUP}/sentinel")" == "old-backup-${phase}" ]]
    [[ ! -e "$SOURCE_SYNC_STAGE" ]]
    [[ ! -e "$SOURCE_SYNC_SEEDS" ]]
    [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]
  done

  for phase in rolling_back renaming_old_back rollback_cleanup; do
    app="Rollback_${phase}"
    reset_source_sync_globals "$app"
    SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.ROLLBACK"
    SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
    mkdir -p -- "$TARGET_DIR" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS"
    write_lines "${TARGET_DIR}/sentinel" "old-active-${phase}"
    write_lines "${SOURCE_SYNC_STAGE}/sentinel" "discard-staged-${phase}"
    capture_source_sync_target_metadata "$TARGET_DIR"
    SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
    SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
    mv -T -- "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"
    if [[ "$phase" == renaming_old_back || "$phase" == rollback_cleanup ]]; then
      mv -T -- "$SOURCE_SYNC_BACKUP" "$TARGET_DIR"
    fi
    if [[ "$phase" == rollback_cleanup ]]; then
      rmdir -- "$SOURCE_SYNC_SEEDS"
    fi
    write_source_sync_journal "$phase"
    recover_source_sync_transaction
    [[ "$SOURCE_SYNC_COMMITTED" == false ]]
    [[ "$(<"${TARGET_DIR}/sentinel")" == "old-active-${phase}" ]]
    [[ ! -e "$SOURCE_SYNC_BACKUP" ]]
    [[ ! -e "$SOURCE_SYNC_STAGE" ]]
    [[ ! -e "$SOURCE_SYNC_SEEDS" ]]
    [[ ! -e "$SOURCE_SYNC_JOURNAL" ]]
  done

  app="DryRunRecovery"
  reset_source_sync_globals "$app"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.DRYRUN"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$TARGET_DIR" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS"
  write_lines "${TARGET_DIR}/sentinel" 'old-active'
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" 'new-staged'
  capture_source_sync_target_metadata "$TARGET_DIR"
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  write_source_sync_journal prepared
  journal_hash=$(sha256sum -- "$SOURCE_SYNC_JOURNAL")
  DRY_RUN=true
  if recover_source_sync_transaction; then
    return 1
  fi
  [[ "$SOURCE_SYNC_PRESERVE" == true ]]
  [[ "$(sha256sum -- "$SOURCE_SYNC_JOURNAL")" == "$journal_hash" ]]
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active ]]
  [[ "$(<"${SOURCE_SYNC_STAGE}/sentinel")" == new-staged ]]
  [[ -d "$SOURCE_SYNC_SEEDS" ]]
  DRY_RUN=false

  app="IdentityDriftRecovery"
  reset_source_sync_globals "$app"
  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/.${app}.source-sync.DRIFT"
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  mkdir -p -- "$TARGET_DIR" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS"
  write_lines "${TARGET_DIR}/sentinel" 'old-active'
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" 'journalled-stage'
  capture_source_sync_target_metadata "$TARGET_DIR"
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE")
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS")
  write_source_sync_journal prepared
  mv -T -- "$SOURCE_SYNC_STAGE" "${SOURCE_SYNC_STAGE}.original"
  mkdir -- "$SOURCE_SYNC_STAGE"
  write_lines "${SOURCE_SYNC_STAGE}/sentinel" 'foreign-replacement-stage'
  if recover_source_sync_transaction; then
    return 1
  fi
  [[ "$SOURCE_SYNC_PRESERVE" == true ]]
  [[ "$(<"${TARGET_DIR}/sentinel")" == old-active ]]
  [[ "$(<"${SOURCE_SYNC_STAGE}/sentinel")" == foreign-replacement-stage ]]
  [[ "$(<"${SOURCE_SYNC_STAGE}.original/sentinel")" == journalled-stage ]]
  [[ -f "$SOURCE_SYNC_JOURNAL" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TEST EXECUTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
run_case repository-descriptor-locking test_repository_descriptor_locking
run_case external-source-sync-logging test_external_source_sync_logging
run_case local-git-source-resolution test_local_git_source_resolution
run_case first-normal-merge-source-revision test_first_normal_merge_uses_source_revision
run_case end-to-end-local-git-sync test_end_to_end_local_git_sync
run_case full-source-sync-noop test_sync_app_source_noop
run_case compose-activation-real-drift test_compose_activation_and_real_drift
run_case env-authority-merge-sentinel test_env_authority_merge_and_sentinel
run_case env-alternatives-rejections test_env_alternative_states_and_rejections
run_case missing-compose-stopped-preflight test_missing_compose_stopped_preflight
run_case source-sync-mount-rejection test_source_sync_mount_rejection
run_case dependency-preflight test_source_sync_dependency_preflight
run_case final-preflight-stage-identity test_final_preflight_stage_identity_drift
run_case prepublication-failure-injection test_source_sync_prepublication_failure_injection
run_case stage-successful-publish test_stage_and_successful_publish
run_case command-failure-injection test_source_sync_command_failure_injection
run_case soft-signal-recovery test_source_sync_soft_signal_recovery
run_case sigkill-recovery test_source_sync_sigkill_recovery
run_case backup-collision test_backup_collision_is_non_mutating
run_case dry-run-confirmation-rejection test_dry_run_and_confirmation_rejection
run_case exact-confirmation-yq-refresh test_exact_confirmation_refreshes_yq
run_case initial-local-only-review test_initial_local_only_key_requires_review
run_case runtime-roots-env-union test_runtime_roots_union_from_both_env_files
run_case recovery-state-matrix test_recovery_state_matrix

printf '\nSource-sync regression summary: %d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  exit 1
fi
