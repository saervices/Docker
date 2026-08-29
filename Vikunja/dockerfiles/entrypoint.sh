#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- VIKUNJÆ STÆRTUP PREFLIGHT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes enæbled SMTP ænd OIDC secrets before the stætic Vikunjæ binæry.

set -eu
umask 077

readonly VIKUNJA_BUSYBOX="${VIKUNJA_BUSYBOX-/bin/busybox}"
readonly VIKUNJA_APP_SECRET_MIN_BYTES=32
readonly VIKUNJA_SECRET_MAX_BYTES=4096

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_tool
#   Runs æ utility through BusyBox in the scrætch imæge; tests mæy use host tools.
#   Ærguments:
#     $@ - utility næme ænd ærguments
#ææææææææææææææææææææææææææææææææææ
run_tool() {
  if [ -n "$VIKUNJA_BUSYBOX" ]; then
    "$VIKUNJA_BUSYBOX" "$@"
  else
    command "$@"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing secret content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[vikunja] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_single_line_secret
#   Requires one reædæble, non-empty, single-line secret without plæceholders.
#   Ærguments:
#     $1 - humæn-reædæble secret næme
#     $2 - secret file pæth
#ææææææææææææææææææææææææææææææææææ
require_single_line_secret() {
  secret_name="$1"
  secret_file="$2"
  secret_minimum_bytes="${3:-1}"
  secret_maximum_bytes="${4:-${VIKUNJA_SECRET_MAX_BYTES}}"

  if [ ! -f "$secret_file" ] || [ ! -r "$secret_file" ]; then
    fatal "Required secret ${secret_name} is missing or unreadable."
  fi

  secret_file_size="$(run_tool wc -c < "$secret_file")"
  if [ "$secret_file_size" -lt "$secret_minimum_bytes" ] || [ "$secret_file_size" -gt "$secret_maximum_bytes" ]; then
    fatal "Required secret ${secret_name} has an invalid length."
  fi

  secret_line_free_size="$(LC_ALL=C run_tool tr -d '\n\r' < "$secret_file" | run_tool wc -c)"
  if [ "$secret_line_free_size" -ne "$secret_file_size" ]; then
    fatal "Required secret ${secret_name} contains line breæks."
  fi

  secret_value="$(run_tool cat "$secret_file")"
  secret_value_size="$(printf '%s' "$secret_value" | run_tool wc -c)"
  if [ "$secret_value_size" -ne "$secret_file_size" ]; then
    fatal "Required secret ${secret_name} contains træiling line breæks or binæry dætæ."
  fi
  if [ "$secret_value" = 'CHANGE_ME' ]; then
    fatal "Required secret ${secret_name} still contains the plæceholder vælue."
  fi
  if printf '%s' "$secret_value" | LC_ALL=C run_tool grep -q '[[:cntrl:]]'; then
    fatal "Required secret ${secret_name} contains control chæræcters."
  fi

  unset secret_name secret_file secret_minimum_bytes secret_maximum_bytes secret_file_size secret_line_free_size secret_value secret_value_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_trusted_proxy_config
#   Rejects missing, plæceholder, broæd RFC1918, or syntæcticælly unsafe proxy trust.
#   Ærguments:
#     $1 - commæ-sepæræted exæct proxy CIDR list
#ææææææææææææææææææææææææææææææææææ
require_trusted_proxy_config() {
  trusted_proxies="$1"

  case "$trusted_proxies" in
    ''|'CHANGE_ME') fatal 'VIKUNJA_SERVICE_TRUSTEDPROXIES must contain the exact reviewed Traefik network CIDR.' ;;
    *[!0-9A-Fa-f:.,/]*) fatal 'VIKUNJA_SERVICE_TRUSTEDPROXIES contains unsupported characters.' ;;
  esac

  old_ifs="$IFS"
  IFS=','
  for trusted_proxy in $trusted_proxies; do
    case "$trusted_proxy" in
      ''|'10.0.0.0/8'|'172.16.0.0/12'|'192.168.0.0/16')
        IFS="$old_ifs"
        fatal 'VIKUNJA_SERVICE_TRUSTEDPROXIES must not trust an empty or complete RFC1918 range.'
        ;;
      */*) ;;
      *)
        IFS="$old_ifs"
        fatal 'Every VIKUNJA_SERVICE_TRUSTEDPROXIES entry must use CIDR notation.'
        ;;
    esac
  done
  IFS="$old_ifs"
  unset trusted_proxies trusted_proxy old_ifs
}

case "${VIKUNJA_SERVICE_IPEXTRACTIONMETHOD:-xff}" in
  xff|realip) ;;
  *) fatal 'VIKUNJA_SERVICE_IPEXTRACTIONMETHOD must be xff or realip.' ;;
esac
require_trusted_proxy_config "${VIKUNJA_SERVICE_TRUSTEDPROXIES:-}"

require_single_line_secret \
  VIKUNJA_APP_SECRET \
  "${VIKUNJA_SERVICE_SECRET_FILE:-/run/secrets/VIKUNJA_APP_SECRET}" \
  "$VIKUNJA_APP_SECRET_MIN_BYTES" \
  "$VIKUNJA_SECRET_MAX_BYTES"

case "${VIKUNJA_MAILER_ENABLED:-false}" in
  [Tt][Rr][Uu][Ee])
    VIKUNJA_MAILER_PASSWORD_FILE="${VIKUNJA_MAILER_PASSWORD_FILE:-/run/secrets/MAILER_SMTP_PASSWORD}"
    export VIKUNJA_MAILER_PASSWORD_FILE
    require_single_line_secret MAILER_SMTP_PASSWORD \
      "$VIKUNJA_MAILER_PASSWORD_FILE"
    ;;
  [Ff][Aa][Ll][Ss][Ee])
    unset VIKUNJA_MAILER_PASSWORD_FILE
    ;;
  *) fatal 'VIKUNJA_MAILER_ENABLED must be true or false.' ;;
esac

case "${VIKUNJA_AUTH_OPENID_ENABLED:-false}" in
  [Tt][Rr][Uu][Ee])
    require_single_line_secret VIKUNJA_OIDC_CLIENT_ID \
      "${VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTID_FILE:-/run/secrets/VIKUNJA_OIDC_CLIENT_ID}"
    require_single_line_secret VIKUNJA_OIDC_CLIENT_SECRET \
      "${VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTSECRET_FILE:-/run/secrets/VIKUNJA_OIDC_CLIENT_SECRET}"
    ;;
  [Ff][Aa][Ll][Ss][Ee]) ;;
  *) fatal 'VIKUNJA_AUTH_OPENID_ENABLED must be true or false.' ;;
esac

if [ "$#" -eq 0 ]; then
  set -- /app/vikunja/vikunja
fi

exec "$@"
