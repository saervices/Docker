#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Fæil-closed Synæpse entrypoint: vælidætes environment ænd secrets, ensures
# æ persistent signing key, renders homeserver.yaml plus the log config on
# privæte tmpfs, then execs the Synæpse homeserver. Secrets stæy out of the
# process environment ænd ærgv; Synæpse reæds them viæ *_pæth options or the
# mode-0600 rendered configurætion.
set -euo pipefail
umask 077

readonly MATRIX_SECRET_READER=/usr/local/lib/matrix-synapse-secret-reader.sh
if [[ -L "${MATRIX_SECRET_READER}" || ! -f "${MATRIX_SECRET_READER}" ]]; then
  printf '[FATAL] matrix-synapse-start: secret reader is missing or is not a regular file\n' >&2
  exit 1
fi
# The runtime helper is mounted æt the vælidæted æbsolute pæth æbove.
# shellcheck disable=SC1090,SC1091
source "${MATRIX_SECRET_READER}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Logging
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() { printf '[INFO]  matrix-synapse-start: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() { printf '[OK]    matrix-synapse-start: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æn error messæge ænd æborts stærtup
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() { printf '[FATAL] matrix-synapse-start: %s\n' "$1" >&2; exit 1; }

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Vælidætion helpers
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_dns_name
#   Fæils closed unless the vælue is æ non-empty bære DNS næme
#   Ærguments:
#     $1 - væriæble næme (for messæges)
#     $2 - væriæble vælue
#ææææææææææææææææææææææææææææææææææ
require_dns_name() {
  [[ -n "$2" ]] || log_fatal "$1 is required and must not be empty"
  [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || log_fatal "$1 must be a bare DNS name without scheme, port, or path"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_secret_snapshot
#   Vælidætes æ mounted single-line secret into æ privæte snæpshot
#   Ærguments:
#     $1 - secret file pæth
#     $2 - privæte snæpshot pæth
#     $3 - secret næme for redæcted error messæges
#ææææææææææææææææææææææææææææææææææ
require_secret_snapshot() {
  matrix_snapshot_secret "$1" "$2" 4096 single || log_fatal "$3 failed the bounded regular-file secret contract"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: yaml_squote
#   Prints the ærgument æs æ sæfe single-quoted YÆML scælær
#   Ærguments:
#     $1 - ræw string vælue
#ææææææææææææææææææææææææææææææææææ
yaml_squote() {
  matrix_yaml_squote "$1"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

require_dns_name MATRIX_SERVER_NAME "${MATRIX_SERVER_NAME:-}"
require_dns_name MATRIX_SYNAPSE_HOST "${MATRIX_SYNAPSE_HOST:-}"
require_dns_name MATRIX_ELEMENT_CALL_HOST "${MATRIX_ELEMENT_CALL_HOST:-}"
require_dns_name MATRIX_RTC_HOST "${MATRIX_RTC_HOST:-}"
require_dns_name MATRIX_SYNAPSE_DB_HOST "${MATRIX_SYNAPSE_DB_HOST:-}"
[[ -n "${MATRIX_SYNAPSE_MAS_ENDPOINT:-}" ]] || log_fatal "MATRIX_SYNAPSE_MAS_ENDPOINT is required"

config_dir=/tmp/synapse
runtime_secret_dir="${config_dir}/secrets"
mkdir -m 0700 -- "${config_dir}" "${runtime_secret_dir}" || log_fatal "cannot create the private Synapse runtime directory"
postgres_password_file="${runtime_secret_dir}/MATRIX_POSTGRES_PASSWORD"
macaroon_secret_file="${runtime_secret_dir}/MATRIX_SYNAPSE_MACAROON_SECRET"
form_secret_file="${runtime_secret_dir}/MATRIX_SYNAPSE_FORM_SECRET"
mas_synapse_secret_file="${runtime_secret_dir}/MATRIX_MAS_SYNAPSE_SECRET"
require_secret_snapshot /run/secrets/MATRIX_POSTGRES_PASSWORD "${postgres_password_file}" MATRIX_POSTGRES_PASSWORD
require_secret_snapshot /run/secrets/MATRIX_SYNAPSE_MACAROON_SECRET "${macaroon_secret_file}" MATRIX_SYNAPSE_MACAROON_SECRET
require_secret_snapshot /run/secrets/MATRIX_SYNAPSE_FORM_SECRET "${form_secret_file}" MATRIX_SYNAPSE_FORM_SECRET
require_secret_snapshot /run/secrets/MATRIX_MAS_SYNAPSE_SECRET "${mas_synapse_secret_file}" MATRIX_MAS_SYNAPSE_SECRET

max_upload_size="${MATRIX_SYNAPSE_MAX_UPLOAD_SIZE:-50M}"
[[ "${max_upload_size}" =~ ^[0-9]+[KMG]?$ ]] || log_fatal "MATRIX_SYNAPSE_MAX_UPLOAD_SIZE must look like 50M"

log_level="${MATRIX_SYNAPSE_LOG_LEVEL:-INFO}"
case "${log_level}" in
  DEBUG|INFO|WARNING|ERROR|CRITICAL) : ;;
  *) log_fatal "MATRIX_SYNAPSE_LOG_LEVEL must be DEBUG, INFO, WARNING, ERROR, or CRITICAL" ;;
esac

presence_enabled="${MATRIX_SYNAPSE_PRESENCE_ENABLED:-true}"
case "${presence_enabled}" in
  true|false) : ;;
  *) log_fatal "MATRIX_SYNAPSE_PRESENCE_ENABLED must be true or false" ;;
esac

#ææææææææææææææææææææææææææææææææææ
# FEDERÆTION MODE
#ææææææææææææææææææææææææææææææææææ
federation_mode="${MATRIX_SYNAPSE_FEDERATION_MODE:-closed}"
federation_block=""
public_listener_resources='[client]'
case "${federation_mode}" in
  open)
    public_listener_resources='[client, federation]'
    log_info "federation is open to all remote servers"
    ;;
  closed)
    federation_block="federation_domain_whitelist: []"
    log_info "federation is closed: no remote servers are allowed"
    ;;
  *)
    [[ "${federation_mode}" =~ ^[A-Za-z0-9.-]+(,[A-Za-z0-9.-]+)*$ ]] || log_fatal "MATRIX_SYNAPSE_FEDERATION_MODE must be open, closed, or a comma-separated domain list"
    public_listener_resources='[client, federation]'
    federation_block="federation_domain_whitelist:"
    IFS=',' read -r -a federation_domains <<< "${federation_mode}"
    for federation_domain in "${federation_domains[@]}"; do
      federation_block+=$'\n'"  - $(yaml_squote "${federation_domain}")"
    done
    log_info "federation restricted to: ${federation_mode}"
    ;;
esac

#ææææææææææææææææææææææææææææææææææ
# OPTIONÆL SMTP
#ææææææææææææææææææææææææææææææææææ
smtp_enabled="${MATRIX_SYNAPSE_SMTP_ENABLED:-false}"
email_block=""
case "${smtp_enabled}" in
  true)
    require_dns_name MATRIX_SYNAPSE_SMTP_HOST "${MATRIX_SYNAPSE_SMTP_HOST:-}"
    [[ "${MATRIX_SYNAPSE_SMTP_PORT:-}" =~ ^[0-9]+$ ]] || log_fatal "MATRIX_SYNAPSE_SMTP_PORT must be numeric"
    [[ -n "${MATRIX_SYNAPSE_SMTP_USER:-}" ]] || log_fatal "MATRIX_SYNAPSE_SMTP_USER is required when SMTP is enabled"
    [[ -n "${MATRIX_SYNAPSE_NOTIF_FROM:-}" ]] || log_fatal "MATRIX_SYNAPSE_NOTIF_FROM is required when SMTP is enabled"
    smtp_password_file="${runtime_secret_dir}/MATRIX_SYNAPSE_SMTP_PASSWORD"
    require_secret_snapshot /run/secrets/MATRIX_SYNAPSE_SMTP_PASSWORD "${smtp_password_file}" MATRIX_SYNAPSE_SMTP_PASSWORD
    smtp_pass="$(<"${smtp_password_file}")"
    case "${MATRIX_SYNAPSE_SMTP_MODE:-starttls}" in
      plain)    smtp_tls_lines=$'  force_tls: false\n  require_transport_security: false' ;;
      tls)      smtp_tls_lines=$'  force_tls: true\n  require_transport_security: true' ;;
      starttls) smtp_tls_lines=$'  force_tls: false\n  require_transport_security: true' ;;
      *) log_fatal "MATRIX_SYNAPSE_SMTP_MODE must be plain, tls, or starttls" ;;
    esac
    email_block="email:
  smtp_host: $(yaml_squote "${MATRIX_SYNAPSE_SMTP_HOST}")
  smtp_port: ${MATRIX_SYNAPSE_SMTP_PORT}
  smtp_user: $(yaml_squote "${MATRIX_SYNAPSE_SMTP_USER}")
  smtp_pass: $(yaml_squote "${smtp_pass}")
${smtp_tls_lines}
  notif_from: $(yaml_squote "${MATRIX_SYNAPSE_NOTIF_FROM}")"
    log_info "SMTP notification email is enabled via ${MATRIX_SYNAPSE_SMTP_HOST}"
    ;;
  false)
    [[ ! -e /run/secrets/MATRIX_SYNAPSE_SMTP_PASSWORD && ! -L /run/secrets/MATRIX_SYNAPSE_SMTP_PASSWORD ]] || log_fatal "MATRIX_SYNAPSE_SMTP_PASSWORD must not be mounted while SMTP is disabled"
    log_info "SMTP notification email is disabled"
    ;;
  *)
    log_fatal "MATRIX_SYNAPSE_SMTP_ENABLED must be true or false"
    ;;
esac

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Persistent signing key
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

signing_key_path="/data/keys/signing.key"
if [[ ! -f "${signing_key_path}" ]]; then
  log_info "generating new signing key at ${signing_key_path}"
  mkdir -p /data/keys
  generate_signing_key -o "${signing_key_path}"
  chmod 0600 "${signing_key_path}"
fi
mkdir -p /data/media_store

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Render configurætion on tmpfs
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

db_password="$(<"${postgres_password_file}")"

cat > "${config_dir}/log.config" <<EOF
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
handlers:
  console:
    class: logging.StreamHandler
    formatter: precise
root:
  level: ${log_level}
  handlers: [console]
disable_existing_loggers: false
EOF

cat > "${config_dir}/homeserver.yaml" <<EOF
server_name: $(yaml_squote "${MATRIX_SERVER_NAME}")
public_baseurl: $(yaml_squote "https://${MATRIX_SYNAPSE_HOST}/")
pid_file: ${config_dir}/homeserver.pid
signing_key_path: ${signing_key_path}
log_config: ${config_dir}/log.config
media_store_path: /data/media_store
max_upload_size: ${max_upload_size}
report_stats: false
enable_registration: false
serve_server_wellknown: false
listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    bind_addresses: ['0.0.0.0']
    resources:
      - names: ${public_listener_resources}
        compress: false
  - port: 8009
    tls: false
    type: http
    x_forwarded: false
    bind_addresses: ['0.0.0.0']
    resources:
      - names: [federation]
        compress: false
database:
  name: psycopg2
  args:
    user: synapse
    password: $(yaml_squote "${db_password}")
    dbname: synapse
    host: $(yaml_squote "${MATRIX_SYNAPSE_DB_HOST}")
    port: 5432
    cp_min: 5
    cp_max: 10
macaroon_secret_key_path: ${macaroon_secret_file}
form_secret_path: ${form_secret_file}
matrix_authentication_service:
  enabled: true
  endpoint: $(yaml_squote "${MATRIX_SYNAPSE_MAS_ENDPOINT}")
  secret_path: ${mas_synapse_secret_file}
trusted_key_servers: []
allow_public_rooms_over_federation: false
presence:
  enabled: ${presence_enabled}
experimental_features:
  msc3266_enabled: true
  msc4222_enabled: true
max_event_delay_duration: 24h
rc_message:
  per_second: 0.5
  burst_count: 30
rc_delayed_event_mgmt:
  per_second: 1
  burst_count: 20
extra_well_known_client_content:
  org.matrix.msc4143.rtc_foci:
    - type: livekit
      livekit_service_url: $(yaml_squote "https://${MATRIX_RTC_HOST}/livekit/jwt")
  io.element.element_call:
    url: $(yaml_squote "https://${MATRIX_ELEMENT_CALL_HOST}")
EOF

if [[ -n "${federation_block}" ]]; then
  printf '%s\n' "${federation_block}" >> "${config_dir}/homeserver.yaml"
fi
if [[ -n "${email_block}" ]]; then
  printf '%s\n' "${email_block}" >> "${config_dir}/homeserver.yaml"
fi

chmod 0600 "${config_dir}/homeserver.yaml"

log_ok "configuration rendered; starting Synapse"
exec python -m synapse.app.homeserver --config-path "${config_dir}/homeserver.yaml"
