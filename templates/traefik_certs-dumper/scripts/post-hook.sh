#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

# Docker mounts compose secrets with permissive modes; OpenSSH rejects those for -i.
readonly CERTS_DUMPER_SSH_SECRET="/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD"
readonly CERTS_DUMPER_SSH_IDENTITY_FILE="/tmp/.ssh/certs_dumper_identity"
readonly CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE="${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE:-/state/known_hosts}"
readonly CERTS_DUMPER_DNS_TOKEN_FILE="${DNS_API_TOKEN_FILE:-/run/secrets/DNS_API_TOKEN}"
readonly CERTS_DUMPER_CF_TOKEN_FILE="$CERTS_DUMPER_DNS_TOKEN_FILE"
readonly CERTS_DUMPER_CF_API_BASE="${CLOUDFLARE_API_BASE:-https://api.cloudflare.com/client/v4}"
readonly CERTS_DUMPER_DESEC_API_BASE="${DESEC_API_BASE:-https://desec.io/api/v1}"
readonly CERTS_DUMPER_CERT_WAIT_SECONDS=60
readonly CERTS_DUMPER_LOCK_DIR="${CERTS_DUMPER_LOCK_DIR:-/run/certs-dumper}"
readonly CERTS_DUMPER_HOOK_LOCK="${CERTS_DUMPER_LOCK_DIR}/post-hook.lock"
readonly CERTS_DUMPER_DNSSEC_RESOLVER="${CERTS_DUMPER_DNSSEC_RESOLVER:-1.1.1.1}"
readonly MAILCOW_TLSA_PREFIX="_25._tcp."
MAILCOW_DNS_PROVIDER=""
MAILCOW_LOCK_HELD=0
MAILCOW_TRANSACTION_OK=0
MAILCOW_ROLLBACK_HOST=""
MAILCOW_ROLLBACK_USER=""
MAILCOW_ROLLBACK_CERT=""
MAILCOW_ROLLBACK_KEY=""
MAILCOW_ROLLBACK_SSH_KEY=""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Prints æn informætionæl messæge to stdout.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info()  { printf '[INFO]  %s\n' "$*"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Prints æ success messæge to stdout.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok()    { printf '[OK]    %s\n' "$*"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Prints æ wærning messæge to stderr.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn()  { printf '[WARN]  %s\n' "$*" >&2; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Prints æn error messæge to stderr ænd exits with code 1.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DEPENDENCY CHECK
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_dependencies
#   Verifies required runtime tools ære present in the imæge.
#   Ærguments:
#     $@ - dependency commænd næmes
#ææææææææææææææææææææææææææææææææææ
check_dependencies() {
  local dep

  for dep in "$@"; do
    command -v "$dep" >/dev/null 2>&1 || log_error "Required dependency missing: ${dep}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_ssh_directory
#   Prepæres tmpfs identity storæge. known_hosts must ælreædy be pinned
#   æt /state/known_hosts (not tmpfs, not accept-new).
#ææææææææææææææææææææææææææææææææææ
prepare_ssh_directory() {
  mkdir -p /tmp/.ssh
  [ ! -L "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" ] \
    || log_error "SSH known_hosts must not be æ symlink: ${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}"
  [ -f "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" ] && [ -s "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" ] \
    || log_error "Pinned SSH known_hosts is missing or empty: ${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_pinned_ssh
#   SSH to dest_user@dest_host with the pinned known_hosts file.
#   Ærguments:
#     $1 - SSH privæte key pæth
#     $2 - destinætion user
#     $3 - destinætion host
#     $4+ - remote commænd
#ææææææææææææææææææææææææææææææææææ
run_pinned_ssh() {
  local ssh_key="$1"
  local dest_user="$2"
  local dest_host="$3"
  shift 3

  ssh -i "$ssh_key" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" \
    "${dest_user}@${dest_host}" "$@"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_pinned_scp
#   scp with host-key pinning (no accept-new).
#   Ærguments:
#     $1 - SSH privæte key pæth
#     $2 - source pæth
#     $3 - destinætion spec
#ææææææææææææææææææææææææææææææææææ
run_pinned_scp() {
  local ssh_key="$1"
  local src_path="$2"
  local dest_spec="$3"

  scp -i "$ssh_key" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" \
    "$src_path" "$dest_spec"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_ssh_identity_from_secret
#   Copies the Docker secret to a tmpfs file with mode 600 so ssh/scp accept -i.
#ææææææææææææææææææææææææææææææææææ
prepare_ssh_identity_from_secret() {
  [ -r "$CERTS_DUMPER_SSH_SECRET" ] || log_error "SSH private key secret not readable: ${CERTS_DUMPER_SSH_SECRET}"
  cp -- "$CERTS_DUMPER_SSH_SECRET" "$CERTS_DUMPER_SSH_IDENTITY_FILE"
  chmod 600 -- "$CERTS_DUMPER_SSH_IDENTITY_FILE"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CLOUDFLÆRE TLSÆ
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_cloudflare_token
#   Reæds the Cloudflære DNS token from Docker secrets.
#ææææææææææææææææææææææææææææææææææ
read_cloudflare_token() {
  read_dns_api_token
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_dns_api_token
#   Reæds the shæred DNS-01 token from Docker secrets.
#ææææææææææææææææææææææææææææææææææ
read_dns_api_token() {
  local token

  [ -r "$CERTS_DUMPER_DNS_TOKEN_FILE" ] || log_error "DNS token secret not readable: ${CERTS_DUMPER_DNS_TOKEN_FILE}"
  token="$(tr -d '\r\n' < "$CERTS_DUMPER_DNS_TOKEN_FILE")"
  [ -n "$token" ] || log_error "DNS token secret is empty: ${CERTS_DUMPER_DNS_TOKEN_FILE}"
  [ "$token" != 'CHANGE_ME' ] || log_error "DNS token is still the inert CHANGE_ME plæceholder"
  printf '%s' "$token"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: derive_mailcow_dns_provider
#   Derives Cloudflære or deSEC from the production ÆCME-store bæsenæme.
#ææææææææææææææææææææææææææææææææææ
derive_mailcow_dns_provider() {
  case "${ACME_FILENAME:-}" in
    cloudflare-acme.json) MAILCOW_DNS_PROVIDER=cloudflare ;;
    desec-acme.json) MAILCOW_DNS_PROVIDER=desec ;;
    *) log_error "ACME_FILENAME must be cloudflare-acme.json or desec-acme.json when mailcow() is enabled" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_mailcow_lock
#   Prevents pærællel dumps. The supervisor lock is reused when present.
#ææææææææææææææææææææææææææææææææææ
acquire_mailcow_lock() {
  if [ "${CERTS_DUMPER_SUPERVISOR_LOCK:-}" = 1 ]; then
    MAILCOW_LOCK_HELD=0
    return 0
  fi
  mkdir -p "$CERTS_DUMPER_LOCK_DIR" || log_error "Could not creæte dump lock directory"
  if ! mkdir "$CERTS_DUMPER_HOOK_LOCK" 2>/dev/null; then
    log_error "Another dump or post-hook is ælreædy running"
  fi
  MAILCOW_LOCK_HELD=1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: release_mailcow_lock
#   Drops the hook lock when this script created it.
#ææææææææææææææææææææææææææææææææææ
release_mailcow_lock() {
  if [ "$MAILCOW_LOCK_HELD" = 1 ]; then
    rmdir "$CERTS_DUMPER_HOOK_LOCK" 2>/dev/null || true
    MAILCOW_LOCK_HELD=0
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_zone_dnssec
#   Requires the DNSSEC ÆD bit for the zone SOA æt æ vælidæting resolver.
#   Ærguments:
#     $1 - DNS zone næme
#ææææææææææææææææææææææææææææææææææ
require_zone_dnssec() {
  local zone_name="$1"
  local dig_output

  command -v dig >/dev/null 2>&1 || log_error "dig is required to vælidæte DNSSEC before TLSÆ writes"
  if ! dig_output="$(dig +tcp +dnssec +noall +comments SOA "$zone_name" "@${CERTS_DUMPER_DNSSEC_RESOLVER}")"; then
    log_error "DNSSEC SOA lookup fæiled for zone ${zone_name}"
  fi
  printf '%s\n' "$dig_output" | grep -Eq 'flags:.*[ 	]ad[; ]' \
    || log_error "DNSSEC ÆD bit is not set for zone ${zone_name}; refusing to write TLSÆ"
  log_ok "DNSSEC is visæble for zone ${zone_name}."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_dns_name
#   Lowercases æ DNS næme ænd removes æ træiling dot.
#   Ærguments:
#     $1 - DNS næme
#ææææææææææææææææææææææææææææææææææ
normalize_dns_name() {
  local dns_name="$1"

  dns_name="${dns_name%.}"
  printf '%s' "$dns_name" | tr '[:upper:]' '[:lower:]'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_mailcow_tlsa_record
#   Selects the existing Mæilcow SMTP DÆNE TLSÆ record from Cloudflære.
#   Ærguments:
#     $1 - Cloudflære TLSÆ records response JSON
#ææææææææææææææææææææææææææææææææææ
select_mailcow_tlsa_record() {
  local records_json="$1"
  local matching_records_json
  local record_count

  matching_records_json="$(printf '%s' "$records_json" | jq -c --arg prefix "$MAILCOW_TLSA_PREFIX" \
    '.result | map(select((.name | ascii_downcase) | startswith($prefix)))')"
  record_count="$(printf '%s' "$matching_records_json" | jq -r 'length')"

  case "$record_count" in
    0)
      log_error "Existing Mailcow Cloudflare TLSA record not found; expected exactly one record starting with ${MAILCOW_TLSA_PREFIX}"
      ;;
    1)
      printf '%s' "$matching_records_json" | jq -c '.[0]'
      ;;
    *)
      log_error "Multiple Cloudflare TLSA records starting with ${MAILCOW_TLSA_PREFIX} found; refusing to guess"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: calculate_tlsa_spki_sha256
#   Cælculætes TLSÆ 3 1 1 SPKI SHÆ-256 hash from æ certificæte.
#   Ærguments:
#     $1 - locæl certificæte pæth
#ææææææææææææææææææææææææææææææææææ
calculate_tlsa_spki_sha256() {
  local cert_path="$1"

  [ -r "$cert_path" ] || log_error "Certificate not readable for TLSA hash: ${cert_path}"
  openssl x509 -in "$cert_path" -noout -pubkey \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_check_response
#   Vælidætes Cloudflære HTTP ænd JSON response content.
#   Ærguments:
#     $1 - HTTP method
#     $2 - HTTP stætus code
#     $3 - response body pæth
#ææææææææææææææææææææææææææææææææææ
cloudflare_check_response() {
  local method="$1"
  local http_status="$2"
  local response_file="$3"
  local error_message

  case "$http_status" in
    2*) ;;
    *)
      log_error "Cloudflare API ${method} HTTP ${http_status}: $(cat "$response_file")"
      ;;
  esac

  if ! jq -e '.success == true' "$response_file" >/dev/null; then
    error_message="$(jq -r '[.errors[]?.message] | join("; ")' "$response_file")"
    [ -n "$error_message" ] || error_message="$(cat "$response_file")"
    log_error "Cloudflare API ${method} failed: ${error_message}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_zones_by_name
#   Lists Cloudflære zones mætching æ domain næme.
#   Ærguments:
#     $1 - zone næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_zones_by_name() {
  local zone_name="$1"
  local token
  local response_file
  local http_status

  token="$(read_cloudflare_token)"
  response_file="$(mktemp /tmp/cloudflare-get-zone.XXXXXX)"

  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' --get \
    --header "Authorization: Bearer ${token}" \
    --data-urlencode "name=${zone_name}" \
    --data-urlencode "per_page=50" \
    "${CERTS_DUMPER_CF_API_BASE}/zones")"; then
    log_error "Cloudflare API zone lookup failed: $(cat "$response_file" 2>/dev/null || true)"
  fi

  cloudflare_check_response "GET zones" "$http_status" "$response_file"
  cat "$response_file"
  rm -f "$response_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_find_zone_id
#   Resolves the Cloudflære zone ID from TRÆEFIK_DOMÆIN.
#   Ærguments:
#     $1 - zone næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_find_zone_id() {
  local zone_name="$1"
  local zones_json
  local zone_count

  zones_json="$(cloudflare_get_zones_by_name "$zone_name")"
  zone_count="$(printf '%s' "$zones_json" | jq -r '.result | length')"

  case "$zone_count" in
    1)
      printf '%s' "$zones_json" | jq -r '.result[0].id'
      ;;
    0)
      log_error "Cloudflare zone not found for TRAEFIK_DOMAIN=${zone_name}"
      ;;
    *)
      log_error "Multiple Cloudflare zones found for TRAEFIK_DOMAIN=${zone_name}; refusing to guess"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_tlsa_records
#   Lists Cloudflære TLSÆ records in æ zone.
#   Ærguments:
#     $1 - Cloudflære zone ID
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_tlsa_records() {
  local zone_id="$1"
  local token
  local response_file
  local http_status

  token="$(read_cloudflare_token)"
  response_file="$(mktemp /tmp/cloudflare-get-tlsa.XXXXXX)"

  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' --get \
    --header "Authorization: Bearer ${token}" \
    --data-urlencode "type=TLSA" \
    --data-urlencode "per_page=5000000" \
    "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records")"; then
    log_error "Cloudflare API GET failed: $(cat "$response_file" 2>/dev/null || true)"
  fi

  cloudflare_check_response "GET" "$http_status" "$response_file"
  cat "$response_file"
  rm -f "$response_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_write_record
#   Creætes or updætes æ Cloudflære DNS record.
#   Ærguments:
#     $1 - HTTP method (POST or PATCH)
#     $2 - request URL
#     $3 - JSON pæyloæd
#ææææææææææææææææææææææææææææææææææ
cloudflare_write_record() {
  local method="$1"
  local url="$2"
  local payload="$3"
  local token
  local response_file
  local http_status

  token="$(read_cloudflare_token)"
  response_file="$(mktemp /tmp/cloudflare-write-tlsa.XXXXXX)"

  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
    --request "$method" \
    --header "Authorization: Bearer ${token}" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    "$url")"; then
    log_error "Cloudflare API ${method} failed: $(cat "$response_file" 2>/dev/null || true)"
  fi

  cloudflare_check_response "$method" "$http_status" "$response_file"
  rm -f "$response_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_tlsa_payload
#   Builds Cloudflære TLSÆ JSON pæyloæd from æn existing record.
#   Ærguments:
#     $1 - existing TLSÆ record JSON
#     $2 - TLSÆ certificæte hash
#ææææææææææææææææææææææææææææææææææ
build_tlsa_payload() {
  local record_json="$1"
  local certificate_hash="$2"

  printf '%s' "$record_json" | jq \
    --arg certificate "$certificate_hash" \
    '{
      type: "TLSA",
      name: .name,
      ttl: (.ttl // 1),
      data: {
        usage: (.data.usage // ((.content // "" | split(" ") | .[0] // "" | tonumber?) // 3)),
        selector: (.data.selector // ((.content // "" | split(" ") | .[1] // "" | tonumber?) // 1)),
        matching_type: (.data.matching_type // ((.content // "" | split(" ") | .[2] // "" | tonumber?) // 1)),
        certificate: $certificate
      }
    }'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: update_existing_cloudflare_tlsa_record
#   Updætes the existing Mæilcow Cloudflære TLSÆ record.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - TLSÆ certificæte hash
#ææææææææææææææææææææææææææææææææææ
update_existing_cloudflare_tlsa_record() {
  local zone_id="$1"
  local certificate_hash="$2"
  local records_json
  local record_json
  local record_id
  local record_name
  local current_certificate
  local payload

  records_json="$(cloudflare_get_tlsa_records "$zone_id")"
  record_json="$(select_mailcow_tlsa_record "$records_json")"
  record_id="$(printf '%s' "$record_json" | jq -r '.id')"
  record_name="$(printf '%s' "$record_json" | jq -r '.name')"
  current_certificate="$(printf '%s' "$record_json" | jq -r '.data.certificate // ""' | tr '[:upper:]' '[:lower:]')"
  if [ -z "$current_certificate" ]; then
    current_certificate="$(printf '%s' "$record_json" | jq -r '.content // "" | split(" ") | .[3] // ""' | tr '[:upper:]' '[:lower:]')"
  fi

  if [ "$current_certificate" = "$certificate_hash" ]; then
    log_ok "Cloudflare TLSA record already current: ${record_name}"
    return 0
  fi

  payload="$(build_tlsa_payload "$record_json" "$certificate_hash")"
  log_info "Updating Cloudflare TLSA record ${record_name}..."
  cloudflare_write_record "PATCH" "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records/${record_id}" "$payload"
  log_ok "Cloudflare TLSA record updated: ${record_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: update_mailcow_tlsa
#   Updætes the existing Mæilcow SMTP DÆNE TLSÆ record viæ CERTRESOLVER.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - DNS zone næme (hærdcoded in mailcow())
#     $3 - SMTP hostnæme (hærdcoded in mailcow())
#ææææææææææææææææææææææææææææææææææ
update_mailcow_tlsa() {
  local cert_path="$1"
  local zone_name="$2"
  local smtp_host="$3"
  local zone_id
  local certificate_hash
  local record_name

  [ -n "$zone_name" ] || log_error "DNS zone is required for Mailcow TLSA updates"
  [ -n "$smtp_host" ] || log_error "SMTP hostnæme is required for Mailcow TLSA updates"
  zone_name="$(normalize_dns_name "$zone_name")"
  smtp_host="$(normalize_dns_name "$smtp_host")"
  record_name="${MAILCOW_TLSA_PREFIX}${smtp_host}"
  derive_mailcow_dns_provider
  require_zone_dnssec "$zone_name"
  certificate_hash="$(calculate_tlsa_spki_sha256 "$cert_path")"
  log_info "Calculated Mailcow TLSA SPKI-SHA256 hash."

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare)
      zone_id="$(cloudflare_find_zone_id "$zone_name")"
      update_existing_cloudflare_tlsa_record "$zone_id" "$certificate_hash"
      ;;
    desec)
      update_existing_desec_tlsa_record "$zone_name" "$record_name" "$certificate_hash"
      ;;
    *)
      log_error "Unsupported Mailcow DNS provider: ${MAILCOW_DNS_PROVIDER}"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_tlsa_subname
#   Derives the deSEC RRset subnæme from the TLSÆ owner ænd zone.
#   Ærguments:
#     $1 - TLSÆ owner
#     $2 - DNS zone næme
#ææææææææææææææææææææææææææææææææææ
desec_tlsa_subname() {
  local record_name="$1"
  local zone_name="$2"

  case "$record_name" in
    *."$zone_name") printf '%s' "${record_name%.${zone_name}}" ;;
    *) log_error "Mailcow TLSA owner is not under the configured deSEC zone ${zone_name}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: update_existing_desec_tlsa_record
#   Updætes the existing Mæilcow deSEC TLSÆ RRset; does not creæte records.
#   Ærguments:
#     $1 - DNS zone næme
#     $2 - TLSÆ owner
#     $3 - TLSÆ certificæte hash
#ææææææææææææææææææææææææææææææææææ
update_existing_desec_tlsa_record() {
  local zone_name="$1"
  local record_name="$2"
  local certificate_hash="$3"
  local subname
  local token
  local response_file
  local http_status
  local current_records
  local ttl
  local payload

  subname="$(desec_tlsa_subname "$record_name" "$zone_name")"
  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/desec-get-tlsa.XXXXXX)"

  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
    --header "Authorization: Token ${token}" \
    "${CERTS_DUMPER_DESEC_API_BASE}/domains/${zone_name}/rrsets/${subname}/TLSA/")"; then
    log_error "deSEC API TLSA lookup failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  case "$http_status" in
    200) ;;
    404) log_error "Existing Mailcow deSEC TLSA RRset not found: ${record_name}" ;;
    *) log_error "deSEC API GET TLSA HTTP ${http_status}: $(cat "$response_file")" ;;
  esac

  ttl="$(jq -r '.ttl // 3600' "$response_file")"
  current_records="$(jq -r '.records // [] | map(ascii_downcase) | join("\n")' "$response_file")"
  if printf '%s\n' "$current_records" | grep -qi "3 1 1 ${certificate_hash}"; then
    log_ok "deSEC TLSA record already current: ${record_name}"
    rm -f "$response_file"
    return 0
  fi

  payload="$(jq -nc --arg subname "$subname" --arg ttl "$ttl" --arg hash "$certificate_hash" \
    '{subname: $subname, type: "TLSA", ttl: ($ttl | tonumber), records: ["3 1 1 " + $hash]}')"
  log_info "Updating deSEC TLSA record ${record_name}..."
  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
    --request PUT \
    --header "Authorization: Token ${token}" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    "${CERTS_DUMPER_DESEC_API_BASE}/domains/${zone_name}/rrsets/${subname}/TLSA/")"; then
    log_error "deSEC API TLSA update failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  case "$http_status" in
    2*) ;;
    *) log_error "deSEC API PUT TLSA HTTP ${http_status}: $(cat "$response_file")" ;;
  esac
  rm -f "$response_file"
  log_ok "deSEC TLSA record updated: ${record_name}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTIFICÆTE FILES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_certificate_files
#   Wæits until the dumped certificæte/key files exist ænd ære non-empty.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#ææææææææææææææææææææææææææææææææææ
wait_for_certificate_files() {
  local cert_path="$1"
  local key_path="$2"
  local waited=0

  while [ "$waited" -lt "$CERTS_DUMPER_CERT_WAIT_SECONDS" ]; do
    if [ -s "$cert_path" ] && [ -s "$key_path" ]; then
      return 0
    fi

    if [ "$waited" -eq 0 ]; then
      log_info "Waiting for dumped certificate files..."
    fi

    sleep 1
    waited=$((waited + 1))
  done

  log_error "Dumped certificate files not ready after ${CERTS_DUMPER_CERT_WAIT_SECONDS}s: ${cert_path}, ${key_path}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTIFICÆTE COPY
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_certificates
#   Stæges the pæir beside the live files, keeps one `.bak` backup, then æctivætes.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote certificæte pæth
#     $6 - remote key pæth
#     $7 - SSH privæte key pæth
#ææææææææææææææææææææææææææææææææææ
copy_certificates() {
  local src_cert="$1"
  local src_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local dest_cert_path="$5"
  local dest_key_path="$6"
  local ssh_key="$7"

  log_info "Stæging certs to ${dest_user}@${dest_host}..."

  if ! run_pinned_ssh "$ssh_key" "$dest_user" "$dest_host" \
    "set -eu; umask 077; cp -p -- '${dest_cert_path}' '${dest_cert_path}.bak'; cp -p -- '${dest_key_path}' '${dest_key_path}.bak'"; then
    log_error "Failed to backup live certificates on ${dest_host}"
  fi
  MAILCOW_ROLLBACK_HOST="$dest_host"
  MAILCOW_ROLLBACK_USER="$dest_user"
  MAILCOW_ROLLBACK_CERT="$dest_cert_path"
  MAILCOW_ROLLBACK_KEY="$dest_key_path"
  MAILCOW_ROLLBACK_SSH_KEY="$ssh_key"
  if ! run_pinned_scp "$ssh_key" "$src_cert" "${dest_user}@${dest_host}:${dest_cert_path}.staging"; then
    log_error "Failed to stage certificate to ${dest_host}:${dest_cert_path}.staging"
  fi
  if ! run_pinned_scp "$ssh_key" "$src_key" "${dest_user}@${dest_host}:${dest_key_path}.staging"; then
    log_error "Failed to stage key to ${dest_host}:${dest_key_path}.staging"
  fi
  if ! run_pinned_ssh "$ssh_key" "$dest_user" "$dest_host" \
    "set -eu; umask 077; mv -f -- '${dest_cert_path}.staging' '${dest_cert_path}'; mv -f -- '${dest_key_path}.staging' '${dest_key_path}'"; then
    log_error "Failed to activate staged certificates on ${dest_host}"
  fi

  log_ok "Certificates copied to ${dest_user}@${dest_host}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_remote_certificates
#   Restores the `.bak` pæir if copy/TLSÆ/restært died mid-way.
#ææææææææææææææææææææææææææææææææææ
rollback_remote_certificates() {
  [ -n "$MAILCOW_ROLLBACK_HOST" ] || return 0
  log_warn "Rolling back Mailcow certificætes on ${MAILCOW_ROLLBACK_HOST}..."
  run_pinned_ssh "$MAILCOW_ROLLBACK_SSH_KEY" "$MAILCOW_ROLLBACK_USER" "$MAILCOW_ROLLBACK_HOST" \
    "set -eu; mv -f -- '${MAILCOW_ROLLBACK_CERT}.bak' '${MAILCOW_ROLLBACK_CERT}'; mv -f -- '${MAILCOW_ROLLBACK_KEY}.bak' '${MAILCOW_ROLLBACK_KEY}'" \
    || log_warn "Mailcow certificæte rollback fæiled on ${MAILCOW_ROLLBACK_HOST}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_cleanup
#   Rollbæck on fæilure, then drop the hook lock.
#ææææææææææææææææææææææææææææææææææ
mailcow_cleanup() {
  if [ "${MAILCOW_TRANSACTION_OK:-0}" != 1 ]; then
    rollback_remote_certificates
  fi
  release_mailcow_lock
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REMOTE SERVICE RESTÆRT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restart_remote_docker_compose
#   Restærts æ Docker Compose project on æ remote host viæ ssh.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote project pæth
#     $4 - SSH privæte key pæth
#     $5+ - optionæl: service næmes (e.g. postfix-mailcow); if omitted, restærts æll services.
#ææææææææææææææææææææææææææææææææææ
restart_remote_docker_compose() {
  local dest_host="$1"
  local dest_user="$2"
  local remote_project_path="$3"
  local ssh_key="$4"
  shift 4
  local remote_cmd

  if [ "$#" -gt 0 ]; then
    log_info "Restarting Docker Compose services ($*) at ${remote_project_path} on ${dest_host}..."
    remote_cmd="docker compose restart $*"
  else
    log_info "Restarting Docker Compose at ${remote_project_path} on ${dest_host}..."
    remote_cmd="docker compose restart"
  fi

  if ! run_pinned_ssh "$ssh_key" "$dest_user" "$dest_host" \
    "cd \"${remote_project_path}\" && ${remote_cmd}"; then
    log_error "Failed to restart Docker Compose on ${dest_host}:${remote_project_path}"
  fi

  if [ "$#" -gt 0 ]; then
    log_ok "Docker Compose services ($*) restarted on ${dest_host}"
  else
    log_ok "Docker Compose restarted on ${dest_host}"
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXÆMPLE USÆGE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mæilcow
#   Copies renewed certificætes to æ Mailcow host ænd restærts TLS services only
#   (postfix, dovecot, nginx) per Mailcow docs for externæl certificætes.
#   Host, user (`certdeploy`), zone, ænd SMTP hostnæme stæy hærdcoded in this function.
#ææææææææææææææææææææææææææææææææææ
mailcow() {
  local ssh_key="$CERTS_DUMPER_SSH_IDENTITY_FILE"
  local dest_host="192.168.20.120"
  local dest_user="certdeploy"
  local dns_zone="xn--lb-1ia.de"
  local smtp_host="mailcow.prd.xn--lb-1ia.de"
  local project_path="/opt/mailcow-dockerized"
  local local_cert="/data/files/mailcow.prd.xn--lb-1ia.de/certificate.pem"
  local local_key="/data/files/mailcow.prd.xn--lb-1ia.de/privatekey.pem"
  local remote_cert="${project_path}/data/assets/ssl/cert.pem"
  local remote_key="${project_path}/data/assets/ssl/key.pem"

  MAILCOW_TRANSACTION_OK=0
  acquire_mailcow_lock
  trap mailcow_cleanup EXIT

  check_dependencies scp ssh curl jq openssl od dig
  prepare_ssh_directory
  prepare_ssh_identity_from_secret
  wait_for_certificate_files "$local_cert" "$local_key"
  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  update_mailcow_tlsa "$local_cert" "$dns_zone" "$smtp_host"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
    postfix-mailcow dovecot-mailcow nginx-mailcow
  MAILCOW_TRANSACTION_OK=1
  trap - EXIT
  mailcow_cleanup
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: example_other_service
#   Templæte function for ædditionæl destinætions.
#   Clone ænd ædæpt for eæch remote host.
#ææææææææææææææææææææææææææææææææææ
example_other_service() {
  local ssh_key="$CERTS_DUMPER_SSH_IDENTITY_FILE"
  local dest_host="192.168.20.121"
  local dest_user="root"
  local project_path="/opt/other-service"
  local local_cert="/data/files/other.domain.tld/certificate.pem"
  local local_key="/data/files/other.domain.tld/privatekey.pem"
  local remote_cert="${project_path}/certs/cert.pem"
  local remote_key="${project_path}/certs/key.pem"

  check_dependencies scp ssh
  prepare_ssh_directory
  prepare_ssh_identity_from_secret
  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# PEM dump does not need SSH or the DNS token. Prepære them only inside
# æn ænæbled remæte tærget (Mæilcow or similær).
# if true; then mailcow; fi
log_ok "All post-hook tasks completed."
