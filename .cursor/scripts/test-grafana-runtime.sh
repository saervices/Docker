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
readonly GRAFANA_BASE_IMAGE="${GRAFANA_TEST_BASE_IMAGE:-grafana/grafana:latest}"
readonly GRAFANA_GO_IMAGE="${GRAFANA_TEST_GO_IMAGE:-docker.io/library/golang:alpine}"
readonly POSTGRES_IMAGE="${GRAFANA_TEST_POSTGRES_IMAGE:-docker.io/library/postgres:18}"
readonly NETWORK_NAME="${TEST_PREFIX}-backend"
readonly MERGED_FRONTEND_NETWORK="${TEST_PREFIX}-merged-frontend"
readonly MERGED_BACKEND_NETWORK="${TEST_PREFIX}-merged-backend"
readonly DATABASE_VOLUME="${TEST_PREFIX}-database"
readonly GRAFANA_DATA_VOLUME="${TEST_PREFIX}-data"
readonly GRAFANA_STATE_VOLUME="${TEST_PREFIX}-bootstrap-state"
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
readonly RUNTIME_ROOT="${TEST_ROOT}/runtime"
readonly EVIDENCE_ROOT="${TEST_ROOT}/evidence"
readonly MERGED_ROOT="${RUNTIME_ROOT}/merged"
readonly MERGED_SOURCE="${MERGED_ROOT}/source"
readonly MERGED_RUNNER="${MERGED_ROOT}/runner"
readonly MERGED_APP_DIR="${MERGED_RUNNER}/Grafana"
readonly MERGED_OVERRIDE_FILE="${MERGED_APP_DIR}/docker-compose.runtime-test.yaml"
readonly MERGED_CONFIG_FILE="${EVIDENCE_ROOT}/merged-config.json"
readonly MERGED_APP_NAME="gfr${RUN_ID//-/}"
readonly MERGED_PROJECT_NAME="${TEST_PREFIX}-merged"
readonly MERGED_APP_CONTAINER="${MERGED_APP_NAME}"
readonly MERGED_POSTGRES_CONTAINER="${MERGED_APP_NAME}-postgresql"
readonly MERGED_BOOTSTRAP_CONTAINER="${MERGED_APP_NAME}-bootstrap"
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
readonly BOOTSTRAP_WRAPPER_FILE="${RUNTIME_ROOT}/grafana-bootstrap-vendor-wrapper.sh"
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
    APP_UID="$TEST_APP_UID" \
    APP_GID="$HOST_GROUP_ID" \
    APP_NAME="$MERGED_APP_NAME" \
    APP_IMAGE="$IMAGE_NAME" \
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
    APP_UID="$TEST_APP_UID" \
    APP_GID="$HOST_GROUP_ID" \
    APP_NAME="$MERGED_APP_NAME" \
    APP_IMAGE="$IMAGE_NAME" \
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
  local resource_id

  trap - EXIT HUP INT TERM
  set +e
  if docker info >/dev/null 2>&1; then
    if [[ "$MERGED_COMPOSE_READY" == true \
      && -f "$MERGED_OVERRIDE_FILE" \
      && -f "${MERGED_APP_DIR}/docker-compose.main.yaml" ]]; then
      if [[ -d "$EVIDENCE_ROOT" ]]; then
        merged_compose logs --no-color \
          >"${EVIDENCE_ROOT}/cleanup-merged-compose.log" 2>&1 || true
      fi
      merged_compose_bounded 120s down --remove-orphans \
        >/dev/null 2>&1 || cleanup_status=1
      MERGED_STARTED=false
    fi
    for container_name in \
      "$APP_LOCKED_CONTAINER" "$APP_FORM_CONTAINER" \
      "$CLI_RESET_CONTAINER" "$CLI_REJECT_CONTAINER" \
      "$MARKER_CHECK_CONTAINER" "$BOOTSTRAP_REPEAT_CONTAINER" \
      "$BOOTSTRAP_SIGNAL_MARKER_CONTAINER" "$BOOTSTRAP_SIGNAL_CONTAINER" \
      "$BOOTSTRAP_CONTAINER" "$POSTGRES_CONTAINER" \
      "$VOLUME_INIT_CONTAINER" \
      "$MERGED_APP_CONTAINER" "$MERGED_BOOTSTRAP_CONTAINER" \
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
    remove_owned_volume "$DATABASE_VOLUME" || cleanup_status=1
    remove_owned_volume "$GRAFANA_DATA_VOLUME" || cleanup_status=1
    remove_owned_volume "$GRAFANA_STATE_VOLUME" || cleanup_status=1
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
    remove_owned_image "$IMAGE_NAME" || cleanup_status=1
    if [[ -n "$(docker container ls --all --quiet --filter "label=${OWNERSHIP_LABEL}=${RUN_ID}" 2>/dev/null)" ]]; then
      cleanup_status=1
    fi
    if docker volume inspect "$DATABASE_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$GRAFANA_DATA_VOLUME" >/dev/null 2>&1 \
      || docker volume inspect "$GRAFANA_STATE_VOLUME" >/dev/null 2>&1 \
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
      || docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
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
    printf 'PASS grafana-runtime: %d assertions in %ds; all owned containers, network, volume, runtime secrets, and the unique final image were removed\n' \
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
    "$POSTGRES_CONTAINER" "$VOLUME_INIT_CONTAINER" \
    "$BOOTSTRAP_CONTAINER" "$BOOTSTRAP_SIGNAL_CONTAINER" \
    "$BOOTSTRAP_SIGNAL_MARKER_CONTAINER" \
    "$BOOTSTRAP_REPEAT_CONTAINER" "$MARKER_CHECK_CONTAINER" \
    "$CLI_REJECT_CONTAINER" "$CLI_RESET_CONTAINER" \
    "$APP_FORM_CONTAINER" "$APP_LOCKED_CONTAINER" \
    "$MERGED_APP_CONTAINER" "$MERGED_POSTGRES_CONTAINER" \
    "$MERGED_BOOTSTRAP_CONTAINER" "$MERGED_MAINTENANCE_CONTAINER" \
    "$MERGED_VOLUME_INIT_CONTAINER" "$MERGED_MARKER_CHECK_CONTAINER"; do
    ! docker container inspect "$container_name" >/dev/null 2>&1 \
      || fail "disposable container name already exists: ${container_name}"
  done
  for volume_name in \
    "$DATABASE_VOLUME" "$GRAFANA_DATA_VOLUME" "$GRAFANA_STATE_VOLUME" \
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
  for image_name in "$IMAGE_NAME" "$MERGED_POSTGRES_IMAGE" "$MERGED_MAINTENANCE_IMAGE"; do
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
  docker exec "$POSTGRES_CONTAINER" bash -euo pipefail -c '
    export PGPASSWORD="$(< /run/secrets/POSTGRES_PASSWORD)"
    exec psql --no-psqlrc --tuples-only --no-align \
      --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
      --command '\''SELECT password FROM "user" WHERE id = 1;'\''
  '
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
    --env GRAFANA_OIDC_NAME=authentik
    --env GRAFANA_OIDC_SLUG=grafana
    --env GRAFANA_OIDC_ACCESS_GROUP=grafana-users
    --env GRAFANA_OIDC_ADMIN_GROUP=grafana-admins
    --env GRAFANA_OIDC_EDITOR_GROUP=grafana-editors
    --env GRAFANA_OIDC_VIEWER_GROUP=grafana-viewers
    --env 'GRAFANA_OIDC_SCOPES=openid profile email'
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

[[ "$KEEP_TEST_OUTPUT" == true || "$KEEP_TEST_OUTPUT" == false ]] \
  || fail 'KEEP_TEST_OUTPUT must be true or false'
[[ -f "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" \
  && ! -L "${TEST_REPO_ROOT}/Grafana/dockerfiles/Dockerfile" ]] \
  || fail 'Grafana Dockerfile is missing or not a regular file'
for required_command in \
  docker curl timeout stat grep base64 date git tar sed jq yq chgrp chmod; do
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

log_info 'building the reviewed final Grafana image without cache'
if ! timeout --foreground 1200s docker build \
  --pull \
  --no-cache \
  --label "${OWNERSHIP_LABEL}=${RUN_ID}" \
  --build-arg "GRAFANA_BASE_IMAGE=${GRAFANA_BASE_IMAGE}" \
  --build-arg "GRAFANA_GO_IMAGE=${GRAFANA_GO_IMAGE}" \
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
log_ok 'final no-cache image build, embedded Go tests, and image contract'

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
    templates/grafana-bootstrap
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
  --arg database_volume "$MERGED_DATABASE_VOLUME" '
    def run_mounts($service):
      [.services[$service].tmpfs[] | select(startswith("/run:"))];
    def exact_run($service):
      run_mounts($service) == [$run_mount];
    (.services | keys | sort) ==
      ["app", "grafana-bootstrap", "postgresql", "postgresql_maintenance"]
    and exact_run("app")
    and exact_run("grafana-bootstrap")
    and exact_run("postgresql")
    and exact_run("postgresql_maintenance")
    and .services.app.user == ("472:" + $app_gid)
    and (.services.app.group_add // []) == []
    and .services["grafana-bootstrap"].user == "472:472"
    and .services["grafana-bootstrap"].group_add == [$app_gid]
    and (.services.postgresql.user // null) == null
    and .services.postgresql.group_add == [$app_gid]
    and .services.postgresql_maintenance.user == "999:999"
    and .services.postgresql_maintenance.group_add == [$app_gid]
    and (.services.app.build // null) == null
    and .services.app.depends_on.postgresql.condition == "service_healthy"
    and .services.app.depends_on["grafana-bootstrap"].condition ==
      "service_completed_successfully"
    and .services["grafana-bootstrap"].depends_on.postgresql.condition ==
      "service_healthy"
    and ([.services.app.secrets[].source] | index("GRAFANA_ADMIN_PASSWORD")) == null
    and ([.services["grafana-bootstrap"].secrets[].source] | sort) ==
      ["GRAFANA_ADMIN_PASSWORD", "GRAFANA_SECRET_KEY", "POSTGRES_PASSWORD"]
    and ([.services.app.volumes[] | select(.target == "/var/lib/grafana")][0].source) ==
      "grafana_runtime_data"
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
log_ok 'run.sh rendered the exact four-service closure with shared UID/GID 0771 /run mounts'

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
  fail 'merged PostgreSQL, bootstrap, maintenance, and app closure did not start'
fi
wait_for_postgresql "$MERGED_POSTGRES_CONTAINER" "$MERGED_APP_NAME" "$MERGED_APP_NAME"
wait_for_grafana "$MERGED_APP_CONTAINER"
[[ "$(docker container inspect --format '{{.State.ExitCode}}' \
  "$MERGED_BOOTSTRAP_CONTAINER")" == 0 ]] \
  || fail 'merged bootstrap job did not complete successfully'
[[ "$(docker container inspect --format '{{.State.Status}}' \
  "$MERGED_MAINTENANCE_CONTAINER")" == running ]] \
  || fail 'merged maintenance scheduler is not running'
docker container inspect \
  "$MERGED_APP_CONTAINER" "$MERGED_BOOTSTRAP_CONTAINER" \
  "$MERGED_POSTGRES_CONTAINER" "$MERGED_MAINTENANCE_CONTAINER" \
  >"${EVIDENCE_ROOT}/merged-runtime-inspect.json"
if ! jq --exit-status \
  --arg app "$MERGED_APP_CONTAINER" \
  --arg bootstrap "$MERGED_BOOTSTRAP_CONTAINER" \
  --arg postgresql "$MERGED_POSTGRES_CONTAINER" \
  --arg maintenance "$MERGED_MAINTENANCE_CONTAINER" \
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
    run_ok($app)
    and run_ok($bootstrap)
    and run_ok($postgresql)
    and run_ok($maintenance)
    and item($app).Config.User == ("472:" + $app_gid)
    and item($bootstrap).Config.User == "472:472"
    and item($bootstrap).HostConfig.GroupAdd == [$app_gid]
    and item($postgresql).HostConfig.GroupAdd == [$app_gid]
    and item($maintenance).Config.User == "999:999"
    and item($maintenance).HostConfig.GroupAdd == [$app_gid]
    and ([item($app).Mounts[].Destination] |
      index("/run/secrets/GRAFANA_ADMIN_PASSWORD")) == null
  ' "${EVIDENCE_ROOT}/merged-runtime-inspect.json" >/dev/null; then
  fail 'runtime containers lost the exact rendered shared /run, user, group, or admin-secret boundary'
fi
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
  --entrypoint /bin/sh \
  "$IMAGE_NAME" -euc '
    marker=/state/bootstrap-v1.complete
    test -f "$marker" && test ! -L "$marker"
    test "$(stat -c %a "$marker")" = 600
    test "$(stat -c %u:%g "$marker")" = 472:472
    test "$(cat "$marker")" = grafana-bootstrap-v1
  ' >"${EVIDENCE_ROOT}/merged-marker-check.log" 2>&1; then
  fail 'merged bootstrap did not publish the exact committed marker'
fi
log_ok 'merged bootstrap published the exact committed marker before final-app startup'

merged_compose logs --no-color \
  >"${EVIDENCE_ROOT}/merged-compose.log" 2>&1 || true
if ! merged_compose_bounded 120s down --remove-orphans \
  >"${EVIDENCE_ROOT}/merged-down.log" 2>&1; then
  fail 'merged closure did not stop cleanly within 120 seconds'
fi
MERGED_STARTED=false
log_ok 'merged PostgreSQL, maintenance, bootstrap, and final-app containers stopped cleanly'

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
log_ok 'final daemon has no administrator secret mount, environment key, staged file, or process value'

printf '{"user":"%s","password":"%s"}' \
  "$ADMIN_USER" "$RESET_PASSWORD_VALUE" >"$LOGIN_PAYLOAD_FILE"
chmod 0600 "$LOGIN_PAYLOAD_FILE"
require_http_status 200 form-login \
  --header 'Content-Type: application/json' \
  --data-binary "@${LOGIN_PAYLOAD_FILE}" \
  "${FORM_APP_URL}/login"
log_ok 'local form login accepted the stdin-rotated recovery password'

BASIC_VALUE="$(printf '%s:%s' "$ADMIN_USER" "$RESET_PASSWORD_VALUE" | base64 -w 0)"
printf 'Authorization: Basic %s\n' "$BASIC_VALUE" >"$BASIC_HEADER_FILE"
unset BASIC_VALUE
chmod 0600 "$BASIC_HEADER_FILE"
require_http_status 401 form-basic-disabled \
  --header "@${BASIC_HEADER_FILE}" \
  "${FORM_APP_URL}/api/admin/settings"
log_ok 'HTTP Basic remained disabled while the local form was enabled'

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
log_ok 'local form login was rejected after the hardened restart'

require_http_status 401 locked-basic-disabled \
  --header "@${BASIC_HEADER_FILE}" \
  "${LOCKED_APP_URL}/api/admin/settings"
log_ok 'HTTP Basic remained disabled after the hardened restart'

require_http_status 401 locked-anonymous-disabled \
  "${LOCKED_APP_URL}/api/admin/settings"
log_ok 'anonymous access remained disabled after the hardened restart'

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
