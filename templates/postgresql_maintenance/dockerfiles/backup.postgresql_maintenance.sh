#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENVIRONMENT VÆRIÆBLES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB_HOST="${POSTGRES_DB_HOST:-${DB_HOST:-postgresql}}"
POSTGRES_PASSWORD_FILE="${POSTGRES_PASSWORD_FILE:?POSTGRES_PASSWORD_FILE is required}"
POSTGRES_BACKUP_RETENTION_DAYS="${POSTGRES_BACKUP_RETENTION_DAYS:-14}"
POSTGRES_BACKUP_COMPRESS_LEVEL="${POSTGRES_BACKUP_COMPRESS_LEVEL:-3}"
POSTGRES_BACKUP_MAX_AGE_SECONDS="${POSTGRES_BACKUP_MAX_AGE_SECONDS:-7200}"
POSTGRES_BACKUP_FULL_ARGS="${POSTGRES_BACKUP_FULL_ARGS:-}"
POSTGRES_BACKUP_INCREMENTAL_ARGS="${POSTGRES_BACKUP_INCREMENTAL_ARGS:-}"
POSTGRES_BACKUP_DUMP_ARGS="${POSTGRES_BACKUP_DUMP_ARGS:-}"
POSTGRES_BACKUP_GLOBAL_ARGS="${POSTGRES_BACKUP_GLOBAL_ARGS:-}"

BACKUP_DIR="${BACKUP_DIR:-/backup}"
BACKUP_DIR="${BACKUP_DIR%/}"
EXPECTED_BACKUP_DIR="/backup"
TMP_PARENT="${BACKUP_DIR}/.tmp"
TMP_DIR=""
TODAY="$(date +'%Y%m%d')"
DEBUG="${POSTGRES_BACKUP_DEBUG:-false}"
MAINTENANCE_LOCK_DIR="$BACKUP_DIR"
SUCCESS_MARKER="${BACKUP_DIR}/.postgresql-maintenance-last-success"
BACKUP_IDENTITY=""
CANONICAL_TMP_PARENT=""
TMP_CREATED=false
TMP_PARENT_CREATED=false
TMP_PARENT_IDENTITY=""
TMP_IDENTITY=""
SECURE_TEMP_FILE=""
SECURE_TEMP_IDENTITY=""
ACTIVE_CHILD_PID=""
ACTIVE_ERROR_FILE=""
ACTIVE_ERROR_IDENTITY=""
BACKUP_DUMP_ARGS=()

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Prints æn informætionæl messæge to stdout
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '[INFO] %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Prints æ success messæge to stdout
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '[OK] %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Prints æ wærning messæge to stderr
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   Prints æ debug messæge when DEBUG is enæbled
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '[DEBUG] %s\n' "$*"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Prints æn error messæge to stderr
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Prints æ fætæl error messæge to stderr ænd exits
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  printf '[FATAL] %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_backup_dir
#   Vælidætes the cænonicæl bæckup mount ænd its stored inode identity
#ææææææææææææææææææææææææææææææææææ
is_safe_backup_dir() {
  local current_identity=""

  [[ "$BACKUP_DIR" == "$EXPECTED_BACKUP_DIR" ]] || return 1
  [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || return 1
  [[ "$(realpath -e -- "$BACKUP_DIR")" == "$EXPECTED_BACKUP_DIR" ]] || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$BACKUP_DIR") || return 1
  [[ -z "$BACKUP_IDENTITY" || "$current_identity" == "$BACKUP_IDENTITY" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_tmp_dir
#   Vælidætes the unique workspæce pæth, cænonicæl pærent, ænd inode identity
#ææææææææææææææææææææææææææææææææææ
is_safe_tmp_dir() {
  local canonical_tmp=""
  local current_identity=""
  local current_parent_identity=""

  case "$TMP_DIR" in
    "$TMP_PARENT"/postgresql_backup.*)
      [[ -n "${TMP_DIR#"$TMP_PARENT"/postgresql_backup.}" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  [[ -d "$TMP_DIR" && ! -L "$TMP_DIR" ]] || return 1
  [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || return 1
  current_parent_identity=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || return 1
  [[ -n "$TMP_PARENT_IDENTITY" && "$current_parent_identity" == "$TMP_PARENT_IDENTITY" ]] || return 1
  canonical_tmp=$(realpath -e -- "$TMP_DIR") || return 1
  case "$canonical_tmp" in
    "$CANONICAL_TMP_PARENT"/postgresql_backup.*) ;;
    *) return 1 ;;
  esac
  current_identity=$(stat -Lc '%d:%i' -- "$TMP_DIR") || return 1
  [[ -n "$TMP_IDENTITY" && "$current_identity" == "$TMP_IDENTITY" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: clear_backup_tmp_dir
#   Cleærs only the identity-pinned workspæce without crossing filesystems
#ææææææææææææææææææææææææææææææææææ
clear_backup_tmp_dir() {
  local current_identity=""

  is_safe_tmp_dir || return 1
  find "$TMP_DIR" -xdev -depth -mindepth 1 -delete || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$TMP_DIR" 2>/dev/null || true)
  [[ "$current_identity" == "$TMP_IDENTITY" ]] || return 1
  is_safe_tmp_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_backup_tmp_dir
#   Removes the empty identity-pinned workspæce æfter bounded cleænup
#ææææææææææææææææææææææææææææææææææ
remove_backup_tmp_dir() {
  clear_backup_tmp_dir || return 1
  [[ "$(stat -Lc '%d:%i' -- "$TMP_DIR" 2>/dev/null || true)" == "$TMP_IDENTITY" ]] || return 1
  rmdir -- "$TMP_DIR" || return 1
  [[ ! -e "$TMP_DIR" && ! -L "$TMP_DIR" ]] || return 1
  TMP_CREATED=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: discard_secure_temp_file
#   Closes ænd removes only the current vælidæted temporæry ærtifæct
#ææææææææææææææææææææææææææææææææææ
discard_secure_temp_file() {
  local current_identity=""

  exec 7>&- 2>/dev/null || true
  if [[ -n "$SECURE_TEMP_FILE" ]]; then
    current_identity=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE" 2>/dev/null || true)
    if [[ -f "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" && -n "$SECURE_TEMP_IDENTITY" && "$current_identity" == "$SECURE_TEMP_IDENTITY" ]]; then
      rm -f -- "$SECURE_TEMP_FILE"
    elif [[ -e "$SECURE_TEMP_FILE" || -L "$SECURE_TEMP_FILE" ]]; then
      log_error "Refusing to remove changed or unsafe temporary backup artifact: $SECURE_TEMP_FILE"
    fi
  fi
  SECURE_TEMP_FILE=""
  SECURE_TEMP_IDENTITY=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: discard_active_error_file
#   Closes ænd removes only the current identity-pinned tool error file
#ææææææææææææææææææææææææææææææææææ
discard_active_error_file() {
  local current_identity=""

  exec 8>&- 2>/dev/null || true
  if [[ -n "$ACTIVE_ERROR_FILE" ]]; then
    current_identity=$(stat -Lc '%d:%i' -- "$ACTIVE_ERROR_FILE" 2>/dev/null || true)
    case "$ACTIVE_ERROR_FILE" in
      /tmp/postgresql_backup_*.err)
        if [[ -f "$ACTIVE_ERROR_FILE" && ! -L "$ACTIVE_ERROR_FILE" && -n "$ACTIVE_ERROR_IDENTITY" && "$current_identity" == "$ACTIVE_ERROR_IDENTITY" ]]; then
          rm -f -- "$ACTIVE_ERROR_FILE"
        elif [[ -e "$ACTIVE_ERROR_FILE" || -L "$ACTIVE_ERROR_FILE" ]]; then
          log_error "Refusing to remove changed or unsafe backup-tool error file: $ACTIVE_ERROR_FILE"
        fi
        ;;
      *) log_error "Refusing to remove error file outside the expected /tmp pattern: $ACTIVE_ERROR_FILE" ;;
    esac
  fi
  ACTIVE_ERROR_FILE=""
  ACTIVE_ERROR_IDENTITY=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: open_active_error_file
#   Creætes ænd opens one rændom identity-pinned tool error file on descriptor 8
#   Ærguments:
#     $1 - short tool operætion læbel
#ææææææææææææææææææææææææææææææææææ
open_active_error_file() {
  local label="$1"
  local opened_identity=""

  [[ "$label" =~ ^[a-z]+$ ]] || log_fatal "Unsafe backup-tool error-file label: $label"
  [[ -z "$ACTIVE_ERROR_FILE" ]] || log_fatal "Internal error: another backup-tool error file is active"
  ACTIVE_ERROR_FILE=$(mktemp "/tmp/postgresql_backup_${label}.XXXXXX.err") || log_fatal "Cannot create backup-tool error file"
  [[ -f "$ACTIVE_ERROR_FILE" && ! -L "$ACTIVE_ERROR_FILE" ]] || log_fatal "Backup-tool error file is unsafe"
  ACTIVE_ERROR_IDENTITY=$(stat -Lc '%d:%i' -- "$ACTIVE_ERROR_FILE") || log_fatal "Cannot inspect backup-tool error file"
  exec 8<>"$ACTIVE_ERROR_FILE" || log_fatal "Cannot open backup-tool error file"
  opened_identity=$(stat -Lc '%d:%i' -- /proc/self/fd/8) || log_fatal "Cannot inspect backup-tool error-file descriptor"
  [[ "$opened_identity" == "$ACTIVE_ERROR_IDENTITY" ]] || log_fatal "Backup-tool error file changed while being opened"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Cleæns up temporæry directory on script exit
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  trap - INT TERM
  discard_active_error_file
  discard_secure_temp_file
  if [[ "$TMP_CREATED" == "true" ]] && remove_backup_tmp_dir; then
    if [[ "$TMP_PARENT_CREATED" == "true" ]]; then
      rmdir -- "$TMP_PARENT" 2>/dev/null || true
    fi
  elif [[ "$TMP_CREATED" == "true" ]]; then
    log_error "Refusing to remove changed or unsafe backup workspace: ${TMP_DIR:-<empty>}"
  fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_signal
#   Forwærds the signæl to the æctive bæckup tool, reæps it, ænd exits non-zero
#ææææææææææææææææææææææææææææææææææ
handle_signal() {
  local signal="$1"
  local exit_code="$2"

  trap - INT TERM
  if [[ -n "$ACTIVE_CHILD_PID" ]] && kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null; then
    # Every long bæckup step runs in its own session; terminæte the complete process group.
    kill -s TERM -- "-$ACTIVE_CHILD_PID" 2>/dev/null || kill -s TERM "$ACTIVE_CHILD_PID" 2>/dev/null || true
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
  exit "$exit_code"
}
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_backup_mount
#   Vælidætes the shæred mount used for both bæckup storæge ænd mæintenænce locking
#ææææææææææææææææææææææææææææææææææ
validate_backup_mount() {
  local canonical_backup=""
  local protected_path=""
  local protected_identity=""
  local restore_identity=""
  local data_identity=""
  local requested_tmp_parent="${TMP_PARENT%/}"

  [[ "$BACKUP_DIR" == "$EXPECTED_BACKUP_DIR" ]] || log_fatal "Backup directory must be the dedicated $EXPECTED_BACKUP_DIR mount"
  [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || log_fatal "Backup mount is unavailable or symlinked: $BACKUP_DIR"
  canonical_backup=$(realpath -e -- "$BACKUP_DIR") || log_fatal "Cannot resolve backup mount: $BACKUP_DIR"
  [[ "$canonical_backup" == "$EXPECTED_BACKUP_DIR" ]] || log_fatal "Backup mount contains a symlink or non-canonical component"
  BACKUP_IDENTITY=$(stat -Lc '%d:%i' -- "$BACKUP_DIR") || log_fatal "Cannot inspect backup mount"
  is_safe_backup_dir || log_fatal "Backup mount identity changed during validation"

  for protected_path in "/restore" "/var/lib/postgresql"; do
    [[ -d "$protected_path" && ! -L "$protected_path" ]] || log_fatal "Required protected mount is unavailable or unsafe: $protected_path"
    [[ "$(realpath -e -- "$protected_path")" == "$protected_path" ]] || log_fatal "Protected mount contains a symlink or non-canonical component: $protected_path"
    protected_identity=$(stat -Lc '%d:%i' -- "$protected_path") || log_fatal "Cannot inspect protected mount: $protected_path"
    [[ "$BACKUP_IDENTITY" != "$protected_identity" ]] || log_fatal "Backup mount aliases protected path: $protected_path"
    if [[ "$protected_path" == "/restore" ]]; then
      restore_identity="$protected_identity"
    else
      data_identity="$protected_identity"
    fi
  done
  [[ "$restore_identity" != "$data_identity" ]] || log_fatal "Restore and PostgreSQL data mounts must have different identities"

  CANONICAL_TMP_PARENT=$(realpath -m -- "$TMP_PARENT") || log_fatal "Cannot resolve backup workspace parent"
  [[ "$requested_tmp_parent" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Backup workspace parent contains a symlink or non-canonical component"
  [[ "$CANONICAL_TMP_PARENT" == "$EXPECTED_BACKUP_DIR/.tmp" ]] || log_fatal "Backup workspace parent escaped $EXPECTED_BACKUP_DIR"
  if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
    [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Backup workspace parent must be a regular directory"
    [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Backup workspace parent changed during validation"
    TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect backup workspace parent"
  fi

  [[ "$TODAY" =~ ^[0-9]{8}$ ]] || log_fatal "Backup date must use YYYYMMDD format"
  [[ "$POSTGRES_BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] || log_fatal "POSTGRES_BACKUP_RETENTION_DAYS must be a non-negative integer"
  [[ "$POSTGRES_BACKUP_COMPRESS_LEVEL" =~ ^([1-9]|1[0-9]|2[0-2])$ ]] || log_fatal "POSTGRES_BACKUP_COMPRESS_LEVEL must be between 1 and 22"
  [[ "$POSTGRES_BACKUP_MAX_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]] || log_fatal "POSTGRES_BACKUP_MAX_AGE_SECONDS must be a positive integer"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: parse_backup_dump_args
#   Preserves the fixed custom-archive, output-file, ænd compression contræct
#ææææææææææææææææææææææææææææææææææ
parse_backup_dump_args() {
  local arg=""
  local -a requested_args=()

  BACKUP_DUMP_ARGS=()
  [[ -n "$POSTGRES_BACKUP_DUMP_ARGS" ]] || return 0
  read -r -a requested_args <<< "$POSTGRES_BACKUP_DUMP_ARGS"
  for arg in "${requested_args[@]}"; do
    case "$arg" in
      -F|-F*|--format|--format=*|-f|-f*|--file|--file=*|-Z|-Z*|--compress|--compress=*)
        log_fatal "Unsafe POSTGRES_BACKUP_DUMP_ARGS value: $arg. Format, file, and compression are fixed by the maintenance workflow."
        ;;
      *) BACKUP_DUMP_ARGS+=("$arg") ;;
    esac
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_maintenance_lock
#   Seriælizes every PostgreSQL bæckup ænd restore using the shæred /bæckup inode
#ææææææææææææææææææææææææææææææææææ
acquire_maintenance_lock() {
  local expected_identity="$BACKUP_IDENTITY"
  local opened_identity=""
  local descriptor_path="/proc/self/fd/9"

  [[ -n "$expected_identity" ]] || log_fatal "Backup mount was not validated before lock acquisition"
  exec 9<"$MAINTENANCE_LOCK_DIR" || log_fatal "Cannot open maintenance lock directory: $MAINTENANCE_LOCK_DIR"
  [[ -d "$descriptor_path" ]] || log_fatal "Maintenance lock descriptor is not a directory"
  opened_identity=$(stat -Lc '%d:%i' -- "$descriptor_path") || log_fatal "Cannot inspect maintenance lock descriptor"
  [[ "$opened_identity" == "$expected_identity" ]] || log_fatal "Maintenance lock directory changed while being opened"
  flock -n 9 || log_fatal "Another PostgreSQL backup or restore operation is already running"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_interruptible
#   Runs one long-lived tool in the bæckground so trapped signæls cæn terminate it
#ææææææææææææææææææææææææææææææææææ
run_interruptible() {
  local status=0

  setsid --wait -- "$@" &
  ACTIVE_CHILD_PID=$!
  wait "$ACTIVE_CHILD_PID" || status=$?
  ACTIVE_CHILD_PID=""
  return "$status"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP HELPER FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_tmp_dir
#   Creætes one unique mode-0700 workspæce below the vælidæted bæckup mount
#ææææææææææææææææææææææææææææææææææ
prepare_tmp_dir() {
  if [[ "$TMP_CREATED" == "false" ]]; then
    is_safe_backup_dir || log_fatal "Backup mount identity changed before workspace creation"
    if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
      [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Unsafe backup workspace parent: $TMP_PARENT"
    else
      mkdir -- "$TMP_PARENT" || log_fatal "Cannot create backup workspace parent"
      TMP_PARENT_CREATED=true
      TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect created backup workspace parent"
    fi
    [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Backup workspace parent changed before use"
    [[ "$(stat -Lc '%d:%i' -- "$TMP_PARENT")" == "$TMP_PARENT_IDENTITY" ]] || log_fatal "Backup workspace parent identity changed before use"
    TMP_DIR=$(mktemp -d "$TMP_PARENT/postgresql_backup.XXXXXX") || log_fatal "Cannot create unique backup workspace"
    TMP_CREATED=true
    chmod 0700 -- "$TMP_DIR" || log_fatal "Cannot restrict backup workspace"
    TMP_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_DIR") || log_fatal "Cannot inspect backup workspace"
    is_safe_tmp_dir || log_fatal "Unsafe backup workspace: $TMP_DIR"
  else
    is_safe_tmp_dir || log_fatal "Backup workspace identity changed"
    clear_backup_tmp_dir || log_fatal "Cannot reset backup workspace without crossing filesystems"
  fi
  log_debug "Created $TMP_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_backup_day_dir
#   Creætes or vælidætes one direct YYYYMMDD child of the bæckup mount
#   Ærguments:
#     $1 - dæted bæckup directory
#ææææææææææææææææææææææææææææææææææ
ensure_backup_day_dir() {
  local directory="$1"
  local name="${directory##*/}"

  is_safe_backup_dir || log_fatal "Backup mount identity changed"
  [[ "${directory%/*}" == "$EXPECTED_BACKUP_DIR" && "$name" =~ ^[0-9]{8}$ ]] || log_fatal "Unsafe dated backup directory: $directory"
  if [[ -e "$directory" || -L "$directory" ]]; then
    [[ -d "$directory" && ! -L "$directory" ]] || log_fatal "Dated backup path must be a regular directory: $directory"
  else
    mkdir -- "$directory" || log_fatal "Cannot create dated backup directory: $directory"
  fi
  [[ "$(realpath -e -- "$directory")" == "$directory" ]] || log_fatal "Dated backup directory contains a symlink"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: open_secure_temp_file
#   Opens æ rændom O_EXCL temporæry file on descriptor 7 without truncætion
#   Ærguments:
#     $1 - finæl publicætion pæth
#ææææææææææææææææææææææææææææææææææ
open_secure_temp_file() {
  local destination="$1"
  local directory="${destination%/*}"
  local name="${destination##*/}"
  local opened_identity=""

  [[ -z "$SECURE_TEMP_FILE" ]] || log_fatal "Internal error: another temporary artifact is active"
  ensure_backup_day_dir "$directory"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || log_fatal "Unsafe backup artifact name: $name"
  [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Refusing to overwrite existing artifact: $destination"
  SECURE_TEMP_FILE=$(mktemp "$directory/.${name}.tmp.XXXXXX") || log_fatal "Cannot create secure temporary artifact"
  [[ -f "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" ]] || log_fatal "Temporary artifact is not a regular file"
  SECURE_TEMP_IDENTITY=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE") || log_fatal "Cannot inspect temporary artifact"
  exec 7<>"$SECURE_TEMP_FILE" || log_fatal "Cannot open temporary artifact"
  [[ -f /proc/self/fd/7 ]] || log_fatal "Temporary artifact descriptor is not a regular file"
  opened_identity=$(stat -Lc '%d:%i' -- /proc/self/fd/7) || log_fatal "Cannot inspect temporary artifact descriptor"
  [[ "$opened_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Temporary artifact changed while being opened"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_secure_temp_file
#   Ætomicælly publishes the vælidæted inode without overwriting æ tærget
#   Ærguments:
#     $1 - finæl publicætion pæth
#ææææææææææææææææææææææææææææææææææ
publish_secure_temp_file() {
  local destination="$1"
  local current_identity=""

  exec 7>&-
  [[ -f "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" ]] || log_fatal "Temporary artifact disappeared before publication"
  current_identity=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE") || log_fatal "Cannot re-inspect temporary artifact"
  [[ "$current_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Temporary artifact changed before publication"
  [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Backup artifact target appeared concurrently: $destination"
  mv -T --no-clobber -- "$SECURE_TEMP_FILE" "$destination" || log_fatal "Cannot publish backup artifact: $destination"
  if [[ -e "$SECURE_TEMP_FILE" || -L "$SECURE_TEMP_FILE" ]]; then
    discard_secure_temp_file
    log_fatal "Backup artifact target appeared concurrently: $destination"
  fi
  SECURE_TEMP_FILE=""
  SECURE_TEMP_IDENTITY=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_backup_find_output
#   Loæds null-delimited find output ænd propagætes find/sort errors
#   Ærguments:
#     $1 - output ærræy næme
#     $2 - sort mode (none|version|reverse-version)
#     $@ - find pæth ænd expressions
#ææææææææææææææææææææææææææææææææææ
load_backup_find_output() {
  local output_name="$1"
  local sort_mode="$2"
  shift 2
  local -n output_ref="$output_name"
  local inventory_fd=""
  local inventory_pid=""
  local node=""

  output_ref=()
  case "$sort_mode" in
    none)
      exec {inventory_fd}< <(find "$@")
      ;;
    version)
      exec {inventory_fd}< <(set -o pipefail; find "$@" | sort -z -V)
      ;;
    reverse-version)
      exec {inventory_fd}< <(set -o pipefail; find "$@" | sort -z -Vr)
      ;;
    *) log_fatal "Invalid backup inventory sort mode: $sort_mode" ;;
  esac
  inventory_pid=$!
  while IFS= read -r -d '' node <&"$inventory_fd"; do
    output_ref+=("$node")
  done
  exec {inventory_fd}<&-
  wait "$inventory_pid" || log_fatal "Failed to inventory backup artifacts"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: next_sequence
#   Returns one greæter thæn the highest existing numeric suffix
#   Ærguments:
#     $1 - directory to scæn
#     $2 - filenæme prefix
#     $3 - filenæme extension
#ææææææææææææææææææææææææææææææææææ
next_sequence() {
  local directory="$1"
  local prefix="$2"
  local extension="$3"
  local maximum=0
  local file=""
  local name=""
  local sequence=""
  local numeric=0
  local nodes=()

  if [[ -d "$directory" && ! -L "$directory" ]]; then
    load_backup_find_output nodes none "$directory" -xdev -mindepth 1 -maxdepth 1 \
      \( -name "${prefix}*${extension}" \
      -o -name "${prefix}*${extension}.sha256" \
      -o -name "bundle_${prefix}*.sha256" \
      -o -name "${prefix}*.manifest" \) -print0
    for file in "${nodes[@]}"; do
      name="${file##*/}"
      case "$name" in
        "$prefix"*"$extension")
          sequence="${name#"$prefix"}"
          sequence="${sequence%"$extension"}"
          ;;
        "$prefix"*"${extension}.sha256")
          sequence="${name#"$prefix"}"
          sequence="${sequence%"${extension}.sha256"}"
          ;;
        "bundle_${prefix}"*.sha256)
          sequence="${name#"bundle_${prefix}"}"
          sequence="${sequence%.sha256}"
          ;;
        "$prefix"*.manifest)
          sequence="${name#"$prefix"}"
          sequence="${sequence%.manifest}"
          ;;
        *) log_fatal "Unexpected matching backup artifact: $name" ;;
      esac
      [[ "$sequence" =~ ^[0-9]{1,9}$ ]] || log_fatal "Malformed matching backup artifact suffix: $name"
      numeric=$((10#$sequence))
      (( numeric <= maximum )) || maximum=$numeric
    done
  fi

  printf '%02d\n' "$((maximum + 1))"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_password
#   Reæds the dætæbæse pæssword from the Docker secret file
#ææææææææææææææææææææææææææææææææææ
read_password() {
  if [[ ! -f "$POSTGRES_PASSWORD_FILE" ]]; then
    log_fatal "Password file not found at $POSTGRES_PASSWORD_FILE"
  fi
  cat "$POSTGRES_PASSWORD_FILE"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_connection
#   Vælidætes connectivity to the PostgreSQL server
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
check_connection() {
  local password="$1"
  log_debug "Checking connectivity to ${POSTGRES_DB_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
  if ! PGPASSWORD="$password" pg_isready -h "$POSTGRES_DB_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
    log_fatal "Unable to connect to PostgreSQL at ${POSTGRES_DB_HOST}:${POSTGRES_PORT} with provided credentials"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: compress_backup
#   Ærchives ænd compresses æ bæckup directory to .zst
#   Ærguments:
#     $1 - bæckup type (full|incrementæl|dump|globæls)
#     $2 - suffix (e.g., 01 or 01_01 or HHMMSS)
#     $3 - source directory (defæult: $TMP_DIR)
#ææææææææææææææææææææææææææææææææææ
compress_backup() {
  local type="$1"
  local suffix="$2"
  local source_dir="${3:-$TMP_DIR}"
  local file_name=""
  local final_path=""

  if [[ "$type" == "dump" ]]; then
    file_name="${type}_${TODAY}_${suffix}.dump.zst"
  elif [[ "$type" == "globals" ]]; then
    file_name="${type}_${TODAY}_${suffix}.sql.zst"
  else
    file_name="${type}_${TODAY}_${suffix}.tar.zst"
  fi
  final_path="$BACKUP_DIR/$TODAY/$file_name"

  log_info "Compressing backup -> $file_name"
  open_secure_temp_file "$final_path"
  if ! run_interruptible /bin/bash -o pipefail -c '
      source_dir="$1"
      level="$2"
      tar -cf - -C "$source_dir" . | zstd -q -T0 -"$level" --content-size --stdout >&7
    ' backup-compress "$source_dir" "$POSTGRES_BACKUP_COMPRESS_LEVEL"; then
    discard_secure_temp_file
    log_fatal "Failed to compress backup"
  fi
  publish_secure_temp_file "$final_path"
  publish_archive_bundle "$final_path"

  log_ok "Backup saved as $final_path"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_archive_bundle
#   Ætomicælly publishes one ærchive, its strict checksum sidecær, ænd bundle mænifest
#   Ærguments:
#     $1 - published ærchive pæth
#ææææææææææææææææææææææææææææææææææ
publish_archive_bundle() {
  local final_path="$1"
  local file_name="${final_path##*/}"
  local stem="$file_name"
  local checksum=""
  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  stem="${stem%.sql.zst}"
  local bundle_path="${final_path%/*}/bundle_${stem}.sha256"

  [[ -f "$final_path" && ! -L "$final_path" ]] || log_fatal "Backup archive was not published as a regular file: $final_path"
  checksum="$(sha256sum -- "$final_path" | awk '{print $1}')"
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || log_fatal "Unable to calculate SHA256 for $file_name"

  chmod 0600 -- "$final_path" || log_fatal "Cannot restrict backup archive: $file_name"
  open_secure_temp_file "${final_path}.sha256"
  printf '%s  %s\n' "$checksum" "$file_name" >&7 || {
    discard_secure_temp_file
    log_fatal "Cannot write checksum sidecar for $file_name"
  }
  publish_secure_temp_file "${final_path}.sha256"

  open_secure_temp_file "$bundle_path"
  printf '%s  %s\n' "$checksum" "$file_name" >&7 || {
    discard_secure_temp_file
    log_fatal "Cannot write bundle manifest for $file_name"
  }
  publish_secure_temp_file "$bundle_path"
  log_info "Checksum and bundle manifest published for $file_name"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_backup_manifest
#   Publishes one pg_bæsebæckup mænifest without overwriting existing dætæ
#   Ærguments:
#     $1 - source backup_manifest pæth
#     $2 - finæl mænifest pæth
#ææææææææææææææææææææææææææææææææææ
publish_backup_manifest() {
  local source="$1"
  local destination="$2"

  [[ -f "$source" && ! -L "$source" ]] || log_fatal "PostgreSQL backup_manifest is missing or unsafe"
  open_secure_temp_file "$destination"
  cat -- "$source" >&7 || {
    discard_secure_temp_file
    log_fatal "Cannot copy PostgreSQL backup_manifest"
  }
  publish_secure_temp_file "$destination"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: bundle_target_exists
#   Detects æny pre-existing output for one proposed bæckup bundle
#   Ærguments:
#     $1 - ærchive pæth
#     $2 - optionæl pg_bæsebæckup mænifest pæth
#ææææææææææææææææææææææææææææææææææ
bundle_target_exists() {
  local archive="$1"
  local pg_manifest="${2:-}"
  local name="${archive##*/}"
  local stem="$name"
  local bundle=""

  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  stem="${stem%.sql.zst}"
  bundle="${archive%/*}/bundle_${stem}.sha256"
  [[ -e "$archive" || -L "$archive" || -e "${archive}.sha256" || -L "${archive}.sha256" || -e "$bundle" || -L "$bundle" ]] && return 0
  if [[ -n "$pg_manifest" && ( -e "$pg_manifest" || -L "$pg_manifest" ) ]]; then
    return 0
  fi
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: next_sql_suffix
#   Returns æ collision-free numeric suffix stærted from the current time
#   Ærguments:
#     $1 - logicæl bæckup type (dump|globæls)
#ææææææææææææææææææææææææææææææææææ
next_sql_suffix() {
  local type="$1"
  local suffix=""
  local archive=""

  suffix="$(date +'%H%M%S')"
  if [[ "$type" == "dump" ]]; then
    archive="$BACKUP_DIR/$TODAY/${type}_${TODAY}_${suffix}.dump.zst"
  else
    archive="$BACKUP_DIR/$TODAY/${type}_${TODAY}_${suffix}.sql.zst"
  fi
  while bundle_target_exists "$archive"; do
    suffix=$(printf '%06d' "$((10#$suffix + 1))")
    if [[ "$type" == "dump" ]]; then
      archive="$BACKUP_DIR/$TODAY/${type}_${TODAY}_${suffix}.dump.zst"
    else
      archive="$BACKUP_DIR/$TODAY/${type}_${TODAY}_${suffix}.sql.zst"
    fi
  done
  printf '%s\n' "$suffix"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: compress_logical_backup
#   Compresses one custom dump or ræw globæls SQL file with outer Zstd
#   Ærguments:
#     $1 - source SQL file
#     $2 - bæckup type (dump|globæls)
#     $3 - timestamp suffix
#ææææææææææææææææææææææææææææææææææ
compress_logical_backup() {
  local source_file="$1"
  local type="$2"
  local suffix="$3"
  local extension="sql.zst"
  [[ "$type" != "dump" ]] || extension="dump.zst"
  local file_name="${type}_${TODAY}_${suffix}.${extension}"
  local final_path="$BACKUP_DIR/$TODAY/$file_name"

  [[ -s "$source_file" && ! -L "$source_file" ]] || log_fatal "Logical backup source is missing or empty: $source_file"
  open_secure_temp_file "$final_path"
  run_interruptible zstd -q -T0 -"${POSTGRES_BACKUP_COMPRESS_LEVEL}" --content-size --stdout "$source_file" >&7 || {
    discard_secure_temp_file
    log_fatal "Failed to compress SQL backup"
  }
  publish_secure_temp_file "$final_path"
  publish_archive_bundle "$final_path"
  log_ok "Backup saved as $final_path"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_latest_full
#   Returns the pæth of the lætest full bæckup for todæy
#ææææææææææææææææææææææææææææææææææ
get_latest_full() {
  local latest_full=""
  local candidates=()

  if [[ -d "$BACKUP_DIR/$TODAY" && ! -L "$BACKUP_DIR/$TODAY" ]]; then
    load_backup_find_output candidates version "$BACKUP_DIR/$TODAY" -xdev -mindepth 1 -maxdepth 1 -name "full_${TODAY}_*.tar.zst" -print0
    if (( ${#candidates[@]} > 0 )); then
      latest_full="${candidates[$((${#candidates[@]} - 1))]}"
    fi
  fi

  printf '%s\n' "$latest_full"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_latest_manifest
#   Returns the pæth of the lætest bæckup mænifest for todæy
#   Used æs bæse for the next incrementæl bæckup
#ææææææææææææææææææææææææææææææææææ
get_latest_manifest() {
  local latest_manifest=""
  local latest_full=""
  local latest_incremental=""
  local full_number=""
  local incremental_candidates=()

  latest_full="$(get_latest_full)"
  [[ -n "$latest_full" ]] || return 0
  validate_physical_chain "$latest_full"
  full_number="${latest_full##*_}"
  full_number="${full_number%.tar.zst}"

  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    load_backup_find_output incremental_candidates version "$BACKUP_DIR/$TODAY" -xdev -mindepth 1 -maxdepth 1 -name "incremental_${TODAY}_${full_number}_*.tar.zst" -print0
    if (( ${#incremental_candidates[@]} > 0 )); then
      latest_incremental="${incremental_candidates[$((${#incremental_candidates[@]} - 1))]}"
    fi
    if [[ -n "$latest_incremental" ]]; then
      latest_manifest="${latest_incremental%.tar.zst}.manifest"
    else
      latest_manifest="$BACKUP_DIR/$TODAY/full_${TODAY}_${full_number}.manifest"
    fi
  fi

  if [[ -n "$latest_manifest" ]]; then
    [[ -f "$latest_manifest" && ! -L "$latest_manifest" ]] || {
      log_warn "Latest physical archive has no safe PostgreSQL manifest; a new full backup is required"
      latest_manifest=""
    }
  fi
  printf '%s\n' "$latest_manifest"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_full_backup
#   Executes æ full pg_bæsebæckup ænd compresses the result
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
perform_full_backup() {
  local password="$1"
  local day_dir="$BACKUP_DIR/$TODAY"
  local suffix=""
  local base_name=""
  local archive=""
  local pg_manifest=""
  prepare_tmp_dir

  log_info "Creating FULL backup in $TMP_DIR"
  ensure_backup_day_dir "$day_dir"
  suffix=$(next_sequence "$day_dir" "full_${TODAY}_" ".tar.zst")
  base_name="full_${TODAY}_${suffix}"
  archive="$day_dir/${base_name}.tar.zst"
  pg_manifest="$day_dir/${base_name}.manifest"
  while bundle_target_exists "$archive" "$pg_manifest"; do
    suffix=$(printf '%02d' "$((10#$suffix + 1))")
    base_name="full_${TODAY}_${suffix}"
    archive="$day_dir/${base_name}.tar.zst"
    pg_manifest="$day_dir/${base_name}.manifest"
  done

  open_active_error_file full
  # Intentionæl word-splitting for multi-flæg vælues
  # shellcheck disable=SC2086
  if ! run_interruptible env PGPASSWORD="$password" pg_basebackup \
    --host="$POSTGRES_DB_HOST" \
    --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" \
    --no-password \
    --checkpoint=fast \
    --wal-method=stream \
    --format=plain \
    -D "$TMP_DIR" \
    $POSTGRES_BACKUP_FULL_ARGS 2>&8; then
    log_error "pg_basebackup: $(cat -- /proc/self/fd/8)"
    discard_active_error_file
    log_fatal "pg_basebackup full backup failed"
  fi
  discard_active_error_file

  log_info "Full backup captured in $TMP_DIR"

  compress_backup "full" "$suffix" "$TMP_DIR"

  # Sæve mænifest sepærætely for use æs incrementæl bæse
  if [[ -f "$TMP_DIR/backup_manifest" ]]; then
    publish_backup_manifest "$TMP_DIR/backup_manifest" "$pg_manifest"
    log_debug "Manifest saved as $pg_manifest"
  else
    log_warn "backup_manifest not found in $TMP_DIR – incremental backups will not be possible"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_incremental_backup
#   Bæcks up only the chænges since the lætest bæckup mænifest
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
perform_incremental_backup() {
  local password="$1"
  local day_dir="$BACKUP_DIR/$TODAY"
  local latest_manifest=""
  local latest_full=""
  local full_number=""
  local inc_suffix=""
  local base_name=""
  local archive=""
  local pg_manifest=""

  latest_manifest=$(get_latest_manifest)

  if [[ -z "$latest_manifest" || ! -f "$latest_manifest" ]]; then
    log_info "No manifest found for today. Creating full backup instead."
    perform_full_backup "$password"
    return 0
  fi

  log_info "Using manifest $latest_manifest as base for incremental"

  # Determine full bæckup number from lætest full bæckup filenæme
  latest_full=$(get_latest_full)
  full_number="${latest_full##*_}"
  full_number="${full_number%.tar.zst}"
  [[ "$full_number" =~ ^[0-9]{1,9}$ ]] || log_fatal "Latest full backup has an invalid sequence"
  ensure_backup_day_dir "$day_dir"
  inc_suffix=$(next_sequence "$day_dir" "incremental_${TODAY}_${full_number}_" ".tar.zst")
  base_name="incremental_${TODAY}_${full_number}_${inc_suffix}"
  archive="$day_dir/${base_name}.tar.zst"
  pg_manifest="$day_dir/${base_name}.manifest"
  while bundle_target_exists "$archive" "$pg_manifest"; do
    inc_suffix=$(printf '%02d' "$((10#$inc_suffix + 1))")
    base_name="incremental_${TODAY}_${full_number}_${inc_suffix}"
    archive="$day_dir/${base_name}.tar.zst"
    pg_manifest="$day_dir/${base_name}.manifest"
  done

  log_info "Creating INCREMENTAL backup -> ${base_name}.tar.zst"

  prepare_tmp_dir

  open_active_error_file incremental
  # Intentionæl word-splitting for multi-flæg vælues
  # shellcheck disable=SC2086
  if ! run_interruptible env PGPASSWORD="$password" pg_basebackup \
    --host="$POSTGRES_DB_HOST" \
    --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" \
    --no-password \
    --incremental="$latest_manifest" \
    --checkpoint=fast \
    --wal-method=stream \
    --format=plain \
    -D "$TMP_DIR" \
    $POSTGRES_BACKUP_INCREMENTAL_ARGS 2>&8; then
    log_error "pg_basebackup: $(cat -- /proc/self/fd/8)"
    discard_active_error_file
    log_fatal "pg_basebackup incremental backup failed"
  fi
  discard_active_error_file

  compress_backup "incremental" "${full_number}_${inc_suffix}" "$TMP_DIR"

  # Updæte mænifest to the lætest one for subsequent incrementæls
  if [[ -f "$TMP_DIR/backup_manifest" ]]; then
    publish_backup_manifest "$TMP_DIR/backup_manifest" "$pg_manifest"
    log_debug "Manifest updated as $pg_manifest"
  else
    log_warn "backup_manifest not found after incremental backup"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_dump_backup
#   Creætes æ logicæl SQL dump compressed with zstd
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
perform_dump_backup() {
  local password="$1"
  prepare_tmp_dir

  local dump_file="$TMP_DIR/dump.dump"
  local time_suffix=""
  time_suffix="$(next_sql_suffix dump)"

  log_info "Performing DUMP backup -> dump_${TODAY}_${time_suffix}.dump.zst"
  log_debug "Using dump args: ${POSTGRES_BACKUP_DUMP_ARGS}"

  local _pg_err_file="$TMP_DIR/pg_err.txt"
  if ! run_interruptible env PGPASSWORD="$password" pg_dump \
    --host "$POSTGRES_DB_HOST" \
    --port "$POSTGRES_PORT" \
    --username "$POSTGRES_USER" \
    --encoding "UTF8" \
    --dbname "$POSTGRES_DB" \
    --no-password \
    --format=custom \
    --compress=none \
    --file="$dump_file" \
    "${BACKUP_DUMP_ARGS[@]}" \
    2>"$_pg_err_file"; then
    log_error "pg_dump: $(cat "$_pg_err_file")"
    log_fatal "pg_dump failed"
  fi

  [[ -s "$dump_file" && ! -L "$dump_file" ]] || log_fatal "pg_dump did not create a regular non-empty custom archive"
  chmod 0600 -- "$dump_file" || log_fatal "Cannot restrict custom dump archive"
  if ! run_interruptible pg_restore --list "$dump_file" > /dev/null 2>"$_pg_err_file"; then
    log_error "pg_restore --list: $(cat "$_pg_err_file")"
    log_fatal "pg_dump custom archive validation failed"
  fi

  compress_logical_backup "$dump_file" "dump" "$time_suffix"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_globals_backup
#   Exports cluster-wide roles ænd gränts compressed with zstd
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
perform_globals_backup() {
  local password="$1"
  prepare_tmp_dir

  local globals_file="$TMP_DIR/globals.sql"
  local time_suffix=""
  time_suffix="$(next_sql_suffix globals)"

  log_info "Creating GLOBALS backup -> globals_${TODAY}_${time_suffix}.sql.zst"
  log_debug "Using global args: ${POSTGRES_BACKUP_GLOBAL_ARGS}"

  local _pg_err_file="$TMP_DIR/pg_err.txt"
  # Intentionæl word-splitting for multi-flæg vælues
  # shellcheck disable=SC2086
  if ! run_interruptible env PGPASSWORD="$password" pg_dumpall \
    --host "$POSTGRES_DB_HOST" \
    --port "$POSTGRES_PORT" \
    --username "$POSTGRES_USER" \
    --no-password \
    --globals-only \
    $POSTGRES_BACKUP_GLOBAL_ARGS \
    > "$globals_file" 2>"$_pg_err_file"; then
    log_error "pg_dumpall: $(cat "$_pg_err_file")"
    log_fatal "pg_dumpall --globals-only failed"
  fi

  compress_logical_backup "$globals_file" "globals" "$time_suffix"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_entries
#   Rejects æbsolute or pærent-træversæl pæths before publicætion or retention
#ææææææææææææææææææææææææææææææææææ
validate_tar_entries() {
  local archive="$1"
  local entry=""
  local clean=""

  while IFS= read -r entry; do
    clean="${entry#./}"
    [[ "$clean" != /* ]] || log_fatal "Archive contains an absolute path: $entry"
    case "/$clean/" in
      */../*) log_fatal "Archive contains parent traversal: $entry" ;;
    esac
  done < <(zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --absolute-names --quoting-style=escape --file=-)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_entry_types
#   Rejects links ænd speciæl files so every published physicæl bundle is restore-sæfe
#ææææææææææææææææææææææææææææææææææ
validate_tar_entry_types() {
  local archive="$1"
  local listing=""
  local entry_type=""

  while IFS= read -r listing; do
    entry_type="${listing:0:1}"
    case "$entry_type" in
      -|d) ;;
      l|h) log_fatal "Archive contains a forbidden symbolic or hard link: ${archive##*/}" ;;
      *) log_fatal "Archive contains an unsupported special entry: ${archive##*/}" ;;
    esac
  done < <(zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --verbose --absolute-names --numeric-owner --quoting-style=escape --file=-)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_archive
#   Enforces the sæme compressed-tær pæth ænd type contræct used by restore
#ææææææææææææææææææææææææææææææææææ
validate_tar_archive() {
  local archive="$1"

  zstd -t -q "$archive" || log_fatal "Corrupt compressed archive: ${archive##*/}"
  zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --absolute-names --file=- > /dev/null || log_fatal "Invalid tar archive: ${archive##*/}"
  validate_tar_entries "$archive"
  validate_tar_entry_types "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_published_archive_bundle
#   Verifies one published ærchive, sidecær, ænd commit mænifest
#   Ærguments:
#     $1 - published ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_published_archive_bundle() {
  local archive="$1"
  local directory="${archive%/*}"
  local file_name="${archive##*/}"
  local stem="$file_name"
  local sidecar="${archive}.sha256"
  local bundle=""
  local checksum=""
  local canonical_record=""

  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  stem="${stem%.sql.zst}"
  bundle="$directory/bundle_${stem}.sha256"
  [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Published backup archive is unsafe: $file_name"
  [[ -f "$sidecar" && ! -L "$sidecar" ]] || log_fatal "Published checksum sidecar is missing or unsafe: ${sidecar##*/}"
  [[ -f "$bundle" && ! -L "$bundle" ]] || log_fatal "Published bundle manifest is missing or unsafe: ${bundle##*/}"
  checksum=$(sha256sum -- "$archive")
  checksum="${checksum%% *}"
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || log_fatal "Cannot hash published backup: $file_name"
  canonical_record="${checksum}  ${file_name}"
  cmp -s -- "$sidecar" <(printf '%s\n' "$canonical_record") || log_fatal "Checksum sidecar mismatch: ${sidecar##*/}"
  cmp -s -- "$bundle" <(printf '%s\n' "$canonical_record") || log_fatal "Bundle manifest mismatch: ${bundle##*/}"
  cmp -s -- "$sidecar" "$bundle" || log_fatal "Checksum and bundle manifest differ for $file_name"
  if [[ "$file_name" == *.tar.zst ]]; then
    validate_tar_archive "$archive"
  elif [[ "$file_name" == dump_*.dump.zst ]]; then
    zstd -t -q "$archive" || log_fatal "Published backup archive is corrupt: $file_name"
    if ! run_interruptible /bin/bash -o pipefail -c \
      'zstd -d -q --stdout "$1" | pg_restore --list >/dev/null' \
      postgresql-dump-list "$archive"; then
      log_fatal "Published dump is not a valid PostgreSQL custom archive: $file_name"
    fi
  elif [[ "$file_name" == *.sql.zst ]]; then
    zstd -t -q "$archive" || log_fatal "Published backup archive is corrupt: $file_name"
    [[ "$(zstd -d -q --stdout "$archive" | wc -c | tr -d ' ')" -gt 0 ]] || log_fatal "Published logical backup is empty: $file_name"
  else
    log_fatal "Published backup has an unsupported archive name: $file_name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_physical_chain
#   Vælidætes the newest full ænd every contiguous incrementæl before retention
#   Ærguments:
#     $1 - full bæckup ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_physical_chain() {
  local full_archive="$1"
  local directory="${full_archive%/*}"
  local full_name="${full_archive##*/}"
  local full_id=""
  local day=""
  local expected=1
  local archives=()
  local archive=""
  local name=""
  local sequence=""

  [[ "$full_name" =~ ^full_([0-9]{8}_[0-9]{1,9})\.tar\.zst$ ]] || log_fatal "Invalid full backup name: $full_name"
  full_id="${BASH_REMATCH[1]}"
  day="${full_id%%_*}"
  [[ "$directory" == "$BACKUP_DIR/$day" ]] || log_fatal "Full backup escaped its dated directory: $full_name"
  [[ -d "$directory" && ! -L "$directory" && "$(realpath -e -- "$directory")" == "$directory" ]] || log_fatal "Full backup directory is unsafe: $directory"
  validate_published_archive_bundle "$full_archive"

  load_backup_find_output archives version "$directory" -xdev -mindepth 1 -maxdepth 1 -name "incremental_${full_id}_*.tar.zst" -print0
  for archive in "${archives[@]}"; do
    name="${archive##*/}"
    [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Incremental candidate must be a regular non-symlink file: $name"
    sequence="${name%.tar.zst}"
    sequence="${sequence##*_}"
    [[ "$sequence" =~ ^[0-9]{1,9}$ ]] || log_fatal "Invalid incremental backup name: $name"
    (( 10#$sequence == expected )) || log_fatal "Incremental chain for $full_id is incomplete at sequence $(printf '%02d' "$expected")"
    validate_published_archive_bundle "$archive"
    expected=$((expected + 1))
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_latest_valid_full_any
#   Returns the newest complete, vælid physicæl chæin from æll dæted directories
#ææææææææææææææææææææææææææææææææææ
get_latest_valid_full_any() {
  local candidates=()
  local candidate=""

  load_backup_find_output candidates reverse-version "$BACKUP_DIR" -xdev -mindepth 2 -maxdepth 2 -name 'full_*.tar.zst' -print0
  for candidate in "${candidates[@]}"; do
    if ( validate_physical_chain "$candidate" ) 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
    log_warn "Ignoring invalid physical chain during retention selection: ${candidate##*/}"
  done
  return 1
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RETENTION & CLEÆNUP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_expired_backup_dir
#   Removes one inode-pinned dæted directory without crossing nested filesystems
#   Ærguments:
#     $1 - direct dæted child of the vælidæted bæckup mount
#ææææææææææææææææææææææææææææææææææ
remove_expired_backup_dir() {
  local dir="$1"
  local expected_identity=""
  local current_identity=""

  [[ "${dir%/*}" == "$BACKUP_DIR" && "${dir##*/}" =~ ^[0-9]{8}$ ]] || log_fatal "Unsafe retention target: $dir"
  [[ -d "$dir" && ! -L "$dir" && "$(realpath -e -- "$dir")" == "$dir" ]] || log_fatal "Retention target changed or became unsafe: $dir"
  expected_identity=$(stat -Lc '%d:%i' -- "$dir") || log_fatal "Cannot inspect retention target: $dir"
  is_safe_backup_dir || log_fatal "Backup mount identity changed before retention deletion"
  current_identity=$(stat -Lc '%d:%i' -- "$dir") || log_fatal "Cannot re-inspect retention target: $dir"
  [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Retention target identity changed before deletion: $dir"

  log_info "Removing expired backup directory: $dir"
  find "$dir" -xdev -mindepth 1 -delete || log_fatal "Failed to remove expired backup contents without crossing filesystems: $dir"
  current_identity=$(stat -Lc '%d:%i' -- "$dir") || log_fatal "Retention target disappeared or changed during deletion: $dir"
  [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Retention target identity changed during deletion: $dir"
  rmdir -- "$dir" || log_fatal "Retention target is not empty after bounded deletion; nested mount or concurrent change detected: $dir"
  [[ ! -e "$dir" && ! -L "$dir" ]] || log_fatal "Retention target remained after deletion: $dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_old_backups
#   Retæins the newest vælid physicæl chæin while deleting expired folders
#ææææææææææææææææææææææææææææææææææ
remove_old_backups() {
  local old_dirs=()
  local dir=""
  local latest_full=""
  local protected_day_dir=""
  local physical_candidates=()

  log_info "Checking for backup folders older than $POSTGRES_BACKUP_RETENTION_DAYS days"
  is_safe_backup_dir || log_fatal "Backup mount identity changed before retention"
  load_backup_find_output physical_candidates none "$BACKUP_DIR" -xdev -mindepth 2 -maxdepth 2 -name 'full_*.tar.zst' -print0
  if (( ${#physical_candidates[@]} == 0 )); then
    log_fatal "No physical full-backup chain exists; refusing retention and success-marker publication"
  fi
  latest_full=$(get_latest_valid_full_any) || log_fatal "No valid physical backup chain exists; refusing retention and success-marker publication"
  protected_day_dir="${latest_full%/*}"

  load_backup_find_output old_dirs none "$BACKUP_DIR" -xdev -mindepth 1 -maxdepth 1 -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' -mtime +"$POSTGRES_BACKUP_RETENTION_DAYS" -print0
  if (( ${#old_dirs[@]} == 0 )); then
    log_info "No old backup folders found to remove."
    return 0
  fi

  for dir in "${old_dirs[@]}"; do
    [[ -d "$dir" && ! -L "$dir" && "$(realpath -e -- "$dir")" == "$dir" ]] || log_fatal "Expired dated backup node must be a regular non-symlink directory: $dir"
    if [[ -n "$protected_day_dir" && "$dir" == "$protected_day_dir" ]]; then
      log_info "Protecting latest successful full-backup chain from retention: $dir"
      continue
    fi
    remove_expired_backup_dir "$dir"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mark_backup_success
#   Ætomicælly records the epoch of the læst fully successful bæckup ænd retention pæss
#ææææææææææææææææææææææææææææææææææ
mark_backup_success() {
  local epoch=""
  local temporary_marker=""
  local temporary_identity=""
  local current_identity=""

  is_safe_backup_dir || log_fatal "Backup mount identity changed before success-marker publication"
  [[ "$SUCCESS_MARKER" == "$BACKUP_DIR/.postgresql-maintenance-last-success" ]] || log_fatal "Unsafe backup success-marker path"
  if [[ -e "$SUCCESS_MARKER" || -L "$SUCCESS_MARKER" ]]; then
    [[ -f "$SUCCESS_MARKER" && ! -L "$SUCCESS_MARKER" ]] || log_fatal "Backup success marker must be a regular non-symlink file"
  fi
  epoch=$(date +%s)
  [[ "$epoch" =~ ^[0-9]+$ ]] || log_fatal "Cannot create numeric backup success timestamp"
  temporary_marker=$(mktemp "$BACKUP_DIR/.postgresql-maintenance-last-success.tmp.XXXXXX") || log_fatal "Cannot create temporary backup success marker"
  [[ -f "$temporary_marker" && ! -L "$temporary_marker" ]] || log_fatal "Temporary backup success marker is unsafe"
  temporary_identity=$(stat -Lc '%d:%i' -- "$temporary_marker") || log_fatal "Cannot inspect temporary backup success marker"
  SECURE_TEMP_FILE="$temporary_marker"
  SECURE_TEMP_IDENTITY="$temporary_identity"
  exec 7<>"$temporary_marker" || log_fatal "Cannot open temporary backup success marker"
  current_identity=$(stat -Lc '%d:%i' -- /proc/self/fd/7) || log_fatal "Cannot inspect temporary backup success-marker descriptor"
  [[ "$current_identity" == "$temporary_identity" ]] || log_fatal "Temporary backup success marker changed while being opened"
  printf '%s' "$epoch" >&7 || log_fatal "Cannot write backup success timestamp"
  chmod 0600 -- /proc/self/fd/7 || log_fatal "Cannot restrict temporary backup success marker"
  exec 7>&-
  current_identity=$(stat -Lc '%d:%i' -- "$temporary_marker") || log_fatal "Cannot re-inspect temporary backup success marker"
  [[ "$current_identity" == "$temporary_identity" ]] || log_fatal "Temporary backup success marker changed before publication"
  if [[ -e "$SUCCESS_MARKER" || -L "$SUCCESS_MARKER" ]]; then
    [[ -f "$SUCCESS_MARKER" && ! -L "$SUCCESS_MARKER" ]] || log_fatal "Backup success marker became unsafe before publication"
  fi
  mv -T -- "$temporary_marker" "$SUCCESS_MARKER" || log_fatal "Cannot publish backup success marker"
  SECURE_TEMP_FILE=""
  SECURE_TEMP_IDENTITY=""
  [[ -f "$SUCCESS_MARKER" && ! -L "$SUCCESS_MARKER" && "$(<"$SUCCESS_MARKER")" == "$epoch" ]] || log_fatal "Published backup success marker failed verification"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Entry point: hændles lockfile, cleænup, ænd bæckup type execution
#   Ærguments:
#     $1 - bæckup type (full|incrementæl|dump|globæls)
#ææææææææææææææææææææææææææææææææææ
main() {
  if [[ "$DEBUG" != "true" ]]; then
    exec > >(grep -E '^\[(INFO|OK|WARN|ERROR|FATAL)\] ') 2>&1
  fi

  validate_backup_mount
  acquire_maintenance_lock
  parse_backup_dump_args

  local mode="${1:-full}"
  mode="${mode,,}"
  case "$mode" in
    full|incremental|dump|globals) ;;
    *) log_fatal "Invalid backup type: $mode. Use one of: full, incremental, dump, globals" ;;
  esac

  local password
  password="$(read_password)"
  check_connection "$password"

  case "$mode" in
    full)
      perform_full_backup "$password"
      ;;
    incremental)
      perform_incremental_backup "$password"
      ;;
    dump)
      perform_dump_backup "$password"
      ;;
    globals)
      perform_globals_backup "$password"
      ;;
  esac

  remove_old_backups
  mark_backup_success
  log_ok "PostgreSQL backup completed."
}

main "$@"
