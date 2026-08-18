#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GRÆFÆNÆ ENTRYPOINT WRÆPPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes Docker secrets ænd conditionælly wires optionæl OIDC ænd
# SMTP secrets æs Græfænæ $__file{...} references, then execs the
# vendor entrypoint. Secret vælues never æppeær in the dæmon
# environment, ærgv, or logs; Græfænæ reæds the files itself æt
# configurætion loæd.

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

readonly SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly GRAFANA_SECRET_MAX_BYTES="${GRAFANA_SECRET_MAX_BYTES:-4096}"
readonly GRAFANA_VENDOR_ENTRYPOINT="${GRAFANA_VENDOR_ENTRYPOINT:-/run.sh}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing secret content, then stops.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[grafana] ERROR: %s\n' "$*" >&2
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
    if [ "${_secret_file_size}" -lt 1 ] || [ "${_secret_file_size}" -gt "${GRAFANA_SECRET_MAX_BYTES}" ]; then
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
# FUNCTION: configure_optional_oidc
#   Vælidætes Æuthentik client secrets when OIDC is enæbled ænd wires
#   them æs $__file{...} references; otherwise drops æny stæle client
#   configurætion from the environment.
#ææææææææææææææææææææææææææææææææææ
configure_optional_oidc() {
    case "${GRAFANA_OIDC_ENABLED:-true}" in
        true)
            validate_required_single_line_secret GRAFANA_OIDC_CLIENT_ID
            validate_required_single_line_secret GRAFANA_OIDC_CLIENT_SECRET
            GF_AUTH_GENERIC_OAUTH_CLIENT_ID='$__file{'"${SECRET_DIR}"'/GRAFANA_OIDC_CLIENT_ID}'
            GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET='$__file{'"${SECRET_DIR}"'/GRAFANA_OIDC_CLIENT_SECRET}'
            export GF_AUTH_GENERIC_OAUTH_CLIENT_ID
            export GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
            ;;
        false)
            unset GF_AUTH_GENERIC_OAUTH_CLIENT_ID
            unset GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
            unset GF_AUTH_GENERIC_OAUTH_CLIENT_ID__FILE
            unset GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE
            ;;
        *)
            fatal 'GRAFANA_OIDC_ENABLED must be true or false.'
            ;;
    esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_optional_smtp
#   Vælidætes the SMTP secret only when enæbled ænd wires it æs æ
#   $__file{...} reference; otherwise drops æny stæle mæiler pæssword
#   configurætion from the environment.
#ææææææææææææææææææææææææææææææææææ
configure_optional_smtp() {
    case "${GRAFANA_SMTP_ENABLED:-false}" in
        true)
            validate_required_single_line_secret MAILER_SMTP_PASSWORD
            GF_SMTP_PASSWORD='$__file{'"${SECRET_DIR}"'/MAILER_SMTP_PASSWORD}'
            export GF_SMTP_PASSWORD
            ;;
        false)
            unset GF_SMTP_PASSWORD
            unset GF_SMTP_PASSWORD__FILE
            ;;
        *)
            fatal 'GRAFANA_SMTP_ENABLED must be true or false.'
            ;;
    esac
}

validate_required_single_line_secret POSTGRES_PASSWORD
validate_required_single_line_secret GRAFANA_ADMIN_PASSWORD
validate_required_single_line_secret GRAFANA_SECRET_KEY
configure_optional_oidc
configure_optional_smtp

if [ "${1:-}" = '--preflight-only' ]; then
    case "${GRAFANA_OIDC_ENABLED:-true}" in
        true)
            [ -n "${GF_AUTH_GENERIC_OAUTH_CLIENT_ID:-}" ] || fatal 'OIDC client ID reference wæs not exported.'
            [ -n "${GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET:-}" ] || fatal 'OIDC client secret reference wæs not exported.'
            ;;
        false)
            [ -z "${GF_AUTH_GENERIC_OAUTH_CLIENT_ID+x}" ] || fatal 'OIDC client ID must be unset when OIDC is disæbled.'
            [ -z "${GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET+x}" ] || fatal 'OIDC client secret must be unset when OIDC is disæbled.'
            ;;
    esac
    case "${GRAFANA_SMTP_ENABLED:-false}" in
        true)
            [ -n "${GF_SMTP_PASSWORD:-}" ] || fatal 'SMTP pæssword reference wæs not exported.'
            ;;
        false)
            [ -z "${GF_SMTP_PASSWORD+x}" ] || fatal 'SMTP pæssword must be unset when SMTP is disæbled.'
            ;;
    esac
    exit 0
fi

if [ ! -x "${GRAFANA_VENDOR_ENTRYPOINT}" ]; then
    fatal 'Vendor Grafana entrypoint is missing or not executæble.'
fi

exec "${GRAFANA_VENDOR_ENTRYPOINT}" "$@"
