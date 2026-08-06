#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
# shellcheck disable=SC2016 # Fixture scripts intentionally keep runtime variable references literal.
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly REPO_ROOT
readonly COMPOSE_FILE="${REPO_ROOT}/templates/crowdsec_agent/docker-compose.crowdsec_agent.yaml"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/crowdsec-agent-wrapper.XXXXXX")"
readonly TEST_ROOT
readonly RAW_ENTRYPOINT="${TEST_ROOT}/entrypoint.raw"
readonly RENDERED_ENTRYPOINT="${TEST_ROOT}/entrypoint.sh"
readonly VALIDATOR_SCRIPT="${TEST_ROOT}/validate-lapi-url.sh"
readonly TRANSFORM_SCRIPT="${TEST_ROOT}/render-vendor-start-script.sh"
readonly EXPECTED_ERROR='CrowdSec LÆPI URL is missing or invalid; expected http(s)://hostname, IPv4, or [IPv6] with an optional port and trailing slash.'
readonly EXPECTED_MARKER_ERROR="CrowdSec docker_start.sh must contain exactly one '## Install hub items' marker; refusing to start."

PASS=0
FAIL=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes the disposæble extracted-wrapper fixtures.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pass
#   Records one successful regression cæse.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled regression cæse without printing the tested URL.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_valid_url
#   Requires one URL to pæss silently.
#   Ærguments:
#     $1 - cæse næme
#     $2 - URL vælue
#ææææææææææææææææææææææææææææææææææ
expect_valid_url() {
  local name="$1"
  local url="$2"
  local output="${TEST_ROOT}/${name}.out"

  if LOCAL_API_URL="$url" /bin/bash "$VALIDATOR_SCRIPT" >"$output" 2>&1 \
    && [[ ! -s "$output" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_invalid_url
#   Requires one URL to fæil with the redæcted generic diægnostic.
#   Ærguments:
#     $1 - cæse næme
#     $2 - URL vælue
#ææææææææææææææææææææææææææææææææææ
expect_invalid_url() {
  local name="$1"
  local url="$2"
  local output="${TEST_ROOT}/${name}.out"
  local status

  set +e
  LOCAL_API_URL="$url" /bin/bash "$VALIDATOR_SCRIPT" >"$output" 2>&1
  status=$?
  set -e
  if (( status != 0 )) \
    && [[ "$(<"$output")" == "$EXPECTED_ERROR" ]] \
    && { [[ -z "$url" ]] || ! grep -Fq -- "$url" "$output"; }; then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_missing_url
#   Requires æn unset URL to fæil with the redæcted generic diægnostic.
#ææææææææææææææææææææææææææææææææææ
expect_missing_url() {
  local output="${TEST_ROOT}/missing-url.out"
  local status

  set +e
  env -u LOCAL_API_URL /bin/bash "$VALIDATOR_SCRIPT" >"$output" 2>&1
  status=$?
  set -e
  if (( status != 0 )) && [[ "$(<"$output")" == "$EXPECTED_ERROR" ]]; then
    pass missing-url
  else
    fail missing-url
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_transform_success
#   Proves the exæct vendor mærker injects the helper once before dæmon hændoff.
#ææææææææææææææææææææææææææææææææææ
expect_transform_success() {
  local fixture="${TEST_ROOT}/transform-valid"
  local event_log="${fixture}/events"
  local output="${fixture}/output"

  mkdir -p -- "$fixture"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''vendor-before\n'\'' >> "${EVENT_LOG:?}"' \
    '    ## Install hub items' \
    'printf '\''daemon-started\n'\'' >> "${EVENT_LOG:?}"' \
    >"${fixture}/docker_start.sh"
  printf '%s\n' 'printf '\''insertion\n'\'' >> "${EVENT_LOG:?}"' \
    >"${fixture}/insertion.sh"

  if EVENT_LOG="$event_log" /bin/bash "$TRANSFORM_SCRIPT" \
      "${fixture}/docker_start.sh" "${fixture}/insertion.sh" "$output" --execute \
      >"${fixture}/stderr" 2>&1 \
    && [[ "$(<"$event_log")" == $'vendor-before\ninsertion\ndaemon-started' ]] \
    && [[ "$(grep -Fxc -- 'printf '\''insertion\n'\'' >> "${EVENT_LOG:?}"' "$output")" -eq 1 ]] \
    && [[ ! -s "${fixture}/stderr" ]]; then
    pass vendor-marker-exactly-once
  else
    fail vendor-marker-exactly-once
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_transform_failure
#   Proves missing or duplicæte mærkers stop before output or dæmon hændoff.
#   Ærguments:
#     $1 - cæse næme
#     $2 - fixture body after the shebæng
#ææææææææææææææææææææææææææææææææææ
expect_transform_failure() {
  local name="$1"
  local body="$2"
  local fixture="${TEST_ROOT}/${name}"
  local output="${fixture}/output"
  local status

  mkdir -p -- "$fixture"
  printf '#!/usr/bin/env bash\n%s\n' "$body" >"${fixture}/docker_start.sh"
  printf '%s\n' 'printf '\''insertion\n'\'' >> "${EVENT_LOG:?}"' \
    >"${fixture}/insertion.sh"

  set +e
  EVENT_LOG="${fixture}/events" /bin/bash "$TRANSFORM_SCRIPT" \
    "${fixture}/docker_start.sh" "${fixture}/insertion.sh" "$output" --execute \
    >"${fixture}/stderr" 2>&1
  status=$?
  set -e

  if (( status != 0 )) \
    && [[ "$(<"${fixture}/stderr")" == "$EXPECTED_MARKER_ERROR" ]] \
    && [[ ! -e "$output" ]] \
    && [[ ! -e "${fixture}/events" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

command -v yq >/dev/null

yq -r '.services.crowdsec_agent.entrypoint[2]' "$COMPOSE_FILE" >"$RAW_ENTRYPOINT"
sed 's/\$\$/\$/g' "$RAW_ENTRYPOINT" >"$RENDERED_ENTRYPOINT"
awk '/^CONFIG=\/etc\/crowdsec\/config.yaml$/ { exit } { print }' \
  "$RENDERED_ENTRYPOINT" >"$VALIDATOR_SCRIPT"
printf 'set -euo pipefail\n\n' >"$TRANSFORM_SCRIPT"
awk '
  /^render_vendor_start_script\(\) \{$/ { copy = 1 }
  copy { print }
  copy && /^}$/ { exit }
' "$RENDERED_ENTRYPOINT" >>"$TRANSFORM_SCRIPT"
cat >>"$TRANSFORM_SCRIPT" <<'EOF'
render_vendor_start_script "$1" "$2" "$3"
if [[ "${4:-}" == --execute ]]; then
  exec /bin/bash "$3"
fi
EOF
chmod 0700 "$VALIDATOR_SCRIPT"
chmod 0700 "$TRANSFORM_SCRIPT"

if [[ -s "$VALIDATOR_SCRIPT" ]] \
  && grep -Fq 'if ! validate_lapi_url "${LOCAL_API_URL:-}"; then' "$VALIDATOR_SCRIPT" \
  && ! grep -Eq '(^|[[:space:]])(cat|cp|mkdir|rm|sed|yq)([[:space:]]|$)' "$VALIDATOR_SCRIPT" \
  && /bin/bash -n "$VALIDATOR_SCRIPT"; then
  pass validation-before-mutation
else
  fail validation-before-mutation
fi

if [[ "$(yq -r '.services.crowdsec_agent.healthcheck.test[0]' "$COMPOSE_FILE")" == CMD-SHELL \
  && "$(yq -r '.services.crowdsec_agent.healthcheck.test[1]' "$COMPOSE_FILE")" == 'cscli lapi status > /dev/null 2>&1' \
  && "$(yq -r '.services.crowdsec_agent.healthcheck.interval' "$COMPOSE_FILE")" == 30s \
  && "$(yq -r '.services.crowdsec_agent.healthcheck.timeout' "$COMPOSE_FILE")" == 10s \
  && "$(yq -r '.services.crowdsec_agent.healthcheck.retries' "$COMPOSE_FILE")" == 3 \
  && "$(yq -r '.services.crowdsec_agent.healthcheck.start_period' "$COMPOSE_FILE")" == 2m ]]; then
  pass lapi-healthcheck-contract
else
  fail lapi-healthcheck-contract
fi

if [[ -s "$TRANSFORM_SCRIPT" ]] \
  && grep -Fq '[[ "${vendor_line}" =~ ^[[:space:]]*##\ Install\ hub\ items[[:space:]]*$ ]]' "$TRANSFORM_SCRIPT" \
  && grep -Fq 'if (( marker_count != 1 )); then' "$TRANSFORM_SCRIPT" \
  && /bin/bash -n "$TRANSFORM_SCRIPT"; then
  pass vendor-transform-contract
else
  fail vendor-transform-contract
fi

expect_transform_success
expect_transform_failure vendor-marker-missing \
  'printf '\''daemon-started\n'\'' >> "${EVENT_LOG:?}"'
expect_transform_failure vendor-marker-duplicated \
  $'## Install hub items\n    ## Install hub items\nprintf '\''daemon-started\\n'\'' >> "${EVENT_LOG:?}"'

expect_valid_url hostname-http 'http://lapi'
expect_valid_url hostname-https 'https://lapi.example.com'
expect_valid_url mixed-case-scheme 'HtTpS://lapi.example.com:443/'
expect_valid_url ipv4-port 'http://192.168.20.1:8080'
expect_valid_url max-port-trailing-slash 'https://example.com:65535/'
expect_valid_url ipv6-loopback 'http://[::1]'
expect_valid_url ipv6-port 'https://[2001:db8::1]:8080/'
expect_valid_url ipv6-embedded-ipv4 'http://[::ffff:192.0.2.1]:80'
expect_valid_url punycode-hostname 'https://xn--bcher-kva.example'

expect_missing_url
expect_invalid_url empty-url ''
expect_invalid_url placeholder-host 'http://CHANGE_ME:8080'
expect_invalid_url embedded-placeholder 'https://lapi.CHANGE_ME.example'
expect_invalid_url unsupported-scheme 'ftp://lapi.example.com'
expect_invalid_url credentials 'https://user:pass@lapi.example.com'
expect_invalid_url path 'https://lapi.example.com/v1'
expect_invalid_url query 'https://lapi.example.com?ready=true'
expect_invalid_url fragment 'https://lapi.example.com#ready'
expect_invalid_url invalid-ipv4 'http://256.1.1.1:8080'
expect_invalid_url abbreviated-ipv4 'http://192.168.1'
expect_invalid_url zero-padded-ipv4 'http://192.168.001.1'
expect_invalid_url trailing-ipv4-separator 'http://192.168.1.1.'
expect_invalid_url raw-ipv6 'http://2001:db8::1'
expect_invalid_url malformed-ipv6 'http://[2001:::1]:8080'
expect_invalid_url oversized-ipv6 'http://[1:2:3:4:5:6:7:8:9]'
expect_invalid_url port-zero 'http://lapi.example.com:0'
expect_invalid_url port-too-large 'http://lapi.example.com:65536'
expect_invalid_url port-alpha 'http://lapi.example.com:http'
expect_invalid_url empty-port 'http://lapi.example.com:'
expect_invalid_url leading-hyphen 'http://-lapi.example.com'
expect_invalid_url underscore-hostname 'http://lapi_internal.example.com'
expect_invalid_url empty-hostname-label 'http://lapi..example.com'
expect_invalid_url extra-trailing-slash 'http://lapi.example.com//'
expect_invalid_url whitespace 'http://lapi.example.com:8080 '

printf '\nCrowdSec ægent wræpper tests: %d pæssed, %d fæiled\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
