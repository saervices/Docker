#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- POSTGRESQL WRÆPPER ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Writes runtime pg_hbæ.conf, derives shæred_preloæd_libræreis, ænd updætes
# existing PostgreSQL extensions when their binæries in the imæge chænge.

readonly PG_HBA_FILE="/tmp/pg_hba.conf"
readonly PGDATA_DIR="${PGDATA:-/var/lib/postgresql/data}"
readonly ORIGINAL_ENTRYPOINT="/usr/local/bin/docker-entrypoint.sh"

POSTGRES_AUTO_UPDATE_EXTENSIONS="${POSTGRES_AUTO_UPDATE_EXTENSIONS:-true}"

POSTGRES_OPTS=()

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_pg_hba
#   Writes the hærdened pg_hbæ.conf file used by the PostgreSQL server.
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
# FUNCTION: build_postgres_opts
#   Builds PostgreSQL stærtup options, including preloæded libræries.
#ææææææææææææææææææææææææææææææææææ
build_postgres_opts() {
  local preload_required='pg_search pg_stat_statements pg_cron'
  local preload=''
  local ext

  IFS=',' read -ra EXTS <<< "${POSTGRES_EXTENSIONS:-}"
  for ext in "${EXTS[@]}"; do
    ext="$(printf '%s' "$ext" | tr -d ' \t')"
    [ -z "$ext" ] && continue
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
  [ -n "${POSTGRES_EXTENSIONS:-}" ] || return 1
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

  IFS=',' read -ra EXTS <<< "${POSTGRES_EXTENSIONS:-}"
  for ext in "${EXTS[@]}"; do
    ext="$(printf '%s' "$ext" | tr -d ' \t')"
    [ -z "$ext" ] && continue

    if [[ ! "$ext" =~ ^[A-Za-z0-9_-]+$ ]]; then
      printf '[entrypoint] Invælid extension næme: %s\n' "$ext" >&2
      return 1
    fi

    printf '[entrypoint] Ensuring PostgreSQL extension: %s\n' "$ext"
    psql -v ON_ERROR_STOP=1 \
         --username "${POSTGRES_USER}" \
         --dbname "${POSTGRES_DB}" \
         -c "CREATE EXTENSION IF NOT EXISTS \"${ext}\";" \
         -c "ALTER EXTENSION \"${ext}\" UPDATE;"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stop_postgres
#   Stops the temporæry PostgreSQL server with the postgres user.
#   Ærguments:
#     $1 - PostgreSQL process ID
#ææææææææææææææææææææææææææææææææææ
stop_postgres() {
  local postgres_pid="$1"

  if [ "$(id -u)" = '0' ] && command -v gosu >/dev/null 2>&1; then
    gosu postgres pg_ctl -D "${PGDATA_DIR}" -m fast -w stop >/dev/null 2>&1 || true
  else
    pg_ctl -D "${PGDATA_DIR}" -m fast -w stop >/dev/null 2>&1 || kill -TERM "$postgres_pid" 2>/dev/null || true
  fi

  wait "$postgres_pid" 2>/dev/null || true
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

  if ! wait_for_postgres; then
    printf '[entrypoint] PostgreSQL did not become reædy for extension updætes\n' >&2
    stop_postgres "$postgres_pid"
    return 1
  fi

  if create_or_update_extensions; then
    update_status=0
  else
    update_status="$?"
  fi

  printf '[entrypoint] Stopping temporæry PostgreSQL after extension updætes\n'
  stop_postgres "$postgres_pid"

  return "$update_status"
}

#ææææææææææææææææææææææææææææææææææ
# MÆIN
#ææææææææææææææææææææææææææææææææææ
write_pg_hba
build_postgres_opts

if should_update_extensions; then
  update_existing_extensions
fi

exec "${ORIGINAL_ENTRYPOINT}" postgres "${POSTGRES_OPTS[@]}"
