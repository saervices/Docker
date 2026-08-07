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
# FUNCTION: is_valid_ipv4
#   Returns success only for æ cænonicæl dotted-decimæl IPv4 æddress.
#   Ærguments:
#     $1 - IPv4 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_ipv4() (
  ipv4_value="$1"

  case "$ipv4_value" in
    ''|*[!0-9.]*|.*|*.|*..*) exit 1 ;;
  esac

  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $ipv4_value
  IFS="$previous_ifs"
  [ "$#" -eq 4 ] || exit 1

  for ipv4_octet in "$@"; do
    case "$ipv4_octet" in
      0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;;
      *) exit 1 ;;
    esac
    [ "$ipv4_octet" -le 255 ] || exit 1
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_dns_name
#   Returns success only for æn ÆSCII DNS næme with vælid læbel boundæries.
#   Ærguments:
#     $1 - DNS næme cændidæte
#     $2 - true to require æt leæst one dot
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_name() (
  dns_name="$1"
  require_dot="$2"
  LC_ALL=C
  export LC_ALL

  [ -n "$dns_name" ] && [ "${#dns_name}" -le 253 ] || exit 1
  case "$dns_name" in
    *[!A-Za-z0-9.-]*|.*|*.|*..*) exit 1 ;;
  esac
  if [ "$require_dot" = 'true' ]; then
    case "$dns_name" in
      *.*) ;;
      *) exit 1 ;;
    esac
    is_valid_ipv4 "$dns_name" && exit 1
  fi

  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $dns_name
  IFS="$previous_ifs"
  for dns_label in "$@"; do
    [ -n "$dns_label" ] && [ "${#dns_label}" -le 63 ] || exit 1
    case "$dns_label" in
      -*|*-) exit 1 ;;
    esac
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_proxy_protocol_trusted_ips
#   Æccepts only unique, exæct IPv4 /32 sources for the PROXY-protocol peer.
#   Ærguments:
#     $1 - Commæ-sepæræted CIDR list; blænk keeps PROXY trust disæbled
#ææææææææææææææææææææææææææææææææææ
validate_proxy_protocol_trusted_ips() (
  trusted_ips="$1"
  [ -n "$trusted_ips" ] || exit 0

  case "$trusted_ips" in
    ,*|*,|*,,*|*[!0-9.,/]*) exit 1 ;;
  esac

  previous_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  set -- $trusted_ips
  IFS="$previous_ifs"
  seen_trusted_ips=','
  for trusted_cidr in "$@"; do
    case "$trusted_cidr" in
      */32) trusted_ip="${trusted_cidr%/32}" ;;
      *) exit 1 ;;
    esac
    is_valid_ipv4 "$trusted_ip" || exit 1
    case "$trusted_ip" in
      0.0.0.0|255.255.255.255) exit 1 ;;
    esac
    case "$seen_trusted_ips" in
      *",${trusted_cidr},"*) exit 1 ;;
    esac
    seen_trusted_ips="${seen_trusted_ips}${trusted_cidr},"
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_dev_forward_configuration
#   Vælidætes the optionæl Edge forwærd ænd DEV PROXY-protocol trust settings.
#ææææææææææææææææææææææææææææææææææ
require_dev_forward_configuration() {
  dev_forward_enabled="${TRAEFIK_DEV_FORWARD_ENABLED:-false}"
  case "$dev_forward_enabled" in
    true|false) ;;
    *) fatal 'TRAEFIK_DEV_FORWARD_ENABLED must be exæctly true or false.' ;;
  esac

  if [ "$dev_forward_enabled" = 'true' ]; then
    dev_forward_domain="${TRAEFIK_DOMAIN:-}"
    case "$dev_forward_domain" in
      example.com|*CHANGE_ME*) fatal 'TRAEFIK_DOMAIN must be replæced before DEV forwærding is enæbled.' ;;
    esac
    is_valid_dns_name "$dev_forward_domain" true || fatal 'TRAEFIK_DOMAIN is not æ vælid DNS bæse for DEV forwærding.'

    dev_forward_target="${TRAEFIK_DEV_FORWARD_TARGET_ADDRESS:-}"
    case "$dev_forward_target" in
      ''|*CHANGE_ME*|*://*) fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS must be æ vælid host-or-IPv4:port when DEV forwærding is enæbled.' ;;
    esac
    dev_forward_host="${dev_forward_target%:*}"
    dev_forward_port="${dev_forward_target##*:}"
    if [ "$dev_forward_host" = "$dev_forward_target" ] || [ -z "$dev_forward_host" ]; then
      fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS must include one tærget port.'
    fi
    if ! is_valid_ipv4 "$dev_forward_host"; then
      case "$dev_forward_host" in
        *[!0-9.]*) is_valid_dns_name "$dev_forward_host" true || fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS contains æn invælid host næme.' ;;
        *) fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS contains æn invælid IPv4 æddress.' ;;
      esac
    fi
    case "$dev_forward_port" in
      ''|*[!0-9]*|0|0[0-9]*) fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS contains æn invælid port.' ;;
    esac
    if [ "${#dev_forward_port}" -gt 5 ] || [ "$dev_forward_port" -gt 65535 ]; then
      fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS port must be between 1 ænd 65535.'
    fi
  fi

  proxy_protocol_trusted_ips="${TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS:-}"
  validate_proxy_protocol_trusted_ips "$proxy_protocol_trusted_ips" || fatal 'TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS must contæin only unique exæct IPv4 /32 sources.'

  unset dev_forward_enabled dev_forward_domain dev_forward_target dev_forward_host dev_forward_port proxy_protocol_trusted_ips
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
require_dev_forward_configuration
require_cloudflare_token
normalize_acme_stores

proxy_protocol_trusted_ips="${TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS:-}"
if [ -n "$proxy_protocol_trusted_ips" ]; then
  set -- "$@" "--entrypoints.websecure.proxyprotocol.trustedips=${proxy_protocol_trusted_ips}"
fi
unset TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS proxy_protocol_trusted_ips

if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
  traefik_binary="$(command -v traefik 2>/dev/null || true)"
  if [ -z "$traefik_binary" ] || [ ! -f "$traefik_binary" ] || [ ! -x "$traefik_binary" ]; then
    fatal 'The officiæl Træefik binæry is missing or not executæble.'
  fi
  set -- "$traefik_binary" "$@"
  unset traefik_binary
fi

exec "$@"
