#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -eu

MARIADB_DATA_ROOT=/var/lib/mysql
MARIADB_VENDOR_ENTRYPOINT=/usr/local/bin/docker-entrypoint.sh
MARIADB_BINLOG_EXPIRE_LOGS_SECONDS="${MARIADB_BINLOG_EXPIRE_LOGS_SECONDS:-604800}"
MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE="${MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE:-0}"

case "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" in
  ''|*[!0-9]*)
    printf '[FATAL] MARIADB_BINLOG_EXPIRE_LOGS_SECONDS must be a whole number.\n' >&2
    exit 78
    ;;
esac
if [ "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -lt 3600 ] || [ "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -gt 31536000 ]; then
  printf '[FATAL] MARIADB_BINLOG_EXPIRE_LOGS_SECONDS must be between 3600 and 31536000.\n' >&2
  exit 78
fi
case "$MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE" in
  ''|*[!0-9]*)
    printf '[FATAL] MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE must be a whole number.\n' >&2
    exit 78
    ;;
esac
if [ "$MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE" -gt 4294967295 ]; then
  printf '[FATAL] MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE exceeds the supported unsigned range.\n' >&2
  exit 78
fi

if [ ! -d "$MARIADB_DATA_ROOT" ] || [ -L "$MARIADB_DATA_ROOT" ]; then
  printf '[FATAL] MariaDB startup blocked because the canonical data root is missing or unsafe.\n' >&2
  exit 78
fi

restore_artifact=''
if ! restore_artifact="$(find "$MARIADB_DATA_ROOT" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*' -print -quit)"; then
  printf '[FATAL] MariaDB startup blocked because restore-artifact inventory failed.\n' >&2
  exit 78
fi
if [ -n "$restore_artifact" ]; then
  printf '[FATAL] MariaDB startup blocked by unfinished restore evidence.\n' >&2
  printf '[FATAL] Keep the database stopped and run the documented maintenance restore recovery.\n' >&2
  exit 78
fi

exec "$MARIADB_VENDOR_ENTRYPOINT" "$@"
