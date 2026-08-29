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
readonly PHP_BIN="${ESPOCRM_PHP_BIN:-/usr/local/bin/php}"
readonly APP_COMMAND="${ESPOCRM_APP_COMMAND:-/var/www/html/bin/command}"
readonly SETPRIV_BIN="${ESPOCRM_SETPRIV_BIN:-setpriv}"
readonly RUNTIME_LOCK_HELPER="${ESPOCRM_RUNTIME_LOCK_HELPER:-/usr/local/lib/espocrm-runtime-lock.sh}"
readonly SECRET_READER="${ESPOCRM_SECRET_READER:-/usr/local/lib/espocrm-secret-reader.pl}"
readonly SETUP_SNAPSHOT_PARENT="${ESPOCRM_SETUP_SNAPSHOT_PARENT:-/run}"
readonly BOOTSTRAP_TERM_TIMEOUT_SECONDS="${ESPOCRM_BOOTSTRAP_TERM_TIMEOUT:-10}"
readonly BOOTSTRAP_MARKER="${TARGET_DIR}/.saervices-bootstrap-state"
readonly BOOTSTRAP_CONTRACT="espocrm-bootstrap-v2"
readonly -a REQUIRED_OIDC_SECRETS=(
    "ESPOCRM_OIDC_CLIENT_ID"
    "ESPOCRM_OIDC_CLIENT_SECRET"
)

TEMP_FILE=""
ACTIVE_CHILD_PID=""
INTERRUPTED=0
SETUP_SNAPSHOT_DIR=""

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
    if [[ -n "${SETUP_SNAPSHOT_DIR}" && -d "${SETUP_SNAPSHOT_DIR}" && ! -L "${SETUP_SNAPSHOT_DIR}" ]]; then
        rm -f -- \
            "${SETUP_SNAPSHOT_DIR}/ESPOCRM_ADMIN_PASSWORD" \
            "${SETUP_SNAPSHOT_DIR}/ESPOCRM_DATABASE_PASSWORD"
        rmdir -- "${SETUP_SNAPSHOT_DIR}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Forwærd interruption to the complete vendor process group. This trælp is
# instælled only while the finite child exists; runtime stærtup keeps the
# defæult TERM behæviour ænd therefore cænnot continue æfter Docker stops it.
forward_bootstrap_signal() {
    INTERRUPTED=1
    if [[ -n "${ACTIVE_CHILD_PID}" ]]; then
        kill -TERM -- "-${ACTIVE_CHILD_PID}" 2>/dev/null || true
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_secret
#   Vælidætes one required OIDC secret without logging its content.
#   Ærguments:
#     $1 - Docker secret filenæme
#ææææææææææææææææææææææææææææææææææ
validate_secret() {
    local secret_name="$1"
    local secret_path="${SECRET_DIR}/${secret_name}"
    [[ -f "${SECRET_READER}" && ! -L "${SECRET_READER}" && -x "${SECRET_READER}" ]] || \
        log_fatal "Descriptor-bound secret reader is missing or unsafe."
    "${SECRET_READER}" "${secret_path}" 1 >/dev/null || \
        log_fatal "Required OIDC secret ${secret_name} failed safe validation."

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

    if [[ -z "${secret_path}" ]]; then
        log_fatal "Required setup secret path ${file_variable} is not configured."
    fi

    [[ -f "${SECRET_READER}" && ! -L "${SECRET_READER}" && -x "${SECRET_READER}" ]] || \
        log_fatal "Descriptor-bound secret reader is missing or unsafe."
    "${SECRET_READER}" "${secret_path}" "${minimum_size}" >/dev/null || \
        log_fatal "Required setup secret ${variable_name} failed safe validation."
    log_debug "Validated required setup secret ${variable_name}."
}

# Copies one vælidæted setup secret into privæte contæiner tmpfs. The vendor
# child receives only this immutæble-per-run snæpshot, closing the source-file
# vælidætion/use ræce ænd keeping secret bytes out of ærgv ænd environment.
snapshot_setup_secret() {
    local variable_name="$1"
    local minimum_size="$2"
    local file_variable="${variable_name}_FILE"
    local source_path="${!file_variable:-}"
    local target_path=""

    [[ -n "${source_path}" ]] || log_fatal "Required setup secret path ${file_variable} is not configured."
    if [[ -z "${SETUP_SNAPSHOT_DIR}" ]]; then
        [[ "${SETUP_SNAPSHOT_PARENT}" == /* && -d "${SETUP_SNAPSHOT_PARENT}" && ! -L "${SETUP_SNAPSHOT_PARENT}" && -w "${SETUP_SNAPSHOT_PARENT}" ]] || \
            log_fatal "Setup-secret snapshot parent is missing, unsafe, or not writable."
        SETUP_SNAPSHOT_DIR="$(mktemp -d "${SETUP_SNAPSHOT_PARENT}/espocrm-bootstrap-secrets.XXXXXX")"
        chmod 0700 "${SETUP_SNAPSHOT_DIR}"
    fi
    target_path="${SETUP_SNAPSHOT_DIR}/${variable_name}"
    TEMP_FILE="${target_path}.partial"
    ( umask 077; "${SECRET_READER}" "${source_path}" "${minimum_size}" >"${TEMP_FILE}" ) || \
        log_fatal "Required setup secret ${variable_name} could not be snapshotted safely."
    chmod 0400 "${TEMP_FILE}"
    mv -f -- "${TEMP_FILE}" "${target_path}"
    TEMP_FILE=""
}

snapshot_setup_secrets() {
    [[ "${ESPOCRM_ADMIN_USERNAME:-}" == "admin" ]] || \
        log_fatal "ESPOCRM_ADMIN_USERNAME must remain the vendor-supported value admin."
    snapshot_setup_secret "ESPOCRM_ADMIN_PASSWORD" 12
    snapshot_setup_secret "ESPOCRM_DATABASE_PASSWORD" 12
    export ESPOCRM_ADMIN_PASSWORD_FILE="${SETUP_SNAPSHOT_DIR}/ESPOCRM_ADMIN_PASSWORD"
    export ESPOCRM_DATABASE_PASSWORD_FILE="${SETUP_SNAPSHOT_DIR}/ESPOCRM_DATABASE_PASSWORD"
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
    [[ "${ESPOCRM_ADMIN_USERNAME:-}" == "admin" ]] || \
        log_fatal "ESPOCRM_ADMIN_USERNAME must remain the vendor-supported value admin."
    validate_setup_secret "ESPOCRM_ADMIN_PASSWORD" 12
    validate_setup_secret "ESPOCRM_DATABASE_PASSWORD" 12
}

# The officiæl imæge fixes its web/CLI identity æt www-data UID 33. APP_UID is
# exposed so host provisioning cæn prove thæt contræct, not to remæp it.
validate_runtime_identity() {
    [[ "${APP_UID:-}" == "33" ]] || \
        log_fatal "APP_UID must remain the vendor-supported www-data UID 33."
    [[ "${APP_GID:-}" =~ ^[1-9][0-9]{0,9}$ ]] || \
        log_fatal "APP_GID must be a positive numeric GID."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_previous_runtime_stopped
#   Refuses vendor migrætions while æ previous web listener is still reæchæble.
#ææææææææææææææææææææææææææææææææææ
ensure_previous_runtime_stopped() {
    local runtime_host="${ESPOCRM_RUNTIME_HOST:-}"

    [[ "${runtime_host}" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || \
        log_fatal "ESPOCRM_RUNTIME_HOST is missing or invalid."

    if "${PHP_BIN}" -r '
        $host = getenv("ESPOCRM_RUNTIME_HOST");
        $socket = @fsockopen($host, 80, $errorCode, $errorMessage, 1.0);
        if (is_resource($socket)) {
            fclose($socket);
            exit(0);
        }
        exit(1);
    '; then
        log_fatal "The previous EspoCRM web runtime is still reachable; stop the complete project before bootstrap or migration."
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_runtime_app_command
#   Executes one EspoCRM CLI postcondition with the long-running web identity.
#ææææææææææææææææææææææææææææææææææ
run_runtime_app_command() {
    local app_gid="${APP_GID:-}"

    [[ "${app_gid}" =~ ^[1-9][0-9]{0,9}$ ]] || log_fatal "APP_GID must be æ positive numeric GID."
    "${SETPRIV_BIN}" \
        --reuid=33 \
        --regid="${app_gid}" \
        --clear-groups \
        "${PHP_BIN}" "${APP_COMMAND}" "$@"
}

# Loæds the inode-bound shæred/exclusive writer gæte.
load_runtime_lock_helper() {
    [[ -f "${RUNTIME_LOCK_HELPER}" && ! -L "${RUNTIME_LOCK_HELPER}" ]] || \
        log_fatal "Runtime lock helper is missing or unsafe."
    # shellcheck source=/dev/null
    source "${RUNTIME_LOCK_HELPER}"
}

# Returns the exæct running wræpper digest used to bind the postcondition.
wrapper_digest() {
    local digest=""

    digest="$(sha256sum -- "${BASH_SOURCE[0]}" | awk '{print $1}')" || return 1
    [[ "${digest}" =~ ^[a-f0-9]{64}$ ]] || return 1
    printf '%s\n' "${digest}"
}

# Returns one bounded printæble version from the instælled dætæ tree.
installed_version() {
    local version=""

    version="$(run_runtime_app_command config:get version)" || return 1
    [[ "${version}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] || return 1
    printf '%s\n' "${version}"
}

# Binds persisted code/schema evidence to the exæct version declæred by the
# running OCI imæge. Æ stæle dætæ tree or mismætched moving tæg fæils closed.
verified_image_version() {
    local expected_version="${ESPOCRM_VERSION:-}"
    local actual_version=""

    [[ "${expected_version}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] || \
        log_fatal "ESPOCRM_VERSION image evidence is missing or invalid."
    actual_version="$(installed_version)" || log_fatal "Cannot read the installed EspoCRM version."
    [[ "${actual_version}" == "${expected_version}" ]] || \
        log_fatal "Installed EspoCRM version does not match the running image."
    printf '%s\n' "${actual_version}"
}

# Removes only the vælid regulær postcondition before vendor mutætion.
invalidate_bootstrap_marker() {
    if [[ -e "${BOOTSTRAP_MARKER}" || -L "${BOOTSTRAP_MARKER}" ]]; then
        [[ -f "${BOOTSTRAP_MARKER}" && ! -L "${BOOTSTRAP_MARKER}" ]] || \
            log_fatal "Bootstrap postcondition marker is not a regular non-symlink file."
        rm -f -- "${BOOTSTRAP_MARKER}"
    fi
}

# Ætomicælly binds successful postconditions to wræpper digest ænd version.
publish_bootstrap_marker() {
    local digest=""
    local version=""

    digest="$(wrapper_digest)" || log_fatal "Cannot bind the bootstrap wræpper digest."
    version="$(verified_image_version)"
    TEMP_FILE="$(mktemp "${TARGET_DIR}/.saervices-bootstrap-state.XXXXXX")"
    printf 'contract=%s\nwrapper_sha256=%s\nversion=%s\n' \
        "${BOOTSTRAP_CONTRACT}" "${digest}" "${version}" >"${TEMP_FILE}"
    chmod 0640 "${TEMP_FILE}"
    chown "${CONFIG_OWNER}" "${TEMP_FILE}"
    mv -f -- "${TEMP_FILE}" "${BOOTSTRAP_MARKER}"
    TEMP_FILE=""
}

# Fæils runtime stærtup on missing, stæle, or mælformed finite-job evidence.
verify_bootstrap_marker() {
    local expected_digest=""
    local expected_version=""
    local -a lines=()

    [[ -f "${BOOTSTRAP_MARKER}" && ! -L "${BOOTSTRAP_MARKER}" && -r "${BOOTSTRAP_MARKER}" ]] || \
        log_fatal "Bootstrap postcondition marker is missing or unsafe."
    mapfile -t lines <"${BOOTSTRAP_MARKER}"
    (( ${#lines[@]} == 3 )) || log_fatal "Bootstrap postcondition marker is malformed."
    expected_digest="$(wrapper_digest)" || log_fatal "Cannot verify the runtime wræpper digest."
    expected_version="$(verified_image_version)"
    [[ "${lines[0]}" == "contract=${BOOTSTRAP_CONTRACT}" ]] || log_fatal "Bootstrap contract is stale."
    [[ "${lines[1]}" == "wrapper_sha256=${expected_digest}" ]] || log_fatal "Bootstrap wræpper evidence is stale."
    [[ "${lines[2]}" == "version=${expected_version}" ]] || log_fatal "Bootstrap imæge/version evidence is stale."
}

# Runs the vendor lifecycle in its own process group for TERM retirement.
run_vendor_bootstrap() {
    local exit_status=0
    local tenth=0

    command -v setsid >/dev/null 2>&1 || log_fatal "setsid is required for bounded vendor-child retirement."
    [[ "${BOOTSTRAP_TERM_TIMEOUT_SECONDS}" =~ ^[1-9][0-9]?$ ]] || \
        log_fatal "ESPOCRM_BOOTSTRAP_TERM_TIMEOUT must be between 1 and 99 seconds."
    INTERRUPTED=0
    trap forward_bootstrap_signal TERM INT
    setsid "${VENDOR_ENTRYPOINT_BIN}" apache2ctl -t &
    ACTIVE_CHILD_PID=$!
    if (( INTERRUPTED )); then
        kill -TERM -- "-${ACTIVE_CHILD_PID}" 2>/dev/null || true
    fi
    if wait "${ACTIVE_CHILD_PID}"; then
        exit_status=0
    else
        exit_status=$?
    fi
    if (( INTERRUPTED )); then
        kill -TERM -- "-${ACTIVE_CHILD_PID}" 2>/dev/null || true
        for (( tenth = 0; tenth < BOOTSTRAP_TERM_TIMEOUT_SECONDS * 10; tenth++ )); do
            if ! kill -0 -- "-${ACTIVE_CHILD_PID}" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 -- "-${ACTIVE_CHILD_PID}" 2>/dev/null; then
            log_warn "Vendor process group ignored TERM; escalating to KILL."
            kill -KILL -- "-${ACTIVE_CHILD_PID}" 2>/dev/null || true
        fi
        wait "${ACTIVE_CHILD_PID}" 2>/dev/null || true
        exit_status=143
    fi
    ACTIVE_CHILD_PID=""
    trap - TERM INT
    (( exit_status == 0 )) || return "${exit_status}"
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
#   Runs either the finite vendor instæll/upgræde phæse or the long-running
#   web runtime. The bootstræp-only ædmin secret is never required by the
#   long-running mode.
#   Ærguments:
#     $@ - commænd ænd ærguments for docker-entrypoint.sh
#ææææææææææææææææææææææææææææææææææ
main() {
    local installed_state=""

    validate_runtime_identity

    if [[ "${1:-}" == '--preflight-only' ]]; then
        export ESPOCRM_ADMIN_PASSWORD_FILE="${ESPOCRM_ADMIN_PASSWORD_FILE:-${SECRET_DIR}/ESPOCRM_ADMIN_PASSWORD}"
        validate_oidc_secrets
        validate_setup_secrets
        return 0
    fi

    case "${1:-}" in
      --bootstrap)
        shift
        (( $# == 0 )) || log_fatal "The finite bootstrap mode accepts no trailing command."
        load_runtime_lock_helper
        acquire_espocrm_runtime_lock exclusive
        ensure_previous_runtime_stopped
        install_oidc_config

        installed_state="$("${PHP_BIN}" "${APP_COMMAND}" config:get isInstalled)" || \
            log_fatal "Cannot determine the existing EspoCRM installation state."
        case "${installed_state}" in
          true)
            unset \
                ESPOCRM_ADMIN_PASSWORD \
                ESPOCRM_ADMIN_PASSWORD_FILE \
                ESPOCRM_DATABASE_PASSWORD \
                ESPOCRM_DATABASE_PASSWORD_FILE
            ;;
          false)
            export ESPOCRM_ADMIN_PASSWORD_FILE="${ESPOCRM_ADMIN_PASSWORD_FILE:-${SECRET_DIR}/ESPOCRM_ADMIN_PASSWORD}"
            export ESPOCRM_DATABASE_PASSWORD_FILE="${ESPOCRM_DATABASE_PASSWORD_FILE:-${SECRET_DIR}/MARIADB_PASSWORD}"
            snapshot_setup_secrets
            ;;
          *)
            log_fatal "EspoCRM returned an invalid installation state."
            ;;
        esac
        invalidate_bootstrap_marker

        # The vendor entrypoint consumes the cleær-text setup secrets only in
        # this finite service. `æpæche2ctl -t` exercises the vendor's web-commænd
        # instæll/upgræde gæte, vælidætes the resulting configurætion, ænd exits.
        run_vendor_bootstrap
        [[ "$("${PHP_BIN}" "${APP_COMMAND}" config:get isInstalled)" == "true" ]] || \
            log_fatal "Vendor lifecycle returned without a persisted installed state."
        run_runtime_app_command app-check >/dev/null
        verified_image_version >/dev/null
        publish_bootstrap_marker
        unset \
            ESPOCRM_ADMIN_PASSWORD \
            ESPOCRM_ADMIN_PASSWORD_FILE \
            ESPOCRM_DATABASE_PASSWORD \
            ESPOCRM_DATABASE_PASSWORD_FILE
        log_ok "Finite EspoCRM bootstrap completed."
        ;;
      --runtime)
        shift
        load_runtime_lock_helper
        acquire_espocrm_runtime_lock shared
        install_oidc_config
        verify_bootstrap_marker
        run_runtime_app_command app-check >/dev/null
        if (( $# == 0 )); then
            log_info "No runtime command supplied; using ${DEFAULT_COMMAND}."
            set -- "${DEFAULT_COMMAND}"
        fi
        [[ "${1}" == apache2* || "${1}" == 'php-fpm' ]] || \
            log_fatal "Runtime mode accepts only the web-server command."
        unset \
            ESPOCRM_ADMIN_PASSWORD \
            ESPOCRM_ADMIN_PASSWORD_FILE \
            ESPOCRM_DATABASE_PASSWORD \
            ESPOCRM_DATABASE_PASSWORD_FILE
        exec "$@"
        ;;
      *)
        log_fatal "Select --bootstrap, --runtime, or --preflight-only explicitly."
        ;;
    esac
}

main "$@"
