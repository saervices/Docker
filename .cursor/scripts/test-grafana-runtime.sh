#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" \
  || { printf 'FAIL grafana-runtime: script directory resolution failed\n' >&2; exit 1; }
readonly TEST_SCRIPT_DIR
TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)" \
  || { printf 'FAIL grafana-runtime: repository root resolution failed\n' >&2; exit 1; }
readonly TEST_REPO_ROOT
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/grafana-runtime.XXXXXX")" \
  || { printf 'FAIL grafana-runtime: private fixture creation failed\n' >&2; exit 1; }
readonly TEST_ROOT
TEST_ROOT_IDENTITY="$(stat -Lc '%d:%i' -- "$TEST_ROOT")" \
  || { printf 'FAIL grafana-runtime: private fixture identity capture failed\n' >&2; exit 1; }
readonly TEST_ROOT_IDENTITY
RUN_ID="${TEST_ROOT##*.}-${BASHPID}"
readonly RUN_ID="${RUN_ID,,}"
readonly TEST_PREFIX="codex-grafana-runtime-${RUN_ID}"
readonly OWNERSHIP_LABEL="codex.grafana-runtime"
readonly IMAGE_NAME="codex-grafana-runtime:${RUN_ID}"
readonly POLICY_IMAGE_NAME="codex-grafana-sso-policy:${RUN_ID}"
readonly GRAFANA_BASE_IMAGE="${GRAFANA_TEST_BASE_IMAGE:-grafana/grafana:latest}"
readonly GRAFANA_GO_IMAGE="${GRAFANA_TEST_GO_IMAGE:-docker.io/library/golang:alpine}"
readonly GRAFANA_SSO_POLICY_GO_IMAGE="${GRAFANA_TEST_SSO_POLICY_GO_IMAGE:-${GRAFANA_GO_IMAGE}}"
readonly POSTGRES_IMAGE="${GRAFANA_TEST_POSTGRES_IMAGE:-postgres:18}"
readonly POSTGRES_MAINTENANCE_IMAGE="${GRAFANA_TEST_POSTGRES_MAINTENANCE_IMAGE:-postgres:18}"
readonly NETWORK_NAME="${TEST_PREFIX}-backend"
readonly MERGED_FRONTEND_NETWORK="${TEST_PREFIX}-merged-frontend"
readonly MERGED_BACKEND_NETWORK="${TEST_PREFIX}-merged-backend"
readonly DATABASE_VOLUME="${TEST_PREFIX}-database"
readonly GRAFANA_DATA_VOLUME="${TEST_PREFIX}-data"
readonly GRAFANA_STATE_VOLUME="${TEST_PREFIX}-bootstrap-state"
readonly ROLE_GRAFANA_DATA_VOLUME="${TEST_PREFIX}-role-data"
readonly MERGED_DATABASE_VOLUME="${TEST_PREFIX}-merged-database"
readonly MERGED_GRAFANA_DATA_VOLUME="${TEST_PREFIX}-merged-data"
readonly MERGED_GRAFANA_STATE_VOLUME="${TEST_PREFIX}-merged-bootstrap-state"
readonly MERGED_BACKUP_VOLUME="${TEST_PREFIX}-merged-backup"
readonly MERGED_RESTORE_VOLUME="${TEST_PREFIX}-merged-restore"
readonly POSTGRES_CONTAINER="${TEST_PREFIX}-postgresql"
readonly VOLUME_INIT_CONTAINER="${TEST_PREFIX}-volume-init"
readonly BOOTSTRAP_CONTAINER="${TEST_PREFIX}-bootstrap"
readonly BOOTSTRAP_SIGNAL_CONTAINER="${TEST_PREFIX}-bootstrap-signal"
readonly BOOTSTRAP_SIGNAL_MARKER_CONTAINER="${TEST_PREFIX}-bootstrap-signal-marker"
readonly BOOTSTRAP_REPEAT_CONTAINER="${TEST_PREFIX}-bootstrap-repeat"
readonly MARKER_CHECK_CONTAINER="${TEST_PREFIX}-marker-check"
readonly CLI_REJECT_CONTAINER="${TEST_PREFIX}-cli-reject"
readonly CLI_RESET_CONTAINER="${TEST_PREFIX}-cli-reset"
readonly APP_FORM_CONTAINER="${TEST_PREFIX}-app-form"
readonly APP_LOCKED_CONTAINER="${TEST_PREFIX}-app-locked"
readonly PEER_PROBE_CONTAINER="${TEST_PREFIX}-peer-probe"
readonly ROLE_OAUTH_BUILD_CONTAINER="${TEST_PREFIX}-role-oauth-build"
readonly ROLE_OAUTH_CONTAINER="${TEST_PREFIX}-role-oauth"
readonly ROLE_APP_CONTAINER="${TEST_PREFIX}-role-app"
readonly ROLE_VOLUME_INIT_CONTAINER="${TEST_PREFIX}-role-volume-init"
readonly APP_IMAGE_PROBE_CONTAINER="${TEST_PREFIX}-app-image-probe"
readonly POLICY_IMAGE_PROBE_CONTAINER="${TEST_PREFIX}-policy-image-probe"
readonly RUNTIME_ROOT="${TEST_ROOT}/runtime"
readonly EVIDENCE_ROOT="${TEST_ROOT}/evidence"
readonly MERGED_ROOT="${RUNTIME_ROOT}/merged"
readonly MERGED_SOURCE="${MERGED_ROOT}/source"
readonly MERGED_RUNNER="${MERGED_ROOT}/runner"
readonly MERGED_APP_DIR="${MERGED_RUNNER}/Grafana"
readonly MERGED_OVERRIDE_FILE="${MERGED_APP_DIR}/docker-compose.runtime-test.yaml"
readonly MERGED_SOURCE_CONFIG_FILE="${EVIDENCE_ROOT}/merged-source-config.json"
readonly MERGED_CONFIG_FILE="${EVIDENCE_ROOT}/merged-config.json"
readonly MERGED_APP_NAME="gfr${RUN_ID//-/}"
readonly MERGED_PROJECT_NAME="${TEST_PREFIX}-merged"
readonly MERGED_APP_CONTAINER="${MERGED_APP_NAME}"
readonly MERGED_POSTGRES_CONTAINER="${MERGED_APP_NAME}-postgresql"
readonly MERGED_BOOTSTRAP_CONTAINER="${MERGED_APP_NAME}-bootstrap"
readonly MERGED_MIGRATOR_CONTAINER="${MERGED_APP_NAME}-migrator"
readonly MERGED_POLICY_CONTAINER="${MERGED_APP_NAME}-grafana-sso-policy"
readonly MERGED_MAINTENANCE_CONTAINER="${MERGED_APP_NAME}-postgresql_maintenance"
readonly MERGED_VOLUME_INIT_CONTAINER="${TEST_PREFIX}-merged-volume-init"
readonly MERGED_MARKER_CHECK_CONTAINER="${TEST_PREFIX}-merged-marker-check"
readonly MERGED_POSTGRES_IMAGE="codex-grafana-postgresql:${RUN_ID}"
readonly MERGED_MAINTENANCE_IMAGE="codex-grafana-postgresql-maintenance:${RUN_ID}"
readonly SECRET_ROOT="${RUNTIME_ROOT}/secrets"
readonly POSTGRES_PASSWORD_FILE="${SECRET_ROOT}/POSTGRES_PASSWORD"
readonly GRAFANA_SECRET_KEY_FILE="${SECRET_ROOT}/GRAFANA_SECRET_KEY"
readonly GRAFANA_ADMIN_PASSWORD_FILE="${SECRET_ROOT}/GRAFANA_ADMIN_PASSWORD"
readonly GRAFANA_OIDC_CLIENT_ID_FILE="${SECRET_ROOT}/GRAFANA_OIDC_CLIENT_ID"
readonly GRAFANA_OIDC_CLIENT_SECRET_FILE="${SECRET_ROOT}/GRAFANA_OIDC_CLIENT_SECRET"
readonly RESET_PASSWORD_FILE="${RUNTIME_ROOT}/reset-password"
readonly LOGIN_PAYLOAD_FILE="${RUNTIME_ROOT}/login.json"
readonly BASIC_HEADER_FILE="${RUNTIME_ROOT}/basic-header"
readonly ADMIN_COOKIE_FILE="${RUNTIME_ROOT}/admin-cookie"
readonly ADMIN_COOKIE_HEADER_FILE="${RUNTIME_ROOT}/admin-cookie-header"
readonly SSO_MUTATION_FILE="${RUNTIME_ROOT}/sso-mutation.json"
readonly ROLE_OAUTH_SOURCE_FILE="${RUNTIME_ROOT}/role-oauth-mock.go"
readonly ROLE_OAUTH_BINARY_FILE="${RUNTIME_ROOT}/role-oauth-mock"
readonly BOOTSTRAP_WRAPPER_FILE="${RUNTIME_ROOT}/grafana-bootstrap-vendor-wrapper.sh"
readonly MIGRATOR_WRAPPER_FILE="${RUNTIME_ROOT}/grafana-migrator-vendor-wrapper.sh"
readonly HOST_USER_ID="$(id -u)"
readonly HOST_GROUP_ID="$(id -g)"
readonly TEST_APP_UID=472
readonly TEST_APP_GID=472
readonly POSTGRES_PASSWORD_VALUE="grafana-postgresql-${RUN_ID}-safe-password"
readonly GRAFANA_SECRET_KEY_VALUE="grafana-secret-key-${RUN_ID}-0123456789abcdefghijklmnopqrstuvwxyz"
readonly GRAFANA_ADMIN_PASSWORD_VALUE="grafana-admin-${RUN_ID}-initial-password"
readonly GRAFANA_OIDC_CLIENT_ID_VALUE="grafana-runtime-${RUN_ID}"
readonly GRAFANA_OIDC_CLIENT_SECRET_VALUE="grafana-oidc-${RUN_ID}-safe-client-secret"
readonly RESET_PASSWORD_VALUE="grafana-admin-${RUN_ID}-rotated-password"
readonly DATABASE_USER="grafana"
readonly DATABASE_NAME="grafana"
readonly ADMIN_USER="admin"
readonly APP_DOMAIN="grafana.runtime.invalid"
readonly AUTHENTIK_DOMAIN="authentik.runtime.invalid"
readonly EXPECTED_ROLE_ATTRIBUTE_PATH="contains(groups[*], 'grafana-admins') && !contains(groups[*], 'grafana-editors') && !contains(groups[*], 'grafana-viewers') && 'GrafanaAdmin' || !contains(groups[*], 'grafana-admins') && contains(groups[*], 'grafana-editors') && !contains(groups[*], 'grafana-viewers') && 'Editor' || !contains(groups[*], 'grafana-admins') && !contains(groups[*], 'grafana-editors') && contains(groups[*], 'grafana-viewers') && 'Viewer'"
readonly -a SSO_PROVIDERS=(generic_oauth github gitlab google azuread okta)
readonly KEEP_TEST_OUTPUT="${KEEP_TEST_OUTPUT:-false}"
readonly START_EPOCH="$(date +%s)"
TEST_COUNT=0
SUITE_COMPLETED=false
MERGED_COMPOSE_READY=false
MERGED_STARTED=false

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs one informational suite message.
#   Arguments:
#     $1 - message
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf 'INFO grafana-runtime: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Records one completed assertion without exposing test credentials.
#   Arguments:
#     $1 - assertion description
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf 'PASS grafana-runtime [%d]: %s\n' "$TEST_COUNT" "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs one failure without printing secret content.
#   Arguments:
#     $1 - failure description
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf 'FAIL grafana-runtime: %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Stops the suite without printing secret content.
#   Arguments:
#     $1 - failure description
#ææææææææææææææææææææææææææææææææææ
fail() {
  log_error "$*"
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_container
#   Removes one exact container only when its ownership label matches.
#   Arguments:
#     $1 - container name or ID
#ææææææææææææææææææææææææææææææææææ
remove_owned_container() {
  local container_name="$1"
  local owner_label

  if ! owner_label="$(docker container inspect --format \
    '{{ index .Config.Labels "codex.grafana-runtime" }}' \
    "$container_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker container rm --force "$container_name" >/dev/null 2>&1 || true
  ! docker container inspect "$container_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_volume
#   Removes the exact PostgreSQL volume only when its ownership label matches.
#   Arguments:
#     $1 - volume name
#ææææææææææææææææææææææææææææææææææ
remove_owned_volume() {
  local volume_name="$1"
  local owner_label

  if ! owner_label="$(docker volume inspect --format \
    '{{ index .Labels "codex.grafana-runtime" }}' \
    "$volume_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker volume rm "$volume_name" >/dev/null 2>&1 || true
  ! docker volume inspect "$volume_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_network
#   Removes the exact backend network only when its ownership label matches.
#   Arguments:
#     $1 - network name
#ææææææææææææææææææææææææææææææææææ
remove_owned_network() {
  local network_name="$1"
  local owner_label

  if ! owner_label="$(docker network inspect --format \
    '{{ index .Labels "codex.grafana-runtime" }}' \
    "$network_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker network rm "$network_name" >/dev/null 2>&1 || true
  ! docker network inspect "$network_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_image
#   Removes one unique test image only when its ownership label matches.
#   Ærguments:
#     $1 - imæge reference
#ææææææææææææææææææææææææææææææææææ
remove_owned_image() {
  local image_name="$1"
  local owner_label

  if ! owner_label="$(docker image inspect --format \
    '{{ index .Config.Labels "codex.grafana-runtime" }}' \
    "$image_name" 2>/dev/null)"; then
    return 0
  fi
  [[ "$owner_label" == "$RUN_ID" ]] || return 1
  docker image rm --force "$image_name" >/dev/null 2>&1 || true
  ! docker image inspect "$image_name" >/dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: merged_compose
#   Runs Docker Compose only for the isolated rendered Grafana closure.
#   Ærguments:
#     $@ - Docker Compose subcommand and arguments
#ææææææææææææææææææææææææææææææææææ
merged_compose() {
  (
    cd -- "$MERGED_APP_DIR"
    env \
    APP_UID="$TEST_APP_UID" \
    APP_GID="$HOST_GROUP_ID" \
    APP_NAME="$MERGED_APP_NAME" \
    APP_IMAGE="$IMAGE_NAME" \
    GRAFANA_SSO_POLICY_IMAGE="$POLICY_IMAGE_NAME" \
    GRAFANA_SSO_POLICY_GO_IMAGE="$GRAFANA_SSO_POLICY_GO_IMAGE" \
    POSTGRES_IMAGE="$POSTGRES_IMAGE" \
    POSTGRES_MAINTENANCE_IMAGE="$POSTGRES_MAINTENANCE_IMAGE" \
    POSTGRES_UID=999 \
    POSTGRES_GID=999 \
    docker compose \
      --project-name "$MERGED_PROJECT_NAME" \
      --env-file .env \
      --file docker-compose.main.yaml \
      --file "$MERGED_OVERRIDE_FILE" \
      "$@"
  )
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: merged_compose_bounded
#   Runs one isolated Compose operation with an explicit wall-clock bound.
#   Ærguments:
#     $1 - timeout value accepted by timeout(1)
#   remaining arguments - Docker Compose subcommand and arguments
#ææææææææææææææææææææææææææææææææææ
merged_compose_bounded() {
  local timeout_value="$1"
  shift

  (
    cd -- "$MERGED_APP_DIR"
    env \
    APP_UID="$TEST_APP_UID" \
    APP_GID="$HOST_GROUP_ID" \
    APP_NAME="$MERGED_APP_NAME" \
    APP_IMAGE="$IMAGE_NAME" \
    GRAFANA_SSO_POLICY_IMAGE="$POLICY_IMAGE_NAME" \
    GRAFANA_SSO_POLICY_GO_IMAGE="$GRAFANA_SSO_POLICY_GO_IMAGE" \
    POSTGRES_IMAGE="$POSTGRES_IMAGE" \
    POSTGRES_MAINTENANCE_IMAGE="$POSTGRES_MAINTENANCE_IMAGE" \
    POSTGRES_UID=999 \
    POSTGRES_GID=999 \
    timeout --foreground "$timeout_value" docker compose \
      --project-name "$MERGED_PROJECT_NAME" \
      --env-file .env \
      --file docker-compose.main.yaml \
      --file "$MERGED_OVERRIDE_FILE" \
      "$@"
  )
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Captures private diagnostics and removes only exact owned test resources.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local original_status="$?"
  local cleanup_status=0
  local container_inventory="${TEST_ROOT}/cleanup-container-inventory"
  local container_name
  local current_identity=''
  local elapsed
  local final_status="$original_status"
  local policy_anonymous_volume=''
  local policy_owner_label=''
  local resource_id
  local volume_labels=''

  trap - EXIT HUP INT TERM
  set +e
  if docker info >/dev/null 2>&1; then
    if [[ "$MERGED_COMPOSE_READY" == true \
      && -f "$MERGED_OVERRIDE_FILE" \
      && -f "${MERGED_APP_DIR}/docker-compose.main.yaml" ]]; then
      policy_owner_label="$(docker container inspect --format \
        '{{ index .Config.Labels "codex.grafana-runtime" }}' \
        "$MERGED_POLICY_CONTAINER" 2>/dev/null)"
      if [[ "$policy_owner_label" == "$RUN_ID" ]]; then
        policy_anonymous_volume="$(docker container inspect \
          "$MERGED_POLICY_CONTAINER" 2>/dev/null \
          | jq --raw-output \
            '.[0].Mounts[] | select(.Type == "volume" and .Destination == "/var/lib/postgresql") | .Name')" \
          || cleanup_status=1
        [[ "$policy_anonymous_volume" != *$'\n'* ]] || cleanup_status=1
      fi
      if [[ -d "$EVIDENCE_ROOT" ]]; then
        merged_compose logs --no-color \
          >"${EVIDENCE_ROOT}/cleanup-merged-compose.log" 2>&1 || true
      fi
      merged_compose_bounded 120s down --remove-orphans \
        >/dev/null 2>&1 || cleanup_status=1
      MERGED_STARTED=false
    fi
    for container_name in \
      "$APP_IMAGE_PROBE_CONTAINER" "$POLICY_IMAGE_PROBE_CONTAINER" \
      "$ROLE_APP_CONTAINER" "$ROLE_OAUTH_CONTAINER" \
      "$ROLE_OAUTH_BUILD_CONTAINER" "$ROLE_VOLUME_INIT_CONTAINER" \
      "$PEER_PROBE_CONTAINER" \
      "$APP_LOCKED_CONTAINER" "$APP_FORM_CONTAINER" \
      "$CLI_RESET_CONTAINER" "$CLI_REJECT_CONTAINER" \
      "$MARKER_CHECK_CONTAINER" "$BOOTSTRAP_REPEAT_CONTAINER" \
      "$BOOTSTRAP_SIGNAL_MARKER_CONTAINER" "$BOOTSTRAP_SIGNAL_CONTAINER" \
      "$BOOTSTRAP_CONTAINER" "$POSTGRES_CONTAINER" \
      "$VOLUME_INIT_CONTAINER" \
      "$MERGED_APP_CONTAINER" "$MERGED_BOOTSTRAP_CONTAINER" \
      "$MERGED_MIGRATOR_CONTAINER" \
      "$MERGED_POLICY_CONTAINER" \
      "$MERGED_MAINTENANCE_CONTAINER" "$MERGED_POSTGRES_CONTAINER" \
      "$MERGED_VOLUME_INIT_CONTAINER" "$MERGED_MARKER_CHECK_CONTAINER"; do
      if [[ -d "$EVIDENCE_ROOT" ]] \
        && docker container inspect "$container_name" >/dev/null 2>&1; then
        docker logs "$container_name" \
          >"${EVIDENCE_ROOT}/cleanup-${container_name##${TEST_PREFIX}-}.log" 2>&1 || true
      fi
      remove_owned_container "$container_name" || cleanup_status=1
    done
    if docker container ls --all --quiet \
      --filter "label=${OWNERSHIP_LABEL}=${RUN_ID}" \
      >"$container_inventory" 2>/dev/null; then
      while IFS= read -r resource_id; do
        [[ -n "$resource_id" ]] || continue
        remove_owned_container "$resource_id" || cleanup_status=1
      done <"$container_inventory"
    else
      cleanup_status=1
    fi
    if [[ -n "$policy_anonymous_volume" ]]; then
      volume_labels="$(docker volume inspect --format '{{json .Labels}}' \
        "$policy_anonymous_volume" 2>/dev/null)" || cleanup_status=1
      if jq --exit-status \
        'type == "object" and has("com.docker.volume.anonymous")' \
        <<<"$volume_labels" >/dev/null 2>&1; then
        docker volume rm "$policy_anonymous_volume" >/dev/null 2>&1 \
          || cleanup_status=1
      else
        cleanup_status=1
      fi
    fi
    remove_owned_volume "$DATABASE_VOLUME" || cleanup_status=1
    remove_owned_volume "$GRAFANA_DATA_VOLUME" || cleanup_status=1
    remove_owned_volume "$GRAFANA_STATE_VOLUME" || cleanup_status=1
    remove_owned_volume "$ROLE_GRAFANA_DATA_VOLUME" || cleanup_status=1
    remove_owned_volume "$MERGED_DATABASE_VOLUME" || cleanup_status=1
    remove_owned_volume "$MERGED_GRAFANA_DATA_VOLUME" || cleanup_status=1
    remove_owned_volume "$MERGED_GRAFANA_STATE_VOLUME" || cleanup_status=1
    remove_owned_volume "$MERGED_BACKUP_VOLUME" || cleanup_status=1
    remove_owned_volume "$MERGED_RESTORE_VOLUME" || cleanup_status=1
    remove_owned_network "$NETWORK_NAME" || cleanup_status=1
    remove_owned_network "$MERGED_FRONTEND_NETWORK" || cleanup_status=1
    remove_owned_network "$MERGED_BACKEND_NETWORK" || cleanup_status=1
    remove_owned_image "$MERGED_MAINTENANCE_IMAGE" || cleanup_status=1
    remove_owned_image "$MERGED_POSTGRES_IMAGE" || cleanup_status=1
    remove_owned_image "$POLICY_IMAGE_NAME" || cleanup_status=1
    remove_owned_image "$IMAGE_NAME" || cleanup_status=1
    if [[ -n "$(docker container ls --all --quiet --filter "label=${OWNERSHIP_LABEL}=${RUN_ID}" 2>/dev/null)" ]]; then
      cleanup_status=1
    fi
    if docker volume inspect "$DATABASE_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$GRAFANA_DATA_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$GRAFANA_STATE_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$ROLE_GRAFANA_DATA_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$MERGED_DATABASE_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$MERGED_GRAFANA_DATA_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$MERGED_GRAFANA_STATE_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$MERGED_BACKUP_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$MERGED_RESTORE_VOLUME" >/dev/null 2>&1 \
      || docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 \
      || docker network inspect "$MERGED_FRONTEND_NETWORK" >/dev/null 2>&1 \
      || docker network inspect "$MERGED_BACKEND_NETWORK" >/dev/null 2>&1 \
      || docker image inspect "$MERGED_MAINTENANCE_IMAGE" >/dev/null 2>&1 \
      || docker image inspect "$MERGED_POSTGRES_IMAGE" >/dev/null 2>&1 \
      || docker image inspect "$POLICY_IMAGE_NAME" >/dev/null 2>&1 \
      || docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 \
      || { [[ -n "$policy_anonymous_volume" ]] \
        && docker volume inspect "$policy_anonymous_volume" >/dev/null 2>&1; }; then
      cleanup_status=1
    fi
  elif [[ "$original_status" -eq 0 ]]; then
    cleanup_status=1
  fi

  if [[ -d "$EVIDENCE_ROOT" \
    && -f "$POSTGRES_PASSWORD_FILE" \
    && -f "$GRAFANA_SECRET_KEY_FILE" \
    && -f "$GRAFANA_ADMIN_PASSWORD_FILE" \
    && -f "$GRAFANA_OIDC_CLIENT_SECRET_FILE" ]] \
    && grep -R -F \
      -f "$POSTGRES_PASSWORD_FILE" \
      -f "$GRAFANA_SECRET_KEY_FILE" \
      -f "$GRAFANA_ADMIN_PASSWORD_FILE" \
      -f "$GRAFANA_OIDC_CLIENT_SECRET_FILE" \
      "$EVIDENCE_ROOT" >/dev/null 2>&1; then
    log_error 'captured runtime evidence contains a synthetic secret value'
    cleanup_status=1
  fi

  current_identity="$(stat -Lc '%d:%i' -- "$TEST_ROOT" 2>/dev/null)"
  if [[ -d "$TEST_ROOT" && ! -L "$TEST_ROOT" && "$current_identity" == "$TEST_ROOT_IDENTITY" ]]; then
    rm -rf -- "$RUNTIME_ROOT" || cleanup_status=1
    if [[ "$KEEP_TEST_OUTPUT" == true ]]; then
      printf 'INFO grafana-runtime: retained non-secret evidence at %s\n' "$EVIDENCE_ROOT"
    else
      rm -rf -- "$TEST_ROOT" || cleanup_status=1
    fi
  else
    cleanup_status=1
  fi

  elapsed=$(( $(date +%s) - START_EPOCH ))
  if [[ "$cleanup_status" -ne 0 ]]; then
    log_error 'cleanup or final evidence verification did not complete safely'
    [[ "$final_status" -ne 0 ]] || final_status=1
  elif [[ "$original_status" -eq 0 && "$SUITE_COMPLETED" == true ]]; then
    printf 'PASS grafana-runtime: %d assertions in %ds; all owned containers, networks, volumes, runtime secrets, and unique test images were removed\n' \
      "$TEST_COUNT" "$elapsed"
  elif [[ "$original_status" -eq 0 ]]; then
    log_error 'suite exited before its final completion marker'
    final_status=1
  else
    printf 'INFO grafana-runtime: failed after %d assertions in %ds; exact owned-resource cleanup completed\n' \
      "$TEST_COUNT" "$elapsed" >&2
  fi
  exit "$final_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_resource_names_available
#   Fails before creation if an exact disposable name or tag already exists.
#ææææææææææææææææææææææææææææææææææ
require_resource_names_available() {
  local container_name
  local image_name
  local network_name
  local volume_name

  for container_name in \
    "$APP_IMAGE_PROBE_CONTAINER" "$POLICY_IMAGE_PROBE_CONTAINER" \
    "$ROLE_APP_CONTAINER" "$ROLE_OAUTH_CONTAINER" \
    "$ROLE_OAUTH_BUILD_CONTAINER" "$ROLE_VOLUME_INIT_CONTAINER" \
    "$PEER_PROBE_CONTAINER" \
    "$POSTGRES_CONTAINER" "$VOLUME_INIT_CONTAINER" \
    "$BOOTSTRAP_CONTAINER" "$BOOTSTRAP_SIGNAL_CONTAINER" \
    "$BOOTSTRAP_SIGNAL_MARKER_CONTAINER" \
    "$BOOTSTRAP_REPEAT_CONTAINER" "$MARKER_CHECK_CONTAINER" \
    "$CLI_REJECT_CONTAINER" "$CLI_RESET_CONTAINER" \
    "$APP_FORM_CONTAINER" "$APP_LOCKED_CONTAINER" \
    "$MERGED_APP_CONTAINER" "$MERGED_POSTGRES_CONTAINER" \
    "$MERGED_BOOTSTRAP_CONTAINER" "$MERGED_MIGRATOR_CONTAINER" \
    "$MERGED_MAINTENANCE_CONTAINER" \
    "$MERGED_POLICY_CONTAINER" \
    "$MERGED_VOLUME_INIT_CONTAINER" "$MERGED_MARKER_CHECK_CONTAINER"; do
    ! docker container inspect "$container_name" >/dev/null 2>&1 \
      || fail "disposable container name already exists: ${container_name}"
  done
  for volume_name in \
    "$DATABASE_VOLUME" "$GRAFANA_DATA_VOLUME" "$GRAFANA_STATE_VOLUME" \
    "$ROLE_GRAFANA_DATA_VOLUME" \
    "$MERGED_DATABASE_VOLUME" "$MERGED_GRAFANA_DATA_VOLUME" \
    "$MERGED_GRAFANA_STATE_VOLUME" "$MERGED_BACKUP_VOLUME" \
    "$MERGED_RESTORE_VOLUME"; do
    ! docker volume inspect "$volume_name" >/dev/null 2>&1 \
      || fail "disposable volume name already exists: ${volume_name}"
  done
  ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1 \
    || fail "disposable network name already exists: ${NETWORK_NAME}"
  for network_name in "$MERGED_FRONTEND_NETWORK" "$MERGED_BACKEND_NETWORK"; do
    ! docker network inspect "$network_name" >/dev/null 2>&1 \
      || fail "disposable network name already exists: ${network_name}"
  done
  for image_name in \
    "$IMAGE_NAME" "$POLICY_IMAGE_NAME" \
    "$MERGED_POSTGRES_IMAGE" "$MERGED_MAINTENANCE_IMAGE"; do
    ! docker image inspect "$image_name" >/dev/null 2>&1 \
      || fail "disposable image tag already exists: ${image_name}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_postgresql
#   Requires the disposable PostgreSQL server to become ready within 120 seconds.
#   Arguments:
#     $1 - optional container name
#     $2 - optional database user
#     $3 - optional database name
#ææææææææææææææææææææææææææææææææææ
wait_for_postgresql() {
  local container_name="${1:-$POSTGRES_CONTAINER}"
  local database_user="${2:-$DATABASE_USER}"
  local database_name="${3:-$DATABASE_NAME}"
  local attempt
  local state

  for attempt in {1..120}; do
    if docker exec "$container_name" pg_isready \
      --dbname "$database_name" --username "$database_user" >/dev/null 2>&1; then
      return 0
    fi
    if ! state="$(docker container inspect --format '{{.State.Status}}' \
      "$container_name" 2>/dev/null)"; then
      fail 'PostgreSQL container disappeared during readiness wait'
    fi
    [[ "$state" != exited && "$state" != dead ]] \
      || fail "PostgreSQL entered terminal state ${state}"
    sleep 1
  done
  fail 'PostgreSQL did not become ready within 120 seconds'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_grafana
#   Requires one Grafana container and its database-aware helper health probe.
#   Arguments:
#     $1 - container name
#ææææææææææææææææææææææææææææææææææ
wait_for_grafana() {
  local container_name="$1"
  local attempt
  local state

  for attempt in {1..180}; do
    if docker exec "$container_name" \
      /usr/local/bin/grafana-entrypoint health >/dev/null 2>&1; then
      return 0
    fi
    if ! state="$(docker container inspect --format '{{.State.Status}}' \
      "$container_name" 2>/dev/null)"; then
      fail "Grafana container disappeared during readiness wait: ${container_name}"
    fi
    [[ "$state" != exited && "$state" != dead ]] \
      || fail "Grafana entered terminal state ${state}: ${container_name}"
    sleep 1
  done
  fail "Grafana did not become database-healthy within 180 seconds: ${container_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: query_admin_hash
#   Reads only the synthetic administrator password hash from PostgreSQL.
#ææææææææææææææææææææææææææææææææææ
query_admin_hash() {
  query_database \
    "$POSTGRES_CONTAINER" "$DATABASE_USER" "$DATABASE_NAME" \
    'SELECT password FROM "user" WHERE id = 1;'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: query_database
#   Runs one noninteractive SQL statement through the container-local secret.
#   Arguments:
#     $1 - PostgreSQL container name
#     $2 - database user
#     $3 - database name
#     $4 - SQL statement without credential values
#ææææææææææææææææææææææææææææææææææ
query_database() {
  local container_name="$1"
  local database_user="$2"
  local database_name="$3"
  local sql_statement="$4"

  docker exec "$container_name" bash -euo pipefail -c '
    export PGPASSWORD="$(< /run/secrets/POSTGRES_PASSWORD)"
    exec psql --no-psqlrc --tuples-only --no-align \
      --set ON_ERROR_STOP=1 \
      --username "$1" --dbname "$2" --command "$3"
  ' grafana-runtime-query "$database_user" "$database_name" "$sql_statement"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: common_grafana_arguments
#   Populates GRAFANA_ARGUMENTS with the hardened common runtime contract.
#   Arguments:
#     $1 - container name
#     $2 - login-form boolean
#ææææææææææææææææææææææææææææææææææ
common_grafana_arguments() {
  local container_name="$1"
  local login_form_disabled="$2"

  GRAFANA_ARGUMENTS=(
    --detach
    --name "$container_name"
    --label "${OWNERSHIP_LABEL}=${RUN_ID}"
    --network "$NETWORK_NAME"
    --user "${TEST_APP_UID}:${TEST_APP_GID}"
    --group-add "$HOST_GROUP_ID"
    --read-only
    --cap-drop ALL
    --security-opt no-new-privileges:true
    --init
    --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${TEST_APP_GID},mode=0771"
    --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m
    --mount "type=volume,src=${GRAFANA_DATA_VOLUME},dst=/var/lib/grafana"
    --mount "type=bind,src=${POSTGRES_PASSWORD_FILE},dst=/run/secrets/POSTGRES_PASSWORD,readonly"
    --mount "type=bind,src=${GRAFANA_SECRET_KEY_FILE},dst=/run/secrets/GRAFANA_SECRET_KEY,readonly"
    --mount "type=bind,src=${GRAFANA_OIDC_CLIENT_ID_FILE},dst=/run/secrets/GRAFANA_OIDC_CLIENT_ID,readonly"
    --mount "type=bind,src=${GRAFANA_OIDC_CLIENT_SECRET_FILE},dst=/run/secrets/GRAFANA_OIDC_CLIENT_SECRET,readonly"
    --publish 127.0.0.1::3000
    --env "APP_DOMAIN=${APP_DOMAIN}"
    --env "AUTHENTIK_DOMAIN=${AUTHENTIK_DOMAIN}"
    --env "GRAFANA_DISABLE_LOGIN_FORM=${login_form_disabled}"
    --env GRAFANA_OAUTH_AUTO_LOGIN=false
    --env GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION=8h
    --env GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION=1h
    --env GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES=5
    --env GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS=90
    --env GRAFANA_OIDC_NAME=authentik
    --env GRAFANA_OIDC_SLUG=grafana
    --env GRAFANA_OIDC_ACCESS_GROUP=grafana-users
    --env GRAFANA_OIDC_ADMIN_GROUP=grafana-admins
    --env GRAFANA_OIDC_EDITOR_GROUP=grafana-editors
    --env GRAFANA_OIDC_VIEWER_GROUP=grafana-viewers
    --env 'GRAFANA_OIDC_SCOPES=openid profile email offline_access'
    --env GRAFANA_SMTP_ENABLED=false
    --env GF_SERVER_HTTP_ADDR=0.0.0.0
    --env GF_SERVER_HTTP_PORT=3000
    --env GF_DATABASE_TYPE=postgres
    --env "GF_DATABASE_HOST=${POSTGRES_CONTAINER}:5432"
    --env "GF_DATABASE_NAME=${DATABASE_NAME}"
    --env "GF_DATABASE_USER=${DATABASE_USER}"
    --env GF_DATABASE_SSL_MODE=disable
    "$IMAGE_NAME"
  )
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: start_grafana
#   Starts one final daemon and returns its loopback host URL through APP_URL.
#   Arguments:
#     $1 - container name
#     $2 - login-form boolean
#ææææææææææææææææææææææææææææææææææ
start_grafana() {
  local container_name="$1"
  local login_form_disabled="$2"
  local host_port

  common_grafana_arguments "$container_name" "$login_form_disabled"
  docker run "${GRAFANA_ARGUMENTS[@]}" >/dev/null
  wait_for_grafana "$container_name"
  if ! host_port="$(docker container inspect --format \
    '{{ (index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort }}' \
    "$container_name")"; then
    fail "cannot resolve loopback test port: ${container_name}"
  fi
  [[ "$host_port" =~ ^[0-9]+$ ]] \
    || fail "invalid loopback test port: ${container_name}"
  APP_URL="http://127.0.0.1:${host_port}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_http_status
#   Requires one exact bounded HTTP response status.
#   Arguments:
#     $1 - expected status
#     $2 - evidence output name
#   remaining arguments - curl request arguments
#ææææææææææææææææææææææææææææææææææ
require_http_status() {
  local expected_status="$1"
  local evidence_name="$2"
  local actual_status
  shift 2

  if ! actual_status="$(curl --silent --show-error --max-time 10 \
    --output "${EVIDENCE_ROOT}/${evidence_name}.body" \
    --write-out '%{http_code}' "$@")"; then
    fail "HTTP request failed: ${evidence_name}"
  fi
  [[ "$actual_status" == "$expected_status" ]] \
    || fail "unexpected HTTP ${actual_status}; expected ${expected_status}: ${evidence_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_host_http
#   Waits for one exact host-published HTTP status after a container restart.
#   Arguments:
#     $1 - host URL
#     $2 - expected status
#ææææææææææææææææææææææææææææææææææ
wait_for_host_http() {
  local request_url="$1"
  local expected_status="$2"
  local actual_status
  local attempt

  for attempt in {1..60}; do
    actual_status="$(curl --silent --max-time 2 --output /dev/null \
      --write-out '%{http_code}' "$request_url" 2>/dev/null || true)"
    if [[ "$actual_status" == "$expected_status" ]]; then
      return 0
    fi
    sleep 1
  done
  fail "host-published HTTP endpoint did not return ${expected_status} within 60 seconds"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_peer_http_status
#   Requires one exact response from the isolated same-network peer.
#   Arguments:
#     $1 - expected status
#     $2 - evidence output name
#     $3 - container-network URL
#ææææææææææææææææææææææææææææææææææ
require_peer_http_status() {
  local expected_status="$1"
  local evidence_name="$2"
  local request_url="$3"
  local actual_status

  if ! actual_status="$(docker exec "$PEER_PROBE_CONTAINER" \
    /usr/bin/curl --silent --show-error --max-time 10 \
    --output "/tmp/${evidence_name}.body" \
    --write-out '%{http_code}' "$request_url")"; then
    fail "peer HTTP request failed: ${evidence_name}"
  fi
  [[ "$actual_status" == "$expected_status" ]] \
    || fail "unexpected peer HTTP ${actual_status}; expected ${expected_status}: ${evidence_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_peer_http
#   Waits for one exact status through the same-network peer.
#   Arguments:
#     $1 - container-network URL
#     $2 - expected status
#ææææææææææææææææææææææææææææææææææ
wait_for_peer_http() {
  local request_url="$1"
  local expected_status="$2"
  local attempt
  local actual_status

  for attempt in {1..180}; do
    actual_status="$(docker exec "$PEER_PROBE_CONTAINER" \
      /usr/bin/curl --silent --max-time 2 --output /dev/null \
      --write-out '%{http_code}' "$request_url" 2>/dev/null || true)"
    if [[ "$actual_status" == "$expected_status" ]]; then
      return 0
    fi
    sleep 1
  done
  fail "peer HTTP endpoint did not return ${expected_status} within 180 seconds"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stop_and_remove_container
#   Stops and removes one exact suite-owned container before the next phase.
#   Arguments:
#     $1 - container name
#ææææææææææææææææææææææææææææææææææ
stop_and_remove_container() {
  local container_name="$1"

  docker stop --time 30 "$container_name" >/dev/null
  remove_owned_container "$container_name" \
    || fail "could not remove exact owned container: ${container_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_merged_policy_job
#   Recreates the exact finite policy service and checks its expected result.
#   Arguments:
#     $1 - success or failure
#     $2 - evidence log stem
#ææææææææææææææææææææææææææææææææææ
run_merged_policy_job() {
  local expected_result="$1"
  local evidence_name="$2"
  local compose_status
  local container_status

  [[ "$expected_result" == success || "$expected_result" == failure ]] \
    || fail 'invalid expected Grafana SSO policy result'
  remove_owned_container "$MERGED_POLICY_CONTAINER" \
    || fail 'could not retire the previous exact owned SSO policy container'
  if merged_compose_bounded 180s run \
    --no-deps \
    --no-TTY \
    --name "$MERGED_POLICY_CONTAINER" \
    --pull never \
    grafana-sso-policy \
    >"${EVIDENCE_ROOT}/${evidence_name}.log" 2>&1; then
    compose_status=0
  else
    compose_status="$?"
  fi
  container_status="$(docker container inspect --format '{{.State.ExitCode}}' \
    "$MERGED_POLICY_CONTAINER")" \
    || fail 'could not inspect the finite SSO policy result'
  [[ "$container_status" =~ ^[0-9]+$ && "$compose_status" =~ ^[0-9]+$ ]] \
    || fail 'finite SSO policy returned a nonnumeric exit status'
  if [[ "$expected_result" == success ]]; then
    [[ "$compose_status" == 0 && "$container_status" == 0 ]] \
      || fail "finite SSO policy unexpectedly failed: ${evidence_name}"
  else
    [[ "$compose_status" != 0 && "$container_status" != 0 ]] \
      || fail "finite SSO policy unexpectedly succeeded: ${evidence_name}"
  fi
}

[[ "$KEEP_TEST_OUTPUT" == true || "$KEEP_TEST_OUTPUT" == false ]] \
  || fail 'KEEP_TEST_OUTPUT must be true or false'
[[ -f "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" \
  && ! -L "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" ]] \
  || fail 'Grafana Dockerfile is missing or not a regular file'
for required_command in \
  docker curl timeout stat grep base64 date git tar sed sort awk jq yq chgrp chmod; do
  command -v "$required_command" >/dev/null 2>&1 \
    || fail "required command is missing: ${required_command}"
done
docker info >/dev/null 2>&1 || fail 'Docker daemon is unavailable'
require_resource_names_available

mkdir -p -- "$EVIDENCE_ROOT" "$SECRET_ROOT"
chmod 0700 "$EVIDENCE_ROOT" "$SECRET_ROOT"
printf '%s' "$POSTGRES_PASSWORD_VALUE" >"$POSTGRES_PASSWORD_FILE"
printf '%s' "$GRAFANA_SECRET_KEY_VALUE" >"$GRAFANA_SECRET_KEY_FILE"
printf '%s' "$GRAFANA_ADMIN_PASSWORD_VALUE" >"$GRAFANA_ADMIN_PASSWORD_FILE"
printf '%s' "$GRAFANA_OIDC_CLIENT_ID_VALUE" >"$GRAFANA_OIDC_CLIENT_ID_FILE"
printf '%s' "$GRAFANA_OIDC_CLIENT_SECRET_VALUE" >"$GRAFANA_OIDC_CLIENT_SECRET_FILE"
printf '%s' "$RESET_PASSWORD_VALUE" >"$RESET_PASSWORD_FILE"
chmod 0640 "$POSTGRES_PASSWORD_FILE" "$GRAFANA_SECRET_KEY_FILE" \
  "$GRAFANA_ADMIN_PASSWORD_FILE" "$GRAFANA_OIDC_CLIENT_ID_FILE" \
  "$GRAFANA_OIDC_CLIENT_SECRET_FILE" "$RESET_PASSWORD_FILE"
chgrp "$HOST_GROUP_ID" "$POSTGRES_PASSWORD_FILE" "$GRAFANA_SECRET_KEY_FILE" \
  "$GRAFANA_ADMIN_PASSWORD_FILE" "$GRAFANA_OIDC_CLIENT_ID_FILE" \
  "$GRAFANA_OIDC_CLIENT_SECRET_FILE" "$RESET_PASSWORD_FILE"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'umask 077' \
  "test \"\${GF_DATABASE_HOST:-}\" = \"${POSTGRES_CONTAINER}:5432\"" \
  'test "${GF_DATABASE_SKIP_MIGRATIONS:-}" = false' \
  'test "${GF_DATABASE_MIGRATION_LOCKING:-}" = true' \
  'test "${GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC:-}" = 0' \
  'tr "\\000" "\\n" <"/proc/$$/environ" | while IFS="=" read -r name _value; do' \
  '  case "$name" in' \
  '    GF_DATABASE_TYPE|GF_DATABASE_HOST|GF_DATABASE_NAME|GF_DATABASE_USER|GF_DATABASE_SSL_MODE|GF_DATABASE_SKIP_MIGRATIONS|GF_DATABASE_MIGRATION_LOCKING|GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC|GF_DATABASE_PASSWORD) ;;' \
  '    GF_DATABASE_*) exit 90 ;;' \
  '  esac' \
  'done' \
  'state=/var/lib/grafana/runtime-test-wrapper' \
  'mkdir -p "$state"' \
  'count=0' \
  'if test -f "$state/child-count" && test ! -L "$state/child-count"; then' \
  '  count="$(cat "$state/child-count")"' \
  '  case "$count" in ""|*[!0-9]*) exit 91;; esac' \
  'fi' \
  'count=$((count + 1))' \
  'printf "%s" "$count" >"$state/child-count"' \
  'term_file="$state/term-${count}"' \
  'child_pid=0' \
  'handle_term() {' \
  '  printf "%s" "$count" >"$term_file"' \
  '  sleep 8' \
  '  if kill -0 "$child_pid" 2>/dev/null; then' \
  '    kill -TERM "$child_pid" 2>/dev/null || true' \
  '  fi' \
  '  wait "$child_pid" 2>/dev/null || true' \
  '  exit 143' \
  '}' \
  'trap handle_term TERM INT' \
  '/run.sh &' \
  'child_pid=$!' \
  'wait "$child_pid"' \
  >"$BOOTSTRAP_WRAPPER_FILE"
chmod 0555 "$BOOTSTRAP_WRAPPER_FILE"
printf '%s\n' \
  '#!/bin/sh' \
  'set -eu' \
  'umask 077' \
  'for required_secret in GRAFANA_SECRET_KEY POSTGRES_PASSWORD; do' \
  '  secret="/run/secrets/${required_secret}"' \
  '  test -f "$secret" && test ! -L "$secret" && test -r "$secret"' \
  'done' \
  'set -- /run/secrets/*' \
  'test "$#" -eq 2' \
  'test "$1" = /run/secrets/GRAFANA_SECRET_KEY' \
  'test "$2" = /run/secrets/POSTGRES_PASSWORD' \
  'for proc_file in "/proc/$$/environ" "/proc/$$/cmdline"; do' \
  '  if tr "\\000" "\\n" <"$proc_file" | grep -Eq "(^|/)(GRAFANA_ADMIN_PASSWORD|GF_SECURITY_ADMIN_PASSWORD|GRAFANA_OIDC_CLIENT_ID|GRAFANA_OIDC_CLIENT_SECRET|GF_AUTH_GENERIC_OAUTH_CLIENT_ID|GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET|MAILER_SMTP_PASSWORD|GF_SMTP_PASSWORD)(=|__FILE=|_FILE=|$)"; then' \
  '    exit 92' \
  '  fi' \
  'done' \
  "test \"\${GF_DATABASE_HOST:-}\" = \"${MERGED_APP_NAME}-postgresql:5432\"" \
  'test "${GF_DATABASE_SKIP_MIGRATIONS:-}" = false' \
  'test "${GF_DATABASE_MIGRATION_LOCKING:-}" = true' \
  'test "${GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC:-}" = 0' \
  'tr "\\000" "\\n" <"/proc/$$/environ" | while IFS="=" read -r name _value; do' \
  '  case "$name" in' \
  '    GF_DATABASE_TYPE|GF_DATABASE_HOST|GF_DATABASE_NAME|GF_DATABASE_USER|GF_DATABASE_SSL_MODE|GF_DATABASE_SKIP_MIGRATIONS|GF_DATABASE_MIGRATION_LOCKING|GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC|GF_DATABASE_PASSWORD) ;;' \
  '    GF_DATABASE_*) exit 94 ;;' \
  '  esac' \
  'done' \
  'state=/var/lib/grafana/runtime-test-migrator' \
  'mkdir -p "$state"' \
  'count=0' \
  'if test -f "$state/child-count" && test ! -L "$state/child-count"; then' \
  '  count="$(cat "$state/child-count")"' \
  '  case "$count" in ""|*[!0-9]*) exit 93;; esac' \
  'fi' \
  'count=$((count + 1))' \
  'printf "%s" "$count" >"$state/child-count"' \
  'printf "%s" env-argv-proc-clean >"$state/secret-boundary"' \
  'exec /run.sh' \
  >"$MIGRATOR_WRAPPER_FILE"
chmod 0555 "$MIGRATOR_WRAPPER_FILE"
printf '%s\n' \
  'package main' \
  '' \
  'import (' \
  '  "encoding/json"' \
  '  "fmt"' \
  '  "log"' \
  '  "net/http"' \
  '  "net/url"' \
  '  "strconv"' \
  '  "strings"' \
  '  "sync/atomic"' \
  '  "time"' \
  ')' \
  '' \
  'var selectedMask atomic.Int64' \
  '' \
  'func writeJSON(response http.ResponseWriter, value any) {' \
  '  response.Header().Set("Content-Type", "application/json")' \
  '  if err := json.NewEncoder(response).Encode(value); err != nil {' \
  '    panic(err)' \
  '  }' \
  '}' \
  '' \
  'func selectMask(response http.ResponseWriter, request *http.Request) {' \
  '  mask, err := strconv.Atoi(request.URL.Query().Get("mask"))' \
  '  if err != nil || mask < 0 || mask > 7 {' \
  '    http.Error(response, "invalid mask", http.StatusBadRequest)' \
  '    return' \
  '  }' \
  '  selectedMask.Store(int64(mask))' \
  '  response.WriteHeader(http.StatusNoContent)' \
  '}' \
  '' \
  'func authorize(response http.ResponseWriter, request *http.Request) {' \
  '  callback, err := url.Parse(request.URL.Query().Get("redirect_uri"))' \
  '  if err != nil || callback.Scheme != "http" || callback.Host == "" {' \
  '    http.Error(response, "invalid callback", http.StatusBadRequest)' \
  '    return' \
  '  }' \
  '  query := callback.Query()' \
  '  query.Set("code", fmt.Sprintf("role-code-%d", selectedMask.Load()))' \
  '  query.Set("state", request.URL.Query().Get("state"))' \
  '  callback.RawQuery = query.Encode()' \
  '  http.Redirect(response, request, callback.String(), http.StatusFound)' \
  '}' \
  '' \
  'func tokenMask(value string) (int, error) {' \
  '  for _, prefix := range []string{"role-code-", "role-refresh-"} {' \
  '    if strings.HasPrefix(value, prefix) {' \
  '      mask, err := strconv.Atoi(strings.TrimPrefix(value, prefix))' \
  '      if err == nil && mask >= 0 && mask <= 7 {' \
  '        return mask, nil' \
  '      }' \
  '    }' \
  '  }' \
  '  return 0, fmt.Errorf("invalid token input")' \
  '}' \
  '' \
  'func token(response http.ResponseWriter, request *http.Request) {' \
  '  if err := request.ParseForm(); err != nil {' \
  '    http.Error(response, "invalid form", http.StatusBadRequest)' \
  '    return' \
  '  }' \
  '  input := request.Form.Get("code")' \
  '  if request.Form.Get("grant_type") == "refresh_token" {' \
  '    input = request.Form.Get("refresh_token")' \
  '  }' \
  '  mask, err := tokenMask(input)' \
  '  if err != nil {' \
  '    http.Error(response, "invalid grant", http.StatusBadRequest)' \
  '    return' \
  '  }' \
  '  writeJSON(response, map[string]any{' \
  '    "access_token": fmt.Sprintf("role-access-%d", mask),' \
  '    "refresh_token": fmt.Sprintf("role-refresh-%d", mask),' \
  '    "token_type": "Bearer",' \
  '    "expires_in": 3600,' \
  '  })' \
  '}' \
  '' \
  'func userInfo(response http.ResponseWriter, request *http.Request) {' \
  '  value := strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer role-access-")' \
  '  mask, err := strconv.Atoi(value)' \
  '  if err != nil || mask < 0 || mask > 7 {' \
  '    http.Error(response, "invalid bearer", http.StatusUnauthorized)' \
  '    return' \
  '  }' \
  '  groups := []string{"grafana-users"}' \
  '  if mask&1 != 0 { groups = append(groups, "grafana-admins") }' \
  '  if mask&2 != 0 { groups = append(groups, "grafana-editors") }' \
  '  if mask&4 != 0 { groups = append(groups, "grafana-viewers") }' \
  '  writeJSON(response, map[string]any{' \
  '    "sub": fmt.Sprintf("role-user-%d", mask),' \
  '    "name": fmt.Sprintf("Role User %d", mask),' \
  '    "email": fmt.Sprintf("role-user-%d@example.invalid", mask),' \
  '    "groups": groups,' \
  '  })' \
  '}' \
  '' \
  'func main() {' \
  '  mux := http.NewServeMux()' \
  '  mux.HandleFunc("/select", selectMask)' \
  '  mux.HandleFunc("/authorize", authorize)' \
  '  mux.HandleFunc("/token", token)' \
  '  mux.HandleFunc("/userinfo", userInfo)' \
  '  mux.HandleFunc("/health", func(response http.ResponseWriter, _ *http.Request) { response.WriteHeader(http.StatusOK) })' \
  '  server := &http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 5 * time.Second}' \
  '  log.Fatal(server.ListenAndServe())' \
  '}' \
  >"$ROLE_OAUTH_SOURCE_FILE"
chmod 0600 "$ROLE_OAUTH_SOURCE_FILE"

log_info 'building the reviewed final Grafana image without cache'
if ! timeout --foreground 1200s docker build \
  --pull \
  --no-cache \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --build-arg "GRAFANA_BASE_IMAGE=${GRAFANA_BASE_IMAGE}" \
  --build-arg "GRAFANA_GO_IMAGE=${GRAFANA_GO_IMAGE}" \
  --build-arg "POSTGRES_IMAGE=${POSTGRES_IMAGE}" \
  --file "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" \
  --tag "$IMAGE_NAME" \
  "${TEST_REPO_ROOT}/Grafana/dockerfiles" \
  >"${EVIDENCE_ROOT}/image-build.log" 2>&1; then
  fail 'no-cache final Grafana image build failed or exceeded 1200 seconds'
fi
[[ "$(docker image inspect --format '{{.Config.User}}' "$IMAGE_NAME")" == 472 ]] \
  || fail 'final Grafana image does not retain vendor UID 472'
[[ "$(docker image inspect --format '{{json .Config.Entrypoint}}' "$IMAGE_NAME")" \
  == '["/usr/local/bin/grafana-entrypoint"]' ]] \
  || fail 'final Grafana image does not use the static helper entrypoint'
FINAL_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE_NAME")" \
  || fail 'could not resolve the exact final Grafana image ID'
BASE_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$GRAFANA_BASE_IMAGE")" \
  || fail 'could not resolve the exact upstream Grafana image ID'
readonly FINAL_IMAGE_ID BASE_IMAGE_ID
[[ "$FINAL_IMAGE_ID" == sha256:* && "$BASE_IMAGE_ID" == sha256:* ]] \
  || fail 'Grafana image IDs are not immutable sha256 identifiers'
log_info "exact upstream image ${BASE_IMAGE_ID}; exact reviewed runtime image ${FINAL_IMAGE_ID}"
log_ok 'final no-cache image build, embedded Go tests, and image contract'

cmp --silent \
  "${TEST_REPO_ROOT}/Grafana/dockerfiles/grafana-entrypoint.go" \
  "${TEST_REPO_ROOT}/templates/grafana-sso-policy/dockerfiles/grafana-entrypoint.grafana-sso-policy.go" \
  || fail 'Grafana SSO policy helper source is not byte-identical to the app helper source'
cmp --silent \
  "${TEST_REPO_ROOT}/Grafana/dockerfiles/grafana-entrypoint_test.go" \
  "${TEST_REPO_ROOT}/templates/grafana-sso-policy/dockerfiles/grafana-entrypoint.grafana-sso-policy_test.go" \
  || fail 'Grafana SSO policy helper tests are not byte-identical to the app helper tests'
log_info 'building the independent Grafana SSO policy image with the classic builder'
if ! DOCKER_BUILDKIT=0 timeout --foreground 1200s docker build \
  --pull \
  --no-cache \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --build-arg "GRAFANA_SSO_POLICY_GO_IMAGE=${GRAFANA_SSO_POLICY_GO_IMAGE}" \
  --build-arg "POSTGRES_IMAGE=${POSTGRES_IMAGE}" \
  --file "${TEST_REPO_ROOT}/templates/grafana-sso-policy/dockerfiles/dockerfile.grafana-sso-policy" \
  --tag "$POLICY_IMAGE_NAME" \
  "${TEST_REPO_ROOT}/templates/grafana-sso-policy/dockerfiles" \
  >"${EVIDENCE_ROOT}/policy-image-build.log" 2>&1; then
  fail 'classic no-cache Grafana SSO policy image build failed or exceeded 1200 seconds'
fi
POLICY_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$POLICY_IMAGE_NAME")" \
  || fail 'could not resolve the exact SSO policy image ID'
readonly POLICY_IMAGE_ID
[[ "$POLICY_IMAGE_ID" == sha256:* ]] \
  || fail 'Grafana SSO policy image ID is not an immutable sha256 identifier'
[[ "$(docker image inspect --format '{{.Config.User}}' "$POLICY_IMAGE_NAME")" == '472:472' ]] \
  || fail 'Grafana SSO policy image does not run as exact UID/GID 472:472'
[[ "$(docker image inspect --format '{{json .Config.Entrypoint}}' "$POLICY_IMAGE_NAME")" \
  == '["/usr/local/bin/grafana-entrypoint"]' ]] \
  || fail 'Grafana SSO policy image does not use the static helper entrypoint'
[[ "$(docker image inspect --format '{{json .Config.Cmd}}' "$POLICY_IMAGE_NAME")" \
  == '["sso-policy"]' ]] \
  || fail 'Grafana SSO policy image does not expose the finite policy command'
if ! docker create \
  --name "$APP_IMAGE_PROBE_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network none \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" \
  -euc 'test -x /usr/local/bin/grafana-entrypoint; test ! -e /usr/lib/postgresql/18/bin/psql; ! command -v psql >/dev/null 2>&1' \
  >/dev/null; then
  fail 'could not create the isolated final Grafana image probe'
fi
if ! timeout --foreground 30s docker start --attach "$APP_IMAGE_PROBE_CONTAINER" \
  >"${EVIDENCE_ROOT}/app-image-probe.log" 2>&1; then
  fail 'final Grafana image unexpectedly contains psql or failed its isolated probe'
fi
docker cp \
  "${APP_IMAGE_PROBE_CONTAINER}:/usr/local/bin/grafana-entrypoint" \
  "${RUNTIME_ROOT}/app-grafana-entrypoint" \
  >/dev/null 2>&1 \
  || fail 'could not extract the reviewed helper from the final Grafana image'
remove_owned_container "$APP_IMAGE_PROBE_CONTAINER" \
  || fail 'could not retire the final Grafana image probe'
if ! docker create \
  --name "$POLICY_IMAGE_PROBE_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network none \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --entrypoint /bin/sh \
  "$POLICY_IMAGE_NAME" \
  -euc 'test -x /usr/local/bin/grafana-entrypoint; test -f /usr/lib/postgresql/18/bin/psql; test ! -L /usr/lib/postgresql/18/bin/psql; test -x /usr/lib/postgresql/18/bin/psql; /usr/lib/postgresql/18/bin/psql --version | grep -Eq "^psql \(PostgreSQL\) 18\."' \
  >/dev/null; then
  fail 'could not create the isolated Grafana SSO policy image probe'
fi
if ! timeout --foreground 30s docker start --attach "$POLICY_IMAGE_PROBE_CONTAINER" \
  >"${EVIDENCE_ROOT}/policy-image-probe.log" 2>&1; then
  fail 'Grafana SSO policy image lacks the exact regular PostgreSQL 18 psql executable'
fi
docker cp \
  "${POLICY_IMAGE_PROBE_CONTAINER}:/usr/local/bin/grafana-entrypoint" \
  "${RUNTIME_ROOT}/policy-grafana-entrypoint" \
  >/dev/null 2>&1 \
  || fail 'could not extract the reviewed helper from the SSO policy image'
remove_owned_container "$POLICY_IMAGE_PROBE_CONTAINER" \
  || fail 'could not retire the Grafana SSO policy image probe'
cmp --silent \
  "${RUNTIME_ROOT}/app-grafana-entrypoint" \
  "${RUNTIME_ROOT}/policy-grafana-entrypoint" \
  || fail 'Grafana app and SSO policy images do not contain the identical helper binary'
log_info "exact classic-built policy image ${POLICY_IMAGE_ID}"
log_ok 'classic no-cache policy build mirrors the app sources and binary, retains exact regular PostgreSQL 18 psql, and keeps psql out of the daemon'

log_info 'creating a secret-free local Git snapshot for the real merged closure'
mkdir -p -- "$MERGED_SOURCE"
if ! (
  cd -- "$TEST_REPO_ROOT"
  tar --create --file - \
    --exclude='Grafana/secrets/*' \
    --exclude='Grafana/appdata/*' \
    --exclude='Grafana/.run.conf/*' \
    --exclude='Grafana/docker-compose.main.yaml' \
    --exclude='Grafana/app.env' \
    --exclude='templates/postgresql/secrets/*' \
    --exclude='templates/postgresql/backup/*' \
    --exclude='templates/postgresql/restore/*' \
    --exclude='templates/postgresql_maintenance/secrets/*' \
    --exclude='templates/postgresql_maintenance/backup/*' \
    --exclude='templates/postgresql_maintenance/restore/*' \
    run.sh Grafana templates/postgresql templates/postgresql_maintenance \
    templates/grafana-bootstrap templates/grafana-migrator \
    templates/grafana-sso-policy
) | tar --extract --directory "$MERGED_SOURCE"; then
  fail 'could not create the allowlisted secret-free merged-closure snapshot'
fi
mkdir -p -- "$MERGED_SOURCE/Grafana/secrets" \
  "$MERGED_SOURCE/templates/postgresql/secrets"
for secret_name in \
  GRAFANA_ADMIN_PASSWORD GRAFANA_SECRET_KEY GRAFANA_OIDC_CLIENT_ID \
  GRAFANA_OIDC_CLIENT_SECRET MAILER_SMTP_PASSWORD; do
  printf 'CHANGE_ME' >"${MERGED_SOURCE}/Grafana/secrets/${secret_name}"
done
printf 'CHANGE_ME' \
  >"${MERGED_SOURCE}/templates/postgresql/secrets/POSTGRES_PASSWORD"
git -C "$MERGED_SOURCE" init --quiet --initial-branch=main
git -C "$MERGED_SOURCE" config user.name 'Grafana Runtime Test'
git -C "$MERGED_SOURCE" config user.email 'grafana-runtime@example.invalid'
git -C "$MERGED_SOURCE" add --all
git -C "$MERGED_SOURCE" commit --quiet -m 'test: isolated Grafana closure snapshot'
git clone --quiet "$MERGED_SOURCE" "$MERGED_RUNNER"
sed -i \
  "s|^readonly REPO_URL=.*|readonly REPO_URL=\"${MERGED_SOURCE}\"|" \
  "$MERGED_RUNNER/run.sh"
sed -i \
  -e "s|^APP_IMAGE=.*|APP_IMAGE=${IMAGE_NAME}|" \
  -e "s|^APP_NAME=.*|APP_NAME=${MERGED_APP_NAME}|" \
  -e "s|^APP_UID=.*|APP_UID=${HOST_USER_ID}|" \
  -e "s|^APP_GID=.*|APP_GID=${HOST_GROUP_ID}|" \
  -e "s|^APP_DOMAIN=.*|APP_DOMAIN=${APP_DOMAIN}|" \
  -e "s|^AUTHENTIK_DOMAIN=.*|AUTHENTIK_DOMAIN=${AUTHENTIK_DOMAIN}|" \
  "$MERGED_APP_DIR/.env"
printf '\nPOSTGRES_UID=%s\nPOSTGRES_GID=%s\n' \
  "$HOST_USER_ID" "$HOST_GROUP_ID" >>"$MERGED_APP_DIR/.env"
mkdir -p -- "$MERGED_APP_DIR/secrets"
printf '%s' "$POSTGRES_PASSWORD_VALUE" \
  >"${MERGED_APP_DIR}/secrets/POSTGRES_PASSWORD"
printf '%s' "$GRAFANA_SECRET_KEY_VALUE" \
  >"${MERGED_APP_DIR}/secrets/GRAFANA_SECRET_KEY"
printf '%s' "$GRAFANA_ADMIN_PASSWORD_VALUE" \
  >"${MERGED_APP_DIR}/secrets/GRAFANA_ADMIN_PASSWORD"
printf '%s' "$GRAFANA_OIDC_CLIENT_ID_VALUE" \
  >"${MERGED_APP_DIR}/secrets/GRAFANA_OIDC_CLIENT_ID"
printf '%s' "$GRAFANA_OIDC_CLIENT_SECRET_VALUE" \
  >"${MERGED_APP_DIR}/secrets/GRAFANA_OIDC_CLIENT_SECRET"
printf '%s' "smtp-disabled-${RUN_ID}" \
  >"${MERGED_APP_DIR}/secrets/MAILER_SMTP_PASSWORD"
chmod 0640 "$MERGED_APP_DIR"/secrets/*
chgrp "$HOST_GROUP_ID" "$MERGED_APP_DIR"/secrets/*

if ! (
  cd -- "$MERGED_RUNNER"
  timeout --foreground 300s ./run.sh Grafana --dry-run
) >"${EVIDENCE_ROOT}/merged-run-dry.log" 2>&1; then
  fail 'isolated run.sh dry-run could not render the Grafana closure'
fi
if ! (
  cd -- "$MERGED_RUNNER"
  timeout --foreground 300s ./run.sh Grafana
) >"${EVIDENCE_ROOT}/merged-run.log" 2>&1; then
  fail 'isolated run.sh could not publish the Grafana closure'
fi
[[ -f "${MERGED_APP_DIR}/docker-compose.main.yaml" \
  && ! -L "${MERGED_APP_DIR}/docker-compose.main.yaml" \
  && -f "${MERGED_APP_DIR}/.env" \
  && ! -L "${MERGED_APP_DIR}/.env" ]] \
  || fail 'isolated run.sh did not publish regular merged outputs'

if ! (
  cd -- "$MERGED_APP_DIR"
  env \
  APP_UID="$TEST_APP_UID" \
  APP_GID="$HOST_GROUP_ID" \
  APP_NAME="$MERGED_APP_NAME" \
  APP_IMAGE="$IMAGE_NAME" \
  GRAFANA_SSO_POLICY_IMAGE="$POLICY_IMAGE_NAME" \
  GRAFANA_SSO_POLICY_GO_IMAGE="$GRAFANA_SSO_POLICY_GO_IMAGE" \
  POSTGRES_IMAGE="$POSTGRES_IMAGE" \
  POSTGRES_MAINTENANCE_IMAGE="$POSTGRES_MAINTENANCE_IMAGE" \
  POSTGRES_UID=999 \
  POSTGRES_GID=999 \
  docker compose \
    --project-name "$MERGED_PROJECT_NAME" \
    --env-file .env \
    --file docker-compose.main.yaml \
    config --format json
) >"$MERGED_SOURCE_CONFIG_FILE" \
  2>"${EVIDENCE_ROOT}/merged-source-config.stderr"; then
  fail 'real unmodified merged closure did not render for its build-contract check'
fi
if ! jq --exit-status \
  --arg app_image "$IMAGE_NAME" \
  --arg go_image "$GRAFANA_SSO_POLICY_GO_IMAGE" \
  --arg policy_image "$POLICY_IMAGE_NAME" \
  --arg postgres_image "$POSTGRES_IMAGE" \
  --arg maintenance_image "$POSTGRES_MAINTENANCE_IMAGE" '
    (.services | keys | sort) ==
      ["app", "grafana-bootstrap", "grafana-migrator", "grafana-sso-policy", "postgresql", "postgresql_maintenance"]
    and .services.app.image == $app_image
    and .services.app.build.target == "grafana-runtime"
    and .services.app.build.dockerfile == "Dockerfile"
    and .services.app.build.pull == true
    and .services.app.build.no_cache == true
    and .services["grafana-migrator"].image == $app_image
    and (.services["grafana-migrator"].build // null) == null
    and .services["grafana-migrator"].pull_policy == "never"
    and .services["grafana-migrator"].volumes == [{
      "type": "bind",
      "source": (.services["grafana-migrator"].volumes[0].source),
      "target": "/var/lib/grafana",
      "bind": {}
    }]
    and ([.services["grafana-migrator"].secrets[].source] | sort) ==
      ["GRAFANA_SECRET_KEY", "POSTGRES_PASSWORD"]
    and .services["grafana-migrator"].command == ["migrate"]
    and .services["grafana-migrator"].entrypoint ==
      ["/usr/local/bin/grafana-entrypoint"]
    and .services["grafana-migrator"].restart == "no"
    and .services["grafana-migrator"].read_only == true
    and .services["grafana-migrator"].healthcheck.disable == true
    and (.services["grafana-migrator"].ports // []) == []
    and (.services["grafana-migrator"].expose // []) == []
    and (.services["grafana-migrator"].networks | keys) == ["backend"]
    and (.services["grafana-migrator"].environment | keys | sort) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER",
      "GRAFANA_MIGRATOR_READY_TIMEOUT_SECONDS",
      "GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS",
      "TZ"
    ]
    and .services["grafana-migrator"].depends_on.postgresql.condition ==
      "service_healthy"
    and .services["grafana-migrator"].depends_on["grafana-bootstrap"].condition ==
      "service_completed_successfully"
    and .services["grafana-sso-policy"].image == $policy_image
    and .services["grafana-sso-policy"].build.dockerfile ==
      "dockerfile.grafana-sso-policy"
    and (.services["grafana-sso-policy"].build.target // null) == null
    and (.services["grafana-sso-policy"].build.additional_contexts // null) == null
    and .services["grafana-sso-policy"].build.pull == true
    and .services["grafana-sso-policy"].build.no_cache == true
    and .services["grafana-sso-policy"].build.args.GRAFANA_SSO_POLICY_GO_IMAGE ==
      $go_image
    and .services["grafana-sso-policy"].build.args.POSTGRES_IMAGE == $postgres_image
    and .services.postgresql.build.args.POSTGRES_IMAGE == $postgres_image
    and .services.postgresql_maintenance.build.args.POSTGRES_MAINTENANCE_IMAGE ==
      $maintenance_image
    and .services["grafana-sso-policy"].volumes == [{
      "type": "tmpfs",
      "target": "/var/lib/postgresql",
      "read_only": true,
      "tmpfs": {"size": "1048576", "mode": 448}
    }]
  ' "$MERGED_SOURCE_CONFIG_FILE" >/dev/null; then
  fail 'unmodified merged Compose lost the six-service app, migrator, policy, or separate PostgreSQL build contract'
fi
log_info "merged PostgreSQL base ${POSTGRES_IMAGE}; maintenance base ${POSTGRES_MAINTENANCE_IMAGE}"

printf '%s\n' \
  'services:' \
  '  app:' \
  "    image: ${IMAGE_NAME}" \
  '    pull_policy: never' \
  '    build: !reset null' \
  '    labels:' \
  "      ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    volumes:' \
  '      - type: volume' \
  '        source: grafana_runtime_data' \
  '        target: /var/lib/grafana' \
  '  grafana-bootstrap:' \
  '    labels:' \
  "      ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    volumes:' \
  '      - type: volume' \
  '        source: grafana_runtime_data' \
  '        target: /var/lib/grafana' \
  '      - type: volume' \
  '        source: grafana_runtime_state' \
  '        target: /var/lib/grafana-bootstrap-state' \
  '  grafana-migrator:' \
  '    labels:' \
  "      ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    environment:' \
  '      GRAFANA_VENDOR_ENTRYPOINT: /runtime-test/grafana-migrator-wrapper.sh' \
  '    volumes:' \
  '      - type: volume' \
  '        source: grafana_runtime_data' \
  '        target: /var/lib/grafana' \
  '      - type: bind' \
  "        source: ${MIGRATOR_WRAPPER_FILE}" \
  '        target: /runtime-test/grafana-migrator-wrapper.sh' \
  '        read_only: true' \
  '  grafana-sso-policy:' \
  "    image: ${POLICY_IMAGE_NAME}" \
  '    pull_policy: never' \
  '    build: !reset null' \
  '    labels:' \
  "      ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '  postgresql:' \
  "    image: ${MERGED_POSTGRES_IMAGE}" \
  '    build:' \
  '      labels:' \
  "        ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    labels:' \
  "      ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    volumes:' \
  '      - type: volume' \
  '        source: postgresql_runtime_data' \
  '        target: /var/lib/postgresql' \
  '  postgresql_maintenance:' \
  "    image: ${MERGED_MAINTENANCE_IMAGE}" \
  '    build:' \
  '      labels:' \
  "        ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    labels:' \
  "      ${OWNERSHIP_LABEL}: \"${RUN_ID}\"" \
  '    volumes:' \
  '      - type: volume' \
  '        source: postgresql_runtime_data' \
  '        target: /var/lib/postgresql' \
  '        read_only: true' \
  '      - type: volume' \
  '        source: postgresql_runtime_backup' \
  '        target: /backup' \
  '      - type: volume' \
  '        source: postgresql_runtime_restore' \
  '        target: /restore' \
  'volumes:' \
  '  postgresql_runtime_data:' \
  '    external: true' \
  "    name: ${MERGED_DATABASE_VOLUME}" \
  '  grafana_runtime_data:' \
  '    external: true' \
  "    name: ${MERGED_GRAFANA_DATA_VOLUME}" \
  '  grafana_runtime_state:' \
  '    external: true' \
  "    name: ${MERGED_GRAFANA_STATE_VOLUME}" \
  '  postgresql_runtime_backup:' \
  '    external: true' \
  "    name: ${MERGED_BACKUP_VOLUME}" \
  '  postgresql_runtime_restore:' \
  '    external: true' \
  "    name: ${MERGED_RESTORE_VOLUME}" \
  'networks:' \
  '  frontend:' \
  '    external: true' \
  "    name: ${MERGED_FRONTEND_NETWORK}" \
  '  backend:' \
  '    external: true' \
  "    name: ${MERGED_BACKEND_NETWORK}" \
  >"$MERGED_OVERRIDE_FILE"

if ! merged_compose config --format json \
  >"$MERGED_CONFIG_FILE" \
  2>"${EVIDENCE_ROOT}/merged-config.stderr"; then
  fail 'real merged closure plus runtime override did not render'
fi
if ! jq --exit-status \
  --arg app_gid "$HOST_GROUP_ID" \
  --arg run_mount "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${HOST_GROUP_ID},mode=0771" \
  --arg data_volume "$MERGED_GRAFANA_DATA_VOLUME" \
  --arg state_volume "$MERGED_GRAFANA_STATE_VOLUME" \
  --arg database_volume "$MERGED_DATABASE_VOLUME" \
  --arg app_image "$IMAGE_NAME" \
  --arg policy_image "$POLICY_IMAGE_NAME" \
  --arg migrator_wrapper "$MIGRATOR_WRAPPER_FILE" \
  --arg app_name "$MERGED_APP_NAME" \
  --arg role_path "$EXPECTED_ROLE_ATTRIBUTE_PATH" '
    def run_mounts($service):
      [.services[$service].tmpfs[] | select(startswith("/run:"))];
    def exact_run($service):
      run_mounts($service) == [$run_mount];
    def database_keys($service):
      [.services[$service].environment | keys[] |
        select(startswith("GF_DATABASE_"))] | sort;
    (.services | keys | sort) ==
      ["app", "grafana-bootstrap", "grafana-migrator", "grafana-sso-policy", "postgresql", "postgresql_maintenance"]
    and exact_run("app")
    and exact_run("grafana-bootstrap")
    and exact_run("grafana-migrator")
    and exact_run("grafana-sso-policy")
    and exact_run("postgresql")
    and exact_run("postgresql_maintenance")
    and .services.app.user == ("472:" + $app_gid)
    and (.services.app.group_add // []) == []
    and .services["grafana-bootstrap"].user == "472:472"
    and .services["grafana-bootstrap"].group_add == [$app_gid]
    and .services["grafana-migrator"].user == "472:472"
    and .services["grafana-migrator"].group_add == [$app_gid]
    and .services["grafana-sso-policy"].user == "472:472"
    and .services["grafana-sso-policy"].group_add == [$app_gid]
    and (.services.postgresql.user // null) == null
    and .services.postgresql.group_add == [$app_gid]
    and .services.postgresql_maintenance.user == "999:999"
    and .services.postgresql_maintenance.group_add == [$app_gid]
    and (.services.app.build // null) == null
    and .services.app.image == $app_image
    and .services.app.pull_policy == "never"
    and (.services["grafana-migrator"].build // null) == null
    and .services["grafana-migrator"].image == $app_image
    and .services["grafana-migrator"].pull_policy == "never"
    and (.services["grafana-sso-policy"].build // null) == null
    and .services["grafana-sso-policy"].image == $policy_image
    and .services["grafana-sso-policy"].pull_policy == "never"
    and .services.app.depends_on.postgresql.condition == "service_healthy"
    and .services.app.depends_on["grafana-bootstrap"].condition ==
      "service_completed_successfully"
    and .services.app.depends_on["grafana-migrator"].condition ==
      "service_completed_successfully"
    and .services.app.depends_on["grafana-sso-policy"].condition ==
      "service_completed_successfully"
    and (.services.app.depends_on | keys | sort) ==
      ["grafana-bootstrap", "grafana-migrator", "grafana-sso-policy", "postgresql"]
    and .services["grafana-bootstrap"].depends_on.postgresql.condition ==
      "service_healthy"
    and database_keys("app") == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and database_keys("grafana-bootstrap") == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and database_keys("grafana-migrator") == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and database_keys("grafana-sso-policy") == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and .services.app.environment.GF_DATABASE_HOST ==
      ($app_name + "-postgresql:5432")
    and .services["grafana-bootstrap"].environment.GF_DATABASE_HOST ==
      ($app_name + "-postgresql:5432")
    and .services["grafana-migrator"].depends_on.postgresql.condition ==
      "service_healthy"
    and .services["grafana-migrator"].depends_on["grafana-bootstrap"].condition ==
      "service_completed_successfully"
    and (.services["grafana-migrator"].depends_on | keys | sort) ==
      ["grafana-bootstrap", "postgresql"]
    and .services["grafana-sso-policy"].depends_on.postgresql.condition ==
      "service_healthy"
    and .services["grafana-sso-policy"].depends_on["grafana-migrator"].condition ==
      "service_completed_successfully"
    and (.services["grafana-sso-policy"].depends_on | keys | sort) ==
      ["grafana-migrator", "postgresql"]
    and ([.services.app.secrets[].source] | index("GRAFANA_ADMIN_PASSWORD")) == null
    and ([.services["grafana-bootstrap"].secrets[].source] | sort) ==
      ["GRAFANA_ADMIN_PASSWORD", "GRAFANA_SECRET_KEY", "POSTGRES_PASSWORD"]
    and ([.services["grafana-migrator"].secrets[].source] | sort) ==
      ["GRAFANA_SECRET_KEY", "POSTGRES_PASSWORD"]
    and ([.services["grafana-sso-policy"].secrets[].source] | sort) ==
      ["POSTGRES_PASSWORD"]
    and .services["grafana-migrator"].command == ["migrate"]
    and .services["grafana-migrator"].entrypoint ==
      ["/usr/local/bin/grafana-entrypoint"]
    and .services["grafana-migrator"].restart == "no"
    and .services["grafana-migrator"].read_only == true
    and .services["grafana-migrator"].healthcheck.disable == true
    and (.services["grafana-migrator"].ports // []) == []
    and (.services["grafana-migrator"].expose // []) == []
    and (.services["grafana-migrator"].networks | keys) == ["backend"]
    and ([.services["grafana-migrator"].labels // {} | keys[] |
      select(startswith("traefik."))] | length) == 0
    and (.services["grafana-migrator"].environment | keys | sort) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER",
      "GRAFANA_MIGRATOR_READY_TIMEOUT_SECONDS",
      "GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS",
      "GRAFANA_VENDOR_ENTRYPOINT",
      "TZ"
    ]
    and .services["grafana-migrator"].environment.GF_DATABASE_TYPE == "postgres"
    and .services["grafana-migrator"].environment.GF_DATABASE_HOST ==
      ($app_name + "-postgresql:5432")
    and .services["grafana-migrator"].environment.GF_DATABASE_NAME == $app_name
    and .services["grafana-migrator"].environment.GF_DATABASE_USER == $app_name
    and .services["grafana-migrator"].environment.GF_DATABASE_SSL_MODE == "disable"
    and .services["grafana-migrator"].environment.GF_DATABASE_SKIP_MIGRATIONS == "false"
    and .services["grafana-migrator"].environment.GF_DATABASE_MIGRATION_LOCKING == "true"
    and .services["grafana-migrator"].environment.GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC == "0"
    and .services["grafana-migrator"].environment.GRAFANA_MIGRATOR_READY_TIMEOUT_SECONDS == "300"
    and .services["grafana-migrator"].environment.GRAFANA_MIGRATOR_STOP_TIMEOUT_SECONDS == "30"
    and .services["grafana-migrator"].environment.GRAFANA_VENDOR_ENTRYPOINT ==
      "/runtime-test/grafana-migrator-wrapper.sh"
    and ([.services["grafana-migrator"].environment | keys[] |
      select(test("ADMIN_PASSWORD|OIDC_CLIENT|SMTP_PASSWORD"))] | length) == 0
    and .services["grafana-sso-policy"].command == ["sso-policy"]
    and .services["grafana-sso-policy"].entrypoint ==
      ["/usr/local/bin/grafana-entrypoint"]
    and .services["grafana-sso-policy"].restart == "no"
    and .services["grafana-sso-policy"].read_only == true
    and .services["grafana-sso-policy"].healthcheck.disable == true
    and .services["grafana-sso-policy"].volumes == [{
      "type": "tmpfs",
      "target": "/var/lib/postgresql",
      "read_only": true,
      "tmpfs": {"size": "1048576", "mode": 448}
    }]
    and (.services["grafana-sso-policy"].ports // []) == []
    and (.services["grafana-sso-policy"].expose // []) == []
    and (.services["grafana-sso-policy"].networks | keys) == ["backend"]
    and ([.services["grafana-sso-policy"].labels // {} | keys[] |
      select(startswith("traefik."))] | length) == 0
    and (.services["grafana-sso-policy"].environment | keys | sort) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER",
      "GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS",
      "GRAFANA_SSO_POLICY_TIMEOUT_SECONDS"
    ]
    and .services["grafana-sso-policy"].environment.GF_DATABASE_TYPE == "postgres"
    and .services["grafana-sso-policy"].environment.GF_DATABASE_HOST ==
      ($app_name + "-postgresql:5432")
    and .services["grafana-sso-policy"].environment.GF_DATABASE_NAME == $app_name
    and .services["grafana-sso-policy"].environment.GF_DATABASE_USER == $app_name
    and .services["grafana-sso-policy"].environment.GF_DATABASE_SSL_MODE == "disable"
    and .services["grafana-sso-policy"].environment.GRAFANA_SSO_POLICY_TIMEOUT_SECONDS == "30"
    and .services["grafana-sso-policy"].environment.GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS == "90"
    and .services.app.environment.GF_DATABASE_SKIP_MIGRATIONS == "false"
    and .services.app.environment.GF_DATABASE_MIGRATION_LOCKING == "true"
    and .services.app.environment.GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC == "0"
    and .services["grafana-bootstrap"].environment.GF_DATABASE_SKIP_MIGRATIONS == "false"
    and .services["grafana-bootstrap"].environment.GF_DATABASE_MIGRATION_LOCKING == "true"
    and .services["grafana-bootstrap"].environment.GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC == "0"
    and .services.app.environment.GRAFANA_LOGIN_MAXIMUM_LIFETIME_DURATION == "8h"
    and .services.app.environment.GRAFANA_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION == "1h"
    and .services.app.environment.GRAFANA_TOKEN_ROTATION_INTERVAL_MINUTES == "5"
    and .services.app.environment.GRAFANA_SERVICE_ACCOUNT_TOKEN_EXPIRATION_DAYS == "90"
    and .services.app.environment.GRAFANA_OIDC_SCOPES ==
      "openid profile email offline_access"
    and .services.app.environment.GF_AUTH_LOGIN_MAXIMUM_LIFETIME_DURATION == "8h"
    and .services.app.environment.GF_AUTH_LOGIN_MAXIMUM_INACTIVE_LIFETIME_DURATION == "1h"
    and .services.app.environment.GF_AUTH_TOKEN_ROTATION_INTERVAL_MINUTES == "5"
    and .services.app.environment.GF_AUTH_GENERIC_OAUTH_SCOPES ==
      "openid profile email offline_access"
    and .services.app.environment.GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN == "true"
    and .services.app.environment.GF_AUTH_OAUTH_ALLOW_INSECURE_EMAIL_LOOKUP == "false"
    and .services.app.environment.GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH == $role_path
    and .services.app.environment.GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT == "true"
    and .services.app.environment.GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS ==
      "saervices_policy_locked"
    and .services.app.environment.GF_SERVICE_ACCOUNTS_TOKEN_EXPIRATION_DAY_LIMIT == "90"
    and .services.app.environment.GF_METRICS_ENABLED == "false"
    and .services.app.environment.GF_PUBLIC_DASHBOARDS_ENABLED == "false"
    and .services.app.environment.GF_SNAPSHOTS_ENABLED == "false"
    and .services.app.environment.GF_SNAPSHOTS_EXTERNAL_ENABLED == "false"
    and .services.app.environment.GF_PLUGINS_PLUGIN_ADMIN_ENABLED == "false"
    and .services.app.environment.GF_SECURITY_COOKIE_SECURE == "true"
    and .services.app.environment.GF_SECURITY_DISABLE_GRAVATAR == "true"
    and .services.app.environment.GF_USERS_ALLOW_SIGN_UP == "false"
    and .services.app.environment.GF_USERS_ALLOW_ORG_CREATE == "false"
    and ([.services.app.volumes[] | select(.target == "/var/lib/grafana")][0].source) ==
      "grafana_runtime_data"
    and ([.services["grafana-migrator"].volumes[] |
      select(.target == "/var/lib/grafana")]) == [{
        "type": "volume",
        "source": "grafana_runtime_data",
        "target": "/var/lib/grafana"
      }]
    and ([.services["grafana-migrator"].volumes[] |
      select(.target == "/runtime-test/grafana-migrator-wrapper.sh")]) == [{
        "type": "bind",
        "source": $migrator_wrapper,
        "target": "/runtime-test/grafana-migrator-wrapper.sh",
        "read_only": true
      }]
    and (.services["grafana-migrator"].volumes | length) == 2
    and ([.services["grafana-bootstrap"].volumes[] |
      select(.target == "/var/lib/grafana-bootstrap-state")][0].source) ==
      "grafana_runtime_state"
    and ([.services.postgresql.volumes[] |
      select(.target == "/var/lib/postgresql")][0].source) ==
      "postgresql_runtime_data"
    and .volumes.grafana_runtime_data.name == $data_volume
    and .volumes.grafana_runtime_state.name == $state_volume
    and .volumes.postgresql_runtime_data.name == $database_volume
  ' "$MERGED_CONFIG_FILE" >/dev/null; then
  fail 'rendered closure lost an exact service, dependency, secret, user, group, volume, or shared tmpfs contract'
fi
MERGED_COMPOSE_READY=true
log_ok 'run.sh rendered the exact six-service bootstrap-migrator-policy chain, least-privilege secrets, and shared 0771 /run mounts'

for network_name in "$MERGED_FRONTEND_NETWORK" "$MERGED_BACKEND_NETWORK"; do
  docker network create \
    --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
    "$network_name" >/dev/null
done
for volume_name in \
  "$MERGED_DATABASE_VOLUME" "$MERGED_GRAFANA_DATA_VOLUME" \
  "$MERGED_GRAFANA_STATE_VOLUME" "$MERGED_BACKUP_VOLUME" \
  "$MERGED_RESTORE_VOLUME"; do
  docker volume create \
    --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
    "$volume_name" >/dev/null
done
docker run \
  --name "$MERGED_VOLUME_INIT_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user 0:0 \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add FOWNER \
  --mount "type=volume,src=${MERGED_GRAFANA_DATA_VOLUME},dst=/data" \
  --mount "type=volume,src=${MERGED_GRAFANA_STATE_VOLUME},dst=/state" \
  --mount "type=volume,src=${MERGED_BACKUP_VOLUME},dst=/backup" \
  --mount "type=volume,src=${MERGED_RESTORE_VOLUME},dst=/restore" \
  --env "APP_UID=${TEST_APP_UID}" \
  --env "APP_GID=${HOST_GROUP_ID}" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc '
    : > /backup/.grafana-runtime-volume-initialized
    : > /restore/.grafana-runtime-volume-initialized
    chown "${APP_UID}:${APP_GID}" /data /state
    chmod 0770 /data /state
    chown 999:999 \
      /backup /backup/.grafana-runtime-volume-initialized \
      /restore /restore/.grafana-runtime-volume-initialized
    chmod 0600 \
      /backup/.grafana-runtime-volume-initialized \
      /restore/.grafana-runtime-volume-initialized
    chmod 0700 /backup /restore
  ' >"${EVIDENCE_ROOT}/merged-volume-init.log" 2>&1 \
  || fail 'could not initialize the exact merged closure volumes'

log_info 'building the merged PostgreSQL and maintenance images without cache'
if ! merged_compose_bounded 1200s build --pull --no-cache \
  postgresql postgresql_maintenance \
  >"${EVIDENCE_ROOT}/merged-images-build.log" 2>&1; then
  fail 'merged PostgreSQL or maintenance no-cache build failed or exceeded 1200 seconds'
fi
for image_name in "$MERGED_POSTGRES_IMAGE" "$MERGED_MAINTENANCE_IMAGE"; do
  [[ "$(docker image inspect --format \
    '{{ index .Config.Labels "codex.grafana-runtime" }}' "$image_name")" == "$RUN_ID" ]] \
    || fail "merged image ownership label is missing: ${image_name}"
done
log_ok 'merged PostgreSQL and maintenance images built without cache under unique labels'

MERGED_STARTED=true
if ! merged_compose_bounded 480s up --detach --no-build --pull never \
  >"${EVIDENCE_ROOT}/merged-up.log" 2>&1; then
  fail 'merged PostgreSQL, bootstrap, migrator, SSO policy, maintenance, and app closure did not start'
fi
wait_for_postgresql "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME"
wait_for_grafana "$MERGED_APP_CONTAINER"
[[ "$(docker container inspect --format '{{.State.ExitCode}}' \
  "$MERGED_BOOTSTRAP_CONTAINER")" == 0 ]] \
  || fail 'merged bootstrap job did not complete successfully'
[[ "$(docker container inspect --format '{{.State.ExitCode}}' \
  "$MERGED_MIGRATOR_CONTAINER")" == 0 ]] \
  || fail 'merged migrator job did not complete successfully'
[[ "$(docker container inspect --format '{{.State.ExitCode}}' \
  "$MERGED_POLICY_CONTAINER")" == 0 ]] \
  || fail 'merged SSO policy job did not complete successfully'
[[ "$(docker container inspect --format '{{.State.Status}}' \
  "$MERGED_MAINTENANCE_CONTAINER")" == running ]] \
  || fail 'merged maintenance scheduler is not running'
docker container inspect \
  "$MERGED_APP_CONTAINER" "$MERGED_BOOTSTRAP_CONTAINER" \
  "$MERGED_MIGRATOR_CONTAINER" "$MERGED_POLICY_CONTAINER" \
  "$MERGED_POSTGRES_CONTAINER" \
  "$MERGED_MAINTENANCE_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-runtime-inspect.json"
if ! jq --exit-status \
  --arg app "$MERGED_APP_CONTAINER" \
  --arg bootstrap "$MERGED_BOOTSTRAP_CONTAINER" \
  --arg migrator "$MERGED_MIGRATOR_CONTAINER" \
  --arg policy "$MERGED_POLICY_CONTAINER" \
  --arg postgresql "$MERGED_POSTGRES_CONTAINER" \
  --arg maintenance "$MERGED_MAINTENANCE_CONTAINER" \
  --arg data_volume "$MERGED_GRAFANA_DATA_VOLUME" \
  --arg migrator_wrapper "$MIGRATOR_WRAPPER_FILE" \
  --arg app_gid "$HOST_GROUP_ID" '
    def item($name): .[] | select(.Name == ("/" + $name));
    def run_ok($name):
      (item($name).HostConfig.Tmpfs["/run"] | split(",")) as $options |
      ($options | index("rw")) != null
      and ($options | index("noexec")) != null
      and ($options | index("nosuid")) != null
      and ($options | index("nodev")) != null
      and ($options | index("size=64m")) != null
      and ($options | index("uid=472")) != null
      and ($options | index("gid=" + $app_gid)) != null
      and ($options | index("mode=0771")) != null;
    def database_env_names($name):
      [item($name).Config.Env[] | split("=")[0] |
        select(startswith("GF_DATABASE_"))] | sort;
    run_ok($app)
    and run_ok($bootstrap)
    and run_ok($migrator)
    and run_ok($policy)
    and run_ok($postgresql)
    and run_ok($maintenance)
    and item($app).Config.User == ("472:" + $app_gid)
    and item($bootstrap).Config.User == "472:472"
    and item($bootstrap).HostConfig.GroupAdd == [$app_gid]
    and database_env_names($app) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and database_env_names($bootstrap) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and database_env_names($migrator) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC",
      "GF_DATABASE_MIGRATION_LOCKING",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SKIP_MIGRATIONS",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and database_env_names($policy) == [
      "GF_DATABASE_HOST",
      "GF_DATABASE_NAME",
      "GF_DATABASE_SSL_MODE",
      "GF_DATABASE_TYPE",
      "GF_DATABASE_USER"
    ]
    and ([item($app).Config.Env[], item($bootstrap).Config.Env[],
      item($migrator).Config.Env[]] |
      map(select(. == "GF_DATABASE_SKIP_MIGRATIONS=false")) | length) == 3
    and ([item($app).Config.Env[], item($bootstrap).Config.Env[],
      item($migrator).Config.Env[]] |
      map(select(. == "GF_DATABASE_MIGRATION_LOCKING=true")) | length) == 3
    and ([item($app).Config.Env[], item($bootstrap).Config.Env[],
      item($migrator).Config.Env[]] |
      map(select(. == "GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC=0")) | length) == 3
    and ([item($app).Config.Env[], item($bootstrap).Config.Env[],
      item($migrator).Config.Env[]] |
      map(select(. == ("GF_DATABASE_HOST=" + $app + "-postgresql:5432"))) |
      length) == 3
    and item($migrator).Config.User == "472:472"
    and item($migrator).HostConfig.GroupAdd == [$app_gid]
    and item($migrator).HostConfig.ReadonlyRootfs == true
    and item($migrator).HostConfig.CapDrop == ["ALL"]
    and item($migrator).HostConfig.SecurityOpt == ["no-new-privileges:true"]
    and item($migrator).HostConfig.RestartPolicy.Name == "no"
    and item($migrator).State.ExitCode == 0
    and item($bootstrap).State.FinishedAt < item($migrator).State.StartedAt
    and item($migrator).State.FinishedAt < item($policy).State.StartedAt
    and item($migrator).Config.Cmd == ["migrate"]
    and item($migrator).Config.Entrypoint == ["/usr/local/bin/grafana-entrypoint"]
    and ([item($migrator).Mounts[].Destination] | sort) == [
      "/run/secrets/GRAFANA_SECRET_KEY",
      "/run/secrets/POSTGRES_PASSWORD",
      "/runtime-test/grafana-migrator-wrapper.sh",
      "/var/lib/grafana"
    ]
    and ([item($migrator).Mounts[] |
      select(.Type == "volume"
        and .Destination == "/var/lib/grafana"
        and .Name == $data_volume
        and .RW == true)] | length) == 1
    and ([item($migrator).Mounts[] |
      select(.Type == "bind"
        and .Source == $migrator_wrapper
        and .Destination == "/runtime-test/grafana-migrator-wrapper.sh"
        and .RW == false)] | length) == 1
    and ([item($migrator).Mounts[].Destination |
      select(test("ADMIN_PASSWORD|OIDC_CLIENT|SMTP_PASSWORD"))] | length) == 0
    and ([item($migrator).Config.Env[] |
      select(test("^(GRAFANA_ADMIN_PASSWORD|GF_SECURITY_ADMIN_PASSWORD|GRAFANA_OIDC_CLIENT_ID|GRAFANA_OIDC_CLIENT_SECRET|GF_AUTH_GENERIC_OAUTH_CLIENT_ID|GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET|MAILER_SMTP_PASSWORD|GF_SMTP_PASSWORD)(=|__FILE=|_FILE=)"))] | length) == 0
    and item($policy).Config.User == "472:472"
    and item($policy).HostConfig.GroupAdd == [$app_gid]
    and item($policy).HostConfig.ReadonlyRootfs == true
    and item($policy).HostConfig.CapDrop == ["ALL"]
    and item($policy).HostConfig.SecurityOpt == ["no-new-privileges:true"]
    and item($policy).HostConfig.RestartPolicy.Name == "no"
    and item($policy).State.ExitCode == 0
    and item($policy).State.FinishedAt < item($app).State.StartedAt
    and ([item($policy).HostConfig.Mounts[] |
      select(.Type == "tmpfs"
        and .Target == "/var/lib/postgresql"
        and .ReadOnly == true
        and .TmpfsOptions.SizeBytes == 1048576
        and .TmpfsOptions.Mode == 448)] | length) == 1
    and ([item($policy).HostConfig.Mounts[] | select(.Type == "volume")] |
      length) == 0
    and ([item($policy).Mounts[] |
      select(.Type == "tmpfs"
        and .Destination == "/var/lib/postgresql"
        and .RW == false)] | length) == 1
    and ([item($policy).Mounts[] | select(.Type == "volume")] | length) == 0
    and ([item($policy).Mounts[].Destination] | sort) ==
      ["/run/secrets/POSTGRES_PASSWORD", "/var/lib/postgresql"]
    and item($postgresql).HostConfig.GroupAdd == [$app_gid]
    and item($maintenance).Config.User == "999:999"
    and item($maintenance).HostConfig.GroupAdd == [$app_gid]
    and ([item($app).Mounts[].Destination] |
      index("/run/secrets/GRAFANA_ADMIN_PASSWORD")) == null
  ' "${EVIDENCE_ROOT}/merged-runtime-inspect.json" >/dev/null; then
  fail 'runtime containers lost the exact rendered shared /run, user, group, or admin-secret boundary'
fi
docker logs "$MERGED_MIGRATOR_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-migrator-first.log" 2>&1
grep -Fxq \
  '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.' \
  "${EVIDENCE_ROOT}/merged-migrator-first.log" \
  || fail 'first merged migrator did not prove real loopback database health'
docker cp \
  "${MERGED_MIGRATOR_CONTAINER}:/var/lib/grafana/runtime-test-migrator/child-count" \
  "${RUNTIME_ROOT}/merged-migrator-first-count" >/dev/null 2>&1 \
  || fail 'could not read the first-generation migrator child counter'
docker cp \
  "${MERGED_MIGRATOR_CONTAINER}:/var/lib/grafana/runtime-test-migrator/secret-boundary" \
  "${RUNTIME_ROOT}/merged-migrator-secret-boundary" >/dev/null 2>&1 \
  || fail 'could not read the first-generation migrator process-boundary proof'
[[ "$(<"${RUNTIME_ROOT}/merged-migrator-first-count")" == 1 \
  && "$(<"${RUNTIME_ROOT}/merged-migrator-secret-boundary")" == env-argv-proc-clean ]] \
  || fail 'first-generation migrator did not execute once behind the exact secret/process boundary'
[[ "$(docker exec "$MERGED_APP_CONTAINER" stat -c '%u:%g:%a' \
  /run/grafana-secrets)" == "472:${HOST_GROUP_ID}:700" ]] \
  || fail 'merged final app private runtime-secret directory is not exact mode 0700'
for container_name in \
  "$MERGED_APP_CONTAINER" "$MERGED_POSTGRES_CONTAINER" \
  "$MERGED_MAINTENANCE_CONTAINER"; do
  [[ "$(docker exec "$container_name" stat -c '%u:%g:%a' /run)" \
    == "472:${HOST_GROUP_ID}:771" ]] \
    || fail "runtime /run ownership or mode differs from the merged anchor: ${container_name}"
done
log_ok 'real merged runtime preserved the shared 0771 /run and nested 0700 Grafana secret directory'

if ! query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT COALESCE(json_agg(json_build_object('table_name', table_name, 'column_name', column_name, 'udt_name', udt_name, 'is_nullable', is_nullable) ORDER BY table_name, ordinal_position), '[]'::json)::text FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN ('api_key', 'sso_setting');" \
  >"${EVIDENCE_ROOT}/merged-policy-schema.json"; then
  fail 'could not read the non-sensitive Grafana policy-table schema'
fi
if ! jq --exit-status '
    ([.[] | select(.table_name == "api_key") |
      [.column_name, .udt_name, .is_nullable]]) == [
        ["id", "int4", "NO"],
        ["org_id", "int8", "NO"],
        ["name", "varchar", "NO"],
        ["key", "varchar", "NO"],
        ["role", "varchar", "NO"],
        ["created", "timestamp", "NO"],
        ["updated", "timestamp", "NO"],
        ["expires", "int8", "YES"],
        ["service_account_id", "int8", "YES"],
        ["last_used_at", "timestamp", "YES"],
        ["is_revoked", "bool", "YES"]
      ]
    and ([.[] | select(.table_name == "sso_setting") |
      [.column_name, .udt_name, .is_nullable]]) == [
        ["id", "varchar", "NO"],
        ["provider", "varchar", "NO"],
        ["settings", "text", "NO"],
        ["created", "timestamp", "NO"],
        ["updated", "timestamp", "NO"],
        ["is_deleted", "bool", "NO"]
      ]
  ' "${EVIDENCE_ROOT}/merged-policy-schema.json" >/dev/null; then
  fail 'Grafana 13.2 policy-table columns, types, or nullability drifted'
fi
POLICY_PRIMARY_KEYS="$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT tc.table_name || ':' || kcu.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON kcu.constraint_schema = tc.constraint_schema AND kcu.constraint_name = tc.constraint_name AND kcu.table_name = tc.table_name WHERE tc.table_schema = 'public' AND tc.constraint_type = 'PRIMARY KEY' AND tc.table_name IN ('api_key', 'sso_setting') ORDER BY tc.table_name, kcu.ordinal_position;")" \
  || fail 'could not read Grafana policy-table primary keys'
[[ "$POLICY_PRIMARY_KEYS" == $'api_key:id\nsso_setting:id' ]] \
  || fail 'Grafana policy-table primary keys drifted'
log_ok 'real Grafana 13.2 migrations expose the exact SSO and token-policy schema, revocation field, nullability, and primary keys'

[[ "$(docker container inspect --format '{{.State.ExitCode}}' \
  "$MERGED_POLICY_CONTAINER")" == 0 ]] \
  || fail 'fresh merged SSO policy job did not complete successfully before the app'
docker logs "$MERGED_POLICY_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-policy-fresh.log" 2>&1
grep -Fq \
  'Verified 0 compliant active API/service-account token(s); reconciled 0 active SSO override(s); active overrides: 0.' \
  "${EVIDENCE_ROOT}/merged-policy-fresh.log" \
  || fail 'fresh merged SSO policy did not prove zero token debt and zero active overrides'
[[ "$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT count(*) FROM sso_setting WHERE is_deleted = false;")" == 0 ]] \
  || fail 'fresh merged database contains an active SSO override'
log_ok 'fresh closure completed the finite zero-debt SSO policy before opening the final listener'

docker cp \
  "${MERGED_BOOTSTRAP_CONTAINER}:/var/lib/grafana-bootstrap-state/bootstrap-v1.complete" \
  "${RUNTIME_ROOT}/merged-bootstrap-marker-first" >/dev/null 2>&1 \
  || fail 'could not capture the first-generation bootstrap marker'
[[ "$(<"${RUNTIME_ROOT}/merged-bootstrap-marker-first")" == grafana-bootstrap-v1 ]] \
  || fail 'first-generation bootstrap marker content drifted'
if ! merged_compose_bounded 480s up --detach --force-recreate \
  --no-build --pull never \
  >"${EVIDENCE_ROOT}/merged-second-generation-up.log" 2>&1; then
  fail 'second merged deployment generation did not complete the bootstrap-migrator-policy chain'
fi
wait_for_postgresql "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME"
wait_for_grafana "$MERGED_APP_CONTAINER"
for container_name in \
  "$MERGED_BOOTSTRAP_CONTAINER" "$MERGED_MIGRATOR_CONTAINER" \
  "$MERGED_POLICY_CONTAINER"; do
  [[ "$(docker container inspect --format '{{.State.ExitCode}}' \
    "$container_name")" == 0 ]] \
    || fail "second-generation finite service failed: ${container_name}"
done
docker logs "$MERGED_BOOTSTRAP_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-bootstrap-second.log" 2>&1
[[ "$(grep -Fxc \
  '[grafana-bootstrap] Existing verified bootstrap marker; credential phase skipped.' \
  "${EVIDENCE_ROOT}/merged-bootstrap-second.log")" == 1 ]] \
  || fail 'second-generation bootstrap did not accept exactly one existing marker without a vendor child'
docker logs "$MERGED_MIGRATOR_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-migrator-second.log" 2>&1
grep -Fxq \
  '[grafana-migrator] Database migrations and health verified without the bootstrap administrator credential.' \
  "${EVIDENCE_ROOT}/merged-migrator-second.log" \
  || fail 'second-generation migrator did not rerun real loopback database health verification'
docker logs "$MERGED_POLICY_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-policy-second-generation.log" 2>&1
grep -Fq \
  'Verified 0 compliant active API/service-account token(s); reconciled 0 active SSO override(s); active overrides: 0.' \
  "${EVIDENCE_ROOT}/merged-policy-second-generation.log" \
  || fail 'second-generation SSO policy did not retain the clean zero state'
docker cp \
  "${MERGED_BOOTSTRAP_CONTAINER}:/var/lib/grafana-bootstrap-state/bootstrap-v1.complete" \
  "${RUNTIME_ROOT}/merged-bootstrap-marker-second" >/dev/null 2>&1 \
  || fail 'could not capture the second-generation bootstrap marker'
cmp --silent \
  "${RUNTIME_ROOT}/merged-bootstrap-marker-first" \
  "${RUNTIME_ROOT}/merged-bootstrap-marker-second" \
  || fail 'second deployment generation changed the committed bootstrap marker'
docker cp \
  "${MERGED_MIGRATOR_CONTAINER}:/var/lib/grafana/runtime-test-migrator/child-count" \
  "${RUNTIME_ROOT}/merged-migrator-second-count" >/dev/null 2>&1 \
  || fail 'could not read the second-generation migrator child counter'
docker cp \
  "${MERGED_MIGRATOR_CONTAINER}:/var/lib/grafana/runtime-test-migrator/secret-boundary" \
  "${RUNTIME_ROOT}/merged-migrator-second-boundary" >/dev/null 2>&1 \
  || fail 'could not read the second-generation migrator process-boundary proof'
[[ "$(<"${RUNTIME_ROOT}/merged-migrator-second-count")" == 2 \
  && "$(<"${RUNTIME_ROOT}/merged-migrator-second-boundary")" == env-argv-proc-clean ]] \
  || fail 'second-generation migrator did not rerun behind the exact two-secret process boundary'
docker container inspect \
  "$MERGED_APP_CONTAINER" "$MERGED_BOOTSTRAP_CONTAINER" \
  "$MERGED_MIGRATOR_CONTAINER" "$MERGED_POLICY_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-second-generation-inspect.json"
if ! jq --exit-status \
  --arg app "$MERGED_APP_CONTAINER" \
  --arg bootstrap "$MERGED_BOOTSTRAP_CONTAINER" \
  --arg migrator "$MERGED_MIGRATOR_CONTAINER" \
  --arg policy "$MERGED_POLICY_CONTAINER" '
    def item($name): .[] | select(.Name == ("/" + $name));
    item($bootstrap).State.ExitCode == 0
    and item($migrator).State.ExitCode == 0
    and item($policy).State.ExitCode == 0
    and item($bootstrap).State.FinishedAt < item($migrator).State.StartedAt
    and item($migrator).State.FinishedAt < item($policy).State.StartedAt
    and item($policy).State.FinishedAt < item($app).State.StartedAt
    and item($app).State.Status == "running"
  ' "${EVIDENCE_ROOT}/merged-second-generation-inspect.json" >/dev/null; then
  fail 'second deployment generation violated bootstrap-migrator-policy-app ordering'
fi
[[ "$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT count(*) FROM sso_setting WHERE is_deleted = false;")" == 0 ]] \
  || fail 'second deployment generation restored an active SSO database override'
log_ok 'second deployment generation reused the marker, reran the secret-minimal migrator and policy, then opened the app listener'

run_merged_policy_job success merged-policy-repeat
grep -Fq \
  'Verified 0 compliant active API/service-account token(s); reconciled 0 active SSO override(s); active overrides: 0.' \
  "${EVIDENCE_ROOT}/merged-policy-repeat.log" \
  || fail 'second finite SSO policy run was not a clean zero-state reconciliation'
[[ "$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT count(*) FROM sso_setting WHERE is_deleted = false;")" == 0 ]] \
  || fail 'second finite SSO policy run created an active override'
log_ok 'second finite SSO policy run was idempotent and retained zero active overrides'

docker stop --time 90 "$MERGED_APP_CONTAINER" >/dev/null
[[ "$(docker container inspect --format '{{.State.Status}}' \
  "$MERGED_APP_CONTAINER")" == exited ]] \
  || fail 'merged final app did not stop before database policy injection'
if ! query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "INSERT INTO sso_setting (id, provider, settings, created, updated, is_deleted) VALUES ('runtime-sso-override', 'generic_oauth', '{\"enabled\":true}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, false); INSERT INTO api_key (org_id, name, key, role, created, updated, expires, service_account_id, last_used_at, is_revoked) VALUES (1, 'grafana-runtime-policy-legacy', 'runtime-policy-legacy-key', 'Viewer', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, NULL, NULL, NULL, false), (1, 'grafana-runtime-policy-service-account', 'runtime-policy-service-account-key', 'Viewer', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, floor(extract(epoch FROM CURRENT_TIMESTAMP + interval '91 days'))::bigint, 424242, NULL, false);" \
  >"${EVIDENCE_ROOT}/merged-policy-injection.log"; then
  fail 'could not inject the isolated SSO and token-policy regression rows'
fi
POLICY_INJECTED_COUNTS="$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT (SELECT count(*) FROM sso_setting WHERE is_deleted = false) || ':' || (SELECT count(*) FROM api_key WHERE COALESCE(is_revoked, false) = false AND name LIKE 'grafana-runtime-policy-%');")" \
  || fail 'could not count the isolated policy regression rows'
[[ "$POLICY_INJECTED_COUNTS" == '1:2' ]] \
  || fail 'isolated policy regression rows were not inserted exactly once'

run_merged_policy_job failure merged-policy-token-debt
grep -Fq \
  '2 active API or service-account token(s) violate the 90-day expiration policy' \
  "${EVIDENCE_ROOT}/merged-policy-token-debt.log" \
  || fail 'token-debt policy failure did not report the bounded non-secret count'
POLICY_ABORT_COUNTS="$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT (SELECT count(*) FROM sso_setting WHERE is_deleted = false) || ':' || (SELECT count(*) FROM api_key WHERE COALESCE(is_revoked, false) = false AND name LIKE 'grafana-runtime-policy-%');")" \
  || fail 'could not prove the token-debt transaction rollback'
[[ "$POLICY_ABORT_COUNTS" == '1:2' ]] \
  || fail 'token-debt failure partially reconciled SSO or token rows'
[[ "$(docker container inspect --format '{{.State.Status}}' \
  "$MERGED_APP_CONTAINER")" == exited ]] \
  || fail 'final app listener restarted despite failed token-debt policy'
if grep -Fq 'runtime-policy-' \
  "${EVIDENCE_ROOT}/merged-policy-token-debt.log"; then
  fail 'token-debt policy log exposed a synthetic token field'
fi
log_ok 'unbounded legacy and overlong service-account tokens aborted the transaction before SSO reconciliation without value disclosure'

query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "UPDATE api_key SET is_revoked = true, updated = CURRENT_TIMESTAMP WHERE name LIKE 'grafana-runtime-policy-%';" \
  >"${EVIDENCE_ROOT}/merged-policy-revoke.log" \
  || fail 'could not revoke the isolated token-policy regression rows'
run_merged_policy_job success merged-policy-reconcile
grep -Fq \
  'Verified 0 compliant active API/service-account token(s); reconciled 1 active SSO override(s); active overrides: 0.' \
  "${EVIDENCE_ROOT}/merged-policy-reconcile.log" \
  || fail 'recovery policy run did not prove one SSO reconciliation and zero token debt'
POLICY_RECOVERY_COUNTS="$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT (SELECT count(*) FROM sso_setting WHERE is_deleted = false) || ':' || (SELECT count(*) FROM sso_setting WHERE id = 'runtime-sso-override' AND is_deleted = true) || ':' || (SELECT count(*) FROM api_key WHERE COALESCE(is_revoked, false) = true AND name LIKE 'grafana-runtime-policy-%');")" \
  || fail 'could not prove the recovered SSO and token-policy state'
[[ "$POLICY_RECOVERY_COUNTS" == '0:1:2' ]] \
  || fail 'recovery policy did not soft-delete the override and retain both revoked token rows'
if ! merged_compose_bounded 240s up --detach --no-deps app \
  >"${EVIDENCE_ROOT}/merged-app-restart.log" 2>&1; then
  fail 'merged final app did not restart after successful policy reconciliation'
fi
wait_for_grafana "$MERGED_APP_CONTAINER"
[[ "$(query_database \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME" \
  "SELECT count(*) FROM sso_setting WHERE is_deleted = false;")" == 0 ]] \
  || fail 'merged app restart restored an active SSO database override'
log_ok 'controlled token revocation enabled atomic SSO soft-delete and a healthy zero-override app restart'

if ! docker exec "$MERGED_MAINTENANCE_CONTAINER" /bin/bash -euo pipefail -c '
  id
  stat -c "%u:%g:%a %n" /backup /restore
  [[ "$(stat -c "%u:%g:%a" /backup)" == "999:999:700" ]]
  probe="/backup/.grafana-runtime-write-probe.$$"
  mkdir -- "$probe"
  rmdir -- "$probe"
' >"${EVIDENCE_ROOT}/merged-maintenance-volume-contract.log" 2>&1; then
  fail 'merged maintenance backup volume is not owned and writable by UID/GID 999'
fi
if ! timeout --foreground 300s docker exec "$MERGED_MAINTENANCE_CONTAINER" \
  /usr/local/bin/backup.sh full \
  >"${EVIDENCE_ROOT}/merged-full-backup.log" 2>&1; then
  fail 'merged maintenance service could not create a bounded full PostgreSQL backup'
fi
if ! docker exec "$MERGED_MAINTENANCE_CONTAINER" /bin/bash -euo pipefail -c '
  pgrep supercronic >/dev/null
  marker=/backup/.postgresql-maintenance-last-success
  test -f "$marker" && test ! -L "$marker"
  epoch="$(<"$marker")"
  [[ "$epoch" =~ ^[0-9]+$ ]]
  (( $(date +%s) - epoch >= 0 ))
  (( $(date +%s) - epoch <= 300 ))
  '; then
  fail 'merged maintenance scheduler or successful-backup marker is invalid'
fi
log_ok 'merged maintenance scheduler completed a real full backup against PostgreSQL 18'

if ! docker run \
  --name "$MERGED_MARKER_CHECK_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user "${TEST_APP_UID}:${HOST_GROUP_ID}" \
  --read-only \
  --mount "type=volume,src=${MERGED_GRAFANA_STATE_VOLUME},dst=/state,readonly" \
  --mount "type=volume,src=${MERGED_GRAFANA_DATA_VOLUME},dst=/data,readonly" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc '
    marker=/state/bootstrap-v1.complete
    test -f "$marker" && test ! -L "$marker"
    test "$(stat -c %a "$marker")" = 600
    test "$(stat -c %u:%g "$marker")" = 472:472
    test "$(cat "$marker")" = grafana-bootstrap-v1
    count=/data/runtime-test-migrator/child-count
    boundary=/data/runtime-test-migrator/secret-boundary
    test -f "$count" && test ! -L "$count"
    test -f "$boundary" && test ! -L "$boundary"
    test "$(cat "$count")" = 2
    test "$(cat "$boundary")" = env-argv-proc-clean
  ' >"${EVIDENCE_ROOT}/merged-marker-check.log" 2>&1; then
  fail 'merged bootstrap marker or two-generation migrator proof is invalid'
fi
log_ok 'merged bootstrap marker and both real migrator generations remained exact through policy recovery'

merged_compose logs --no-color \
  >"${EVIDENCE_ROOT}/merged-compose.log" 2>&1 || true
if ! merged_compose_bounded 120s down --remove-orphans \
  >"${EVIDENCE_ROOT}/merged-down.log" 2>&1; then
  fail 'merged closure did not stop cleanly within 120 seconds'
fi
MERGED_STARTED=false
log_ok 'merged PostgreSQL, maintenance, bootstrap, migrator, SSO-policy, and final-app containers stopped cleanly'

timeout --foreground 300s docker pull "$POSTGRES_IMAGE" \
  >"${EVIDENCE_ROOT}/postgres-image-pull.log" 2>&1 \
  || fail 'PostgreSQL 18 image pull failed or exceeded 300 seconds'
docker network create \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  "$NETWORK_NAME" >/dev/null
docker volume create \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  "$DATABASE_VOLUME" >/dev/null
docker volume create \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  "$GRAFANA_DATA_VOLUME" >/dev/null
docker volume create \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  "$GRAFANA_STATE_VOLUME" >/dev/null
docker run --detach \
  --name "$PEER_PROBE_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc 'exec sleep 3600' >/dev/null
[[ "$(docker container inspect --format '{{.State.Status}}' \
  "$PEER_PROBE_CONTAINER")" == running ]] \
  || fail 'isolated same-network HTTP peer did not remain running'
docker run \
  --name "$VOLUME_INIT_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user 0:0 \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add FOWNER \
  --mount "type=volume,src=${GRAFANA_DATA_VOLUME},dst=/data" \
  --mount "type=volume,src=${GRAFANA_STATE_VOLUME},dst=/state" \
  --env "APP_UID=${TEST_APP_UID}" \
  --env "APP_GID=${TEST_APP_GID}" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc '
    chown "${APP_UID}:${APP_GID}" /data /state
    chmod 0770 /data /state
  ' >"${EVIDENCE_ROOT}/volume-init.log" 2>&1 \
  || fail 'could not initialize private Grafana data and bootstrap-state volumes'
docker run --detach \
  --name "$POSTGRES_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --group-add "$HOST_GROUP_ID" \
  --mount "type=volume,src=${DATABASE_VOLUME},dst=/var/lib/postgresql" \
  --mount "type=bind,src=${POSTGRES_PASSWORD_FILE},dst=/run/secrets/POSTGRES_PASSWORD,readonly" \
  --env "POSTGRES_USER=${DATABASE_USER}" \
  --env "POSTGRES_DB=${DATABASE_NAME}" \
  --env POSTGRES_PASSWORD_FILE=/run/secrets/POSTGRES_PASSWORD \
  --pull never \
  "$POSTGRES_IMAGE" >/dev/null
wait_for_postgresql
log_ok 'fresh PostgreSQL 18 database became ready'

log_info 'injecting late SIGTERM during the second bootstrap child retirement'
docker run --detach \
  --name "$BOOTSTRAP_SIGNAL_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --group-add "$HOST_GROUP_ID" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${TEST_APP_GID},mode=0771" \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,src=${GRAFANA_DATA_VOLUME},dst=/var/lib/grafana" \
  --mount "type=volume,src=${GRAFANA_STATE_VOLUME},dst=/var/lib/grafana-bootstrap-state" \
  --mount "type=bind,src=${POSTGRES_PASSWORD_FILE},dst=/run/secrets/POSTGRES_PASSWORD,readonly" \
  --mount "type=bind,src=${GRAFANA_SECRET_KEY_FILE},dst=/run/secrets/GRAFANA_SECRET_KEY,readonly" \
  --mount "type=bind,src=${GRAFANA_ADMIN_PASSWORD_FILE},dst=/run/secrets/GRAFANA_ADMIN_PASSWORD,readonly" \
  --mount "type=bind,src=${BOOTSTRAP_WRAPPER_FILE},dst=/runtime-test/grafana-vendor-wrapper.sh,readonly" \
  --env GF_DATABASE_TYPE=postgres \
  --env "GF_DATABASE_HOST=${POSTGRES_CONTAINER}:5432" \
  --env "GF_DATABASE_NAME=${DATABASE_NAME}" \
  --env "GF_DATABASE_USER=${DATABASE_USER}" \
  --env GF_DATABASE_SSL_MODE=disable \
  --env "GRAFANA_ADMIN_USER=${ADMIN_USER}" \
  --env GRAFANA_BOOTSTRAP_READY_TIMEOUT_SECONDS=240 \
  --env GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS=20 \
  --env GRAFANA_VENDOR_ENTRYPOINT=/runtime-test/grafana-vendor-wrapper.sh \
  "$IMAGE_NAME" bootstrap >/dev/null
SECOND_RETIREMENT_OBSERVED=false
for attempt in {1..240}; do
  if docker exec "$BOOTSTRAP_SIGNAL_CONTAINER" /bin/sh -ec \
    'test -f /var/lib/grafana/runtime-test-wrapper/term-2' \
    >/dev/null 2>&1; then
    SECOND_RETIREMENT_OBSERVED=true
    break
  fi
  if [[ "$(docker container inspect --format '{{.State.Status}}' \
    "$BOOTSTRAP_SIGNAL_CONTAINER")" == exited ]]; then
    break
  fi
  sleep 1
done
[[ "$SECOND_RETIREMENT_OBSERVED" == true ]] \
  || fail 'could not deterministically observe the second bootstrap child retirement'
docker kill --signal TERM "$BOOTSTRAP_SIGNAL_CONTAINER" >/dev/null
SIGNAL_EXIT_CODE=''
if ! SIGNAL_EXIT_CODE="$(timeout --foreground 90s docker wait \
  "$BOOTSTRAP_SIGNAL_CONTAINER")"; then
  fail 'late-SIGTERM bootstrap did not stop within 90 seconds'
fi
docker logs "$BOOTSTRAP_SIGNAL_CONTAINER" \
  >"${EVIDENCE_ROOT}/bootstrap-signal.log" 2>&1
[[ "$SIGNAL_EXIT_CODE" == 143 ]] \
  || fail "late-SIGTERM bootstrap exited ${SIGNAL_EXIT_CODE}; expected 143"
if ! docker run \
  --name "$BOOTSTRAP_SIGNAL_MARKER_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --read-only \
  --mount "type=volume,src=${GRAFANA_STATE_VOLUME},dst=/state,readonly" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc '
    test ! -e /state/bootstrap-v1.complete
    test ! -L /state/bootstrap-v1.complete
  ' >"${EVIDENCE_ROOT}/bootstrap-signal-marker.log" 2>&1; then
  fail 'late pre-commit SIGTERM left a bootstrap marker behind'
fi
log_ok 'late SIGTERM during second child retirement exited 143 and revoked every uncommitted marker'

log_info 'running the first bounded one-shot bootstrap'
if ! timeout --foreground 360s docker run \
  --name "$BOOTSTRAP_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --group-add "$HOST_GROUP_ID" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${TEST_APP_GID},mode=0771" \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,src=${GRAFANA_DATA_VOLUME},dst=/var/lib/grafana" \
  --mount "type=volume,src=${GRAFANA_STATE_VOLUME},dst=/var/lib/grafana-bootstrap-state" \
  --mount "type=bind,src=${POSTGRES_PASSWORD_FILE},dst=/run/secrets/POSTGRES_PASSWORD,readonly" \
  --mount "type=bind,src=${GRAFANA_SECRET_KEY_FILE},dst=/run/secrets/GRAFANA_SECRET_KEY,readonly" \
  --mount "type=bind,src=${GRAFANA_ADMIN_PASSWORD_FILE},dst=/run/secrets/GRAFANA_ADMIN_PASSWORD,readonly" \
  --env GF_DATABASE_TYPE=postgres \
  --env "GF_DATABASE_HOST=${POSTGRES_CONTAINER}:5432" \
  --env "GF_DATABASE_NAME=${DATABASE_NAME}" \
  --env "GF_DATABASE_USER=${DATABASE_USER}" \
  --env GF_DATABASE_SSL_MODE=disable \
  --env "GRAFANA_ADMIN_USER=${ADMIN_USER}" \
  --env GRAFANA_BOOTSTRAP_READY_TIMEOUT_SECONDS=240 \
  --env GRAFANA_BOOTSTRAP_STOP_TIMEOUT_SECONDS=30 \
  "$IMAGE_NAME" bootstrap \
  >"${EVIDENCE_ROOT}/bootstrap.log" 2>&1; then
  fail 'first Grafana bootstrap failed or exceeded 360 seconds'
fi
[[ "$(docker container inspect --format '{{.State.ExitCode}}' "$BOOTSTRAP_CONTAINER")" == 0 ]] \
  || fail 'first Grafana bootstrap did not exit zero'
log_ok 'first bootstrap initialized and independently reverified the recovery administrator'

if ! docker run \
  --name "$MARKER_CHECK_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --read-only \
  --mount "type=volume,src=${GRAFANA_STATE_VOLUME},dst=/state,readonly" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc '
    marker=/state/bootstrap-v1.complete
    test -f "$marker" && test ! -L "$marker"
    test "$(stat -c %a "$marker")" = 600
    test "$(stat -c %u:%g "$marker")" = 472:472
    test "$(stat -c %h "$marker")" = 1
    test "$(stat -c %s "$marker")" = 20
    test "$(cat "$marker")" = grafana-bootstrap-v1
  ' >"${EVIDENCE_ROOT}/marker-check.log" 2>&1; then
  fail 'bootstrap marker content, ownership, mode, link count, or size is invalid'
fi
log_ok 'bootstrap marker is exact, single-linked, UID/GID 472:472, mode 0600, and 20 bytes'

if ! timeout --foreground 30s docker run \
  --name "$BOOTSTRAP_REPEAT_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${TEST_APP_GID},mode=0771" \
  --mount "type=volume,src=${GRAFANA_STATE_VOLUME},dst=/var/lib/grafana-bootstrap-state,readonly" \
  "$IMAGE_NAME" bootstrap \
  >"${EVIDENCE_ROOT}/bootstrap-repeat.log" 2>&1; then
  fail 'marker-based second bootstrap failed or exceeded 30 seconds'
fi
grep -Fq 'Existing verified bootstrap marker; credential phase skipped.' \
  "${EVIDENCE_ROOT}/bootstrap-repeat.log" \
  || fail 'second bootstrap did not report credential-phase skip'
docker container inspect --format '{{json .Mounts}} {{json .Config.Env}}' \
  "$BOOTSTRAP_REPEAT_CONTAINER" >"${EVIDENCE_ROOT}/bootstrap-repeat-inspect.json"
if grep -Eq '/run/secrets|POSTGRES_PASSWORD|GRAFANA_SECRET_KEY|GRAFANA_ADMIN_PASSWORD' \
  "${EVIDENCE_ROOT}/bootstrap-repeat-inspect.json"; then
  fail 'marker-skip bootstrap unexpectedly received credential injection'
fi
log_ok 'second bootstrap skipped from the verified marker without any credential mount or environment injection'

HASH_BEFORE_REJECTION=''
if ! HASH_BEFORE_REJECTION="$(query_admin_hash)"; then
  fail 'could not capture administrator hash before CLI rejection test'
fi
[[ -n "$HASH_BEFORE_REJECTION" ]] || fail 'administrator hash is empty before CLI test'
if timeout --foreground 60s docker run \
  --name "$CLI_REJECT_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --group-add "$HOST_GROUP_ID" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${TEST_APP_GID},mode=0771" \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,src=${GRAFANA_DATA_VOLUME},dst=/var/lib/grafana" \
  --mount "type=bind,src=${POSTGRES_PASSWORD_FILE},dst=/run/secrets/POSTGRES_PASSWORD,readonly" \
  --mount "type=bind,src=${GRAFANA_SECRET_KEY_FILE},dst=/run/secrets/GRAFANA_SECRET_KEY,readonly" \
  --env GF_DATABASE_TYPE=postgres \
  --env "GF_DATABASE_HOST=${POSTGRES_CONTAINER}:5432" \
  --env "GF_DATABASE_NAME=${DATABASE_NAME}" \
  --env "GF_DATABASE_USER=${DATABASE_USER}" \
  --env GF_DATABASE_SSL_MODE=disable \
  "$IMAGE_NAME" grafana-cli admin reset-admin-password \
  --user-id 1 "forbidden-argv-${RUN_ID}" \
  >"${EVIDENCE_ROOT}/cli-reject.log" 2>&1; then
  fail 'argv password was unexpectedly accepted by the helper CLI'
fi
HASH_AFTER_REJECTION=''
if ! HASH_AFTER_REJECTION="$(query_admin_hash)"; then
  fail 'could not capture administrator hash after CLI rejection test'
fi
[[ "$HASH_AFTER_REJECTION" == "$HASH_BEFORE_REJECTION" ]] \
  || fail 'rejected argv password changed the administrator hash'
log_ok 'argv password was rejected before database mutation'

if ! printf '%s\n' "$RESET_PASSWORD_VALUE" | timeout --foreground 120s docker run --interactive \
  --name "$CLI_RESET_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --group-add "$HOST_GROUP_ID" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs "/run:rw,noexec,nosuid,nodev,size=64m,uid=${TEST_APP_UID},gid=${TEST_APP_GID},mode=0771" \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,src=${GRAFANA_DATA_VOLUME},dst=/var/lib/grafana" \
  --mount "type=bind,src=${POSTGRES_PASSWORD_FILE},dst=/run/secrets/POSTGRES_PASSWORD,readonly" \
  --mount "type=bind,src=${GRAFANA_SECRET_KEY_FILE},dst=/run/secrets/GRAFANA_SECRET_KEY,readonly" \
  --env GF_DATABASE_TYPE=postgres \
  --env "GF_DATABASE_HOST=${POSTGRES_CONTAINER}:5432" \
  --env "GF_DATABASE_NAME=${DATABASE_NAME}" \
  --env "GF_DATABASE_USER=${DATABASE_USER}" \
  --env GF_DATABASE_SSL_MODE=disable \
  "$IMAGE_NAME" grafana-cli admin reset-admin-password \
  --user-id 1 --password-from-stdin \
  >"${EVIDENCE_ROOT}/cli-reset.log" 2>&1; then
  fail 'stdin-only helper CLI password reset failed or exceeded 120 seconds'
fi
HASH_AFTER_RESET=''
if ! HASH_AFTER_RESET="$(query_admin_hash)"; then
  fail 'could not capture administrator hash after stdin CLI reset'
fi
[[ -n "$HASH_AFTER_RESET" && "$HASH_AFTER_RESET" != "$HASH_BEFORE_REJECTION" ]] \
  || fail 'stdin helper CLI did not mutate the administrator hash'
[[ "${#HASH_AFTER_RESET}" -eq 100 ]] \
  || fail 'stdin helper CLI produced an unexpected password-hash length'
log_ok 'stdin-only helper CLI with explicit user ID changed the password hash'

log_info 'starting the final daemon with the local form temporarily enabled'
start_grafana "$APP_FORM_CONTAINER" false
FORM_APP_URL="$APP_URL"
readonly FORM_APP_URL
log_ok 'final daemon became database-healthy with form login enabled'

require_http_status 200 form-health "${FORM_APP_URL}/api/health"
if ! jq --exit-status '
    .database == "ok"
    and (.version | type == "string")
    and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+([+-].*)?$"))
  ' "${EVIDENCE_ROOT}/form-health.body" >/dev/null; then
  fail 'real Grafana health did not expose a database-ok semantic version'
fi
GRAFANA_RUNTIME_VERSION="$(jq --exit-status --raw-output '.version' \
  "${EVIDENCE_ROOT}/form-health.body")" \
  || fail 'could not resolve the exact running Grafana version'
readonly GRAFANA_RUNTIME_VERSION
log_ok "real reviewed image runs Grafana ${GRAFANA_RUNTIME_VERSION}"

docker container inspect --format '{{json .Mounts}} {{json .Config.Env}}' \
  "$APP_FORM_CONTAINER" >"${EVIDENCE_ROOT}/app-form-inspect.json"
if ! docker exec --user "${TEST_APP_UID}:${TEST_APP_GID}" "$APP_FORM_CONTAINER" /bin/sh -euc '
  test ! -e /run/secrets/GRAFANA_ADMIN_PASSWORD
  test ! -e /run/grafana-secrets/GRAFANA_ADMIN_PASSWORD
  '; then
  fail 'final daemon unexpectedly exposes an administrator secret path'
fi
if ! docker exec --user "${TEST_APP_UID}:${TEST_APP_GID}" "$APP_FORM_CONTAINER" /bin/sh -euc '
  found_server=false
  for process_dir in /proc/[0-9]*; do
    test -r "$process_dir/cmdline" || continue
    command_line="$(tr "\000" "\n" <"$process_dir/cmdline" 2>/dev/null || true)"
    if test -r "$process_dir/comm" \
      && test "$(cat "$process_dir/comm" 2>/dev/null || true)" = grafana; then
      found_server=true
    fi
    printf "PROCESS %s\n" "${process_dir##*/}"
    printf "%s\n" "$command_line"
    if test -r "$process_dir/environ"; then
      tr "\000" "\n" <"$process_dir/environ" 2>/dev/null || true
    fi
  done
  test "$found_server" = true
  ' >"${EVIDENCE_ROOT}/app-form-processes.txt" 2>&1; then
  fail 'could not inspect the final daemon process set'
fi
if grep -Eq 'GRAFANA_ADMIN_PASSWORD|GF_SECURITY_ADMIN_PASSWORD' \
  "${EVIDENCE_ROOT}/app-form-inspect.json" \
  "${EVIDENCE_ROOT}/app-form-processes.txt"; then
  fail 'final daemon exposed an administrator secret mount or environment key'
fi
if grep -R -F -f "$GRAFANA_ADMIN_PASSWORD_FILE" \
  "${EVIDENCE_ROOT}/app-form-inspect.json" \
  "${EVIDENCE_ROOT}/app-form-processes.txt" >/dev/null; then
  fail 'final daemon exposed the initial administrator secret value'
fi
DATABASE_PROCESS_KEYS="$(sed -n \
  's/^\(GF_DATABASE_[A-Z0-9_]*\)=.*/\1/p' \
  "${EVIDENCE_ROOT}/app-form-processes.txt" | sort -u)"
readonly DATABASE_PROCESS_KEYS
[[ "$DATABASE_PROCESS_KEYS" == $'GF_DATABASE_HOST\nGF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC\nGF_DATABASE_MIGRATION_LOCKING\nGF_DATABASE_NAME\nGF_DATABASE_PASSWORD\nGF_DATABASE_SKIP_MIGRATIONS\nGF_DATABASE_SSL_MODE\nGF_DATABASE_TYPE\nGF_DATABASE_USER' ]] \
  || fail 'final daemon process accepted an unknown or omitted GF_DATABASE setting'
for required_database_setting in \
  "GF_DATABASE_HOST=${POSTGRES_CONTAINER}:5432" \
  'GF_DATABASE_SKIP_MIGRATIONS=false' \
  'GF_DATABASE_MIGRATION_LOCKING=true' \
  'GF_DATABASE_LOCKING_ATTEMPT_TIMEOUT_SEC=0'; do
  grep -Fxq "$required_database_setting" \
    "${EVIDENCE_ROOT}/app-form-processes.txt" \
    || fail "final daemon process lost reviewed database setting: ${required_database_setting%%=*}"
done
log_ok 'final daemon has no administrator secret exposure and enforces the exact PostgreSQL migration/locking environment'

printf '{"user":"%s","password":"%s"}' \
  "$ADMIN_USER" "$RESET_PASSWORD_VALUE" >"$LOGIN_PAYLOAD_FILE"
printf '%s' '{"provider":"generic_oauth","settings":{"enabled":false}}' \
  >"$SSO_MUTATION_FILE"
chmod 0600 "$LOGIN_PAYLOAD_FILE"
require_http_status 200 form-login \
  --cookie-jar "$ADMIN_COOKIE_FILE" \
  --header 'Content-Type: application/json' \
  --data-binary "@${LOGIN_PAYLOAD_FILE}" \
  "${FORM_APP_URL}/login"
chmod 0600 "$ADMIN_COOKIE_FILE"
if ! awk \
  '$6 == "grafana_session" && $4 == "TRUE" { found = 1 } END { exit(found ? 0 : 1) }' \
  "$ADMIN_COOKIE_FILE"; then
  fail 'form login did not emit an HTTPS-only Grafana session cookie'
fi
ADMIN_COOKIE_VALUE="$(awk '$6 == "grafana_session" { print $7; exit }' \
  "$ADMIN_COOKIE_FILE")"
[[ -n "$ADMIN_COOKIE_VALUE" \
  && "$ADMIN_COOKIE_VALUE" != *$'\r'* \
  && "$ADMIN_COOKIE_VALUE" != *$'\n'* ]] \
  || fail 'captured Grafana session cookie is empty or malformed'
printf 'Cookie: grafana_session=%s\n' "$ADMIN_COOKIE_VALUE" \
  >"$ADMIN_COOKIE_HEADER_FILE"
unset ADMIN_COOKIE_VALUE
chmod 0600 "$ADMIN_COOKIE_HEADER_FILE"
log_ok 'local form login accepted the stdin-rotated recovery password'

require_http_status 200 form-admin-settings \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  "${FORM_APP_URL}/api/admin/settings"
if ! jq --exit-status \
  --arg role_path "$EXPECTED_ROLE_ATTRIBUTE_PATH" '
    .auth.login_maximum_lifetime_duration == "8h"
    and .auth.login_maximum_inactive_lifetime_duration == "1h"
    and .auth.token_rotation_interval_minutes == "5"
    and .auth.api_key_max_seconds_to_live == "7776000"
    and .auth.oauth_allow_insecure_email_lookup == "false"
    and .["auth.generic_oauth"].scopes == "openid profile email offline_access"
    and .["auth.generic_oauth"].use_refresh_token == "true"
    and .["auth.generic_oauth"].role_attribute_path == $role_path
    and .sso_settings.configurable_providers == "saervices_policy_locked"
    and .metrics.enabled == "false"
    and .public_dashboards.enabled == "false"
    and .snapshots.enabled == "false"
    and .snapshots.external_enabled == "false"
    and .plugins.plugin_admin_enabled == "false"
    and .service_accounts.token_expiration_day_limit == "90"
    and .security.cookie_secure == "true"
    and .security.disable_gravatar == "true"
    and .users.allow_sign_up == "false"
    and .users.allow_org_create == "false"
  ' "${EVIDENCE_ROOT}/form-admin-settings.body" >/dev/null; then
  fail 'effective final settings lost a session, OAuth, SSO-lock, token, metrics, sharing, snapshot, or plugin invariant'
fi
log_ok 'effective final settings enforce refresh-aware OIDC, bounded sessions and tokens, exact-one roles, and disabled public mutation surfaces'

require_http_status 302 form-metrics-disabled \
  "${FORM_APP_URL}/metrics"
require_http_status 302 form-public-dashboard-disabled \
  "${FORM_APP_URL}/public-dashboards/runtime-invalid-token"
require_http_status 403 form-snapshot-api-disabled \
  "${FORM_APP_URL}/api/snapshots/runtime-invalid-token"
require_peer_http_status 302 peer-metrics-disabled \
  "http://${APP_FORM_CONTAINER}:3000/metrics"
require_peer_http_status 302 peer-public-dashboard-disabled \
  "http://${APP_FORM_CONTAINER}:3000/public-dashboards/runtime-invalid-token"
require_peer_http_status 403 peer-snapshot-api-disabled \
  "http://${APP_FORM_CONTAINER}:3000/api/snapshots/runtime-invalid-token"
if grep -Eq '^# (HELP|TYPE) ' "${EVIDENCE_ROOT}/form-metrics-disabled.body"; then
  fail 'host-side disabled metrics route returned Prometheus exposition data'
fi
if docker exec "$PEER_PROBE_CONTAINER" /bin/grep -Eq '^# (HELP|TYPE) ' \
  /tmp/peer-metrics-disabled.body; then
  fail 'same-network disabled metrics route returned Prometheus exposition data'
else
  PEER_METRICS_GREP_STATUS="$?"
  [[ "$PEER_METRICS_GREP_STATUS" == 1 ]] \
    || fail 'could not inspect the same-network disabled metrics response body'
fi
METRICS_CONTENT_TYPE="$(curl --silent --show-error --max-time 10 \
  --output /dev/null --write-out '%{content_type}' \
  "${FORM_APP_URL}/metrics")" \
  || fail 'could not resolve disabled host-side metrics content type'
PEER_METRICS_CONTENT_TYPE="$(docker exec "$PEER_PROBE_CONTAINER" \
  /usr/bin/curl --silent --show-error --max-time 10 \
  --output /dev/null --write-out '%{content_type}' \
  "http://${APP_FORM_CONTAINER}:3000/metrics")" \
  || fail 'could not resolve disabled peer metrics content type'
readonly METRICS_CONTENT_TYPE PEER_METRICS_CONTENT_TYPE
case "$METRICS_CONTENT_TYPE $PEER_METRICS_CONTENT_TYPE" in
  *text/plain*|*application/openmetrics-text*)
    fail 'disabled metrics route retained a Prometheus response content type'
    ;;
esac
log_ok 'host and same-network anonymous metrics, public-dashboard, and snapshot routes remained unavailable'

require_http_status 200 form-sso-settings-list \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  "${FORM_APP_URL}/api/v1/sso-settings"
if ! jq --exit-status '
    [.. | objects | .provider? // empty]
    | all(. != "generic_oauth"
      and . != "github"
      and . != "gitlab"
      and . != "google"
      and . != "azuread"
      and . != "okta")
  ' "${EVIDENCE_ROOT}/form-sso-settings-list.body" >/dev/null; then
  fail 'SSO settings list exposed a known mutable OAuth provider'
fi
for provider_name in "${SSO_PROVIDERS[@]}"; do
  require_http_status 404 "form-sso-get-${provider_name}" \
    --header "@${ADMIN_COOKIE_HEADER_FILE}" \
    "${FORM_APP_URL}/api/v1/sso-settings/${provider_name}"
  require_http_status 404 "form-sso-put-${provider_name}" \
    --request PUT \
    --header "@${ADMIN_COOKIE_HEADER_FILE}" \
    --header 'Content-Type: application/json' \
    --data-binary "@${SSO_MUTATION_FILE}" \
    "${FORM_APP_URL}/api/v1/sso-settings/${provider_name}"
done
[[ "$(query_database \
  "$POSTGRES_CONTAINER" "$DATABASE_USER" "$DATABASE_NAME" \
  "SELECT count(*) FROM sso_setting WHERE NOT is_deleted;")" == 0 ]] \
  || fail 'blocked SSO API requests created an active database override'
log_ok 'the UI-backed SSO API listed no OAuth provider and rejected every known OAuth GET/PUT mutation without database state'

BASIC_VALUE="$(printf '%s:%s' "$ADMIN_USER" "$RESET_PASSWORD_VALUE" | base64 -w 0)"
printf 'Authorization: Basic %s\n' "$BASIC_VALUE" >"$BASIC_HEADER_FILE"
unset BASIC_VALUE
chmod 0600 "$BASIC_HEADER_FILE"
require_http_status 401 form-basic-disabled \
  --header "@${BASIC_HEADER_FILE}" \
  "${FORM_APP_URL}/api/admin/settings"
log_ok 'HTTP Basic remained disabled while the local form was enabled'

FORM_CONTAINER_ID_BEFORE_RESTART="$(docker container inspect --format '{{.Id}}' \
  "$APP_FORM_CONTAINER")" \
  || fail 'could not capture the final form-enabled container identity before restart'
FORM_STARTED_AT_BEFORE_RESTART="$(docker container inspect --format '{{.State.StartedAt}}' \
  "$APP_FORM_CONTAINER")" \
  || fail 'could not capture the final form-enabled container start time before restart'
if ! timeout --foreground 120s docker restart --timeout 90 "$APP_FORM_CONTAINER" \
  >"${EVIDENCE_ROOT}/form-container-restart.log" 2>&1; then
  fail 'real final Grafana container restart failed or exceeded 120 seconds'
fi
wait_for_grafana "$APP_FORM_CONTAINER"
FORM_RESTARTED_HOST_PORT="$(docker container inspect --format \
  '{{ (index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort }}' \
  "$APP_FORM_CONTAINER")" \
  || fail 'could not resolve the final form-enabled host port after restart'
[[ "$FORM_RESTARTED_HOST_PORT" =~ ^[0-9]+$ ]] \
  || fail 'Docker returned an invalid dynamic host port after container restart'
FORM_RESTARTED_APP_URL="http://127.0.0.1:${FORM_RESTARTED_HOST_PORT}"
readonly FORM_RESTARTED_HOST_PORT FORM_RESTARTED_APP_URL
wait_for_host_http "${FORM_RESTARTED_APP_URL}/api/health" 200
FORM_CONTAINER_ID_AFTER_RESTART="$(docker container inspect --format '{{.Id}}' \
  "$APP_FORM_CONTAINER")" \
  || fail 'could not capture the final form-enabled container identity after restart'
FORM_STARTED_AT_AFTER_RESTART="$(docker container inspect --format '{{.State.StartedAt}}' \
  "$APP_FORM_CONTAINER")" \
  || fail 'could not capture the final form-enabled container start time after restart'
[[ "$FORM_CONTAINER_ID_AFTER_RESTART" == "$FORM_CONTAINER_ID_BEFORE_RESTART" \
  && "$FORM_STARTED_AT_AFTER_RESTART" > "$FORM_STARTED_AT_BEFORE_RESTART" ]] \
  || fail 'Docker did not restart the same final Grafana container process'
require_http_status 200 form-admin-settings-after-container-restart \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  "${FORM_RESTARTED_APP_URL}/api/admin/settings"
if ! jq --exit-status \
  --arg role_path "$EXPECTED_ROLE_ATTRIBUTE_PATH" '
    .auth.login_maximum_lifetime_duration == "8h"
    and .auth.login_maximum_inactive_lifetime_duration == "1h"
    and .auth.token_rotation_interval_minutes == "5"
    and .auth.api_key_max_seconds_to_live == "7776000"
    and .auth.oauth_allow_insecure_email_lookup == "false"
    and .["auth.generic_oauth"].scopes == "openid profile email offline_access"
    and .["auth.generic_oauth"].use_refresh_token == "true"
    and .["auth.generic_oauth"].role_attribute_path == $role_path
    and .sso_settings.configurable_providers == "saervices_policy_locked"
    and .metrics.enabled == "false"
    and .public_dashboards.enabled == "false"
    and .snapshots.enabled == "false"
    and .snapshots.external_enabled == "false"
    and .plugins.plugin_admin_enabled == "false"
    and .service_accounts.token_expiration_day_limit == "90"
    and .security.cookie_secure == "true"
    and .security.disable_gravatar == "true"
    and .users.allow_sign_up == "false"
    and .users.allow_org_create == "false"
  ' "${EVIDENCE_ROOT}/form-admin-settings-after-container-restart.body" >/dev/null; then
  fail 'real container restart changed a session, OAuth, TTL, SSO-lock, or public-feature invariant'
fi
require_http_status 404 form-sso-get-generic-oauth-after-container-restart \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  "${FORM_RESTARTED_APP_URL}/api/v1/sso-settings/generic_oauth"
require_http_status 404 form-sso-put-generic-oauth-after-container-restart \
  --request PUT \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  --header 'Content-Type: application/json' \
  --data-binary "@${SSO_MUTATION_FILE}" \
  "${FORM_RESTARTED_APP_URL}/api/v1/sso-settings/generic_oauth"
[[ "$(query_database \
  "$POSTGRES_CONTAINER" "$DATABASE_USER" "$DATABASE_NAME" \
  "SELECT count(*) FROM sso_setting WHERE NOT is_deleted;")" == 0 ]] \
  || fail 'real container restart restored or created an active SSO database override'
log_ok 'real same-container restart preserved zero overrides, the SSO sentinel, bounded TTLs, and disabled public features without claiming a fresh policy run'

stop_and_remove_container "$APP_FORM_CONTAINER"
log_info 'starting the final daemon with the local form disabled'
start_grafana "$APP_LOCKED_CONTAINER" true
LOCKED_APP_URL="$APP_URL"
readonly LOCKED_APP_URL
log_ok 'final daemon became database-healthy with form login disabled'

require_http_status 400 locked-form-disabled \
  --header 'Content-Type: application/json' \
  --data-binary "@${LOGIN_PAYLOAD_FILE}" \
  "${LOCKED_APP_URL}/login"
log_ok 'local form login was rejected after the locked relaunch'

require_http_status 401 locked-basic-disabled \
  --header "@${BASIC_HEADER_FILE}" \
  "${LOCKED_APP_URL}/api/admin/settings"
log_ok 'HTTP Basic remained disabled after the locked relaunch'

require_http_status 401 locked-anonymous-disabled \
  "${LOCKED_APP_URL}/api/admin/settings"
log_ok 'anonymous access remained disabled after the locked relaunch'

require_http_status 200 locked-session-persisted \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  "${LOCKED_APP_URL}/api/admin/settings"
if ! jq --exit-status '
    .sso_settings.configurable_providers == "saervices_policy_locked"
    and .["auth.generic_oauth"].use_refresh_token == "true"
    and .auth.oauth_allow_insecure_email_lookup == "false"
    and .metrics.enabled == "false"
    and .public_dashboards.enabled == "false"
    and .snapshots.enabled == "false"
    and .snapshots.external_enabled == "false"
    and .plugins.plugin_admin_enabled == "false"
    and .security.cookie_secure == "true"
    and .security.disable_gravatar == "true"
    and .users.allow_sign_up == "false"
    and .users.allow_org_create == "false"
  ' "${EVIDENCE_ROOT}/locked-session-persisted.body" >/dev/null; then
  fail 'locked relaunch changed the effective SSO or anonymous-feature policy'
fi
require_http_status 404 locked-sso-put-generic-oauth \
  --request PUT \
  --header "@${ADMIN_COOKIE_HEADER_FILE}" \
  --header 'Content-Type: application/json' \
  --data-binary "@${SSO_MUTATION_FILE}" \
  "${LOCKED_APP_URL}/api/v1/sso-settings/generic_oauth"
[[ "$(query_database \
  "$POSTGRES_CONTAINER" "$DATABASE_USER" "$DATABASE_NAME" \
  "SELECT count(*) FROM sso_setting WHERE NOT is_deleted;")" == 0 ]] \
  || fail 'locked relaunch restored or created an active SSO database override'
log_ok 'locked relaunch preserved the administrator session while the sentinel and zero active SSO overrides remained authoritative'

if ! OIDC_STATUS="$(curl --silent --show-error --max-time 10 \
  --dump-header "${EVIDENCE_ROOT}/oidc.headers" \
  --output "${EVIDENCE_ROOT}/oidc.body" \
  --write-out '%{http_code}' \
  "${LOCKED_APP_URL}/login/generic_oauth")"; then
  fail 'OIDC redirect request failed'
fi
[[ "$OIDC_STATUS" == 302 ]] || fail "OIDC endpoint returned HTTP ${OIDC_STATUS}; expected 302"
grep -Eqi "^location: https://${AUTHENTIK_DOMAIN}/application/o/authorize/" \
  "${EVIDENCE_ROOT}/oidc.headers" \
  || fail 'OIDC redirect did not target the configured Authentik authorization endpoint'
grep -Eqi '(^|[?&])code_challenge=' "${EVIDENCE_ROOT}/oidc.headers" \
  || fail 'OIDC redirect did not include a PKCE code challenge'
log_ok 'OIDC produced a bounded Authentik authorization redirect with PKCE'

log_info 'building an isolated OAuth claim source for the real Grafana role engine'
if ! timeout --foreground 300s docker run \
  --name "$ROLE_OAUTH_BUILD_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network none \
  --user "${HOST_USER_ID}:${HOST_GROUP_ID}" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=256m \
  --mount "type=bind,src=${RUNTIME_ROOT},dst=/work" \
  --workdir /work \
  --env GOCACHE=/tmp/go-cache \
  --entrypoint /bin/sh \
  "$GRAFANA_GO_IMAGE" -euc '
    gofmt -w role-oauth-mock.go
    CGO_ENABLED=0 go build -buildvcs=false -trimpath \
      -ldflags="-s -w -buildid=" -o role-oauth-mock role-oauth-mock.go
  ' >"${EVIDENCE_ROOT}/role-oauth-build.log" 2>&1; then
  fail 'isolated OAuth claim-source build failed or exceeded 300 seconds'
fi
[[ -f "$ROLE_OAUTH_BINARY_FILE" && ! -L "$ROLE_OAUTH_BINARY_FILE" ]] \
  || fail 'isolated OAuth claim-source build did not publish a regular binary'
chmod 0555 "$ROLE_OAUTH_BINARY_FILE"

docker volume create \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  "$ROLE_GRAFANA_DATA_VOLUME" >/dev/null
docker run \
  --name "$ROLE_VOLUME_INIT_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --user 0:0 \
  --cap-drop ALL \
  --cap-add CHOWN \
  --mount "type=volume,src=${ROLE_GRAFANA_DATA_VOLUME},dst=/data" \
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc 'chmod 0700 /data; chown 472:472 /data' \
  >"${EVIDENCE_ROOT}/role-volume-init.log" 2>&1 \
  || fail 'could not initialize the isolated role-engine data volume'
docker run --detach \
  --name "$ROLE_OAUTH_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user 65534:65534 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
  --mount "type=bind,src=${ROLE_OAUTH_BINARY_FILE},dst=/usr/local/bin/role-oauth-mock,readonly" \
  --entrypoint /usr/local/bin/role-oauth-mock \
  "$GRAFANA_GO_IMAGE" >/dev/null
wait_for_peer_http "http://${ROLE_OAUTH_CONTAINER}:8080/health" 200

docker run --detach \
  --name "$ROLE_APP_CONTAINER" \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --network "$NETWORK_NAME" \
  --user "${TEST_APP_UID}:${TEST_APP_GID}" \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,src=${ROLE_GRAFANA_DATA_VOLUME},dst=/var/lib/grafana" \
  --env GF_SERVER_HTTP_ADDR=0.0.0.0 \
  --env GF_SERVER_HTTP_PORT=3000 \
  --env "GF_SERVER_ROOT_URL=http://${ROLE_APP_CONTAINER}:3000/" \
  --env GF_AUTH_DISABLE_LOGIN_FORM=true \
  --env GF_AUTH_BASIC_ENABLED=false \
  --env GF_AUTH_ANONYMOUS_ENABLED=false \
  --env GF_AUTH_GENERIC_OAUTH_ENABLED=true \
  --env GF_AUTH_GENERIC_OAUTH_NAME=runtime-role-proof \
  --env GF_AUTH_GENERIC_OAUTH_CLIENT_ID=runtime-role-client \
  --env 'GF_AUTH_GENERIC_OAUTH_SCOPES=openid profile email offline_access' \
  --env "GF_AUTH_GENERIC_OAUTH_AUTH_URL=http://${ROLE_OAUTH_CONTAINER}:8080/authorize" \
  --env "GF_AUTH_GENERIC_OAUTH_TOKEN_URL=http://${ROLE_OAUTH_CONTAINER}:8080/token" \
  --env "GF_AUTH_GENERIC_OAUTH_API_URL=http://${ROLE_OAUTH_CONTAINER}:8080/userinfo" \
  --env GF_AUTH_GENERIC_OAUTH_ALLOW_SIGN_UP=true \
  --env GF_AUTH_GENERIC_OAUTH_USE_PKCE=true \
  --env GF_AUTH_GENERIC_OAUTH_USE_REFRESH_TOKEN=true \
  --env GF_AUTH_GENERIC_OAUTH_VALIDATE_ID_TOKEN=false \
  --env GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH=sub \
  --env GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH=name \
  --env GF_AUTH_GENERIC_OAUTH_EMAIL_ATTRIBUTE_PATH=email \
  --env GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH=groups \
  --env GF_AUTH_GENERIC_OAUTH_ALLOWED_GROUPS=grafana-users \
  --env "GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH=${EXPECTED_ROLE_ATTRIBUTE_PATH}" \
  --env GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT=true \
  --env GF_AUTH_GENERIC_OAUTH_ALLOW_ASSIGN_GRAFANA_ADMIN=true \
  --env GF_SSO_SETTINGS_CONFIGURABLE_PROVIDERS=saervices_policy_locked \
  --env GF_ANALYTICS_REPORTING_ENABLED=false \
  --env GF_ANALYTICS_CHECK_FOR_UPDATES=false \
  --env GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false \
  --entrypoint /run.sh \
  "$IMAGE_NAME" >/dev/null
wait_for_peer_http "http://${ROLE_APP_CONTAINER}:3000/api/health" 200

for role_mask in 0 1 2 3 4 5 6 7; do
  require_peer_http_status 204 "role-select-${role_mask}" \
    "http://${ROLE_OAUTH_CONTAINER}:8080/select?mask=${role_mask}"
  if ! docker exec "$PEER_PROBE_CONTAINER" /bin/sh -euc '
    cookie_file="/tmp/role-cookie-${1}"
    rm -f -- "$cookie_file"
    status="$(/usr/bin/curl --silent --show-error --location --max-time 30 \
      --cookie-jar "$cookie_file" --cookie "$cookie_file" \
      --output "/tmp/role-flow-${1}.body" --write-out "%{http_code}" \
      "http://${2}:3000/login/generic_oauth")"
    test "$status" = 200
  ' grafana-runtime-role "$role_mask" "$ROLE_APP_CONTAINER"; then
    fail "real OAuth flow failed for role mask ${role_mask}"
  fi
  if ! ROLE_USER_STATUS="$(docker exec "$PEER_PROBE_CONTAINER" /bin/sh -euc '
    exec /usr/bin/curl --silent --show-error --max-time 10 \
      --cookie "/tmp/role-cookie-${1}" \
      --output "/tmp/role-user-${1}.json" --write-out "%{http_code}" \
      "http://${2}:3000/api/user"
  ' grafana-runtime-role "$role_mask" "$ROLE_APP_CONTAINER")"; then
    fail "real OAuth user probe failed for role mask ${role_mask}"
  fi
  case "$role_mask" in
    1)
      [[ "$ROLE_USER_STATUS" == 200 ]] \
        || fail 'admin-only group claim did not authenticate'
      if ! docker exec "$PEER_PROBE_CONTAINER" /bin/cat \
        "/tmp/role-user-${role_mask}.json" \
        >"${EVIDENCE_ROOT}/role-user-${role_mask}.json"; then
        fail 'could not capture the admin-only role response'
      fi
      jq --exit-status '.isGrafanaAdmin == true' \
        "${EVIDENCE_ROOT}/role-user-${role_mask}.json" >/dev/null \
        || fail 'admin-only group claim did not receive GrafanaAdmin'
      ;;
    2|4)
      [[ "$ROLE_USER_STATUS" == 200 ]] \
        || fail "single non-admin role group ${role_mask} did not authenticate"
      if ! docker exec "$PEER_PROBE_CONTAINER" /bin/cat \
        "/tmp/role-user-${role_mask}.json" \
        >"${EVIDENCE_ROOT}/role-user-${role_mask}.json"; then
        fail "could not capture the single-group role response for mask ${role_mask}"
      fi
      jq --exit-status '.isGrafanaAdmin == false' \
        "${EVIDENCE_ROOT}/role-user-${role_mask}.json" >/dev/null \
        || fail "single non-admin role group ${role_mask} received GrafanaAdmin"
      if ! ROLE_ORGS_STATUS="$(docker exec "$PEER_PROBE_CONTAINER" /bin/sh -euc '
        exec /usr/bin/curl --silent --show-error --max-time 10 \
          --cookie "/tmp/role-cookie-${1}" \
          --output "/tmp/role-orgs-${1}.json" --write-out "%{http_code}" \
          "http://${2}:3000/api/user/orgs"
      ' grafana-runtime-role "$role_mask" "$ROLE_APP_CONTAINER")"; then
        fail "real OAuth organization probe failed for role mask ${role_mask}"
      fi
      [[ "$ROLE_ORGS_STATUS" == 200 ]] \
        || fail "single role group ${role_mask} could not read its organization role"
      if ! docker exec "$PEER_PROBE_CONTAINER" /bin/cat \
        "/tmp/role-orgs-${role_mask}.json" \
        >"${EVIDENCE_ROOT}/role-orgs-${role_mask}.json"; then
        fail "could not capture the organization-role response for mask ${role_mask}"
      fi
      if [[ "$role_mask" == 2 ]]; then
        jq --exit-status 'any(.[]; .role == "Editor")' \
          "${EVIDENCE_ROOT}/role-orgs-${role_mask}.json" >/dev/null \
          || fail 'editor-only group claim did not receive Editor'
      else
        jq --exit-status 'any(.[]; .role == "Viewer")' \
          "${EVIDENCE_ROOT}/role-orgs-${role_mask}.json" >/dev/null \
          || fail 'viewer-only group claim did not receive Viewer'
      fi
      ;;
    *)
      [[ "$ROLE_USER_STATUS" == 401 ]] \
        || fail "zero, paired, or triple role groups unexpectedly authenticated for mask ${role_mask}"
      ;;
  esac
  log_ok "real Grafana JMESPath role engine enforced exact-one semantics for mask ${role_mask}"
done

docker logs "$APP_LOCKED_CONTAINER" >"${EVIDENCE_ROOT}/app-locked.log" 2>&1
if grep -R -F -f "$POSTGRES_PASSWORD_FILE" \
  -f "$GRAFANA_SECRET_KEY_FILE" \
  -f "$GRAFANA_ADMIN_PASSWORD_FILE" \
  -f "$GRAFANA_OIDC_CLIENT_SECRET_FILE" \
  "$EVIDENCE_ROOT" >/dev/null; then
  fail 'a synthetic secret value appeared in retained runtime evidence'
fi
log_ok 'runtime evidence contains no synthetic password, secret key, or OIDC client secret value'

SUITE_COMPLETED=true
