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
    export AUTHENTIK_FORWARD_AUTH_ADDRESS="${AUTHENTIK_FORWARD_AUTH_ADDRESS:-http://192.168.20.110:9000/outpost.goauthentik.io/auth/traefik}"
    sh "$TRAEFIK_SCRIPT" --api=true
  ) >"${TEST_ROOT}/${name}.out" 2>&1
}

mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/secrets" "${TEST_ROOT}/dynamic" "${TEST_ROOT}/acme"
cp -- "${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/stage-traefik-forward.yaml" \
  "${TEST_ROOT}/dynamic/stage-traefik-forward.yaml"

cat >"${TEST_ROOT}/bin/traefik" <<'EOF'
#!/bin/sh
printf 'TRAFFIK_ARGV\n'
printf '%s\n' "$@"
printf 'CF_DNS_API_TOKEN_FILE=%s\n' "${CF_DNS_API_TOKEN_FILE:-}"
printf 'DESEC_TOKEN_FILE=%s\n' "${DESEC_TOKEN_FILE:-}"
printf 'TRAEFIK_STAGE_FORWARD_HTTP_URL=%s\n' "${TRAEFIK_STAGE_FORWARD_HTTP_URL:-}"
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
# HTTP-01 REQUIRES PLÆCEHOLDER ÆND DISÆBLED WILDCæRD FLÆG
#ææææææææææææææææææææææææææææææææææ
write_token 'CHANGE_ME'
CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper http-ok && \
  grep -q -- '--certificatesresolvers.http.acme.httpchallenge.entrypoint=web' "${TEST_ROOT}/http-ok.out" && \
  ! grep -q -- 'dnschallenge.provider' "${TEST_ROOT}/http-ok.out" && \
  ! grep -q -- 'allowacmebypass' "${TEST_ROOT}/http-ok.out" && \
  pass http-ok || fail http-ok

write_token 'live-token-should-fail'
if CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper http-live-token; then
  fail http-live-token
else
  grep -q 'CHANGE_ME' "${TEST_ROOT}/http-live-token.out" && pass http-live-token || fail http-live-token
fi

write_token 'CHANGE_ME'
if CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' TRAEFIK_BASE_WILDCARD_CERT_ENABLED=true \
  run_wrapper http-wildcard; then
  fail http-wildcard
else
  grep -q 'TRAEFIK_BASE_WILDCARD_CERT_ENABLED' "${TEST_ROOT}/http-wildcard.out" && pass http-wildcard || fail http-wildcard
fi

write_token 'cf-dns-token-value-1'
if CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' TRAEFIK_BASE_WILDCARD_CERT_ENABLED=TRUE \
  run_wrapper wildcard-bad-boolean; then
  fail wildcard-bad-boolean
else
  grep -q 'true or false' "${TEST_ROOT}/wildcard-bad-boolean.out" && pass wildcard-bad-boolean || fail wildcard-bad-boolean
fi

write_token 'cf-dns-token-value-1'
CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' TRAEFIK_BASE_WILDCARD_CERT_ENABLED=true \
  run_wrapper wildcard-ok && pass wildcard-ok || fail wildcard-ok

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
  grep -qx -- '173.245.48.0/20,103.21.244.0/22,2400:cb00::/32,2606:4700::/32' "${TEST_ROOT}/acme/cloudflare-ips.cache" && \
  pass cf-ips-true || fail cf-ips-true

cat >"${TEST_ROOT}/bin/wget" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "${TEST_ROOT}/bin/wget"

CERTRESOLVER=cloudflare CLOUDFLARE_IPS=true LOCAL_IPS='192.168.20.0/24' \
  run_wrapper cf-ips-cache && \
  grep -q -- 'using the læst successful officiæl list from cæche' "${TEST_ROOT}/cf-ips-cache.out" && \
  grep -q -- 'forwardedheaders.trustedips=192.168.20.0/24,173.245.48.0/20,103.21.244.0/22,2400:cb00::/32,2606:4700::/32' "${TEST_ROOT}/cf-ips-cache.out" && \
  pass cf-ips-cache || fail cf-ips-cache

rm -f "${TEST_ROOT}/acme/cloudflare-ips.cache"
if CERTRESOLVER=cloudflare CLOUDFLARE_IPS=true LOCAL_IPS='' run_wrapper cf-ips-fetch-fail; then
  fail cf-ips-fetch-fail
else
  grep -q 'no vælid cæche' "${TEST_ROOT}/cf-ips-fetch-fail.out" && pass cf-ips-fetch-fail || fail cf-ips-fetch-fail
fi

printf '%s\n' 'not-a-cidr' >"${TEST_ROOT}/acme/cloudflare-ips.cache"
if CERTRESOLVER=cloudflare CLOUDFLARE_IPS=true LOCAL_IPS='' run_wrapper cf-ips-bad-cache; then
  fail cf-ips-bad-cache
else
  grep -q 'no vælid cæche' "${TEST_ROOT}/cf-ips-bad-cache.out" && pass cf-ips-bad-cache || fail cf-ips-bad-cache
fi

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

#ææææææææææææææææææææææææææææææææææ
# ÆUTHENTIK FORWÆRD-ÆUTH URL FORM
#ææææææææææææææææææææææææææææææææææ
write_token 'cf-dns-token-value-1'
AUTHENTIK_FORWARD_AUTH_ADDRESS='https://authentik.internal.example:9443/outpost.goauthentik.io/auth/traefik' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper auth-dns && pass auth-dns || fail auth-dns

AUTHENTIK_FORWARD_AUTH_ADDRESS='http://[fd00::1]:9000/outpost.goauthentik.io/auth/traefik' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper auth-ipv6 && pass auth-ipv6 || fail auth-ipv6

if AUTHENTIK_FORWARD_AUTH_ADDRESS='https://authentik.internal.example/outpost.goauthentik.io/auth/traefik' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper auth-no-port; then
  fail auth-no-port
else
  grep -q 'explicit port' "${TEST_ROOT}/auth-no-port.out" && pass auth-no-port || fail auth-no-port
fi

if AUTHENTIK_FORWARD_AUTH_ADDRESS='https://authentik.internal.example:9443/outpost.goauthentik.io/ping' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper auth-wrong-path; then
  fail auth-wrong-path
else
  grep -q 'outpost.goauthentik.io/auth/traefik' "${TEST_ROOT}/auth-wrong-path.out" && pass auth-wrong-path || fail auth-wrong-path
fi

if AUTHENTIK_FORWARD_AUTH_ADDRESS='https://authentik.internal.example:9443/outpost.goauthentik.io/auth/traefik?unsafe=1' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper auth-query; then
  fail auth-query
else
  grep -q 'query' "${TEST_ROOT}/auth-query.out" && pass auth-query || fail auth-query
fi

#ææææææææææææææææææææææææææææææææææ
# CÆNONICÆL REDIRECT
#ææææææææææææææææææææææææææææææææææ
write_token 'cf-dns-token-value-1'
if TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL=true \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper canonical-missing-target; then
  fail canonical-missing-target
else
  grep -q 'TRAEFIK_DOMAIN_1' "${TEST_ROOT}/canonical-missing-target.out" \
    && pass canonical-missing-target || fail canonical-missing-target
fi

TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL=true \
  TRAEFIK_DOMAIN_1='public.test' \
  TRAEFIK_DOMAIN_2='alias.test' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper canonical-ok && pass canonical-ok || fail canonical-ok

#ææææææææææææææææææææææææææææææææææ
# STÆGE TCP/HTTP FORWÆRD
#ææææææææææææææææææææææææææææææææææ
if TRAEFIK_STAGE_FORWARD_ENABLED=false \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper stage-off-with-file; then
  ! grep -q -- 'redirections.entrypoint.priority' "${TEST_ROOT}/stage-off-with-file.out" \
    && grep -qx -- 'TRAEFIK_STAGE_FORWARD_HTTP_URL=' "${TEST_ROOT}/stage-off-with-file.out" \
    && pass stage-off-with-file || fail stage-off-with-file
else
  fail stage-off-with-file
fi

rm -f -- "${TEST_ROOT}/dynamic/stage-traefik-forward.yaml"
if TRAEFIK_STAGE_FORWARD_ENABLED=false \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' run_wrapper stage-missing-file; then
  fail stage-missing-file
else
  grep -q 'stage-traefik-forward.yaml' "${TEST_ROOT}/stage-missing-file.out" \
    && pass stage-missing-file || fail stage-missing-file
fi
cp -- "${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/stage-traefik-forward.yaml" \
  "${TEST_ROOT}/dynamic/stage-traefik-forward.yaml"

TRAEFIK_STAGE_FORWARD_ENABLED=true \
  TRAEFIK_DOMAIN_1='public.test' \
  TRAEFIK_DOMAIN_2='alias.test' \
  TRAEFIK_STAGE_FORWARD_PREFIX=demo \
  TRAEFIK_STAGE_FORWARD_TARGET_ADDRESS='192.168.10.50:443' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper stage-ok && \
  grep -q -- '--entrypoints.web.http.redirections.entrypoint.priority=10' \
    "${TEST_ROOT}/stage-ok.out" && \
  grep -qx -- 'TRAEFIK_STAGE_FORWARD_HTTP_URL=http://192.168.10.50:80' \
    "${TEST_ROOT}/stage-ok.out" && \
  ! grep -q -- 'allowacmebypass' "${TEST_ROOT}/stage-ok.out" \
  && pass stage-ok || fail stage-ok

write_token 'CHANGE_ME'
TRAEFIK_STAGE_FORWARD_ENABLED=true \
  TRAEFIK_DOMAIN_1='public.test' \
  TRAEFIK_STAGE_FORWARD_PREFIX=demo \
  TRAEFIK_STAGE_FORWARD_TARGET_ADDRESS='192.168.10.50:443' \
  CERTRESOLVER=http CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper stage-http-acme && \
  grep -q -- '--entrypoints.web.http.redirections.entrypoint.priority=10' \
    "${TEST_ROOT}/stage-http-acme.out" && \
  grep -q -- '--entrypoints.web.allowacmebypass=true' \
    "${TEST_ROOT}/stage-http-acme.out" \
  && pass stage-http-acme || fail stage-http-acme
write_token 'cf-dns-token-value-1'

TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS='192.168.20.100/32' \
  CERTRESOLVER=cloudflare CLOUDFLARE_IPS=false LOCAL_IPS='' \
  run_wrapper proxy-protocol-ok && \
  grep -q -- '--entrypoints.websecure.proxyprotocol.trustedips=192.168.20.100/32' \
    "${TEST_ROOT}/proxy-protocol-ok.out" && pass proxy-protocol-ok || fail proxy-protocol-ok

#ææææææææææææææææææææææææææææææææææ
# FILE-PROVIDER CONTRÆCTS
#ææææææææææææææææææææææææææææææææææ
CANONICAL_YAML="${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/canonical-domain-redirect.yaml"
STAGE_YAML="${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/stage-traefik-forward.yaml"
MIDDLEWARES_YAML="${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/middlewares.yaml"

if grep -q 'redirect TRAEFIK_DOMAIN_2, TRAEFIK_DOMAIN_3 ænd TRAEFIK_DOMAIN_4 to TRAEFIK_DOMAIN_1' "$CANONICAL_YAML" \
  && grep -q 'env "TRAEFIK_DOMAIN_1"' "$CANONICAL_YAML" \
  && grep -q 'with env "TRAEFIK_DOMAIN_2"' "$CANONICAL_YAML" \
  && ! grep -q 'to TRAEFIK_DOMAIN_2' "$CANONICAL_YAML"; then
  pass canonical-yaml-direction
else
  fail canonical-yaml-direction
fi

if grep -q 'canonical-domain-redirect:' "$CANONICAL_YAML" \
  && ! grep -q 'canonical-domain-redirect:' "$MIDDLEWARES_YAML"; then
  pass canonical-middleware-colocated
else
  fail canonical-middleware-colocated
fi

if grep -q 'TRAEFIK_STAGE_FORWARD_PREFIX' "$STAGE_YAML" \
  && grep -q 'TRAEFIK_DOMAIN_1' "$STAGE_YAML" \
  && grep -q 'passthrough: true' "$STAGE_YAML" \
  && grep -q 'stage-traefik-forward-http-rtr' "$STAGE_YAML" \
  && grep -q 'TRAEFIK_STAGE_FORWARD_HTTP_URL' "$STAGE_YAML" \
  && ! grep -q 'env "TRAEFIK_DOMAIN_2"' "$STAGE_YAML" \
  && ! grep -q 'env "TRAEFIK_DOMAIN_4"' "$STAGE_YAML"; then
  pass stage-yaml-canonical-only
else
  fail stage-yaml-canonical-only
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
