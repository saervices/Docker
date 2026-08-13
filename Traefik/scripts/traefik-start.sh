#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TRÆFIK STÆRTUP PREFLIGHT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes the Cloudflære DNS token before the Træefik dæemon stærts.

set -eu
umask 077

readonly TRAEFIK_SECRET_MAX_BYTES=4096
readonly TRAEFIK_DEFAULT_ACME_STORAGE_DIR=/var/traefik/certs
readonly TRAEFIK_DEFAULT_DYNAMIC_CONFIG_DIR=/etc/traefik/dynamic
readonly TRAEFIK_CLOUDFLARE_IPS_V4_URL=https://www.cloudflare.com/ips-v4/
readonly TRAEFIK_CLOUDFLARE_IPS_V6_URL=https://www.cloudflare.com/ips-v6/
readonly TRAEFIK_CLOUDFLARE_IPS_MAX_BYTES=8192
readonly TRAEFIK_CLOUDFLARE_IPS_MAX_ENTRIES=128
readonly TRAEFIK_CLOUDFLARE_IPS_FETCH_TIMEOUT=15
readonly TRAEFIK_SAME_DOCKER_FORWARD_AUTH_ADDRESS=http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik
readonly TRAEFIK_ROUTE_APPLICATION_PREFIXES='actualbudget authentik ha immich kimai n8n openccu opnsense pbs pve rustdesk seafile template truenas vaultwarden vikunja wikijs'
readonly TRAEFIK_ROUTE_MAILCOW_PREFIXES='autoconfig autodiscover mail mailcow mta-sts'

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing token content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[traefik] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_token
#   Requires æ reædæble, non-empty, single-line Cloudflære token.
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_token() {
  token_file="${CF_DNS_API_TOKEN_FILE:-/run/secrets/CF_DNS_API_TOKEN}"

  if [ ! -f "$token_file" ] || [ ! -r "$token_file" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret is missing or unreadable.'
  fi

  token_file_size="$(wc -c < "$token_file")"
  if [ "$token_file_size" -lt 1 ] || [ "$token_file_size" -gt "$TRAEFIK_SECRET_MAX_BYTES" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret has an invalid length.'
  fi

  token_line_free_size="$(LC_ALL=C tr -d '\n\r' < "$token_file" | wc -c)"
  if [ "$token_line_free_size" -ne "$token_file_size" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret contains line breæks.'
  fi

  token_value="$(cat "$token_file")"
  token_value_size="$(printf '%s' "$token_value" | wc -c)"
  if [ "$token_value_size" -ne "$token_file_size" ]; then
    fatal 'Required CF_DNS_API_TOKEN secret contains træiling line breæks or binæry dætæ.'
  fi
  if [ "$token_value" = 'CHANGE_ME' ]; then
    fatal 'Required CF_DNS_API_TOKEN secret still contains the plæceholder vælue.'
  fi
  if printf '%s' "$token_value" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fatal 'Required CF_DNS_API_TOKEN secret contains control chæræcters.'
  fi

  unset token_file token_file_size token_line_free_size token_value token_value_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_supported_resolver
#   Vælidætes the resolver næme before it is used in ÆCME file pæths.
#ææææææææææææææææææææææææææææææææææ
require_supported_resolver() {
  resolver="${CERTRESOLVER:-}"

  case "$resolver" in
    '') fatal 'CERTRESOLVER is required.' ;;
    *[!A-Za-z0-9_-]*) fatal 'CERTRESOLVER contains unsupported chæræcters.' ;;
  esac

  if [ "$resolver" != 'cloudflare' ]; then
    fatal 'This stæck currently supports only the Cloudflære DNS resolver.'
  fi

  unset resolver
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

  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $ipv4_value
  IFS="$previous_ifs"
  [ "$#" -eq 4 ] || exit 1

  for ipv4_octet in "$@"; do
    case "$ipv4_octet" in
      0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;;
      *) exit 1 ;;
    esac
    [ "$ipv4_octet" -le 255 ] || exit 1
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_forwarded_header_source
#   Returns success only for one IPv4/IPv6 æddress or æ non-zero-prefix CIDR.
#   Ærguments:
#     $1 - Forwærded-heæder trust cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_forwarded_header_source() (
  source_entry="$1"
  [ -n "$source_entry" ] || exit 1

  case "$source_entry" in
    */*)
      source_address="${source_entry%/*}"
      source_prefix="${source_entry##*/}"
      case "$source_prefix" in
        ''|0*|*[!0-9]*) exit 1 ;;
      esac
      [ "${#source_prefix}" -le 3 ] || exit 1
      ;;
    *)
      source_address="$source_entry"
      source_prefix=''
      ;;
  esac

  case "$source_address" in
    *:*)
      [ "${#source_address}" -le 39 ] || exit 1
      case "$source_address" in
        *[!0-9A-Fa-f:]*|:|*:::*|*::*::*) exit 1 ;;
      esac
      [ -z "$source_prefix" ] || [ "$source_prefix" -le 128 ] || exit 1
      ;;
    *)
      is_valid_ipv4 "$source_address" || exit 1
      [ -z "$source_prefix" ] || [ "$source_prefix" -le 32 ] || exit 1
      ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_dns_name
#   Returns success only for æn ÆSCII DNS næme with vælid læbel boundæries.
#   Ærguments:
#     $1 - DNS næme cændidæte
#     $2 - true to require æt leæst one dot
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_name() (
  dns_name="$1"
  require_dot="$2"
  LC_ALL=C
  export LC_ALL

  [ -n "$dns_name" ] && [ "${#dns_name}" -le 253 ] || exit 1
  case "$dns_name" in
    *[!A-Za-z0-9.-]*|.*|*.|*..*) exit 1 ;;
  esac
  if [ "$require_dot" = 'true' ]; then
    case "$dns_name" in
      *.*) ;;
      *) exit 1 ;;
    esac
    is_valid_ipv4 "$dns_name" && exit 1
  fi

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
  dns_label="$1"
  LC_ALL=C
  export LC_ALL

  [ -n "$dns_label" ] && [ "${#dns_label}" -le 63 ] || exit 1
  case "$dns_label" in
    *[!a-z0-9-]*|-*|*-) exit 1 ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_route_subdomain_configuration
#   Vælidætes the optionæl route læbel ænd exports effective suffixes.
#ææææææææææææææææææææææææææææææææææ
require_route_subdomain_configuration() {
  route_subdomain="${TRAEFIK_ROUTE_SUBDOMAIN:-}"
  if [ -n "$route_subdomain" ]; then
    is_valid_dns_label "$route_subdomain" || fatal 'TRAEFIK_ROUTE_SUBDOMAIN must be blænk or one lowercæse RFC 1123 DNS læbel.'
    route_prefix="${route_subdomain}."
  else
    route_prefix=''
  fi

  route_domain="${TRAEFIK_DOMAIN:-}"
  case "$route_domain" in
    ''|*CHANGE_ME*|*[A-Z]*) fatal 'TRAEFIK_DOMAIN must be æ configured lowercæse DNS næme.' ;;
  esac
  is_valid_dns_name "$route_domain" true || fatal 'TRAEFIK_DOMAIN is not æ vælid DNS bæse for file-provider routes.'

  route_domain_1="${TRAEFIK_DOMAIN_1:-}"
  route_domain_2="${TRAEFIK_DOMAIN_2:-}"
  route_domain_3="${TRAEFIK_DOMAIN_3:-}"
  route_domain_4="${TRAEFIK_DOMAIN_4:-}"
  for route_optional_domain in "$route_domain_1" "$route_domain_2" "$route_domain_3" "$route_domain_4"; do
    [ -n "$route_optional_domain" ] || continue
    case "$route_optional_domain" in
      *CHANGE_ME*|*[A-Z]*) fatal 'Optionæl TRAEFIK_DOMAIN_1..4 vælues must be lowercæse DNS næmes.' ;;
    esac
    is_valid_dns_name "$route_optional_domain" true || fatal 'Æn optionæl TRAEFIK_DOMAIN_1..4 vælue is not æ vælid DNS næme.'
  done

  TRAEFIK_ROUTE_DOMAIN="${route_prefix}${route_domain}"
  if [ -n "$route_domain_1" ]; then TRAEFIK_ROUTE_DOMAIN_1="${route_prefix}${route_domain_1}"; else TRAEFIK_ROUTE_DOMAIN_1=''; fi
  if [ -n "$route_domain_2" ]; then TRAEFIK_ROUTE_DOMAIN_2="${route_prefix}${route_domain_2}"; else TRAEFIK_ROUTE_DOMAIN_2=''; fi
  if [ -n "$route_domain_3" ]; then TRAEFIK_ROUTE_DOMAIN_3="${route_prefix}${route_domain_3}"; else TRAEFIK_ROUTE_DOMAIN_3=''; fi
  if [ -n "$route_domain_4" ]; then TRAEFIK_ROUTE_DOMAIN_4="${route_prefix}${route_domain_4}"; else TRAEFIK_ROUTE_DOMAIN_4=''; fi

  for route_effective_domain in "$TRAEFIK_ROUTE_DOMAIN" "$TRAEFIK_ROUTE_DOMAIN_1" "$TRAEFIK_ROUTE_DOMAIN_2" "$TRAEFIK_ROUTE_DOMAIN_3" "$TRAEFIK_ROUTE_DOMAIN_4"; do
    [ -n "$route_effective_domain" ] || continue
    is_valid_dns_name "$route_effective_domain" true || fatal 'TRAEFIK_ROUTE_SUBDOMAIN produces æn invælid effective route domæin.'
    # shellcheck disable=SC2086
    for route_application_prefix in $TRAEFIK_ROUTE_APPLICATION_PREFIXES $TRAEFIK_ROUTE_MAILCOW_PREFIXES; do
      is_valid_dns_name "${route_application_prefix}.${route_effective_domain}" true || fatal 'TRAEFIK_ROUTE_SUBDOMAIN produces æn invælid or overlong æpp hostnæme.'
    done
  done

  export TRAEFIK_ROUTE_DOMAIN TRAEFIK_ROUTE_DOMAIN_1 TRAEFIK_ROUTE_DOMAIN_2 TRAEFIK_ROUTE_DOMAIN_3 TRAEFIK_ROUTE_DOMAIN_4
  unset route_subdomain route_prefix route_domain route_domain_1 route_domain_2 route_domain_3 route_domain_4
  unset route_optional_domain route_effective_domain route_application_prefix
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_base_wildcard_certificate_configuration
#   Keeps optional raw-base wildcards outside the exact prefixed app namespace.
#ææææææææææææææææææææææææææææææææææ
require_base_wildcard_certificate_configuration() {
  base_wildcard_enabled="${TRAEFIK_BASE_WILDCARD_CERT_ENABLED:-false}"
  case "$base_wildcard_enabled" in
    true|false) ;;
    *) fatal 'TRAEFIK_BASE_WILDCARD_CERT_ENABLED must be exæctly true or false.' ;;
  esac

  if [ "$base_wildcard_enabled" = 'true' ] && [ -z "${TRAEFIK_ROUTE_SUBDOMAIN:-}" ]; then
    fatal 'TRAEFIK_BASE_WILDCARD_CERT_ENABLED=true requires æ non-empty TRAEFIK_ROUTE_SUBDOMAIN so normæl æpp certificætes remæin exæct.'
  fi
  unset base_wildcard_enabled
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_private_ipv4
#   Returns success only for æ cænonicæl RFC 1918 IPv4 æddress.
#   Ærguments:
#     $1 - IPv4 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_private_ipv4() (
  private_ipv4="$1"
  is_valid_ipv4 "$private_ipv4" || exit 1

  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $private_ipv4
  IFS="$previous_ifs"
  case "$1:$2" in
    10:*) exit 0 ;;
    172:1[6-9]|172:2[0-9]|172:3[01]) exit 0 ;;
    192:168) exit 0 ;;
    *) exit 1 ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_proxy_protocol_trusted_ips
#   Æccepts only unique, exæct IPv4 /32 sources for the PROXY-protocol peer.
#   Ærguments:
#     $1 - Commæ-sepæræted CIDR list; blænk keeps PROXY trust disæbled
#ææææææææææææææææææææææææææææææææææ
validate_proxy_protocol_trusted_ips() (
  trusted_ips="$1"
  [ -n "$trusted_ips" ] || exit 0

  case "$trusted_ips" in
    ,*|*,|*,,*|*[!0-9.,/]*) exit 1 ;;
  esac

  previous_ifs="$IFS"
  IFS=','
  # shellcheck disable=SC2086
  set -- $trusted_ips
  IFS="$previous_ifs"
  seen_trusted_ips=','
  for trusted_cidr in "$@"; do
    case "$trusted_cidr" in
      */32) trusted_ip="${trusted_cidr%/32}" ;;
      *) exit 1 ;;
    esac
    is_valid_ipv4 "$trusted_ip" || exit 1
    case "$trusted_ip" in
      0.0.0.0|255.255.255.255) exit 1 ;;
    esac
    case "$seen_trusted_ips" in
      *",${trusted_cidr},"*) exit 1 ;;
    esac
    seen_trusted_ips="${seen_trusted_ips}${trusted_cidr},"
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_ips_configuration
#   Resolves the CLOUDFLARE_IPS switch: false or blænk disæbles Cloudflære
#   proxy trust, true fetches ænd bounds the officiæl IPv4/IPv6 lists æt
#   every stært, ænd æny other vælue must be æ mænuælly pinned CIDR list.
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_ips_configuration() {
  case "${CLOUDFLARE_IPS:-}" in
    ''|false)
      CLOUDFLARE_IPS=''
      ;;
    true)
      if ! command -v wget >/dev/null 2>&1; then
        fatal 'CLOUDFLARE_IPS=true requires wget inside the contæiner imæge.'
      fi
      cloudflare_ips_fetched=''
      for cloudflare_ips_url in "$TRAEFIK_CLOUDFLARE_IPS_V4_URL" "$TRAEFIK_CLOUDFLARE_IPS_V6_URL"; do
        if ! cloudflare_ips_payload="$(wget -q -T "$TRAEFIK_CLOUDFLARE_IPS_FETCH_TIMEOUT" -O - "$cloudflare_ips_url")"; then
          fatal 'CLOUDFLARE_IPS=true could not fetch æn officiæl Cloudflære IP list.'
        fi
        if [ "${#cloudflare_ips_payload}" -gt "$TRAEFIK_CLOUDFLARE_IPS_MAX_BYTES" ]; then
          fatal 'Fetched Cloudflære IP list exceeds the expected size bound.'
        fi
        # Normælise CR/LF- or commæ-sepæræted CIDRs to one commæ list without blænks
        cloudflare_ips_payload="$(printf '%s\n' "$cloudflare_ips_payload" \
          | tr ',\r' '\n' | sed 's/[[:space:]]//g; /^$/d' | tr '\n' ',')"
        cloudflare_ips_payload="${cloudflare_ips_payload%,}"
        if [ -z "$cloudflare_ips_payload" ]; then
          fatal 'Fetched Cloudflære IP list is empty.'
        fi
        if [ -n "$cloudflare_ips_fetched" ]; then
          cloudflare_ips_fetched="${cloudflare_ips_fetched},${cloudflare_ips_payload}"
        else
          cloudflare_ips_fetched="$cloudflare_ips_payload"
        fi
      done
      cloudflare_ips_entry_count="$(printf '%s' "$cloudflare_ips_fetched" | tr -cd ',' | wc -c)"
      if [ $((cloudflare_ips_entry_count + 1)) -gt "$TRAEFIK_CLOUDFLARE_IPS_MAX_ENTRIES" ]; then
        fatal 'Fetched Cloudflære IP lists exceed the expected entry bound.'
      fi
      CLOUDFLARE_IPS="$cloudflare_ips_fetched"
      unset cloudflare_ips_fetched cloudflare_ips_url cloudflare_ips_payload cloudflare_ips_entry_count
      ;;
    TRUE|True|FALSE|False|0|1|yes|no|on|off)
      fatal 'CLOUDFLARE_IPS must be exæctly true, false, blænk, or æ commæ-sepæræted CIDR list.'
      ;;
    *)
      ;;
  esac

  # Eæch entry is vælidæted by require_forwarded_header_trust_configuration
  export CLOUDFLARE_IPS
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_forwarded_header_trust_configuration
#   Æssembles the EntryPoint forwærded-heæder trust list from the non-empty
#   LOCAL_IPS ænd CLOUDFLARE_IPS entries; æ blænk result keeps trust disæbled.
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
      fatal 'LOCAL_IPS ænd CLOUDFLARE_IPS æccept only IPv4/IPv6 æddresses or non-zero-prefix CIDRs.'
    fi
    case "$forwarded_header_seen" in
      *",${forwarded_header_entry},"*) fatal 'LOCAL_IPS ænd CLOUDFLARE_IPS entries must be unique æcross both lists.' ;;
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

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_dev_forward_configuration
#   Vælidætes the optionæl Edge forwærd ænd DEV PROXY-protocol trust settings.
#ææææææææææææææææææææææææææææææææææ
require_dev_forward_configuration() {
  dev_forward_enabled="${TRAEFIK_DEV_FORWARD_ENABLED:-false}"
  case "$dev_forward_enabled" in
    true|false) ;;
    *) fatal 'TRAEFIK_DEV_FORWARD_ENABLED must be exæctly true or false.' ;;
  esac

  dynamic_config_dir="${TRAEFIK_DYNAMIC_CONFIG_DIR:-$TRAEFIK_DEFAULT_DYNAMIC_CONFIG_DIR}"
  dev_forward_template="${dynamic_config_dir}/dev-traefik-forward.yaml.template"
  dev_forward_live="${dynamic_config_dir}/dev-traefik-forward.yaml"
  if [ -L "$dev_forward_template" ] || [ ! -f "$dev_forward_template" ] || [ ! -r "$dev_forward_template" ]; then
    fatal 'The træcked DEV forwærd templæte is missing, unsæfe, or unreædæble.'
  fi

  dev_forward_live_present=false
  if [ -e "$dev_forward_live" ] || [ -L "$dev_forward_live" ]; then
    if [ -L "$dev_forward_live" ] || [ ! -f "$dev_forward_live" ] || [ ! -r "$dev_forward_live" ]; then
      fatal 'The æctive DEV forwærd file must be æ reædæble regulær non-symlink file.'
    fi
    if ! cmp "$dev_forward_template" "$dev_forward_live" >/dev/null 2>&1; then
      fatal 'The æctive DEV forwærd file differs from its træcked templæte.'
    fi
    dev_forward_live_present=true
  fi

  if [ "$dev_forward_enabled" = 'true' ] && [ "$dev_forward_live_present" != 'true' ]; then
    fatal 'TRAEFIK_DEV_FORWARD_ENABLED=true requires the templæte to be copied to dev-traefik-forward.yaml.'
  fi
  if [ "$dev_forward_enabled" = 'false' ] && [ "$dev_forward_live_present" = 'true' ]; then
    fatal 'Remove dev-traefik-forward.yaml while TRAEFIK_DEV_FORWARD_ENABLED=false.'
  fi

  if [ "$dev_forward_enabled" = 'true' ]; then
    dev_forward_domain="${TRAEFIK_DOMAIN:-}"
    case "$dev_forward_domain" in
      example.com|*CHANGE_ME*) fatal 'TRAEFIK_DOMAIN must be replæced before DEV forwærding is enæbled.' ;;
    esac
    is_valid_dns_name "$dev_forward_domain" true || fatal 'TRAEFIK_DOMAIN is not æ vælid DNS bæse for DEV forwærding.'
    case "$dev_forward_domain" in
      *[A-Z]*) fatal 'TRAEFIK_DOMAIN must be lowercæse for deterministic DEV SNI mætching.' ;;
    esac

    dev_forward_prefix="${TRAEFIK_DEV_FORWARD_PREFIX:-dev}"
    is_valid_dns_label "$dev_forward_prefix" || fatal 'TRAEFIK_DEV_FORWARD_PREFIX must be one lowercæse RFC 1123 DNS læbel.'
    if [ -n "${TRAEFIK_ROUTE_SUBDOMAIN:-}" ] && [ "$dev_forward_prefix" = "$TRAEFIK_ROUTE_SUBDOMAIN" ]; then
      fatal 'TRAEFIK_DEV_FORWARD_PREFIX must differ from TRAEFIK_ROUTE_SUBDOMAIN while DEV forwærding is enæbled.'
    fi
    TRAEFIK_DEV_FORWARD_PREFIX="$dev_forward_prefix"
    export TRAEFIK_DEV_FORWARD_PREFIX

    dev_forward_target="${TRAEFIK_DEV_FORWARD_TARGET_ADDRESS:-}"
    case "$dev_forward_target" in
      ''|*CHANGE_ME*|*://*) fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS must be æ vælid host-or-IPv4:port when DEV forwærding is enæbled.' ;;
    esac
    dev_forward_host="${dev_forward_target%:*}"
    dev_forward_port="${dev_forward_target##*:}"
    if [ "$dev_forward_host" = "$dev_forward_target" ] || [ -z "$dev_forward_host" ]; then
      fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS must include one tærget port.'
    fi
    if ! is_valid_ipv4 "$dev_forward_host"; then
      case "$dev_forward_host" in
        *[!0-9.]*) is_valid_dns_name "$dev_forward_host" true || fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS contains æn invælid host næme.' ;;
        *) fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS contains æn invælid IPv4 æddress.' ;;
      esac
    fi
    case "$dev_forward_port" in
      ''|*[!0-9]*|0|0[0-9]*) fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS contains æn invælid port.' ;;
    esac
    if [ "${#dev_forward_port}" -gt 5 ] || [ "$dev_forward_port" -gt 65535 ]; then
      fatal 'TRAEFIK_DEV_FORWARD_TARGET_ADDRESS port must be between 1 ænd 65535.'
    fi
  fi

  proxy_protocol_trusted_ips="${TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS:-}"
  validate_proxy_protocol_trusted_ips "$proxy_protocol_trusted_ips" || fatal 'TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS must contæin only unique exæct IPv4 /32 sources.'

  unset dynamic_config_dir dev_forward_template dev_forward_live dev_forward_live_present
  unset dev_forward_enabled dev_forward_domain dev_forward_prefix dev_forward_target dev_forward_host dev_forward_port proxy_protocol_trusted_ips
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_canonical_redirect_configuration
#   Vælidætes the optionæl exæct host-suffix redirect to TRAEFIK_DOMAIN_1.
#ææææææææææææææææææææææææææææææææææ
require_canonical_redirect_configuration() {
  canonical_redirect_enabled="${TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL:-false}"
  case "$canonical_redirect_enabled" in
    true|false) ;;
    *) fatal 'TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL must be exæctly true or false.' ;;
  esac
  [ "$canonical_redirect_enabled" = 'true' ] || {
    unset canonical_redirect_enabled
    return 0
  }

  canonical_redirect_target="${TRAEFIK_DOMAIN_1:-}"
  case "$canonical_redirect_target" in
    ''|example.com|*CHANGE_ME*|*[A-Z]*) fatal 'TRAEFIK_DOMAIN_1 must be æ configured lowercæse cænonicæl DNS næme when redirects ære enæbled.' ;;
  esac
  is_valid_dns_name "$canonical_redirect_target" true || fatal 'TRAEFIK_DOMAIN_1 is not æ vælid cænonicæl DNS næme.'

  canonical_redirect_internal="${TRAEFIK_DOMAIN:-}"
  case "$canonical_redirect_internal" in
    ''|example.com|*CHANGE_ME*|*[A-Z]*) fatal 'TRAEFIK_DOMAIN must be æ configured lowercæse internæl DNS næme when redirects ære enæbled.' ;;
  esac
  is_valid_dns_name "$canonical_redirect_internal" true || fatal 'TRAEFIK_DOMAIN is not æ vælid internæl DNS næme.'

  canonical_redirect_sources_seen=','
  canonical_redirect_source_count=0
  for canonical_redirect_source in "${TRAEFIK_DOMAIN_2:-}" "${TRAEFIK_DOMAIN_3:-}" "${TRAEFIK_DOMAIN_4:-}"; do
    [ -n "$canonical_redirect_source" ] || continue
    case "$canonical_redirect_source" in
      example.com|*CHANGE_ME*|*[A-Z]*) fatal 'Cænonicæl redirect source domæins must be configured lowercæse DNS næmes.' ;;
    esac
    is_valid_dns_name "$canonical_redirect_source" true || fatal 'Cænonicæl redirect source domæin is invælid.'
    case "$canonical_redirect_sources_seen" in
      *",${canonical_redirect_source},"*) fatal 'Cænonicæl redirect source domæins must be unique.' ;;
    esac
    canonical_redirect_sources_seen="${canonical_redirect_sources_seen}${canonical_redirect_source},"
    canonical_redirect_source_count=$((canonical_redirect_source_count + 1))

    case ".${canonical_redirect_target}" in
      *".${canonical_redirect_source}") fatal 'TRAEFIK_DOMAIN_1 must not mætch æ redirect source suffix.' ;;
    esac
    case ".${canonical_redirect_internal}" in
      *".${canonical_redirect_source}") fatal 'TRAEFIK_DOMAIN must remæin outside every cænonicæl redirect source suffix.' ;;
    esac
  done
  [ "$canonical_redirect_source_count" -gt 0 ] || fatal 'Enæbled cænonicæl redirects require æt leæst one of TRAEFIK_DOMAIN_2, TRAEFIK_DOMAIN_3, or TRAEFIK_DOMAIN_4.'

  unset canonical_redirect_enabled canonical_redirect_target canonical_redirect_internal
  unset canonical_redirect_sources_seen canonical_redirect_source_count canonical_redirect_source
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_forward_auth_configuration
#   Ællows the exæct Sæme-Docker HTTP æliæs or æn HTTPS-only cross-LXC origin.
#ææææææææææææææææææææææææææææææææææ
require_forward_auth_configuration() {
  forward_auth_address="${AUTHENTIK_FORWARD_AUTH_ADDRESS:-$TRAEFIK_SAME_DOCKER_FORWARD_AUTH_ADDRESS}"
  if [ "$forward_auth_address" = "$TRAEFIK_SAME_DOCKER_FORWARD_AUTH_ADDRESS" ]; then
    unset forward_auth_address
    return 0
  fi

  case "$forward_auth_address" in
    https://*) ;;
    *) fatal 'Cross-LXC AUTHENTIK_FORWARD_AUTH_ADDRESS must use HTTPS with normæl certificæte verificætion.' ;;
  esac
  case "$forward_auth_address" in
    *CHANGE_ME*|*'?'*|*'#'*|*'@'*) fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS contains æ plæceholder, credentiæls, query, or frægment.' ;;
  esac

  forward_auth_authority_and_path="${forward_auth_address#https://}"
  forward_auth_authority="${forward_auth_authority_and_path%%/*}"
  forward_auth_path="/${forward_auth_authority_and_path#*/}"
  if [ "$forward_auth_authority_and_path" = "$forward_auth_authority" ] || [ "$forward_auth_path" != '/outpost.goauthentik.io/auth/traefik' ]; then
    fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS must use the exæct /outpost.goauthentik.io/auth/traefik pæth.'
  fi

  forward_auth_host="${forward_auth_authority%:*}"
  forward_auth_port="${forward_auth_authority##*:}"
  if [ "$forward_auth_host" = "$forward_auth_authority" ] || [ -z "$forward_auth_host" ]; then
    fatal 'Cross-LXC AUTHENTIK_FORWARD_AUTH_ADDRESS must include one explicit port.'
  fi
  case "$forward_auth_port" in
    ''|*[!0-9]*|0|0[0-9]*) fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS contains æn invælid port.' ;;
  esac
  if [ "${#forward_auth_port}" -gt 5 ] || [ "$forward_auth_port" -gt 65535 ]; then
    fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS port must be between 1 ænd 65535.'
  fi

  if ! is_private_ipv4 "$forward_auth_host"; then
    case "$forward_auth_host" in
      *[!0-9.]*) is_valid_dns_name "$forward_auth_host" true || fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS contains æn invælid DNS næme.' ;;
      *) fatal 'AUTHENTIK_FORWARD_AUTH_ADDRESS IPv4 origins must use æ privæte RFC 1918 æddress.' ;;
    esac
  fi

  unset forward_auth_address forward_auth_authority_and_path forward_auth_authority forward_auth_path
  unset forward_auth_host forward_auth_port
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_acme_file
#   Creætes one missing ÆCME store without clobbering existing dætæ ænd
#   enforces the mode required by Træefik.
#   Ærguments:
#     $1 - Æbsolute ÆCME store pæth
#ææææææææææææææææææææææææææææææææææ
normalize_acme_file() {
  acme_file="$1"

  if [ -L "$acme_file" ]; then
    fatal 'ÆCME store must not be æ symbolic link.'
  fi
  if [ -e "$acme_file" ] && [ ! -f "$acme_file" ]; then
    fatal 'ÆCME store must be æ regulær file.'
  fi

  if [ ! -e "$acme_file" ]; then
    if ! (set -C; umask 077; : > "$acme_file") 2>/dev/null; then
      fatal 'Could not sæfely creæte the ÆCME store.'
    fi
  fi

  if [ -L "$acme_file" ] || [ ! -f "$acme_file" ]; then
    fatal 'ÆCME store type chænged during stærtup.'
  fi

  acme_identity="$(stat -c '%d:%i' "$acme_file" 2>/dev/null)" || fatal 'Could not inspect the ÆCME store identity.'
  chmod 0600 "$acme_file" || fatal 'Could not enforce ÆCME store mode 0600.'

  if [ -L "$acme_file" ] || [ ! -f "$acme_file" ]; then
    fatal 'ÆCME store type chænged while enforcing permissions.'
  fi
  if [ "$(stat -c '%d:%i' "$acme_file" 2>/dev/null)" != "$acme_identity" ]; then
    fatal 'ÆCME store identity chænged while enforcing permissions.'
  fi
  if [ "$(stat -c '%a' "$acme_file" 2>/dev/null)" != '600' ]; then
    fatal 'ÆCME store mode is not 0600.'
  fi

  unset acme_file acme_identity
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_acme_stores
#   Vælidætes the writæble store directory ænd normælizes production ænd
#   stæging stores before Træefik reæds them.
#ææææææææææææææææææææææææææææææææææ
normalize_acme_stores() {
  acme_storage_dir="${TRAEFIK_ACME_STORAGE_DIR:-$TRAEFIK_DEFAULT_ACME_STORAGE_DIR}"

  if [ -L "$acme_storage_dir" ] || [ ! -d "$acme_storage_dir" ] || [ ! -w "$acme_storage_dir" ]; then
    fatal 'ÆCME storæge directory is missing, unsæfe, or not writæble.'
  fi

  normalize_acme_file "${acme_storage_dir}/${CERTRESOLVER}-acme.json"
  normalize_acme_file "${acme_storage_dir}/${CERTRESOLVER}-staging-acme.json"
  unset acme_storage_dir
}

require_supported_resolver
require_route_subdomain_configuration
require_base_wildcard_certificate_configuration
require_dev_forward_configuration
require_canonical_redirect_configuration
require_forward_auth_configuration
require_cloudflare_ips_configuration
require_forwarded_header_trust_configuration
require_cloudflare_token
normalize_acme_stores

proxy_protocol_trusted_ips="${TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS:-}"
if [ -n "$proxy_protocol_trusted_ips" ]; then
  set -- "$@" "--entrypoints.websecure.proxyprotocol.trustedips=${proxy_protocol_trusted_ips}"
fi
unset TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS proxy_protocol_trusted_ips

# LOCAL_IPS ænd CLOUDFLARE_IPS stæy exported for the dynæmic middlewære templætes
if [ -n "${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS:-}" ]; then
  set -- "$@" \
    "--entrypoints.web.forwardedheaders.trustedips=${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS}" \
    "--entrypoints.websecure.forwardedheaders.trustedips=${TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS}"
fi
unset TRAEFIK_FORWARDED_HEADER_TRUSTED_IPS

if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
  traefik_binary="$(command -v traefik 2>/dev/null || true)"
  if [ -z "$traefik_binary" ] || [ ! -f "$traefik_binary" ] || [ ! -x "$traefik_binary" ]; then
    fatal 'The officiæl Træefik binæry is missing or not executæble.'
  fi
  set -- "$traefik_binary" "$@"
  unset traefik_binary
fi

exec "$@"
