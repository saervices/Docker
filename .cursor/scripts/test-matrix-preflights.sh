#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Docker-free Mætrix secret, SMTP, proxy, listener, ænd LiveKit regressions.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly REPO_ROOT
readonly SYNAPSE_HELPER="${REPO_ROOT}/templates/matrix-synapse/scripts/matrix-synapse-secret-reader.sh"
readonly MAS_HELPER="${REPO_ROOT}/templates/matrix-authentication-service/dockerfiles/matrix-mas-secret-reader.sh"
readonly POSTGRES_HELPER="${REPO_ROOT}/templates/matrix-postgres/scripts/matrix-postgres-secret-reader.sh"
readonly LIVEKIT_HELPER="${REPO_ROOT}/templates/matrix-livekit/scripts/matrix-livekit-secret-reader.sh"
readonly SYNAPSE_COMPOSE="${REPO_ROOT}/templates/matrix-synapse/docker-compose.matrix-synapse.yaml"
readonly MAS_COMPOSE="${REPO_ROOT}/templates/matrix-authentication-service/docker-compose.matrix-authentication-service.yaml"
readonly SYNAPSE_ENTRYPOINT="${REPO_ROOT}/templates/matrix-synapse/scripts/matrix-synapse-start.sh"
readonly MAS_ENTRYPOINT="${REPO_ROOT}/templates/matrix-authentication-service/dockerfiles/entrypoint.matrix-authentication-service.sh"
readonly POSTGRES_ENTRYPOINT="${REPO_ROOT}/templates/matrix-postgres/scripts/matrix-postgres-entrypoint.sh"
readonly LIVEKIT_ENTRYPOINT="${REPO_ROOT}/templates/matrix-livekit/scripts/matrix-livekit-start.sh"
readonly LIVEKIT_JWT_ENV="${REPO_ROOT}/templates/matrix-livekit-jwt/.env"
readonly LIVEKIT_JWT_COMPOSE="${REPO_ROOT}/templates/matrix-livekit-jwt/docker-compose.matrix-livekit-jwt.yaml"
readonly LIVEKIT_JWT_DOCKERFILE="${REPO_ROOT}/templates/matrix-livekit-jwt/dockerfiles/dockerfile.matrix-livekit-jwt"
readonly LIVEKIT_JWT_DOCKERIGNORE="${REPO_ROOT}/templates/matrix-livekit-jwt/dockerfiles/dockerfile.matrix-livekit-jwt.dockerignore"
readonly LIVEKIT_JWT_ENTRYPOINT="${REPO_ROOT}/templates/matrix-livekit-jwt/dockerfiles/entrypoint.matrix-livekit-jwt.go"
readonly LIVEKIT_JWT_ENTRYPOINT_TEST="${REPO_ROOT}/templates/matrix-livekit-jwt/dockerfiles/entrypoint.matrix-livekit-jwt_test.go"
readonly LIVEKIT_JWT_README="${REPO_ROOT}/templates/matrix-livekit-jwt/README.md"
readonly MATRIX_ROUTE_TEMPLATE="${REPO_ROOT}/Traefik/appdata/config/conf.d/matrix.yaml.template"
readonly MATRIX_README="${REPO_ROOT}/Matrix/README.md"

tests_passed=0
tests_failed=0
TEST_TMP="$(mktemp -d /tmp/matrix-preflights.XXXXXX)"
readonly TEST_TMP
TEST_TMP_IDENTITY="$(LC_ALL=C stat -Lc '%d:%i' -- "${TEST_TMP}")"
readonly TEST_TMP_IDENTITY
TEST_TMP_PARENT_IDENTITY="$(LC_ALL=C stat -Lc '%d:%i' -- /tmp)"
readonly TEST_TMP_PARENT_IDENTITY

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the identity-pinned privæte test directory.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local current_parent current_tmp
  current_parent="$(LC_ALL=C stat -Lc '%d:%i' -- /tmp 2>/dev/null || true)"
  current_tmp="$(LC_ALL=C stat -Lc '%d:%i' -- "${TEST_TMP}" 2>/dev/null || true)"
  if [[ "${current_parent}" != "${TEST_TMP_PARENT_IDENTITY}" || "${current_tmp}" != "${TEST_TMP_IDENTITY}" || -L "${TEST_TMP}" ]]; then
    printf '[WARN]  matrix-preflights: preserving drifted test directory %s\n' "${TEST_TMP}" >&2
    return
  fi
  find -P "${TEST_TMP}" -depth -mindepth 1 -delete
  rmdir -- "${TEST_TMP}"
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_success
#   Records one command thæt must return zero.
#   Ærguments:
#     $1 - test næme
#     $2... - command ænd ærguments
#ææææææææææææææææææææææææææææææææææ
expect_success() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    tests_passed=$((tests_passed + 1))
    printf '[PASS] %s\n' "${name}"
  else
    tests_failed=$((tests_failed + 1))
    printf '[FAIL] %s\n' "${name}" >&2
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_failure
#   Records one command thæt must return non-zero.
#   Ærguments:
#     $1 - test næme
#     $2... - command ænd ærguments
#ææææææææææææææææææææææææææææææææææ
expect_failure() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    tests_failed=$((tests_failed + 1))
    printf '[FAIL] %s unexpectedly succeeded\n' "${name}" >&2
  else
    tests_passed=$((tests_passed + 1))
    printf '[PASS] %s\n' "${name}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: invoke_snapshot
#   Sources one production helper ænd invokes its reæl snapshot function.
#   Ærguments:
#     $1 - helper pæth
#     $2 - source pæth
#     $3 - destination pæth
#     $4 - byte policy
#ææææææææææææææææææææææææææææææææææ
invoke_snapshot() {
  local helper="$1" source_path="$2" destination_path="$3" policy="$4"
  (
    # shellcheck disable=SC1090
    source "${helper}"
    matrix_snapshot_secret "${source_path}" "${destination_path}" 4096 "${policy}"
  )
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_secret_matrix
#   Exercises positive ænd hostile inputs ægæinst one production helper.
#   Ærguments:
#     $1 - helper læbel
#     $2 - helper pæth
#ææææææææææææææææææææææææææææææææææ
run_secret_matrix() {
  local label="$1" helper="$2" case_dir source_path destination_path source_link hard_link
  case_dir="${TEST_TMP}/${label}"
  mkdir -m 0700 -- "${case_dir}"

  source_path="${case_dir}/source"
  destination_path="${case_dir}/snapshot"
  printf '%s' "Alpha#beta:quo'te\\path" > "${source_path}"
  expect_success "${label}: printable punctuation" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single
  expect_success "${label}: snapshot bytes preserved" cmp -s -- "${source_path}" "${destination_path}"
  expect_success "${label}: snapshot mode 0400" test "$(LC_ALL=C stat -c '%a' -- "${destination_path}")" = 400

  rm -f -- "${source_path}" "${destination_path}"
  printf '%s' CHANGE_ME > "${source_path}"
  expect_failure "${label}: placeholder rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  : > "${source_path}"
  expect_failure "${label}: empty rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  printf 'line-one\n' > "${source_path}"
  expect_failure "${label}: trailing newline rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  printf 'line-one\nline-two' > "${source_path}"
  expect_failure "${label}: multiline rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  printf 'tab\tbyte' > "${source_path}"
  expect_failure "${label}: control rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  printf 'invalid-\377' > "${source_path}"
  expect_failure "${label}: invalid UTF-8 rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  dd if=/dev/zero bs=4097 count=1 2>/dev/null | LC_ALL=C tr '\000' A > "${source_path}"
  expect_failure "${label}: oversized rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${destination_path}"
  printf '%s' regular-value > "${source_path}"
  source_link="${case_dir}/source-link"
  ln -s -- "${source_path}" "${source_link}"
  expect_failure "${label}: symlink rejected" invoke_snapshot "${helper}" "${source_link}" "${destination_path}" single

  rm -f -- "${source_link}" "${destination_path}"
  hard_link="${case_dir}/hard-link"
  ln -- "${source_path}" "${hard_link}"
  expect_failure "${label}: multi-link inode rejected" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single

  rm -f -- "${source_path}" "${hard_link}" "${destination_path}"
  mkfifo -- "${source_path}"
  expect_failure "${label}: FIFO rejected without blocking" invoke_snapshot "${helper}" "${source_path}" "${destination_path}" single
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_yaml_quote
#   Proves punctuation is inert inside the production YAML serializer.
#   Ærguments:
#     $1 - helper læbel
#     $2 - helper pæth
#ææææææææææææææææææææææææææææææææææ
test_yaml_quote() {
  local label="$1" helper="$2" actual expected
  expected="'Alpha#beta:quo''te\\path'"
  # shellcheck disable=SC1090
  source "${helper}"
  actual="$(matrix_yaml_squote "Alpha#beta:quo'te\\path")"
  [[ "${actual}" == "${expected}" ]]
}

#æææææææææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: test_synapse_openid_route
#   Proves only the exæct OpenID pæth is routed to the 8009 service.
#æææææææææææææææææææææææææææææææææææææææææææææææææ
test_synapse_openid_route() {
  local labels
  labels="$(yq -r '.services."matrix-synapse".labels[]' "${SYNAPSE_COMPOSE}")" || return 1
  # The Traefik backticks are deliberate literal syntax.
  # shellcheck disable=SC2016
  grep -Fq 'Path(`/_matrix/federation/v1/openid/userinfo`)' <<<"${labels}" || return 1
  grep -Fq 'matrix-synapse-openid-svc.loadbalancer.server.port=8009' <<<"${labels}"
}

#ææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: test_cross_host_route_contract
#   Proves the composite file-provider templæte ænd its documented fixed
#   host-prefix contræct remæin complete.
#ææææææææææææææææææææææææææææææææææææææææææ
test_cross_host_route_contract() {
  local prefix route_domain origin_variable
  for prefix in element matrix auth call rtc; do
    for route_domain in TRAEFIK_ROUTE_DOMAIN TRAEFIK_ROUTE_DOMAIN_1 TRAEFIK_ROUTE_DOMAIN_2 TRAEFIK_ROUTE_DOMAIN_3 TRAEFIK_ROUTE_DOMAIN_4; do
      grep -Fq -- "${prefix}.{{env \"${route_domain}\"}}" "${MATRIX_ROUTE_TEMPLATE}" || return 1
    done
  done
  for origin_variable in \
    MATRIX_ELEMENT_WEB_ORIGIN_PORT \
    MATRIX_SYNAPSE_ORIGIN_PORT \
    MATRIX_MAS_ORIGIN_PORT \
    MATRIX_ELEMENT_CALL_ORIGIN_PORT \
    MATRIX_LIVEKIT_ORIGIN_PORT \
    MATRIX_LIVEKIT_JWT_ORIGIN_PORT \
    MATRIX_SYNAPSE_OPENID_ORIGIN_PORT; do
    grep -Fq -- "<${origin_variable}>" "${MATRIX_ROUTE_TEMPLATE}" || return 1
  done
  grep -Fq -- 'MATRIX_SERVER_NAME` must equæl Træefik' "${MATRIX_README}" || return 1
  grep -Fq -- 'service hosts must be `element.`, `matrix.`, `auth.`, `call.`, ænd `rtc.`' "${MATRIX_README}"
}

#ææææææææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: test_cross_host_exact_discovery_routes
#   Proves the edge exposes only the required exæct discovery ænd OpenID
#   pæths through their dedicæted high-priority routers.
#ææææææææææææææææææææææææææææææææææææææææææææææææ
test_cross_host_exact_discovery_routes() {
  grep -Fq -- 'Path(`/.well-known/matrix/client`)' "${MATRIX_ROUTE_TEMPLATE}" || return 1
  grep -Fq -- 'Path(`/.well-known/matrix/server`)' "${MATRIX_ROUTE_TEMPLATE}" || return 1
  grep -Fq -- 'Path(`/_matrix/federation/v1/openid/userinfo`)' "${MATRIX_ROUTE_TEMPLATE}" || return 1
  ! grep -Fq -- 'PathPrefix(`/.well-known/matrix`)' "${MATRIX_ROUTE_TEMPLATE}"
}

#æææææææææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: test_livekit_jwt_builder_contract
#   Proves the moving vendor ænd Go imæges ære refreshed, wired only through
#   build ærguments, ænd documented with their exæct defaults.
#æææææææææææææææææææææææææææææææææææææææææææææææææ
test_livekit_jwt_builder_contract() {
  grep -Eq '^MATRIX_LIVEKIT_JWT_IMAGE=ghcr\.io/element-hq/lk-jwt-service:latest[[:space:]]+#' "${LIVEKIT_JWT_ENV}" || return 1
  grep -Eq '^MATRIX_LIVEKIT_JWT_BUILD_IMAGE=golang:alpine[[:space:]]+#' "${LIVEKIT_JWT_ENV}" || return 1
  yq -e '
    .services."matrix-livekit-jwt".pull_policy == "build" and
    .services."matrix-livekit-jwt".build.pull == true and
    .services."matrix-livekit-jwt".build.no_cache == true and
    .services."matrix-livekit-jwt".build.args.MATRIX_LIVEKIT_JWT_IMAGE == "${MATRIX_LIVEKIT_JWT_IMAGE:?Image required}" and
    .services."matrix-livekit-jwt".build.args.MATRIX_LIVEKIT_JWT_BUILD_IMAGE == "${MATRIX_LIVEKIT_JWT_BUILD_IMAGE:-golang:alpine}"
  ' "${LIVEKIT_JWT_COMPOSE}" >/dev/null || return 1
  grep -Fxq 'ARG MATRIX_LIVEKIT_JWT_IMAGE=ghcr.io/element-hq/lk-jwt-service:latest' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fxq 'ARG MATRIX_LIVEKIT_JWT_BUILD_IMAGE=golang:alpine' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fxq 'FROM ${MATRIX_LIVEKIT_JWT_IMAGE}' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fxq 'FROM ${MATRIX_LIVEKIT_JWT_BUILD_IMAGE} AS builder' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fq '`ghcr.io/element-hq/lk-jwt-service:latest`' "${LIVEKIT_JWT_README}" || return 1
  grep -Fq '`golang:alpine`' "${LIVEKIT_JWT_README}" || return 1
  test_livekit_jwt_supervisor_contract
}

#æææææææææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: test_livekit_jwt_supervisor_contract
#   Proves the scrætch imæge uses the tested stætic PID-1 supervisor ænd
#   preserves the vendor CMD æs its supervised child.
#æææææææææææææææææææææææææææææææææææææææææææææææææ
test_livekit_jwt_supervisor_contract() {
  [[ -f "${LIVEKIT_JWT_ENTRYPOINT}" && ! -L "${LIVEKIT_JWT_ENTRYPOINT}" ]] || return 1
  [[ -f "${LIVEKIT_JWT_ENTRYPOINT_TEST}" && ! -L "${LIVEKIT_JWT_ENTRYPOINT_TEST}" ]] || return 1
  yq -e '.services."matrix-livekit-jwt".init == false' "${LIVEKIT_JWT_COMPOSE}" >/dev/null || return 1
  grep -Fxq 'ENTRYPOINT ["/lk-jwt-service-entrypoint"]' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fxq 'CMD ["/lk-jwt-service"]' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fq 'CGO_ENABLED=0 go test -count=1 ./...' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fq 'entrypoint.matrix-livekit-jwt.go ./entrypoint/main.go' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fq 'entrypoint.matrix-livekit-jwt_test.go ./entrypoint/main_test.go' "${LIVEKIT_JWT_DOCKERFILE}" || return 1
  grep -Fxq '!entrypoint.matrix-livekit-jwt.go' "${LIVEKIT_JWT_DOCKERIGNORE}" || return 1
  grep -Fxq '!entrypoint.matrix-livekit-jwt_test.go' "${LIVEKIT_JWT_DOCKERIGNORE}" || return 1
  grep -Fq 'The locæl supervisor runs æs PID 1 (`init: false`)' "${LIVEKIT_JWT_README}" || return 1
  grep -Fq 'vendor `/lk-jwt-service` CMD' "${LIVEKIT_JWT_README}" || return 1
  grep -Fq 'docker compose --env-file .env -f docker-compose.main.yaml stop -t 30 matrix-livekit-jwt' "${LIVEKIT_JWT_README}"
}

#æææææææææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: service_has_secret
#   Returns success only when one service mounts the named secret.
#   Ærguments:
#     $1 - compose file
#     $2 - service name
#     $3 - secret name
#æææææææææææææææææææææææææææææææææææææææææææææææææ
service_has_secret() {
  local compose_file="$1" service_name="$2" secret_name="$3"
  yq -r ".services.\"${service_name}\".secrets[]" "${compose_file}" | grep -Fxq -- "${secret_name}"
}

#æææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: test_mas_pem
#   Proves valid, encrypted, duplicated, ænd mælformed PEM behæviour.
#æææææææææææææææææææææææææææææææææææææææææææ
test_mas_pem() {
  local pem_dir="${TEST_TMP}/pem" source_path snapshot encrypted duplicated
  mkdir -m 0700 -- "${pem_dir}"
  source_path="${pem_dir}/rsa.pem"
  snapshot="${pem_dir}/snapshot.pem"
  encrypted="${pem_dir}/encrypted.pem"
  duplicated="${pem_dir}/duplicated.pem"
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${source_path}" >/dev/null 2>&1
  # shellcheck source=/dev/null
  source "${MAS_HELPER}"
  matrix_snapshot_secret "${source_path}" "${snapshot}" 32768 pem
  matrix_require_rsa_private_key "${snapshot}"
  openssl genpkey -algorithm RSA -aes-256-cbc -pass pass:test-only -pkeyopt rsa_keygen_bits:2048 -out "${encrypted}" >/dev/null 2>&1
  if matrix_require_rsa_private_key "${encrypted}"; then return 1; fi
  printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'ZmFrZQ==' '-----END PRIVATE KEY-----' > "${duplicated}"
  if matrix_require_rsa_private_key "${duplicated}"; then return 1; fi
}

#ææææææææææææææææææææææææææææææææææææææææææ
# FUNCTION: invoke_proxy_case
#   Loads the production proxy functions ænd checks one CIDR set.
#   Ærguments:
#     $1 - expected result: success or failure
#     $2... - CIDRs
#ææææææææææææææææææææææææææææææææææææææææææ
invoke_proxy_case() {
  local expectation="$1"
  shift
  (
    # The sourced production functions invoke this test stub.
    # shellcheck disable=SC2329
    log_fatal() { exit 91; }
    # shellcheck source=/dev/null
    source "${TEST_TMP}/proxy-functions.sh"
    for proxy_cidr in "$@"; do add_trusted_proxy_cidr "${proxy_cidr}"; done
    reject_overlapping_cidrs
  )
  local status=$?
  if [[ "${expectation}" == success ]]; then [[ "${status}" == 0 ]]; else [[ "${status}" != 0 ]]; fi
}

run_secret_matrix synapse "${SYNAPSE_HELPER}"
run_secret_matrix mas "${MAS_HELPER}"
run_secret_matrix postgres "${POSTGRES_HELPER}"
run_secret_matrix livekit "${LIVEKIT_HELPER}"

expect_success 'Synapse: YAML punctuation escaped' test_yaml_quote synapse "${SYNAPSE_HELPER}"
expect_success 'MAS: YAML punctuation escaped' test_yaml_quote mas "${MAS_HELPER}"
expect_success 'LiveKit: YAML punctuation escaped' test_yaml_quote livekit "${LIVEKIT_HELPER}"
expect_success 'MAS: PEM contract' test_mas_pem

awk '
  /^# --- Trusted proxy CIDR vælidætion$/ { capture = 1; next }
  /^# --- Preflight: domæins ænd endpoints$/ { exit }
  capture { print }
' "${MAS_ENTRYPOINT}" > "${TEST_TMP}/proxy-functions.sh"

expect_success 'MAS proxy: private Docker subnet plus cross-host /32' invoke_proxy_case success 172.20.0.0/24 10.23.45.67/32
expect_success 'MAS proxy: private 192.168 subnet' invoke_proxy_case success 192.168.44.0/24
for rejected_cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/15 8.8.8.8/32 100.64.0.0/16 192.0.2.0/24 198.18.0.0/16 169.254.0.0/16 224.0.0.0/16 0.0.0.0/32 255.255.255.255/32 127.0.0.0/16 10.1.2.1/24 010.1.0.0/16; do
  expect_success "MAS proxy rejects ${rejected_cidr}" invoke_proxy_case failure "${rejected_cidr}"
done
expect_success 'MAS proxy rejects duplicate entries' invoke_proxy_case failure 10.1.0.0/16 10.1.0.0/16
expect_success 'MAS proxy rejects overlap' invoke_proxy_case failure 10.1.0.0/16 10.1.2.0/24

expect_success 'Synapse SMTP top-level declaration remains available' yq -e '.secrets.MATRIX_SYNAPSE_SMTP_PASSWORD.file' "${SYNAPSE_COMPOSE}"
expect_success 'MAS SMTP top-level declaration remains available' yq -e '.secrets.MATRIX_MAS_SMTP_PASSWORD.file' "${MAS_COMPOSE}"
expect_failure 'Synapse disabled service has no SMTP mount' service_has_secret "${SYNAPSE_COMPOSE}" matrix-synapse MATRIX_SYNAPSE_SMTP_PASSWORD
expect_failure 'MAS disabled service has no SMTP mount' service_has_secret "${MAS_COMPOSE}" matrix-authentication-service MATRIX_MAS_SMTP_PASSWORD
expect_success 'Synapse has explicit SMTP activation line' grep -Fq '# - MATRIX_SYNAPSE_SMTP_PASSWORD' "${SYNAPSE_COMPOSE}"
expect_success 'MAS has explicit SMTP activation line' grep -Fq '# - MATRIX_MAS_SMTP_PASSWORD' "${MAS_COMPOSE}"
expect_success 'Synapse rejects stale disabled SMTP mount' grep -Fq 'must not be mounted while SMTP is disabled' "${SYNAPSE_ENTRYPOINT}"
expect_success 'MAS rejects stale disabled SMTP mount' grep -Fq 'must not be mounted while SMTP is disabled' "${MAS_ENTRYPOINT}"

expect_success 'PostgreSQL stages Synapse password from validated descriptor' grep -Fq 'matrix_snapshot_secret /run/secrets/MATRIX_POSTGRES_PASSWORD' "${POSTGRES_ENTRYPOINT}"
expect_success 'PostgreSQL stages MAS password from validated descriptor' grep -Fq 'matrix_snapshot_secret /run/secrets/MATRIX_MAS_POSTGRES_PASSWORD' "${POSTGRES_ENTRYPOINT}"
expect_failure 'PostgreSQL no longer installs directly from a secret path' grep -Fq 'install -m 0400 /run/secrets/' "${POSTGRES_ENTRYPOINT}"
expect_success 'PostgreSQL init consumes the pinned inherited descriptor' grep -Fq "FROM '/proc/self/fd/9'" "${REPO_ROOT}/templates/matrix-postgres/scripts/matrix-postgres-init.sh"
expect_failure 'PostgreSQL init never places the MAS password in psql argv' grep -Fq -- '-v mas_password=' "${REPO_ROOT}/templates/matrix-postgres/scripts/matrix-postgres-init.sh"

expect_success 'LiveKit disables automatic room creation' grep -Fq "printf '  auto_create: false\\n'" "${LIVEKIT_ENTRYPOINT}"
expect_success 'LiveKit renders the internal JWT webhook' grep -Fq 'matrix-livekit-jwt:8080/sfu_webhook' "${LIVEKIT_ENTRYPOINT}"
expect_success 'LiveKit webhook key follows MATRIX_LIVEKIT_KEY' grep -Fq "printf '  api_key: %s\\n'" "${LIVEKIT_ENTRYPOINT}"
expect_success 'Synapse defaults public listener to client-only' grep -Fq "public_listener_resources='[client]'" "${SYNAPSE_ENTRYPOINT}"
expect_success 'Synapse renders dedicated federation listener 8009' grep -Fq '  - port: 8009' "${SYNAPSE_ENTRYPOINT}"
expect_success 'Synapse exact OpenID route targets 8009 service' test_synapse_openid_route
expect_success 'Cross-host route template keeps every fixed host and origin' test_cross_host_route_contract
expect_success 'Cross-host discovery and OpenID routes stay exact' test_cross_host_exact_discovery_routes
expect_success 'LiveKit JWT moving builder contract stays complete' test_livekit_jwt_builder_contract
expect_success 'LiveKit JWT PID-1 supervisor contract stays complete' test_livekit_jwt_supervisor_contract
expect_success 'Synapse delegates server well-known to the edge' grep -Fq 'serve_server_wellknown: false' "${SYNAPSE_ENTRYPOINT}"
expect_success 'Synapse apex route serves only client well-known' grep -Fq "Path(\`/.well-known/matrix/client\`)" "${SYNAPSE_COMPOSE}"
expect_failure 'Synapse apex route has no broad well-known prefix' grep -Fq "PathPrefix(\`/.well-known/matrix\`)" "${SYNAPSE_COMPOSE}"
expect_success 'MAS origin supports reviewed cross-host bind IP' grep -Fq "\${MATRIX_ORIGIN_BIND_IP:-127.0.0.1}:\${MATRIX_MAS_ORIGIN_PORT:-18082}:8080" "${MAS_COMPOSE}"

printf '[SUMMARY] matrix-preflights: %d passed, %d failed\n' "${tests_passed}" "${tests_failed}"
(( tests_failed == 0 ))
