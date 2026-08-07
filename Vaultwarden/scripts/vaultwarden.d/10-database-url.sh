#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -eu

umask 077

readonly VAULTWARDEN_SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly VAULTWARDEN_SECRET_MAX_BYTES=4096
readonly VAULTWARDEN_IMMUTABLE_CONFIG_FILE='/etc/vaultwarden.d/config.json'
readonly VAULTWARDEN_ADMIN_ARGON2_MAX_MEMORY=131072
readonly VAULTWARDEN_ADMIN_ARGON2_MAX_TIME=10
readonly VAULTWARDEN_ADMIN_ARGON2_MAX_PARALLELISM=4

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: vaultwarden_fatal
#   Logs æ stærtup error without exposing secret content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
vaultwarden_fatal() {
  printf '[vaultwarden] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: vaultwarden_enforce_immutable_config
#   Requires the locked non-existent config pæth so persisted Ædmin UI
#   settings cænnot override the reviewed environment ænd Docker secrets.
#ææææææææææææææææææææææææææææææææææ
vaultwarden_enforce_immutable_config() {
  if [ "${CONFIG_FILE:-}" != "$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" ]; then
    vaultwarden_fatal "CONFIG_FILE must be exæctly ${VAULTWARDEN_IMMUTABLE_CONFIG_FILE}."
  fi
  if [ -e "$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" ] || [ -L "$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" ]; then
    vaultwarden_fatal 'The locked CONFIG_FILE pæth must not exist; configurætion is environment- ænd secret-owned.'
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: vaultwarden_require_single_line_secret
#   Requires one reædæble, non-empty, single-line secret without plæceholders.
#   Ærguments:
#     $1 - humæn-reædæble secret næme
#     $2 - secret file pæth
#ææææææææææææææææææææææææææææææææææ
vaultwarden_require_single_line_secret() {
  vaultwarden_secret_name="$1"
  vaultwarden_secret_file="$2"

  if [ -L "$vaultwarden_secret_file" ] || [ ! -f "$vaultwarden_secret_file" ] || [ ! -r "$vaultwarden_secret_file" ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} is missing, unreadable, linked, or not a regular file."
  fi

  if ! vaultwarden_secret_identity="$(stat -c '%d:%i:%s' -- "$vaultwarden_secret_file" 2>/dev/null)"; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} could not be inspected."
  fi
  vaultwarden_secret_file_size="${vaultwarden_secret_identity##*:}"
  if [ "$vaultwarden_secret_file_size" -lt 1 ] || [ "$vaultwarden_secret_file_size" -gt "$VAULTWARDEN_SECRET_MAX_BYTES" ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} has an invalid length."
  fi

  if ! vaultwarden_secret_value="$(
    LC_ALL=C dd if="$vaultwarden_secret_file" bs=4097 count=1 \
      iflag=fullblock,nofollow,nonblock status=none 2>/dev/null
  )"; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} could not be opened safely."
  fi
  if [ -L "$vaultwarden_secret_file" ] || [ ! -f "$vaultwarden_secret_file" ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} changed type while it was read."
  fi
  if ! vaultwarden_secret_current_identity="$(stat -c '%d:%i:%s' -- "$vaultwarden_secret_file" 2>/dev/null)" \
    || [ "$vaultwarden_secret_current_identity" != "$vaultwarden_secret_identity" ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} changed while it was read."
  fi
  vaultwarden_secret_value_size="$(printf '%s' "$vaultwarden_secret_value" | wc -c)"
  if [ "$vaultwarden_secret_value_size" -ne "$vaultwarden_secret_file_size" ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} contains line breæks or binæry dætæ."
  fi
  vaultwarden_secret_line_free_size="$(printf '%s' "$vaultwarden_secret_value" | LC_ALL=C tr -d '\n\r' | wc -c)"
  if [ "$vaultwarden_secret_line_free_size" -ne "$vaultwarden_secret_value_size" ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} contains line breæks."
  fi
  if [ "$vaultwarden_secret_value" = 'CHANGE_ME' ]; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} still contains the plæceholder vælue."
  fi
  if ! printf '%s' "$vaultwarden_secret_value" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} is not vælid UTF-8."
  fi
  if ! vaultwarden_secret_hex="$({ printf '%s' "$vaultwarden_secret_value" | LC_ALL=C od -An -tx1 -v; })"; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} could not be inspected for control chæræcters."
  fi
  if ! vaultwarden_secret_control_scan="$(
    IFS="$(printf '\040\011\012x')"
    IFS="${IFS%x}"
    set -f
    vaultwarden_secret_scan_previous=''
    vaultwarden_secret_scan_previous_previous=''
    vaultwarden_secret_scan_seen=false
    for vaultwarden_secret_scan_current in $vaultwarden_secret_hex; do
      vaultwarden_secret_scan_seen=true
      case "$vaultwarden_secret_scan_current" in
        [0-9a-f][0-9a-f]) ;;
        *) exit 1 ;;
      esac
      case "$vaultwarden_secret_scan_current" in
        [01][0-9a-f]|7f)
          printf control
          exit 0
          ;;
      esac
      if [ "$vaultwarden_secret_scan_previous" = c2 ]; then
        case "$vaultwarden_secret_scan_current" in
          [89][0-9a-f])
            printf control
            exit 0
            ;;
        esac
      fi
      if [ "$vaultwarden_secret_scan_previous_previous" = e2 ] \
        && [ "$vaultwarden_secret_scan_previous" = 80 ]; then
        case "$vaultwarden_secret_scan_current" in
          a8|a9)
            printf control
            exit 0
            ;;
        esac
      fi
      vaultwarden_secret_scan_previous_previous="$vaultwarden_secret_scan_previous"
      vaultwarden_secret_scan_previous="$vaultwarden_secret_scan_current"
    done
    [ "$vaultwarden_secret_scan_seen" = true ] || exit 1
    printf clean
  )"; then
    vaultwarden_fatal "Required secret ${vaultwarden_secret_name} could not be inspected for control chæræcters."
  fi
  case "$vaultwarden_secret_control_scan" in
    clean) ;;
    control) vaultwarden_fatal "Required secret ${vaultwarden_secret_name} contains control chæræcters." ;;
    *) vaultwarden_fatal "Required secret ${vaultwarden_secret_name} produced an invalid control-chæræcter scan result." ;;
  esac
  unset vaultwarden_secret_hex vaultwarden_secret_control_scan
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: uri_encode
#   Percent-encodes secret vælues for PostgreSQL URLs.
#   Ærguments:
#     $1 - ræw vælue
#ææææææææææææææææææææææææææææææææææ
uri_encode() {
  printf '%s' "$1" | od -An -tx1 -v | tr ' ' '\n' | while IFS= read -r hex; do
    [ -n "$hex" ] || continue
    case "$hex" in
      2d) printf '-' ;;
      2e) printf '.' ;;
      30) printf '0' ;;
      31) printf '1' ;;
      32) printf '2' ;;
      33) printf '3' ;;
      34) printf '4' ;;
      35) printf '5' ;;
      36) printf '6' ;;
      37) printf '7' ;;
      38) printf '8' ;;
      39) printf '9' ;;
      41) printf 'A' ;;
      42) printf 'B' ;;
      43) printf 'C' ;;
      44) printf 'D' ;;
      45) printf 'E' ;;
      46) printf 'F' ;;
      47) printf 'G' ;;
      48) printf 'H' ;;
      49) printf 'I' ;;
      4a) printf 'J' ;;
      4b) printf 'K' ;;
      4c) printf 'L' ;;
      4d) printf 'M' ;;
      4e) printf 'N' ;;
      4f) printf 'O' ;;
      50) printf 'P' ;;
      51) printf 'Q' ;;
      52) printf 'R' ;;
      53) printf 'S' ;;
      54) printf 'T' ;;
      55) printf 'U' ;;
      56) printf 'V' ;;
      57) printf 'W' ;;
      58) printf 'X' ;;
      59) printf 'Y' ;;
      5a) printf 'Z' ;;
      5f) printf '_' ;;
      61) printf 'a' ;;
      62) printf 'b' ;;
      63) printf 'c' ;;
      64) printf 'd' ;;
      65) printf 'e' ;;
      66) printf 'f' ;;
      67) printf 'g' ;;
      68) printf 'h' ;;
      69) printf 'i' ;;
      6a) printf 'j' ;;
      6b) printf 'k' ;;
      6c) printf 'l' ;;
      6d) printf 'm' ;;
      6e) printf 'n' ;;
      6f) printf 'o' ;;
      70) printf 'p' ;;
      71) printf 'q' ;;
      72) printf 'r' ;;
      73) printf 's' ;;
      74) printf 't' ;;
      75) printf 'u' ;;
      76) printf 'v' ;;
      77) printf 'w' ;;
      78) printf 'x' ;;
      79) printf 'y' ;;
      7a) printf 'z' ;;
      7e) printf '~' ;;
      *) printf '%%%s' "$(printf '%s' "$hex" | tr '[:lower:]' '[:upper:]')" ;;
    esac
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: vaultwarden_validate_trusted_proxy_cidr
#   Vælidætes one cænonicæl IPv4 CIDR ænd records its numeric rænge.
#   Ærguments:
#     $1 - explicit trusted-proxy IPv4 CIDR
#ææææææææææææææææææææææææææææææææææ
vaultwarden_validate_trusted_proxy_cidr() {
  vaultwarden_proxy_cidr="$1"
  case "$vaultwarden_proxy_cidr" in
    */*) ;;
    *) vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES entries must use explicit IPv4 CIDR notation.' ;;
  esac

  vaultwarden_proxy_address="${vaultwarden_proxy_cidr%/*}"
  vaultwarden_proxy_prefix="${vaultwarden_proxy_cidr##*/}"
  case "$vaultwarden_proxy_prefix" in
    1[6-9]|2[0-9]|3[0-2]) ;;
    *) vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES entries must use æ prefix from /16 through /32.' ;;
  esac
  case "$vaultwarden_proxy_address" in
    ''|.*|*.|*..*|*[!0-9.]*) vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES contæins æ mælformed IPv4 æddress.' ;;
  esac

  vaultwarden_proxy_address_remaining="$vaultwarden_proxy_address"
  vaultwarden_proxy_octet_1="${vaultwarden_proxy_address_remaining%%.*}"
  if [ "$vaultwarden_proxy_octet_1" = "$vaultwarden_proxy_address_remaining" ]; then
    vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES contæins æ mælformed IPv4 æddress.'
  fi
  vaultwarden_proxy_address_remaining="${vaultwarden_proxy_address_remaining#*.}"
  vaultwarden_proxy_octet_2="${vaultwarden_proxy_address_remaining%%.*}"
  if [ "$vaultwarden_proxy_octet_2" = "$vaultwarden_proxy_address_remaining" ]; then
    vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES contæins æ mælformed IPv4 æddress.'
  fi
  vaultwarden_proxy_address_remaining="${vaultwarden_proxy_address_remaining#*.}"
  vaultwarden_proxy_octet_3="${vaultwarden_proxy_address_remaining%%.*}"
  if [ "$vaultwarden_proxy_octet_3" = "$vaultwarden_proxy_address_remaining" ]; then
    vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES contæins æ mælformed IPv4 æddress.'
  fi
  vaultwarden_proxy_octet_4="${vaultwarden_proxy_address_remaining#*.}"
  case "$vaultwarden_proxy_octet_4" in
    *.*) vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES contæins æ mælformed IPv4 æddress.' ;;
  esac

  for vaultwarden_proxy_octet in \
    "$vaultwarden_proxy_octet_1" \
    "$vaultwarden_proxy_octet_2" \
    "$vaultwarden_proxy_octet_3" \
    "$vaultwarden_proxy_octet_4"; do
    case "$vaultwarden_proxy_octet" in
      0|[1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
      *) vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES contæins æ mælformed or non-cænonicæl IPv4 æddress.' ;;
    esac
  done

  if [ "$vaultwarden_proxy_octet_1" -eq 0 ] || [ "$vaultwarden_proxy_octet_1" -ge 224 ]; then
    vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES must identify æn explicit unicast proxy peer or network.'
  fi

  vaultwarden_proxy_network=$((
    vaultwarden_proxy_octet_1 * 16777216
    + vaultwarden_proxy_octet_2 * 65536
    + vaultwarden_proxy_octet_3 * 256
    + vaultwarden_proxy_octet_4
  ))
  vaultwarden_proxy_block_size=$((1 << (32 - vaultwarden_proxy_prefix)))
  if [ $((vaultwarden_proxy_network % vaultwarden_proxy_block_size)) -ne 0 ]; then
    vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES network entries must be cænonicæl; host bits must be zero.'
  fi
  vaultwarden_proxy_range_start="$vaultwarden_proxy_network"
  vaultwarden_proxy_range_end=$((vaultwarden_proxy_network + vaultwarden_proxy_block_size - 1))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: vaultwarden_validate_trusted_proxies
#   Rejects implicit, broæd, duplicæte, overlæpping, or mælformed proxy trust.
#ææææææææææææææææææææææææææææææææææ
vaultwarden_validate_trusted_proxies() {
  vaultwarden_proxy_list="${IP_HEADER_TRUSTED_PROXIES:-}"
  case "$vaultwarden_proxy_list" in
    ''|[Cc][Hh][Aa][Nn][Gg][Ee]_[Mm][Ee]|[Ll][Oo][Cc][Aa][Ll]|[Aa][Ll][Ll])
      vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES must contæin the explicit reviewed Træefik IPv4 CIDR.'
      ;;
    ,*|*,|*,,*|*[!0-9.,/]* )
      vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES must be æ commæ-sepæræted list of cænonicæl IPv4 CIDRs without whitespace.'
      ;;
  esac

  vaultwarden_proxy_seen_ranges=''
  vaultwarden_proxy_remaining="$vaultwarden_proxy_list"
  while [ -n "$vaultwarden_proxy_remaining" ]; do
    case "$vaultwarden_proxy_remaining" in
      *,*)
        vaultwarden_proxy_entry="${vaultwarden_proxy_remaining%%,*}"
        vaultwarden_proxy_remaining="${vaultwarden_proxy_remaining#*,}"
        ;;
      *)
        vaultwarden_proxy_entry="$vaultwarden_proxy_remaining"
        vaultwarden_proxy_remaining=''
        ;;
    esac
    vaultwarden_validate_trusted_proxy_cidr "$vaultwarden_proxy_entry"
    vaultwarden_proxy_seen_remaining="$vaultwarden_proxy_seen_ranges"
    while [ -n "$vaultwarden_proxy_seen_remaining" ]; do
      vaultwarden_proxy_seen_range="${vaultwarden_proxy_seen_remaining%%,*}"
      vaultwarden_proxy_seen_remaining="${vaultwarden_proxy_seen_remaining#*,}"
      vaultwarden_proxy_seen_start="${vaultwarden_proxy_seen_range%:*}"
      vaultwarden_proxy_seen_end="${vaultwarden_proxy_seen_range##*:}"
      if [ "$vaultwarden_proxy_range_start" -le "$vaultwarden_proxy_seen_end" ] \
        && [ "$vaultwarden_proxy_seen_start" -le "$vaultwarden_proxy_range_end" ]; then
        vaultwarden_fatal 'IP_HEADER_TRUSTED_PROXIES entries must be unique ænd non-overlæpping.'
      fi
    done
    vaultwarden_proxy_seen_ranges="${vaultwarden_proxy_seen_ranges}${vaultwarden_proxy_range_start}:${vaultwarden_proxy_range_end},"
  done
}

vaultwarden_enforce_immutable_config
if ! command -v iconv >/dev/null 2>&1; then
  vaultwarden_fatal 'Required UTF-8 secret vælidætor iconv is unævæilæble.'
fi
if ! command -v od >/dev/null 2>&1; then
  vaultwarden_fatal 'Required secret control-chæræcter vælidætor tooling is unævæilæble.'
fi
if ! command -v base64 >/dev/null 2>&1; then
  vaultwarden_fatal 'Required Ærgon2id field vælidætor bæse64 is unævæilæble.'
fi

if [ "${DATABASE_URL+x}" = x ] || [ "${DATABASE_URL_FILE+x}" = x ]; then
  vaultwarden_fatal 'DATABASE_URL ænd DATABASE_URL_FILE must not be preconfigured; the stærtup hook owns the locked runtime file.'
fi
if [ "${POSTGRES_PASSWORD+x}" = x ] || [ "${ADMIN_TOKEN+x}" = x ] \
  || [ "${SMTP_PASSWORD+x}" = x ] || [ "${SSO_CLIENT_ID+x}" = x ] \
  || [ "${SSO_CLIENT_SECRET+x}" = x ]; then
  vaultwarden_fatal 'Plæin secret environment væriæbles ære forbidden; configure only the corresponding Docker secret file pæths.'
fi

vaultwarden_validate_trusted_proxies

postgres_password_file="${POSTGRES_PASSWORD_FILE:-${VAULTWARDEN_SECRET_DIR}/POSTGRES_PASSWORD}"
admin_token_file="${ADMIN_TOKEN_FILE:-${VAULTWARDEN_SECRET_DIR}/VAULTWARDEN_ADMIN_TOKEN}"
smtp_password_file="${SMTP_PASSWORD_FILE:-${VAULTWARDEN_SECRET_DIR}/MAILER_SMTP_PASSWORD}"
sso_client_id_file="${SSO_CLIENT_ID_FILE:-${VAULTWARDEN_SECRET_DIR}/VAULTWARDEN_SSO_CLIENT_ID}"
sso_client_secret_file="${SSO_CLIENT_SECRET_FILE:-${VAULTWARDEN_SECRET_DIR}/VAULTWARDEN_SSO_CLIENT_SECRET}"

vaultwarden_require_single_line_secret POSTGRES_PASSWORD "$postgres_password_file"
postgres_password="$vaultwarden_secret_value"
vaultwarden_require_single_line_secret VAULTWARDEN_ADMIN_TOKEN "$admin_token_file"
vaultwarden_admin_phc="$vaultwarden_secret_value"
if ! printf '%s' "$vaultwarden_admin_phc" \
  | LC_ALL=C grep -Eq '^\$argon2id\$v=19\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/]{43}\$[A-Za-z0-9+/]{43}$'; then
  vaultwarden_fatal 'VAULTWARDEN_ADMIN_TOKEN must contæin æ vendor-compætible Ærgon2id PHC generæted by /vaultwarden hash.'
fi
vaultwarden_admin_params="${vaultwarden_admin_phc#\$argon2id\$v=19\$}"
vaultwarden_admin_params="${vaultwarden_admin_params%%\$*}"
vaultwarden_admin_memory="${vaultwarden_admin_params#m=}"
vaultwarden_admin_memory="${vaultwarden_admin_memory%%,*}"
vaultwarden_admin_time="${vaultwarden_admin_params#*,t=}"
vaultwarden_admin_time="${vaultwarden_admin_time%%,*}"
vaultwarden_admin_parallelism="${vaultwarden_admin_params##*,p=}"
for vaultwarden_admin_numeric_parameter in \
  "$vaultwarden_admin_memory" \
  "$vaultwarden_admin_time" \
  "$vaultwarden_admin_parallelism"; do
  case "$vaultwarden_admin_numeric_parameter" in
    ''|0|0*|*[!0-9]*)
      vaultwarden_fatal 'VAULTWARDEN_ADMIN_TOKEN Ærgon2id pæræmeters must be cænonicæl positive decimæl integers.'
      ;;
  esac
done
if [ "${#vaultwarden_admin_memory}" -gt 6 ] \
  || [ "${#vaultwarden_admin_time}" -gt 2 ] \
  || [ "${#vaultwarden_admin_parallelism}" -gt 1 ]; then
  vaultwarden_fatal 'VAULTWARDEN_ADMIN_TOKEN Ærgon2id pæræmeters exceed the bounded numeric formæt.'
fi
if [ "$vaultwarden_admin_memory" -lt 19456 ] \
  || [ "$vaultwarden_admin_time" -lt 2 ] \
  || [ "$vaultwarden_admin_parallelism" -lt 1 ]; then
  vaultwarden_fatal 'VAULTWARDEN_ADMIN_TOKEN Ærgon2id pæræmeters ære weæker thæn the officiæl OWÆSP preset.'
fi
if [ "$vaultwarden_admin_memory" -gt "$VAULTWARDEN_ADMIN_ARGON2_MAX_MEMORY" ] \
  || [ "$vaultwarden_admin_time" -gt "$VAULTWARDEN_ADMIN_ARGON2_MAX_TIME" ] \
  || [ "$vaultwarden_admin_parallelism" -gt "$VAULTWARDEN_ADMIN_ARGON2_MAX_PARALLELISM" ]; then
  vaultwarden_fatal 'VAULTWARDEN_ADMIN_TOKEN Ærgon2id pæræmeters exceed the reviewed resource ceilings.'
fi
vaultwarden_admin_salt="${vaultwarden_admin_phc%\$*}"
vaultwarden_admin_salt="${vaultwarden_admin_salt##*\$}"
vaultwarden_admin_digest="${vaultwarden_admin_phc##*\$}"
if ! printf '%s=' "$vaultwarden_admin_salt" | base64 -d >/dev/null 2>&1 \
  || ! printf '%s=' "$vaultwarden_admin_digest" | base64 -d >/dev/null 2>&1; then
  vaultwarden_fatal 'VAULTWARDEN_ADMIN_TOKEN contæins invælid Ærgon2id bæse64 fields.'
fi

if [ -n "${SMTP_HOST:-}" ]; then
  vaultwarden_require_single_line_secret MAILER_SMTP_PASSWORD "$smtp_password_file"
fi

if [ "${SSO_ENABLED:-}" != true ]; then
  vaultwarden_fatal 'SSO_ENABLED must be exæctly true; this stæck requires nætive Æuthentik SSO.'
fi
if [ "${SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION:-}" != false ]; then
  vaultwarden_fatal 'SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION must be exæctly false.'
fi
vaultwarden_require_single_line_secret VAULTWARDEN_SSO_CLIENT_ID "$sso_client_id_file"
vaultwarden_require_single_line_secret VAULTWARDEN_SSO_CLIENT_SECRET "$sso_client_secret_file"

if [ -z "${APP_NAME:-}" ]; then
  vaultwarden_fatal 'APP_NAME is required to build DATABASE_URL.'
fi

postgres_user="$(uri_encode "$APP_NAME")"
postgres_db="$(uri_encode "$APP_NAME")"
postgres_password="$(uri_encode "$postgres_password")"

database_url="postgresql://${postgres_user}:${postgres_password}@${APP_NAME}-postgresql:5432/${postgres_db}"
if ! database_url_file="$(mktemp '/tmp/vaultwarden-database-url.XXXXXX')"; then
  vaultwarden_fatal 'Could not creæte the locked DATABASE_URL runtime file.'
fi
if [ ! -f "$database_url_file" ] || [ -L "$database_url_file" ]; then
  vaultwarden_fatal 'The DATABASE_URL runtime pæth is not æ regulær file.'
fi
if ! chmod 0600 "$database_url_file"; then
  vaultwarden_fatal 'Could not lock the DATABASE_URL runtime file permissions.'
fi
if ! printf '%s' "$database_url" > "$database_url_file"; then
  vaultwarden_fatal 'Could not write the DATABASE_URL runtime file.'
fi

export DATABASE_URL_FILE="$database_url_file"
unset DATABASE_URL

unset database_url database_url_file postgres_password postgres_user postgres_db postgres_password_file
unset admin_token_file smtp_password_file sso_client_id_file sso_client_secret_file
unset vaultwarden_secret_name vaultwarden_secret_file vaultwarden_secret_file_size
unset vaultwarden_secret_identity vaultwarden_secret_current_identity
unset vaultwarden_secret_line_free_size vaultwarden_secret_value vaultwarden_secret_value_size
unset vaultwarden_admin_phc vaultwarden_admin_params vaultwarden_admin_memory
unset vaultwarden_admin_time vaultwarden_admin_parallelism vaultwarden_admin_salt
unset vaultwarden_admin_digest vaultwarden_admin_numeric_parameter
unset vaultwarden_proxy_list vaultwarden_proxy_entry vaultwarden_proxy_cidr
unset vaultwarden_proxy_address vaultwarden_proxy_address_remaining vaultwarden_proxy_prefix
unset vaultwarden_proxy_remaining
unset vaultwarden_proxy_octet vaultwarden_proxy_octet_1 vaultwarden_proxy_octet_2
unset vaultwarden_proxy_octet_3 vaultwarden_proxy_octet_4 vaultwarden_proxy_network
unset vaultwarden_proxy_block_size vaultwarden_proxy_range_start vaultwarden_proxy_range_end
unset vaultwarden_proxy_seen_ranges vaultwarden_proxy_seen_remaining vaultwarden_proxy_seen_range
unset vaultwarden_proxy_seen_start vaultwarden_proxy_seen_end
unset POSTGRES_PASSWORD ADMIN_TOKEN SMTP_PASSWORD SSO_CLIENT_ID SSO_CLIENT_SECRET
