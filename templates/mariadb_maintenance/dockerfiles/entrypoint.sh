#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENVIRONMENT VÆRIÆBLES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
MARIADB_ROOT_USER="${MARIADB_ROOT_USER:-root}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:?MARIADB_ROOT_PASSWORD_FILE is required}"
MARIADB_DB_HOST="${MARIADB_DB_HOST:-mariadb}"
MARIADB_RESTORE_DRY_RUN="${MARIADB_RESTORE_DRY_RUN:-false}"

RESTORE_DIR="/restore"
TMP_BASE="/tmp/restore_chain"
MARIADB_DIR="/var/lib/mysql"
DEBUG="${MARIADB_RESTORE_DEBUG:-false}"
LOCKFILE="/tmp/restore.lock"

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

log_dry() {
  if [[ "${MARIADB_RESTORE_DRY_RUN:-false}" == "true" ]]; then
    printf '[DRY RUN] %s\n' "$*"
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
#   Removes temporæry restore dætæ ænd lockfile when the script exits
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  rm -rf "$TMP_BASE"
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RESTORE FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_db_running
#   Verifies thæt MæriæDB is not running before stærting the restore
#ææææææææææææææææææææææææææææææææææ
is_db_running() {
  if mariadb-admin ping --silent --host="$MARIADB_DB_HOST" --user="$MARIADB_ROOT_USER" --password="$(<"$MARIADB_ROOT_PASSWORD_FILE")" > /dev/null 2>&1; then
    log_fatal "MariaDB appears to be running (ping successful). Aborting restore."
  fi

  if pgrep -x mariadbd > /dev/null; then
    log_fatal "MariaDB process found running. Aborting restore."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: find_restore_chain
#   Identifies the lætest full bæckup ænd æssociæted incrementæls
#ææææææææææææææææææææææææææææææææææ
find_restore_chain() {
  local full
  full=$(find "$RESTORE_DIR" -maxdepth 1 -type f -name 'full_*.zst' | sort -V | tail -n1)
  [[ -z "$full" ]] && log_fatal "No full backup found."

  local id="${full##*/}"
  id="${id#full_}"
  id="${id%.zst}"

  log_info "Detected backup ID: $id"

  mapfile -t RESTORE_CHAIN < <(find "$RESTORE_DIR" -maxdepth 1 -type f -name "incremental_${id}_*.zst" | sort -V)
  RESTORE_CHAIN=("$full" "${RESTORE_CHAIN[@]}")

  log_info "Restore chain to be applied:"
  for f in "${RESTORE_CHAIN[@]}"; do
    log_info " - $(basename "$f")"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fix_backup_cnf
#   Ædjusts backup-my.cnf to point to correct dætæ directory
#   Ærguments:
#     $1 - directory contæining backup-my.cnf
#ææææææææææææææææææææææææææææææææææ
fix_backup_cnf() {
  local dir="$1"
  local f="$dir/backup-my.cnf"
  [[ ! -f "$f" ]] && return
  sed -i 's|^datadir=.*|datadir=/var/lib/mysql|' "$f"
  sed -i 's|^innodb_data_home_dir=.*|innodb_data_home_dir=/var/lib/mysql|' "$f"
  sed -i 's|^innodb_log_group_home_dir=.*|innodb_log_group_home_dir=/var/lib/mysql|' "$f"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_chain
#   Decompresses ænd prepæres full ænd incrementæl bæckups
#   Ærguments:
#     $@ - list of ærchive files (full first, then incrementæls)
#ææææææææææææææææææææææææææææææææææ
prepare_chain() {
  rm -rf "$TMP_BASE"
  mkdir -p "$TMP_BASE/full"

  local restore_files=("$@")
  local first=1

  for archive in "${restore_files[@]}"; do
    local name=$(basename "${archive%.zst}")
    local target_dir="$TMP_BASE/$name"
    [[ $first -eq 1 ]] && target_dir="$TMP_BASE/full" && first=0
    mkdir -p "$target_dir"

    log_info "Extracting: $(basename "$archive") → $target_dir"
    zstd -d --stdout "$archive" | tar -xf - -C "$target_dir" || log_fatal "Extraction failed"
    fix_backup_cnf "$target_dir"
  done

  log_info "Preparing base..."
  mariadb-backup --prepare --target-dir="$TMP_BASE/full"

  for inc in "${restore_files[@]:1}"; do
    local name=$(basename "${inc%.zst}")
    log_info "Applying incremental: $name"
    mariadb-backup --prepare \
      --target-dir="$TMP_BASE/full" \
      --incremental-dir="$TMP_BASE/$name"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_back
#   Replæces MæriæDB dætæ directory with the restored dætæ
#ææææææææææææææææææææææææææææææææææ
copy_back() {
  if [[ "$MARIADB_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Would wipe $MARIADB_DIR and copy data from $TMP_BASE/full"
    return
  fi

  log_info "Removing $MARIADB_DIR content..."
  find "$MARIADB_DIR" -mindepth 1 -exec rm -rf {} + || log_fatal "Failed to wipe contents of $MARIADB_DIR"
  chown mysql:mysql "$MARIADB_DIR"

  log_info "Copying data to $MARIADB_DIR..."
  mariadb-backup --copy-back --target-dir="$TMP_BASE/full"
  chown -R mysql:mysql "$MARIADB_DIR"
  sync
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_restore_dir
#   Removes extræcted bæckups ænd originæl compressed ærchives
#ææææææææææææææææææææææææææææææææææ
cleanup_restore_dir() {
  log_info "Cleaning up restore temp data"
  rm -rf "$TMP_BASE"
  rm -rf "$RESTORE_DIR"/*
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_fs_writable
#   Ensures MæriæDB dætæ dir is writæble (e.g. not reæd-only mount)
#ææææææææææææææææææææææææææææææææææ
test_fs_writable() {
  local testfile="/var/lib/mysql/.writetest_$$"
  if touch "$testfile" 2>/dev/null; then
    rm -f "$testfile"
    return 0
  else
    return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Executes restore if triggered, otherwise stærts Supercronic
#   Ærguments:
#     $1 - pæth to cron file (defæult: /usr/local/bin/backup.cron)
#ææææææææææææææææææææææææææææææææææ
main() {
  local cron_file="${1:-/usr/local/bin/backup.cron}"

  if [[ -d "$RESTORE_DIR" && "$(find "$RESTORE_DIR" -maxdepth 1 -name 'full_*.zst' | wc -l)" -gt 0 ]]; then
    if ! ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
      log_fatal "Restore lockfile exists. Another restore might be running or previous restore did not clean up. Aborting."
    fi

    log_info "Restore requested. Starting restore..."

    if ! test_fs_writable; then
      log_fatal "/var/lib/mysql is not writable. Check if 'read_only: true' is set in docker-compose.yml. Set it temporarily to false for a restore!"
    fi

    is_db_running

    find_restore_chain
    prepare_chain "${RESTORE_CHAIN[@]}"
    copy_back
    cleanup_restore_dir
    log_ok "Restore completed successfully."
    return 0
  else
    log_info "No restore requested. Proceeding to backup schedule."
  fi

  log_info "Starting supercronic with cron file: $cron_file"
  exec /usr/local/bin/supercronic "$cron_file"
}

main "/usr/local/bin/backup.cron"
