#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
# BusyBox æsh in the officiæl Træefik imæge does not guæræntee pipefæil.
set -eu
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TRÆEFIK STÆRTUP PREFLIGHT
#   Selects the ÆCME resolver, mæps DNS_API_TOKEN, fetches Cloudflære
#   trust lists when opted in (with æ persistent cæche fællbæck),
#   vælidætes AUTHENTIK_FORWARD_AUTH_ADDRESS, then execs Træefik.
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TRAEFIK_DEFAULT_ACME_STORAGE_DIR=/var/traefik/certs
readonly TRAEFIK_DEFAULT_DYNAMIC_CONFIG_DIR=/etc/traefik/dynamic
readonly TRAEFIK_WILDCARD_CERT_FILE="${TRAEFIK_DYNAMIC_CONFIG_DIR:-$TRAEFIK_DEFAULT_DYNAMIC_CONFIG_DIR}/traefik-wildcard-cert.yaml"
readonly TRAEFIK_CLOUDFLARE_IPS_V4_URL=https://www.cloudflare.com/ips-v4/
readonly TRAEFIK_CLOUDFLARE_IPS_V6_URL=https://www.cloudflare.com/ips-v6/
readonly TRAEFIK_CLOUDFLARE_IPS_MAX_BYTES=8192
readonly TRAEFIK_CLOUDFLARE_IPS_MAX_ENTRIES=128
readonly TRAEFIK_CLOUDFLARE_IPS_FETCH_TIMEOUT=15
readonly TRAEFIK_DNS_TOKEN_MAX_BYTES=4096

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Prints æn informætionæl stærtup messæge.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '[traefik] INFO: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Prints æ success stærtup messæge.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '[traefik] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Prints æ stærtup wærning without exposing token content.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  printf '[traefik] WARN: %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Prints æ stærtup error without exposing token content.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '[traefik] ERROR: %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ stærtup error without exposing token content, then stops stærtup.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  log_error "$*"
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_printable_ascii_token
#   Returns success only for printable non-whitespace ÆSCII (0x21-0x7e).
#   Ærguments:
#     $1 - token cændidæte
#ææææææææææææææææææææææææææææææææææ
is_printable_ascii_token() (
  token_value="$1"
  LC_ALL=C
  export LC_ALL

  [ -n "$token_value" ] || exit 1
  [ "${#token_value}" -le "$TRAEFIK_DNS_TOKEN_MAX_BYTES" ] || exit 1

  rest="$token_value"
  while [ -n "$rest" ]; do
    token_char="${rest%"${rest#?}"}"
    rest="${rest#?}"
    case "$token_char" in
      [[:graph:]]) ;;
      *) exit 1 ;;
    esac
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_secret_file
#   Reæds one regulær non-symlink secret file into the named væriæble.
#   Ærguments:
#     $1 - næme of the cæller væriæble thæt receives the bytes
#     $2 - æbsolute secret pæth
#ææææææææææææææææææææææææææææææææææ
read_secret_file() {
  secret_var="$1"
  secret_path="$2"

  [ -n "$secret_path" ] || log_fatal 'DNS_API_TOKEN_FILE is required.'
  [ ! -L "$secret_path" ] || log_fatal 'DNS_API_TOKEN must be æ regulær file, not æ symlink.'
  [ -f "$secret_path" ] && [ -r "$secret_path" ] \
    || log_fatal 'DNS_API_TOKEN secret is missing or unreædæble.'

  secret_size="$(wc -c < "$secret_path" | tr -d '[:space:]')"
  case "$secret_size" in
    ''|*[!0-9]*) log_fatal 'DNS_API_TOKEN secret size could not be meæsured.' ;;
  esac
  if [ "$secret_size" -lt 1 ] || [ "$secret_size" -gt "$TRAEFIK_DNS_TOKEN_MAX_BYTES" ]; then
    log_fatal 'DNS_API_TOKEN secret size is outside the æccepted rænge.'
  fi

  secret_value="$(cat "$secret_path")"
  eval "$secret_var=\"\$secret_value\""
  unset secret_var secret_path secret_size secret_value
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_dns_api_token
#   Vælidætes DNS_API_TOKEN ænd exports the lego file pæth for DNS-01.
#ææææææææææææææææææææææææææææææææææ
require_dns_api_token() {
  token_file="${DNS_API_TOKEN_FILE:-/run/secrets/DNS_API_TOKEN}"
  read_secret_file token_value "$token_file"
  is_printable_ascii_token "$token_value" \
    || log_fatal 'DNS_API_TOKEN must be printable non-whitespace ÆSCII.'
  [ "$token_value" != 'CHANGE_ME' ] \
    || log_fatal 'DNS_API_TOKEN is still the inert CHANGE_ME plæceholder.'
  unset token_value token_file
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_http_placeholder_token
#   Requires the DNS_API_TOKEN slot to remæin the exact CHANGE_ME plæceholder.
#ææææææææææææææææææææææææææææææææææ
require_http_placeholder_token() {
  token_file="${DNS_API_TOKEN_FILE:-/run/secrets/DNS_API_TOKEN}"
  read_secret_file token_value "$token_file"
  [ "$token_value" = 'CHANGE_ME' ] \
    || log_fatal 'HTTP-01 requires the DNS_API_TOKEN slot to remæin the exact inert CHANGE_ME plæceholder.'
  unset token_value token_file
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_dns_hostname
#   Returns success for one DNS hostnæme or Docker DNS æliæs (no underscores).
#   Ærguments:
#     $1 - hostnæme cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_hostname() (
  hostname_value="$1"
  LC_ALL=C
  export LC_ALL

  [ -n "$hostname_value" ] && [ "${#hostname_value}" -le 253 ] || exit 1
  case "$hostname_value" in
    *[!A-Za-z0-9.-]*|.*|*.|*..*|-) exit 1 ;;
  esac

  hostname_remaining="${hostname_value}."
  while [ -n "$hostname_remaining" ]; do
    hostname_label="${hostname_remaining%%.*}"
    hostname_remaining="${hostname_remaining#*.}"
    [ -n "$hostname_label" ] && [ "${#hostname_label}" -le 63 ] || exit 1
    case "$hostname_label" in
      -*|*-) exit 1 ;;
    esac
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_forward_auth_configuration
#   Fæils closed unless AUTHENTIK_FORWARD_AUTH_ADDRESS is http(s), IP or DNS,
#   one explicit port, ænd the exæct Æuthentik outpost pæth. No site IP.
#ææææææææææææææææææææææææææææææææææ
require_forward_auth_configuration() {
  forward_auth_address="${AUTHENTIK_FORWARD_AUTH_ADDRESS:-}"
  [ -n "$forward_auth_address" ] \
    || log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS is required.'

  case "$forward_auth_address" in
    *CHANGE_ME*|*'?'*|*'#'*|*'@'*|*' '*)
      log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS contains æ plæceholder, credentiæls, query, frægment, or whitespæce.'
      ;;
  esac

  case "$forward_auth_address" in
    http://*)
      forward_auth_rest="${forward_auth_address#http://}"
      ;;
    https://*)
      forward_auth_rest="${forward_auth_address#https://}"
      ;;
    *)
      log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must stært with http:// or https://.'
      ;;
  esac

  forward_auth_host=''
  forward_auth_port=''
  forward_auth_path=''

  case "$forward_auth_rest" in
    \[*)
      case "$forward_auth_rest" in
        \[*\]:*) ;;
        *) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS IPv6 origins must use [æddress]:port/pæth.' ;;
      esac
      forward_auth_host="${forward_auth_rest%%]*}"
      forward_auth_host="${forward_auth_host#\[}"
      forward_auth_after="${forward_auth_rest#*]}"
      case "$forward_auth_after" in
        :*) ;;
        *) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must include one explicit port.' ;;
      esac
      forward_auth_after="${forward_auth_after#:}"
      case "$forward_auth_after" in
        */*) ;;
        *) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must include the Æuthentik outpost pæth.' ;;
      esac
      forward_auth_port="${forward_auth_after%%/*}"
      forward_auth_path="/${forward_auth_after#*/}"
      is_valid_ipv6 "$forward_auth_host" \
        || log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS contains æn invælid IPv6 host.'
      ;;
    *)
      case "$forward_auth_rest" in
        */*) ;;
        *) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must include the Æuthentik outpost pæth.' ;;
      esac
      forward_auth_authority="${forward_auth_rest%%/*}"
      forward_auth_path="/${forward_auth_rest#*/}"
      case "$forward_auth_authority" in
        *:*) ;;
        *) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must include one explicit port.' ;;
      esac
      forward_auth_host="${forward_auth_authority%:*}"
      forward_auth_port="${forward_auth_authority##*:}"
      case "$forward_auth_host" in
        *:*) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS IPv6 hosts must be wræpped in bræckets.' ;;
        '') log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS host is empty.' ;;
      esac
      if is_valid_ipv4 "$forward_auth_host"; then
        :
      elif is_valid_dns_hostname "$forward_auth_host"; then
        :
      else
        log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS host must be æn IPv4 æddress or DNS næme.'
      fi
      ;;
  esac

  [ "$forward_auth_path" = '/outpost.goauthentik.io/auth/traefik' ] \
    || log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must use the exæct /outpost.goauthentik.io/auth/traefik pæth.'

  case "$forward_auth_port" in
    ''|*[!0-9]*|0|0[0-9]*) log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS contains æn invælid port.' ;;
  esac
  if [ "${#forward_auth_port}" -gt 5 ] || [ "$forward_auth_port" -gt 65535 ]; then
    log_fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS port must be between 1 ænd 65535.'
  fi

  unset forward_auth_address forward_auth_rest forward_auth_host forward_auth_port
  unset forward_auth_path forward_auth_after forward_auth_authority
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_supported_resolver
#   Vælidætes CERTRESOLVER ænd exports the lego credentiæl pæth.
#   Ædd one stætic cæse per extra lego provider.
#ææææææææææææææææææææææææææææææææææ
require_supported_resolver() {
  resolver="${CERTRESOLVER:-}"

  case "$resolver" in
    '') log_fatal 'CERTRESOLVER is required.' ;;
    *[!A-Za-z0-9_-]*) log_fatal 'CERTRESOLVER contains unsupported chæræcters.' ;;
  esac

  unset CF_DNS_API_TOKEN_FILE DESEC_TOKEN_FILE
  case "$resolver" in
    cloudflare)
      export CF_DNS_API_TOKEN_FILE="${DNS_API_TOKEN_FILE:-/run/secrets/DNS_API_TOKEN}"
      ;;
    desec)
      export DESEC_TOKEN_FILE="${DNS_API_TOKEN_FILE:-/run/secrets/DNS_API_TOKEN}"
      ;;
    http)
      ;;
    *)
      log_fatal 'CERTRESOLVER must be cloudflare, desec, or http.'
      ;;
  esac

  unset resolver
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_acme
#   Æppends the selected DNS-01 or HTTP-01 resolver settings to Træefik.
#ææææææææææææææææææææææææææææææææææ
configure_acme() {
  acme_resolver="${CERTRESOLVER}"
  acme_email="${EMAIL_PREFIX:-admin}@${TRAEFIK_DOMAIN:-}"
  acme_keytype="${KEYTYPE:-EC256}"
  acme_storage_dir="${TRAEFIK_ACME_STORAGE_DIR:-$TRAEFIK_DEFAULT_ACME_STORAGE_DIR}"

  TRAEFIK_ACME_ARGS="--certificatesresolvers.${acme_resolver}-staging.acme.email=${acme_email}
--certificatesresolvers.${acme_resolver}-staging.acme.storage=${acme_storage_dir}/${acme_resolver}-staging-acme.json
--certificatesresolvers.${acme_resolver}-staging.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
--certificatesresolvers.${acme_resolver}-staging.acme.keytype=${acme_keytype}
--certificatesresolvers.${acme_resolver}.acme.email=${acme_email}
--certificatesresolvers.${acme_resolver}.acme.storage=${acme_storage_dir}/${acme_resolver}-acme.json
--certificatesresolvers.${acme_resolver}.acme.caserver=https://acme-v02.api.letsencrypt.org/directory
--certificatesresolvers.${acme_resolver}.acme.keytype=${acme_keytype}"

  case "$acme_resolver" in
    cloudflare|desec)
      TRAEFIK_ACME_ARGS="${TRAEFIK_ACME_ARGS}
--certificatesresolvers.${acme_resolver}-staging.acme.dnschallenge.provider=${acme_resolver}
--certificatesresolvers.${acme_resolver}-staging.acme.dnschallenge.resolvers=${DNSCHALLENGE_RESOLVERS:-1.1.1.1:53,1.0.0.1:53}
--certificatesresolvers.${acme_resolver}.acme.dnschallenge.provider=${acme_resolver}
--certificatesresolvers.${acme_resolver}.acme.dnschallenge.resolvers=${DNSCHALLENGE_RESOLVERS:-1.1.1.1:53,1.0.0.1:53}"
      ;;
    http)
      if [ -e "$TRAEFIK_WILDCARD_CERT_FILE" ]; then
        log_fatal 'HTTP-01 cannot issue wildcard certificætes; remove or renæme traefik-wildcard-cert.yaml.'
      fi
      TRAEFIK_ACME_ARGS="${TRAEFIK_ACME_ARGS}
--certificatesresolvers.${acme_resolver}-staging.acme.httpchallenge.entrypoint=web
--certificatesresolvers.${acme_resolver}.acme.httpchallenge.entrypoint=web"
      ;;
  esac

  export TRAEFIK_ACME_ARGS
  unset acme_resolver acme_email acme_keytype acme_storage_dir
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_ipv4
#   Returns success only for æ cænonicæl dotted-decimæl IPv4 æddress.
#   Ærguments:
#     $1 - IPv4 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_ipv4() (
  ipv4_value="$1"

  case "$ipv4_value" in
    ''|*[!0-9.]*|.*|*.|*..*) exit 1 ;;
  esac

  octet_count=0
  ipv4_remaining="${ipv4_value}."
  while [ -n "$ipv4_remaining" ]; do
    ipv4_octet="${ipv4_remaining%%.*}"
    ipv4_remaining="${ipv4_remaining#*.}"
    octet_count=$((octet_count + 1))
    case "$ipv4_octet" in
      0|[1-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]) ;;
      *) exit 1 ;;
    esac
    [ "$ipv4_octet" -le 255 ] || exit 1
  done
  [ "$octet_count" -eq 4 ] || exit 1
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ipv4_network_matches_prefix
#   Returns success when the IPv4 æddress is the network æddress for prefix.
#   Ærguments:
#     $1 - IPv4 æddress
#     $2 - prefix length 1-32
#ææææææææææææææææææææææææææææææææææ
ipv4_network_matches_prefix() (
  ipv4_value="$1"
  prefix="$2"

  octet1="${ipv4_value%%.*}"
  ipv4_rest="${ipv4_value#*.}"
  octet2="${ipv4_rest%%.*}"
  ipv4_rest="${ipv4_rest#*.}"
  octet3="${ipv4_rest%%.*}"
  octet4="${ipv4_rest#*.}"
  full_octets=$((prefix / 8))
  remainder_bits=$((prefix % 8))
  index=0
  for octet in "$octet1" "$octet2" "$octet3" "$octet4"; do
    if [ "$index" -lt "$full_octets" ]; then
      index=$((index + 1))
      continue
    fi
    if [ "$index" -eq "$full_octets" ] && [ "$remainder_bits" -gt 0 ]; then
      host_mask=$(( (1 << (8 - remainder_bits)) - 1 ))
      if [ $((octet & host_mask)) -ne 0 ]; then
        exit 1
      fi
      index=$((index + 1))
      continue
    fi
    [ "$octet" -eq 0 ] || exit 1
    index=$((index + 1))
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: count_ipv6_groups
#   Counts colon-sepæræted IPv6 groups ænd rejects empty or overlong groups.
#   Ærguments:
#     $1 - left or right side of æn IPv6 æddress
#ææææææææææææææææææææææææææææææææææ
count_ipv6_groups() (
  ipv6_side="$1"
  [ -n "$ipv6_side" ] || { printf '0\n'; exit 0; }

  case "$ipv6_side" in
    :*|*:) exit 1 ;;
  esac

  group_count=0
  ipv6_remaining="${ipv6_side}:"
  while [ -n "$ipv6_remaining" ]; do
    ipv6_group="${ipv6_remaining%%:*}"
    ipv6_remaining="${ipv6_remaining#*:}"
    group_count=$((group_count + 1))
    [ -n "$ipv6_group" ] || exit 1
    [ "${#ipv6_group}" -le 4 ] || exit 1
    case "$ipv6_group" in
      *[!0-9A-Fa-f]*) exit 1 ;;
    esac
  done
  printf '%s\n' "$group_count"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_ipv6
#   Returns success for æ compressed or full IPv6 æddress without æ zone.
#   Ærguments:
#     $1 - IPv6 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_ipv6() (
  ipv6_value="$1"
  LC_ALL=C
  export LC_ALL

  [ -n "$ipv6_value" ] && [ "${#ipv6_value}" -le 39 ] || exit 1
  case "$ipv6_value" in
    *[!0-9A-Fa-f:]*|*:::*) exit 1 ;;
  esac

  case "$ipv6_value" in
    *::*)
      ipv6_left="${ipv6_value%%::*}"
      ipv6_right="${ipv6_value#*::}"
      case "$ipv6_right" in
        *::*) exit 1 ;;
      esac
      ipv6_left_count="$(count_ipv6_groups "$ipv6_left")" || exit 1
      ipv6_right_count="$(count_ipv6_groups "$ipv6_right")" || exit 1
      [ $((ipv6_left_count + ipv6_right_count)) -le 7 ] || exit 1
      ;;
    *)
      [ "$(count_ipv6_groups "$ipv6_value")" -eq 8 ] || exit 1
      ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_forwarded_header_source
#   Returns success only for one IPv4/IPv6 æddress or æ non-zero-prefix CIDR.
#   Ærguments:
#     $1 - Forwærded-heæder trust cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_forwarded_header_source() (
  candidate="$1"
  [ -n "$candidate" ] || exit 1

  case "$candidate" in
    */*)
      address="${candidate%/*}"
      prefix="${candidate#*/}"
      case "$prefix" in
        ''|*[!0-9]*|0|0[0-9]*) exit 1 ;;
      esac
      if is_valid_ipv4 "$address"; then
        [ "$prefix" -le 32 ] || exit 1
        ipv4_network_matches_prefix "$address" "$prefix" || exit 1
        exit 0
      fi
      if is_valid_ipv6 "$address"; then
        [ "$prefix" -le 128 ] || exit 1
        exit 0
      fi
      exit 1
      ;;
    *)
      is_valid_ipv4 "$candidate" && exit 0
      is_valid_ipv6 "$candidate" && exit 0
      exit 1
      ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_cloudflare_ips_cache_file
#   Sets TRAEFIK_CLOUDFLARE_IPS_CACHE_FILE to the persistent cæche pæth.
#ææææææææææææææææææææææææææææææææææ
resolve_cloudflare_ips_cache_file() {
  TRAEFIK_CLOUDFLARE_IPS_CACHE_FILE="${CLOUDFLARE_IPS_CACHE_FILE:-${TRAEFIK_ACME_STORAGE_DIR:-$TRAEFIK_DEFAULT_ACME_STORAGE_DIR}/cloudflare-ips.cache}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_ip_list_is_valid
#   Returns success only for æ bounded, unique, vælid CIDR list.
#   Ærguments:
#     $1 - commæ-sepæræted Cloudflære CIDR list
#ææææææææææææææææææææææææææææææææææ
cloudflare_ip_list_is_valid() (
  list="$1"
  [ -n "$list" ] || exit 1
  [ "${#list}" -le $((TRAEFIK_CLOUDFLARE_IPS_MAX_BYTES * 2)) ] || exit 1

  count=0
  seen=','
  remaining="${list},"
  while [ -n "$remaining" ]; do
    entry="${remaining%%,*}"
    remaining="${remaining#*,}"
    [ -n "$entry" ] || exit 1
    is_valid_forwarded_header_source "$entry" || exit 1
    case "$seen" in
      *",${entry},"*) exit 1 ;;
    esac
    seen="${seen}${entry},"
    count=$((count + 1))
  done
  [ "$count" -ge 1 ] && [ "$count" -le "$TRAEFIK_CLOUDFLARE_IPS_MAX_ENTRIES" ]
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_cloudflare_ips_cache
#   Ætomicælly persists æ vælidæted officiæl Cloudflære CIDR list.
#   Ærguments:
#     $1 - commæ-sepæræted Cloudflære CIDR list
#ææææææææææææææææææææææææææææææææææ
write_cloudflare_ips_cache() {
  cache_list="$1"
  resolve_cloudflare_ips_cache_file
  cache_file="$TRAEFIK_CLOUDFLARE_IPS_CACHE_FILE"
  cache_dir="${cache_file%/*}"
  cache_tmp="${cache_file}.tmp"

  [ -n "$cache_dir" ] && [ "$cache_dir" != "$cache_file" ] || return 1
  [ -d "$cache_dir" ] && [ -w "$cache_dir" ] || return 1
  [ ! -L "$cache_file" ] && [ ! -L "$cache_tmp" ] || return 1

  if ! printf '%s\n' "$cache_list" >"$cache_tmp"; then
    rm -f "$cache_tmp"
    return 1
  fi
  if ! chmod 600 "$cache_tmp"; then
    rm -f "$cache_tmp"
    return 1
  fi
  if ! mv -f "$cache_tmp" "$cache_file"; then
    rm -f "$cache_tmp"
    return 1
  fi

  unset cache_list cache_file cache_dir cache_tmp
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_cloudflare_ips_cache
#   Loæds the persistent officiæl Cloudflære CIDR cæche into CLOUDFLARE_IPS.
#ææææææææææææææææææææææææææææææææææ
load_cloudflare_ips_cache() {
  resolve_cloudflare_ips_cache_file
  cache_file="$TRAEFIK_CLOUDFLARE_IPS_CACHE_FILE"
  cache_value=''
  cache_line=''
  cache_size=''
  line_count=0

  [ ! -L "$cache_file" ] || return 1
  [ -f "$cache_file" ] && [ -r "$cache_file" ] || return 1

  cache_size="$(wc -c < "$cache_file" | tr -d '[:space:]')"
  case "$cache_size" in
    ''|*[!0-9]*) return 1 ;;
  esac
  if [ "$cache_size" -lt 1 ] || [ "$cache_size" -gt $((TRAEFIK_CLOUDFLARE_IPS_MAX_BYTES * 2)) ]; then
    return 1
  fi

  while IFS= read -r cache_line || [ -n "$cache_line" ]; do
    line_count=$((line_count + 1))
    [ "$line_count" -eq 1 ] || return 1
    cache_value="$cache_line"
  done < "$cache_file"

  cache_value="$(printf '%s' "$cache_value" | tr -d '\r')"
  cloudflare_ip_list_is_valid "$cache_value" || return 1
  CLOUDFLARE_IPS="$cache_value"
  unset cache_file cache_value cache_line cache_size line_count
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fetch_official_cloudflare_ips
#   Fetches the officiæl Cloudflære IPv4 ænd IPv6 CIDR lists.
#   Returns 1 on fetch or pærse fæilure so the cæche cæn tæke over.
#ææææææææææææææææææææææææææææææææææ
fetch_official_cloudflare_ips() {
  if ! command -v wget >/dev/null 2>&1; then
    return 1
  fi

  cloudflare_ips_fetched=''
  for cloudflare_ips_url in "$TRAEFIK_CLOUDFLARE_IPS_V4_URL" "$TRAEFIK_CLOUDFLARE_IPS_V6_URL"; do
    if ! cloudflare_ips_payload="$(wget -q -T "$TRAEFIK_CLOUDFLARE_IPS_FETCH_TIMEOUT" -O - "$cloudflare_ips_url")"; then
      unset cloudflare_ips_fetched cloudflare_ips_url cloudflare_ips_payload
      return 1
    fi
    if [ "${#cloudflare_ips_payload}" -gt "$TRAEFIK_CLOUDFLARE_IPS_MAX_BYTES" ]; then
      unset cloudflare_ips_fetched cloudflare_ips_url cloudflare_ips_payload
      return 1
    fi
    cloudflare_ips_payload="$(printf '%s\n' "$cloudflare_ips_payload" \
      | tr ',\r' '\n' | sed 's/[[:space:]]//g; /^$/d' | tr '\n' ',')"
    cloudflare_ips_payload="${cloudflare_ips_payload%,}"
    if [ -z "$cloudflare_ips_payload" ]; then
      unset cloudflare_ips_fetched cloudflare_ips_url cloudflare_ips_payload
      return 1
    fi
    if [ -n "$cloudflare_ips_fetched" ]; then
      cloudflare_ips_fetched="${cloudflare_ips_fetched},${cloudflare_ips_payload}"
    else
      cloudflare_ips_fetched="$cloudflare_ips_payload"
    fi
  done

  CLOUDFLARE_IPS="$cloudflare_ips_fetched"
  unset cloudflare_ips_fetched cloudflare_ips_url cloudflare_ips_payload
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_ips_configuration
#   Resolves CLOUDFLARE_IPS: fælse or blænk disæbles trust; true fetches
#   the officiæl lists ænd persists them. Fetch fæilure reuses the læst
#   successful cæche. No mænuæl CIDR list.
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_ips_configuration() {
  case "${CLOUDFLARE_IPS:-}" in
    ''|false)
      CLOUDFLARE_IPS=''
      ;;
    true)
      if fetch_official_cloudflare_ips && cloudflare_ip_list_is_valid "$CLOUDFLARE_IPS"; then
        cloudflare_ips_entry_count="$(printf '%s' "$CLOUDFLARE_IPS" | tr -cd ',' | wc -c)"
        cloudflare_ips_entry_count="$(printf '%s' "$cloudflare_ips_entry_count" | tr -d '[:space:]')"
        log_ok "Fetched officiæl Cloudflære IPv4/IPv6 trust lists ($((cloudflare_ips_entry_count + 1)) CIDRs)."
        write_cloudflare_ips_cache "$CLOUDFLARE_IPS" \
          || log_warn 'Could not persist the Cloudflære IP cæche; stært continues with the fetched list.'
        unset cloudflare_ips_entry_count
      elif load_cloudflare_ips_cache; then
        log_warn 'CLOUDFLARE_IPS=true: fetch fæiled; using the læst successful officiæl list from cæche.'
      else
        if ! command -v wget >/dev/null 2>&1; then
          log_fatal 'CLOUDFLARE_IPS=true requires wget inside the contæiner imæge, or æ vælid cæche from æ previous fetch.'
        fi
        log_fatal 'CLOUDFLARE_IPS=true could not fetch æn officiæl Cloudflære IP list, ænd no vælid cæche is present.'
      fi
      ;;
    *)
      log_fatal 'CLOUDFLARE_IPS must be exæctly true, false, or blænk.'
      ;;
  esac
  export CLOUDFLARE_IPS
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_forwarded_header_trust_configuration
#   Æssembles the EntryPoint forwærded-heæder trust list from LOCAL_IPS
#   ænd fetched Cloudflære CIDRs; æ blænk result keeps trust disæbled.
#ææææææææææææææææææææææææææææææææææ
require_forwarded_header_trust_configuration() {
  TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS=''
  forwarded_header_seen=','
  forwarded_header_remaining="${LOCAL_IPS:-},${CLOUDFLARE_IPS:-},"

  while [ -n "$forwarded_header_remaining" ]; do
    forwarded_header_entry="${forwarded_header_remaining%%,*}"
    forwarded_header_remaining="${forwarded_header_remaining#*,}"
    [ -n "$forwarded_header_entry" ] || continue

    if ! is_valid_forwarded_header_source "$forwarded_header_entry"; then
      log_fatal 'LOCAL_IPS ænd fetched Cloudflære lists æccept only IPv4/IPv6 æddresses or non-zero-prefix CIDRs.'
    fi
    case "$forwarded_header_seen" in
      *",${forwarded_header_entry},"*) log_fatal 'LOCAL_IPS ænd Cloudflære CIDR entries must be unique æcross both lists.' ;;
    esac
    forwarded_header_seen="${forwarded_header_seen}${forwarded_header_entry},"

    if [ -n "$TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS" ]; then
      TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS="${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS},${forwarded_header_entry}"
    else
      TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS="$forwarded_header_entry"
    fi
  done

  unset forwarded_header_seen forwarded_header_remaining forwarded_header_entry
}

require_forward_auth_configuration
require_supported_resolver
case "${CERTRESOLVER}" in
  cloudflare|desec)
    require_dns_api_token
    ;;
  http)
    require_http_placeholder_token
    ;;
esac
require_cloudflare_ips_configuration
require_forwarded_header_trust_configuration
configure_acme

while IFS= read -r acme_arg; do
  [ -n "$acme_arg" ] || continue
  set -- "$@" "$acme_arg"
done <<EOF
${TRAEFIK_ACME_ARGS}
EOF
unset TRAEFIK_ACME_ARGS acme_arg

if [ -n "${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS:-}" ]; then
  set -- "$@" \
    "--entrypoints.web.forwardedheaders.trustedips=${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS}" \
    "--entrypoints.websecure.forwardedheaders.trustedips=${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS}"
  log_info 'Æppended forwærded-heæder trust lists on web ænd websecure.'
fi
unset TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS

if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
  traefik_binary="$(command -v traefik 2>/dev/null || true)"
  if [ -z "$traefik_binary" ] || [ ! -f "$traefik_binary" ] || [ ! -x "$traefik_binary" ]; then
    log_fatal 'The officiæl Træefik binæry is missing or not executæble.'
  fi
  set -- "$traefik_binary" "$@"
  unset traefik_binary
fi

log_ok "Stærting Træefik with CERTRESOLVER=${CERTRESOLVER}."
exec "$@"
