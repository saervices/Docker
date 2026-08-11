#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆSEÆRCH BOOTSTRÆP SECRET LIFETIME
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -euo pipefail
umask 077

readonly PASSWORD_FILE="${SEASEARCH_PASSWORD_FILE:-/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD}"
readonly DATA_PATH="${SS_DATA_PATH:-/opt/seasearch/data}"
readonly INITIALIZATION_MARKER="${DATA_PATH}/_metadata.bolt"
readonly SEASEARCH_BIN="${SEASEARCH_BIN:-/opt/seasearch/seasearch}"
readonly BOOTSTRAP_TIMEOUT="${SEASEARCH_BOOTSTRAP_TIMEOUT:-120}"

bootstrap_pid=''

fatal() {
  printf '[seasearch] ERROR: %s\n' "$*" >&2
  exit 1
}

stop_bootstrap() {
  local attempt

  if [[ -z "${bootstrap_pid}" ]] || ! kill -0 "${bootstrap_pid}" 2>/dev/null; then
    return 0
  fi

  kill -TERM "${bootstrap_pid}" 2>/dev/null || true
  for attempt in {1..30}; do
    if ! kill -0 "${bootstrap_pid}" 2>/dev/null; then
      wait "${bootstrap_pid}" 2>/dev/null || true
      bootstrap_pid=''
      return 0
    fi
    sleep 1
  done

  kill -KILL "${bootstrap_pid}" 2>/dev/null || true
  wait "${bootstrap_pid}" 2>/dev/null || true
  bootstrap_pid=''
}

trap stop_bootstrap EXIT INT TERM

load_password() {
  local file_size
  local value_size
  local LC_ALL=C

  if [[ -L "${PASSWORD_FILE}" || ! -f "${PASSWORD_FILE}" || ! -r "${PASSWORD_FILE}" ]]; then
    fatal 'SEAFILE_SEASEARCH_ADMIN_PASSWORD is missing, unreadable, or not a regular file.'
  fi

  file_size="$(wc -c <"${PASSWORD_FILE}")"
  if (( file_size < 12 || file_size > 4096 )); then
    fatal 'SEAFILE_SEASEARCH_ADMIN_PASSWORD has an invalid length.'
  fi

  SEASEARCH_SECRET_VALUE="$(<"${PASSWORD_FILE}")"
  value_size="$(printf '%s' "${SEASEARCH_SECRET_VALUE}" | wc -c)"
  if (( value_size != file_size )); then
    fatal 'SEAFILE_SEASEARCH_ADMIN_PASSWORD contains line breaks or binary data.'
  fi
  if [[ "${SEASEARCH_SECRET_VALUE}" == 'CHANGE_ME' ]]; then
    fatal 'SEAFILE_SEASEARCH_ADMIN_PASSWORD still contains the placeholder value.'
  fi
  if [[ "${SEASEARCH_SECRET_VALUE}" =~ [[:cntrl:]] ]]; then
    fatal 'SEAFILE_SEASEARCH_ADMIN_PASSWORD contains control characters.'
  fi
}

load_password

if [[ "${1:-}" == '--preflight-only' ]]; then
  unset SEASEARCH_SECRET_VALUE
  exit 0
fi

if [[ ! -x "${SEASEARCH_BIN}" ]]; then
  fatal 'The SeaSearch vendor binary is missing or not executable.'
fi

mkdir -p "${DATA_PATH}"

if [[ ! -s "${INITIALIZATION_MARKER}" ]]; then
  printf '[seasearch] INFO: Running bounded first-start credential bootstrap.\n'
  ZINC_FIRST_ADMIN_USER=seasearch \
    ZINC_FIRST_ADMIN_PASSWORD="${SEASEARCH_SECRET_VALUE}" \
    "${SEASEARCH_BIN}" &
  bootstrap_pid="$!"

  ready=false
  for ((attempt = 1; attempt <= BOOTSTRAP_TIMEOUT; attempt++)); do
    if ! kill -0 "${bootstrap_pid}" 2>/dev/null; then
      wait "${bootstrap_pid}" 2>/dev/null || true
      bootstrap_pid=''
      fatal 'SeaSearch exited before first-start bootstrap completed.'
    fi

    if [[ -s "${INITIALIZATION_MARKER}" ]] \
      && { exec 3<>/dev/tcp/127.0.0.1/4080; } 2>/dev/null; then
      exec 3>&-
      ready=true
      break
    fi
    sleep 1
  done

  if [[ "${ready}" != true ]]; then
    fatal 'SeaSearch first-start bootstrap timed out.'
  fi

  stop_bootstrap
  printf '[seasearch] INFO: First-start credential bootstrap completed; restarting with æ scrubbed environment.\n'
fi

unset SEASEARCH_SECRET_VALUE ZINC_FIRST_ADMIN_USER ZINC_FIRST_ADMIN_PASSWORD
trap - EXIT INT TERM

exec "${SEASEARCH_BIN}"
