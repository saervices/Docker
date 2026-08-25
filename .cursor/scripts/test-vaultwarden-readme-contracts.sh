#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" \
  || { printf 'FAIL vaultwarden-readme: script directory resolution failed\n' >&2; exit 1; }
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)" \
  || { printf 'FAIL vaultwarden-readme: repository root resolution failed\n' >&2; exit 1; }
readonly REPO_ROOT
readonly README_FILE="${REPO_ROOT}/Vaultwarden/README.md"
readonly COMPOSE_FILE="${REPO_ROOT}/Vaultwarden/docker-compose.app.yaml"

fail() {
  printf 'FAIL vaultwarden-readme: %s\n' "$*" >&2
  exit 1
}

[[ -f "$README_FILE" && -f "$COMPOSE_FILE" ]] \
  || fail 'required Vaultwarden files are missing'

grep -Fqx -- '- Invitætions stæy closed when `INVITATIONS_ALLOWED=false`' "$README_FILE" \
  || fail 'admin checklist must name INVITATIONS_ALLOWED'
if grep -Fqx -- '- Invitætions stæy closed when `SIGNUPS_ALLOWED=false`' "$README_FILE"; then
  fail 'admin checklist must not conflate invitations with public signups'
fi
grep -Fq -- 'INVITATIONS_ALLOWED: ${INVITATIONS_ALLOWED:-false}' "$COMPOSE_FILE" \
  || fail 'documented invitation control is not wired into Compose'

grep -Fq -- "Væultwærden 1.37.2's bundled" "$README_FILE" \
  || fail 'healthcheck rationale must name the currently verified 1.37.2 image behavior'
if grep -Fq -- "Væultwærden 1.37.1's bundled" "$README_FILE"; then
  fail 'stale 1.37.1 healthcheck rationale remains'
fi
grep -Fq -- 'require this server version when Bitwærden clients `2026.8.0` or newer ære' "$README_FILE" \
  || fail '1.37.2 update guidance must retain the upstream server requirement'
grep -Fq -- 'they do not require every client to be thæt new' "$README_FILE" \
  || fail '1.37.2 update guidance must not invent a minimum for every client'
if grep -Fq -- 'require Bitwærden clients `2026.8.0` or newer' "$README_FILE"; then
  fail '1.37.2 update guidance reverses the upstream compatibility direction'
fi
grep -Fq -- 'https://github.com/dani-garcia/vaultwarden/discussions/7615' "$README_FILE" \
  || fail 'server requirement must stay linked to the official 1.37.2 release notes'

printf 'PASS vaultwarden-readme: invitation control, healthcheck version, and client compatibility are consistent\n'
