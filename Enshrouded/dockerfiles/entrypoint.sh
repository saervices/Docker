#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Enshrouded server entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Responsibilities:
#   1. Prepære writæble runtime directories inside the persisted /server volume.
#   2. Run SteamCMD for AppID 2278520 on first stært ænd every configured stært.
#   3. Resolve the configured GE-Proton releæse ænd instæll it to persistent dætæ if needed.
#   4. Render enshrouded_server.json from environment væriæbles ænd Docker secrets.
#   5. Stært the Windows dedicæted server viæ GE-Proton ænd shut it down græcefully.

set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Logging
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
timestamp() {
    date +"%Y-%m-%d %H:%M:%S,%3N"
}

log_info() {
    printf '%s INFO: %s\n' "$(timestamp)" "$*" >&2
}

log_warn() {
    printf '%s WARN: %s\n' "$(timestamp)" "$*" >&2
}

log_error() {
    printf '%s ERROR: %s\n' "$(timestamp)" "$*" >&2
}

fatal() {
    log_error "$*"
    exit 1
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Pæths
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly STEAM_APP_ID="${STEAM_APP_ID:-2278520}"
readonly SERVER_ROOT="${ENSHROUDED_SERVER_ROOT:-/server}"
readonly GAME_DIR="${ENSHROUDED_GAME_DIR:-${SERVER_ROOT}/game}"
readonly HOME_DIR="${SERVER_ROOT}/home"
readonly TMP_DIR="${SERVER_ROOT}/tmp"
readonly CONFIG_FILE="${GAME_DIR}/enshrouded_server.json"
readonly SERVER_EXE="${GAME_DIR}/enshrouded_server.exe"
readonly BAKED_PROTON_DIR="${PROTON_DIR:-/opt/ge-proton}"
readonly BAKED_PROTON_BIN="${BAKED_PROTON_DIR}/proton"
readonly PROTON_STORE_DIR="${SERVER_ROOT}/proton"
readonly SDK32_SOURCE="/opt/steam-sdk/sdk32/steamclient.so"
readonly SDK64_SOURCE="/opt/steam-sdk/sdk64/steamclient.so"
PROTON_BIN="${BAKED_PROTON_BIN}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Configuræble vælues
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
SERVER_NAME="${ENSHROUDED_SERVER_NAME:-Enshrouded Server}"
readonly SERVER_IP="0.0.0.0"
readonly STEAM_PORT="27015"
QUERY_PORT="${ENSHROUDED_QUERY_PORT:-15637}"
SLOT_COUNT="${ENSHROUDED_SLOT_COUNT:-16}"
SAVE_DIR="${ENSHROUDED_SAVE_DIR:-./savegame}"
LOG_DIR="${ENSHROUDED_LOG_DIR:-./logs}"
VOICE_CHAT_MODE="${ENSHROUDED_VOICE_CHAT_MODE:-Proximity}"
ENABLE_VOICE_CHAT="${ENSHROUDED_ENABLE_VOICE_CHAT:-false}"
ENABLE_TEXT_CHAT="${ENSHROUDED_ENABLE_TEXT_CHAT:-false}"
GAME_SETTINGS_PRESET="${ENSHROUDED_GAME_SETTINGS_PRESET:-Default}"
UPDATE_ON_START="${ENSHROUDED_UPDATE_ON_START:-true}"
STEAM_BRANCH="${ENSHROUDED_STEAM_BRANCH:-public}"
PROTON_UPDATE_ON_START="${ENSHROUDED_PROTON_UPDATE_ON_START:-true}"
GE_PROTON_VERSION_REQUEST="${ENSHROUDED_GE_PROTON_VERSION:-latest}"
GE_PROTON_SHA512_REQUEST="${ENSHROUDED_GE_PROTON_SHA512:-auto}"
ADMIN_PASSWORD_FILE="${ENSHROUDED_ADMIN_PASSWORD_FILE:-/run/secrets/ENSHROUDED_ADMIN_PASSWORD}"
FRIEND_PASSWORD_FILE="${ENSHROUDED_FRIEND_PASSWORD_FILE:-/run/secrets/ENSHROUDED_FRIEND_PASSWORD}"
GUEST_PASSWORD_FILE="${ENSHROUDED_GUEST_PASSWORD_FILE:-/run/secrets/ENSHROUDED_GUEST_PASSWORD}"

server_pid=0

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Vælidætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
normalize_bool() {
    local name="$1"
    local value="${2,,}"

    case "${value}" in
        true|false)
            printf '%s' "${value}"
            ;;
        *)
            fatal "${name} must be true or false"
            ;;
    esac
}

validate_port() {
    local name="$1"
    local value="$2"

    [[ "${value}" =~ ^[0-9]+$ ]] || fatal "${name} must be numeric"
    (( value >= 1 && value <= 65535 )) || fatal "${name} must be between 1 and 65535"
}

validate_relative_path() {
    local name="$1"
    local value="$2"

    [[ "${value}" != /* ]] || fatal "${name} must be relative to the server directory"
    [[ "${value}" != *".."* ]] || fatal "${name} must not contain '..'"
}

validate_secret_file() {
    local path="$1"
    local name="$2"
    local value

    [[ -f "${path}" ]] || fatal "Docker secret ${name} is missing at ${path}"
    value="$(tr -d '\r\n' < "${path}")"
    [[ -n "${value}" ]] || fatal "Docker secret ${name} must not be empty"
    [[ "${value}" != "CHANGE_ME" ]] || fatal "Docker secret ${name} still contains CHANGE_ME"
}

validate_config() {
    validate_port "ENSHROUDED_QUERY_PORT" "${QUERY_PORT}"
    [[ "${SLOT_COUNT}" =~ ^[0-9]+$ ]] || fatal "ENSHROUDED_SLOT_COUNT must be numeric"
    (( SLOT_COUNT >= 1 && SLOT_COUNT <= 16 )) || fatal "ENSHROUDED_SLOT_COUNT must be between 1 and 16"
    validate_relative_path "ENSHROUDED_SAVE_DIR" "${SAVE_DIR}"
    validate_relative_path "ENSHROUDED_LOG_DIR" "${LOG_DIR}"

    case "${VOICE_CHAT_MODE}" in
        Proximity|Global)
            ;;
        *)
            fatal "ENSHROUDED_VOICE_CHAT_MODE must be Proximity or Global"
            ;;
    esac

    case "${GAME_SETTINGS_PRESET}" in
        Default|Relaxed|Hard|Survival|Custom)
            ;;
        *)
            fatal "ENSHROUDED_GAME_SETTINGS_PRESET must be Default, Relaxed, Hard, Survival or Custom"
            ;;
    esac

    ENABLE_VOICE_CHAT="$(normalize_bool "ENSHROUDED_ENABLE_VOICE_CHAT" "${ENABLE_VOICE_CHAT}")"
    ENABLE_TEXT_CHAT="$(normalize_bool "ENSHROUDED_ENABLE_TEXT_CHAT" "${ENABLE_TEXT_CHAT}")"
    UPDATE_ON_START="$(normalize_bool "ENSHROUDED_UPDATE_ON_START" "${UPDATE_ON_START}")"
    PROTON_UPDATE_ON_START="$(normalize_bool "ENSHROUDED_PROTON_UPDATE_ON_START" "${PROTON_UPDATE_ON_START}")"

    validate_secret_file "${ADMIN_PASSWORD_FILE}" "ENSHROUDED_ADMIN_PASSWORD"
    validate_secret_file "${FRIEND_PASSWORD_FILE}" "ENSHROUDED_FRIEND_PASSWORD"
    validate_secret_file "${GUEST_PASSWORD_FILE}" "ENSHROUDED_GUEST_PASSWORD"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Runtime prepærætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_runtime() {
    export HOME="${HOME_DIR}"
    export USER="${USER:-steam}"
    export TMPDIR="${TMP_DIR}"
    export XDG_CACHE_HOME="${HOME_DIR}/.cache"
    export XDG_CONFIG_HOME="${HOME_DIR}/.config"
    export XDG_DATA_HOME="${HOME_DIR}/.local/share"
    export WINEDEBUG="${WINEDEBUG:--all}"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="${HOME_DIR}/.steam/steam"
    export STEAM_COMPAT_DATA_PATH="${GAME_DIR}/steamapps/compatdata/${STEAM_APP_ID}"
    export STEAM_DIR="${HOME_DIR}/.steam/steam"
    export UMU_ID="${UMU_ID:-0}"

    mkdir -p \
        "${GAME_DIR}" \
        "${TMP_DIR}" \
        "${HOME_DIR}/.cache/protonfixes" \
        "${HOME_DIR}/.config/protonfixes" \
        "${HOME_DIR}/.local/share" \
        "${HOME_DIR}/.steam/sdk32" \
        "${HOME_DIR}/.steam/sdk64" \
        "${HOME_DIR}/.steam/steam" \
        "${PROTON_STORE_DIR}" \
        "${STEAM_COMPAT_DATA_PATH}"

    if [[ -f "${SDK32_SOURCE}" ]]; then
        ln -sf "${SDK32_SOURCE}" "${HOME_DIR}/.steam/sdk32/steamclient.so"
    fi
    if [[ -f "${SDK64_SOURCE}" ]]; then
        ln -sf "${SDK64_SOURCE}" "${HOME_DIR}/.steam/sdk64/steamclient.so"
        ln -sf "${SDK64_SOURCE}" "${HOME_DIR}/.steam/sdk64/steamservice.so"
    fi

    mkdir -p "${GAME_DIR}/${SAVE_DIR#./}" "${GAME_DIR}/${LOG_DIR#./}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GE-Proton updæte
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
baked_proton_version() {
    if [[ -f "${BAKED_PROTON_DIR}/GE-PROTON-VERSION" ]]; then
        tr -d '\r\n' < "${BAKED_PROTON_DIR}/GE-PROTON-VERSION"
    fi
}

latest_ge_proton_version() {
    curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest \
        | jq -r '.tag_name' \
        | sed 's/^GE-Proton//'
}

resolve_ge_proton_version() {
    local requested="$1"
    local version

    if [[ "${requested}" == "latest" ]]; then
        version="$(latest_ge_proton_version)"
    else
        version="${requested#GE-Proton}"
    fi

    [[ -n "${version}" && "${version}" != "null" ]] || return 1
    printf '%s' "${version}"
}

resolve_ge_proton_sha512() {
    local version="$1"
    local requested_sha="$2"

    if [[ "${requested_sha}" != "auto" ]]; then
        printf '%s' "${requested_sha}"
        return 0
    fi

    curl -fsSL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${version}/GE-Proton${version}.sha512sum" \
        | awk -v file="GE-Proton${version}.tar.gz" '$2 == file { print $1; exit }'
}

install_ge_proton() {
    local version="$1"
    local sha512="$2"
    local target_dir="${PROTON_STORE_DIR}/GE-Proton${version}"
    local tmp_dir

    if [[ -x "${target_dir}/proton" ]]; then
        PROTON_BIN="${target_dir}/proton"
        log_info "Using persisted GE-Proton ${version}"
        return 0
    fi

    [[ -n "${sha512}" ]] || return 1
    tmp_dir="$(mktemp -d "${TMP_DIR}/ge-proton.XXXXXX")"

    log_info "Downloading GE-Proton ${version}"
    curl -fsSL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${version}/GE-Proton${version}.tar.gz" \
        -o "${tmp_dir}/ge-proton.tar.gz"
    echo "${sha512}  ${tmp_dir}/ge-proton.tar.gz" | sha512sum -c -

    rm -rf "${target_dir}.tmp"
    mkdir -p "${target_dir}.tmp"
    tar -xzf "${tmp_dir}/ge-proton.tar.gz" -C "${target_dir}.tmp" --strip-components=1
    printf '%s\n' "${version}" > "${target_dir}.tmp/GE-PROTON-VERSION"
    chmod -R u+rwX,go+rX "${target_dir}.tmp"
    mv "${target_dir}.tmp" "${target_dir}"
    rm -rf "${tmp_dir}"

    PROTON_BIN="${target_dir}/proton"
    log_info "Installed GE-Proton ${version}"
}

ensure_ge_proton() {
    local version
    local sha512
    local baked_version

    baked_version="$(baked_proton_version || true)"

    if [[ "${PROTON_UPDATE_ON_START}" != "true" ]]; then
        PROTON_BIN="${BAKED_PROTON_BIN}"
        log_info "Skipping GE-Proton update because ENSHROUDED_PROTON_UPDATE_ON_START=false"
        return 0
    fi

    if ! version="$(resolve_ge_proton_version "${GE_PROTON_VERSION_REQUEST}")"; then
        log_warn "Could not resolve GE-Proton ${GE_PROTON_VERSION_REQUEST}; using baked Proton"
        PROTON_BIN="${BAKED_PROTON_BIN}"
        return 0
    fi

    if [[ -n "${baked_version}" && "${version}" == "${baked_version}" && -x "${BAKED_PROTON_BIN}" ]]; then
        PROTON_BIN="${BAKED_PROTON_BIN}"
        log_info "Baked GE-Proton ${version} is current"
        return 0
    fi

    if ! sha512="$(resolve_ge_proton_sha512 "${version}" "${GE_PROTON_SHA512_REQUEST}")"; then
        log_warn "Could not resolve checksum for GE-Proton ${version}; using baked Proton"
        PROTON_BIN="${BAKED_PROTON_BIN}"
        return 0
    fi

    if ! install_ge_proton "${version}" "${sha512}"; then
        log_warn "Could not install GE-Proton ${version}; using baked Proton"
        PROTON_BIN="${BAKED_PROTON_BIN}"
    fi
}

verify_cpu_mhz() {
    local cpu_mhz
    cpu_mhz="$(grep '^cpu MHz' /proc/cpuinfo | head -1 | cut -d : -f 2 | xargs || true)"
    if [[ "${cpu_mhz}" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( ${cpu_mhz%.*} > 0 )); then
        unset CPU_MHZ || true
    else
        export CPU_MHZ="1500.000"
    fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SteamCMD updæte
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
steamcmd_args() {
    local args=(
        +@sSteamCmdForcePlatformType windows
        +force_install_dir "${GAME_DIR}"
        +login anonymous
        +app_update "${STEAM_APP_ID}"
    )

    if [[ "${STEAM_BRANCH}" != "public" ]]; then
        args+=(-beta "${STEAM_BRANCH}")
    fi

    args+=(validate +quit)
    printf '%s\0' "${args[@]}"
}

run_steamcmd_update() {
    local -a args

    mapfile -d '' -t args < <(steamcmd_args)
    verify_cpu_mhz

    log_info "Running SteamCMD update for AppID ${STEAM_APP_ID} (branch: ${STEAM_BRANCH})"
    if steamcmd "${args[@]}"; then
        return 0
    fi

    log_warn "SteamCMD update failed; removing appmanifest and retrying once"
    rm -f "${GAME_DIR}/steamapps/appmanifest_${STEAM_APP_ID}.acf"
    steamcmd "${args[@]}"
}

ensure_server_files() {
    if [[ "${UPDATE_ON_START}" == "true" || ! -f "${SERVER_EXE}" ]]; then
        run_steamcmd_update
    else
        log_info "Skipping SteamCMD update because ENSHROUDED_UPDATE_ON_START=false"
    fi

    [[ -f "${SERVER_EXE}" ]] || fatal "Server executable not found at ${SERVER_EXE}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Server configurætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
render_config_filter() {
    cat <<'JQ'
def trim_secret: gsub("[\r\n]+$"; "");
.name = $name
| .password = ""
| .saveDirectory = $saveDirectory
| .logDirectory = $logDirectory
| .ip = $ip
| .queryPort = ($queryPort | tonumber)
| .slotCount = ($slotCount | tonumber)
| .voiceChatMode = $voiceChatMode
| .enableVoiceChat = ($enableVoiceChat == "true")
| .enableTextChat = ($enableTextChat == "true")
| .gameSettingsPreset = $gameSettingsPreset
| .userGroups = [
    {
      "name": "Admin",
      "password": ($adminPassword | trim_secret),
      "canKickBan": true,
      "canAccessInventories": true,
      "canEditBase": true,
      "canExtendBase": true,
      "reservedSlots": 1
    },
    {
      "name": "Friend",
      "password": ($friendPassword | trim_secret),
      "canKickBan": false,
      "canAccessInventories": true,
      "canEditBase": true,
      "canExtendBase": true,
      "reservedSlots": 3
    },
    {
      "name": "Guest",
      "password": ($guestPassword | trim_secret),
      "canKickBan": false,
      "canAccessInventories": false,
      "canEditBase": false,
      "canExtendBase": false,
      "reservedSlots": 0
    }
  ]
JQ
}

write_server_config() {
    local tmp_file
    local jq_filter

    tmp_file="$(mktemp "${GAME_DIR}/enshrouded_server.json.XXXXXX")"
    jq_filter="$(render_config_filter)"

    if [[ -f "${CONFIG_FILE}" ]]; then
        jq \
            --arg name "${SERVER_NAME}" \
            --arg saveDirectory "${SAVE_DIR}" \
            --arg logDirectory "${LOG_DIR}" \
            --arg ip "${SERVER_IP}" \
            --arg queryPort "${QUERY_PORT}" \
            --arg slotCount "${SLOT_COUNT}" \
            --arg voiceChatMode "${VOICE_CHAT_MODE}" \
            --arg enableVoiceChat "${ENABLE_VOICE_CHAT}" \
            --arg enableTextChat "${ENABLE_TEXT_CHAT}" \
            --arg gameSettingsPreset "${GAME_SETTINGS_PRESET}" \
            --rawfile adminPassword "${ADMIN_PASSWORD_FILE}" \
            --rawfile friendPassword "${FRIEND_PASSWORD_FILE}" \
            --rawfile guestPassword "${GUEST_PASSWORD_FILE}" \
            "${jq_filter}" "${CONFIG_FILE}" > "${tmp_file}"
    else
        jq -n \
            --arg name "${SERVER_NAME}" \
            --arg saveDirectory "${SAVE_DIR}" \
            --arg logDirectory "${LOG_DIR}" \
            --arg ip "${SERVER_IP}" \
            --arg queryPort "${QUERY_PORT}" \
            --arg slotCount "${SLOT_COUNT}" \
            --arg voiceChatMode "${VOICE_CHAT_MODE}" \
            --arg enableVoiceChat "${ENABLE_VOICE_CHAT}" \
            --arg enableTextChat "${ENABLE_TEXT_CHAT}" \
            --arg gameSettingsPreset "${GAME_SETTINGS_PRESET}" \
            --rawfile adminPassword "${ADMIN_PASSWORD_FILE}" \
            --rawfile friendPassword "${FRIEND_PASSWORD_FILE}" \
            --rawfile guestPassword "${GUEST_PASSWORD_FILE}" \
            "${jq_filter}" > "${tmp_file}"
    fi

    mv "${tmp_file}" "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
    log_info "Updated ${CONFIG_FILE}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Server process
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
udp_port_open() {
    local port_hex
    port_hex="$(printf '%04X' "${QUERY_PORT}")"
    awk -v port=":${port_hex}" 'toupper($2) ~ port "$" { found = 1 } END { exit found ? 0 : 1 }' /proc/net/udp /proc/net/udp6 2>/dev/null
}

shutdown() {
    log_info "Received shutdown signal"

    pkill -INT -f '[e]nshrouded_server.exe' 2>/dev/null || true
    if (( server_pid > 0 )) && kill -0 "${server_pid}" 2>/dev/null; then
        kill -INT "${server_pid}" 2>/dev/null || true
    fi

    for _ in $(seq 1 90); do
        pgrep -f '[e]nshrouded_server.exe' >/dev/null 2>&1 || return 0
        sleep 1
    done

    log_warn "Graceful shutdown timed out; sending SIGTERM"
    pkill -TERM -f '[e]nshrouded_server.exe' 2>/dev/null || true
    if (( server_pid > 0 )) && kill -0 "${server_pid}" 2>/dev/null; then
        kill -TERM "${server_pid}" 2>/dev/null || true
    fi
}

start_server() {
    [[ -x "${PROTON_BIN}" ]] || fatal "Proton executable not found at ${PROTON_BIN}"

    chmod +x "${SERVER_EXE}" || true
    trap shutdown SIGINT SIGTERM

    log_info "Starting Enshrouded Dedicated Server on UDP ${QUERY_PORT}; Steam discovery UDP ${STEAM_PORT}"
    "${PROTON_BIN}" run "${SERVER_EXE}" &
    server_pid=$!

    log_info "Waiting for server UDP listener"
    for _ in $(seq 1 180); do
        if udp_port_open; then
            log_info "Server is listening on UDP ${QUERY_PORT}"
            break
        fi
        if ! kill -0 "${server_pid}" 2>/dev/null; then
            wait "${server_pid}" || true
            fatal "Proton process exited before the server opened UDP ${QUERY_PORT}"
        fi
        sleep 5
    done

    udp_port_open || fatal "Timed out waiting for UDP ${QUERY_PORT}"

    while udp_port_open; do
        sleep 10
    done

    wait "${server_pid}" || true
    log_info "Server UDP listener stopped"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mæin
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main() {
    log_info "Preparing Enshrouded Dedicated Server"
    validate_config
    prepare_runtime
    ensure_ge_proton
    ensure_server_files
    write_server_config
    start_server
}

main "$@"
