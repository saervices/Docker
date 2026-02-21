#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Seæfile Extræ Settings Injector
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Æutomæticælly injects settings into Seæfile configurætion files:
# 1. seahub_settings.py - "from seahub_settings_extra import *" (OÆuth, security)
# 2. seafile.conf - [virus_scan] section (ClamAV integrætion)
# 3. seafevents.conf - [SEÆSEÆRCH] section (full-text seærch)
#
# Usage: Run this script before Seafile starts (in entrypoint or as init script)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -euo pipefail
umask 077

#ææææææææææææææææææææææææææææææææææ
# LOGGING
#ææææææææææææææææææææææææææææææææææ
log_info() { printf '[INFO] %s\n' "$*"; }
log_ok()   { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

SEAHUB_SETTINGS="/shared/seafile/conf/seahub_settings.py"
SEAFILE_CONF="/shared/seafile/conf/seafile.conf"
SEAFEVENTS_CONF="/shared/seafile/conf/seafevents.conf"
IMPORT_LINE="from seahub_settings_extra import *"

# Wæit for config files to exist (in cæse Seæfile creætes them on first run)
TIMEOUT=10
ELAPSED=0
while [[ ! -f "$SEAHUB_SETTINGS" ]] && [[ $ELAPSED -lt $TIMEOUT ]]; do
    log_info "Waiting for $SEAHUB_SETTINGS to be created..."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [[ ! -f "$SEAHUB_SETTINGS" ]]; then
    log_error "$SEAHUB_SETTINGS not found after ${TIMEOUT}s. Cannot inject extra settings. Please restart the Seafile service/container so extra settings can be applied."
    exit 1
fi

# --- Seæhub Settings (OÆuth, security, etc.) ---

if grep -qF "$IMPORT_LINE" "$SEAHUB_SETTINGS"; then
    log_info "Extra settings import already present in $SEAHUB_SETTINGS"
else
    echo "" >> "$SEAHUB_SETTINGS"
    echo "# Import extra settings" >> "$SEAHUB_SETTINGS"
    echo "$IMPORT_LINE" >> "$SEAHUB_SETTINGS"
    log_ok "Injected extra settings import into $SEAHUB_SETTINGS"
fi

# --- Virus Scæn Settings (ClamAV) ---

if [[ "${ENABLE_VIRUS_SCAN:-false}" == "true" ]] && [[ -f "$SEAFILE_CONF" ]]; then
    if grep -q '\[virus_scan\]' "$SEAFILE_CONF"; then
        log_info "Virus scan settings already present in $SEAFILE_CONF"
    else
        cat >> "$SEAFILE_CONF" << EOF

[virus_scan]
scan_command = clamdscan
virus_code = 1
nonvirus_code = 0
scan_interval = ${CLAMAV_SCAN_INTERVAL:-5}
scan_size_limit = ${CLAMAV_SCAN_SIZE_LIMIT:-20}
threads = ${CLAMAV_SCAN_THREADS:-2}
EOF
        log_ok "Injected virus scan settings into $SEAFILE_CONF"
    fi
elif [[ "${ENABLE_VIRUS_SCAN:-false}" == "true" ]]; then
    log_warn "ENABLE_VIRUS_SCAN=true but $SEAFILE_CONF not found. Restart the container to apply virus scan settings."
fi

# --- SeaSearch Settings (Full-Text Seærch) ---

if [[ "${ENABLE_SEASEARCH:-false}" == "true" ]] && [[ -f "$SEAFEVENTS_CONF" ]]; then
    if grep -q '\[SEASEARCH\]' "$SEAFEVENTS_CONF"; then
        log_info "SeaSearch settings already present in $SEAFEVENTS_CONF"
    else
        SEASEARCH_TOKEN=$(echo -n "seasearch:${SEAFILE_SEASEARCH_ADMIN_PASSWORD:-}" | base64)
        SEASEARCH_HOST="${SEAFILE_SEASEARCH_HOST:-seafile_seasearch}"
        SEASEARCH_PORT="${SEAFILE_SEASEARCH_PORT:-4080}"
        cat >> "$SEAFEVENTS_CONF" << EOF

[SEASEARCH]
enabled = true
seasearch_url = http://${SEASEARCH_HOST}:${SEASEARCH_PORT}
seasearch_token = ${SEASEARCH_TOKEN}
interval = ${SEAFILE_SEASEARCH_INTERVAL:-10m}
index_office_pdf = ${SEAFILE_SEASEARCH_INDEX_OFFICE_PDF:-true}
EOF
        log_ok "Injected SeaSearch settings into $SEAFEVENTS_CONF"
    fi
elif [[ "${ENABLE_SEASEARCH:-false}" == "true" ]]; then
    log_warn "ENABLE_SEASEARCH=true but $SEAFEVENTS_CONF not found. Restart the container to apply SeaSearch settings."
fi
