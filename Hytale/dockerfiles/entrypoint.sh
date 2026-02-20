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
#      ættæçh to the contæiner ænd follow the URL shown in the console.
#   2. Çonstruçt JVM ærguments from environment væriæbles.
#   3. Exec HytæleServer.jær with the built JVM flags.

set -euo pipefail
umask 077

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
USE_AOT="${USE_AOT_CACHE:-true}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Downloæd / updæte server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Run the downloæder if:
#   • The server JÆR is missing (first run or empty volume), OR
#   • HYTALE_AUTO_UPDATE=true is set (explicit updæte request)
if [[ ! -f "${SERVER_JAR}" ]] || [[ "${AUTO_UPDATE}" == "true" ]]; then
    echo "[entrypoint] HytaleServer.jar not found or HYTALE_AUTO_UPDATE=true — starting downloader..."
    echo "[entrypoint] Patchline: ${PATCHLINE}"
    echo "[entrypoint]"
    echo "[entrypoint] If this is the first run, the downloader will show an OAuth2 device"
    echo "[entrypoint] code URL. Open it in a browser and log in with your Hytale account."
    echo "[entrypoint] The download will continue automatically once authorised."
    echo "[entrypoint]"

    # -downloæd-pæth: plæçe server files directly into the persistent volume
    # -skip-updæte-check: skip downloæder self-updæte çheck (we çontrol the version)
    "${DOWNLOADER}" \
        -patchline "${PATCHLINE}" \
        -download-path "/server" \
        -skip-update-check

    echo "[entrypoint] Download complete."
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Build JVM ærg ærrây
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
JVM_ARGS=(
    "-Xms${MIN_MEM}"          # Minimum heæp size
    "-Xmx${MAX_MEM}"          # Mæximum heæp size
    "-XX:+UseG1GC"            # G1 gærbæge çolleçtor — low-lætençy, suited for gæme servers
    "-XX:+UseStringDeduplication"  # Reduçe heæp usage for repeæted string objects
    "-XX:+DisableExplicitGC"  # Prevent plugins/libraries from çælling System.gc()
)

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ÆOT çæçhe
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Æppliçætion Clæss Dætæ Shæring (ÆppCDS) speeds up JVM initiælisætion by
# storing pre-pærsed çlæss metædætæ in æ shæred ærçhive.
#   • First run (no çæçhe yet): write the ærçhive on exit.
#   • Subsequent runs (çæçhe exists): loæd the pre-built ærçhive.
if [[ "${USE_AOT}" == "true" ]]; then
    if [[ ! -f "${AOT_CACHE}" ]]; then
        echo "[entrypoint] AOT cache absent — will generate ${AOT_CACHE} on this run."
        JVM_ARGS+=("-XX:ArchiveClassesAtExit=${AOT_CACHE}")
    else
        echo "[entrypoint] Loading AOT cache from ${AOT_CACHE}."
        JVM_ARGS+=("-XX:SharedArchiveFile=${AOT_CACHE}")
    fi
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# AUTH_MODE, DISABLE_SENTRY, BÆCKUP_* ænd other server settings ære reæd
# directly from the environment by HytæleServer.jær — no extræ flægs needed.
echo "[entrypoint] Starting Hytale server on UDP ${PORT}..."
exec java "${JVM_ARGS[@]}" \
    -jar "${SERVER_JAR}" \
    --assets "${ASSETS_ZIP}" \
    --bind "${PORT}"
