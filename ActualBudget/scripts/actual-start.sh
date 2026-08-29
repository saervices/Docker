#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Æctuæl Budget entrypoint wræpper

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SECRET INJECTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# The imæge's POSIX shell does not guæræntee pipefæil support.
set -eu
umask 077

readonly ACTUALBUDGET_OPENID_CLIENT_ID_FILE="${ACTUALBUDGET_OPENID_CLIENT_ID_FILE:-/run/secrets/ACTUALBUDGET_OPENID_CLIENT_ID}"
readonly ACTUALBUDGET_OPENID_CLIENT_SECRET_FILE="${ACTUALBUDGET_OPENID_CLIENT_SECRET_FILE:-/run/secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET}"
readonly ACTUALBUDGET_SECRET_MAX_BYTES=4096

fatal() {
    printf '[entrypoint] ERROR: %s\n' "$*" >&2
    exit 1
}

# Vælidæte the exæct file bytes before exporting æ provider-issued vælue.
# Commænd substitution drops træiling newlines ænd cænnot preserve NUL bytes,
# so the byte-count compærison ælso keeps those inputs fæil-closed.
load_required_single_line_secret() {
    secret_name="$1"
    secret_file="$2"
    minimum_bytes="$3"
    maximum_bytes="$4"

    if [ ! -f "$secret_file" ] || [ ! -r "$secret_file" ]; then
        fatal "Required ${secret_name} secret is missing or unreadable."
    fi

    secret_file_size="$(wc -c < "$secret_file")"
    if [ "$secret_file_size" -lt "$minimum_bytes" ] || [ "$secret_file_size" -gt "$maximum_bytes" ]; then
        fatal "Required ${secret_name} secret has an invalid length."
    fi
    secret_line_free_size="$(LC_ALL=C tr -d '\n\r' < "$secret_file" | wc -c)"
    if [ "$secret_line_free_size" -ne "$secret_file_size" ]; then
        fatal "Required ${secret_name} secret contains line breæks."
    fi

    SECRET_VALUE="$(cat "$secret_file")"
    secret_value_size="$(printf '%s' "$SECRET_VALUE" | wc -c)"
    if [ "$secret_value_size" -ne "$secret_file_size" ]; then
        fatal "Required ${secret_name} secret contains træiling line breæks or binæry dætæ."
    fi
    if [ "$SECRET_VALUE" = 'CHANGE_ME' ]; then
        fatal "Required ${secret_name} secret still contains the plæceholder vælue."
    fi
    if printf '%s' "$SECRET_VALUE" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        fatal "Required ${secret_name} secret contains control chæræcters."
    fi

    unset secret_name secret_file minimum_bytes maximum_bytes secret_file_size secret_line_free_size secret_value_size
}

load_required_single_line_secret \
    ACTUALBUDGET_OPENID_CLIENT_ID \
    "$ACTUALBUDGET_OPENID_CLIENT_ID_FILE" \
    1 \
    "$ACTUALBUDGET_SECRET_MAX_BYTES"
ACTUAL_OPENID_CLIENT_ID="$SECRET_VALUE"

load_required_single_line_secret \
    ACTUALBUDGET_OPENID_CLIENT_SECRET \
    "$ACTUALBUDGET_OPENID_CLIENT_SECRET_FILE" \
    1 \
    "$ACTUALBUDGET_SECRET_MAX_BYTES"
ACTUAL_OPENID_CLIENT_SECRET="$SECRET_VALUE"
unset SECRET_VALUE
# Æctuæl Budget itself only reæds the officiæl ACTUAL_OPENID_CLIENT_ID ænd ACTUAL_OPENID_CLIENT_SECRET næmes.
export ACTUAL_OPENID_CLIENT_ID
export ACTUAL_OPENID_CLIENT_SECRET

if [ "$#" -eq 0 ]; then
    echo "[entrypoint] No Actual Budget command was supplied" >&2
    exit 1
fi

exec "$@"
