#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

# Docker mounts compose secrets with permissive modes; OpenSSH rejects those for -i.
readonly CERTS_DUMPER_SSH_SECRET="/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD"
readonly CERTS_DUMPER_SSH_IDENTITY_FILE="/tmp/.ssh/certs_dumper_identity"
readonly CERTS_DUMPER_SSH_STATE_ROOT="/state"
readonly CERTS_DUMPER_SSH_STATE_DIR="${CERTS_DUMPER_SSH_STATE_ROOT}/.ssh"
readonly CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE="${CERTS_DUMPER_SSH_STATE_DIR}/known_hosts"
readonly CERTS_DUMPER_MAILCOW_LOCK_FILE="${CERTS_DUMPER_SSH_STATE_ROOT}/mailcow-rollover.lock"
readonly CERTS_DUMPER_CF_TOKEN_FILE="${CF_DNS_API_TOKEN_FILE:-/run/secrets/CF_DNS_API_TOKEN}"
readonly CERTS_DUMPER_CF_API_BASE="${CLOUDFLARE_API_BASE:-https://api.cloudflare.com/client/v4}"
readonly CERTS_DUMPER_CERT_WAIT_SECONDS=60
readonly CERTS_DUMPER_DNS_POLL_SECONDS=5
readonly CERTS_DUMPER_SMTP_WAIT_SECONDS=60
readonly CERTS_DUMPER_SMTP_POLL_SECONDS=5
readonly CERTS_DUMPER_SMTP_ATTEMPT_SECONDS=5
readonly MAILCOW_SMTP_HOSTNAME_INPUT="${MAILCOW_SMTP_HOSTNAME:-}"
readonly MAILCOW_CLOUDFLARE_ZONE_INPUT="${MAILCOW_CLOUDFLARE_ZONE:-}"
readonly MAILCOW_DANE_TTL_SECONDS_INPUT="${MAILCOW_DANE_TTL_SECONDS:-300}"
readonly MAILCOW_DANE_TTL_SAFETY_SECONDS_INPUT="${MAILCOW_DANE_TTL_SAFETY_SECONDS:-60}"
readonly MAILCOW_DANE_VALIDATING_RESOLVER_INPUT="${MAILCOW_DANE_VALIDATING_RESOLVER:-1.1.1.1}"
MAILCOW_CERT_MAIN_DOMAIN=''
MAILCOW_SMTP_HOSTNAME=''
MAILCOW_CLOUDFLARE_ZONE_NAME=''
MAILCOW_TLSA_RECORD_NAME=''
MAILCOW_DANE_TTL_SECONDS=''
MAILCOW_DANE_TTL_SAFETY_SECONDS=''
MAILCOW_DANE_VALIDATING_RESOLVER=''
MAILCOW_ROLLBACK_ARMED=false
MAILCOW_ROLLBACK_DEST_HOST=''
MAILCOW_ROLLBACK_DEST_USER=''
MAILCOW_ROLLBACK_PROJECT_PATH=''
MAILCOW_ROLLBACK_SSH_KEY=''
MAILCOW_ROLLBACK_TRANSACTION_ID=''
MAILCOW_ROLLBACK_EXPECTED_SPKI=''
MAILCOW_ROLLBACK_EXPECTED_LEAF=''

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
# FUNCTION: harden_directory_no_follow
#   Creætes or pins one reæl directory ænd enforces owner-only mode viæ its descriptor.
#   Ærguments:
#     $1 - directory pæth
#ææææææææææææææææææææææææææææææææææ
harden_directory_no_follow() {
  local directory_path="$1"
  local descriptor_identity
  local path_identity

  if [ ! -e "$directory_path" ] && [ ! -L "$directory_path" ]; then
    mkdir -m 0700 -- "$directory_path" || log_error "Could not create SSH directory: ${directory_path}"
  fi
  [ ! -L "$directory_path" ] && [ -d "$directory_path" ] || log_error "SSH directory must be a real directory, never a symlink or special node: ${directory_path}"
  if ! { exec 9<"$directory_path"; }; then
    log_error "Could not open SSH directory without mutation: ${directory_path}"
  fi
  [ ! -L "$directory_path" ] && [ -d "$directory_path" ] || log_error "SSH directory must be a real directory, never a symlink or special node: ${directory_path}"
  path_identity="$(stat -c '%d:%i' -- "$directory_path")" || log_error "Could not inspect SSH directory identity: ${directory_path}"
  descriptor_identity="$(stat -Lc '%d:%i' -- /proc/self/fd/9)" || log_error "Could not inspect pinned SSH directory descriptor: ${directory_path}"
  [ "$path_identity" = "$descriptor_identity" ] || log_error "SSH directory identity changed during validation: ${directory_path}"
  chmod 0700 -- /proc/self/fd/9 || log_error "Could not enforce mode 0700 on SSH directory: ${directory_path}"
  [ "$(stat -Lc '%a' -- /proc/self/fd/9)" = "700" ] || log_error "SSH directory mode is not 0700: ${directory_path}"
  [ ! -L "$directory_path" ] && [ -d "$directory_path" ] || log_error "SSH directory type changed during validation: ${directory_path}"
  path_identity="$(stat -c '%d:%i' -- "$directory_path")" || log_error "Could not re-inspect SSH directory identity: ${directory_path}"
  [ "$path_identity" = "$descriptor_identity" ] || log_error "SSH directory path changed during validation: ${directory_path}"
  exec 9<&-
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: harden_regular_file_no_follow
#   Creætes or pins one regulær single-link file ænd enforces owner-only mode.
#   Ærguments:
#     $1 - file pæth
#ææææææææææææææææææææææææææææææææææ
harden_regular_file_no_follow() {
  local file_path="$1"
  local descriptor_identity
  local path_identity

  if [ ! -e "$file_path" ] && [ ! -L "$file_path" ]; then
    if ! (set -C; : >"$file_path"); then
      log_error "Could not create SSH state file without following an existing node: ${file_path}"
    fi
  fi
  [ ! -L "$file_path" ] && [ -f "$file_path" ] || log_error "SSH state file must be a regular file, never a symlink or special node: ${file_path}"
  if ! { exec 8<>"$file_path"; }; then
    log_error "Could not open SSH state file for validation: ${file_path}"
  fi
  [ ! -L "$file_path" ] && [ -f "$file_path" ] || log_error "SSH state file must be a regular file, never a symlink or special node: ${file_path}"
  path_identity="$(stat -c '%d:%i' -- "$file_path")" || log_error "Could not inspect SSH state-file identity: ${file_path}"
  descriptor_identity="$(stat -Lc '%d:%i' -- /proc/self/fd/8)" || log_error "Could not inspect pinned SSH state-file descriptor: ${file_path}"
  [ "$path_identity" = "$descriptor_identity" ] || log_error "SSH state-file identity changed during validation: ${file_path}"
  [ "$(stat -Lc '%h' -- /proc/self/fd/8)" = "1" ] || log_error "SSH state file must not have additional hard links: ${file_path}"
  chmod 0600 -- /proc/self/fd/8 || log_error "Could not enforce mode 0600 on SSH state file: ${file_path}"
  [ "$(stat -Lc '%a' -- /proc/self/fd/8)" = "600" ] || log_error "SSH state-file mode is not 0600: ${file_path}"
  [ ! -L "$file_path" ] && [ -f "$file_path" ] || log_error "SSH state-file type changed during validation: ${file_path}"
  path_identity="$(stat -c '%d:%i' -- "$file_path")" || log_error "Could not re-inspect SSH state-file identity: ${file_path}"
  [ "$path_identity" = "$descriptor_identity" ] || log_error "SSH state-file path changed during validation: ${file_path}"
  exec 8>&-
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_ssh_directory
#   Prepæres tmpfs identity storæge ænd persistent known_hosts stæte.
#ææææææææææææææææææææææææææææææææææ
prepare_ssh_directory() {
  [ ! -L "$CERTS_DUMPER_SSH_STATE_ROOT" ] && [ -d "$CERTS_DUMPER_SSH_STATE_ROOT" ] || log_error "Persistent SSH state root must be a real directory: ${CERTS_DUMPER_SSH_STATE_ROOT}"
  harden_directory_no_follow /tmp/.ssh
  harden_directory_no_follow "$CERTS_DUMPER_SSH_STATE_DIR"
  harden_regular_file_no_follow "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE"
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
  if ! token="$(awk '
    NR != 1 { exit 1 }
    length($0) == 0 || $0 == "CHANGE_ME" || $0 ~ /[[:space:]]/ { exit 1 }
    { token = $0 }
    END {
      if (NR != 1 || token == "") exit 1
      printf "%s", token
    }
  ' "$CERTS_DUMPER_CF_TOKEN_FILE")"; then
    log_error "Cloudflare token secret must contain exactly one non-empty, non-placeholder line without whitespace: ${CERTS_DUMPER_CF_TOKEN_FILE}"
  fi
  printf '%s' "$token"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_mailcow_lock
#   Æcquires one kernel-releæsed exclusive lock for the complete Mæilcow/DÆNE flow.
#ææææææææææææææææææææææææææææææææææ
acquire_mailcow_lock() {
  harden_regular_file_no_follow "$CERTS_DUMPER_MAILCOW_LOCK_FILE"
  if ! { exec 7<>"$CERTS_DUMPER_MAILCOW_LOCK_FILE"; }; then
    log_error "Could not open the Mailcow roll-over lock file"
  fi
  flock -n 7 || log_error "Another Mailcow/DANE certificate roll-over is already active"
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
# FUNCTION: is_valid_dns_name
#   Returns success only for æ lowercæse ÆSCII DNS næme with vælid læbels.
#   Ærguments:
#     $1 - DNS næme cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_name() (
  local dns_name="$1"
  local previous_ifs
  local dns_label

  [ -n "$dns_name" ] && [ "${#dns_name}" -le 253 ] || exit 1
  case "$dns_name" in
    *[!a-z0-9.-]*|.*|*.|*..*) exit 1 ;;
    *.*) ;;
    *) exit 1 ;;
  esac
  case "$dns_name" in
    *[a-z-]*) ;;
    *) exit 1 ;;
  esac

  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $dns_name
  IFS="$previous_ifs"
  for dns_label in "$@"; do
    [ -n "$dns_label" ] && [ "${#dns_label}" -le 63 ] || exit 1
    case "$dns_label" in
      -*|*-) exit 1 ;;
    esac
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_dns_label
#   Returns success only for one lowercæse RFC 1123 DNS læbel.
#   Ærguments:
#     $1 - DNS læbel cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_label() (
  local dns_label="$1"

  [ -n "$dns_label" ] && [ "${#dns_label}" -le 63 ] || exit 1
  case "$dns_label" in
    *[!a-z0-9-]*|-*|*-) exit 1 ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_bounded_integer
#   Returns success only for æ cænonicæl decimæl integer inside one closed rænge.
#   Ærguments:
#     $1 - integer cændidæte
#     $2 - minimum væluæ
#     $3 - mæximum væluæ
#ææææææææææææææææææææææææææææææææææ
is_valid_bounded_integer() (
  local candidate="$1"
  local minimum="$2"
  local maximum="$3"

  case "$candidate" in
    0|[1-9]|[1-9][0-9]*) ;;
    *) exit 1 ;;
  esac
  [ "$candidate" -ge "$minimum" ] && [ "$candidate" -le "$maximum" ]
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_ipv4_address
#   Returns success only for one cænonicæl dotted-decimæl IPv4 æddress.
#   Ærguments:
#     $1 - IPv4 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_ipv4_address() (
  local candidate="$1"
  local previous_ifs
  local octet

  case "$candidate" in
    *[!0-9.]*|.*|*.|*..*) exit 1 ;;
  esac
  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $candidate
  IFS="$previous_ifs"
  [ "$#" -eq 4 ] || exit 1
  for octet in "$@"; do
    case "$octet" in
      0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;;
      *) exit 1 ;;
    esac
    [ "$octet" -le 255 ] || exit 1
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_mailcow_tlsa_owner
#   Ællows only the fixed SMTP service læbels plus one vælid DNS hostnæme.
#   Ærguments:
#     $1 - TLSÆ owner næme cændidæte
#     $2 - expected SMTP/MX hostnæme
#ææææææææææææææææææææææææææææææææææ
is_valid_mailcow_tlsa_owner() (
  local tlsa_owner="$1"
  local smtp_hostname="$2"

  [ -n "$tlsa_owner" ] && [ "${#tlsa_owner}" -le 253 ] || exit 1
  is_valid_dns_name "$smtp_hostname" || exit 1
  [ "$tlsa_owner" = "_25._tcp.${smtp_hostname}" ] || exit 1
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_mailcow_configuration
#   Derives the dumped certificæte directory ænd exæct SMTP/TLSÆ DNS contræct.
#ææææææææææææææææææææææææææææææææææ
resolve_mailcow_configuration() {
  local route_subdomain="${TRAEFIK_ROUTE_SUBDOMAIN:-}"
  local route_prefix=''
  local primary_domain="${TRAEFIK_DOMAIN:-}"
  local base_domain
  local effective_domain
  local expected_smtp_hostname
  local match_count=0

  if [ -n "$route_subdomain" ]; then
    is_valid_dns_label "$route_subdomain" || log_error "TRAEFIK_ROUTE_SUBDOMAIN must be blank or one lowercase RFC 1123 DNS label"
    route_prefix="${route_subdomain}."
  fi

  [ -n "$primary_domain" ] || log_error "TRAEFIK_DOMAIN is required for the Mailcow certificate main"
  is_valid_dns_name "$primary_domain" || log_error "TRAEFIK_DOMAIN is not a valid lowercase DNS base"
  MAILCOW_CERT_MAIN_DOMAIN="mailcow.${route_prefix}${primary_domain}"
  is_valid_dns_name "$MAILCOW_CERT_MAIN_DOMAIN" || log_error "The derived Mailcow certificate main is invalid or overlong"

  case "$MAILCOW_SMTP_HOSTNAME_INPUT" in
    ''|*CHANGE_ME*) log_error "MAILCOW_SMTP_HOSTNAME must be configured before mailcow() is enabled" ;;
  esac
  MAILCOW_SMTP_HOSTNAME="$(normalize_dns_name "$MAILCOW_SMTP_HOSTNAME_INPUT")"
  [ "$MAILCOW_SMTP_HOSTNAME" = "$MAILCOW_SMTP_HOSTNAME_INPUT" ] || log_error "MAILCOW_SMTP_HOSTNAME must be lowercase without a trailing dot"
  is_valid_dns_name "$MAILCOW_SMTP_HOSTNAME" || log_error "MAILCOW_SMTP_HOSTNAME is not a valid lowercase DNS name"

  for base_domain in "$primary_domain" "${TRAEFIK_DOMAIN_1:-}" "${TRAEFIK_DOMAIN_2:-}" "${TRAEFIK_DOMAIN_3:-}" "${TRAEFIK_DOMAIN_4:-}"; do
    [ -n "$base_domain" ] || continue
    is_valid_dns_name "$base_domain" || log_error "A configured TRAEFIK_DOMAIN_1..4 value is not a valid lowercase DNS base"
    effective_domain="${route_prefix}${base_domain}"
    expected_smtp_hostname="mail.${effective_domain}"
    is_valid_dns_name "$expected_smtp_hostname" || log_error "A derived Mailcow SMTP hostname is invalid or overlong"
    if [ "$MAILCOW_SMTP_HOSTNAME" = "$expected_smtp_hostname" ]; then
      match_count=$((match_count + 1))
    fi
  done

  [ "$match_count" -eq 1 ] || log_error "MAILCOW_SMTP_HOSTNAME must match exactly one rendered mail.<route-domain> hostname"
  case "$MAILCOW_CLOUDFLARE_ZONE_INPUT" in
    ''|*CHANGE_ME*) log_error "MAILCOW_CLOUDFLARE_ZONE must be configured before mailcow() is enabled" ;;
  esac
  MAILCOW_CLOUDFLARE_ZONE_NAME="$(normalize_dns_name "$MAILCOW_CLOUDFLARE_ZONE_INPUT")"
  [ "$MAILCOW_CLOUDFLARE_ZONE_NAME" = "$MAILCOW_CLOUDFLARE_ZONE_INPUT" ] || log_error "MAILCOW_CLOUDFLARE_ZONE must be lowercase without a trailing dot"
  is_valid_dns_name "$MAILCOW_CLOUDFLARE_ZONE_NAME" || log_error "MAILCOW_CLOUDFLARE_ZONE is not a valid lowercase DNS zone"
  case "$MAILCOW_SMTP_HOSTNAME" in
    *."$MAILCOW_CLOUDFLARE_ZONE_NAME") ;;
    *) log_error "MAILCOW_CLOUDFLARE_ZONE must be a complete-label suffix of MAILCOW_SMTP_HOSTNAME" ;;
  esac
  MAILCOW_TLSA_RECORD_NAME="_25._tcp.${MAILCOW_SMTP_HOSTNAME}"
  is_valid_mailcow_tlsa_owner "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_SMTP_HOSTNAME" || log_error "The derived Mailcow TLSA record name is invalid or overlong"

  is_valid_bounded_integer "$MAILCOW_DANE_TTL_SECONDS_INPUT" 60 86400 || log_error "MAILCOW_DANE_TTL_SECONDS must be an explicit integer from 60 through 86400; Cloudflare automatic TTL=1 is not accepted"
  is_valid_bounded_integer "$MAILCOW_DANE_TTL_SAFETY_SECONDS_INPUT" 1 86400 || log_error "MAILCOW_DANE_TTL_SAFETY_SECONDS must be an integer from 1 through 86400"
  is_valid_ipv4_address "$MAILCOW_DANE_VALIDATING_RESOLVER_INPUT" || log_error "MAILCOW_DANE_VALIDATING_RESOLVER must be one canonical dotted-decimal IPv4 address"
  MAILCOW_DANE_TTL_SECONDS="$MAILCOW_DANE_TTL_SECONDS_INPUT"
  MAILCOW_DANE_TTL_SAFETY_SECONDS="$MAILCOW_DANE_TTL_SAFETY_SECONDS_INPUT"
  MAILCOW_DANE_VALIDATING_RESOLVER="$MAILCOW_DANE_VALIDATING_RESOLVER_INPUT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_sha256_hash
#   Returns success only for one lowercæse SHÆ-256 hex digest.
#   Ærguments:
#     $1 - digest cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_sha256_hash() {
  local candidate="$1"

  [ "${#candidate}" -eq 64 ] || return 1
  case "$candidate" in
    *[!0-9a-f]*) return 1 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_mailcow_tlsa_records
#   Selects ænd vælidætes one stæble or two trænsitionæl exæct TLSÆ records.
#   Ærguments:
#     $1 - Cloudflære TLSÆ records response JSON
#     $2 - exæct expected TLSÆ record næme
#     $3 - explicit expected TTL in seconds
#ææææææææææææææææææææææææææææææææææ
select_mailcow_tlsa_records() {
  local records_json="$1"
  local expected_record_name="$2"
  local expected_ttl="$3"

  if ! printf '%s' "$records_json" | jq -ce \
    --arg expected_record_name "$expected_record_name" \
    --argjson expected_ttl "$expected_ttl" '
      def tuple_value($index; $field):
        .data[$field] // ((.content // "" | split(" ") | .[$index] // "" | tonumber?));
      def certificate_hash:
        (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase);
      (.result // []) as $result |
      [$result[] |
        select((.type | ascii_upcase) == "TLSA" and
          ((.name | ascii_downcase | rtrimstr(".")) == $expected_record_name))] as $records |
      if (($records | length) >= 1 and ($records | length) <= 2) and
        (($result | length) == ($records | length)) and
        ([$records[].id] | all(type == "string" and test("^[0-9a-fA-F]{32}$"))) and
        (([$records[].id] | unique | length) == ($records | length)) and
        ($records | all(
          tuple_value(0; "usage") == 3 and
          tuple_value(1; "selector") == 1 and
          tuple_value(2; "matching_type") == 1 and
          (.ttl == $expected_ttl) and
          (.proxied != true) and
          (certificate_hash | test("^[0-9a-f]{64}$")))) and
        (([$records[] | certificate_hash] | unique | length) == ($records | length))
      then $records
      else error("invalid Mailcow TLSA RRset")
      end
    '; then
    log_error "Mailcow TLSA RRset must contain one stable or two unique transitional exact 3 1 1 records with explicit TTL ${expected_ttl}; automatic TTL=1 and duplicates are rejected"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_tlsa_hashes
#   Prints the normælised SPKI hæsh from eæch vælidæted TLSÆ record.
#   Ærguments:
#     $1 - vælidæted TLSÆ record JSON ærræy
#ææææææææææææææææææææææææææææææææææ
mailcow_tlsa_hashes() {
  local records_json="$1"

  printf '%s' "$records_json" | jq -r '.[] | (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase)'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_tlsa_rrset_contains_hash
#   Returns success only when the vælidæted RRset contæins one exæct hæsh.
#   Ærguments:
#     $1 - vælidæted TLSÆ record JSON ærræy
#     $2 - lowercæse SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
mailcow_tlsa_rrset_contains_hash() {
  local records_json="$1"
  local expected_hash="$2"

  printf '%s' "$records_json" | jq -e --arg expected_hash "$expected_hash" '
    any(.[];
      ((.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase) == $expected_hash)
    )
  ' >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_mailcow_tlsa_record_by_hash
#   Selects exæctly one vælidæted TLSÆ record by its SPKI hæsh.
#   Ærguments:
#     $1 - vælidæted TLSÆ record JSON ærræy
#     $2 - lowercæse SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
select_mailcow_tlsa_record_by_hash() {
  local records_json="$1"
  local expected_hash="$2"

  if ! printf '%s' "$records_json" | jq -ce --arg expected_hash "$expected_hash" '
    [.[] |
      select(
        ((.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase) == $expected_hash)
      )
    ] |
    if length == 1 then .[0] else error("record hash is missing or ambiguous") end
  '; then
    log_error "Mailcow TLSA record hash is missing or ambiguous: ${expected_hash}"
  fi
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
# FUNCTION: calculate_certificate_sha256
#   Cælculætes the exæct leæf certificæte DER SHÆ-256 fingerprint.
#   Ærguments:
#     $1 - certificæte pæth
#ææææææææææææææææææææææææææææææææææ
calculate_certificate_sha256() {
  local cert_path="$1"

  [ -r "$cert_path" ] || log_error "Certificate not readable for leaf fingerprint: ${cert_path}"
  openssl x509 -in "$cert_path" -outform DER \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_certificate_hostname
#   Requires the dumped certificæte to cover the configured SMTP/MX host.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - expected SMTP/MX hostnæme
#ææææææææææææææææææææææææææææææææææ
require_certificate_hostname() {
  local cert_path="$1"
  local expected_hostname="$2"

  [ -r "$cert_path" ] || log_error "Certificate not readable for hostname verification: ${cert_path}"
  if ! openssl x509 -in "$cert_path" -noout -checkhost "$expected_hostname" >/dev/null 2>&1; then
    log_error "Mailcow certificate does not cover MAILCOW_SMTP_HOSTNAME=${expected_hostname}"
  fi
  log_ok "Mailcow certificate covers SMTP/MX hostname: ${expected_hostname}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_certificate_key_pair
#   Requires the dumped certificæte ænd privæte key to shære one public key.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#ææææææææææææææææææææææææææææææææææ
require_certificate_key_pair() {
  local cert_path="$1"
  local key_path="$2"
  local cert_public_key_hash
  local private_public_key_hash

  [ -r "$cert_path" ] || log_error "Certificate not readable for key-pair verification: ${cert_path}"
  [ -r "$key_path" ] || log_error "Private key not readable for key-pair verification: ${key_path}"
  if ! cert_public_key_hash="$(openssl x509 -in "$cert_path" -noout -pubkey \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256)"; then
    log_error "Could not derive the Mailcow certificate public key"
  fi
  if ! private_public_key_hash="$(openssl pkey -in "$key_path" -pubout -outform DER \
    | openssl dgst -sha256)"; then
    log_error "Could not derive the Mailcow private-key public key"
  fi
  [ -n "$cert_public_key_hash" ] && [ "$cert_public_key_hash" = "$private_public_key_hash" ] || log_error "Mailcow certificate and private key do not match"
  log_ok "Mailcow certificate and private key match."
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
#   Resolves one Cloudflære zone ID from the explicit Mæilcow zone.
#   Ærguments:
#     $1 - zone næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_find_zone_id() {
  local zone_name="$1"
  local zones_json
  local matching_zones_json
  local zone_count

  zones_json="$(cloudflare_get_zones_by_name "$zone_name")"
  matching_zones_json="$(printf '%s' "$zones_json" | jq -c --arg zone_name "$zone_name" \
    '.result | map(select((.name | ascii_downcase | rtrimstr(".")) == $zone_name))')"
  zone_count="$(printf '%s' "$matching_zones_json" | jq -r 'length')"

  case "$zone_count" in
    1)
      if ! printf '%s' "$matching_zones_json" | jq -er '
        .[0] |
        if (.status == "active" and (.id | type == "string" and test("^[0-9a-fA-F]{32}$")))
        then .id
        else error("zone is inactive or its ID is invalid")
        end
      '; then
        log_error "Configured Mailcow Cloudflare zone must be active and return one valid zone ID: ${zone_name}"
      fi
      ;;
    0)
      log_error "Configured Mailcow Cloudflare zone not found: ${zone_name}"
      ;;
    *)
      log_error "Multiple Cloudflare zones found for configured Mailcow zone ${zone_name}; refusing to guess"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_dnssec
#   Fetches DNSSEC stætus for one exæct Cloudflære zone.
#   Ærguments:
#     $1 - Cloudflære zone ID
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_dnssec() {
  local zone_id="$1"
  local token
  local response_file
  local http_status

  token="$(read_cloudflare_token)"
  response_file="$(mktemp /tmp/cloudflare-get-dnssec.XXXXXX)"
  if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
    --header "Authorization: Bearer ${token}" \
    "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dnssec")"; then
    log_error "Cloudflare API DNSSEC lookup failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  cloudflare_check_response "GET DNSSEC" "$http_status" "$response_file"
  cat "$response_file"
  rm -f "$response_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_dnssec_active
#   Requires Cloudflære änd the pærent delegætion to report DNSSEC æctive.
#   Ærguments:
#     $1 - Cloudflære zone ID
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_dnssec_active() {
  local zone_id="$1"
  local dnssec_json

  dnssec_json="$(cloudflare_get_dnssec "$zone_id")"
  if ! printf '%s' "$dnssec_json" | jq -e '.result.status == "active"' >/dev/null; then
    log_error "Cloudflare DNSSEC must be active before the Mailcow DANE workflow mutates DNS or certificates"
  fi
  log_ok "Cloudflare DNSSEC is active for the configured Mailcow zone."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_tlsa_records
#   Lists Cloudflære TLSÆ records with one exæct DNS næme in æ zone.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - exæct TLSÆ record næme
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
    --data-urlencode "per_page=50" \
    "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records")"; then
    log_error "Cloudflare API GET failed: $(cat "$response_file" 2>/dev/null || true)"
  fi

  cloudflare_check_response "GET" "$http_status" "$response_file"
  cat "$response_file"
  rm -f "$response_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_mutate_record
#   Creætes or deletes one exæct Cloudflære DNS record.
#   Ærguments:
#     $1 - HTTP method (POST or DELETE)
#     $2 - request URL
#     $3 - JSON pæyloæd for POST, blænk for DELETE
#ææææææææææææææææææææææææææææææææææ
cloudflare_mutate_record() {
  local method="$1"
  local url="$2"
  local payload="$3"
  local token
  local response_file
  local http_status

  token="$(read_cloudflare_token)"
  response_file="$(mktemp /tmp/cloudflare-write-tlsa.XXXXXX)"

  case "$method" in
    POST)
      if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
        --request POST \
        --header "Authorization: Bearer ${token}" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$url")"; then
        log_error "Cloudflare API POST failed: $(cat "$response_file" 2>/dev/null || true)"
      fi
      ;;
    DELETE)
      [ -z "$payload" ] || log_error "Cloudflare DELETE payload must be blank"
      if ! http_status="$(curl -sS -o "$response_file" -w '%{http_code}' \
        --request DELETE \
        --header "Authorization: Bearer ${token}" \
        "$url")"; then
        log_error "Cloudflare API DELETE failed: $(cat "$response_file" 2>/dev/null || true)"
      fi
      ;;
    *) log_error "Unsupported Cloudflare mutation method: ${method}" ;;
  esac

  cloudflare_check_response "$method" "$http_status" "$response_file"
  rm -f "$response_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_tlsa_payload
#   Builds one exæct Cloudflære TLSÆ 3 1 1 record pæyloæd.
#   Ærguments:
#     $1 - exæct TLSÆ owner
#     $2 - explicit TTL in seconds
#     $3 - TLSÆ SPKI SHÆ-256 hæsh
#ææææææææææææææææææææææææææææææææææ
build_tlsa_payload() {
  local record_name="$1"
  local record_ttl="$2"
  local certificate_hash="$3"

  jq -n \
    --arg record_name "$record_name" \
    --argjson record_ttl "$record_ttl" \
    --arg certificate "$certificate_hash" \
    '{
      type: "TLSA",
      name: $record_name,
      ttl: $record_ttl,
      data: {
        usage: 3,
        selector: 1,
        matching_type: 1,
        certificate: $certificate
      }
    }'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_cloudflare_tlsa_record
#   Ædds the future SPKI hæsh without replæcing the current TLSÆ record.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - exæct TLSÆ record næme
#     $3 - explicit TTL in seconds
#     $4 - future SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
create_cloudflare_tlsa_record() {
  local zone_id="$1"
  local record_name="$2"
  local record_ttl="$3"
  local certificate_hash="$4"
  local payload

  payload="$(build_tlsa_payload "$record_name" "$record_ttl" "$certificate_hash")"
  log_info "Publishing future Mailcow TLSA 3 1 1 record alongside the active key..."
  cloudflare_mutate_record "POST" "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records" "$payload"
  log_ok "Future Mailcow TLSA record published: ${record_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: delete_cloudflare_tlsa_record
#   Deletes one identity-proven obsolete TLSÆ record by its exæct ID.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - obsolete Cloudflære TLSÆ record ID
#ææææææææææææææææææææææææææææææææææ
delete_cloudflare_tlsa_record() {
  local zone_id="$1"
  local record_id="$2"

  case "$record_id" in
    *[!0-9a-fA-F]*|'') log_error "Refusing to delete an invalid Cloudflare TLSA record ID" ;;
  esac
  [ "${#record_id}" -eq 32 ] || log_error "Refusing to delete a non-canonical Cloudflare TLSA record ID"
  cloudflare_mutate_record "DELETE" "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records/${record_id}" ''
  log_ok "Obsolete Mailcow TLSA record deleted after verified overlap."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dnssec_tlsa_rrset_matches
#   Locælly vælidætes one exæct DNSSEC RRset from æ recursive DNS server.
#   Ærguments:
#     $1 - TLSÆ owner
#     $2 - configured mæximum TTL
#     $3+ - exæct expected SPKI hæshes
#ææææææææææææææææææææææææææææææææææ
dnssec_tlsa_rrset_matches() {
  local record_name="$1"
  local expected_ttl="$2"
  shift 2
  local delv_output
  local actual_hashes
  local expected_hashes
  local expected_hash

  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 1
  for expected_hash in "$@"; do
    is_valid_sha256_hash "$expected_hash" || return 1
  done
  if ! delv_output="$(timeout 20 delv \
    "@${MAILCOW_DANE_VALIDATING_RESOLVER}" +tcp +nosplit +nodnssec \
    +noall +comments +trust +ttl +class "$record_name" TLSA 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "$delv_output" | grep -Eq '^; fully validated$' || return 1
  if ! actual_hashes="$(printf '%s\n' "$delv_output" | awk \
    -v expected_name="$record_name" -v maximum_ttl="$expected_ttl" '
      BEGIN { count = 0; valid = 1 }
      $1 !~ /^;/ && toupper($4) == "TLSA" {
        owner = tolower($1); sub(/[.]$/, "", owner)
        digest = tolower($8)
        if (owner != expected_name || $2 !~ /^[0-9]+$/ || $2 < 1 || $2 > maximum_ttl ||
            $5 != 3 || $6 != 1 || $7 != 1 || length(digest) != 64 || digest !~ /^[0-9a-f]+$/) {
          valid = 0
        }
        print digest
        count++
      }
      END { if (!valid || count < 1 || count > 2) exit 1 }
    ')"; then
    return 1
  fi
  expected_hashes="$(printf '%s\n' "$@" | sort -u)"
  actual_hashes="$(printf '%s\n' "$actual_hashes" | sort -u)"
  [ "$actual_hashes" = "$expected_hashes" ]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_dnssec_tlsa_rrset
#   Polls until the exæct DNSSEC-æuthenticæted RRset is visible or fæils closed.
#   Ærguments:
#     $1 - TLSÆ owner
#     $2 - configured mæximum TTL
#     $3 - mæximum wæit in seconds
#     $4+ - exæct expected SPKI hæshes
#ææææææææææææææææææææææææææææææææææ
wait_for_dnssec_tlsa_rrset() {
  local record_name="$1"
  local expected_ttl="$2"
  local maximum_wait="$3"
  shift 3
  local waited=0

  while [ "$waited" -le "$maximum_wait" ]; do
    if dnssec_tlsa_rrset_matches "$record_name" "$expected_ttl" "$@"; then
      log_ok "DNSSEC-validating resolver sees the expected Mailcow TLSA RRset."
      return 0
    fi
    [ "$waited" -lt "$maximum_wait" ] || break
    sleep "$CERTS_DUMPER_DNS_POLL_SECONDS"
    waited=$((waited + CERTS_DUMPER_DNS_POLL_SECONDS))
  done
  log_error "Expected DNSSEC-authenticated Mailcow TLSA RRset was not visible within ${maximum_wait}s"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_dane_window
#   Wæits one explicit RFC 7671 roll-over window.
#   Ærguments:
#     $1 - phæse description
#     $2 - wæit time in seconds
#ææææææææææææææææææææææææææææææææææ
wait_for_dane_window() {
  local phase="$1"
  local wait_seconds="$2"

  log_info "Mailcow DANE ${phase}: waiting ${wait_seconds}s."
  sleep "$wait_seconds"
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

  if ! scp -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "$src_cert" "${dest_user}@${dest_host}:${dest_cert_path}"; then
    log_error "Failed to copy certificate to ${dest_host}:${dest_cert_path}"
  fi
  if ! scp -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "$src_key" "${dest_user}@${dest_host}:${dest_key_path}"; then
    log_error "Failed to copy key to ${dest_host}:${dest_key_path}"
  fi

  log_ok "Certificates copied to ${dest_user}@${dest_host}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_remote_mailcow_certificate
#   Stæges ænd vælidætes the new pæir beside the æctive files ænd keeps one bæckup.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote Mæilcow project pæth
#     $6 - SSH privæte key pæth
#     $7 - new leæf SHÆ-256 trænsæction ID
#     $8 - new SPKI SHÆ-256 hæsh
#     $9 - prior SPKI SHÆ-256 hæsh
#     $10 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
stage_remote_mailcow_certificate() {
  local src_cert="$1"
  local src_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local project_path="$5"
  local ssh_key="$6"
  local transaction_id="$7"
  local expected_new_spki="$8"
  local expected_prior_spki="$9"
  local expected_prior_leaf="${10}"
  local transaction_path="${project_path}/data/assets/ssl/.certs-dumper-rollover-${transaction_id}"

  log_info "Preparing remote Mailcow certificate transaction ${transaction_id}..."
  if ! ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" sh -s -- "$project_path" "$transaction_id" <<'REMOTE_PREPARE'
set -eu
umask 077
project_path="$1"
transaction_id="$2"
ssl_path="${project_path}/data/assets/ssl"
transaction_path="${ssl_path}/.certs-dumper-rollover-${transaction_id}"
active_cert="${ssl_path}/cert.pem"
active_key="${ssl_path}/key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"

case "$project_path" in
  /*) ;;
  *) exit 71 ;;
esac
case "$transaction_id" in
  *[!0-9a-f]*|'') exit 72 ;;
esac
[ "${#transaction_id}" -eq 64 ] || exit 73
[ -d "$ssl_path" ] && [ ! -L "$ssl_path" ] || exit 74
[ -f "$active_cert" ] && [ ! -L "$active_cert" ] || exit 75
[ -f "$active_key" ] && [ ! -L "$active_key" ] || exit 76
if [ ! -e "$transaction_path" ] && [ ! -L "$transaction_path" ]; then
  mkdir -m 0700 -- "$transaction_path" || exit 77
fi
[ -d "$transaction_path" ] && [ ! -L "$transaction_path" ] || exit 78
chmod 0700 -- "$transaction_path" || exit 79
if { [ -e "$backup_cert" ] || [ -L "$backup_cert" ]; } || { [ -e "$backup_key" ] || [ -L "$backup_key" ]; }; then
  [ -f "$backup_cert" ] && [ ! -L "$backup_cert" ] || exit 80
  [ -f "$backup_key" ] && [ ! -L "$backup_key" ] || exit 81
else
  cp -p -- "$active_cert" "$backup_cert" || exit 82
  cp -p -- "$active_key" "$backup_key" || exit 83
fi
REMOTE_PREPARE
  then
    return 1
  fi
  if ! scp -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "$src_cert" "${dest_user}@${dest_host}:${transaction_path}/incoming-cert.pem"; then
    return 1
  fi
  if ! scp -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "$src_key" "${dest_user}@${dest_host}:${transaction_path}/incoming-key.pem"; then
    return 1
  fi
  if ! ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" sh -s -- "$project_path" "$transaction_id" \
    "$expected_new_spki" "$expected_prior_spki" "$expected_prior_leaf" <<'REMOTE_VALIDATE'
set -eu
project_path="$1"
transaction_id="$2"
expected_new_spki="$3"
expected_prior_spki="$4"
expected_prior_leaf="$5"
transaction_path="${project_path}/data/assets/ssl/.certs-dumper-rollover-${transaction_id}"
incoming_cert="${transaction_path}/incoming-cert.pem"
incoming_key="${transaction_path}/incoming-key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"

for file_path in "$incoming_cert" "$incoming_key" "$backup_cert" "$backup_key"; do
  [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 84
done
chmod 0600 -- "$incoming_cert" "$incoming_key" "$backup_cert" "$backup_key" || exit 85
cert_hash="$(openssl x509 -in "$incoming_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 86
key_hash="$(openssl pkey -in "$incoming_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 87
cert_leaf="$(openssl x509 -in "$incoming_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 88
backup_spki="$(openssl x509 -in "$backup_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 89
backup_key_spki="$(openssl pkey -in "$backup_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 90
backup_leaf="$(openssl x509 -in "$backup_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 91
[ "$cert_hash" = "$expected_new_spki" ] && [ "$key_hash" = "$expected_new_spki" ] || exit 92
[ "$cert_leaf" = "$transaction_id" ] || exit 93
[ "$backup_spki" = "$expected_prior_spki" ] && [ "$backup_key_spki" = "$expected_prior_spki" ] || exit 94
[ "$backup_leaf" = "$expected_prior_leaf" ] || exit 95
REMOTE_VALIDATE
  then
    return 1
  fi
  log_ok "Remote Mailcow certificate pair staged with a retained backup."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: activate_remote_mailcow_certificate
#   Æctivætes the stæged pæir through one rollbæck-guærded remote trænsæction.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - new leæf SHÆ-256 trænsæction ID
#     $6 - new SPKI SHÆ-256 hæsh
#ææææææææææææææææææææææææææææææææææ
activate_remote_mailcow_certificate() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local transaction_id="$5"
  local expected_new_spki="$6"

  if ! ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" sh -s -- "$project_path" "$transaction_id" "$expected_new_spki" <<'REMOTE_ACTIVATE'
set -eu
umask 077
project_path="$1"
transaction_id="$2"
expected_new_spki="$3"
ssl_path="${project_path}/data/assets/ssl"
transaction_path="${ssl_path}/.certs-dumper-rollover-${transaction_id}"
active_cert="${ssl_path}/cert.pem"
active_key="${ssl_path}/key.pem"
incoming_cert="${transaction_path}/incoming-cert.pem"
incoming_key="${transaction_path}/incoming-key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"
next_cert="${transaction_path}/activate-cert.pem"
next_key="${transaction_path}/activate-key.pem"
committed=false

rollback_pair() {
  [ "$committed" = false ] || return 0
  cp -- "$backup_cert" "${transaction_path}/rollback-cert.pem" || return 1
  cp -- "$backup_key" "${transaction_path}/rollback-key.pem" || return 1
  chmod 0600 -- "${transaction_path}/rollback-cert.pem" "${transaction_path}/rollback-key.pem" || return 1
  mv -f -- "${transaction_path}/rollback-cert.pem" "$active_cert" || return 1
  mv -f -- "${transaction_path}/rollback-key.pem" "$active_key" || return 1
}

for file_path in "$active_cert" "$active_key" "$incoming_cert" "$incoming_key" "$backup_cert" "$backup_key"; do
  [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 91
done
cp -- "$incoming_cert" "$next_cert" || exit 92
cp -- "$incoming_key" "$next_key" || exit 93
chmod 0600 -- "$next_cert" "$next_key" || exit 94
trap 'rollback_pair' EXIT HUP INT TERM
mv -f -- "$next_cert" "$active_cert" || exit 95
mv -f -- "$next_key" "$active_key" || exit 96
cert_hash="$(openssl x509 -in "$active_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 97
key_hash="$(openssl pkey -in "$active_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 98
cert_leaf="$(openssl x509 -in "$active_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 99
[ "$cert_hash" = "$expected_new_spki" ] && [ "$key_hash" = "$expected_new_spki" ] || exit 100
[ "$cert_leaf" = "$transaction_id" ] || exit 101
committed=true
trap - EXIT HUP INT TERM
REMOTE_ACTIVATE
  then
    return 1
  fi
  log_ok "Remote Mailcow certificate pair activated from staged files."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_remote_mailcow_certificate
#   Restores the retained remote pæir ænd verifies its exæct prior identity.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - new leæf SHÆ-256 trænsæction ID
#     $6 - prior SPKI SHÆ-256 hæsh
#     $7 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
rollback_remote_mailcow_certificate() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local transaction_id="$5"
  local expected_spki="$6"
  local expected_leaf="$7"

  ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" sh -s -- \
    "$project_path" "$transaction_id" "$expected_spki" "$expected_leaf" <<'REMOTE_ROLLBACK'
set -eu
umask 077
project_path="$1"
transaction_id="$2"
expected_spki="$3"
expected_leaf="$4"
ssl_path="${project_path}/data/assets/ssl"
transaction_path="${ssl_path}/.certs-dumper-rollover-${transaction_id}"
active_cert="${ssl_path}/cert.pem"
active_key="${ssl_path}/key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"
rollback_cert="${transaction_path}/rollback-cert.pem"
rollback_key="${transaction_path}/rollback-key.pem"

for file_path in "$backup_cert" "$backup_key"; do
  [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 100
done
cp -- "$backup_cert" "$rollback_cert" || exit 101
cp -- "$backup_key" "$rollback_key" || exit 102
chmod 0600 -- "$rollback_cert" "$rollback_key" || exit 103
mv -f -- "$rollback_cert" "$active_cert" || exit 104
mv -f -- "$rollback_key" "$active_key" || exit 105
actual_spki="$(openssl x509 -in "$active_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 106
actual_key="$(openssl pkey -in "$active_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 107
actual_leaf="$(openssl x509 -in "$active_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 108
[ "$actual_spki" = "$expected_spki" ] && [ "$actual_key" = "$expected_spki" ] && [ "$actual_leaf" = "$expected_leaf" ]
REMOTE_ROLLBACK
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_remote_mailcow_transaction
#   Removes only the deterministic proven roll-over stæging directory.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - leæf SHÆ-256 trænsæction ID
#ææææææææææææææææææææææææææææææææææ
cleanup_remote_mailcow_transaction() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local transaction_id="$5"

  if ! ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" sh -s -- "$project_path" "$transaction_id" <<'REMOTE_CLEANUP'
set -eu
project_path="$1"
transaction_id="$2"
transaction_path="${project_path}/data/assets/ssl/.certs-dumper-rollover-${transaction_id}"
[ -e "$transaction_path" ] || exit 0
[ -d "$transaction_path" ] && [ ! -L "$transaction_path" ] || exit 109
for file_name in backup-cert.pem backup-key.pem incoming-cert.pem incoming-key.pem activate-cert.pem activate-key.pem rollback-cert.pem rollback-key.pem; do
  file_path="${transaction_path}/${file_name}"
  if [ -e "$file_path" ] || [ -L "$file_path" ]; then
    [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 110
    rm -- "$file_path" || exit 111
  fi
done
rmdir -- "$transaction_path"
REMOTE_CLEANUP
  then
    return 1
  fi
  log_ok "Remote Mailcow roll-over backup removed after final DNS verification."
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

  if ! ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" "cd \"${remote_project_path}\" && ${remote_cmd}"; then
    log_error "Failed to restart Docker Compose on ${dest_host}:${remote_project_path}"
  fi

  if [ "$#" -gt 0 ]; then
    log_ok "Docker Compose services ($*) restarted on ${dest_host}"
  else
    log_ok "Docker Compose restarted on ${dest_host}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restart_remote_mailcow_services
#   Restærts only the three Mæilcow TLS consumers; returns non-zero for rollbæck.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#ææææææææææææææææææææææææææææææææææ
restart_remote_mailcow_services() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"

  log_info "Restarting Mailcow TLS services on ${dest_host}..."
  ssh -i "$ssh_key" -o ConnectTimeout=10 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
    -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
    "${dest_user}@${dest_host}" sh -s -- "$project_path" <<'REMOTE_RESTART'
set -eu
project_path="$1"
cd -- "$project_path"
docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow
REMOTE_RESTART
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fetch_remote_smtp_identity
#   Reæds the leæf/SPKI identity currently served over SMTP STÆRTTLS.
#   Ærguments:
#     $1 - SMTP server æddress
#     $2 - expected SMTP TLS server næme
#ææææææææææææææææææææææææææææææææææ
fetch_remote_smtp_identity() {
  local smtp_address="$1"
  local smtp_hostname="$2"
  local smtp_output
  local served_spki
  local served_leaf

  if ! smtp_output="$(timeout "$CERTS_DUMPER_SMTP_ATTEMPT_SECONDS" openssl s_client -starttls smtp \
    -connect "${smtp_address}:25" -servername "$smtp_hostname" -name "$smtp_hostname" \
    -showcerts </dev/null 2>/dev/null)"; then
    return 1
  fi
  if ! served_spki="$(printf '%s\n' "$smtp_output" \
    | openssl x509 -noout -pubkey 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n')"; then
    return 1
  fi
  if ! served_leaf="$(printf '%s\n' "$smtp_output" \
    | openssl x509 -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n')"; then
    return 1
  fi
  is_valid_sha256_hash "$served_spki" && is_valid_sha256_hash "$served_leaf" || return 1
  printf '%s\n%s\n' "$served_spki" "$served_leaf"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_remote_smtp_identity
#   Wæits for one readable SMTP STÆRTTLS leæf/SPKI identity.
#   Ærguments:
#     $1 - SMTP server æddress
#     $2 - expected SMTP TLS server næme
#ææææææææææææææææææææææææææææææææææ
get_remote_smtp_identity() {
  local smtp_address="$1"
  local smtp_hostname="$2"
  local attempt=1
  local maximum_attempts
  local identity

  maximum_attempts=$((CERTS_DUMPER_SMTP_WAIT_SECONDS / (CERTS_DUMPER_SMTP_ATTEMPT_SECONDS + CERTS_DUMPER_SMTP_POLL_SECONDS)))
  [ "$maximum_attempts" -ge 1 ] || maximum_attempts=1
  while [ "$attempt" -le "$maximum_attempts" ]; do
    if identity="$(fetch_remote_smtp_identity "$smtp_address" "$smtp_hostname")"; then
      printf '%s\n' "$identity"
      return 0
    fi
    [ "$attempt" -lt "$maximum_attempts" ] || break
    sleep "$CERTS_DUMPER_SMTP_POLL_SECONDS"
    attempt=$((attempt + 1))
  done
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: verify_remote_smtp_identity
#   Requires SMTP STÆRTTLS to serve the exæct expected leæf ænd SPKI.
#   Ærguments:
#     $1 - SMTP server æddress
#     $2 - expected SMTP TLS server næme
#     $3 - expected SPKI SHÆ-256 hæsh
#     $4 - expected leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
verify_remote_smtp_identity() {
  local smtp_address="$1"
  local smtp_hostname="$2"
  local expected_spki="$3"
  local expected_leaf="$4"
  local identity
  local served_spki
  local served_leaf

  identity="$(get_remote_smtp_identity "$smtp_address" "$smtp_hostname")" || return 1
  served_spki="$(printf '%s\n' "$identity" | sed -n '1p')"
  served_leaf="$(printf '%s\n' "$identity" | sed -n '2p')"
  [ "$served_spki" = "$expected_spki" ] && [ "$served_leaf" = "$expected_leaf" ]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_emergency_rollback
#   Restores the prior remote pæir on every known post-æctivætion fæilure.
#ææææææææææææææææææææææææææææææææææ
mailcow_emergency_rollback() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  [ "$MAILCOW_ROLLBACK_ARMED" = true ] || return "$exit_status"
  MAILCOW_ROLLBACK_ARMED=false
  log_warn "Mailcow certificate activation did not complete verification; attempting the retained-pair rollback."
  if rollback_remote_mailcow_certificate \
    "$MAILCOW_ROLLBACK_DEST_HOST" "$MAILCOW_ROLLBACK_DEST_USER" \
    "$MAILCOW_ROLLBACK_PROJECT_PATH" "$MAILCOW_ROLLBACK_SSH_KEY" \
    "$MAILCOW_ROLLBACK_TRANSACTION_ID" "$MAILCOW_ROLLBACK_EXPECTED_SPKI" \
    "$MAILCOW_ROLLBACK_EXPECTED_LEAF" \
    && restart_remote_mailcow_services \
      "$MAILCOW_ROLLBACK_DEST_HOST" "$MAILCOW_ROLLBACK_DEST_USER" \
      "$MAILCOW_ROLLBACK_PROJECT_PATH" "$MAILCOW_ROLLBACK_SSH_KEY" \
    && verify_remote_smtp_identity \
      "$MAILCOW_ROLLBACK_DEST_HOST" "$MAILCOW_SMTP_HOSTNAME" \
      "$MAILCOW_ROLLBACK_EXPECTED_SPKI" "$MAILCOW_ROLLBACK_EXPECTED_LEAF"; then
    log_warn "Mailcow rollback restored and re-verified the prior SMTP certificate; the transitional TLSA RRset remains published for a safe retry."
  else
    log_warn "Mailcow rollback could not be fully verified. Keep both TLSA records and inspect the deterministic remote transaction backup before manual intervention."
  fi
  return "$exit_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: arm_mailcow_rollback
#   Ærms exit ænd signæl træps before the first remote æctivætion mutætion.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - new leæf SHÆ-256 trænsæction ID
#     $6 - prior SPKI SHÆ-256 hæsh
#     $7 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
arm_mailcow_rollback() {
  MAILCOW_ROLLBACK_DEST_HOST="$1"
  MAILCOW_ROLLBACK_DEST_USER="$2"
  MAILCOW_ROLLBACK_PROJECT_PATH="$3"
  MAILCOW_ROLLBACK_SSH_KEY="$4"
  MAILCOW_ROLLBACK_TRANSACTION_ID="$5"
  MAILCOW_ROLLBACK_EXPECTED_SPKI="$6"
  MAILCOW_ROLLBACK_EXPECTED_LEAF="$7"
  MAILCOW_ROLLBACK_ARMED=true
  trap 'mailcow_emergency_rollback' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: disarm_mailcow_rollback
#   Disærms the retained-pæir rollbæck only æfter exæct SMTP verificætion.
#ææææææææææææææææææææææææææææææææææ
disarm_mailcow_rollback() {
  MAILCOW_ROLLBACK_ARMED=false
  trap - EXIT HUP INT TERM
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: deploy_mailcow_certificate_pair
#   Stæges, æctivætes, restærts ænd verifies one Mæilcow pæir under rollbæck guærd.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote Mæilcow project pæth
#     $6 - SSH privæte key pæth
#     $7 - new SPKI SHÆ-256 hæsh
#     $8 - new leæf SHÆ-256 fingerprint
#     $9 - prior SPKI SHÆ-256 hæsh
#     $10 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
deploy_mailcow_certificate_pair() {
  local local_cert="$1"
  local local_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local project_path="$5"
  local ssh_key="$6"
  local new_spki="$7"
  local new_leaf="$8"
  local prior_spki="$9"
  local prior_leaf="${10}"

  if ! stage_remote_mailcow_certificate \
    "$local_cert" "$local_key" "$dest_host" "$dest_user" "$project_path" \
    "$ssh_key" "$new_leaf" "$new_spki" "$prior_spki" "$prior_leaf"; then
    log_error "Could not stage and validate the remote Mailcow certificate transaction"
  fi
  arm_mailcow_rollback \
    "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
    "$new_leaf" "$prior_spki" "$prior_leaf"
  if ! activate_remote_mailcow_certificate \
    "$dest_host" "$dest_user" "$project_path" "$ssh_key" "$new_leaf" "$new_spki"; then
    log_error "Could not activate the staged Mailcow certificate transaction"
  fi
  if ! restart_remote_mailcow_services "$dest_host" "$dest_user" "$project_path" "$ssh_key"; then
    log_error "Could not restart all targeted Mailcow TLS consumers"
  fi
  if ! verify_remote_smtp_identity "$dest_host" "$MAILCOW_SMTP_HOSTNAME" "$new_spki" "$new_leaf"; then
    log_error "Mailcow SMTP STARTTLS did not serve the exact newly activated leaf and SPKI"
  fi
  disarm_mailcow_rollback
  log_ok "Mailcow SMTP STARTTLS serves the exact renewed certificate and SPKI."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXÆMPLE USÆGE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mæilcow
#   Runs one resumæble RFC 7671 Mæilcow/DÆNE certificæte roll-over.
#ææææææææææææææææææææææææææææææææææ
mailcow() {
  local ssh_key="$CERTS_DUMPER_SSH_IDENTITY_FILE"
  local dest_host="192.168.20.120"
  local dest_user="root"
  local project_path="/opt/mailcow-dockerized"
  local local_cert
  local local_key
  local local_spki
  local local_leaf
  local zone_id
  local records_response
  local records_json
  local record_count
  local first_hash
  local second_hash=''
  local old_hash=''
  local old_record
  local old_record_id
  local remote_identity
  local remote_spki
  local remote_leaf
  local observation_wait
  local overlap_wait

  acquire_mailcow_lock
  resolve_mailcow_configuration
  local_cert="/data/files/${MAILCOW_CERT_MAIN_DOMAIN}/certificate.pem"
  local_key="/data/files/${MAILCOW_CERT_MAIN_DOMAIN}/privatekey.pem"
  wait_for_certificate_files "$local_cert" "$local_key"
  require_certificate_key_pair "$local_cert" "$local_key"
  require_certificate_hostname "$local_cert" "$MAILCOW_SMTP_HOSTNAME"
  local_spki="$(calculate_tlsa_spki_sha256 "$local_cert")"
  local_leaf="$(calculate_certificate_sha256 "$local_cert")"
  is_valid_sha256_hash "$local_spki" || log_error "Could not derive a canonical Mailcow TLSA SPKI hash"
  is_valid_sha256_hash "$local_leaf" || log_error "Could not derive a canonical Mailcow leaf fingerprint"
  read_cloudflare_token >/dev/null

  zone_id="$(cloudflare_find_zone_id "$MAILCOW_CLOUDFLARE_ZONE_NAME")"
  require_cloudflare_dnssec_active "$zone_id"
  observation_wait=$((MAILCOW_DANE_TTL_SECONDS + MAILCOW_DANE_TTL_SAFETY_SECONDS))
  overlap_wait=$((2 * MAILCOW_DANE_TTL_SECONDS + MAILCOW_DANE_TTL_SAFETY_SECONDS))

  records_response="$(cloudflare_get_tlsa_records "$zone_id" "$MAILCOW_TLSA_RECORD_NAME")"
  records_json="$(select_mailcow_tlsa_records \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
  record_count="$(printf '%s' "$records_json" | jq -r 'length')"
  first_hash="$(printf '%s' "$records_json" | jq -r \
    '.[0] | (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase)')"
  if [ "$record_count" -eq 2 ]; then
    second_hash="$(printf '%s' "$records_json" | jq -r \
      '.[1] | (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase)')"
    wait_for_dnssec_tlsa_rrset \
      "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
      "$first_hash" "$second_hash"
  else
    wait_for_dnssec_tlsa_rrset \
      "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
      "$first_hash"
  fi

  remote_identity="$(get_remote_smtp_identity "$dest_host" "$MAILCOW_SMTP_HOSTNAME")" \
    || log_error "Could not read the current Mailcow SMTP STARTTLS certificate identity"
  remote_spki="$(printf '%s\n' "$remote_identity" | sed -n '1p')"
  remote_leaf="$(printf '%s\n' "$remote_identity" | sed -n '2p')"
  if ! is_valid_sha256_hash "$remote_spki" || ! is_valid_sha256_hash "$remote_leaf"; then
    log_error "Mailcow SMTP STARTTLS returned a non-canonical certificate identity"
  fi
  mailcow_tlsa_rrset_contains_hash "$records_json" "$remote_spki" \
    || log_error "The active Mailcow SMTP SPKI is not protected by the current exact TLSA RRset"

  case "$record_count" in
    1)
      [ "$remote_spki" = "$first_hash" ] \
        || log_error "The stable Mailcow TLSA record does not match the active SMTP SPKI"
      if [ "$local_spki" = "$remote_spki" ]; then
        if [ "$local_leaf" != "$remote_leaf" ]; then
          log_info "Mailcow renewal keeps the existing SPKI; deploying the renewed leaf without DNS mutation."
          deploy_mailcow_certificate_pair \
            "$local_cert" "$local_key" "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
            "$local_spki" "$local_leaf" "$remote_spki" "$remote_leaf"
        else
          log_ok "Mailcow already serves the exact dumped leaf and SPKI; no deployment is needed."
        fi
        cleanup_remote_mailcow_transaction \
          "$dest_host" "$dest_user" "$project_path" "$ssh_key" "$local_leaf"
        return 0
      fi

      old_hash="$remote_spki"
      create_cloudflare_tlsa_record \
        "$zone_id" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$local_spki"
      records_response="$(cloudflare_get_tlsa_records "$zone_id" "$MAILCOW_TLSA_RECORD_NAME")"
      records_json="$(select_mailcow_tlsa_records \
        "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
      [ "$(printf '%s' "$records_json" | jq -r 'length')" -eq 2 ] \
        || log_error "Cloudflare did not return the expected two-record transitional Mailcow TLSA RRset"
      if ! mailcow_tlsa_rrset_contains_hash "$records_json" "$old_hash" \
        || ! mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki"; then
        log_error "The transitional Mailcow TLSA RRset does not contain exactly the prior and future SPKI hashes"
      fi
      wait_for_dnssec_tlsa_rrset \
        "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
        "$old_hash" "$local_spki"
      wait_for_dane_window "pre-deployment overlap" "$overlap_wait"
      ;;
    2)
      mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki" \
        || log_error "The resumable transitional Mailcow TLSA RRset does not contain the dumped certificate SPKI"
      if [ "$first_hash" = "$local_spki" ]; then
        old_hash="$second_hash"
      else
        old_hash="$first_hash"
      fi
      if [ "$remote_spki" != "$local_spki" ]; then
        [ "$remote_spki" = "$old_hash" ] \
          || log_error "The active SMTP SPKI matches neither side of the transitional Mailcow TLSA RRset"
        log_info "Resuming a pre-deployment Mailcow DANE transition with both TLSA records already published."
        wait_for_dane_window "resumed pre-deployment overlap" "$overlap_wait"
      else
        log_info "Resuming a post-deployment Mailcow DANE transition with both TLSA records still published."
      fi
      ;;
    *) log_error "Unexpected Mailcow TLSA RRset cardinality after validation" ;;
  esac

  if [ "$remote_leaf" != "$local_leaf" ] || [ "$remote_spki" != "$local_spki" ]; then
    deploy_mailcow_certificate_pair \
      "$local_cert" "$local_key" "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
      "$local_spki" "$local_leaf" "$remote_spki" "$remote_leaf"
  else
    log_ok "Mailcow already serves the exact new leaf and SPKI; continuing the resumable DNS retirement phase."
  fi

  wait_for_dane_window "post-deployment overlap" "$overlap_wait"
  records_response="$(cloudflare_get_tlsa_records "$zone_id" "$MAILCOW_TLSA_RECORD_NAME")"
  records_json="$(select_mailcow_tlsa_records \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
  [ "$(printf '%s' "$records_json" | jq -r 'length')" -eq 2 ] \
    || log_error "The Mailcow TLSA RRset changed before retirement of the prior key"
  if ! mailcow_tlsa_rrset_contains_hash "$records_json" "$old_hash" \
    || ! mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki"; then
    log_error "The Mailcow TLSA RRset no longer contains the proven prior/new hash pair"
  fi
  wait_for_dnssec_tlsa_rrset \
    "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
    "$old_hash" "$local_spki"
  verify_remote_smtp_identity "$dest_host" "$MAILCOW_SMTP_HOSTNAME" "$local_spki" "$local_leaf" \
    || log_error "Mailcow SMTP STARTTLS identity changed before retirement of the prior TLSA record"

  old_record="$(select_mailcow_tlsa_record_by_hash "$records_json" "$old_hash")"
  old_record_id="$(printf '%s' "$old_record" | jq -r '.id')"
  delete_cloudflare_tlsa_record "$zone_id" "$old_record_id"
  records_response="$(cloudflare_get_tlsa_records "$zone_id" "$MAILCOW_TLSA_RECORD_NAME")"
  records_json="$(select_mailcow_tlsa_records \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
  if [ "$(printf '%s' "$records_json" | jq -r 'length')" -ne 1 ] \
    || ! mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki"; then
    log_error "Cloudflare did not converge to the one-record final Mailcow TLSA RRset"
  fi
  wait_for_dnssec_tlsa_rrset \
    "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
    "$local_spki"
  cleanup_remote_mailcow_transaction \
    "$dest_host" "$dest_user" "$project_path" "$ssh_key" "$local_leaf"
  log_ok "Mailcow DANE roll-over completed with the exact new TLSA 3 1 1 record."
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

check_dependencies scp ssh curl jq openssl od stat delv timeout awk grep sed sort flock
prepare_ssh_directory
prepare_ssh_identity_from_secret
# if true; then mailcow; fi
log_ok "All post-hook tasks completed."
