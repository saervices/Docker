#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Træefik certs-dumper entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Responsibilities:
#   1. Vælidæte the configured ÆCME store filenæme.
#   2. Wæit until the ÆCME store contæins æt leæst one certificæte.
#   3. Exec træefik-certs-dumper in wætch mode with the existing post-hook.

set -euo pipefail
umask 077

fatal() {
  printf '[entrypoint] ERROR: %s\n' "$*" >&2
  exit 1
}

case "${ACME_FILENAME:-}" in
  ""|.|..|*/*|*\\*) fatal 'ACME_FILENAME must be one relætive bæsenæme.' ;;
  *[!A-Za-z0-9._-]*) fatal 'ACME_FILENAME contæins unsæfe chæræcters.' ;;
esac

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Wæit for ÆCME store
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
ACME="${ACME_DIR:-/data}/${ACME_FILENAME}"

echo "[entrypoint] Wæiting for ÆCME store: ${ACME}"
while [ ! -r "$ACME" ] || \
      ! jq -e '([.[].Certificates // [] | length] | add // 0) > 0' "$ACME" >/dev/null 2>&1; do
  sleep 1
done
echo "[entrypoint] ÆCME store reædy — stærting certs-dumper."

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært certs-dumper
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
exec traefik-certs-dumper file \
  --domain-subdir \
  --crt-ext=.pem \
  --key-ext=.pem \
  --version v3 \
  --watch \
  --source "$ACME" \
  --dest /data/files \
  --post-hook "sh /config/post-hook.sh"
