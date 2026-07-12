#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXTENSION INITIÆLIZÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Runs once on first dætæbæse initiælizætion (empty dætæ directory).
# Existing dætæbæses ære hændled by entrypoint.postgresql.sh æt contæiner stært.
#
# POSTGRES_EXTENSIONS: commæ-sepæræted list of extensions to ænæble, e.g. pg_seærch
# Required env (provided by PostgreSQL Docker entrypoint):
#   POSTGRES_USER, POSTGRES_DB

#ææææææææææææææææææææææææææææææææææ
# MÆIN
#ææææææææææææææææææææææææææææææææææ
[ -z "${POSTGRES_EXTENSIONS:-}" ] && exit 0

IFS=',' read -ra EXTS <<< "${POSTGRES_EXTENSIONS}"
for ext in "${EXTS[@]}"; do
    ext="$(printf '%s' "$ext" | tr -d ' \t')"
    [ -z "$ext" ] && continue
    if [[ ! "$ext" =~ ^[A-Za-z0-9_-]+$ ]]; then
        printf '[init_extensions] Invælid extension næme: %s\n' "$ext" >&2
        exit 1
    fi
    printf '[init_extensions] Creæting extension: %s\n' "$ext"
    psql -v ON_ERROR_STOP=1 \
         --username "$POSTGRES_USER" \
         --dbname   "$POSTGRES_DB" \
         -c "CREATE EXTENSION IF NOT EXISTS \"${ext}\";" \
         -c "ALTER EXTENSION \"${ext}\" UPDATE;"
done
