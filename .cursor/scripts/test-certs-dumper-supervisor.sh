#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTS-DUMPER SUPERVISOR CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly ENTRYPOINT="${TEST_REPO_ROOT}/templates/traefik_certs-dumper/dockerfiles/entrypoint.traefik_certs-dumper.sh"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/certs-dumper-supervisor.XXXXXX")"

PASS=0
FAIL=0

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  sed -n '1,40p' "${TEST_ROOT}/${1}.out" >&2 || true
}

mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/data" "${TEST_ROOT}/data/files" \
  "${TEST_ROOT}/run" "${TEST_ROOT}/config"

cat >"${TEST_ROOT}/bin/traefik-certs-dumper" <<'EOF'
#!/bin/sh
source_path=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      source_path="$2"
      shift
      ;;
  esac
  shift || true
done
printf 'DUMPER_SOURCE=%s\n' "$source_path" >>"${CERTS_DUMPER_TEST_LOG}"
mkdir -p "${ACME_DEST}/example.com"
printf 'cert\n' >"${ACME_DEST}/example.com/certificate.pem"
printf 'key\n' >"${ACME_DEST}/example.com/privatekey.pem"
exit 0
EOF
chmod +x "${TEST_ROOT}/bin/traefik-certs-dumper"

cat >"${TEST_ROOT}/config/post-hook.sh" <<'EOF'
#!/bin/sh
printf 'HOOK_RAN=1\n' >>"${CERTS_DUMPER_TEST_LOG}"
exit 0
EOF
chmod +x "${TEST_ROOT}/config/post-hook.sh"

printf '{"letsencrypt":{"Certificates":[{"domain":{"main":"example.com"}}]}}\n' \
  >"${TEST_ROOT}/data/cloudflare-acme.json"

export PATH="${TEST_ROOT}/bin:${PATH}"
export ACME_FILENAME=cloudflare-acme.json
export ACME_DIR="${TEST_ROOT}/data"
export ACME_DEST="${TEST_ROOT}/data/files"
export CERTS_DUMPER_RUNTIME_DIR="${TEST_ROOT}/run"
export CERTS_DUMPER_POLL_SECONDS=1
export POST_HOOK="${TEST_ROOT}/config/post-hook.sh"
export CERTS_DUMPER_TEST_LOG="${TEST_ROOT}/dumper.log"

if timeout 4 sh "$ENTRYPOINT" >"${TEST_ROOT}/supervisor.out" 2>&1; then
  fail supervisor-timeout
else
  if [ -f "${TEST_ROOT}/run/ready" ] \
    && grep -q 'HOOK_RAN=1' "$CERTS_DUMPER_TEST_LOG" \
    && grep -qx "DUMPER_SOURCE=${TEST_ROOT}/run/acme.json" "$CERTS_DUMPER_TEST_LOG"; then
    pass supervisor-snapshot
  else
    fail supervisor-snapshot
  fi
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
