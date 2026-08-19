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

# Loæd functions without executing run.sh's finæl mæin cæll.
# shellcheck disable=SC1090
source <(sed '$d' "$TEST_RUN_SH")

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

  SCENARIO="$name"
  UP_CALLED=false
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
# FUNCTION: stub_container_ids
#   Emits Compose contæiner IDs for the selected lifecycle scenærio.
#ææææææææææææææææææææææææææææææææææ
stub_container_ids() {
  local service="$1"
  if [[ "$UP_CALLED" == true ]]; then
    printf 'new-%s\n' "$service"
    return 0
  fi
  case "$SCENARIO" in
    stopped|pull-failure|build-failure|inspection-failure)
      ;;
    partial)
      [[ "$service" == app ]] && printf 'current-app\n'
      ;;
    matching|stale-retry|normal-stopped|normal-paused|normal-restarting)
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
    example/app:1) printf 'sha256:new-app\n' ;;
    example/worker:1) printf 'sha256:new-worker\n' ;;
    example/built:1) printf 'sha256:new-built\n' ;;
    local/app:1)
      [[ "$LOCAL_IMAGE_PRODUCED" == true ]] || return 1
      printf 'sha256:new-local\n'
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
  local image_id="sha256:new-${service}"
  local status=running
  local running=true
  local exit_code=0

  if [[ "$SCENARIO" == stale-retry && "$container_id" == current-* ]]; then
    image_id="sha256:old-${service}"
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
      image_id=sha256:new-local
      if [[ "$UP_CALLED" == true ]]; then
        exit_code="$POST_UP_JOB_EXIT"
      else
        case "$SCENARIO" in
          completion-stale)
            image_id=sha256:old-local
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
      image_id=sha256:new-local
    fi
  fi
  if [[ "$format" == *'.State.Status'* ]]; then
    printf '%s %s %s %s\n' "$status" "$running" "$exit_code" "$image_id"
  elif [[ "$format" == *'.Image'* ]]; then
    printf '%s %s %s\n' "$running" "$exit_code" "$image_id"
  else
    printf '%s\n' "$running"
  fi
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
    local service=""
    case " $* " in
      *' config --format json '*)
        [[ "$FAIL_CONFIG" != true ]] || return 1
        printf '%s\n' "$RENDERED_JSON"
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
        LOCAL_IMAGE_PRODUCED=true
        return 0
        ;;
      *' down --remove-orphans '*)
        return 0
        ;;
      *' up -d --no-build --pull never '*)
        UP_CALLED=true
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
  [[ "$UP_CALLED" == false ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: assert_one_reconciliation
#   Proves exæctly one full down/up reconciliætion wæs requested.
#ææææææææææææææææææææææææææææææææææ
assert_one_reconciliation() {
  [[ "$(grep -c ' down --remove-orphans ' "$CALL_LOG")" -eq 1 ]]
  [[ "$(grep -c ' up -d --no-build --pull never ' "$CALL_LOG")" -eq 1 ]]
  [[ "$UP_CALLED" == true ]]
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
  [[ "$UP_CALLED" == true ]]
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
  [[ "$UP_CALLED" == true ]]
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
