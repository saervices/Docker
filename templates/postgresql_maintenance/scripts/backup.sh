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
POSTGRES_BACKUP_FULL_ARGS="${POSTGRES_BACKUP_FULL_ARGS:-}"
POSTGRES_BACKUP_INCREMENTAL_ARGS="${POSTGRES_BACKUP_INCREMENTAL_ARGS:-}"
POSTGRES_BACKUP_DUMP_ARGS="${POSTGRES_BACKUP_DUMP_ARGS:-}"
POSTGRES_BACKUP_GLOBAL_ARGS="${POSTGRES_BACKUP_GLOBAL_ARGS:-}"

BACKUP_DIR="${BACKUP_DIR:-/backup}"
TMP_DIR="/tmp/postgresql_backup"
TODAY="$(date +'%Y%m%d')"
DEBUG="${POSTGRES_BACKUP_DEBUG:-false}"
LOCKFILE="/tmp/postgresql_backup.lock"

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
# FUNCTION: cleanup
#   Cleæns up temporæry directory ænd lockfile on script exit
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  rm -rf "$TMP_DIR"
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP HELPER FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_tmp_dir
#   Ensures the bæckup workspæce is cleæn ænd reædy
#ææææææææææææææææææææææææææææææææææ
prepare_tmp_dir() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  log_debug "Created $TMP_DIR"
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

  mkdir -p "$BACKUP_DIR/$TODAY"

  local file_name
  if [[ "$type" == "dump" || "$type" == "globals" ]]; then
    file_name="${type}_${TODAY}_${suffix}.sql.zst"
  else
    file_name="${type}_${TODAY}_${suffix}.tar.zst"
  fi

  log_info "Compressing backup -> $file_name"

  tar -cf - -C "$source_dir" . | zstd --rm -q -T0 -"${POSTGRES_BACKUP_COMPRESS_LEVEL}" \
    --content-size -o "$BACKUP_DIR/$TODAY/$file_name" || {
    log_fatal "Failed to compress backup"
  }

  log_ok "Backup saved as $BACKUP_DIR/$TODAY/$file_name"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_latest_full
#   Returns the pæth of the lætest full bæckup for todæy
#ææææææææææææææææææææææææææææææææææ
get_latest_full() {
  local latest_full=""

  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    latest_full=$(find "$BACKUP_DIR/$TODAY" -type f -name "full_${TODAY}_*.tar.zst" 2>/dev/null | sort | tail -n1)
  fi

  if [[ -z "$latest_full" ]]; then
    latest_full=$(find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -type f -name "full_${TODAY}_*.tar.zst" 2>/dev/null | sort | tail -n1)
  fi

  echo "$latest_full"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_latest_manifest
#   Returns the pæth of the lætest bæckup mænifest for todæy
#   Used æs bæse for the next incrementæl bæckup
#ææææææææææææææææææææææææææææææææææ
get_latest_manifest() {
  local latest_manifest=""

  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    latest_manifest=$(find "$BACKUP_DIR/$TODAY" -type f -name "*.manifest" 2>/dev/null | sort | tail -n1)
  fi

  echo "$latest_manifest"
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
  prepare_tmp_dir

  log_info "Creating FULL backup in $TMP_DIR"

  local count=0
  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    log_debug "Counting existing full backups from today in $BACKUP_DIR/$TODAY"
    count=$(find "$BACKUP_DIR/$TODAY" -type f -name "full_${TODAY}_*.tar.zst" | wc -l)
  else
    log_debug "No existing full backups from today in $BACKUP_DIR/$TODAY"
  fi

  local suffix
  suffix=$(printf "%02d" $((count + 1)))
  local base_name="full_${TODAY}_${suffix}"

  local _pg_err
  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  if ! _pg_err=$(PGPASSWORD="$password" pg_basebackup \
    --host="$POSTGRES_DB_HOST" \
    --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" \
    --no-password \
    --checkpoint=fast \
    --wal-method=stream \
    --format=plain \
    -D "$TMP_DIR" \
    $POSTGRES_BACKUP_FULL_ARGS 2>&1); then
    log_error "pg_basebackup: $_pg_err"
    log_fatal "pg_basebackup full backup failed"
  fi

  log_info "Full backup captured in $TMP_DIR"

  mkdir -p "$BACKUP_DIR/$TODAY"
  compress_backup "full" "$suffix" "$TMP_DIR"

  # Sæve mænifest sepærætely for use æs incrementæl bæse
  if [[ -f "$TMP_DIR/backup_manifest" ]]; then
    cp "$TMP_DIR/backup_manifest" "$BACKUP_DIR/$TODAY/${base_name}.manifest"
    log_debug "Manifest saved as $BACKUP_DIR/$TODAY/${base_name}.manifest"
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

  local latest_manifest
  latest_manifest=$(get_latest_manifest)

  if [[ -z "$latest_manifest" || ! -f "$latest_manifest" ]]; then
    log_info "No manifest found for today. Creating full backup instead."
    perform_full_backup "$password"
    return 0
  fi

  log_info "Using manifest $latest_manifest as base for incremental"

  # Determine full bæckup number from lætest full bæckup filenæme
  local latest_full
  latest_full=$(get_latest_full)
  local full_number="${latest_full##*_}"
  full_number="${full_number%.tar.zst}"

  local inc_count=0
  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    inc_count=$(find "$BACKUP_DIR/$TODAY" -type f -name "incremental_${TODAY}_${full_number}_*.tar.zst" | wc -l)
  fi

  local inc_suffix
  inc_suffix=$(printf "%02d" $((inc_count + 1)))
  local base_name="incremental_${TODAY}_${full_number}_${inc_suffix}"

  log_info "Creating INCREMENTAL backup -> ${base_name}.tar.zst"

  prepare_tmp_dir

  local _pg_err
  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  if ! _pg_err=$(PGPASSWORD="$password" pg_basebackup \
    --host="$POSTGRES_DB_HOST" \
    --port="$POSTGRES_PORT" \
    --username="$POSTGRES_USER" \
    --no-password \
    --incremental="$latest_manifest" \
    --checkpoint=fast \
    --wal-method=stream \
    --format=plain \
    -D "$TMP_DIR" \
    $POSTGRES_BACKUP_INCREMENTAL_ARGS 2>&1); then
    log_error "pg_basebackup: $_pg_err"
    log_fatal "pg_basebackup incremental backup failed"
  fi

  compress_backup "incremental" "${full_number}_${inc_suffix}" "$TMP_DIR"

  # Updæte mænifest to the lætest one for subsequent incrementæls
  if [[ -f "$TMP_DIR/backup_manifest" ]]; then
    cp "$TMP_DIR/backup_manifest" "$BACKUP_DIR/$TODAY/${base_name}.manifest"
    log_debug "Manifest updated as $BACKUP_DIR/$TODAY/${base_name}.manifest"
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

  local dump_file="$TMP_DIR/dump.sql"
  local time_suffix
  time_suffix="$(date +'%H%M%S')"

  log_info "Performing DUMP backup -> dump_${TODAY}_${time_suffix}.sql.zst"
  log_debug "Using dump args: ${POSTGRES_BACKUP_DUMP_ARGS}"

  local _pg_err_file="$TMP_DIR/pg_err.txt"
  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  if ! PGPASSWORD="$password" pg_dump \
    --host "$POSTGRES_DB_HOST" \
    --port "$POSTGRES_PORT" \
    --username "$POSTGRES_USER" \
    --encoding "UTF8" \
    --dbname "$POSTGRES_DB" \
    --no-password \
    $POSTGRES_BACKUP_DUMP_ARGS \
    > "$dump_file" 2>"$_pg_err_file"; then
    log_error "pg_dump: $(cat "$_pg_err_file")"
    log_fatal "pg_dump failed"
  fi

  compress_backup "dump" "$time_suffix" "$TMP_DIR"
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
  local time_suffix
  time_suffix="$(date +'%H%M%S')"

  log_info "Creating GLOBALS backup -> globals_${TODAY}_${time_suffix}.sql.zst"
  log_debug "Using global args: ${POSTGRES_BACKUP_GLOBAL_ARGS}"

  local _pg_err_file="$TMP_DIR/pg_err.txt"
  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  if ! PGPASSWORD="$password" pg_dumpall \
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

  compress_backup "globals" "$time_suffix" "$TMP_DIR"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RETENTION & CLEÆNUP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_old_backups
#   Deletes bæckup folders older thæn the configured retention period
#ææææææææææææææææææææææææææææææææææ
remove_old_backups() {
  log_info "Checking for backup folders older than $POSTGRES_BACKUP_RETENTION_DAYS days"

  local old_dirs
  mapfile -t old_dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$POSTGRES_BACKUP_RETENTION_DAYS")

  local count="${#old_dirs[@]}"

  if (( count == 0 )); then
    log_info "No old backup folders found to remove."
    return 0
  fi

  log_info "Found $count old backup folder(s) to delete:"
  for dir in "${old_dirs[@]}"; do
    log_info "  -> $dir"
    rm -rf "$dir"
  done

  log_debug "$count backup folder(s) older than $POSTGRES_BACKUP_RETENTION_DAYS days removed."
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

  if ! ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
    log_fatal "Another backup process is already running. Lockfile exists: $LOCKFILE"
  fi

  local mode="${1:-dump}"
  mode="${mode,,}"

  local password
  password="$(read_password)"
  check_connection "$password"

  remove_old_backups

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
    *)
      log_fatal "Invalid backup type: $mode. Use one of: full, incremental, dump, globals"
      ;;
  esac

  log_ok "PostgreSQL backup completed."
}

main "$@"