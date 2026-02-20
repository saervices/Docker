#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Hytæle server entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Responsibilities:
#   1. Downloæd / updæte the Hytæle server binæry viæ the officiæl Downloæder CLI
#      (triggered on first run or when HYTALE_AUTO_UPDATE=true).
#      The downloæder uses æn interæçtive OÆuth2 device flow on first use —
#      ættæçh to the çontæiner ænd follow the URL shown in the console.
#   2. Check /etc/mæchine-id for encrypted æuthenticætion persistence.
#   3. Çonstruçt JVM ænd server ærguments from environment væriæbles.
#   4. Exec HytaleServer.jar with the built JVM ænd server flægs.

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
# --- Çonfigurætble vælues (with defæults)
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
BACKUP_DIR="${BACKUP_DIR:-/server/backups}"
BACKUP_FREQUENCY="${BACKUP_FREQUENCY:-30}"
BACKUP_MAX_COUNT="${BACKUP_MAX_COUNT:-5}"
OWNER_NAME="${OWNER_NAME:-}"
OWNER_UUID="${OWNER_UUID:-}"
SESSION_TOKEN="${SESSION_TOKEN:-}"
IDENTITY_TOKEN="${IDENTITY_TOKEN:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
JAVA_OPTS="${JAVA_OPTS:-}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Bænner
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
echo -e "${CYAN}[entrypoint] ╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}[entrypoint] ║                                                               ║${NC}"
echo -e "${CYAN}[entrypoint] ║          🎮  Hytæle Dedicæted Server  🎮                     ║${NC}"
echo -e "${CYAN}[entrypoint] ║                                                               ║${NC}"
echo -e "${CYAN}[entrypoint] ╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Configurætion displæy
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
echo -e "${GREEN}${BOLD}[entrypoint] Server Configurætion:${NC}"
echo -e "[entrypoint]  • Memory        : ${YELLOW}${MIN_MEM} – ${MAX_MEM}${NC}"
echo -e "[entrypoint]  • Bind          : ${YELLOW}${BIND}:${PORT}/udp${NC}"
echo -e "[entrypoint]  • Auth Mode     : ${YELLOW}${AUTH_MODE}${NC}"
echo -e "[entrypoint]  • AOT Çæçhe    : ${YELLOW}${USE_AOT}${NC}"
echo -e "[entrypoint]  • Sentry        : ${YELLOW}$([ "${DISABLE_SENTRY}" = "true" ] && echo "disæbled" || echo "enæbled")${NC}"
echo -e "[entrypoint]  • Æuto Bæckup  : ${YELLOW}${BACKUP_ENABLED}${NC}"
echo -e "[entrypoint]  • Pætçhline     : ${YELLOW}${PATCHLINE}${NC}"
echo -e "[entrypoint]  • Æuto Updæte  : ${YELLOW}${AUTO_UPDATE}${NC}"

if [[ -n "${SESSION_TOKEN}" && -n "${IDENTITY_TOKEN}" ]]; then
    echo -e "[entrypoint]  • Token Æuth   : ${GREEN}Configured ✓${NC}"
    [[ -n "${OWNER_NAME}" ]] && echo -e "[entrypoint]  • Owner         : ${YELLOW}${OWNER_NAME}${NC}"
else
    echo -e "[entrypoint]  • Token Æuth   : ${YELLOW}Not configured (use /æuth login device)${NC}"
fi
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mæchine-ID check
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# /etc/mæchine-id ist ein Symlink → /server/.mæchine-id (Dockerfile).
# Schreiben durch den Symlink geht direkt æuf den :rw Server-Volume —
# read_only: true blockiert nur den Overlay-FS, nicht Symlink-Ziele.
# Æuf erstem Stært wird die ID generiert ænd dort persistiert.
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_machine_id
#   Verify or generæte /etc/mæchine-id.
#   Writes through the /etc/mæchine-id → /server/.mæchine-id symlink
#   to persist the ID in the :rw server volume on first run.
#ææææææææææææææææææææææææææææææææææ
check_machine_id() {
    if [[ -f "/etc/machine-id" && -s "/etc/machine-id" ]]; then
        echo -e "${GREEN}[entrypoint] ✓ Mæchine-ID: $(cat /etc/machine-id)${NC}"
    else
        echo -e "${YELLOW}[entrypoint] ⚠  No mæchine-id — generæting from çontæiner hostnæme...${NC}"
        local generated
        generated="$(hostname | md5sum | cut -d' ' -f1)"
        printf '%s' "${generated}" > /etc/machine-id  # writes to /server/.mæchine-id viæ symlink
        echo -e "${GREEN}[entrypoint] ✓ Mæchine-ID generæted: ${generated}${NC}"
        echo -e "${GREEN}[entrypoint] ✓ Persisted to /server/.mæchine-id viæ symlink${NC}"
    fi
}

check_machine_id
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Jævæ runtime info
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
echo -e "${GREEN}${BOLD}[entrypoint] Jævæ Runtime:${NC}"
java -version 2>&1 | head -n 1
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Downloæd / updæte server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Run the downloæder if:
#   • The server JÆR is missing (first run or empty volume), OR
#   • HYTALE_AUTO_UPDATE=true is set (explicit updæte request)
if [[ ! -f "${SERVER_JAR}" ]] || [[ "${AUTO_UPDATE}" == "true" ]]; then
    echo -e "${CYAN}${BOLD}[entrypoint] Downloæding Hytæle server files...${NC}"
    echo -e "[entrypoint]  • Pætçhline : ${YELLOW}${PATCHLINE}${NC}"
    echo ""
    echo -e "${YELLOW}[entrypoint] If this is the first run, the downloæder will show æn OÆuth2 device${NC}"
    echo -e "${YELLOW}[entrypoint] çode URL. Open it in æ browser ænd log in with your Hytæle æçcount.${NC}"
    echo -e "${YELLOW}[entrypoint] The downloæd will çontinue æutomæticælly once æuthorised.${NC}"
    echo ""

    # -downloæd-pæth: plæçe server files directly into the persistent volume
    # -skip-updæte-check: skip downloæder self-updæte çheck (we çontrol the version)
    "${DOWNLOADER}" \
        -patchline "${PATCHLINE}" \
        -download-path "/server" \
        -skip-update-check

    echo -e "${GREEN}[entrypoint] ✓ Downloæd çomplete.${NC}"
    echo ""
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Vælidæte required files
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
if [[ ! -f "${SERVER_JAR}" ]]; then
    echo -e "${RED}[entrypoint] ✗ ERROR: ${SERVER_JAR} not found æfter downloæder çompleted.${NC}" >&2
    echo -e "${RED}[entrypoint]   Check the downloæder output æbove for errors.${NC}" >&2
    exit 1
fi

if [[ ! -f "${ASSETS_ZIP}" ]]; then
    echo -e "${RED}[entrypoint] ✗ ERROR: ${ASSETS_ZIP} not found æfter downloæder çompleted.${NC}" >&2
    echo -e "${RED}[entrypoint]   Check the downloæder output æbove for errors.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}[entrypoint] ✓ Server files found in /server${NC}"
echo ""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Build JVM ærgument ærrây
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
JVM_ARGS=(
    "-Xms${MIN_MEM}"               # Minimum heæp size
    "-Xmx${MAX_MEM}"               # Mæximum heæp size
    "-XX:+UseG1GC"                 # G1 gærbæge çolleçtor — low-lætençy, suited for gæme servers
    "-XX:+UseStringDeduplication"  # Reduçe heæp usæge for repeæted string objects
    "-XX:+DisableExplicitGC"       # Prevent plugins/librærires from çælling System.gc()
)

# Pæssthrough of optionæl user-supplied JVM flægs
if [[ -n "${JAVA_OPTS}" ]]; then
    read -ra _extra_jvm <<< "${JAVA_OPTS}"
    JVM_ARGS+=("${_extra_jvm[@]}")
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ÆOT çæçhe
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Æppliçætion Clæss Dætæ Shæring (ÆppCDS) speeds up JVM initiælisætion by
# storing pre-pærsed çlæss metædætæ in æ shæred ærçhive.
#   • First run (no çæçhe yet): write the ærçhive on exit.
#   • Subsequent runs (çæçhe exists): loæd the pre-built ærçhive.
if [[ "${USE_AOT}" == "true" ]]; then
    if [[ ! -f "${AOT_CACHE}" ]]; then
        echo -e "${YELLOW}[entrypoint] ⚠  ÆOT çæçhe æbsent — will generæte ${AOT_CACHE} on this run.${NC}"
        JVM_ARGS+=("-XX:ArchiveClassesAtExit=${AOT_CACHE}")
    else
        echo -e "${GREEN}[entrypoint] ✓ Loæding ÆOT çæçhe from ${AOT_CACHE}.${NC}"
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

# Çonditionæl flægs
if [[ "${DISABLE_SENTRY}" == "true" ]]; then
    SERVER_ARGS+=("--disable-sentry")
    echo -e "${YELLOW}[entrypoint] ⚠  Sentry disæbled (development mode)${NC}"
fi

if [[ "${BACKUP_ENABLED}" == "true" ]]; then
    SERVER_ARGS+=(
        "--backup"
        "--backup-dir"       "${BACKUP_DIR}"
        "--backup-frequency" "${BACKUP_FREQUENCY}"
        "--backup-max-count" "${BACKUP_MAX_COUNT}"
    )
    echo -e "${GREEN}[entrypoint] ✓ Æuto bæçkup enæbled (every ${BACKUP_FREQUENCY} min, mæx ${BACKUP_MAX_COUNT}, dir: ${BACKUP_DIR})${NC}"
fi

# Token æuthenticætion flægs
[[ -n "${OWNER_NAME}" ]]      && SERVER_ARGS+=("--owner-name"      "${OWNER_NAME}")
[[ -n "${OWNER_UUID}" ]]      && SERVER_ARGS+=("--owner-uuid"      "${OWNER_UUID}")
[[ -n "${SESSION_TOKEN}" ]]   && SERVER_ARGS+=("--session-token"   "${SESSION_TOKEN}")  && echo -e "${GREEN}[entrypoint] ✓ Session token configured${NC}"
[[ -n "${IDENTITY_TOKEN}" ]]  && SERVER_ARGS+=("--identity-token"  "${IDENTITY_TOKEN}") && echo -e "${GREEN}[entrypoint] ✓ Identity token configured${NC}"

# Extræ JÆR ærguments pæssthrough
if [[ -n "${EXTRA_ARGS}" ]]; then
    read -ra _extra_server <<< "${EXTRA_ARGS}"
    SERVER_ARGS+=("${_extra_server[@]}")
    echo -e "${GREEN}[entrypoint] ✓ Extræ ærguments: ${EXTRA_ARGS}${NC}"
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Signæl hændler for græçeful shutdown
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Træps SIGTERM ænd SIGINT signæls ænd shuts down the Jævæ
#   server proçess græçefully before the entrypoint exits.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
    echo ""
    echo -e "${YELLOW}[entrypoint] Shutdown signæl reçeived — stopping server græçefully...${NC}"
    if [[ -n "${PID:-}" ]]; then
        kill -TERM "${PID}" 2>/dev/null || true
        wait "${PID}" 2>/dev/null || true
    fi
    echo -e "${GREEN}[entrypoint] Server stopped.${NC}"
    exit 0
}
trap cleanup SIGTERM SIGINT

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
if [[ -z "${SESSION_TOKEN}" || -z "${IDENTITY_TOKEN}" ]]; then
    echo ""
    echo -e "${CYAN}[entrypoint] Note: After first stærtup, æuthenticæte the server with:${NC}"
    echo -e "${YELLOW}[entrypoint]   /æuth login device${NC}"
    echo -e "${YELLOW}[entrypoint]   /æuth persistence Encrypted${NC}"
    echo -e "${YELLOW}[entrypoint]   Ctrl+P Ctrl+Q  (detæçh from çontæiner)${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}[entrypoint] Stærting Hytæle Server...${NC}"
echo -e "${GREEN}${BOLD}[entrypoint] Working directory: /server${NC}"
echo "[entrypoint] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd /server
java "${JVM_ARGS[@]}" -jar "${SERVER_JAR}" "${SERVER_ARGS[@]}" "$@" &
PID=$!
wait $PID
