#!/bin/bash
set -euo pipefail
umask 077

# === ENVIRONMENT VARIABLES === #
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

# === LOGGING FUNCTIONS === #
log_info() {
  printf '[INFO] %s\n' "$*"
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '[DEBUG] %s\n' "$*"
  fi
}

log_dry() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] %s\n' "$*"
  fi
}

log_err() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

# === CLEANUP HANDLER ON EXIT === #
# Cleans up temporary directory and lockfile on script exit
cleanup() {
  rm -rf "$TMP_DIR"
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

# === CREATE/RESET TEMPORARY DIRECTORY === #
# Ensures the backup workspace is clean and ready
prepare_tmp_dir() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  log_debug "Created $TMP_DIR"
}

# === COMPRESS BACKUP DIRECTORY TO .zst FILE === #
# Archives and compresses a backup directory to .zst
compress_backup() {
  local type="$1"     # full|incremental|dump
  local suffix="$2"   # e.g., 01 or 01_01
  local source_dir="${3:-$TMP_DIR}"  # directory to compress

  mkdir -p "$BACKUP_DIR/$TODAY"

  local file_name
  if [[ "$type" == "dump" ]]; then
    file_name="${type}_${TODAY}_${suffix}.sql.zst"
  else
    file_name="${type}_${TODAY}_${suffix}.zst"
  fi

  log_info "Compressing backup -> $file_name"

  tar -cf - -C "$source_dir" . | zstd --rm -q --content-size -o "$BACKUP_DIR/$TODAY/$file_name" || {
    log_err "Failed to compress backup"
  }

  log_info "Backup saved as $BACKUP_DIR/$TODAY/$file_name"
}

# === LOCATE LATEST FULL BACKUP === #
# Returns the path of the latest full backup for today or earlier
get_latest_full() {
  local latest_full
  latest_full=$(find "$BACKUP_DIR"/"$TODAY"/full_"$TODAY"_*.zst "$BACKUP_DIR"/full_"$TODAY"_*.zst 2>/dev/null \
    | grep -v '.zst.*.zst' | sort | tail -n1)

  if [[ -z "$latest_full" ]]; then
    latest_full=$(find "$BACKUP_DIR"/*/full_${TODAY}_*.zst "$BACKUP_DIR"/full_${TODAY}_*.zst 2>/dev/null \
      | grep -v '.zst.*.zst' | sort | tail -n1)
  fi

  echo "$latest_full"
}

# === DECOMPRESS BACKUP TO TEMP FOLDER === #
# Unpacks a given .zst archive into $TMP_DIR
decompress_backup() {
  local file="$1"

  log_info "Decompressing $file -> /tmp/mariadb_backup/"
  prepare_tmp_dir

  zstd -d -q --stdout "$file" | tar -xf - -C "$TMP_DIR" || {
    log_err "Failed to decompress $file"
  }
}

# === PERFORM FULL BACKUP === #
# Executes a full mariadb-backup and compresses the result
perform_full_backup() {
  prepare_tmp_dir

  log_info "Creating FULL backup in $TMP_DIR"

  mariadb-backup \
    --backup \
    --target-dir="$TMP_DIR" \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" \
    --password="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" > /dev/null 2>&1 || {
    log_err "MariaDB full backup failed"
  }

  log_info "Full backup created in $TMP_DIR"

  # Count existing full backups today
  local count=0
  if [[ -d "$BACKUP_DIR/$TODAY" ]]; then
    log_debug "Counting existing full backups from today in $BACKUP_DIR/$TODAY"
    count=$(find "$BACKUP_DIR"/"$TODAY" -type f -name "full_${TODAY}_*.zst" | wc -l)
  else
    log_debug "No existing full backups from today in $BACKUP_DIR/$TODAY"
  fi

  local suffix=$(printf "%02d" $((count + 1)))
  compress_backup "full" "$suffix" "$TMP_DIR"
}

# === PERFORM INCREMENTAL BACKUP === #
# Backs up only the changes since the latest full backup
perform_incremental_backup() {
  local latest_full
  latest_full=$(get_latest_full)

  if [[ ! -f "$latest_full" ]]; then
    log_info "No full backup found. Creating one instead."
    perform_full_backup
    return 0
  fi

  log_info "Using $latest_full as base for incremental"

  # Decompress latest full backup into /tmp
  decompress_backup "$latest_full"

  # Extract full backup number
  local full_number="${latest_full##*_}"  # e.g., full_20250615_01.zst -> 01.zst
  full_number="${full_number%.zst}"      # 01.zst -> 01

  # Count existing incrementals for this full backup
  local inc_count
  inc_count=$(find "$BACKUP_DIR"/"$TODAY" -type f -name "incremental_${TODAY}_${full_number}_*.zst" | wc -l)

  local inc_suffix=$(printf "%02d" $((inc_count + 1)))

  log_info "Creating INCREMENTAL backup -> incremental_${TODAY}_${full_number}_${inc_suffix}.zst"

  mariadb-backup \
    --backup \
    --target-dir="$TMP_DIR/incremental" \
    --incremental-basedir="$TMP_DIR" \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" \
    --password="$(cat "$MARIADB_ROOT_PASSWORD_FILE")" > /dev/null 2>&1 || {
    log_err "Failed to create incremental backup"
  }

  compress_backup "incremental" "${full_number}_${inc_suffix}" "$TMP_DIR/incremental"
}

# === PERFORM SQL DUMP BACKUP === #
# Creates a logical SQL dump and compresses it with zstd
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
      log_err "Failed to create SQL dump"
    }

  compress_backup "dump" "$(date +'%H%M%S')" "$TMP_DIR"
}

# === DELETE OLD BACKUPS === #
# Deletes backup folders older than the configured retention period
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

# === MAIN ENTRY POINT === #
# Entry point: handles lockfile, cleanup, backup type execution
main() {
  # Filter output unless DEBUG=true
  if [[ "$DEBUG" != "true" ]]; then
    exec > >(grep -E '^\[INFO\] |^\[ERROR\] ') 2>&1
  fi

  if ! ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
    log_err "Another backup process is already running. Lockfile exists: $LOCKFILE"
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
      log_err "Invalid backup type: $1"
      ;;
  esac
}

main "$@"