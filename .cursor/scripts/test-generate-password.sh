#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GENERÆTE_PÆSSWORD CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/generate-password.XXXXXX")"
readonly SCRIPT_DIR="$TEST_REPO_ROOT"
DRY_RUN=false
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
# FUNCTION: log_info
#   No-op logger for sourced run.sh functions.
#ææææææææææææææææææææææææææææææææææ
log_info() { :; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   No-op logger for sourced run.sh functions.
#ææææææææææææææææææææææææææææææææææ
log_debug() { :; }

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

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_secret
#   Writes secret bytes without æ træiling newlæne.
#   Ærguments:
#     $1 - filenæme
#     $2 - content
#ææææææææææææææææææææææææææææææææææ
write_secret() {
  printf '%s' "$2" >"${TEST_ROOT}/secrets/$1"
}

eval "$(sed -n '/^secret_is_declared_for_app()/,/^apply_app_gid_secret_permissions()/{ /^apply_app_gid_secret_permissions()/d; p; }' "${TEST_REPO_ROOT}/run.sh")"

is_mikefarah_yq_v4() {
  command -v yq &>/dev/null || return 1
  local version
  version="$(yq --version 2>/dev/null || true)"
  [[ "$version" == *"mikefarah/yq"* && "$version" == *"version v4."* ]]
}

mkdir -p "${TEST_ROOT}/secrets"
cat >"${TEST_ROOT}/docker-compose.app.yaml" <<'EOF'
x-secret-generation-exclusions:
  - DNS_API_TOKEN
x-required-services: []
secrets:
  DNS_API_TOKEN:
    file: ./secrets/DNS_API_TOKEN
  APP_PASSWORD:
    file: ./secrets/APP_PASSWORD
EOF

write_secret DNS_API_TOKEN 'CHANGE_ME'
write_secret APP_PASSWORD 'CHANGE_ME'
write_secret LIVE_SECRET 'already-set'

if generate_password "${TEST_ROOT}/secrets" 12 '' DNS_API_TOKEN; then
  [[ "$(cat "${TEST_ROOT}/secrets/DNS_API_TOKEN")" == 'CHANGE_ME' ]] && \
    [[ "$(cat "${TEST_ROOT}/secrets/LIVE_SECRET")" == 'already-set' ]] && \
    [[ "$(wc -c < "${TEST_ROOT}/secrets/APP_PASSWORD" | tr -d '[:space:]')" == 12 ]] && \
    pass preserve-live-and-excluded || fail preserve-live-and-excluded
else
  fail preserve-live-and-excluded
fi

write_secret DNS_API_TOKEN 'CHANGE_ME'
if generate_password "${TEST_ROOT}/secrets" 12 DNS_API_TOKEN DNS_API_TOKEN; then
  fail explicit-excluded
else
  [[ "$(cat "${TEST_ROOT}/secrets/DNS_API_TOKEN")" == 'CHANGE_ME' ]] && pass explicit-excluded || fail explicit-excluded
fi

write_secret LIVE_SECRET 'already-set'
if generate_password "${TEST_ROOT}/secrets" 12 LIVE_SECRET; then
  fail explicit-live
else
  [[ "$(cat "${TEST_ROOT}/secrets/LIVE_SECRET")" == 'already-set' ]] && pass explicit-live || fail explicit-live
fi

if load_secret_generation_exclusions "${TEST_ROOT}/docker-compose.app.yaml" loaded_exclusions && \
   [[ "${loaded_exclusions[*]}" == 'DNS_API_TOKEN' ]]; then
  pass load-exclusions
else
  fail load-exclusions
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
