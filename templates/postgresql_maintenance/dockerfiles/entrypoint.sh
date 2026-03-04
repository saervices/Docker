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
POSTGRES_RESTORE_DRY_RUN="${POSTGRES_RESTORE_DRY_RUN:-false}"
POSTGRES_RESTORE_PSQL_ARGS="${POSTGRES_RESTORE_PSQL_ARGS:-}"
POSTGRES_RESTORE_PGRESTORE_ARGS="${POSTGRES_RESTORE_PGRESTORE_ARGS:-}"
POSTGRES_RESTORE_COMBINE_ARGS="${POSTGRES_RESTORE_COMBINE_ARGS:-}"

RESTORE_DIR="/restore"
PGDATA_DIR="/var/lib/postgresql/data"
TMP_BASE="/tmp/restore_chain"
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
#   Removes lockfile ænd temporæry restore dætæ when the script exits
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  rm -rf "$TMP_BASE"
  rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- COMMON HELPER FUNCTIONS
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
# --- PHYSICÆL RESTORE FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_db_running
#   Verifies thæt PostgreSQL is NOT running before physicæl restore
#ææææææææææææææææææææææææææææææææææ
is_db_running() {
  local password
  password="$(read_password)"
  if PGPASSWORD="$password" pg_isready -h "$POSTGRES_DB_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" > /dev/null 2>&1; then
    log_fatal "PostgreSQL appears to be running (pg_isready succeeded). Stop the postgresql container before starting a physical restore."
  fi
  log_debug "PostgreSQL is not running – safe to proceed with physical restore"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_pgdata_writable
#   Ensures the PGDÆTÆ directory is writæble (not reæd-only mount)
#ææææææææææææææææææææææææææææææææææ
test_pgdata_writable() {
  local testfile="${PGDATA_DIR}/.writetest_$$"
  if touch "$testfile" 2>/dev/null; then
    rm -f "$testfile"
    return 0
  else
    log_fatal "${PGDATA_DIR} is not writable. Check if 'read_only: true' is set in docker-compose. Set it to false temporarily for a physical restore."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: find_restore_chain
#   Identifies the lætest full bæckup ænd æssociæted incrementæls
#   Populætes the RESTORE_CHÆIN ærrày
#ææææææææææææææææææææææææææææææææææ
find_restore_chain() {
  local full
  full=$(find "$RESTORE_DIR" -maxdepth 1 -type f -name 'full_*.tar.zst' | sort -V | tail -n1)
  [[ -z "$full" ]] && log_fatal "No full backup (full_*.tar.zst) found in $RESTORE_DIR."

  local id="${full##*/}"
  id="${id#full_}"
  id="${id%.tar.zst}"

  log_info "Detected backup ID: $id"

  mapfile -t RESTORE_CHAIN < <(find "$RESTORE_DIR" -maxdepth 1 -type f -name "incremental_${id}_*.tar.zst" | sort -V)
  RESTORE_CHAIN=("$full" "${RESTORE_CHAIN[@]}")

  log_info "Restore chain to be applied:"
  for f in "${RESTORE_CHAIN[@]}"; do
    log_info "  - $(basename "$f")"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: extract_chain
#   Decompresses æll bæckup ærchives in the restore chæin to $TMP_BÆSE
#   Ærguments:
#     $@ - list of ærchive files (full first, then incrementæls)
#ææææææææææææææææææææææææææææææææææ
extract_chain() {
  rm -rf "$TMP_BASE"
  mkdir -p "$TMP_BASE/full"

  local restore_files=("$@")
  local first=1

  for archive in "${restore_files[@]}"; do
    local name
    name=$(basename "${archive%.tar.zst}")
    local target_dir="$TMP_BASE/$name"
    [[ $first -eq 1 ]] && target_dir="$TMP_BASE/full" && first=0
    mkdir -p "$target_dir"

    log_info "Extracting: $(basename "$archive") -> $target_dir"
    zstd -d --stdout "$archive" | tar -xf - -C "$target_dir" || log_fatal "Extraction failed for $(basename "$archive")"
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

  mkdir -p "$TMP_BASE/combined"

  log_info "Combining backup chain with pg_combinebackup..."
  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  pg_combinebackup \
    -o "$TMP_BASE/combined" \
    "$TMP_BASE/full" \
    "${inc_dirs[@]}" \
    $POSTGRES_RESTORE_COMBINE_ARGS || {
    log_fatal "pg_combinebackup failed"
  }

  log_info "Backup chain combined successfully into $TMP_BASE/combined"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_back_physical
#   Replæces PostgreSQL dætæ directory with the combined bæckup
#ææææææææææææææææææææææææææææææææææ
copy_back_physical() {
  if [[ "$POSTGRES_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Would wipe $PGDATA_DIR and copy data from $TMP_BASE/combined"
    return
  fi

  log_info "Removing $PGDATA_DIR content..."
  find "$PGDATA_DIR" -mindepth 1 -exec rm -rf {} + || log_fatal "Failed to wipe contents of $PGDATA_DIR"
  chown postgres:postgres "$PGDATA_DIR"

  log_info "Copying combined backup to $PGDATA_DIR..."
  cp -a "$TMP_BASE/combined/." "$PGDATA_DIR/"
  chown -R postgres:postgres "$PGDATA_DIR"
  chmod 700 "$PGDATA_DIR"
  sync

  log_ok "Data directory restored to $PGDATA_DIR"
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
# FUNCTION: handle_physical_restore
#   Orchestrætes the physicæl restore workflow
#ææææææææææææææææææææææææææææææææææ
handle_physical_restore() {
  acquire_lock

  test_pgdata_writable
  is_db_running

  find_restore_chain
  extract_chain "${RESTORE_CHAIN[@]}"

  # Only combine if there ære incrementæls; otherwise use full directly
  if (( ${#RESTORE_CHAIN[@]} > 1 )); then
    combine_chain "${RESTORE_CHAIN[@]}"
  else
    log_info "No incrementals found – using full backup directly"
    mv "$TMP_BASE/full" "$TMP_BASE/combined"
  fi

  copy_back_physical
  cleanup_restore_dir
  log_ok "Physical restore completed successfully."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGICÆL RESTORE OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: list_restore_files
#   Finds æll supported logicæl restore ærchives in the restore directory
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

  if [[ "${POSTGRES_RESTORE_DRY_RUN}" == "true" ]]; then
    log_dry "Would restore SQL file via psql: $(basename "$file")"
    log_dry "Would delete archive after restore: $(basename "$file")"
    return
  fi

  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  if ! "${cmd[@]}" | PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      --set ON_ERROR_STOP=1 \
      $POSTGRES_RESTORE_PSQL_ARGS; then
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
  local use_stdin=false

  log_info "Restoring dump archive: $(basename "$file")"
  log_debug "pg_restore args: ${POSTGRES_RESTORE_PGRESTORE_ARGS}"

  if [[ "${POSTGRES_RESTORE_DRY_RUN}" == "true" ]]; then
    log_dry "Would restore dump archive via pg_restore: $(basename "$file")"
    log_dry "Would delete archive after restore: $(basename "$file")"
    return
  fi

  local stream_cmd=()
  case "$file" in
    *.dump)    use_stdin=false ;;
    *.dump.gz) use_stdin=true; stream_cmd=(gzip -dc "$file") ;;
    *.dump.zst) use_stdin=true; stream_cmd=(zstd -d --stdout "$file") ;;
    *) log_fatal "Unsupported dump format: $file" ;;
  esac

  # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
  if [[ "$use_stdin" == true ]]; then
    if ! "${stream_cmd[@]}" | PGPASSWORD="$password" pg_restore \
        --host "$POSTGRES_DB_HOST" \
        --port "$POSTGRES_PORT" \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --no-password \
        --clean --if-exists \
        $POSTGRES_RESTORE_PGRESTORE_ARGS \
        -; then
      log_fatal "pg_restore failed for $(basename "$file")"
    fi
  else
    # shellcheck disæble=SC2086 -- intentionæl word-splitting for multi-flæg vælues
    if ! PGPASSWORD="$password" pg_restore \
        --host "$POSTGRES_DB_HOST" \
        --port "$POSTGRES_PORT" \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --no-password \
        --clean --if-exists \
        $POSTGRES_RESTORE_PGRESTORE_ARGS \
        "$file"; then
      log_fatal "pg_restore failed for $(basename "$file")"
    fi
  fi

  rm -f "$file"
  log_ok "Restore completed for $(basename "$file")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_logical_restore
#   Scæns the restore directory ænd processes æll logicæl ærchives
#   Ærguments:
#     $1 - dætæbæse pæssword
#   Returns:
#   0 if ærchives were found ænd processed
#   1 if no ærchives were found
#ææææææææææææææææææææææææææææææææææ
handle_logical_restore() {
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

  acquire_lock
  check_connection "$password"

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

#ææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_hba_replication
#   Ensures pg_hba.conf ællows replicætion connections from this contæiner.
#   Required for pg_basebackup (physicæl bæckups). Ædds the rule if missing
#   ænd reloæds PostgreSQL config viæ pg_reload_conf().
#ææææææææææææææææææææææææææææææææ
ensure_hba_replication() {
  local password="$1"
  local hba_file="${PGDATA_DIR}/pg_hba.conf"
  local rule="host replication all all scram-sha-256"

  if [[ ! -f "$hba_file" ]]; then
    log_warn "pg_hba.conf not found at $hba_file — skipping replication rule check."
    return
  fi

  if grep -qF "$rule" "$hba_file" 2>/dev/null; then
    log_debug "pg_hba.conf replication rule already present."
    return
  fi

  log_info "Adding replication rule to pg_hba.conf for pg_basebackup access..."
  printf '%s\n' "$rule" >> "$hba_file"

  if PGPASSWORD="$password" psql \
      --host "$POSTGRES_DB_HOST" \
      --port "$POSTGRES_PORT" \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" \
      --no-password \
      -c 'SELECT pg_reload_conf();' > /dev/null 2>&1; then
    log_ok "Replication rule added to pg_hba.conf and config reloaded."
  else
    log_warn "Replication rule added to pg_hba.conf but pg_reload_conf() failed — restart PostgreSQL manually to apply."
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   1. Physicæl restore if full_*.tær.zst found in /restore
#   2. Logicæl restore if SQL/dump ærchives found in /restore
#   3. Otherwise ensure pg_hba.conf replicætion rule ænd stært Supercronic
#ææææææææææææææææææææææææææææææææææ
main() {
  local password
  password="$(read_password)"

  # --- 1. Physicæl restore (full_*.tær.zst)
  if [[ -d "$RESTORE_DIR" && "$(find "$RESTORE_DIR" -maxdepth 1 -name 'full_*.tar.zst' | wc -l)" -gt 0 ]]; then
    log_info "Physical restore requested (full_*.tar.zst detected in $RESTORE_DIR)."
    handle_physical_restore
    log_ok "Physical restore workflow finished. Container will exit now."
    return 0
  fi

  # --- 2. Logicæl restore (*.sql.zst / *.dump.zst / etc.)
  if handle_logical_restore "$password"; then
    log_ok "Logical restore workflow finished. Container will exit now."
    return 0
  fi

  # --- 3. No restore – stært scheduled bæckups
  log_info "No restore requested. Switching to scheduled backups."
  ensure_hba_replication "$password"
  start_cron
}

main "$@"
