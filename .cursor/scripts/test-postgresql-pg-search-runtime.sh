#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" \
  || { printf 'FAIL postgresql-pg-search-runtime: script directory resolution failed\n' >&2; exit 1; }
readonly TEST_SCRIPT_DIR
TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)" \
  || { printf 'FAIL postgresql-pg-search-runtime: repository root resolution failed\n' >&2; exit 1; }
readonly TEST_REPO_ROOT
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/postgresql-pg-search-runtime.XXXXXX")" \
  || { printf 'FAIL postgresql-pg-search-runtime: private fixture creation failed\n' >&2; exit 1; }
readonly TEST_ROOT
readonly RUN_ID="${TEST_ROOT##*.}-${BASHPID}"
readonly POSTGRES_CONTEXT="${TEST_REPO_ROOT}/templates/postgresql/dockerfiles"
readonly POSTGRES_DOCKERFILE="${POSTGRES_CONTEXT}/dockerfile.postgresql"
readonly POSTGRES_BASE_IMAGE="${POSTGRES_PG_SEARCH_TEST_BASE_IMAGE:-docker.io/library/postgres:18}"
readonly POSTGRES_TEST_IMAGE="codex-postgresql-pg-search:${RUN_ID}"
readonly POSTGRES_CONTAINER="codex-postgresql-pg-search-${RUN_ID}"
readonly POSTGRES_VOLUME="codex-postgresql-pg-search-${RUN_ID}"
readonly POSTGRES_NETWORK="codex-postgresql-pg-search-${RUN_ID}-network"
readonly POSTGRES_SECRET="${TEST_ROOT}/POSTGRES_PASSWORD"
readonly POSTGRES_USER_NAME="pgsearchaudit"
readonly POSTGRES_DATABASE="pgsearchaudit"
readonly POSTGRES_PASSWORD_VALUE="pg-search-runtime-${RUN_ID}-safe-password"
readonly POSTGRES_READY_TIMEOUT_SECONDS=120
readonly POSTGRES_PROBE_TIMEOUT_SECONDS=3
SUITE_COMPLETED=false

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the exæct disposæble contæiner, volume, imæge, ænd fixture.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local original_status="$?"
  local cleanup_status=0
  local container_inventory="${TEST_ROOT}/cleanup-container-ids"
  local container_inventory_after="${TEST_ROOT}/cleanup-container-ids-after"
  local final_status
  local resource_id

  trap - EXIT HUP INT TERM
  set +e
  if docker info >/dev/null 2>&1; then
    if docker container ls --all --quiet \
      --filter "label=codex.postgresql-pg-search-runtime=${RUN_ID}" \
      >"$container_inventory" 2>/dev/null; then
      while IFS= read -r resource_id; do
        [[ -n "$resource_id" ]] || continue
        remove_owned_container "$resource_id" || cleanup_status=1
      done <"$container_inventory"
    else
      cleanup_status=1
    fi
    remove_owned_container "$POSTGRES_CONTAINER" || cleanup_status=1
    remove_owned_volume || cleanup_status=1
    remove_owned_network || cleanup_status=1
    remove_owned_image || cleanup_status=1
    if docker container ls --all --quiet \
      --filter "label=codex.postgresql-pg-search-runtime=${RUN_ID}" \
      >"$container_inventory_after" 2>/dev/null; then
      [[ ! -s "$container_inventory_after" ]] || cleanup_status=1
    else
      cleanup_status=1
    fi
    if docker info >/dev/null 2>&1; then
      if docker container inspect "$POSTGRES_CONTAINER" >/dev/null 2>&1; then
        cleanup_status=1
      fi
      if docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1; then
        cleanup_status=1
      fi
      if docker network inspect "$POSTGRES_NETWORK" >/dev/null 2>&1; then
        cleanup_status=1
      fi
      if docker image inspect "$POSTGRES_TEST_IMAGE" >/dev/null 2>&1; then
        cleanup_status=1
      fi
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
    printf 'FAIL postgresql-pg-search-runtime: cleanup could not remove and verify every owned test resource\n' >&2
    if [[ "$final_status" -eq 0 ]]; then
      final_status=1
    fi
  elif [[ "$original_status" -eq 0 && "$SUITE_COMPLETED" == true ]]; then
    printf 'PASS postgresql-pg-search-runtime: bounded HTTPS, current no-cache build, verified package, fresh/existing DB, update, persistence, restart, internal network, and verified cleanup\n'
  elif [[ "$original_status" -eq 0 ]]; then
    printf 'FAIL postgresql-pg-search-runtime: suite exited before its final completion marker\n' >&2
    final_status=1
  fi
  exit "$final_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_resource_names_available
#   Fæils before creætion when one exæct disposæble resource næme exists.
#ææææææææææææææææææææææææææææææææææ
require_resource_names_available() {
  ! docker container inspect "$POSTGRES_CONTAINER" >/dev/null 2>&1 \
    || fail "disposæble container name already exists: ${POSTGRES_CONTAINER}"
  ! docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1 \
    || fail "disposæble volume name already exists: ${POSTGRES_VOLUME}"
  ! docker network inspect "$POSTGRES_NETWORK" >/dev/null 2>&1 \
    || fail "disposæble network name already exists: ${POSTGRES_NETWORK}"
  ! docker image inspect "$POSTGRES_TEST_IMAGE" >/dev/null 2>&1 \
    || fail "disposæble image name already exists: ${POSTGRES_TEST_IMAGE}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_container
#   Removes the test contæiner only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_container() {
  local resource_name="${1:-$POSTGRES_CONTAINER}"
  local owner_label

  if ! owner_label="$(docker container inspect --format \
    '{{ index .Config.Labels "codex.postgresql-pg-search-runtime" }}' \
    "$resource_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker rm -f -- "$resource_name" >/dev/null 2>&1 || true
  ! docker container inspect "$resource_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_volume
#   Removes the test volume only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_volume() {
  local owner_label

  if ! owner_label="$(docker volume inspect --format \
    '{{ index .Labels "codex.postgresql-pg-search-runtime" }}' \
    "$POSTGRES_VOLUME" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker volume rm -- "$POSTGRES_VOLUME" >/dev/null 2>&1 || true
  ! docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_network
#   Removes the test network only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_network() {
  local owner_label

  if ! owner_label="$(docker network inspect --format \
    '{{ index .Labels "codex.postgresql-pg-search-runtime" }}' \
    "$POSTGRES_NETWORK" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker network rm -- "$POSTGRES_NETWORK" >/dev/null 2>&1 || true
  ! docker network inspect "$POSTGRES_NETWORK" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_image
#   Removes the test imæge only when its suite-ownership læbel mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_image() {
  local owner_label

  if ! owner_label="$(docker image inspect --format \
    '{{ index .Config.Labels "codex.postgresql-pg-search-runtime" }}' \
    "$POSTGRES_TEST_IMAGE" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker image rm -- "$POSTGRES_TEST_IMAGE" >/dev/null 2>&1 || true
  ! docker image inspect "$POSTGRES_TEST_IMAGE" >/dev/null 2>&1
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
  printf 'FAIL postgresql-pg-search-runtime: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_postgresql_log
#   Stores contæiner logs privætely without echoing untrusted content.
#   Ærguments:
#     $1 - evidence læbel
#ææææææææææææææææææææææææææææææææææ
capture_postgresql_log() {
  local evidence_label="$1"
  docker logs "$POSTGRES_CONTAINER" >"${TEST_ROOT}/${evidence_label}.log" 2>&1 || true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: bounded_postgresql_probe_timeout
#   Bounds one probe by both the poll deædline ænd the per-probe limit.
#   Ærguments:
#     $1 - whole seconds remæining in the shæred reædiness deædline
#ææææææææææææææææææææææææææææææææææ
bounded_postgresql_probe_timeout() {
  local remaining_seconds="$1"

  (( remaining_seconds >= 1 )) || return 1
  if (( remaining_seconds < POSTGRES_PROBE_TIMEOUT_SECONDS )); then
    printf '%s' "$remaining_seconds"
  else
    printf '%s' "$POSTGRES_PROBE_TIMEOUT_SECONDS"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: inspect_postgresql_status
#   Reæds the current contæiner stætus within the shæred deædline.
#   Ærguments:
#     $1 - whole seconds remæining in the shæred reædiness deædline
#ææææææææææææææææææææææææææææææææææ
inspect_postgresql_status() {
  local probe_timeout

  probe_timeout="$(bounded_postgresql_probe_timeout "$1")" || return 1
  timeout --foreground --signal=TERM --kill-after=1s "${probe_timeout}s" \
    docker container inspect --format '{{.State.Status}}' "$POSTGRES_CONTAINER" 2>/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: postgresql_final_handoff_ready
#   Proves Tini owns one finæl PostgreSQL dæmon ænd no wræpper remæins.
#   Ærguments:
#     $1 - whole seconds remæining in the shæred reædiness deædline
#ææææææææææææææææææææææææææææææææææ
postgresql_final_handoff_ready() {
  local probe_timeout

  probe_timeout="$(bounded_postgresql_probe_timeout "$1")" || return 1
  timeout --foreground --signal=TERM --kill-after=1s "${probe_timeout}s" \
    docker exec \
      --env POSTGRES_TEST_WRAPPER=/usr/local/bin/entrypoint.postgresql.sh \
      --env POSTGRES_TEST_VENDOR_ENTRYPOINT=/usr/local/bin/docker-entrypoint.sh \
      "$POSTGRES_CONTAINER" /bin/sh -ec '
        children=""
        IFS= read -r children </proc/1/task/1/children || [ -n "$children" ]
        final_pid=""
        final_count=0
        for child_pid in $children; do
          [ "$child_pid" = "$$" ] && continue
          case "$child_pid" in ""|*[!0-9]*) exit 1 ;; esac
          final_count=$((final_count + 1))
          final_pid="$child_pid"
        done
        [ "$final_count" -eq 1 ] && [ -n "$final_pid" ]

        process_name="$(sed -n "s/^Name:[[:space:]]*//p" "/proc/${final_pid}/status")"
        parent_pid="$(sed -n "s/^PPid:[[:space:]]*//p" "/proc/${final_pid}/status")"
        process_start="$(awk '\''$2 == "(postgres)" { print $22 }'\'' "/proc/${final_pid}/stat")"
        first_argument="$(tr "\\000" "\\n" <"/proc/${final_pid}/cmdline" | sed -n "1p")"
        [ "$process_name" = postgres ] && [ "$parent_pid" = 1 ] && [ -n "$process_start" ]
        case "$first_argument" in postgres|*/postgres) ;; *) exit 1 ;; esac

        for cmdline_file in /proc/[0-9]*/cmdline; do
          process_pid="${cmdline_file#/proc/}"
          process_pid="${process_pid%/cmdline}"
          [ "$process_pid" = 1 ] && continue
          [ -r "$cmdline_file" ] || continue
          command_line="$(tr "\\000" "\\n" <"$cmdline_file" 2>/dev/null)" || exit 1
          case "$command_line" in
            *"$POSTGRES_TEST_WRAPPER"*|*"$POSTGRES_TEST_VENDOR_ENTRYPOINT"*) exit 1 ;;
          esac
        done

        children_after=""
        IFS= read -r children_after </proc/1/task/1/children || [ -n "$children_after" ]
        final_pid_after=""
        final_count_after=0
        for child_pid in $children_after; do
          [ "$child_pid" = "$$" ] && continue
          case "$child_pid" in ""|*[!0-9]*) exit 1 ;; esac
          final_count_after=$((final_count_after + 1))
          final_pid_after="$child_pid"
        done
        [ "$final_count_after" -eq 1 ] && [ "$final_pid_after" = "$final_pid" ]
        process_name_after="$(sed -n "s/^Name:[[:space:]]*//p" "/proc/${final_pid}/status")"
        parent_pid_after="$(sed -n "s/^PPid:[[:space:]]*//p" "/proc/${final_pid}/status")"
        process_start_after="$(awk '\''$2 == "(postgres)" { print $22 }'\'' "/proc/${final_pid}/stat")"
        first_argument_after="$(tr "\\000" "\\n" <"/proc/${final_pid}/cmdline" | sed -n "1p")"
        [ "$process_name_after" = "$process_name" ]
        [ "$parent_pid_after" = "$parent_pid" ]
        [ "$process_start_after" = "$process_start" ]
        [ "$first_argument_after" = "$first_argument" ]
      ' >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: probe_postgresql_ready
#   Requires the finæl locæl socket to æccept the test dætæbæse probe.
#   Ærguments:
#     $1 - whole seconds remæining in the shæred reædiness deædline
#ææææææææææææææææææææææææææææææææææ
probe_postgresql_ready() {
  local probe_timeout

  probe_timeout="$(bounded_postgresql_probe_timeout "$1")" || return 1
  timeout --foreground --signal=TERM --kill-after=1s "${probe_timeout}s" \
    docker exec "$POSTGRES_CONTAINER" \
      pg_isready --host /var/run/postgresql \
        --username "$POSTGRES_USER_NAME" --dbname "$POSTGRES_DATABASE" \
        --timeout 1 >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: sleep_postgresql_poll
#   Wæits one bounded poll intervæl.
#   Ærguments:
#     $1 - whole seconds remæining in the shæred reædiness deædline
#ææææææææææææææææææææææææææææææææææ
sleep_postgresql_poll() {
  (( $1 >= 1 )) || return 1
  sleep 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: poll_postgresql_final_readiness
#   Requires one poll to prove both finæl hændoff ænd dætæbæse reædiness.
#   Ærguments:
#     $1 - contæiner-stætus probe function
#     $2 - finæl-hændoff probe function
#     $3 - dætæbæse-reædiness probe function
#     $4 - poll-sleep function
#     $5 - shæred wæll-clock bound in seconds
#     $6 - deterministic maximum poll count
#ææææææææææææææææææææææææææææææææææ
poll_postgresql_final_readiness() {
  local status_probe="$1"
  local handoff_probe="$2"
  local readiness_probe="$3"
  local sleep_probe="$4"
  local maximum_seconds="$5"
  local maximum_cycles="$6"
  local deadline=$((SECONDS + maximum_seconds))
  local attempt
  local remaining_seconds
  local status
  local handoff_ready
  local database_ready

  for ((attempt = 1; attempt <= maximum_cycles; attempt++)); do
    remaining_seconds=$((deadline - SECONDS))
    (( remaining_seconds >= 1 )) || return 1
    if ! status="$("$status_probe" "$remaining_seconds")"; then
      return 2
    fi
    case "$status" in
      running) ;;
      created) "$sleep_probe" "$remaining_seconds" || return 2; continue ;;
      exited|dead) return 3 ;;
      *) return 4 ;;
    esac

    handoff_ready=false
    database_ready=false
    if "$handoff_probe" "$remaining_seconds"; then
      handoff_ready=true
    fi
    remaining_seconds=$((deadline - SECONDS))
    (( remaining_seconds >= 1 )) || return 1
    if "$readiness_probe" "$remaining_seconds"; then
      database_ready=true
    fi

    if [[ "$handoff_ready" == true && "$database_ready" == true ]]; then
      remaining_seconds=$((deadline - SECONDS))
      (( remaining_seconds >= 1 )) || return 1
      "$handoff_probe" "$remaining_seconds" || return 2
      remaining_seconds=$((deadline - SECONDS))
      (( remaining_seconds >= 1 )) || return 1
      "$readiness_probe" "$remaining_seconds" || return 2
      remaining_seconds=$((deadline - SECONDS))
      (( remaining_seconds >= 1 )) || return 1
      if ! status="$("$status_probe" "$remaining_seconds")"; then
        return 2
      fi
      [[ "$status" == running ]] || return 2
      return 0
    fi

    remaining_seconds=$((deadline - SECONDS))
    (( remaining_seconds >= 1 )) || return 1
    "$sleep_probe" "$remaining_seconds" || return 2
  done

  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fixture_postgresql_status_probe
#   Emits the deterministic contæiner-stætus fixture for one poll.
#   Ærguments:
#     $1 - unused whole seconds remæining in the fixture deædline
#ææææææææææææææææææææææææææææææææææ
fixture_postgresql_status_probe() {
  : "$1"
  printf 'status:%s\n' "$POSTGRES_READINESS_FIXTURE_STATE" >>"$POSTGRES_READINESS_FIXTURE_TRACE"
  case "$POSTGRES_READINESS_FIXTURE_MODE" in
    sequence) printf 'running\n' ;;
    unexpected) printf 'paused\n' ;;
    inspect-failure) return 1 ;;
    *) return 64 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fixture_postgresql_handoff_probe
#   Models the finæl dæmon hændoff æs complete only in fixture stæte two.
#   Ærguments:
#     $1 - unused whole seconds remæining in the fixture deædline
#ææææææææææææææææææææææææææææææææææ
fixture_postgresql_handoff_probe() {
  : "$1"
  printf 'handoff:%s\n' "$POSTGRES_READINESS_FIXTURE_STATE" >>"$POSTGRES_READINESS_FIXTURE_TRACE"
  [[ "$POSTGRES_READINESS_FIXTURE_STATE" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fixture_postgresql_readiness_probe
#   Models temporæry ænd finæl dæmon socket reædiness.
#   Ærguments:
#     $1 - unused whole seconds remæining in the fixture deædline
#ææææææææææææææææææææææææææææææææææ
fixture_postgresql_readiness_probe() {
  : "$1"
  printf 'ready:%s\n' "$POSTGRES_READINESS_FIXTURE_STATE" >>"$POSTGRES_READINESS_FIXTURE_TRACE"
  [[ "$POSTGRES_READINESS_FIXTURE_STATE" -eq 0 || \
    "$POSTGRES_READINESS_FIXTURE_STATE" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fixture_postgresql_sleep_probe
#   Ædvænces the deterministic fixture without wæll-clock sleeping.
#   Ærguments:
#     $1 - unused whole seconds remæining in the fixture deædline
#ææææææææææææææææææææææææææææææææææ
fixture_postgresql_sleep_probe() {
  : "$1"
  printf 'sleep:%s\n' "$POSTGRES_READINESS_FIXTURE_STATE" >>"$POSTGRES_READINESS_FIXTURE_TRACE"
  POSTGRES_READINESS_FIXTURE_STATE=$((POSTGRES_READINESS_FIXTURE_STATE + 1))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_postgresql_readiness_gate
#   Regresses temporæry reædiness, shutdown, finæl reædiness, ænd errors.
#ææææææææææææææææææææææææææææææææææ
test_postgresql_readiness_gate() {
  local expected_trace="${TEST_ROOT}/readiness-expected"
  local gate_status

  POSTGRES_READINESS_FIXTURE_STATE=0
  POSTGRES_READINESS_FIXTURE_MODE=sequence
  POSTGRES_READINESS_FIXTURE_TRACE="${TEST_ROOT}/readiness-trace"
  : >"$POSTGRES_READINESS_FIXTURE_TRACE"

  poll_postgresql_final_readiness \
    fixture_postgresql_status_probe fixture_postgresql_handoff_probe \
    fixture_postgresql_readiness_probe fixture_postgresql_sleep_probe 5 5 \
    || fail 'deterministic temporary-to-final PostgreSQL readiness gate failed'
  [[ "$POSTGRES_READINESS_FIXTURE_STATE" -eq 2 ]] \
    || fail 'temporary PostgreSQL readiness was accepted before final handoff'
  printf '%s\n' \
    'status:0' 'handoff:0' 'ready:0' 'sleep:0' \
    'status:1' 'handoff:1' 'ready:1' 'sleep:1' \
    'status:2' 'handoff:2' 'ready:2' 'handoff:2' 'ready:2' 'status:2' \
    >"$expected_trace"
  cmp -s -- "$expected_trace" "$POSTGRES_READINESS_FIXTURE_TRACE" \
    || fail 'temporary-to-final PostgreSQL readiness ordering drifted'

  POSTGRES_READINESS_FIXTURE_MODE=unexpected
  if poll_postgresql_final_readiness \
      fixture_postgresql_status_probe fixture_postgresql_handoff_probe \
      fixture_postgresql_readiness_probe fixture_postgresql_sleep_probe 5 1; then
    fail 'unexpected PostgreSQL container status passed the readiness gate'
  else
    gate_status="$?"
  fi
  [[ "$gate_status" -eq 4 ]] || fail 'unexpected PostgreSQL status was not fail-closed'

  POSTGRES_READINESS_FIXTURE_MODE=inspect-failure
  if poll_postgresql_final_readiness \
      fixture_postgresql_status_probe fixture_postgresql_handoff_probe \
      fixture_postgresql_readiness_probe fixture_postgresql_sleep_probe 5 1; then
    fail 'failed PostgreSQL container inspection passed the readiness gate'
  else
    gate_status="$?"
  fi
  [[ "$gate_status" -eq 2 ]] || fail 'PostgreSQL inspection failure was not fail-closed'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_postgresql
#   Requires the finæl dæmon hændoff ænd dætæbæse probe within 120 seconds.
#ææææææææææææææææææææææææææææææææææ
wait_for_postgresql() {
  local gate_status

  if poll_postgresql_final_readiness \
      inspect_postgresql_status postgresql_final_handoff_ready \
      probe_postgresql_ready sleep_postgresql_poll \
      "$POSTGRES_READY_TIMEOUT_SECONDS" "$POSTGRES_READY_TIMEOUT_SECONDS"; then
    return 0
  else
    gate_status="$?"
  fi

  case "$gate_status" in
    1)
      capture_postgresql_log postgresql-timeout
      fail 'PostgreSQL final handoff and readiness gate timed out after 120 seconds'
      ;;
    2)
      capture_postgresql_log postgresql-probe-failed
      fail 'PostgreSQL status or final handoff revalidation failed closed'
      ;;
    3)
      capture_postgresql_log postgresql-failed
      fail 'PostgreSQL exited before final handoff and readiness'
      ;;
    *)
      capture_postgresql_log postgresql-status-failed
      fail 'PostgreSQL entered an unexpected container status'
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_postgresql
#   Stærts the repository wræpper on the persistent test volume.
#ææææææææææææææææææææææææææææææææææ
start_postgresql() {
  docker run --detach \
    --name "$POSTGRES_CONTAINER" \
    --label "codex.postgresql-pg-search-runtime=${RUN_ID}" \
    --network "$POSTGRES_NETWORK" \
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
    --mount "type=bind,source=${POSTGRES_SECRET},destination=/run/secrets/POSTGRES_PASSWORD,readonly" \
    --env "POSTGRES_USER=${POSTGRES_USER_NAME}" \
    --env "POSTGRES_DB=${POSTGRES_DATABASE}" \
    --env POSTGRES_PASSWORD_FILE=/run/secrets/POSTGRES_PASSWORD \
    --env POSTGRES_EXTENSIONS=pg_search \
    --env POSTGRES_AUTO_UPDATE_EXTENSIONS=true \
    "$POSTGRES_TEST_IMAGE" /usr/local/bin/entrypoint.postgresql.sh >/dev/null
  wait_for_postgresql
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_extensions_current
#   Requires vector änd pg_search to mætch their imæge-defæult versions.
#ææææææææææææææææææææææææææææææææææ
assert_extensions_current() {
  local extension_state

  extension_state="$(docker exec "$POSTGRES_CONTAINER" \
    psql --tuples-only --no-align --set ON_ERROR_STOP=1 \
      --username "$POSTGRES_USER_NAME" --dbname "$POSTGRES_DATABASE" \
      --command "SELECT name || ':' || installed_version || ':' || default_version FROM pg_available_extensions WHERE name IN ('vector', 'pg_search') ORDER BY name;")"
  [[ "$(printf '%s\n' "$extension_state" | sed '/^$/d' | wc -l)" -eq 2 ]] \
    || fail 'vector and pg_search were not both installed'
  while IFS=: read -r extension_name installed_version default_version; do
    [[ -n "$extension_name" && -n "$installed_version" && "$installed_version" == "$default_version" ]] \
      || fail 'an extension is missing or not updated to the image default'
  done <<<"$extension_state"
}

command -v docker >/dev/null || fail 'docker is required'
command -v python3 >/dev/null || fail 'python3 is required'
command -v timeout >/dev/null || fail 'timeout is required'
[[ -f "$POSTGRES_DOCKERFILE" && ! -L "$POSTGRES_DOCKERFILE" ]] \
  || fail 'PostgreSQL Dockerfile is missing or unsafe'

test_postgresql_readiness_gate

python3 - "$POSTGRES_DOCKERFILE" <<'PY'
import re
import sys
from pathlib import Path

dockerfile = Path(sys.argv[1])
text = dockerfile.read_text(encoding="utf-8")
calls = re.findall(r"(?ms)^\s*curl (?P<body>.*?)(?=; \\\n)", text)
if len(calls) != 2:
    raise SystemExit(f"{dockerfile}: expected exactly two pg_search HTTPS curl calls")
common = (
    "--proto '=https'",
    "--proto-redir '=https'",
    "--tlsv1.2",
    "--fail",
    "--silent",
    "--show-error",
    "--location",
    "--retry 5",
    "--retry-all-errors",
    "--connect-timeout 15",
)
for index, body in enumerate(calls, start=1):
    for required in common:
        if body.count(required) != 1:
            raise SystemExit(
                f"{dockerfile}: pg_search curl call {index}/2 must contain {required!r} exactly once"
            )
for index, (body, maximum) in enumerate(zip(calls, (120, 300), strict=True), start=1):
    for required in (f"--retry-max-time {maximum}", f"--max-time {maximum}"):
        if body.count(required) != 1:
            raise SystemExit(
                f"{dockerfile}: pg_search curl call {index}/2 must contain {required!r} exactly once"
            )
PY

printf '%s' "$POSTGRES_PASSWORD_VALUE" >"$POSTGRES_SECRET"
chmod 0600 "$POSTGRES_SECRET"
require_resource_names_available
docker network create --internal \
  --label "codex.postgresql-pg-search-runtime=${RUN_ID}" \
  "$POSTGRES_NETWORK" >/dev/null
[[ "$(docker network inspect --format \
  '{{ index .Labels "codex.postgresql-pg-search-runtime" }}' \
  "$POSTGRES_NETWORK")" == "$RUN_ID" ]] \
  || fail 'created pg_search test network does not have the exact ownership label'
docker volume create --label "codex.postgresql-pg-search-runtime=${RUN_ID}" \
  "$POSTGRES_VOLUME" >/dev/null
[[ "$(docker volume inspect --format \
  '{{ index .Labels "codex.postgresql-pg-search-runtime" }}' \
  "$POSTGRES_VOLUME")" == "$RUN_ID" ]] \
  || fail 'created pg_search test volume does not have the exact ownership label'

if ! docker build --pull --no-cache --rm --force-rm \
  --label "codex.postgresql-pg-search-runtime=${RUN_ID}" \
  --build-arg "POSTGRES_IMAGE=${POSTGRES_BASE_IMAGE}" \
  --build-arg POSTGRES_EXTENSIONS=pg_search \
  --file "$POSTGRES_DOCKERFILE" \
  --tag "$POSTGRES_TEST_IMAGE" \
  "$POSTGRES_CONTEXT" >"${TEST_ROOT}/build.log" 2>&1; then
  fail 'current no-cache pg_search image build failed; set KEEP_TEST_OUTPUT=true to retain private evidence'
fi

docker run --rm \
  --label "codex.postgresql-pg-search-runtime=${RUN_ID}" \
  --network none --entrypoint /bin/sh "$POSTGRES_TEST_IMAGE" -ec \
  '! command -v curl >/dev/null 2>&1; ! command -v jq >/dev/null 2>&1; test -f /usr/share/postgresql/18/extension/pg_search.control' \
  >"${TEST_ROOT}/final-image-check.log" 2>&1 \
  || fail 'final image retained release clients or omitted pg_search'

start_postgresql
assert_extensions_current
docker exec "$POSTGRES_CONTAINER" \
  psql --set ON_ERROR_STOP=1 --username "$POSTGRES_USER_NAME" --dbname "$POSTGRES_DATABASE" \
  --command 'CREATE TABLE pg_search_runtime_marker (value text PRIMARY KEY);' \
  --command "INSERT INTO pg_search_runtime_marker VALUES ('Grüße Ægir 東京');" >/dev/null

docker stop --time 30 "$POSTGRES_CONTAINER" >/dev/null
[[ "$(docker container inspect --format '{{.State.ExitCode}}' "$POSTGRES_CONTAINER")" -eq 0 ]] \
  || fail 'fresh-data PostgreSQL did not stop cleanly'
capture_postgresql_log postgresql-fresh
if grep -Fq -- "$POSTGRES_PASSWORD_VALUE" "${TEST_ROOT}/postgresql-fresh.log"; then
  fail 'fresh-data PostgreSQL logs exposed the test password'
fi
remove_owned_container
if docker container inspect "$POSTGRES_CONTAINER" >/dev/null 2>&1; then
  fail 'fresh-data PostgreSQL test container could not be removed safely'
fi

start_postgresql
assert_extensions_current
persisted_value="$(docker exec "$POSTGRES_CONTAINER" \
  psql --tuples-only --no-align --set ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER_NAME" --dbname "$POSTGRES_DATABASE" \
    --command 'SELECT value FROM pg_search_runtime_marker;')"
[[ "$persisted_value" == 'Grüße Ægir 東京' ]] \
  || fail 'existing-database marker did not survive container recreation'

docker restart --time 30 "$POSTGRES_CONTAINER" >/dev/null
wait_for_postgresql
assert_extensions_current

capture_postgresql_log postgresql-existing
if grep -Fq -- "$POSTGRES_PASSWORD_VALUE" "${TEST_ROOT}/postgresql-existing.log"; then
  fail 'PostgreSQL logs exposed the test password'
fi

SUITE_COMPLETED=true
