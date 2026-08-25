#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly CONTEXT_DIR="${REPO_ROOT}/templates/collabora/dockerfiles"
readonly DOCKERFILE="${CONTEXT_DIR}/dockerfile.collabora"
readonly COMPOSE_FILE="${REPO_ROOT}/templates/collabora/docker-compose.collabora.yaml"
readonly ENV_FILE="${REPO_ROOT}/templates/collabora/.env"
readonly BASE_IMAGE="${COLLABORA_BASE_IMAGE:-collabora/code:latest}"
readonly GO_IMAGE="${COLLABORA_GO_IMAGE:-golang:alpine}"
readonly RUN_ID="${BASHPID}"
readonly TEST_IMAGE="codex-collabora-preflight-test:${RUN_ID}"
readonly RUNTIME_CONTAINER="codex-collabora-preflight-runtime-${RUN_ID}"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/collabora-preflight.XXXXXX")"

PASS=0
FAIL=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes exæct test contæiners, the locæl test tæg, ænd fixtures.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  docker ps -aq --filter "label=codex.collabora-preflight=${RUN_ID}" \
    | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker image rm "$TEST_IMAGE" >/dev/null 2>&1 || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pass
#   Records one successful cæse.
#ææææææææææææææææææææææææææææææææææ
pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Records one fæiled cæse without printing secret content.
#ææææææææææææææææææææææææææææææææææ
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_preflight
#   Runs the shellless preflight with only existing fixture files mounted.
#   Ærguments:
#     $1 - fixture directory
#     $2 - output file
#     $3 - optionæl COLLABORA_EXTRA_PARAMS vælue
#ææææææææææææææææææææææææææææææææææ
run_preflight() {
  local fixture="$1"
  local output="$2"
  local extra_params="${3-}"
  local -a command=(
    docker run --rm
    --label "codex.collabora-preflight=${RUN_ID}"
    --network none
    --read-only
    --cap-drop ALL
    --security-opt no-new-privileges:true
  )
  if [[ -e "${fixture}/proof_key" ]]; then
    command+=(--mount "type=bind,source=${fixture}/proof_key,destination=/etc/coolwsd/proof_key,readonly")
  fi
  if [[ -e "${fixture}/proof_key.pub" ]]; then
    command+=(--mount "type=bind,source=${fixture}/proof_key.pub,destination=/etc/coolwsd/proof_key.pub,readonly")
  fi
  if (( $# >= 3 )); then
    command+=(--env "COLLABORA_EXTRA_PARAMS=${extra_params}")
  fi
  command+=("$TEST_IMAGE" --preflight-only)
  "${command[@]}" >"$output" 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_valid_pair
#   Creætes one unencrypted RSÆ fixture pæir.
#   Ærguments:
#     $1 - fixture directory
#ææææææææææææææææææææææææææææææææææ
prepare_valid_pair() {
  local fixture="$1"
  mkdir -p -- "$fixture"
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "${fixture}/proof_key" >/dev/null 2>&1
  openssl pkey -in "${fixture}/proof_key" -pubout \
    -out "${fixture}/proof_key.pub" >/dev/null 2>&1
  chmod 0644 "${fixture}/proof_key" "${fixture}/proof_key.pub"
}

command -v docker >/dev/null
command -v openssl >/dev/null
command -v yq >/dev/null

compose_user="$(yq -r '.services.collabora.user' "$COMPOSE_FILE")"
compose_cap_drop="$(yq -o=json -I=0 '.services.collabora.cap_drop' "$COMPOSE_FILE")"
compose_cap_add="$(yq -o=json -I=0 '.services.collabora.cap_add' "$COMPOSE_FILE")"
compose_image="$(yq -r '.services.collabora.image' "$COMPOSE_FILE")"
compose_base_arg="$(yq -r '.services.collabora.build.args.COLLABORA_BASE_IMAGE' "$COMPOSE_FILE")"
compose_go_arg="$(yq -r '.services.collabora.build.args.COLLABORA_GO_IMAGE' "$COMPOSE_FILE")"
compose_pull_policy="$(yq -r '.services.collabora.pull_policy' "$COMPOSE_FILE")"
compose_build_pull="$(yq -r '.services.collabora.build.pull' "$COMPOSE_FILE")"
compose_no_cache="$(yq -r '.services.collabora.build.no_cache' "$COMPOSE_FILE")"
compose_extra_env="$(yq -r '.services.collabora.environment.COLLABORA_EXTRA_PARAMS' "$COMPOSE_FILE")"
compose_legacy_extra="$(yq -r '.services.collabora.environment.extra_params' "$COMPOSE_FILE")"
compose_legacy_cert="$(yq -r '.services.collabora.environment.DONT_GEN_SSL_CERT' "$COMPOSE_FILE")"
compose_router_rule="$(yq -r '.services.collabora.labels[] | select(test("routers.*rule="))' "$COMPOSE_FILE")"
default_output_image="$(awk -F= '$1 == "COLLABORA_IMAGE" { value=$2; sub(/[[:space:]]+#.*/, "", value); print value }' "$ENV_FILE")"
default_base_image="$(awk -F= '$1 == "COLLABORA_BASE_IMAGE" { value=$2; sub(/[[:space:]]+#.*/, "", value); print value }' "$ENV_FILE")"

if [[ "$compose_user" == '${COLLABORA_UID:-1001}:${COLLABORA_GID:-1001}' \
  && "$compose_cap_drop" == '["ALL"]' \
  && "$compose_cap_add" == null \
  && "$compose_image" == '${COLLABORA_IMAGE:?Image required}' \
  && "$compose_base_arg" == '${COLLABORA_BASE_IMAGE:?Vendor image required}' \
  && "$compose_go_arg" == '${COLLABORA_GO_IMAGE:-golang:alpine}' \
  && "$compose_pull_policy" == build \
  && "$compose_build_pull" == true \
  && "$compose_no_cache" == true \
  && "$compose_extra_env" == '${COLLABORA_EXTRA_PARAMS:-}' \
  && "$compose_legacy_extra" == null \
  && "$compose_legacy_cert" == null \
  && "$compose_router_rule" == *'PathPrefix(`/hosting/discovery`)'* \
  && "$compose_router_rule" == *'PathPrefix(`/hosting/capabilities`)'* \
  && -n "$default_output_image" \
  && -n "$default_base_image" \
  && "$default_output_image" != "$default_base_image" ]]; then
  pass compose-shellless-hardening-contract
else
  fail compose-shellless-hardening-contract
fi

expected_entrypoint='["/usr/bin/coolwsd","--use-env-vars","--o:sys_template_path=/opt/cool/systemplate","--o:child_root_path=/opt/cool/child-roots","--o:file_server_root_path=/usr/share/coolwsd","--o:cache_files.path=/opt/cool/cache","--o:logging.color=false","--o:stop_on_config_change=true"]'

docker pull "$BASE_IMAGE" >/dev/null
actual_entrypoint="$(docker image inspect "$BASE_IMAGE" --format '{{json .Config.Entrypoint}}')"
actual_command="$(docker image inspect "$BASE_IMAGE" --format '{{json .Config.Cmd}}')"
actual_user="$(docker image inspect "$BASE_IMAGE" --format '{{.Config.User}}')"
if [[ "$actual_entrypoint" == "$expected_entrypoint" && "$actual_command" == null && "$actual_user" == 1001 ]]; then
  pass vendor-shellless-contract
else
  fail vendor-shellless-contract
fi

docker build --pull --no-cache --rm --force-rm \
  --build-arg "COLLABORA_BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg "COLLABORA_GO_IMAGE=${GO_IMAGE}" \
  --file "$DOCKERFILE" \
  --tag "$TEST_IMAGE" \
  "$CONTEXT_DIR"
pass gofmt-unit-tests-and-build

wrapper_entrypoint="$(docker image inspect "$TEST_IMAGE" --format '{{json .Config.Entrypoint}}')"
wrapper_command="$(docker image inspect "$TEST_IMAGE" --format '{{json .Config.Cmd}}')"
wrapper_user="$(docker image inspect "$TEST_IMAGE" --format '{{.Config.User}}')"
if [[ "$wrapper_entrypoint" == '["/usr/local/bin/collabora-preflight"]' \
  && "$wrapper_command" == null \
  && "$wrapper_user" == 1001 \
  && "$TEST_IMAGE" != "$BASE_IMAGE" ]]; then
  pass wrapper-image-contract
else
  fail wrapper-image-contract
fi

prepare_valid_pair "${TEST_ROOT}/valid"
if run_preflight "${TEST_ROOT}/valid" "${TEST_ROOT}/valid.out"; then
  pass runtime-valid-pair
else
  fail runtime-valid-pair
fi

prepare_valid_pair "${TEST_ROOT}/missing-private"
rm -f -- "${TEST_ROOT}/missing-private/proof_key"
if run_preflight "${TEST_ROOT}/missing-private" "${TEST_ROOT}/missing-private.out"; then
  fail runtime-missing-private
else
  pass runtime-missing-private
fi

prepare_valid_pair "${TEST_ROOT}/empty-public"
: >"${TEST_ROOT}/empty-public/proof_key.pub"
chmod 0644 "${TEST_ROOT}/empty-public/proof_key.pub"
if run_preflight "${TEST_ROOT}/empty-public" "${TEST_ROOT}/empty-public.out"; then
  fail runtime-empty-public
else
  pass runtime-empty-public
fi

prepare_valid_pair "${TEST_ROOT}/placeholder-private"
printf 'CHANGE_ME' >"${TEST_ROOT}/placeholder-private/proof_key"
chmod 0644 "${TEST_ROOT}/placeholder-private/proof_key"
if run_preflight "${TEST_ROOT}/placeholder-private" "${TEST_ROOT}/placeholder-private.out"; then
  fail runtime-placeholder-private
else
  pass runtime-placeholder-private
fi

prepare_valid_pair "${TEST_ROOT}/malformed-public"
printf 'not-a-public-key' >"${TEST_ROOT}/malformed-public/proof_key.pub"
chmod 0644 "${TEST_ROOT}/malformed-public/proof_key.pub"
if run_preflight "${TEST_ROOT}/malformed-public" "${TEST_ROOT}/malformed-public.out"; then
  fail runtime-malformed-public
else
  pass runtime-malformed-public
fi

prepare_valid_pair "${TEST_ROOT}/mismatch"
prepare_valid_pair "${TEST_ROOT}/other"
cp -- "${TEST_ROOT}/other/proof_key.pub" "${TEST_ROOT}/mismatch/proof_key.pub"
if run_preflight "${TEST_ROOT}/mismatch" "${TEST_ROOT}/mismatch.out"; then
  fail runtime-mismatched-pair
else
  pass runtime-mismatched-pair
fi

if run_preflight "${TEST_ROOT}/valid" "${TEST_ROOT}/reserved-option.out" '--o:security.capabilities=true'; then
  fail runtime-reserved-option
else
  pass runtime-reserved-option
fi

if run_preflight "${TEST_ROOT}/valid" "${TEST_ROOT}/reserved-base-option.out" '--o:child_root_path=/tmp/override'; then
  fail runtime-reserved-base-option
else
  pass runtime-reserved-base-option
fi

if run_preflight "${TEST_ROOT}/valid" "${TEST_ROOT}/duplicate-option.out" '--o:logging.level=warning --o:logging.level=debug'; then
  fail runtime-duplicate-option
else
  pass runtime-duplicate-option
fi

if run_preflight "${TEST_ROOT}/valid" "${TEST_ROOT}/non-option.out" '--version'; then
  fail runtime-non-option
else
  pass runtime-non-option
fi

control_params=$'--o:logging.level=warning\n--o:net.proto=IPv4'
if run_preflight "${TEST_ROOT}/valid" "${TEST_ROOT}/control-option.out" "$control_params"; then
  fail runtime-control-character
else
  pass runtime-control-character
fi

docker run -d \
  --name "$RUNTIME_CONTAINER" \
  --label "codex.collabora-preflight=${RUN_ID}" \
  --network none \
  --user 1001:1001 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 1g \
  --pids-limit 256 \
  --tmpfs /run:rw,noexec,nosuid,nodev,size=64m \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m \
  --tmpfs /var/tmp:rw,noexec,nosuid,nodev,size=128m \
  --mount "type=bind,source=${TEST_ROOT}/valid/proof_key,destination=/etc/coolwsd/proof_key,readonly" \
  --mount "type=bind,source=${TEST_ROOT}/valid/proof_key.pub,destination=/etc/coolwsd/proof_key.pub,readonly" \
  --env 'COLLABORA_EXTRA_PARAMS=--o:logging.level=warning' \
  "$TEST_IMAGE" >/dev/null

runtime_healthy=false
for _ in {1..20}; do
  runtime_status="$(docker inspect "$RUNTIME_CONTAINER" --format '{{.State.Status}}')"
  if docker exec "$RUNTIME_CONTAINER" /usr/bin/coolwsd --probe --disable-ssl >/dev/null 2>&1; then
    runtime_healthy=true
    break
  fi
  if [[ "$runtime_status" == exited || "$runtime_status" == dead ]]; then
    break
  fi
  sleep 2
done
if [[ "$runtime_healthy" == true ]]; then
  pass runtime-native-health-probe
else
  fail runtime-native-health-probe
fi

runtime_user="$(docker inspect "$RUNTIME_CONTAINER" --format '{{.Config.User}}')"
runtime_cap_drop="$(docker inspect "$RUNTIME_CONTAINER" --format '{{json .HostConfig.CapDrop}}')"
runtime_cap_add="$(docker inspect "$RUNTIME_CONTAINER" --format '{{json .HostConfig.CapAdd}}')"
runtime_security="$(docker inspect "$RUNTIME_CONTAINER" --format '{{json .HostConfig.SecurityOpt}}')"
if [[ "$runtime_user" == '1001:1001' \
  && "$runtime_cap_drop" == '["ALL"]' \
  && "$runtime_cap_add" == null \
  && "$runtime_security" == '["no-new-privileges:true"]' ]]; then
  pass runtime-linux-hardening-contract
else
  fail runtime-linux-hardening-contract
fi

docker top "$RUNTIME_CONTAINER" -eo pid,args >"${TEST_ROOT}/runtime.top"
runtime_pid_argv="$(sed -n '2p' "${TEST_ROOT}/runtime.top")"
effective_argv=true
for expected_option in \
  '/usr/bin/coolwsd' \
  '--o:logging.level=warning' \
  '--o:ssl.enable=false' \
  '--o:ssl.termination=true' \
  '--o:mount_jail_tree=false' \
  '--o:security.capabilities=false'; do
  if [[ "$runtime_pid_argv" != *"$expected_option"* ]]; then
    effective_argv=false
  fi
done
if [[ "$effective_argv" == true && "$runtime_pid_argv" != *'/usr/local/bin/collabora-preflight'* ]]; then
  pass runtime-effective-pid-argv
else
  fail runtime-effective-pid-argv
fi

if docker run --rm \
  --label "codex.collabora-preflight=${RUN_ID}" \
  --network "container:${RUNTIME_CONTAINER}" \
  --read-only \
  --user 65534:65534 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  "$GO_IMAGE" wget -qO- http://127.0.0.1:9980/hosting/discovery >"${TEST_ROOT}/discovery.xml" \
  && rg -q '<proof-key' "${TEST_ROOT}/discovery.xml"; then
  pass runtime-http-discovery-proof-key
else
  fail runtime-http-discovery-proof-key
fi

if docker run --rm \
  --label "codex.collabora-preflight=${RUN_ID}" \
  --network "container:${RUNTIME_CONTAINER}" \
  --read-only \
  --user 65534:65534 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  "$GO_IMAGE" wget -qO- http://127.0.0.1:9980/hosting/capabilities >"${TEST_ROOT}/capabilities.json" \
  && rg -q '"convert-to"' "${TEST_ROOT}/capabilities.json" \
  && rg -q '"productName"' "${TEST_ROOT}/capabilities.json"; then
  pass runtime-http-capabilities
else
  fail runtime-http-capabilities
fi

docker logs "$RUNTIME_CONTAINER" >"${TEST_ROOT}/runtime.out" 2>&1
if rg -q 'Could not open proof RSA key|Failed to spawn coolforkit|Setting ShutdownRequestFlag|Forced Exit' "${TEST_ROOT}/runtime.out"; then
  fail runtime-capability-and-key-errors
elif rg -q 'security\.capabilities: false' "${TEST_ROOT}/runtime.out" \
  && rg -q 'Disabling Bind-Mounting of jail contents' "${TEST_ROOT}/runtime.out" \
  && rg -q 'Launching forkit process: /usr/bin/coolforkit-ns .* --nocaps' "${TEST_ROOT}/runtime.out"; then
  pass runtime-capability-and-key-contract
else
  fail runtime-capability-and-key-contract
fi

private_marker="$(sed -n '2p' "${TEST_ROOT}/valid/proof_key")"
public_marker="$(sed -n '2p' "${TEST_ROOT}/valid/proof_key.pub")"
if rg -F -- "$private_marker" "$TEST_ROOT"/*.out >/dev/null \
  || rg -F -- "$public_marker" "$TEST_ROOT"/*.out >/dev/null \
  || rg -- 'BEGIN (RSA )?(PRIVATE|PUBLIC) KEY' "$TEST_ROOT"/*.out >/dev/null; then
  fail runtime-output-secret-leak
else
  pass runtime-output-secret-leak
fi

printf '\nCollæboræ wrapper tests: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
