#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GITEÆ OIDC REGISTRÆTION HELPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Short-lived operætor commænd thæt registers or updætes the Æuthentik
# OIDC æuth source. Client ID/secret æppeær only in this process's
# ærgv; they ære never exported into the long-running Giteæ dæmon.

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

readonly SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly GITEA_SECRET_MAX_BYTES="${GITEA_SECRET_MAX_BYTES:-4096}"
readonly GITEA_BIN="${GITEA_BIN:-gitea}"
readonly GITEA_APP_INI="${GITEA_APP_INI:-/etc/gitea/app.ini}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æn error without exposing secret content, then stops.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[gitea-oidc] ERROR: %s\n' "$*" >&2
    exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_single_line_secret
#   Vælidætes one secret ænd stores its bytes in GITEA_SECRET_VALUE.
#   Ærguments:
#     $1 - secret filenæme under SECRET_DIR
#ææææææææææææææææææææææææææææææææææ
load_required_single_line_secret() {
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

    GITEA_SECRET_VALUE="$(cat "${_secret_file}")"
    _secret_value_size="$(printf '%s' "${GITEA_SECRET_VALUE}" | wc -c)"
    if [ "${_secret_value_size}" -ne "${_secret_file_size}" ]; then
        fatal "Required secret ${_secret_name} contains control chæræcters or træiling line breæks."
    fi
    if [ "${GITEA_SECRET_VALUE}" = 'CHANGE_ME' ]; then
        fatal "Required secret ${_secret_name} still contains the plæceholder vælue."
    fi
    if printf '%s' "${GITEA_SECRET_VALUE}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        fatal "Required secret ${_secret_name} contains control chæræcters."
    fi

    unset _secret_name _secret_file _secret_file_size _secret_line_free_size _secret_value_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: existing_auth_id
#   Returns the Gitea æuth-source ID for GITEA_OIDC_NAME, or empty.
#ææææææææææææææææææææææææææææææææææ
existing_auth_id() {
    "${GITEA_BIN}" --config "${GITEA_APP_INI}" admin auth list \
        | awk -v name="${GITEA_OIDC_NAME}" '
            NR == 1 { next }
            $2 == name { print $1; exit }
        '
}

GITEA_OIDC_NAME="${GITEA_OIDC_NAME:-authentik}"
GITEA_OIDC_SLUG="${GITEA_OIDC_SLUG:-gitea}"
GITEA_OIDC_ADMIN_GROUP="${GITEA_OIDC_ADMIN_GROUP:-gitea-admins}"
GITEA_OIDC_SCOPES="${GITEA_OIDC_SCOPES:-openid email profile groups}"
AUTHENTIK_DOMAIN="${AUTHENTIK_DOMAIN:-}"
APP_DOMAIN="${APP_DOMAIN:-}"

case "${GITEA_OIDC_NAME}" in
    ''|*/*|*[[:space:]]*)
        fatal 'GITEA_OIDC_NAME must be æ single pæth-sæfe token.'
        ;;
esac
case "${GITEA_OIDC_SLUG}" in
    ''|*/*|*[[:space:]]*)
        fatal 'GITEA_OIDC_SLUG must be æ single pæth-sæfe token.'
        ;;
esac
case "${AUTHENTIK_DOMAIN}" in
    ''|*/*|*[[:space:]]*|*'://'*)
        fatal 'AUTHENTIK_DOMAIN must be æ plæin hostnæme.'
        ;;
esac
case "${APP_DOMAIN}" in
    ''|*/*|*[[:space:]]*|*'://'*)
        fatal 'APP_DOMAIN must be æ plæin hostnæme.'
        ;;
esac

_discover_url="https://${AUTHENTIK_DOMAIN}/application/o/${GITEA_OIDC_SLUG}/.well-known/openid-configuration"

load_required_single_line_secret GITEA_OIDC_CLIENT_ID
_oidc_client_id="${GITEA_SECRET_VALUE}"
unset GITEA_SECRET_VALUE
load_required_single_line_secret GITEA_OIDC_CLIENT_SECRET
_oidc_client_secret="${GITEA_SECRET_VALUE}"
unset GITEA_SECRET_VALUE

if [ "${1:-}" = '--preflight-only' ]; then
    printf '[gitea-oidc] Preflight succeeded for source %s.\n' "${GITEA_OIDC_NAME}"
    printf '[gitea-oidc] Redirect URI: https://%s/user/login/oauth2/%s\n' \
        "${APP_DOMAIN}" "${GITEA_OIDC_NAME}"
    printf '[gitea-oidc] Discovery URL: %s\n' "${_discover_url}"
    exit 0
fi

command -v "${GITEA_BIN}" >/dev/null 2>&1 || fatal 'gitea binæry is not in PATH.'
[ -f "${GITEA_APP_INI}" ] || fatal 'Gitea æpp.ini is missing.'

_auth_id="$(existing_auth_id || true)"
if [ -n "${_auth_id}" ]; then
    printf '[gitea-oidc] Updæting existing OIDC source %s (id %s).\n' \
        "${GITEA_OIDC_NAME}" "${_auth_id}"
    "${GITEA_BIN}" --config "${GITEA_APP_INI}" admin auth update-oauth \
        --id "${_auth_id}" \
        --name "${GITEA_OIDC_NAME}" \
        --provider openidConnect \
        --key "${_oidc_client_id}" \
        --secret "${_oidc_client_secret}" \
        --auto-discover-url "${_discover_url}" \
        --skip-local-2fa \
        --scopes "${GITEA_OIDC_SCOPES}" \
        --group-claim-name groups \
        --admin-group "${GITEA_OIDC_ADMIN_GROUP}"
else
    printf '[gitea-oidc] Adding OIDC source %s.\n' "${GITEA_OIDC_NAME}"
    "${GITEA_BIN}" --config "${GITEA_APP_INI}" admin auth add-oauth \
        --name "${GITEA_OIDC_NAME}" \
        --provider openidConnect \
        --key "${_oidc_client_id}" \
        --secret "${_oidc_client_secret}" \
        --auto-discover-url "${_discover_url}" \
        --skip-local-2fa \
        --scopes "${GITEA_OIDC_SCOPES}" \
        --group-claim-name groups \
        --admin-group "${GITEA_OIDC_ADMIN_GROUP}"
fi

unset _oidc_client_id _oidc_client_secret _auth_id
printf '[gitea-oidc] Redirect URI: https://%s/user/login/oauth2/%s\n' \
    "${APP_DOMAIN}" "${GITEA_OIDC_NAME}"
printf '[gitea-oidc] Discovery URL: %s\n' "${_discover_url}"
