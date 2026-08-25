#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Renders /tmp/element-web-config/config.json ænd the server-delegætion
# `.well-known` response from environment væriæbles. Æ dedicæted Nginx vhost
# serves only the exæct delegætion pæth for the Mætrix server-næme host.
# Runs æs æ vendor docker-entrypoint.d hook æfter the module loæder copied
# the bæked-in defæults, so this rendered file wins. Æ non-zero exit æborts
# contæiner stærtup (fæil closed).
#
# The Element Web imæge is Ælpine bæsed: POSIX sh only, pipefæil unævæilæble.
set -eu
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Logging
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() { printf '[INFO]  element-web-render-config: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() { printf '[OK]    element-web-render-config: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æn error messæge ænd æborts stærtup
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() { printf '[FATAL] element-web-render-config: %s\n' "$1" >&2; exit 1; }

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Vælidætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_dns_name
#   Fæils closed unless the vælue is æ non-empty bære DNS næme
#   Ærguments:
#     $1 - væriæble næme (for messæges)
#     $2 - væriæble vælue
#ææææææææææææææææææææææææææææææææææ
require_dns_name() {
  [ -n "$2" ] || log_fatal "$1 is required and must not be empty"
  case "$2" in
    *[!A-Za-z0-9.-]*) log_fatal "$1 must be a bare DNS name without scheme, port, or path" ;;
    -*|.*) log_fatal "$1 must not start with a dot or hyphen" ;;
  esac
}

require_dns_name MATRIX_SERVER_NAME "${MATRIX_SERVER_NAME:-}"
require_dns_name MATRIX_SYNAPSE_HOST "${MATRIX_SYNAPSE_HOST:-}"
require_dns_name MATRIX_ELEMENT_CALL_HOST "${MATRIX_ELEMENT_CALL_HOST:-}"

theme="${ELEMENT_WEB_DEFAULT_THEME:-dark}"
case "${theme}" in
  light|dark) : ;;
  *) log_fatal "ELEMENT_WEB_DEFAULT_THEME must be light or dark" ;;
esac

country="${ELEMENT_WEB_DEFAULT_COUNTRY:-DE}"
case "${country}" in
  [A-Z][A-Z]) : ;;
  *) log_fatal "ELEMENT_WEB_DEFAULT_COUNTRY must be a two-letter uppercase country code" ;;
esac

command -v jq >/dev/null 2>&1 || log_fatal "jq is required inside the Element Web image"

element_web_port="${ELEMENT_WEB_PORT:-80}"
case "${element_web_port}" in
  ''|*[!0-9]*) log_fatal "ELEMENT_WEB_PORT must be numeric" ;;
esac
[ "${element_web_port}" -ge 1 ] && [ "${element_web_port}" -le 65535 ] || log_fatal "ELEMENT_WEB_PORT must be between 1 and 65535"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Render config.json
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

config_dir="/tmp/element-web-config"
mkdir -p "${config_dir}"

log_info "rendering ${config_dir}/config.json for ${MATRIX_SERVER_NAME}"

jq -n \
  --arg base_url "https://${MATRIX_SYNAPSE_HOST}" \
  --arg server_name "${MATRIX_SERVER_NAME}" \
  --arg call_url "https://${MATRIX_ELEMENT_CALL_HOST}" \
  --arg theme "${theme}" \
  --arg country "${country}" \
  '{
    "default_server_config": {
      "m.homeserver": {
        "base_url": $base_url,
        "server_name": $server_name
      }
    },
    "brand": "Element",
    "default_theme": $theme,
    "default_country_code": $country,
    "default_federate": false,
    "disable_custom_urls": true,
    "disable_guests": true,
    "disable_3pid_login": true,
    "show_labs_settings": false,
    "room_directory": {
      "servers": [$server_name]
    },
    "features": {
      "feature_video_rooms": true,
      "feature_group_calls": true,
      "feature_element_call_video_rooms": true
    },
    "element_call": {
      "url": $call_url,
      "use_exclusively": true
    }
  }' > "${config_dir}/config.json.new"

mv "${config_dir}/config.json.new" "${config_dir}/config.json"
chmod 0644 "${config_dir}/config.json"

jq -n \
  --arg delegated_server "${MATRIX_SYNAPSE_HOST}:443" \
  '{"m.server": $delegated_server}' > "${config_dir}/server.json.new"
mv "${config_dir}/server.json.new" "${config_dir}/server.json"
chmod 0644 "${config_dir}/server.json"

cat > /etc/nginx/conf.d/zz-matrix-server-well-known.conf <<EOF
server {
    listen ${element_web_port};
    server_name ${MATRIX_SERVER_NAME};

    location = /.well-known/matrix/server {
        alias ${config_dir}/server.json;
        default_type application/json;
        add_header Access-Control-Allow-Origin "*" always;
        add_header Cache-Control "no-store" always;
        limit_except GET { deny all; }
    }

    location / {
        return 404;
    }
}
EOF
chmod 0644 /etc/nginx/conf.d/zz-matrix-server-well-known.conf

log_ok "config.json ænd Mætrix server delegætion rendered"
