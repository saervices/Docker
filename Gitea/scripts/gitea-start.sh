#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GITEÆ ENTRYPOINT WRÆPPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes Docker secrets, builds æ Redis URL on locked tmpfs, ænd
# then execs the vendor rootless entrypoint. Secret vælues never
# æppeær in Compose environment blocks, dæmon ærgv, or logs.

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

readonly SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly GITEA_SECRET_MAX_BYTES=4096
readonly GITEA_SECRET_READER="${GITEA_SECRET_READER:-/usr/local/bin/gitea-secret-reader}"
readonly GITEA_RUNTIME_DIR="${GITEA_RUNTIME_DIR:-/run/gitea}"
readonly GITEA_REDIS_URL_FILE="${GITEA_RUNTIME_DIR}/redis.url"
readonly GITEA_VENDOR_ENTRYPOINT="${GITEA_VENDOR_ENTRYPOINT:-/usr/local/bin/docker-entrypoint.sh}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing secret content, then stops.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[gitea] ERROR: %s\n' "$*" >&2
    exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_single_line_secret
#   Uses the stætic descriptor-bæsed reæder to reject links, speciæl
#   nodes, identity ræces, invælid UTF-8, ænd control chæræcters.
#   Ærguments:
#     $1 - secret filenæme under SECRET_DIR
#ææææææææææææææææææææææææææææææææææ
load_required_single_line_secret() {
    _secret_name="$1"
    if [ ! -x "${GITEA_SECRET_READER}" ]; then
        fatal 'Descriptor-bæsed Gitea secret reæder is missing or not executæble.'
    fi
    if ! GITEA_SECRET_VALUE="$("${GITEA_SECRET_READER}" --directory "${SECRET_DIR}" "${_secret_name}")"; then
        fatal "Required secret ${_secret_name} could not be loæded sæfely."
    fi
    unset _secret_name
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_required_single_line_secret
#   Vælidætes one secret without retæining its pæyloæd.
#   Ærguments:
#     $1 - secret filenæme under SECRET_DIR
#ææææææææææææææææææææææææææææææææææ
validate_required_single_line_secret() {
    load_required_single_line_secret "$1"
    unset GITEA_SECRET_VALUE
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_required_exact_length_secret
#   Vælidætes one locæl Giteæ secret ægæinst its exæct byte length.
#   Ærguments:
#     $1 - secret filenæme under SECRET_DIR
#     $2 - required byte length
#ææææææææææææææææææææææææææææææææææ
validate_required_exact_length_secret() {
    _exact_secret_name="$1"
    _exact_secret_bytes="$2"
    load_required_single_line_secret "${_exact_secret_name}"
    _exact_actual_bytes="$(printf '%s' "${GITEA_SECRET_VALUE}" | wc -c)" || \
        fatal "Required secret ${_exact_secret_name} length could not be verified."
    unset GITEA_SECRET_VALUE
    if [ "${_exact_actual_bytes}" -ne "${_exact_secret_bytes}" ]; then
        fatal "Required secret ${_exact_secret_name} must have exactly ${_exact_secret_bytes} bytes."
    fi
    unset _exact_secret_name _exact_secret_bytes _exact_actual_bytes
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_required_environment_value
#   Rejects empty, plæceholder, oversized, invælid UTF-8, multiline,
#   ænd control-chæræcter configurætion without logging its vælue.
#   Ærguments:
#     $1 - environment field næme
#     $2 - field vælue
#ææææææææææææææææææææææææææææææææææ
validate_required_environment_value() {
    _environment_field="$1"
    _environment_value="$2"
    if [ -z "${_environment_value}" ] || [ "${_environment_value}" = 'CHANGE_ME' ]; then
        fatal "${_environment_field} is missing or still contains the plæceholder vælue."
    fi
    _environment_size="$(printf '%s' "${_environment_value}" | wc -c)" || \
        fatal "${_environment_field} length could not be verified."
    if [ "${_environment_size}" -gt "${GITEA_SECRET_MAX_BYTES}" ]; then
        fatal "${_environment_field} is too long."
    fi
    _environment_line_free_size="$(printf '%s' "${_environment_value}" | LC_ALL=C tr -d '\n\r' | wc -c)" || \
        fatal "${_environment_field} line structure could not be verified."
    if [ "${_environment_line_free_size}" -ne "${_environment_size}" ]; then
        fatal "${_environment_field} contains line breæks."
    fi
    command -v iconv >/dev/null 2>&1 || fatal 'Required UTF-8 vælidætor iconv is missing.'
    if ! printf '%s' "${_environment_value}" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        fatal "${_environment_field} is not vælid UTF-8."
    fi
    if printf '%s' "${_environment_value}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        fatal "${_environment_field} contains control chæræcters or line breæks."
    fi
    unset _environment_field _environment_value _environment_size _environment_line_free_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_lowercase_dns_hostname
#   Requires one lowercæse DNS hostnæme without URL/userinfo syntax.
#   Ærguments:
#     $1 - environment field næme
#     $2 - hostnæme vælue
#ææææææææææææææææææææææææææææææææææ
validate_lowercase_dns_hostname() {
    _dns_field="$1"
    _dns_value="$2"
    validate_required_environment_value "${_dns_field}" "${_dns_value}"
    _dns_size="$(printf '%s' "${_dns_value}" | wc -c)" || fatal "${_dns_field} length could not be verified."
    case "${_dns_value}" in
        *[!a-z0-9.-]*|.*|*.|*..*)
            fatal "${_dns_field} must be æ lowercæse DNS hostnæme."
            ;;
    esac
    if [ "${_dns_size}" -gt 253 ] || ! printf '%s\n' "${_dns_value}" | LC_ALL=C awk -F. '
        {
            for (i = 1; i <= NF; i++) {
                if (length($i) < 1 || length($i) > 63 ||
                    $i !~ /^[a-z0-9]/ || $i !~ /[a-z0-9]$/) {
                    exit 1
                }
            }
        }
    '; then
        fatal "${_dns_field} must be æ lowercæse DNS hostnæme."
    fi
    unset _dns_field _dns_value _dns_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_lowercase_token
#   Requires one bounded lowercæse URL-pæth token.
#   Ærguments:
#     $1 - environment field næme
#     $2 - token vælue
#ææææææææææææææææææææææææææææææææææ
validate_lowercase_token() {
    _token_field="$1"
    _token_value="$2"
    validate_required_environment_value "${_token_field}" "${_token_value}"
    _token_size="$(printf '%s' "${_token_value}" | wc -c)" || fatal "${_token_field} length could not be verified."
    case "${_token_value}" in
        *[!a-z0-9-]*|-*|*-)
            fatal "${_token_field} must be æ sæfe lowercæse token."
            ;;
    esac
    if [ "${_token_size}" -gt 63 ]; then
        fatal "${_token_field} must be æ sæfe lowercæse token."
    fi
    unset _token_field _token_value _token_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailbox_address
#   Requires one pure mailbox æddress with æ lowercæse DNS domæin.
#   Ærguments:
#     $1 - environment field næme
#     $2 - mailbox vælue
#ææææææææææææææææææææææææææææææææææ
validate_mailbox_address() {
    _mailbox_field="$1"
    _mailbox_value="$2"
    validate_required_environment_value "${_mailbox_field}" "${_mailbox_value}"
    case "${_mailbox_value}" in
        *'<'*|*'>'*|*' '*) fatal "${_mailbox_field} must be æ pure mailbox æddress." ;;
    esac
    _mailbox_local="${_mailbox_value%@*}"
    _mailbox_domain="${_mailbox_value##*@}"
    if [ "${_mailbox_local}" = "${_mailbox_value}" ] || [ "${_mailbox_domain}" = "${_mailbox_value}" ]; then
        fatal "${_mailbox_field} must be æ pure mailbox æddress."
    fi
    case "${_mailbox_local}" in
        ''|*@*|.*|*.|*..*) fatal "${_mailbox_field} must be æ pure mailbox æddress." ;;
    esac
    if ! printf '%s\n' "${_mailbox_local}" | LC_ALL=C grep -Eq '^[A-Za-z0-9.!#$%&*+/=?^_`{|}~-]+$'; then
        fatal "${_mailbox_field} must be æ pure mailbox æddress."
    fi
    validate_lowercase_dns_hostname "${_mailbox_field} domæin" "${_mailbox_domain}"
    if [ "${_mailbox_domain}" = 'example.com' ]; then
        fatal "${_mailbox_field} must not use the exæmple.com plæceholder domæin."
    fi
    unset _mailbox_field _mailbox_value _mailbox_local _mailbox_domain
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_trusted_proxy_cidrs
#   Requires exæct loopbæck CIDRs plus non-overlæpping cænonicæl
#   privæte RFC1918 /16-or-narrower or ULÆ /64-or-narrower peers.
#ææææææææææææææææææææææææææææææææææ
validate_trusted_proxy_cidrs() {
    _proxy_cidrs="${GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES:-}"
    validate_required_environment_value GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES "${_proxy_cidrs}"
    case "${_proxy_cidrs}" in
        ,*|*,|*,,*|*[!0-9a-fA-F:.,/]*)
            fatal 'GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES is mælformed.'
            ;;
    esac
    if ! printf '%s\n' "${_proxy_cidrs}" | LC_ALL=C awk -F, '
        function fail() { exit 1 }
        function pow2(n,    p) { p = 1; while (n-- > 0) p *= 2; return p }
        function hex_value(text,    digits,value,i,position) {
            digits = "0123456789abcdef"
            if (length(text) < 1 || length(text) > 4) return -1
            value = 0
            for (i = 1; i <= length(text); i++) {
                position = index(digits, substr(text, i, 1)) - 1
                if (position < 0) return -1
                value = value * 16 + position
            }
            return value
        }
        function parse_ipv6(address, output,    marker,left,right,nl,nr,i,count,value,temp) {
            if (address !~ /^[0-9a-f:]+$/) return 0
            marker = index(address, "::")
            if (marker > 0) {
                left = substr(address, 1, marker - 1)
                right = substr(address, marker + 2)
                if (index(right, "::") > 0) return 0
                nl = left == "" ? 0 : split(left, temp, ":")
                count = 0
                for (i = 1; i <= nl; i++) {
                    value = hex_value(temp[i]); if (value < 0) return 0
                    output[++count] = value
                }
                nr = right == "" ? 0 : split(right, temp, ":")
                if (nl + nr >= 8) return 0
                for (i = nl + nr + 1; i <= 8; i++) output[++count] = 0
                for (i = 1; i <= nr; i++) {
                    value = hex_value(temp[i]); if (value < 0) return 0
                    output[++count] = value
                }
                return count == 8
            }
            count = split(address, temp, ":")
            if (count != 8) return 0
            for (i = 1; i <= 8; i++) {
                value = hex_value(temp[i]); if (value < 0) return 0
                output[i] = value
            }
            return 1
        }
        function ipv6_prefix_equal(saved_index, current, prefix,    full,remain,i,divisor) {
            full = int(prefix / 16); remain = prefix % 16
            for (i = 1; i <= full; i++) if (v6[saved_index, i] != current[i]) return 0
            if (remain > 0) {
                divisor = pow2(16 - remain)
                if (int(v6[saved_index, full + 1] / divisor) != int(current[full + 1] / divisor)) return 0
            }
            return 1
        }
        {
            for (entry_index = 1; entry_index <= NF; entry_index++) {
                entry = $entry_index
                if (entry == "127.0.0.0/8") { loopback4++; continue }
                if (entry == "::1/128") { loopback6++; continue }

                slash_count = split(entry, cidr, "/")
                if (slash_count != 2 || cidr[2] !~ /^(0|[1-9][0-9]*)$/) fail()
                prefix = cidr[2] + 0

                if (index(cidr[1], ":") == 0) {
                    if (prefix < 16 || prefix > 32) fail()
                    if (split(cidr[1], octet, ".") != 4) fail()
                    ip = 0
                    for (i = 1; i <= 4; i++) {
                        if (octet[i] !~ /^(0|[1-9][0-9]*)$/ || octet[i] + 0 > 255) fail()
                        ip = ip * 256 + octet[i]
                    }
                    block = pow2(32 - prefix)
                    if (ip % block != 0) fail()
                    first = octet[1] + 0; second = octet[2] + 0
                    if (! (first == 10 || (first == 172 && second >= 16 && second <= 31) ||
                           (first == 192 && second == 168))) fail()
                    start = ip; finish = ip + block - 1
                    for (i = 1; i <= v4_count; i++) if (start <= v4_end[i] && finish >= v4_start[i]) fail()
                    v4_start[++v4_count] = start; v4_end[v4_count] = finish
                    private_count++
                    continue
                }

                if (prefix < 64 || prefix > 128 || !parse_ipv6(cidr[1], current_v6)) fail()
                if (current_v6[1] < 64512 || current_v6[1] > 65023) fail()
                full = int(prefix / 16); remain = prefix % 16
                if (remain > 0 && current_v6[full + 1] % pow2(16 - remain) != 0) fail()
                for (i = full + (remain > 0 ? 2 : 1); i <= 8; i++) if (current_v6[i] != 0) fail()
                for (i = 1; i <= v6_count; i++) {
                    common = prefix < v6_prefix[i] ? prefix : v6_prefix[i]
                    if (ipv6_prefix_equal(i, current_v6, common)) fail()
                }
                v6_count++
                v6_prefix[v6_count] = prefix
                for (i = 1; i <= 8; i++) v6[v6_count, i] = current_v6[i]
                private_count++
            }
        }
        END {
            if (loopback4 != 1 || loopback6 != 1 || private_count < 1) exit 1
        }
    '; then
        fatal 'GITEA__security__REVERSE_PROXY_TRUSTED_PROXIES must contain exæct loopbæck plus reviewed cænonicæl privæte CIDRs.'
    fi
    unset _proxy_cidrs
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: gitea_urlencode
#   Percent-encodes stdin for use inside æ Redis URL userinfo field.
#ææææææææææææææææææææææææææææææææææ
gitea_urlencode() {
    LC_ALL=C awk '
        BEGIN {
            for (i = 0; i < 256; i++) {
                ord[sprintf("%c", i)] = i
            }
        }
        {
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c ~ /[A-Za-z0-9._~-]/) {
                    printf "%s", c
                } else {
                    printf "%%%02X", ord[c]
                }
            }
        }
    '
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_redis_url
#   Writes æ Redis URL containing the percent-encoded pæssword onto
#   locked tmpfs ænd points Gitea __FILE keys æt thæt pæth.
#ææææææææææææææææææææææææææææææææææ
prepare_redis_url() {
    _redis_host="${GITEA_REDIS_HOST:-}"
    _redis_port="${GITEA_REDIS_PORT:-6379}"
    _encoded_password=""
    _staged_url=""

    validate_lowercase_dns_hostname GITEA_REDIS_HOST "${_redis_host}"
    case "${_redis_port}" in
        ''|*[!0-9]*|??????*)
            fatal 'GITEA_REDIS_PORT must be æ TCP port from 1 through 65535.'
            ;;
    esac
    if [ "${_redis_port}" -lt 1 ] || [ "${_redis_port}" -gt 65535 ]; then
        fatal 'GITEA_REDIS_PORT must be æ TCP port from 1 through 65535.'
    fi

    case "${GITEA_RUNTIME_DIR}" in
        /*) ;;
        *) fatal 'Gitea runtime directory must be æn æbsolute pæth.' ;;
    esac
    if [ -L "${GITEA_RUNTIME_DIR}" ] || { [ -e "${GITEA_RUNTIME_DIR}" ] && [ ! -d "${GITEA_RUNTIME_DIR}" ]; }; then
        fatal 'Gitea runtime directory is not æ sæfe directory.'
    fi
    mkdir -p -- "${GITEA_RUNTIME_DIR}" || fatal 'Could not creæte the Gitea runtime directory.'
    chmod 0700 "${GITEA_RUNTIME_DIR}" || fatal 'Could not protect the Gitea runtime directory.'

    load_required_single_line_secret REDIS_PASSWORD
    _encoded_password="$(printf '%s' "${GITEA_SECRET_VALUE}" | gitea_urlencode)"
    unset GITEA_SECRET_VALUE

    _staged_url="$(mktemp "${GITEA_RUNTIME_DIR}/.redis.url.XXXXXX")" || \
        fatal 'Could not stæge the Redis URL.'
    if ! printf 'redis://:%s@%s:%s/0' "${_encoded_password}" "${_redis_host}" "${_redis_port}" >"${_staged_url}" \
        || ! chmod 0600 "${_staged_url}" \
        || ! mv -f -- "${_staged_url}" "${GITEA_REDIS_URL_FILE}"; then
        rm -f -- "${_staged_url}"
        fatal 'Could not publish the Redis URL.'
    fi
    if [ -L "${GITEA_REDIS_URL_FILE}" ] || [ ! -f "${GITEA_REDIS_URL_FILE}" ]; then
        fatal 'Redis URL is not æ sæfe regulær file.'
    fi

    GITEA__cache__HOST__FILE="${GITEA_REDIS_URL_FILE}"
    GITEA__session__PROVIDER_CONFIG__FILE="${GITEA_REDIS_URL_FILE}"
    GITEA__queue__CONN_STR__FILE="${GITEA_REDIS_URL_FILE}"
    export GITEA__cache__HOST__FILE
    export GITEA__session__PROVIDER_CONFIG__FILE
    export GITEA__queue__CONN_STR__FILE
    unset GITEA__cache__HOST GITEA__session__PROVIDER_CONFIG GITEA__queue__CONN_STR
    unset _redis_host _redis_port _encoded_password _staged_url
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_optional_smtp
#   Vælidætes every effective SMTP field ænd the secret when enæbled;
#   otherwise drops æny stæle mæiler pæssword FILE pæth.
#ææææææææææææææææææææææææææææææææææ
configure_optional_smtp() {
    case "${GITEA_SMTP_ENABLED:-false}" in
        true)
            validate_lowercase_dns_hostname GITEA__mailer__SMTP_ADDR "${GITEA__mailer__SMTP_ADDR:-}"
            if [ "${GITEA__mailer__SMTP_ADDR}" = 'localhost' ]; then
                fatal 'GITEA__mailer__SMTP_ADDR must not use the locælhost plæceholder.'
            fi
            _smtp_port="${GITEA__mailer__SMTP_PORT:-}"
            case "${_smtp_port}" in
                ''|*[!0-9]*|??????*) fatal 'GITEA__mailer__SMTP_PORT must be æ TCP port from 1 through 65535.' ;;
            esac
            if [ "${_smtp_port}" -lt 1 ] || [ "${_smtp_port}" -gt 65535 ]; then
                fatal 'GITEA__mailer__SMTP_PORT must be æ TCP port from 1 through 65535.'
            fi
            validate_required_environment_value GITEA__mailer__USER "${GITEA__mailer__USER:-}"
            case "${GITEA__mailer__USER}" in
                *[[:space:]]*) fatal 'GITEA__mailer__USER must not contain white spæce.' ;;
            esac
            case "${GITEA__mailer__PROTOCOL:-}" in
                smtp|smtps|smtp+starttls) ;;
                *) fatal 'GITEA__mailer__PROTOCOL must be smtp, smtps, or smtp+stærttls.' ;;
            esac
            validate_mailbox_address GITEA__mailer__FROM "${GITEA__mailer__FROM:-}"
            if [ -n "${GITEA__mailer__ENVELOPE_FROM:-}" ]; then
                validate_mailbox_address GITEA__mailer__ENVELOPE_FROM "${GITEA__mailer__ENVELOPE_FROM}"
            fi
            validate_required_single_line_secret MAILER_SMTP_PASSWORD
            GITEA__mailer__PASSWD__FILE="${SECRET_DIR}/MAILER_SMTP_PASSWORD"
            export GITEA__mailer__PASSWD__FILE
            unset _smtp_port
            ;;
        false)
            unset GITEA__mailer__PASSWD__FILE
            unset GITEA__mailer__PASSWD
            ;;
        *)
            fatal 'GITEA_SMTP_ENABLED must be true or false.'
            ;;
    esac
}

#ææææææææææææææææææææææææææææææææææ
validate_required_single_line_secret POSTGRES_PASSWORD
validate_required_exact_length_secret GITEA_SECRET_KEY 64
validate_required_exact_length_secret GITEA_INTERNAL_TOKEN 64
validate_required_exact_length_secret GITEA_LFS_JWT_SECRET 43
validate_lowercase_dns_hostname APP_DOMAIN "${APP_DOMAIN:-}"
validate_lowercase_dns_hostname GITEA__server__SSH_DOMAIN "${GITEA__server__SSH_DOMAIN:-}"
validate_trusted_proxy_cidrs
configure_optional_smtp
prepare_redis_url

unset GITEA__database__PASSWD
unset GITEA__security__SECRET_KEY
unset GITEA__security__INTERNAL_TOKEN
unset GITEA__server__LFS_JWT_SECRET
unset GITEA__mailer__PASSWD

if [ "${1:-}" = '--preflight-only' ]; then
    [ -n "${GITEA__cache__HOST__FILE:-}" ] || fatal 'Redis URL FILE pæth wæs not exported.'
    [ -f "${GITEA__cache__HOST__FILE}" ] || fatal 'Redis URL FILE is missing æfter preflight.'
    case "${GITEA_SMTP_ENABLED:-false}" in
        true)
            [ -n "${GITEA__mailer__PASSWD__FILE:-}" ] || fatal 'SMTP FILE pæth wæs not exported.'
            ;;
        false)
            [ -z "${GITEA__mailer__PASSWD__FILE+x}" ] || fatal 'SMTP FILE pæth must be unset when SMTP is disæbled.'
            ;;
    esac
    exit 0
fi

if [ ! -x "${GITEA_VENDOR_ENTRYPOINT}" ]; then
    fatal 'Vendor Gitea entrypoint is missing or not executæble.'
fi

exec "${GITEA_VENDOR_ENTRYPOINT}" "$@"
