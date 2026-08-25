#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Fæil-closed MÆS entrypoint: vælidætes environment, secret files, ænd the
# reviewed trusted-proxy CIDRs, renders config.yaml on privæte tmpfs, lets
# mæs-cli verify the rendered configurætion, then execs the MÆS server.
# Secrets stæy out of the process environment ænd ærgv; MÆS reæds them viæ
# *_file options or the mode-0600 rendered configurætion.
set -euo pipefail
umask 077

readonly MATRIX_SECRET_READER=/usr/local/lib/matrix-mas-secret-reader.sh
if [[ -L "${MATRIX_SECRET_READER}" || ! -f "${MATRIX_SECRET_READER}" ]]; then
  printf '[FATAL] mas-entrypoint: secret reader is missing or is not a regular file\n' >&2
  exit 1
fi
# The runtime helper is copied to the vælidæted æbsolute pæth æbove.
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
log_info() { printf '[INFO]  mas-entrypoint: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() { printf '[OK]    mas-entrypoint: %s\n' "$1"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æn error messæge ænd æborts stærtup
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() { printf '[FATAL] mas-entrypoint: %s\n' "$1" >&2; exit 1; }

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
# FUNCTION: require_url
#   Fæils closed unless the vælue is æn æbsolute URL with the given scheme
#   Ærguments:
#     $1 - væriæble næme (for messæges)
#     $2 - væriæble vælue
#     $3 - required scheme regex (e.g. https or https?)
#ææææææææææææææææææææææææææææææææææ
require_url() {
  [[ -n "$2" ]] || log_fatal "$1 is required and must not be empty"
  [[ "$2" =~ ^($3)://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?(/[A-Za-z0-9._~/-]*)?$ ]] || log_fatal "$1 must be an absolute $3:// URL without query, fragment, or user-info"
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

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_pem_private_key
#   Vælidætes æ mounted PEM privæte key into æ privæte snæpshot
#   Ærguments:
#     $1 - secret file pæth
#     $2 - privæte snæpshot pæth
#     $3 - secret næme for redæcted error messæges
#ææææææææææææææææææææææææææææææææææ
require_pem_private_key() {
  matrix_snapshot_secret "$1" "$2" 32768 pem || log_fatal "$3 failed the bounded regular-file PEM contract"
  matrix_require_rsa_private_key "$2" || log_fatal "$3 must contain exactly one valid unencrypted RSA private key"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_bool
#   Fæils closed unless the vælue is exæctly true or false
#   Ærguments:
#     $1 - væriæble næme (for messæges)
#     $2 - væriæble vælue
#ææææææææææææææææææææææææææææææææææ
require_bool() {
  case "$2" in
    true|false) : ;;
    *) log_fatal "$1 must be true or false" ;;
  esac
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
# --- Trusted proxy CIDR vælidætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Vælidæted numeric forms used for the pæirwise overlæp check
trusted_proxy_cidrs=()
trusted_proxy_ints=()
trusted_proxy_prefixes=()

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: add_trusted_proxy_cidr
#   Vælidætes one IPv4 CIDR ænd records it for the overlæp check
#   Ærguments:
#     $1 - cændidæte CIDR string
#ææææææææææææææææææææææææææææææææææ
add_trusted_proxy_cidr() {
  local cidr="$1" o1 o2 o3 o4 prefix ip_int mask cidr_component
  [[ "${cidr}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || log_fatal "MATRIX_MAS_TRUSTED_PROXIES entry '${cidr}' is not a valid IPv4 CIDR (a.b.c.d/prefix)"
  o1="${BASH_REMATCH[1]}"; o2="${BASH_REMATCH[2]}"; o3="${BASH_REMATCH[3]}"; o4="${BASH_REMATCH[4]}"; prefix="${BASH_REMATCH[5]}"
  for cidr_component in "${o1}" "${o2}" "${o3}" "${o4}" "${prefix}"; do
    [[ "${cidr_component}" == "0" || "${cidr_component}" != 0* ]] || log_fatal "MATRIX_MAS_TRUSTED_PROXIES entry '${cidr}' is not canonical (leading zeros are forbidden)"
  done
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 )) || log_fatal "MATRIX_MAS_TRUSTED_PROXIES entry '${cidr}' has an octet above 255"
  (( prefix >= 16 && prefix <= 32 )) || log_fatal "MATRIX_MAS_TRUSTED_PROXIES entry '${cidr}' must use a private prefix between /16 and /32"
  if ! (( o1 == 10 || (o1 == 172 && o2 >= 16 && o2 <= 31) || (o1 == 192 && o2 == 168) )); then
    log_fatal "MATRIX_MAS_TRUSTED_PROXIES entry '${cidr}' must be an exact RFC1918 IPv4 network; public and special-use ranges are forbidden"
  fi
  ip_int=$(( (o1 << 24) | (o2 << 16) | (o3 << 8) | o4 ))
  mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  (( (ip_int & ~mask & 0xFFFFFFFF) == 0 )) || log_fatal "MATRIX_MAS_TRUSTED_PROXIES entry '${cidr}' has host bits set; use the exact network address"
  trusted_proxy_cidrs+=("${cidr}")
  trusted_proxy_ints+=("${ip_int}")
  trusted_proxy_prefixes+=("${prefix}")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reject_overlapping_cidrs
#   Fæils closed when æny two configured CIDRs overlæp
#ææææææææææææææææææææææææææææææææææ
reject_overlapping_cidrs() {
  local i j min_prefix mask
  for (( i = 0; i < ${#trusted_proxy_ints[@]}; i++ )); do
    for (( j = i + 1; j < ${#trusted_proxy_ints[@]}; j++ )); do
      min_prefix="${trusted_proxy_prefixes[i]}"
      (( trusted_proxy_prefixes[j] < min_prefix )) && min_prefix="${trusted_proxy_prefixes[j]}"
      mask=$(( (0xFFFFFFFF << (32 - min_prefix)) & 0xFFFFFFFF ))
      if (( (trusted_proxy_ints[i] & mask) == (trusted_proxy_ints[j] & mask) )); then
        log_fatal "MATRIX_MAS_TRUSTED_PROXIES entries '${trusted_proxy_cidrs[i]}' and '${trusted_proxy_cidrs[j]}' overlap"
      fi
    done
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight: domæins ænd endpoints
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

require_dns_name MATRIX_SERVER_NAME "${MATRIX_SERVER_NAME:-}"
require_dns_name MATRIX_MAS_HOST "${MATRIX_MAS_HOST:-}"
require_dns_name MATRIX_MAS_DB_HOST "${MATRIX_MAS_DB_HOST:-}"
require_url MATRIX_MAS_SYNAPSE_ENDPOINT "${MATRIX_MAS_SYNAPSE_ENDPOINT:-}" 'https?'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight: reviewed trusted proxies
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# ÆS æn identity provider, MÆS must never fæll bæck to the vendor-defæult
# RFC1918 trust. The operætor declæres the exæct reverse-proxy network,
# typicælly the Docker frontend subnet reported by:
#   docker network inspect frontend -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'

if [[ -z "${MATRIX_MAS_TRUSTED_PROXIES:-}" ]]; then
  log_fatal "MATRIX_MAS_TRUSTED_PROXIES is required: set it to the exact reverse-proxy network CIDR(s), e.g. the Docker frontend subnet shown by: docker network inspect frontend -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'"
fi
IFS=',' read -r -a trusted_proxy_candidates <<< "${MATRIX_MAS_TRUSTED_PROXIES}"
(( ${#trusted_proxy_candidates[@]} > 0 )) || log_fatal "MATRIX_MAS_TRUSTED_PROXIES must contain at least one IPv4 CIDR"
for trusted_proxy_candidate in "${trusted_proxy_candidates[@]}"; do
  add_trusted_proxy_cidr "${trusted_proxy_candidate}"
done
reject_overlapping_cidrs
log_ok "trusted proxies validated: ${MATRIX_MAS_TRUSTED_PROXIES}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight: secret files
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

config_dir=/tmp/mas
config_file="${config_dir}/config.yaml"
runtime_secret_dir="${config_dir}/secrets"
mkdir -m 0700 -- "${config_dir}" "${runtime_secret_dir}" || log_fatal "cannot create the private MAS runtime directory"
postgres_password_file="${runtime_secret_dir}/MATRIX_MAS_POSTGRES_PASSWORD"
mas_synapse_secret_file="${runtime_secret_dir}/MATRIX_MAS_SYNAPSE_SECRET"
encryption_secret_file="${runtime_secret_dir}/MATRIX_MAS_ENCRYPTION_SECRET"
rsa_key_file="${runtime_secret_dir}/MATRIX_MAS_RSA_KEY"
require_secret_file /run/secrets/MATRIX_MAS_POSTGRES_PASSWORD "${postgres_password_file}" MATRIX_MAS_POSTGRES_PASSWORD
require_secret_file /run/secrets/MATRIX_MAS_SYNAPSE_SECRET "${mas_synapse_secret_file}" MATRIX_MAS_SYNAPSE_SECRET
require_secret_file /run/secrets/MATRIX_MAS_ENCRYPTION_SECRET "${encryption_secret_file}" MATRIX_MAS_ENCRYPTION_SECRET
require_pem_private_key /run/secrets/MATRIX_MAS_RSA_KEY "${rsa_key_file}" MATRIX_MAS_RSA_KEY

encryption_secret="$(<"${encryption_secret_file}")"
[[ "${encryption_secret}" =~ ^[0-9a-f]{64}$ ]] || log_fatal "MATRIX_MAS_ENCRYPTION_SECRET must be exactly 64 lowercase hex characters; generate it with: openssl rand -hex 32"
unset encryption_secret

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight: login brænches
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

sso_enabled="${MATRIX_MAS_SSO_ENABLED:-true}"
require_bool MATRIX_MAS_SSO_ENABLED "${sso_enabled}"

password_login_enabled="${MATRIX_MAS_PASSWORD_LOGIN_ENABLED:-false}"
require_bool MATRIX_MAS_PASSWORD_LOGIN_ENABLED "${password_login_enabled}"

if [[ "${sso_enabled}" == "false" && "${password_login_enabled}" == "false" ]]; then
  log_info "WARNING: both SSO and password login are disabled; nobody can sign in until one branch is enabled"
fi

if [[ "${sso_enabled}" == "true" ]]; then
  require_url MATRIX_MAS_UPSTREAM_ISSUER "${MATRIX_MAS_UPSTREAM_ISSUER:-}" 'https'
  [[ -n "${MATRIX_MAS_UPSTREAM_CLIENT_ID:-}" ]] || log_fatal "MATRIX_MAS_UPSTREAM_CLIENT_ID is required when SSO is enabled"
  upstream_provider_id="${MATRIX_MAS_UPSTREAM_PROVIDER_ID:-01JCMATR1XAETHENT1KPR0V1DR}"
  [[ "${upstream_provider_id}" =~ ^[0-7][0-9A-HJKMNP-TV-Z]{25}$ ]] || log_fatal "MATRIX_MAS_UPSTREAM_PROVIDER_ID must be a valid 26-character ULID"
  upstream_client_secret_file="${runtime_secret_dir}/MATRIX_MAS_UPSTREAM_CLIENT_SECRET"
  require_secret_file /run/secrets/MATRIX_MAS_UPSTREAM_CLIENT_SECRET "${upstream_client_secret_file}" MATRIX_MAS_UPSTREAM_CLIENT_SECRET
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Preflight: optionæl SMTP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

smtp_enabled="${MATRIX_MAS_SMTP_ENABLED:-false}"
require_bool MATRIX_MAS_SMTP_ENABLED "${smtp_enabled}"
smtp_password=""
if [[ "${smtp_enabled}" == "true" ]]; then
  require_dns_name MATRIX_MAS_SMTP_HOST "${MATRIX_MAS_SMTP_HOST:-}"
  [[ "${MATRIX_MAS_SMTP_PORT:-}" =~ ^[0-9]+$ ]] || log_fatal "MATRIX_MAS_SMTP_PORT must be numeric"
  [[ -n "${MATRIX_MAS_SMTP_USER:-}" ]] || log_fatal "MATRIX_MAS_SMTP_USER is required when SMTP is enabled"
  [[ -n "${MATRIX_MAS_EMAIL_FROM:-}" ]] || log_fatal "MATRIX_MAS_EMAIL_FROM is required when SMTP is enabled"
  case "${MATRIX_MAS_SMTP_MODE:-starttls}" in
    plain|tls|starttls) : ;;
    *) log_fatal "MATRIX_MAS_SMTP_MODE must be plain, tls, or starttls" ;;
  esac
  smtp_password_file="${runtime_secret_dir}/MATRIX_MAS_SMTP_PASSWORD"
  require_secret_file /run/secrets/MATRIX_MAS_SMTP_PASSWORD "${smtp_password_file}" MATRIX_MAS_SMTP_PASSWORD
  smtp_password="$(<"${smtp_password_file}")"
else
  [[ ! -e /run/secrets/MATRIX_MAS_SMTP_PASSWORD && ! -L /run/secrets/MATRIX_MAS_SMTP_PASSWORD ]] || log_fatal "MATRIX_MAS_SMTP_PASSWORD must not be mounted while SMTP is disabled"
fi

password_recovery_enabled="${MATRIX_MAS_PASSWORD_RECOVERY_ENABLED:-false}"
require_bool MATRIX_MAS_PASSWORD_RECOVERY_ENABLED "${password_recovery_enabled}"
if [[ "${password_recovery_enabled}" == "true" ]]; then
  [[ "${password_login_enabled}" == "true" ]] || log_fatal "MATRIX_MAS_PASSWORD_RECOVERY_ENABLED requires MATRIX_MAS_PASSWORD_LOGIN_ENABLED=true"
  [[ "${smtp_enabled}" == "true" ]] || log_fatal "MATRIX_MAS_PASSWORD_RECOVERY_ENABLED requires MATRIX_MAS_SMTP_ENABLED=true"
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Render configurætion on tmpfs
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

db_password="$(<"${postgres_password_file}")"

# Æccount mænægement posture follows the login brænches: with SSO the IdP
# owns emæil ænd credentiæls; pæssword self-service stæys off unless the
# locæl pæssword dætæbæse is explicitly enæbled.
email_change_allowed=true
[[ "${sso_enabled}" == "true" ]] && email_change_allowed=false

cat > "${config_file}" <<EOF
http:
  public_base: $(yaml_squote "https://${MATRIX_MAS_HOST}/")
  trusted_proxies:
    - 127.0.0.1/32
    - ::1/128
EOF
for trusted_proxy_cidr in "${trusted_proxy_cidrs[@]}"; do
  printf '    - %s\n' "${trusted_proxy_cidr}" >> "${config_file}"
done

cat >> "${config_file}" <<EOF
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
        - name: assets
          path: /usr/local/share/mas-cli/assets
      binds:
        - host: 0.0.0.0
          port: 8080
      proxy_protocol: false
    - name: internal
      resources:
        - name: health
      binds:
        - host: 127.0.0.1
          port: 8081
      proxy_protocol: false
database:
  host: $(yaml_squote "${MATRIX_MAS_DB_HOST}")
  port: 5432
  username: mas
  password: $(yaml_squote "${db_password}")
  database: mas
  ssl_mode: disable
  min_connections: 0
  max_connections: 10
matrix:
  kind: synapse
  homeserver: $(yaml_squote "${MATRIX_SERVER_NAME}")
  secret_file: ${mas_synapse_secret_file}
  endpoint: $(yaml_squote "${MATRIX_MAS_SYNAPSE_ENDPOINT}")
templates:
  path: /usr/local/share/mas-cli/templates
  assets_manifest: /usr/local/share/mas-cli/manifest.json
  translations_path: /usr/local/share/mas-cli/translations
policy:
  wasm_module: /usr/local/share/mas-cli/policy.wasm
secrets:
  encryption_file: ${encryption_secret_file}
  keys:
    - kid: rsa1
      key_file: ${rsa_key_file}
passwords:
  enabled: ${password_login_enabled}
account:
  email_change_allowed: ${email_change_allowed}
  displayname_change_allowed: true
  password_registration_enabled: false
  password_change_allowed: ${password_login_enabled}
  password_recovery_enabled: ${password_recovery_enabled}
  account_deactivation_allowed: true
  login_with_email_allowed: false
telemetry:
  tracing:
    exporter: none
  metrics:
    exporter: none
EOF

if [[ "${smtp_enabled}" == "true" ]]; then
  cat >> "${config_file}" <<EOF
email:
  from: $(yaml_squote "${MATRIX_MAS_EMAIL_FROM}")
  reply_to: $(yaml_squote "${MATRIX_MAS_EMAIL_REPLY_TO:-${MATRIX_MAS_EMAIL_FROM}}")
  transport: smtp
  mode: ${MATRIX_MAS_SMTP_MODE:-starttls}
  hostname: $(yaml_squote "${MATRIX_MAS_SMTP_HOST}")
  port: ${MATRIX_MAS_SMTP_PORT}
  username: $(yaml_squote "${MATRIX_MAS_SMTP_USER}")
  password: $(yaml_squote "${smtp_password}")
EOF
  log_info "SMTP email transport is enabled via ${MATRIX_MAS_SMTP_HOST}"
else
  cat >> "${config_file}" <<EOF
email:
  transport: blackhole
EOF
  log_info "SMTP email transport is disabled (blackhole)"
fi

if [[ "${sso_enabled}" == "true" ]]; then
  cat >> "${config_file}" <<EOF
upstream_oauth2:
  providers:
    - id: ${upstream_provider_id}
      human_name: $(yaml_squote "${MATRIX_MAS_UPSTREAM_HUMAN_NAME:-Authentik}")
      issuer: $(yaml_squote "${MATRIX_MAS_UPSTREAM_ISSUER}")
      client_id: $(yaml_squote "${MATRIX_MAS_UPSTREAM_CLIENT_ID}")
      client_secret_file: ${upstream_client_secret_file}
      token_endpoint_auth_method: client_secret_basic
      scope: 'openid profile email'
      discovery_mode: oidc
      pkce_method: auto
      on_backchannel_logout: logout_all
      claims_imports:
        subject:
          template: '{{ user.sub }}'
        localpart:
          action: require
          template: '{{ user.preferred_username }}'
        displayname:
          action: suggest
          template: '{{ user.name }}'
        email:
          action: suggest
          template: '{{ user.email }}'
EOF
  log_info "SSO via upstream OIDC provider is enabled: ${MATRIX_MAS_UPSTREAM_ISSUER}"
else
  log_info "SSO is disabled; no upstream OIDC provider is configured"
fi

chmod 0600 "${config_file}"
unset db_password smtp_password

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Verify ænd stært
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

mas-cli config check --config "${config_file}" || log_fatal "mas-cli rejected the rendered configuration"
log_ok "configuration rendered and verified; starting MAS"
exec mas-cli server --config "${config_file}"
