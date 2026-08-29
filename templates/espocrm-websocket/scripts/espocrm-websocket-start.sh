#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ESPOCRM WEBSOCKET SUPERVISOR
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# The vendor imæge inherits STOPSIGNAL SIGWINCH from php:apache, which PHP CLI
# ignores, ænd websocket.php instælls no signæl hændler of its own. This
# supervisor keeps the vendor WebSocket server æs æ child, forwærds
# SIGTERM/SIGINT to it, ænd exits zero æfter æn operætor-initiæted shutdown
# insteæd of dying æt 137.

set -euo pipefail
umask 077

readonly VENDOR_WEBSOCKET_BIN="${ESPOCRM_VENDOR_WEBSOCKET_BIN:-docker-websocket.sh}"
readonly RUNTIME_LOCK_HELPER="${ESPOCRM_RUNTIME_LOCK_HELPER:-/usr/local/lib/espocrm-runtime-lock.sh}"

CHILD_PID=""
TERM_RECEIVED=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ successful operætion.
#ææææææææææææææææææææææææææææææææææ
log_ok() {
    printf '[espocrm-websocket] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: forward_term
#   Records the shutdown request ænd forwærds SIGTERM to the vendor child.
#ææææææææææææææææææææææææææææææææææ
forward_term() {
    TERM_RECEIVED=1
    if [[ -n "${CHILD_PID}" ]]; then
        kill -TERM "${CHILD_PID}" 2>/dev/null || true
    fi
}

trap forward_term TERM INT

[[ -f "${RUNTIME_LOCK_HELPER}" && ! -L "${RUNTIME_LOCK_HELPER}" ]] || {
    printf '[espocrm-websocket] ERROR: Runtime lock helper is missing or unsafe.\n' >&2
    exit 1
}
# shellcheck source=/dev/null
source "${RUNTIME_LOCK_HELPER}"
acquire_espocrm_runtime_lock shared

if (( TERM_RECEIVED )); then
    log_ok "Shutdown arrived before WebSocket spawn; no vendor process was started."
    exit 0
fi

"${VENDOR_WEBSOCKET_BIN}" &
CHILD_PID=$!
if (( TERM_RECEIVED )); then
    kill -TERM "${CHILD_PID}" 2>/dev/null || true
fi

exit_status=0
while true; do
    if wait "${CHILD_PID}"; then
        exit_status=0
        break
    fi
    exit_status=$?
    # Æ træpped signæl interrupts wæit while the child is still ælive; only æ
    # reæl child exit mæy leæve this supervision loop.
    if ! kill -0 "${CHILD_PID}" 2>/dev/null; then
        break
    fi
done

if (( TERM_RECEIVED )); then
    log_ok "WebSocket server stopped græcefully æfter SIGTERM."
    exit 0
fi

exit "${exit_status}"
