#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GET-FOLDER SECRET PRESERVÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/get-folder-secrets.XXXXXX")"
REPO_SUBFOLDER=Traefik
SCRIPT_DIR="$TEST_ROOT"
_TMPDIR="${TEST_ROOT}/src"
TARGET_DIR="${TEST_ROOT}/dest"
DRY_RUN=false
FORCE=true
PASS=0
FAIL=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes the disposæble fixture tree.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   No-op logger for sourced get-folder functions.
#ææææææææææææææææææææææææææææææææææ
log_ok() { :; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   No-op logger for sourced get-folder functions.
#ææææææææææææææææææææææææææææææææææ
log_info() { :; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   No-op logger for sourced get-folder functions.
#ææææææææææææææææææææææææææææææææææ
log_debug() { :; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   No-op logger for sourced get-folder functions.
#ææææææææææææææææææææææææææææææææææ
log_warn() { :; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Prints æn error without stopping the cæse hærness.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '%s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pass
#   Records one successful cæse.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled cæse.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
}

eval "$(sed -n '/^ensure_dir_exists()/,/^parse_args()/{ /^parse_args()/d; p; }' "${TEST_REPO_ROOT}/get-folder.sh")"
eval "$(sed -n '/^is_secret_relative_path()/,/^main()/{ /^main()/d; p; }' "${TEST_REPO_ROOT}/get-folder.sh")"

mkdir -p "${_TMPDIR}/Traefik/secrets" "${_TMPDIR}/Traefik/appdata" \
  "${TARGET_DIR}/secrets" "${TARGET_DIR}/appdata"
printf 'upstream-readme' >"${_TMPDIR}/Traefik/README.md"
printf 'upstream-token' >"${_TMPDIR}/Traefik/secrets/DNS_API_TOKEN"
printf 'upstream-new' >"${_TMPDIR}/Traefik/secrets/NEW_SECRET"
printf 'live-token' >"${TARGET_DIR}/secrets/DNS_API_TOKEN"
printf 'old-readme' >"${TARGET_DIR}/README.md"

if copy_files && \
   [[ "$(cat "${TARGET_DIR}/secrets/DNS_API_TOKEN")" == 'live-token' ]] && \
   [[ "$(cat "${TARGET_DIR}/secrets/NEW_SECRET")" == 'upstream-new' ]] && \
   [[ "$(cat "${TARGET_DIR}/README.md")" == 'upstream-readme' ]]; then
  pass preserve-existing-copy-missing
else
  fail preserve-existing-copy-missing
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
