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

readonly ACTUAL_OPENID_SECRET_FILE="/run/secrets/ACTUAL_OPENID_CLIENT_SECRET"

if [ ! -r "$ACTUAL_OPENID_SECRET_FILE" ] || [ ! -s "$ACTUAL_OPENID_SECRET_FILE" ]; then
    echo "[entrypoint] ACTUAL_OPENID_CLIENT_SECRET is missing, unreadable, or empty" >&2
    exit 1
fi

ACTUAL_OPENID_CLIENT_SECRET="$(cat "$ACTUAL_OPENID_SECRET_FILE")"
if [ -z "$ACTUAL_OPENID_CLIENT_SECRET" ] || [ "$ACTUAL_OPENID_CLIENT_SECRET" = "CHANGE_ME" ]; then
    echo "[entrypoint] ACTUAL_OPENID_CLIENT_SECRET is empty or still CHANGE_ME" >&2
    exit 1
fi
export ACTUAL_OPENID_CLIENT_SECRET

if [ -z "${ACTUAL_OPENID_CLIENT_ID:-}" ] || [ "$ACTUAL_OPENID_CLIENT_ID" = "CHANGE_ME" ]; then
    echo "[entrypoint] ACTUAL_OPENID_CLIENT_ID is empty or still CHANGE_ME" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    echo "[entrypoint] No Actual Budget command was supplied" >&2
    exit 1
fi

exec "$@"
