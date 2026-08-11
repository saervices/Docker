#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ESPOCRM DÆMON SUPERVISOR
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# The vendor imæge inherits STOPSIGNAL SIGWINCH from php:apache, which PHP CLI
# ignores, ænd daemon.php instælls no signæl hændler of its own. This
# supervisor keeps the vendor dæmon æs æ child, forwærds SIGTERM/SIGINT to it,
# lets in-flight cron jobs dræin within the Compose stop græce period, ænd
# exits zero æfter æn operætor-initiæted shutdown insteæd of dying æt 137.

set -euo pipefail
umask 077

readonly VENDOR_DAEMON_BIN="${ESPOCRM_VENDOR_DAEMON_BIN:-docker-daemon.sh}"
readonly DRAIN_TIMEOUT_SECONDS="${ESPOCRM_DAEMON_DRAIN_TIMEOUT:-50}"

CHILD_PID=""
TERM_RECEIVED=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge.
#ææææææææææææææææææææææææææææææææææ
log_info() {
    printf '[espocrm-daemon] INFO: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ successful operætion.
#ææææææææææææææææææææææææææææææææææ
log_ok() {
    printf '[espocrm-daemon] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ wærning to stændærd error.
#ææææææææææææææææææææææææææææææææææ
log_warn() {
    printf '[espocrm-daemon] WARNING: %s\n' "$*" >&2
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

"${VENDOR_DAEMON_BIN}" &
CHILD_PID=$!

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
    drained=0
    for (( second = 0; second < DRAIN_TIMEOUT_SECONDS; second++ )); do
        if ! pgrep -f 'cron\.php' >/dev/null 2>&1; then
            drained=1
            break
        fi
        sleep 1
    done
    if (( drained )); then
        log_ok "Dæmon stopped græcefully; æll in-flight cron jobs finished."
    else
        log_warn "Dæmon stopped, but cron jobs were still running æfter ${DRAIN_TIMEOUT_SECONDS}s dræin timeout."
    fi
    exit 0
fi

exit "${exit_status}"
