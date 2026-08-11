#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly ERPNEXT_BAKED_ASSETS_ROOT="${ERPNEXT_BAKED_ASSETS_ROOT:-/home/frappe/frappe-bench/assets}"
readonly ERPNEXT_NGINX_TEMPLATE="${ERPNEXT_NGINX_TEMPLATE:-/templates/nginx/frappe.conf.template}"
readonly ERPNEXT_VENDOR_NGINX_ENTRYPOINT="${ERPNEXT_VENDOR_NGINX_ENTRYPOINT:-/usr/local/bin/nginx-entrypoint.sh}"
readonly ERPNEXT_NGINX_RENDERED_CONFIGURATION="${ERPNEXT_NGINX_RENDERED_CONFIGURATION:-/etc/nginx/conf.d/frappe.conf}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs a startup error without exposing sensitive data, then exits.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[erpnext-frontend] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_ipv4
#   Accepts one canonical dotted-decimal IPv4 address.
#   Arguments:
#     $1 - IPv4 candidate
#ææææææææææææææææææææææææææææææææææ
is_valid_ipv4() {
  local candidate="$1"
  local octet
  local -a octets=()

  [[ "${candidate}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS='.' read -r -a octets <<<"${candidate}"
  (( ${#octets[@]} == 4 )) || return 1

  for octet in "${octets[@]}"; do
    [[ "${octet}" == "0" || "${octet}" =~ ^[1-9][0-9]{0,2}$ ]] || return 1
    (( 10#${octet} <= 255 )) || return 1
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_proxy_cidr
#   Requires a bounded IPv4 CIDR for the direct Traefik peer network.
#   Arguments:
#     $1 - IPv4 CIDR candidate
#ææææææææææææææææææææææææææææææææææ
require_proxy_cidr() {
  local cidr="$1"
  local address prefix address_integer host_mask
  local -a octets=()

  [[ -n "${cidr}" && "${cidr}" != 'CHANGE_ME' && "${cidr}" == */* ]] || \
    fatal 'ERPNEXT_TRUSTED_PROXY_CIDR must be replaced with an explicit IPv4 CIDR.'
  case "${cidr}" in
    10.0.0.0/8|172.16.0.0/12|192.168.0.0/16)
      fatal 'ERPNEXT_TRUSTED_PROXY_CIDR must not use a vendor-default broad private range.'
      ;;
  esac
  address="${cidr%/*}"
  prefix="${cidr##*/}"
  is_valid_ipv4 "${address}" || fatal 'ERPNEXT_TRUSTED_PROXY_CIDR contains an invalid IPv4 address.'
  [[ "${prefix}" =~ ^(1[6-9]|2[0-9]|3[0-2])$ ]] || \
    fatal 'ERPNEXT_TRUSTED_PROXY_CIDR must use a prefix length from /16 through /32.'
  [[ "${address}" != '0.0.0.0' && "${address}" != '255.255.255.255' && "${address}" != 127.* ]] || \
    fatal 'ERPNEXT_TRUSTED_PROXY_CIDR must identify the real non-loopback Traefik source network.'

  IFS='.' read -r -a octets <<<"${address}"
  address_integer=$((
    (10#${octets[0]} << 24) |
    (10#${octets[1]} << 16) |
    (10#${octets[2]} << 8) |
    10#${octets[3]}
  ))
  if (( 10#${prefix} == 32 )); then
    host_mask=0
  else
    host_mask=$(( (1 << (32 - 10#${prefix})) - 1 ))
  fi
  (( (address_integer & host_mask) == 0 )) || \
    fatal 'ERPNEXT_TRUSTED_PROXY_CIDR must use the canonical network address for its prefix.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_dns_name
#   Requires one lowercase DNS hostname and rejects shipped placeholders.
#   Arguments:
#     $1 - Environment variable name
#     $2 - DNS hostname candidate
#ææææææææææææææææææææææææææææææææææ
require_dns_name() {
  local variable_name="$1"
  local candidate="$2"
  local label
  local -a labels=()

  [[ -n "${candidate}" && ${#candidate} -le 253 ]] || fatal "${variable_name} is missing or too long."
  [[ "${candidate}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && "${candidate}" == *.* ]] || \
    fatal "${variable_name} must be a lowercase fully-qualified DNS name."
  [[ "${candidate}" != *'..'* && "${candidate}" != *CHANGE_ME* ]] || \
    fatal "${variable_name} still contains a placeholder or an invalid label boundary."
  case ".${candidate}" in
    *.example.com|*.example.net|*.example.org|*.invalid|*.test|*.localhost)
      fatal "${variable_name} uses a reserved example or local-only DNS suffix."
      ;;
  esac

  IFS='.' read -r -a labels <<<"${candidate}"
  for label in "${labels[@]}"; do
    [[ ${#label} -le 63 && "${label}" != -* && "${label}" != *- ]] || \
      fatal "${variable_name} contains an invalid DNS label."
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_bounded_integer
#   Requires an unsigned decimal integer within a closed range.
#   Arguments:
#     $1 - Environment variable name
#     $2 - Candidate value
#     $3 - Minimum value
#     $4 - Maximum value
#ææææææææææææææææææææææææææææææææææ
require_bounded_integer() {
  local variable_name="$1"
  local candidate="$2"
  local minimum="$3"
  local maximum="$4"

  [[ "${candidate}" =~ ^[1-9][0-9]*$ ]] || fatal "${variable_name} must be a positive decimal integer."
  (( 10#${candidate} >= minimum && 10#${candidate} <= maximum )) || \
    fatal "${variable_name} is outside the supported range."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_configuration
#   Validates every value interpolated into the vendor Nginx template.
#ææææææææææææææææææææææææææææææææææ
validate_configuration() {
  [[ "${APP_NAME:-}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || \
    fatal 'APP_NAME must be a safe lowercase service prefix.'
  [[ "${BACKEND:-}" == "${APP_NAME}-erpnext-backend:8000" ]] || \
    fatal 'BACKEND does not match the APP_NAME-scoped ERPNext backend endpoint.'
  [[ "${SOCKETIO:-}" == "${APP_NAME}-erpnext-websocket:9000" ]] || \
    fatal 'SOCKETIO does not match the APP_NAME-scoped ERPNext websocket endpoint.'
  require_dns_name 'FRAPPE_SITE_NAME_HEADER' "${FRAPPE_SITE_NAME_HEADER:-}"
  require_proxy_cidr "${UPSTREAM_REAL_IP_ADDRESS:-}"
  [[ "${UPSTREAM_REAL_IP_HEADER:-}" == 'X-Forwarded-For' ]] || \
    fatal 'UPSTREAM_REAL_IP_HEADER must be X-Forwarded-For.'
  [[ "${UPSTREAM_REAL_IP_RECURSIVE:-}" == 'off' ]] || \
    fatal 'UPSTREAM_REAL_IP_RECURSIVE must remain off for the single trusted proxy hop.'
  require_bounded_integer 'PROXY_READ_TIMEOUT' "${PROXY_READ_TIMEOUT:-}" 1 600
  [[ "${CLIENT_MAX_BODY_SIZE:-}" =~ ^[1-9][0-9]{0,3}[mM]$ ]] || \
    fatal 'CLIENT_MAX_BODY_SIZE must be between 1m and 9999m in Nginx size syntax.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_template_marker
#   Requires one literal contract marker in the mounted Nginx template.
#   Arguments:
#     $1 - Required literal marker
#ææææææææææææææææææææææææææææææææææ
require_template_marker() {
  grep -Fq -- "$1" "${ERPNEXT_NGINX_TEMPLATE}" || \
    fatal 'The mounted Nginx template is missing a required least-privilege marker.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_frontend_state
#   Requires the reviewed custom template and image-baked public assets only.
#ææææææææææææææææææææææææææææææææææ
validate_frontend_state() {
  local template_metadata
  local template_type template_size

  [[ ! -L "${ERPNEXT_BAKED_ASSETS_ROOT}" && -d "${ERPNEXT_BAKED_ASSETS_ROOT}" && \
      -r "${ERPNEXT_BAKED_ASSETS_ROOT}" ]] || \
    fatal 'The baked ERPNext assets directory is missing, unreadable, or unsafe.'
  [[ ! -L "${ERPNEXT_NGINX_TEMPLATE}" ]] || \
    fatal 'The mounted Nginx template must not be a symbolic link.'
  template_metadata=$(stat -c '%F:%s' -- "${ERPNEXT_NGINX_TEMPLATE}") || \
    fatal 'The mounted Nginx template is missing or unreadable.'
  IFS=':' read -r template_type template_size <<<"${template_metadata}"
  [[ "${template_type}" == 'regular file' && "${template_size}" =~ ^[1-9][0-9]*$ && \
      -r "${ERPNEXT_NGINX_TEMPLATE}" ]] || \
    fatal 'The mounted Nginx template must be a non-empty readable regular file.'

  require_template_marker 'root /home/frappe/frappe-bench;'
  require_template_marker "server \${BACKEND} fail_timeout=0;"
  require_template_marker "server \${SOCKETIO} fail_timeout=0;"
  require_template_marker 'proxy_pass http://backend-server;'
  require_template_marker 'proxy_pass http://socketio-server;'
  require_template_marker "proxy_set_header Host \${FRAPPE_SITE_NAME_HEADER};"
  require_template_marker 'proxy_set_header X-Forwarded-For $remote_addr;'
  require_template_marker 'location ~* ^/(?:private/)?files/.*\.(?:htm|html|xht|xhtml|svg|svgz|xml)$ {'
  require_template_marker 'proxy_hide_header Content-Disposition;'
  require_template_marker 'server_tokens off;'
  require_template_marker 'include /etc/nginx/snippets/security_headers.conf;'
  if grep -Fq -- 'X-Use-X-Accel-Redirect' "${ERPNEXT_NGINX_TEMPLATE}" || \
      grep -Fq -- '/home/frappe/frappe-bench/sites' "${ERPNEXT_NGINX_TEMPLATE}" || \
      grep -Fq -- 'proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' "${ERPNEXT_NGINX_TEMPLATE}" || \
      grep -Fq -- "proxy_set_header Host \$host;" "${ERPNEXT_NGINX_TEMPLATE}"; then
    fatal 'The mounted Nginx template attempts to use site-volume file serving.'
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_vendor_marker
#   Requires one literal marker in the inspected vendor Nginx entrypoint.
#   Arguments:
#     $1 - Required literal marker
#ææææææææææææææææææææææææææææææææææ
require_vendor_marker() {
  grep -Fq -- "$1" "${ERPNEXT_VENDOR_NGINX_ENTRYPOINT}" || \
    fatal 'The vendor Nginx entrypoint drifted from the replicated startup contract.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_vendor_entrypoint
#   Rejects vendor drift before replicating the exact vendor startup steps.
#ææææææææææææææææææææææææææææææææææ
validate_vendor_entrypoint() {
  local variable_name

  [[ ! -L "${ERPNEXT_VENDOR_NGINX_ENTRYPOINT}" && -f "${ERPNEXT_VENDOR_NGINX_ENTRYPOINT}" && \
      -r "${ERPNEXT_VENDOR_NGINX_ENTRYPOINT}" ]] || \
    fatal 'The vendor Nginx entrypoint is missing, unreadable, or an unexpected symlink.'

  require_vendor_marker "</templates/nginx/frappe.conf.template >/etc/nginx/conf.d/frappe.conf"
  require_vendor_marker "nginx -g 'daemon off;'"
  for variable_name in BACKEND SOCKETIO UPSTREAM_REAL_IP_ADDRESS UPSTREAM_REAL_IP_HEADER \
      UPSTREAM_REAL_IP_RECURSIVE FRAPPE_SITE_NAME_HEADER PROXY_READ_TIMEOUT CLIENT_MAX_BODY_SIZE; do
    require_vendor_marker "\${${variable_name}}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: render_nginx_configuration
#   Renders the validated template exactly like the inspected vendor script.
#ææææææææææææææææææææææææææææææææææ
render_nginx_configuration() {
  # shellcheck disable=SC2016
  # The single-quoted væriæble list is the literæl envsubst SHELL-FORMAT contræct.
  envsubst '${BACKEND} ${SOCKETIO} ${UPSTREAM_REAL_IP_ADDRESS} ${UPSTREAM_REAL_IP_HEADER} ${UPSTREAM_REAL_IP_RECURSIVE} ${FRAPPE_SITE_NAME_HEADER} ${PROXY_READ_TIMEOUT} ${CLIENT_MAX_BODY_SIZE}' \
    <"${ERPNEXT_NGINX_TEMPLATE}" >"${ERPNEXT_NGINX_RENDERED_CONFIGURATION}" || \
    fatal 'Rendering the validated Nginx configuration failed.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Runs fail-closed validation, renders the vendor-equivalent configuration,
#   and executes Nginx directly so SIGTERM reaches the daemon and exits 0.
#   Arguments:
#     $1 - Optional --preflight-only test mode
#ææææææææææææææææææææææææææææææææææ
main() {
  validate_configuration
  validate_frontend_state

  if [[ "${1:-}" == '--preflight-only' ]]; then
    (( $# == 1 )) || fatal 'The preflight-only mode accepts no additional arguments.'
    return 0
  fi
  (( $# == 0 )) || fatal 'Unsupported frontend wrapper arguments were supplied.'
  validate_vendor_entrypoint
  render_nginx_configuration

  exec nginx -g 'daemon off;'
}

main "$@"
