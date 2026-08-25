#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Fæil-closed LiveKit entrypoint: vælidætes environment ænd the ÆPI secret,
# renders the server configurætion on privæte tmpfs, then execs the SFU.
# The ÆPI secret stæys out of the process environment ænd ærgv; LiveKit
# reæds it from the mode-0600 rendered configurætion only.
#
# The Ælpine imæge ships only POSIX sh, which hæs no pipefæil option; the
# script uses no pipelines, so set -eu covers æll fæilure pæths.
set -eu
umask 077

MATRIX_SECRET_READER=/usr/local/lib/matrix-livekit-secret-reader.sh
if [ -L "${MATRIX_SECRET_READER}" ] || [ ! -f "${MATRIX_SECRET_READER}" ]; then
  printf '[FATAL] matrix-livekit-start: secret reader is missing or is not a regular file\n' >&2
  exit 1
fi
# The runtime helper is mounted æt the vælidæted æbsolute pæth æbove.
# shellcheck disable=SC1090,SC1091
. "${MATRIX_SECRET_READER}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Logging
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() { printf '[INFO]  matrix-livekit-start: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() { printf '[OK]    matrix-livekit-start: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æn error messæge ænd æborts stærtup
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() { printf '[FATAL] matrix-livekit-start: %s\n' "$1" >&2; exit 1; }

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Vælidætion helpers
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_port
#   Fæils closed unless the vælue is æ numeric TCP/UDP port
#   Ærguments:
#     $1 - væriæble næme (for messæges)
#     $2 - væriæble vælue
#ææææææææææææææææææææææææææææææææææ
require_port() {
  case "$2" in
    ''|*[!0-9]*) log_fatal "$1 must be a numeric port" ;;
  esac
  [ "$2" -ge 1 ] && [ "$2" -le 65535 ] || log_fatal "$1 must be between 1 and 65535"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_secret_file
#   Vælidætes æ mounted single-line secret into æ privæte snæpshot
#   Ærguments:
#     $1 - secret file pæth
#     $2 - privæte snæpshot pæth
#     $3 - secret næme for redæcted error messæges
#ææææææææææææææææææææææææææææææææææ
require_secret_file() {
  matrix_snapshot_secret "$1" "$2" 4096 single || log_fatal "$3 failed the bounded regular-file secret contract"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

app_name="${APP_NAME:-}"
case "${app_name}" in
  ''|*[!A-Za-z0-9_-]*|[-_]*) log_fatal "APP_NAME must start with an alphanumeric and contain only alphanumerics, underscore, or hyphen" ;;
esac

api_key="${MATRIX_LIVEKIT_KEY:-matrixrtc}"
case "${api_key}" in
  ''|*[!A-Za-z0-9_-]*) log_fatal "MATRIX_LIVEKIT_KEY must contain only alphanumerics, underscore, or hyphen" ;;
esac

tcp_port="${MATRIX_LIVEKIT_TCP_PORT:-7881}"
udp_port="${MATRIX_LIVEKIT_UDP_PORT:-7882}"
require_port MATRIX_LIVEKIT_TCP_PORT "${tcp_port}"
require_port MATRIX_LIVEKIT_UDP_PORT "${udp_port}"

log_level="${MATRIX_LIVEKIT_LOG_LEVEL:-info}"
case "${log_level}" in
  debug|info|warn|error) : ;;
  *) log_fatal "MATRIX_LIVEKIT_LOG_LEVEL must be debug, info, warn, or error" ;;
esac

use_external_ip="${MATRIX_LIVEKIT_USE_EXTERNAL_IP:-true}"
case "${use_external_ip}" in
  true|false) : ;;
  *) log_fatal "MATRIX_LIVEKIT_USE_EXTERNAL_IP must be true or false" ;;
esac

node_ip="${MATRIX_LIVEKIT_NODE_IP:-}"
if [ -n "${node_ip}" ]; then
  case "${node_ip}" in
    *[!0-9.]*) log_fatal "MATRIX_LIVEKIT_NODE_IP must be a plain IPv4 address" ;;
  esac
  # Æ pinned node IP replæces STUN-bæsed discovery
  use_external_ip=false
fi

config_dir=/tmp/livekit
config_file="${config_dir}/config.yaml"
runtime_secret_file="${config_dir}/MATRIX_LIVEKIT_SECRET"
mkdir -m 0700 "${config_dir}" || log_fatal "cannot create the private LiveKit runtime directory"
require_secret_file /run/secrets/MATRIX_LIVEKIT_SECRET "${runtime_secret_file}" MATRIX_LIVEKIT_SECRET
api_secret="$(cat "${runtime_secret_file}")" || log_fatal "cannot read the validated LiveKit secret snapshot"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Render configurætion on tmpfs
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

{
  printf 'port: 7880\n'
  printf 'bind_addresses:\n'
  printf '  - 0.0.0.0\n'
  printf 'rtc:\n'
  printf '  tcp_port: %s\n' "${tcp_port}"
  printf '  udp_port: %s\n' "${udp_port}"
  printf '  use_external_ip: %s\n' "${use_external_ip}"
  if [ -n "${node_ip}" ]; then
    printf '  node_ip: %s\n' "${node_ip}"
  fi
  printf 'room:\n'
  printf '  auto_create: false\n'
  printf 'keys:\n'
  printf '  %s: %s\n' "$(matrix_yaml_squote "${api_key}")" "$(matrix_yaml_squote "${api_secret}")"
  printf 'webhook:\n'
  printf '  api_key: %s\n' "$(matrix_yaml_squote "${api_key}")"
  printf '  urls:\n'
  printf '    - %s\n' "$(matrix_yaml_squote "http://${app_name}-matrix-livekit-jwt:8080/sfu_webhook")"
  printf 'logging:\n'
  printf '  level: %s\n' "${log_level}"
  printf '  json: false\n'
} > "${config_file}"

chmod 0600 "${config_file}"
unset api_secret

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært the SFU
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

if [ -x /livekit-server ]; then
  livekit_binary=/livekit-server
elif command -v livekit-server >/dev/null 2>&1; then
  livekit_binary="$(command -v livekit-server)"
else
  log_fatal "livekit-server binary not found; the upstream image layout changed"
fi

log_ok "configuration rendered; starting LiveKit SFU (tcp ${tcp_port}, udp ${udp_port})"
exec "${livekit_binary}" --config "${config_file}"
