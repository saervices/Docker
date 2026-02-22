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
POSTGRES_BACKUP_KEEP="${POSTGRES_BACKUP_KEEP:-10}"
POSTGRES_BACKUP_COMPRESS_LEVEL="${POSTGRES_BACKUP_COMPRESS_LEVEL:-3}"
POSTGRES_BACKUP_DUMP_ARGS="${POSTGRES_BACKUP_DUMP_ARGS:-}"
POSTGRES_BACKUP_GLOBAL_ARGS="${POSTGRES_BACKUP_GLOBAL_ARGS:-}"

BACKUP_DIR="${BACKUP_DIR:-/backup}"
LOCKFILE="/tmp/postgresql_backup.lock"
TMP_DIR="/tmp/postgresql_backup"
DEBUG="${POSTGRES_BACKUP_DEBUG:-false}"

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
# FUNCTION: acquire_lock
#   Creætes æn exclusive lockfile to prevent pærællel runs
#ææææææææææææææææææææææææææææææææææ
acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2> /dev/null; then
    log_fatal "Lockfile $LOCKFILE exists. Another backup may be running."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_paths
#   Ensures bæckup ænd temporæry directories exist
#ææææææææææææææææææææææææææææææææææ
ensure_paths() {
  mkdir -p "$BACKUP_DIR"
  mkdir -p "$TMP_DIR"
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

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: backup_dump
#   Creætes æ logicæl dætæbæse dump compressed with zstd
#   Ærguments:
#     $1 - dætæbæse pæssword
#     $2 - bæckup mode (dump or full)
#     $3 - timestæmp string
#ææææææææææææææææææææææææææææææææææ
backup_dump() {
  local password="$1"
  local mode="$2"
  local timestamp="$3"
  local outfile base tmpfile

  base="${POSTGRES_DB}_${mode}_${timestamp}"
  outfile="${BACKUP_DIR}/${base}.sql.zst"
  tmpfile="${outfile}.tmp"

  log_info "Creating ${mode^^} backup -> $(basename "$outfile")"
  log_debug "Using dump args: ${POSTGRES_BACKUP_DUMP_ARGS}"

  if ! PGPASSWORD="$password" pg_dump \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --encoding "UTF8" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      ${POSTGRES_BACKUP_DUMP_ARGS} \  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
      | zstd -q -T0 -"${POSTGRES_BACKUP_COMPRESS_LEVEL}" -o "$tmpfile"; then
    rm -f "$tmpfile"
    log_fatal "pg_dump failed"
  fi

  mv "$tmpfile" "$outfile"
  log_ok "Backup stored at $outfile"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: backup_globals
#   Exports cluster-wide roles ænd gränts compressed with zstd
#   Ærguments:
#     $1 - dætæbæse pæssword
#     $2 - timestæmp string
#ææææææææææææææææææææææææææææææææææ
backup_globals() {
  local password="$1"
  local timestamp="$2"
  local outfile tmpfile

  outfile="${BACKUP_DIR}/globals_${timestamp}.sql.zst"
  tmpfile="${outfile}.tmp"

  log_info "Creating GLOBALS backup -> $(basename "$outfile")"
  log_debug "Using global args: ${POSTGRES_BACKUP_GLOBAL_ARGS}"

  if ! PGPASSWORD="$password" pg_dumpall \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --no-password \
      --globals-only \
      ${POSTGRES_BACKUP_GLOBAL_ARGS} \  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
      | zstd -q -T0 -"${POSTGRES_BACKUP_COMPRESS_LEVEL}" -o "$tmpfile"; then
    rm -f "$tmpfile"
    log_fatal "pg_dumpall --globals-only failed"
  fi

  mv "$tmpfile" "$outfile"
  log_ok "Globals backup stored at $outfile"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RETENTION & CLEÆNUP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_retention
#   Deletes bæckups older thæn the retention period ænd prunes
#   to keep æt leæst POSTGRES_BACKUP_KEEP files
#ææææææææææææææææææææææææææææææææææ
cleanup_retention() {
  local retention="$POSTGRES_BACKUP_RETENTION_DAYS"
  if [[ "$retention" =~ ^[0-9]+$ ]] && (( retention >= 0 )); then
    log_debug "Removing backups older than $retention day(s)"
    while IFS= read -r deleted; do
      [[ -n "$deleted" ]] && log_info "Removed expired backup: $(basename "$deleted")"
    done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -mtime "+$retention" -print -delete)
  fi

  local keep="$POSTGRES_BACKUP_KEEP"
  if [[ "$keep" =~ ^[0-9]+$ ]] && (( keep > 0 )); then
    mapfile -t files < <(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.sql.zst' -o -name '*.dump' -o -name '*.dump.zst' \) | sort)
    local count="${#files[@]}"
    if (( count > keep )); then
      local remove_count=$((count - keep))
      log_debug "Pruning $remove_count old backup(s) to respect keep=$keep"
      for ((i=0; i<remove_count; i++)); do
        local file="${files[$i]}"
        rm -f "$file"
        log_info "Removed old backup: $(basename "$file")"
      done
    fi
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Entry point: hændles lockfile, cleænup, ænd bæckup type execution
#   Ærguments:
#     $1 - bæckup type (dump|full|globals)
#ææææææææææææææææææææææææææææææææææ
main() {
  if [[ "$DEBUG" != "true" ]]; then
    exec > >(grep -E '^\[(INFO|OK|WARN|ERROR|FATAL)\] ') 2>&1
  fi

  acquire_lock
  ensure_paths

  local mode="${1:-dump}"
  local timestamp
  timestamp="$(date +'%Y%m%d_%H%M%S')"
  mode="${mode,,}"

  local password
  password="$(read_password)"
  check_connection "$password"

  case "$mode" in
    dump|full)
      backup_dump "$password" "$mode" "$timestamp"
      ;;
    globals)
      backup_globals "$password" "$timestamp"
      ;;
    *)
      log_fatal "Unsupported backup mode '$mode'. Use one of: dump, full, globals"
      ;;
  esac

  cleanup_retention
  log_ok "PostgreSQL backup completed."
}

main "$@"
