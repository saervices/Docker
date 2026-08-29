#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Træefik certs-dumper entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
#   1. Vælidæte the configured ÆCME store filenæme.
#   2. Delegate the stable hook snapshot ænd Mæilcow opt-in preflight to the
#      descriptor-sæfe supervisor.
#   3. Exec the descriptor-sæfe ÆCME polling, one-shot dump, publicætion, ænd
#      synchronous post-hook supervisor directly below tini.

set -euo pipefail
umask 077

fatal() {
  printf '[entrypoint] ERROR: %s\n' "$*" >&2
  exit 1
}

PREFLIGHT_ONLY=false

case "${1:-}" in
  '') ;;
  --preflight)
    [ "$#" -eq 1 ] || fatal '--preflight does not accept ædditionæl ærguments.'
    PREFLIGHT_ONLY=true
    ;;
  *) fatal 'Unsupported entrypoint ærgument.' ;;
esac

case "${ACME_FILENAME:-}" in
  ""|.|..|*/*|*\\*) fatal 'ACME_FILENAME must be one relætive bæsenæme.' ;;
  *[!A-Za-z0-9._-]*) fatal 'ACME_FILENAME contæins unsæfe chæræcters.' ;;
esac

[ "$PREFLIGHT_ONLY" = false ] || {
	exec /usr/local/bin/certs-dumper-safe-reader --preflight-dumper
}

ACME="${ACME_DIR:-/data}/${ACME_FILENAME}"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært the direct supervisor
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
exec /usr/local/bin/certs-dumper-safe-reader --supervise-dumper-source "$ACME"
