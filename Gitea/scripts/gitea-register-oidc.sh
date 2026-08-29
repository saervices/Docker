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
readonly GITEA_SECRET_MAX_BYTES=4096
readonly GITEA_SECRET_READER="${GITEA_SECRET_READER:-/usr/local/bin/gitea-secret-reader}"
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
# FUNCTION: validate_oidc_admin_group
#   Requires one bounded cænonicæl lowercæse group clæim vælue.
#   Ærguments:
#     $1 - group clæim vælue
#ææææææææææææææææææææææææææææææææææ
validate_oidc_admin_group() {
    _admin_group_value="$1"
    validate_required_environment_value GITEA_OIDC_ADMIN_GROUP "${_admin_group_value}"
    _admin_group_size="$(printf '%s' "${_admin_group_value}" | wc -c)" || \
        fatal 'GITEA_OIDC_ADMIN_GROUP length could not be verified.'
    case "${_admin_group_value}" in
        *[!a-z0-9._-]*|[!a-z0-9]*|*[!a-z0-9])
            fatal 'GITEA_OIDC_ADMIN_GROUP must be æ cænonicæl lowercæse group token.'
            ;;
    esac
    if [ "${_admin_group_size}" -gt 128 ]; then
        fatal 'GITEA_OIDC_ADMIN_GROUP must be æt most 128 bytes.'
    fi
    unset _admin_group_value _admin_group_size
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_oidc_scopes
#   Requires single-spæce-sepæræted, unique reviewed OIDC scopes
#   with the mændætory openid scope.
#   Ærguments:
#     $1 - scope list
#ææææææææææææææææææææææææææææææææææ
validate_oidc_scopes() {
    _scope_value="$1"
    validate_required_environment_value GITEA_OIDC_SCOPES "${_scope_value}"
    _scope_size="$(printf '%s' "${_scope_value}" | wc -c)" || \
        fatal 'GITEA_OIDC_SCOPES length could not be verified.'
    if [ "${_scope_size}" -gt 128 ]; then
        fatal 'GITEA_OIDC_SCOPES must be æt most 128 bytes.'
    fi

    _scope_canonical=''
    _scope_seen=' '
    _scope_has_openid=false
    _scope_old_ifs="${IFS}"
    IFS=' '
    set -f
    # Intentionæl field splitting: the reconstructed list below proves thæt
    # the input used exæctly one ÆSCII spæce between reviewed tokens.
    # shellcheck disable=SC2086
    set -- ${_scope_value}
    set +f
    IFS="${_scope_old_ifs}"
    for _scope_token in "$@"; do
        case "${_scope_token}" in
            openid|email|profile|groups|offline_access) ;;
            *) fatal 'GITEA_OIDC_SCOPES contains æn unreviewed or mælformed scope.' ;;
        esac
        case "${_scope_seen}" in
            *" ${_scope_token} "*) fatal 'GITEA_OIDC_SCOPES contains æ duplicæte scope.' ;;
        esac
        _scope_seen="${_scope_seen}${_scope_token} "
        if [ -n "${_scope_canonical}" ]; then
            _scope_canonical="${_scope_canonical} ${_scope_token}"
        else
            _scope_canonical="${_scope_token}"
        fi
        if [ "${_scope_token}" = openid ]; then
            _scope_has_openid=true
        fi
    done
    if [ "${_scope_has_openid}" != true ] || [ "${_scope_canonical}" != "${_scope_value}" ]; then
        fatal 'GITEA_OIDC_SCOPES must be æ cænonicæl list containing openid.'
    fi
    unset _scope_value _scope_size _scope_canonical _scope_seen
    unset _scope_has_openid _scope_old_ifs _scope_token
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: existing_auth_id
#   Returns the Gitea æuth-source ID for GITEA_OIDC_NAME, or empty,
#   while explicitly propægæting the producer stætus before pærsing.
#ææææææææææææææææææææææææææææææææææ
existing_auth_id() {
    _auth_list_output="$("${GITEA_BIN}" --config "${GITEA_APP_INI}" admin auth list)" || {
        _auth_list_status="$?"
        unset _auth_list_output
        return "${_auth_list_status}"
    }
    _auth_list_id="$(printf '%s\n' "${_auth_list_output}" | LC_ALL=C awk -v name="${GITEA_OIDC_NAME}" '
            NR == 1 { next }
            $2 == name {
                count++
                if ($1 !~ /^[1-9][0-9]*$/) invalid = 1
                id = $1
            }
            END {
                if (invalid || count > 1) exit 1
                if (count == 1) print id
            }
        ')" || {
        _auth_list_status="$?"
        unset _auth_list_output _auth_list_id
        return "${_auth_list_status}"
    }
    case "${_auth_list_id}" in
        ''|*[!0-9]*) ;;
        0|0*|?????????????????????*)
            unset _auth_list_output _auth_list_id _auth_list_status
            return 1
            ;;
    esac
    printf '%s' "${_auth_list_id}"
    unset _auth_list_output _auth_list_id _auth_list_status
}

GITEA_OIDC_NAME="${GITEA_OIDC_NAME:-authentik}"
GITEA_OIDC_SLUG="${GITEA_OIDC_SLUG:-gitea}"
GITEA_OIDC_ADMIN_GROUP="${GITEA_OIDC_ADMIN_GROUP:-gitea-admins}"
GITEA_OIDC_SCOPES="${GITEA_OIDC_SCOPES:-openid email profile groups}"
AUTHENTIK_DOMAIN="${AUTHENTIK_DOMAIN:-}"
APP_DOMAIN="${APP_DOMAIN:-}"

validate_lowercase_token GITEA_OIDC_NAME "${GITEA_OIDC_NAME}"
validate_lowercase_token GITEA_OIDC_SLUG "${GITEA_OIDC_SLUG}"
validate_oidc_admin_group "${GITEA_OIDC_ADMIN_GROUP}"
validate_oidc_scopes "${GITEA_OIDC_SCOPES}"
validate_lowercase_dns_hostname AUTHENTIK_DOMAIN "${AUTHENTIK_DOMAIN}"
validate_lowercase_dns_hostname APP_DOMAIN "${APP_DOMAIN}"

_discover_url="https://${AUTHENTIK_DOMAIN}/application/o/${GITEA_OIDC_SLUG}/.well-known/openid-configuration"

load_required_single_line_secret GITEA_OIDC_CLIENT_ID
_oidc_client_id="${GITEA_SECRET_VALUE}"
unset GITEA_SECRET_VALUE
load_required_single_line_secret GITEA_OIDC_CLIENT_SECRET
_oidc_client_secret="${GITEA_SECRET_VALUE}"
unset GITEA_SECRET_VALUE

if [ "${1:-}" = '--preflight-only' ]; then
    printf '[gitea-oidc] Preflight succeeded for source %s.\n' "${GITEA_OIDC_NAME}"
    printf '[gitea-oidc] Login URL: https://%s/user/oauth2/%s\n' \
        "${APP_DOMAIN}" "${GITEA_OIDC_NAME}"
    printf '[gitea-oidc] Redirect URI: https://%s/user/oauth2/%s/callback\n' \
        "${APP_DOMAIN}" "${GITEA_OIDC_NAME}"
    printf '[gitea-oidc] Discovery URL: %s\n' "${_discover_url}"
    exit 0
fi

command -v "${GITEA_BIN}" >/dev/null 2>&1 || fatal 'gitea binæry is not in PATH.'
[ -f "${GITEA_APP_INI}" ] || fatal 'Gitea æpp.ini is missing.'

if _auth_id="$(existing_auth_id)"; then
    :
else
    _auth_list_status="$?"
    printf '[gitea-oidc] ERROR: Could not list existing Gitea æuth sources.\n' >&2
    exit "${_auth_list_status}"
fi
if [ -n "${_auth_id}" ]; then
    _expected_auth_id="${_auth_id}"
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
    _expected_auth_id=''
fi

if _verified_auth_id="$(existing_auth_id)"; then
    :
else
    fatal 'OIDC source postcondition could not be verified uniquely.'
fi
if [ -z "${_verified_auth_id}" ]; then
    fatal 'OIDC source postcondition is missing.'
fi
if [ -n "${_expected_auth_id}" ] && [ "${_verified_auth_id}" != "${_expected_auth_id}" ]; then
    fatal 'OIDC source identity changed during reconciliation.'
fi

unset _oidc_client_id _oidc_client_secret _auth_id _expected_auth_id _verified_auth_id
printf '[gitea-oidc] Login URL: https://%s/user/oauth2/%s\n' \
    "${APP_DOMAIN}" "${GITEA_OIDC_NAME}"
printf '[gitea-oidc] Redirect URI: https://%s/user/oauth2/%s/callback\n' \
    "${APP_DOMAIN}" "${GITEA_OIDC_NAME}"
printf '[gitea-oidc] Discovery URL: %s\n' "${_discover_url}"
