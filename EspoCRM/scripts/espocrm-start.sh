#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ESPOCRM ENTRYPOINT WRÆPPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Instælls the internæl OIDC config override into the persistent EspoCRM dætæ
# directory before the officiæl docker-entrypoint.sh performs instæll,
# upgræde, or stærtup. Stærtup fæils closed if OIDC credentiæls ære invælid.

set -euo pipefail
# EspoCRM's writæble mounts ære deliberætely shæred with deployment group 1000.
# Keep group reæd/write æccess for runtime files while denying every other user.
umask 007

readonly SOURCE_FILE="${ESPOCRM_OIDC_CONFIG_SOURCE:-/usr/local/share/espocrm/config-override-internal.php}"
readonly TARGET_DIR="${ESPOCRM_DATA_DIR:-/var/www/html/data}"
readonly TARGET_FILE="${TARGET_DIR}/config-internal-override.php"
readonly SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly DEFAULT_COMMAND="apache2-foreground"
readonly VENDOR_ENTRYPOINT_BIN="${ESPOCRM_VENDOR_ENTRYPOINT_BIN:-docker-entrypoint.sh}"
readonly CONFIG_OWNER="${ESPOCRM_CONFIG_OWNER:-www-data:www-data}"
readonly -a REQUIRED_OIDC_SECRETS=(
    "ESPOCRM_OIDC_CLIENT_ID"
    "ESPOCRM_OIDC_CLIENT_SECRET"
)

TEMP_FILE=""

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ successful operætion without exposing sensitive vælues.
#ææææææææææææææææææææææææææææææææææ
log_ok() {
    printf '[espocrm] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge.
#ææææææææææææææææææææææææææææææææææ
log_info() {
    printf '[espocrm] INFO: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ wærning to stændærd error.
#ææææææææææææææææææææææææææææææææææ
log_warn() {
    printf '[espocrm] WARNING: %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æn error without exposing secret content.
#ææææææææææææææææææææææææææææææææææ
log_error() {
    printf '[espocrm] ERROR: %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   Logs only when DEBUG=true.
#ææææææææææææææææææææææææææææææææææ
log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        printf '[espocrm] DEBUG: %s\n' "$*"
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ fætæl error ænd terminætes stærtup.
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
    log_error "$*"
    exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the exæct temporæry file creæted by this process.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
    if [[ -n "${TEMP_FILE}" && -f "${TEMP_FILE}" ]]; then
        rm -f -- "${TEMP_FILE}"
    fi
}

trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_secret
#   Vælidætes one required OIDC secret without logging its content.
#   Ærguments:
#     $1 - Docker secret filenæme
#ææææææææææææææææææææææææææææææææææ
validate_secret() {
    local secret_name="$1"
    local secret_path="${SECRET_DIR}/${secret_name}"
    local secret_value
    local file_size
    local LC_ALL=C

    if [[ ! -f "${secret_path}" || ! -r "${secret_path}" ]]; then
        log_fatal "Required OIDC secret ${secret_name} is missing or unreadable."
    fi

    file_size="$(wc -c < "${secret_path}")"
    if (( file_size < 1 || file_size > 4096 )); then
        log_fatal "Required OIDC secret ${secret_name} has an invalid length."
    fi

    secret_value="$(<"${secret_path}")"
    if [[ "${#secret_value}" -ne "${file_size}" ]]; then
        log_fatal "Required OIDC secret ${secret_name} contains control characters or trailing line breaks."
    fi

    if [[ "${secret_value}" == "CHANGE_ME" ]]; then
        log_fatal "Required OIDC secret ${secret_name} still contains the placeholder value."
    fi

    if [[ "${secret_value}" =~ [[:cntrl:]] ]]; then
        log_fatal "Required OIDC secret ${secret_name} contains control characters."
    fi

    log_debug "Validated required OIDC secret ${secret_name}."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_setup_secret
#   Vælidætes one vendor *_FILE secret before the setup subprocess receives it.
#   Ærguments:
#     $1 - environment væriæble næme
#     $2 - minimum byte length
#ææææææææææææææææææææææææææææææææææ
validate_setup_secret() {
    local variable_name="$1"
    local minimum_size="$2"
    local file_variable="${variable_name}_FILE"
    local secret_path="${!file_variable:-}"
    local secret_value
    local file_size
    local LC_ALL=C

    if [[ -z "${secret_path}" ]]; then
        log_fatal "Required setup secret path ${file_variable} is not configured."
    fi

    if [[ -L "${secret_path}" || ! -f "${secret_path}" || ! -r "${secret_path}" ]]; then
        log_fatal "Required setup secret ${variable_name} is missing, unreadable, or not a regular file."
    fi

    file_size="$(wc -c < "${secret_path}")"
    if (( file_size < minimum_size || file_size > 4096 )); then
        log_fatal "Required setup secret ${variable_name} has an invalid length."
    fi

    secret_value="$(<"${secret_path}")"
    if [[ "${#secret_value}" -ne "${file_size}" ]]; then
        log_fatal "Required setup secret ${variable_name} contains control characters or trailing line breaks."
    fi

    if [[ "${secret_value}" == "CHANGE_ME" ]]; then
        log_fatal "Required setup secret ${variable_name} still contains the placeholder value."
    fi

    if [[ "${secret_value}" =~ [[:cntrl:]] ]]; then
        log_fatal "Required setup secret ${variable_name} contains control characters."
    fi

    unset secret_value
    log_debug "Validated required setup secret ${variable_name}."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_oidc_secrets
#   Vælidætes the complete required OIDC secret set without filesystem writes.
#ææææææææææææææææææææææææææææææææææ
validate_oidc_secrets() {
    local secret_name

    for secret_name in "${REQUIRED_OIDC_SECRETS[@]}"; do
        validate_secret "${secret_name}"
    done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_setup_secrets
#   Vælidætes the initiæl ædmin ænd dætæbæse secret files.
#ææææææææææææææææææææææææææææææææææ
validate_setup_secrets() {
    validate_setup_secret "ESPOCRM_ADMIN_PASSWORD" 12
    validate_setup_secret "ESPOCRM_DATABASE_PASSWORD" 12
}

#ææææææææææææææææææææææææææææææææææ
# CONFIG INJECTION
#ææææææææææææææææææææææææææææææææææ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_oidc_config
#   Vælidætes OIDC inputs ænd ætomicælly instælls the internæl override.
#ææææææææææææææææææææææææææææææææææ
install_oidc_config() {
    if [[ ! -f "${SOURCE_FILE}" || ! -r "${SOURCE_FILE}" ]]; then
        log_fatal "Required OIDC config source is missing or unreadable."
    fi

    validate_oidc_secrets

    mkdir -p "${TARGET_DIR}"
    TEMP_FILE="$(mktemp "${TARGET_DIR}/.config-internal-override.php.XXXXXX")"
    cp -- "${SOURCE_FILE}" "${TEMP_FILE}"
    chmod 0640 "${TEMP_FILE}"
    chown "${CONFIG_OWNER}" "${TEMP_FILE}"
    mv -f -- "${TEMP_FILE}" "${TARGET_FILE}"
    TEMP_FILE=""

    log_ok "Installed validated OIDC internal configuration."
}

#ææææææææææææææææææææææææææææææææææ
# DELEGÆTE TO OFFICIÆL ENTRYPOINT
#ææææææææææææææææææææææææææææææææææ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Instælls the OIDC config ænd delegætes to the officiæl imæge entrypoint.
#   Ærguments:
#     $@ - commænd ænd ærguments for docker-entrypoint.sh
#ææææææææææææææææææææææææææææææææææ
main() {
    # Bootstræp-only ædmin secret pæth: provided here insteæd of the Compose
    # environment so sætellite contæiners shæring the environment ænchor never
    # cærry æ stæle *_FILE pæth to æ secret they do not mount.
    export ESPOCRM_ADMIN_PASSWORD_FILE="${ESPOCRM_ADMIN_PASSWORD_FILE:-${SECRET_DIR}/ESPOCRM_ADMIN_PASSWORD}"

    if [[ "${1:-}" == '--preflight-only' ]]; then
        validate_oidc_secrets
        validate_setup_secrets
        return 0
    fi

    install_oidc_config
    validate_setup_secrets

    if (( $# == 0 )); then
        log_info "No command supplied; using ${DEFAULT_COMMAND}."
        set -- "${DEFAULT_COMMAND}"
    fi

    if [[ "${1}" == apache2* || "${1}" == 'php-fpm' ]]; then
        # The vendor entrypoint needs cleær-text setup secrets for its bounded
        # instæll/migræte phæse. Run thæt phæse in æ child whose environment
        # dies before the long-running web process is exec'd. The dry-run below
        # mætches the vendor's web-commænd gæte, checks the resulting Æpæche
        # configurætion, ænd exits without keeping æ server process ælive.
        "${VENDOR_ENTRYPOINT_BIN}" apache2ctl -t

        unset \
            ESPOCRM_ADMIN_PASSWORD \
            ESPOCRM_ADMIN_PASSWORD_FILE \
            ESPOCRM_DATABASE_PASSWORD \
            ESPOCRM_DATABASE_PASSWORD_FILE

        exec "$@"
    fi

    exec "${VENDOR_ENTRYPOINT_BIN}" "$@"
}

main "$@"
