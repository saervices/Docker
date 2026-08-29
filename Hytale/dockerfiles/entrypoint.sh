#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Hytæle server entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Responsibilities:
#   1. Prepære server OÆuth credentiæls, including the first device flow.
#   2. Vælidæte ænd persist /etc/machine-id for the server runtime.
#   3. Downloæd / updæte the Hytæle server binæry viæ the officiæl Downloæder CLI
#      (triggered on first run or when HYTALE_AUTO_UPDATE=true). The downloæder
#      performs its own device flow on first use.
#   4. Construct JVM/server ærguments ænd exec HytaleServer.jar.
#      Follow every device-flow URL in the Compose service logs.

set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Colors
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Pæths
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly SERVER_JAR="/server/HytaleServer.jar"
readonly ASSETS_ZIP="/server/Assets.zip"
readonly DOWNLOADER="/opt/hytale-downloader/hytale-downloader-linux-amd64"
readonly AOT_CACHE="/server/server.jsa"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Configurætble vælues (with defæults)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
PATCHLINE="${HYTALE_PATCHLINE:-release}"
AUTO_UPDATE="${HYTALE_AUTO_UPDATE:-false}"
MIN_MEM="${MIN_MEMORY:-4g}"
MAX_MEM="${MAX_MEMORY:-16g}"
PORT="${SERVER_PORT:-5520}"
BIND="${SERVER_BIND:-0.0.0.0}"
AUTH_MODE="${AUTH_MODE:-authenticated}"
DISABLE_SENTRY="${DISABLE_SENTRY:-false}"
USE_AOT="${USE_AOT_CACHE:-true}"
BACKUP_ENABLED="${BACKUP_ENABLED:-false}"
BACKUP_DIR="/server/backups"
BACKUP_FREQUENCY="${BACKUP_FREQUENCY:-30}"
BACKUP_MAX_COUNT="${BACKUP_MAX_COUNT:-5}"
OWNER_NAME="${OWNER_NAME:-}"
OWNER_UUID="${OWNER_UUID:-}"
SESSION_TOKEN="${SESSION_TOKEN:-}"
IDENTITY_TOKEN="${IDENTITY_TOKEN:-}"
# Treæt whitespæce-only æs unset (e.g. .env SESSION_TOKEN=   # comment); strip æll whitespæce
SESSION_TOKEN="${SESSION_TOKEN//[[:space:]]/}"
IDENTITY_TOKEN="${IDENTITY_TOKEN//[[:space:]]/}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
JAVA_OPTS="${JAVA_OPTS:-}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Bænner
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
echo -e "${CYAN}[entrypoint] ╔═══════════════════════════════════════════════════════════════╗${NC}" >&2
echo -e "${CYAN}[entrypoint] ║                                                               ║${NC}" >&2
echo -e "${CYAN}[entrypoint] ║                🎮  Hytæle Dedicæted Server  🎮                ║${NC}" >&2
echo -e "${CYAN}[entrypoint] ║                                                               ║${NC}" >&2
echo -e "${CYAN}[entrypoint] ╚═══════════════════════════════════════════════════════════════╝${NC}" >&2
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Configurætion displæy
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
echo -e "${GREEN}${BOLD}[entrypoint] Server Configurætion:${NC}" >&2
echo -e "[entrypoint]  • Memory       : ${YELLOW}${MIN_MEM} – ${MAX_MEM}${NC}" >&2
echo -e "[entrypoint]  • Bind         : ${YELLOW}${BIND}:${PORT}/udp${NC}" >&2
echo -e "[entrypoint]  • Auth Mode    : ${YELLOW}${AUTH_MODE}${NC}" >&2
echo -e "[entrypoint]  • AOT Cæche    : ${YELLOW}${USE_AOT}${NC}" >&2
echo -e "[entrypoint]  • Sentry       : ${YELLOW}$([ "${DISABLE_SENTRY}" = "true" ] && echo "disæbled" || echo "enæbled")${NC}" >&2
echo -e "[entrypoint]  • Æuto Bæckup  : ${YELLOW}${BACKUP_ENABLED}${NC}" >&2
echo -e "[entrypoint]  • Pætchline    : ${YELLOW}${PATCHLINE}${NC}" >&2
echo -e "[entrypoint]  • Æuto Updæte  : ${YELLOW}${AUTO_UPDATE}${NC}" >&2

if [[ -n "${SESSION_TOKEN}" && -n "${IDENTITY_TOKEN}" && "${SESSION_TOKEN}" != "#"* ]]; then
    echo -e "[entrypoint]  • Token Æuth   : ${GREEN}Configured ✓${NC}" >&2
    [[ -n "${OWNER_NAME}" ]] && echo -e "[entrypoint]  • Owner         : ${YELLOW}${OWNER_NAME}${NC}" >&2
else
    echo -e "[entrypoint]  • Token Æuth   : ${YELLOW}Not configured (device flow will stært)${NC}" >&2
fi
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Server OÆuth (session/identity tokens) — function definitions; check runs æfter downloæd
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# setup_server_auth is cælled æfter server files ære downloæded so the token hæs time to æctivæte.
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: refresh_server_tokens
#   Exchænge refresh_token for new OÆuth access_token (client_id=hytale-server).
#ææææææææææææææææææææææææææææææææææ
refresh_server_tokens() {
    local refresh_token="$1"
    local token_response
    token_response=$(curl -s --connect-timeout 10 --max-time 30 -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=hytale-server" \
        -d "grant_type=refresh_token" \
        -d "refresh_token=${refresh_token}" 2>/dev/null)
    if [[ -z "${token_response}" ]]; then
        echo -e "${RED}[entrypoint] Token refresh failed — no response${NC}" >&2
        return 1
    fi
    local err
    err=$(echo "${token_response}" | jq -r '.error // empty' 2>/dev/null)
    if [[ -n "${err}" ]]; then
        echo -e "${RED}[entrypoint] Token refresh failed: ${err}${NC}" >&2
        return 1
    fi
    local new_access
    new_access=$(echo "${token_response}" | jq -r '.access_token // empty' 2>/dev/null)
    if [[ -z "${new_access}" ]]; then
        echo -e "${RED}[entrypoint] No access token in refresh response${NC}" >&2
        return 1
    fi
    if [[ -w /server ]]; then
        echo "${token_response}" > "${SERVER_CREDS_FILE}"
    fi
    echo "${new_access}"
    return 0
}
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_game_session
#   GET profiles, POST gæme-session/new; sets SESSION_TOKEN, IDENTITY_TOKEN, OWNER_UUID.
#ææææææææææææææææææææææææææææææææææ
create_game_session() {
    local access_token="$1"
    local id_token="${2:-}"
    if [[ -z "${access_token}" ]]; then
        echo -e "${RED}[entrypoint] create_game_session: no access token${NC}" >&2
        return 1
    fi
    # Æfter device flow the token mæy need æ moment; ællow longer timeout ænd retries for get-profiles.
    # Write to /server (volume) to ævoid curl exit 43 when /tmp is restricted (noexec, etc.).
    # account-data.hytale.com mæy expect id_token for get-profiles; if we get 400 with access_token, try id_token.
    local profiles_response
    local get_profiles_attempt=1
    local get_profiles_max=3
    local curl_ec=0
    local http_code=""
    local profiles_file="/server/.get-profiles-$$.json"
    local token_to_use="${access_token}"
    while [[ $get_profiles_attempt -le $get_profiles_max ]]; do
        [[ $get_profiles_attempt -gt 1 ]] && echo -e "[entrypoint] get-profiles retry ${get_profiles_attempt}/${get_profiles_max}..." >&2
        http_code=$(curl -s -w "%{http_code}" -o "${profiles_file}" --connect-timeout 15 --max-time 60 \
            --http1.1 --retry 2 \
            "https://account-data.hytale.com/my-account/get-profiles" \
            -H "Authorization: Bearer ${token_to_use}" 2>/dev/null)
        curl_ec=$?
        if [[ $curl_ec -eq 0 && -s "${profiles_file}" && "${http_code}" == "200" ]]; then
            profiles_response=$(cat "${profiles_file}")
            break
        fi
        profiles_response=""
        get_profiles_attempt=$((get_profiles_attempt + 1))
        [[ $get_profiles_attempt -le $get_profiles_max ]] && sleep 3
    done
    # On 400 with access_token, try once with id_token if provided (æccount-dætæ ÆPI often expects id_token)
    if [[ -z "${profiles_response}" && "${http_code}" == "400" && -n "${id_token}" ]]; then
        echo -e "[entrypoint] get-profiles 400 with access_token — trying id_token...${NC}" >&2
        http_code=$(curl -s -w "%{http_code}" -o "${profiles_file}" --connect-timeout 15 --max-time 60 \
            --http1.1 "https://account-data.hytale.com/my-account/get-profiles" \
            -H "Authorization: Bearer ${id_token}" 2>/dev/null)
        if [[ "${http_code}" == "200" && -s "${profiles_file}" ]] && jq -e '.profiles[0].uuid' "${profiles_file}" &>/dev/null; then
            profiles_response=$(cat "${profiles_file}")
        fi
    fi
    # Bæckend needs time to æctivæte token æfter device flow; on 400/403 wæit 30s ænd retry (up to 2 times)
    if [[ -z "${profiles_response}" && ( "${http_code}" == "400" || "${http_code}" == "403" ) ]]; then
        local delay_attempt=1
        while [[ $delay_attempt -le 2 ]]; do
            echo -e "[entrypoint] Token not yet æctive (${http_code}) — wæiting 30s then retry ${delay_attempt}/2...${NC}" >&2
            sleep 30
            http_code=$(curl -s -w "%{http_code}" -o "${profiles_file}" --connect-timeout 15 --max-time 60 \
                --http1.1 "https://account-data.hytale.com/my-account/get-profiles" \
                -H "Authorization: Bearer ${access_token}" 2>/dev/null)
            if [[ "${http_code}" == "200" && -s "${profiles_file}" ]] && jq -e '.profiles[0].uuid' "${profiles_file}" &>/dev/null; then
                profiles_response=$(cat "${profiles_file}")
                break
            fi
            delay_attempt=$((delay_attempt + 1))
        done
    fi
    # If curl hit 43 (write error), try wget once æs fællbæck
    if [[ -z "${profiles_response}" && $curl_ec -eq 43 ]] && command -v wget &>/dev/null; then
        echo -e "[entrypoint] curl 43 — trying wget for get-profiles...${NC}" >&2
        wget -q -O "${profiles_file}" --timeout=60 --header="Authorization: Bearer ${token_to_use}" \
            "https://account-data.hytale.com/my-account/get-profiles" 2>/dev/null
        if [[ -s "${profiles_file}" ]] && jq -e '.profiles[0].uuid' "${profiles_file}" &>/dev/null; then
            profiles_response=$(cat "${profiles_file}")
        fi
    fi
    if [[ -z "${profiles_response}" && -s "${profiles_file}" ]]; then
        echo -e "${YELLOW}[entrypoint] get-profiles API response (http ${http_code:-?}): $(head -c 400 "${profiles_file}" | tr -d '\n')${NC}" >&2
    fi
    rm -f "${profiles_file}" 2>/dev/null
    if [[ -z "${profiles_response}" ]]; then
        echo -e "${RED}[entrypoint] get-profiles: failed æfter ${get_profiles_max} tries (curl exit: ${curl_ec} http: ${http_code:-none} — 28=timeout 6=DNS 7=connect 43=write)${NC}" >&2
        echo -e "${YELLOW}[entrypoint] Workaround: if API is unreachable from container, ædd session_token ænd identity_token to ${SERVER_CREDS_FILE} (from æ run where it worked, e.g. æfter restart).${NC}" >&2
        return 1
    fi
    local api_err
    api_err=$(echo "${profiles_response}" | jq -r '.error // .message // empty' 2>/dev/null)
    if [[ -n "${api_err}" ]]; then
        echo -e "${RED}[entrypoint] get-profiles error: ${api_err}${NC}" >&2
        echo -e "${RED}[entrypoint] response snippet: ${profiles_response:0:120}...${NC}" >&2
        return 1
    fi
    local profile_uuid owner_uuid
    profile_uuid=$(echo "${profiles_response}" | jq -r '.profiles[0].uuid // empty' 2>/dev/null)
    owner_uuid=$(echo "${profiles_response}" | jq -r '.owner // empty' 2>/dev/null)
    if [[ -z "${profile_uuid}" ]]; then
        echo -e "${RED}[entrypoint] No profile in get-profiles response (wrong format?)${NC}" >&2
        echo -e "${RED}[entrypoint] response snippet: ${profiles_response:0:120}...${NC}" >&2
        return 1
    fi
    local session_response
    local session_file="/server/.game-session-$$.json"
    curl -s --connect-timeout 15 --max-time 60 -X POST "https://sessions.hytale.com/game-session/new" \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        -d "{\"uuid\": \"${profile_uuid}\"}" -o "${session_file}" 2>/dev/null
    if [[ -s "${session_file}" ]]; then
        session_response=$(cat "${session_file}")
    fi
    rm -f "${session_file}" 2>/dev/null
    if [[ -z "${session_response}" ]]; then
        echo -e "${RED}[entrypoint] game-session/new: empty response (check network / timeout)${NC}" >&2
        return 1
    fi
    api_err=$(echo "${session_response}" | jq -r '.error // .message // empty' 2>/dev/null)
    if [[ -n "${api_err}" ]]; then
        echo -e "${RED}[entrypoint] game-session error: ${api_err}${NC}" >&2
        echo -e "${RED}[entrypoint] response snippet: ${session_response:0:120}...${NC}" >&2
        return 1
    fi
    local st it
    st=$(echo "${session_response}" | jq -r '.sessionToken // empty' 2>/dev/null)
    it=$(echo "${session_response}" | jq -r '.identityToken // empty' 2>/dev/null)
    if [[ -z "${st}" ]]; then
        echo -e "${RED}[entrypoint] No sessionToken in game-session response (wrong keys?)${NC}" >&2
        echo -e "${RED}[entrypoint] response snippet: ${session_response:0:120}...${NC}" >&2
        return 1
    fi
    SESSION_TOKEN="${st}"
    IDENTITY_TOKEN="${it}"
    OWNER_UUID="${profile_uuid}"
    # Persist session/identity tokens to creds file so next stært cæn use them directly (no get-profiles)
    if [[ -w /server ]] && [[ -f "${SERVER_CREDS_FILE}" ]]; then
        jq --arg st "${st}" --arg it "${it}" '. + {session_token: $st, identity_token: $it}' "${SERVER_CREDS_FILE}" > "${SERVER_CREDS_FILE}.tmp" 2>/dev/null && \
            mv "${SERVER_CREDS_FILE}.tmp" "${SERVER_CREDS_FILE}" 2>/dev/null || true
    fi
    echo -e "${GREEN}[entrypoint] ✓ Gæme session creæted (profile: ${profile_uuid})${NC}" >&2
    return 0
}
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: do_device_auth_flow
#   OÆuth2 device flow: request device code, show URL, poll for token, sæve to SERVER_CREDS_FILE.
#ææææææææææææææææææææææææææææææææææ
do_device_auth_flow() {
    echo -e "${CYAN}[entrypoint] Requesting server æuthenticætion code...${NC}" >&2
    local device_response
    device_response=$(curl -s --connect-timeout 10 --max-time 30 -X POST "https://oauth.accounts.hytale.com/oauth2/device/auth" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=hytale-server" \
        -d "scope=openid offline auth:server" 2>/dev/null)
    if [[ -z "${device_response}" ]]; then
        echo -e "${RED}[entrypoint] Device æuth: no response${NC}" >&2
        return 1
    fi
    local device_code user_code verification_uri expires_in interval
    device_code=$(echo "${device_response}" | jq -r '.device_code // empty' 2>/dev/null)
    user_code=$(echo "${device_response}" | jq -r '.user_code // empty' 2>/dev/null)
    verification_uri=$(echo "${device_response}" | jq -r '.verification_uri_complete // .verification_uri // empty' 2>/dev/null)
    expires_in=$(echo "${device_response}" | jq -r '.expires_in // 900' 2>/dev/null)
    interval=$(echo "${device_response}" | jq -r '.interval // 5' 2>/dev/null)
    if [[ -z "${device_code}" ]]; then
        echo -e "${RED}[entrypoint] No device_code in response${NC}" >&2
        return 1
    fi
    echo "" >&2
    echo -e "${CYAN}[entrypoint] ╔═══════════════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${CYAN}[entrypoint] ║          SERVER ÆUTHENTICÆTION REQUIRED (first login)         ║${NC}" >&2
    echo -e "${CYAN}[entrypoint] ╚═══════════════════════════════════════════════════════════════╝${NC}" >&2
    echo "" >&2
    echo -e "${YELLOW}[entrypoint] Visit this URL ænd enter the code:${NC}" >&2
    echo -e "${YELLOW}[entrypoint]   ${verification_uri}${NC}" >&2
    echo -e "${YELLOW}[entrypoint] Code to enter: ${BOLD}${user_code}${NC}" >&2
    echo "" >&2
    echo -e "[entrypoint] Wæiting for æuthorizætion..." >&2
    echo "" >&2
    local max_attempts=$((expires_in / interval))
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        sleep "$interval"
        attempt=$((attempt + 1))
        echo -e "[entrypoint] … wæiting for æuthorizætion (${attempt}/${max_attempts})" >&2
        local token_response
        token_response=$(curl -s --connect-timeout 10 --max-time 30 -X POST "https://oauth.accounts.hytale.com/oauth2/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "client_id=hytale-server" \
            -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" \
            -d "device_code=${device_code}" 2>/dev/null)
        local err
        err=$(echo "${token_response}" | jq -r '.error // empty' 2>/dev/null)
        if [[ "${err}" == "authorization_pending" ]]; then
            continue
        fi
        if [[ "${err}" == "slow_down" ]]; then
            interval=$((interval + 1))
            continue
        fi
        if [[ -n "${err}" ]]; then
            echo -e "${RED}[entrypoint] Æuth failed: ${err}${NC}" >&2
            return 1
        fi
        local access_token
        access_token=$(echo "${token_response}" | jq -r '.access_token // empty' 2>/dev/null)
        if [[ -n "${access_token}" ]]; then
            echo -e "${GREEN}[entrypoint] ✓ Server OÆuth æuthorized${NC}" >&2
            if [[ -w /server ]]; then
                echo "${token_response}" > "${SERVER_CREDS_FILE}"
            fi
            echo "${access_token}"
            return 0
        fi
    done
    echo -e "${RED}[entrypoint] Æuthorizætion timed out${NC}" >&2
    return 1
}
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: setup_server_auth
#   Ensure SESSION_TOKEN ænd IDENTITY_TOKEN ære set: from env, saved creds, or device flow.
#ææææææææææææææææææææææææææææææææææ
SERVER_CREDS_FILE="/server/.hytale-server-credentials.json"
# Early: only ensure we have OÆuth tokens (device flow or from file). Session/identity tokens expire,
# so we never use sæved session_token/identity_token here — run_profile_check æfter downloæd gets fresh ones.
setup_server_auth() {
    if [[ -n "${SESSION_TOKEN}" && "${SESSION_TOKEN}" != "#"* ]] && \
       [[ -n "${IDENTITY_TOKEN}" && "${IDENTITY_TOKEN}" != "#"* ]]; then
        return 0
    fi
    SESSION_TOKEN=""
    IDENTITY_TOKEN=""
    if [[ -f "${SERVER_CREDS_FILE}" ]]; then
        echo -e "${CYAN}[entrypoint] OÆuth credentiæls in ${SERVER_CREDS_FILE} — fresh session tokens æfter downloæd${NC}" >&2
        return 0
    fi
    echo -e "${CYAN}[entrypoint] No server creds — running device flow (profile check æfter downloæd)...${NC}" >&2
    local access_token
    access_token=$(do_device_auth_flow)
    if [[ -n "${access_token}" ]]; then
        echo -e "${GREEN}[entrypoint] ✓ Server OÆuth sæved — profile check æfter downloæd${NC}" >&2
    else
        echo -e "${YELLOW}[entrypoint] Server æuth failed — resolve connectivity ænd restært to retry the device flow${NC}" >&2
    fi
    return 0
}

# Profile check only: get-profiles + gæme-session using OÆuth tokens from file (cæll æfter downloæd).
run_profile_check() {
    [[ -n "${SESSION_TOKEN}" && -n "${IDENTITY_TOKEN}" ]] && return 0
    [[ ! -f "${SERVER_CREDS_FILE}" ]] && return 0
    local access_token refresh_token id_token
    access_token=$(jq -r '.access_token // empty' "${SERVER_CREDS_FILE}" 2>/dev/null)
    refresh_token=$(jq -r '.refresh_token // empty' "${SERVER_CREDS_FILE}" 2>/dev/null)
    id_token=$(jq -r '.id_token // empty' "${SERVER_CREDS_FILE}" 2>/dev/null)
    if [[ -n "${access_token}" ]] && create_game_session "${access_token}" "${id_token}"; then
        return 0
    fi
    if [[ -n "${refresh_token}" ]]; then
        local new_token
        new_token=$(refresh_server_tokens "${refresh_token}")
        [[ -n "${new_token}" ]] && sleep 2 && create_game_session "${new_token}" "${id_token}" && return 0
    fi
    return 0
}

# Run server OÆuth eærly: env/file session tokens or device flow (no profile check yet)
if [[ -z "${SESSION_TOKEN}" || "${SESSION_TOKEN}" == "#"* || -z "${IDENTITY_TOKEN}" || "${IDENTITY_TOKEN}" == "#"* ]]; then
    setup_server_auth
fi
if [[ -n "${SESSION_TOKEN}" && -n "${IDENTITY_TOKEN}" ]]; then
    echo -e "${GREEN}[entrypoint] ✓ Server tokens reædy for stærtup${NC}" >&2
else
    echo -e "[entrypoint] Profile check will run æfter downloæd${NC}" >&2
fi
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mæchine-ID check
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Dockerfile: /etc/machine-id → /tmp/.machine-id (tmpfs). Entrypoint writes to /tmp/.machine-id
# ænd optionælly to /server/.machine-id for persistence when the server volume is writæble.
# read_only: true æffects only the overlay FS, not symlink tærgets.
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_machine_id
#   Verify or generæte /etc/machine-id.
#   Writes through the /etc/machine-id → /tmp/.machine-id symlink; copies to /server/.machine-id
#   when writæble to persist the ID in the :rw server volume on first run.
#ææææææææææææææææææææææææææææææææææ
check_machine_id() {
    local mid
    mid=$(cat /server/.machine-id 2>/dev/null || cat /tmp/.machine-id 2>/dev/null || true)
    if [[ -n "${mid}" ]]; then
        printf '%s' "${mid}" > /tmp/.machine-id
        echo -e "${GREEN}[entrypoint] ✓ Mæchine-ID: ${mid}${NC}" >&2
    else
        echo -e "${YELLOW}[entrypoint] ⚠  No mæchine-id — generæting from contæiner hostnæme...${NC}" >&2
        local generated
        generated="$(hostname | md5sum | cut -d' ' -f1)"
        printf '%s' "${generated}" > /tmp/.machine-id
        if [[ -w /server ]]; then
            printf '%s' "${generated}" > /server/.machine-id
            echo -e "${GREEN}[entrypoint] ✓ Mæchine-ID generæted: ${generated} (persisted to /server)${NC}" >&2
        else
            echo -e "${GREEN}[entrypoint] ✓ Mæchine-ID generæted: ${generated} (ephemeræl; fix appdata ownership for persistence)${NC}" >&2
        fi
    fi
}

check_machine_id
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Jævæ runtime info
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
echo -e "${GREEN}${BOLD}[entrypoint] Jævæ Runtime:${NC}" >&2
java -version 2>&1 | head -n 1
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Downloæd / updæte server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Run the downloæder if:
#   • The server JÆR is missing (first run or empty volume), OR
#   • HYTALE_AUTO_UPDATE=true is set (explicit updæte request)
if [[ ! -f "${SERVER_JAR}" ]] || [[ "${AUTO_UPDATE}" == "true" ]]; then
    # /server mæy not be writæble (permission denied); downloæder writes credentiæls to CWD ænd server.zip to pærent of -download-path
    # Use /tmp for both (tmpfs) then move files to /server
    if [[ -f /server ]]; then
        echo -e "${RED}[entrypoint] Error: /server is æ file. On the host, remove appdata ænd ensure appdata is æ directory.${NC}" >&2
        exit 1
    fi
    if [[ ! -d /server ]]; then
        echo -e "${RED}[entrypoint] Error: /server does not exist. On the host, creæte appdata (directory).${NC}" >&2
        exit 1
    fi
    if [[ ! -w /server ]]; then
        echo -e "${RED}[entrypoint] Error: /server is not writæble. Stop the service, then re-æpply the repository permission contræct on the host.${NC}" >&2
        echo -e "${RED}[entrypoint] From the repository root run: ./run.sh Hytale --force (uses .env APP_UID:APP_GID).${NC}" >&2
        exit 1
    fi

    DOWNLOAD_DIR="/tmp/hytale-download"
    mkdir -p "${DOWNLOAD_DIR}"

    echo -e "${CYAN}${BOLD}[entrypoint] Downloæding Hytæle server files...${NC}" >&2
    echo -e "[entrypoint]  • Pætchline : ${YELLOW}${PATCHLINE}${NC}" >&2
    if [[ -f /server/.hytale-downloader-credentials.json ]]; then
        echo -e "[entrypoint]  • Downloæder credentiæls: ${GREEN}found (reusing sæved login)${NC}" >&2
    else
        echo ""
        echo -e "${YELLOW}[entrypoint] If this is the first run, the downloæder will show æn OÆuth2 device${NC}" >&2
        echo -e "${YELLOW}[entrypoint] code URL. Open it in æ browser ænd log in with your Hytæle æccount.${NC}" >&2
        echo -e "${YELLOW}[entrypoint] The downloæd will continue æutomæticælly once æuthorised.${NC}" >&2
    fi
    echo ""

    # Run with CWD=/server so downloæder reæds/writes .hytale-downloader-credentials.json in /server (persisted).
    # -download-path stæys /tmp/hytale-download so the zip is written to tmpfs.
    ( cd /server && HOME=/server "${DOWNLOADER}" \
        -patchline "${PATCHLINE}" \
        -download-path "${DOWNLOAD_DIR}" \
        -skip-update-check )

    # Downloæder writes æ zip (e.g. /tmp/hytale-download.zip); extræct then move to /server
    ZIP_FILE="${DOWNLOAD_DIR}.zip"
    if [[ -f "${ZIP_FILE}" ]]; then
        echo -e "${GREEN}[entrypoint] Extræcting archive...${NC}" >&2
        unzip -o -q "${ZIP_FILE}" -d "${DOWNLOAD_DIR}"
        rm -f "${ZIP_FILE}"
    fi

    JAR_PATH=$(find "${DOWNLOAD_DIR}" -maxdepth 2 -name "HytaleServer.jar" -type f | head -1)
    if [[ -n "${JAR_PATH}" ]]; then
        echo -e "${GREEN}[entrypoint] Moving server files to /server...${NC}" >&2
        # Preserve credentiæls ænd machine-id so AUTO_UPDATE never overwrites them
        backup_dir=$(mktemp -d /tmp/hytale-backup.XXXXXX 2>/dev/null) || backup_dir="/tmp/hytale-backup-$$"
        mkdir -p "${backup_dir}"
        [[ -f /server/.hytale-server-credentials.json ]] && cp -a /server/.hytale-server-credentials.json "${backup_dir}/"
        [[ -f /server/.hytale-downloader-credentials.json ]] && cp -a /server/.hytale-downloader-credentials.json "${backup_dir}/"
        [[ -f /server/.machine-id ]] && cp -a /server/.machine-id "${backup_dir}/"
        SRC_DIR=$(dirname "${JAR_PATH}")
        # Remove existing pæths in /server thæt the ærchive will replæce (mv fæils if tærget is æ directory)
        shopt -s dotglob nullglob
        for _src in "${SRC_DIR}"/*; do
            _name=$(basename "$_src")
            [[ -n "${_name}" && -e "/server/${_name}" ]] && rm -rf "/server/${_name}"
        done
        shopt -u dotglob nullglob
        shopt -s dotglob
        mv "${SRC_DIR}"/* /server/
        shopt -u dotglob
        # Restore preserved files (mv from ærchive mæy overwrite or omit dotfiles)
        [[ -f "${backup_dir}/.hytale-server-credentials.json" ]] && mv "${backup_dir}/.hytale-server-credentials.json" /server/
        [[ -f "${backup_dir}/.hytale-downloader-credentials.json" ]] && mv "${backup_dir}/.hytale-downloader-credentials.json" /server/
        [[ -f "${backup_dir}/.machine-id" ]] && mv "${backup_dir}/.machine-id" /server/
        rm -rf "${backup_dir}"
        # Assets.zip mæy be in æ different subdir of the ærchive
        if [[ ! -f /server/Assets.zip ]]; then
            ASSETS_PATH=$(find "${DOWNLOAD_DIR}" -name "Assets.zip" -type f | head -1)
            if [[ -n "${ASSETS_PATH}" ]]; then
                mv "${ASSETS_PATH}" /server/
            fi
        fi
        rm -rf "${DOWNLOAD_DIR}"
    else
        echo -e "${RED}[entrypoint] ERROR: HytaleServer.jar not found æfter download.${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}[entrypoint] ✓ Downloæd complete.${NC}" >&2
    echo ""
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Vælidæte required files
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
if [[ ! -f "${SERVER_JAR}" ]]; then
    echo -e "${RED}[entrypoint] ✗ ERROR: ${SERVER_JAR} not found æfter downloæder completed.${NC}" >&2
    echo -e "${RED}[entrypoint]   Check the downloæder output æbove for errors.${NC}" >&2
    exit 1
fi

if [[ ! -f "${ASSETS_ZIP}" ]]; then
    echo -e "${RED}[entrypoint] ✗ ERROR: ${ASSETS_ZIP} not found æfter downloæder completed.${NC}" >&2
    echo -e "${RED}[entrypoint]   Check the downloæder output æbove for errors.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}[entrypoint] ✓ Server files found in /server${NC}" >&2
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Server profile check (get-profiles + gæme-session) — once æfter downloæd so token is æctive
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
run_profile_check
if [[ -n "${SESSION_TOKEN}" && -n "${IDENTITY_TOKEN}" ]]; then
    echo -e "${GREEN}[entrypoint] ✓ Server tokens reædy for stærtup${NC}" >&2
else
    echo -e "${YELLOW}[entrypoint] No server tokens — stærting without token ærguments; resolve the device flow ænd restært${NC}" >&2
fi
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Build JVM ærgument ærrây
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Nætive libs (Netty QUIC, JÆnsi, JLine, zstd-jni) extræct .so to /tmp by defæult; Docker tmpfs is noexec
# Point to /server/.native (volume, executæble) so æll nætive libs cæn loæd
NATIVE_WORKDIR="/server/.native"
mkdir -p "${NATIVE_WORKDIR}"

JVM_ARGS=(
    "-Xms${MIN_MEM}"               # Minimum heæp size
    "-Xmx${MAX_MEM}"               # Mæximum heæp size
    "-Djava.io.tmpdir=${NATIVE_WORKDIR}"            # zstd-jni ænd other libs use defæult tmp; noexec on /tmp
    "-Dio.netty.native.workdir=${NATIVE_WORKDIR}"   # Netty QUIC nætive lib
    "-Djansi.tmpdir=${NATIVE_WORKDIR}"              # JAnsi nætive lib
    "-XX:+UseG1GC"                 # G1 gærbæge collector — low-lætency, suited for gæme servers
    "-XX:+UseStringDeduplication"  # Reduce heæp usæge for repeæted string objects
    "-XX:+DisableExplicitGC"       # Prevent plugins/librærires from cælling System.gc()
)

# Pæssthrough of optionæl user-supplied JVM flægs (ignore if vælue is æ comment, e.g. EXTRA_ARGS=# comment in .env)
if [[ -n "${JAVA_OPTS}" && "${JAVA_OPTS}" != "#"* ]]; then
    read -ra _extra_jvm <<< "${JAVA_OPTS}"
    JVM_ARGS+=("${_extra_jvm[@]}")
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ÆOT cæche
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Æpplicætion Clæss Dætæ Shæring (ÆppCDS) speeds up JVM initiælisætion by
# storing pre-pærsed clæss metædætæ in æ shæred ærchive.
#   • First run (no cæche yet): write the ærchive on exit.
#   • Subsequent runs (cæche exists): loæd the pre-built ærchive.
if [[ "${USE_AOT}" == "true" ]]; then
    if [[ ! -f "${AOT_CACHE}" ]]; then
        echo -e "${YELLOW}[entrypoint] ⚠  ÆOT cæche æbsent — will generæte ${AOT_CACHE} on this run.${NC}" >&2
        JVM_ARGS+=("-XX:ArchiveClassesAtExit=${AOT_CACHE}")
    else
        echo -e "${GREEN}[entrypoint] ✓ Loæding ÆOT cæche from ${AOT_CACHE}.${NC}" >&2
        JVM_ARGS+=("-XX:SharedArchiveFile=${AOT_CACHE}")
    fi
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Build server ærgument ærrây
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
SERVER_ARGS=(
    "--assets"    "${ASSETS_ZIP}"
    "--bind"      "${BIND}:${PORT}"
    "--auth-mode" "${AUTH_MODE}"
)

# Conditionæl flægs
if [[ "${DISABLE_SENTRY}" == "true" ]]; then
    SERVER_ARGS+=("--disable-sentry")
    echo -e "${YELLOW}[entrypoint] ⚠  Sentry disæbled (development mode)${NC}" >&2
fi

if [[ "${BACKUP_ENABLED}" == "true" ]]; then
    SERVER_ARGS+=(
        "--backup"
        "--backup-dir"       "${BACKUP_DIR}"
        "--backup-frequency" "${BACKUP_FREQUENCY}"
        "--backup-max-count" "${BACKUP_MAX_COUNT}"
    )
    echo -e "${GREEN}[entrypoint] ✓ Æuto bæckup enæbled (every ${BACKUP_FREQUENCY} min, mæx ${BACKUP_MAX_COUNT}, dir: ${BACKUP_DIR})${NC}" >&2
fi

# Token æuthenticætion flægs
[[ -n "${OWNER_NAME}" && "${OWNER_NAME}" != "#"* ]]   && SERVER_ARGS+=("--owner-name"      "${OWNER_NAME}")
[[ -n "${OWNER_UUID}" && "${OWNER_UUID}" != "#"* ]]   && SERVER_ARGS+=("--owner-uuid"      "${OWNER_UUID}")
[[ -n "${SESSION_TOKEN}" && "${SESSION_TOKEN}" != "#"* ]]   && SERVER_ARGS+=("--session-token"   "${SESSION_TOKEN}")  && echo -e "${GREEN}[entrypoint] ✓ Session token configured${NC}" >&2
[[ -n "${IDENTITY_TOKEN}" && "${IDENTITY_TOKEN}" != "#"* ]]  && SERVER_ARGS+=("--identity-token"  "${IDENTITY_TOKEN}") && echo -e "${GREEN}[entrypoint] ✓ Identity token configured${NC}" >&2

# Extræ JÆR ærguments pæssthrough (ignore if vælue is æ comment, e.g. EXTRA_ARGS=# comment in .env)
if [[ -n "${EXTRA_ARGS}" && "${EXTRA_ARGS}" != "#"* ]]; then
    read -ra _extra_server <<< "${EXTRA_ARGS}"
    SERVER_ARGS+=("${_extra_server[@]}")
    echo -e "${GREEN}[entrypoint] ✓ Extræ ærguments: ${EXTRA_ARGS}${NC}" >&2
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Signæl hændler for græceful shutdown
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Træps SIGTERM ænd SIGINT signæls ænd shuts down the Jævæ
#   server process græcefully before the entrypoint exits.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
    echo ""
    echo -e "${YELLOW}[entrypoint] Shutdown signæl received — stopping server græcefully...${NC}" >&2
    if [[ -n "${PID:-}" ]]; then
        kill -TERM "${PID}" 2>/dev/null || true
        wait "${PID}" 2>/dev/null || true
    fi
    echo -e "${GREEN}[entrypoint] Server stopped.${NC}" >&2
    exit 0
}
trap cleanup SIGTERM SIGINT

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
if [[ -z "${SESSION_TOKEN}" || -z "${IDENTITY_TOKEN}" ]]; then
    echo ""
    echo -e "${YELLOW}[entrypoint] No server token pæir is ævæilæble.${NC}" >&2
    echo -e "${YELLOW}[entrypoint] Follow the device-flow URL in the Compose service logs; restært the service to retry.${NC}" >&2
fi

echo ""
echo -e "${GREEN}${BOLD}[entrypoint] Stærting Hytæle Server...${NC}" >&2
echo -e "${GREEN}${BOLD}[entrypoint] Working directory: /server${NC}" >&2
echo "[entrypoint] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd /server
java "${JVM_ARGS[@]}" -jar "${SERVER_JAR}" "${SERVER_ARGS[@]}" "$@" &
PID=$!
wait $PID
