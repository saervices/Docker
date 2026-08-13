#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
# shellcheck disable=SC2016 # Fixture scripts intentionally keep runtime variable references literal.
set -euo pipefail
umask 077

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_ROOT="$(/usr/bin/mktemp -d /tmp/run-logrotate-test.XXXXXX)"
HARNESS_ROOT="${TEST_ROOT}/repo"
HOST_ROOT="${TEST_ROOT}/host/etc/logrotate.d"
TOOL_ROOT="${TEST_ROOT}/tools"
TRACE_FILE="${TEST_ROOT}/trace.log"
OUTPUT_FILE="${TEST_ROOT}/output.log"
RUNNER="${HARNESS_ROOT}/run.sh"
APP_UID="$(id -u)"
APP_GID="$(id -g)"
APP_USER_NAME="$(/usr/bin/getent passwd "$APP_UID" | /usr/bin/cut -d: -f1)"
APP_GROUP_NAME="$(/usr/bin/getent group "$APP_GID" | /usr/bin/cut -d: -f1)"
PASS_COUNT=0

cleanup() {
  /usr/bin/chmod -R u+rwX -- "$TEST_ROOT" 2>/dev/null || true
  /usr/bin/rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "$OUTPUT_FILE" ]]; then
    /usr/bin/sed -n '1,200p' "$OUTPUT_FILE" >&2
  fi
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok %d - %s\n' "$PASS_COUNT" "$*"
}

write_lines() {
  local target="$1"
  shift
  printf '%s\n' "$@" > "$target"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  /usr/bin/grep -Fq -- "$expected" "$file" || \
    fail "Expected '$expected' in '$file'."
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if /usr/bin/grep -Fq -- "$unexpected" "$file"; then
    fail "Unexpected '$unexpected' in '$file'."
  fi
}

assert_empty_trace() {
  if [[ -s "$TRACE_FILE" ]]; then
    fail "Unexpected privileged or parser trace: $(/usr/bin/tr '\n' ' ' < "$TRACE_FILE")"
  fi
}

snapshot_tree() {
  local root="$1"
  local output="$2"
  local path=""

  if [[ ! -e "$root" && ! -L "$root" ]]; then
    printf 'absent\n' > "$output"
    return 0
  fi
  {
    /usr/bin/find -P "$root" -xdev -printf '%y\t%m\t%u\t%g\t%D:%i\t%p\t%l\n' | \
      /usr/bin/sort
    while IFS= read -r -d '' path; do
      /usr/bin/sha256sum -- "$path"
    done < <(/usr/bin/find -P "$root" -xdev -type f -print0 | /usr/bin/sort -z)
  } > "$output"
}

assert_tree_unchanged() {
  local root="$1"
  local before="$2"
  local after="${TEST_ROOT}/snapshot-after.$RANDOM.$RANDOM"

  snapshot_tree "$root" "$after"
  if ! /usr/bin/cmp -s -- "$before" "$after"; then
    /usr/bin/diff -u -- "$before" "$after" >&2 || true
    fail "Rejected case mutated '$root'."
  fi
  /usr/bin/rm -f -- "$after"
}

expect_rejected_without_mutation() {
  local label="$1"
  local project="$2"
  shift 2
  local app_before="${TEST_ROOT}/snapshot-app.$RANDOM.$RANDOM"
  local host_before="${TEST_ROOT}/snapshot-host.$RANDOM.$RANDOM"

  snapshot_tree "${HARNESS_ROOT}/${project}" "$app_before"
  snapshot_tree "$HOST_ROOT" "$host_before"
  reset_trace
  run_runner "$project" "$@"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "$label unexpectedly succeeded."
  assert_tree_unchanged "${HARNESS_ROOT}/${project}" "$app_before"
  assert_tree_unchanged "$HOST_ROOT" "$host_before"
  /usr/bin/rm -f -- "$app_before" "$host_before"
  pass "$label"
}

clear_fake_host() {
  /usr/bin/find -P "$HOST_ROOT" -mindepth 1 -maxdepth 1 -exec /usr/bin/rm -rf -- {} +
}

reset_case() {
  local project="$1"
  local compose_name="${2:-teststack}"

  clear_fake_host
  reset_project "$project" "$compose_name"
  reset_trace
}

set_yaml_expression() {
  local project="$1"
  local expression="$2"

  yq -i "$expression" "${HARNESS_ROOT}/${project}/docker-compose.main.yaml"
}

reject_yaml_case() {
  local label="$1"
  local expression="$2"
  local project="MatrixApp"

  reset_case "$project" matrixstack
  set_yaml_expression "$project" "$expression"
  expect_rejected_without_mutation "$label" "$project" --install-logrotate --dry-run
  assert_not_contains "$TRACE_FILE" 'sudo:'
}

run_runner() {
  local project="$1"
  shift
  : > "$OUTPUT_FILE"
  set +e
  PATH="${TOOL_ROOT}:/usr/bin:/bin" \
    TMPDIR="${TEST_ROOT}/tmp" \
    HOST_LOGROTATE_TEST_ROOT="$HOST_ROOT" \
    HOST_LOGROTATE_TEST_TRACE="$TRACE_FILE" \
    "$RUNNER" "$project" "$@" > "$OUTPUT_FILE" 2>&1
  RUN_STATUS=$?
  set -e
}

expect_success() {
  local label="$1"
  shift
  run_runner "$@"
  [[ "$RUN_STATUS" -eq 0 ]] || fail "$label returned $RUN_STATUS."
  pass "$label"
}

expect_failure() {
  local label="$1"
  shift
  run_runner "$@"
  [[ "$RUN_STATUS" -ne 0 ]] || fail "$label unexpectedly succeeded."
  pass "$label"
}

reset_trace() {
  : > "$TRACE_FILE"
}

write_compose() {
  local project_dir="$1"
  local project_name="${2:-teststack}"
  local signal_name="${3:-USR1}"
  local relative_path="${4:-appdata/logs/access.log}"
  local create_mode="${5:-0640}"
  local user_value="${6:-${APP_UID}:${APP_GID}}"

  write_lines "${project_dir}/docker-compose.main.yaml" \
    "name: ${project_name}" \
    'x-host-logrotate:' \
    '  version: 1' \
    '  entries:' \
    '    - id: access' \
    "      relative-path: ${relative_path}" \
    '      writer-service: app' \
    '      interval: daily' \
    '      max-size: 50M' \
    '      rotations: 14' \
    '      compress: true' \
    '      delay-compress: true' \
    "      create-mode: \"${create_mode}\"" \
    '      reopen:' \
    '        type: docker-signal' \
    '        service: app' \
    "        signal: ${signal_name}" \
    'services:' \
    '  app:' \
    '    image: alpine:latest' \
    "    container_name: ${project_name}-app" \
    "    user: \"${user_value}\"" \
    '    volumes:' \
    '      - type: bind' \
    '        source: ./appdata/logs' \
    '        target: /var/log/app'
}

reset_project() {
  local project_name="$1"
  local compose_name="${2:-teststack}"
  local project_dir="${HARNESS_ROOT}/${project_name}"

  /usr/bin/rm -rf -- "$project_dir"
  /usr/bin/mkdir -p -- "${project_dir}/appdata/logs"
  /usr/bin/chmod 0770 -- "${project_dir}/appdata/logs"
  write_lines "${project_dir}/.env" "APP_UID=${APP_UID}" "APP_GID=${APP_GID}"
  write_compose "$project_dir" "$compose_name"
}

find_target() {
  local project_name="${1:-teststack}"
  local -a targets=()
  mapfile -t targets < <(
    /usr/bin/find "$HOST_ROOT" -mindepth 1 -maxdepth 1 -type f \
      -name "saervices-docker-${project_name}-*" -print
  )
  [[ "${#targets[@]}" -eq 1 ]] || fail "Expected one host config for '$project_name'."
  printf '%s\n' "${targets[0]}"
}

/usr/bin/mkdir -p -- "$HARNESS_ROOT" "$HOST_ROOT" "$TOOL_ROOT" "${TEST_ROOT}/tmp"
/usr/bin/chmod 0755 -- "$HOST_ROOT"
/usr/bin/cp -- "${REPO_ROOT}/run.sh" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"

write_lines "${TOOL_ROOT}/stat" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'target="${!#}"' \
  'if [[ -n "${HOST_LOGROTATE_TEST_MASK_OWNER_DIR:-}" && "$target" == "$HOST_LOGROTATE_TEST_MASK_OWNER_DIR" && " $* " == *" %u:%g:%a:%d:%i "* ]]; then' \
  '  printf "0:0:%s:%s:%s\\n" "$(/usr/bin/stat -Lc '\''%a'\'' -- "$target")" "$(/usr/bin/stat -Lc '\''%d'\'' -- "$target")" "$(/usr/bin/stat -Lc '\''%i'\'' -- "$target")"' \
  '  exit 0' \
  'fi' \
  'special=false' \
  'case "$target" in /|/usr|/usr/bin|/usr/bin/docker|/usr/bin/gzip|/usr/local|/usr/local/bin|/usr/local/bin/docker) special=true ;; esac' \
  'if [[ -n "${HOST_LOGROTATE_TEST_TRUSTED_DOCKER:-}" && ( "$target" == "$HOST_LOGROTATE_TEST_TRUSTED_DOCKER" || "$HOST_LOGROTATE_TEST_TRUSTED_DOCKER" == "$target/"* ) ]]; then special=true; fi' \
  'if [[ "$target" == "$HOST_LOGROTATE_TEST_ROOT" || "$target" == "$HOST_LOGROTATE_TEST_ROOT/"* || "$HOST_LOGROTATE_TEST_ROOT" == "$target/"* ]]; then special=true; fi' \
  'if [[ "$special" == true ]]; then' \
  '  if [[ " $* " == *" %u:%g:%a:%h "* ]]; then' \
  '    if [[ -d "$target" ]]; then' \
  '      printf "0:0:755:1\\n"' \
  '    elif [[ "$target" == "$HOST_LOGROTATE_TEST_ROOT/"* ]]; then' \
  '      printf "0:0:%s:%s\\n" "$(/usr/bin/stat -Lc '\''%a'\'' -- "$target")" "$(/usr/bin/stat -Lc '\''%h'\'' -- "$target")"' \
  '    else' \
  '      printf "0:0:644:1\\n"' \
  '    fi' \
  '    exit 0' \
  '  fi' \
  '  if [[ " $* " == *" %u:%g:%a "* ]]; then' \
  '    if [[ -d "$target" ]]; then' \
  '      printf "0:0:755\\n"' \
  '    elif [[ "$target" == "$HOST_LOGROTATE_TEST_ROOT/"* ]]; then' \
  '      printf "0:0:%s\\n" "$(/usr/bin/stat -Lc '\''%a'\'' -- "$target")"' \
  '    else' \
  '      printf "0:0:644\\n"' \
  '    fi' \
  '    exit 0' \
  '  fi' \
  'fi' \
  'exec /usr/bin/stat "$@"'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/stat"

REAL_LOGROTATE_BIN=""
for REAL_LOGROTATE_CANDIDATE in /usr/sbin/logrotate /usr/bin/logrotate; do
  if [[ -f "$REAL_LOGROTATE_CANDIDATE" && -x "$REAL_LOGROTATE_CANDIDATE" ]]; then
    REAL_LOGROTATE_BIN="$REAL_LOGROTATE_CANDIDATE"
    break
  fi
done
[[ -n "$REAL_LOGROTATE_BIN" ]] || \
  fail 'No host logrotate binary found below /usr/sbin or /usr/bin; install logrotate first.'

write_lines "${TOOL_ROOT}/logrotate" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "logrotate-debug\\n" >> "$HOST_LOGROTATE_TEST_TRACE"' \
  'if [[ -n "${HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG:-}" ]]; then' \
  '  denial=true' \
  '  if [[ -n "${HOST_LOGROTATE_TEST_MASK_OWNER_DIR:-}" ]]; then' \
  '    mask_mode=$(/usr/bin/stat -Lc "%a" -- "$HOST_LOGROTATE_TEST_MASK_OWNER_DIR")' \
  '    if (( (8#$mask_mode & 8#010) != 0 )); then denial=false; fi' \
  '  fi' \
  '  if [[ "$denial" == true ]]; then' \
  '    printf "error: stat of %s failed: Permission denied\\n" "$HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG"' \
  '    exit 1' \
  '  fi' \
  'fi' \
  'if [[ -n "${HOST_LOGROTATE_TEST_SWAP_CONFIG_DIR:-}" && ! -e "$HOST_LOGROTATE_TEST_SWAP_CONFIG_DIR" ]]; then' \
  '  /usr/bin/mv -- "$HOST_LOGROTATE_TEST_ROOT" "${HOST_LOGROTATE_TEST_ROOT}.original"' \
  '  /usr/bin/mkdir -p -- "$HOST_LOGROTATE_TEST_ROOT"' \
  '  : > "$HOST_LOGROTATE_TEST_SWAP_CONFIG_DIR"' \
  'fi' \
  'if [[ -n "${HOST_LOGROTATE_TEST_SWAP_LOG_PARENT:-}" && ! -e "$HOST_LOGROTATE_TEST_SWAP_LOG_PARENT" ]]; then' \
  '  /usr/bin/mv -- "$HOST_LOGROTATE_TEST_LOG_PARENT" "${HOST_LOGROTATE_TEST_LOG_PARENT}.original"' \
  '  /usr/bin/mkdir -p -- "$HOST_LOGROTATE_TEST_LOG_PARENT"' \
  '  /usr/bin/chmod 0770 -- "$HOST_LOGROTATE_TEST_LOG_PARENT"' \
  '  : > "$HOST_LOGROTATE_TEST_SWAP_LOG_PARENT"' \
  'fi' \
  'if [[ "${HOST_LOGROTATE_TEST_FAIL_PARSER:-false}" == true ]]; then exit 71; fi' \
  "exec \"${REAL_LOGROTATE_BIN}\" \"\$@\""
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/logrotate"

write_lines "${TOOL_ROOT}/sudo" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'command_path="$1"' \
  'shift' \
  'printf "sudo:%s\\n" "${command_path##*/}" >> "$HOST_LOGROTATE_TEST_TRACE"' \
  'if [[ -n "${HOST_LOGROTATE_TEST_SWAP_SOURCE:-}" && ! -e "$HOST_LOGROTATE_TEST_SWAP_SOURCE" ]]; then' \
  '  source_file=$(/usr/bin/find "${TMPDIR}" -type f -name host-logrotate.conf -print -quit)' \
  '  if [[ -n "$source_file" ]]; then' \
  '    /usr/bin/rm -- "$source_file"' \
  '    /usr/bin/ln -s -- "$HOST_LOGROTATE_TEST_SECRET" "$source_file"' \
  '    : > "$HOST_LOGROTATE_TEST_SWAP_SOURCE"' \
  '  fi' \
  'fi' \
  'if [[ "${HOST_LOGROTATE_TEST_FAIL_COMMAND:-}" == "${command_path##*/}" ]]; then exit 73; fi' \
  'if [[ "$command_path" == /usr/bin/mv && -n "${HOST_LOGROTATE_TEST_REPLACE_PRIVILEGED_TMP:-}" && ! -e "$HOST_LOGROTATE_TEST_REPLACE_PRIVILEGED_TMP" ]]; then' \
  '  source_arg="${@: -2:1}"' \
  '  if [[ "$source_arg" == "$HOST_LOGROTATE_TEST_ROOT/".saervices-docker-*.tmp.?????? ]]; then' \
  '    /usr/bin/mv -- "$source_arg" "${source_arg}.process-owned"' \
  '    printf "FOREIGN_PRIVILEGED_TEMP_SENTINEL\\n" > "$source_arg"' \
  '    /usr/bin/chmod 0644 -- "$source_arg"' \
  '    printf "%s\\n" "$source_arg" > "$HOST_LOGROTATE_TEST_REPLACE_PRIVILEGED_TMP"' \
  '    exit 74' \
  '  fi' \
  'fi' \
  'if [[ "$command_path" == /usr/bin/mv && -n "${HOST_LOGROTATE_TEST_SIGNAL_MARKER:-}" && ! -e "$HOST_LOGROTATE_TEST_SIGNAL_MARKER" ]]; then' \
  '  /usr/bin/mv "$@"' \
  '  : > "$HOST_LOGROTATE_TEST_SIGNAL_MARKER"' \
  '  /usr/bin/kill -s "${HOST_LOGROTATE_TEST_SIGNAL:-TERM}" "$PPID"' \
  '  /usr/bin/sleep 0.1' \
  '  exit 0' \
  'fi' \
  'if [[ "$command_path" == /usr/bin/mv && -n "${HOST_LOGROTATE_TEST_CORRUPT_MARKER:-}" && ! -e "$HOST_LOGROTATE_TEST_CORRUPT_MARKER" ]]; then' \
  '  /usr/bin/mv "$@"' \
  '  destination="${!#}"' \
  '  printf "tampered-after-publish\\n" >> "$destination"' \
  '  : > "$HOST_LOGROTATE_TEST_CORRUPT_MARKER"' \
  '  exit 0' \
  'fi' \
  'exec "$command_path" "$@"'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/sudo"

/usr/bin/sed -i \
  -e "s|readonly HOST_LOGROTATE_DIR=\"/etc/logrotate.d\"|readonly HOST_LOGROTATE_DIR=\"${HOST_ROOT}\"|" \
  -e "s|readonly HOST_LOGROTATE_STAT_BIN=\"/usr/bin/stat\"|readonly HOST_LOGROTATE_STAT_BIN=\"${TOOL_ROOT}/stat\"|" \
  -e "s|readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(/usr/sbin/logrotate /usr/bin/logrotate)|readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(\"${TOOL_ROOT}/logrotate\")|" \
  -e "s|readonly HOST_LOGROTATE_SUDO_BIN=\"/usr/bin/sudo\"|readonly HOST_LOGROTATE_SUDO_BIN=\"${TOOL_ROOT}/sudo\"|" \
  "$RUNNER"
/usr/bin/grep -Fq "HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(\"${TOOL_ROOT}/logrotate\")" "$RUNNER" || \
  fail 'Logrotate candidate substitution did not match the runner source.'

bash -n "$RUNNER"

TEMPLATE_BLOCK="${TEST_ROOT}/app-template-host-logrotate.yaml"
/usr/bin/sed -n '/^# x-host-logrotate:/,/^x-required-services:/p' \
  "${REPO_ROOT}/app_template/docker-compose.app.yaml" | \
  /usr/bin/sed '$d; s/^# //' > "$TEMPLATE_BLOCK"
yq -e '
  ."x-host-logrotate".version == 1 and
  (."x-host-logrotate".entries | length == 1) and
  ((."x-host-logrotate".entries[0] | keys | join(",")) ==
    "id,relative-path,writer-service,interval,max-size,rotations,compress,delay-compress,create-mode,reopen") and
  ((."x-host-logrotate".entries[0].reopen | keys | join(",")) == "type,service,signal")
' "$TEMPLATE_BLOCK" >/dev/null || fail 'app_template host-logrotate block is incomplete.'
TEMPLATE_SECRET_LINE=$(/usr/bin/grep -n '^x-secrets-use-app-gid:' \
  "${REPO_ROOT}/app_template/docker-compose.app.yaml" | /usr/bin/cut -d: -f1)
TEMPLATE_LOGROTATE_LINE=$(/usr/bin/grep -n '^# x-host-logrotate:' \
  "${REPO_ROOT}/app_template/docker-compose.app.yaml" | /usr/bin/cut -d: -f1)
TEMPLATE_REQUIRED_LINE=$(/usr/bin/grep -n '^x-required-services:' \
  "${REPO_ROOT}/app_template/docker-compose.app.yaml" | /usr/bin/cut -d: -f1)
[[ "$TEMPLATE_SECRET_LINE" -lt "$TEMPLATE_LOGROTATE_LINE" && \
   "$TEMPLATE_LOGROTATE_LINE" -lt "$TEMPLATE_REQUIRED_LINE" ]] || \
  fail 'app_template host-logrotate block is not in the canonical metadata position.'
if yq -e 'has("x-host-logrotate")' \
    "${REPO_ROOT}/app_template/docker-compose.app.yaml" &>/dev/null; then
  fail 'app_template unexpectedly activates host-logrotate metadata.'
fi
pass 'app_template keeps one complete canonical commented opt-in block'

reset_case NoOpt noopt
set_yaml_expression NoOpt 'del(."x-host-logrotate")'
UPDATE_DOCKER_TRACE="${TEST_ROOT}/ordinary-update-docker.trace"
write_lines "${TOOL_ROOT}/docker" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\\n" "$*" >> "$HOST_LOGROTATE_UPDATE_DOCKER_TRACE"' \
  'case " $* " in' \
  '  *" compose version "*) exit 0 ;;' \
  '  *" config --format json "*) /usr/bin/jq -nc '\''{name:"noopt",services:{app:{image:"alpine:latest"}}}'\''; exit 0 ;;' \
  '  *" ps --all --quiet "*) exit 0 ;;' \
  '  *" image inspect "*) echo sha256:fixture; exit 0 ;;' \
  'esac' \
  'exit 64'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/docker"
ORDINARY_HOST_BEFORE="${TEST_ROOT}/ordinary-host.before"
snapshot_tree "$HOST_ROOT" "$ORDINARY_HOST_BEFORE"
: > "$TRACE_FILE"
: > "$OUTPUT_FILE"
set +e
PATH="${TOOL_ROOT}:/usr/bin:/bin" \
  TMPDIR="${TEST_ROOT}/tmp" \
  HOST_LOGROTATE_TEST_ROOT="$HOST_ROOT" \
  HOST_LOGROTATE_TEST_TRACE="$TRACE_FILE" \
  HOST_LOGROTATE_UPDATE_DOCKER_TRACE="$UPDATE_DOCKER_TRACE" \
  "$RUNNER" NoOpt --update --dry-run > "$OUTPUT_FILE" 2>&1
RUN_STATUS=$?
set -e
[[ "$RUN_STATUS" -eq 0 ]] || fail "Ordinary no-opt-in update returned $RUN_STATUS."
assert_tree_unchanged "$HOST_ROOT" "$ORDINARY_HOST_BEFORE"
assert_empty_trace
assert_not_contains "$UPDATE_DOCKER_TRACE" 'kill --signal='
/usr/bin/rm -- "${TOOL_ROOT}/docker"
pass 'Ordinary no-opt-in update never inspects or mutates host logrotate state'

MERGE_REMOTE="${TEST_ROOT}/merge-remote"
MERGE_PROJECT="${HARNESS_ROOT}/Traefik"
/usr/bin/mkdir -p -- "${MERGE_REMOTE}/templates" "${MERGE_PROJECT}/appdata/logs"
/usr/bin/chmod 0770 -- "${MERGE_PROJECT}/appdata/logs"
write_lines "${MERGE_REMOTE}/templates/.gitkeep" ''
write_lines "${MERGE_PROJECT}/docker-compose.app.yaml" \
  '---' \
  'x-secrets-use-app-gid: false' \
  'x-host-logrotate:' \
  '  version: 1' \
  '  entries:' \
  '    - id: access' \
  '      relative-path: appdata/logs/access.log' \
  '      writer-service: app' \
  '      interval: daily' \
  '      max-size: 50M' \
  '      rotations: 14' \
  '      compress: true' \
  '      delay-compress: true' \
  '      create-mode: "0640"' \
  '      reopen:' \
  '        type: docker-signal' \
  '        service: app' \
  '        signal: USR1' \
  'x-required-services: []' \
  'services:' \
  '  app:' \
  '    image: ${APP_IMAGE:?Image required}' \
  '    container_name: ${APP_NAME:?App name required}' \
  '    user: "${APP_UID:-1000}:${APP_GID:-1000}"' \
  '    volumes:' \
  '      - type: bind' \
  '        source: ./appdata/logs' \
  '        target: /var/log/app'
write_lines "${MERGE_PROJECT}/app.env" \
  'APP_IMAGE=alpine:latest' \
  'APP_NAME=traefik-logrotate-merge-test' \
  "APP_UID=${APP_UID}" \
  "APP_GID=${APP_GID}"
command git -C "$MERGE_REMOTE" init --quiet --initial-branch=main
command git -C "$MERGE_REMOTE" config user.name 'Host Logrotate Test'
command git -C "$MERGE_REMOTE" config user.email 'host-logrotate@example.invalid'
command git -C "$MERGE_REMOTE" add templates
command git -C "$MERGE_REMOTE" commit --quiet -m fixture
RUNNER_BEFORE_MERGE="${TEST_ROOT}/runner-before-merge"
/usr/bin/cp -- "$RUNNER" "$RUNNER_BEFORE_MERGE"
/usr/bin/sed -i -E "s|^readonly REPO_URL=.*|readonly REPO_URL=\"${MERGE_REMOTE}\"|" "$RUNNER"
CURRENT_YQ_TAG=$(yq --version | /usr/bin/sed -nE 's/.*version (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
[[ "$CURRENT_YQ_TAG" =~ ^v4\.[0-9]+\.[0-9]+$ ]] || fail 'Could not derive local yq v4 version.'
CURRENT_YQ_BIN=$(command -v yq)
/usr/bin/ln -s -- "$CURRENT_YQ_BIN" "${TOOL_ROOT}/yq"
write_lines "${TOOL_ROOT}/curl" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "https://github.com/mikefarah/yq/releases/tag/%s" "${YQ_TEST_TAG:?}"'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/curl"
: > "$OUTPUT_FILE"
set +e
YQ_TEST_TAG="$CURRENT_YQ_TAG" PATH="${TOOL_ROOT}:/usr/bin:/bin" \
  TMPDIR="${TEST_ROOT}/tmp" HOST_LOGROTATE_TEST_ROOT="$HOST_ROOT" \
  HOST_LOGROTATE_TEST_TRACE="$TRACE_FILE" \
  "$RUNNER" Traefik --force --skip-permissions > "$OUTPUT_FILE" 2>&1
RUN_STATUS=$?
set -e
/usr/bin/cp -- "$RUNNER_BEFORE_MERGE" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"
/usr/bin/rm -- "${TOOL_ROOT}/curl"
[[ "$RUN_STATUS" -eq 0 ]] || fail "Real local-snapshot merge returned $RUN_STATUS."
yq -e '
  ."x-host-logrotate".version == 1 and
  (."x-host-logrotate".entries | length == 1) and
  (has("x-required-services") | not) and
  (has("x-secrets-use-app-gid") | not) and
  (has("x-secret-generation-exclusions") | not)
' "${MERGE_PROJECT}/docker-compose.main.yaml" >/dev/null || \
  fail 'Real merge did not preserve exactly the runtime x-host-logrotate metadata.'
yq -o=json '.' "${MERGE_PROJECT}/docker-compose.main.yaml" | \
  /usr/bin/jq -e '[keys[] | select(startswith("x-"))] == ["x-host-logrotate"]' \
    >/dev/null || fail 'Real merge retained build-time or unknown x-* metadata.'
/usr/bin/docker compose --project-directory "$MERGE_PROJECT" \
  --env-file "${MERGE_PROJECT}/.env" -f "${MERGE_PROJECT}/docker-compose.main.yaml" \
  config --format json >/dev/null || fail 'Real merged Compose failed Docker Compose rendering.'
reset_trace
expect_success 'Real merged Traefik metadata passes dedicated dry-run' \
  Traefik --install-logrotate --dry-run
assert_contains "$OUTPUT_FILE" 'kill --signal=USR1'
assert_not_contains "$OUTPUT_FILE" 'copytruncate'
assert_not_contains "$TRACE_FILE" 'sudo:'
pass 'Root App to local Git snapshot to force merge preserves only runtime metadata'

MERGE_SWAP_PROJECT="${HARNESS_ROOT}/MergeSwap"
MERGE_SWAP_SOURCE="${MERGE_SWAP_PROJECT}/docker-compose.app.yaml"
MERGE_SWAP_REPLACEMENT="${TEST_ROOT}/merge-swap.replacement.yaml"
MERGE_SWAP_ORIGINAL="${TEST_ROOT}/merge-swap.original.yaml"
MERGE_SWAP_MARKER="${TEST_ROOT}/merge-swap.triggered"
/usr/bin/mkdir -p -- "${MERGE_SWAP_PROJECT}/appdata/logs"
/usr/bin/chmod 0770 -- "${MERGE_SWAP_PROJECT}/appdata/logs"
write_lines "$MERGE_SWAP_SOURCE" \
  '---' \
  'x-host-logrotate:' \
  '  version: 1' \
  '  entries:' \
  '    - id: access' \
  '      relative-path: appdata/logs/access.log' \
  '      writer-service: app' \
  '      interval: daily' \
  '      max-size: 50M' \
  '      rotations: 14' \
  '      compress: true' \
  '      delay-compress: true' \
  '      create-mode: "0640"' \
  '      reopen:' \
  '        type: docker-signal' \
  '        service: app' \
  '        signal: USR1' \
  'x-required-services: []' \
  'services:' \
  '  app:' \
  '    image: alpine:latest' \
  '    container_name: merge-swap-app' \
  "    user: \"${APP_UID}:${APP_GID}\"" \
  '    environment:' \
  '      SOURCE_REVISION: old' \
  '    volumes:' \
  '      - type: bind' \
  '        source: ./appdata/logs' \
  '        target: /var/log/app'
write_lines "$MERGE_SWAP_REPLACEMENT" \
  '---' \
  'x-host-logrotate:' \
  '  version: 1' \
  '  entries:' \
  '    - id: access' \
  '      relative-path: appdata/logs/access.log' \
  '      writer-service: app' \
  '      interval: daily' \
  '      max-size: 75M' \
  '      rotations: 14' \
  '      compress: true' \
  '      delay-compress: true' \
  '      create-mode: "0640"' \
  '      reopen:' \
  '        type: docker-signal' \
  '        service: app' \
  '        signal: USR1' \
  'x-required-services: []' \
  'services:' \
  '  app:' \
  '    image: busybox:latest' \
  '    container_name: merge-swap-app' \
  "    user: \"${APP_UID}:${APP_GID}\"" \
  '    environment:' \
  '      SOURCE_REVISION: new' \
  '    volumes:' \
  '      - type: bind' \
  '        source: ./appdata/logs' \
  '        target: /var/log/app'
write_lines "${MERGE_SWAP_PROJECT}/app.env" \
  "APP_UID=${APP_UID}" \
  "APP_GID=${APP_GID}"
write_lines "${MERGE_SWAP_PROJECT}/.env" \
  'PRESERVED_ENV=before-source-swap'
write_lines "${MERGE_SWAP_PROJECT}/docker-compose.main.yaml" \
  '---' \
  'services:' \
  '  preserved:' \
  '    image: alpine:latest' \
  '    environment:' \
  '      DEPLOYMENT_REVISION: preserved'
MERGE_SWAP_HOST_BEFORE="${TEST_ROOT}/merge-swap.host.before"
snapshot_tree "$HOST_ROOT" "$MERGE_SWAP_HOST_BEFORE"

MERGE_SWAP_RUNNER_BACKUP="${TEST_ROOT}/runner-before-source-swap"
/usr/bin/cp -- "$RUNNER" "$MERGE_SWAP_RUNNER_BACKUP"
/usr/bin/sed -i -E "s|^readonly REPO_URL=.*|readonly REPO_URL=\"${MERGE_REMOTE}\"|" "$RUNNER"
/usr/bin/rm -- "${TOOL_ROOT}/yq"
write_lines "${TOOL_ROOT}/yq" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  "readonly REAL_YQ_BIN=\"${CURRENT_YQ_BIN}\"" \
  'matched_raw_snapshot=false' \
  'for argument in "$@"; do' \
  '  if [[ "$argument" == */process-merge-source-raw.*.yaml ]]; then matched_raw_snapshot=true; fi' \
  'done' \
  'set +e' \
  '"$REAL_YQ_BIN" "$@"' \
  'status=$?' \
  'set -e' \
  'if [[ "$status" -eq 0 && "$matched_raw_snapshot" == true && ! -e "$HOST_LOGROTATE_MERGE_SWAP_MARKER" ]]; then' \
  '  /usr/bin/mv -- "$HOST_LOGROTATE_MERGE_SWAP_SOURCE" "$HOST_LOGROTATE_MERGE_SWAP_ORIGINAL"' \
  '  /usr/bin/mv -- "$HOST_LOGROTATE_MERGE_SWAP_REPLACEMENT" "$HOST_LOGROTATE_MERGE_SWAP_SOURCE"' \
  '  : > "$HOST_LOGROTATE_MERGE_SWAP_MARKER"' \
  'fi' \
  'exit "$status"'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/yq"
write_lines "${TOOL_ROOT}/curl" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "https://github.com/mikefarah/yq/releases/tag/%s" "${YQ_TEST_TAG:?}"'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/curl"
export HOST_LOGROTATE_MERGE_SWAP_SOURCE="$MERGE_SWAP_SOURCE"
export HOST_LOGROTATE_MERGE_SWAP_REPLACEMENT="$MERGE_SWAP_REPLACEMENT"
export HOST_LOGROTATE_MERGE_SWAP_ORIGINAL="$MERGE_SWAP_ORIGINAL"
export HOST_LOGROTATE_MERGE_SWAP_MARKER="$MERGE_SWAP_MARKER"
export YQ_TEST_TAG="$CURRENT_YQ_TAG"
reset_trace
run_runner MergeSwap --force --skip-permissions
unset HOST_LOGROTATE_MERGE_SWAP_SOURCE HOST_LOGROTATE_MERGE_SWAP_REPLACEMENT \
  HOST_LOGROTATE_MERGE_SWAP_ORIGINAL HOST_LOGROTATE_MERGE_SWAP_MARKER YQ_TEST_TAG
/usr/bin/cp -- "$MERGE_SWAP_RUNNER_BACKUP" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"
/usr/bin/rm -- "${TOOL_ROOT}/curl" "${TOOL_ROOT}/yq"
/usr/bin/ln -s -- "$CURRENT_YQ_BIN" "${TOOL_ROOT}/yq"
[[ "$RUN_STATUS" -eq 0 ]] || fail "Coherent snapshot merge returned $RUN_STATUS after live-source replacement."
[[ -f "$MERGE_SWAP_MARKER" && -f "$MERGE_SWAP_ORIGINAL" ]] || \
  fail 'Compose source replacement hook did not run deterministically.'
assert_contains "$MERGE_SWAP_SOURCE" 'max-size: 75M'
assert_contains "$MERGE_SWAP_SOURCE" 'SOURCE_REVISION: new'
yq -e '
  ."x-host-logrotate".entries[0]."max-size" == "50M" and
  .services.app.image == "alpine:latest" and
  .services.app.environment.SOURCE_REVISION == "old"
' "${MERGE_SWAP_PROJECT}/docker-compose.main.yaml" >/dev/null || \
  fail 'Compose merge did not publish one coherent snapshot revision.'
assert_not_contains "${MERGE_SWAP_PROJECT}/docker-compose.main.yaml" 'max-size: 75M'
assert_not_contains "${MERGE_SWAP_PROJECT}/docker-compose.main.yaml" 'busybox:latest'
assert_not_contains "${MERGE_SWAP_PROJECT}/docker-compose.main.yaml" 'SOURCE_REVISION: new'
assert_tree_unchanged "$HOST_ROOT" "$MERGE_SWAP_HOST_BEFORE"
assert_empty_trace
pass 'Compose source replacement publishes one coherent private-snapshot revision'

SYNTAX_ROOT="${TEST_ROOT}/syntax-root-\""$'\n''daily {'
SYNTAX_PROJECT="${SYNTAX_ROOT}/SyntaxApp"
SYNTAX_RUNNER="${SYNTAX_ROOT}/run.sh"
/usr/bin/mkdir -p -- "${SYNTAX_PROJECT}/appdata/logs"
/usr/bin/chmod 0770 -- "${SYNTAX_PROJECT}/appdata/logs"
/usr/bin/cp -- "$RUNNER" "$SYNTAX_RUNNER"
/usr/bin/chmod 0755 -- "$SYNTAX_RUNNER"
write_lines "${SYNTAX_PROJECT}/.env" \
  "APP_UID=${APP_UID}" \
  "APP_GID=${APP_GID}"
write_compose "$SYNTAX_PROJECT" syntaxstack
SYNTAX_APP_BEFORE="${TEST_ROOT}/syntax-root-app.before"
SYNTAX_HOST_BEFORE="${TEST_ROOT}/syntax-root-host.before"
snapshot_tree "$SYNTAX_PROJECT" "$SYNTAX_APP_BEFORE"
snapshot_tree "$HOST_ROOT" "$SYNTAX_HOST_BEFORE"
reset_trace
: > "$OUTPUT_FILE"
set +e
PATH="${TOOL_ROOT}:/usr/bin:/bin" \
  TMPDIR="${TEST_ROOT}/tmp" \
  HOST_LOGROTATE_TEST_ROOT="$HOST_ROOT" \
  HOST_LOGROTATE_TEST_TRACE="$TRACE_FILE" \
  "$SYNTAX_RUNNER" SyntaxApp --install-logrotate --dry-run > "$OUTPUT_FILE" 2>&1
RUN_STATUS=$?
set -e
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Logrotate-syntax project root unexpectedly validated.'
assert_tree_unchanged "$SYNTAX_PROJECT" "$SYNTAX_APP_BEFORE"
assert_tree_unchanged "$HOST_ROOT" "$SYNTAX_HOST_BEFORE"
assert_empty_trace
assert_not_contains "$OUTPUT_FILE" 'BEGIN GENERATED HOST LOGROTATE CONFIG'
pass 'Quote and line-feed project root fails before parser or host action'

reset_project TestApp

reset_trace
expect_failure 'Mutuælly exclusive host actions fail' TestApp --check-logrotate --install-logrotate
assert_empty_trace

reset_trace
expect_success 'Install dry-run validates without mutation' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ ! -e "${HARNESS_ROOT}/TestApp/.run.conf" ]] || fail 'Dry-run created .run.conf.'
assert_contains "$OUTPUT_FILE" 'BEGIN GENERATED HOST LOGROTATE CONFIG'
assert_contains "$OUTPUT_FILE" "su ${APP_USER_NAME} ${APP_GROUP_NAME}"
assert_contains "$OUTPUT_FILE" "create 0640 ${APP_USER_NAME} ${APP_GROUP_NAME}"
assert_not_contains "$OUTPUT_FILE" "su ${APP_UID} ${APP_GID}"
assert_contains "$OUTPUT_FILE" 'com.docker.compose.project'
assert_contains "$OUTPUT_FILE" 'com.docker.compose.service'
assert_contains "$OUTPUT_FILE" 'kill --signal=USR1'
assert_not_contains "$OUTPUT_FILE" 'copytruncate'

LEGACY_FILE="${HOST_ROOT}/traefik-access"
write_lines "$LEGACY_FILE" \
  "\"${HARNESS_ROOT}/TestApp/appdata/logs/access.log\" {" \
  '    daily' \
  '    rotate 7' \
  '    missingok' \
  '}'
/usr/bin/chmod 0644 -- "$LEGACY_FILE"
LEGACY_HASH="$(/usr/bin/sha256sum -- "$LEGACY_FILE")"
reset_trace
expect_failure 'Check rejects legæcy peer rule read-only' TestApp --check-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'
assert_contains "$OUTPUT_FILE" "$LEGACY_FILE"
[[ ! -e "${HARNESS_ROOT}/TestApp/.run.conf" ]] || fail 'Conflicting check created .run.conf.'

reset_trace
expect_failure 'Legæcy peer rule for exact log path fails closed' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'
assert_contains "$OUTPUT_FILE" "$LEGACY_FILE"
[[ "$(/usr/bin/sha256sum -- "$LEGACY_FILE")" == "$LEGACY_HASH" ]] || \
  fail 'Legæcy peer rule was modified.'

reset_trace
expect_failure 'Real install rejects legæcy peer before sudo' TestApp --install-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'
assert_contains "$OUTPUT_FILE" "$LEGACY_FILE"
[[ "$(/usr/bin/sha256sum -- "$LEGACY_FILE")" == "$LEGACY_HASH" ]] || \
  fail 'Real rejected install modified legæcy peer.'
[[ -z "$(/usr/bin/find "$HOST_ROOT" -maxdepth 1 -type f -name 'saervices-docker-*' -print -quit)" ]] || \
  fail 'Conflicting install published a managed target.'
/usr/bin/rm -- "$LEGACY_FILE"

reset_project TestApp
DOT_PEER="${HOST_ROOT}/traefik.access"
write_lines "$DOT_PEER" \
  "${HARNESS_ROOT}/TestApp/appdata/logs/access.log {" \
  '    daily' \
  '    missingok' \
  '}'
/usr/bin/chmod 0644 -- "$DOT_PEER"
reset_trace
expect_failure 'Peer filename with dot cannot bypass conflict scan' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'
assert_contains "$OUTPUT_FILE" "$DOT_PEER"
/usr/bin/rm -- "$DOT_PEER"

UNSAFE_PEER="${HOST_ROOT}/unsafe-peer"
/usr/bin/ln -s -- "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml" "$UNSAFE_PEER"
reset_trace
expect_failure 'Symlinked peer fails closed without following' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ -L "$UNSAFE_PEER" ]] || fail 'Unsafe peer was mutated.'
/usr/bin/rm -- "$UNSAFE_PEER"

reset_trace
expect_failure 'First-use check reports missing config read-only' TestApp --check-logrotate
[[ ! -e "${HARNESS_ROOT}/TestApp/.run.conf" ]] || fail 'Check created .run.conf.'
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_trace
expect_success 'Atomic install publishes managed config' TestApp --install-logrotate
TARGET_FILE="$(find_target)"
[[ -f "$TARGET_FILE" && ! -L "$TARGET_FILE" ]] || fail 'Managed target is not a regular file.'
assert_contains "$TARGET_FILE" '# Managed-content-sha256:'
assert_contains "$TARGET_FILE" '# Project-root-sha256:'
assert_contains "$TARGET_FILE" 'noallowhardlink'
assert_not_contains "$TARGET_FILE" 'copytruncate'
FIRST_LOGROTATE_LINE="$(/usr/bin/grep -n '^logrotate-debug$' "$TRACE_FILE" | /usr/bin/head -n1 | /usr/bin/cut -d: -f1)"
FIRST_SUDO_LINE="$(/usr/bin/grep -n '^sudo:' "$TRACE_FILE" | /usr/bin/head -n1 | /usr/bin/cut -d: -f1)"
[[ "$FIRST_LOGROTATE_LINE" -lt "$FIRST_SUDO_LINE" ]] || fail 'sudo ran before logrotate --debug.'
reset_trace
expect_success 'Idempotent install performs no root write' TestApp --install-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_trace
expect_success 'Check proves exact installed state' TestApp --check-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'

/usr/bin/cp -- "$TARGET_FILE" "${TEST_ROOT}/valid-target.snapshot"
printf 'manual-tamper\n' >> "$TARGET_FILE"
reset_trace
expect_failure 'Tampered managed config fails closed' TestApp --install-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'
/usr/bin/cp -- "${TEST_ROOT}/valid-target.snapshot" "$TARGET_FILE"

/usr/bin/sed -i 's/max-size: 50M/max-size: 60M/' "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_success 'Legitimate managed update uses atomic rollback staging' TestApp --install-logrotate
assert_contains "$TARGET_FILE" 'maxsize 60M'
assert_contains "$TRACE_FILE" 'sudo:tee'

UPDATED_HASH="$(/usr/bin/sha256sum -- "$TARGET_FILE")"
/usr/bin/sed -i 's/max-size: 60M/max-size: 65M/' "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
SIGNAL_MARKER="${TEST_ROOT}/signal-once.marker"
export HOST_LOGROTATE_TEST_SIGNAL_MARKER="$SIGNAL_MARKER"
export HOST_LOGROTATE_TEST_SIGNAL=TERM
run_runner TestApp --install-logrotate
unset HOST_LOGROTATE_TEST_SIGNAL_MARKER HOST_LOGROTATE_TEST_SIGNAL
[[ "$RUN_STATUS" -eq 143 ]] || fail "Interrupted publication returned $RUN_STATUS instead of 143."
[[ "$(/usr/bin/sha256sum -- "$TARGET_FILE")" == "$UPDATED_HASH" ]] || \
  fail 'TERM publication window did not restore previous bytes.'
if /usr/bin/find "$HOST_ROOT" -mindepth 1 -maxdepth 1 -type f \
    \( -name '.*.tmp.*' -o -name '.*.rollback.*' \) -print -quit | /usr/bin/grep -q .; then
  fail 'TERM publication window left privileged staging behind.'
fi
pass 'TERM during publication rolls back before deferred exit'

/usr/bin/sed -i 's/max-size: 65M/max-size: 70M/' "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
export HOST_LOGROTATE_TEST_FAIL_COMMAND=mv
expect_failure 'Failed publication preserves previous target' TestApp --install-logrotate
unset HOST_LOGROTATE_TEST_FAIL_COMMAND
[[ "$(/usr/bin/sha256sum -- "$TARGET_FILE")" == "$UPDATED_HASH" ]] || fail 'Failed mv changed the previous target.'

reset_trace
CORRUPT_MARKER="${TEST_ROOT}/corrupt-once.marker"
export HOST_LOGROTATE_TEST_CORRUPT_MARKER="$CORRUPT_MARKER"
expect_failure 'Post-publication corruption triggers exact rollback' TestApp --install-logrotate
unset HOST_LOGROTATE_TEST_CORRUPT_MARKER
[[ "$(/usr/bin/sha256sum -- "$TARGET_FILE")" == "$UPDATED_HASH" ]] || fail 'Post-publication rollback did not restore previous bytes.'

/usr/bin/sed -i 's/max-size: 70M/max-size: 60M/' "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_success 'Remove dry-run preserves exact target' TestApp --remove-logrotate --dry-run
[[ -f "$TARGET_FILE" ]] || fail 'Remove dry-run removed target.'
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_trace
expect_success 'Exact managed remove succeeds' TestApp --remove-logrotate
[[ ! -e "$TARGET_FILE" && ! -L "$TARGET_FILE" ]] || fail 'Managed target remains after remove.'

reset_trace
expect_success 'Missing managed remove is idempotent' TestApp --remove-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'

write_lines "$TARGET_FILE" 'foreign-config'
/usr/bin/chmod 0644 -- "$TARGET_FILE"
reset_trace
expect_failure 'Foreign target is never overwritten' TestApp --install-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ "$(/usr/bin/sed -n '1p' "$TARGET_FILE")" == foreign-config ]] || fail 'Foreign target changed.'
/usr/bin/rm -- "$TARGET_FILE"

write_compose "${HARNESS_ROOT}/TestApp" teststack TERM
reset_trace
expect_failure 'Disallowed signal fails before sudo' TestApp --install-logrotate --dry-run
assert_empty_trace

write_compose "${HARNESS_ROOT}/TestApp" teststack USR1 appdata/logs/access.log 0660
reset_trace
expect_failure 'Over-permissive create mode fails' TestApp --install-logrotate --dry-run
assert_empty_trace

write_compose "${HARNESS_ROOT}/TestApp" teststack USR1 ../access.log
reset_trace
expect_failure 'Traversal log path fails' TestApp --install-logrotate --dry-run
assert_empty_trace

/usr/bin/mkdir -p -- "${HARNESS_ROOT}/TestApp/appdata/other"
/usr/bin/chmod 0770 -- "${HARNESS_ROOT}/TestApp/appdata/other"
write_compose "${HARNESS_ROOT}/TestApp" teststack USR1 appdata/other/access.log
reset_trace
expect_failure 'Log outside writer bind fails' TestApp --install-logrotate --dry-run
assert_empty_trace

write_compose "${HARNESS_ROOT}/TestApp" teststack USR1 appdata/logs/access.log 0640 root
reset_trace
expect_failure 'Nonnumeric writer identity fails' TestApp --install-logrotate --dry-run
assert_empty_trace

write_compose "${HARNESS_ROOT}/TestApp"
printf 'existing\n' > "${HARNESS_ROOT}/TestApp/appdata/logs/access.log"
/usr/bin/chmod 0644 -- "${HARNESS_ROOT}/TestApp/appdata/logs/access.log"
reset_trace
expect_failure 'World-readable existing access log fails' TestApp --install-logrotate --dry-run
assert_empty_trace
/usr/bin/rm -- "${HARNESS_ROOT}/TestApp/appdata/logs/access.log"

/usr/bin/chmod 0570 -- "${HARNESS_ROOT}/TestApp/appdata/logs"
reset_trace
expect_failure 'Unwritable writer parent fails' TestApp --install-logrotate --dry-run
assert_empty_trace
/usr/bin/chmod 0770 -- "${HARNESS_ROOT}/TestApp/appdata/logs"

printf 'existing\n' > "${HARNESS_ROOT}/TestApp/appdata/logs/access.log"
/usr/bin/chmod 0640 -- "${HARNESS_ROOT}/TestApp/appdata/logs/access.log"
/usr/bin/ln -- "${HARNESS_ROOT}/TestApp/appdata/logs/access.log" \
  "${HARNESS_ROOT}/TestApp/appdata/logs/access-hardlink.log"
reset_trace
expect_failure 'Hard-linked existing log fails' TestApp --install-logrotate --dry-run
assert_empty_trace
/usr/bin/rm -- "${HARNESS_ROOT}/TestApp/appdata/logs/access.log" \
  "${HARNESS_ROOT}/TestApp/appdata/logs/access-hardlink.log"

reset_project TestApp
/usr/bin/sed -i 's/version: 1/version: 2/' "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Unsupported metadata version fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i '/      rotations: 14/a\      unexpected: value' \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Unknown entry key fails closed' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i '/        signal: USR1/a\        command: nope' \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Unknown reopen key fails closed' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i 's/^      compress: true$/      compress: "true"/' \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Type-confused Boolean fails closed' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i 's/interval: daily/interval: yearly/' \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Unsupported interval fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i 's/rotations: 14/rotations: 3651/' \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Excessive rotation count fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i '/    container_name:/d' "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Missing explicit container name fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
printf '%s\n' \
  '  other:' \
  '    image: alpine:latest' \
  '    container_name: teststack-app' \
  '    user: "1000:1000"' >> "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Duplicate rendered container name fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i \
  "s|source: ./appdata/logs|source: ${HARNESS_ROOT}/TestApp/appdata/logs|" \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Absolute bind source cannot satisfy relative contract' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/mv -- "${HARNESS_ROOT}/TestApp/appdata/logs" \
  "${HARNESS_ROOT}/TestApp/appdata/logs-real"
/usr/bin/ln -s -- logs-real "${HARNESS_ROOT}/TestApp/appdata/logs"
reset_trace
expect_failure 'Symlinked log parent fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/mkfifo -- "${HARNESS_ROOT}/TestApp/appdata/logs/access.log"
reset_trace
expect_failure 'FIFO log target fails' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/sed -i '/^x-host-logrotate:/,/^services:/{ /^services:/!d; }' \
  "${HARNESS_ROOT}/TestApp/docker-compose.main.yaml"
reset_trace
expect_failure 'Missing opt-in metadata fails dedicated mode' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_project TestApp
/usr/bin/cp -- "$RUNNER" "${TEST_ROOT}/runner-with-gzip"
/usr/bin/sed -i "s|/usr/bin/gzip|${TEST_ROOT}/missing-gzip|g" "$RUNNER"
reset_trace
expect_failure 'Missing compressor fails before installation' TestApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'
/usr/bin/mv -- "${TEST_ROOT}/runner-with-gzip" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"

reset_project Traefik traefik
write_compose "${HARNESS_ROOT}/Traefik" traefik HUP
reset_trace
expect_failure 'Traefik rejects generic HUP reopen' Traefik --install-logrotate --dry-run
assert_empty_trace

reset_project TestApp
write_lines "${TOOL_ROOT}/docker" \
  '#!/usr/bin/env bash' \
  'printf "executed\\n" > "$HOST_LOGROTATE_MALICIOUS_SENTINEL"' \
  'exit 0'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/docker"
MALICIOUS_SENTINEL="${TEST_ROOT}/malicious-docker.executed"
reset_trace
set +e
PATH="${TOOL_ROOT}:/usr/bin:/bin" TMPDIR="${TEST_ROOT}/tmp" \
  HOST_LOGROTATE_TEST_ROOT="$HOST_ROOT" HOST_LOGROTATE_TEST_TRACE="$TRACE_FILE" \
  HOST_LOGROTATE_MALICIOUS_SENTINEL="$MALICIOUS_SENTINEL" \
  "$RUNNER" TestApp --install-logrotate --dry-run > "$OUTPUT_FILE" 2>&1
RUN_STATUS=$?
set -e
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Malicious PATH Docker was accepted.'
[[ ! -e "$MALICIOUS_SENTINEL" ]] || fail 'Malicious PATH Docker was executed.'
assert_empty_trace
/usr/bin/rm -- "${TOOL_ROOT}/docker"
pass 'Malicious PATH Docker fails before root action'

# Every rejected schemæ/vælue cæse below is wræpped in complete byte, type,
# mode, owner, link, ænd inode snæpshots of both the fæke host root ænd Æpp.
reject_yaml_case 'Missing root version fails without mutation' \
  'del(."x-host-logrotate".version)'
reject_yaml_case 'Missing root entries fails without mutation' \
  'del(."x-host-logrotate".entries)'
reject_yaml_case 'Unknown root metadata key fails without mutation' \
  '."x-host-logrotate".unexpected = "value"'
reject_yaml_case 'Root metadata scalar type confusion fails without mutation' \
  '."x-host-logrotate" = "version-1"'
reject_yaml_case 'String metadata version fails without mutation' \
  '."x-host-logrotate".version = "1"'
reject_yaml_case 'Entries mapping type confusion fails without mutation' \
  '."x-host-logrotate".entries = {"id": "access"}'
reject_yaml_case 'Empty entries list fails without mutation' \
  '."x-host-logrotate".entries = []'
reset_case MatrixApp matrixstack
for _ in $(/usr/bin/seq 1 64); do
  set_yaml_expression MatrixApp \
    '."x-host-logrotate".entries += [."x-host-logrotate".entries[0]]'
done
expect_rejected_without_mutation 'More than 64 entries fail without mutation' \
  MatrixApp --install-logrotate --dry-run

for ENTRY_FIELD in id relative-path writer-service interval max-size rotations \
    compress delay-compress create-mode reopen; do
  reject_yaml_case "Missing entry key '${ENTRY_FIELD}' fails without mutation" \
    "del(.\"x-host-logrotate\".entries[0].\"${ENTRY_FIELD}\")"
done
reject_yaml_case 'Unknown entry key fails without mutation snapshot' \
  '."x-host-logrotate".entries[0].unexpected = "value"'
for REOPEN_FIELD in type service signal; do
  reject_yaml_case "Missing reopen key '${REOPEN_FIELD}' fails without mutation" \
    "del(.\"x-host-logrotate\".entries[0].reopen.\"${REOPEN_FIELD}\")"
done
reject_yaml_case 'Unknown reopen key fails without mutation snapshot' \
  '."x-host-logrotate".entries[0].reopen.command = "nope"'

reject_yaml_case 'Entry scalar type confusion fails without mutation' \
  '."x-host-logrotate".entries[0] = "access"'
reject_yaml_case 'ID type confusion fails without mutation' \
  '."x-host-logrotate".entries[0].id = 1'
reject_yaml_case 'Path type confusion fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = []'
reject_yaml_case 'Writer type confusion fails without mutation' \
  '."x-host-logrotate".entries[0]."writer-service" = {}'
reject_yaml_case 'Interval type confusion fails without mutation' \
  '."x-host-logrotate".entries[0].interval = 1'
reject_yaml_case 'Size type confusion fails without mutation' \
  '."x-host-logrotate".entries[0]."max-size" = 50'
reject_yaml_case 'Rotation string type confusion fails without mutation' \
  '."x-host-logrotate".entries[0].rotations = "14"'
reject_yaml_case 'Compress string type confusion fails without mutation snapshot' \
  '."x-host-logrotate".entries[0].compress = "true"'
reject_yaml_case 'Delay-compress string type confusion fails without mutation' \
  '."x-host-logrotate".entries[0]."delay-compress" = "true"'
reject_yaml_case 'Mode numeric type confusion fails without mutation' \
  '."x-host-logrotate".entries[0]."create-mode" = 640'
reject_yaml_case 'Reopen scalar type confusion fails without mutation' \
  '."x-host-logrotate".entries[0].reopen = "USR1"'
reject_yaml_case 'Reopen type field confusion fails without mutation' \
  '."x-host-logrotate".entries[0].reopen.type = 1'
reject_yaml_case 'Reopen service field confusion fails without mutation' \
  '."x-host-logrotate".entries[0].reopen.service = []'
reject_yaml_case 'Reopen signal field confusion fails without mutation' \
  '."x-host-logrotate".entries[0].reopen.signal = true'

reset_case MatrixApp matrixstack
/usr/bin/printf '\nx-host-logrotate: {}\n' >> \
  "${HARNESS_ROOT}/MatrixApp/docker-compose.main.yaml"
expect_rejected_without_mutation 'Duplicate root key fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
/usr/bin/sed -i '/^    - id: access$/a\      id: duplicate' \
  "${HARNESS_ROOT}/MatrixApp/docker-compose.main.yaml"
expect_rejected_without_mutation 'Duplicate entry key fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
/usr/bin/sed -i '/^        signal: USR1$/a\        signal: HUP' \
  "${HARNESS_ROOT}/MatrixApp/docker-compose.main.yaml"
expect_rejected_without_mutation 'Duplicate reopen key fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
/usr/bin/sed -i \
  -e '/^x-host-logrotate:/i\x-logrotate-reopen: \&reopen-defaults\n  type: docker-signal\n  service: app\n  signal: USR1' \
  -e '/^      reopen:/,/^        signal: USR1$/c\      reopen: *reopen-defaults' \
  "${HARNESS_ROOT}/MatrixApp/docker-compose.main.yaml"
expect_rejected_without_mutation 'YAML alias in metadata fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
write_lines "${HARNESS_ROOT}/MatrixApp/docker-compose.main.yaml" \
  'name: matrixstack' \
  'x-logrotate-entry: &entry-defaults' \
  '  id: access' \
  '  relative-path: appdata/logs/access.log' \
  '  writer-service: app' \
  '  interval: daily' \
  '  max-size: 50M' \
  '  rotations: 14' \
  '  compress: true' \
  '  delay-compress: true' \
  '  create-mode: "0640"' \
  '  reopen:' \
  '    type: docker-signal' \
  '    service: app' \
  '    signal: USR1' \
  'x-host-logrotate:' \
  '  version: 1' \
  '  entries:' \
  '    - <<: *entry-defaults' \
  'services:' \
  '  app:' \
  '    image: alpine:latest' \
  '    container_name: matrixstack-app' \
  "    user: \"${APP_UID}:${APP_GID}\"" \
  '    volumes:' \
  '      - type: bind' \
  '        source: ./appdata/logs' \
  '        target: /var/log/app'
expect_rejected_without_mutation 'YAML merge in metadata fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reject_yaml_case 'Duplicate entry ID fails without mutation' \
  '."x-host-logrotate".entries += [."x-host-logrotate".entries[0]]'
reject_yaml_case 'Duplicate log path fails without mutation' \
  '."x-host-logrotate".entries += [."x-host-logrotate".entries[0]] |
   ."x-host-logrotate".entries[1].id = "second"'

reject_yaml_case 'Uppercase entry ID fails without mutation' \
  '."x-host-logrotate".entries[0].id = "Access"'
reject_yaml_case 'Leading-hyphen entry ID fails without mutation' \
  '."x-host-logrotate".entries[0].id = "-access"'
reject_yaml_case 'Dotted entry ID fails without mutation' \
  '."x-host-logrotate".entries[0].id = "access.log"'
reject_yaml_case 'Overlong entry ID fails without mutation' \
  '."x-host-logrotate".entries[0].id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'

reject_yaml_case 'Absolute log path fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = "/tmp/access.log"'
reject_yaml_case 'Empty log path fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = ""'
reject_yaml_case 'Dot path component fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata/./access.log"'
reject_yaml_case 'Dot-dot path component fails without mutation snapshot' \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata/../access.log"'
reject_yaml_case 'Trailing slash path fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata/logs/"'
reject_yaml_case 'Repeated separator path fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata//logs/access.log"'
reject_yaml_case 'Backslash path fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata\\logs\\access.log"'
reject_yaml_case 'Control-character path fails without mutation' \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata/logs/access\n.log"'

reset_case MatrixApp matrixstack
/usr/bin/sed -i 's/^    - id: access$/    - id: "access\\0payload"/' \
  "${HARNESS_ROOT}/MatrixApp/docker-compose.main.yaml"
expect_rejected_without_mutation 'YAML NUL is rejected before Bash extraction' \
  MatrixApp --install-logrotate --dry-run
assert_empty_trace
assert_contains "$OUTPUT_FILE" 'Host-logrotate entry strings must not contæin ÆSCII control chæræcters.'
assert_not_contains "$OUTPUT_FILE" 'ignored null byte'
assert_not_contains "$OUTPUT_FILE" 'BEGIN GENERATED HOST LOGROTATE CONFIG'

reset_case MatrixApp matrixstack
/usr/bin/mv -- "${HARNESS_ROOT}/MatrixApp/appdata/logs" \
  "${HARNESS_ROOT}/MatrixApp/appdata/logs-real"
/usr/bin/ln -s -- logs-real "${HARNESS_ROOT}/MatrixApp/appdata/logs"
expect_rejected_without_mutation 'Symlinked log parent fails without mutation snapshot' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
write_lines "${HARNESS_ROOT}/MatrixApp/appdata/log-target" 'sentinel'
/usr/bin/ln -s -- ../log-target \
  "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log"
expect_rejected_without_mutation 'Symlinked log target fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
/usr/bin/mkfifo -- "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log"
expect_rejected_without_mutation 'Special-file log target fails without mutation snapshot' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
/usr/bin/mkdir -p -- "${HARNESS_ROOT}/MatrixApp/appdata/other"
/usr/bin/chmod 0770 -- "${HARNESS_ROOT}/MatrixApp/appdata/other"
set_yaml_expression MatrixApp \
  '."x-host-logrotate".entries[0]."relative-path" = "appdata/other/access.log"'
expect_rejected_without_mutation 'Log outside writer bind fails without mutation snapshot' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
set_yaml_expression MatrixApp '.services.app.volumes[0].read_only = true'
expect_rejected_without_mutation 'Read-only writer bind fails without mutation' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
write_lines "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log" 'existing'
/usr/bin/chmod 0644 -- "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log"
expect_rejected_without_mutation 'World-readable existing log fails without mutation snapshot' \
  MatrixApp --install-logrotate --dry-run

reset_case MatrixApp matrixstack
write_lines "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log" 'existing'
/usr/bin/chmod 0640 -- "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log"
/usr/bin/ln -- "${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log" \
  "${HARNESS_ROOT}/MatrixApp/appdata/logs/access-hardlink.log"
expect_rejected_without_mutation 'Hard-linked existing log fails without mutation snapshot' \
  MatrixApp --install-logrotate --dry-run

reject_yaml_case 'Zero size fails without mutation' \
  '."x-host-logrotate".entries[0]."max-size" = "0"'
reject_yaml_case 'Leading-zero size fails without mutation' \
  '."x-host-logrotate".entries[0]."max-size" = "050M"'
reject_yaml_case 'Oversized size token fails without mutation' \
  '."x-host-logrotate".entries[0]."max-size" = "1000000M"'
reject_yaml_case 'Unsupported lowercase size unit fails without mutation' \
  '."x-host-logrotate".entries[0]."max-size" = "50m"'
reject_yaml_case 'Injected size directive fails without mutation' \
  '."x-host-logrotate".entries[0]."max-size" = "50M rotate 0"'
reject_yaml_case 'Zero rotations fails without mutation' \
  '."x-host-logrotate".entries[0].rotations = 0'
reject_yaml_case 'Negative rotations fail without mutation' \
  '."x-host-logrotate".entries[0].rotations = -1'
reject_yaml_case 'Excessive rotations fail without mutation snapshot' \
  '."x-host-logrotate".entries[0].rotations = 3651'
reject_yaml_case 'Unsupported interval fails without mutation snapshot' \
  '."x-host-logrotate".entries[0].interval = "yearly"'
reject_yaml_case 'Injected interval fails without mutation' \
  '."x-host-logrotate".entries[0].interval = "daily; copytruncate"'
reject_yaml_case 'Three-digit mode fails without mutation' \
  '."x-host-logrotate".entries[0]."create-mode" = "640"'
reject_yaml_case 'Over-permissive mode fails without mutation snapshot' \
  '."x-host-logrotate".entries[0]."create-mode" = "0660"'
reject_yaml_case 'Injected mode fails without mutation' \
  '."x-host-logrotate".entries[0]."create-mode" = "0640 create root"'
reject_yaml_case 'Delay-compress without compression fails without mutation' \
  '."x-host-logrotate".entries[0].compress = false'

reject_yaml_case 'Unsafe writer service name fails without mutation' \
  '."x-host-logrotate".entries[0]."writer-service" = "App" |
   ."x-host-logrotate".entries[0].reopen.service = "App"'
reject_yaml_case 'Missing writer service fails without mutation' \
  '."x-host-logrotate".entries[0]."writer-service" = "missing" |
   ."x-host-logrotate".entries[0].reopen.service = "missing"'
reject_yaml_case 'Writer and reopen service mismatch fails without mutation' \
  '."x-host-logrotate".entries[0].reopen.service = "other"'

UNKNOWN_UID=60000
while /usr/bin/getent passwd "$UNKNOWN_UID" >/dev/null; do
  UNKNOWN_UID=$((UNKNOWN_UID + 1))
done
UNKNOWN_GID=60000
while /usr/bin/getent group "$UNKNOWN_GID" >/dev/null; do
  UNKNOWN_GID=$((UNKNOWN_GID + 1))
done
reject_yaml_case 'Writer UID without host account fails without mutation' \
  ".services.app.user = \"${UNKNOWN_UID}:${APP_GID}\""
assert_contains "$OUTPUT_FILE" "Writer identity '${UNKNOWN_UID}:${APP_GID}' hæs no complete host æccount mæpping"
assert_contains "$OUTPUT_FILE" "Run: sudo useradd --system --uid ${UNKNOWN_UID} --gid ${APP_GID} --no-create-home --shell /usr/sbin/nologin saervices-logs"
assert_not_contains "$OUTPUT_FILE" 'sudo groupadd'
reject_yaml_case 'Writer GID without host group fails without mutation' \
  ".services.app.user = \"${APP_UID}:${UNKNOWN_GID}\""
assert_contains "$OUTPUT_FILE" "Writer identity '${APP_UID}:${UNKNOWN_GID}' hæs no complete host æccount mæpping"
assert_contains "$OUTPUT_FILE" "Run: sudo groupadd --system --gid ${UNKNOWN_GID} saervices-logs"
assert_not_contains "$OUTPUT_FILE" 'sudo useradd'
reject_yaml_case 'Writer identity without host account or group fails without mutation' \
  ".services.app.user = \"${UNKNOWN_UID}:${UNKNOWN_GID}\""
assert_contains "$OUTPUT_FILE" \
  "Run: sudo groupadd --system --gid ${UNKNOWN_GID} saervices-logs && sudo useradd --system --uid ${UNKNOWN_UID} --gid ${UNKNOWN_GID} --no-create-home --shell /usr/sbin/nologin saervices-logs"

reset_case MatrixApp matrixstack
set_yaml_expression MatrixApp ".services.app.user = \"${UNKNOWN_UID}:${UNKNOWN_GID}\""
printf 'APP_LOGROTATE_ACCOUNT=matrix-writer-logs # locæl override\n' >> "${HARNESS_ROOT}/MatrixApp/.env"
expect_rejected_without_mutation 'Environment-selected account name drives the creation guidance' \
  MatrixApp --install-logrotate --dry-run
assert_contains "$OUTPUT_FILE" \
  "Run: sudo groupadd --system --gid ${UNKNOWN_GID} matrix-writer-logs && sudo useradd --system --uid ${UNKNOWN_UID} --gid ${UNKNOWN_GID} --no-create-home --shell /usr/sbin/nologin matrix-writer-logs"
assert_not_contains "$OUTPUT_FILE" 'saervices-logs'
assert_not_contains "$TRACE_FILE" 'sudo:'

reset_case MatrixApp matrixstack
printf 'APP_LOGROTATE_ACCOUNT=Bad Name!\n' >> "${HARNESS_ROOT}/MatrixApp/.env"
expect_rejected_without_mutation 'Invalid environment account name fails closed' \
  MatrixApp --install-logrotate --dry-run
assert_contains "$OUTPUT_FILE" "APP_LOGROTATE_ACCOUNT is not æ vælid host æccount næme: 'Bad Name!'"
assert_not_contains "$TRACE_FILE" 'sudo:'

TRAVERSAL_LOG="${HARNESS_ROOT}/MatrixApp/appdata/logs/access.log"
reset_case MatrixApp matrixstack
/usr/bin/chmod 0700 -- "$HARNESS_ROOT"
export HOST_LOGROTATE_TEST_MASK_OWNER_DIR="$HARNESS_ROOT"
export HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG="$TRAVERSAL_LOG"
reset_trace
run_runner MatrixApp --install-logrotate --dry-run
[[ "$RUN_STATUS" -eq 0 ]] || fail "Traversal dry-run returned $RUN_STATUS."
assert_contains "$OUTPUT_FILE" "chmod g+x,o+x '${HARNESS_ROOT}'"
assert_contains "$OUTPUT_FILE" 'Dry-run: would grant the reported writer træversæl bits'
assert_contains "$OUTPUT_FILE" 'the instæll æpplies the reported træversæl grants first'
assert_not_contains "$OUTPUT_FILE" '[ERROR]'
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ "$(/usr/bin/stat -Lc '%a' -- "$HARNESS_ROOT")" == 700 ]] || \
  fail 'Traversal dry-run changed the blocked ancestor mode.'
pass 'Traversal dry-run reports the exact grant plan without mutation'

reset_trace
run_runner MatrixApp --check-logrotate
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Traversal check unexpectedly succeeded.'
assert_contains "$OUTPUT_FILE" "chmod g+x,o+x '${HARNESS_ROOT}'"
assert_contains "$OUTPUT_FILE" 'reæl instæll æpplies the reported træversæl grants first'
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ "$(/usr/bin/stat -Lc '%a' -- "$HARNESS_ROOT")" == 700 ]] || \
  fail 'Traversal check changed the blocked ancestor mode.'
pass 'Traversal check mode fails closed with the exact grant plan'

reset_trace
run_runner MatrixApp --install-logrotate
[[ "$RUN_STATUS" -eq 0 ]] || fail "Traversal install returned $RUN_STATUS."
assert_contains "$OUTPUT_FILE" "Grænted writer træversæl: chmod g+x,o+x '${HARNESS_ROOT}'"
assert_contains "$OUTPUT_FILE" 'vælidætion pæssed æfter the writer træversæl grants'
assert_not_contains "$OUTPUT_FILE" '[ERROR]'
assert_contains "$TRACE_FILE" 'sudo:chmod'
[[ "$(/usr/bin/stat -Lc '%a' -- "$HARNESS_ROOT")" == 711 ]] || \
  fail 'Real install did not grant g+x,o+x on the blocked ancestor.'
TRAVERSAL_TARGET_FILE=$(find_target matrixstack)
assert_contains "$TRAVERSAL_TARGET_FILE" "    su ${APP_USER_NAME} ${APP_GROUP_NAME}"
unset HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG HOST_LOGROTATE_TEST_MASK_OWNER_DIR
/usr/bin/chmod 0755 -- "$HARNESS_ROOT"
pass 'Real install grants the minimal traversal bits, re-validates, and publishes'

reset_case MatrixApp matrixstack
/usr/bin/chmod 0700 -- "$HARNESS_ROOT"
export HOST_LOGROTATE_TEST_MASK_OWNER_DIR="$HARNESS_ROOT"
export HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG="$TRAVERSAL_LOG"
export HOST_LOGROTATE_TEST_FAIL_PARSER=true
reset_trace
run_runner MatrixApp --install-logrotate
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Post-grant validation failure unexpectedly succeeded.'
assert_contains "$OUTPUT_FILE" "Grænted writer træversæl: chmod g+x,o+x '${HARNESS_ROOT}'"
assert_contains "$OUTPUT_FILE" 'vælidætion still fæils æfter the writer træversæl grants'
assert_contains "$OUTPUT_FILE" "Restored mode 0700 on '${HARNESS_ROOT}'"
[[ "$(/usr/bin/stat -Lc '%a' -- "$HARNESS_ROOT")" == 700 ]] || \
  fail 'Failed install did not restore the pre-grant ancestor mode.'
mapfile -t TRAVERSAL_TARGETS < <(
  /usr/bin/find "$HOST_ROOT" -mindepth 1 -maxdepth 1 -type f \
    -name 'saervices-docker-matrixstack-*' -print
)
[[ "${#TRAVERSAL_TARGETS[@]}" -eq 0 ]] || \
  fail 'Failed install published a target despite validation failure.'
unset HOST_LOGROTATE_TEST_FAIL_PARSER HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG \
  HOST_LOGROTATE_TEST_MASK_OWNER_DIR
/usr/bin/chmod 0755 -- "$HARNESS_ROOT"
pass 'Later validation failure rolls back the granted traversal bit exactly'

reset_case MatrixApp matrixstack
export HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG="$TRAVERSAL_LOG"
expect_rejected_without_mutation 'Permission denial without computed blockers fails closed' \
  MatrixApp --install-logrotate
unset HOST_LOGROTATE_TEST_PERMISSION_DENIED_LOG
assert_contains "$OUTPUT_FILE" 'no æncestor mode blocker wæs computed'
assert_contains "$OUTPUT_FILE" 'namei -l'
assert_not_contains "$TRACE_FILE" 'sudo:'

reject_yaml_case 'Unsupported reopen type fails without mutation' \
  '."x-host-logrotate".entries[0].reopen.type = "copytruncate"'
reject_yaml_case 'Unsupported reopen signal fails without mutation snapshot' \
  '."x-host-logrotate".entries[0].reopen.signal = "TERM"'
reject_yaml_case 'Injected reopen signal fails without mutation' \
  '."x-host-logrotate".entries[0].reopen.signal = "USR1; touch payload"'

PAYLOAD_SENTINEL="${TEST_ROOT}/metadata-payload.executed"
reset_case MatrixApp matrixstack
set_yaml_expression MatrixApp \
  ".\"x-host-logrotate\".entries[0].id = \"access; /usr/bin/touch ${PAYLOAD_SENTINEL}\""
expect_rejected_without_mutation 'Metadata shell payload is data and never executes' \
  MatrixApp --install-logrotate --dry-run
[[ ! -e "$PAYLOAD_SENTINEL" ]] || fail 'Metadata payload executed as shell text.'

reset_case MatrixApp matrixstack
set_yaml_expression MatrixApp \
  '."x-host-logrotate".entries += [."x-host-logrotate".entries[0]] |
   ."x-host-logrotate".entries[1].id = "later" |
   ."x-host-logrotate".entries[1].interval = "yearly"'
expect_rejected_without_mutation 'Bad later entry rejects globally before first mutation' \
  MatrixApp --install-logrotate
assert_not_contains "$TRACE_FILE" 'sudo:'

run_missing_tool_case() {
  local label="$1"
  local variable_name="$2"
  local action="${3:---install-logrotate --dry-run}"
  local runner_backup="${TEST_ROOT}/runner-tool-backup"
  local -a action_args=()

  reset_case ToolApp toolstack
  /usr/bin/cp -- "$RUNNER" "$runner_backup"
  /usr/bin/sed -i -E \
    "s|^readonly ${variable_name}=.*|readonly ${variable_name}=\"${TEST_ROOT}/missing-${variable_name}\"|" \
    "$RUNNER"
  read -r -a action_args <<< "$action"
  expect_rejected_without_mutation "$label" ToolApp "${action_args[@]}"
  assert_not_contains "$TRACE_FILE" 'sudo:'
  /usr/bin/cp -- "$runner_backup" "$RUNNER"
  /usr/bin/chmod 0755 -- "$RUNNER"
}

run_missing_tool_case 'Missing fixed realpath fails without mutation' \
  HOST_LOGROTATE_REALPATH_BIN
run_missing_tool_case 'Missing fixed stat fails without mutation' \
  HOST_LOGROTATE_STAT_BIN
run_missing_tool_case 'Missing fixed jq fails without mutation' \
  HOST_LOGROTATE_JQ_BIN
run_missing_tool_case 'Missing fixed getent fails without mutation' \
  HOST_LOGROTATE_GETENT_BIN
run_missing_tool_case 'Missing fixed id fails without mutation' \
  HOST_LOGROTATE_ID_BIN

reset_case ToolApp toolstack
PARSER_RUNNER_BACKUP="${TEST_ROOT}/runner-parser-backup"
/usr/bin/cp -- "$RUNNER" "$PARSER_RUNNER_BACKUP"
/usr/bin/sed -i \
  "s|readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(.*)|readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(\"${TEST_ROOT}/missing-logrotate-sbin\" \"${TEST_ROOT}/missing-logrotate-bin\")|" \
  "$RUNNER"
expect_rejected_without_mutation 'Missing fixed parser fails without mutation' \
  ToolApp --install-logrotate --dry-run
assert_not_contains "$TRACE_FILE" 'sudo:'
assert_contains "$OUTPUT_FILE" 'Required host-logrotate tool is unævæilæble; no fixed cændidæte resolves to æ regulær executæble'
assert_contains "$OUTPUT_FILE" "'${TEST_ROOT}/missing-logrotate-sbin' is missing or unresolvæble"
assert_contains "$OUTPUT_FILE" "'${TEST_ROOT}/missing-logrotate-bin' is missing or unresolvæble"
assert_contains "$OUTPUT_FILE" 'sudo apt-get install logrotate'
/usr/bin/cp -- "$PARSER_RUNNER_BACKUP" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"

reset_case ToolApp toolstack
/usr/bin/cp -- "$RUNNER" "$PARSER_RUNNER_BACKUP"
/usr/bin/ln -s -- "${TOOL_ROOT}/logrotate" "${TEST_ROOT}/linked-logrotate"
/usr/bin/sed -i \
  "s|readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(.*)|readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(\"${TEST_ROOT}/missing-logrotate-sbin\" \"${TEST_ROOT}/linked-logrotate\")|" \
  "$RUNNER"
reset_trace
expect_success 'Symlinked parser candidate resolves to its canonical target' \
  ToolApp --install-logrotate --dry-run
assert_contains "$TRACE_FILE" 'logrotate-debug'
assert_not_contains "$TRACE_FILE" 'sudo:'
/usr/bin/rm -- "${TEST_ROOT}/linked-logrotate"
/usr/bin/cp -- "$PARSER_RUNNER_BACKUP" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"

run_missing_tool_case 'Missing privileged mktemp fails before mutation' \
  HOST_LOGROTATE_ROOT_MKTEMP_BIN '--install-logrotate'
run_missing_tool_case 'Missing fixed sudo fails before mutation' \
  HOST_LOGROTATE_SUDO_BIN '--install-logrotate'

reset_case ToolApp toolstack
export HOST_LOGROTATE_TEST_FAIL_PARSER=true
expect_rejected_without_mutation 'Failing logrotate parser leaves host and App unchanged' \
  ToolApp --install-logrotate --dry-run
unset HOST_LOGROTATE_TEST_FAIL_PARSER
assert_not_contains "$TRACE_FILE" 'sudo:'
assert_contains "$TRACE_FILE" 'logrotate-debug'

run_jq_producer_failure_case() {
  local label="$1"
  local failure_mode="$2"
  local expected_error="$3"
  local runner_backup="${TEST_ROOT}/runner-jq-producer-backup"
  local jq_marker="${TEST_ROOT}/jq-producer-${failure_mode}.triggered"
  local jq_stub="${TOOL_ROOT}/jq-producer-fault"

  reset_case ProducerApp producerstack
  write_lines "$jq_stub" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'matched=false' \
    'for argument in "$@"; do' \
    '  case "${HOST_LOGROTATE_TEST_JQ_FAILURE_MODE:?}" in' \
    '    entries) [[ "$argument" == '\''."x-host-logrotate".entries[]'\'' ]] && matched=true ;;' \
    '    field) [[ "$argument" == '\''."max-size"'\'' ]] && matched=true ;;' \
    '    binds) [[ "$argument" == *"@tsv"* ]] && matched=true ;;' \
    '    *) exit 78 ;;' \
    '  esac' \
    'done' \
    'if [[ "$matched" == true ]]; then' \
    '  : > "$HOST_LOGROTATE_TEST_JQ_FAILURE_MARKER"' \
    '  exit 77' \
    'fi' \
    'exec /usr/bin/jq "$@"'
  /usr/bin/chmod 0755 -- "$jq_stub"
  /usr/bin/cp -- "$RUNNER" "$runner_backup"
  /usr/bin/sed -i \
    "s|readonly HOST_LOGROTATE_JQ_BIN=\"/usr/bin/jq\"|readonly HOST_LOGROTATE_JQ_BIN=\"${jq_stub}\"|" \
    "$RUNNER"
  export HOST_LOGROTATE_TEST_JQ_FAILURE_MODE="$failure_mode"
  export HOST_LOGROTATE_TEST_JQ_FAILURE_MARKER="$jq_marker"
  expect_rejected_without_mutation "$label" ProducerApp --install-logrotate --dry-run
  unset HOST_LOGROTATE_TEST_JQ_FAILURE_MODE HOST_LOGROTATE_TEST_JQ_FAILURE_MARKER
  /usr/bin/cp -- "$runner_backup" "$RUNNER"
  /usr/bin/chmod 0755 -- "$RUNNER"
  /usr/bin/rm -- "$jq_stub"
  [[ -f "$jq_marker" ]] || fail "JQ producer fault '$failure_mode' was not injected."
  assert_contains "$OUTPUT_FILE" "$expected_error"
  assert_empty_trace
}

run_jq_producer_failure_case \
  'Entries JQ failure propagates without host or App mutation' \
  entries 'Fæiled to enumeræte rendered host-logrotate entries.'
run_jq_producer_failure_case \
  'Mid-entry field JQ failure propagates without host or App mutation' \
  field 'Fæiled to extræct host-logrotate mæx-size.'
run_jq_producer_failure_case \
  'Writer-bind JQ failure propagates without host or App mutation' \
  binds 'Fæiled to enumeræte rendered writer bind mounts.'

reset_case ProducerApp producerstack
PEER_FIND_RUNNER_BACKUP="${TEST_ROOT}/runner-peer-find-backup"
PEER_FIND_MARKER="${TEST_ROOT}/peer-find.triggered"
PEER_FIND_STUB="${TOOL_ROOT}/find-peer-fault"
write_lines "$PEER_FIND_STUB" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ " $* " == *" $HOST_LOGROTATE_TEST_ROOT "* && " $* " == *" -print0 "* ]]; then' \
  '  : > "$HOST_LOGROTATE_TEST_PEER_FIND_MARKER"' \
  '  exit 76' \
  'fi' \
  'exec /usr/bin/find "$@"'
/usr/bin/chmod 0755 -- "$PEER_FIND_STUB"
/usr/bin/cp -- "$RUNNER" "$PEER_FIND_RUNNER_BACKUP"
/usr/bin/sed -i "s|/usr/bin/find|${PEER_FIND_STUB}|g" "$RUNNER"
export HOST_LOGROTATE_TEST_PEER_FIND_MARKER="$PEER_FIND_MARKER"
expect_rejected_without_mutation \
  'Peer find failure propagates without host or App mutation' \
  ProducerApp --install-logrotate --dry-run
unset HOST_LOGROTATE_TEST_PEER_FIND_MARKER
/usr/bin/cp -- "$PEER_FIND_RUNNER_BACKUP" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"
/usr/bin/rm -- "$PEER_FIND_STUB"
[[ -f "$PEER_FIND_MARKER" ]] || fail 'Peer find fault was not injected.'
assert_contains "$OUTPUT_FILE" 'Fæiled to enumeræte host-logrotate peer configurætions.'
assert_empty_trace

run_fake_docker_failure() {
  local label="$1"
  local mode="$2"
  local runner_backup="${TEST_ROOT}/runner-docker-backup"
  local fake_docker="${TOOL_ROOT}/docker"

  reset_case ToolApp toolstack
  write_lines "$fake_docker" \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case " $* " in' \
    '  *" compose version "*) [[ "${HOST_LOGROTATE_TEST_DOCKER_MODE}" != unavailable ]] ;;' \
    '  *" config "*)' \
    '    if [[ "${HOST_LOGROTATE_TEST_DOCKER_MODE}" == render-failure ]]; then exit 72; fi' \
    '    printf '\''{malformed-json\\n'\''' \
    '    ;;' \
    '  *) exit 73 ;;' \
    'esac'
  /usr/bin/chmod 0755 -- "$fake_docker"
  /usr/bin/cp -- "$RUNNER" "$runner_backup"
  /usr/bin/sed -i "s|/usr/bin/docker|${fake_docker}|g" "$RUNNER"
  export HOST_LOGROTATE_TEST_TRUSTED_DOCKER="$fake_docker"
  export HOST_LOGROTATE_TEST_DOCKER_MODE="$mode"
  expect_rejected_without_mutation "$label" ToolApp --install-logrotate --dry-run
  unset HOST_LOGROTATE_TEST_TRUSTED_DOCKER HOST_LOGROTATE_TEST_DOCKER_MODE
  /usr/bin/cp -- "$runner_backup" "$RUNNER"
  /usr/bin/chmod 0755 -- "$RUNNER"
  /usr/bin/rm -- "$fake_docker"
}

run_fake_docker_failure 'Unavailable Docker Compose fails without mutation' unavailable
run_fake_docker_failure 'Compose render failure leaves host and App unchanged' render-failure
run_fake_docker_failure 'Malformed rendered Compose fails closed without mutation' malformed

reset_case TimerApp timerstack
TIMER_RUNNER_BACKUP="${TEST_ROOT}/runner-timer-backup"
TIMER_SYSTEMD_ROOT="${TEST_ROOT}/fake-systemd/system"
TIMER_TRACE="${TEST_ROOT}/timer.trace"
/usr/bin/mkdir -p -- "$TIMER_SYSTEMD_ROOT"
write_lines "${TOOL_ROOT}/systemctl" \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\\n" "$*" >> "$HOST_LOGROTATE_TIMER_TRACE"' \
  'case "$1" in' \
  '  is-active) printf "active\\n" ;;' \
  '  is-enabled) printf "enabled\\n" ;;' \
  '  *) exit 79 ;;' \
  'esac'
/usr/bin/chmod 0755 -- "${TOOL_ROOT}/systemctl"
/usr/bin/cp -- "$RUNNER" "$TIMER_RUNNER_BACKUP"
/usr/bin/sed -i \
  -e "s|/run/systemd/system|${TIMER_SYSTEMD_ROOT}|g" \
  -e "s|/usr/bin/systemctl|${TOOL_ROOT}/systemctl|g" \
  "$RUNNER"
TIMER_APP_BEFORE="${TEST_ROOT}/timer-app.before"
TIMER_HOST_BEFORE="${TEST_ROOT}/timer-host.before"
snapshot_tree "${HARNESS_ROOT}/TimerApp" "$TIMER_APP_BEFORE"
snapshot_tree "$HOST_ROOT" "$TIMER_HOST_BEFORE"
export HOST_LOGROTATE_TIMER_TRACE="$TIMER_TRACE"
reset_trace
run_runner TimerApp --install-logrotate --dry-run
unset HOST_LOGROTATE_TIMER_TRACE
[[ "$RUN_STATUS" -eq 0 ]] || fail "Timer observation returned $RUN_STATUS."
assert_tree_unchanged "${HARNESS_ROOT}/TimerApp" "$TIMER_APP_BEFORE"
assert_tree_unchanged "$HOST_ROOT" "$TIMER_HOST_BEFORE"
assert_contains "$TIMER_TRACE" 'is-active logrotate.timer'
assert_contains "$TIMER_TRACE" 'is-enabled logrotate.timer'
if /usr/bin/grep -Eq '(^| )(enable|start|restart|enable --now)( |$)' "$TIMER_TRACE"; then
  fail 'Timer observation attempted to mutate scheduler state.'
fi
/usr/bin/cp -- "$TIMER_RUNNER_BACKUP" "$RUNNER"
/usr/bin/chmod 0755 -- "$RUNNER"
/usr/bin/rm -- "${TOOL_ROOT}/systemctl"
pass 'Timer state is observed through read-only calls without any mutation'

reset_case SwapApp swapstack
CONFIG_SWAP_MARKER="${TEST_ROOT}/config-dir-swapped.marker"
export HOST_LOGROTATE_TEST_SWAP_CONFIG_DIR="$CONFIG_SWAP_MARKER"
reset_trace
run_runner SwapApp --install-logrotate
unset HOST_LOGROTATE_TEST_SWAP_CONFIG_DIR
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Config-directory identity swap unexpectedly succeeded.'
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ -d "${HOST_ROOT}.original" && -d "$HOST_ROOT" ]] || \
  fail 'Config-directory identity swap fixture did not run.'
[[ -z "$(/usr/bin/find -P "$HOST_ROOT" "${HOST_ROOT}.original" -maxdepth 1 \
  -type f -name 'saervices-docker-*' -print -quit)" ]] || \
  fail 'Config-directory identity swap published a managed host file.'
/usr/bin/rm -rf -- "$HOST_ROOT"
/usr/bin/mv -- "${HOST_ROOT}.original" "$HOST_ROOT"
pass 'Config-directory identity drift, including mount-equivalent swaps, fails before mutation'

reset_case SwapApp swapstack
LOG_PARENT="${HARNESS_ROOT}/SwapApp/appdata/logs"
LOG_PARENT_SWAP_MARKER="${TEST_ROOT}/log-parent-swapped.marker"
export HOST_LOGROTATE_TEST_SWAP_LOG_PARENT="$LOG_PARENT_SWAP_MARKER"
export HOST_LOGROTATE_TEST_LOG_PARENT="$LOG_PARENT"
reset_trace
run_runner SwapApp --install-logrotate
unset HOST_LOGROTATE_TEST_SWAP_LOG_PARENT HOST_LOGROTATE_TEST_LOG_PARENT
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Writer-parent identity swap unexpectedly succeeded.'
assert_not_contains "$TRACE_FILE" 'sudo:'
[[ -d "${LOG_PARENT}.original" && -d "$LOG_PARENT" ]] || \
  fail 'Writer-parent identity swap fixture did not run.'
[[ -z "$(/usr/bin/find -P "$HOST_ROOT" -maxdepth 1 -type f \
  -name 'saervices-docker-*' -print -quit)" ]] || \
  fail 'Writer-parent identity swap published a managed host file.'
pass 'Writer-parent identity drift fails before privileged mutation'

reset_project SecondApp teststack
reset_trace
expect_success 'Second deployment with same Compose name validates' SecondApp --install-logrotate --dry-run
SECOND_TARGET=$(/usr/bin/grep -o "${HOST_ROOT}/saervices-docker-teststack-[0-9a-f]*" "$OUTPUT_FILE" | /usr/bin/head -n1)
reset_trace
expect_success 'First deployment with same Compose name validates' TestApp --install-logrotate --dry-run
FIRST_TARGET=$(/usr/bin/grep -o "${HOST_ROOT}/saervices-docker-teststack-[0-9a-f]*" "$OUTPUT_FILE" | /usr/bin/head -n1)
[[ -n "$FIRST_TARGET" && -n "$SECOND_TARGET" && "$FIRST_TARGET" != "$SECOND_TARGET" ]] || \
  fail 'Canonical project-root hashes did not separate same-name deployments.'

SECRET_FILE="${TEST_ROOT}/root-only.secret"
write_lines "$SECRET_FILE" 'ROOT_ONLY_SENTINEL'
/usr/bin/chmod 0000 -- "$SECRET_FILE"
SWAP_MARKER="${TEST_ROOT}/source-swapped.marker"
reset_trace
export HOST_LOGROTATE_TEST_SWAP_SOURCE="$SWAP_MARKER"
export HOST_LOGROTATE_TEST_SECRET="$SECRET_FILE"
expect_success 'Pinned source resists sudo-prompt symlink swap' TestApp --install-logrotate
unset HOST_LOGROTATE_TEST_SWAP_SOURCE HOST_LOGROTATE_TEST_SECRET
TARGET_FILE="$(find_target)"
assert_not_contains "$TARGET_FILE" 'ROOT_ONLY_SENTINEL'
assert_contains "$TARGET_FILE" '# Managed by it.saervices run.sh (host-logrotate-v1)'

if /usr/bin/grep -Eq 'systemctl.*(enable|start|restart)' "$TRACE_FILE"; then
  fail 'Host-logrotate workflow attempted timer mutation.'
fi
pass 'Scheduler remains report-only'

reset_case CleanupApp cleanupstack
PRIVILEGED_REPLACEMENT_MARKER="${TEST_ROOT}/privileged-temp-replaced.path"
export HOST_LOGROTATE_TEST_REPLACE_PRIVILEGED_TMP="$PRIVILEGED_REPLACEMENT_MARKER"
reset_trace
run_runner CleanupApp --install-logrotate
unset HOST_LOGROTATE_TEST_REPLACE_PRIVILEGED_TMP
[[ "$RUN_STATUS" -ne 0 ]] || fail 'Replaced privileged staging unexpectedly published.'
[[ -f "$PRIVILEGED_REPLACEMENT_MARKER" && ! -L "$PRIVILEGED_REPLACEMENT_MARKER" ]] || \
  fail 'Privileged staging replacement hook did not record its exact path.'
REPLACED_PRIVILEGED_TMP=$(/usr/bin/sed -n '1p' "$PRIVILEGED_REPLACEMENT_MARKER")
[[ "$REPLACED_PRIVILEGED_TMP" == \
    "$HOST_ROOT/".saervices-docker-cleanupstack-*.tmp.?????? ]] || \
  fail 'Privileged staging replacement hook returned an unsafe path.'
[[ -f "$REPLACED_PRIVILEGED_TMP" && ! -L "$REPLACED_PRIVILEGED_TMP" ]] || \
  fail 'Cleanup removed the foreign privileged staging replacement.'
[[ "$(/usr/bin/sed -n '1p' "$REPLACED_PRIVILEGED_TMP")" == \
    FOREIGN_PRIVILEGED_TEMP_SENTINEL ]] || \
  fail 'Cleanup modified the foreign privileged staging replacement.'
[[ -f "${REPLACED_PRIVILEGED_TMP}.process-owned" ]] || \
  fail 'Replacement fixture did not preserve the original process-owned inode.'
[[ -z "$(/usr/bin/find -P "$HOST_ROOT" -mindepth 1 -maxdepth 1 -type f \
  -name 'saervices-docker-*' -print -quit)" ]] || \
  fail 'Replaced privileged staging unexpectedly created a managed target.'
assert_contains "$OUTPUT_FILE" 'Preserving replæced or modified privileged host-logrotate publish stæging'
assert_contains "$TRACE_FILE" 'sudo:mv'
assert_not_contains "$TRACE_FILE" 'sudo:rm'
pass 'Cleanup preserves a foreign replacement of privileged staging'

printf 'PASS: %d host-logrotate regression checks completed under %s\n' \
  "$PASS_COUNT" "$TEST_ROOT"
