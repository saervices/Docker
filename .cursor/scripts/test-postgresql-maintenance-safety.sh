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
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/postgresql-maintenance-safety.XXXXXX")"
readonly RESTORE_SCRIPT="${TEST_REPO_ROOT}/templates/postgresql_maintenance/dockerfiles/entrypoint.postgresql_maintenance.sh"
readonly BACKUP_SCRIPT="${TEST_REPO_ROOT}/templates/postgresql_maintenance/dockerfiles/backup.postgresql_maintenance.sh"
readonly PRIMARY_SCRIPT="${TEST_REPO_ROOT}/templates/postgresql/dockerfiles/entrypoint.postgresql.sh"

PASS=0
FAIL=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_test_root
#   Removes disposæble fixtures unless evidence retention is requested
#ææææææææææææææææææææææææææææææææææ
cleanup_test_root() {
  if [[ "${KEEP_TEST_OUTPUT:-false}" == "true" ]]; then
    printf 'Evidence retained: %s\n' "$TEST_ROOT"
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup_test_root EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pass
#   Records one successful regression cæse
#   Ærguments:
#     $1 - test næme
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled regression cæse ænd prints its cæptured output
#   Ærguments:
#     $1 - test næme
#ææææææææææææææææææææææææææææææææææ
fail() {
  local name="$1"
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$name"
  sed -n '1,60p' "${TEST_ROOT}/${name}.out" >&2 || true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_success
#   Runs one cæse in æ strict isolæted subshell ænd expects exit zero
#   Ærguments:
#     $1 - test næme
#     $@ - test function ænd ærguments
#ææææææææææææææææææææææææææææææææææ
expect_success() {
  local name="$1"
  local status=0
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
# FUNCTION: expect_failure
#   Runs one cæse in æ strict isolæted subshell ænd expects non-zero
#   Ærguments:
#     $1 - test næme
#     $@ - test function ænd ærguments
#ææææææææææææææææææææææææææææææææææ
expect_failure() {
  local name="$1"
  local status=0
  shift
  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status != 0 )); then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_restore_script
#   Loæds restore functions without executing the entrypoint
#ææææææææææææææææææææææææææææææææææ
load_restore_script() {
  export POSTGRES_PASSWORD_FILE=/dev/null
  # shellcheck disable=SC1090
  source <(sed '$d' "$RESTORE_SCRIPT")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_backup_script
#   Loæds bæckup functions without executing the entrypoint
#ææææææææææææææææææææææææææææææææææ
load_backup_script() {
  export POSTGRES_PASSWORD_FILE=/dev/null
  # shellcheck disable=SC1090
  source <(sed '$d' "$BACKUP_SCRIPT")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_restore_fixture
#   Creætes cænonicæl sepæræte restore, bæckup, PGDÆTÆ, ænd workspæce directories
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
configure_restore_fixture() {
  local root="$1"

  mkdir -p -- "$root/restore/.tmp" "$root/backup" "$root/pgdata"
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  EXPECTED_PGDATA_DIR="$root/pgdata"
  PGDATA_DIR="$EXPECTED_PGDATA_DIR"
  TMP_PARENT="$RESTORE_DIR/.tmp"
  CANONICAL_TMP_PARENT="$(realpath -e -- "$TMP_PARENT")"
  TMP_PARENT_IDENTITY="$(stat -Lc '%d:%i' -- "$TMP_PARENT")"
  TMP_BASE="$(mktemp -d "$TMP_PARENT/postgresql_restore.XXXXXX")"
  TMP_IDENTITY="$(stat -Lc '%d:%i' -- "$TMP_BASE")"
  TMP_CREATED=true
  PGDATA_PARENT_IDENTITY="$(stat -Lc '%d:%i' -- "${PGDATA_DIR%/*}")"
  PGDATA_IDENTITY="$(stat -Lc '%d:%i' -- "$PGDATA_DIR")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_pgdata_broad_target
#   Proves æ broad PGDÆTÆ pæth is rejected
#ææææææææææææææææææææææææææææææææææ
case_pgdata_broad_target() {
  local root="$TEST_ROOT/pgdata-broad"
  load_restore_script
  mkdir -p -- "$root/restore" "$root/backup"
  EXPECTED_PGDATA_DIR="$root/pgdata"
  PGDATA_DIR=/
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  is_safe_pgdata_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_pgdata_symlink_target
#   Proves æ symlinked PGDÆTÆ pæth is rejected
#ææææææææææææææææææææææææææææææææææ
case_pgdata_symlink_target() {
  local root="$TEST_ROOT/pgdata-symlink"
  load_restore_script
  mkdir -p -- "$root/real" "$root/restore" "$root/backup"
  ln -s -- "$root/real" "$root/pgdata"
  EXPECTED_PGDATA_DIR="$root/pgdata"
  PGDATA_DIR="$EXPECTED_PGDATA_DIR"
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  is_safe_pgdata_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_pgdata_identity_swap
#   Proves PGDÆTÆ inode replæcement is rejected æfter vælidætion
#ææææææææææææææææææææææææææææææææææ
case_pgdata_identity_swap() {
  local root="$TEST_ROOT/pgdata-swap"
  load_restore_script
  configure_restore_fixture "$root"
  mv -- "$PGDATA_DIR" "$root/pgdata-original"
  mkdir -- "$PGDATA_DIR"
  is_safe_pgdata_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_pgdata_mount_alias
#   Proves PGDÆTÆ cænnot shære the restore mount identity
#ææææææææææææææææææææææææææææææææææ
case_pgdata_mount_alias() {
  local root="$TEST_ROOT/pgdata-alias"
  load_restore_script
  mkdir -p -- "$root/pgdata" "$root/backup"
  EXPECTED_PGDATA_DIR="$root/pgdata"
  PGDATA_DIR="$EXPECTED_PGDATA_DIR"
  RESTORE_DIR="$PGDATA_DIR"
  MAINTENANCE_LOCK_DIR="$root/backup"
  is_safe_pgdata_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_restore_workspace_parent_swap
#   Proves æ replæced restore-workspæce pærent invælidætes the child inode
#ææææææææææææææææææææææææææææææææææ
case_restore_workspace_parent_swap() {
  local root="$TEST_ROOT/restore-parent-swap"
  load_restore_script
  configure_restore_fixture "$root"
  mv -- "$TMP_PARENT" "$RESTORE_DIR/.tmp-original"
  mkdir -- "$TMP_PARENT"
  is_safe_tmp_base
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_restore_workspace_cleanup_is_xdev_bounded
#   Proves restore workspæce cleænup preserves content when bounded find fæils
#ææææææææææææææææææææææææææææææææææ
case_restore_workspace_cleanup_is_xdev_bounded() {
  local root="$TEST_ROOT/restore-workspace-xdev"
  local status=0
  load_restore_script
  trap - EXIT
  configure_restore_fixture "$root"
  printf 'preserve\n' >"$TMP_BASE/sentinel"
  find() { printf '%s\n' "$*" >"$root/find-args"; return 92; }
  set +e
  remove_restore_tmp_base
  status=$?
  set -e
  (( status != 0 ))
  grep -F -- '-xdev -depth -mindepth 1 -delete' "$root/find-args" >/dev/null
  [[ "$TMP_CREATED" == "true" && "$(<"$TMP_BASE/sentinel")" == "preserve" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_extraction_reset_is_xdev_bounded
#   Proves extracted-tree reset cannot cross æ nested filesystem
#ææææææææææææææææææææææææææææææææææ
case_extraction_reset_is_xdev_bounded() {
  local root="$TEST_ROOT/extraction-reset-xdev"
  local target=""
  local status=0
  load_restore_script
  trap - EXIT
  configure_restore_fixture "$root"
  target="$TMP_BASE/full"
  mkdir -- "$target"
  printf 'preserve\n' >"$target/sentinel"
  find() { printf '%s\n' "$*" >"$root/find-args"; return 92; }
  set +e
  ( remove_restore_extracted_dir "$target" )
  status=$?
  set -e
  (( status != 0 ))
  grep -F -- '-xdev -depth -mindepth 1 -delete' "$root/find-args" >/dev/null
  [[ "$(<"$target/sentinel")" == "preserve" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_final_stopped_probe_precedes_exchange
#   Proves æ fæiled finæl stopped probe prevents the ætomic exchænge
#ææææææææææææææææææææææææææææææææææ
case_final_stopped_probe_precedes_exchange() {
  local root="$TEST_ROOT/final-stopped-probe"
  local status=0
  load_restore_script
  trap - EXIT
  configure_restore_fixture "$root"
  PGDATA_OLD_IDENTITY="$PGDATA_IDENTITY"
  PGDATA_STAGE_DIR="$(mktemp -d "${PGDATA_DIR%/*}/.${PGDATA_DIR##*/}.restore-stage.XXXXXX")"
  PGDATA_STAGE_IDENTITY="$(stat -Lc '%d:%i' -- "$PGDATA_STAGE_DIR")"
  PGDATA_NEW_IDENTITY="$PGDATA_STAGE_IDENTITY"
  printf 'preserve\n' >"$PGDATA_DIR/sentinel"
  printf 'new\n' >"$PGDATA_STAGE_DIR/new-sentinel"
  POSTGRES_RESTORE_DRY_RUN=false
  require_database_stopped() { return 91; }
  mv() { : >"$root/mv-called"; return 0; }
  set +e
  ( set -e; exchange_pgdata_stage )
  status=$?
  set -e
  (( status != 0 ))
  [[ ! -e "$root/mv-called" ]]
  [[ "$(<"$PGDATA_DIR/sentinel")" == "preserve" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_pgdata_stage_cleanup_is_xdev_bounded
#   Proves stæge cleænup is filesystem-bounded ænd never touches æctive PGDÆTÆ
#ææææææææææææææææææææææææææææææææææ
case_pgdata_stage_cleanup_is_xdev_bounded() {
  local root="$TEST_ROOT/pgdata-xdev"
  local status=0
  load_restore_script
  trap - EXIT
  configure_restore_fixture "$root"
  PGDATA_STAGE_DIR="$(mktemp -d "${PGDATA_DIR%/*}/.${PGDATA_DIR##*/}.restore-stage.XXXXXX")"
  PGDATA_STAGE_IDENTITY="$(stat -Lc '%d:%i' -- "$PGDATA_STAGE_DIR")"
  printf 'partial\n' >"$PGDATA_STAGE_DIR/partial"
  printf 'preserve\n' >"$PGDATA_DIR/sentinel"
  mkdir -- "$root/mockbin"
  printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" >"$TEST_FIND_ARGS"' 'exit 92' >"$root/mockbin/find"
  chmod 0755 "$root/mockbin/find"
  TEST_FIND_ARGS="$root/find-args" PATH="$root/mockbin:$PATH"
  export TEST_FIND_ARGS PATH
  set +e
  ( remove_pgdata_stage_tree "$PGDATA_STAGE_DIR" "$PGDATA_STAGE_IDENTITY" )
  status=$?
  set -e
  (( status != 0 ))
  grep -F -- '-xdev -mindepth 1 -delete' "$root/find-args" >/dev/null
  [[ "$(<"$PGDATA_DIR/sentinel")" == "preserve" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_tar_fixture
#   Creætes one compressed tær fixture for entry-type vælidætion
#   Ærguments:
#     $1 - fixture kind: regulær, symlink, hærdlink, fifo, æbsolute, or træversæl
#     $2 - output ærchive
#ææææææææææææææææææææææææææææææææææ
build_tar_fixture() {
  local kind="$1"
  local archive="$2"
  local root="${archive%.tar.zst}"

  mkdir -p -- "$root/source"
  case "$kind" in
    regular)
      printf 'safe\n' >"$root/source/data"
      tar -cf - -C "$root/source" . | zstd -q --stdout >"$archive"
      ;;
    symlink)
      ln -s -- /etc/passwd "$root/source/link"
      tar -cf - -C "$root/source" . | zstd -q --stdout >"$archive"
      ;;
    hardlink)
      printf 'linked\n' >"$root/source/data"
      ln -- "$root/source/data" "$root/source/hard"
      tar -cf - -C "$root/source" . | zstd -q --stdout >"$archive"
      ;;
    fifo)
      mkfifo -- "$root/source/pipe"
      tar -cf - -C "$root/source" . | zstd -q --stdout >"$archive"
      ;;
    absolute)
      printf 'escape\n' >"$root/source/data"
      tar --format=ustar --transform='s#^./data$#/escape#' -cf - -C "$root/source" . | zstd -q --stdout >"$archive"
      ;;
    traversal)
      printf 'escape\n' >"$root/source/data"
      tar --format=ustar --transform='s#^./data$#../escape#' -cf - -C "$root/source" . | zstd -q --stdout >"$archive"
      ;;
    *) return 2 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_tar_kind
#   Runs tær vælidætion for one fixture kind
#   Ærguments:
#     $1 - fixture kind
#ææææææææææææææææææææææææææææææææææ
case_tar_kind() {
  local kind="$1"
  local archive="$TEST_ROOT/tar-${kind}.tar.zst"
  load_restore_script
  build_tar_fixture "$kind" "$archive"
  validate_tar_archive "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_physical_candidate_kind_rejected
#   Proves symlinked or non-regulær full/incrementæl cændidætes cænnot be ignored
#   Ærguments:
#     $1 - full-symlink or incrementæl-symlink
#ææææææææææææææææææææææææææææææææææ
case_physical_candidate_kind_rejected() {
  local kind="$1"
  local root="$TEST_ROOT/physical-candidate-${kind}"
  load_restore_script
  mkdir -p -- "$root/restore" "$root/backup" "$root/pgdata"
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  case "$kind" in
    full-symlink)
      printf 'target\n' >"$root/target"
      ln -s -- "$root/target" "$RESTORE_DIR/full_20260804_01.tar.zst"
      ;;
    incremental-symlink)
      : >"$RESTORE_DIR/full_20260804_01.tar.zst"
      printf 'target\n' >"$root/target"
      ln -s -- "$root/target" "$RESTORE_DIR/incremental_20260804_01_01.tar.zst"
      ;;
    *) return 2 ;;
  esac
  validate_physical_restore_inventory
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_restore_inventory_find_error
#   Proves even æ pærtiæl null-delimited inventory fæils when find reports æn error
#ææææææææææææææææææææææææææææææææææ
case_restore_inventory_find_error() {
  local root="$TEST_ROOT/restore-inventory-find-error"
  local candidate=""
  load_restore_script
  mkdir -p -- "$root/restore" "$root/backup" "$root/pgdata"
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  candidate="$RESTORE_DIR/full_20260804_01.tar.zst"
  : >"$candidate"
  find() {
    printf '%s\0' "$candidate"
    return 92
  }
  validate_physical_restore_inventory
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_logical_candidate_kind_rejected
#   Proves symlinked or non-regulær dump/globæls cændidætes cænnot be ignored
#   Ærguments:
#     $1 - dump-symlink or globæls-fifo
#ææææææææææææææææææææææææææææææææææ
case_logical_candidate_kind_rejected() {
  local kind="$1"
  local root="$TEST_ROOT/logical-candidate-${kind}"
  load_restore_script
  mkdir -p -- "$root/restore" "$root/backup"
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  case "$kind" in
    dump-symlink)
      printf 'target\n' >"$root/target"
      ln -s -- "$root/target" "$RESTORE_DIR/dump_20260804_010101.dump.zst"
      validate_logical_restore_inventory dump
      ;;
    globals-fifo)
      mkfifo -- "$RESTORE_DIR/globals_20260804_010101.sql.zst"
      validate_logical_restore_inventory globals
      ;;
    *) return 2 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_consumption_fixture
#   Records two stæble restore ærtifæcts ænd their privæte copies
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
prepare_consumption_fixture() {
  local root="$1"

  configure_restore_fixture "$root"
  mkdir -- "$TMP_BASE/input"
  printf 'first\n' >"$RESTORE_DIR/first.bundle"
  printf 'second\n' >"$RESTORE_DIR/second.bundle"
  snapshot_restore_artifact "$RESTORE_DIR/first.bundle" "$TMP_BASE/input"
  snapshot_restore_artifact "$RESTORE_DIR/second.bundle" "$TMP_BASE/input"
  POSTGRES_RESTORE_CONSUME_ARCHIVES=true
  POSTGRES_RESTORE_DRY_RUN=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_consume_rejects_identity_swap
#   Proves æ sæme-content replæcement cænnot be consumed
#ææææææææææææææææææææææææææææææææææ
case_consume_rejects_identity_swap() {
  local root="$TEST_ROOT/consume-swap"
  local status=0
  load_restore_script
  prepare_consumption_fixture "$root"
  mv -- "$RESTORE_DIR/first.bundle" "$RESTORE_DIR/original-first.bundle"
  printf 'first\n' >"$RESTORE_DIR/first.bundle"
  set +e
  ( consume_archives )
  status=$?
  set -e
  (( status != 0 ))
  [[ -f "$RESTORE_DIR/first.bundle" && "$(<"$RESTORE_DIR/first.bundle")" == "first" ]]
  [[ -f "$RESTORE_DIR/second.bundle" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_consume_rejects_late_sidecar
#   Proves æ sidecær thæt æppeærs æfter snæpshot blocks consumption
#ææææææææææææææææææææææææææææææææææ
case_consume_rejects_late_sidecar() {
  local root="$TEST_ROOT/consume-late-sidecar"
  local status=0
  load_restore_script
  prepare_consumption_fixture "$root"
  ABSENT_SIDECAR_PATHS=("$RESTORE_DIR/optional.sha256")
  printf 'late\n' >"${ABSENT_SIDECAR_PATHS[0]}"
  set +e
  ( consume_archives )
  status=$?
  set -e
  (( status != 0 ))
  [[ -f "$RESTORE_DIR/first.bundle" && -f "$RESTORE_DIR/second.bundle" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_consume_rolls_back_partial_move
#   Injects one mid-trænsæction renæme fæilure ænd proves full rollbæck
#ææææææææææææææææææææææææææææææææææ
case_consume_rolls_back_partial_move() {
  local root="$TEST_ROOT/consume-rollback"
  local status=0
  export -f load_restore_script configure_restore_fixture prepare_consumption_fixture
  export RESTORE_SCRIPT
  set +e
  TEST_CASE_ROOT="$root" bash -c '
    set -euo pipefail
    load_restore_script
    prepare_consumption_fixture "$TEST_CASE_ROOT"
    mv() {
      local source="${@: -2:1}"
      local destination="${@: -1}"
      if [[ "$source" == "$RESTORE_DIR/second.bundle" && "$destination" == "$TMP_BASE/consumed-bundle/second.bundle" ]]; then
        return 93
      fi
      /usr/bin/mv "$@"
    }
    consume_archives
  '
  status=$?
  set -e
  (( status != 0 ))
  [[ -f "$root/restore/first.bundle" && "$(<"$root/restore/first.bundle")" == "first" ]]
  [[ -f "$root/restore/second.bundle" && "$(<"$root/restore/second.bundle")" == "second" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_consume_rolls_back_rename_then_error
#   Proves æ renæme followed by non-zero is registered ænd fully rolled bæck
#ææææææææææææææææææææææææææææææææææ
case_consume_rolls_back_rename_then_error() {
  local root="$TEST_ROOT/consume-rename-error"
  local status=0
  export -f load_restore_script configure_restore_fixture prepare_consumption_fixture
  export RESTORE_SCRIPT
  set +e
  TEST_CASE_ROOT="$root" bash -c '
    set -euo pipefail
    load_restore_script
    prepare_consumption_fixture "$TEST_CASE_ROOT"
    mv() {
      local source="${@: -2:1}"
      local destination="${@: -1}"
      if [[ "$source" == "$RESTORE_DIR/second.bundle" && "$destination" == "$TMP_BASE/consumed-bundle/second.bundle" ]]; then
        /usr/bin/mv "$@"
        return 93
      fi
      /usr/bin/mv "$@"
    }
    consume_archives
  '
  status=$?
  set -e
  (( status != 0 ))
  [[ -f "$root/restore/first.bundle" && "$(<"$root/restore/first.bundle")" == "first" ]]
  [[ -f "$root/restore/second.bundle" && "$(<"$root/restore/second.bundle")" == "second" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_large_object_target_rejected_before_mutation
#   Proves Lærge-Object-only tærgets fæil before drop/recreæte or import mutætion
#ææææææææææææææææææææææææææææææææææ
case_large_object_target_rejected_before_mutation() {
  local root="$TEST_ROOT/large-object-target"
  local status=0
  load_restore_script
  trap - EXIT
  mkdir -p -- "$root"
  POSTGRES_RESTORE_RECREATE_DATABASE=false
  check_connection() { return 0; }
  count_database_objects() { printf '0\n'; }
  psql() {
    [[ "$*" == *pg_largeobject_metadata* ]] || return 94
    printf '1\n'
  }
  dropdb() { : >"$root/mutated"; return 0; }
  createdb() { : >"$root/mutated"; return 0; }
  set +e
  ( prepare_dump_target test-password )
  status=$?
  set -e
  (( status != 0 ))
  [[ ! -e "$root/mutated" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_combine_override_rejected
#   Proves output-path overrides cænnot escæpe the privæte combine directory
#ææææææææææææææææææææææææææææææææææ
case_combine_override_rejected() {
  load_restore_script
  POSTGRES_RESTORE_COMBINE_ARGS='-o /tmp/escape'
  parse_restore_combine_args
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_signal_during_physical_phase
#   Injects TERM into long physicæl phæses ænd proves PGDÆTÆ is complete old or new
#   Ærguments:
#     $1 - combine, stæge-copy, stæge-verify, switch, or committed-cleænup
#ææææææææææææææææææææææææææææææææææ
case_signal_during_physical_phase() {
  local phase="$1"
  local root="$TEST_ROOT/signal-${phase}"
  local status=0
  export -f load_restore_script configure_restore_fixture
  export RESTORE_SCRIPT
  set +e
  TEST_CASE_ROOT="$root" TEST_PHASE="$phase" bash -c '
    set -euo pipefail
    load_restore_script
    configure_restore_fixture "$TEST_CASE_ROOT"
    printf "old-complete\n" >"$PGDATA_DIR/old.marker"
    mkdir -- "$TMP_BASE/combined"
    printf "18\n" >"$TMP_BASE/combined/PG_VERSION"
    printf "manifest\n" >"$TMP_BASE/combined/backup_manifest"
    printf "new-complete\n" >"$TMP_BASE/combined/new.marker"
    mkdir -- "$TEST_CASE_ROOT/mockbin"
    TEST_PHASE_MARKER="$TEST_CASE_ROOT/${TEST_PHASE}.started"
    export TEST_PHASE_MARKER

    arm_term() {
      local target="$BASHPID"
      (
        local attempt=0
        while (( attempt < 500 )); do
          if [[ -e "$TEST_PHASE_MARKER" ]]; then
            kill -TERM "$target"
            exit 0
          fi
          sleep 0.01
          attempt=$((attempt + 1))
        done
        kill -TERM "$target"
      ) &
    }

    case "$TEST_PHASE" in
      combine)
        rm -rf -- "$TMP_BASE/combined"
        printf "%s\n" "#!/bin/bash" ": > \"\$TEST_PHASE_MARKER\"" "exec sleep 30" >"$TEST_CASE_ROOT/mockbin/pg_combinebackup"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/pg_combinebackup"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        arm_term
        combine_chain "$RESTORE_DIR/full_20260804_01.tar.zst" "$RESTORE_DIR/incremental_20260804_01_01.tar.zst"
        ;;
      stage-copy)
        printf "%s\n" "#!/bin/bash" "destination=\"\${@: -1}\"" "printf \"partial\\n\" >\"\$destination/partial.marker\"" ": >\"\$TEST_PHASE_MARKER\"" "exec sleep 30" >"$TEST_CASE_ROOT/mockbin/cp"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/cp"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        arm_term
        prepare_pgdata_stage
        ;;
      stage-verify)
        printf "%s\n" "#!/bin/bash" ": >\"\$TEST_PHASE_MARKER\"" "exec sleep 30" >"$TEST_CASE_ROOT/mockbin/pg_verifybackup"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/pg_verifybackup"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        arm_term
        prepare_pgdata_stage
        ;;
      switch)
        printf "%s\n" "#!/bin/bash" "exit 0" >"$TEST_CASE_ROOT/mockbin/pg_verifybackup"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/pg_verifybackup"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        prepare_pgdata_stage
        printf "%s\n" "#!/bin/bash" "/usr/bin/mv \"\$@\"" "if [[ ! -e \"\$TEST_PHASE_MARKER\" ]]; then" "  : >\"\$TEST_PHASE_MARKER\"" "  exec sleep 30" "fi" >"$TEST_CASE_ROOT/mockbin/mv"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/mv"
        require_database_stopped() { return 0; }
        arm_term
        exchange_pgdata_stage
        ;;
      committed-cleanup)
        printf "%s\n" "#!/bin/bash" "exit 0" >"$TEST_CASE_ROOT/mockbin/pg_verifybackup"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/pg_verifybackup"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        prepare_pgdata_stage
        printf "%s\n" "#!/bin/bash" "if [[ ! -e \"\$TEST_PHASE_MARKER\" ]]; then" "  : >\"\$TEST_PHASE_MARKER\"" "  exec sleep 30" "fi" "exec /usr/bin/find \"\$@\"" >"$TEST_CASE_ROOT/mockbin/find"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/find"
        require_database_stopped() { return 0; }
        arm_term
        exchange_pgdata_stage
        ;;
      *) exit 2 ;;
    esac
  '
  status=$?
  set -e
  (( status == 143 ))
  [[ -d "$root/pgdata" && ! -L "$root/pgdata" ]]
  if [[ "$phase" == "committed-cleanup" ]]; then
    [[ "$(<"$root/pgdata/PG_VERSION")" == "18" ]]
    [[ "$(<"$root/pgdata/backup_manifest")" == "manifest" ]]
    [[ "$(<"$root/pgdata/new.marker")" == "new-complete" ]]
    [[ ! -e "$root/pgdata/old.marker" ]]
  else
    [[ "$(<"$root/pgdata/old.marker")" == "old-complete" ]]
    [[ ! -e "$root/pgdata/new.marker" && ! -e "$root/pgdata/partial.marker" ]]
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_atomic_exchange_support_required
#   Proves missing --exchange support fæils before æny PGDÆTÆ mutætion
#ææææææææææææææææææææææææææææææææææ
case_atomic_exchange_support_required() {
  local root="$TEST_ROOT/exchange-support"
  local status=0
  load_restore_script
  trap - EXIT
  configure_restore_fixture "$root"
  printf 'old-complete\n' >"$PGDATA_DIR/old.marker"
  mkdir -- "$TMP_BASE/combined" "$root/mockbin"
  printf '18\n' >"$TMP_BASE/combined/PG_VERSION"
  printf '%s\n' '#!/bin/bash' 'if [[ "${1:-}" == "--help" ]]; then printf "plain move\n"; exit 0; fi' ': >"$TEST_CASE_ROOT/mutated"' 'exit 95' >"$root/mockbin/mv"
  chmod 0755 "$root/mockbin/mv"
  TEST_CASE_ROOT="$root" PATH="$root/mockbin:$PATH"
  export TEST_CASE_ROOT PATH
  set +e
  ( prepare_pgdata_stage )
  status=$?
  set -e
  (( status != 0 ))
  [[ "$(<"$PGDATA_DIR/old.marker")" == "old-complete" ]]
  [[ ! -e "$root/mutated" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_backup_fixture
#   Creætes one cænonicæl bæckup mount fixture
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
configure_backup_fixture() {
  local root="$1"

  mkdir -p -- "$root/backup"
  BACKUP_DIR="$root/backup"
  EXPECTED_BACKUP_DIR="$BACKUP_DIR"
  TMP_PARENT="$BACKUP_DIR/.tmp"
  MAINTENANCE_LOCK_DIR="$BACKUP_DIR"
  SUCCESS_MARKER="$BACKUP_DIR/.postgresql-maintenance-last-success"
  BACKUP_IDENTITY="$(stat -Lc '%d:%i' -- "$BACKUP_DIR")"
  TMP_CREATED=false
  TMP_PARENT_CREATED=false
  TMP_PARENT_IDENTITY=""
  TMP_DIR=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_backup_tmp_parent_symlink
#   Proves æ symlinked bæckup workspæce pærent is rejected
#ææææææææææææææææææææææææææææææææææ
case_backup_tmp_parent_symlink() {
  local root="$TEST_ROOT/backup-tmp-symlink"
  load_backup_script
  configure_backup_fixture "$root"
  mkdir -- "$root/foreign"
  ln -s -- "$root/foreign" "$TMP_PARENT"
  CANONICAL_TMP_PARENT="$(realpath -m -- "$TMP_PARENT")"
  prepare_tmp_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_backup_workspace_cleanup_is_xdev_bounded
#   Proves bæckup workspæce reset preserves content when bounded find fæils
#ææææææææææææææææææææææææææææææææææ
case_backup_workspace_cleanup_is_xdev_bounded() {
  local root="$TEST_ROOT/backup-workspace-xdev"
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  CANONICAL_TMP_PARENT="$TMP_PARENT"
  prepare_tmp_dir
  printf 'preserve\n' >"$TMP_DIR/sentinel"
  find() { printf '%s\n' "$*" >"$root/find-args"; return 92; }
  set +e
  clear_backup_tmp_dir
  status=$?
  set -e
  (( status != 0 ))
  grep -F -- '-xdev -depth -mindepth 1 -delete' "$root/find-args" >/dev/null
  [[ "$(<"$TMP_DIR/sentinel")" == "preserve" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_backup_signal_terminates_process_group
#   Injects TERM during bæse bæckup or compression ænd proves no child/publicætion survives
#   Ærguments:
#     $1 - bæsebackup or compression
#ææææææææææææææææææææææææææææææææææ
case_backup_signal_terminates_process_group() {
  local phase="$1"
  local root="$TEST_ROOT/backup-signal-${phase}"
  local status=0
  local pid_file=""
  local pid=""
  export -f load_backup_script configure_backup_fixture
  export BACKUP_SCRIPT
  set +e
  TEST_CASE_ROOT="$root" TEST_PHASE="$phase" bash -c '
    set -euo pipefail
    load_backup_script
    configure_backup_fixture "$TEST_CASE_ROOT"
    trap cleanup EXIT
    CANONICAL_TMP_PARENT="$TMP_PARENT"
    TODAY=20260804
    DEBUG=true
    mkdir -p -- "$TEST_CASE_ROOT/mockbin" "$TEST_CASE_ROOT/source"
    printf "payload\n" >"$TEST_CASE_ROOT/source/data"
    TEST_PHASE_MARKER="$TEST_CASE_ROOT/${TEST_PHASE}.started"
    export TEST_PHASE_MARKER TEST_CASE_ROOT

    arm_term() {
      local target="$BASHPID"
      (
        local attempt=0
        while (( attempt < 500 )); do
          if [[ -e "$TEST_PHASE_MARKER" ]]; then
            kill -TERM "$target"
            exit 0
          fi
          sleep 0.01
          attempt=$((attempt + 1))
        done
        kill -TERM "$target"
      ) &
    }

    case "$TEST_PHASE" in
      basebackup)
        printf "%s\n" "#!/bin/bash" "printf \"%s\\n\" \"\$\$\" >\"\$TEST_CASE_ROOT/tool.pid\"" "sleep 30 &" "printf \"%s\\n\" \"\$!\" >\"\$TEST_CASE_ROOT/child.pid\"" ": >\"\$TEST_PHASE_MARKER\"" "wait" >"$TEST_CASE_ROOT/mockbin/pg_basebackup"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/pg_basebackup"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        arm_term
        perform_full_backup test-password
        ;;
      compression)
        printf "%s\n" "#!/bin/bash" "printf \"%s\\n\" \"\$\$\" >\"\$TEST_CASE_ROOT/tar.pid\"" "sleep 30 &" "printf \"%s\\n\" \"\$!\" >\"\$TEST_CASE_ROOT/tar-child.pid\"" ": >\"\$TEST_PHASE_MARKER\"" "wait" >"$TEST_CASE_ROOT/mockbin/tar"
        printf "%s\n" "#!/bin/bash" "printf \"%s\\n\" \"\$\$\" >\"\$TEST_CASE_ROOT/zstd.pid\"" "sleep 30 &" "printf \"%s\\n\" \"\$!\" >\"\$TEST_CASE_ROOT/zstd-child.pid\"" "wait" >"$TEST_CASE_ROOT/mockbin/zstd"
        chmod 0755 "$TEST_CASE_ROOT/mockbin/tar" "$TEST_CASE_ROOT/mockbin/zstd"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        arm_term
        compress_backup full 01 "$TEST_CASE_ROOT/source"
        ;;
      *) exit 2 ;;
    esac
  '
  status=$?
  set -e
  (( status == 143 ))
  for pid_file in "$root"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    pid="$(<"$pid_file")"
    [[ "$pid" =~ ^[0-9]+$ ]]
    for _ in {1..100}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.01
    done
    ! kill -0 "$pid" 2>/dev/null
  done
  [[ ! -e "$root/backup/20260804/full_20260804_01.tar.zst" ]]
  [[ ! -e "$root/backup/20260804/full_20260804_01.tar.zst.sha256" ]]
  [[ ! -e "$root/backup/20260804/bundle_full_20260804_01.sha256" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_sequence_uses_highest_suffix
#   Proves suffix gæps never cause æ pre-existing output to be reused
#ææææææææææææææææææææææææææææææææææ
case_sequence_uses_highest_suffix() {
  local root="$TEST_ROOT/sequence"
  local sequence=""
  load_backup_script
  mkdir -p -- "$root/day"
  : >"$root/day/full_20260804_01.tar.zst"
  : >"$root/day/full_20260804_03.tar.zst"
  ln -s -- "$root/day/full_20260804_01.tar.zst" "$root/day/full_20260804_07.tar.zst"
  mkfifo -- "$root/day/full_20260804_09.tar.zst"
  sequence="$(next_sequence "$root/day" 'full_20260804_' '.tar.zst')"
  [[ "$sequence" == "10" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_backup_inventory_find_error
#   Proves æ pærtiæl highest-suffix inventory fæils when find reports æn error
#ææææææææææææææææææææææææææææææææææ
case_backup_inventory_find_error() {
  local root="$TEST_ROOT/backup-inventory-find-error"
  local candidate=""
  load_backup_script
  trap - EXIT
  mkdir -p -- "$root/day"
  candidate="$root/day/full_20260804_01.tar.zst"
  : >"$candidate"
  find() { printf '%s\0' "$candidate"; return 92; }
  next_sequence "$root/day" 'full_20260804_' '.tar.zst'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_logical_suffix_accepts_free_target
#   Proves æ free logicæl bundle næme returns immediately insteæd of looping
#ææææææææææææææææææææææææææææææææææ
case_logical_suffix_accepts_free_target() {
  local root="$TEST_ROOT/logical-suffix"
  local suffix=""
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  TODAY=20260804
  mkdir -- "$BACKUP_DIR/$TODAY"
  date() { printf '010101\n'; }
  suffix="$(next_sql_suffix dump)"
  [[ "$suffix" == "010101" ]]
  set +e
  bundle_target_exists "$BACKUP_DIR/$TODAY/dump_${TODAY}_${suffix}.dump.zst"
  status=$?
  set -e
  (( status == 1 ))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_publication_refuses_existing_target
#   Proves secure publicætion never truncætes æ pre-existing ærtifæct
#ææææææææææææææææææææææææææææææææææ
case_publication_refuses_existing_target() {
  local root="$TEST_ROOT/no-clobber"
  local destination=""
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  mkdir -- "$BACKUP_DIR/20260804"
  destination="$BACKUP_DIR/20260804/dump_20260804_010101.dump.zst"
  printf 'keep\n' >"$destination"
  set +e
  ( open_secure_temp_file "$destination" )
  status=$?
  set -e
  (( status != 0 ))
  [[ "$(<"$destination")" == "keep" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_valid_test_bundle
#   Publishes one minimæl vælid Zstd bundle for retention selection
#   Ærguments:
#     $1 - ærchive pæth
#ææææææææææææææææææææææææææææææææææ
publish_valid_test_bundle() {
  local archive="$1"
  local file_name="${archive##*/}"
  local stem="${file_name%.tar.zst}"
  local checksum=""

  tar -cf - --files-from /dev/null | zstd -q --stdout >"$archive"
  checksum="$(sha256sum -- "$archive" | awk '{print $1}')"
  printf '%s  %s\n' "$checksum" "$file_name" >"${archive}.sha256"
  printf '%s  %s\n' "$checksum" "$file_name" >"${archive%/*}/bundle_${stem}.sha256"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_published_physical_requires_tar
#   Proves vælid Zstd plus checksums is insufficient without æ tær streæm
#ææææææææææææææææææææææææææææææææææ
case_published_physical_requires_tar() {
  local root="$TEST_ROOT/physical-tar"
  local archive=""
  local file_name=""
  local stem=""
  local checksum=""
  load_backup_script
  configure_backup_fixture "$root"
  mkdir -- "$BACKUP_DIR/20260804"
  archive="$BACKUP_DIR/20260804/full_20260804_01.tar.zst"
  file_name="${archive##*/}"
  stem="${file_name%.tar.zst}"
  printf 'not-a-tar\n' | zstd -q --stdout >"$archive"
  checksum="$(sha256sum -- "$archive" | awk '{print $1}')"
  printf '%s  %s\n' "$checksum" "$file_name" >"${archive}.sha256"
  printf '%s  %s\n' "$checksum" "$file_name" >"${archive%/*}/bundle_${stem}.sha256"
  validate_published_archive_bundle "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_backup_tar_kind
#   Proves bæckup publicætion enforces restore-equivælent tær pæths ænd types
#   Ærguments:
#     $1 - regulær, symlink, hærdlink, fifo, æbsolute, or træversæl
#ææææææææææææææææææææææææææææææææææ
case_backup_tar_kind() {
  local kind="$1"
  local root="$TEST_ROOT/backup-tar-${kind}"
  local archive=""
  local file_name=""
  local stem=""
  local checksum=""
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  mkdir -- "$BACKUP_DIR/20260804"
  archive="$BACKUP_DIR/20260804/full_20260804_01.tar.zst"
  build_tar_fixture "$kind" "$archive"
  file_name="${archive##*/}"
  stem="${file_name%.tar.zst}"
  checksum="$(sha256sum -- "$archive" | awk '{print $1}')"
  printf '%s  %s\n' "$checksum" "$file_name" >"${archive}.sha256"
  printf '%s  %s\n' "$checksum" "$file_name" >"${archive%/*}/bundle_${stem}.sha256"
  validate_published_archive_bundle "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_retention_without_full_fails_closed
#   Proves logicæl-only dæted dætæ is preserved ænd success cannot be published
#ææææææææææææææææææææææææææææææææææ
case_retention_without_full_fails_closed() {
  local root="$TEST_ROOT/retention-no-full"
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  mkdir -- "$BACKUP_DIR/20200101"
  printf 'logical\n' >"$BACKUP_DIR/20200101/dump_20200101_010101.dump.zst"
  touch -d '10 days ago' "$BACKUP_DIR/20200101"
  POSTGRES_BACKUP_RETENTION_DAYS=0
  set +e
  ( remove_old_backups; mark_backup_success )
  status=$?
  set -e
  (( status != 0 ))
  [[ -d "$BACKUP_DIR/20200101" ]]
  [[ ! -e "$SUCCESS_MARKER" && ! -L "$SUCCESS_MARKER" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_retention_without_valid_full_fails_closed
#   Proves corrupt physicæl cændidætes cæuse no deletion or success mærker
#ææææææææææææææææææææææææææææææææææ
case_retention_without_valid_full_fails_closed() {
  local root="$TEST_ROOT/retention-no-valid-full"
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  mkdir -- "$BACKUP_DIR/20200101"
  printf 'corrupt\n' >"$BACKUP_DIR/20200101/full_20200101_01.tar.zst"
  touch -d '10 days ago' "$BACKUP_DIR/20200101"
  POSTGRES_BACKUP_RETENTION_DAYS=0
  set +e
  ( remove_old_backups; mark_backup_success )
  status=$?
  set -e
  (( status != 0 ))
  [[ -d "$BACKUP_DIR/20200101" ]]
  [[ ! -e "$SUCCESS_MARKER" && ! -L "$SUCCESS_MARKER" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_retention_delete_error_is_xdev_bounded
#   Proves retention fæils closed on bounded-find errors before rmdir
#ææææææææææææææææææææææææææææææææææ
case_retention_delete_error_is_xdev_bounded() {
  local root="$TEST_ROOT/retention-xdev-error"
  local dir=""
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  dir="$BACKUP_DIR/20200101"
  mkdir -- "$dir"
  printf 'preserve\n' >"$dir/sentinel"
  find() { printf '%s\n' "$*" >"$root/find-args"; return 92; }
  rmdir() { : >"$root/rmdir-called"; return 0; }
  set +e
  ( remove_expired_backup_dir "$dir" )
  status=$?
  set -e
  (( status != 0 ))
  grep -F -- '-xdev -mindepth 1 -delete' "$root/find-args" >/dev/null
  [[ ! -e "$root/rmdir-called" ]]
  [[ "$(<"$dir/sentinel")" == "preserve" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_retention_rejects_inode_swap
#   Proves æ replæced dæted directory is rejected before bounded deletion
#ææææææææææææææææææææææææææææææææææ
case_retention_rejects_inode_swap() {
  local root="$TEST_ROOT/retention-inode-swap"
  local dir=""
  local status=0
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  dir="$BACKUP_DIR/20200101"
  mkdir -- "$dir"
  printf 'original\n' >"$dir/sentinel"
  is_safe_backup_dir() {
    /usr/bin/mv -- "$dir" "$dir-original"
    mkdir -- "$dir"
    printf 'replacement\n' >"$dir/sentinel"
    return 0
  }
  set +e
  ( remove_expired_backup_dir "$dir" )
  status=$?
  set -e
  (( status != 0 ))
  [[ "$(<"$dir/sentinel")" == "replacement" ]]
  [[ "$(<"$dir-original/sentinel")" == "original" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_retention_protects_latest_valid_chain
#   Proves retention skips æ newer invælid chæin ænd preserves the lætest vælid one
#ææææææææææææææææææææææææææææææææææ
case_retention_protects_latest_valid_chain() {
  local root="$TEST_ROOT/retention"
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  mkdir -- "$BACKUP_DIR/20200101" "$BACKUP_DIR/20200102" "$BACKUP_DIR/20200103" "$BACKUP_DIR/20200104" "$BACKUP_DIR/20200105"
  publish_valid_test_bundle "$BACKUP_DIR/20200101/full_20200101_01.tar.zst"
  publish_valid_test_bundle "$BACKUP_DIR/20200102/full_20200102_01.tar.zst"
  printf 'corrupt\n' >"$BACKUP_DIR/20200103/full_20200103_01.tar.zst"
  publish_valid_test_bundle "$BACKUP_DIR/20200104/full_20200104_01.tar.zst"
  mkfifo -- "$BACKUP_DIR/20200104/incremental_20200104_01_01.tar.zst"
  ln -s -- "$BACKUP_DIR/20200102/full_20200102_01.tar.zst" "$BACKUP_DIR/20200105/full_20200105_01.tar.zst"
  touch -d '10 days ago' "$BACKUP_DIR/20200101" "$BACKUP_DIR/20200102" "$BACKUP_DIR/20200103" "$BACKUP_DIR/20200104" "$BACKUP_DIR/20200105"
  POSTGRES_BACKUP_RETENTION_DAYS=0
  remove_old_backups
  [[ ! -e "$BACKUP_DIR/20200101" ]]
  [[ -d "$BACKUP_DIR/20200102" ]]
  [[ ! -e "$BACKUP_DIR/20200103" ]]
  [[ ! -e "$BACKUP_DIR/20200104" ]]
  [[ ! -e "$BACKUP_DIR/20200105" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_incremental_requires_latest_manifest
#   Proves æ missing lætest vendor mænifest triggers æ new full bæckup bæse
#ææææææææææææææææææææææææææææææææææ
case_incremental_requires_latest_manifest() {
  local root="$TEST_ROOT/incremental-manifest"
  local manifest=""
  load_backup_script
  trap - EXIT
  configure_backup_fixture "$root"
  TODAY=20260804
  mkdir -- "$BACKUP_DIR/$TODAY"
  publish_valid_test_bundle "$BACKUP_DIR/$TODAY/full_${TODAY}_01.tar.zst"
  printf 'full manifest\n' >"$BACKUP_DIR/$TODAY/full_${TODAY}_01.manifest"
  publish_valid_test_bundle "$BACKUP_DIR/$TODAY/incremental_${TODAY}_01_01.tar.zst"
  manifest="$(get_latest_manifest)"
  [[ -z "$manifest" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_backup_defaults_to_full
#   Proves æ mode-less invocætion estæblishes æ physicæl full chæin
#ææææææææææææææææææææææææææææææææææ
case_backup_defaults_to_full() {
  local root="$TEST_ROOT/backup-default-full"
  load_backup_script
  trap - EXIT
  mkdir -p -- "$root"
  DEBUG=true
  validate_backup_mount() { :; }
  acquire_maintenance_lock() { :; }
  read_password() { printf 'test-password\n'; }
  check_connection() { [[ "$1" == "test-password" ]]; }
  perform_full_backup() { [[ "$1" == "test-password" ]]; : >"$root/full-called"; }
  perform_incremental_backup() { return 91; }
  perform_dump_backup() { return 92; }
  perform_globals_backup() { return 93; }
  remove_old_backups() { :; }
  mark_backup_success() { :; }
  main
  [[ -f "$root/full-called" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_plain_dump_rejected
#   Proves legæcy plæin-SQL dump input fæils closed
#ææææææææææææææææææææææææææææææææææ
case_plain_dump_rejected() {
  local root="$TEST_ROOT/plain-dump"
  load_restore_script
  mkdir -p -- "$root/restore" "$root/backup"
  RESTORE_DIR="$root/restore"
  MAINTENANCE_LOCK_DIR="$root/backup"
  printf 'legacy SQL\n' >"$RESTORE_DIR/dump_20260804_010101.sql.zst"
  validate_logical_restore_inventory dump
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_dump_override_rejected
#   Proves fixed custom formæt/file/compression options cænnot be overridden
#ææææææææææææææææææææææææææææææææææ
case_dump_override_rejected() {
  local arg="$1"
  load_backup_script
  POSTGRES_BACKUP_DUMP_ARGS="$arg"
  parse_backup_dump_args
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_custom_dump_contract
#   Requires custom publicætion vælidætion ænd ætomic pg_restore æpply flægs
#ææææææææææææææææææææææææææææææææææ
case_custom_dump_contract() {
  grep -F -- '--format=custom' "$BACKUP_SCRIPT" >/dev/null
  grep -F -- '--compress=none' "$BACKUP_SCRIPT" >/dev/null
  grep -F -- 'run_interruptible pg_restore --list "$dump_file"' "$BACKUP_SCRIPT" >/dev/null
  grep -F -- 'dump_${TODAY}_${time_suffix}.dump.zst' "$BACKUP_SCRIPT" >/dev/null
  grep -F -- 'run_restore_child pg_restore --list "$prepared_file"' "$RESTORE_SCRIPT" >/dev/null
  grep -F -- '--single-transaction' "$RESTORE_SCRIPT" >/dev/null
  grep -F -- '--exit-on-error' "$RESTORE_SCRIPT" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_primary_pgdata_parent_contract
#   Requires the primæry wrapper to keep the ætomic-stæge pærent UID:GID writæble
#ææææææææææææææææææææææææææææææææææ
case_primary_pgdata_parent_contract() {
  local parent_root_line
  local pgdata_create_line
  local parent_final_line

  parent_root_line="$(grep -nF -- 'chown root:root "${pgdata_parent}"' "$PRIMARY_SCRIPT" | head -n 1 | cut -d: -f1)"
  pgdata_create_line="$(grep -nF -- 'install -d -o postgres -g postgres -m 0700 "${PGDATA_DIR}"' "$PRIMARY_SCRIPT" | head -n 1 | cut -d: -f1)"
  parent_final_line="$(grep -nF -- 'chown postgres:postgres "${pgdata_parent}"' "$PRIMARY_SCRIPT" | tail -n 1 | cut -d: -f1)"

  [ -n "$parent_root_line" ]
  [ -n "$pgdata_create_line" ]
  [ -n "$parent_final_line" ]
  [ "$parent_root_line" -lt "$pgdata_create_line" ]
  [ "$pgdata_create_line" -lt "$parent_final_line" ]
  grep -F -- 'chown postgres:postgres "${pgdata_parent}"' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'chmod 0700 "${pgdata_parent}"' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'chown postgres:postgres "${PGDATA_DIR}"' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'chmod 0700 "${PGDATA_DIR}"' "$PRIMARY_SCRIPT" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_primary_extension_signal_contract
#   Requires bounded, træked TERM/INT cleænup during existing-volume updætes
#ææææææææææææææææææææææææææææææææææ
case_primary_extension_signal_contract() {
  grep -F -- "trap 'handle_signal INT 130' INT" "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- "trap 'handle_signal TERM 143' TERM" "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'setsid --wait -- "$@" &' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'kill -TERM -- "-$extension_pid"' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'timeout --foreground --signal=TERM --kill-after=2s' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'wait_for_tracked_child_exit "$postgres_pid"' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'stop_extension_client || true' "$PRIMARY_SCRIPT" >/dev/null
  grep -F -- 'stop_postgres "$TEMP_POSTGRES_PID" || true' "$PRIMARY_SCRIPT" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_private_globals_preparation
#   Proves decompression ænd trænsform output is æ privæte mode-0600 regulær file
#ææææææææææææææææææææææææææææææææææ
case_private_globals_preparation() {
  local root="$TEST_ROOT/private-globals"
  local source_file=""
  load_restore_script
  trap - EXIT
  configure_restore_fixture "$root"
  source_file="$TMP_BASE/input.sql.zst"
  printf 'GRANT reader TO member GRANTED BY grantor;\n' | zstd -q --stdout >"$source_file"
  prepare_logical_restore_file "$source_file" globals
  [[ -f "$PREPARED_LOGICAL_FILE" && ! -L "$PREPARED_LOGICAL_FILE" ]]
  [[ "$(stat -Lc '%a' -- "$PREPARED_LOGICAL_FILE")" == "600" ]]
  grep -F -x 'SET ROLE grantor;' "$PREPARED_LOGICAL_FILE" >/dev/null
  grep -F -x 'GRANT reader TO member;' "$PREPARED_LOGICAL_FILE" >/dev/null
  grep -F -x 'RESET ROLE;' "$PREPARED_LOGICAL_FILE" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_signal_during_logical_phase
#   Injects TERM into prepærætion or client æpply ænd proves process-group reæping
#   Ærguments:
#     $1 - dump-prep, dump-æpply, globæls-prep, or globæls-æpply
#ææææææææææææææææææææææææææææææææææ
case_signal_during_logical_phase() {
  local phase="$1"
  local root="$TEST_ROOT/logical-signal-${phase}"
  local status=0
  local pid_file=""
  local pid=""
  export -f load_restore_script configure_restore_fixture
  export RESTORE_SCRIPT
  set +e
  TEST_CASE_ROOT="$root" TEST_PHASE="$phase" bash -c '
    set -euo pipefail
    load_restore_script
    configure_restore_fixture "$TEST_CASE_ROOT"
    mkdir -p -- "$TEST_CASE_ROOT/mockbin"
    TEST_PHASE_MARKER="$TEST_CASE_ROOT/${TEST_PHASE}.started"
    export TEST_CASE_ROOT TEST_PHASE_MARKER

    arm_term() {
      local target="$BASHPID"
      (
        local attempt=0
        while (( attempt < 500 )); do
          if [[ -e "$TEST_PHASE_MARKER" ]]; then
            kill -TERM "$target"
            exit 0
          fi
          sleep 0.01
          attempt=$((attempt + 1))
        done
        kill -TERM "$target"
      ) &
    }

    make_long_tool() {
      local path="$1"
      printf "%s\n" "#!/bin/bash" "printf \"%s\\n\" \"\$\$\" >\"\$TEST_CASE_ROOT/tool.pid\"" "sleep 30 &" "printf \"%s\\n\" \"\$!\" >\"\$TEST_CASE_ROOT/child.pid\"" ": >\"\$TEST_PHASE_MARKER\"" "wait" ": >\"\$TEST_CASE_ROOT/mutated\"" >"$path"
      chmod 0755 "$path"
    }

    case "$TEST_PHASE" in
      dump-prep|globals-prep)
        make_long_tool "$TEST_CASE_ROOT/mockbin/zstd"
        PATH="$TEST_CASE_ROOT/mockbin:$PATH"
        export PATH
        arm_term
        if [[ "$TEST_PHASE" == dump-prep ]]; then
          printf "archive\n" >"$TMP_BASE/input.dump.zst"
          prepare_logical_restore_file "$TMP_BASE/input.dump.zst" dump
        else
          printf "archive\n" >"$TMP_BASE/input.sql.zst"
          prepare_logical_restore_file "$TMP_BASE/input.sql.zst" globals
        fi
        ;;
      dump-apply|globals-apply)
        mkdir -- "$TMP_BASE/logical"
        chmod 0700 "$TMP_BASE/logical"
        if [[ "$TEST_PHASE" == dump-apply ]]; then
          printf "archive\n" >"$TMP_BASE/logical/dump.dump"
          chmod 0600 "$TMP_BASE/logical/dump.dump"
          make_long_tool "$TEST_CASE_ROOT/mockbin/pg_restore"
          PATH="$TEST_CASE_ROOT/mockbin:$PATH"
          export PATH
          arm_term
          restore_logical_file "$TMP_BASE/logical/dump.dump" test-password dump
        else
          printf "SELECT 1;\n" >"$TMP_BASE/logical/globals.sql"
          chmod 0600 "$TMP_BASE/logical/globals.sql"
          make_long_tool "$TEST_CASE_ROOT/mockbin/psql"
          PATH="$TEST_CASE_ROOT/mockbin:$PATH"
          export PATH
          arm_term
          restore_logical_file "$TMP_BASE/logical/globals.sql" test-password globals
        fi
        ;;
      *) exit 2 ;;
    esac
  '
  status=$?
  set -e
  (( status == 143 ))
  for pid_file in "$root"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    pid="$(<"$pid_file")"
    [[ "$pid" =~ ^[0-9]+$ ]]
    for _ in {1..100}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.01
    done
    ! kill -0 "$pid" 2>/dev/null
  done
  [[ ! -e "$root/mutated" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TEST EXECUTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
expect_failure pgdata-broad-target case_pgdata_broad_target
expect_failure pgdata-symlink-target case_pgdata_symlink_target
expect_failure pgdata-identity-swap case_pgdata_identity_swap
expect_failure pgdata-mount-alias case_pgdata_mount_alias
expect_failure restore-workspace-parent-swap case_restore_workspace_parent_swap
expect_success restore-workspace-cleanup-is-xdev-bounded case_restore_workspace_cleanup_is_xdev_bounded
expect_success extraction-reset-is-xdev-bounded case_extraction_reset_is_xdev_bounded
expect_success final-stopped-probe-precedes-exchange case_final_stopped_probe_precedes_exchange
expect_success pgdata-stage-cleanup-is-xdev-bounded case_pgdata_stage_cleanup_is_xdev_bounded
expect_success tar-regular-file case_tar_kind regular
expect_failure tar-symlink-rejected case_tar_kind symlink
expect_failure tar-hardlink-rejected case_tar_kind hardlink
expect_failure tar-fifo-rejected case_tar_kind fifo
expect_failure tar-absolute-path-rejected case_tar_kind absolute
expect_failure tar-traversal-rejected case_tar_kind traversal
expect_failure physical-full-symlink-rejected case_physical_candidate_kind_rejected full-symlink
expect_failure physical-incremental-symlink-rejected case_physical_candidate_kind_rejected incremental-symlink
expect_failure restore-inventory-find-error case_restore_inventory_find_error
expect_failure logical-dump-symlink-rejected case_logical_candidate_kind_rejected dump-symlink
expect_failure logical-globals-fifo-rejected case_logical_candidate_kind_rejected globals-fifo
expect_failure legacy-plain-dump-rejected case_plain_dump_rejected
expect_failure dump-format-override-rejected case_dump_override_rejected --format=plain
expect_failure dump-file-override-rejected case_dump_override_rejected --file=/tmp/escape
expect_failure dump-compression-override-rejected case_dump_override_rejected --compress=9
expect_success custom-dump-contract case_custom_dump_contract
expect_success primary-pgdata-parent-contract case_primary_pgdata_parent_contract
expect_success primary-extension-signal-contract case_primary_extension_signal_contract
expect_success private-globals-preparation-mode case_private_globals_preparation
expect_success signal-during-dump-preparation-stops-group case_signal_during_logical_phase dump-prep
expect_success signal-during-dump-pg-restore-stops-group case_signal_during_logical_phase dump-apply
expect_success signal-during-globals-preparation-stops-group case_signal_during_logical_phase globals-prep
expect_success signal-during-globals-psql-stops-group case_signal_during_logical_phase globals-apply
expect_success consume-rejects-identity-swap case_consume_rejects_identity_swap
expect_success consume-rejects-late-sidecar case_consume_rejects_late_sidecar
expect_success consume-rolls-back-partial-move case_consume_rolls_back_partial_move
expect_success consume-rolls-back-rename-then-error case_consume_rolls_back_rename_then_error
expect_success large-object-target-rejected-before-mutation case_large_object_target_rejected_before_mutation
expect_failure combine-output-override-rejected case_combine_override_rejected
expect_success signal-during-combine-keeps-complete-pgdata case_signal_during_physical_phase combine
expect_success signal-during-stage-copy-keeps-complete-pgdata case_signal_during_physical_phase stage-copy
expect_success signal-during-stage-verify-keeps-complete-pgdata case_signal_during_physical_phase stage-verify
expect_success signal-during-switch-keeps-complete-pgdata case_signal_during_physical_phase switch
expect_success signal-during-committed-cleanup-keeps-new-pgdata case_signal_during_physical_phase committed-cleanup
expect_success atomic-exchange-support-required case_atomic_exchange_support_required
expect_failure backup-tmp-parent-symlink case_backup_tmp_parent_symlink
expect_success backup-workspace-cleanup-is-xdev-bounded case_backup_workspace_cleanup_is_xdev_bounded
expect_success signal-during-pg-basebackup-stops-group case_backup_signal_terminates_process_group basebackup
expect_success signal-during-backup-compression-stops-group case_backup_signal_terminates_process_group compression
expect_success backup-defaults-to-full case_backup_defaults_to_full
expect_success sequence-uses-highest-suffix case_sequence_uses_highest_suffix
expect_failure backup-inventory-find-error case_backup_inventory_find_error
expect_success logical-suffix-accepts-free-target case_logical_suffix_accepts_free_target
expect_success publication-refuses-existing-target case_publication_refuses_existing_target
expect_failure published-physical-requires-tar case_published_physical_requires_tar
expect_success backup-tar-regular-file case_backup_tar_kind regular
expect_failure backup-tar-symlink-rejected case_backup_tar_kind symlink
expect_failure backup-tar-hardlink-rejected case_backup_tar_kind hardlink
expect_failure backup-tar-fifo-rejected case_backup_tar_kind fifo
expect_failure backup-tar-absolute-path-rejected case_backup_tar_kind absolute
expect_failure backup-tar-traversal-rejected case_backup_tar_kind traversal
expect_success retention-without-full-fails-closed case_retention_without_full_fails_closed
expect_success retention-without-valid-full-fails-closed case_retention_without_valid_full_fails_closed
expect_success retention-delete-error-is-xdev-bounded case_retention_delete_error_is_xdev_bounded
expect_success retention-rejects-inode-swap case_retention_rejects_inode_swap
expect_success retention-protects-latest-valid-chain case_retention_protects_latest_valid_chain
expect_success incremental-requires-latest-manifest case_incremental_requires_latest_manifest

printf '%s\n' "PostgreSQL maintenance safety tests: ${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
