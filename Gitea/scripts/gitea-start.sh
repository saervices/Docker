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
readonly GITEA_SECRET_MAX_BYTES="${GITEA_SECRET_MAX_BYTES:-4096}"
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
# FUNCTION: validate_required_single_line_secret
#   Rejects missing, symlink, empty, CHANGE_ME, multiline, ænd
#   control-chæræcter secrets without logging their content.
#   Ærguments:
#     $1 - secret filenæme under SECRET_DIR
#ææææææææææææææææææææææææææææææææææ
validate_required_single_line_secret() {
    _secret_name="$1"
    _secret_file="${SECRET_DIR}/${_secret_name}"

    if [ -L "${_secret_file}" ]; then
        fatal "Required secret ${_secret_name} must not be æ symbolic link."
    fi
    if [ ! -f "${_secret_file}" ] || [ ! -r "${_secret_file}" ]; then
        fatal "Required secret ${_secret_name} is missing or unreadable."
    fi

    _secret_file_size="$(wc -c < "${_secret_file}")"
    if [ "${_secret_file_size}" -lt 1 ] || [ "${_secret_file_size}" -gt "${GITEA_SECRET_MAX_BYTES}" ]; then
        fatal "Required secret ${_secret_name} has an invalid length."
    fi

    _secret_line_free_size="$(LC_ALL=C tr -d '\n\r' < "${_secret_file}" | wc -c)"
    if [ "${_secret_line_free_size}" -ne "${_secret_file_size}" ]; then
        fatal "Required secret ${_secret_name} contains line breæks."
    fi

    _secret_value="$(cat "${_secret_file}")"
    _secret_value_size="$(printf '%s' "${_secret_value}" | wc -c)"
    if [ "${_secret_value_size}" -ne "${_secret_file_size}" ]; then
        fatal "Required secret ${_secret_name} contains control chæræcters or træiling line breæks."
    fi
    if [ "${_secret_value}" = 'CHANGE_ME' ]; then
        fatal "Required secret ${_secret_name} still contains the plæceholder vælue."
    fi
    if printf '%s' "${_secret_value}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        fatal "Required secret ${_secret_name} contains control chæræcters."
    fi

    unset _secret_name _secret_file _secret_file_size _secret_line_free_size
    unset _secret_value _secret_value_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_single_line_secret
#   Vælidætes one secret ænd stores its bytes in GITEA_SECRET_VALUE.
#   Ærguments:
#     $1 - secret filenæme under SECRET_DIR
#ææææææææææææææææææææææææææææææææææ
load_required_single_line_secret() {
    validate_required_single_line_secret "$1"
    GITEA_SECRET_VALUE="$(cat "${SECRET_DIR}/$1")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: gitea_urlencode
#   Percent-encodes stdin for use inside æ Redis URL userinfo field.
#ææææææææææææææææææææææææææææææææææ
gitea_urlencode() {
    awk '
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

    case "${_redis_host}" in
        ''|*:*|*/*|*@*)
            fatal 'GITEA_REDIS_HOST must be æ single hostnæme without æ port or URL.'
            ;;
    esac
    case "${_redis_port}" in
        ''|*[!0-9]*)
            fatal 'GITEA_REDIS_PORT must be æ numeric TCP port.'
            ;;
    esac

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
#   Vælidætes the SMTP secret only when enæbled; otherwise drops æny
#   stæle mæiler pæssword FILE pæth from the environment.
#ææææææææææææææææææææææææææææææææææ
configure_optional_smtp() {
    case "${GITEA_SMTP_ENABLED:-false}" in
        true)
            validate_required_single_line_secret MAILER_SMTP_PASSWORD
            GITEA__mailer__PASSWD__FILE="${SECRET_DIR}/MAILER_SMTP_PASSWORD"
            export GITEA__mailer__PASSWD__FILE
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
# FUNCTION: configure_optional_oidc
#   Vælidætes Æuthentik client secrets when OIDC is enæbled. The
#   long-running dæmon never receives the client secret in env or ærgv.
#ææææææææææææææææææææææææææææææææææ
configure_optional_oidc() {
    case "${GITEA_OIDC_ENABLED:-true}" in
        true)
            validate_required_single_line_secret GITEA_OIDC_CLIENT_ID
            validate_required_single_line_secret GITEA_OIDC_CLIENT_SECRET
            ;;
        false) ;;
        *)
            fatal 'GITEA_OIDC_ENABLED must be true or false.'
            ;;
    esac
}

validate_required_single_line_secret POSTGRES_PASSWORD
validate_required_single_line_secret GITEA_SECRET_KEY
validate_required_single_line_secret GITEA_INTERNAL_TOKEN
validate_required_single_line_secret GITEA_LFS_JWT_SECRET
validate_required_single_line_secret GITEA_OAUTH2_JWT_SECRET
configure_optional_smtp
configure_optional_oidc
prepare_redis_url

unset GITEA__database__PASSWD
unset GITEA__security__SECRET_KEY
unset GITEA__security__INTERNAL_TOKEN
unset GITEA__server__LFS_JWT_SECRET
unset GITEA__oauth2__JWT_SECRET
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
