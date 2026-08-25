#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -eu
umask 077

MARIADB_DATA_ROOT=/var/lib/mysql
MARIADB_BINLOG_SCANNER=/usr/local/libexec/scan-binlogs.mariadb.pl
MARIADB_BINLOG_SCANNER_SHA256='239103c167e51dc264c4295472c017d838f26ec12116ca66dccd1107ce8315b2'
MARIADB_BINLOG_SCANNER_OWNER='0:0'
MARIADB_VENDOR_ENTRYPOINT=/usr/local/bin/docker-entrypoint-reviewed.sh
MARIADB_VENDOR_ENTRYPOINT_SHA256S='f25d3c3a100936e686b9a508cca4f1fa9d2abcc4bc74ed4c1dabe57e88703be3 23426ac0f8d688aa3f8f1c7506a46f884269e19d4e7661831421649d03579ee4'
MARIADB_VENDOR_ENTRYPOINT_OWNER='0:0'
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

if [ ! -f "$MARIADB_BINLOG_SCANNER" ] || [ -L "$MARIADB_BINLOG_SCANNER" ]; then
  printf '[FATAL] MariaDB startup blocked because the binary-log scanner is missing or unsafe.\n' >&2
  exit 78
fi
if [ "$(stat -c '%u:%g:%h:%a' "$MARIADB_BINLOG_SCANNER")" != "${MARIADB_BINLOG_SCANNER_OWNER}:1:555" ]; then
  printf '[FATAL] MariaDB startup blocked because the binary-log scanner metadata drifted.\n' >&2
  exit 78
fi
binlog_scanner_sha256="$(sha256sum "$MARIADB_BINLOG_SCANNER")"
binlog_scanner_sha256="${binlog_scanner_sha256%% *}"
if [ "$binlog_scanner_sha256" != "$MARIADB_BINLOG_SCANNER_SHA256" ]; then
  printf '[FATAL] MariaDB startup blocked because the binary-log scanner bytes drifted.\n' >&2
  exit 78
fi
if "$MARIADB_BINLOG_SCANNER"; then
  :
else
  printf '[FATAL] MariaDB startup blocked by the binary-log secret audit.\n' >&2
  exit 78
fi

if [ ! -f "$MARIADB_VENDOR_ENTRYPOINT" ] || [ -L "$MARIADB_VENDOR_ENTRYPOINT" ]; then
  printf '[FATAL] MariaDB startup blocked because the reviewed vendor entrypoint is missing or unsafe.\n' >&2
  exit 78
fi
if [ "$(stat -c '%u:%g:%h:%a' "$MARIADB_VENDOR_ENTRYPOINT")" != "${MARIADB_VENDOR_ENTRYPOINT_OWNER}:1:555" ]; then
  printf '[FATAL] MariaDB startup blocked because the reviewed vendor entrypoint metadata drifted.\n' >&2
  exit 78
fi
vendor_entrypoint_sha256="$(sha256sum "$MARIADB_VENDOR_ENTRYPOINT")"
vendor_entrypoint_sha256="${vendor_entrypoint_sha256%% *}"
case " $MARIADB_VENDOR_ENTRYPOINT_SHA256S " in
  *" $vendor_entrypoint_sha256 "*) ;;
  *)
    printf '[FATAL] MariaDB startup blocked because the reviewed vendor entrypoint bytes drifted.\n' >&2
    exit 78
    ;;
esac

exec "$MARIADB_VENDOR_ENTRYPOINT" "$@"
