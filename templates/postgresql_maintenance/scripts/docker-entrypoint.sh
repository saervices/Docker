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
POSTGRES_RESTORE_STRICT="${POSTGRES_RESTORE_STRICT:-false}"
POSTGRES_RESTORE_DEBUG="${POSTGRES_RESTORE_DEBUG:-false}"
POSTGRES_RESTORE_PSQL_ARGS="${POSTGRES_RESTORE_PSQL_ARGS:-}"
POSTGRES_RESTORE_PGRESTORE_ARGS="${POSTGRES_RESTORE_PGRESTORE_ARGS:-}"

RESTORE_DIR="/restore"
CRON_FILE="/usr/local/bin/backup.cron"
LOCKFILE="/tmp/postgresql_restore.lock"
DEBUG="${POSTGRES_RESTORE_DEBUG}"

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
#   Removes lockfile when the script exits
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RESTORE HELPER FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_lock
#   Creætes æn exclusive lockfile to prevent pærællel runs
#ææææææææææææææææææææææææææææææææææ
acquire_lock() {
  if ! ( set -o noclobber; echo "$$" > "$LOCKFILE" ) 2> /dev/null; then
    log_fatal "Another restore seems in progress (lockfile $LOCKFILE exists)."
  fi
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
  log_debug "Validating connection to ${POSTGRES_DB_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
  if ! PGPASSWORD="$password" pg_isready -h "$POSTGRES_DB_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
    log_fatal "Database ${POSTGRES_DB} on ${POSTGRES_DB_HOST}:${POSTGRES_PORT} is not reachable"
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RESTORE OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: list_restore_files
#   Finds æll supported restore ærchives in the restore directory
#ææææææææææææææææææææææææææææææææææ
list_restore_files() {
  find "$RESTORE_DIR" -maxdepth 1 -type f \( \
    -name '*.sql' -o \
    -name '*.sql.gz' -o \
    -name '*.sql.zst' -o \
    -name '*.dump' -o \
    -name '*.dump.gz' -o \
    -name '*.dump.zst' \
  \) -print0 | sort -z
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_sql_stream
#   Restores æ SQL file (plæin, gzip, or zstd) viæ psql
#   Ærguments:
#     $1 - pæth to the SQL ærchive
#     $2 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
restore_sql_stream() {
  local file="$1"
  local password="$2"
  local cmd=()

  case "$file" in
    *.sql)     cmd=(cat "$file") ;;
    *.sql.gz)  cmd=(gzip -dc "$file") ;;
    *.sql.zst) cmd=(zstd -d --stdout "$file") ;;
    *)         log_fatal "Unsupported SQL file format: $file" ;;
  esac

  log_info "Restoring SQL file: $(basename "$file")"
  log_debug "psql args: ${POSTGRES_RESTORE_PSQL_ARGS}"

  if ! "${cmd[@]}" | PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      --set ON_ERROR_STOP=1 \
      ${POSTGRES_RESTORE_PSQL_ARGS}; then
    log_fatal "psql restore failed for $(basename "$file")"
  fi

  rm -f "$file"
  log_ok "Restore completed for $(basename "$file")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_dump_archive
#   Restores æ dump ærchive (plæin, gzip, or zstd) viæ pg_restore
#   Ærguments:
#     $1 - pæth to the dump ærchive
#     $2 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
restore_dump_archive() {
  local file="$1"
  local password="$2"
  local cmd=()
  local use_stdin=false

  case "$file" in
    *.dump)
      cmd=(pg_restore \
        --host "$POSTGRES_DB_HOST" \
        --port "$POSTGRES_PORT" \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --no-password \
        --clean --if-exists \
        ${POSTGRES_RESTORE_PGRESTORE_ARGS} \
        "$file")
      ;;
    *.dump.gz)
      cmd=(pg_restore \
        --host "$POSTGRES_DB_HOST" \
        --port "$POSTGRES_PORT" \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --no-password \
        --clean --if-exists \
        ${POSTGRES_RESTORE_PGRESTORE_ARGS} \
        -)
      use_stdin=true
      ;;
    *.dump.zst)
      cmd=(pg_restore \
        --host "$POSTGRES_DB_HOST" \
        --port "$POSTGRES_PORT" \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --no-password \
        --clean --if-exists \
        ${POSTGRES_RESTORE_PGRESTORE_ARGS} \
        -)
      use_stdin=true
      ;;
    *)
      log_fatal "Unsupported dump format: $file"
      ;;
  esac

  log_info "Restoring dump archive: $(basename "$file")"
  log_debug "pg_restore args: ${POSTGRES_RESTORE_PGRESTORE_ARGS}"

  if [[ "$use_stdin" == true ]]; then
    local stream_cmd=()
    case "$file" in
      *.dump.gz)  stream_cmd=(gzip -dc "$file") ;;
      *.dump.zst) stream_cmd=(zstd -d --stdout "$file") ;;
    esac
    if ! "${stream_cmd[@]}" | PGPASSWORD="$password" "${cmd[@]}"; then
      log_fatal "pg_restore failed for $(basename "$file")"
    fi
  else
    if ! PGPASSWORD="$password" "${cmd[@]}"; then
      log_fatal "pg_restore failed for $(basename "$file")"
    fi
  fi

  rm -f "$file"
  log_ok "Restore completed for $(basename "$file")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_restore
#   Scæns the restore directory ænd processes æll found ærchives
#   Ærguments:
#     $1 - dætæbæse pæssword
#ææææææææææææææææææææææææææææææææææ
handle_restore() {
  local password="$1"
  local files=()

  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(list_restore_files)

  local count="${#files[@]}"
  if (( count == 0 )); then
    log_info "No restore archives detected in $RESTORE_DIR."
    return 1
  fi

  log_info "Found $count restore archive(s) in $RESTORE_DIR"
  if [[ "$POSTGRES_RESTORE_STRICT" == "true" ]] && (( count > 1 )); then
    log_fatal "Strict restore mode is enabled but multiple files were found. Please leave only one archive inside $RESTORE_DIR."
  fi

  for file in "${files[@]}"; do
    case "$file" in
      *.sql|*.sql.gz|*.sql.zst)
        restore_sql_stream "$file" "$password"
        ;;
      *.dump|*.dump.gz|*.dump.zst)
        restore_dump_archive "$file" "$password"
        ;;
      *)
        log_fatal "Unsupported restore file: $file"
        ;;
    esac
  done

  return 0
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
#   Executes restore if triggered, otherwise stærts Supercronic
#ææææææææææææææææææææææææææææææææææ
main() {
  acquire_lock
  local password
  password="$(read_password)"
  check_connection "$password"

  if handle_restore "$password"; then
    log_ok "Restore workflow finished. Container will exit now."
    return 0
  fi

  log_info "No restore requested. Switching to scheduled backups."
  start_cron
}

main "$@"
