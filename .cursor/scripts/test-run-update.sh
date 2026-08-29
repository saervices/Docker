#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS ÆND TEST HÆRNESS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_RUN_SH="${1:-${TEST_REPO_ROOT}/run.sh}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/run-update.XXXXXX")"

PASS=0
FAIL=0
readonly ID_APP="sha256:$(printf '1%.0s' {1..64})"
readonly ID_WORKER="sha256:$(printf '2%.0s' {1..64})"
readonly ID_BUILT="sha256:$(printf '3%.0s' {1..64})"
readonly ID_LOCAL="sha256:$(printf '4%.0s' {1..64})"
readonly ID_OLD_APP="sha256:$(printf '5%.0s' {1..64})"
readonly ID_OLD_WORKER="sha256:$(printf '6%.0s' {1..64})"
readonly ID_OLD_LOCAL="sha256:$(printf '7%.0s' {1..64})"
readonly ID_RETAGGED_LOCAL="sha256:$(printf '8%.0s' {1..64})"

# Loæd functions without executing run.sh's finæl mæin cæll.
# shellcheck disable=SC1090
source <(sed '$d' "$TEST_RUN_SH")

# Replæce the ræw Linux clock, reæl sleeps, ænd coreutils timeouts with æ
# deterministic virtuæl clock. The production monotonicity checks stæy æctive.
# Docker invocætions still flow through the strict stub below.
completion_read_monotonic_seconds() {
  local output_name="$1"
  local -n output_ref="$output_name"
  case "${SCENARIO:-}" in
    post-start-clock-missing)
      return 1
      ;;
    post-start-clock-malformed)
      output_ref="1.5"
      ;;
    *)
      output_ref="$(<"${FIXTURE}/clock")"
      ;;
  esac
}

completion_wait_delay() {
  local current
  current="$(<"${FIXTURE}/clock")"
  if [[ "${SCENARIO:-}" == post-start-clock-backward ]]; then
    printf '%s\n' "$((current - 1))" >"${FIXTURE}/clock"
  else
    printf '%s\n' "$((current + 1))" >"${FIXTURE}/clock"
  fi
}

completion_run_bounded() {
  shift
  if [[ "${SCENARIO:-}" == post-start-query-timeout ]] && up_was_called; then
    return 124
  fi
  if [[ "${SCENARIO:-}" == post-start-final-query-timeout ]] && up_was_called && \
     [[ " $* " == *' ps --all --quiet '* ]]; then
    local bounded_ps_count
    bounded_ps_count=$(wc -l <"${FIXTURE}/bounded-ps-calls")
    printf 'x\n' >>"${FIXTURE}/bounded-ps-calls"
    if (( bounded_ps_count >= 2 )); then
      return 124
    fi
  fi
  "$@"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes every disposæble updæte fixture unless evidence is requested.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ "${KEEP_TEST_OUTPUT:-false}" == true ]]; then
    printf 'Evidence retained: %s\n' "$TEST_ROOT"
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pass
#   Records one successful regression cæse.
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled regression cæse ænd prints cæptured evidence.
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1"
  sed -n '1,200p' "$2"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_case
#   Executes one strict isolæted regression cæse.
#ææææææææææææææææææææææææææææææææææ
run_case() {
  local name="$1"
  local function_name="$2"
  local output="${TEST_ROOT}/${name}.out"
  local status

  set +e
  ( set -e; "$function_name" ) >"$output" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    pass "$name"
  else
    fail "$name" "$output"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reset_fixture
#   Creætes one Compose/env fixture ænd resets the Docker stub.
#ææææææææææææææææææææææææææææææææææ
reset_fixture() {
  local name="$1"
  FIXTURE="${TEST_ROOT}/${name}"
  COMPOSE_FILE="${FIXTURE}/docker-compose.main.yaml"
  ENV_FILE="${FIXTURE}/.env"
  CALL_LOG="${FIXTURE}/docker.calls"
  SENTINEL="${FIXTURE}/must-not-execute"
  mkdir -p -- "$FIXTURE"
  printf '%s\n' 'services:' '  app:' '    image: example/app:1' >"$COMPOSE_FILE"
  printf 'APP_NAME=fixture\nUNTRUSTED=$$(touch %s)\nRULE=Host(`example.invalid`)\n' \
    "$SENTINEL" >"$ENV_FILE"
  : >"$CALL_LOG"
  : >"${FIXTURE}/post-start-inspects"
  : >"${FIXTURE}/post-start-ps"
  : >"${FIXTURE}/post-start-image-inspects"
  : >"${FIXTURE}/post-start-restart-inspects"
  : >"${FIXTURE}/config-calls"
  : >"${FIXTURE}/bounded-ps-calls"
  : >"${FIXTURE}/gate-ps-order"
  printf '0\n' >"${FIXTURE}/clock"
  rm -f -- "${FIXTURE}/up-called" "${FIXTURE}/retag-active" \
    "${FIXTURE}/observed-frozen-images.json" "${FIXTURE}/snapshot-directory" \
    "${FIXTURE}/build-complete"

  SCENARIO="$name"
  FAIL_INSPECTION=false
  FAIL_CONFIG=false
  FAIL_PULL_IMAGE=""
  FAIL_BUILD=false
  MISSING_IMAGE=""
  LOCAL_IMAGE_PRODUCED=false
  POST_UP_JOB_EXIT=0
  DRY_RUN=false
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"example/app:1"},"worker":{"image":"example/worker:1"}}}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_completion_fixture
#   Renders one locælly built dæemon plus its finite one-shot dependency.
#ææææææææææææææææææææææææææææææææææ
configure_completion_fixture() {
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"local/app:1","build":{"context":"."},"depends_on":{"bootstrap":{"condition":"service_completed_successfully","required":true}}},"bootstrap":{"image":"local/app:1","pull_policy":"never"}}}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_post_start_completion_fixture
#   Renders one running dæemon ænd one consumerless labelled finite job.
#ææææææææææææææææææææææææææææææææææ
configure_post_start_completion_fixture() {
  local timeout_seconds="${1:-3}"
  RENDERED_JSON=$(jq -cn --arg timeout "$timeout_seconds" '
    {
      name: "fixture",
      services: {
        app: {
          image: "local/app:1",
          build: {context: "."}
        },
        oidc: {
          image: "local/app:1",
          pull_policy: "never",
          restart: "no",
          labels: {
            "de.saervices.run.completion-timeout-seconds": $timeout
          },
          depends_on: {
            app: {condition: "service_healthy", required: true}
          }
        }
      }
    }
  ')
}

configure_two_post_start_completion_fixture() {
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"local/app:1","build":{"context":"."}},"oidc":{"image":"local/app:1","pull_policy":"never","restart":"no","labels":{"de.saervices.run.completion-timeout-seconds":"3"},"depends_on":{"app":{"condition":"service_healthy","required":true}}},"audit":{"image":"example/worker:1","restart":"no","labels":{"de.saervices.run.completion-timeout-seconds":"3"},"depends_on":{"app":{"condition":"service_healthy","required":true}}}}}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_unequal_post_start_completion_fixture
#   Declæres one short ænd one longer independent completion deædline.
#ææææææææææææææææææææææææææææææææææ
configure_unequal_post_start_completion_fixture() {
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"local/app:1","build":{"context":"."}},"oidc":{"image":"local/app:1","pull_policy":"never","restart":"no","labels":{"de.saervices.run.completion-timeout-seconds":"1"},"depends_on":{"app":{"condition":"service_healthy","required":true}}},"audit":{"image":"example/worker:1","restart":"no","labels":{"de.saervices.run.completion-timeout-seconds":"3"},"depends_on":{"app":{"condition":"service_healthy","required":true}}}}}'
}

up_was_called() {
  [[ -e "${FIXTURE}/up-called" ]]
}

test_clock_value() {
  local -n output_ref="$1"
  output_ref="$(<"${FIXTURE}/clock")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stub_container_ids
#   Emits Compose contæiner IDs for the selected lifecycle scenærio.
#ææææææææææææææææææææææææææææææææææ
stub_container_ids() {
  local service="$1"
  if up_was_called; then
    if [[ "$SCENARIO" == post-start-unequal-deadlines && ( "$service" == oidc || "$service" == audit ) ]]; then
      printf '%s\n' "$service" >>"${FIXTURE}/gate-ps-order"
    fi
    case "$SCENARIO:$service" in
      post-start-missing:oidc)
        return 0
        ;;
      post-start-multiple:oidc)
        printf 'new-oidc-a\nnew-oidc-b\n'
        return 0
        ;;
      post-start-stale-container:oidc)
        printf 'current-oidc\n'
        return 0
        ;;
      post-start-identity-race:oidc)
        local ps_count
        ps_count=$(wc -l <"${FIXTURE}/post-start-ps")
        printf 'x\n' >>"${FIXTURE}/post-start-ps"
        if (( ps_count == 0 )); then
          printf 'new-oidc\n'
        else
          printf 'replacement-oidc\n'
        fi
        return 0
        ;;
      post-start-final-replacement:oidc)
        local final_ps_count
        final_ps_count=$(wc -l <"${FIXTURE}/post-start-ps")
        printf 'x\n' >>"${FIXTURE}/post-start-ps"
        if (( final_ps_count < 3 )); then
          printf 'new-oidc\n'
        else
          printf 'replacement-oidc\n'
        fi
        return 0
        ;;
      post-start-two-identity-race:oidc)
        local clock_value
        test_clock_value clock_value
        if (( clock_value == 0 )); then
          printf 'new-oidc\n'
        else
          printf 'replacement-oidc\n'
        fi
        return 0
        ;;
    esac
    printf 'new-%s\n' "$service"
    return 0
  fi
  case "$SCENARIO" in
    stopped|pull-failure|build-failure|inspection-failure|snapshot-signal-*)
      ;;
    stopped-external-start)
      [[ -e "${FIXTURE}/build-complete" ]] && printf 'current-%s\n' "$service"
      ;;
    partial)
      [[ "$service" == app ]] && printf 'current-app\n'
      ;;
    matching|stale-retry|stale-retry-source-after-down|normal-stopped|normal-paused|normal-restarting)
      printf 'current-%s\n' "$service"
      ;;
    completion-matching|completion-stale|completion-nonzero|completion-running|completion-created|completion-dead|completion-zero-scale|completion-post-up-failure)
      printf 'current-%s\n' "$service"
      ;;
    completion-missing)
      [[ "$service" == app ]] && printf 'current-app\n'
      ;;
    completion-scale-mismatch)
      if [[ "$service" == app ]]; then
        printf 'current-app\n'
      else
        printf 'current-bootstrap-a\ncurrent-bootstrap-b\n'
      fi
      ;;
    post-start-*)
      printf 'current-%s\n' "$service"
      ;;
    local-missing|local-never-dry-run|build-before-local-check)
      ;;
    *)
      return 1
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stub_image_id
#   Returns the current locæl imæge ID for one effective reference.
#ææææææææææææææææææææææææææææææææææ
stub_image_id() {
  [[ "$1" != "$MISSING_IMAGE" ]] || return 1
  case "$1" in
    example/app:1) printf '%s\n' "$ID_APP" ;;
    example/worker:1) printf '%s\n' "$ID_WORKER" ;;
    example/built:1) printf '%s\n' "$ID_BUILT" ;;
    local/app:1)
      [[ "$LOCAL_IMAGE_PRODUCED" == true ]] || return 1
      if [[ -e "${FIXTURE}/retag-active" ]]; then
        printf '%s\n' "$ID_RETAGGED_LOCAL"
        return 0
      fi
      if [[ "$SCENARIO" == post-start-image-drift || "$SCENARIO" == post-start-late-image-drift ]] && up_was_called; then
        local image_inspect_count
        image_inspect_count=$(wc -l <"${FIXTURE}/post-start-image-inspects")
        printf 'x\n' >>"${FIXTURE}/post-start-image-inspects"
        if [[ "$SCENARIO" == post-start-image-drift && "$image_inspect_count" -ge 0 ]] || \
           [[ "$SCENARIO" == post-start-late-image-drift && "$image_inspect_count" -gt 0 ]]; then
          printf '%s\n' "$ID_RETAGGED_LOCAL"
          return 0
        fi
      fi
      printf '%s\n' "$ID_LOCAL"
      ;;
    *) return 1 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stub_container_state
#   Returns running stæte ænd, when requested, the contæiner imæge ID.
#ææææææææææææææææææææææææææææææææææ
stub_container_state() {
  local format="$1"
  local container_id="$2"
  local service="${container_id##*-}"
  local image_id="$ID_APP"
  local status=running
  local running=true
  local exit_code=0
  local restart_policy=no

  if [[ "$SCENARIO" == stale-retry* && "$container_id" == current-* ]]; then
    case "$service" in
      app) image_id="$ID_OLD_APP" ;;
      worker) image_id="$ID_OLD_WORKER" ;;
    esac
  elif [[ "$service" == worker ]]; then
    image_id="$ID_WORKER"
  elif [[ "$service" == built ]]; then
    image_id="$ID_BUILT"
  fi
  if [[ "$SCENARIO" == normal-stopped && "$container_id" == current-worker ]]; then
    status=exited
    running=false
  fi
  if [[ "$SCENARIO" == normal-paused && "$container_id" == current-worker ]]; then
    status=paused
  fi
  if [[ "$SCENARIO" == normal-restarting && "$container_id" == current-worker ]]; then
    status=restarting
  fi
  if [[ "$SCENARIO" == completion-* ]]; then
    if [[ "$container_id" == *bootstrap* ]]; then
      service=bootstrap
      status=exited
      running=false
      image_id="$ID_LOCAL"
      if up_was_called; then
        exit_code="$POST_UP_JOB_EXIT"
      else
        case "$SCENARIO" in
          completion-stale)
            image_id="$ID_OLD_LOCAL"
            ;;
          completion-nonzero|completion-post-up-failure)
            exit_code=1
            ;;
          completion-running)
            status=running
            running=true
            ;;
          completion-created)
            status=created
            ;;
          completion-dead)
            status=dead
            ;;
        esac
      fi
    else
      image_id="$ID_LOCAL"
    fi
  fi
  if [[ "$SCENARIO" == post-start-* ]]; then
    image_id="$ID_LOCAL"
    if [[ "$container_id" == *oidc* || "$container_id" == *audit* ]]; then
      if [[ "$container_id" == *oidc* ]]; then
        service=oidc
        image_id="$ID_LOCAL"
      else
        service=audit
        image_id="$ID_WORKER"
      fi
      status=exited
      running=false
      if ! up_was_called; then
        if [[ "$SCENARIO" != post-start-matching ]]; then
          if [[ "$service" == oidc ]]; then
            image_id="$ID_OLD_LOCAL"
          else
            image_id="$ID_OLD_WORKER"
          fi
        fi
      else
        case "$SCENARIO" in
          post-start-success|post-start-clock-backward)
            if [[ "$format" == *'.State.Status'* ]]; then
              local inspect_count
              inspect_count=$(wc -l <"${FIXTURE}/post-start-inspects")
              printf 'x\n' >>"${FIXTURE}/post-start-inspects"
              if (( inspect_count == 0 )); then
                status=running
                running=true
              fi
            fi
            ;;
          post-start-nonzero)
            exit_code=17
            ;;
          post-start-timeout)
            status=running
            running=true
            ;;
          post-start-created)
            status=created
            ;;
          post-start-dead)
            status=dead
            ;;
          post-start-stale-image)
            image_id="$ID_OLD_LOCAL"
            ;;
          post-start-host-restart-drift)
            if [[ "$format" == *'.State.Status'* ]]; then
              local restart_inspect_count
              restart_inspect_count=$(wc -l <"${FIXTURE}/post-start-restart-inspects")
              printf 'x\n' >>"${FIXTURE}/post-start-restart-inspects"
              if (( restart_inspect_count > 0 )); then
                restart_policy=unless-stopped
              fi
            fi
            ;;
          post-start-final-host-restart-drift)
            if [[ "$service" == oidc && "$format" == *'.State.Status'* ]]; then
              local final_restart_inspect_count
              final_restart_inspect_count=$(wc -l <"${FIXTURE}/post-start-restart-inspects")
              printf 'x\n' >>"${FIXTURE}/post-start-restart-inspects"
              if (( final_restart_inspect_count >= 3 )); then
                restart_policy=unless-stopped
              fi
            fi
            ;;
          post-start-unequal-deadlines)
            if [[ "$service" == audit ]]; then
              local unequal_clock
              test_clock_value unequal_clock
              if (( unequal_clock < 2 )); then
                status=running
                running=true
              fi
            fi
            ;;
          post-start-state-race)
            if [[ "$format" == *'.State.Status'* ]]; then
              local state_race_count
              state_race_count=$(wc -l <"${FIXTURE}/post-start-inspects")
              printf 'x\n' >>"${FIXTURE}/post-start-inspects"
              if (( state_race_count > 0 )); then
                status=running
                running=true
              fi
            fi
            ;;
          post-start-two-identity-race)
            if [[ "$service" == audit && "$format" == *'.State.Status'* ]]; then
              local two_job_inspect_count
              two_job_inspect_count=$(wc -l <"${FIXTURE}/post-start-inspects")
              printf 'x\n' >>"${FIXTURE}/post-start-inspects"
              if (( two_job_inspect_count == 0 )); then
                status=running
                running=true
              fi
            fi
            ;;
        esac
      fi
    fi
  fi
  if [[ "$format" == *'.State.Status'* ]]; then
    if [[ "$SCENARIO" == post-start-malformed-state && "$container_id" == *oidc* ]] && up_was_called; then
      printf 'exited false 0 %s no unexpected\n' "$image_id"
      return 0
    fi
    printf '%s %s %s %s %s\n' "$status" "$running" "$exit_code" "$image_id" "$restart_policy"
  elif [[ "$format" == *'.Image'* ]]; then
    printf '%s %s %s\n' "$running" "$exit_code" "$image_id"
  else
    printf '%s\n' "$running"
  fi
}

render_frozen_stub_json() {
  local rendered="$RENDERED_JSON"
  local services svc image image_id

  services=$(jq -r '.services | keys[]' <<< "$rendered") || return 1
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    image=$(jq -r --arg svc "$svc" '.services[$svc].image // ""' <<< "$rendered") || return 1
    if [[ -z "$image" ]]; then
      image="fixture-${svc}"
    fi
    image_id=$(stub_image_id "$image") || return 1
    rendered=$(jq -c --arg svc "$svc" --arg image_id "$image_id" \
      '.services[$svc].image = $image_id' <<< "$rendered") || return 1
  done <<< "$services"
  if [[ "$SCENARIO" == *override-contract-drift* ]]; then
    rendered=$(jq -c '.services.injected = {image:"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"}' \
      <<< "$rendered") || return 1
  fi
  printf '%s\n' "$rendered"
}

compose_argument_after() {
  local wanted="$1"
  local output_name="$2"
  shift 2
  local previous="" argument
  local -n output_ref="$output_name"

  output_ref=""
  for argument in "$@"; do
    if [[ "$previous" == "$wanted" ]]; then
      output_ref="$argument"
    fi
    previous="$argument"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: docker
#   Deterministic Docker/Compose test double for run.sh's updæte flow.
#ææææææææææææææææææææææææææææææææææ
docker() {
  printf '%q ' "$@" >>"$CALL_LOG"
  printf '\n' >>"$CALL_LOG"

  if [[ "$1" == compose && "$2" == version ]]; then
    printf 'Docker Compose version fixture\n'
    return 0
  fi
  if [[ "$1" == compose ]]; then
    local service="" compose_path="" env_path="" project_directory="" project_name=""
    case " $* " in
      *' config --format json '*)
        [[ "$FAIL_CONFIG" != true ]] || return 1
        compose_argument_after -f compose_path "$@"
        if [[ "$compose_path" == */frozen-images.json ]]; then
          render_frozen_stub_json
          return
        fi
        if [[ "$compose_path" == /proc/*/fd/*/compose.yaml ]]; then
          /usr/bin/realpath -e -- "${compose_path%/*}" >"${FIXTURE}/snapshot-directory"
        fi
        printf '%s\n' "$RENDERED_JSON"
        local config_count
        config_count=$(wc -l <"${FIXTURE}/config-calls")
        printf 'x\n' >>"${FIXTURE}/config-calls"
        if (( config_count == 0 )); then
          case "$SCENARIO" in
            compose-source-swap)
              printf '%s\n' '  injected:' '    image: example/injected:1' >>"$COMPOSE_FILE"
              ;;
            env-source-swap)
              printf '%s\n' 'COMPOSE_PROJECT_NAME=drifted' >>"$ENV_FILE"
              ;;
            project-directory-swap)
              local old_project="${COMPOSE_FILE%/*}.old"
              /usr/bin/mv -- "${COMPOSE_FILE%/*}" "$old_project"
              /usr/bin/mkdir -- "${COMPOSE_FILE%/*}"
              /usr/bin/cp -- "$old_project/${COMPOSE_FILE##*/}" "$COMPOSE_FILE"
              /usr/bin/cp -- "$old_project/${ENV_FILE##*/}" "$ENV_FILE"
              ;;
          esac
        fi
        return 0
        ;;
      *' ps --all --quiet '*)
        if [[ "$FAIL_INSPECTION" == true ]]; then
          return 1
        fi
        service="${!#}"
        stub_container_ids "$service"
        return 0
        ;;
      *' build --pull --no-cache '*)
        [[ "$FAIL_BUILD" != true ]] || return 1
        if [[ "$SCENARIO" == snapshot-signal-* ]]; then
          kill -s "${SCENARIO##*-}" "$BASHPID"
        fi
        LOCAL_IMAGE_PRODUCED=true
        : >"${FIXTURE}/build-complete"
        return 0
        ;;
      *' down --remove-orphans '*)
        if [[ "$SCENARIO" == stale-retry-source-after-down ]]; then
          printf '%s\n' '  injected-after-down:' '    image: example/injected:1' >>"$COMPOSE_FILE"
        fi
        return 0
        ;;
      *' up -d --no-build --pull never '*)
        local first_compose_path="" previous_argument="" argument="" snapshot_directory=""
        for argument in "$@"; do
          if [[ "$previous_argument" == -f && -z "$first_compose_path" ]]; then
            first_compose_path="$argument"
          fi
          previous_argument="$argument"
        done
        compose_argument_after -f compose_path "$@"
        compose_argument_after --env-file env_path "$@"
        compose_argument_after --project-directory project_directory "$@"
        compose_argument_after --project-name project_name "$@"
        [[ "$compose_path" == */frozen-images.json && "$env_path" == /proc/*/fd/*/compose.env && \
           "$first_compose_path" == /proc/*/fd/*/compose.yaml && \
           "$project_directory" == "${COMPOSE_FILE%/*}" && "$project_name" == fixture ]] || return 1
        [[ "$(/usr/bin/stat -Lc '%a' -- "$first_compose_path")" == 600 && \
           "$(/usr/bin/stat -Lc '%a' -- "$env_path")" == 600 && \
           "$(/usr/bin/stat -Lc '%a' -- "$compose_path")" == 600 ]] || return 1
        snapshot_directory=$(/usr/bin/realpath -e -- "${compose_path%/*}") || return 1
        [[ "$(/usr/bin/stat -Lc '%a' -- "$snapshot_directory")" == 700 ]] || return 1
        printf '%s\n' "$snapshot_directory" >"${FIXTURE}/snapshot-directory"
        /usr/bin/cp -- "$compose_path" "${FIXTURE}/observed-frozen-images.json"
        : >"${FIXTURE}/up-called"
        if [[ "$SCENARIO" == post-start-pre-up-retag ]]; then
          : >"${FIXTURE}/retag-active"
        fi
        return 0
        ;;
    esac
    printf 'Unexpected Compose stub cæll: %q\n' "$*" >&2
    return 1
  fi
  if [[ "$1" == image && "$2" == inspect ]]; then
    stub_image_id "${!#}"
    return
  fi
  if [[ "$1" == pull ]]; then
    [[ "$2" != "$FAIL_PULL_IMAGE" ]]
    return
  fi
  if [[ "$1" == inspect ]]; then
    if [[ "$FAIL_INSPECTION" == true ]]; then
      return 1
    fi
    if [[ "$SCENARIO" == post-start-inspection-failure && "${!#}" == *oidc* ]] && up_was_called; then
      return 1
    fi
    stub_container_state "$2" "${!#}"
    return
  fi
  printf 'Unexpected Docker stub cæll: %q\n' "$*" >&2
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_no_restart
#   Proves neither shutdown nor stært wæs requested.
#ææææææææææææææææææææææææææææææææææ
assert_no_restart() {
  ! grep -Eq ' down | up ' "$CALL_LOG"
  ! up_was_called
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_one_reconciliation
#   Proves exæctly one full down/up reconciliætion wæs requested.
#ææææææææææææææææææææææææææææææææææ
assert_one_reconciliation() {
  [[ "$(grep -c ' down --remove-orphans ' "$CALL_LOG")" -eq 1 ]]
  [[ "$(grep -c ' up -d --no-build --pull never ' "$CALL_LOG")" -eq 1 ]]
  up_was_called
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stopped_project_stays_stopped
#   Successful pulls must not stært æ previously stopped project.
#ææææææææææææææææææææææææææææææææææ
test_stopped_project_stays_stopped() {
  reset_fixture stopped
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  [[ ! -e "$SENTINEL" ]]
  [[ "$(grep -c '^pull ' "$CALL_LOG")" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_matching_project_does_not_restart
#   Unchænged running imæges must not cæuse downtime.
#ææææææææææææææææææææææææææææææææææ
test_matching_project_does_not_restart() {
  reset_fixture matching
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  [[ ! -e "$SENTINEL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_matching_completion_job_does_not_restart
#   Æ completed exit-zero one-shot using the locæl build tæg must mætch without
#   pulling thæt tæg or restærting the running dæemon.
#ææææææææææææææææææææææææææææææææææ
test_matching_completion_job_does_not_restart() {
  reset_fixture completion-matching
  configure_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  grep -Eq ' build .*--pull .*--no-cache .*app' "$CALL_LOG"
  ! grep -Fq 'pull local/app:1' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stale_completion_job_reconciles_once
#   Æn old one-shot imæge ID requires one redeployment; the resulting stopped
#   exit-zero job must be accepted æs the desired post-up stæte.
#ææææææææææææææææææææææææææææææææææ
test_stale_completion_job_reconciles_once() {
  reset_fixture completion-stale
  configure_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
  ! grep -Fq 'pull local/app:1' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_failed_completion_job_reconciles
#   Æ stopped nonzero one-shot is unhealthy ænd must be reconciled.
#ææææææææææææææææææææææææææææææææææ
test_failed_completion_job_reconciles() {
  reset_fixture completion-nonzero
  configure_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_running_completion_job_reconciles
#   Æ finite one-shot thæt is still running is not æ completed dependency.
#ææææææææææææææææææææææææææææææææææ
test_running_completion_job_reconciles() {
  reset_fixture completion-running
  configure_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_unfinished_completion_states_reconcile
#   Creæted ænd deæd exit-zero contæiners hæve not proved successful completion.
#ææææææææææææææææææææææææææææææææææ
test_unfinished_completion_states_reconcile() {
  local scenario
  for scenario in completion-created completion-dead; do
    reset_fixture "$scenario"
    configure_completion_fixture
    pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
    assert_one_reconciliation
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_zero_scale_completion_job_fails_closed
#   Æ required finite dependency must hæve exæctly one provæble contæiner.
#ææææææææææææææææææææææææææææææææææ
test_zero_scale_completion_job_fails_closed() {
  reset_fixture completion-zero-scale
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"local/app:1","build":{"context":"."},"depends_on":{"bootstrap":{"condition":"service_completed_successfully","required":true}}},"bootstrap":{"image":"local/app:1","pull_policy":"never","deploy":{"replicas":0}}}}'
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_missing_completion_job_reconciles
#   Æ missing finite one-shot contæiner is æ deployment scæle mismætch.
#ææææææææææææææææææææææææææææææææææ
test_missing_completion_job_reconciles() {
  reset_fixture completion-missing
  configure_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_completion_job_scale_mismatch_reconciles
#   Multiple contæiners for æ single-replicæ one-shot require reconciliætion.
#ææææææææææææææææææææææææææææææææææ
test_completion_job_scale_mismatch_reconciles() {
  reset_fixture completion-scale-mismatch
  configure_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_up_completion_failure_fails_closed
#   Æ post-up nonzero one-shot must fæil finæl verificætion without æ retry loop.
#ææææææææææææææææææææææææææææææææææ
test_post_up_completion_failure_fails_closed() {
  reset_fixture completion-post-up-failure
  configure_completion_fixture
  POST_UP_JOB_EXIT=1
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_post_start_gate_failure
#   Runs one labelled-job scenærio ænd proves the runner fails æfter one
#   redeployment, never retrying or accepting uncertæin completion evidence.
#ææææææææææææææææææææææææææææææææææ
assert_post_start_gate_failure() {
  local scenario="$1"
  local timeout_seconds="${2:-3}"
  reset_fixture "$scenario"
  configure_post_start_completion_fixture "$timeout_seconds"
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_running_then_success
#   Æ newly creæted labelled job mæy run briefly, but only stable exit-zero
#   evidence from one new project contæiner completes the updæte.
#ææææææææææææææææææææææææææææææææææ
test_post_start_running_then_success() {
  reset_fixture post-start-success
  configure_post_start_completion_fixture 3
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
  local clock_value
  test_clock_value clock_value
  [[ "$clock_value" -eq 1 ]]
  [[ "$(wc -l <"${FIXTURE}/post-start-inspects")" -eq 5 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_matching_post_start_job_does_not_restart
#   Without imæge or lifecycle drift, existing successful completion evidence
#   remæins valid and no post-start gate or project restart is requested.
#ææææææææææææææææææææææææææææææææææ
test_matching_post_start_job_does_not_restart() {
  reset_fixture post-start-matching
  configure_post_start_completion_fixture 3
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  [[ ! -s "${FIXTURE}/post-start-inspects" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_multiple_post_start_services_keep_image_identity
#   Multiple labelled services use their own immutable desired imæge IDs;
#   associative iteration order mæy not cross-wire their proof.
#ææææææææææææææææææææææææææææææææææ
test_multiple_post_start_services_keep_image_identity() {
  reset_fixture post-start-two-success
  configure_two_post_start_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_completed_job_replacement_during_peer_wait_fails
#   Completion evidence from an eærlier job is rebound in one finæl snæpshot
#   æfter every peer finishes; replæcement during thæt wæit must fæil closed.
#ææææææææææææææææææææææææææææææææææ
test_completed_job_replacement_during_peer_wait_fails() {
  reset_fixture post-start-two-identity-race
  configure_two_post_start_completion_fixture
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_nonzero_fails_closed
#   Æ labelled job's nonzero exit is terminal fæilure.
#ææææææææææææææææææææææææææææææææææ
test_post_start_nonzero_fails_closed() {
  assert_post_start_gate_failure post-start-nonzero
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_timeout_fails_closed
#   Æ perpetuælly running labelled job is bounded by its canonical timeout.
#ææææææææææææææææææææææææææææææææææ
test_post_start_timeout_fails_closed() {
  assert_post_start_gate_failure post-start-timeout 3
  local clock_value
  test_clock_value clock_value
  [[ "$clock_value" -eq 3 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_cardinality_fails_closed
#   Missing or multiple project contæiners cannot prove one job completion.
#ææææææææææææææææææææææææææææææææææ
test_post_start_cardinality_fails_closed() {
  local scenario
  for scenario in post-start-missing post-start-multiple; do
    assert_post_start_gate_failure "$scenario"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_unfinished_states_fail_closed
#   Creæted and deæd states are neither running progress nor completion.
#ææææææææææææææææææææææææææææææææææ
test_post_start_unfinished_states_fail_closed() {
  local scenario
  for scenario in post-start-created post-start-dead; do
    assert_post_start_gate_failure "$scenario"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_identity_and_state_races_fail_closed
#   Reused or chænging contæiner identities and chænging inspected states are
#   rejected instead of accepting stale exit-zero evidence.
#ææææææææææææææææææææææææææææææææææ
test_post_start_identity_and_state_races_fail_closed() {
  local scenario
  for scenario in post-start-stale-container post-start-identity-race post-start-state-race; do
    assert_post_start_gate_failure "$scenario"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_image_drift_fails_closed
#   A stale contæiner image or a tag changing during the wait invalidates the
#   deployment identity proof.
#ææææææææææææææææææææææææææææææææææ
test_post_start_image_drift_fails_closed() {
  local scenario
  for scenario in post-start-stale-image post-start-image-drift post-start-late-image-drift; do
    assert_post_start_gate_failure "$scenario"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_pre_up_retag_uses_frozen_override
#   Æ tæg retægged inside the up window mæy invalidate the finæl gæte, but the
#   Compose up cæll itself must receive only the eærlier frozen imæge ID.
#ææææææææææææææææææææææææææææææææææ
test_pre_up_retag_uses_frozen_override() {
  reset_fixture post-start-pre-up-retag
  configure_post_start_completion_fixture 3
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_one_reconciliation
  jq -e --arg id "$ID_LOCAL" \
    '.services.app.image == $id and .services.oidc.image == $id and ([.. | strings | select(test("^local/app:"))] | length == 0)' \
    "${FIXTURE}/observed-frozen-images.json" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_override_contract_drift_fails_before_shutdown
#   The privæte override mæy only replæce existing service imæges; topology or
#   non-imæge drift in the merged render is rejected before project shutdown.
#ææææææææææææææææææææææææææææææææææ
test_override_contract_drift_fails_before_shutdown() {
  reset_fixture post-start-override-contract-drift
  configure_post_start_completion_fixture 3
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq ' down | up ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_snapshot_and_project_contract
#   Every mutæting Compose cæll uses privæte snæpshot bytes, one explicit
#   project identity, ænd æ mode-0600 imæge-ID override thæt is cleæned on exit.
#ææææææææææææææææææææææææææææææææææ
test_snapshot_and_project_contract() {
  local snapshot_directory
  reset_fixture stale-retry
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
  snapshot_directory="$(<"${FIXTURE}/snapshot-directory")"
  [[ "$snapshot_directory" == /tmp/run-update-snapshot.* ]]
  [[ ! -e "$snapshot_directory" && ! -L "$snapshot_directory" ]]
  ! grep -Fq -- "--env-file $ENV_FILE" "$CALL_LOG"
  grep -Fq -- "--project-name fixture" "$CALL_LOG"
  grep -Fq -- "--project-directory $FIXTURE" "$CALL_LOG"
  jq -e --arg app "$ID_APP" --arg worker "$ID_WORKER" \
    '.services == {app:{image:$app},worker:{image:$worker}}' \
    "${FIXTURE}/observed-frozen-images.json" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_snapshot_cleanup_on_signals
#   HUP, INT, ænd TERM during æ build remove only the descriptor-pinned
#   privæte snæpshot before the updæte subshell returns non-zero.
#ææææææææææææææææææææææææææææææææææ
test_snapshot_cleanup_on_signals() {
  local signal snapshot_directory
  for signal in hup int term; do
    reset_fixture "snapshot-signal-${signal}"
    RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"local/app:1","build":{"context":"."}}}}'
    if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
      return 1
    fi
    assert_no_restart
    snapshot_directory="$(<"${FIXTURE}/snapshot-directory")"
    [[ "$snapshot_directory" == /tmp/run-update-snapshot.* ]]
    [[ ! -e "$snapshot_directory" && ! -L "$snapshot_directory" ]]
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_shutdown_source_drift_uses_snapshot
#   Once shutdown begins, læter source edits cænnot enter the trænsæction; the
#   pinned Compose/env bytes still stært only the frozen service/imæge set.
#ææææææææææææææææææææææææææææææææææ
test_post_shutdown_source_drift_uses_snapshot() {
  reset_fixture stale-retry-source-after-down
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
  jq -e --arg app "$ID_APP" --arg worker "$ID_WORKER" \
    '.services == {app:{image:$app},worker:{image:$worker}}' \
    "${FIXTURE}/observed-frozen-images.json" >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_compose_env_and_project_swaps_fail_closed
#   Source-byte, env-byte, ænd project-directory identity swaps during the
#   initiæl render stop before Docker image or deployment mutation.
#ææææææææææææææææææææææææææææææææææ
test_compose_env_and_project_swaps_fail_closed() {
  local scenario project_root
  for scenario in compose-source-swap env-source-swap; do
    reset_fixture "$scenario"
    if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
      return 1
    fi
    assert_no_restart
    ! grep -Eq '^pull | build | ps --all --quiet ' "$CALL_LOG"
  done

  reset_fixture project-directory-swap
  project_root="${FIXTURE}/project"
  /usr/bin/mkdir -- "$project_root"
  /usr/bin/cp -- "$COMPOSE_FILE" "${project_root}/docker-compose.main.yaml"
  /usr/bin/cp -- "$ENV_FILE" "${project_root}/.env"
  COMPOSE_FILE="${project_root}/docker-compose.main.yaml"
  ENV_FILE="${project_root}/.env"
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq '^pull | build | ps --all --quiet ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_monotonic_clock_uncertainty_fails_closed
#   Missing ænd mælformed clocks stop before mutation; æ bæckwærd step during
#   the bounded gæte is rejected æfter exæctly one requested reconciliætion.
#ææææææææææææææææææææææææææææææææææ
test_monotonic_clock_uncertainty_fails_closed() {
  local scenario
  for scenario in post-start-clock-missing post-start-clock-malformed; do
    reset_fixture "$scenario"
    configure_post_start_completion_fixture 3
    if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
      return 1
    fi
    assert_no_restart
    ! grep -Eq '^pull | build | ps --all --quiet ' "$CALL_LOG"
  done

  reset_fixture post-start-clock-backward
  configure_post_start_completion_fixture 3
  printf '2\n' >"${FIXTURE}/clock"
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_runtime_restart_policy_drift_fails_closed
#   Stætic restart:no is insufficient: both runtime inspections must prove the
#   contæiner HostConfig restært policy is exæctly no.
#ææææææææææææææææææææææææææææææææææ
test_runtime_restart_policy_drift_fails_closed() {
  assert_post_start_gate_failure post-start-host-restart-drift
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_final_completion_identity_and_hostconfig_fail_closed
#   Single-job finæl reconciliætion retains the gæted ID, while single ænd
#   multi-job finæl evidence reject æ læte HostConfig restært-policy drift.
#ææææææææææææææææææææææææææææææææææ
test_final_completion_identity_and_hostconfig_fail_closed() {
  assert_post_start_gate_failure post-start-final-replacement
  assert_post_start_gate_failure post-start-final-host-restart-drift

  reset_fixture post-start-final-host-restart-drift
  configure_two_post_start_completion_fixture
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_unequal_completion_deadlines_do_not_starve
#   The one-second job is queried before its three-second peer; the completed
#   short job remæins identity-bound while the longer job finishes.
#ææææææææææææææææææææææææææææææææææ
test_unequal_completion_deadlines_do_not_starve() {
  local clock_value first_service
  reset_fixture post-start-unequal-deadlines
  configure_unequal_post_start_completion_fixture
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
  first_service="$(sed -n '1p' "${FIXTURE}/gate-ps-order")"
  [[ "$first_service" == oidc ]]
  test_clock_value clock_value
  [[ "$clock_value" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_final_reconciliation_query_is_bounded
#   Æ Compose query thæt hængs only æfter the successful gæte is stopped by
#   the gæte's remæining totæl monotonic deædline.
#ææææææææææææææææææææææææææææææææææ
test_final_reconciliation_query_is_bounded() {
  assert_post_start_gate_failure post-start-final-query-timeout
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_external_start_during_build_fails_closed
#   Æ project observed stopped before build is re-observed before mutætion; æn
#   externæl stært is not mislæbelled æs preserved-stopped success.
#ææææææææææææææææææææææææææææææææææ
test_external_start_during_build_fails_closed() {
  reset_fixture stopped-external-start
  RENDERED_JSON='{"name":"fixture","services":{"app":{"image":"local/app:1","build":{"context":"."}}}}'
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  grep -Eq ' build .*--pull .*--no-cache .*app' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_post_start_inspection_uncertainty_fails_closed
#   Docker errors and malformed runtime fields cannot satisfy the gate.
#ææææææææææææææææææææææææææææææææææ
test_post_start_inspection_uncertainty_fails_closed() {
  local scenario
  for scenario in post-start-inspection-failure post-start-malformed-state post-start-query-timeout; do
    assert_post_start_gate_failure "$scenario"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_invalid_post_start_contract
#   Proves rendered completion-label uncertainty stops before Docker mutation.
#ææææææææææææææææææææææææææææææææææ
assert_invalid_post_start_contract() {
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq ' ps --all --quiet | image inspect |^pull | build ' "$CALL_LOG"
  [[ ! -e "$SENTINEL" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_invalid_post_start_timeouts_fail_closed
#   Only a quoted canonical decimal from 1 through 3600 is accepted. Shell
#   metacharacters remain inert data and are never evaluated.
#ææææææææææææææææææææææææææææææææææ
test_invalid_post_start_timeouts_fail_closed() {
  local value scenario payload
  local -a invalid_values=("0" "01" "3601" "1e2")
  for value in "${invalid_values[@]}"; do
    scenario="post-start-invalid-timeout-${value//[^a-zA-Z0-9]/_}"
    reset_fixture "$scenario"
    configure_post_start_completion_fixture "$value"
    assert_invalid_post_start_contract
  done

  reset_fixture post-start-shell-timeout
  payload='$(touch '"$SENTINEL"')'
  configure_post_start_completion_fixture "$payload"
  assert_invalid_post_start_contract

  reset_fixture post-start-numeric-timeout
  configure_post_start_completion_fixture 3
  RENDERED_JSON=$(jq -c \
    '.services.oidc.labels["de.saervices.run.completion-timeout-seconds"] = 3' \
    <<< "$RENDERED_JSON")
  assert_invalid_post_start_contract
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_conflicting_post_start_contracts_fail_closed
#   Reserved-label aliases, wrong label structure, wrong restart/scale, and a
#   job already consumed as a dependency are all ambiguous and rejected.
#ææææææææææææææææææææææææææææææææææ
test_conflicting_post_start_contracts_fail_closed() {
  local mutation scenario
  local -a mutations=(
    '.services.oidc.labels["de.saervices.run.completion-shadow"] = "3"'
    '.services.oidc.labels = ["de.saervices.run.completion-timeout-seconds=3"]'
    '.services.oidc.restart = "unless-stopped"'
    '.services.app.depends_on.oidc = {condition:"service_completed_successfully",required:true}'
    '.services.app.depends_on.oidc = {condition:"service_started",required:true}'
    '.services.oidc.deploy.restart_policy = {condition:"any"}'
    '.services.oidc.deploy.restart_policy = {condition:"on-failure"}'
    '.services.oidc.scale = 0'
    '.services.oidc.scale = 2'
    '.services.oidc.deploy.replicas = 2'
  )
  local index=0
  for mutation in "${mutations[@]}"; do
    scenario="post-start-conflict-${index}"
    reset_fixture "$scenario"
    configure_post_start_completion_fixture 3
    RENDERED_JSON=$(jq -c "$mutation" <<< "$RENDERED_JSON")
    assert_invalid_post_start_contract
    index=$((index + 1))
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stopped_normal_service_reconciles
#   Non-job services must remæin running even with exit stætus zero.
#ææææææææææææææææææææææææææææææææææ
test_stopped_normal_service_reconciles() {
  reset_fixture normal-stopped
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_one_reconciliation
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_nonrunning_daemon_states_reconcile
#   Running=true is insufficient while Docker reports pæused or restærting.
#ææææææææææææææææææææææææææææææææææ
test_nonrunning_daemon_states_reconcile() {
  local scenario
  for scenario in normal-paused normal-restarting; do
    reset_fixture "$scenario"
    pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
    assert_one_reconciliation
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_missing_pull_never_image_fails_closed
#   Æ reæl updæte must require the locæl-only imæge without pulling its tæg.
#ææææææææææææææææææææææææææææææææææ
test_missing_pull_never_image_fails_closed() {
  reset_fixture local-missing
  RENDERED_JSON='{"name":"fixture","services":{"bootstrap":{"image":"local/app:1","pull_policy":"never"}}}'
  MISSING_IMAGE=local/app:1
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Fq 'pull local/app:1' "$CALL_LOG"
  grep -Fq 'image inspect --format=\{\{.Id\}\} local/app:1 ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_pull_never_dry_run_is_read_only
#   Dry-run reports the locæl check without pull, build, or imæge inspection.
#ææææææææææææææææææææææææææææææææææ
test_pull_never_dry_run_is_read_only() {
  reset_fixture local-never-dry-run
  RENDERED_JSON='{"name":"fixture","services":{"bootstrap":{"image":"local/app:1","pull_policy":"never"}}}'
  MISSING_IMAGE=local/app:1
  DRY_RUN=true
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  ! grep -Eq '^pull | build |image inspect ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_build_precedes_lexical_local_consumer_check
#   Æ lexicælly eærlier consumer of æ locæl tæg is checked only æfter the later
#   producer service finishes building thæt tæg.
#ææææææææææææææææææææææææææææææææææ
test_build_precedes_lexical_local_consumer_check() {
  reset_fixture build-before-local-check
  RENDERED_JSON='{"name":"fixture","services":{"abootstrap":{"image":"local/app:1","pull_policy":"never"},"zbuilder":{"image":"local/app:1","build":{"context":"."}}}}'
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  grep -Eq ' build .*--pull .*--no-cache .*zbuilder' "$CALL_LOG"
  ! grep -Fq 'pull local/app:1' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_partial_project_reconciles
#   Æ pærtiælly running project must be reconciled æs one unit.
#ææææææææææææææææææææææææææææææææææ
test_partial_project_reconciles() {
  reset_fixture partial
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  grep -Eq ' down .*--remove-orphans' "$CALL_LOG"
  grep -Fq ' up -d --no-build --pull never ' "$CALL_LOG"
  up_was_called
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_stale_retry_reconciles
#   Unchænged locæl tægs still require replæcing stæle contæiners.
#ææææææææææææææææææææææææææææææææææ
test_stale_retry_reconciles() {
  reset_fixture stale-retry
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  grep -Eq ' down .*--remove-orphans' "$CALL_LOG"
  grep -Fq ' up -d --no-build --pull never ' "$CALL_LOG"
  up_was_called
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_pull_failure_prevents_restart
#   One fæiled pull must fæil the run without pærtiæl redeployment.
#ææææææææææææææææææææææææææææææææææ
test_pull_failure_prevents_restart() {
  reset_fixture pull-failure
  FAIL_PULL_IMAGE=example/worker:1
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  [[ "$(grep -c '^pull ' "$CALL_LOG")" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_build_failure_prevents_restart
#   Æ custom-build fæilure must stop before shutdown.
#ææææææææææææææææææææææææææææææææææ
test_build_failure_prevents_restart() {
  reset_fixture build-failure
  RENDERED_JSON='{"name":"fixture","services":{"built":{"image":"example/built:1","build":{"context":"."}}}}'
  FAIL_BUILD=true
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  grep -Eq ' build .*--pull .*--no-cache .*built' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_inspection_failure_prevents_operations
#   Pre-updæte inspection errors must occur before pull, build, or shutdown.
#ææææææææææææææææææææææææææææææææææ
test_inspection_failure_prevents_operations() {
  reset_fixture inspection-failure
  FAIL_INSPECTION=true
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq '^pull | build ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_config_failure_prevents_operations
#   Compose render errors must stop before inspection or update operætions.
#ææææææææææææææææææææææææææææææææææ
test_config_failure_prevents_operations() {
  reset_fixture config-failure
  FAIL_CONFIG=true
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  ! grep -Eq '^pull | image inspect | inspect ' "$CALL_LOG"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_missing_desired_image_prevents_restart
#   Missing post-updæte image evidence must fæil before shutdown.
#ææææææææææææææææææææææææææææææææææ
test_missing_desired_image_prevents_restart() {
  reset_fixture matching
  MISSING_IMAGE=example/worker:1
  if pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"; then
    return 1
  fi
  assert_no_restart
  [[ "$(grep -c '^pull ' "$CALL_LOG")" -eq 2 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_dry_run_is_read_only
#   Dry-run renders ænd inspects only; it must not pull, build, or restart.
#ææææææææææææææææææææææææææææææææææ
test_dry_run_is_read_only() {
  reset_fixture matching
  DRY_RUN=true
  pull_docker_images "$COMPOSE_FILE" "$ENV_FILE"
  assert_no_restart
  ! grep -Eq '^pull | build ' "$CALL_LOG"
  [[ ! -e "$SENTINEL" ]]
}

run_case stopped-project-stays-stopped test_stopped_project_stays_stopped
run_case matching-project-no-restart test_matching_project_does_not_restart
run_case matching-completion-job-no-restart test_matching_completion_job_does_not_restart
run_case stale-completion-job-reconciles-once test_stale_completion_job_reconciles_once
run_case failed-completion-job-reconciles test_failed_completion_job_reconciles
run_case running-completion-job-reconciles test_running_completion_job_reconciles
run_case unfinished-completion-states-reconcile test_unfinished_completion_states_reconcile
run_case zero-scale-completion-job-fails-closed test_zero_scale_completion_job_fails_closed
run_case missing-completion-job-reconciles test_missing_completion_job_reconciles
run_case completion-job-scale-mismatch-reconciles test_completion_job_scale_mismatch_reconciles
run_case post-up-completion-failure-fails-closed test_post_up_completion_failure_fails_closed
run_case post-start-running-then-success test_post_start_running_then_success
run_case matching-post-start-job-no-restart test_matching_post_start_job_does_not_restart
run_case multiple-post-start-services-image-identity test_multiple_post_start_services_keep_image_identity
run_case completed-job-replacement-during-peer-wait-fails test_completed_job_replacement_during_peer_wait_fails
run_case post-start-nonzero-fails-closed test_post_start_nonzero_fails_closed
run_case post-start-timeout-fails-closed test_post_start_timeout_fails_closed
run_case post-start-cardinality-fails-closed test_post_start_cardinality_fails_closed
run_case post-start-unfinished-states-fail-closed test_post_start_unfinished_states_fail_closed
run_case post-start-identity-state-races-fail-closed test_post_start_identity_and_state_races_fail_closed
run_case post-start-image-drift-fails-closed test_post_start_image_drift_fails_closed
run_case pre-up-retag-uses-frozen-override test_pre_up_retag_uses_frozen_override
run_case override-contract-drift-fails-before-shutdown test_override_contract_drift_fails_before_shutdown
run_case snapshot-project-contract test_snapshot_and_project_contract
run_case snapshot-cleanup-on-signals test_snapshot_cleanup_on_signals
run_case post-shutdown-source-drift-uses-snapshot test_post_shutdown_source_drift_uses_snapshot
run_case compose-env-project-swaps-fail-closed test_compose_env_and_project_swaps_fail_closed
run_case monotonic-clock-uncertainty-fails-closed test_monotonic_clock_uncertainty_fails_closed
run_case runtime-restart-policy-drift-fails-closed test_runtime_restart_policy_drift_fails_closed
run_case final-completion-identity-hostconfig-fail-closed test_final_completion_identity_and_hostconfig_fail_closed
run_case unequal-completion-deadlines-no-starvation test_unequal_completion_deadlines_do_not_starve
run_case final-reconciliation-query-bounded test_final_reconciliation_query_is_bounded
run_case external-start-during-build-fails-closed test_external_start_during_build_fails_closed
run_case post-start-inspection-uncertainty-fails-closed test_post_start_inspection_uncertainty_fails_closed
run_case invalid-post-start-timeouts-fail-closed test_invalid_post_start_timeouts_fail_closed
run_case conflicting-post-start-contracts-fail-closed test_conflicting_post_start_contracts_fail_closed
run_case stopped-normal-service-reconciles test_stopped_normal_service_reconciles
run_case nonrunning-daemon-states-reconcile test_nonrunning_daemon_states_reconcile
run_case missing-pull-never-image-fails-closed test_missing_pull_never_image_fails_closed
run_case pull-never-dry-run-read-only test_pull_never_dry_run_is_read_only
run_case build-precedes-local-consumer-check test_build_precedes_lexical_local_consumer_check
run_case partial-project-reconciles test_partial_project_reconciles
run_case stale-retry-reconciles test_stale_retry_reconciles
run_case pull-failure-no-restart test_pull_failure_prevents_restart
run_case build-failure-no-restart test_build_failure_prevents_restart
run_case inspection-failure-no-operations test_inspection_failure_prevents_operations
run_case config-failure-no-operations test_config_failure_prevents_operations
run_case missing-image-no-restart test_missing_desired_image_prevents_restart
run_case dry-run-read-only test_dry_run_is_read_only

printf '\nResult: %d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  KEEP_TEST_OUTPUT=true
  printf 'Evidence retained for failed cases: %s\n' "$TEST_ROOT"
  exit 1
fi
