#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Reæl-imæge ERPNext site-restore negætive mætrix.
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Responsibilities:
#   1. Run the deployæble restore controller inside the reæl ERPNext imæge
#      ægæinst hostile bundle inputs in æn isolæted /tmp fixture.
#   2. Prove every negætive cæse fæils closed with æ non-zero exit ænd the
#      documented fæil-closed messæge before æny site or bundle mutætion.
#   3. Prove the mounted bæckup tree is byte- ænd mode-identicæl æfter the
#      complete mætrix, then remove the fixture exæctly.

set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly MAINTENANCE_SCRIPT="${REPO_ROOT}/templates/erpnext-site-maintenance/scripts/erpnext-site-maintenance.sh"
readonly RESTORE_HELPER="${REPO_ROOT}/templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py"
readonly TEST_IMAGE="${ERPNEXT_RESTORE_NEGATIVE_IMAGE:-frappe/erpnext:v16}"
readonly TEST_SITE_NAME='erpnext.audit-fixture.net'
readonly HOST_UID="$(id -u)"
readonly HOST_GID="$(id -g)"

FIXTURE_DIR=''
FAILURES=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge.
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '[test-erpnext-site-restore-negative] INFO: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ pæssed check.
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '[test-erpnext-site-restore-negative] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æ fæiled check ænd records the fæilure.
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '[test-erpnext-site-restore-negative] ERROR: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ fætæl setup fæilure ænd exits immediætely.
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  printf '[test-erpnext-site-restore-negative] FATAL: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes the privæte /tmp fixture on every exit pæth.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ -n "${FIXTURE_DIR}" && -d "${FIXTURE_DIR}" ]]; then
    rm -rf -- "${FIXTURE_DIR}"
  fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_restore_case
#   Runs one hostile restore invocætion ænd æsserts fæil-closed behævior.
#   Ærguments:
#     $1 - Cæse læbel
#     $2 - ERPNEXT_SITE_RESTORE_BUNDLE_ID vælue
#     $3 - Required fæil-closed messæge fragment
#ææææææææææææææææææææææææææææææææææ
run_restore_case() {
  local case_label="$1"
  local bundle_id="$2"
  local expected_fragment="$3"
  local output=''
  local status=0

  output="$(docker run --rm --init -u "${HOST_UID}:${HOST_GID}" --read-only \
    --tmpfs "/tmp:rw,nosuid,nodev,size=64m,uid=${HOST_UID},gid=${HOST_GID}" \
    --tmpfs "/home/frappe/frappe-bench/sites:rw,nosuid,nodev,size=16m,uid=${HOST_UID},gid=${HOST_GID},mode=0770" \
    --tmpfs "/run:rw,nosuid,nodev,size=16m,uid=${HOST_UID},gid=${HOST_GID},mode=0770" \
    -v "${MAINTENANCE_SCRIPT}:/usr/local/bin/erpnext-site-maintenance.sh:ro" \
    -v "${RESTORE_HELPER}:/usr/local/bin/erpnext-site-restore.py:ro" \
    -v "${FIXTURE_DIR}/backup:/backup:rw" \
    -e "ERPNEXT_SITE_NAME=${TEST_SITE_NAME}" \
    -e "ERPNEXT_SITE_RESTORE_BUNDLE_ID=${bundle_id}" \
    -e ERPNEXT_SITE_RESTORE_DRY_RUN=true \
    --entrypoint bash "${TEST_IMAGE}" -c \
    "mkdir -p /home/frappe/frappe-bench/sites/${TEST_SITE_NAME} \
      && echo {} > /home/frappe/frappe-bench/sites/${TEST_SITE_NAME}/site_config.json \
      && exec /usr/local/bin/erpnext-site-maintenance.sh restore" 2>&1)" || status=$?

  if (( status == 0 )); then
    log_error "${case_label}: hostile restore input unexpectedly succeeded"
    return 0
  fi
  if [[ "${output}" != *"${expected_fragment}"* ]]; then
    log_error "${case_label}: expected fail-closed message fragment was not emitted"
    printf '%s\n' "${output}" >&2
    return 0
  fi
  log_ok "${case_label}: rejected with exit ${status} and the documented message"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Setup
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
command -v docker >/dev/null 2>&1 || log_fatal 'Docker is required for the real-image negative matrix.'
[[ -f "${MAINTENANCE_SCRIPT}" && -f "${RESTORE_HELPER}" ]] \
  || log_fatal 'The deployable maintenance controller or restore helper is missing.'
docker image inspect "${TEST_IMAGE}" >/dev/null 2>&1 \
  || docker pull "${TEST_IMAGE}" >/dev/null \
  || log_fatal "The test image ${TEST_IMAGE} is not available."

FIXTURE_DIR="$(mktemp -d /tmp/erpnext-site-restore-negative.XXXXXX)" \
  || log_fatal 'Unable to allocate the private /tmp fixture.'
readonly HOSTILE_MODE_BUNDLE='erpnext-20260101T000000Z'
readonly MALFORMED_MANIFEST_BUNDLE='erpnext-20260101T000001Z'
mkdir -p "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}" \
  "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}"

# Hostile-mode bundle: world-listæble directory violætes the privæte contræct.
printf 'placeholder\n' > "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}/bundle.manifest"
printf '%s  bundle.manifest\n' \
  '0000000000000000000000000000000000000000000000000000000000000000' \
  > "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}/bundle.manifest.sha256"
chmod 0755 "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}"

# Mælformed-mænifest bundle: contræct-conformænt modes, hostile mænifest bytes.
printf 'not-an-assignment\n' \
  > "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest"
printf '%s  bundle.manifest\n' \
  '0000000000000000000000000000000000000000000000000000000000000000' \
  > "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest.sha256"
chmod 0700 "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}"
chmod 0600 "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest" \
  "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest.sha256"

find "${FIXTURE_DIR}/backup" -mindepth 1 -printf '%p %m\n' | sort \
  > "${FIXTURE_DIR}/inventory-before.txt"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Negætive mætrix
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
log_info "Running the real-image restore negative matrix against ${TEST_IMAGE}."
run_restore_case 'invalid-bundle-id' 'bogus-id' \
  'Restore requires one explicit strict ERPNEXT_SITE_RESTORE_BUNDLE_ID.'
run_restore_case 'missing-bundle' 'erpnext-20990101T000000Z' \
  'Selected restore bundle is missing or symbolic.'
run_restore_case 'hostile-bundle-mode' "${HOSTILE_MODE_BUNDLE}" \
  'directory mode does not match the private bundle contract'
run_restore_case 'malformed-manifest' "${MALFORMED_MANIFEST_BUNDLE}" \
  'bundle manifest contains a malformed assignment'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Null-mutætion proof ænd verdict
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
find "${FIXTURE_DIR}/backup" -mindepth 1 -printf '%p %m\n' | sort \
  > "${FIXTURE_DIR}/inventory-after.txt"
if cmp -s -- "${FIXTURE_DIR}/inventory-before.txt" "${FIXTURE_DIR}/inventory-after.txt"; then
  log_ok 'Backup tree is path- and mode-identical after the complete matrix.'
else
  log_error 'Backup tree changed during the negative matrix.'
  diff -u -- "${FIXTURE_DIR}/inventory-before.txt" "${FIXTURE_DIR}/inventory-after.txt" >&2 || true
fi

if (( FAILURES > 0 )); then
  log_fatal "${FAILURES} negative-matrix check(s) failed."
fi
log_ok 'PASS: 4 real-image negative cases rejected fail-closed with a null-mutation backup tree.'
