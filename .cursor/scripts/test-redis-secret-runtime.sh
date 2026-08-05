#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/redis-secret-runtime.XXXXXX")"
readonly RUN_ID="${BASHPID}"
readonly CONTAINER_NAME="redis-secret-runtime-${RUN_ID}"
readonly NEGATIVE_CONTAINER_NAME="redis-secret-negative-${RUN_ID}"
readonly VOLUME_NAME="redis-secret-runtime-${RUN_ID}"
readonly REDIS_IMAGE="${REDIS_TEST_IMAGE:-docker.io/library/redis:8-alpine}"
readonly SECRET_FILE="${TEST_ROOT}/REDIS_PASSWORD"
readonly PLACEHOLDER_FILE="${TEST_ROOT}/REDIS_PASSWORD_CHANGE_ME"
readonly REDIS_START_SOURCE="${TEST_REPO_ROOT}/templates/redis/scripts/redis-start.sh"
readonly REDIS_START_UNDER_TEST="${TEST_ROOT}/redis-start.sh"
readonly SECRET_VALUE='Redis-Æ-quote"-slash\-hash#-spæce vælue!'

cleanup() {
  docker rm -f -- "$CONTAINER_NAME" "$NEGATIVE_CONTAINER_NAME" >/dev/null 2>&1 || true
  docker volume rm -- "$VOLUME_NAME" >/dev/null 2>&1 || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL redis-secret-runtime: %s\n' "$*" >&2
  exit 1
}

wait_for_healthy() {
  local attempt status

  for attempt in {1..60}; do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER_NAME")"
    if [[ "$status" == healthy ]]; then
      return 0
    fi
    if [[ "$status" == unhealthy || "$status" == exited || "$status" == dead ]]; then
      docker logs "$CONTAINER_NAME" >&2 || true
      fail "container entered state ${status}"
    fi
    sleep 1
  done

  docker logs "$CONTAINER_NAME" >&2 || true
  fail 'container did not become healthy within 60 seconds'
}

printf '%s' "$SECRET_VALUE" >"$SECRET_FILE"
printf '%s' 'CHANGE_ME' >"$PLACEHOLDER_FILE"
chmod 0640 "$SECRET_FILE" "$PLACEHOLDER_FILE"
chgrp 1000 "$SECRET_FILE" "$PLACEHOLDER_FILE"

[[ -f "$REDIS_START_SOURCE" && ! -L "$REDIS_START_SOURCE" ]] \
  || fail 'Redis start wrapper source is missing or not a regular file'
cp -- "$REDIS_START_SOURCE" "$REDIS_START_UNDER_TEST"
chmod 0555 "$REDIS_START_UNDER_TEST"
cmp -s -- "$REDIS_START_SOURCE" "$REDIS_START_UNDER_TEST" \
  || fail 'private executable wrapper copy differs from the repository source'

docker volume create "$VOLUME_NAME" >/dev/null

docker run --detach \
  --name "$CONTAINER_NAME" \
  --user 999:1000 \
  --group-add 1000 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs /run:rw,noexec,nosuid,nodev,size=64m \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=volume,src=${VOLUME_NAME},dst=/data" \
  --mount "type=bind,src=${REDIS_START_UNDER_TEST},dst=/usr/local/bin/redis-start.sh,readonly" \
  --mount "type=bind,src=${SECRET_FILE},dst=/run/secrets/REDIS_PASSWORD,readonly" \
  --entrypoint /usr/local/bin/redis-start.sh \
  --health-cmd 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning ping | grep -qx PONG' \
  --health-interval 1s \
  --health-timeout 3s \
  --health-retries 20 \
  --health-start-period 2s \
  "$REDIS_IMAGE" redis-server >/dev/null

wait_for_healthy

docker exec "$CONTAINER_NAME" sh -ec '
  runtime_config="$(find /tmp -mindepth 2 -maxdepth 2 -type f -name redis.conf -print -quit)"
  test -n "$runtime_config"
  test "$(stat -c %a "$runtime_config")" = 600
  test "$(stat -c %u:%g "$runtime_config")" = 999:1000
  REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning ping | grep -qx PONG
'

docker inspect --format '{{json .Path}} {{json .Args}} {{json .Config.Healthcheck.Test}} {{json .Config.Env}}' \
  "$CONTAINER_NAME" >"${TEST_ROOT}/inspect.txt"
docker exec "$CONTAINER_NAME" sh -ec 'tr "\000" "\n" </proc/1/cmdline; tr "\000" "\n" </proc/1/environ' \
  >"${TEST_ROOT}/process.txt"
docker logs "$CONTAINER_NAME" >"${TEST_ROOT}/logs.txt" 2>&1

if grep -Ff "$SECRET_FILE" "${TEST_ROOT}/inspect.txt" "${TEST_ROOT}/process.txt" "${TEST_ROOT}/logs.txt" >/dev/null; then
  fail 'secret appeared in inspect output, PID 1 argv/environment, or logs'
fi

if docker exec "$CONTAINER_NAME" sh -ec 'REDISCLI_AUTH=definitely-wrong redis-cli -e --no-auth-warning ping >/dev/null 2>&1'; then
  fail 'Redis accepted an invalid password'
fi

docker exec "$CONTAINER_NAME" sh -ec '
  REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning set codex:redis-secret-runtime "Grüße Ægir 東京" >/dev/null
  REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning save >/dev/null
'

docker restart "$CONTAINER_NAME" >/dev/null
wait_for_healthy

persisted_value="$(docker exec "$CONTAINER_NAME" sh -ec 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning --raw get codex:redis-secret-runtime')"
[[ "$persisted_value" == 'Grüße Ægir 東京' ]] || fail 'authenticated Unicode value did not survive restart'

if docker run --name "$NEGATIVE_CONTAINER_NAME" \
  --user 999:1000 \
  --group-add 1000 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=bind,src=${REDIS_START_UNDER_TEST},dst=/usr/local/bin/redis-start.sh,readonly" \
  --mount "type=bind,src=${PLACEHOLDER_FILE},dst=/run/secrets/REDIS_PASSWORD,readonly" \
  --entrypoint /usr/local/bin/redis-start.sh \
  "$REDIS_IMAGE" redis-server >"${TEST_ROOT}/negative.out" 2>&1; then
  fail 'CHANGE_ME placeholder unexpectedly started Redis'
fi

if grep -Fq 'CHANGE_ME' "${TEST_ROOT}/negative.out"; then
  fail 'negative startup output exposed the placeholder value'
fi
grep -Fq 'placeholder value' "${TEST_ROOT}/negative.out" || fail 'negative startup did not report the placeholder class'

printf 'PASS redis-secret-runtime: health, auth, no argv/env/log leak, restart persistence, and fail-closed placeholder\n'
