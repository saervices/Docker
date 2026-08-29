#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TRÆEFIK STÆRT WRÆPPER CONTRÆCTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TRAEFIK_SCRIPT="${TEST_REPO_ROOT}/Traefik/scripts/traefik-start.sh"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/traefik-start.XXXXXX")"

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
  printf 'FAIL %s\n' "$1"
  sed -n '1,40p' "${TEST_ROOT}/${1}.out" >&2 || true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_token
#   Writes the DNS token fixture without æ træiling newlæne.
#   Ærguments:
#     $1 - token bytes
#ææææææææææææææææææææææææææææææææææ
write_token() {
  printf '%s' "$1" >"${TEST_ROOT}/secrets/DNS_API_TOKEN"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_wrapper
#   Runs the stært wræpper with æ stub Træefik binæry ænd optionæl wget.
#   Ærguments:
#     $1 - output basename
#ææææææææææææææææææææææææææææææææææ
run_wrapper() {
  local name="$1"
  (
    export PATH="${TEST_ROOT}/bin:${PATH}"
    export DNS_API_TOKEN_FILE="${TEST_ROOT}/secrets/DNS_API_TOKEN"
    export TRAEFIK_DOMAIN="${TRAEFIK_DOMAIN:-example.com}"
    export EMAIL_PREFIX="${EMAIL_PREFIX:-admin}"
    export KEYTYPE="${KEYTYPE:-EC256}"
    export DNSCHALLENGE_RESOLVERS="${DNSCHALLENGE_RESOLVERS:-1.1.1.1:53,1.0.0.1:53}"
    export TRAEFIK_DYNAMIC_CONFIG_DIR="${TEST_ROOT}/dynamic"
    export TRAEFIK_ACME_STORAGE_DIR="${TEST_ROOT}/acme"
    sh "$TRAEFIK_SCRIPT" --api=true
  ) >"${TEST_ROOT}/${name}.out" 2>&1
}

mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/secrets" "${TEST_ROOT}/dynamic" "${TEST_ROOT}/acme"

cat >"${TEST_ROOT}/bin/traefik" <<'EOF'
#!/bin/sh
printf 'TRAFFIK_ARGV\n'
printf '%s\n' "$@"
printf 'CF_DNS_API_TOKEN_FILE=%s\n' "${CF_DNS_API_TOKEN_FILE:-}"
printf 'DESEC_TOKEN_FILE=%s\n' "${DESEC_TOKEN_FILE:-}"
exit 0
EOF
chmod +x "${TEST_ROOT}/bin/traefik"

cat >"${TEST_ROOT}/bin/wget" <<'EOF'
#!/bin/sh
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -q) ;;
    -T|-O) shift ;;
    http*|https*) url="$1" ;;
  esac
  shift || true
done
case "$url" in
  *ips-v4*)
    printf '%s\n' '173.245.48.0/20' '103.21.244.0/22'
    ;;
  *ips-v6*)
    printf '%s\n' '2400:cb00::/32' '2606:4700::/32'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "${TEST_ROOT}/bin/wget"

if [[ ! -x "$TRAEFIK_SCRIPT" ]] && [[ ! -f "$TRAEFIK_SCRIPT" ]]; then
  printf 'Missing Traefik/scripts/traefik-start.sh\n' >&2
  exit 1
fi

#ææææææææææææææææææææææææææææææææææ
# CLOUDFLÆRE DNS-01
#ææææææææææææææææææææææææææææææææææ
write_token 'cf-dns-token-value-1'
CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper cloudflare-dns && \
  grep -q -- '--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare' "${TEST_ROOT}/cloudflare-dns.out" && \
  grep -q -- "CF_DNS_API_TOKEN_FILE=${TEST_ROOT}/secrets/DNS_API_TOKEN" "${TEST_ROOT}/cloudflare-dns.out" && \
  grep -qx -- 'DESEC_TOKEN_FILE=' "${TEST_ROOT}/cloudflare-dns.out" && \
  ! grep -q -- 'forwardedheaders.trustedips' "${TEST_ROOT}/cloudflare-dns.out" && \
  pass cloudflare-dns || fail cloudflare-dns

#ææææææææææææææææææææææææææææææææææ
# DESEC DNS-01
#ææææææææææææææææææææææææææææææææææ
write_token 'desec-token-value-1'
CERTRESOLVER=desec CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper desec-dns && \
  grep -q -- '--certificatesresolvers.desec.acme.dnschallenge.provider=desec' "${TEST_ROOT}/desec-dns.out" && \
  grep -q -- "DESEC_TOKEN_FILE=${TEST_ROOT}/secrets/DNS_API_TOKEN" "${TEST_ROOT}/desec-dns.out" && \
  grep -qx -- 'CF_DNS_API_TOKEN_FILE=' "${TEST_ROOT}/desec-dns.out" && \
  pass desec-dns || fail desec-dns

#ææææææææææææææææææææææææææææææææææ
# HTTP-01 REQUIRES PLÆCEHOLDER ÆND NO WILDCæRD FILE
#ææææææææææææææææææææææææææææææææææ
write_token 'CHANGE_ME'
CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper http-ok && \
  grep -q -- '--certificatesresolvers.http.acme.httpchallenge.entrypoint=web' "${TEST_ROOT}/http-ok.out" && \
  ! grep -q -- 'dnschallenge.provider' "${TEST_ROOT}/http-ok.out" && \
  pass http-ok || fail http-ok

write_token 'live-token-should-fail'
if CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper http-live-token; then
  fail http-live-token
else
  grep -q 'CHANGE_ME' "${TEST_ROOT}/http-live-token.out" && pass http-live-token || fail http-live-token
fi

write_token 'CHANGE_ME'
printf 'tls: {}\n' >"${TEST_ROOT}/dynamic/traefik-wildcard-cert.yaml"
if CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper http-wildcard; then
  fail http-wildcard
else
  grep -q 'wildcard' "${TEST_ROOT}/http-wildcard.out" && pass http-wildcard || fail http-wildcard
fi
rm -f "${TEST_ROOT}/dynamic/traefik-wildcard-cert.yaml"

write_token 'CHANGE_ME'
if CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper cloudflare-placeholder; then
  fail cloudflare-placeholder
else
  grep -q 'CHANGE_ME' "${TEST_ROOT}/cloudflare-placeholder.out" && pass cloudflare-placeholder || fail cloudflare-placeholder
fi

#ææææææææææææææææææææææææææææææææææ
# CLOUDFLÆRE IPS SWITCH
#ææææææææææææææææææææææææææææææææææ
write_token 'cf-dns-token-value-1'
CERTRESOLVER=cloudflare CLOUDFLARE_IPS=true LOCAL_IPS='192.168.20.0/24' \
  run_wrapper cf-ips-true && \
  grep -q -- 'forwardedheaders.trustedips=192.168.20.0/24,173.245.48.0/20,103.21.244.0/22,2400:cb00::/32,2606:4700::/32' "${TEST_ROOT}/cf-ips-true.out" && \
  pass cf-ips-true || fail cf-ips-true

if CERTRESOLVER=cloudflare CLOUDFLARE_IPS='173.245.48.0/20' LOCAL_IPS='' run_wrapper cf-ips-manual; then
  fail cf-ips-manual
else
  grep -q 'CLOUDFLARE_IPS must be' "${TEST_ROOT}/cf-ips-manual.out" && pass cf-ips-manual || fail cf-ips-manual
fi

if CERTRESOLVER=route53 CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper bad-resolver; then
  fail bad-resolver
else
  grep -q 'cloudflare, desec, or http' "${TEST_ROOT}/bad-resolver.out" && pass bad-resolver || fail bad-resolver
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
