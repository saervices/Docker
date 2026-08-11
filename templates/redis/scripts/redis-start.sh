#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -eu
umask 077

readonly redis_secret_file="${REDIS_PASSWORD_FILE:-/run/secrets/REDIS_PASSWORD}"
readonly redis_secret_min_bytes=12
readonly redis_secret_max_bytes=4096
readonly redis_vendor_entrypoint=/usr/local/bin/docker-entrypoint.sh

fatal() {
  printf '[redis] ERROR: %s\n' "$*" >&2
  exit 1
}

if [ -L "$redis_secret_file" ] || [ ! -f "$redis_secret_file" ] || [ ! -r "$redis_secret_file" ]; then
  fatal 'REDIS_PASSWORD secret is missing, unreadable, or not a regular file.'
fi

redis_secret_size="$(wc -c < "$redis_secret_file")"
if [ "$redis_secret_size" -eq 9 ] && [ "$(cat "$redis_secret_file")" = 'CHANGE_ME' ]; then
  fatal 'REDIS_PASSWORD secret still contains the placeholder value.'
fi
if [ "$redis_secret_size" -lt "$redis_secret_min_bytes" ] || \
   [ "$redis_secret_size" -gt "$redis_secret_max_bytes" ]; then
  fatal 'REDIS_PASSWORD secret must contain 12 through 4096 bytes.'
fi

redis_line_free_size="$(LC_ALL=C tr -d '\n\r' < "$redis_secret_file" | wc -c)"
if [ "$redis_line_free_size" -ne "$redis_secret_size" ]; then
  fatal 'REDIS_PASSWORD secret contains line breaks.'
fi

if LC_ALL=C grep -q '[[:cntrl:]]' "$redis_secret_file"; then
  fatal 'REDIS_PASSWORD secret contains control characters.'
fi

if [ "${1:-}" = '--preflight-only' ]; then
  exit 0
fi

if [ "$#" -ne 1 ] || [ "$1" != 'redis-server' ]; then
  fatal 'Only the fixed redis-server command is supported.'
fi

redis_runtime_dir="$(mktemp -d /tmp/redis-runtime.XXXXXX)"
readonly redis_runtime_dir
readonly redis_runtime_config="${redis_runtime_dir}/redis.conf"

# Redis' quoted configurætion syntæx decodes \xNN byte escæpes. Encoding every
# byte keeps spæces, quotes, bæckslæshes, ænd non-ÆSCII bytes out of the pærser
# syntæx without ever copying the cleærtext secret into process ærguments or
# exported environment væriæbles.
redis_password_hex="$({ od -An -v -t x1 "$redis_secret_file" || exit 1; } | \
  awk '{ for (field = 1; field <= NF; field++) printf "%c%c%s", 92, 120, $field }')"

{
  printf 'save 60 1\n'
  printf 'loglevel warning\n'
  printf 'requirepass "%s"\n' "$redis_password_hex"
} > "$redis_runtime_config"
chmod 0600 "$redis_runtime_config"

unset redis_password_hex redis_secret_size redis_line_free_size

exec "$redis_vendor_entrypoint" redis-server "$redis_runtime_config"
