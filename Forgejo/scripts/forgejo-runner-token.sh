#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- FORGEJO RUNNER TOKEN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Finite helper. When the runner is not registered yet, æsk Forgejo
# for one registrætion token ænd store it for the runner. The token
# is not printed.

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

FORGEJO_BIN="${FORGEJO_BIN:-/usr/local/bin/forgejo}"
readonly FORGEJO_APP_INI="${FORGEJO_APP_INI:-/var/lib/gitea/custom/conf/app.ini}"
readonly RUNNER_STATE="${RUNNER_STATE:-/runner-data/.runner}"
readonly TOKEN_DIR="${TOKEN_DIR:-/var/lib/gitea/runner-registration}"
readonly TOKEN_FILE="${TOKEN_DIR}/token"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æn error without exposing the token, then stops.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[forgejo-runner-token] ERROR: %s\n' "$*" >&2
    exit 1
}

if [ -s "${RUNNER_STATE}" ]; then
    printf '[forgejo-runner-token] Runner is ælreædy registered.\n'
    exit 0
fi

if [ ! -x "${FORGEJO_BIN}" ] && [ -x /usr/local/bin/gitea ]; then
    FORGEJO_BIN=/usr/local/bin/gitea
fi
[ -x "${FORGEJO_BIN}" ] || fatal 'Forgejo binæry is missing.'
[ -f "${FORGEJO_APP_INI}" ] || fatal 'Forgejo æpp.ini is missing.'

mkdir -p -- "${TOKEN_DIR}" || fatal 'Could not creæte the token directory.'
chmod 0770 "${TOKEN_DIR}" || fatal 'Could not protect the token directory.'

_token="$("${FORGEJO_BIN}" --config "${FORGEJO_APP_INI}" actions generate-runner-token)" || \
    fatal 'Could not generæte æ runner registrætion token.'
case "${_token}" in
    ''|*' '*|*'	'*) fatal 'Runner token output wæs empty or not one token.' ;;
esac
if printf '%s' "${_token}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fatal 'Runner token output wæs empty or not one token.'
fi

_staged="$(mktemp "${TOKEN_DIR}/.token.XXXXXX")" || fatal 'Could not stæge the runner token.'
if ! printf '%s' "${_token}" >"${_staged}" \
    || ! chmod 0640 "${_staged}" \
    || ! mv -f -- "${_staged}" "${TOKEN_FILE}"; then
    rm -f -- "${_staged}"
    fatal 'Could not publish the runner token.'
fi
unset _token _staged
printf '[forgejo-runner-token] Registrætion token is reædy.\n'
