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
POSTGRES_RESTORE_DEBUG="${POSTGRES_RESTORE_DEBUG:-false}"
POSTGRES_RESTORE_DRY_RUN="${POSTGRES_RESTORE_DRY_RUN:-false}"
POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED="${POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED:-false}"
POSTGRES_RESTORE_CONSUME_ARCHIVES="${POSTGRES_RESTORE_CONSUME_ARCHIVES:-false}"
POSTGRES_RESTORE_REQUIRE_CHECKSUM="${POSTGRES_RESTORE_REQUIRE_CHECKSUM:-true}"
POSTGRES_RESTORE_BACKUP_ID="${POSTGRES_RESTORE_BACKUP_ID:-}"
POSTGRES_RESTORE_RECREATE_DATABASE="${POSTGRES_RESTORE_RECREATE_DATABASE:-false}"
POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT="${POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT:-false}"
POSTGRES_RESTORE_MAINTENANCE_DB="${POSTGRES_RESTORE_MAINTENANCE_DB:-postgres}"
POSTGRES_RESTORE_PSQL_ARGS="${POSTGRES_RESTORE_PSQL_ARGS:-}"
POSTGRES_RESTORE_COMBINE_ARGS="${POSTGRES_RESTORE_COMBINE_ARGS:-}"

RESTORE_DIR="/restore"
EXPECTED_PGDATA_DIR="/var/lib/postgresql/18/docker"
PGDATA_DIR="${PGDATA:-$EXPECTED_PGDATA_DIR}"
TMP_PARENT="${RESTORE_DIR}/.tmp"
TMP_BASE=""
CRON_FILE="/usr/local/bin/backup.cron"
MAINTENANCE_LOCK_DIR="/backup"
DEBUG="${POSTGRES_RESTORE_DEBUG}"
RESTORE_PSQL_ARGS=()
RESTORE_COMBINE_ARGS=()
RESTORE_CHAIN=()
ORIGINAL_RESTORE_CHAIN=()
ORIGINAL_ARTIFACT_PATHS=()
ORIGINAL_ARTIFACT_IDENTITIES=()
SNAPSHOT_ARTIFACT_PATHS=()
ABSENT_SIDECAR_PATHS=()
MOVED_ARTIFACT_SOURCES=()
MOVED_ARTIFACT_DESTINATIONS=()
MOVED_ARTIFACT_IDENTITIES=()
TMP_CREATED=false
TMP_PARENT_CREATED=false
TMP_PARENT_IDENTITY=""
TMP_IDENTITY=""
CANONICAL_RESTORE_DIR=""
CANONICAL_TMP_PARENT=""
RESTORE_IDENTITY=""
BACKUP_IDENTITY=""
PGDATA_IDENTITY=""
PGDATA_PARENT_IDENTITY=""
CONSUME_COMMITTED=false
CONSUME_ROLLBACK_UNCERTAIN=false
ACTIVE_CHILD_PID=""
RESTORE_SIGNALLED=false
PREPARED_LOGICAL_FILE=""
PGDATA_STAGE_DIR=""
PGDATA_STAGE_IDENTITY=""
PGDATA_OLD_IDENTITY=""
PGDATA_NEW_IDENTITY=""
PGDATA_SWITCH_COMMITTED=false

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
# FUNCTION: log_dry
#   Prints æ dry-run messæge when POSTGRES_RESTORE_DRY_RUN is enæbled
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_dry() {
  if [[ "${POSTGRES_RESTORE_DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] %s\n' "$*"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only this process' vælidæted unique restore workspæce
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  trap - INT TERM
  local index=0
  local preserve_workspace="$CONSUME_ROLLBACK_UNCERTAIN"
  local expected_identity=""
  local restored_identity=""

  if [[ -n "$PGDATA_STAGE_DIR" ]]; then
    reconcile_pgdata_stage_on_exit
  fi

  if [[ "$CONSUME_COMMITTED" != "true" && ${#MOVED_ARTIFACT_SOURCES[@]} -gt 0 ]]; then
    index=$((${#MOVED_ARTIFACT_SOURCES[@]} - 1))
    while (( index >= 0 )); do
      expected_identity="${MOVED_ARTIFACT_IDENTITIES[$index]:-}"
      if [[ -z "$expected_identity" || -e "${MOVED_ARTIFACT_SOURCES[$index]}" || -L "${MOVED_ARTIFACT_SOURCES[$index]}" || ! -f "${MOVED_ARTIFACT_DESTINATIONS[$index]}" || -L "${MOVED_ARTIFACT_DESTINATIONS[$index]}" ]]; then
        preserve_workspace=true
        index=$((index - 1))
        continue
      fi
      restored_identity=$(stat -Lc '%d:%i:%s' -- "${MOVED_ARTIFACT_DESTINATIONS[$index]}" 2>/dev/null || true)
      if [[ "$restored_identity" != "$expected_identity" ]]; then
        preserve_workspace=true
        index=$((index - 1))
        continue
      fi
      mv -T --no-clobber -- "${MOVED_ARTIFACT_DESTINATIONS[$index]}" "${MOVED_ARTIFACT_SOURCES[$index]}" || preserve_workspace=true
      restored_identity=$(stat -Lc '%d:%i:%s' -- "${MOVED_ARTIFACT_SOURCES[$index]}" 2>/dev/null || true)
      if [[ -e "${MOVED_ARTIFACT_DESTINATIONS[$index]}" || -L "${MOVED_ARTIFACT_DESTINATIONS[$index]}" || ! -f "${MOVED_ARTIFACT_SOURCES[$index]}" || -L "${MOVED_ARTIFACT_SOURCES[$index]}" || "$restored_identity" != "$expected_identity" ]]; then
        preserve_workspace=true
      fi
      index=$((index - 1))
    done
    if [[ "$preserve_workspace" == "true" ]]; then
      log_error "Bundle-consumption rollback failed; preserving private workspace for manual recovery: $TMP_BASE"
    else
      MOVED_ARTIFACT_SOURCES=()
      MOVED_ARTIFACT_DESTINATIONS=()
      MOVED_ARTIFACT_IDENTITIES=()
    fi
  fi

  if [[ "$preserve_workspace" == "true" && "$TMP_CREATED" == "true" ]]; then
    log_error "Preserving private restore workspace for manual recovery: $TMP_BASE"
  elif [[ "$TMP_CREATED" == "true" ]]; then
    if remove_restore_tmp_base; then
      if [[ "$TMP_PARENT_CREATED" == "true" ]]; then
        rmdir -- "$TMP_PARENT" 2>/dev/null || true
      fi
    else
      log_error "Refusing to remove changed or unsafe restore workspace: ${TMP_BASE:-<empty>}"
    fi
  fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_signal
#   Forwærds the signæl to the æctive restore client, reæps it, ænd exits non-zero
#ææææææææææææææææææææææææææææææææææ
handle_signal() {
  local signal="$1"
  local exit_code="$2"

  trap - INT TERM
  RESTORE_SIGNALLED=true
  if [[ -n "$ACTIVE_CHILD_PID" ]] && kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null; then
    # Every long physicæl step runs in its own session; terminæte the complete process group.
    kill -s TERM -- "-$ACTIVE_CHILD_PID" 2>/dev/null || kill -s TERM "$ACTIVE_CHILD_PID" 2>/dev/null || true
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
  exit "$exit_code"
}
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_restore_child
#   Runs one long restore step æs æ træked child so signæls cæn terminæte ænd reæp it
#   Ærguments:
#     $@ - commænd ænd ærguments
#ææææææææææææææææææææææææææææææææææ
run_restore_child() {
  local status=0

  setsid --wait -- "$@" &
  ACTIVE_CHILD_PID=$!
  wait "$ACTIVE_CHILD_PID" || status=$?
  ACTIVE_CHILD_PID=""
  return "$status"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- COMMON HELPER FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_tmp_base
#   Vælidætes the unique workspæce pæth, cænonicæl pærent, ænd inode identity
#ææææææææææææææææææææææææææææææææææ
is_safe_tmp_base() {
  local canonical_base=""
  local current_identity=""
  local current_parent_identity=""

  case "$TMP_BASE" in
    "$TMP_PARENT"/postgresql_restore.*)
      [[ -n "${TMP_BASE#"$TMP_PARENT"/postgresql_restore.}" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  [[ -d "$TMP_BASE" && ! -L "$TMP_BASE" ]] || return 1
  [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || return 1
  current_parent_identity=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || return 1
  [[ -n "$TMP_PARENT_IDENTITY" && "$current_parent_identity" == "$TMP_PARENT_IDENTITY" ]] || return 1
  canonical_base=$(realpath -e -- "$TMP_BASE") || return 1
  case "$canonical_base" in
    "$CANONICAL_TMP_PARENT"/postgresql_restore.*) ;;
    *) return 1 ;;
  esac
  current_identity=$(stat -Lc '%d:%i' -- "$TMP_BASE") || return 1
  [[ -n "$TMP_IDENTITY" && "$current_identity" == "$TMP_IDENTITY" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_restore_tmp_base
#   Removes only the identity-pinned workspæce without crossing filesystems
#ææææææææææææææææææææææææææææææææææ
remove_restore_tmp_base() {
  local current_identity=""

  is_safe_tmp_base || return 1
  find "$TMP_BASE" -xdev -depth -mindepth 1 -delete || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$TMP_BASE" 2>/dev/null || true)
  [[ "$current_identity" == "$TMP_IDENTITY" ]] || return 1
  is_safe_tmp_base || return 1
  rmdir -- "$TMP_BASE" || return 1
  [[ ! -e "$TMP_BASE" && ! -L "$TMP_BASE" ]] || return 1
  TMP_CREATED=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_restore_extracted_dir
#   Removes one strict identity-pinned extraction child with `-xdev`
#   Ærguments:
#     $1 - direct full, combined, or incrementæl workspæce child
#ææææææææææææææææææææææææææææææææææ
remove_restore_extracted_dir() {
  local target="$1"
  local name="${target##*/}"
  local expected_identity=""
  local current_identity=""

  is_safe_tmp_base || log_fatal "Restore workspace changed before extraction reset"
  [[ "${target%/*}" == "$TMP_BASE" ]] || log_fatal "Extraction reset target escaped the restore workspace: $target"
  [[ "$name" == "full" || "$name" == "combined" || "$name" =~ ^incremental_[0-9]{8}_[0-9]{1,9}_[0-9]{1,9}$ ]] || log_fatal "Unsafe extraction reset target: $name"
  [[ -d "$target" && ! -L "$target" && "$(realpath -e -- "$target")" == "$target" ]] || log_fatal "Extraction reset target must be a regular non-symlink directory: $name"
  expected_identity=$(stat -Lc '%d:%i' -- "$target") || log_fatal "Cannot inspect extraction reset target: $name"
  find "$target" -xdev -depth -mindepth 1 -delete || log_fatal "Cannot reset extraction directory without crossing filesystems: $name"
  current_identity=$(stat -Lc '%d:%i' -- "$target" 2>/dev/null || true)
  [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Extraction reset target identity changed during deletion: $name"
  is_safe_tmp_base || log_fatal "Restore workspace changed during extraction reset"
  rmdir -- "$target" || log_fatal "Extraction reset target is not empty after bounded deletion: $name"
  [[ ! -e "$target" && ! -L "$target" ]] || log_fatal "Extraction reset target remained after deletion: $name"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_pgdata_dir
#   Rejects broad, symlinked, changed, or mount-æliæsed PGDÆTÆ tærgets
#ææææææææææææææææææææææææææææææææææ
is_safe_pgdata_dir() {
  local canonical_pgdata=""
  local current_identity=""
  local pgdata_parent="${PGDATA_DIR%/*}"
  local expected_parent="${EXPECTED_PGDATA_DIR%/*}"
  local current_parent_identity=""
  local protected_path=""
  local protected_identity=""

  [[ "$PGDATA_DIR" == "$EXPECTED_PGDATA_DIR" ]] || return 1
  [[ "$pgdata_parent" == "$expected_parent" ]] || return 1
  [[ -d "$pgdata_parent" && ! -L "$pgdata_parent" ]] || return 1
  [[ "$(realpath -e -- "$pgdata_parent")" == "$expected_parent" ]] || return 1
  current_parent_identity=$(stat -Lc '%d:%i' -- "$pgdata_parent") || return 1
  if [[ -n "$PGDATA_PARENT_IDENTITY" && "$current_parent_identity" != "$PGDATA_PARENT_IDENTITY" ]]; then
    return 1
  fi
  [[ -d "$PGDATA_DIR" && ! -L "$PGDATA_DIR" ]] || return 1
  canonical_pgdata=$(realpath -e -- "$PGDATA_DIR") || return 1
  [[ "$canonical_pgdata" == "$EXPECTED_PGDATA_DIR" ]] || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$PGDATA_DIR") || return 1
  if [[ -n "$PGDATA_IDENTITY" && "$current_identity" != "$PGDATA_IDENTITY" ]]; then
    return 1
  fi
  for protected_path in "$RESTORE_DIR" "$MAINTENANCE_LOCK_DIR"; do
    [[ -d "$protected_path" && ! -L "$protected_path" ]] || return 1
    protected_identity=$(stat -Lc '%d:%i' -- "$protected_path") || return 1
    [[ "$current_identity" != "$protected_identity" ]] || return 1
    if [[ "$protected_path" == "$RESTORE_DIR" && -n "$RESTORE_IDENTITY" && "$protected_identity" != "$RESTORE_IDENTITY" ]]; then
      return 1
    fi
    if [[ "$protected_path" == "$MAINTENANCE_LOCK_DIR" && -n "$BACKUP_IDENTITY" && "$protected_identity" != "$BACKUP_IDENTITY" ]]; then
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_pgdata_target
#   Records ænd rechecks the exæct cænonicæl PGDÆTÆ inode before restore work
#ææææææææææææææææææææææææææææææææææ
validate_pgdata_target() {
  is_safe_pgdata_dir || log_fatal "PostgreSQL data directory must be the dedicated canonical $EXPECTED_PGDATA_DIR mount path"
  PGDATA_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "${PGDATA_DIR%/*}") || log_fatal "Cannot inspect PostgreSQL data-directory parent"
  PGDATA_IDENTITY=$(stat -Lc '%d:%i' -- "$PGDATA_DIR") || log_fatal "Cannot inspect PostgreSQL data directory"
  is_safe_pgdata_dir || log_fatal "PostgreSQL data directory identity changed during validation"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_restore_mounts
#   Rejects symlinked, æliæsed, or shæred bæckup/restore mount identities
#ææææææææææææææææææææææææææææææææææ
validate_restore_mounts() {
  local canonical_backup=""
  local requested_tmp_parent="${TMP_PARENT%/}"

  [[ "$RESTORE_DIR" == "/restore" ]] || log_fatal "Restore directory must be the dedicated /restore mount"
  [[ -d "$RESTORE_DIR" && ! -L "$RESTORE_DIR" ]] || log_fatal "Restore mount is unavailable or symlinked: $RESTORE_DIR"
  CANONICAL_RESTORE_DIR=$(realpath -e -- "$RESTORE_DIR") || log_fatal "Cannot resolve restore mount: $RESTORE_DIR"
  [[ "$CANONICAL_RESTORE_DIR" == "/restore" ]] || log_fatal "Restore mount contains a symlink or non-canonical component"
  RESTORE_IDENTITY=$(stat -Lc '%d:%i' -- "$RESTORE_DIR") || log_fatal "Cannot inspect restore mount"

  [[ -d "$MAINTENANCE_LOCK_DIR" && ! -L "$MAINTENANCE_LOCK_DIR" ]] || log_fatal "Backup mount is unavailable or symlinked: $MAINTENANCE_LOCK_DIR"
  canonical_backup=$(realpath -e -- "$MAINTENANCE_LOCK_DIR") || log_fatal "Cannot resolve backup mount"
  [[ "$canonical_backup" == "/backup" ]] || log_fatal "Backup mount contains a symlink or non-canonical component"
  BACKUP_IDENTITY=$(stat -Lc '%d:%i' -- "$MAINTENANCE_LOCK_DIR") || log_fatal "Cannot inspect backup mount"
  [[ "$RESTORE_IDENTITY" != "$BACKUP_IDENTITY" ]] || log_fatal "Restore and backup mounts must have different identities"

  CANONICAL_TMP_PARENT=$(realpath -m -- "$TMP_PARENT") || log_fatal "Cannot resolve restore workspace parent"
  [[ "$requested_tmp_parent" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Restore workspace parent contains a symlink or non-canonical component"
  [[ "$CANONICAL_TMP_PARENT" == "$CANONICAL_RESTORE_DIR/.tmp" ]] || log_fatal "Restore workspace parent escaped the restore directory"
  if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
    [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Restore workspace parent must be a regular directory"
    [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Restore workspace parent changed during validation"
    TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect restore workspace parent"
  fi
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
# FUNCTION: create_tmp_base
#   Creætes one mode-0700 workspæce below the vælidæted restore mount
#ææææææææææææææææææææææææææææææææææ
create_tmp_base() {
  if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
    [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Unsafe restore workspace parent: $TMP_PARENT"
  else
    mkdir -- "$TMP_PARENT" || log_fatal "Cannot create restore workspace parent"
    TMP_PARENT_CREATED=true
    TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect created restore workspace parent"
  fi
  [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Restore workspace parent changed before use"
  [[ "$(stat -Lc '%d:%i' -- "$TMP_PARENT")" == "$TMP_PARENT_IDENTITY" ]] || log_fatal "Restore workspace parent identity changed before use"
  TMP_BASE=$(mktemp -d "$TMP_PARENT/postgresql_restore.XXXXXX") || log_fatal "Cannot create private restore workspace"
  TMP_CREATED=true
  chmod 0700 -- "$TMP_BASE" || log_fatal "Cannot restrict private restore workspace"
  TMP_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_BASE") || log_fatal "Cannot inspect private restore workspace"
  is_safe_tmp_base || log_fatal "Unsafe restore workspace: $TMP_BASE"
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
# FUNCTION: validate_boolean
#   Requires æ strict lowercæse true/fælse environment vælue
#ææææææææææææææææææææææææææææææææææ
validate_boolean() {
  local name="$1"
  local value="$2"
  [[ "$value" == "true" || "$value" == "false" ]] || log_fatal "$name must be true or false"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: parse_restore_psql_args
#   Ællows only diægnostic psql flægs thæt cænnot bypass restore sæfety
#ææææææææææææææææææææææææææææææææææ
parse_restore_psql_args() {
  local arg=""
  local -a requested_args=()

  [[ -n "$POSTGRES_RESTORE_PSQL_ARGS" ]] || return 0
  read -r -a requested_args <<< "$POSTGRES_RESTORE_PSQL_ARGS"
  for arg in "${requested_args[@]}"; do
    case "$arg" in
      -a|--echo-all|-b|--echo-errors|-e|--echo-queries|-q|--quiet|-X|--no-psqlrc)
        RESTORE_PSQL_ARGS+=("$arg")
        ;;
      *)
        log_fatal "Unsafe POSTGRES_RESTORE_PSQL_ARGS value: $arg. Only diagnostic echo/quiet/no-psqlrc flags are allowed."
        ;;
    esac
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: parse_restore_combine_args
#   Prevents output, link, mænifest, ænd duræbility overrides during combine
#ææææææææææææææææææææææææææææææææææ
parse_restore_combine_args() {
  local arg=""
  local -a requested_args=()

  [[ -n "$POSTGRES_RESTORE_COMBINE_ARGS" ]] || return 0
  read -r -a requested_args <<< "$POSTGRES_RESTORE_COMBINE_ARGS"
  for arg in "${requested_args[@]}"; do
    case "$arg" in
      --debug) RESTORE_COMBINE_ARGS+=("$arg") ;;
      *) log_fatal "Unsafe POSTGRES_RESTORE_COMBINE_ARGS value: $arg. Only --debug is allowed." ;;
    esac
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: verify_archive_bundle
#   Vælidætes one ærchive ægæinst its strict sidecær ænd bundle mænifest
#ææææææææææææææææææææææææææææææææææ
verify_archive_bundle() {
  local archive="$1"
  local file_name="${archive##*/}"
  local stem="$file_name"
  local sidecar="${archive}.sha256"
  local bundle=""
  local expected=""
  local listed_name=""
  local actual=""

  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  stem="${stem%.sql.zst}"
  bundle="${archive%/*}/bundle_${stem}.sha256"

  [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Restore archive must be a regular non-symlink file: $file_name"
  [[ -f "$bundle" && ! -L "$bundle" ]] || log_fatal "Missing bundle manifest: ${bundle##*/}"
  [[ "$(wc -l < "$bundle" | tr -d ' ')" == "1" ]] || log_fatal "Bundle manifest must contain exactly one newline-terminated record: ${bundle##*/}"
  read -r expected listed_name < "$bundle"
  listed_name="${listed_name#\*}"
  [[ "$expected" =~ ^[0-9a-f]{64}$ && "$listed_name" == "$file_name" ]] || log_fatal "Invalid bundle manifest: ${bundle##*/}"
  cmp -s -- "$bundle" <(printf '%s  %s\n' "$expected" "$file_name") || log_fatal "Bundle manifest is not one canonical record: ${bundle##*/}"
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || log_fatal "Bundle manifest checksum mismatch: $file_name"

  if [[ -e "$sidecar" || -L "$sidecar" ]]; then
    [[ -f "$sidecar" && ! -L "$sidecar" ]] || log_fatal "Checksum sidecar must be a regular non-symlink file: ${sidecar##*/}"
    cmp -s -- "$sidecar" "$bundle" || log_fatal "Checksum sidecar does not match bundle manifest: ${sidecar##*/}"
    log_info "Checksum sidecar and mandatory bundle manifest verified: $file_name"
  elif [[ "$POSTGRES_RESTORE_REQUIRE_CHECKSUM" == "true" ]]; then
    log_fatal "Missing checksum sidecar: ${sidecar##*/}"
  else
    log_warn "Checksum sidecar is absent for $file_name; mandatory bundle manifest verified the archive"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_entries
#   Rejects æbsolute or pærent-træversæl pæths before extræction
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
#   Rejects links ænd speciæl files so no entry cæn escæpe or abuse stæging
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
#   Rejects corrupt, unsæfe-pæth, link, ænd speciæl-file ærchives
#ææææææææææææææææææææææææææææææææææ
validate_tar_archive() {
  local archive="$1"

  zstd -t -q "$archive" || log_fatal "Corrupt compressed archive: ${archive##*/}"
  zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --absolute-names --file=- > /dev/null || log_fatal "Invalid tar archive: ${archive##*/}"
  validate_tar_entries "$archive"
  validate_tar_entry_types "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_connection
#   Vælidætes æn æuthenticæted PostgreSQL connection with æ reæl query
#   Ærguments:
#     $1 - dætæbæse pæssword
#     $2 - dætæbæse næme (optionæl; defæults to POSTGRES_DB)
#ææææææææææææææææææææææææææææææææææ
check_connection() {
  local password="$1"
  local database="${2:-$POSTGRES_DB}"
  local result=""

  log_debug "Validating authenticated connection to ${POSTGRES_DB_HOST}:${POSTGRES_PORT}/${database}"
  if ! result="$(PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$database" \
      --no-password \
      --tuples-only \
      --no-align \
      --set ON_ERROR_STOP=1 \
      --command 'SELECT 1' 2>/dev/null)"; then
    log_fatal "Authenticated connection to database ${database} on ${POSTGRES_DB_HOST}:${POSTGRES_PORT} failed"
  fi
  [[ "$result" == "1" ]] || log_fatal "Database ${database} returned an unexpected connection probe result"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- PHYSICÆL RESTORE FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: database_is_alive
#   Detects æ PostgreSQL server thæt is æccepting or rejecting connections
#ææææææææææææææææææææææææææææææææææ
database_is_alive() {
  local status=0

  pg_isready -h "$POSTGRES_DB_HOST" -p "$POSTGRES_PORT" -t 2 > /dev/null 2>&1 || status=$?
  (( status == 0 || status == 1 ))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_database_stopped
#   Requires operætor confirmætion ænd both remote ænd locæl stopped probes
#ææææææææææææææææææææææææææææææææææ
require_database_stopped() {
  [[ "$POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED" == "true" ]] || log_fatal "Physical restore requires POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true after every database writer is stopped"
  database_is_alive && log_fatal "PostgreSQL is reachable. Stop it before a physical restore."
  if pgrep -x postgres > /dev/null; then
    log_fatal "A local postgres process is running. Aborting physical restore."
  fi
  log_warn "PostgreSQL did not answer the alive probe; proceeding only because explicit stop confirmation was supplied"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_pgdata_writable
#   Ensures the PGDÆTÆ directory is writæble (not reæd-only mount)
#ææææææææææææææææææææææææææææææææææ
test_pgdata_writable() {
  local testfile=""
  local testfile_identity=""
  local current_identity=""

  is_safe_pgdata_dir || log_fatal "Unsafe PostgreSQL data directory: $PGDATA_DIR"
  testfile=$(mktemp "$PGDATA_DIR/.restore-writetest.XXXXXX") || log_fatal "${PGDATA_DIR} is not writable. Default maintenance mounts PGDATA read-only. For a physical restore, stop PostgreSQL and run the explicit one-shot restore override with PGDATA mounted rw and UID/GID aligned with the PostgreSQL server image."
  [[ -f "$testfile" && ! -L "$testfile" ]] || log_fatal "Unsafe PostgreSQL writability-test artifact"
  testfile_identity=$(stat -Lc '%d:%i' -- "$testfile") || log_fatal "Cannot inspect PostgreSQL writability-test artifact"
  current_identity=$(stat -Lc '%d:%i' -- "$testfile") || log_fatal "Cannot re-inspect PostgreSQL writability-test artifact"
  [[ "$current_identity" == "$testfile_identity" && -f "$testfile" && ! -L "$testfile" ]] || log_fatal "PostgreSQL writability-test artifact changed concurrently"
  rm -f -- "$testfile"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_restore_candidates
#   Loæds one null-delimited cændidæte inventory ænd propagætes find/sort errors
#   Ærguments:
#     $1 - output ærræy næme
#     $2 - find næme pættern
#     $3 - true to require regulær files in the find expression
#     $4 - true to version-sort the null-delimited output
#ææææææææææææææææææææææææææææææææææ
load_restore_candidates() {
  local output_name="$1"
  local pattern="$2"
  local regular_only="$3"
  local version_sort="$4"
  local -n output_ref="$output_name"
  local find_args=("$RESTORE_DIR" -xdev -mindepth 1 -maxdepth 1)
  local inventory_fd=""
  local inventory_pid=""
  local candidate=""

  [[ "$regular_only" == "true" || "$regular_only" == "false" ]] || log_fatal "Invalid restore inventory type filter"
  [[ "$version_sort" == "true" || "$version_sort" == "false" ]] || log_fatal "Invalid restore inventory sort mode"
  [[ -n "$pattern" ]] || log_fatal "Restore inventory pattern must not be empty"
  if [[ "$regular_only" == "true" ]]; then
    find_args+=(-type f)
  fi
  find_args+=(-name "$pattern" -print0)
  output_ref=()

  if [[ "$version_sort" == "true" ]]; then
    exec {inventory_fd}< <(set -o pipefail; find "${find_args[@]}" | sort -z -V)
  else
    exec {inventory_fd}< <(find "${find_args[@]}")
  fi
  inventory_pid=$!
  while IFS= read -r -d '' candidate <&"$inventory_fd"; do
    output_ref+=("$candidate")
  done
  exec {inventory_fd}<&-
  wait "$inventory_pid" || log_fatal "Failed to inventory restore candidates matching $pattern"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_restore_candidate_inventory
#   Rejects non-regulær, symlinked, or mælformed top-level selection cændidætes
#   Ærguments:
#     $1 - humæn-reædæble cændidæte kind
#     $2 - find næme pættern
#     $3 - strict Bæsh filenæme regulær expression
#ææææææææææææææææææææææææææææææææææ
validate_restore_candidate_inventory() {
  local kind="$1"
  local pattern="$2"
  local strict_regex="$3"
  local candidates=()
  local candidate=""
  local name=""

  load_restore_candidates candidates "$pattern" false false
  for candidate in "${candidates[@]}"; do
    name="${candidate##*/}"
    [[ -f "$candidate" && ! -L "$candidate" ]] || log_fatal "Matching ${kind} restore candidate must be a regular non-symlink file: $name"
    [[ "$name" =~ $strict_regex ]] || log_fatal "Matching ${kind} restore candidate has an invalid name: $name"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_physical_restore_inventory
#   Vælidætes every full ænd incrementæl cændidæte before selection or æpply
#ææææææææææææææææææææææææææææææææææ
validate_physical_restore_inventory() {
  validate_restore_candidate_inventory full 'full_*.tar.zst' '^full_[0-9]{8}_[0-9]{1,9}\.tar\.zst$'
  validate_restore_candidate_inventory incremental 'incremental_*.tar.zst' '^incremental_[0-9]{8}_[0-9]{1,9}_[0-9]{1,9}\.tar\.zst$'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_logical_restore_inventory
#   Vælidætes every dump or globæls cændidæte before selection or æpply
#   Ærguments:
#     $1 - dump or globæls
#ææææææææææææææææææææææææææææææææææ
validate_logical_restore_inventory() {
  local kind="$1"
  local strict_regex=""
  local legacy_candidates=()

  [[ "$kind" == "dump" || "$kind" == "globals" ]] || log_fatal "Invalid logical restore inventory kind: $kind"
  if [[ "$kind" == "dump" ]]; then
    load_restore_candidates legacy_candidates 'dump_*.sql.zst' false false
    (( ${#legacy_candidates[@]} == 0 )) || log_fatal "Legacy plain-SQL dump archives are unsupported; create a new dump_*.dump.zst custom archive"
    strict_regex='^dump_[0-9]{8}_[0-9]{1,9}\.dump\.zst$'
    validate_restore_candidate_inventory dump 'dump_*.dump.zst' "$strict_regex"
  else
    strict_regex='^globals_[0-9]{8}_[0-9]{1,9}\.sql\.zst$'
    validate_restore_candidate_inventory globals 'globals_*.sql.zst' "$strict_regex"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: find_restore_chain
#   Identifies the lætest full bæckup ænd æssociæted incrementæls
#   Populætes the RESTORE_CHAIN ærrày
#ææææææææææææææææææææææææææææææææææ
find_restore_chain() {
  local full=""
  local full_candidates=()
  local expected_sequence=1
  local incremental=""
  local sequence=""

  validate_physical_restore_inventory
  if [[ -n "$POSTGRES_RESTORE_BACKUP_ID" ]]; then
    [[ "$POSTGRES_RESTORE_BACKUP_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid requested physical backup ID"
    full="$RESTORE_DIR/full_${POSTGRES_RESTORE_BACKUP_ID}.tar.zst"
    [[ -e "$full" || -L "$full" ]] || log_fatal "Requested full backup not found: ${full##*/}"
    [[ -f "$full" && ! -L "$full" ]] || log_fatal "Requested full backup must be a regular non-symlink file: ${full##*/}"
  else
    load_restore_candidates full_candidates 'full_*.tar.zst' true true
    if (( ${#full_candidates[@]} > 0 )); then
      full="${full_candidates[$((${#full_candidates[@]} - 1))]}"
    fi
  fi
  [[ -z "$full" ]] && log_fatal "No full backup (full_*.tar.zst) found in $RESTORE_DIR."

  local id="${full##*/}"
  id="${id#full_}"
  id="${id%.tar.zst}"
  [[ "$id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Selected full backup has an invalid ID: ${full##*/}"

  log_info "Detected backup ID: $id"

  load_restore_candidates RESTORE_CHAIN "incremental_${id}_*.tar.zst" true true
  RESTORE_CHAIN=("$full" "${RESTORE_CHAIN[@]}")

  for incremental in "${RESTORE_CHAIN[@]:1}"; do
    [[ "${incremental##*/}" =~ ^incremental_${id}_([0-9]{1,9})\.tar\.zst$ ]] || log_fatal "Invalid incremental archive name: ${incremental##*/}"
    sequence="${BASH_REMATCH[1]}"
    (( 10#$sequence == expected_sequence )) || log_fatal "Non-contiguous incremental chain at ${incremental##*/}; expected sequence $(printf '%02d' "$expected_sequence")"
    ((expected_sequence += 1))
  done

  log_info "Restore chain to be applied:"
  for f in "${RESTORE_CHAIN[@]}"; do
    log_info "  - $(basename "$f")"
    verify_archive_bundle "$f"
    validate_tar_archive "$f"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: snapshot_restore_artifact
#   Copies one stæble top-level restore ærtifæct ænd records its identity
#   Ærguments:
#     $1 - originæl ærtifæct pæth
#     $2 - privæte snæpshot directory
#ææææææææææææææææææææææææææææææææææ
snapshot_restore_artifact() {
  local source="$1"
  local snapshot_dir="$2"
  local destination="$snapshot_dir/${source##*/}"
  local source_identity=""
  local current_identity=""

  [[ "${source%/*}" == "$RESTORE_DIR" ]] || log_fatal "Refusing to snapshot artifact outside $RESTORE_DIR: $source"
  [[ -f "$source" && ! -L "$source" ]] || log_fatal "Snapshot source must be a regular non-symlink file: ${source##*/}"
  [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Duplicate snapshot artifact: ${destination##*/}"
  source_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot inspect snapshot source: ${source##*/}"
  cp --reflink=never --no-preserve=mode,ownership,timestamps -- "$source" "$destination" || log_fatal "Cannot snapshot restore artifact: ${source##*/}"
  current_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot re-inspect snapshot source: ${source##*/}"
  [[ "$current_identity" == "$source_identity" ]] || log_fatal "Restore artifact changed while being copied: ${source##*/}"
  [[ -f "$destination" && ! -L "$destination" ]] || log_fatal "Unsafe copied restore artifact: ${destination##*/}"
  cmp -s -- "$source" "$destination" || log_fatal "Restore artifact content changed while being copied: ${source##*/}"
  chmod 0600 -- "$destination" || log_fatal "Cannot restrict copied restore artifact: ${destination##*/}"
  ORIGINAL_ARTIFACT_PATHS+=("$source")
  ORIGINAL_ARTIFACT_IDENTITIES+=("$source_identity")
  SNAPSHOT_ARTIFACT_PATHS+=("$destination")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: snapshot_restore_chain
#   Copies the selected mænifest-bound chæin into æ privæte workspæce ænd re-vælidætes it
#ææææææææææææææææææææææææææææææææææ
snapshot_restore_chain() {
  local archive=""
  local file_name=""
  local stem=""
  local snapshot=""
  local snapshots=()

  is_safe_tmp_base || log_fatal "Unsafe restore workspace: $TMP_BASE"
  mkdir -- "$TMP_BASE/input" || log_fatal "Cannot create restore snapshot directory"
  chmod 0700 -- "$TMP_BASE/input" || log_fatal "Cannot restrict restore snapshot directory"
  ORIGINAL_RESTORE_CHAIN=("${RESTORE_CHAIN[@]}")
  ORIGINAL_ARTIFACT_PATHS=()
  ORIGINAL_ARTIFACT_IDENTITIES=()
  SNAPSHOT_ARTIFACT_PATHS=()
  ABSENT_SIDECAR_PATHS=()

  for archive in "${ORIGINAL_RESTORE_CHAIN[@]}"; do
    file_name="${archive##*/}"
    stem="${file_name%.tar.zst}"
    snapshot_restore_artifact "$archive" "$TMP_BASE/input"
    snapshot_restore_artifact "${archive%/*}/bundle_${stem}.sha256" "$TMP_BASE/input"
    if [[ -e "${archive}.sha256" || -L "${archive}.sha256" ]]; then
      snapshot_restore_artifact "${archive}.sha256" "$TMP_BASE/input"
    else
      ABSENT_SIDECAR_PATHS+=("${archive}.sha256")
    fi
    snapshot="$TMP_BASE/input/$file_name"
    verify_archive_bundle "$snapshot"
    validate_tar_archive "$snapshot"
    snapshots+=("$snapshot")
  done
  RESTORE_CHAIN=("${snapshots[@]}")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: extract_chain
#   Decompresses æll bæckup ærchives in the restore chæin to $TMP_BASE
#   Ærguments:
#     $@ - list of ærchive files (full first, then incrementæls)
#ææææææææææææææææææææææææææææææææææ
extract_chain() {
  local restore_files=("$@")
  local first=1
  local archive=""
  local reset_target=""

  is_safe_tmp_base || log_fatal "Unsafe restore workspace before extraction: $TMP_BASE"
  for reset_target in "$TMP_BASE/full" "$TMP_BASE/combined" "$TMP_BASE"/incremental_*; do
    [[ -e "$reset_target" || -L "$reset_target" ]] || continue
    remove_restore_extracted_dir "$reset_target"
  done
  mkdir -- "$TMP_BASE/full" || log_fatal "Cannot create full-backup extraction directory"

  for archive in "${restore_files[@]}"; do
    local name
    name=$(basename "${archive%.tar.zst}")
    local target_dir="$TMP_BASE/$name"
    [[ $first -eq 1 ]] && target_dir="$TMP_BASE/full" && first=0
    if [[ "$target_dir" != "$TMP_BASE/full" ]]; then
      [[ "$name" =~ ^incremental_[0-9]{8}_[0-9]{1,9}_[0-9]{1,9}$ ]] || log_fatal "Unsafe incremental extraction directory name: $name"
      mkdir -- "$target_dir" || log_fatal "Cannot create incremental extraction directory: $name"
    fi

    log_info "Extracting: $(basename "$archive") -> $target_dir"
    run_restore_child /bin/bash -o pipefail -c \
      'zstd -d --stdout "$1" | tar --extract --file=- --directory="$2"' \
      postgresql-restore-extract "$archive" "$target_dir" || log_fatal "Extraction failed for $(basename "$archive")"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: combine_chain
#   Runs pg_combinebæckup to merge full ænd incrementæl bæckups
#   Ærguments:
#     $@ - list of ærchive files (full first, then incrementæls)
#ææææææææææææææææææææææææææææææææææ
combine_chain() {
  local restore_files=("$@")
  local inc_dirs=()
  local archive=""

  # Build list of extræcted incrementæl directories (skip first = full)
  local first=1
  for archive in "${restore_files[@]}"; do
    if [[ $first -eq 1 ]]; then
      first=0
      continue
    fi
    local name
    name=$(basename "${archive%.tar.zst}")
    inc_dirs+=("$TMP_BASE/$name")
  done

  is_safe_tmp_base || log_fatal "Unsafe restore workspace before combine: $TMP_BASE"
  [[ ! -e "$TMP_BASE/combined" && ! -L "$TMP_BASE/combined" ]] || log_fatal "Combined restore target already exists"

  log_info "Combining backup chain with pg_combinebackup..."
  run_restore_child pg_combinebackup \
    "${RESTORE_COMBINE_ARGS[@]}" \
    -o "$TMP_BASE/combined" \
    "$TMP_BASE/full" \
    "${inc_dirs[@]}" || {
    log_fatal "pg_combinebackup failed"
  }

  log_info "Backup chain combined successfully into $TMP_BASE/combined"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_pgdata_stage_dir
#   Vælidætes one identity-pinned hidden sibling on the PGDÆTÆ filesystem
#   Ærguments:
#     $1 - stæge pæth
#     $2 - expected device:inode identity
#ææææææææææææææææææææææææææææææææææ
is_safe_pgdata_stage_dir() {
  local stage="$1"
  local expected_identity="$2"
  local pgdata_parent="${PGDATA_DIR%/*}"
  local pgdata_name="${PGDATA_DIR##*/}"
  local stage_name="${stage##*/}"
  local current_identity=""
  local current_parent_identity=""
  local parent_device=""
  local stage_device=""

  [[ -n "$stage" && -n "$expected_identity" ]] || return 1
  [[ "${stage%/*}" == "$pgdata_parent" ]] || return 1
  [[ "$stage_name" == ".${pgdata_name}.restore-stage."* && -n "${stage_name#.${pgdata_name}.restore-stage.}" ]] || return 1
  [[ "$stage_name" != */* ]] || return 1
  [[ -d "$pgdata_parent" && ! -L "$pgdata_parent" && "$(realpath -e -- "$pgdata_parent")" == "$pgdata_parent" ]] || return 1
  current_parent_identity=$(stat -Lc '%d:%i' -- "$pgdata_parent") || return 1
  [[ -n "$PGDATA_PARENT_IDENTITY" && "$current_parent_identity" == "$PGDATA_PARENT_IDENTITY" ]] || return 1
  [[ -d "$stage" && ! -L "$stage" && "$(realpath -e -- "$stage")" == "$stage" ]] || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$stage") || return 1
  [[ "$current_identity" == "$expected_identity" ]] || return 1
  parent_device=$(stat -Lc '%d' -- "$pgdata_parent") || return 1
  stage_device=$(stat -Lc '%d' -- "$stage") || return 1
  [[ "$stage_device" == "$parent_device" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_pgdata_stage_tree
#   Deletes only one vælidæted stæge tree without crossing filesystem boundæries
#   Ærguments:
#     $1 - stæge pæth
#     $2 - expected device:inode identity
#ææææææææææææææææææææææææææææææææææ
remove_pgdata_stage_tree() {
  local stage="$1"
  local expected_identity="$2"
  local current_identity=""

  is_safe_pgdata_stage_dir "$stage" "$expected_identity" || {
    log_error "Refusing to remove changed or unsafe PostgreSQL restore stage: ${stage:-<empty>}"
    return 1
  }
  run_restore_child find "$stage" -xdev -mindepth 1 -delete || {
    log_error "Failed to remove PostgreSQL restore stage without crossing filesystems: $stage"
    return 1
  }
  current_identity=$(stat -Lc '%d:%i' -- "$stage" 2>/dev/null || true)
  [[ "$current_identity" == "$expected_identity" ]] || {
    log_error "PostgreSQL restore stage identity changed during cleanup: $stage"
    return 1
  }
  rmdir -- "$stage" || {
    log_error "PostgreSQL restore stage is not empty after bounded cleanup: $stage"
    return 1
  }
  [[ ! -e "$stage" && ! -L "$stage" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: clear_pgdata_stage_state
#   Cleærs trænsient stæge bookkeeping only æfter the sibling no longer exists
#ææææææææææææææææææææææææææææææææææ
clear_pgdata_stage_state() {
  PGDATA_STAGE_DIR=""
  PGDATA_STAGE_IDENTITY=""
  PGDATA_OLD_IDENTITY=""
  PGDATA_NEW_IDENTITY=""
  PGDATA_SWITCH_COMMITTED=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reconcile_pgdata_stage_on_exit
#   Rolls bæck æn uncommitted exchænge or preserves both complete trees if uncertain
#ææææææææææææææææææææææææææææææææææ
reconcile_pgdata_stage_on_exit() {
  local current_pgdata_identity=""
  local current_stage_identity=""

  [[ -n "$PGDATA_STAGE_DIR" ]] || return 0
  current_pgdata_identity=$(stat -Lc '%d:%i' -- "$PGDATA_DIR" 2>/dev/null || true)
  current_stage_identity=$(stat -Lc '%d:%i' -- "$PGDATA_STAGE_DIR" 2>/dev/null || true)

  if [[ "$current_pgdata_identity" == "$PGDATA_OLD_IDENTITY" && "$current_stage_identity" == "$PGDATA_NEW_IDENTITY" ]]; then
    PGDATA_IDENTITY="$PGDATA_OLD_IDENTITY"
    if remove_pgdata_stage_tree "$PGDATA_STAGE_DIR" "$PGDATA_NEW_IDENTITY"; then
      clear_pgdata_stage_state
    else
      log_error "Preserving incomplete PostgreSQL restore stage for manual inspection: $PGDATA_STAGE_DIR"
    fi
    return 0
  fi

  if [[ "$current_pgdata_identity" == "$PGDATA_NEW_IDENTITY" && "$current_stage_identity" == "$PGDATA_OLD_IDENTITY" ]]; then
    PGDATA_IDENTITY="$PGDATA_NEW_IDENTITY"
    PGDATA_STAGE_IDENTITY="$PGDATA_OLD_IDENTITY"
    if [[ "$PGDATA_SWITCH_COMMITTED" != "true" ]]; then
      log_warn "Rolling back uncommitted atomic PostgreSQL data-directory exchange"
      if run_restore_child mv --exchange --no-copy -T -- "$PGDATA_STAGE_DIR" "$PGDATA_DIR"; then
        current_pgdata_identity=$(stat -Lc '%d:%i' -- "$PGDATA_DIR" 2>/dev/null || true)
        current_stage_identity=$(stat -Lc '%d:%i' -- "$PGDATA_STAGE_DIR" 2>/dev/null || true)
        if [[ "$current_pgdata_identity" == "$PGDATA_OLD_IDENTITY" && "$current_stage_identity" == "$PGDATA_NEW_IDENTITY" ]]; then
          PGDATA_IDENTITY="$PGDATA_OLD_IDENTITY"
          PGDATA_STAGE_IDENTITY="$PGDATA_NEW_IDENTITY"
          if remove_pgdata_stage_tree "$PGDATA_STAGE_DIR" "$PGDATA_NEW_IDENTITY"; then
            clear_pgdata_stage_state
            return 0
          fi
        fi
      fi
      log_error "Atomic PostgreSQL rollback could not be proven; preserving both complete trees: $PGDATA_STAGE_DIR"
    else
      log_error "Committed PostgreSQL data directory is active; preserving old tree after interrupted cleanup: $PGDATA_STAGE_DIR"
    fi
    return 0
  fi

  if [[ ! -e "$PGDATA_STAGE_DIR" && ! -L "$PGDATA_STAGE_DIR" && ( "$current_pgdata_identity" == "$PGDATA_OLD_IDENTITY" || "$current_pgdata_identity" == "$PGDATA_NEW_IDENTITY" ) ]]; then
    PGDATA_IDENTITY="$current_pgdata_identity"
    clear_pgdata_stage_state
    return 0
  fi

  log_error "PostgreSQL restore-stage state is ambiguous; refusing cleanup and preserving available trees: $PGDATA_STAGE_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_pgdata_stage
#   Builds, verifies, ænd synchronizes the complete new tree beside PGDÆTÆ
#ææææææææææææææææææææææææææææææææææ
prepare_pgdata_stage() {
  local pgdata_parent="${PGDATA_DIR%/*}"
  local pgdata_name="${PGDATA_DIR##*/}"
  local pgdata_owner=""
  local process_owner=""
  local pgdata_device=""
  local stage_device=""

  is_safe_pgdata_dir || log_fatal "Unsafe PostgreSQL data directory before staging: $PGDATA_DIR"
  [[ -d "$TMP_BASE/combined" && ! -L "$TMP_BASE/combined" ]] || log_fatal "Combined physical backup is missing or unsafe"
  LC_ALL=C mv --help | grep -F -- '--exchange' > /dev/null || log_fatal "mv lacks required atomic --exchange support"
  LC_ALL=C mv --help | grep -F -- '--no-copy' > /dev/null || log_fatal "mv lacks required no-copy rename support"
  pgdata_owner=$(stat -Lc '%u:%g' -- "$PGDATA_DIR") || log_fatal "Cannot inspect PostgreSQL data-directory ownership"
  process_owner="$(id -u):$(id -g)"
  [[ "$process_owner" == "$pgdata_owner" ]] || log_fatal "Maintenance UID:GID ${process_owner} must match PostgreSQL data-directory owner ${pgdata_owner}"

  PGDATA_OLD_IDENTITY="$PGDATA_IDENTITY"
  PGDATA_STAGE_DIR=$(mktemp -d "$pgdata_parent/.${pgdata_name}.restore-stage.XXXXXX") || log_fatal "Cannot create same-filesystem PostgreSQL restore stage"
  chmod 0700 -- "$PGDATA_STAGE_DIR" || log_fatal "Cannot restrict PostgreSQL restore stage"
  PGDATA_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$PGDATA_STAGE_DIR") || log_fatal "Cannot inspect PostgreSQL restore stage"
  PGDATA_NEW_IDENTITY="$PGDATA_STAGE_IDENTITY"
  is_safe_pgdata_stage_dir "$PGDATA_STAGE_DIR" "$PGDATA_STAGE_IDENTITY" || log_fatal "Unsafe PostgreSQL restore stage"
  pgdata_device=$(stat -Lc '%d' -- "$PGDATA_DIR") || log_fatal "Cannot inspect PostgreSQL data-directory device"
  stage_device=$(stat -Lc '%d' -- "$PGDATA_STAGE_DIR") || log_fatal "Cannot inspect PostgreSQL restore-stage device"
  [[ "$stage_device" == "$pgdata_device" ]] || log_fatal "PostgreSQL restore stage and data directory must share one filesystem"

  log_info "Staging complete physical backup beside PostgreSQL data directory..."
  run_restore_child cp -a -- "$TMP_BASE/combined/." "$PGDATA_STAGE_DIR/" || log_fatal "Failed to stage combined PostgreSQL backup"
  chmod 0700 -- "$PGDATA_STAGE_DIR" || log_fatal "Failed to restrict staged PostgreSQL data directory"
  is_safe_pgdata_stage_dir "$PGDATA_STAGE_DIR" "$PGDATA_NEW_IDENTITY" || log_fatal "PostgreSQL restore stage changed during copy"
  run_restore_child pg_verifybackup "$PGDATA_STAGE_DIR" || log_fatal "pg_verifybackup rejected the staged PostgreSQL data directory"
  run_restore_child sync -f "$PGDATA_STAGE_DIR" || log_fatal "Failed to synchronize staged PostgreSQL data"
  is_safe_pgdata_stage_dir "$PGDATA_STAGE_DIR" "$PGDATA_NEW_IDENTITY" || log_fatal "PostgreSQL restore stage changed after validation"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: exchange_pgdata_stage
#   Atomically exchænges old PGDÆTÆ with the fully vælidæted sibling tree
#ææææææææææææææææææææææææææææææææææ
exchange_pgdata_stage() {
  local current_pgdata_identity=""
  local current_stage_identity=""

  require_database_stopped
  is_safe_pgdata_dir || log_fatal "PostgreSQL data directory changed before atomic exchange"
  [[ "$PGDATA_IDENTITY" == "$PGDATA_OLD_IDENTITY" ]] || log_fatal "PostgreSQL data-directory identity changed before atomic exchange"
  is_safe_pgdata_stage_dir "$PGDATA_STAGE_DIR" "$PGDATA_NEW_IDENTITY" || log_fatal "PostgreSQL restore stage changed before atomic exchange"

  log_info "Atomically exchanging validated PostgreSQL restore stage with $PGDATA_DIR..."
  run_restore_child mv --exchange --no-copy -T -- "$PGDATA_STAGE_DIR" "$PGDATA_DIR" || log_fatal "Atomic PostgreSQL data-directory exchange failed; no wipe/copy fallback is allowed"
  current_pgdata_identity=$(stat -Lc '%d:%i' -- "$PGDATA_DIR") || log_fatal "Cannot inspect exchanged PostgreSQL data directory"
  current_stage_identity=$(stat -Lc '%d:%i' -- "$PGDATA_STAGE_DIR") || log_fatal "Cannot inspect exchanged old PostgreSQL tree"
  [[ "$current_pgdata_identity" == "$PGDATA_NEW_IDENTITY" && "$current_stage_identity" == "$PGDATA_OLD_IDENTITY" ]] || log_fatal "Atomic PostgreSQL data-directory exchange produced an unproven inode state"
  PGDATA_IDENTITY="$PGDATA_NEW_IDENTITY"
  PGDATA_STAGE_IDENTITY="$PGDATA_OLD_IDENTITY"

  run_restore_child pg_verifybackup "$PGDATA_DIR" || log_fatal "pg_verifybackup rejected PostgreSQL data after atomic exchange"
  run_restore_child sync -f "${PGDATA_DIR%/*}" || log_fatal "Failed to synchronize atomic PostgreSQL data-directory exchange"
  PGDATA_SWITCH_COMMITTED=true

  remove_pgdata_stage_tree "$PGDATA_STAGE_DIR" "$PGDATA_OLD_IDENTITY" || log_fatal "New PostgreSQL data directory is committed, but old-tree cleanup failed"
  clear_pgdata_stage_state
  log_ok "Data directory atomically restored to $PGDATA_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_back_physical
#   Stæges ænd atomically exchænges æ complete vælidæted PostgreSQL dætæ tree
#ææææææææææææææææææææææææææææææææææ
copy_back_physical() {
  if [[ "$POSTGRES_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Would stage, verify, synchronize, and atomically exchange $TMP_BASE/combined with $PGDATA_DIR"
    return
  fi

  prepare_pgdata_stage
  exchange_pgdata_stage
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_absent_sidecars_unchanged
#   Rejects æ sidecær thæt æppeæred æfter the originæl snæpshot
#ææææææææææææææææææææææææææææææææææ
require_absent_sidecars_unchanged() {
  local sidecar=""

  for sidecar in "${ABSENT_SIDECAR_PATHS[@]}"; do
    [[ ! -e "$sidecar" && ! -L "$sidecar" ]] || log_fatal "Checksum sidecar appeared after snapshot: ${sidecar##*/}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: consume_archives
#   Quæræntines every revælidæted bundle ærtifæct before cleænup removes it
#ææææææææææææææææææææææææææææææææææ
consume_archives() {
  local quarantine=""
  local source=""
  local snapshot=""
  local destination=""
  local expected_identity=""
  local current_identity=""
  local moved_identity=""
  local source_device=""
  local quarantine_device=""
  local index=0

  [[ "$POSTGRES_RESTORE_CONSUME_ARCHIVES" == "true" ]] || return 0
  [[ "$POSTGRES_RESTORE_DRY_RUN" != "true" ]] || return 0
  [[ "$TMP_CREATED" == "true" ]] && is_safe_tmp_base || log_fatal "Complete bundle consumption requires the private restore workspace"
  (( ${#ORIGINAL_ARTIFACT_PATHS[@]} > 0 )) || log_fatal "Refusing empty bundle consumption"
  (( ${#ORIGINAL_ARTIFACT_PATHS[@]} == ${#ORIGINAL_ARTIFACT_IDENTITIES[@]} )) || log_fatal "Restore artifact identity records are incomplete"
  (( ${#ORIGINAL_ARTIFACT_PATHS[@]} == ${#SNAPSHOT_ARTIFACT_PATHS[@]} )) || log_fatal "Restore artifact snapshots are incomplete"

  require_absent_sidecars_unchanged

  index=0
  while (( index < ${#ORIGINAL_ARTIFACT_PATHS[@]} )); do
    source="${ORIGINAL_ARTIFACT_PATHS[$index]}"
    snapshot="${SNAPSHOT_ARTIFACT_PATHS[$index]}"
    expected_identity="${ORIGINAL_ARTIFACT_IDENTITIES[$index]}"
    [[ "${source%/*}" == "$RESTORE_DIR" ]] || log_fatal "Refusing bundle consumption outside $RESTORE_DIR: $source"
    [[ -f "$source" && ! -L "$source" ]] || log_fatal "Bundle artifact disappeared or became unsafe: ${source##*/}"
    [[ -f "$snapshot" && ! -L "$snapshot" ]] || log_fatal "Private bundle snapshot disappeared or became unsafe: ${snapshot##*/}"
    current_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot re-inspect bundle artifact: ${source##*/}"
    [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Bundle artifact identity changed after snapshot: ${source##*/}"
    cmp -s -- "$source" "$snapshot" || log_fatal "Bundle artifact content changed after snapshot: ${source##*/}"
    index=$((index + 1))
  done
  require_absent_sidecars_unchanged

  quarantine="$TMP_BASE/consumed-bundle"
  [[ ! -e "$quarantine" && ! -L "$quarantine" ]] || log_fatal "Bundle-consumption quarantine already exists"
  mkdir -- "$quarantine" || log_fatal "Cannot create bundle-consumption quarantine"
  chmod 0700 -- "$quarantine" || log_fatal "Cannot restrict bundle-consumption quarantine"
  quarantine_device=$(stat -Lc '%d' -- "$quarantine") || log_fatal "Cannot inspect bundle-consumption quarantine"
  MOVED_ARTIFACT_SOURCES=()
  MOVED_ARTIFACT_DESTINATIONS=()
  MOVED_ARTIFACT_IDENTITIES=()
  CONSUME_COMMITTED=false
  CONSUME_ROLLBACK_UNCERTAIN=false

  index=0
  while (( index < ${#ORIGINAL_ARTIFACT_PATHS[@]} )); do
    source="${ORIGINAL_ARTIFACT_PATHS[$index]}"
    snapshot="${SNAPSHOT_ARTIFACT_PATHS[$index]}"
    expected_identity="${ORIGINAL_ARTIFACT_IDENTITIES[$index]}"
    [[ -f "$source" && ! -L "$source" ]] || log_fatal "Bundle artifact became unsafe during consumption: ${source##*/}"
    current_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot inspect bundle artifact during consumption: ${source##*/}"
    [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Bundle artifact identity changed during consumption: ${source##*/}"
    cmp -s -- "$source" "$snapshot" || log_fatal "Bundle artifact content changed during consumption: ${source##*/}"
    source_device=$(stat -Lc '%d' -- "$source") || log_fatal "Cannot inspect bundle artifact device: ${source##*/}"
    [[ "$source_device" == "$quarantine_device" ]] || log_fatal "Bundle consumption requires atomic same-filesystem renames"
    destination="$quarantine/${source##*/}"
    [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Duplicate bundle artifact in consumption quarantine: ${source##*/}"
    if ! mv -T --no-clobber -- "$source" "$destination"; then
      current_identity=$(stat -Lc '%d:%i:%s' -- "$source" 2>/dev/null || true)
      moved_identity=$(stat -Lc '%d:%i:%s' -- "$destination" 2>/dev/null || true)
      if [[ ! -e "$source" && ! -L "$source" && -f "$destination" && ! -L "$destination" && "$moved_identity" == "$expected_identity" ]]; then
        MOVED_ARTIFACT_SOURCES+=("$source")
        MOVED_ARTIFACT_DESTINATIONS+=("$destination")
        MOVED_ARTIFACT_IDENTITIES+=("$expected_identity")
      elif [[ -f "$source" && ! -L "$source" && "$current_identity" == "$expected_identity" && ! -e "$destination" && ! -L "$destination" ]]; then
        : # The renæme provæbly did not occur; previously moved entries still roll bæck.
      else
        CONSUME_ROLLBACK_UNCERTAIN=true
      fi
      log_fatal "Failed to quarantine complete bundle artifact: ${source##*/}"
    fi
    MOVED_ARTIFACT_SOURCES+=("$source")
    MOVED_ARTIFACT_DESTINATIONS+=("$destination")
    MOVED_ARTIFACT_IDENTITIES+=("$expected_identity")
    [[ ! -e "$source" && ! -L "$source" ]] || log_fatal "Bundle artifact remained at its original path during quarantine: ${source##*/}"
    [[ -f "$destination" && ! -L "$destination" ]] || log_fatal "Quarantined bundle artifact became unsafe: ${source##*/}"
    moved_identity=$(stat -Lc '%d:%i:%s' -- "$destination") || log_fatal "Cannot inspect quarantined bundle artifact: ${source##*/}"
    [[ "$moved_identity" == "$expected_identity" ]] || log_fatal "Bundle artifact changed during quarantine rename: ${source##*/}"
    index=$((index + 1))
  done
  require_absent_sidecars_unchanged
  CONSUME_COMMITTED=true

  for source in "${ORIGINAL_ARTIFACT_PATHS[@]}"; do
    log_info "Consumed complete bundle artifact: ${source##*/}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_physical_restore
#   Orchestrætes the physicæl restore workflow
#ææææææææææææææææææææææææææææææææææ
handle_physical_restore() {
  acquire_maintenance_lock

  validate_pgdata_target
  find_restore_chain
  require_database_stopped
  create_tmp_base
  snapshot_restore_chain
  if [[ "$POSTGRES_RESTORE_DRY_RUN" == "false" ]]; then
    test_pgdata_writable
  fi
  extract_chain "${RESTORE_CHAIN[@]}"

  # Only combine if there ære incrementæls; otherwise use full directly
  if (( ${#RESTORE_CHAIN[@]} > 1 )); then
    combine_chain "${RESTORE_CHAIN[@]}"
  else
    log_info "No incrementals found – using full backup directly"
    mv -T --no-clobber -- "$TMP_BASE/full" "$TMP_BASE/combined" || log_fatal "Cannot promote full backup into combined restore directory"
  fi

  run_restore_child pg_verifybackup "$TMP_BASE/combined" || log_fatal "pg_verifybackup rejected the combined physical backup"
  validate_physical_restore_inventory
  copy_back_physical
  validate_physical_restore_inventory
  consume_archives
  log_ok "Physical restore completed successfully."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGICÆL RESTORE OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: count_database_objects
#   Counts non-boilerplæte schemæ dump lines thæt prove æ tærget is non-empty
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
count_database_objects() {
  local password="$1"
  local count=""

  if ! count="$(PGPASSWORD="$password" pg_dump \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      --schema-only \
      --no-owner | awk '
        /^[[:space:]]*$/ { next }
        /^--/ { next }
        /^\\/ { next }
        /^SET / { next }
        /^SELECT pg_catalog\.set_config\(/ { next }
        { count += 1 }
        END { print count + 0 }
      ')"; then
    log_fatal "Could not inspect logical restore target ${POSTGRES_DB}"
  fi
  [[ "$count" =~ ^[0-9]+$ ]] || log_fatal "Logical restore target inspection returned an invalid object count"
  printf '%s\n' "$count"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: count_database_large_objects
#   Counts Lærge Objects omitted by pg_dump --schemæ-only emptiness inspection
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
count_database_large_objects() {
  local password="$1"
  local count=""

  if ! count="$(PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      --tuples-only \
      --no-align \
      --set ON_ERROR_STOP=1 \
      --command 'SELECT count(*) FROM pg_catalog.pg_largeobject_metadata;')"; then
    log_fatal "Could not inspect Large Objects in logical restore target ${POSTGRES_DB}"
  fi
  [[ "$count" =~ ^[0-9]+$ ]] || log_fatal "Logical restore Large Object inspection returned an invalid count"
  printf '%s\n' "$count"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_database_recreate_privileges
#   Requires ownership ænd CREÆTEDB/superuser before destructive replæcement
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
check_database_recreate_privileges() {
  local password="$1"
  local allowed=""

  if ! allowed="$(PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      --tuples-only \
      --no-align \
      --set ON_ERROR_STOP=1 \
      --command "SELECT CASE
                          WHEN (r.rolsuper OR r.rolcreatedb)
                           AND (r.rolsuper OR d.datdba = r.oid)
                          THEN 1 ELSE 0
                        END
                   FROM pg_roles r
                   JOIN pg_database d ON d.datname = current_database()
                  WHERE r.rolname = current_user;")"; then
    log_fatal "Could not validate database replacement privileges"
  fi
  [[ "$allowed" == "1" ]] || log_fatal "Database replacement requires target ownership plus CREATEDB, or superuser privileges"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_dump_target
#   Enforces æn empty tærget or explicitly recreætes the configured dætæbæse
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
prepare_dump_target() {
  local password="$1"
  local object_count=""
  local large_object_count=""

  check_connection "$password" "$POSTGRES_DB"
  object_count="$(count_database_objects "$password")"
  large_object_count="$(count_database_large_objects "$password")"
  log_info "Logical restore target contains ${object_count} non-boilerplate schema statement(s) and ${large_object_count} Large Object(s)"

  if [[ "$POSTGRES_RESTORE_RECREATE_DATABASE" == "false" ]]; then
    (( object_count == 0 && large_object_count == 0 )) || log_fatal "Logical restore target ${POSTGRES_DB} is not empty; no changes were applied. Stop every writer and set POSTGRES_RESTORE_RECREATE_DATABASE=true plus POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true for an explicit replacement."
    return
  fi

  [[ "$POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT" == "true" ]] || log_fatal "Database replacement requires POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true after every writer is stopped"
  [[ -n "$POSTGRES_RESTORE_MAINTENANCE_DB" ]] || log_fatal "POSTGRES_RESTORE_MAINTENANCE_DB must not be empty"
  [[ "$POSTGRES_DB" != "$POSTGRES_RESTORE_MAINTENANCE_DB" ]] || log_fatal "Restore target and maintenance database must be different"
  [[ "$POSTGRES_DB" != "template0" && "$POSTGRES_DB" != "template1" ]] || log_fatal "Refusing to replace a PostgreSQL template database"

  check_connection "$password" "$POSTGRES_RESTORE_MAINTENANCE_DB"
  check_database_recreate_privileges "$password"

  if [[ "$POSTGRES_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Would force-disconnect clients, drop ${POSTGRES_DB}, and recreate it from template0 with owner ${POSTGRES_USER}"
    return
  fi

  log_warn "Replacing database ${POSTGRES_DB}; every existing object will be removed"
  if ! PGPASSWORD="$password" dropdb \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --maintenance-db "$POSTGRES_RESTORE_MAINTENANCE_DB" \
      --no-password \
      --if-exists \
      --force \
      "$POSTGRES_DB"; then
    log_fatal "Failed to drop logical restore target ${POSTGRES_DB}"
  fi

  if ! PGPASSWORD="$password" createdb \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --maintenance-db "$POSTGRES_RESTORE_MAINTENANCE_DB" \
      --no-password \
      --owner "$POSTGRES_USER" \
      --template template0 \
      --encoding UTF8 \
      "$POSTGRES_DB"; then
    log_fatal "Target ${POSTGRES_DB} was dropped but could not be recreated"
  fi

  check_connection "$password" "$POSTGRES_DB"
  [[ "$(count_database_objects "$password")" == "0" && "$(count_database_large_objects "$password")" == "0" ]] || log_fatal "Recreated logical restore target is unexpectedly non-empty"
  log_ok "Database ${POSTGRES_DB} recreated as an empty logical restore target"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_globals_target
#   Enforces æ fresh cluster ænd prevents bootstræp-role collisions
#   Ærguments:
#     $1 - dætæbæse pæssword
#     $2 - pæth to globals SQL ærchive
#ææææææææææææææææææææææææææææææææææ
validate_globals_target() {
  local password="$1"
  local file="$2"
  local state=""
  local quoted_bootstrap=""
  local is_superuser=""

  [[ "$POSTGRES_RESTORE_RECREATE_DATABASE" == "false" ]] || log_fatal "POSTGRES_RESTORE_RECREATE_DATABASE applies only to restore-dump"
  [[ -n "$POSTGRES_RESTORE_MAINTENANCE_DB" ]] || log_fatal "POSTGRES_RESTORE_MAINTENANCE_DB must not be empty"
  check_connection "$password" "$POSTGRES_RESTORE_MAINTENANCE_DB"

  if ! state="$(PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_RESTORE_MAINTENANCE_DB" \
      --no-password \
      --tuples-only \
      --no-align \
      --set ON_ERROR_STOP=1 \
      --command "SELECT
                   (SELECT count(*) FROM pg_roles
                     WHERE rolname <> current_user AND rolname !~ '^pg_')
                   || ':' ||
                   (SELECT count(*) FROM pg_tablespace
                     WHERE spcname NOT IN ('pg_default', 'pg_global'));" )"; then
    log_fatal "Could not inspect globals restore target"
  fi
  [[ "$state" == "0:0" ]] || log_fatal "Globals restore requires a freshly initialized cluster containing only the bootstrap role and default tablespaces; found ${state} extra roles:tablespaces"

  is_superuser="$(PGPASSWORD="$password" psql \
    --host "$POSTGRES_DB_HOST" \
    --port "$POSTGRES_PORT" \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_RESTORE_MAINTENANCE_DB" \
    --no-password \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --command 'SELECT rolsuper::int FROM pg_roles WHERE rolname = current_user;')" || log_fatal "Could not inspect globals restore privileges"
  [[ "$is_superuser" == "1" ]] || log_fatal "Globals restore requires a superuser bootstrap role"

  quoted_bootstrap="$(PGPASSWORD="$password" psql \
    --host "$POSTGRES_DB_HOST" \
    --port "$POSTGRES_PORT" \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_RESTORE_MAINTENANCE_DB" \
    --no-password \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --command 'SELECT quote_ident(current_user);')" || log_fatal "Could not quote the globals bootstrap role"

  [[ -f "$file" && ! -L "$file" && "$(stat -Lc '%a' -- "$file")" == "600" ]] || log_fatal "Prepared globals SQL file is unsafe"
  if grep -F -x "CREATE ROLE ${quoted_bootstrap};" "$file" >/dev/null; then
    log_fatal "Globals archive creates bootstrap role ${POSTGRES_USER}; initialize the target cluster with a different temporary superuser before restoring globals"
  fi
  if grep -E '^CREATE TABLESPACE ' "$file" >/dev/null; then
    log_fatal "Globals archive contains CREATE TABLESPACE, which cannot be restored atomically; recreate required tablespaces separately and produce a --no-tablespaces globals bundle"
  fi
  log_ok "Fresh globals restore target and bootstrap-role separation verified"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_tracked_restore_file
#   Writes one child command to æ privæte inode-pinned mode-0600 file
#   Ærguments:
#     $1 - output file inside $TMP_BASE/logical
#     $@ - træked child commænd ænd ærguments
#ææææææææææææææææææææææææææææææææææ
write_tracked_restore_file() {
  local destination="$1"
  shift
  local descriptor=""
  local expected_identity=""
  local opened_identity=""
  local current_identity=""
  local status=0

  is_safe_tmp_base || log_fatal "Unsafe restore workspace before logical file creation"
  [[ "${destination%/*}" == "$TMP_BASE/logical" ]] || log_fatal "Logical restore output escaped its private directory"
  [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Logical restore output already exists: ${destination##*/}"
  ( umask 077; : > "$destination" ) || log_fatal "Cannot create logical restore output: ${destination##*/}"
  chmod 0600 -- "$destination" || log_fatal "Cannot restrict logical restore output: ${destination##*/}"
  [[ -f "$destination" && ! -L "$destination" ]] || log_fatal "Logical restore output is not a regular file: ${destination##*/}"
  expected_identity=$(stat -Lc '%d:%i' -- "$destination") || log_fatal "Cannot inspect logical restore output"
  exec {descriptor}>"$destination" || log_fatal "Cannot open logical restore output"
  opened_identity=$(stat -Lc '%d:%i' -- "/proc/self/fd/$descriptor") || log_fatal "Cannot inspect logical restore output descriptor"
  [[ "$opened_identity" == "$expected_identity" ]] || log_fatal "Logical restore output changed while being opened"
  run_restore_child "$@" >&"$descriptor" || status=$?
  exec {descriptor}>&-
  (( status == 0 )) || log_fatal "Tracked logical restore preparation failed for ${destination##*/}"
  current_identity=$(stat -Lc '%d:%i' -- "$destination") || log_fatal "Cannot re-inspect logical restore output"
  [[ "$current_identity" == "$expected_identity" && -s "$destination" && -f "$destination" && ! -L "$destination" ]] || log_fatal "Logical restore output changed or is empty: ${destination##*/}"
  [[ "$(stat -Lc '%a' -- "$destination")" == "600" ]] || log_fatal "Logical restore output permissions changed: ${destination##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_logical_restore_file
#   Decompresses ænd vælidætes one logicæl bundle in the privæte workspæce
#   Ærguments:
#     $1 - pæth to the SQL ærchive
#     $2 - logicæl restore kind (dump or globals)
#ææææææææææææææææææææææææææææææææææ
prepare_logical_restore_file() {
  local file="$1"
  local kind="$2"
  local raw_file=""
  local prepared_file=""

  [[ "$kind" == "dump" || "$kind" == "globals" ]] || log_fatal "Invalid logical restore kind: $kind"
  is_safe_tmp_base || log_fatal "Unsafe restore workspace before logical preparation"
  [[ ! -e "$TMP_BASE/logical" && ! -L "$TMP_BASE/logical" ]] || log_fatal "Logical restore workspace already exists"
  mkdir -- "$TMP_BASE/logical" || log_fatal "Cannot create logical restore workspace"
  chmod 0700 -- "$TMP_BASE/logical" || log_fatal "Cannot restrict logical restore workspace"

  if [[ "$kind" == "dump" ]]; then
    [[ "$file" == *.dump.zst ]] || log_fatal "Unsupported dump archive format: ${file##*/}"
    prepared_file="$TMP_BASE/logical/dump.dump"
    write_tracked_restore_file "$prepared_file" zstd -d -q --stdout "$file"
    run_restore_child pg_restore --list "$prepared_file" > /dev/null || log_fatal "pg_restore rejected the custom dump archive"
  else
    [[ "$file" == *.sql.zst ]] || log_fatal "Unsupported globals archive format: ${file##*/}"
    raw_file="$TMP_BASE/logical/globals.raw.sql"
    prepared_file="$TMP_BASE/logical/globals.sql"
    write_tracked_restore_file "$raw_file" zstd -d -q --stdout "$file"
    write_tracked_restore_file "$prepared_file" sed -E \
      's/^(GRANT .*) GRANTED BY ("([^"]|"")*"|[^ ;]+);$/SET ROLE \2;\n\1;\nRESET ROLE;/' \
      "$raw_file"
  fi
  PREPARED_LOGICAL_FILE="$prepared_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_logical_file
#   Applies æ custom dump viæ pg_restore or globæls SQL viæ psql
#   Ærguments:
#     $1 - privæte prepæred file
#     $2 - dætæbæse pæssword
#     $3 - logicæl restore kind (dump or globals)
#ææææææææææææææææææææææææææææææææææ
restore_logical_file() {
  local file="$1"
  local password="$2"
  local kind="$3"
  local database="$POSTGRES_DB"

  [[ "$kind" == "dump" || "$kind" == "globals" ]] || log_fatal "Invalid logical restore kind: $kind"
  [[ -f "$file" && ! -L "$file" && "$(stat -Lc '%a' -- "$file")" == "600" ]] || log_fatal "Prepared logical restore file is unsafe"
  [[ "$kind" != "globals" ]] || database="$POSTGRES_RESTORE_MAINTENANCE_DB"

  log_info "Restoring logical ${kind} file: $(basename "$file")"

  if [[ "${POSTGRES_RESTORE_DRY_RUN}" == "true" ]]; then
    if [[ "$kind" == "dump" ]]; then
      log_dry "Would restore custom archive atomically via pg_restore: $(basename "$file")"
    else
      log_dry "Would restore globals SQL atomically via psql: $(basename "$file")"
    fi
    return
  fi

  if [[ "$kind" == "dump" ]]; then
    run_restore_child env PGPASSWORD="$password" pg_restore \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$database" \
      --no-password \
      --single-transaction \
      --exit-on-error \
      "$file" || log_fatal "pg_restore failed for $(basename "$file")"
  else
    log_debug "globals psql args: ${POSTGRES_RESTORE_PSQL_ARGS}"
    run_restore_child env PGPASSWORD="$password" psql \
      "${RESTORE_PSQL_ARGS[@]}" \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$database" \
      --no-password \
      --set ON_ERROR_STOP=1 \
      --single-transaction \
      --file "$file" || log_fatal "psql restore failed for $(basename "$file")"
  fi

  log_ok "Restore completed for $(basename "$file")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_logical_restore
#   Selects, vælidætes, snapshots, ænd restores one logicæl ærchive bundle
#   Ærguments:
#     $1 - dætæbæse pæssword
#     $2 - logicæl restore kind (dump or globals)
#ææææææææææææææææææææææææææææææææææ
handle_logical_restore() {
  local password="$1"
  local kind="$2"
  local file=""
  local original_file=""
  local file_name=""
  local stem=""
  local bundle=""
  local extension="sql.zst"

  [[ "$kind" == "dump" || "$kind" == "globals" ]] || log_fatal "Invalid logical restore kind: $kind"
  [[ "$kind" != "dump" ]] || extension="dump.zst"
  acquire_maintenance_lock
  validate_logical_restore_inventory "$kind"
  if [[ -n "$POSTGRES_RESTORE_BACKUP_ID" ]]; then
    [[ "$POSTGRES_RESTORE_BACKUP_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid requested logical backup ID"
    file="$RESTORE_DIR/${kind}_${POSTGRES_RESTORE_BACKUP_ID}.${extension}"
    [[ -e "$file" || -L "$file" ]] || log_fatal "Requested logical archive not found: ${file##*/}"
    [[ -f "$file" && ! -L "$file" ]] || log_fatal "Requested logical archive must be a regular non-symlink file: ${file##*/}"
  else
    local candidates=()
    load_restore_candidates candidates "${kind}_*.${extension}" true true
    if (( ${#candidates[@]} > 0 )); then
      file="${candidates[$((${#candidates[@]} - 1))]}"
    fi
    [[ -n "$file" ]] || log_fatal "No ${kind}_*.${extension} archive found in $RESTORE_DIR"
  fi

  original_file="$file"
  file_name="${file##*/}"
  if [[ "$kind" == "dump" ]]; then
    [[ "$file_name" =~ ^dump_([0-9]{8}_[0-9]{1,9})\.dump\.zst$ ]] || log_fatal "Selected logical archive has an invalid ID: $file_name"
    stem="${file_name%.dump.zst}"
  else
    [[ "$file_name" =~ ^globals_([0-9]{8}_[0-9]{1,9})\.sql\.zst$ ]] || log_fatal "Selected logical archive has an invalid ID: $file_name"
    stem="${file_name%.sql.zst}"
  fi
  verify_archive_bundle "$file"
  bundle="${file%/*}/bundle_${stem}.sha256"
  create_tmp_base
  mkdir -- "$TMP_BASE/input" || log_fatal "Cannot create restore snapshot directory"
  chmod 0700 -- "$TMP_BASE/input" || log_fatal "Cannot restrict restore snapshot directory"
  ORIGINAL_RESTORE_CHAIN=("$original_file")
  ORIGINAL_ARTIFACT_PATHS=()
  ORIGINAL_ARTIFACT_IDENTITIES=()
  SNAPSHOT_ARTIFACT_PATHS=()
  ABSENT_SIDECAR_PATHS=()
  snapshot_restore_artifact "$file" "$TMP_BASE/input"
  snapshot_restore_artifact "$bundle" "$TMP_BASE/input"
  if [[ -e "${file}.sha256" || -L "${file}.sha256" ]]; then
    snapshot_restore_artifact "${file}.sha256" "$TMP_BASE/input"
  else
    ABSENT_SIDECAR_PATHS+=("${file}.sha256")
  fi
  file="$TMP_BASE/input/$file_name"
  verify_archive_bundle "$file"
  zstd -t -q "$file" || log_fatal "Corrupt logical archive: ${file##*/}"
  prepare_logical_restore_file "$file" "$kind"
  if [[ "$kind" == "dump" ]]; then
    prepare_dump_target "$password"
  else
    validate_globals_target "$password" "$PREPARED_LOGICAL_FILE"
  fi
  validate_logical_restore_inventory "$kind"
  restore_logical_file "$PREPARED_LOGICAL_FILE" "$password" "$kind"
  validate_logical_restore_inventory "$kind"
  consume_archives
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CRON STÆRTUP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_cron
#   Læunches Supercronic with the configured schedule file
#ææææææææææææææææææææææææææææææææææ
start_cron() {
  log_info "Starting supercronic with schedule file $CRON_FILE"
  exec /usr/local/bin/supercronic "$CRON_FILE"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Dispatches explicit schedule, physicæl restore, dump restore, or globæls restore mode
#ææææææææææææææææææææææææææææææææææ
main() {
  local mode="${1:-schedule}"
  local password

  [[ "${2:-}" != "--dry-run" ]] || POSTGRES_RESTORE_DRY_RUN=true
  validate_boolean "POSTGRES_RESTORE_DRY_RUN" "$POSTGRES_RESTORE_DRY_RUN"
  validate_boolean "POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED" "$POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED"
  validate_boolean "POSTGRES_RESTORE_CONSUME_ARCHIVES" "$POSTGRES_RESTORE_CONSUME_ARCHIVES"
  validate_boolean "POSTGRES_RESTORE_REQUIRE_CHECKSUM" "$POSTGRES_RESTORE_REQUIRE_CHECKSUM"
  validate_boolean "POSTGRES_RESTORE_RECREATE_DATABASE" "$POSTGRES_RESTORE_RECREATE_DATABASE"
  validate_boolean "POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT" "$POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT"
  parse_restore_combine_args

  case "$mode" in
    schedule)
      log_info "Scheduled backup mode selected."
      start_cron
      ;;
    restore)
      validate_restore_mounts
      handle_physical_restore
      ;;
    restore-dump)
      validate_restore_mounts
      password="$(read_password)"
      handle_logical_restore "$password" dump
      ;;
    restore-globals)
      parse_restore_psql_args
      validate_restore_mounts
      password="$(read_password)"
      handle_logical_restore "$password" globals
      ;;
    *)
      log_fatal "Invalid mode: $mode. Use schedule, restore, restore-dump, or restore-globals"
      ;;
  esac
}

main "$@"
