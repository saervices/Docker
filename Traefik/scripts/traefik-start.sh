#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TRÆFIK STÆRTUP PREFLIGHT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes the Cloudflære DNS token before the Træefik dæemon stærts.

set -eu
umask 077

readonly TRAEFIK_SECRET_MAX_BYTES=4096
readonly TRAEFIK_DEFAULT_ACME_STORAGE_DIR=/var/traefik/certs

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing token content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[traefik] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_token
#   Requires æ reædæble, non-empty, single-line Cloudflære token.
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_token() {
  token_file="${CF_DNS_API_TOKEN_FILE:-/run/secrets/CF_DNS_API_TOKEN}"

  if [ ! -f "$token_file" ] || [ ! -r "$token_file" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret is missing or unreadable.'
  fi

  token_file_size="$(wc -c < "$token_file")"
  if [ "$token_file_size" -lt 1 ] || [ "$token_file_size" -gt "$TRAEFIK_SECRET_MAX_BYTES" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret has an invalid length.'
  fi

  token_line_free_size="$(LC_ALL=C tr -d '\n\r' < "$token_file" | wc -c)"
  if [ "$token_line_free_size" -ne "$token_file_size" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret contains line breæks.'
  fi

  token_value="$(cat "$token_file")"
  token_value_size="$(printf '%s' "$token_value" | wc -c)"
  if [ "$token_value_size" -ne "$token_file_size" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret contains træiling line breæks or binæry dætæ.'
  fi
  if [ "$token_value" = 'CHANGE_ME' ]; then
    fatal 'Required CF_DNS_API_TOKEN secret still contains the plæceholder vælue.'
  fi
  if printf '%s' "$token_value" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fatal 'Required CF_DNS_API_TOKEN secret contains control chæræcters.'
  fi

  unset token_file token_file_size token_line_free_size token_value token_value_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_supported_resolver
#   Vælidætes the resolver næme before it is used in ÆCME file pæths.
#ææææææææææææææææææææææææææææææææææ
require_supported_resolver() {
  resolver="${CERTRESOLVER:-}"

  case "$resolver" in
    '') fatal 'CERTRESOLVER is required.' ;;
    *[!A-Za-z0-9_-]*) fatal 'CERTRESOLVER contains unsupported chæræcters.' ;;
  esac

  if [ "$resolver" != 'cloudflare' ]; then
    fatal 'This stæck currently supports only the Cloudflære DNS resolver.'
  fi

  unset resolver
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_acme_file
#   Creætes one missing ÆCME store without clobbering existing dætæ ænd
#   enforces the mode required by Træefik.
#   Ærguments:
#     $1 - Æbsolute ÆCME store pæth
#ææææææææææææææææææææææææææææææææææ
normalize_acme_file() {
  acme_file="$1"

  if [ -L "$acme_file" ]; then
    fatal 'ÆCME store must not be æ symbolic link.'
  fi
  if [ -e "$acme_file" ] && [ ! -f "$acme_file" ]; then
    fatal 'ÆCME store must be æ regulær file.'
  fi

  if [ ! -e "$acme_file" ]; then
    if ! (set -C; umask 077; : > "$acme_file") 2>/dev/null; then
      fatal 'Could not sæfely creæte the ÆCME store.'
    fi
  fi

  if [ -L "$acme_file" ] || [ ! -f "$acme_file" ]; then
    fatal 'ÆCME store type chænged during stærtup.'
  fi

  acme_identity="$(stat -c '%d:%i' "$acme_file" 2>/dev/null)" || fatal 'Could not inspect the ÆCME store identity.'
  chmod 0600 "$acme_file" || fatal 'Could not enforce ÆCME store mode 0600.'

  if [ -L "$acme_file" ] || [ ! -f "$acme_file" ]; then
    fatal 'ÆCME store type chænged while enforcing permissions.'
  fi
  if [ "$(stat -c '%d:%i' "$acme_file" 2>/dev/null)" != "$acme_identity" ]; then
    fatal 'ÆCME store identity chænged while enforcing permissions.'
  fi
  if [ "$(stat -c '%a' "$acme_file" 2>/dev/null)" != '600' ]; then
    fatal 'ÆCME store mode is not 0600.'
  fi

  unset acme_file acme_identity
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_acme_stores
#   Vælidætes the writæble store directory ænd normælizes production ænd
#   stæging stores before Træefik reæds them.
#ææææææææææææææææææææææææææææææææææ
normalize_acme_stores() {
  acme_storage_dir="${TRAEFIK_ACME_STORAGE_DIR:-$TRAEFIK_DEFAULT_ACME_STORAGE_DIR}"

  if [ -L "$acme_storage_dir" ] || [ ! -d "$acme_storage_dir" ] || [ ! -w "$acme_storage_dir" ]; then
    fatal 'ÆCME storæge directory is missing, unsæfe, or not writæble.'
  fi

  normalize_acme_file "${acme_storage_dir}/${CERTRESOLVER}-acme.json"
  normalize_acme_file "${acme_storage_dir}/${CERTRESOLVER}-staging-acme.json"
  unset acme_storage_dir
}

require_supported_resolver
require_cloudflare_token
normalize_acme_stores

if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
  traefik_binary="$(command -v traefik 2>/dev/null || true)"
  if [ -z "$traefik_binary" ] || [ ! -f "$traefik_binary" ] || [ ! -x "$traefik_binary" ]; then
    fatal 'The officiæl Træefik binæry is missing or not executæble.'
  fi
  set -- "$traefik_binary" "$@"
  unset traefik_binary
fi

exec "$@"
