#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly IMMICH_PARSER_FILE="${REPO_ROOT}/templates/crowdsec_agent/appdata/crowdsec_agent/config/parsers/s02-enrich/immich-thumbnail-whitelist.yaml"
readonly SEAFILE_PARSER_FILE="${REPO_ROOT}/templates/crowdsec_agent/appdata/crowdsec_agent/config/parsers/s02-enrich/seafile-sync-whitelist.yaml"
readonly CROWDSEC_IMAGE="${CROWDSEC_TEST_IMAGE:-crowdsecurity/crowdsec:latest}"
readonly IMMICH_HOST="immich.it.xn--srvices-mxa.de"
readonly IMMICH_UUID="123e4567-e89b-12d3-a456-426614174000"
readonly IMMICH_WHITELIST_REASON="legitimate Immich edited-thumbnail request"
readonly SEAFILE_HOST="seafile.it.xn--srvices-mxa.de"
readonly SEAFILE_WHITELIST_REASON="legitimate Seafile sync traffic"
readonly RESET='\033[0m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'
readonly GREEN='\033[0;32m'
readonly CYAN='\033[0;36m'
readonly GREY='\033[1;30m'

DEBUG=false
DRY_RUN=false
TEST_ROOT=''
CONTAINER_ID=''
PASS=0
FAIL=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_line
#   Writes one structured messæge to the selected streæm ænd optionæl log file.
#   Ærguments:
#     $1 - level
#     $2 - color
#     $3 - output streæm
#     $4 - messæge
#ææææææææææææææææææææææææææææææææææ
log_line() {
  local level="$1"
  local color="$2"
  local stream="$3"
  local message="$4"

  if [[ "$stream" == stderr ]]; then
    printf '%b[%s]%b %s\n' "$color" "$level" "$RESET" "$message" >&2
  else
    printf '%b[%s]%b %s\n' "$color" "$level" "$RESET" "$message"
  fi
  if [[ -n "${LOGFILE:-}" ]]; then
    printf '[%s] %s\n' "$level" "$message" >>"$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  log_line OK "$GREEN" stdout "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_info() {
  log_line INFO "$CYAN" stdout "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ wærning messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  log_line WARN "$YELLOW" stderr "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æn error messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_error() {
  log_line ERROR "$RED" stderr "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   Logs æ debug messæge when requested.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_debug() {
  if [[ "$DEBUG" == true ]]; then
    log_line DEBUG "$GREY" stdout "$1"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ fætæl messæge ænd exits.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  log_error "$1"
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: show_help
#   Prints usæge informætion.
#ææææææææææææææææææææææææææææææææææ
show_help() {
  printf 'Usage: %s [--debug] [--dry-run] [-h|--help]\n' "$(basename -- "${BASH_SOURCE[0]}")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: parse_args
#   Pærses stændærd script flægs.
#   Ærguments:
#     $@ - commænd-line ærguments
#ææææææææææææææææææææææææææææææææææ
parse_args() {
  while (($# > 0)); do
    case "$1" in
      --debug)
        DEBUG=true
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -h | --help)
        show_help
        exit 0
        ;;
      *)
        log_fatal "Unknown option: $1"
        ;;
    esac
    shift
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only this test's exæct contæiner ænd temporæry fixture.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ -n "$CONTAINER_ID" ]]; then
    docker rm --force "$CONTAINER_ID" >/dev/null 2>&1 || true
    CONTAINER_ID=''
  fi
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    rm -rf -- "$TEST_ROOT"
    TEST_ROOT=''
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_signal
#   Cleæns the fixture ænd exits with the signæl-specific stætus.
#   Ærguments:
#     $1 - exit stætus
#ææææææææææææææææææææææææææææææææææ
handle_signal() {
  local status="$1"

  trap - EXIT HUP INT TERM
  cleanup
  exit "$status"
}

trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_command
#   Requires one host commænd.
#   Ærguments:
#     $1 - commænd næme
#ææææææææææææææææææææææææææææææææææ
require_command() {
  command -v "$1" >/dev/null 2>&1 || log_fatal "Required command not found: $1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_contract
#   Fæils closed when either nærrow locæl exception drifts.
#ææææææææææææææææææææææææææææææææææ
validate_source_contract() {
  [[ -f "$IMMICH_PARSER_FILE" && ! -L "$IMMICH_PARSER_FILE" ]] || log_fatal "Immich parser whitelist is missing or unsafe."
  grep -Fq "evt.Meta.target_fqdn == '${IMMICH_HOST}'" "$IMMICH_PARSER_FILE" || log_fatal "Immich host restriction is missing."
  grep -Fq "evt.Meta.http_verb == 'GET'" "$IMMICH_PARSER_FILE" || log_fatal "Immich GET restriction is missing."
  grep -Fq "evt.Meta.http_status == '404'" "$IMMICH_PARSER_FILE" || log_fatal "Immich 404 restriction is missing."
  grep -Fq "evt.Meta.http_path matches '^/api/assets/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/thumbnail$'" "$IMMICH_PARSER_FILE" || log_fatal "Exact Immich UUID thumbnail path restriction is missing."
  if grep -Eq 'source_ip|size=thumbnail|edited=true' "$IMMICH_PARSER_FILE"; then
    log_fatal "Immich whitelist must not contain IP or query-based exceptions."
  fi

  [[ -f "$SEAFILE_PARSER_FILE" && ! -L "$SEAFILE_PARSER_FILE" ]] || log_fatal "Seafile parser whitelist is missing or unsafe."
  grep -Fq "evt.Meta.target_fqdn == '${SEAFILE_HOST}'" "$SEAFILE_PARSER_FILE" || log_fatal "Seafile host restriction is missing."
  grep -Fq "evt.Meta.http_verb in ['GET', 'HEAD']" "$SEAFILE_PARSER_FILE" || log_fatal "Seafile method restriction is missing."
  grep -Fq "evt.Meta.http_status in ['200', '206', '304']" "$SEAFILE_PARSER_FILE" || log_fatal "Seafile status restriction is missing."
  grep -Fq "evt.Meta.http_path startsWith '/seafhttp/'" "$SEAFILE_PARSER_FILE" || log_fatal "Seafile transfer-path restriction is missing."
  grep -Fq "evt.Meta.http_path startsWith '/api/v2.1/events/'" "$SEAFILE_PARSER_FILE" || log_fatal "Seafile versioned-events restriction is missing."
  if grep -Eq 'source_ip|RequestPath|\?' "$SEAFILE_PARSER_FILE"; then
    log_fatal "Seafile whitelist must not contain IP, raw-field, or query-based exceptions."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: render_event
#   Renders one reælistic Træefik JSON æccess-log event.
#   Ærguments:
#     $1 - request host
#     $2 - request method
#     $3 - downstreæm stætus
#     $4 - queryless request pæth
#     $5 - client IP
#ææææææææææææææææææææææææææææææææææ
render_event() {
  local host="$1"
  local method="$2"
  local status="$3"
  local path="$4"
  local client_ip="$5"

  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || log_fatal "Unsafe fixture host."
  [[ "$method" =~ ^[A-Z]+$ ]] || log_fatal "Unsafe fixture method."
  [[ "$status" =~ ^[0-9]{3}$ ]] || log_fatal "Unsafe fixture status."
  [[ "$path" == /* && "$path" != *['"\\']* ]] || log_fatal "Unsafe fixture path."
  [[ "$client_ip" =~ ^[0-9.]+$ ]] || log_fatal "Unsafe fixture client IP."

  printf '{"ClientAddr":"%s:49152","ClientHost":"%s","ClientPort":"49152","ClientUsername":"-","DownstreamContentSize":0,"DownstreamStatus":%s,"Duration":1500000,"OriginContentSize":0,"OriginDuration":1400000,"OriginStatus":%s,"Overhead":100000,"RequestAddr":"%s","RequestContentSize":0,"RequestCount":42,"RequestHost":"%s","RequestMethod":"%s","RequestPath":"%s","RequestPort":"-","RequestProtocol":"HTTP/2.0","RequestScheme":"https","RetryAttempts":0,"RouterName":"immich@docker","ServiceAddr":"172.18.0.10:2283","ServiceName":"immich@docker","ServiceURL":"http://172.18.0.10:2283","StartLocal":"2026-08-06T12:00:00+02:00","StartUTC":"2026-08-06T10:00:00Z","TLSCipher":"TLS_AES_128_GCM_SHA256","TLSVersion":"1.3","entryPointName":"websecure","level":"info","msg":"","time":"2026-08-06T10:00:00Z"}\n' \
    "$client_ip" "$client_ip" "$status" "$status" "$host" "$host" "$method" "$path"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: record_pass
#   Records one successful regression cæse.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
record_pass() {
  PASS=$((PASS + 1))
  log_ok "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: record_fail
#   Records one fæiled regression cæse ænd prints bounded diægnostics.
#   Ærguments:
#     $1 - cæse næme
#     $2 - output file
#ææææææææææææææææææææææææææææææææææ
record_fail() {
  FAIL=$((FAIL + 1))
  log_error "$1"
  if [[ -f "$2" ]]; then
    sed -n '1,160p' "$2" >&2
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_runtime
#   Pulls ænd stærts one isolæted CrowdSec LÆPI/processor fixture.
#ææææææææææææææææææææææææææææææææææ
start_runtime() {
  log_info "Pulling current CrowdSec test image: ${CROWDSEC_IMAGE}"
  docker pull "$CROWDSEC_IMAGE" >/dev/null || log_fatal "Unable to pull the CrowdSec image."

  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/crowdsec-parser-whitelists.XXXXXX")"
  mkdir -p -- "${TEST_ROOT}/cases"

  CONTAINER_ID="$(
    docker run --detach --rm \
      --tmpfs /etc/crowdsec:rw,noexec,nosuid,nodev,mode=0700 \
      --tmpfs /var/lib/crowdsec/data:rw,noexec,nosuid,nodev,mode=0700 \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777 \
      --mount "type=bind,src=${IMMICH_PARSER_FILE},dst=/etc/crowdsec/parsers/s02-enrich/immich-thumbnail-whitelist.yaml,readonly" \
      --mount "type=bind,src=${SEAFILE_PARSER_FILE},dst=/etc/crowdsec/parsers/s02-enrich/seafile-sync-whitelist.yaml,readonly" \
      --mount "type=bind,src=${TEST_ROOT}/cases,dst=/test-cases,readonly" \
      --env COLLECTIONS=crowdsecurity/traefik \
      --env CUSTOM_HOSTNAME=crowdsec-parser-test \
      --env DISABLE_ONLINE_API=true \
      "$CROWDSEC_IMAGE"
  )" || log_fatal "Unable to start the CrowdSec parser fixture."
  [[ "$CONTAINER_ID" =~ ^[0-9a-f]{64}$ ]] || log_fatal "CrowdSec returned an invalid container ID."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_runtime
#   Wæits boundedly for locæl LÆPI æuthenticætion ænd collection loæding.
#ææææææææææææææææææææææææææææææææææ
wait_for_runtime() {
  local attempt
  local collection_state="${TEST_ROOT}/collection.json"

  for ((attempt = 1; attempt <= 60; attempt++)); do
    if docker exec "$CONTAINER_ID" cscli lapi status >/dev/null 2>&1; then
      if ! docker exec "$CONTAINER_ID" cscli --color no -o json collections inspect \
        crowdsecurity/traefik --no-metrics >"$collection_state" 2>&1 \
        || ! grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' "$collection_state"; then
        log_fatal "Traefik collection is not installed."
      fi
      log_debug "CrowdSec became ready after ${attempt} checks."
      return 0
    fi
    if ! docker inspect "$CONTAINER_ID" >/dev/null 2>&1; then
      log_error "CrowdSec parser fixture exited before readiness."
      docker logs "$CONTAINER_ID" >&2 || true
      return 1
    fi
    sleep 1
  done

  log_error "CrowdSec parser fixture did not become ready within 60 seconds."
  docker logs "$CONTAINER_ID" >&2 || true
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_allowed_matrix
#   Proves queryless legitimæte thumbnæils, including æ burst, ære fully whitelisted.
#ææææææææææææææææææææææææææææææææææ
run_allowed_matrix() {
  local burst_count=32
  local expected_count=$((burst_count + 2))
  local index
  local uuid
  local event_file="${TEST_ROOT}/cases/allowed-matrix.log"
  local output_file="${TEST_ROOT}/cases/allowed-matrix.out"
  local lines
  local parsers
  local matches

  : >"$event_file"
  render_event "$IMMICH_HOST" GET 404 "/api/assets/${IMMICH_UUID}/thumbnail" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 404 "/api/assets/${IMMICH_UUID}/thumbnail" 198.51.100.44 >>"$event_file"
  for ((index = 1; index <= burst_count; index++)); do
    printf -v uuid '123e4567-e89b-12d3-a456-%012x' "$index"
    render_event "$IMMICH_HOST" GET 404 "/api/assets/${uuid}/thumbnail" 203.0.113.10 >>"$event_file"
  done

  if ! docker exec "$CONTAINER_ID" cscli --color no explain \
    --file /test-cases/allowed-matrix.log --type traefik --only-successful-parsers \
    >"$output_file" 2>&1; then
    record_fail 'allowed-matrix: cscli explain failed' "$output_file"
    return
  fi

  lines="$(grep -c '^line: ' "$output_file" || true)"
  parsers="$(grep -Fc 'crowdsecurity/traefik-logs' "$output_file" || true)"
  matches="$(grep -Fc "ignored by whitelist (${IMMICH_WHITELIST_REASON})" "$output_file" || true)"
  if [[ "$lines" == "$expected_count" \
    && "$parsers" == "$expected_count" \
    && "$matches" == "$expected_count" ]] \
    && [[ "$(grep -Fc '[whitelisted]' "$output_file" || true)" == "$expected_count" ]] \
    && ! grep -Fq 'Scenarios' "$output_file"; then
    record_pass "allowed-matrix (${expected_count} events)"
  else
    record_fail "allowed-matrix: expected ${expected_count} narrow matches, got ${matches}" "$output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_inspected_matrix
#   Proves hosts, methods, stætuses, uploæds, generic pæths, ænd mælformed pæths remæin inspected.
#ææææææææææææææææææææææææææææææææææ
run_inspected_matrix() {
  local expected_count=10
  local event_file="${TEST_ROOT}/cases/inspected-matrix.log"
  local output_file="${TEST_ROOT}/cases/inspected-matrix.out"
  local lines
  local parsers
  local unchanged

  : >"$event_file"
  render_event example.invalid GET 404 "/api/assets/${IMMICH_UUID}/thumbnail" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" POST 404 "/api/assets/${IMMICH_UUID}/thumbnail" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 200 "/api/assets/${IMMICH_UUID}/thumbnail" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 401 "/api/assets/${IMMICH_UUID}/thumbnail" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" POST 201 /api/assets 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 404 /api/assets 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 404 "/api/assets/${IMMICH_UUID}" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 404 /api/assets/not-a-uuid/thumbnail 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 404 "/api/assets/${IMMICH_UUID}/thumbnail/original" 203.0.113.10 >>"$event_file"
  render_event "$IMMICH_HOST" GET 404 "/api/assets/${IMMICH_UUID}/thumbnail?size=thumbnail&edited=true" 203.0.113.10 >>"$event_file"

  if ! docker exec "$CONTAINER_ID" cscli --color no explain \
    --file /test-cases/inspected-matrix.log --type traefik --only-successful-parsers \
    >"$output_file" 2>&1; then
    record_fail 'inspected-matrix: cscli explain failed' "$output_file"
    return
  fi

  lines="$(grep -c '^line: ' "$output_file" || true)"
  parsers="$(grep -Fc 'crowdsecurity/traefik-logs' "$output_file" || true)"
  unchanged="$(grep -Fc 'local/immich-thumbnail-whitelist (unchanged)' "$output_file" || true)"
  if [[ "$lines" == "$expected_count" \
    && "$parsers" == "$expected_count" \
    && "$unchanged" == "$expected_count" ]] \
    && ! grep -Fq "ignored by whitelist (${IMMICH_WHITELIST_REASON})" "$output_file" \
    && ! grep -Fq '[whitelisted]' "$output_file"; then
    record_pass "inspected-matrix (${expected_count} events)"
  else
    record_fail "inspected-matrix: expected ${expected_count} fully inspected events" "$output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_seafile_allowed_matrix
#   Proves only reviewed successful Seæfile sync routes ære whitelisted.
#ææææææææææææææææææææææææææææææææææ
run_seafile_allowed_matrix() {
  local expected_count=10
  local event_file="${TEST_ROOT}/cases/seafile-allowed-matrix.log"
  local output_file="${TEST_ROOT}/cases/seafile-allowed-matrix.out"
  local lines
  local parsers
  local matches

  : >"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /seafhttp/repo-id/file-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" HEAD 206 /seafhttp/repo-id/file-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 304 /api2/repos 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /api2/repos/repo-id/file 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" HEAD 200 /api2/events 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 206 /api2/events/next 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /api/v2.1/repos 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" HEAD 304 /api/v2.1/repos/repo-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /api/v2.1/events 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 206 /api/v2.1/events/next 198.51.100.55 >>"$event_file"

  if ! docker exec "$CONTAINER_ID" cscli --color no explain \
    --file /test-cases/seafile-allowed-matrix.log --type traefik --only-successful-parsers \
    >"$output_file" 2>&1; then
    record_fail 'seafile-allowed-matrix: cscli explain failed' "$output_file"
    return
  fi

  lines="$(grep -c '^line: ' "$output_file" || true)"
  parsers="$(grep -Fc 'crowdsecurity/traefik-logs' "$output_file" || true)"
  matches="$(grep -Fc "ignored by whitelist (${SEAFILE_WHITELIST_REASON})" "$output_file" || true)"
  if [[ "$lines" == "$expected_count" \
    && "$parsers" == "$expected_count" \
    && "$matches" == "$expected_count" ]] \
    && [[ "$(grep -Fc '[whitelisted]' "$output_file" || true)" == "$expected_count" ]] \
    && ! grep -Fq 'Scenarios' "$output_file"; then
    record_pass "seafile-allowed-matrix (${expected_count} events)"
  else
    record_fail "seafile-allowed-matrix: expected ${expected_count} narrow matches, got ${matches}" "$output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_seafile_inspected_matrix
#   Proves neærby host, method, stætus, pæth, ænd query drifts stæy inspected.
#ææææææææææææææææææææææææææææææææææ
run_seafile_inspected_matrix() {
  local expected_count=7
  local event_file="${TEST_ROOT}/cases/seafile-inspected-matrix.log"
  local output_file="${TEST_ROOT}/cases/seafile-inspected-matrix.out"
  local lines
  local parsers
  local unchanged

  : >"$event_file"
  render_event example.invalid GET 200 /seafhttp/repo-id/file-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" POST 200 /seafhttp/repo-id/file-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 404 /seafhttp/repo-id/file-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /seafhttpx/repo-id/file-id 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /api2/repositories 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 /api/v2.1/repository 203.0.113.20 >>"$event_file"
  render_event "$SEAFILE_HOST" GET 200 '/api2/repos?cursor=must-not-be-persisted' 203.0.113.20 >>"$event_file"

  if ! docker exec "$CONTAINER_ID" cscli --color no explain \
    --file /test-cases/seafile-inspected-matrix.log --type traefik --only-successful-parsers \
    >"$output_file" 2>&1; then
    record_fail 'seafile-inspected-matrix: cscli explain failed' "$output_file"
    return
  fi

  lines="$(grep -c '^line: ' "$output_file" || true)"
  parsers="$(grep -Fc 'crowdsecurity/traefik-logs' "$output_file" || true)"
  unchanged="$(grep -Fc 'local/seafile-sync-whitelist (unchanged)' "$output_file" || true)"
  if [[ "$lines" == "$expected_count" \
    && "$parsers" == "$expected_count" \
    && "$unchanged" == "$expected_count" ]] \
    && ! grep -Fq "ignored by whitelist (${SEAFILE_WHITELIST_REASON})" "$output_file" \
    && ! grep -Fq '[whitelisted]' "$output_file"; then
    record_pass "seafile-inspected-matrix (${expected_count} events)"
  else
    record_fail "seafile-inspected-matrix: expected ${expected_count} fully inspected events" "$output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_seafile_malformed_case
#   Proves mælformed JSON cænnot reæch the Seæfile whitelist.
#ææææææææææææææææææææææææææææææææææ
run_seafile_malformed_case() {
  local event_file="${TEST_ROOT}/cases/seafile-malformed.log"
  local output_file="${TEST_ROOT}/cases/seafile-malformed.out"

  printf '{"RequestHost":"%s","RequestMethod":"GET","DownstreamStatus":200,"RequestPath":\n' \
    "$SEAFILE_HOST" >"$event_file"
  if ! docker exec "$CONTAINER_ID" cscli --color no explain \
    --file /test-cases/seafile-malformed.log --type traefik -v \
    >"$output_file" 2>&1; then
    record_fail 'seafile-malformed: cscli explain failed' "$output_file"
    return
  fi

  if grep -Fq 'crowdsecurity/traefik-logs' "$output_file" \
    && grep -Fq 'parser failure' "$output_file" \
    && ! grep -Fq "ignored by whitelist (${SEAFILE_WHITELIST_REASON})" "$output_file" \
    && ! grep -Fq '[whitelisted]' "$output_file"; then
    record_pass 'seafile-malformed: invalid JSON was not whitelisted'
  else
    record_fail 'seafile-malformed: invalid JSON reached the whitelist' "$output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Runs the stætic contræct ænd reæl CrowdSec pærser regression mætrix.
#   Ærguments:
#     $@ - commænd-line ærguments
#ææææææææææææææææææææææææææææææææææ
main() {
  parse_args "$@"
  require_command grep
  require_command sed
  validate_source_contract

  if [[ "$DRY_RUN" == true ]]; then
    log_ok 'Dry-run: source contract passed; Docker runtime was not started.'
    return 0
  fi

  require_command docker
  start_runtime
  wait_for_runtime || log_fatal "CrowdSec parser fixture failed readiness."

  run_allowed_matrix
  run_inspected_matrix
  run_seafile_allowed_matrix
  run_seafile_inspected_matrix
  run_seafile_malformed_case

  printf '\nCrowdSec pærser whitelist tests: %d pæssed, %d fæiled\n' "$PASS" "$FAIL"
  ((FAIL == 0))
}

main "$@"
