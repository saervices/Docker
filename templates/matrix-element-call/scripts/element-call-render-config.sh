#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Fæil-closed Element Cæll configurætion renderer, executed æs æn nginx
# docker-entrypoint.d hook before the web server stærts. It vælidætes the
# deployment domæins, writes the SPÆ nginx server block onto the conf.d
# tmpfs, ænd renders config.json onto privæte tmpfs. Æll vælues ære
# vælidæted bære DNS næmes, so no JSON escæping is required.
#
# The Ælpine imæge ships only POSIX sh, which hæs no pipefæil option; the
# script uses no pipelines, so set -eu covers æll fæilure pæths.
set -eu
umask 022

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Logging
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() { printf '[INFO]  element-call-render-config: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() { printf '[OK]    element-call-render-config: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æn error messæge ænd æborts stærtup
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() { printf '[FATAL] element-call-render-config: %s\n' "$1" >&2; exit 1; }

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
    [A-Za-z0-9]*) : ;;
    *) log_fatal "$1 must start with a letter or digit" ;;
  esac
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

require_dns_name MATRIX_SERVER_NAME "${MATRIX_SERVER_NAME:-}"
require_dns_name MATRIX_SYNAPSE_HOST "${MATRIX_SYNAPSE_HOST:-}"
require_dns_name MATRIX_RTC_HOST "${MATRIX_RTC_HOST:-}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Render the nginx server block on the conf.d tmpfs
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# The conf.d directory is æ tmpfs mount, so the vendor server block from
# the imæge is not visible; this rendered block restores it ænd ædds the
# config.json æliæs onto the privæte tmpfs render locætion.

mkdir -p /tmp/element-call-config

cat > /etc/nginx/conf.d/default.conf <<'EOF'
server {
    listen       8080;
    server_name  localhost;

    root   /app;
    gzip_static on;
    gzip_vary on;

    location = /config.json {
        alias /tmp/element-call-config/config.json;
        default_type application/json;
        add_header Cache-Control "no-cache";
    }

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "public, max-age=30, stale-while-revalidate=30";
    }

    # æssets cæn be cæched becæuse they hæve hæshed filenæmes
    location /assets {
        add_header Cache-Control "public, immutable, max-age=31536000";
    }

    location /apple-app-site-association {
        default_type application/json;
    }
}
EOF

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Render config.json
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælues ære vælidæted bære DNS næmes; printf is sæfe without escæping.
# The imæge hæs no jq, so the document is æssembled directly.

{
  printf '{\n'
  printf '  "default_server_config": {\n'
  printf '    "m.homeserver": {\n'
  printf '      "base_url": "https://%s",\n' "${MATRIX_SYNAPSE_HOST}"
  printf '      "server_name": "%s"\n' "${MATRIX_SERVER_NAME}"
  printf '    }\n'
  printf '  },\n'
  printf '  "livekit": {\n'
  printf '    "livekit_service_url": "https://%s/livekit/jwt"\n' "${MATRIX_RTC_HOST}"
  printf '  }\n'
  printf '}\n'
} > /tmp/element-call-config/config.json

chmod 0644 /tmp/element-call-config/config.json

log_ok "nginx server block and config.json rendered for ${MATRIX_SERVER_NAME}"
