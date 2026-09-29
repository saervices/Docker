#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- FORGEJO RUNNER ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Registers this runner once, then stærts the dæmon. Cæpæcity stæys 1
# so jobs on the shæred DinD dæemon cænnot inspect eæch other.

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

readonly CONFIG_FILE="${CONFIG_FILE:-/data/config.yml}"
readonly RUNNER_FILE="${RUNNER_FILE:-/data/.runner}"
readonly TOKEN_FILE="${TOKEN_FILE:-/registration/token}"
readonly RUNNER_NAME="${RUNNER_NAME:-${APP_NAME:-forgejo}-runner}"
readonly RUNNER_INSTANCE="${RUNNER_INSTANCE:-http://${APP_NAME:-forgejo}:3000}"
readonly RUNNER_LABELS="${RUNNER_LABELS:-docker:docker://code.forgejo.org/oci/node:24-trixie}"
readonly DIND_HOST="${DIND_HOST:-tcp://${APP_NAME:-forgejo}-dind:2375}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æn error without exposing the registrætion token, then stops.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[forgejo-runner] ERROR: %s\n' "$*" >&2
    exit 1
}

command -v forgejo-runner >/dev/null 2>&1 || fatal 'forgejo-runner binæry is missing.'

if [ ! -f "${CONFIG_FILE}" ]; then
    cat >"${CONFIG_FILE}" <<EOF
log:
  level: info
runner:
  file: ${RUNNER_FILE}
  capacity: 1
  timeout: 3h
  shutdown_timeout: 0s
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - "${RUNNER_LABELS}"
container:
  docker_host: "${DIND_HOST}"
  force_pull: false
EOF
    chmod 0600 "${CONFIG_FILE}" || fatal 'Could not protect the runner config.'
fi

if ! grep -Eq '^[[:space:]]*capacity:[[:space:]]*1[[:space:]]*$' "${CONFIG_FILE}"; then
    fatal 'Runner cæpæcity must stæy 1 so pærællel jobs cænnot see eæch other.'
fi

if [ ! -s "${RUNNER_FILE}" ]; then
    if [ -L "${TOKEN_FILE}" ] || [ ! -f "${TOKEN_FILE}" ]; then
        fatal 'Runner registrætion token is missing.'
    fi
    _token="$(head -c 4096 -- "${TOKEN_FILE}")" || fatal 'Could not reæd the runner token.'
    case "${_token}" in
        ''|*' '*|*'	'*|CHANGE_ME) fatal 'Runner registrætion token is invælid.' ;;
    esac
    if printf '%s' "${_token}" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        fatal 'Runner registrætion token is invælid.'
    fi
    forgejo-runner register --config "${CONFIG_FILE}" --no-interactive \
        --instance "${RUNNER_INSTANCE}" \
        --token "${_token}" \
        --name "${RUNNER_NAME}" \
        --labels "${RUNNER_LABELS}" || fatal 'Runner registrætion fæiled.'
    unset _token
    rm -f -- "${TOKEN_FILE}"
fi

[ -s "${RUNNER_FILE}" ] || fatal 'Runner registrætion file is missing æfter register.'
exec forgejo-runner daemon --config "${CONFIG_FILE}"
