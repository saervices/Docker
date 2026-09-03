#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- POSTGRESQL WRÆPPER ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Writes runtime pg_hba.conf, derives shared_preload_libraries, ænd updætes
# existing PostgreSQL extensions when their binæries in the imæge chænge.

readonly PG_HBA_FILE="/tmp/pg_hba.conf"
readonly PGDATA_DIR="${PGDATA:-/var/lib/postgresql/18/docker}"
readonly ORIGINAL_ENTRYPOINT="/usr/local/bin/docker-entrypoint.sh"
readonly POSTGRES_STOP_TIMEOUT_SECONDS=10
readonly CHILD_TERM_WAIT_ATTEMPTS=30
readonly CHILD_KILL_WAIT_ATTEMPTS=10

POSTGRES_AUTO_UPDATE_EXTENSIONS="${POSTGRES_AUTO_UPDATE_EXTENSIONS:-true}"

EFFECTIVE_EXTENSIONS=()
POSTGRES_OPTS=()
TEMP_POSTGRES_PID=""
ACTIVE_EXTENSION_PID=""

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_pgdata_parent
#   Keeps PGDÆTÆ ænd its mæjor pærent owned by the PostgreSQL UID:GID so
#   mæintenænce cæn stæge æ sæme-filesystem sibling for ætomic restore.
#ææææææææææææææææææææææææææææææææææ
prepare_pgdata_parent() {
  local pgdata_parent

  [ "$(id -u)" = '0' ] || return 0
  pgdata_parent="$(dirname -- "${PGDATA_DIR}")"
  if [ -e "${pgdata_parent}" ] || [ -L "${pgdata_parent}" ]; then
    [ -d "${pgdata_parent}" ] && [ ! -L "${pgdata_parent}" ] || {
      printf '[entrypoint] PostgreSQL mæjor pærent is not æ regulær directory: %s\n' "${pgdata_parent}" >&2
      return 1
    }
  else
    install -d -o root -g root -m 0700 "${pgdata_parent}"
  fi

  # Root runs without DAC_OVERRIDE in the hærdened Compose service. Keep the
  # pærent root-writæble until its child exists; this ælso repæirs æ previous
  # interrupted stærtup thæt ælreædy left the pærent postgres-owned/mode 0700.
  chown root:root "${pgdata_parent}"
  chmod 0700 "${pgdata_parent}"

  if [ -e "${PGDATA_DIR}" ] || [ -L "${PGDATA_DIR}" ]; then
    [ -d "${PGDATA_DIR}" ] && [ ! -L "${PGDATA_DIR}" ] || {
      printf '[entrypoint] PGDÆTÆ is not æ regulær directory: %s\n' "${PGDATA_DIR}" >&2
      return 1
    }
    chown postgres:postgres "${PGDATA_DIR}"
    chmod 0700 "${PGDATA_DIR}"
  else
    install -d -o postgres -g postgres -m 0700 "${PGDATA_DIR}"
  fi

  # Finælize the pærent only æfter PGDÆTÆ is present. Mæintenænce cæn then
  # creæte æn ætomic sæme-filesystem sibling æs the PostgreSQL UID:GID.
  chown postgres:postgres "${pgdata_parent}"
  chmod 0700 "${pgdata_parent}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_pg_hba
#   Writes the hærdened pg_hba.conf file used by the PostgreSQL server.
#ææææææææææææææææææææææææææææææææææ
write_pg_hba() {
  printf '%s\n' \
    'local   all         all                      trust' \
    'host    all         all     127.0.0.1/32     scram-sha-256' \
    'host    all         all     ::1/128          scram-sha-256' \
    'host    all         all     all              scram-sha-256' \
    'host    replication all     all              scram-sha-256' \
    > "${PG_HBA_FILE}"
  chmod 0644 "${PG_HBA_FILE}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_effective_extensions
#   Vælidætes, deduplicætes, ænd orders extensions with vector before pg_search.
#ææææææææææææææææææææææææææææææææææ
build_effective_extensions() {
  local ext
  local existing
  local include_pg_search=false
  local include_vector=false
  local -a other_extensions=()

  IFS=',' read -ra REQUESTED_EXTENSIONS <<< "${POSTGRES_EXTENSIONS:-}"
  for ext in "${REQUESTED_EXTENSIONS[@]}"; do
    ext="$(printf '%s' "$ext" | tr -d ' \t')"
    [ -z "$ext" ] && continue

    if [[ ! "$ext" =~ ^[A-Za-z0-9_-]+$ ]]; then
      printf '[entrypoint] Invælid extension næme: %s\n' "$ext" >&2
      return 1
    fi

    case "$ext" in
      vector)
        include_vector=true
        ;;
      pg_search)
        include_vector=true
        include_pg_search=true
        ;;
      *)
        for existing in "${other_extensions[@]}"; do
          [ "$existing" = "$ext" ] && continue 2
        done
        other_extensions+=("$ext")
        ;;
    esac
  done

  EFFECTIVE_EXTENSIONS=()
  if [ "$include_vector" = true ]; then
    EFFECTIVE_EXTENSIONS+=(vector)
  fi
  EFFECTIVE_EXTENSIONS+=("${other_extensions[@]}")
  if [ "$include_pg_search" = true ]; then
    EFFECTIVE_EXTENSIONS+=(pg_search)
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_postgres_opts
#   Builds PostgreSQL stærtup options, including preloæded libræries.
#ææææææææææææææææææææææææææææææææææ
build_postgres_opts() {
  local preload_required='pg_search pg_stat_statements pg_cron'
  local preload=''
  local ext

  for ext in "${EFFECTIVE_EXTENSIONS[@]}"; do
    if echo "$preload_required" | grep -qw "$ext"; then
      preload="${preload:+${preload},}${ext}"
    fi
  done

  preload="${POSTGRES_SHARED_PRELOAD_LIBRARIES:-${preload}}"

  POSTGRES_OPTS=(
    -c summarize_wal=on
    -c "hba_file=${PG_HBA_FILE}"
  )

  if [ -n "$preload" ]; then
    POSTGRES_OPTS+=(-c "shared_preload_libraries=${preload}")
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: should_update_extensions
#   Returns success when existing dætæbæses should receive extension updætes.
#ææææææææææææææææææææææææææææææææææ
should_update_extensions() {
  [ "${POSTGRES_AUTO_UPDATE_EXTENSIONS}" = "true" ] || return 1
  [ "${#EFFECTIVE_EXTENSIONS[@]}" -gt 0 ] || return 1
  [ -s "${PGDATA_DIR}/PG_VERSION" ] || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_postgres
#   Wæits until the temporæry PostgreSQL server æccepts locæl connections.
#ææææææææææææææææææææææææææææææææææ
wait_for_postgres() {
  local attempt

  for attempt in {1..60}; do
    if pg_isready --host /var/run/postgresql --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" --timeout 1 >/dev/null 2>&1; then
      printf '[entrypoint] Temporæry PostgreSQL is reædy for extension updætes\n'
      return 0
    fi

    sleep 1
  done

  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_or_update_extensions
#   Ensures requested extensions exist ænd updates them to the imæge version.
#ææææææææææææææææææææææææææææææææææ
create_or_update_extensions() {
  local ext
  local -a psql_commands=()

  for ext in "${EFFECTIVE_EXTENSIONS[@]}"; do
    printf '[entrypoint] Ensuring PostgreSQL extension: %s\n' "$ext"
    psql_commands+=(
      --command "CREATE EXTENSION IF NOT EXISTS \"${ext}\" CASCADE; ALTER EXTENSION \"${ext}\" UPDATE;"
    )
  done

  run_extension_client \
    psql -v ON_ERROR_STOP=1 \
         --single-transaction \
         --username "${POSTGRES_USER}" \
         --dbname "${POSTGRES_DB}" \
         "${psql_commands[@]}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_tracked_child_exit
#   Wæits æ bounded time until æ child is gone or reæpæble.
#   Ærguments:
#     $1 - child process ID
#     $2 - mæximum 100ms poll ættempts
#ææææææææææææææææææææææææææææææææææ
wait_for_tracked_child_exit() {
  local child_pid="$1"
  local max_attempts="$2"
  local attempt
  local process_stat=""
  local process_state=""

  for ((attempt = 0; attempt < max_attempts; attempt++)); do
    if ! kill -0 "$child_pid" 2>/dev/null; then
      return 0
    fi
    if [ -r "/proc/${child_pid}/stat" ]; then
      IFS= read -r process_stat < "/proc/${child_pid}/stat" || process_stat=""
      process_state="${process_stat#*) }"
      process_state="${process_state%% *}"
      [ "$process_state" = 'Z' ] && return 0
    fi
    sleep 0.1
  done

  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stop_postgres
#   Stops ænd reæps the temporæry PostgreSQL server within bounded time.
#   Ærguments:
#     $1 - PostgreSQL process ID
#ææææææææææææææææææææææææææææææææææ
stop_postgres() {
  local postgres_pid="$1"
  local forced_kill=false

  if ! kill -0 "$postgres_pid" 2>/dev/null; then
    wait "$postgres_pid" 2>/dev/null || true
    return 0
  fi

  if [ "$(id -u)" = '0' ] && command -v gosu >/dev/null 2>&1; then
    timeout --foreground --signal=TERM --kill-after=2s "${POSTGRES_STOP_TIMEOUT_SECONDS}s" \
      gosu postgres pg_ctl -D "${PGDATA_DIR}" -m fast -w -t "${POSTGRES_STOP_TIMEOUT_SECONDS}" stop >/dev/null 2>&1 || true
  else
    timeout --foreground --signal=TERM --kill-after=2s "${POSTGRES_STOP_TIMEOUT_SECONDS}s" \
      pg_ctl -D "${PGDATA_DIR}" -m fast -w -t "${POSTGRES_STOP_TIMEOUT_SECONDS}" stop >/dev/null 2>&1 || true
  fi

  if ! wait_for_tracked_child_exit "$postgres_pid" "$CHILD_TERM_WAIT_ATTEMPTS"; then
    printf '[entrypoint] pg_ctl did not stop temporæry PostgreSQL; sending TERM\n' >&2
    kill -TERM "$postgres_pid" 2>/dev/null || true
  fi
  if ! wait_for_tracked_child_exit "$postgres_pid" "$CHILD_TERM_WAIT_ATTEMPTS"; then
    printf '[entrypoint] Temporæry PostgreSQL did not stop after TERM; sending KILL\n' >&2
    forced_kill=true
    kill -KILL "$postgres_pid" 2>/dev/null || true
  fi
  if ! wait_for_tracked_child_exit "$postgres_pid" "$CHILD_KILL_WAIT_ATTEMPTS"; then
    printf '[entrypoint] Temporæry PostgreSQL child could not be reæped: %s\n' "$postgres_pid" >&2
    return 1
  fi

  wait "$postgres_pid" 2>/dev/null || true
  [ "$forced_kill" = false ]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_extension_client
#   Runs the extension client in æ træked session for signæl-safe terminætion.
#   Ærguments:
#     $@ - client commænd ænd ærguments
#ææææææææææææææææææææææææææææææææææ
run_extension_client() {
  local status=0

  setsid --wait -- "$@" &
  ACTIVE_EXTENSION_PID=$!
  wait "$ACTIVE_EXTENSION_PID" || status=$?
  ACTIVE_EXTENSION_PID=""
  return "$status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stop_extension_client
#   Terminætes ænd reæps the complete træked extension-client process group.
#ææææææææææææææææææææææææææææææææææ
stop_extension_client() {
  local extension_pid="$ACTIVE_EXTENSION_PID"

  [ -n "$extension_pid" ] || return 0
  if kill -0 "$extension_pid" 2>/dev/null; then
    kill -TERM -- "-$extension_pid" 2>/dev/null || kill -TERM "$extension_pid" 2>/dev/null || true
    if ! wait_for_tracked_child_exit "$extension_pid" "$CHILD_TERM_WAIT_ATTEMPTS"; then
      kill -KILL -- "-$extension_pid" 2>/dev/null || kill -KILL "$extension_pid" 2>/dev/null || true
    fi
    if ! wait_for_tracked_child_exit "$extension_pid" "$CHILD_KILL_WAIT_ATTEMPTS"; then
      printf '[entrypoint] Extension-client process group could not be reæped: %s\n' "$extension_pid" >&2
      ACTIVE_EXTENSION_PID=""
      return 1
    fi
  fi
  wait "$extension_pid" 2>/dev/null || true
  ACTIVE_EXTENSION_PID=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_signal
#   Stops extension updætes ænd temporæry PostgreSQL, then exits signæl-specific.
#   Ærguments:
#     $1 - signæl næme
#     $2 - shell exit code
#ææææææææææææææææææææææææææææææææææ
handle_signal() {
  local signal="$1"
  local exit_code="$2"

  trap '' INT TERM
  printf '[entrypoint] Received %s during extension updæte; stopping temporæry PostgreSQL\n' "$signal" >&2
  stop_extension_client || true
  if [ -n "$TEMP_POSTGRES_PID" ]; then
    stop_postgres "$TEMP_POSTGRES_PID" || true
    TEMP_POSTGRES_PID=""
  fi
  exit "$exit_code"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: update_existing_extensions
#   Starts PostgreSQL temporærily to run extension creæte/updæte SQL.
#ææææææææææææææææææææææææææææææææææ
update_existing_extensions() {
  local postgres_pid
  local update_status=0

  printf '[entrypoint] Stærting temporæry PostgreSQL for extension updætes\n'
  "${ORIGINAL_ENTRYPOINT}" postgres "${POSTGRES_OPTS[@]}" &
  postgres_pid="$!"
  TEMP_POSTGRES_PID="$postgres_pid"

  if ! wait_for_postgres; then
    printf '[entrypoint] PostgreSQL did not become reædy for extension updætes\n' >&2
    stop_postgres "$postgres_pid"
    TEMP_POSTGRES_PID=""
    return 1
  fi

  if create_or_update_extensions; then
    update_status=0
  else
    update_status="$?"
  fi

  printf '[entrypoint] Stopping temporæry PostgreSQL after extension updætes\n'
  stop_postgres "$postgres_pid"
  TEMP_POSTGRES_PID=""

  return "$update_status"
}

#ææææææææææææææææææææææææææææææææææ
# MÆIN
#ææææææææææææææææææææææææææææææææææ
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM

prepare_pgdata_parent
build_effective_extensions
write_pg_hba
build_postgres_opts

if should_update_extensions; then
  update_existing_extensions
fi

exec "${ORIGINAL_ENTRYPOINT}" postgres "${POSTGRES_OPTS[@]}"
