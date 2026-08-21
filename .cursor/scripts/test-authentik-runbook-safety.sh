#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" \
  || { printf 'FAIL authentik-runbook-safety: script directory resolution failed\n' >&2; exit 1; }
readonly TEST_SCRIPT_DIR
TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)" \
  || { printf 'FAIL authentik-runbook-safety: repository root resolution failed\n' >&2; exit 1; }
readonly TEST_REPO_ROOT
readonly README_FILE="${TEST_REPO_ROOT}/Authentik/README.md"
TEST_ROOT=''
TEST_ROOT_ID=''
TEST_ROOT_FD=''
TEST_ROOT_PARENT="$(readlink -e -- "${TMPDIR:-/tmp}")" \
  || { printf 'FAIL authentik-runbook-safety: temporary parent resolution failed\n' >&2; exit 1; }
readonly TEST_ROOT_PARENT
exec {TEST_ROOT_PARENT_FD}<"$TEST_ROOT_PARENT"
readonly TEST_ROOT_PARENT_ID="$(stat -Lc '%d:%i' -- "$TEST_ROOT_PARENT")"
[[ "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${TEST_ROOT_PARENT_FD}")" == \
  "$TEST_ROOT_PARENT_ID" ]]
SUITE_COMPLETED=false

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the identity-pinned privæte fixture tree.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local original_status=$?
  local cleanup_status=0
  local final_status="$original_status"

  trap - EXIT
  trap '' HUP INT TERM
  set +e
  if [[ -n "$TEST_ROOT" && ( -e "$TEST_ROOT" || -L "$TEST_ROOT" ) ]]; then
    if [[ -n "$TEST_ROOT_ID" && "$TEST_ROOT_FD" =~ ^[0-9]+$ && \
      -d "$TEST_ROOT" && ! -L "$TEST_ROOT" && \
      "$(stat -Lc '%d:%i' -- "$TEST_ROOT")" == "$TEST_ROOT_ID" && \
      "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${TEST_ROOT_FD}")" == \
        "$TEST_ROOT_ID" && \
      "$(stat -Lc '%d:%i' -- "$TEST_ROOT_PARENT")" == \
        "$TEST_ROOT_PARENT_ID" && \
      "$(stat -Lc '%d:%i' -- \
        "/proc/${BASHPID}/fd/${TEST_ROOT_PARENT_FD}")" == \
        "$TEST_ROOT_PARENT_ID" ]]; then
      if ! (
        cd -- "/proc/${BASHPID}/fd/${TEST_ROOT_FD}" &&
          find -P . -xdev -depth -mindepth 1 -delete
      ); then
        cleanup_status=1
      fi
      if [[ "$cleanup_status" == 0 && -d "$TEST_ROOT" && \
        ! -L "$TEST_ROOT" && \
        "$(stat -Lc '%d:%i' -- "$TEST_ROOT")" == "$TEST_ROOT_ID" && \
        "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${TEST_ROOT_FD}")" == \
          "$TEST_ROOT_ID" ]]; then
        rmdir -- "$TEST_ROOT" || cleanup_status=1
      fi
      [[ "$cleanup_status" != 0 || \
        ( ! -e "$TEST_ROOT" && ! -L "$TEST_ROOT" ) ]] || cleanup_status=1
    else
      printf 'FAIL authentik-runbook-safety: fixture identity drift; preserving %q\n' \
        "$TEST_ROOT" >&2
      cleanup_status=1
    fi
  fi
  if [[ "$TEST_ROOT_FD" =~ ^[0-9]+$ && \
    -e "/proc/${BASHPID}/fd/${TEST_ROOT_FD}" ]]; then
    exec {TEST_ROOT_FD}<&-
  fi
  exec {TEST_ROOT_PARENT_FD}<&-
  if [[ "$cleanup_status" -ne 0 && "$final_status" -eq 0 ]]; then
    final_status=1
  fi
  if [[ "$final_status" -eq 0 && "$SUITE_COMPLETED" == true ]]; then
    printf 'PASS authentik-runbook-safety: lock, marker inventory, trap ordering, pinned publish, database guard/file pins, reverse-swap retry, hold ambiguity, and abort-schema regressions\n'
  elif [[ "$final_status" -eq 0 ]]; then
    printf 'FAIL authentik-runbook-safety: suite exited before completion\n' >&2
    final_status=1
  fi
  exit "$final_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

trap '' HUP INT TERM
TEST_ROOT="$(mktemp -d \
  "$TEST_ROOT_PARENT/authentik-runbook-safety.XXXXXX")"
TEST_ROOT_ID="$(stat -Lc '%d:%i' -- "$TEST_ROOT")"
exec {TEST_ROOT_FD}<"$TEST_ROOT"
[[ "${TEST_ROOT%/*}" == "$TEST_ROOT_PARENT" && \
  "${TEST_ROOT##*/}" =~ ^authentik-runbook-safety\.[A-Za-z0-9]+$ && \
  -d "$TEST_ROOT" && ! -L "$TEST_ROOT" && \
  "$(stat -Lc '%a:%u:%g:%h' -- "$TEST_ROOT")" == \
    "700:$(id -u):$(id -g):2" && \
  "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${TEST_ROOT_FD}")" == \
    "$TEST_ROOT_ID" ]]
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Stops on one violated runbook regression contræct.
#ææææææææææææææææææææææææææææææææææ
fail() {
  printf 'FAIL authentik-runbook-safety: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local needle="$1"
  grep -Fq -- "$needle" "$README_FILE" \
    || fail "missing README contract: ${needle}"
}

line_of() {
  local needle="$1"
  awk -v needle="$needle" '
    $0 == needle { print NR; found=1; exit }
    END { if (!found) exit 1 }
  ' "$README_FILE"
}

assert_order() {
  local earlier="$1" later="$2" earlier_line later_line
  earlier_line="$(line_of "$earlier")" \
    || fail "missing ordering anchor: ${earlier}"
  later_line="$(line_of "$later")" \
    || fail "missing ordering anchor: ${later}"
  (( earlier_line < later_line )) \
    || fail "ordering contract violated: ${earlier} before ${later}"
}

count_literal() {
  local needle="$1"
  awk -v needle="$needle" 'index($0, needle) { count++ } END { print count+0 }' \
    "$README_FILE"
}

assert_function_excludes() {
  local function_name="$1" forbidden="$2"
  if awk -v function_name="$function_name" '
    $0 == function_name "() {" { capture=1 }
    capture { print }
    capture && $0 == "}" { exit }
  ' "$README_FILE" | grep -Fq -- "$forbidden"; then
    fail "${function_name} contains forbidden cleanup transition: ${forbidden}"
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- STÆTIC RUNBOOK BOUNDÆRIES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
[[ -f "$README_FILE" && ! -L "$README_FILE" ]] \
  || fail 'Authentik README is missing or symbolic'
(( $(count_literal 'flock -n -x "$AUTHENTIK_OPERATION_LOCK_FD"') >= 4 )) \
  || fail 'one long-lived project-directory lock is not enforced in every flow'
(( $(count_literal 'acquire_authentik_operation_lock') >= 8 )) \
  || fail 'the bind-before-open project lock helper is not used in every flow'
assert_contains '"/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}"'
assert_contains 'find -P .. -mindepth 1 -maxdepth 1 \'
(( $(count_literal "-name '.authentik-update-abort-*'") >= 4 )) \
  || fail 'hidden abort staging names are not inventoried in every flow'
(( $(count_literal "-name '.authentik-restore-abort-*'") >= 4 )) \
  || fail 'hidden restore-abort staging names are not globally inventoried'
assert_contains 'mv -Tn -- "$staging" "$path"'
assert_contains 'RECOVERY_POINT_RECOVERY_DIR_CREATED=true'
assert_contains 'RECOVERY_POINT_PRIVATE_DIR_CREATED=true'
assert_contains 'hold_state=unknown'
assert_contains '{schema_version:2,status:"external-gate-recovery-required"'
assert_contains 'sync -f -- "$staging"'
assert_contains 'ensure_image_reference_absent "$TARGET_HOLD_REF" "$TARGET_APP_IMAGE"'
assert_order "trap 'abort_gated_update 129' HUP" 'ABORT_RECOVERY_REQUIRED=true'
assert_order "trap 'abort_recovery_point 129' HUP" \
  'RECOVERY_POINT_RECOVERY_REQUIRED=true'
assert_order "trap 'abort_restore_transaction 129' HUP" \
  'RESTORE_ROLLBACK_REQUIRED=true'
for function_name in abort_gated_update rollback_discovery \
  cleanup_review_failure rollback_pre_migration_update; do
  assert_function_excludes "$function_name" 'trap - HUP INT TERM'
done
assert_contains 'RESTORE_DB_GUARD_PUBLISHED=true'
assert_contains 'validate_restore_db_guard || abort_restore_database_phase 125'
assert_contains 'recovery_dir:$recovery_dir'
assert_contains 'abort_restore_abort_recovery_exit() {'
assert_contains '(( RESTORE_ABORT_ACTIVE_COUNT == 1 && RESTORE_ABORT_SAME_UPDATE_COUNT <= 1 ))'
assert_contains 'resolve_restore_abort_recovery_marker'
if ! awk '
  {
    current=$0
    sub(/^[[:space:]]+/, "", current)
  }
  current == "RESTORE_DB_MUTATION_STARTED=true" {
    if (previous != "verify_restore_db_phase_preamble" &&
        previous != "validate_restore_abort_recovery_state") exit 1
    count++
  }
  { previous=current }
  END { if (count < 3) exit 1 }
' "$README_FILE"; then
  fail 'a database apply is not immediately preceded by its identity preamble'
fi
(( $(count_literal '(( status != 0 )) || status=125') >= 7 )) \
  || fail 'an active EXIT handler can still preserve a successful status'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- STÆBLE DESCRIPTOR LOCK
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
LOCK_ROOT="$TEST_ROOT/project-lock"
mkdir -m 0700 -- "$LOCK_ROOT"
exec {LOCK_FD}<"$LOCK_ROOT"
flock -n -x "$LOCK_FD" || fail 'first project-directory lock failed'
flock -n -x "$LOCK_FD" || fail 'same descriptor could not be revalidated'
if (
  exec {CONTENDER_FD}<"$LOCK_ROOT"
  flock -n -x "$CONTENDER_FD"
); then
  fail 'a second descriptor bypassed the held exclusive lock'
fi
exec {LOCK_FD}<&-

LOCK_HELPER_FUNCTIONS="$TEST_ROOT/operation-lock-functions.sh"
if ! awk '
  /^validate_authentik_operation_lock\(\)/ { capture=1 }
  capture && /^acquire_authentik_operation_lock$/ { exit }
  capture { print }
' "$README_FILE" > "$LOCK_HELPER_FUNCTIONS"; then
  fail 'operation-lock helper extraction failed'
fi
[[ -s "$LOCK_HELPER_FUNCTIONS" ]] \
  || fail 'operation-lock helper functions are missing'
POST_FLOCK_SENTINEL="$TEST_ROOT/post-flock-rename-rejected"
if ! (
  # shellcheck source=/dev/null
  source "$LOCK_HELPER_FUNCTIONS"
  lock_parent="$TEST_ROOT/post-flock-rename"
  lock_root="$lock_parent/project"
  mkdir -p -m 0700 -- "$lock_root"
  cd -- "$lock_root"
  AUTHENTIK_OPERATION_ROOT="$(pwd -P)"
  unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_LOCK_IDENTITY
  POST_FLOCK_RENAME_DONE=false
  flock() {
    command flock "$@" || return 125
    if [[ "$POST_FLOCK_RENAME_DONE" == false ]]; then
      POST_FLOCK_RENAME_DONE=true
      mv -T -- "$AUTHENTIK_OPERATION_ROOT" \
        "${AUTHENTIK_OPERATION_ROOT}.locked" || return 125
      mkdir -m 0700 -- "$AUTHENTIK_OPERATION_ROOT" || return 125
    fi
  }
  if acquire_authentik_operation_lock; then
    exit 91
  fi
  [[ "$POST_FLOCK_RENAME_DONE" == true && \
    -d "$AUTHENTIK_OPERATION_ROOT" && \
    -d "${AUTHENTIK_OPERATION_ROOT}.locked" ]]
  printf rejected > "$POST_FLOCK_SENTINEL"
); then
  fail 'post-flock project-directory replacement test failed unexpectedly'
fi
[[ "$(<"$POST_FLOCK_SENTINEL")" == rejected ]] \
  || fail 'post-flock project-directory replacement bypassed revalidation'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- NUL-SÆFE ÆBORT INVENTORY
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
scan_abort_markers() {
  local parent="$1" expected_id="${2:-}" inventory inventory_id inventory_fd
  local candidate name status=0 active_count=0

  inventory="$(mktemp "$TEST_ROOT/marker-inventory.XXXXXX")" || return 125
  inventory_id="$(stat -Lc '%d:%i' -- "$inventory")" || return 125
  exec {inventory_fd}<"$inventory" || return 125
  if ! find -P "$parent" -mindepth 1 -maxdepth 1 \
    \( -name 'authentik-update-abort-*' -o \
      -name '.authentik-update-abort-*' -o \
      -name 'authentik-restore-abort-*' -o \
      -name '.authentik-restore-abort-*' \) -print0 > "$inventory"; then
    status=125
  fi
  if [[ "$status" == 0 ]]; then
    while IFS= read -r -d '' candidate; do
      name="${candidate##*/}"
      if [[ ! -d "$candidate" || -L "$candidate" ]]; then
        status=125
        break
      fi
      if [[ "$name" =~ \
        ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z-resolved-[0-9]{8}T[0-9]{6}Z$ ]]; then
        continue
      fi
      if [[ -n "$expected_id" && \
        "$name" == "authentik-update-abort-${expected_id}" ]]; then
        ((active_count+=1))
        continue
      fi
      status=125
      break
    done < "$inventory"
  fi
  if [[ -n "$expected_id" && "$active_count" -gt 1 ]]; then
    status=125
  fi
  if [[ ! -f "$inventory" || -L "$inventory" || \
    "$(stat -Lc '%d:%i' -- "$inventory")" != "$inventory_id" || \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${inventory_fd}")" != \
      "$inventory_id" ]]; then
    status=125
  else
    rm -f -- "$inventory" || status=125
  fi
  exec {inventory_fd}<&-
  return "$status"
}

RECOVERY_ID_ONE=20260821T120000Z
RECOVERY_ID_TWO=20260821T120001Z
MARKER_EMPTY="$TEST_ROOT/markers-empty"
MARKER_RESOLVED="$TEST_ROOT/markers-resolved"
MARKER_EXPECTED="$TEST_ROOT/markers-expected"
MARKER_FOREIGN="$TEST_ROOT/markers-foreign"
MARKER_MULTIPLE="$TEST_ROOT/markers-multiple"
MARKER_MALFORMED="$TEST_ROOT/markers-malformed"
MARKER_HIDDEN="$TEST_ROOT/markers-hidden"
MARKER_SYMLINK="$TEST_ROOT/markers-symlink"
MARKER_FILE="$TEST_ROOT/markers-file"
MARKER_HOSTILE="$TEST_ROOT/markers-hostile"
MARKER_RESTORE_RESOLVED="$TEST_ROOT/markers-restore-resolved"
MARKER_RESTORE_ACTIVE="$TEST_ROOT/markers-restore-active"
mkdir -m 0700 -- "$MARKER_EMPTY" "$MARKER_RESOLVED" "$MARKER_EXPECTED" \
  "$MARKER_FOREIGN" "$MARKER_MULTIPLE" "$MARKER_MALFORMED" \
  "$MARKER_HIDDEN" "$MARKER_SYMLINK" "$MARKER_FILE" "$MARKER_HOSTILE" \
  "$MARKER_RESTORE_RESOLVED" "$MARKER_RESTORE_ACTIVE"
mkdir -m 0700 -- \
  "$MARKER_RESOLVED/authentik-update-abort-${RECOVERY_ID_ONE}-resolved-${RECOVERY_ID_TWO}" \
  "$MARKER_EXPECTED/authentik-update-abort-${RECOVERY_ID_ONE}" \
  "$MARKER_FOREIGN/authentik-update-abort-${RECOVERY_ID_TWO}" \
  "$MARKER_MULTIPLE/authentik-update-abort-${RECOVERY_ID_ONE}" \
  "$MARKER_MULTIPLE/authentik-update-abort-${RECOVERY_ID_TWO}" \
  "$MARKER_MALFORMED/authentik-update-abort-bad" \
  "$MARKER_HIDDEN/.authentik-update-abort-${RECOVERY_ID_ONE}.staging" \
  "$MARKER_RESTORE_RESOLVED/authentik-restore-abort-${RECOVERY_ID_ONE}-resolved-${RECOVERY_ID_TWO}" \
  "$MARKER_RESTORE_ACTIVE/authentik-restore-abort-${RECOVERY_ID_ONE}" \
  "$MARKER_HOSTILE/authentik-update-abort-${RECOVERY_ID_ONE}"$'\nforeign'
ln -s -- "$MARKER_EMPTY" \
  "$MARKER_SYMLINK/authentik-update-abort-${RECOVERY_ID_ONE}"
install -m 0600 /dev/null \
  "$MARKER_FILE/authentik-update-abort-${RECOVERY_ID_ONE}"
scan_abort_markers "$MARKER_EMPTY" "$RECOVERY_ID_ONE" \
  || fail 'empty marker inventory was rejected'
scan_abort_markers "$MARKER_RESOLVED" "$RECOVERY_ID_ONE" \
  || fail 'resolved marker was not excluded exactly'
scan_abort_markers "$MARKER_RESTORE_RESOLVED" "$RECOVERY_ID_ONE" \
  || fail 'resolved restore marker was not excluded exactly'
scan_abort_markers "$MARKER_EXPECTED" "$RECOVERY_ID_ONE" \
  || fail 'one same-ID restore marker was rejected'
for parent in "$MARKER_FOREIGN" "$MARKER_MULTIPLE" "$MARKER_MALFORMED" \
  "$MARKER_HIDDEN" "$MARKER_SYMLINK" "$MARKER_FILE" "$MARKER_HOSTILE"; do
  if scan_abort_markers "$parent" "$RECOVERY_ID_ONE"; then
    fail "hostile marker inventory passed: ${parent##*/}"
  fi
done
if scan_abort_markers "$MARKER_RESTORE_ACTIVE" "$RECOVERY_ID_ONE"; then
  fail 'an active restore marker passed the restore inventory'
fi
if scan_abort_markers "$MARKER_EXPECTED"; then
  fail 'an active marker passed the global fail-closed inventory'
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXÆCT SWÆP ROLLBÆCK STÆTES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
ROLLBACK_FUNCTIONS="$TEST_ROOT/rollback-functions.sh"
if ! awk '
  /^path_present\(\)/ { capture=1 }
  /^quarantine_fresh_restore_state\(\)/ { exit }
  capture { print }
' "$README_FILE" > "$ROLLBACK_FUNCTIONS"; then
  fail 'rollback function extraction failed'
fi
[[ -s "$ROLLBACK_FUNCTIONS" ]] || fail 'rollback functions were not found'
# shellcheck source=/dev/null
source "$ROLLBACK_FUNCTIONS"
sudo() { "$@"; }

assert_rolled_back() {
  local root="$1"
  [[ "$(<"$root/live")" == original && "$(<"$root/candidate")" == new && \
    ! -e "$root/old" && ! -L "$root/old" ]]
}

ROLLBACK_BEFORE="$TEST_ROOT/rollback-before"
ROLLBACK_FIRST="$TEST_ROOT/rollback-after-first"
ROLLBACK_SECOND="$TEST_ROOT/rollback-after-second"
ROLLBACK_AMBIGUOUS="$TEST_ROOT/rollback-ambiguous"
mkdir -m 0700 -- "$ROLLBACK_BEFORE" "$ROLLBACK_FIRST" "$ROLLBACK_SECOND" \
  "$ROLLBACK_AMBIGUOUS"
printf original > "$ROLLBACK_BEFORE/live"
printf new > "$ROLLBACK_BEFORE/candidate"
printf original > "$ROLLBACK_FIRST/old"
printf new > "$ROLLBACK_FIRST/candidate"
printf new > "$ROLLBACK_SECOND/live"
printf original > "$ROLLBACK_SECOND/old"
printf new > "$ROLLBACK_AMBIGUOUS/live"
printf candidate > "$ROLLBACK_AMBIGUOUS/candidate"
printf original > "$ROLLBACK_AMBIGUOUS/old"
for root in "$ROLLBACK_BEFORE" "$ROLLBACK_FIRST" "$ROLLBACK_SECOND"; do
  rollback_swapped_unit "$root/live" "$root/candidate" "$root/old" \
    || fail "first rollback failed: ${root##*/}"
  rollback_swapped_unit "$root/live" "$root/candidate" "$root/old" \
    || fail "idempotent rollback failed: ${root##*/}"
  assert_rolled_back "$root" || fail "rollback state drift: ${root##*/}"
done
MERGE_SENTINEL="$ROLLBACK_AMBIGUOUS/merge-ran"
if rollback_swapped_unit "$ROLLBACK_AMBIGUOUS/live" \
  "$ROLLBACK_AMBIGUOUS/candidate" "$ROLLBACK_AMBIGUOUS/old"; then
  printf touched > "$MERGE_SENTINEL"
fi
[[ ! -e "$MERGE_SENTINEL" ]] \
  || fail 'ambiguous unit rollback continued into merge work'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- PINNED RECOVERY DIRECTORY PUBLICÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
RECOVERY_FUNCTIONS="$TEST_ROOT/recovery-functions.sh"
if ! awk '
  /^create_pinned_empty_recovery_dir\(\)/ { capture=1 }
  /^invalidate_owned_recovery_path\(\)/ { exit }
  capture { print }
' "$README_FILE" > "$RECOVERY_FUNCTIONS"; then
  fail 'recovery-directory function extraction failed'
fi
[[ -s "$RECOVERY_FUNCTIONS" ]] || fail 'recovery-directory function missing'
# shellcheck source=/dev/null
source "$RECOVERY_FUNCTIONS"
RECOVERY_POINT_PARENT="$TEST_ROOT/recovery-parent"
mkdir -m 0700 -- "$RECOVERY_POINT_PARENT"
exec {RECOVERY_POINT_PARENT_FD}<"$RECOVERY_POINT_PARENT"
RECOVERY_POINT_PARENT_ID="$(stat -Lc '%d:%i' -- "$RECOVERY_POINT_PARENT")"
RECOVERY_ID="$RECOVERY_ID_ONE"
RECOVERY_POINT_RECOVERY_DIR_CREATED=false
RECOVERY_POINT_PRIVATE_DIR_CREATED=false
RECOVERY_POINT_RECOVERY_DIR_ID=''
RECOVERY_POINT_PRIVATE_DIR_ID=''
RECOVERY_POINT_RECOVERY_DIR_FD=''
RECOVERY_POINT_PRIVATE_DIR_FD=''
PINNED_RECOVERY_DIR_ID=''
PINNED_RECOVERY_DIR_FD=''
COLLISION_PATH="$RECOVERY_POINT_PARENT/authentik-recovery-${RECOVERY_ID}"
mkdir -m 0700 -- "$COLLISION_PATH"
printf sentinel > "$COLLISION_PATH/sentinel"
COLLISION_ID="$(stat -Lc '%d:%i' -- "$COLLISION_PATH")"
if (set -e; create_pinned_empty_recovery_dir "$COLLISION_PATH"); then
  fail 'pre-existing recovery-ID collision was accepted'
fi
[[ "$(stat -Lc '%d:%i' -- "$COLLISION_PATH")" == "$COLLISION_ID" && \
  "$(<"$COLLISION_PATH/sentinel")" == sentinel ]]
FRESH_RECOVERY_PATH="$RECOVERY_POINT_PARENT/authentik-private-${RECOVERY_ID}"
create_pinned_empty_recovery_dir "$FRESH_RECOVERY_PATH"
[[ "$RECOVERY_POINT_PRIVATE_DIR_CREATED" == true && \
  "$RECOVERY_POINT_PRIVATE_DIR_ID" == \
    "$(stat -Lc '%d:%i' -- "$FRESH_RECOVERY_PATH")" && \
  "$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${RECOVERY_POINT_PRIVATE_DIR_FD}")" == \
    "$RECOVERY_POINT_PRIVATE_DIR_ID" ]]
exec {RECOVERY_POINT_PRIVATE_DIR_FD}<&-
rmdir -- "$FRESH_RECOVERY_PATH"

INVALIDATOR_FUNCTIONS="$TEST_ROOT/invalidator-functions.sh"
if ! awk '
  /^invalidate_owned_recovery_path\(\)/ { capture=1 }
  /^invalidate_incomplete_recovery_point\(\)/ { exit }
  capture { print }
' "$README_FILE" > "$INVALIDATOR_FUNCTIONS"; then
  fail 'recovery invalidator extraction failed'
fi
[[ -s "$INVALIDATOR_FUNCTIONS" ]] || fail 'recovery invalidator missing'
# shellcheck source=/dev/null
source "$INVALIDATOR_FUNCTIONS"
INVALIDATE_PATH="$RECOVERY_POINT_PARENT/authentik-recovery-${RECOVERY_ID}"
rmdir -- "$COLLISION_PATH" 2>/dev/null \
  || rm -f -- "$COLLISION_PATH/sentinel"
rmdir -- "$COLLISION_PATH"
mkdir -m 0700 -- "$INVALIDATE_PATH"
INVALIDATE_ID="$(stat -Lc '%d:%i' -- "$INVALIDATE_PATH")"
exec {INVALIDATE_FD}<"$INVALIDATE_PATH"
INVALIDATE_MV_SENTINEL="$TEST_ROOT/recovery-invalidator-mv-called"
INVALIDATE_STDERR="$TEST_ROOT/recovery-invalidator.stderr"
set +e
(
  mv() {
    printf called > "$INVALIDATE_MV_SENTINEL"
    return 1
  }
  invalidate_owned_recovery_path "$INVALIDATE_PATH" \
    "authentik-recovery-${RECOVERY_ID}" true "$INVALIDATE_ID" \
    "$INVALIDATE_FD"
) 2> "$INVALIDATE_STDERR"
INVALIDATE_STATUS=$?
set -e
[[ "$INVALIDATE_STATUS" == 125 && -f "$INVALIDATE_MV_SENTINEL" && \
  ! -s "$INVALIDATE_STDERR" ]] \
  || fail 'recovery invalidator did not reach and propagate the injected mv failure'
[[ -d "$INVALIDATE_PATH" && \
  "$(stat -Lc '%d:%i' -- "$INVALIDATE_PATH")" == "$INVALIDATE_ID" ]]
exec {INVALIDATE_FD}<&-
rmdir -- "$INVALIDATE_PATH"

DB_INVALIDATOR_FUNCTIONS="$TEST_ROOT/db-invalidator-functions.sh"
if ! awk '
  /^invalidate_db_rollback_preflight\(\)/ { capture=1 }
  /^abort_restore_preflight\(\)/ { exit }
  capture { print }
' "$README_FILE" > "$DB_INVALIDATOR_FUNCTIONS"; then
  fail 'DB invalidator extraction failed'
fi
[[ -s "$DB_INVALIDATOR_FUNCTIONS" ]] || fail 'DB invalidator missing'
# shellcheck source=/dev/null
source "$DB_INVALIDATOR_FUNCTIONS"
RESTORE_OPERATION_PARENT="$RECOVERY_POINT_PARENT"
RESTORE_OPERATION_PARENT_ID="$RECOVERY_POINT_PARENT_ID"
RESTORE_OPERATION_PARENT_FD="$RECOVERY_POINT_PARENT_FD"
DB_ROLLBACK_DIR="$RESTORE_OPERATION_PARENT/authentik-db-rollback.AbCd12"
mkdir -m 0700 -- "$DB_ROLLBACK_DIR"
DB_ROLLBACK_DIR_ID="$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")"
DB_ROLLBACK_DIR_CREATED=true
exec {DB_ROLLBACK_DIR_FD}<"$DB_ROLLBACK_DIR"
DB_INVALIDATE_MV_SENTINEL="$TEST_ROOT/db-invalidator-mv-called"
DB_INVALIDATE_STDERR="$TEST_ROOT/db-invalidator.stderr"
set +e
(
  mv() {
    printf called > "$DB_INVALIDATE_MV_SENTINEL"
    return 1
  }
  invalidate_db_rollback_preflight
) 2> "$DB_INVALIDATE_STDERR"
DB_INVALIDATE_STATUS=$?
set -e
[[ "$DB_INVALIDATE_STATUS" == 125 && -f "$DB_INVALIDATE_MV_SENTINEL" && \
  ! -s "$DB_INVALIDATE_STDERR" ]] \
  || fail 'DB invalidator did not reach and propagate the injected mv failure'
[[ -d "$DB_ROLLBACK_DIR" && \
  "$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")" == "$DB_ROLLBACK_DIR_ID" ]]
exec {DB_ROLLBACK_DIR_FD}<&-
rmdir -- "$DB_ROLLBACK_DIR"
exec {RECOVERY_POINT_PARENT_FD}<&-

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DURÆBLE DÆTÆBÆSE RESTORE GUÆRD
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
DB_GUARD_FUNCTIONS="$TEST_ROOT/db-guard-functions.sh"
if ! awk '
  /^validate_restore_old_state\(\)/ { capture=1 }
  /^abort_restore_database_phase_exit\(\)/ { exit_handler=1 }
  capture { print }
  capture && exit_handler && /^}$/ { exit }
' "$README_FILE" > "$DB_GUARD_FUNCTIONS"; then
  fail 'database guard function extraction failed'
fi
[[ -s "$DB_GUARD_FUNCTIONS" ]] || fail 'database guard functions missing'
# shellcheck source=/dev/null
source "$DB_GUARD_FUNCTIONS"
# shellcheck source=/dev/null
source "$LOCK_HELPER_FUNCTIONS"
for HANDOFF_MODE in parent-sync rename-error; do
HANDOFF_ROOT="$TEST_ROOT/db-guard-handoff-${HANDOFF_MODE}"
HANDOFF_PROJECT="$HANDOFF_ROOT/project"
HANDOFF_PARENT="$HANDOFF_ROOT/parent"
HANDOFF_RECOVERY="$HANDOFF_ROOT/recovery"
HANDOFF_STAGE="$HANDOFF_PROJECT/stage"
HANDOFF_OLD="$HANDOFF_PARENT/authentik-pre-restore.HaNd0f"
HANDOFF_MARKER="$HANDOFF_PARENT/authentik-restore-abort-20260821T010203Z"
HANDOFF_OLD_TRAP_SENTINEL="$HANDOFF_ROOT/old-file-rollback-called"
HANDOFF_STOP_SENTINEL="$HANDOFF_ROOT/project-stop-called"
HANDOFF_STDERR="$HANDOFF_ROOT/handler.stderr"
mkdir -m 0700 -- "$HANDOFF_ROOT"
if (
  mkdir -p -m 0700 -- "$HANDOFF_PROJECT/appdata" \
    "$HANDOFF_PROJECT/secrets" "$HANDOFF_PROJECT/scripts" \
    "$HANDOFF_PROJECT/.run.conf" "$HANDOFF_STAGE/scripts" \
    "$HANDOFF_STAGE/.run.conf" "$HANDOFF_OLD/appdata" \
    "$HANDOFF_OLD/secrets" "$HANDOFF_OLD/scripts" \
    "$HANDOFF_OLD/.run.conf" "$HANDOFF_OLD/database" "$HANDOFF_RECOVERY"
  printf restored > "$HANDOFF_PROJECT/appdata/value"
  printf restored > "$HANDOFF_PROJECT/app.env"
  printf restored > "$HANDOFF_PROJECT/secrets/value"
  printf restored > "$HANDOFF_PROJECT/scripts/backup.cron"
  printf restored > "$HANDOFF_PROJECT/.run.conf/.templates.lock"
  printf original > "$HANDOFF_OLD/appdata/value"
  printf original > "$HANDOFF_OLD/app.env"
  printf original > "$HANDOFF_OLD/secrets/value"
  printf original > "$HANDOFF_OLD/scripts/backup.cron"
  printf original > "$HANDOFF_OLD/.run.conf/.templates.lock"
  jq -n '{version:1,kind:"maintenance",physical_id:"20260821_1",
    logical_id:"20260821_120000",payload_manifest_sha256:
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
    > "$HANDOFF_OLD/database/rollback.json"
  chmod 0600 "$HANDOFF_OLD/database/rollback.json"
  cd -- "$HANDOFF_PROJECT"
  RESTORE_OPERATION_PARENT="$HANDOFF_PARENT"
  exec {RESTORE_OPERATION_PARENT_FD}<"$RESTORE_OPERATION_PARENT"
  RESTORE_OPERATION_PARENT_ID="$(stat -Lc '%d:%i' -- \
    "$RESTORE_OPERATION_PARENT")"
  OLD="$HANDOFF_OLD"
  exec {RESTORE_OLD_FD}<"$OLD"
  RESTORE_OLD_ID="$(stat -Lc '%d:%i' -- "$OLD")"
  DB_ROLLBACK_DIR="$OLD/database"
  exec {DB_ROLLBACK_DIR_FD}<"$DB_ROLLBACK_DIR"
  DB_ROLLBACK_DIR_ID="$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")"
  RECOVERY_DIR="$HANDOFF_RECOVERY"
  RESTORE_RECOVERY_ID=20260821T010203Z
  RECOVERY_PROJECT_NAME=authentik_handoff_test
  RESTORE_DB_ABORT_DIR="$HANDOFF_MARKER"
  RESTORE_DB_ABORT_ID=''
  RESTORE_DB_ABORT_FD=''
  RESTORE_DB_GUARD_ARMED=false
  RESTORE_DB_GUARD_PUBLISHED=false
  RESTORE_DB_MUTATION_STARTED=false
  RESTORE_COMPLETE=false
  RESTORE_DB_HANDLER_RUNNING=false
  RESTORE_ROLLBACK_REQUIRED=true
  RESTORE_TRANSACTION_COMPLETE=false
  abort_restore_transaction() {
    printf called > "$HANDOFF_OLD_TRAP_SENTINEL"
    mv -Tn -- "$HANDOFF_PROJECT/app.env" "$HANDOFF_STAGE/app.env" || true
    trap - ERR EXIT
    exit "${1:-125}"
  }
  compose_handoff_stub() {
    [[ "$1" == down ]] || return 125
    printf stopped > "$HANDOFF_STOP_SENTINEL"
  }
  COMPOSE=(compose_handoff_stub)
  docker() {
    [[ "$1" == container && "$2" == ls ]] || return 125
    return 0
  }
  mv() {
    if [[ "$HANDOFF_MODE" == rename-error && "$1" == -Tn && \
      "$2" == -- && "$4" == "$RESTORE_DB_ABORT_DIR" ]]; then
      command mv "$@" || return 125
      return 1
    fi
    command mv "$@"
  }
  sync() {
    if [[ "$HANDOFF_MODE" == parent-sync && \
      "$*" == "-f -- $RESTORE_OPERATION_PARENT" ]]; then
      return 1
    fi
    return 0
  }
  trap 'abort_restore_transaction 129' HUP
  trap 'abort_restore_transaction 130' INT
  trap 'abort_restore_transaction 143' TERM
  trap 'abort_restore_transaction $?' ERR
  trap 'abort_restore_transaction $?' EXIT
  publish_restore_db_guard
  exit 90
) 2> "$HANDOFF_STDERR"; then
  HANDOFF_STATUS=0
else
  HANDOFF_STATUS=$?
fi
[[ "$HANDOFF_STATUS" == 125 && \
  ! -e "$HANDOFF_OLD_TRAP_SENTINEL" && \
  "$(<"$HANDOFF_STOP_SENTINEL")" == stopped && \
  -d "$HANDOFF_MARKER" && ! -L "$HANDOFF_MARKER" ]] \
  || fail 'post-publish parent-sync failure did not use the database handler'
[[ "$(<"$HANDOFF_PROJECT/appdata/value")" == restored && \
  "$(<"$HANDOFF_PROJECT/app.env")" == restored && \
  "$(<"$HANDOFF_PROJECT/secrets/value")" == restored && \
  "$(<"$HANDOFF_PROJECT/scripts/backup.cron")" == restored && \
  "$(<"$HANDOFF_PROJECT/.run.conf/.templates.lock")" == restored && \
  "$(<"$HANDOFF_OLD/appdata/value")" == original && \
  "$(<"$HANDOFF_OLD/app.env")" == original && \
  "$(<"$HANDOFF_OLD/secrets/value")" == original && \
  "$(<"$HANDOFF_OLD/scripts/backup.cron")" == original && \
  "$(<"$HANDOFF_OLD/.run.conf/.templates.lock")" == original && \
  ! -e "$HANDOFF_STAGE/appdata" && ! -L "$HANDOFF_STAGE/appdata" && \
  ! -e "$HANDOFF_STAGE/app.env" && ! -L "$HANDOFF_STAGE/app.env" && \
  ! -e "$HANDOFF_STAGE/secrets" && ! -L "$HANDOFF_STAGE/secrets" && \
  ! -e "$HANDOFF_STAGE/scripts/backup.cron" && \
  ! -L "$HANDOFF_STAGE/scripts/backup.cron" && \
  ! -e "$HANDOFF_STAGE/.run.conf/.templates.lock" && \
  ! -L "$HANDOFF_STAGE/.run.conf/.templates.lock" ]] \
  || fail 'post-publish failure changed a five-unit 101 restore state'
done
DB_GUARD_PROJECT="$TEST_ROOT/db-guard-project"
RESTORE_OPERATION_PARENT="$TEST_ROOT/db-guard-parent"
mkdir -m 0700 -- "$DB_GUARD_PROJECT" "$RESTORE_OPERATION_PARENT"
DB_GUARD_ORIGINAL_PWD="$(pwd -P)"
cd -- "$DB_GUARD_PROJECT"
AUTHENTIK_OPERATION_ROOT="$DB_GUARD_PROJECT"
unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_LOCK_IDENTITY
acquire_authentik_operation_lock \
  || fail 'database guard could not acquire its project lock fixture'
exec {RESTORE_OPERATION_PARENT_FD}<"$RESTORE_OPERATION_PARENT"
RESTORE_OPERATION_PARENT_ID="$(stat -Lc '%d:%i' -- \
  "$RESTORE_OPERATION_PARENT")"
RESTORE_RECOVERY_ID="$RECOVERY_ID_ONE"
RECOVERY_PROJECT_NAME=authentik_guard_test
RECOVERY_DIR="$TEST_ROOT/db-guard-recovery"
OLD="$RESTORE_OPERATION_PARENT/authentik-pre-restore.AbCd12"
DB_ROLLBACK_DIR="$OLD/database"
RESTORE_DB_ABORT_DIR="$RESTORE_OPERATION_PARENT/authentik-restore-abort-${RESTORE_RECOVERY_ID}"
RESTORE_DB_ABORT_ID=''
RESTORE_DB_ABORT_FD=''
RESTORE_DB_RESOLVED_DIR=''
RESTORE_COMPLETE=false
RESTORE_DB_GUARD_ARMED=false
RESTORE_DB_GUARD_PUBLISHED=false
RESTORE_DB_HANDLER_RUNNING=false
RESTORE_ROLLBACK_REQUIRED=true
RESTORE_TRANSACTION_COMPLETE=false
compose_db_guard_stub() { [[ "$1" == down ]]; }
COMPOSE=(compose_db_guard_stub)
docker() {
  [[ "$1" == container && "$2" == ls ]] || return 125
  return 0
}
mkdir -m 0700 -- "$RECOVERY_DIR" "$OLD" "$DB_ROLLBACK_DIR"
exec {RESTORE_OLD_FD}<"$OLD"
RESTORE_OLD_ID="$(stat -Lc '%d:%i' -- "$OLD")"
exec {DB_ROLLBACK_DIR_FD}<"$DB_ROLLBACK_DIR"
DB_ROLLBACK_DIR_ID="$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")"
jq -n '{version:1,kind:"maintenance",physical_id:"20260821_1",
  logical_id:"20260821_120000",payload_manifest_sha256:
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
  > "$DB_ROLLBACK_DIR/rollback.json"
chmod 0600 "$DB_ROLLBACK_DIR/rollback.json"
publish_restore_db_guard || fail 'database guard publication failed'
[[ "$RESTORE_DB_GUARD_PUBLISHED" == true && \
  "$RESTORE_DB_GUARD_ARMED" == true && \
  "$RESTORE_ROLLBACK_REQUIRED" == false && \
  "$RESTORE_TRANSACTION_COMPLETE" == true ]] \
  || fail 'database guard publication did not complete its trap handoff'
[[ -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
  "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == \
    "$RESTORE_DB_ABORT_ID" && \
  "$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${RESTORE_DB_ABORT_FD}")" == \
    "$RESTORE_DB_ABORT_ID" ]]
jq -e --arg recovery_dir "$RECOVERY_DIR" '
  keys == ["database_id","old_id","old_path","project_name","recovery_dir",
    "recovery_id","rollback_kind","schema_version","status"] and
  .schema_version == 1 and .status == "db-restore-unresolved" and
  .recovery_dir == $recovery_dir and .rollback_kind == "maintenance"
' "$RESTORE_DB_ABORT_DIR/restore-abort.json" >/dev/null \
  || fail 'database guard schema did not bind its recovery artifacts'
DB_GUARD_MARKER_ID="$RESTORE_DB_ABORT_ID"
if publish_restore_db_guard; then
  fail 'an existing active database guard was overwritten'
fi
[[ "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == \
  "$DB_GUARD_MARKER_ID" ]]
verify_restore_db_phase_preamble \
  || fail 'valid database guard preamble was rejected'

DB_GUARD_OLD_MOVED="${OLD}.moved"
mv -T -- "$OLD" "$DB_GUARD_OLD_MOVED"
mkdir -m 0700 -- "$OLD"
if verify_restore_db_phase_preamble; then
  fail 'OLD path replacement passed the database guard preamble'
fi
rmdir -- "$OLD"
mv -T -- "$DB_GUARD_OLD_MOVED" "$OLD"
DB_GUARD_DATABASE_MOVED="$OLD/database.moved"
mv -T -- "$DB_ROLLBACK_DIR" "$DB_GUARD_DATABASE_MOVED"
mkdir -m 0700 -- "$DB_ROLLBACK_DIR"
if verify_restore_db_phase_preamble; then
  fail 'database path replacement passed the database guard preamble'
fi
rmdir -- "$DB_ROLLBACK_DIR"
mv -T -- "$DB_GUARD_DATABASE_MOVED" "$DB_ROLLBACK_DIR"
DB_GUARD_MARKER_MOVED="${RESTORE_DB_ABORT_DIR}.moved"
mv -T -- "$RESTORE_DB_ABORT_DIR" "$DB_GUARD_MARKER_MOVED"
mkdir -m 0700 -- "$RESTORE_DB_ABORT_DIR"
if verify_restore_db_phase_preamble; then
  fail 'marker path replacement passed the database guard preamble'
fi
rmdir -- "$RESTORE_DB_ABORT_DIR"
mv -T -- "$DB_GUARD_MARKER_MOVED" "$RESTORE_DB_ABORT_DIR"
verify_restore_db_phase_preamble \
  || fail 'database guard preamble did not recover after exact restoration'

sync() { return 1; }
if resolve_restore_db_guard; then
  DB_GUARD_RESOLVE_STATUS=0
else
  DB_GUARD_RESOLVE_STATUS=$?
fi
unset -f sync
[[ "$DB_GUARD_RESOLVE_STATUS" == 125 && \
  -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
  "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == \
    "$DB_GUARD_MARKER_ID" ]] \
  || fail 'failed parent sync did not restore the active database guard'
resolve_restore_db_guard || fail 'database guard resolution failed'
[[ ! -e "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
  -d "$RESTORE_DB_RESOLVED_DIR" && ! -L "$RESTORE_DB_RESOLVED_DIR" && \
  "$(stat -Lc '%d:%i' -- "$RESTORE_DB_RESOLVED_DIR")" == \
    "$DB_GUARD_MARKER_ID" && \
  "$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${RESTORE_DB_ABORT_FD}")" == \
    "$DB_GUARD_MARKER_ID" ]]
RESTORE_COMPLETE=true
RESTORE_DB_GUARD_ARMED=false
trap - ERR EXIT HUP INT TERM
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
unset -f docker compose_db_guard_stub
exec {RESTORE_DB_ABORT_FD}<&-
exec {DB_ROLLBACK_DIR_FD}<&-
exec {RESTORE_OLD_FD}<&-
exec {RESTORE_OPERATION_PARENT_FD}<&-
exec {AUTHENTIK_OPERATION_LOCK_FD}<&-
cd -- "$DB_GUARD_ORIGINAL_PWD"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RESTORE-ÆBORT REVERSE-SWÆP STÆTE MÆCHINE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
RESTORE_ABORT_SWAP_FUNCTION="$TEST_ROOT/restore-abort-swap-function.sh"
if ! awk '
  /^validate_restore_abort_move_path\(\)/ { capture=1 }
  /^rollback_restore_abort_files\(\)/ { exit }
  capture { print }
' "$README_FILE" > "$RESTORE_ABORT_SWAP_FUNCTION"; then
  fail 'restore-abort reverse-swap extraction failed'
fi
[[ -s "$RESTORE_ABORT_SWAP_FUNCTION" ]] \
  || fail 'restore-abort reverse-swap function missing'
# shellcheck source=/dev/null
source "$RESTORE_ABORT_SWAP_FUNCTION"
sudo() { "$@"; }
snapshot_restore_abort_state() {
  local root="$1" path
  for path in live failed old; do
    if [[ -f "$root/$path" && ! -L "$root/$path" ]]; then
      printf '%s=%s\n' "$path" "$(<"$root/$path")"
    elif [[ -e "$root/$path" || -L "$root/$path" ]]; then
      printf '%s=unsafe\n' "$path"
    else
      printf '%s=absent\n' "$path"
    fi
  done
}
for bits in 000 001 010 011 100 101 110 111; do
  state_root="$TEST_ROOT/reverse-state-${bits}"
  mkdir -m 0700 -- "$state_root"
  [[ "${bits:0:1}" == 0 ]] || printf restored > "$state_root/live"
  [[ "${bits:1:1}" == 0 ]] || printf restored > "$state_root/failed"
  [[ "${bits:2:1}" == 0 ]] || printf original > "$state_root/old"
  if [[ "$bits" == 110 ]]; then
    printf original > "$state_root/live"
  fi
  before="$(snapshot_restore_abort_state "$state_root")"
  case "$bits" in
    011|101|110)
      reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
        "$state_root/old" || fail "valid reverse state ${bits} failed"
      reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
        "$state_root/old" || fail "reverse state ${bits} was not idempotent"
      [[ "$(<"$state_root/live")" == original && \
        "$(<"$state_root/failed")" == restored && \
        ! -e "$state_root/old" && ! -L "$state_root/old" ]] \
        || fail "valid reverse state ${bits} ended incorrectly"
      ;;
    *)
      if reverse_restore_abort_unit "$state_root/live" \
        "$state_root/failed" "$state_root/old"; then
        fail "invalid reverse state ${bits} was accepted"
      fi
      [[ "$(snapshot_restore_abort_state "$state_root")" == "$before" ]] \
        || fail "invalid reverse state ${bits} was mutated"
      ;;
  esac
done
for fail_after in 1 2; do
  state_root="$TEST_ROOT/reverse-injected-${fail_after}"
  mkdir -m 0700 -- "$state_root"
  printf restored > "$state_root/live"
  printf original > "$state_root/old"
  RESTORE_ABORT_MV_COUNT=0
  sudo() {
    ((RESTORE_ABORT_MV_COUNT+=1))
    "$@" || return
    [[ "$RESTORE_ABORT_MV_COUNT" != "$fail_after" ]]
  }
  if reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
    "$state_root/old"; then
    fail "injected reverse move ${fail_after} unexpectedly succeeded"
  fi
  sudo() { "$@"; }
  reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
    "$state_root/old" || fail "reverse retry ${fail_after} failed"
  [[ "$(<"$state_root/live")" == original && \
    "$(<"$state_root/failed")" == restored && \
    ! -e "$state_root/old" && ! -L "$state_root/old" ]] \
    || fail "reverse retry ${fail_after} did not converge"
done
for fail_after in {1..10}; do
  state_root="$TEST_ROOT/reverse-five-unit-${fail_after}"
  live_root="$state_root/live-root"
  old_root="$state_root/old"
  failed_root="$old_root/failed-live"
  mkdir -p -m 0700 -- "$live_root/appdata" "$live_root/secrets" \
    "$live_root/scripts" "$live_root/.run.conf" "$old_root/appdata" \
    "$old_root/secrets" "$old_root/scripts" "$old_root/.run.conf" \
    "$old_root/database" "$failed_root/scripts" "$failed_root/.run.conf"
  printf restored > "$live_root/appdata/value"
  printf restored > "$live_root/secrets/value"
  printf restored > "$live_root/app.env"
  printf restored > "$live_root/scripts/backup.cron"
  printf restored > "$live_root/.run.conf/.templates.lock"
  printf original > "$old_root/appdata/value"
  printf original > "$old_root/secrets/value"
  printf original > "$old_root/app.env"
  printf original > "$old_root/scripts/backup.cron"
  printf original > "$old_root/.run.conf/.templates.lock"
  printf database-sentinel > "$old_root/database/sentinel"
  printf metadata-sentinel > "$old_root/metadata"
  RESTORE_ABORT_MV_COUNT=0
  sudo() {
    ((RESTORE_ABORT_MV_COUNT+=1))
    "$@" || return
    [[ "$RESTORE_ABORT_MV_COUNT" != "$fail_after" ]]
  }
  failed_once=false
  while IFS='|' read -r live relative; do
    if ! reverse_restore_abort_unit "$live_root/$live" \
      "$failed_root/$relative" "$old_root/$relative"; then
      failed_once=true
      break
    fi
  done <<'EOF'
.run.conf/.templates.lock|.run.conf/.templates.lock
scripts/backup.cron|scripts/backup.cron
secrets|secrets
app.env|app.env
appdata|appdata
EOF
  [[ "$failed_once" == true ]] \
    || fail "five-unit injected move ${fail_after} did not fire"
  sudo() { "$@"; }
  while IFS='|' read -r live relative; do
    reverse_restore_abort_unit "$live_root/$live" \
      "$failed_root/$relative" "$old_root/$relative" \
      || fail "five-unit retry ${fail_after} failed at ${relative}"
  done <<'EOF'
.run.conf/.templates.lock|.run.conf/.templates.lock
scripts/backup.cron|scripts/backup.cron
secrets|secrets
app.env|app.env
appdata|appdata
EOF
  [[ "$(<"$live_root/appdata/value")" == original && \
    "$(<"$failed_root/appdata/value")" == restored && \
    "$(<"$live_root/secrets/value")" == original && \
    "$(<"$failed_root/secrets/value")" == restored && \
    "$(<"$live_root/app.env")" == original && \
    "$(<"$failed_root/app.env")" == restored && \
    "$(<"$live_root/scripts/backup.cron")" == original && \
    "$(<"$failed_root/scripts/backup.cron")" == restored && \
    "$(<"$live_root/.run.conf/.templates.lock")" == original && \
    "$(<"$failed_root/.run.conf/.templates.lock")" == restored && \
    "$(<"$old_root/database/sentinel")" == database-sentinel && \
    "$(<"$old_root/metadata")" == metadata-sentinel ]]
done
state_root="$TEST_ROOT/reverse-destination-injection"
mkdir -m 0700 -- "$state_root"
printf restored > "$state_root/live"
printf original > "$state_root/old"
sudo() {
  printf destination-sentinel > "$state_root/failed"
  "$@" 2>/dev/null
}
if reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
  "$state_root/old"; then
  fail 'file destination injection bypassed mv -Tn'
fi
[[ "$(<"$state_root/live")" == restored && \
  "$(<"$state_root/old")" == original && \
  "$(<"$state_root/failed")" == destination-sentinel ]] \
  || fail 'file destination injection clobbered a path'
sudo() { "$@"; }
state_root="$TEST_ROOT/reverse-directory-destination-injection"
mkdir -p -m 0700 -- "$state_root/live" "$state_root/old"
printf restored > "$state_root/live/value"
printf original > "$state_root/old/value"
sudo() {
  mkdir -m 0700 -- "$state_root/failed"
  "$@" 2>/dev/null
}
if reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
  "$state_root/old"; then
  fail 'directory destination injection bypassed mv -Tn'
fi
[[ "$(<"$state_root/live/value")" == restored && \
  "$(<"$state_root/old/value")" == original && \
  -d "$state_root/failed" && -z "$(find "$state_root/failed" -mindepth 1 \
    -print -quit)" ]] || fail 'directory destination injection clobbered a path'
sudo() { "$@"; }
state_root="$TEST_ROOT/reverse-second-destination-injection"
mkdir -m 0700 -- "$state_root"
printf restored > "$state_root/live"
printf original > "$state_root/old"
RESTORE_ABORT_MV_COUNT=0
sudo() {
  ((RESTORE_ABORT_MV_COUNT+=1))
  if [[ "$RESTORE_ABORT_MV_COUNT" == 2 ]]; then
    printf second-destination-sentinel > "$state_root/live"
  fi
  "$@" 2>/dev/null
}
if reverse_restore_abort_unit "$state_root/live" "$state_root/failed" \
  "$state_root/old"; then
  fail 'second destination injection bypassed mv -Tn'
fi
[[ "$(<"$state_root/live")" == second-destination-sentinel && \
  "$(<"$state_root/failed")" == restored && \
  "$(<"$state_root/old")" == original ]] \
  || fail 'second destination injection clobbered a path'
sudo() { "$@"; }
state_root="$TEST_ROOT/reverse-unsafe-paths"
mkdir -m 0700 -- "$state_root"
printf safe > "$state_root/regular"
ln -s -- regular "$state_root/symlink"
mkfifo -- "$state_root/fifo"
if validate_restore_abort_move_path "$state_root/symlink"; then
  fail 'reverse-swap move guard accepted a symlink'
fi
if validate_restore_abort_move_path "$state_root/fifo"; then
  fail 'reverse-swap move guard accepted a FIFO'
fi
RESTORE_ABORT_MOUNT_TARGET="$(readlink -e -- "$state_root/regular")"
if (
  findmnt() {
    printf '{"filesystems":[{"target":"%s"}]}\n' \
      "$RESTORE_ABORT_MOUNT_TARGET"
  }
  validate_restore_abort_move_path "$state_root/regular"
); then
  fail 'reverse-swap move guard accepted a declared mount'
fi
if (
  stat() {
    if [[ "$*" == *"-- $state_root/regular" ]]; then
      printf '999999\n'
    else
      command stat "$@"
    fi
  }
  validate_restore_abort_move_path "$state_root/regular"
); then
  fail 'reverse-swap move guard accepted a cross-device path'
fi
sudo() { "$@"; }

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RESTORE-ÆBORT DÆTÆBÆSE FILE PINS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
RESTORE_ABORT_PIN_FUNCTIONS="$TEST_ROOT/restore-abort-pin-functions.sh"
if ! awk '
  /^validate_restore_abort_database_file\(\)/ { capture=1 }
  /^validate_restore_abort_recovery_state\(\)/ { exit }
  capture { print }
' "$README_FILE" > "$RESTORE_ABORT_PIN_FUNCTIONS"; then
  fail 'restore-abort database-pin extraction failed'
fi
[[ -s "$RESTORE_ABORT_PIN_FUNCTIONS" ]] \
  || fail 'restore-abort database-pin functions missing'
# shellcheck source=/dev/null
source "$RESTORE_ABORT_PIN_FUNCTIONS"
RESTORE_ABORT_PIN_ROOT="$TEST_ROOT/restore-abort-pin"
DB_ROLLBACK_DIR="$RESTORE_ABORT_PIN_ROOT/database"
mkdir -m 0700 -- "$RESTORE_ABORT_PIN_ROOT" "$DB_ROLLBACK_DIR"
DB_ROLLBACK_DIR_FD=''
exec {DB_ROLLBACK_DIR_FD}<"$DB_ROLLBACK_DIR"
RESTORE_ABORT_INVENTORY="$(mktemp \
  "$TEST_ROOT/restore-abort-pin-inventory.XXXXXX")"
exec {RESTORE_ABORT_INVENTORY_FD}<"$RESTORE_ABORT_INVENTORY"
RESTORE_ROLLBACK_KIND=maintenance
unset RESTORE_DB_FILE_FDS RESTORE_DB_FILE_IDS RESTORE_DB_FILE_METADATA \
  RESTORE_DB_FILE_NAMES
declare -gA RESTORE_DB_FILE_FDS=()
declare -gA RESTORE_DB_FILE_IDS=()
declare -gA RESTORE_DB_FILE_METADATA=()
declare -ga RESTORE_DB_FILE_NAMES=()
jq -n '{version:1,kind:"maintenance",physical_id:"20260821_1",
  logical_id:"20260821_120000",payload_manifest_sha256:
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
  > "$DB_ROLLBACK_DIR/rollback.json"
for file in full_20260821_1.tar.zst \
  full_20260821_1.tar.zst.sha256 bundle_full_20260821_1.sha256 \
  full_20260821_1.manifest dump_20260821_120000.dump.zst \
  dump_20260821_120000.dump.zst.sha256 \
  bundle_dump_20260821_120000.sha256; do
  printf 'bound-%s\n' "$file" > "$DB_ROLLBACK_DIR/$file"
done
(
  cd -- "$DB_ROLLBACK_DIR"
  sha256sum -- full_* bundle_full_* dump_* bundle_dump_* > payload.sha256
)
chmod 0600 "$DB_ROLLBACK_DIR"/*
pin_restore_abort_database_files \
  || fail 'valid restore-abort database inventory was not pinned'
validate_restore_abort_payload \
  || fail 'valid restore-abort payload manifest was rejected'
PINNED_ROLLBACK_ID="${RESTORE_DB_FILE_IDS[rollback.json]}"
mv -T -- "$DB_ROLLBACK_DIR/rollback.json" \
  "$DB_ROLLBACK_DIR/rollback.json.original"
jq -n '{version:1,kind:"maintenance",physical_id:"20260821_1",
  logical_id:"20260821_120000",payload_manifest_sha256:
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
  > "$DB_ROLLBACK_DIR/rollback.json"
chmod 0600 "$DB_ROLLBACK_DIR/rollback.json"
if validate_restore_abort_database_file rollback.json; then
  fail 'same-directory rollback-record leaf replacement passed its file pin'
fi
mv -T -- "$DB_ROLLBACK_DIR/rollback.json" \
  "$DB_ROLLBACK_DIR/rollback.json.replacement"
mv -T -- "$DB_ROLLBACK_DIR/rollback.json.original" \
  "$DB_ROLLBACK_DIR/rollback.json"
[[ "$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR/rollback.json")" == \
  "$PINNED_ROLLBACK_ID" ]]
close_restore_abort_database_files \
  || fail 'restore-abort database file descriptors did not close cleanly'
printf unexpected > "$DB_ROLLBACK_DIR/unexpected.bin"
chmod 0600 "$DB_ROLLBACK_DIR/unexpected.bin"
if pin_restore_abort_database_files; then
  fail 'extra restore-abort database evidence was accepted'
fi
close_restore_abort_database_files \
  || fail 'failed database-pin attempt leaked unclosable descriptors'
exec {RESTORE_ABORT_INVENTORY_FD}<&-
exec {DB_ROLLBACK_DIR_FD}<&-

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DOCKER-FREE HOLD RECONCILIÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
HOLD_FUNCTIONS="$TEST_ROOT/hold-functions.sh"
if ! awk '
  /^probe_image_reference\(\)/ && !capture { capture=1 }
  /^cleanup_abort_record_staging\(\)/ && capture { exit }
  capture { print }
' "$README_FILE" > "$HOLD_FUNCTIONS"; then
  fail 'hold function extraction failed'
fi
[[ -s "$HOLD_FUNCTIONS" ]] || fail 'hold functions were not found'
# shellcheck source=/dev/null
source "$HOLD_FUNCTIONS"
DOCKER_STUB_STATE=absent
DOCKER_STUB_ID="sha256:$(printf 'a%.0s' {1..64})"
DOCKER_STUB_DAEMON=ok
DOCKER_STUB_RM=ok
docker() {
  [[ "$1" == image ]] || return 64
  case "$2" in
    ls)
      [[ "$DOCKER_STUB_DAEMON" == ok ]] || return 125
      [[ "$DOCKER_STUB_STATE" == absent ]] || printf '%s\n' "$DOCKER_STUB_ID"
      ;;
    inspect)
      [[ "$DOCKER_STUB_DAEMON" == ok && "$DOCKER_STUB_STATE" == present ]] \
        || return 125
      printf '%s\n' "$DOCKER_STUB_ID"
      ;;
    rm)
      [[ "$DOCKER_STUB_DAEMON" == ok ]] || return 125
      DOCKER_STUB_STATE=absent
      [[ "$DOCKER_STUB_RM" == ok ]] || return 125
      ;;
    *) return 64 ;;
  esac
}
IMAGE_REFERENCE_STATE=unknown
IMAGE_REFERENCE_ID=''
probe_image_reference example.invalid/hold:test \
  || fail 'absent hold probe failed'
[[ "$IMAGE_REFERENCE_STATE" == absent ]]
DOCKER_STUB_DAEMON=failed
IMAGE_REFERENCE_STATE=unknown
if probe_image_reference example.invalid/hold:test; then
  fail 'daemon failure was classified as an absent hold'
fi
[[ "$IMAGE_REFERENCE_STATE" == unknown ]]
DOCKER_STUB_DAEMON=ok
DOCKER_STUB_STATE=present
DOCKER_STUB_RM=ok
ensure_image_reference_absent example.invalid/hold:test "$DOCKER_STUB_ID" \
  || fail 'exact present hold was not removed'
ensure_image_reference_absent example.invalid/hold:test "$DOCKER_STUB_ID" \
  || fail 'already absent hold was not idempotent'
DOCKER_STUB_STATE=present
DOCKER_STUB_RM=effective-error
ensure_image_reference_absent example.invalid/hold:test "$DOCKER_STUB_ID" \
  || fail 'effective removal with non-zero status was not reconciled'
DOCKER_STUB_STATE=present
DOCKER_STUB_RM=ok
WRONG_IMAGE="sha256:$(printf 'b%.0s' {1..64})"
if ensure_image_reference_absent example.invalid/hold:test "$WRONG_IMAGE"; then
  fail 'drifted hold image was removed'
fi
[[ "$DOCKER_STUB_STATE" == present ]]
DOCKER_STUB_DAEMON=failed
if ensure_image_reference_absent example.invalid/hold:test "$DOCKER_STUB_ID"; then
  fail 'daemon failure passed hold reconciliation'
fi

SUITE_COMPLETED=true
