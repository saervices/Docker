#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" \
  || exit 1
readonly TEST_SCRIPT_DIR
TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)" \
  || exit 1
readonly TEST_REPO_ROOT
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/erpnext-redis-compatibility.XXXXXX")" \
  || exit 1
readonly TEST_ROOT
if ! TEST_ROOT_IDENTITY="$(stat -Lc '%d:%i' -- "$TEST_ROOT")"; then
  rmdir -- "$TEST_ROOT" || true
  exit 1
fi
readonly TEST_ROOT_IDENTITY
readonly TEST_RUN_ID="${BASHPID}"
readonly TEST_NETWORK="erpnext-redis-compatibility-${TEST_RUN_ID}"
readonly TEST_CACHE_CONTAINER="erpnext-redis-cache-compatibility-${TEST_RUN_ID}"
readonly TEST_QUEUE_CONTAINER="erpnext-redis-queue-compatibility-${TEST_RUN_ID}"
readonly TEST_REDIS_IMAGE="docker.io/library/redis:8-alpine"
readonly TEST_CLIENT_IMAGE="${ERPNEXT_REDIS_COMPATIBILITY_CLIENT_IMAGE:-frappe/erpnext:v16}"
readonly TEST_PULL="${ERPNEXT_REDIS_COMPATIBILITY_PULL:-false}"
readonly TEST_CACHE_SECRET="${TEST_ROOT}/ERPNEXT_REDIS_CACHE_PASSWORD"
readonly TEST_QUEUE_SECRET="${TEST_ROOT}/ERPNEXT_REDIS_QUEUE_PASSWORD"
readonly TEST_CACHE_WRAPPER="${TEST_REPO_ROOT}/templates/erpnext-redis-cache/scripts/erpnext-redis-cache-start.sh"
readonly TEST_QUEUE_WRAPPER="${TEST_REPO_ROOT}/templates/erpnext-redis-queue/scripts/erpnext-redis-queue-start.sh"
readonly TEST_SECRET_VALUE='ERPNext-Redis-compatibility-Æ-2026'
TEST_NETWORK_CREATED=false
TEST_CACHE_CREATED=false
TEST_QUEUE_CREATED=false

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the uniquely næmed contæiners, network, ænd privæte fixture.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local exit_status="$?"
  local cleanup_failed=false
  local current_identity

  if [[ "$TEST_CACHE_CREATED" == true ]] && \
     ! docker rm -f -- "$TEST_CACHE_CONTAINER" >/dev/null 2>&1; then
    printf 'FAIL erpnext-redis-compatibility: could not remove cache fixture\n' >&2
    cleanup_failed=true
  fi
  if [[ "$TEST_QUEUE_CREATED" == true ]] && \
     ! docker rm -f -- "$TEST_QUEUE_CONTAINER" >/dev/null 2>&1; then
    printf 'FAIL erpnext-redis-compatibility: could not remove queue fixture\n' >&2
    cleanup_failed=true
  fi
  if [[ "$TEST_NETWORK_CREATED" == true ]] && \
     ! docker network rm -- "$TEST_NETWORK" >/dev/null 2>&1; then
    printf 'FAIL erpnext-redis-compatibility: could not remove fixture network\n' >&2
    cleanup_failed=true
  fi

  if [[ -L "$TEST_ROOT" ]] || \
     ! current_identity="$(stat -Lc '%d:%i' -- "$TEST_ROOT" 2>/dev/null)" || \
     [[ "$current_identity" != "$TEST_ROOT_IDENTITY" ]]; then
    printf 'FAIL erpnext-redis-compatibility: private fixture identity drifted; preserving replacement\n' >&2
    cleanup_failed=true
  elif ! find -P "$TEST_ROOT" -xdev -mindepth 1 -delete || \
       ! rmdir -- "$TEST_ROOT"; then
    printf 'FAIL erpnext-redis-compatibility: could not remove private fixture\n' >&2
    cleanup_failed=true
  fi

  if [[ "$exit_status" -eq 0 && "$cleanup_failed" == true ]]; then
    return 1
  fi
  return "$exit_status"
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Reports one deterministic test fæilure ænd exits non-zero.
#   Ærguments:
#     $* - Fæilure description
#ææææææææææææææææææææææææææææææææææ
fail() {
  printf 'FAIL erpnext-redis-compatibility: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_healthy
#   Wæits for one Redis fixture to become Docker-heælthy.
#   Ærguments:
#     $1 - Exæct contæiner næme
#ææææææææææææææææææææææææææææææææææ
wait_for_healthy() {
  local container_name="$1"
  local attempt status

  for ((attempt = 1; attempt <= 60; attempt++)); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_name")" \
      || fail "could not inspect ${container_name}"
    if [[ "$status" == healthy ]]; then
      return 0
    fi
    if [[ "$status" == unhealthy || "$status" == exited || "$status" == dead ]]; then
      docker logs "$container_name" >&2 || true
      fail "${container_name} entered state ${status}"
    fi
    sleep 1
  done

  docker logs "$container_name" >&2 || true
  fail "${container_name} did not become healthy within 60 seconds"
}

[[ "$TEST_PULL" == true || "$TEST_PULL" == false ]] \
  || fail 'ERPNEXT_REDIS_COMPATIBILITY_PULL must be true or false'
[[ -f "$TEST_CACHE_WRAPPER" && ! -L "$TEST_CACHE_WRAPPER" ]] \
  || fail 'cache start wrapper is missing or unsafe'
[[ -f "$TEST_QUEUE_WRAPPER" && ! -L "$TEST_QUEUE_WRAPPER" ]] \
  || fail 'queue start wrapper is missing or unsafe'

grep -Fq "ERPNEXT_REDIS_CACHE_IMAGE=${TEST_REDIS_IMAGE} " \
  "${TEST_REPO_ROOT}/templates/erpnext-redis-cache/.env" >/dev/null \
  || fail 'cache template no longer selects the reviewed Redis 8 Alpine channel'
grep -Fq "ERPNEXT_REDIS_QUEUE_IMAGE=${TEST_REDIS_IMAGE} " \
  "${TEST_REPO_ROOT}/templates/erpnext-redis-queue/.env" >/dev/null \
  || fail 'queue template no longer selects the reviewed Redis 8 Alpine channel'

if [[ "$TEST_PULL" == true ]]; then
  docker pull "$TEST_REDIS_IMAGE" >/dev/null \
    || fail "could not refresh ${TEST_REDIS_IMAGE}"
  docker pull "$TEST_CLIENT_IMAGE" >/dev/null \
    || fail "could not refresh ${TEST_CLIENT_IMAGE}"
else
  printf 'INFO erpnext-redis-compatibility: using local images; this is diagnostic evidence, not a fresh-channel release proof\n'
fi

redis_image_id="$(docker image inspect --format '{{.Id}}' "$TEST_REDIS_IMAGE")" \
  || fail "local image is unavailable: ${TEST_REDIS_IMAGE}"
client_image_id="$(docker image inspect --format '{{.Id}}' "$TEST_CLIENT_IMAGE")" \
  || fail "local image is unavailable: ${TEST_CLIENT_IMAGE}"
[[ "$redis_image_id" == sha256:* ]] || fail 'Redis image ID is not canonical'
[[ "$client_image_id" == sha256:* ]] || fail 'ERPNext client image ID is not canonical'
readonly redis_image_id client_image_id

printf '%s' "$TEST_SECRET_VALUE" >"$TEST_CACHE_SECRET"
printf '%s' "$TEST_SECRET_VALUE" >"$TEST_QUEUE_SECRET"
chmod 0640 "$TEST_CACHE_SECRET" "$TEST_QUEUE_SECRET"
chgrp 1000 "$TEST_CACHE_SECRET" "$TEST_QUEUE_SECRET"

docker network create "$TEST_NETWORK" >/dev/null \
  || fail 'could not create the isolated compatibility network'
TEST_NETWORK_CREATED=true

docker run --detach \
  --name "$TEST_CACHE_CONTAINER" \
  --network "$TEST_NETWORK" \
  --network-alias erpnext-redis-cache \
  --user 999:1000 \
  --group-add 1000 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs /run:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=1000,mode=0770 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m,uid=999,gid=1000,mode=1770 \
  --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=1000,mode=1770 \
  --mount "type=bind,src=${TEST_CACHE_WRAPPER},dst=/usr/local/bin/erpnext-redis-cache-start.sh,readonly" \
  --mount "type=bind,src=${TEST_CACHE_SECRET},dst=/run/secrets/ERPNEXT_REDIS_CACHE_PASSWORD,readonly" \
  --entrypoint /usr/local/bin/erpnext-redis-cache-start.sh \
  --env ERPNEXT_REDIS_CACHE_MAXMEMORY=48mb \
  --health-cmd 'REDISCLI_AUTH="$(cat /run/secrets/ERPNEXT_REDIS_CACHE_PASSWORD)" redis-cli --no-auth-warning ping | grep -qx PONG' \
  --health-interval 1s \
  --health-timeout 3s \
  --health-retries 20 \
  --health-start-period 2s \
  "$redis_image_id" redis-server >/dev/null \
  || fail 'could not start the cache Redis fixture'
TEST_CACHE_CREATED=true

docker run --detach \
  --name "$TEST_QUEUE_CONTAINER" \
  --network "$TEST_NETWORK" \
  --network-alias erpnext-redis-queue \
  --user 999:1000 \
  --group-add 1000 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --init \
  --tmpfs /run:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=1000,mode=0770 \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m,uid=999,gid=1000,mode=1770 \
  --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=16m,uid=999,gid=1000,mode=1770 \
  --tmpfs /data:rw,noexec,nosuid,nodev,size=64m,uid=999,gid=1000,mode=0770 \
  --mount "type=bind,src=${TEST_QUEUE_WRAPPER},dst=/usr/local/bin/erpnext-redis-queue-start.sh,readonly" \
  --mount "type=bind,src=${TEST_QUEUE_SECRET},dst=/run/secrets/ERPNEXT_REDIS_QUEUE_PASSWORD,readonly" \
  --entrypoint /usr/local/bin/erpnext-redis-queue-start.sh \
  --env ERPNEXT_REDIS_QUEUE_MAXMEMORY=48mb \
  --health-cmd 'REDISCLI_AUTH="$(cat /run/secrets/ERPNEXT_REDIS_QUEUE_PASSWORD)" redis-cli --no-auth-warning ping | grep -qx PONG' \
  --health-interval 1s \
  --health-timeout 3s \
  --health-retries 20 \
  --health-start-period 2s \
  "$redis_image_id" redis-server >/dev/null \
  || fail 'could not start the queue Redis fixture'
TEST_QUEUE_CREATED=true

wait_for_healthy "$TEST_CACHE_CONTAINER"
wait_for_healthy "$TEST_QUEUE_CONTAINER"

redis_server_version="$(docker exec "$TEST_CACHE_CONTAINER" redis-server --version)" \
  || fail 'could not read the resolved Redis server version'
[[ "$redis_server_version" =~ ^Redis\ server\ v=8\. ]] \
  || fail "resolved channel is not Redis 8: ${redis_server_version}"
readonly redis_server_version

docker run --rm \
  --network "$TEST_NETWORK" \
  --user 1000:1000 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m,uid=1000,gid=1000,mode=1770 \
  --mount "type=bind,src=${TEST_CACHE_SECRET},dst=/run/secrets/ERPNEXT_REDIS_CACHE_PASSWORD,readonly" \
  --mount "type=bind,src=${TEST_QUEUE_SECRET},dst=/run/secrets/ERPNEXT_REDIS_QUEUE_PASSWORD,readonly" \
  --workdir /home/frappe/frappe-bench \
  --entrypoint /home/frappe/frappe-bench/env/bin/python \
  --env FRAPPE_REDIS_QUEUE=redis://erpnext-redis-queue:6379 \
  --env PYTHONDONTWRITEBYTECODE=1 \
  "$client_image_id" -c '
from importlib.metadata import version
from pathlib import Path
from urllib.parse import quote

import frappe
from frappe.utils.redis_queue import RedisQueue
from rq import Queue
from rq.job import Job

cache_password = Path("/run/secrets/ERPNEXT_REDIS_CACHE_PASSWORD").read_text(encoding="utf-8")
queue_password = Path("/run/secrets/ERPNEXT_REDIS_QUEUE_PASSWORD").read_text(encoding="utf-8")
encoded_cache_password = quote(cache_password, safe="")
frappe.local.conf = frappe._dict(
    db_name="erpnext_redis_compatibility",
    redis_cache=f"redis://:{encoded_cache_password}@erpnext-redis-cache:6379",
    redis_cache_sentinel_enabled=False,
    redis_queue="redis://erpnext-redis-queue:6379",
    redis_queue_sentinel_enabled=False,
)
frappe.setup_redis_cache_connection()
cache = frappe.cache
queue_connection = RedisQueue.get_connection(password=queue_password)
assert cache.ping() is True
assert queue_connection.ping() is True
assert cache.set("erpnext:redis:compatibility", "Grüße Ægir 東京") is True
assert cache.get("erpnext:redis:compatibility") == "Grüße Ægir 東京".encode()
assert cache.delete("erpnext:redis:compatibility") == 1
queue = Queue("short", connection=queue_connection)
job = queue.enqueue_call(
    func="operator.add",
    args=(20, 22),
    job_id="erpnext-redis-compatibility",
)
assert queue.get_job_ids() == [job.id]
fetched = Job.fetch(job.id, connection=queue_connection)
assert fetched.func_name == "operator.add"
assert fetched.args == (20, 22)
queue.empty()
assert queue.count == 0
print(
    "frappe=" + version("frappe"),
    "erpnext=" + version("erpnext"),
    "redis-py=" + version("redis"),
    "rq=" + version("rq"),
)
' \
  || fail 'Frappe RedisWrapper or RQ compatibility probe failed'

printf 'PASS erpnext-redis-compatibility: redis_ref=%s redis_id=%s client_ref=%s client_id=%s %s\n' \
  "$TEST_REDIS_IMAGE" "$redis_image_id" "$TEST_CLIENT_IMAGE" "$client_image_id" "$redis_server_version"
