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

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_documented_runbook_contracts
#   Vælidætes criticæl Græfænæ runbooks ænd isolæted negætive fixtures.
#ææææææææææææææææææææææææææææææææææ
validate_documented_runbook_contracts() {
  python3 - "${TEST_REPO_ROOT}/Grafana/README.md" \
    "${TEST_REPO_ROOT}/run.sh" \
    "${RUNTIME_ROOT}/runbook-contracts" <<'PY'
import re
import subprocess
import sys
import textwrap
from pathlib import Path


class ContractError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise ContractError(message)


def require_text(source, needle, message):
    require(needle in source, message)


def require_order(source, needles, message):
    offset = 0
    for step_number, needle in enumerate(needles, start=1):
        position = source.find(needle, offset)
        if position < 0:
            raise ContractError(
                f"{message}: step {step_number} missing or reordered {needle!r}"
            )
        offset = position + len(needle)


def bash_block_after_anchor(document, anchor):
    marker = f'<div id="{anchor}"></div>'
    require(document.count(marker) == 1, f"anchor must occur exactly once: {anchor}")
    anchor_offset = document.index(marker) + len(marker)
    tail = document[anchor_offset:]
    fence = re.search(r"(?m)^[ \t]*```bash[ \t]*$", tail)
    require(fence is not None, f"anchor has no Bash block: {anchor}")
    block_offset = anchor_offset + fence.end()
    block_tail = document[block_offset:]
    closing = re.search(r"(?m)^[ \t]*```[ \t]*$", block_tail)
    require(closing is not None, f"Bash block is not closed: {anchor}")
    return textwrap.dedent(block_tail[:closing.start()]).strip() + "\n"


def bash_block_records(document):
    return [
        (
            match.start(),
            match.end(),
            textwrap.dedent(match.group(1)).strip() + "\n",
        )
        for match in re.finditer(
            r"(?ms)^[ \t]*```bash[ \t]*$\n(.*?)^[ \t]*```[ \t]*$",
            document,
        )
    ]


def bash_blocks(document):
    return [block for _, _, block in bash_block_records(document)]


def bash_block_containing(document, marker):
    matches = [block for block in bash_blocks(document) if marker in block]
    require(len(matches) == 1, f"Bash marker must select exactly one block: {marker}")
    return matches[0]


def bash_block_record_containing(document, marker):
    matches = [record for record in bash_block_records(document) if marker in record[2]]
    require(len(matches) == 1, f"Bash marker must select exactly one block: {marker}")
    return matches[0]


def normalize_shell(source):
    return re.sub(r"[ \t]+", " ", re.sub(r"\\\n[ \t]*", "", source))


def compact_shell(source):
    return re.sub(r"\s+", " ", normalize_shell(source)).strip()


def require_bash_syntax(block, name):
    result = subprocess.run(
        ["bash", "-n"],
        input=block,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(result.returncode == 0, f"{name} is not valid Bash: {result.stderr.strip()}")


def find_shell_function_end(lines, start, function_name):
    last_error = "no closing brace candidate"
    for end in range(start + 1, len(lines)):
        if lines[end].strip() != "}":
            continue
        candidate = textwrap.dedent("\n".join(lines[start:end + 1])) + "\n"
        result = subprocess.run(
            ["bash", "-n"],
            input=candidate,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode == 0:
            return end
        last_error = result.stderr.strip()
    raise ContractError(
        f"documented function is not closed: {function_name}: {last_error}"
    )


def extract_shell_function(block, function_name):
    lines = block.splitlines()
    signature = f"{function_name}() {{"
    try:
        start = next(index for index, line in enumerate(lines) if line.strip() == signature)
    except StopIteration as error:
        raise ContractError(f"missing documented function: {function_name}") from error
    end = find_shell_function_end(lines, start, function_name)
    return textwrap.dedent("\n".join(lines[start:end + 1])) + "\n"


def validate_function_extractor_fixture():
    fixture = r'''fixture_function() {
  local rendered
  rendered="$(printf '%s\n' '
{
  "quoted-closing-brace": "}"
}
')" || {
    return 1
  }
  test -n "$rendered" || {
    return 1
  }
  printf '%s\n' extractor-reached-tail
}
outside_function=true
'''
    extracted = extract_shell_function(fixture, "fixture_function")
    require_text(
        extracted,
        "extractor-reached-tail",
        "function extractor stopped at a quoted or nested brace",
    )
    require(
        "outside_function" not in extracted,
        "function extractor consumed commands after the function",
    )


def validate_restore_exchange(block):
    compact_block = compact_shell(block)
    required_fragments = (
        'app_stage_parent="$(pwd)/.appdata-restore-$restore_id"',
        'app_stage="$app_stage_parent/appdata"',
        'appdata_manifest="$db_stage/appdata-tree.manifest.v1"',
        'appdata_binding="$db_stage/appdata-tree.binding.v1"',
        "'directory:700:0:0'",
        'test ! -L "$app_stage_parent"',
        'find . -xdev -print0 | LC_ALL=C sort -z |',
        'test ! -L "$manifest_entry"',
        'manifest_type=directory',
        'manifest_type=file',
        'test "$(stat -c \'%h\' -- "$manifest_entry")" -eq 1',
        'manifest_size="$(stat -c \'%s\' -- "$manifest_entry")"',
        'manifest_mtime="$(stat -c \'%y\' -- "$manifest_entry")"',
        'content_digest="$(sha256sum < "$manifest_entry" | awk \'{ print $1 }\')" || exit 1',
        'manifest_mode="$(stat -c \'%a\' -- "$manifest_entry")"',
        'manifest_uid="$(stat -c \'%u\' -- "$manifest_entry")"',
        'manifest_gid="$(stat -c \'%g\' -- "$manifest_entry")"',
        'getfacl --numeric --absolute-names --omit-header --',
        'getfattr --absolute-names --dump --encoding=hex --match=- --',
        'if ! find . -xdev -print0 | LC_ALL=C sort -z |',
        'done; then exit 1 fi ) > "$manifest_output"; then',
        'test -s "$manifest_output" || return 1',
        '[[ "$content_digest" =~ ^[0-9a-f]{64}$ ]] || exit 1',
        '[[ "$acl_digest" =~ ^[0-9a-f]{64}$ ]] || exit 1',
        '[[ "$xattr_digest" =~ ^[0-9a-f]{64}$ ]] || exit 1',
        "printf '%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0'",
        "'regular file:1:600:0:0'",
        "'format|grafana-appdata-manifest-v1'",
        '"bundle-sha256|$restore_bundle_digest"',
        '"tree-sha256|$appdata_manifest_digest"',
        'mv --exchange --no-copy -T appdata "$app_stage"',
    )
    for fragment in required_fragments:
        require(
            fragment in block or compact_shell(fragment) in compact_block,
            f"restore exchange lost contract fragment {fragment!r}",
        )
    record_arguments = (
        '"$manifest_entry" "$manifest_type" "$manifest_mode" '
        '"$manifest_uid" "$manifest_gid" "$manifest_size" '
        '"$manifest_mtime" "$content_digest" "$acl_digest" "$xattr_digest"'
    )
    require_text(
        normalize_shell(block),
        record_arguments,
        "manifest fields are not all emitted in the canonical NUL record",
    )
    require('$app_stage/appdata-tree.manifest' not in block, "manifest moved inside app_stage")
    require('$app_stage_parent/appdata-tree.manifest' not in block, "manifest moved inside stage parent")
    stage_probe = 'write_appdata_manifest "$app_stage" "$appdata_manifest_check"'
    live_probe = 'write_appdata_manifest appdata "$appdata_manifest_check"'
    compare = 'cmp -s -- "$appdata_manifest" "$appdata_manifest_check"'
    exchange = 'mv --exchange --no-copy -T appdata "$app_stage"'
    require(block.count(stage_probe) >= 2, "restore needs initial and immediate pre-exchange stage probes")
    require(block.count(live_probe) == 1, "restore needs exactly one post-exchange live probe")
    exchange_offset = block.index(exchange)
    pre_probe_offset = block.rfind(stage_probe, 0, exchange_offset)
    require(pre_probe_offset >= 0, "restore lacks the immediate pre-exchange stage probe")
    require(
        block.rfind(stage_probe) == pre_probe_offset,
        "restore stage probe must not move behind the exchange",
    )
    pre_compare_offset = block.find(compare, pre_probe_offset)
    require(
        pre_probe_offset < pre_compare_offset < exchange_offset,
        "restore stage compare must precede the exchange",
    )
    require(
        '"$appdata_manifest_digest"' in block[pre_compare_offset:exchange_offset],
        "restore stage digest must be rechecked immediately before exchange",
    )
    live_probe_offset = block.find(live_probe, exchange_offset)
    live_compare_offset = block.find(compare, live_probe_offset)
    require(
        exchange_offset < live_probe_offset < live_compare_offset,
        "restore live compare must follow the exchange",
    )
    require(
        '"$appdata_manifest_digest"' in block[live_compare_offset:],
        "restore live digest must be rechecked after exchange",
    )
    parent_check = block.index("'directory:700:0:0'")
    first_stage_probe = block.index(stage_probe)
    require(parent_check < first_stage_probe, "root-owned stage parent must precede tree use")


def validate_restore_stage(block):
    parent_install = 'install -d -o 0 -g 0 -m 0700 -- "$app_stage_parent" "$db_stage"'
    child_install = 'install -d -o 472 -g 472 -m 0770 -- "$app_stage"'
    extraction = '"$restore_bundle/grafana-appdata.tar" -C "$app_stage"'
    require_order(
        normalize_shell(block),
        (
            parent_install,
            child_install,
            "'directory:700:0:0'",
            extraction,
        ),
        "restore stage parent must be root-owned and closed before extraction",
    )
    require_text(block, 'test ! -L "$app_stage_parent"', "stage parent symlink rejection is missing")


def validate_break_glass_matrix(block):
    required_fragments = (
        'BREAKGLASS_PEER_ALLOWLIST_FILE=',
        '"regular file:1:600:$(id -u)"',
        'allowlist_last_byte="$(tail -c 1 -- "$allowlist_file" |',
        'test "$allowlist_last_byte" = 0a',
        'delimiter_bytes="${allowed_line//[^|]/}"',
        'test "${#delimiter_bytes}" -eq 9',
        'declare -gA break_glass_allowed_result=()',
        'declare -gA break_glass_allowed_trust=()',
        'declare -gA break_glass_allowed_image=()',
        'declare -gA break_glass_allowed_namespace_image=()',
        'declare -gA break_glass_allowed_project=()',
        'declare -gA break_glass_allowed_service=()',
        'case "$allowed_network" in frontend|backend)',
        '[[ "$allowed_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]',
        '[[ "$allowed_image" =~ ^sha256:[0-9a-f]{64}$ ]]',
        'test "$allowed_namespace_name" = -',
        'test "$allowed_namespace_image" = -',
        '[[ "$allowed_namespace_image" =~ ^sha256:[0-9a-f]{64}$ ]]',
        'test "$allowed_project" = -',
        'test "$allowed_service" = -',
        'case "$allowed_result" in DENIED|REACHABLE)',
        'case "$allowed_trust" in trusted|untrusted)',
        '[ "$allowed_trust" = untrusted ]',
        'test "$allowed_result" = DENIED',
        'allowed_key="$allowed_network|$allowed_name|$allowed_scope|$allowed_namespace_name"',
        'test -z "${break_glass_allowed_result[$allowed_key]:-}"',
        'break_glass_allowed_image[$allowed_key]="$allowed_image"',
        'break_glass_allowed_namespace_image[$allowed_key]="$allowed_namespace_image"',
        'break_glass_allowed_project[$allowed_key]="$allowed_project"',
        'break_glass_allowed_service[$allowed_key]="$allowed_service"',
        '[[ "$break_glass_peer_allowlist_sha256" =~ ^[0-9a-f]{64}$ ]]',
        '--network "$listener_network"',
        '"http://$listener_ip:3000/api/health"',
        '[ "$listener_status" = 200 ]',
        "printf 'UNTESTED listener-%s %s %s status-%s\\n'",
        'return 1',
        'local untested_peer_count=0 policy_violation_count=0',
        'declare -A observed_peer_keys=()',
        'peer_inventory_file="$(mktemp /tmp/grafana-peer-inventory.XXXXXX)"',
        'if ! docker ps --all --quiet --no-trunc > "$peer_inventory_file"; then',
        'test ! -L "$peer_inventory_file"',
        'peer_inventory_metadata="$(stat -c \'%h:%a:%u\' --',
        'test "$peer_inventory_metadata" = "1:600:$(id -u)"',
        'mapfile -t docker_container_ids < "$peer_inventory_file"',
        'rm -f -- "$peer_inventory_file"',
        'test "${#docker_container_ids[@]}" -gt 0 || return 1',
        "peer_name=\"$(docker inspect --format '{{.Name}}' \"$peer_id\")\"",
        "peer_image=\"$(docker inspect --format '{{.Image}}' \"$peer_id\")\"",
        "'(. // {})[\"com.docker.compose.project\"] // \"-\"'",
        "'(. // {})[\"com.docker.compose.service\"] // \"-\"'",
        'peer_key="$breakglass_network|$peer_name|$peer_scope|$namespace_name"',
        '[ "$peer_image" != "${break_glass_allowed_image[$peer_key]}" ]',
        '[ "$peer_project" !=',
        '"${break_glass_allowed_project[$peer_key]}"',
        '[ "$peer_service" !=',
        '"${break_glass_allowed_service[$peer_key]}"',
        'probe_break_glass_listener "$breakglass_network" "$app_network_ip"',
        'peer_result=UNTESTED',
        'peer_result=REACHABLE',
        'peer_result=DENIED',
        '[ "$peer_result" = UNTESTED ]',
        'peer_detail="listener-control-failed-after-$peer_detail"',
        '[ "$peer_result" != "$peer_expected" ]',
        '[ "$peer_trust" = untrusted ]',
        '[ "$peer_result" != DENIED ]',
        'printf \'UNTESTED allowlist-entry-missing %s\\n\'',
        'test "$untested_peer_count" -eq 0',
        'test "$policy_violation_count" -eq 0',
        'declare -f load_break_glass_peer_allowlist',
        'declare -f probe_break_glass_listener',
        'declare -f probe_break_glass_peers',
        'peer_policy_ref="$(docker compose --env-file .env',
        "'.services[\"grafana-sso-policy\"].image | select(length > 0)'",
        'peer_policy_image_id="$(docker image inspect --format \'{{.Id}}\'',
        '[[ "$peer_policy_image_id" =~ ^sha256:[0-9a-f]{64}$ ]]',
        "'format|grafana-break-glass-peer-v1\\nprobe-image|%s\\nhelper-sha256|%s\\nallowlist-sha256|%s\\npolicy-image-id|%s\\n'",
        'sha256sum -c "$peer_manifest_checksum"',
        "'{{.State.Running}}:{{.State.ExitCode}}'",
        "'false:0'",
        '"${peer_cleanup_compose[@]}" rm -f',
        'test -z "$("${peer_cleanup_compose[@]}" ps --all -q',
        'probe_break_glass_peers',
    )
    for fragment in required_fragments:
        require_text(block, fragment, f"break-glass matrix lost contract fragment {fragment!r}")
    allowlist_function = extract_shell_function(block, "load_break_glass_peer_allowlist")
    require_text(
        allowlist_function,
        '"regular file:1:600:$(id -u)"',
        "peer allowlist must remain owner-only",
    )
    peer_function = extract_shell_function(block, "probe_break_glass_peers")
    require(
        'peer_key="$breakglass_network|$peer_id|' not in peer_function,
        "volatile container ID became peer allowlist identity",
    )
    require("< <(" not in peer_function, "peer inventory must check producer exit status")
    require_order(
        normalize_shell(peer_function),
        (
            'peer_inventory_file="$(mktemp /tmp/grafana-peer-inventory.XXXXXX)"',
            'if ! docker ps --all --quiet --no-trunc > "$peer_inventory_file"; then',
            'test ! -L "$peer_inventory_file" || {',
            'peer_inventory_metadata="$(stat -c \'%h:%a:%u\' -- "$peer_inventory_file")" || {',
            'test "$peer_inventory_metadata" = "1:600:$(id -u)" || {',
            'mapfile -t docker_container_ids < "$peer_inventory_file"',
            'rm -f -- "$peer_inventory_file"',
            'test "${#docker_container_ids[@]}" -gt 0 || return 1',
        ),
        "peer inventory producer and owner-only handoff",
    )
    require_order(
        normalize_shell(peer_function),
        (
            'before-matrix',
            'peer_result=UNTESTED',
            '[ "$peer_result" = UNTESTED ]',
            'after-denied-$peer_id',
            'peer_result=UNTESTED',
            '[ "$peer_trust" = untrusted ]',
            '[ "$peer_result" != DENIED ]',
            'after-matrix',
            'UNTESTED allowlist-entry-missing',
            'test "$untested_peer_count" -eq 0',
            'test "$policy_violation_count" -eq 0',
        ),
        "break-glass listener and fail-closed matrix order",
    )
    require(
        block.rfind("probe_break_glass_peers") > block.index("sha256sum -c \"$peer_manifest_checksum\""),
        "initial peer matrix must run only after its saved contract is checksummed",
    )
    require_order(
        normalize_shell(block),
        (
            "'{{.State.Running}}:{{.State.ExitCode}}'",
            "'false:0'",
            '"${peer_cleanup_compose[@]}" rm -f',
            'test -z "$("${peer_cleanup_compose[@]}" ps --all -q',
            'probe_break_glass_peers',
        ),
        "finite jobs must be attested and removed before the initial peer matrix",
    )
    policy_contract = block[
        block.index('peer_policy_ref='):
        block.index("printf 'format|grafana-break-glass-peer-v1")
    ]
    require(
        "ps --all -q grafana-sso-policy" not in policy_contract,
        "peer contract must resolve the removed policy job through configured image identity",
    )


def shell_function_section(source, function_name):
    signature = f"{function_name}() {{"
    require(source.count(signature) == 1, f"function must occur exactly once: {function_name}")
    start = source.index(signature)
    following = re.search(r"(?m)^#æ{10,}$\n# FUNCTION:", source[start + len(signature):])
    require(following is not None, f"could not delimit shell function: {function_name}")
    end = start + len(signature) + following.start()
    return source[start:end].strip() + "\n"


def validate_operation_lock_contract(block, run_script):
    begin_function = extract_shell_function(block, "begin_grafana_operation")
    verify_function = extract_shell_function(block, "verify_grafana_operation")
    finish_function = extract_shell_function(block, "finish_grafana_operation")
    run_repository = shell_function_section(run_script, "acquire_repository_lock")
    run_project = shell_function_section(run_script, "acquire_project_lock")
    require_order(
        normalize_shell(run_repository),
        (
            'local lock_mode="--shared"',
            'REPOSITORY_LOCK_IDENTITY=$(stat -Lc \'%d:%i\' -- "$SCRIPT_DIR")',
            'exec {REPOSITORY_LOCK_FD}<"$SCRIPT_DIR"',
            '"/proc/${BASHPID}/fd/${REPOSITORY_LOCK_FD}"',
            'flock "$lock_mode" --nonblock "$REPOSITORY_LOCK_FD"',
        ),
        "run.sh repository lock reference changed",
    )
    require_order(
        normalize_shell(run_project),
        (
            'bootstrap_identity=$(stat -Lc \'%d:%i\' -- "$TARGET_DIR")',
            'exec {PROJECT_BOOTSTRAP_LOCK_FD}<"$TARGET_DIR"',
            'flock --exclusive --nonblock "$PROJECT_BOOTSTRAP_LOCK_FD"',
            'PROJECT_LOCK_IDENTITY=$(stat -Lc \'%d:%i\' -- "$lock_dir")',
            'exec {PROJECT_LOCK_FD}<"$lock_dir"',
            'flock --exclusive --nonblock "$PROJECT_LOCK_FD"',
        ),
        "run.sh per-project lock reference changed",
    )
    require_order(
        normalize_shell(begin_function),
        (
            'GRAFANA_OPS_REPOSITORY_PATH="$(realpath -e -- ..)"',
            'GRAFANA_OPS_PROJECT_PATH="$(pwd -P)"',
            'GRAFANA_OPS_RUNTIME_PATH="$GRAFANA_OPS_PROJECT_PATH/.run.conf"',
            'GRAFANA_OPS_REPOSITORY_IDENTITY="$(stat -Lc \'%d:%i\' -- "$GRAFANA_OPS_REPOSITORY_PATH")"',
            'exec {GRAFANA_OPS_REPOSITORY_FD}<"$GRAFANA_OPS_REPOSITORY_PATH"',
            '"/proc/$BASHPID/fd/$GRAFANA_OPS_REPOSITORY_FD"',
            'flock --shared --nonblock "$GRAFANA_OPS_REPOSITORY_FD"',
            'GRAFANA_OPS_PROJECT_IDENTITY="$(stat -Lc \'%d:%i\' -- "$GRAFANA_OPS_PROJECT_PATH")"',
            'exec {GRAFANA_OPS_PROJECT_FD}<"$GRAFANA_OPS_PROJECT_PATH"',
            '"/proc/$BASHPID/fd/$GRAFANA_OPS_PROJECT_FD"',
            'flock --exclusive --nonblock "$GRAFANA_OPS_PROJECT_FD"',
            'GRAFANA_OPS_RUNTIME_IDENTITY="$(stat -Lc \'%d:%i\' -- "$GRAFANA_OPS_RUNTIME_PATH")"',
            'exec {GRAFANA_OPS_RUNTIME_FD}<"$GRAFANA_OPS_RUNTIME_PATH"',
            '"/proc/$BASHPID/fd/$GRAFANA_OPS_RUNTIME_FD"',
            'flock --exclusive --nonblock "$GRAFANA_OPS_RUNTIME_FD"',
            'verify_grafana_operation "$requested_workflow" "$requested_id"',
        ),
        "Grafana operation locks must match normal run.sh order and modes",
    )
    require(begin_function.count("flock --shared --nonblock") == 1, "operation needs one shared lock")
    require(begin_function.count("flock --exclusive --nonblock") == 2, "operation needs two exclusive locks")
    require(".lock" not in begin_function, "operation lock must not use a separate lock file")
    for lock_name in ("REPOSITORY", "PROJECT", "RUNTIME"):
        for fragment in (
            f'GRAFANA_OPS_{lock_name}_FD',
            f'GRAFANA_OPS_{lock_name}_IDENTITY',
            f'GRAFANA_OPS_{lock_name}_PATH',
            f'/proc/$BASHPID/fd/$GRAFANA_OPS_{lock_name}_FD',
            f'flock -n -x "$GRAFANA_OPS_{lock_name}_PATH" true',
        ):
            require_text(verify_function, fragment, f"operation verify lost {lock_name.lower()} lock proof")
    require_order(
        normalize_shell(finish_function),
        (
            'verify_grafana_operation "$expected_workflow" "$expected_id"',
            'flock -u "$GRAFANA_OPS_RUNTIME_FD"',
            'exec {GRAFANA_OPS_RUNTIME_FD}<&-',
            'flock -u "$GRAFANA_OPS_PROJECT_FD"',
            'exec {GRAFANA_OPS_PROJECT_FD}<&-',
            'flock -u "$GRAFANA_OPS_REPOSITORY_FD"',
            'exec {GRAFANA_OPS_REPOSITORY_FD}<&-',
        ),
        "Grafana operation locks must release in reverse order",
    )


def validate_secret_manifest_contract(block):
    function_source = extract_shell_function(block, "write_grafana_secret_manifest")
    normalized_function = normalize_shell(function_source)
    required_fragments = (
        'local manifest_output=$1 rendered_config secret_name secret_file',
        'secret_compose=("$@")',
        'secret_owner_path="${GRAFANA_OPS_PROJECT_PATH:-.}"',
        'expected_secret_uid="${GRAFANA_SECRET_EXPECTED_UID:-$(stat -c \'%u\' -- "$secret_owner_path")}"',
        'expected_secret_gid="${GRAFANA_SECRET_EXPECTED_GID:-$(jq -er',
        '(.value.group_add // [])[] | tostring',
        'unique | if length == 1 then .[0] else error("ambiguous secret group") end',
        "' \"$rendered_config\")}",
        '[[ "$expected_secret_uid" =~ ^[0-9]+$ ]]',
        '[[ "$expected_secret_gid" =~ ^[0-9]+$ ]]',
        'rendered_config="$(mktemp /tmp/grafana-secret-config.XXXXXX)"',
        'secret_names_file="$(mktemp /tmp/grafana-secret-names.XXXXXX)"',
        'for secret_temp_file in "$rendered_config" "$secret_names_file"; do',
        'test -f "$secret_temp_file"',
        '"1:600:$(id -u)"',
        'test ! -L "$secret_temp_file"',
        'config --format json > "$rendered_config"',
        'if ! jq -j',
        '.services | to_entries[]',
        '.key == "app"',
        '.key == "grafana-bootstrap"',
        '.key == "grafana-migrator"',
        '.key == "grafana-sso-policy"',
        '(.value.secrets // [])[]',
        'if type == "string" then . else .source end',
        'unique[] | . + "\\u0000"',
        'done < "$secret_names_file"',
        'test -s "$secret_names_file"',
        '.secrets[$secret_name].file',
        '[[ "$secret_file" == /* ]]',
        'test -f "$secret_file"',
        'test ! -L "$secret_file"',
        'test "$(stat -c \'%F:%h\' -- "$secret_file")" = \'regular file:1\'',
        'secret_mode="$(stat -c \'%a\' -- "$secret_file")"',
        'secret_uid="$(stat -c \'%u\' -- "$secret_file")"',
        'secret_gid="$(stat -c \'%g\' -- "$secret_file")"',
        'secret_size="$(stat -c \'%s\' -- "$secret_file")"',
        'case "$secret_mode" in',
        '600) ;;',
        '640) test "$secret_gid" -eq "$expected_secret_gid"',
        'test "$secret_uid" -eq "$expected_secret_uid"',
        'secret_digest="$(sha256sum < "$secret_file" | awk \'{ print $1 }\')"',
        "printf '%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0'",
        '"$secret_name" "$secret_file" "$secret_mode" "$secret_uid"',
        '"$secret_gid" "$secret_size" "$secret_digest"',
        'chmod 0600 -- "$manifest_output"',
        'test -s "$manifest_output"',
        '"regular file:1:600:$(id -u)"',
        'test ! -L "$manifest_output"',
    )
    for fragment in required_fragments:
        require(
            fragment in function_source or normalize_shell(fragment) in normalized_function,
            f"secret manifest lost contract fragment {fragment!r}",
        )
    require('cat "$secret_file"' not in function_source, "secret manifest must never print or shell-read secret values")
    require(
        'test "$secret_uid" -eq "$(id -u)"' not in normalized_function,
        "secret owner must not be coupled to the current root/operator UID",
    )
    require(
        'expected_secret_uid="${GRAFANA_SECRET_EXPECTED_UID:-$(id -u)}"' not in normalized_function,
        "secret owner fallback must come from the explicit deployment path",
    )
    require("< <(" not in function_source, "secret inventory must check every producer exit status")
    require_order(
        normalized_function,
        (
            'rendered_config="$(mktemp /tmp/grafana-secret-config.XXXXXX)"',
            'secret_names_file="$(mktemp /tmp/grafana-secret-names.XXXXXX)"',
            '"1:600:$(id -u)"',
            'if ! "${secret_compose[@]}" config --format json > "$rendered_config"; then',
            'if ! jq -j',
            '> "$secret_names_file"; then',
            'done < "$secret_names_file"',
        ),
        "secret inventory producer and owner-only handoff",
    )
    return function_source


def validate_generation_builder(document, function_name, required_fragments=()):
    function_block = bash_block_containing(document, f"{function_name}() {{")
    function_source = extract_shell_function(function_block, function_name)
    compact_source = compact_shell(function_source)
    require_bash_syntax(function_source, f"Grafana {function_name} runbook function")
    require("< <(" not in function_source, f"{function_name} uses unchecked process substitution")
    for fragment in required_fragments:
        require(
            fragment in function_source or compact_shell(fragment) in compact_source,
            f"{function_name} lost contract fragment {fragment!r}",
        )
    printf_offsets = [
        match.start()
        for match in re.finditer(r"printf 'format\|grafana-", function_source)
    ]
    require(len(printf_offsets) == 1, f"{function_name} needs one canonical format record")
    require(
        "$(" not in function_source[printf_offsets[0]:],
        f"{function_name} evaluates an unchecked producer inside its final printf",
    )
    assignment_pattern = re.compile(
        r'(?ms)^[ \t]*([A-Za-z_][A-Za-z0-9_]*)="\$\((.*?)\)"'
        r'[ \t]*(?:\\\n[ \t]*)?(\|\|[ \t]+return[ \t]+1)?'
    )
    assignments = list(assignment_pattern.finditer(function_source))
    require(assignments, f"{function_name} has no producer-bound digest assignments")
    for assignment in assignments:
        require(
            assignment.group(3) is not None,
            f"{function_name} does not propagate producer failure for {assignment.group(1)}",
        )
    for line in compact_source.split(" ; "):
        if "[[" not in line or "=~ ^[0-9a-f]{64}$ ]]" not in line:
            continue
        require(
            "|| return 1" in line,
            f"{function_name} digest validation relies on suppressed errexit",
        )
    require(
        re.search(r'> "\$[A-Za-z_][A-Za-z0-9_]*" \|\| return 1', compact_source),
        f"{function_name} does not propagate its manifest write failure",
    )
    if "config --format json" in function_source:
        require_text(
            function_source,
            "if ! ",
            f"{function_name} effective-config producer is not checked",
        )
        require(
            re.search(
                r'test -s "\$[A-Za-z_][A-Za-z0-9_]*" \|\|.{0,200}return 1',
                compact_source,
            ) is not None,
            f"{function_name} accepts an empty effective configuration",
        )
    return function_source


def validate_workflow_contract(document, spec):
    workflow = spec["workflow"]
    operation_id = spec["operation_id"]
    generation_verifier = spec["generation_verifier"]
    accepted_variable = spec["accepted_variable"]
    begin_command = f'begin_grafana_operation {workflow} "${operation_id}"'
    finish_command = f'finish_grafana_operation {workflow} "${operation_id}"'
    records = bash_block_records(document)
    begin_record = bash_block_record_containing(document, begin_command)
    finish_record = bash_block_record_containing(document, finish_command)
    begin_index = records.index(begin_record)
    finish_index = records.index(finish_record)
    require(begin_index < finish_index, f"{workflow} acceptance precedes its operation begin")
    selected_records = records[begin_index:finish_index + 1]
    for _, _, block in selected_records:
        require_bash_syntax(block, f"Grafana {workflow} operation block")
    first_block = begin_record[2]
    first_slice = first_block[first_block.index(begin_command):]
    operation_blocks = [first_slice]
    operation_blocks.extend(record[2] for record in selected_records[1:])
    operation_region = "\n".join(operation_blocks)
    require(operation_region.count(begin_command) == 1, f"{workflow} operation begin is ambiguous")
    require(operation_region.count(finish_command) == 1, f"{workflow} operation finish is ambiguous")
    require("./run.sh Grafana" not in operation_region, f"{workflow} invokes run.sh while holding operation locks")
    finish_offset = operation_region.index(finish_command)
    locked_region = operation_region[:finish_offset]
    for forbidden in (
        'flock -u "$GRAFANA_OPS_',
        'exec {GRAFANA_OPS_',
        'exec {recovery_lock_fd}<&-',
    ):
        require(forbidden not in locked_region, f"{workflow} releases an operation FD before acceptance")
    require_order(
        normalize_shell(operation_region),
        tuple(spec["mutation_sequence"]),
        f"{workflow} mutation/generation/activation sequence",
    )
    final_anchor_marker = f'<div id="{spec["final_anchor"]}"></div>'
    final_anchor_offset = document.index(final_anchor_marker)
    for prerequisite_marker in spec.get("final_prerequisite_markers", ()):
        prerequisite_offset = document.rfind(
            prerequisite_marker,
            begin_record[1],
            final_anchor_offset,
        )
        require(
            prerequisite_offset >= begin_record[1],
            f"{workflow} final acceptance precedes prerequisite {prerequisite_marker!r}",
        )
    final_block = bash_block_after_anchor(document, spec["final_anchor"])
    require(final_block == finish_record[2], f"{workflow} final acceptance anchor selects the wrong block")
    normalized_final = normalize_shell(final_block)
    require_order(
        normalized_final,
        (
            spec.get("final_generation_verifier", generation_verifier),
            finish_command,
            f"{accepted_variable}=true",
            "trap - EXIT",
        ),
        f"{workflow} must finish locks before accepting and disarming its guard",
    )
    require_text(
        final_block,
        f"{finish_command}\n{accepted_variable}=true\ntrap - EXIT",
        f"{workflow} finish must be a direct successful command immediately before acceptance",
    )
    finish_in_final = normalized_final.index(finish_command)
    for final_check in spec["final_checks"]:
        check_offset = normalized_final.find(final_check)
        require(
            0 <= check_offset < finish_in_final,
            f"{workflow} final acceptance lost pre-finish check {final_check!r}",
        )
    require(
        operation_region.count(f"{accepted_variable}=true") == 1,
        f"{workflow} may accept the app only in its final block",
    )
    guard_function = spec["guard_function"]
    require_order(
        normalize_shell(operation_region),
        (
            f"{accepted_variable}=false",
            f"trap {guard_function} EXIT",
            spec["guarded_app_start"],
            finish_command,
            f"{accepted_variable}=true",
        ),
        f"{workflow} app guard must remain armed from start through finish",
    )
    verifier_function = spec.get("final_generation_verifier", generation_verifier)
    verifier_block = bash_block_containing(document, f"{verifier_function}() {{")
    verifier_source = extract_shell_function(verifier_block, verifier_function)
    for fragment in (
        f'verify_grafana_operation {workflow} "${operation_id}"',
        "sha256sum -c",
        "write_grafana_secret_manifest",
        "cmp -s --",
    ):
        require_text(
            verifier_source,
            fragment,
            f"{workflow} generation verifier lost {fragment!r}",
        )
    require("< <(" not in verifier_source, f"{workflow} verifier must check producer exit status")
    for _, _, block in selected_records:
        normalized_block = normalize_shell(block)
        start_match = re.search(r"\bup -d .*?(?:--force-recreate )?app(?:;|$)", normalized_block)
        if start_match is None:
            continue
        verifier_offsets = [
            normalized_block.rfind(verifier, 0, start_match.start())
            for verifier in spec.get("start_verifiers", (generation_verifier,))
        ]
        require(
            max(verifier_offsets, default=-1) >= 0,
            f"{workflow} app start lacks an in-block generation recheck",
        )
    return {
        "begin_record": begin_record,
        "finish_record": finish_record,
        "operation_region": operation_region,
        "final_block": final_block,
    }


def validate_break_glass_workflow(document, workflow_result):
    activation_block = bash_block_after_anchor(document, "grafana-break-glass-activation")
    operation_region = workflow_result["operation_region"]
    compact_activation = compact_shell(activation_block)
    compact_operation = compact_shell(operation_region)
    override_payload = (
        "printf '%s\\n' 'services:' '  app:' '    environment:' "
        "'      GRAFANA_DISABLE_LOGIN_FORM: \"false\"' "
        "'      GRAFANA_OAUTH_AUTO_LOGIN: \"false\"' > "
        '"$break_glass_form_override"'
    )
    for fragment in (
        'test "$(grep -Fxc \'GRAFANA_DISABLE_LOGIN_FORM=true\' app.env)" -eq 1',
        'install -m 0600 /dev/null "$break_glass_form_override"',
        '"regular file:1:600:$(id -u)"',
        '(.services.app.environment | (keys | sort) == [',
        '"GRAFANA_DISABLE_LOGIN_FORM", "GRAFANA_OAUTH_AUTO_LOGIN"',
        '.services.app.environment.GRAFANA_DISABLE_LOGIN_FORM == "false"',
        '.services.app.environment.GRAFANA_OAUTH_AUTO_LOGIN == "false"',
        'break_glass_compose=("${break_glass_base_compose[@]}" -f "$break_glass_form_override")',
        '$form | .services.app.environment.GRAFANA_DISABLE_LOGIN_FORM = $base.services.app.environment.GRAFANA_DISABLE_LOGIN_FORM',
        '.services.app.environment.GRAFANA_OAUTH_AUTO_LOGIN = $base.services.app.environment.GRAFANA_OAUTH_AUTO_LOGIN',
        ') == $base)',
    ):
        require(
            fragment in activation_block or compact_shell(fragment) in compact_activation,
            f"break-glass strict override lost {fragment!r}",
        )
    require(
        compact_shell(override_payload) in compact_activation,
        "break-glass form override is not the exact two-key owner-only document",
    )
    form_assignment = 'break_glass_compose=("${break_glass_base_compose[@]}" -f "$break_glass_form_override")'
    form_start = compact_operation.index(form_assignment)
    override_removal = 'rm -- "$break_glass_form_override"'
    form_end = compact_operation.index(override_removal, form_start)
    form_region = compact_operation[form_start:form_end]
    require(
        re.search(
            r'"\$\{break_glass_base_compose\[@\]\}" (?:stop|rm|up|run|exec)',
            form_region,
        ) is None,
        "break-glass form phase mutates through the base Compose command",
    )
    require(
        "./run.sh Grafana" not in form_region,
        "break-glass form phase reruns run.sh under held directory locks",
    )
    require_order(
        compact_operation,
        (
            'verify_break_glass_final_generation',
            '"${break_glass_compose[@]}" stop app',
            'test -z "$("${break_glass_compose[@]}" ps --status running -q app)"',
            override_removal,
            'test ! -e "$break_glass_form_override"',
            'break_glass_compose=("${break_glass_base_compose[@]}")',
            '.services.app.environment.GRAFANA_DISABLE_LOGIN_FORM == "true"',
            'write_break_glass_closed_generation "$break_glass_closed_generation"',
            'verify_break_glass_closed_generation',
        ),
        "break-glass closed-form transition",
    )
    closed_region = compact_operation[form_end:]
    require(
        '-f "$break_glass_form_override"' not in closed_region,
        "break-glass closed phase still composes the form override",
    )
    require_order(
        compact_operation,
        (
            'mv -- "$final_admin_stage" "$final_admin_secret"',
            'write_grafana_secret_manifest "$break_glass_final_secret_manifest" "${break_glass_compose[@]}"',
            'write_break_glass_final_generation "$break_glass_final_generation"',
            'verify_break_glass_final_generation',
            'rm -- "$marker"',
            'verify_break_glass_final_generation',
            '"${break_glass_compose[@]}" stop app',
            override_removal,
        ),
        "break-glass post-rotation final secret contract",
    )
    force_marker = "--force-recreate app"
    force_offsets = [match.start() for match in re.finditer(force_marker, compact_operation)]
    require(len(force_offsets) == 2, "break-glass must have exactly form and closed app recreates")
    for force_index, force_offset in enumerate(force_offsets, start=1):
        next_force = force_offsets[force_index] if force_index < len(force_offsets) else len(compact_operation)
        probe_offset = compact_operation.find("probe_break_glass_peers", force_offset, next_force)
        require(probe_offset >= 0, f"break-glass recreate {force_index} lacks repeated peer matrix")
        reload_region = compact_operation[force_offset:probe_offset]
        require_order(
            reload_region,
            (
                "'false:0'",
                'sha256sum -c "$break_glass_finite_evidence_checksum"',
                '"${break_glass_compose[@]}" rm -f',
                "test -z",
            ),
            f"break-glass recreate {force_index} finite evidence and cleanup before matrix",
        )
        for reload_fragment in (
            'sha256sum -c "$peer_manifest_checksum"',
            '. "$peer_helper"',
            'load_break_glass_peer_allowlist "$peer_allowlist"',
        ):
            require_text(
                reload_region,
                reload_fragment,
                f"break-glass recreate {force_index} peer contract is not reloaded",
            )
    final_block = workflow_result["final_block"]
    require_order(
        compact_shell(final_block),
        (
            'sha256sum -c "$peer_manifest_checksum"',
            '. "$peer_helper"',
            'load_break_glass_peer_allowlist "$peer_allowlist"',
            'probe_break_glass_peers',
            'verify_break_glass_closed_generation',
            'finish_grafana_operation break-glass "$break_glass_id"',
        ),
        "break-glass final peer fence",
    )


def validate_restore_workflow(document, workflow_result):
    operation_region = workflow_result["operation_region"]
    compact_operation = compact_shell(operation_region)
    stage_probe = 'write_appdata_manifest "$app_stage" "$appdata_manifest_check"'
    live_probe = 'write_appdata_manifest appdata "$appdata_manifest_check"'
    require(
        compact_operation.count(stage_probe) == 2,
        "restore operation must probe staged appdata only initially and immediately pre-exchange",
    )
    require(
        compact_operation.count(live_probe) == 1,
        "restore operation must probe live appdata exactly once immediately post-exchange",
    )
    exchange = 'mv --exchange --no-copy -T appdata "$app_stage"'
    exchange_offset = compact_operation.index(exchange)
    initial_probe = compact_operation.index(stage_probe)
    pre_probe = compact_operation.rindex(stage_probe, 0, exchange_offset)
    live_probe_offset = compact_operation.index(live_probe, exchange_offset)
    require(initial_probe < pre_probe < exchange_offset < live_probe_offset, "restore appdata probes lost exchange order")
    require(
        "write_appdata_manifest" not in compact_operation[live_probe_offset + len(live_probe):],
        "restore recomputes mutable live appdata after its post-exchange proof",
    )
    require(
        "verify_restore_generation appdata" not in compact_operation,
        "restore activation rehashes mutable live appdata",
    )
    activation_verifier_block = bash_block_containing(
        document,
        "verify_restore_activation_generation() {",
    )
    activation_verifier = extract_shell_function(
        activation_verifier_block,
        "verify_restore_activation_generation",
    )
    require(
        "write_appdata_manifest" not in activation_verifier,
        "restore activation verifier binds mutable full live appdata",
    )
    for sentinel_fragment in (
        'appdata/.restore-generation-$restore_id',
        'appdata/.restore-bundle-$restore_id.sha256',
        'write_grafana_secret_manifest "$secret_check" "${restore_compose[@]}"',
        'write_restore_activation_generation "$activation_check"',
    ):
        require_text(
            activation_verifier,
            sentinel_fragment,
            f"restore activation lost immutable sentinel/config proof {sentinel_fragment!r}",
        )
    require(
        re.search(r"\bcmp\b[^\n]*<\(", operation_region) is None,
        "restore compares unchecked process substitutions",
    )
    require("< <(" not in activation_verifier, "restore activation uses unchecked process substitution")
    require_order(
        compact_operation,
        (
            'recovery_lock_fd="$GRAFANA_OPS_RUNTIME_FD"',
            exchange,
            live_probe,
            'recovery_form_override="${GRAFANA_RECOVERY_FORM_OVERRIDE:-}"',
            'restore_override_binding="$recovery_form_override_sha256"',
            'effective-config-sha256|%s',
            'verify_restore_activation_generation',
            'rm -- "$recovery_form_override"',
            'unset GRAFANA_RECOVERY_FORM_OVERRIDE',
            'test "$restore_activation_phase" = closed-form',
            'finish_grafana_operation restore "$restore_id"',
        ),
        "restore same-lock recovery-form and closed rerun",
    )
    require(
        'exec {recovery_lock_fd}<&-' not in operation_region,
        "restore closes the inherited runtime lock descriptor during form cleanup",
    )
    require(
        operation_region.count('begin_grafana_operation restore "$restore_id"') == 1,
        "restore opens a new operation shell instead of inheriting the three locks",
    )
    final_block = workflow_result["final_block"]
    require("write_appdata_manifest" not in final_block, "restore final acceptance hashes mutable appdata")
    require("verify_restore_generation appdata" not in final_block, "restore final acceptance hashes mutable appdata")


def require_rejected_mutation(block, mutate, validator, name):
    mutated = mutate(block)
    require(mutated != block, f"negative mutation did not change the block: {name}")
    try:
        validator(mutated)
    except ContractError:
        return
    raise ContractError(f"negative mutation was accepted: {name}")


def replace_once(source, old, new):
    require(source.count(old) >= 1, f"mutation source is missing: {old!r}")
    return source.replace(old, new, 1)


def replace_last_once(source, old, new):
    position = source.rfind(old)
    require(position >= 0, f"mutation source is missing: {old!r}")
    return source[:position] + new + source[position + len(old):]


def mutate_anchored_bash_block(document, anchor, transform):
    marker = f'<div id="{anchor}"></div>'
    marker_offset = document.index(marker) + len(marker)
    fence = re.search(r"(?m)^[ \t]*```bash[ \t]*$\n", document[marker_offset:])
    require(fence is not None, f"mutation anchor has no Bash fence: {anchor}")
    block_start = marker_offset + fence.end()
    closing = re.search(r"(?m)^[ \t]*```[ \t]*$", document[block_start:])
    require(closing is not None, f"mutation anchor has no closing fence: {anchor}")
    block_end = block_start + closing.start()
    original = document[block_start:block_end]
    mutated = transform(original)
    require(mutated != original, f"anchored mutation did not change {anchor}")
    return document[:block_start] + mutated + document[block_end:]


def mutate_document_function(document, function_name, transform):
    lines = document.splitlines(keepends=True)
    signature = f"{function_name}() {{"
    starts = [index for index, line in enumerate(lines) if line.strip() == signature]
    require(len(starts) == 1, f"mutation function must occur once: {function_name}")
    start = starts[0]
    parse_lines = [line.rstrip("\r\n") for line in lines]
    end = find_shell_function_end(parse_lines, start, function_name)
    original = "".join(lines[start:end + 1])
    mutated = transform(original)
    require(mutated != original, f"function mutation did not change {function_name}")
    return "".join(lines[:start]) + mutated + "".join(lines[end + 1:])


def inject_inline_generation_producer(function_source):
    printf_offset = function_source.index("printf 'format|grafana-")
    argument_offset = function_source.find('"$', printf_offset)
    require(argument_offset >= 0, "generation printf has no variable arguments")
    return (
        function_source[:argument_offset]
        + '"$(false)" '
        + function_source[argument_offset:]
    )


def move_final_anchor_before_marker(document, anchor, prerequisite_marker):
    anchor_marker = f'<div id="{anchor}"></div>'
    anchor_offset = document.index(anchor_marker)
    without_anchor = document[:anchor_offset] + document[anchor_offset + len(anchor_marker):]
    prerequisite_offset = without_anchor.index(prerequisite_marker)
    return (
        without_anchor[:prerequisite_offset]
        + anchor_marker
        + "\n\n"
        + without_anchor[prerequisite_offset:]
    )


def swap_project_and_runtime_lock_segments(source):
    project_marker = 'GRAFANA_OPS_PROJECT_IDENTITY="$(stat -Lc'
    runtime_marker = 'GRAFANA_OPS_RUNTIME_IDENTITY="$(stat -Lc'
    workflow_marker = 'GRAFANA_OPS_WORKFLOW=$requested_workflow'
    project_start = source.index(project_marker)
    runtime_start = source.index(runtime_marker, project_start)
    workflow_start = source.index(workflow_marker, runtime_start)
    return (
        source[:project_start]
        + source[runtime_start:workflow_start]
        + source[project_start:runtime_start]
        + source[workflow_start:]
    )


def move_exchange_before_last_stage_probe(source):
    exchange = 'mv --exchange --no-copy -T appdata "$app_stage"'
    stage_probe = 'write_appdata_manifest "$app_stage" "$appdata_manifest_check"'
    without_exchange = source.replace(exchange, "", 1)
    insertion = without_exchange.rfind(stage_probe)
    require(insertion >= 0, "could not build exchange-order mutation")
    return without_exchange[:insertion] + exchange + "\n" + without_exchange[insertion:]


def run_manifest_fixture(function_source, fixture_root):
    harness = """
set -euo pipefail
umask 077
""" + function_source + r'''
fixture_root=$1
tree="$fixture_root/tree"
baseline="$fixture_root/baseline.manifest"
candidate="$fixture_root/candidate.manifest"
acl_backup="$fixture_root/acl.backup"
mkdir -p -- "$tree/nested"
printf 'alpha\n' > "$tree/nested/data"
printf 'newline-name\n' > "$tree/line
break"
chmod 0750 "$tree/nested"
chmod 0640 "$tree/nested/data"
setfattr -n user.grafana_contract -v alpha -- "$tree/nested/data"
getfacl --absolute-names -- "$tree/nested/data" > "$acl_backup"
file_mtime="$(stat -c '%y' -- "$tree/nested/data")"
tree_mtime="$(stat -c '%y' -- "$tree")"
write_appdata_manifest "$tree" "$baseline"
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"

printf 'beta\n' > "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
! cmp -s -- "$baseline" "$candidate"
printf 'alpha\n' > "$tree/nested/data"
touch -d "$file_mtime" -- "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"

touch -d '2001-02-03 04:05:06 UTC' -- "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
! cmp -s -- "$baseline" "$candidate"
touch -d "$file_mtime" -- "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"

chmod 0600 "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
! cmp -s -- "$baseline" "$candidate"
chmod 0640 "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"

setfattr -n user.grafana_contract -v beta -- "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
! cmp -s -- "$baseline" "$candidate"
setfattr -n user.grafana_contract -v alpha -- "$tree/nested/data"
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"

if setfacl -m u:65534:r-- -- "$tree/nested/data" 2>/dev/null; then
  test "$(stat -c '%a' -- "$tree/nested/data")" = 640
  write_appdata_manifest "$tree" "$candidate"
  ! cmp -s -- "$baseline" "$candidate"
  setfacl --physical --restore="$acl_backup"
else
  setfacl -m u::r-- -- "$tree/nested/data"
  write_appdata_manifest "$tree" "$candidate"
  ! cmp -s -- "$baseline" "$candidate"
  setfacl --physical --restore="$acl_backup"
fi
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"

require_manifest_rejection() {
  if write_appdata_manifest "$tree" "$candidate"; then
    return 1
  fi
}

(
  find() {
    printf '.\0'
    return 23
  }
  if write_appdata_manifest "$tree" "$candidate"; then
    exit 1
  fi
)
(
  find() {
    return 0
  }
  if write_appdata_manifest "$tree" "$candidate"; then
    exit 1
  fi
)
(
  getfacl() {
    command getfacl "$@"
    return 23
  }
  if write_appdata_manifest "$tree" "$candidate"; then
    exit 1
  fi
)
(
  getfattr() {
    command getfattr "$@"
    return 23
  }
  if write_appdata_manifest "$tree" "$candidate"; then
    exit 1
  fi
)

ln -s nested/data "$tree/symlink"
require_manifest_rejection
rm -- "$tree/symlink"
touch -d "$tree_mtime" -- "$tree"
ln "$tree/nested/data" "$tree/hardlink"
require_manifest_rejection
rm -- "$tree/hardlink"
touch -d "$tree_mtime" -- "$tree"
mkfifo "$tree/fifo"
require_manifest_rejection
rm -- "$tree/fifo"
touch -d "$tree_mtime" -- "$tree"
write_appdata_manifest "$tree" "$candidate"
cmp -s -- "$baseline" "$candidate"
'''
    result = subprocess.run(
        ["bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-s", "--", str(fixture_root)],
        input=harness,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        result.returncode == 0,
        f"documented appdata manifest failed its isolated fixture: {result.stderr.strip()}",
    )


def run_peer_allowlist_fixture(function_source, fixture_root):
    harness = """
set -euo pipefail
umask 077
""" + function_source + r'''
fixture_root=$1
peer_root="$fixture_root/peer"
allowlist="$peer_root/allowlist"
allowlist_target="$peer_root/allowlist-target"
image_a=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
image_b=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
image_c=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
mkdir -p -- "$peer_root"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|REACHABLE|trusted\nbackend|database|%s|direct-endpoint|-|-|grafana|postgresql|DENIED|untrusted\nfrontend|sidecar|%s|shared-namespace|gateway|%s|-|-|DENIED|untrusted\n' \
  "$image_a" "$image_b" "$image_c" "$image_a" > "$allowlist"
chmod 0600 -- "$allowlist"
load_break_glass_peer_allowlist "$allowlist"
test "${#break_glass_allowed_result[@]}" -eq 3
test "${break_glass_allowed_result[frontend|gateway|direct-endpoint|-]}" = REACHABLE
test "${break_glass_allowed_trust[frontend|gateway|direct-endpoint|-]}" = trusted
test "${break_glass_allowed_image[frontend|gateway|direct-endpoint|-]}" = "$image_a"
test "${break_glass_allowed_project[frontend|gateway|direct-endpoint|-]}" = grafana
test "${break_glass_allowed_service[frontend|gateway|direct-endpoint|-]}" = gateway
test "${break_glass_allowed_result[backend|database|direct-endpoint|-]}" = DENIED
test "${break_glass_allowed_trust[backend|database|direct-endpoint|-]}" = untrusted
test "${break_glass_allowed_image[backend|database|direct-endpoint|-]}" = "$image_b"
test "${break_glass_allowed_result[frontend|sidecar|shared-namespace|gateway]}" = DENIED
test "${break_glass_allowed_namespace_image[frontend|sidecar|shared-namespace|gateway]}" = "$image_a"
[[ "$break_glass_peer_allowlist_sha256" =~ ^[0-9a-f]{64}$ ]]

require_load_rejection() {
  set +e
  (
    set -e
    load_break_glass_peer_allowlist "$1"
  )
  rejection_status=$?
  set -e
  test "$rejection_status" -ne 0
}

chmod 0644 -- "$allowlist"
require_load_rejection "$allowlist"
chmod 0600 -- "$allowlist"
printf 'backend|database|%s|direct-endpoint|-|-|grafana|postgresql|REACHABLE|untrusted\n' "$image_b" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|REACHABLE|trusted\nfrontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|DENIED|trusted\n' \
  "$image_a" "$image_a" > "$allowlist"
require_load_rejection "$allowlist"
printf 'outside|database|%s|direct-endpoint|-|-|grafana|postgresql|DENIED|untrusted\n' "$image_b" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|-|DENIED|trusted\n' "$image_a" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|sidecar|%s|shared-namespace|gateway|-|-|-|DENIED|untrusted\n' "$image_c" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|DENIED|trusted' "$image_a" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|DENIED|trusted|\n' "$image_a" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|DENIED|trusted|extra\n' "$image_a" > "$allowlist"
require_load_rejection "$allowlist"
printf 'frontend|gateway|%s|direct-endpoint|-|-|grafana|gateway|DENIED|trusted\n' "$image_a" > "$allowlist_target"
chmod 0600 -- "$allowlist_target"
rm -- "$allowlist"
ln -s "$allowlist_target" "$allowlist"
require_load_rejection "$allowlist"
'''
    result = subprocess.run(
        ["bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-s", "--", str(fixture_root)],
        input=harness,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        result.returncode == 0,
        f"documented peer allowlist failed its isolated fixture: {result.stderr.strip()}",
    )


def run_peer_inventory_failure_fixture(function_source, fixture_root):
    harness = """
set -euo pipefail
umask 077
""" + function_source + r'''
fixture_root=$1
app_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BREAKGLASS_PROBE_IMAGE=probe.example.invalid/curl@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
declare -A break_glass_allowed_result=()
declare -A break_glass_allowed_trust=()
declare -A break_glass_allowed_image=()
declare -A break_glass_allowed_namespace_image=()
declare -A break_glass_allowed_project=()
declare -A break_glass_allowed_service=()
inventory_mode=partial
docker() {
  case "$1" in
    compose)
      printf '%s\n' "$app_id"
      ;;
    inspect)
      case "$*" in
        *"{{.Id}}"*) printf '%s\n' "$app_id" ;;
        *"{{json .NetworkSettings.Networks}}"*)
          printf '%s\n' \
            '{"frontend":{"IPAddress":"172.30.0.2"},"backend":{"IPAddress":"172.31.0.2"}}'
          ;;
        *) return 97 ;;
      esac
      ;;
    ps)
      if [ "$inventory_mode" = partial ]; then
        printf '%s\n' "$app_id"
        return 23
      fi
      return 0
      ;;
    network)
      return 0
      ;;
    run)
      printf '200'
      ;;
    *) return 98 ;;
  esac
}
if probe_break_glass_peers; then
  exit 1
fi
inventory_mode=empty
if probe_break_glass_peers; then
  exit 1
fi
'''
    result = subprocess.run(
        ["bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-s", "--", str(fixture_root)],
        input=harness,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        result.returncode == 0,
        f"documented peer inventory accepted partial producer output: {result.stderr.strip()}",
    )


def run_operation_lock_fixture(function_source, fixture_root):
    harness = """
set -euo pipefail
umask 077
""" + function_source + r'''
fixture_root=$1
repository_root="$fixture_root/lock-repository"
project_root="$repository_root/Grafana"
mkdir -p -- "$project_root/.run.conf"
cd "$project_root"
begin_grafana_operation update 20260821T120000Z
verify_grafana_operation update 20260821T120000Z
! flock -n -x "$repository_root" true
flock -n -s "$repository_root" true
! flock -n -x "$project_root" true
! flock -n -x "$project_root/.run.conf" true
finish_grafana_operation update 20260821T120000Z
flock -n -x "$repository_root" true
flock -n -x "$project_root" true
flock -n -x "$project_root/.run.conf" true
'''
    result = subprocess.run(
        ["bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-s", "--", str(fixture_root)],
        input=harness,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        result.returncode == 0,
        f"documented operation locks failed their isolated fixture: {result.stderr.strip()}",
    )


def run_secret_manifest_fixture(function_source, fixture_root):
    harness = """
set -euo pipefail
umask 077
""" + function_source + r'''
fixture_root=$1
secret_root="$fixture_root/secrets"
baseline="$fixture_root/secrets-baseline.manifest"
candidate="$fixture_root/secrets-candidate.manifest"
mkdir -p -- "$secret_root"
for secret_name in POSTGRES_PASSWORD GRAFANA_SECRET_KEY \
  GRAFANA_ADMIN_PASSWORD GRAFANA_OIDC_CLIENT_ID \
  GRAFANA_OIDC_CLIENT_SECRET MAILER_SMTP_PASSWORD; do
  printf '%s-value\n' "$secret_name" > "$secret_root/$secret_name"
  chmod 0640 -- "$secret_root/$secret_name"
done
mv -- "$secret_root/MAILER_SMTP_PASSWORD" \
  "$secret_root/MAILER_SMTP_PASSWORD"$'\nmaterial'
emit_secret_config() {
  test "$#" -eq 3
  test "$1" = config
  test "$2" = --format
  test "$3" = json
  jq -n --arg root "$secret_root" --argjson secret_gid "$(id -g)" '
    {
      services: {
        app: {secrets: [
          "POSTGRES_PASSWORD",
          {source: "GRAFANA_SECRET_KEY"},
          "GRAFANA_OIDC_CLIENT_ID",
          "GRAFANA_OIDC_CLIENT_SECRET",
          "MAILER_SMTP_PASSWORD"
        ]},
        "grafana-bootstrap": {group_add: [$secret_gid], secrets: [
          "POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY",
          "GRAFANA_ADMIN_PASSWORD"
        ]},
        "grafana-migrator": {group_add: [$secret_gid], secrets: [
          "POSTGRES_PASSWORD", "GRAFANA_SECRET_KEY"
        ]},
        "grafana-sso-policy": {
          group_add: [$secret_gid], secrets: ["POSTGRES_PASSWORD"]
        }
      },
      secrets: {
        POSTGRES_PASSWORD: {file: ($root + "/POSTGRES_PASSWORD")},
        GRAFANA_SECRET_KEY: {file: ($root + "/GRAFANA_SECRET_KEY")},
        GRAFANA_ADMIN_PASSWORD: {file: ($root + "/GRAFANA_ADMIN_PASSWORD")},
        GRAFANA_OIDC_CLIENT_ID: {file: ($root + "/GRAFANA_OIDC_CLIENT_ID")},
        GRAFANA_OIDC_CLIENT_SECRET: {file: ($root + "/GRAFANA_OIDC_CLIENT_SECRET")},
        MAILER_SMTP_PASSWORD: {file: ($root + "/MAILER_SMTP_PASSWORD\nmaterial")}
      }
    }
  '
}
emit_secret_config_without_smtp() {
  emit_secret_config "$@" |
    jq 'del(.services.app.secrets[] | select(. == "MAILER_SMTP_PASSWORD"))'
}
emit_partial_secret_config() {
  emit_secret_config "$@"
  return 23
}
emit_empty_secret_config() {
  test "$#" -eq 3
  return 0
}
export GRAFANA_SECRET_EXPECTED_UID="$(id -u)"
export GRAFANA_SECRET_EXPECTED_GID="$(id -g)"
write_grafana_secret_manifest "$baseline" emit_secret_config
write_grafana_secret_manifest "$candidate" emit_secret_config
cmp -s -- "$baseline" "$candidate"
test "$(stat -c '%F:%h:%a:%u' -- "$baseline")" = \
  "regular file:1:600:$(id -u)"
mapfile -d '' -t recorded_secret_fields < "$baseline"
test "${#recorded_secret_fields[@]}" -eq 42
recorded_secret_names=()
for ((field_index = 0; field_index < 42; field_index += 7)); do
  recorded_secret_names+=("${recorded_secret_fields[$field_index]}")
done
test "${#recorded_secret_names[@]}" -eq 6
for secret_name in POSTGRES_PASSWORD GRAFANA_SECRET_KEY \
  GRAFANA_ADMIN_PASSWORD GRAFANA_OIDC_CLIENT_ID \
  GRAFANA_OIDC_CLIENT_SECRET MAILER_SMTP_PASSWORD; do
  printf '%s\n' "${recorded_secret_names[@]}" | grep -Fx "$secret_name"
  ! grep -aF -- "$secret_name-value" "$baseline"
done

rm -- "$candidate"
if write_grafana_secret_manifest "$candidate" emit_partial_secret_config; then
  exit 1
fi
test ! -e "$candidate"
if write_grafana_secret_manifest "$candidate" emit_empty_secret_config; then
  exit 1
fi
test ! -e "$candidate"

(
  jq() {
    if [ "${1:-}" = -j ]; then
      printf 'POSTGRES_PASSWORD\0'
      return 23
    fi
    command jq "$@"
  }
  if write_grafana_secret_manifest "$candidate" emit_secret_config; then
    exit 1
  fi
)
test ! -e "$candidate"
(
  jq() {
    if [ "${1:-}" = -j ]; then
      return 0
    fi
    command jq "$@"
  }
  if write_grafana_secret_manifest "$candidate" emit_secret_config; then
    exit 1
  fi
)
test ! -e "$candidate"

GRAFANA_SECRET_EXPECTED_UID=$((GRAFANA_SECRET_EXPECTED_UID + 1))
export GRAFANA_SECRET_EXPECTED_UID
if write_grafana_secret_manifest "$candidate" emit_secret_config; then
  exit 1
fi
GRAFANA_SECRET_EXPECTED_UID="$(id -u)"
export GRAFANA_SECRET_EXPECTED_UID

GRAFANA_SECRET_EXPECTED_GID=$((GRAFANA_SECRET_EXPECTED_GID + 1))
export GRAFANA_SECRET_EXPECTED_GID
if write_grafana_secret_manifest "$candidate" emit_secret_config; then
  exit 1
fi
GRAFANA_SECRET_EXPECTED_GID="$(id -g)"
export GRAFANA_SECRET_EXPECTED_GID

original_mtime="$(stat -c '%y' -- "$secret_root/GRAFANA_SECRET_KEY")"
printf 'GRAFANA_SECRET_KEZ-value\n' > "$secret_root/GRAFANA_SECRET_KEY"
touch -d "$original_mtime" -- "$secret_root/GRAFANA_SECRET_KEY"
write_grafana_secret_manifest "$candidate" emit_secret_config
! cmp -s -- "$baseline" "$candidate"
printf 'GRAFANA_SECRET_KEY-value\n' > "$secret_root/GRAFANA_SECRET_KEY"
touch -d "$original_mtime" -- "$secret_root/GRAFANA_SECRET_KEY"
write_grafana_secret_manifest "$candidate" emit_secret_config
cmp -s -- "$baseline" "$candidate"

chmod 0600 -- "$secret_root/GRAFANA_OIDC_CLIENT_ID"
write_grafana_secret_manifest "$candidate" emit_secret_config
! cmp -s -- "$baseline" "$candidate"
chmod 0640 -- "$secret_root/GRAFANA_OIDC_CLIENT_ID"
write_grafana_secret_manifest "$candidate" emit_secret_config
cmp -s -- "$baseline" "$candidate"

write_grafana_secret_manifest "$candidate" emit_secret_config_without_smtp
! cmp -s -- "$baseline" "$candidate"
mapfile -d '' -t recorded_secret_fields < "$candidate"
test "${#recorded_secret_fields[@]}" -eq 35

require_secret_manifest_rejection() {
  if write_grafana_secret_manifest "$candidate" emit_secret_config; then
    return 1
  fi
}
mv -- "$secret_root/GRAFANA_OIDC_CLIENT_SECRET" \
  "$secret_root/GRAFANA_OIDC_CLIENT_SECRET.real"
ln -s GRAFANA_OIDC_CLIENT_SECRET.real \
  "$secret_root/GRAFANA_OIDC_CLIENT_SECRET"
require_secret_manifest_rejection
rm -- "$secret_root/GRAFANA_OIDC_CLIENT_SECRET"
mv -- "$secret_root/GRAFANA_OIDC_CLIENT_SECRET.real" \
  "$secret_root/GRAFANA_OIDC_CLIENT_SECRET"
ln "$secret_root/POSTGRES_PASSWORD" "$secret_root/POSTGRES_PASSWORD.link"
require_secret_manifest_rejection
rm -- "$secret_root/POSTGRES_PASSWORD.link"
'''
    result = subprocess.run(
        ["bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-s", "--", str(fixture_root)],
        input=harness,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        result.returncode == 0,
        f"documented secret manifest failed its isolated fixture: {result.stderr.strip()}",
    )


def run_generation_producer_fixture(function_source, fixture_root):
    harness = """
set -euo pipefail
umask 077
""" + function_source + r'''
fixture_root=$1
generation_root="$fixture_root/generation-producer"
mkdir -p -- "$generation_root"
cd "$generation_root"
printf 'app-env\n' > app.env
printf 'env\n' > .env
printf 'compose\n' > docker-compose.main.yaml
printf 'images\n' > images.manifest
printf 'peers\n' > peers.manifest
break_glass_manifest="$generation_root/images.manifest"
peer_manifest="$generation_root/peers.manifest"
break_glass_id=20260821T120000Z
break_glass_final_generation_digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
break_glass_final_secret_digest=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
break_glass_app_image_id=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
break_glass_policy_image_id=sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
producer_mode=valid
emit_effective_config() {
  test "$#" -eq 3
  test "$1" = config
  test "$2" = --format
  test "$3" = json
  case "$producer_mode" in
    valid|partial-jq) printf '%s\n' '{"services":{"app":{"environment":{}}}}' ;;
    partial-compose)
      printf '%s\n' '{"services":'
      return 23
      ;;
    empty-compose) return 0 ;;
    *) return 97 ;;
  esac
}
jq() {
  if [ "$producer_mode" = partial-jq ]; then
    printf '%s\n' '{}'
    return 23
  fi
  command jq "$@"
}
break_glass_compose=(emit_effective_config)
closed_output="$generation_root/closed.manifest"
if ! write_break_glass_closed_generation "$closed_output"; then
  exit 1
fi
test -s "$closed_output"
for producer_mode in partial-compose empty-compose partial-jq; do
  rm -f -- "$closed_output"
  if write_break_glass_closed_generation "$closed_output"; then
    exit 1
  fi
  test ! -e "$closed_output"
done
producer_mode=valid
mv -- app.env app.env.saved
if write_break_glass_closed_generation "$closed_output"; then
  exit 1
fi
test ! -e "$closed_output"
mv -- app.env.saved app.env
'''
    result = subprocess.run(
        ["bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-s", "--", str(fixture_root)],
        input=harness,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    require(
        result.returncode == 0,
        f"documented generation builder accepted partial or empty producer output: {result.stderr.strip()}",
    )


readme_path = Path(sys.argv[1])
run_script_path = Path(sys.argv[2])
fixture_root = Path(sys.argv[3])
require(readme_path.is_file() and not readme_path.is_symlink(), "Grafana README must be a regular file")
require(run_script_path.is_file() and not run_script_path.is_symlink(), "run.sh must be a regular file")
document = readme_path.read_text(encoding="utf-8")
run_script = run_script_path.read_text(encoding="utf-8")
validate_function_extractor_fixture()
operation_helper_block = bash_block_containing(document, "begin_grafana_operation() {")
restore_stage_block = bash_block_containing(
    document,
    'install -d -o 0 -g 0 -m 0700 -- "$app_stage_parent" "$db_stage"',
)
restore_block = bash_block_after_anchor(document, "grafana-restore-exchange-activation")
peer_matrix_block = bash_block_after_anchor(document, "grafana-break-glass-peer-matrix")
require_bash_syntax(restore_stage_block, "Grafana restore staging runbook")
require_bash_syntax(restore_block, "Grafana restore exchange runbook")
require_bash_syntax(peer_matrix_block, "Grafana break-glass peer-matrix runbook")
require_bash_syntax(operation_helper_block, "Grafana operation-lock helper")
validate_operation_lock_contract(operation_helper_block, run_script)
secret_manifest_function = validate_secret_manifest_contract(operation_helper_block)
validate_restore_stage(restore_stage_block)
validate_restore_exchange(restore_block)
validate_break_glass_matrix(peer_matrix_block)
for generation_function in (
    "write_adoption_activation_manifest",
    "write_sso_generation_manifest",
    "write_break_glass_intent",
    "write_break_glass_generation",
    "write_break_glass_final_generation",
    "write_break_glass_closed_generation",
    "write_restore_generation_manifest",
    "write_restore_activation_generation",
    "write_update_generation",
):
    validate_generation_builder(document, generation_function)

workflow_specs = (
    {
        "workflow": "adoption",
        "operation_id": "adoption_id",
        "generation_verifier": "verify_adoption_activation_generation",
        "accepted_variable": "adoption_app_accepted",
        "guard_function": "stop_unaccepted_adoption_app",
        "guarded_app_start": "up -d --wait --wait-timeout 180",
        "final_anchor": "grafana-adoption-final-acceptance",
        "final_prerequisite_markers": (
            "Run the six-provider `GET`/`PUT` mætrix ænd positive/negætive OIDC checks",
        ),
        "mutation_sequence": (
            'begin_grafana_operation adoption "$adoption_id"',
            'write_grafana_secret_manifest "$adoption_mutation_secrets"',
            "grafana-cli admin reset-admin-password",
            'mv -- "$admin_secret_stage" "$admin_secret"',
            'write_grafana_secret_manifest "$adoption_activation_secrets"',
            'write_adoption_activation_manifest "$adoption_activation_manifest"',
            "verify_adoption_activation_generation",
            "rm --stop -f grafana-bootstrap grafana-migrator grafana-sso-policy",
            "verify_adoption_activation_generation",
            "--exit-code-from grafana-bootstrap grafana-bootstrap",
            "verify_adoption_activation_generation",
            "--exit-code-from grafana-migrator grafana-migrator",
            "verify_adoption_activation_generation",
            "--exit-code-from grafana-sso-policy grafana-sso-policy",
            "adoption_app_accepted=false",
            "trap stop_unaccepted_adoption_app EXIT",
            "verify_adoption_activation_generation",
            "up -d --wait --wait-timeout 180",
            "verify_adoption_activation_generation",
            'finish_grafana_operation adoption "$adoption_id"',
        ),
        "final_checks": (
            "verify_adoption_activation_generation",
            "'false:0'",
            '"$reviewed_app_image_id"',
            "healthy",
            "active overrides: 0",
        ),
    },
    {
        "workflow": "sso-reconcile",
        "operation_id": "sso_reconcile_id",
        "generation_verifier": "verify_sso_generation",
        "accepted_variable": "sso_app_accepted",
        "guard_function": "stop_unaccepted_sso_app",
        "guarded_app_start": "up -d --wait --wait-timeout 180",
        "final_anchor": "grafana-sso-reconcile-final-acceptance",
        "final_prerequisite_markers": (
            "full positive ænd negætive OIDC mætrix in child subshells",
        ),
        "mutation_sequence": (
            'begin_grafana_operation sso-reconcile "$sso_reconcile_id"',
            'write_grafana_secret_manifest "$sso_secret_manifest"',
            'write_sso_generation_manifest "$sso_generation_manifest"',
            "verify_sso_generation",
            '"${sso_compose[@]}" stop app',
            "verify_sso_generation",
            '"${sso_compose[@]}" rm -f',
            "verify_sso_generation",
            "--exit-code-from grafana-bootstrap grafana-bootstrap",
            "verify_sso_generation",
            "--exit-code-from grafana-migrator grafana-migrator",
            "verify_sso_generation",
            "--exit-code-from grafana-sso-policy grafana-sso-policy",
            "verify_sso_generation",
            "sso_app_accepted=false",
            "trap stop_unaccepted_sso_app EXIT",
            "verify_sso_generation",
            "up -d --wait --wait-timeout 180",
            "verify_sso_generation",
            'finish_grafana_operation sso-reconcile "$sso_reconcile_id"',
        ),
        "final_checks": (
            "verify_sso_generation",
            '"$sso_app_image_id"',
            "healthy",
            "active overrides: 0",
        ),
    },
    {
        "workflow": "break-glass",
        "operation_id": "break_glass_id",
        "generation_verifier": "verify_break_glass_generation",
        "final_generation_verifier": "verify_break_glass_closed_generation",
        "start_verifiers": (
            "verify_break_glass_generation",
            "verify_break_glass_closed_generation",
        ),
        "accepted_variable": "break_glass_app_accepted",
        "guard_function": "stop_unaccepted_break_glass_app",
        "guarded_app_start": "up -d --wait --wait-timeout 180",
        "final_anchor": "grafana-break-glass-final-acceptance",
        "final_prerequisite_markers": (
            "Force logout æll devices",
            "old recovery browser session fæils",
        ),
        "mutation_sequence": (
            'begin_grafana_operation break-glass "$break_glass_id"',
            'install -m 0600 /dev/null "$break_glass_form_override"',
            'write_grafana_secret_manifest "$break_glass_secret_manifest"',
            'write_break_glass_generation "$break_glass_generation"',
            "verify_break_glass_generation",
            "--exit-code-from grafana-sso-policy grafana-sso-policy",
            "break_glass_app_accepted=false",
            "trap stop_unaccepted_break_glass_app EXIT",
            "verify_break_glass_generation",
            "--force-recreate app",
            "probe_break_glass_peers",
            "verify_break_glass_generation",
            'mv -- "$final_admin_stage" "$final_admin_secret"',
            'write_grafana_secret_manifest "$break_glass_final_secret_manifest"',
            'write_break_glass_final_generation "$break_glass_final_generation"',
            "verify_break_glass_final_generation",
            'rm -- "$marker"',
            "verify_break_glass_final_generation",
            'rm -- "$break_glass_form_override"',
            'write_break_glass_closed_generation "$break_glass_closed_generation"',
            "verify_break_glass_closed_generation",
            "--exit-code-from grafana-sso-policy grafana-sso-policy",
            "verify_break_glass_closed_generation",
            "--force-recreate app",
            "probe_break_glass_peers",
            "verify_break_glass_closed_generation",
            'finish_grafana_operation break-glass "$break_glass_id"',
        ),
        "final_checks": (
            "verify_break_glass_closed_generation",
            'sha256sum -c "$break_glass_finite_evidence_checksum"',
            "probe_break_glass_peers",
            '"$break_glass_app_image_id"',
            "healthy",
        ),
    },
    {
        "workflow": "restore",
        "operation_id": "restore_id",
        "generation_verifier": "verify_restore_generation",
        "final_generation_verifier": "verify_restore_activation_generation",
        "start_verifiers": ("verify_restore_activation_generation",),
        "accepted_variable": "restore_app_accepted",
        "guard_function": "stop_unaccepted_restored_app",
        "guarded_app_start": "up -d --wait --wait-timeout 180",
        "final_anchor": "grafana-restore-final-acceptance",
        "final_prerequisite_markers": (
            "sæme Step 4\nlock-owning root shell",
            "Æfter æll closed-form OIDC, role, dætæ, plugin, ælert, SMTP",
        ),
        "mutation_sequence": (
            'begin_grafana_operation restore "$restore_id"',
            'write_grafana_secret_manifest "$restore_secret_manifest"',
            'write_restore_generation_manifest "$restore_generation_manifest"',
            "verify_restore_generation",
            'write_appdata_manifest "$app_stage" "$appdata_manifest_check"',
            "verify_restore_generation",
            'mv --exchange --no-copy -T appdata "$app_stage"',
            'write_appdata_manifest appdata "$appdata_manifest_check"',
            "verify_restore_generation",
            'recovery_form_override="${GRAFANA_RECOVERY_FORM_OVERRIDE:-}"',
            'write_restore_activation_generation "$restore_activation_manifest"',
            "verify_restore_activation_generation",
            "--exit-code-from grafana-bootstrap grafana-bootstrap",
            "verify_restore_activation_generation",
            "--exit-code-from grafana-migrator grafana-migrator",
            "verify_restore_activation_generation",
            "--exit-code-from grafana-sso-policy grafana-sso-policy",
            "verify_restore_activation_generation",
            "restore_app_accepted=false",
            "trap stop_unaccepted_restored_app EXIT",
            "verify_restore_activation_generation",
            "up -d --wait --wait-timeout 180",
            "verify_restore_activation_generation",
            'rm -- "$recovery_form_override"',
            'test "$restore_activation_phase" = closed-form',
            'finish_grafana_operation restore "$restore_id"',
        ),
        "final_checks": (
            'test "$restore_activation_phase" = closed-form',
            "verify_restore_activation_generation",
            "'false:0'",
            '"${restore_image_ids[app]}"',
            "healthy",
            "active overrides: 0",
        ),
    },
    {
        "workflow": "update",
        "operation_id": "update_id",
        "generation_verifier": "verify_update_generation",
        "accepted_variable": "update_app_accepted",
        "guard_function": "stop_unaccepted_updated_app",
        "guarded_app_start": "up -d --wait --wait-timeout 180",
        "final_anchor": "grafana-update-final-acceptance",
        "final_prerequisite_markers": (
            "Prove OIDC æccess ænd æll three roles plus both deniæl cæses",
        ),
        "mutation_sequence": (
            'begin_grafana_operation update "$update_id"',
            'write_grafana_secret_manifest "$update_secret_manifest"',
            'write_update_generation "$update_generation_manifest"',
            "verify_update_generation",
            '"${update_compose[@]}" stop app',
            "verify_update_generation",
            '"${update_compose[@]}" rm -f',
            "verify_update_generation",
            "--exit-code-from grafana-bootstrap grafana-bootstrap",
            "verify_update_generation",
            "--exit-code-from grafana-migrator grafana-migrator",
            "verify_update_generation",
            "--exit-code-from grafana-sso-policy grafana-sso-policy",
            "verify_update_generation",
            "update_app_accepted=false",
            "trap stop_unaccepted_updated_app EXIT",
            "verify_update_generation",
            "up -d --wait --wait-timeout 180",
            "verify_update_generation",
            'finish_grafana_operation update "$update_id"',
        ),
        "final_checks": (
            "verify_update_generation",
            "'false:0'",
            '"$expected_app_image_id"',
            "healthy",
            "active overrides: 0",
            "pgrep supercronic",
        ),
    },
)
workflow_results = {}
for workflow_spec in workflow_specs:
    workflow_results[workflow_spec["workflow"]] = validate_workflow_contract(
        document,
        workflow_spec,
    )
validate_break_glass_workflow(document, workflow_results["break-glass"])
validate_restore_workflow(document, workflow_results["restore"])

for generation_function in (
    "write_adoption_activation_manifest",
    "write_sso_generation_manifest",
    "write_break_glass_intent",
    "write_break_glass_generation",
    "write_break_glass_final_generation",
    "write_break_glass_closed_generation",
    "write_restore_generation_manifest",
    "write_restore_activation_generation",
    "write_update_generation",
):
    generation_mutations = (
        (
            "ignore digest producer failure",
            lambda function_source: replace_once(
                function_source,
                "|| return 1",
                "|| :",
            ),
        ),
        ("evaluate producer inside manifest printf", inject_inline_generation_producer),
    )
    for mutation_name, function_mutation in generation_mutations:
        require_rejected_mutation(
            document,
            lambda value, name=generation_function, mutate=function_mutation: (
                mutate_document_function(value, name, mutate)
            ),
            lambda value, name=generation_function: validate_generation_builder(
                value,
                name,
            ),
            f"{generation_function}: {mutation_name}",
        )

for generation_function in (
    "write_break_glass_generation",
    "write_break_glass_final_generation",
    "write_break_glass_closed_generation",
    "write_restore_activation_generation",
    "write_update_generation",
):
    require_rejected_mutation(
        document,
        lambda value, name=generation_function: mutate_document_function(
            value,
            name,
            lambda function_source: replace_once(
                function_source,
                'test -s "$effective_config"',
                'test -f "$effective_config"',
            ),
        ),
        lambda value, name=generation_function: validate_generation_builder(
            value,
            name,
        ),
        f"{generation_function}: accept empty effective config",
    )


def validate_mutated_workflow(mutated_document, workflow_spec):
    result = validate_workflow_contract(mutated_document, workflow_spec)
    if workflow_spec["workflow"] == "break-glass":
        validate_break_glass_workflow(mutated_document, result)
    elif workflow_spec["workflow"] == "restore":
        validate_restore_workflow(mutated_document, result)


for workflow_spec in workflow_specs:
    workflow = workflow_spec["workflow"]
    operation_id = workflow_spec["operation_id"]
    accepted_variable = workflow_spec["accepted_variable"]
    begin_command = f'begin_grafana_operation {workflow} "${operation_id}"'
    finish_command = f'finish_grafana_operation {workflow} "${operation_id}"'
    final_verifier = workflow_spec.get(
        "final_generation_verifier",
        workflow_spec["generation_verifier"],
    )
    prerequisite_marker = workflow_spec["final_prerequisite_markers"][0]

    def move_acceptance_early(value, accepted=accepted_variable):
        mutated = replace_once(value, f"{accepted}=false", f"{accepted}=true")
        return replace_last_once(mutated, f"{accepted}=true", f"{accepted}=false")

    workflow_mutations = (
        (
            "invoke run.sh under held locks",
            lambda value, begin=begin_command: replace_once(
                value,
                begin,
                f"{begin}\n./run.sh Grafana",
            ),
        ),
        (
            "release project FD before acceptance",
            lambda value, begin=begin_command: replace_once(
                value,
                begin,
                f'{begin}\nflock -u "$GRAFANA_OPS_PROJECT_FD"',
            ),
        ),
        (
            "accept before finish",
            lambda value, finish=finish_command, accepted=accepted_variable: replace_once(
                value,
                f"{finish}\n{accepted}=true",
                f"{accepted}=true\n{finish}",
            ),
        ),
        (
            "disarm guard before acceptance",
            lambda value, accepted=accepted_variable: replace_once(
                value,
                f"{accepted}=true\ntrap - EXIT",
                f"trap - EXIT\n{accepted}=true",
            ),
        ),
        (
            "suppress finish failure",
            lambda value, finish=finish_command: replace_once(
                value,
                finish,
                f"if ! {finish}; then :; fi",
            ),
        ),
        (
            "remove final generation recheck",
            lambda value, anchor=workflow_spec["final_anchor"], verifier=final_verifier: (
                mutate_anchored_bash_block(
                    value,
                    anchor,
                    lambda block: block.replace(verifier, ":"),
                )
            ),
        ),
        ("accept in activation block", move_acceptance_early),
        (
            "place final anchor before manual evidence",
            lambda value, anchor=workflow_spec["final_anchor"], marker=prerequisite_marker: (
                move_final_anchor_before_marker(value, anchor, marker)
            ),
        ),
    )
    for mutation_name, mutation in workflow_mutations:
        require_rejected_mutation(
            document,
            mutation,
            lambda value, spec=workflow_spec: validate_mutated_workflow(value, spec),
            f"{workflow}: {mutation_name}",
        )

break_glass_document_mutations = (
    (
        "add a third form override key",
        lambda value: mutate_anchored_bash_block(
            value,
            "grafana-break-glass-activation",
            lambda block: replace_once(
                block,
                "  '      GRAFANA_OAUTH_AUTO_LOGIN: \"false\"' > \\\n",
                "  '      GRAFANA_OAUTH_AUTO_LOGIN: \"false\"' \\\n"
                "  '      GF_AUTH_BASIC_ENABLED: \"true\"' > \\\n",
            ),
        ),
    ),
    (
        "mutate form app through base compose",
        lambda value: mutate_anchored_bash_block(
            value,
            "grafana-break-glass-activation",
            lambda block: replace_once(
                block,
                '"${break_glass_compose[@]}" stop app',
                '"${break_glass_base_compose[@]}" stop app',
            ),
        ),
    ),
    (
        "retain form override in closed phase",
        lambda value: replace_once(
            value,
            'rm -- "$break_glass_form_override"',
            ': # form override retained',
        ),
    ),
    (
        "skip first post-recreate peer matrix",
        lambda value: replace_once(
            value,
            "probe_break_glass_peers\n   verify_break_glass_generation",
            ": # peer matrix skipped\n   verify_break_glass_generation",
        ),
    ),
    (
        "remove final peer-contract reload",
        lambda value: replace_last_once(value, '. "$peer_helper"', ':'),
    ),
    (
        "drop finite evidence before matrix",
        lambda value: replace_once(
            value,
            'sha256sum -c "$break_glass_finite_evidence_checksum"',
            ': # unchecked finite evidence',
        ),
    ),
)
for mutation_name, mutation in break_glass_document_mutations:
    require_rejected_mutation(
        document,
        mutation,
        lambda value: validate_break_glass_workflow(
            value,
            validate_workflow_contract(value, workflow_specs[2]),
        ),
        f"break-glass: {mutation_name}",
    )

restore_document_mutations = (
    (
        "rehash mutable appdata at final acceptance",
        lambda value: mutate_anchored_bash_block(
            value,
            "grafana-restore-final-acceptance",
            lambda block: replace_once(
                block,
                "verify_restore_activation_generation",
                'write_appdata_manifest appdata "$appdata_manifest_check"\n'
                "verify_restore_activation_generation",
            ),
        ),
    ),
    (
        "call legacy live-tree generation verifier after start",
        lambda value: mutate_anchored_bash_block(
            value,
            "grafana-restore-final-acceptance",
            lambda block: replace_once(
                block,
                "verify_restore_activation_generation",
                "verify_restore_generation appdata\n"
                "verify_restore_activation_generation",
            ),
        ),
    ),
    (
        "close inherited recovery FD during form cleanup",
        lambda value: replace_once(
            value,
            'rm -- "$recovery_form_override"\nsync -f "$config_stage"',
            'rm -- "$recovery_form_override"\nexec {recovery_lock_fd}<&-\n'
            'sync -f "$config_stage"',
        ),
    ),
    (
        "start a new restore lock chain for form cleanup",
        lambda value: replace_once(
            value,
            ': "${recovery_form_override:?}"',
            ': "${recovery_form_override:?}"\n'
            'begin_grafana_operation restore "$restore_id"',
        ),
    ),
    (
        "compare unchecked restore producer",
        lambda value: mutate_document_function(
            value,
            "verify_restore_activation_generation",
            lambda function_source: replace_once(
                function_source,
                'cmp -s -- "$restore_generation_manifest" "$base_generation_check"',
                'cmp <(cat "$restore_generation_manifest") '
                '<(cat "$base_generation_check")',
            ),
        ),
    ),
)
for mutation_name, mutation in restore_document_mutations:
    require_rejected_mutation(
        document,
        mutation,
        lambda value: validate_restore_workflow(
            value,
            validate_workflow_contract(value, workflow_specs[3]),
        ),
        f"restore: {mutation_name}",
    )
manifest_function = extract_shell_function(restore_block, "write_appdata_manifest")
allowlist_function = extract_shell_function(peer_matrix_block, "load_break_glass_peer_allowlist")
run_manifest_fixture(manifest_function, fixture_root)
run_peer_allowlist_fixture(allowlist_function, fixture_root)
peer_inventory_functions = "\n".join(
    extract_shell_function(peer_matrix_block, function_name)
    for function_name in ("probe_break_glass_listener", "probe_break_glass_peers")
)
run_peer_inventory_failure_fixture(peer_inventory_functions, fixture_root)
operation_functions = "\n".join(
    extract_shell_function(operation_helper_block, function_name)
    for function_name in (
        "begin_grafana_operation",
        "verify_grafana_operation",
        "finish_grafana_operation",
    )
)
run_operation_lock_fixture(operation_functions, fixture_root)
run_secret_manifest_fixture(secret_manifest_function, fixture_root)
closed_generation_block = bash_block_containing(
    document,
    "write_break_glass_closed_generation() {",
)
closed_generation_function = extract_shell_function(
    closed_generation_block,
    "write_break_glass_closed_generation",
)
run_generation_producer_fixture(closed_generation_function, fixture_root)

operation_lock_mutations = (
    ("replace repository directory with lock file", lambda value: replace_once(value, 'GRAFANA_OPS_REPOSITORY_PATH="$(realpath -e -- ..)"', 'GRAFANA_OPS_REPOSITORY_PATH="$(pwd -P)/.grafana-operation.lock"')),
    ("make repository lock exclusive", lambda value: replace_once(value, 'flock --shared --nonblock "$GRAFANA_OPS_REPOSITORY_FD"', 'flock --exclusive --nonblock "$GRAFANA_OPS_REPOSITORY_FD"')),
    ("make project lock shared", lambda value: replace_once(value, 'flock --exclusive --nonblock "$GRAFANA_OPS_PROJECT_FD"', 'flock --shared --nonblock "$GRAFANA_OPS_PROJECT_FD"')),
    ("make runtime lock shared", lambda value: replace_once(value, 'flock --exclusive --nonblock "$GRAFANA_OPS_RUNTIME_FD"', 'flock --shared --nonblock "$GRAFANA_OPS_RUNTIME_FD"')),
    ("reverse project and runtime acquisition", swap_project_and_runtime_lock_segments),
    ("remove repository FD identity proof", lambda value: replace_once(value, '/proc/$BASHPID/fd/$GRAFANA_OPS_REPOSITORY_FD', '$GRAFANA_OPS_REPOSITORY_PATH')),
    ("release repository before runtime", lambda value: replace_once(value, 'flock -u "$GRAFANA_OPS_RUNTIME_FD"', 'flock -u "$GRAFANA_OPS_REPOSITORY_FD"')),
)
for mutation_name, mutation in operation_lock_mutations:
    require_rejected_mutation(
        operation_helper_block,
        mutation,
        lambda value: validate_operation_lock_contract(value, run_script),
        mutation_name,
    )

secret_manifest_mutations = (
    ("drop canonical secret ordering", lambda value: replace_once(value, 'unique[] | . + "\\u0000"', '.[] | . + "\\u0000"')),
    ("omit bootstrap-mounted admin secret", lambda value: value.replace('.key == "grafana-bootstrap"', '.key == "grafana-bootstrap-disabled"')),
    ("follow secret symlinks", lambda value: replace_once(value, 'test ! -L "$secret_file"', ':')),
    ("permit multiply linked secrets", lambda value: replace_once(value, "'regular file:1' || exit 1", "'regular file:2' || exit 1")),
    ("omit secret mode metadata", lambda value: replace_last_once(value, '"$secret_mode"', '"-"')),
    ("omit secret content digest", lambda value: replace_last_once(value, '"$secret_digest"', '"-"')),
    ("make secret manifest group-readable", lambda value: replace_once(value, 'chmod 0600 -- "$manifest_output"', 'chmod 0640 -- "$manifest_output"')),
    ("couple deployment owner to current shell", lambda value: replace_once(value, 'secret_owner_path="${GRAFANA_OPS_PROJECT_PATH:-.}"', 'secret_owner_path=.; expected_secret_uid="$(id -u)"')),
    ("drop rendered secret group contract", lambda value: replace_once(value, '(.value.group_add // [])[] | tostring', '(.value.missing_group_add // [])[] | tostring')),
    ("permit wrong group for 0640", lambda value: replace_once(value, '640) test "$secret_gid" -eq "$expected_secret_gid" || exit 1 ;;', '640) ;;')),
    ("log secret values", lambda value: replace_once(value, 'secret_digest="$(sha256sum < "$secret_file"', 'printf \'%s\\n\' "$(cat "$secret_file")"\n    secret_digest="$(sha256sum < "$secret_file"')),
)
for mutation_name, mutation in secret_manifest_mutations:
    require_rejected_mutation(
        operation_helper_block,
        mutation,
        validate_secret_manifest_contract,
        mutation_name,
    )

restore_mutations = (
    ("remove NUL sorting", lambda value: replace_once(value, "find . -xdev -print0 | LC_ALL=C sort -z |", "find . -xdev -print | LC_ALL=C sort |")),
    ("remove hardlink rejection", lambda value: replace_once(value, "test \"$(stat -c '%h' -- \"$manifest_entry\")\" -eq 1", ":")),
    ("remove ACL metadata", lambda value: replace_once(value, "getfacl --numeric --absolute-names --omit-header --", "printf ACL --")),
    ("remove xattr metadata", lambda value: replace_once(value, "getfattr --absolute-names --dump --encoding=hex --match=- --", "printf XATTR --")),
    ("omit ACL digest from NUL record", lambda value: replace_once(value, '"$acl_digest"', '"-"')),
    ("weaken stage parent ownership", lambda value: replace_once(value, "'directory:700:0:0'", "'directory:770:472:472'")),
    ("move manifest into app_stage", lambda value: replace_once(value, 'appdata_manifest="$db_stage/appdata-tree.manifest.v1"', 'appdata_manifest="$app_stage/appdata-tree.manifest.v1"')),
    ("remove live post-exchange probe", lambda value: replace_once(value, 'write_appdata_manifest appdata "$appdata_manifest_check"', ":")),
    ("exchange before final stage probe", move_exchange_before_last_stage_probe),
)
for mutation_name, mutation in restore_mutations:
    require_rejected_mutation(restore_block, mutation, validate_restore_exchange, mutation_name)

restore_stage_mutations = (
    ("remove root stage owner", lambda value: replace_once(value, 'install -d -o 0 -g 0 -m 0700 -- "$app_stage_parent" "$db_stage"', 'install -d -m 0700 -- "$app_stage_parent" "$db_stage"')),
    ("make stage parent group accessible", lambda value: replace_once(value, 'install -d -o 0 -g 0 -m 0700 -- "$app_stage_parent" "$db_stage"', 'install -d -o 0 -g 0 -m 0750 -- "$app_stage_parent" "$db_stage"')),
)
for mutation_name, mutation in restore_stage_mutations:
    require_rejected_mutation(restore_stage_block, mutation, validate_restore_stage, mutation_name)

peer_matrix_mutations = (
    ("make allowlist group-readable", lambda value: replace_once(value, '"regular file:1:600:$(id -u)"', '"regular file:1:640:$(id -u)"')),
    ("accept unterminated allowlist", lambda value: replace_once(value, 'test "$allowlist_last_byte" = 0a', 'test -n "$allowlist_last_byte"')),
    ("accept an eleventh empty field", lambda value: replace_once(value, 'test "${#delimiter_bytes}" -eq 9', 'test "${#delimiter_bytes}" -ge 9')),
    ("permit untrusted reachable peers", lambda value: replace_once(value, 'test "$allowed_result" = DENIED', 'test -n "$allowed_result"')),
    ("weaken positive listener status", lambda value: replace_once(value, '[ "$listener_status" = 200 ]', '[ -n "$listener_status" ]')),
    ("remove fail-closed peer default", lambda value: replace_once(value, 'peer_result=UNTESTED', 'peer_result=DENIED')),
    ("remove denied positive control", lambda value: replace_once(value, 'after-denied-$peer_id', 'denied-without-control-$peer_id')),
    ("remove post-matrix listener control", lambda value: replace_once(value, 'after-matrix', 'matrix-finished')),
    ("permit untrusted non-denial", lambda value: replace_once(value, '[ "$peer_result" != DENIED ]', '[ -z "$peer_result" ]')),
    ("ignore missing allowlist peers", lambda value: replace_once(value, "printf 'UNTESTED allowlist-entry-missing %s\\n'", "printf 'IGNORED allowlist-entry-missing %s\\n'")),
    ("permit UNTESTED results", lambda value: replace_once(value, 'test "$untested_peer_count" -eq 0', 'test "$untested_peer_count" -ge 0')),
    ("drop helper hash binding", lambda value: replace_once(value, 'helper-sha256|%s', 'helper-unbound|%s')),
    ("use volatile container ID as allowlist key", lambda value: replace_once(value, 'peer_key="$breakglass_network|$peer_name|$peer_scope|$namespace_name"', 'peer_key="$breakglass_network|$peer_id|$peer_scope|$namespace_name"')),
    ("drop peer image identity", lambda value: replace_once(value, '[ "$peer_image" != "${break_glass_allowed_image[$peer_key]}" ]', '[ -z "$peer_image" ]')),
    ("drop Compose service identity", lambda value: replace_once(value, '"${break_glass_allowed_service[$peer_key]}"', '"-"')),
    ("drop finite-job exit-zero attestation", lambda value: replace_once(value, "'false:0'", "'false:ignored'")),
    ("leave finite jobs in peer inventory", lambda value: replace_once(value, '"${peer_cleanup_compose[@]}" rm -f', '"${peer_cleanup_compose[@]}" ps --all')),
    ("ignore peer inventory producer failure", lambda value: replace_once(value, 'if ! docker ps --all --quiet --no-trunc > "$peer_inventory_file"; then', 'if docker ps --all --quiet --no-trunc > "$peer_inventory_file"; then')),
    ("consume peer inventory via unchecked process substitution", lambda value: replace_once(value, 'mapfile -t docker_container_ids < "$peer_inventory_file"', 'mapfile -t docker_container_ids < <(docker ps --all --quiet --no-trunc)')),
)
for mutation_name, mutation in peer_matrix_mutations:
    require_rejected_mutation(peer_matrix_block, mutation, validate_break_glass_matrix, mutation_name)
PY
}

[[ "$KEEP_TEST_OUTPUT" == true || "$KEEP_TEST_OUTPUT" == false ]] \
  || fail 'KEEP_TEST_OUTPUT must be true or false'
[[ -f "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" \
  && ! -L "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" ]] \
  || fail 'Grafana Dockerfile is missing or not a regular file'
for required_command in \
  docker curl timeout stat grep base64 date git tar sed sort awk jq yq chgrp chmod \
  python3 bash getfacl getfattr setfacl setfattr; do
  command -v "$required_command" >/dev/null 2>&1 \
    || fail "required command is missing: ${required_command}"
done
validate_documented_runbook_contracts \
  || fail 'documented Grafana runbook contracts or isolated negative fixtures failed'
log_ok 'documented restore manifest and exchange contract rejects metadata, content, ordering, and object-type drift'
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
