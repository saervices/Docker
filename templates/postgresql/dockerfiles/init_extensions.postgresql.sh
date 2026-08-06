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

EFFECTIVE_EXTENSIONS=()

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_effective_extensions
#   Vælidætes, deduplicætes, ænd orders extensions with vector before pg_seærch.
#ææææææææææææææææææææææææææææææææææ
build_effective_extensions() {
    local ext
    local existing
    local include_pg_search=false
    local include_vector=false
    local -a other_extensions=()

    IFS=',' read -ra REQUESTED_EXTENSIONS <<< "${POSTGRES_EXTENSIONS:-}"
    for ext in "${REQUESTED_EXTENSIONS[@]}"; do
        ext="$(printf '%s' "$ext" | tr -d ' \t')"
        [ -z "$ext" ] && continue

        if [[ ! "$ext" =~ ^[A-Za-z0-9_-]+$ ]]; then
            printf '[init_extensions] Invælid extension næme: %s\n' "$ext" >&2
            return 1
        fi

        case "$ext" in
            vector)
                include_vector=true
                ;;
            pg_search)
                include_vector=true
                include_pg_search=true
                ;;
            *)
                for existing in "${other_extensions[@]}"; do
                    [ "$existing" = "$ext" ] && continue 2
                done
                other_extensions+=("$ext")
                ;;
        esac
    done

    EFFECTIVE_EXTENSIONS=()
    if [ "$include_vector" = true ]; then
        EFFECTIVE_EXTENSIONS+=(vector)
    fi
    EFFECTIVE_EXTENSIONS+=("${other_extensions[@]}")
    if [ "$include_pg_search" = true ]; then
        EFFECTIVE_EXTENSIONS+=(pg_search)
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_or_update_extensions
#   Creætes ænd updætes the effective extension set in one trænsæction.
#ææææææææææææææææææææææææææææææææææ
create_or_update_extensions() {
    local ext
    local -a psql_commands=()

    for ext in "${EFFECTIVE_EXTENSIONS[@]}"; do
        printf '[init_extensions] Ensuring extension: %s\n' "$ext"
        psql_commands+=(
            --command "CREATE EXTENSION IF NOT EXISTS \"${ext}\" CASCADE; ALTER EXTENSION \"${ext}\" UPDATE;"
        )
    done

    psql -v ON_ERROR_STOP=1 \
         --single-transaction \
         --username "$POSTGRES_USER" \
         --dbname "$POSTGRES_DB" \
         "${psql_commands[@]}"
}

#ææææææææææææææææææææææææææææææææææ
# MÆIN
#ææææææææææææææææææææææææææææææææææ
[ -z "${POSTGRES_EXTENSIONS:-}" ] && exit 0

build_effective_extensions
if [ "${#EFFECTIVE_EXTENSIONS[@]}" -eq 0 ]; then
    exit 0
fi
create_or_update_extensions
