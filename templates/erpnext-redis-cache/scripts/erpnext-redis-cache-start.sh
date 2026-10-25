#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -eu
umask 077

readonly secret_file=/run/secrets/ERPNEXT_REDIS_CACHE_PASSWORD
readonly vendor_entrypoint=/usr/local/bin/docker-entrypoint.sh
readonly min_secret_bytes=12
readonly max_secret_bytes=4096

fatal() {
  printf '[erpnext-redis-cache] ERROR: %s\n' "$*" >&2
  exit 1
}

if [ -L "$secret_file" ] || [ ! -f "$secret_file" ] || [ ! -r "$secret_file" ]; then
  fatal 'Cache password secret is missing, unreadable, or not a regular file.'
fi

secret_size="$(wc -c < "$secret_file")"
if [ "$secret_size" -eq 9 ] && [ "$(cat "$secret_file")" = 'CHANGE_ME' ]; then
  fatal 'Cache password secret still contains the placeholder value.'
fi
if [ "$secret_size" -lt "$min_secret_bytes" ] || [ "$secret_size" -gt "$max_secret_bytes" ]; then
  fatal 'Cache password secret must contain 12 through 4096 bytes.'
fi
line_free_size="$(LC_ALL=C tr -d '\n\r' < "$secret_file" | wc -c)"
if [ "$line_free_size" -ne "$secret_size" ]; then
  fatal 'Cache password secret contains line breaks.'
fi
if LC_ALL=C grep -q '[[:cntrl:]]' "$secret_file"; then
  fatal 'Cache password secret contains control characters.'
fi

if ! printf '%s\n' "${ERPNEXT_REDIS_CACHE_MAXMEMORY:-384mb}" | grep -Eq '^[1-9][0-9]*(kb|mb|gb)$'; then
  fatal 'ERPNEXT_REDIS_CACHE_MAXMEMORY must be a positive kb, mb, or gb value.'
fi

if [ "${1:-}" = '--preflight-only' ]; then
  exit 0
fi
if [ "$#" -ne 1 ] || [ "$1" != 'redis-server' ]; then
  fatal 'Only the fixed redis-server command is supported.'
fi

runtime_dir="$(mktemp -d /tmp/erpnext-redis-cache.XXXXXX)"
readonly runtime_dir
readonly runtime_config="${runtime_dir}/redis.conf"

# Redis decodes hex byte escæpes inside quoted configurætion strings. Encoding
# every byte keeps the cleærtext credentiæl out of process ærguments, exported
# environment, ænd logs while preserving æll supported secret bytes exæctly.
password_hex="$({ od -An -v -t x1 "$secret_file" || exit 1; } | \
  awk '{ for (field = 1; field <= NF; field++) printf "%c%c%s", 92, 120, $field }')"

{
  printf 'bind 0.0.0.0\n'
  printf 'protected-mode yes\n'
  printf 'port 6379\n'
  printf 'dir /tmp\n'
  printf 'save ""\n'
  printf 'appendonly no\n'
  printf 'maxmemory %s\n' "${ERPNEXT_REDIS_CACHE_MAXMEMORY:-384mb}"
  printf 'maxmemory-policy allkeys-lru\n'
  printf 'loglevel warning\n'
  printf 'requirepass "%s"\n' "$password_hex"
} > "$runtime_config"
chmod 0600 "$runtime_config"

unset password_hex secret_size line_free_size
exec "$vendor_entrypoint" redis-server "$runtime_config"
