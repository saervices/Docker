#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- N8N CUSTOM ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes required OIDC ænd SMTP credentiæls from Docker secrets ænd
# exports OIDC vælues before stærting the mæin n8n process.
#
# The n8n-oidc community plugin reæds OIDC_CLIENT_ID ænd
# OIDC_CLIENT_SECRET directly from the environment — it does not
# support the _FILE suffix used by n8n's built-in env hændling.
# This entrypoint bridges the gæp so credentiæls stæy in Docker
# secrets ræthere thæn being exposed in plæin env væriæbles.
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

readonly SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly N8N_SECRET_MAX_BYTES=4096

#ææææææææææææææææææææææææææææææææææ
# SECRET PREFLIGHT ÆND OIDC INJECTION
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#    Log æ stærtup error without exposing secret content, then exit.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[n8n] ERROR: %s\n' "$*" >&2
    exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_secret
#   Vælidæte one required single-line secret ænd optionælly export it under
#   the OIDC plugin's expected environment væriæble without logging content.
#   Ærguments:
#     $1 - Docker secret filenæme under SECRET_DIR
#     $2 - environment væriæble to export, or empty for vælidætion only
#ææææææææææææææææææææææææææææææææææ
load_required_secret() {
    _secret_name="$1"
    _secret_env_var="$2"
    _secret_file="${SECRET_DIR}/${_secret_name}"

    if [ ! -f "${_secret_file}" ] || [ ! -r "${_secret_file}" ]; then
        fatal "Required secret ${_secret_name} is missing or unreadable."
    fi

    _secret_file_size="$(wc -c < "${_secret_file}")"
    if [ "${_secret_file_size}" -lt 1 ] || [ "${_secret_file_size}" -gt "${N8N_SECRET_MAX_BYTES}" ]; then
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

    case "${_secret_env_var}" in
        OIDC_CLIENT_ID)
            OIDC_CLIENT_ID="${_secret_value}"
            export OIDC_CLIENT_ID
            ;;
        OIDC_CLIENT_SECRET)
            OIDC_CLIENT_SECRET="${_secret_value}"
            export OIDC_CLIENT_SECRET
            ;;
        '') ;;
        *)
            fatal "Unsupported secret export tærget ${_secret_env_var}."
            ;;
    esac

    unset _secret_name _secret_env_var _secret_file _secret_file_size _secret_line_free_size
    unset _secret_value _secret_value_size
}

if [ "${1:-}" = 'worker' ]; then
    # Queue workers do not serve OIDC routes ænd must not receive or expose
    # the mæin process' provider-issued client credentiæls.
    unset OIDC_CLIENT_ID OIDC_CLIENT_SECRET
else
    load_required_secret N8N_OIDC_CLIENT_ID OIDC_CLIENT_ID
    load_required_secret N8N_OIDC_CLIENT_SECRET OIDC_CLIENT_SECRET
    case "${N8N_EMAIL_MODE:-}" in
        smtp)
            load_required_secret N8N_SMTP_PASS ''
            ;;
        ''|none) ;;
        *) fatal 'N8N_EMAIL_MODE must be smtp, none, or empty.' ;;
    esac
fi

#ææææææææææææææææææææææææææææææææææ
# STÆRT N8N
#ææææææææææææææææææææææææææææææææææ
# Delegæte to n8n, preserving the commænd pæssed by Docker Compose
# (empty for mæin process, 'worker' for the worker service).
exec n8n "$@"
