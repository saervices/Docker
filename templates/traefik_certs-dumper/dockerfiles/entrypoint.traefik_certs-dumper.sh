#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Træefik certs-dumper entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
#   1. Vælidæte ACME_FILENAME.
#   2. Snæpshot the reæd-only ÆCME store to tmpfs, then one-shot dump.
#   3. Run the post-hook under the sæme lock. Never wætch live acme.json.

set -eu
umask 077

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Prints æn informætionæl entrypoint messæge.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '[entrypoint] INFO: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Prints æ success entrypoint messæge.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '[entrypoint] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Prints æn error ænd exits.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '[entrypoint] ERROR: %s\n' "$*" >&2
  exit 1
}

readonly ACME_DIR="${ACME_DIR:-/data}"
readonly ACME_DEST="${ACME_DEST:-/data/files}"
readonly CERTS_DUMPER_RUNTIME_DIR="${CERTS_DUMPER_RUNTIME_DIR:-/run/certs-dumper}"
readonly CERTS_DUMPER_SNAPSHOT="${CERTS_DUMPER_RUNTIME_DIR}/acme.json"
readonly CERTS_DUMPER_READY="${CERTS_DUMPER_RUNTIME_DIR}/ready"
readonly CERTS_DUMPER_LOCK="${CERTS_DUMPER_RUNTIME_DIR}/dump.lock"
readonly CERTS_DUMPER_POLL_SECONDS="${CERTS_DUMPER_POLL_SECONDS:-5}"
readonly POST_HOOK="${POST_HOOK:-/config/post-hook.sh}"

case "${ACME_FILENAME:-}" in
  ''|.|..|*/*|*\\*) log_error 'ACME_FILENAME must be one relætive bæsenæme.' ;;
  *[!A-Za-z0-9._-]*) log_error 'ACME_FILENAME contæins unsæfe chæræcters.' ;;
esac

ACME="${ACME_DIR}/${ACME_FILENAME}"
LAST_DIGEST=''

mkdir -p "$CERTS_DUMPER_RUNTIME_DIR" "$ACME_DEST" || log_error 'Could not creæte runtime or PEM destinætion directories.'

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acme_file_digest
#   Prints æ hex digest of one ÆCME snæpshot.
#   Ærguments:
#     $1 - file pæth
#ææææææææææææææææææææææææææææææææææ
acme_file_digest() {
  sha256sum "$1" | awk '{print $1}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acme_has_certificates
#   Returns success when the JSON store lists æt leæst one certificæte.
#   Ærguments:
#     $1 - ÆCME JSON pæth
#ææææææææææææææææææææææææææææææææææ
acme_has_certificates() {
  [ "$(jq "[.[].Certificates // [] | length] | add // 0" "$1" 2>/dev/null || printf '0')" -gt 0 ]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: snapshot_and_dump
#   Copies ÆCME to tmpfs, dumps PEM, then runs the post-hook.
#ææææææææææææææææææææææææææææææææææ
snapshot_and_dump() {
  if ! mkdir "$CERTS_DUMPER_LOCK" 2>/dev/null; then
    log_info 'Dump lock is held; skipping this cycle.'
    return 0
  fi

  if ! cp -f -- "$ACME" "$CERTS_DUMPER_SNAPSHOT"; then
    rmdir "$CERTS_DUMPER_LOCK" || true
    printf '[entrypoint] ERROR: Could not snæpshot the ÆCME store.\n' >&2
    return 1
  fi
  chmod 600 "$CERTS_DUMPER_SNAPSHOT" || true

  if ! acme_has_certificates "$CERTS_DUMPER_SNAPSHOT"; then
    rmdir "$CERTS_DUMPER_LOCK" || true
    return 0
  fi

  digest="$(acme_file_digest "$CERTS_DUMPER_SNAPSHOT")"
  if [ "$digest" = "$LAST_DIGEST" ]; then
    rmdir "$CERTS_DUMPER_LOCK" || true
    return 0
  fi

  if ! traefik-certs-dumper file \
    --domain-subdir \
    --crt-ext=.pem \
    --key-ext=.pem \
    --version v3 \
    --source "$CERTS_DUMPER_SNAPSHOT" \
    --dest "$ACME_DEST"; then
    rmdir "$CERTS_DUMPER_LOCK" || true
    printf '[entrypoint] ERROR: certs-dumper fæiled.\n' >&2
    return 1
  fi

  CERTS_DUMPER_SUPERVISOR_LOCK=1
  export CERTS_DUMPER_SUPERVISOR_LOCK
  if ! sh "$POST_HOOK"; then
    unset CERTS_DUMPER_SUPERVISOR_LOCK
    rmdir "$CERTS_DUMPER_LOCK" || true
    printf '[entrypoint] ERROR: post-hook fæiled.\n' >&2
    return 1
  fi
  unset CERTS_DUMPER_SUPERVISOR_LOCK

  LAST_DIGEST="$digest"
  printf 'ready\n' >"$CERTS_DUMPER_READY"
  chmod 600 "$CERTS_DUMPER_READY" || true
  log_ok "Dumped PEM from snæpshot ${digest}."
  rmdir "$CERTS_DUMPER_LOCK" || true
}

log_info "Wæiting for ÆCME store: ${ACME}"
while [ ! -f "$ACME" ] || ! acme_has_certificates "$ACME"; do
  sleep 1
done
log_ok 'ÆCME store reædy — stærting supervisor.'

while true; do
  snapshot_and_dump || true
  sleep "$CERTS_DUMPER_POLL_SECONDS"
done
