#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTS-DUMPER POST-HOOK CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly HOOK="${TEST_REPO_ROOT}/templates/traefik_certs-dumper/scripts/post-hook.sh"
readonly DUMPER_COMPOSE="${TEST_REPO_ROOT}/templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml"
readonly KNOWN_HOSTS="${TEST_REPO_ROOT}/Traefik/appdata/certs-dumper-state/known_hosts"
readonly PARSER_IMMICH="${TEST_REPO_ROOT}/templates/crowdsec_agent/appdata/crowdsec_agent/config/parsers/s02-enrich/immich-thumbnail-whitelist.yaml"
readonly PARSER_SEAFILE="${TEST_REPO_ROOT}/templates/crowdsec_agent/appdata/crowdsec_agent/config/parsers/s02-enrich/seafile-sync-whitelist.yaml"
readonly CROWDSEC_README="${TEST_REPO_ROOT}/templates/crowdsec_agent/README.md"
readonly DUMPER_README="${TEST_REPO_ROOT}/templates/traefik_certs-dumper/README.md"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
}

if grep -q 'StrictHostKeyChecking=yes' "$HOOK" \
  && grep -q '/state/known_hosts' "$HOOK" \
  && ! grep -q 'StrictHostKeyChecking=accept-new' "$HOOK"; then
  pass hook-ssh-pin
else
  fail hook-ssh-pin
fi

if grep -q 'local dest_user="certdeploy"' "$HOOK" \
  && grep -q '^# if true; then mailcow; fi$' "$HOOK" \
  && ! grep -q '^if true; then mailcow; fi$' "$HOOK"; then
  pass hook-mailcow-deploy-user
else
  fail hook-mailcow-deploy-user
fi

if grep -qE '^[[:space:]]+# group_add:' "$DUMPER_COMPOSE" \
  && grep -qE '^[[:space:]]+# secrets:' "$DUMPER_COMPOSE" \
  && grep -qE '^[[:space:]]+#[[:space:]]+DNS_API_TOKEN_FILE:' "$DUMPER_COMPOSE" \
  && ! grep -qE '^[[:space:]]+group_add:' "$DUMPER_COMPOSE" \
  && ! grep -qE '^[[:space:]]+DNS_API_TOKEN_FILE:' "$DUMPER_COMPOSE" \
  && grep -qE '^secrets:' "$DUMPER_COMPOSE" \
  && grep -qE '^  TRAEFIK_CERTS_DUMPER_PASSWORD:' "$DUMPER_COMPOSE"; then
  pass hook-mailcow-package
else
  fail hook-mailcow-package
fi

if [[ ! -e "$KNOWN_HOSTS" ]] \
  && grep -q 'Pinned SSH known_hosts is missing or empty' "$HOOK"; then
  pass hook-known-hosts-empty
else
  fail hook-known-hosts-empty
fi

if grep -q 'useradd --create-home --shell /bin/sh --user-group certdeploy' "$DUMPER_README" \
  && grep -q '/opt/mailcow-dockerized/data/assets/ssl' "$DUMPER_README" \
  && grep -q 'docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow' "$DUMPER_README" \
  && grep -q 'root-equivælent' "$DUMPER_README" \
  && grep -q 'usermod -aG docker certdeploy' "$DUMPER_README" \
  && grep -q 'ssh-keyscan -H 192.168.20.120 > appdata/certs-dumper-state/known_hosts' "$DUMPER_README" \
  && grep -q 'scp /tmp/certdeploy_mailcow.pub root@192.168.20.120:/root/certdeploy_mailcow.pub' "$DUMPER_README"; then
  pass hook-certdeploy-readme
else
  fail hook-certdeploy-readme
fi

if grep -q 'cloudflare-acme.json' "$HOOK" \
  && grep -q 'desec-acme.json' "$HOOK" \
  && grep -q 'desec.io/api/v1' "$HOOK"; then
  pass hook-provider-case
else
  fail hook-provider-case
fi

if grep -q 'require_zone_dnssec' "$HOOK" \
  && grep -q '${dest_cert_path}.bak' "$HOOK" \
  && grep -q 'post-hook.lock' "$HOOK"; then
  pass hook-dnssec-stage-lock
else
  fail hook-dnssec-stage-lock
fi

if grep -q "startsWith 'immich.'" "$PARSER_IMMICH" \
  && ! grep -q 'xn--srvices-mxa.de' "$PARSER_IMMICH" \
  && grep -q 'stærts with `immich.`' "$CROWDSEC_README" \
  && grep -q 'Do not depend on query pæræmeters' "$CROWDSEC_README"; then
  pass parser-immich
else
  fail parser-immich
fi

if grep -q "startsWith 'seafile.'" "$PARSER_SEAFILE" \
  && ! grep -q 'xn--srvices-mxa.de' "$PARSER_SEAFILE" \
  && grep -q 'stærts with `seafile.`' "$CROWDSEC_README"; then
  pass parser-seafile
else
  fail parser-seafile
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
