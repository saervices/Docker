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
readonly CERTS_DUMPER_CF_ZONE_ID="${TRAEFIK_CERTS_DUMPER_CF_ZONE_ID:-}"
readonly MAILCOW_TLSA_ENABLED="${TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_ENABLED:-true}"
readonly MAILCOW_TLSA_NAME="${TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_NAME:-_25._tcp.mail.it.xn--lb-1ia.de}"
readonly MAILCOW_TLSA_TTL="${TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_TTL:-300}"

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
# FUNCTION: cloudflare_get_tlsa_records
#   Lists Cloudflære TLSÆ records by exæct næme.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - TLSÆ record næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_tlsa_records() {
  local zone_id="$1"
  local record_name="$2"
  local token
  local response_file
  local http_status

  token="$(read_cloudflare_token)"
  response_file="$(mktemp /tmp/cloudflare-get-tlsa.XXXXXX)"

  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' --get \
    --header "Authorization: Bearer ${token}" \
    --data-urlencode "type=TLSA" \
    --data-urlencode "name=${record_name}" \
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
#   Builds Cloudflære TLSÆ JSON pæyloæd.
#   Ærguments:
#     $1 - TLSÆ record næme
#     $2 - TTL
#     $3 - TLSÆ certificæte hash
#ææææææææææææææææææææææææææææææææææ
build_tlsa_payload() {
  local record_name="$1"
  local ttl="$2"
  local certificate_hash="$3"

  jq -n \
    --arg name "$record_name" \
    --arg certificate "$certificate_hash" \
    --argjson ttl "$ttl" \
    '{
      type: "TLSA",
      name: $name,
      ttl: $ttl,
      data: {
        usage: 3,
        selector: 1,
        matching_type: 1,
        certificate: $certificate
      },
      comment: "Managed by traefik_certs-dumper mailcow hook"
    }'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: upsert_cloudflare_tlsa_record
#   Creætes or updætes the configured Cloudflære TLSÆ record.
#   Ærguments:
#     $1 - TLSÆ certificæte hash
#ææææææææææææææææææææææææææææææææææ
upsert_cloudflare_tlsa_record() {
  local certificate_hash="$1"
  local records_json
  local record_count
  local record_id
  local current_certificate
  local payload

  [ -n "$CERTS_DUMPER_CF_ZONE_ID" ] || log_error "TRAEFIK_CERTS_DUMPER_CF_ZONE_ID is required for TLSA updates"
  case "$MAILCOW_TLSA_TTL" in
    ''|*[!0-9]*) log_error "TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_TTL must be numeric: ${MAILCOW_TLSA_TTL}" ;;
  esac

  records_json="$(cloudflare_get_tlsa_records "$CERTS_DUMPER_CF_ZONE_ID" "$MAILCOW_TLSA_NAME")"
  record_count="$(printf '%s' "$records_json" | jq -r '.result | length')"
  payload="$(build_tlsa_payload "$MAILCOW_TLSA_NAME" "$MAILCOW_TLSA_TTL" "$certificate_hash")"

  case "$record_count" in
    0)
      log_info "Creating Cloudflare TLSA record ${MAILCOW_TLSA_NAME}..."
      cloudflare_write_record "POST" "${CERTS_DUMPER_CF_API_BASE}/zones/${CERTS_DUMPER_CF_ZONE_ID}/dns_records" "$payload"
      log_ok "Cloudflare TLSA record created: ${MAILCOW_TLSA_NAME}"
      ;;
    1)
      record_id="$(printf '%s' "$records_json" | jq -r '.result[0].id')"
      current_certificate="$(printf '%s' "$records_json" | jq -r '.result[0].data.certificate // ""' | tr '[:upper:]' '[:lower:]')"
      if [ -z "$current_certificate" ]; then
        current_certificate="$(printf '%s' "$records_json" | jq -r '.result[0].content // "" | split(" ") | .[3] // ""' | tr '[:upper:]' '[:lower:]')"
      fi

      if [ "$current_certificate" = "$certificate_hash" ]; then
        log_ok "Cloudflare TLSA record already current: ${MAILCOW_TLSA_NAME}"
        return 0
      fi

      log_info "Updating Cloudflare TLSA record ${MAILCOW_TLSA_NAME}..."
      cloudflare_write_record "PATCH" "${CERTS_DUMPER_CF_API_BASE}/zones/${CERTS_DUMPER_CF_ZONE_ID}/dns_records/${record_id}" "$payload"
      log_ok "Cloudflare TLSA record updated: ${MAILCOW_TLSA_NAME}"
      ;;
    *)
      log_error "Multiple Cloudflare TLSA records found for ${MAILCOW_TLSA_NAME}; refusing to update"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: update_mailcow_tlsa
#   Upserts the Mæilcow SMTP DÆNE TLSÆ record in Cloudflære.
#   Ærguments:
#     $1 - locæl certificæte pæth
#ææææææææææææææææææææææææææææææææææ
update_mailcow_tlsa() {
  local cert_path="$1"
  local certificate_hash

  case "$MAILCOW_TLSA_ENABLED" in
    true|TRUE|1|yes|YES|on|ON) ;;
    false|FALSE|0|no|NO|off|OFF)
      log_info "Mailcow TLSA update disabled."
      return 0
      ;;
    *)
      log_error "Invalid TRAEFIK_CERTS_DUMPER_MAILCOW_TLSA_ENABLED value: ${MAILCOW_TLSA_ENABLED}"
      ;;
  esac

  certificate_hash="$(calculate_tlsa_spki_sha256 "$cert_path")"
  log_info "Calculated Mailcow TLSA 3 1 1 hash for ${MAILCOW_TLSA_NAME}."
  upsert_cloudflare_tlsa_record "$certificate_hash"
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
