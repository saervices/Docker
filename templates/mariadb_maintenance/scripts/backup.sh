#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENVIRONMENT VÆRIÆBLES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
MARIADB_ROOT_USER="${MARIADB_ROOT_USER:-root}"
MARIADB_DATABASE="${MARIADB_DATABASE:?MARIADB_DATABASE is required}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:?MARIADB_ROOT_PASSWORD_FILE is required}"
MARIADB_DB_HOST="${MARIADB_DB_HOST:-mariadb}"
MARIADB_BACKUP_RETENTION_DAYS="${MARIADB_BACKUP_RETENTION_DAYS:-7}"

BACKUP_DIR="/backup"
TMP_DIR="/tmp/mariadb_backup"
TODAY="$(date +'%Y%m%d')"
DEBUG="${MARIADB_BACKUP_DEBUG:-false}"
LOCKFILE="/tmp/mariadb_backup.lock"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
log_info() {
  printf '[INFO] %s\n' "$*"
}

log_ok() {
  printf '[OK] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '[DEBUG] %s\n' "$*"
  fi
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

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
# FUNCTION: compress_backup
#   Ærchives ænd compresses æ bæckup directory to .zst
#   Ærguments:
#     $1 - bæckup type (full|incrementæl|dump)
#     $2 - suffix (e.g., 01 or 01_01)
#     $3 - source directory (defæult: $TMP_DIR)
#ææææææææææææææææææææææææææææææææææ
compress_backup() {
  local type="$1"
  local suffix="$2"
  local source_dir="${3:-$TMP_DIR}"

  mkdir -p "$BACKUP_DIR/$TODAY"

  local file_name
  if [[ "$type" == "dump" ]]; then
    file_name="${type}_${TODAY}_${suffix}.sql.zst"
  else
    file_name="${type}_${TODAY}_${suffix}.zst"
  fi

  log_info "Compressing backup -> $file_name"

  tar -cf - -C "$source_dir" . | zstd --rm -q --content-size -o "$BACKUP_DIR/$TODAY/$file_name" || {
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
    latest_full=$(find "$BACKUP_DIR/$TODAY" -type f -name "full_${TODAY}_*.zst" 2>/dev/null | sort | tail -n1)
  fi

  if [[ -z "$latest_full" ]]; then
    latest_full=$(find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -type f -name "full_${TODAY}_*.zst" 2>/dev/null | sort | tail -n1)
  fi

  echo "$latest_full"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: decompress_backup
#   Unpæcks æ given .zst ærchive into $TMP_DIR
#   Ærguments:
#     $1 - pæth to the .zst ærchive file
#ææææææææææææææææææææææææææææææææææ
decompress_backup() {
  local file="$1"

  log_info "Decompressing $file -> $TMP_DIR"
  prepare_tmp_dir

  zstd -d -q --stdout "$file" | tar -xf - -C "$TMP_DIR" || {
    log_fatal "Failed to decompress $file"
  }
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_full_backup
#   Executes æ full mariadb-backup ænd compresses the result
#ææææææææææææææææææææææææææææææææææ
perform_full_backup() {
  prepare_tmp_dir

  log_info "Creating FULL backup in $TMP_DIR"

  mariadb-backup \
    --backup \
    --target-dir="$TMP_DIR" \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" \
    --password="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" > /dev/null 2>&1 || {
    log_fatal "MariaDB full backup failed"
  }

  log_info "Full backup created in $TMP_DIR"

  local count=0
  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    log_debug "Counting existing full backups from today in $BACKUP_DIR/$TODAY"
    count=$(find "$BACKUP_DIR/$TODAY" -type f -name "full_${TODAY}_*.zst" | wc -l)
  else
    log_debug "No existing full backups from today in $BACKUP_DIR/$TODAY"
  fi

  local suffix=$(printf "%02d" $((count + 1)))
  compress_backup "full" "$suffix" "$TMP_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_incremental_backup
#   Bæcks up only the chænges since the lætest full bæckup
#ææææææææææææææææææææææææææææææææææ
perform_incremental_backup() {
  local latest_full
  latest_full=$(get_latest_full)

  if [[ -z "$latest_full" || ! -f "$latest_full" ]]; then
    log_info "No full backup found. Creating one instead."
    perform_full_backup
    return 0
  fi

  log_info "Using $latest_full as base for incremental"

  decompress_backup "$latest_full"

  local full_number="${latest_full##*_}"
  full_number="${full_number%.zst}"

  local inc_count=0
  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    inc_count=$(find "$BACKUP_DIR/$TODAY" -type f -name "incremental_${TODAY}_${full_number}_*.zst" | wc -l)
  fi

  local inc_suffix=$(printf "%02d" $((inc_count + 1)))

  log_info "Creating INCREMENTAL backup -> incremental_${TODAY}_${full_number}_${inc_suffix}.zst"

  mariadb-backup \
    --backup \
    --target-dir="$TMP_DIR/incremental" \
    --incremental-basedir="$TMP_DIR" \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" \
    --password="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" > /dev/null 2>&1 || {
    log_fatal "Failed to create incremental backup"
  }

  compress_backup "incremental" "${full_number}_${inc_suffix}" "$TMP_DIR/incremental"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_dump_backup
#   Creætes æ logicæl SQL dump ænd compresses it with zstd
#ææææææææææææææææææææææææææææææææææ
perform_dump_backup() {
  prepare_tmp_dir

  local dump_file="$TMP_DIR/dump.sql"
  local compressed_file="dump_${TODAY}_$(date +'%H%M%S').sql.zst"

  log_info "Performing DUMP backup -> $compressed_file"

  mariadb-dump \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" \
    --password="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" \
    --databases "$MARIADB_DATABASE" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --add-drop-database \
    --add-drop-table \
    --create-options \
    --extended-insert \
    --quick \
    --net_buffer_length=1M \
    > "$dump_file" 2>/dev/null || {
      log_fatal "Failed to create SQL dump"
    }

  compress_backup "dump" "$(date +'%H%M%S')" "$TMP_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_old_backups
#   Deletes bæckup folders older thæn the configured retention period
#ææææææææææææææææææææææææææææææææææ
remove_old_backups() {
  log_info "Checking for backup folders older than $MARIADB_BACKUP_RETENTION_DAYS days"

  local old_dirs
  mapfile -t old_dirs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$MARIADB_BACKUP_RETENTION_DAYS")

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

  log_debug "$count backup folder(s) older than $MARIADB_BACKUP_RETENTION_DAYS days removed."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Entry point: hændles lockfile, cleænup, bæckup type execution
#   Ærguments:
#     $1 - bæckup type (full|incrementæl|dump)
#ææææææææææææææææææææææææææææææææææ
main() {
  if [[ "$DEBUG" != "true" ]]; then
    exec > >(grep -E '^\[(INFO|OK|WARN|ERROR|FATAL)\] ') 2>&1
  fi

  if ! ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
    log_fatal "Another backup process is already running. Lockfile exists: $LOCKFILE"
  fi

  remove_old_backups

  case "$1" in
    full)
      perform_full_backup
      ;;
    incremental)
      perform_incremental_backup
      ;;
    dump)
      perform_dump_backup
      ;;
    *)
      log_fatal "Invalid backup type: $1"
      ;;
  esac
}

main "$@"
