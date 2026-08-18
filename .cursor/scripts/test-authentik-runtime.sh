#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" \
  || { printf 'FAIL authentik-runtime: script directory resolution failed\n' >&2; exit 1; }
readonly TEST_SCRIPT_DIR
TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)" \
  || { printf 'FAIL authentik-runtime: repository root resolution failed\n' >&2; exit 1; }
readonly TEST_REPO_ROOT
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/authentik-runtime.XXXXXX")" \
  || { printf 'FAIL authentik-runtime: private fixture creation failed\n' >&2; exit 1; }
readonly TEST_ROOT
readonly RUN_ID="${TEST_ROOT##*.}-${BASHPID}"
readonly AUTHENTIK_IMAGE="${AUTHENTIK_TEST_IMAGE:-ghcr.io/goauthentik/server:2026.5}"
readonly POSTGRES_IMAGE="${AUTHENTIK_TEST_POSTGRES_IMAGE:-docker.io/library/postgres:18}"
readonly TEST_PREFIX="codex-authentik-runtime-${RUN_ID}"
readonly POSTGRES_CONTAINER="${TEST_PREFIX}-postgresql"
readonly BOOTSTRAP_CONTAINER="${TEST_PREFIX}-bootstrap"
readonly BOOTSTRAP_REPEAT_CONTAINER="${TEST_PREFIX}-bootstrap-repeat"
readonly BOOTSTRAP_PEER_CONTAINER="${TEST_PREFIX}-bootstrap-peer"
readonly SERVER_CONTAINER="${TEST_PREFIX}-server"
readonly WORKER_CONTAINER="${TEST_PREFIX}-worker"
readonly BACKEND_NETWORK="${TEST_PREFIX}-backend"
readonly FRONTEND_NETWORK="${TEST_PREFIX}-frontend"
readonly POSTGRES_VOLUME="${TEST_PREFIX}-postgresql"
readonly AUTHENTIK_DATA_VOLUME="${TEST_PREFIX}-data"
readonly POSTGRES_PASSWORD_FILE="${TEST_ROOT}/POSTGRES_PASSWORD"
readonly AUTHENTIK_SECRET_KEY_FILE="${TEST_ROOT}/AUTHENTIK_SECRET_KEY_PASSWORD"
readonly AUTHENTIK_BOOTSTRAP_PASSWORD_FILE="${TEST_ROOT}/AUTHENTIK_BOOTSTRAP_PASSWORD"
readonly SERVER_ENTRYPOINT_SOURCE="${TEST_REPO_ROOT}/Authentik/scripts/authentik-server-entrypoint.py"
readonly BOOTSTRAP_ENTRYPOINT_SOURCE="${TEST_REPO_ROOT}/templates/authentik-bootstrap/scripts/authentik-bootstrap-entrypoint.sh"
readonly BOOTSTRAP_HELPER_SOURCE="${TEST_REPO_ROOT}/templates/authentik-bootstrap/scripts/authentik-bootstrap.py"
readonly SERVER_ENTRYPOINT="${TEST_ROOT}/authentik-server-entrypoint.py"
readonly BOOTSTRAP_ENTRYPOINT="${TEST_ROOT}/authentik-bootstrap-entrypoint.sh"
readonly BOOTSTRAP_HELPER="${TEST_ROOT}/authentik-bootstrap.py"
readonly LOGIN_CLIENT="${TEST_ROOT}/authentik-login.py"
readonly PEER_CLIENT="${TEST_ROOT}/authentik-peer-probe.py"
readonly BOOTSTRAP_PEER_CLIENT="${TEST_ROOT}/authentik-bootstrap-peer-probe.py"
readonly BOOTSTRAP_PEER_CONTROL="${TEST_ROOT}/bootstrap-peer-control"
readonly FORWARD_HEADER_CLIENT="${TEST_ROOT}/authentik-forward-header-probe.py"
readonly PASSWORD_VERIFIER="${TEST_ROOT}/authentik-password-verifier.py"
readonly POSTGRES_PASSWORD_VALUE="authentik-postgresql-${RUN_ID}-safe-password"
readonly AUTHENTIK_SECRET_KEY_VALUE="authentik-secret-key-${RUN_ID}-0123456789abcdefghijklmnopqrstuvwxyz"
readonly AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE="authentik-bootstrap-${RUN_ID}-safe-password"
readonly AUTHENTIK_DATABASE_USER="authentik"
readonly AUTHENTIK_DATABASE_NAME="authentik"
BACKEND_SUBNET=''
FRONTEND_SUBNET=''
PASSWORD_VERIFIER_RUN=0
SUITE_COMPLETED=false

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the exæct disposæble contæiners, volumes, network, ænd fixture.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local original_status="$?"
  local cleanup_status=0
  local container_inventory="${TEST_ROOT}/cleanup-container-ids"
  local container_inventory_after="${TEST_ROOT}/cleanup-container-ids-after"
  local final_status
  local resource_id
  local resource_name

  trap - EXIT HUP INT TERM
  set +e
  if docker info >/dev/null 2>&1; then
    if docker container ls --all --quiet \
      --filter "label=codex.authentik-runtime=${RUN_ID}" \
      >"$container_inventory" 2>/dev/null; then
      while IFS= read -r resource_id; do
        [[ -n "$resource_id" ]] || continue
        remove_owned_container "$resource_id" || cleanup_status=1
      done <"$container_inventory"
    else
      cleanup_status=1
    fi
    for resource_name in \
      "$SERVER_CONTAINER" "$WORKER_CONTAINER" \
      "$BOOTSTRAP_CONTAINER" "$BOOTSTRAP_REPEAT_CONTAINER" \
      "$BOOTSTRAP_PEER_CONTAINER" \
      "$POSTGRES_CONTAINER"; do
      remove_owned_container "$resource_name" || cleanup_status=1
    done
    for resource_name in "$POSTGRES_VOLUME" "$AUTHENTIK_DATA_VOLUME"; do
      remove_owned_volume "$resource_name" || cleanup_status=1
    done
    for resource_name in "$BACKEND_NETWORK" "$FRONTEND_NETWORK"; do
      remove_owned_network "$resource_name" || cleanup_status=1
    done
    if docker container ls --all --quiet \
      --filter "label=codex.authentik-runtime=${RUN_ID}" \
      >"$container_inventory_after" 2>/dev/null; then
      [[ ! -s "$container_inventory_after" ]] || cleanup_status=1
    else
      cleanup_status=1
    fi
    if docker info >/dev/null 2>&1; then
      for resource_name in \
        "$SERVER_CONTAINER" "$WORKER_CONTAINER" \
        "$BOOTSTRAP_CONTAINER" "$BOOTSTRAP_REPEAT_CONTAINER" \
        "$BOOTSTRAP_PEER_CONTAINER" \
        "$POSTGRES_CONTAINER"; do
        if docker container inspect "$resource_name" >/dev/null 2>&1; then
          cleanup_status=1
        fi
      done
      for resource_name in "$POSTGRES_VOLUME" "$AUTHENTIK_DATA_VOLUME"; do
        if docker volume inspect "$resource_name" >/dev/null 2>&1; then
          cleanup_status=1
        fi
      done
      for resource_name in "$BACKEND_NETWORK" "$FRONTEND_NETWORK"; do
        if docker network inspect "$resource_name" >/dev/null 2>&1; then
          cleanup_status=1
        fi
      done
    else
      cleanup_status=1
    fi
  else
    cleanup_status=1
  fi
  if [[ "${KEEP_TEST_OUTPUT:-false}" == true ]]; then
    printf 'Private evidence retained: %s\n' "$TEST_ROOT" >&2
  else
    rm -rf -- "$TEST_ROOT" >/dev/null 2>&1 || cleanup_status=1
    [[ ! -e "$TEST_ROOT" ]] || cleanup_status=1
  fi
  final_status="$original_status"
  if [[ "$cleanup_status" -ne 0 ]]; then
    printf 'FAIL authentik-runtime: cleanup could not remove and verify every owned test resource\n' >&2
    if [[ "$final_status" -eq 0 ]]; then
      final_status=1
    fi
  elif [[ "$original_status" -eq 0 && "$SUITE_COMPLETED" == true ]]; then
    printf 'PASS authentik-runtime: fresh one-shot, persisted verifier, real login, restart, skip, no final secret exposure, exact two-network proxy boundary, native health, peer isolation, clean stop, and verified cleanup\n'
  elif [[ "$original_status" -eq 0 ]]; then
    printf 'FAIL authentik-runtime: suite exited before its final completion marker\n' >&2
    final_status=1
  fi
  exit "$final_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_resource_names_available
#   Fæils before creætion when one exæct disposæble resource næme exists.
#ææææææææææææææææææææææææææææææææææ
require_resource_names_available() {
  local resource_name

  for resource_name in \
    "$SERVER_CONTAINER" "$WORKER_CONTAINER" \
    "$BOOTSTRAP_CONTAINER" "$BOOTSTRAP_REPEAT_CONTAINER" \
    "$BOOTSTRAP_PEER_CONTAINER" \
    "$POSTGRES_CONTAINER"; do
    ! docker container inspect "$resource_name" >/dev/null 2>&1 \
      || fail "disposæble container name already exists: ${resource_name}"
  done
  for resource_name in "$POSTGRES_VOLUME" "$AUTHENTIK_DATA_VOLUME"; do
    ! docker volume inspect "$resource_name" >/dev/null 2>&1 \
      || fail "disposæble volume name already exists: ${resource_name}"
  done
  for resource_name in "$BACKEND_NETWORK" "$FRONTEND_NETWORK"; do
    ! docker network inspect "$resource_name" >/dev/null 2>&1 \
      || fail "disposæble network name already exists: ${resource_name}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_container
#   Removes one contæiner only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_container() {
  local resource_name="$1"
  local owner_label

  if ! owner_label="$(docker container inspect --format \
    '{{ index .Config.Labels "codex.authentik-runtime" }}' \
    "$resource_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker rm -f -- "$resource_name" >/dev/null 2>&1 || true
  ! docker container inspect "$resource_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_volume
#   Removes one volume only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_volume() {
  local resource_name="$1"
  local owner_label

  if ! owner_label="$(docker volume inspect --format \
    '{{ index .Labels "codex.authentik-runtime" }}' \
    "$resource_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker volume rm -- "$resource_name" >/dev/null 2>&1 || true
  ! docker volume inspect "$resource_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_network
#   Removes one network only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_network() {
  local resource_name="$1"
  local owner_label

  if ! owner_label="$(docker network inspect --format \
    '{{ index .Labels "codex.authentik-runtime" }}' \
    "$resource_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker network rm -- "$resource_name" >/dev/null 2>&1 || true
  ! docker network inspect "$resource_name" >/dev/null 2>&1
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Stops the suite without printing secret content.
#ææææææææææææææææææææææææææææææææææ
fail() {
  printf 'FAIL authentik-runtime: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_container_log
#   Stores one contæiner log privætely without echoing untrusted content.
#   Ærguments:
#     $1 - contæiner næme
#     $2 - evidence læbel
#ææææææææææææææææææææææææææææææææææ
capture_container_log() {
  local container_name="$1"
  local evidence_label="$2"
  docker logs "$container_name" >"${TEST_ROOT}/${evidence_label}.diagnostic.log" 2>&1 || true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_postgresql
#   Requires the disposæble PostgreSQL service to become reædy.
#ææææææææææææææææææææææææææææææææææ
wait_for_postgresql() {
  local attempt
  local status

  for attempt in {1..120}; do
    status="$(docker container inspect --format '{{.State.Status}}' "$POSTGRES_CONTAINER" 2>/dev/null || true)"
    if [[ "$status" == running ]] \
      && docker exec "$POSTGRES_CONTAINER" \
        pg_isready --username "$AUTHENTIK_DATABASE_USER" \
          --dbname "$AUTHENTIK_DATABASE_NAME" --timeout 1 >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$status" == exited || "$status" == dead ]]; then
      capture_container_log "$POSTGRES_CONTAINER" postgresql
      fail "PostgreSQL entered state ${status}"
    fi
    sleep 1
  done

  capture_container_log "$POSTGRES_CONTAINER" postgresql
  fail 'PostgreSQL did not become ready within 120 seconds'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_authentik_server
#   Requires the nætive server reædiness endpoint to return HTTP 200.
#ææææææææææææææææææææææææææææææææææ
wait_for_authentik_server() {
  local attempt
  local health_status
  local status

  for attempt in {1..180}; do
    status="$(docker container inspect --format '{{.State.Status}}' "$SERVER_CONTAINER" 2>/dev/null || true)"
    health_status="$(docker container inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$SERVER_CONTAINER" 2>/dev/null || true)"
    if [[ "$status" == running && "$health_status" == healthy ]] \
      && docker exec "$SERVER_CONTAINER" python3 -c \
        "import urllib.request; response=urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/', timeout=2); raise SystemExit(0 if response.status == 200 else 1)" \
        >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$status" == exited || "$status" == dead ]]; then
      capture_container_log "$SERVER_CONTAINER" server
      fail "authentik server entered state ${status}"
    fi
    sleep 1
  done

  capture_container_log "$SERVER_CONTAINER" server
  fail 'authentik server did not become ready within 180 seconds'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_authentik_worker
#   Requires the vendor worker heælthcheck to succeed.
#ææææææææææææææææææææææææææææææææææ
wait_for_authentik_worker() {
  local attempt
  local health_status
  local status

  for attempt in {1..180}; do
    status="$(docker container inspect --format '{{.State.Status}}' "$WORKER_CONTAINER" 2>/dev/null || true)"
    health_status="$(docker container inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$WORKER_CONTAINER" 2>/dev/null || true)"
    if [[ "$status" == running && "$health_status" == healthy ]] \
      && docker exec "$WORKER_CONTAINER" ak healthcheck >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$status" == exited || "$status" == dead ]]; then
      capture_container_log "$WORKER_CONTAINER" worker
      fail "authentik worker entered state ${status}"
    fi
    sleep 1
  done

  capture_container_log "$WORKER_CONTAINER" worker
  fail 'authentik worker did not become healthy within 180 seconds'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_bootstrap
#   Runs one bounded one-shot bootstræp contæiner ænd requires exit zero.
#   Ærguments:
#     $1 - contæiner næme
#ææææææææææææææææææææææææææææææææææ
run_bootstrap() {
  local container_name="$1"
  local require_peer_probe="${2:-false}"
  local bootstrap_status
  local healthcheck_test
  local timeout_status
  local wait_status

  docker create \
    --name "$container_name" \
    --label "codex.authentik-runtime=${RUN_ID}" \
    --network "$BACKEND_NETWORK" \
    --network-alias authentik-bootstrap \
    --user 1000:1000 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --init \
    --no-healthcheck \
    --tmpfs /run:rw,noexec,nosuid,nodev,size=64m \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
    --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=128m \
    --mount "type=volume,source=${AUTHENTIK_DATA_VOLUME},destination=/data" \
    --mount "type=bind,source=${BOOTSTRAP_ENTRYPOINT},destination=/usr/local/bin/authentik-bootstrap-entrypoint.sh,readonly" \
    --mount "type=bind,source=${BOOTSTRAP_HELPER},destination=/usr/local/lib/authentik-bootstrap.py,readonly" \
    --mount "type=bind,source=${POSTGRES_PASSWORD_FILE},destination=/run/secrets/POSTGRES_PASSWORD,readonly" \
    --mount "type=bind,source=${AUTHENTIK_SECRET_KEY_FILE},destination=/run/secrets/AUTHENTIK_SECRET_KEY_PASSWORD,readonly" \
    --mount "type=bind,source=${AUTHENTIK_BOOTSTRAP_PASSWORD_FILE},destination=/run/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD,readonly" \
    --env AUTHENTIK_POSTGRESQL__HOST=postgresql \
    --env "AUTHENTIK_POSTGRESQL__USER=${AUTHENTIK_DATABASE_USER}" \
    --env "AUTHENTIK_POSTGRESQL__NAME=${AUTHENTIK_DATABASE_NAME}" \
    --env AUTHENTIK_POSTGRESQL__PASSWORD=file:///run/secrets/POSTGRES_PASSWORD \
    --env AUTHENTIK_SECRET_KEY=file:///run/secrets/AUTHENTIK_SECRET_KEY_PASSWORD \
    --env AUTHENTIK_ERROR_REPORTING__ENABLED=false \
    --env AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true \
    --env AUTHENTIK_LISTEN__HTTP=127.0.0.1:9000 \
    --env AUTHENTIK_LISTEN__METRICS=127.0.0.1:9300 \
    --env AUTHENTIK_LISTEN__DEBUG_PY=127.0.0.1:9901 \
    --env AUTHENTIK_BOOTSTRAP_EMAIL=admin@example.test \
    --env AUTHENTIK_BOOTSTRAP_MIGRATION_TIMEOUT_SECONDS=1200 \
    --env AUTHENTIK_BOOTSTRAP_READY_TIMEOUT_SECONDS=900 \
    --env AUTHENTIK_BOOTSTRAP_STOP_TIMEOUT_SECONDS=60 \
    --entrypoint /bin/sh \
    "$AUTHENTIK_IMAGE" /usr/local/bin/authentik-bootstrap-entrypoint.sh bootstrap >/dev/null
  healthcheck_test="$(docker container inspect --format \
    '{{json .Config.Healthcheck.Test}}' "$container_name")"
  [[ "$healthcheck_test" == '["NONE"]' ]] \
    || fail 'authentik bootstrap did not disable the inherited vendor healthcheck'
  if [[ "$require_peer_probe" == true ]]; then
    start_bootstrap_peer_monitor
  fi
  docker start "$container_name" >/dev/null
  if [[ "$require_peer_probe" == true ]]; then
    wait_for_bootstrap_worker "$container_name"
    bootstrap_status="$(docker container inspect --format '{{.State.Status}}' "$container_name")"
    [[ "$bootstrap_status" == running ]] \
      || fail 'fresh-data bootstrap exited during its peer-listener probe'
    finish_bootstrap_peer_monitor
  fi

  set +e
  wait_status="$(timeout --foreground --signal=TERM --kill-after=70s 1300s \
    docker wait "$container_name" 2>/dev/null)"
  timeout_status=$?
  set -e
  if [[ "$timeout_status" -ne 0 || "$wait_status" != 0 ]]; then
    capture_container_log "$container_name" "${container_name##*-}"
    fail "authentik bootstrap ${container_name} did not complete successfully"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_bootstrap_peer_monitor
#   Monitors bootstræp peer ports from before stært until worker reædiness.
#ææææææææææææææææææææææææææææææææææ
start_bootstrap_peer_monitor() {
  mkdir -m 0700 -- "$BOOTSTRAP_PEER_CONTROL"
  docker run --detach \
    --name "$BOOTSTRAP_PEER_CONTAINER" \
    --label "codex.authentik-runtime=${RUN_ID}" \
    --network "$BACKEND_NETWORK" \
    --user 1000:1000 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=32m \
    --mount "type=bind,source=${BOOTSTRAP_PEER_CONTROL},destination=/control" \
    --mount "type=bind,source=${BOOTSTRAP_PEER_CLIENT},destination=/fixture/authentik-bootstrap-peer-probe.py,readonly" \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /fixture/authentik-bootstrap-peer-probe.py >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: bootstrap_worker_process_is_running
#   Returns success only while the finæl vendor worker process is present.
#ææææææææææææææææææææææææææææææææææ
bootstrap_worker_process_is_running() {
  local container_name="$1"

  docker exec -i "$container_name" python3 - >/dev/null 2>&1 <<'PY'
from pathlib import Path

for command_path in Path("/proc").glob("[0-9]*/cmdline"):
    try:
        command = [item for item in command_path.read_bytes().split(b"\0") if item]
    except OSError:
        continue
    executable = command[0].rsplit(b"/", 1)[-1] if command else b""
    if executable == b"authentik" and b"worker" in command[1:]:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_bootstrap_worker
#   Boundedly proves the finæl vendor worker process ænd nætive heælthcheck.
#ææææææææææææææææææææææææææææææææææ
wait_for_bootstrap_worker() {
  local container_name="$1"
  local attempt
  local container_status

  if ! timeout --foreground --signal=TERM --kill-after=5s 1210s \
    docker exec -i "$container_name" python3 - >/dev/null <<'PY'
import time
from pathlib import Path

deadline = time.monotonic() + 1200
while time.monotonic() < deadline:
    for command_path in Path("/proc").glob("[0-9]*/cmdline"):
        try:
            command = [item for item in command_path.read_bytes().split(b"\0") if item]
        except OSError:
            continue
        executable = command[0].rsplit(b"/", 1)[-1] if command else b""
        if executable == b"authentik" and b"worker" in command[1:]:
            raise SystemExit(0)
    time.sleep(0.25)
raise SystemExit(1)
PY
  then
    fail 'fresh-data bootstrap did not start the final native worker within 1200 seconds'
  fi
  for attempt in {1..180}; do
    container_status="$(docker container inspect --format \
      '{{.State.Status}}' "$container_name" 2>/dev/null || true)"
    if [[ "$container_status" == running ]] \
      && bootstrap_worker_process_is_running "$container_name" \
      && docker exec "$container_name" ak healthcheck >/dev/null 2>&1; then
      return 0
    fi
    if [[ "$container_status" == exited || "$container_status" == dead ]]; then
      fail "fresh-data bootstrap exited before native worker readiness: ${container_status}"
    fi
    sleep 1
  done
  fail 'fresh-data bootstrap native worker did not become healthy within 180 seconds'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: finish_bootstrap_peer_monitor
#   Stops ænd requires the full peer-port monitor to hæve observed the bootstræp.
#ææææææææææææææææææææææææææææææææææ
finish_bootstrap_peer_monitor() {
  local monitor_status
  local wait_status

  : >"${BOOTSTRAP_PEER_CONTROL}/done"
  set +e
  wait_status="$(timeout --foreground --signal=TERM --kill-after=5s 30s \
    docker wait "$BOOTSTRAP_PEER_CONTAINER" 2>/dev/null)"
  monitor_status=$?
  set -e
  [[ "$monitor_status" -eq 0 && "$wait_status" == 0 \
      && -f "${BOOTSTRAP_PEER_CONTROL}/observed" ]] \
    || fail 'bootstrap peer monitor did not prove continuous listener isolation'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: common_authentik_runtime_args
#   Builds the shæred hærdened server/worker Docker ærguments.
#   Ærguments:
#     $1 - destination ærræy næme
#     $2 - exæct first network
#ææææææææææææææææææææææææææææææææææ
common_authentik_runtime_args() {
  local destination_name="$1"
  local runtime_network="$2"
  local -n destination="$destination_name"

  # shellcheck disable=SC2034 # The næmeref writes into the cæller's ærræy.
  destination=(
    --label "codex.authentik-runtime=${RUN_ID}"
    --network "$runtime_network"
    --user 1000:1000
    --read-only
    --cap-drop ALL
    --security-opt no-new-privileges:true
    --init
    --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m"
    --tmpfs "/tmp:rw,noexec,nosuid,nodev,size=128m"
    --tmpfs "/var/tmp:rw,noexec,nosuid,nodev,size=128m"
    --mount "type=volume,source=${AUTHENTIK_DATA_VOLUME},destination=/data"
    --mount "type=bind,source=${SERVER_ENTRYPOINT},destination=/usr/local/lib/authentik-server-entrypoint.py,readonly"
    --mount "type=bind,source=${POSTGRES_PASSWORD_FILE},destination=/run/secrets/POSTGRES_PASSWORD,readonly"
    --mount "type=bind,source=${AUTHENTIK_SECRET_KEY_FILE},destination=/run/secrets/AUTHENTIK_SECRET_KEY_PASSWORD,readonly"
    --env AUTHENTIK_POSTGRESQL__HOST=postgresql
    --env "AUTHENTIK_POSTGRESQL__USER=${AUTHENTIK_DATABASE_USER}"
    --env "AUTHENTIK_POSTGRESQL__NAME=${AUTHENTIK_DATABASE_NAME}"
    --env AUTHENTIK_POSTGRESQL__PASSWORD=file:///run/secrets/POSTGRES_PASSWORD
    --env AUTHENTIK_SECRET_KEY=file:///run/secrets/AUTHENTIK_SECRET_KEY_PASSWORD
    --env AUTHENTIK_ERROR_REPORTING__ENABLED=false
    --env AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true
    --env AUTHENTIK_EMAIL_ENABLED=false
    --env AUTHENTIK_SMTP_HOST=CHANGE_ME
    --env AUTHENTIK_SMTP_PORT=465
    --env AUTHENTIK_SMTP_USERNAME=CHANGE_ME
    --env AUTHENTIK_SMTP_USE_TLS=false
    --env AUTHENTIK_SMTP_USE_SSL=true
    --env AUTHENTIK_SMTP_TIMEOUT=10
    --env AUTHENTIK_SMTP_FROM=CHANGE_ME
  )
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_authentik_server
#   Stærts the finæl server without the bootstræp secret.
#ææææææææææææææææææææææææææææææææææ
start_authentik_server() {
  local -a common_args=()
  common_authentik_runtime_args common_args "$FRONTEND_NETWORK"
  docker create \
    --name "$SERVER_CONTAINER" \
    --network-alias authentik-frontend \
    "${common_args[@]}" \
    --env AUTHENTIK_LISTEN__METRICS=127.0.0.1:9300 \
    --env AUTHENTIK_LISTEN__DEBUG=127.0.0.1:9900 \
    --env AUTHENTIK_LISTEN__DEBUG_PY=127.0.0.1:9901 \
    --env "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,::1/128,${FRONTEND_SUBNET}" \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /usr/local/lib/authentik-server-entrypoint.py server >/dev/null
  docker network connect --alias authentik-server "$BACKEND_NETWORK" "$SERVER_CONTAINER"
  docker start "$SERVER_CONTAINER" >/dev/null
  wait_for_authentik_server
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_authentik_worker
#   Stærts the finæl backend-only worker without the bootstræp secret.
#ææææææææææææææææææææææææææææææææææ
start_authentik_worker() {
  local -a common_args=()
  common_authentik_runtime_args common_args "$BACKEND_NETWORK"
  docker run --detach \
    --name "$WORKER_CONTAINER" \
    --network-alias authentik-worker \
    "${common_args[@]}" \
    --env AUTHENTIK_LISTEN__HTTP=127.0.0.1:9000 \
    --env AUTHENTIK_LISTEN__METRICS=127.0.0.1:9300 \
    --env AUTHENTIK_LISTEN__DEBUG_PY=127.0.0.1:9901 \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /usr/local/lib/authentik-server-entrypoint.py worker >/dev/null
  wait_for_authentik_worker
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_login
#   Executes the complete identification/password flow from æ frontend peer.
#ææææææææææææææææææææææææææææææææææ
run_login() {
  docker run --rm \
    --label "codex.authentik-runtime=${RUN_ID}" \
    --network "$FRONTEND_NETWORK" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=32m \
    --mount "type=bind,source=${LOGIN_CLIENT},destination=/fixture/authentik-login.py,readonly" \
    --mount "type=bind,source=${AUTHENTIK_BOOTSTRAP_PASSWORD_FILE},destination=/run/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD,readonly" \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /fixture/authentik-login.py \
      http://authentik-frontend:9000 /run/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_password_verifier
#   Verifies the persisted ækædmin hæsh in æ short-lived reæl-imæge process.
#ææææææææææææææææææææææææææææææææææ
run_password_verifier() {
  local denied_value
  local evidence_file

  PASSWORD_VERIFIER_RUN=$((PASSWORD_VERIFIER_RUN + 1))
  evidence_file="${TEST_ROOT}/password-verifier-${PASSWORD_VERIFIER_RUN}.log"
  if ! docker run --rm \
    --label "codex.authentik-runtime=${RUN_ID}" \
    --network "$BACKEND_NETWORK" \
    --user 1000:1000 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --init \
    --tmpfs /run:rw,noexec,nosuid,nodev,size=64m \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
    --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=128m \
    --mount "type=volume,source=${AUTHENTIK_DATA_VOLUME},destination=/data" \
    --mount "type=bind,source=${PASSWORD_VERIFIER},destination=/fixture/authentik-password-verifier.py,readonly" \
    --mount "type=bind,source=${POSTGRES_PASSWORD_FILE},destination=/run/secrets/POSTGRES_PASSWORD,readonly" \
    --mount "type=bind,source=${AUTHENTIK_SECRET_KEY_FILE},destination=/run/secrets/AUTHENTIK_SECRET_KEY_PASSWORD,readonly" \
    --mount "type=bind,source=${AUTHENTIK_BOOTSTRAP_PASSWORD_FILE},destination=/run/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD,readonly" \
    --env AUTHENTIK_POSTGRESQL__HOST=postgresql \
    --env "AUTHENTIK_POSTGRESQL__USER=${AUTHENTIK_DATABASE_USER}" \
    --env "AUTHENTIK_POSTGRESQL__NAME=${AUTHENTIK_DATABASE_NAME}" \
    --env AUTHENTIK_POSTGRESQL__PASSWORD=file:///run/secrets/POSTGRES_PASSWORD \
    --env AUTHENTIK_SECRET_KEY=file:///run/secrets/AUTHENTIK_SECRET_KEY_PASSWORD \
    --env AUTHENTIK_ERROR_REPORTING__ENABLED=false \
    --env AUTHENTIK_DISABLE_STARTUP_ANALYTICS=true \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /fixture/authentik-password-verifier.py \
      /run/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD \
      >"$evidence_file" 2>&1; then
    fail 'persisted akadmin password verifier failed; set KEEP_TEST_OUTPUT=true to retain private evidence'
  fi
  for denied_value in \
    "$POSTGRES_PASSWORD_VALUE" \
    "$AUTHENTIK_SECRET_KEY_VALUE" \
    "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE"; do
    if grep -Fq -- "$denied_value" "$evidence_file"; then
      fail 'persisted-password verifier evidence exposed test secret content'
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_peer_probe
#   Verifies the public server listener ænd every privæte listener from æ peer.
#ææææææææææææææææææææææææææææææææææ
run_peer_probe() {
  local network_name="$1"
  local probe_mode="$2"
  docker run --rm \
    --label "codex.authentik-runtime=${RUN_ID}" \
    --network "$network_name" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=32m \
    --mount "type=bind,source=${PEER_CLIENT},destination=/fixture/authentik-peer-probe.py,readonly" \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /fixture/authentik-peer-probe.py "$probe_mode"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_forward_header_probe
#   Sends unique XFF/XFP probes through one exæct Docker network.
#   Ærguments:
#     $1 - network næme
#     $2 - network-specific server æliæs
#     $3 - unique request pæth
#     $4 - synthetic XFF æddress
#ææææææææææææææææææææææææææææææææææ
run_forward_header_probe() {
  local network_name="$1"
  local server_alias="$2"
  local request_path="$3"
  local forwarded_address="$4"

  docker run --rm \
    --label "codex.authentik-runtime=${RUN_ID}" \
    --network "$network_name" \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=32m \
    --mount "type=bind,source=${FORWARD_HEADER_CLIENT},destination=/fixture/authentik-forward-header-probe.py,readonly" \
    --entrypoint python3 \
    "$AUTHENTIK_IMAGE" /fixture/authentik-forward-header-probe.py \
      "http://${server_alias}:9000${request_path}" "$forwarded_address"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_runtime_network_topology
#   Proves server/worker network membership ænd the frontend-only routing æliæs.
#ææææææææææææææææææææææææææææææææææ
assert_runtime_network_topology() {
  local evidence_file="${TEST_ROOT}/runtime-topology.inspect.json"

  docker container inspect "$SERVER_CONTAINER" "$WORKER_CONTAINER" >"$evidence_file"
  python3 - \
    "$evidence_file" "$SERVER_CONTAINER" "$WORKER_CONTAINER" \
    "$FRONTEND_NETWORK" "$BACKEND_NETWORK" "$FRONTEND_SUBNET" <<'PY'
import json
import sys

(
    evidence_path,
    server_name,
    worker_name,
    frontend_name,
    backend_name,
    frontend_subnet,
) = sys.argv[1:]
with open(evidence_path, encoding="utf-8") as evidence_handle:
    containers = {item["Name"].lstrip("/"): item for item in json.load(evidence_handle)}

server = containers[server_name]
server_networks = server["NetworkSettings"]["Networks"]
worker_networks = containers[worker_name]["NetworkSettings"]["Networks"]
if set(server_networks) != {frontend_name, backend_name}:
    raise SystemExit("server does not have the exact frontend/backend network set")
if set(worker_networks) != {backend_name}:
    raise SystemExit("worker is not backend-only")

frontend_aliases = set(server_networks[frontend_name].get("Aliases") or [])
backend_aliases = set(server_networks[backend_name].get("Aliases") or [])
if "authentik-frontend" not in frontend_aliases:
    raise SystemExit("frontend network is missing the dedicated routing alias")
if "authentik-frontend" in backend_aliases:
    raise SystemExit("dedicated routing alias leaked onto the backend network")
if "authentik-server" not in backend_aliases:
    raise SystemExit("backend network is missing its server alias")
if "authentik-server" in frontend_aliases:
    raise SystemExit("backend server alias leaked onto the frontend network")

trusted_proxy_setting = (
    "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS="
    f"127.0.0.0/8,::1/128,{frontend_subnet}"
)
if trusted_proxy_setting not in server["Config"].get("Env", []):
    raise SystemExit("server trusted-proxy configuration is not the exact frontend subnet")
PY
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_forward_header_boundary
#   Proves frontend-only XFF trust ænd records the independent XFP limitætion.
#ææææææææææææææææææææææææææææææææææ
assert_forward_header_boundary() {
  local trusted_path="/runtime-proxy-probe-${RUN_ID}-trusted/"
  local untrusted_path="/runtime-proxy-probe-${RUN_ID}-untrusted/"
  local trusted_address='198.51.100.41'
  local untrusted_address='203.0.113.42'
  local evidence_file="${TEST_ROOT}/forward-header.log"
  local attempt
  local assertion_status

  run_forward_header_probe \
    "$FRONTEND_NETWORK" authentik-frontend "$trusted_path" "$trusted_address"
  run_forward_header_probe \
    "$BACKEND_NETWORK" authentik-server "$untrusted_path" "$untrusted_address"

  for ((attempt = 1; attempt <= 20; attempt++)); do
    docker logs "$SERVER_CONTAINER" >"$evidence_file" 2>&1 || true
    set +e
    python3 - \
      "$evidence_file" "$trusted_path" "$trusted_address" \
      "$untrusted_path" "$untrusted_address" <<'PY'
import json
import sys

log_path, trusted_path, trusted_address, untrusted_path, untrusted_address = sys.argv[1:]
records = {}
with open(log_path, encoding="utf-8", errors="replace") as log_handle:
    for line in log_handle:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        event_path = event.get("event")
        if event_path in {trusted_path, untrusted_path} and {
            "remote",
            "scheme",
        }.issubset(event):
            records[event_path] = event

if set(records) != {trusted_path, untrusted_path}:
    raise SystemExit(2)
trusted = records[trusted_path]
untrusted = records[untrusted_path]
if trusted["remote"] != trusted_address:
    raise SystemExit("trusted frontend peer did not control X-Forwarded-For")
if untrusted["remote"] == untrusted_address:
    raise SystemExit("untrusted backend peer controlled X-Forwarded-For")
if trusted["scheme"] != "https":
    raise SystemExit("trusted frontend X-Forwarded-Proto was not honored")
if untrusted["scheme"] != "https":
    raise SystemExit(
        "current vendor limitation changed: untrusted X-Forwarded-Proto was not honored"
    )
PY
    assertion_status=$?
    set -e
    if [[ "$assertion_status" -eq 0 ]]; then
      return 0
    elif [[ "$assertion_status" -ne 2 ]]; then
      fail 'authentik forwarding-header trust boundary failed'
    fi
    sleep 1
  done

  fail 'authentik forwarding-header evidence was not emitted within 20 seconds'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_final_process_evidence
#   Cæptures inspect, every reædæble process environment/ærgv, ænd logs.
#ææææææææææææææææææææææææææææææææææ
capture_final_process_evidence() {
  local container_name
  local denied_values_file="${TEST_ROOT}/final-denied-values"
  local evidence_name

  for container_name in "$SERVER_CONTAINER" "$WORKER_CONTAINER"; do
    evidence_name="${container_name##*-}"
    docker container inspect "$container_name" >"${TEST_ROOT}/${evidence_name}.inspect.json"
    docker exec -i "$container_name" python3 - \
      >"${TEST_ROOT}/${evidence_name}.process.json" <<'PY'
import json
import os
import sys
from pathlib import Path

records = []
for process_path in sorted(
    (path for path in Path("/proc").iterdir() if path.name.isdigit()),
    key=lambda path: int(path.name),
):
    if int(process_path.name) == os.getpid():
        continue
    try:
        command = process_path.joinpath("cmdline").read_bytes().split(b"\0")
        environment = process_path.joinpath("environ").read_bytes().split(b"\0")
    except OSError:
        continue
    records.append(
        {
            "pid": int(process_path.name),
            "cmdline": [item.decode(errors="replace") for item in command if item],
            "environ": [item.decode(errors="replace") for item in environment if item],
        }
    )
json.dump(records, sys.stdout, sort_keys=True)
PY
    docker logs "$container_name" >"${TEST_ROOT}/${evidence_name}.log" 2>&1
  done

  printf '%s\n' \
    "$POSTGRES_PASSWORD_VALUE" \
    "$AUTHENTIK_SECRET_KEY_VALUE" \
    "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE" >"$denied_values_file"
  if grep -Ff "$denied_values_file" \
      "${TEST_ROOT}/server.inspect.json" "${TEST_ROOT}/server.process.json" "${TEST_ROOT}/server.log" \
      "${TEST_ROOT}/worker.inspect.json" "${TEST_ROOT}/worker.process.json" "${TEST_ROOT}/worker.log" \
      >/dev/null; then
    fail 'final server or worker exposed secret content in inspect, argv, environment, or logs'
  fi
  if rg -n 'AUTHENTIK_BOOTSTRAP_(PASSWORD|PASSWORD_HASH|TOKEN)' \
      "${TEST_ROOT}/server.inspect.json" "${TEST_ROOT}/server.process.json" "${TEST_ROOT}/server.log" \
      "${TEST_ROOT}/worker.inspect.json" "${TEST_ROOT}/worker.process.json" "${TEST_ROOT}/worker.log" \
      >/dev/null; then
    fail 'final server or worker exposed a bootstrap credential name'
  fi
  if rg -n 'AUTHENTIK_EMAIL__' \
      "${TEST_ROOT}/server.inspect.json" "${TEST_ROOT}/server.process.json" "${TEST_ROOT}/server.log" \
      "${TEST_ROOT}/worker.inspect.json" "${TEST_ROOT}/worker.process.json" "${TEST_ROOT}/worker.log" \
      >/dev/null; then
    fail 'disabled SMTP vendor environment reached final runtime evidence'
  fi
  python3 - \
    "${TEST_ROOT}/server.process.json" server \
    "${TEST_ROOT}/worker.process.json" worker <<'PY'
import json
import sys

for evidence_path, role in zip(sys.argv[1::2], sys.argv[2::2], strict=True):
    with open(evidence_path, encoding="utf-8") as evidence_handle:
        processes = json.load(evidence_handle)
    def is_daemon(process):
        command = process["cmdline"]
        executable = command[0].rsplit("/", 1)[-1] if command else ""
        if role == "server":
            return executable == "authentik-server"
        return executable == "authentik" and "worker" in command[1:]

    daemon_processes = [
        process for process in processes if process["pid"] != 1 and is_daemon(process)
    ]
    if not daemon_processes:
        raise SystemExit(f"no real authentik {role} daemon process was captured")
    for process in daemon_processes:
        environment_names = {
            item.partition("=")[0] for item in process["environ"]
        }
        if any(
            name.startswith("AUTHENTIK_SMTP_")
            for name in environment_names
        ):
            raise SystemExit(
                f"disabled SMTP environment reached {role} process {process['pid']}"
            )
PY
}

command -v docker >/dev/null || fail 'docker is required'
command -v python3 >/dev/null || fail 'python3 is required'
command -v rg >/dev/null || fail 'rg is required'
for source_file in \
  "$SERVER_ENTRYPOINT_SOURCE" "$BOOTSTRAP_ENTRYPOINT_SOURCE" "$BOOTSTRAP_HELPER_SOURCE"; do
  [[ -f "$source_file" && ! -L "$source_file" ]] || fail "unsafe source file: ${source_file}"
done

cp -- "$SERVER_ENTRYPOINT_SOURCE" "$SERVER_ENTRYPOINT"
cp -- "$BOOTSTRAP_ENTRYPOINT_SOURCE" "$BOOTSTRAP_ENTRYPOINT"
cp -- "$BOOTSTRAP_HELPER_SOURCE" "$BOOTSTRAP_HELPER"
chmod 0555 "$SERVER_ENTRYPOINT" "$BOOTSTRAP_ENTRYPOINT" "$BOOTSTRAP_HELPER"
cmp -s -- "$SERVER_ENTRYPOINT_SOURCE" "$SERVER_ENTRYPOINT" || fail 'server entrypoint copy drifted'
cmp -s -- "$BOOTSTRAP_ENTRYPOINT_SOURCE" "$BOOTSTRAP_ENTRYPOINT" || fail 'bootstrap entrypoint copy drifted'
cmp -s -- "$BOOTSTRAP_HELPER_SOURCE" "$BOOTSTRAP_HELPER" || fail 'bootstrap helper copy drifted'

printf '%s' "$POSTGRES_PASSWORD_VALUE" >"$POSTGRES_PASSWORD_FILE"
printf '%s' "$AUTHENTIK_SECRET_KEY_VALUE" >"$AUTHENTIK_SECRET_KEY_FILE"
printf '%s' "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE" >"$AUTHENTIK_BOOTSTRAP_PASSWORD_FILE"
chmod 0640 "$POSTGRES_PASSWORD_FILE" "$AUTHENTIK_SECRET_KEY_FILE" "$AUTHENTIK_BOOTSTRAP_PASSWORD_FILE"

cat >"$LOGIN_CLIENT" <<'PY'
#!/usr/bin/env python3
import http.cookiejar
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

base_url = sys.argv[1].rstrip("/")
password = Path(sys.argv[2]).read_text(encoding="utf-8")
cookie_jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
executor_url = (
    f"{base_url}/api/v3/flows/executor/default-authentication-flow/"
    "?query=next%3D%252F"
)


def request(method, url, payload=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
        csrf = next(
            (cookie.value for cookie in cookie_jar if cookie.name == "authentik_csrf"),
            "",
        )
        if csrf:
            headers["X-CSRFToken"] = csrf
    response = opener.open(
        urllib.request.Request(url, data=data, headers=headers, method=method),
        timeout=15,
    )
    body = response.read()
    return response.status, json.loads(body.decode("utf-8"))


phase = "identification-get"
try:
    stage = None
    for _attempt in range(180):
        try:
            status, stage = request("GET", executor_url)
            break
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            time.sleep(1)
    if stage is None:
        raise RuntimeError("default authentication flow was not published within 180 seconds")
    if status != 200 or stage.get("component") != "ak-stage-identification":
        raise RuntimeError(f"unexpected identification stage: {stage.get('component')!r}")
    phase = "identification-post"
    status, stage = request("POST", executor_url, {"uid_field": "akadmin"})
    if status != 200 or stage.get("component") != "ak-stage-password":
        raise RuntimeError(f"unexpected password stage: {stage.get('component')!r}")
    phase = "password-post"
    status, stage = request("POST", executor_url, {"password": password})
    if status != 200 or stage.get("component") != "xak-flow-redirect":
        raise RuntimeError(f"unexpected authenticated redirect: {stage.get('component')!r}")
    phase = "users-me-get"
    status, user = request("GET", f"{base_url}/api/v3/core/users/me/")
    if status != 200 or user.get("user", {}).get("username") != "akadmin":
        raise RuntimeError("authenticated users/me response did not identify akadmin")
except (OSError, ValueError, RuntimeError, urllib.error.HTTPError) as error:
    error_url = getattr(error, "url", "")
    print(
        f"authentik login flow failed during {phase}: {error} {error_url}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY

cat >"$PEER_CLIENT" <<'PY'
#!/usr/bin/env python3
import socket
import sys


def connects(host, port):
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


def resolves(host):
    try:
        socket.getaddrinfo(host, None)
        return True
    except socket.gaierror:
        return False


mode = sys.argv[1]
server_host = "authentik-server" if mode == "backend" else "authentik-frontend"
if not connects(server_host, 9000):
    raise SystemExit("network peer could not reach the intended server HTTP listener")
private_listeners = [(server_host, (9300, 9900, 9901))]
if mode == "backend":
    if resolves("authentik-frontend"):
        raise SystemExit("frontend-only server alias resolved from the backend network")
    private_listeners.append(("authentik-worker", (9000, 9300, 9900, 9901)))
elif mode == "frontend":
    if resolves("authentik-server") or resolves("authentik-worker"):
        raise SystemExit("backend-only alias resolved from the frontend network")
elif mode != "frontend":
    raise SystemExit("unknown peer probe mode")
for host, ports in private_listeners:
    for port in ports:
        if connects(host, port):
            raise SystemExit(f"network peer reached private listener {host}:{port}")
PY

cat >"$BOOTSTRAP_PEER_CLIENT" <<'PY'
#!/usr/bin/env python3
import socket
import time
from pathlib import Path

control = Path("/control")
deadline = time.monotonic() + 1300
observed = False
while time.monotonic() < deadline:
    if control.joinpath("done").exists():
        if not observed:
            raise SystemExit("bootstrap peer alias was never observed")
        raise SystemExit(0)
    try:
        socket.getaddrinfo("authentik-bootstrap", None)
    except socket.gaierror:
        time.sleep(0.1)
        continue
    observed = True
    control.joinpath("observed").touch(exist_ok=True)
    for port in (9000, 9300, 9900, 9901):
        try:
            with socket.create_connection(("authentik-bootstrap", port), timeout=0.2):
                raise SystemExit(f"network peer reached bootstrap listener {port}")
        except OSError:
            pass
    time.sleep(0.1)
raise SystemExit("bootstrap peer monitor exceeded its deadline")
PY

cat >"$FORWARD_HEADER_CLIENT" <<'PY'
#!/usr/bin/env python3
import sys
import urllib.error
import urllib.request

request = urllib.request.Request(
    sys.argv[1],
    headers={
        "X-Forwarded-For": sys.argv[2],
        "X-Forwarded-Proto": "https",
    },
)
try:
    with urllib.request.urlopen(request, timeout=15) as response:
        response.read()
except urllib.error.HTTPError as error:
    error.read()
except OSError:
    raise SystemExit("forwarded-header probe could not reach authentik")
PY

cat >"$PASSWORD_VERIFIER" <<'PY'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

try:
    password = Path(sys.argv[1]).read_text(encoding="utf-8")
    sys.path.insert(0, "/")
    from authentik.root.setup import setup

    setup()
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "authentik.root.settings")
    import django

    django.setup()
    from authentik.core.models import User
    from authentik.tenants.models import Tenant

    tenants = list(Tenant.objects.filter(ready=True).order_by("schema_name"))
    if not tenants:
        raise RuntimeError
    for tenant in tenants:
        with tenant:
            user = User.objects.filter(username="akadmin", is_active=True).first()
            if (
                user is None
                or not user.check_password(password)
                or not user.groups.filter(is_superuser=True).exists()
            ):
                raise RuntimeError
except Exception:
    raise SystemExit("persisted akadmin password verifier failed")
PY
chmod 0555 \
  "$LOGIN_CLIENT" "$PEER_CLIENT" "$BOOTSTRAP_PEER_CLIENT" \
  "$FORWARD_HEADER_CLIENT" "$PASSWORD_VERIFIER"

require_resource_names_available
if ! docker pull "$POSTGRES_IMAGE" >"${TEST_ROOT}/postgresql-pull.log" 2>&1; then
  fail 'PostgreSQL image pull failed; set KEEP_TEST_OUTPUT=true to retain private evidence'
fi
if ! docker pull "$AUTHENTIK_IMAGE" >"${TEST_ROOT}/authentik-pull.log" 2>&1; then
  fail 'authentik image pull failed; set KEEP_TEST_OUTPUT=true to retain private evidence'
fi
docker network create --internal \
  --label "codex.authentik-runtime=${RUN_ID}" "$BACKEND_NETWORK" >/dev/null
docker network create --internal \
  --label "codex.authentik-runtime=${RUN_ID}" "$FRONTEND_NETWORK" >/dev/null
for network_name in "$BACKEND_NETWORK" "$FRONTEND_NETWORK"; do
  [[ "$(docker network inspect --format \
    '{{ index .Labels "codex.authentik-runtime" }}' "$network_name")" == "$RUN_ID" ]] \
    || fail "created runtime network lacks exact ownership label: ${network_name}"
done
BACKEND_SUBNET="$(docker network inspect --format '{{(index .IPAM.Config 0).Subnet}}' "$BACKEND_NETWORK")"
FRONTEND_SUBNET="$(docker network inspect --format '{{(index .IPAM.Config 0).Subnet}}' "$FRONTEND_NETWORK")"
python3 - "$BACKEND_SUBNET" "$FRONTEND_SUBNET" <<'PY' \
  || fail 'Docker selected an invalid, public, or overlapping runtime subnet'
import ipaddress
import sys

networks = [ipaddress.ip_network(value, strict=True) for value in sys.argv[1:]]
private_ranges = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
]
if any(
    network.version != 4
    or not any(network.subnet_of(private_range) for private_range in private_ranges)
    for network in networks
):
    raise SystemExit(1)
if networks[0].overlaps(networks[1]):
    raise SystemExit(1)
PY
docker volume create --label "codex.authentik-runtime=${RUN_ID}" "$POSTGRES_VOLUME" >/dev/null
docker volume create --label "codex.authentik-runtime=${RUN_ID}" "$AUTHENTIK_DATA_VOLUME" >/dev/null
for volume_name in "$POSTGRES_VOLUME" "$AUTHENTIK_DATA_VOLUME"; do
  [[ "$(docker volume inspect --format \
    '{{ index .Labels "codex.authentik-runtime" }}' "$volume_name")" == "$RUN_ID" ]] \
    || fail "created runtime volume lacks exact ownership label: ${volume_name}"
done

docker run --rm \
  --label "codex.authentik-runtime=${RUN_ID}" \
  --user 0:0 \
  --network none \
  --mount "type=volume,source=${AUTHENTIK_DATA_VOLUME},destination=/data" \
  --entrypoint /bin/sh "$AUTHENTIK_IMAGE" -ec 'chown 1000:1000 /data; chmod 0700 /data'

docker run --detach \
  --name "$POSTGRES_CONTAINER" \
  --hostname postgresql \
  --network "$BACKEND_NETWORK" \
  --network-alias postgresql \
  --label "codex.authentik-runtime=${RUN_ID}" \
  --read-only \
  --cap-drop ALL \
  --cap-add KILL \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-add CHOWN \
  --cap-add FOWNER \
  --cap-add DAC_READ_SEARCH \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs /run:rw,noexec,nosuid,nodev,size=64m \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,source=${POSTGRES_VOLUME},destination=/var/lib/postgresql" \
  --mount "type=bind,source=${POSTGRES_PASSWORD_FILE},destination=/run/secrets/POSTGRES_PASSWORD,readonly" \
  --env "POSTGRES_USER=${AUTHENTIK_DATABASE_USER}" \
  --env "POSTGRES_DB=${AUTHENTIK_DATABASE_NAME}" \
  --env POSTGRES_PASSWORD_FILE=/run/secrets/POSTGRES_PASSWORD \
  "$POSTGRES_IMAGE" >/dev/null
wait_for_postgresql

run_bootstrap "$BOOTSTRAP_CONTAINER" true
capture_container_log "$BOOTSTRAP_CONTAINER" bootstrap-fresh
if grep -Fq -- \
  "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE" "${TEST_ROOT}/bootstrap-fresh.diagnostic.log"; then
  fail 'fresh-data bootstrap logs exposed the bootstrap password'
fi
run_password_verifier

start_authentik_server
start_authentik_worker
assert_runtime_network_topology
run_login
run_peer_probe "$FRONTEND_NETWORK" frontend
run_peer_probe "$BACKEND_NETWORK" backend
assert_forward_header_boundary
capture_final_process_evidence

docker restart --time 60 "$SERVER_CONTAINER" "$WORKER_CONTAINER" >/dev/null
wait_for_authentik_server
wait_for_authentik_worker
assert_runtime_network_topology
run_password_verifier
run_login
run_peer_probe "$FRONTEND_NETWORK" frontend
run_peer_probe "$BACKEND_NETWORK" backend
assert_forward_header_boundary

printf 'CHANGE_ME' >"$AUTHENTIK_BOOTSTRAP_PASSWORD_FILE"
run_bootstrap "$BOOTSTRAP_REPEAT_CONTAINER"
capture_container_log "$BOOTSTRAP_REPEAT_CONTAINER" bootstrap-repeat
if ! grep -Fq -- \
  '[INFO] authentik is already initialized; credential phase skipped' \
  "${TEST_ROOT}/bootstrap-repeat.diagnostic.log"; then
  fail 'initialized-data bootstrap did not prove its credential-phase skip'
fi
if rg -q 'credential-bearing worker exited|CHANGE_ME' \
  "${TEST_ROOT}/bootstrap-repeat.diagnostic.log"; then
  fail 'initialized-data bootstrap consumed or exposed the replaced credential'
fi

printf '%s' "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE" >"$AUTHENTIK_BOOTSTRAP_PASSWORD_FILE"
run_login
capture_final_process_evidence

docker stop --time 60 "$SERVER_CONTAINER" "$WORKER_CONTAINER" >/dev/null
for container_name in "$SERVER_CONTAINER" "$WORKER_CONTAINER"; do
  [[ "$(docker container inspect --format '{{.State.ExitCode}}' "$container_name")" -eq 0 ]] \
    || fail "${container_name} did not stop cleanly"
done

SUITE_COMPLETED=true
