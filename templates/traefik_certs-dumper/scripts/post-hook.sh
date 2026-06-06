#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

# Docker mounts compose secrets with permissive modes; OpenSSH rejects those for -i.
readonly CERTS_DUMPER_SSH_SECRET="/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD"
readonly CERTS_DUMPER_SSH_IDENTITY_FILE="/tmp/.ssh/certs_dumper_identity"
readonly CERTS_DUMPER_CF_TOKEN_FILE="${CF_DNS_API_TOKEN_FILE:-/run/secrets/CF_DNS_API_TOKEN}"
readonly CERTS_DUMPER_CF_API_BASE="${CLOUDFLARE_API_BASE:-https://api.cloudflare.com/client/v4}"
readonly TRAEFIK_DOMAIN_NAME="${TRAEFIK_DOMAIN:-}"
readonly MAILCOW_TLSA_PREFIX="_25._tcp.mail"

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
#   Creætes /tmp/.ssh with known_hosts on tmpfs.
#ææææææææææææææææææææææææææææææææææ
prepare_ssh_directory() {
  mkdir -p /tmp/.ssh
  touch /tmp/.ssh/known_hosts
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
  local token

  [ -r "$CERTS_DUMPER_CF_TOKEN_FILE" ] || log_error "Cloudflare token secret not readable: ${CERTS_DUMPER_CF_TOKEN_FILE}"
  token="$(tr -d '\r\n' < "$CERTS_DUMPER_CF_TOKEN_FILE")"
  [ -n "$token" ] || log_error "Cloudflare token secret is empty: ${CERTS_DUMPER_CF_TOKEN_FILE}"
  printf '%s' "$token"
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
# FUNCTION: build_mailcow_tlsa_name
#   Builds the Mailcow SMTP DÆNE TLSÆ record næme from TRÆEFIK_DOMÆIN.
#   Ærguments:
#     $1 - normalized Træefik domain
#ææææææææææææææææææææææææææææææææææ
build_mailcow_tlsa_name() {
  local zone_name="$1"

  printf '%s.%s' "$MAILCOW_TLSA_PREFIX" "$zone_name"
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
#     $2 - TLSÆ record næme
#     $3 - TLSÆ certificæte hash
#ææææææææææææææææææææææææææææææææææ
update_existing_cloudflare_tlsa_record() {
  local zone_id="$1"
  local record_name="$2"
  local certificate_hash="$3"
  local records_json
  local matching_records_json
  local record_json
  local record_count
  local record_id
  local current_certificate
  local payload

  records_json="$(cloudflare_get_tlsa_records "$zone_id")"
  matching_records_json="$(printf '%s' "$records_json" | jq -c --arg name "$record_name" \
    '.result | map(select((.name | ascii_downcase) == ($name | ascii_downcase)))')"
  record_count="$(printf '%s' "$matching_records_json" | jq -r 'length')"

  case "$record_count" in
    0)
      log_error "Existing Cloudflare TLSA record not found: ${record_name}"
      ;;
    1)
      record_json="$(printf '%s' "$matching_records_json" | jq -c '.[0]')"
      record_id="$(printf '%s' "$record_json" | jq -r '.id')"
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
      ;;
    *)
      log_error "Multiple Cloudflare TLSA records found for ${record_name}; refusing to update"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: update_mailcow_tlsa
#   Updætes the existing Mæilcow SMTP DÆNE TLSÆ record in Cloudflære.
#   Ærguments:
#     $1 - locæl certificæte pæth
#ææææææææææææææææææææææææææææææææææ
update_mailcow_tlsa() {
  local cert_path="$1"
  local zone_name
  local zone_id
  local record_name
  local certificate_hash

  [ -n "$TRAEFIK_DOMAIN_NAME" ] || log_error "TRAEFIK_DOMAIN is required for Mailcow TLSA updates"

  zone_name="$(normalize_dns_name "$TRAEFIK_DOMAIN_NAME")"
  record_name="$(build_mailcow_tlsa_name "$zone_name")"
  zone_id="$(cloudflare_find_zone_id "$zone_name")"
  certificate_hash="$(calculate_tlsa_spki_sha256 "$cert_path")"
  log_info "Calculated Mailcow TLSA SPKI-SHA256 hash for ${record_name}."
  update_existing_cloudflare_tlsa_record "$zone_id" "$record_name" "$certificate_hash"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTIFICÆTE COPY
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_certificates
#   Copies æ certificæte/key pæir to æ remote host viæ scp.
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

  log_info "Copying certs to ${dest_user}@${dest_host}..."

  if ! scp -i "$ssh_key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/.ssh/known_hosts \
    "$src_cert" "${dest_user}@${dest_host}:${dest_cert_path}"; then
    log_error "Failed to copy certificate to ${dest_host}:${dest_cert_path}"
  fi
  if ! scp -i "$ssh_key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/.ssh/known_hosts \
    "$src_key" "${dest_user}@${dest_host}:${dest_key_path}"; then
    log_error "Failed to copy key to ${dest_host}:${dest_key_path}"
  fi

  log_ok "Certificates copied to ${dest_user}@${dest_host}"
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

  if ! ssh -i "$ssh_key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/.ssh/known_hosts \
    "${dest_user}@${dest_host}" "cd \"${remote_project_path}\" && ${remote_cmd}"; then
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
#ææææææææææææææææææææææææææææææææææ
mailcow() {
  local ssh_key="$CERTS_DUMPER_SSH_IDENTITY_FILE"
  local dest_host="192.168.20.120"
  local dest_user="root"
  local project_path="/opt/mailcow-dockerized"
  local local_cert="/data/files/mailcow.prd.xn--lb-1ia.de/certificate.pem"
  local local_key="/data/files/mailcow.prd.xn--lb-1ia.de/privatekey.pem"
  local remote_cert="${project_path}/data/assets/ssl/cert.pem"
  local remote_key="${project_path}/data/assets/ssl/key.pem"

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  update_mailcow_tlsa "$local_cert"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
    postfix-mailcow dovecot-mailcow nginx-mailcow
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

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

check_dependencies scp ssh curl jq openssl od
prepare_ssh_directory
prepare_ssh_identity_from_secret
mailcow
log_ok "All post-hook tasks completed."
