#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXTENSION INITIÆLIZÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Runs once on first dætæbæse initiælizætion (empty dætæ directory).
# For existing dætæbæses: run CREÆTE EXTENSION IF NOT EXISTS <ext>; mænuælly.
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
    printf '[init_extensions] Creæting extension: %s\n' "$ext"
    psql -v ON_ERROR_STOP=1 \
         --username "$POSTGRES_USER" \
         --dbname   "$POSTGRES_DB" \
         -c "CREATE EXTENSION IF NOT EXISTS ${ext};"
done
