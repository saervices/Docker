#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/espocrm-bootstrap.XXXXXX")"
readonly WRAPPER="${TEST_ROOT}/espocrm-start.sh"
readonly LOCK_HELPER="${TEST_ROOT}/espocrm-runtime-lock.sh"
readonly SECRET_READER="${TEST_ROOT}/espocrm-secret-reader.pl"
readonly DATA_DIR="${TEST_ROOT}/data"
readonly SETUP_SECRETS="${TEST_ROOT}/setup-secrets"
readonly RUNTIME_SECRETS="${TEST_ROOT}/runtime-secrets"
readonly STATE_FILE="${TEST_ROOT}/installed-state"
readonly VENDOR_MARKER="${TEST_ROOT}/vendor-started"
readonly CHILD_TERM_MARKER="${TEST_ROOT}/vendor-terminated"

PASS=0
FAIL=0

cleanup() {
  rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
}

expect_success() {
  local name="$1"
  shift
  if "$@" >"${TEST_ROOT}/${name}.out" 2>&1; then
    pass "${name}"
  else
    sed -n '1,80p' "${TEST_ROOT}/${name}.out" >&2 || true
    fail "${name}"
  fi
}

expect_failure() {
  local name="$1"
  shift
  if "$@" >"${TEST_ROOT}/${name}.out" 2>&1; then
    fail "${name}"
  else
    pass "${name}"
  fi
}

cp -- "${TEST_REPO_ROOT}/EspoCRM/scripts/espocrm-start.sh" "${WRAPPER}"
cp -- "${TEST_REPO_ROOT}/EspoCRM/scripts/espocrm-runtime-lock.sh" "${LOCK_HELPER}"
cp -- "${TEST_REPO_ROOT}/EspoCRM/scripts/espocrm-secret-reader.pl" "${SECRET_READER}"
chmod 0755 "${WRAPPER}" "${LOCK_HELPER}" "${SECRET_READER}"
mkdir -m 0700 -- "${DATA_DIR}" "${SETUP_SECRETS}" "${RUNTIME_SECRETS}"
printf 'provider-client-id' >"${SETUP_SECRETS}/ESPOCRM_OIDC_CLIENT_ID"
printf 'provider-client-secret' >"${SETUP_SECRETS}/ESPOCRM_OIDC_CLIENT_SECRET"
printf 'strong-admin-password' >"${SETUP_SECRETS}/ESPOCRM_ADMIN_PASSWORD"
printf 'strong-database-password' >"${SETUP_SECRETS}/MARIADB_PASSWORD"
cp -- "${SETUP_SECRETS}/ESPOCRM_OIDC_CLIENT_ID" "${RUNTIME_SECRETS}/ESPOCRM_OIDC_CLIENT_ID"
cp -- "${SETUP_SECRETS}/ESPOCRM_OIDC_CLIENT_SECRET" "${RUNTIME_SECRETS}/ESPOCRM_OIDC_CLIENT_SECRET"
printf 'false' >"${STATE_FILE}"
printf '<?php return [];\n' >"${TEST_ROOT}/config-override.php"

cat >"${TEST_ROOT}/php-stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-r" ]]; then
  exit 1
fi
shift
case "${1:-}:${2:-}" in
  config:get:isInstalled)
    cat -- "${ESPO_STATE_FILE}"
    ;;
  config:get:version)
    [[ "$(<"${ESPO_STATE_FILE}")" == true ]]
    printf '10.0.0\n'
    ;;
  app-check:)
    [[ "$(<"${ESPO_STATE_FILE}")" == true ]]
    ;;
  *)
    printf 'unexpected PHP stub arguments: %q %q\n' "${1:-}" "${2:-}" >&2
    exit 1
    ;;
esac
SH

cat >"${TEST_ROOT}/setpriv-stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
while [[ "${1:-}" == --* ]]; do shift; done
exec "$@"
SH

cat >"${TEST_ROOT}/vendor-stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'started\n' >"${ESPO_VENDOR_MARKER}"
case "${ESPO_VENDOR_MODE:-fresh}" in
  fresh)
    test -r "${ESPOCRM_ADMIN_PASSWORD_FILE}" || { printf 'admin snapshot unreadable\n' >&2; exit 1; }
    test -r "${ESPOCRM_DATABASE_PASSWORD_FILE}" || { printf 'database snapshot unreadable\n' >&2; exit 1; }
    test "$(<"${ESPOCRM_ADMIN_PASSWORD_FILE}")" = strong-admin-password || { printf 'admin snapshot mismatch\n' >&2; exit 1; }
    test "$(<"${ESPOCRM_DATABASE_PASSWORD_FILE}")" = strong-database-password || { printf 'database snapshot mismatch\n' >&2; exit 1; }
    printf 'true' >"${ESPO_STATE_FILE}"
    ;;
  snapshot)
    printf 'mutated-after-snapshot' >"${ESPO_SOURCE_ADMIN}"
    test "$(<"${ESPOCRM_ADMIN_PASSWORD_FILE}")" = strong-admin-password || { printf 'admin snapshot was not stable\n' >&2; exit 1; }
    test "$(<"${ESPOCRM_DATABASE_PASSWORD_FILE}")" = strong-database-password || { printf 'database snapshot mismatch\n' >&2; exit 1; }
    printf 'true' >"${ESPO_STATE_FILE}"
    ;;
  installed)
    test -z "${ESPOCRM_ADMIN_PASSWORD+x}"
    test -z "${ESPOCRM_ADMIN_PASSWORD_FILE+x}"
    test -z "${ESPOCRM_DATABASE_PASSWORD+x}"
    test -z "${ESPOCRM_DATABASE_PASSWORD_FILE+x}"
    ;;
  fail)
    exit 42
    ;;
  wait)
    trap 'printf "terminated\n" >"${ESPO_CHILD_TERM_MARKER}"; exit 143' TERM INT
    while true; do sleep 0.1; done
    ;;
  ignore-term)
    trap '' TERM INT
    while true; do sleep 0.1; done
    ;;
  *)
    exit 2
    ;;
esac
SH

cat >"${TEST_ROOT}/apache2-foreground" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
test ! -e "${SECRET_DIR}/ESPOCRM_ADMIN_PASSWORD"
test ! -e "${SECRET_DIR}/MARIADB_PASSWORD"
test -z "${ESPOCRM_ADMIN_PASSWORD+x}"
test -z "${ESPOCRM_ADMIN_PASSWORD_FILE+x}"
test -z "${ESPOCRM_DATABASE_PASSWORD+x}"
test -z "${ESPOCRM_DATABASE_PASSWORD_FILE+x}"
SH
chmod 0755 "${TEST_ROOT}/php-stub" "${TEST_ROOT}/setpriv-stub" \
  "${TEST_ROOT}/vendor-stub" "${TEST_ROOT}/apache2-foreground"

run_wrapper() {
  local secret_dir="$1"
  local vendor_mode="$2"
  shift 2
  SECRET_DIR="${secret_dir}" \
  ESPO_STATE_FILE="${STATE_FILE}" \
  ESPO_VENDOR_MARKER="${VENDOR_MARKER}" \
  ESPO_CHILD_TERM_MARKER="${CHILD_TERM_MARKER}" \
  ESPO_VENDOR_MODE="${vendor_mode}" \
  ESPO_SOURCE_ADMIN="${SETUP_SECRETS}/ESPOCRM_ADMIN_PASSWORD" \
  ESPOCRM_VERSION="${ESPO_TEST_IMAGE_VERSION:-10.0.0}" \
  ESPOCRM_ADMIN_USERNAME=admin \
  APP_UID=33 \
  ESPOCRM_RUNTIME_HOST=espocrm \
  APP_GID=1000 \
  ESPOCRM_DATA_DIR="${DATA_DIR}" \
  ESPOCRM_OIDC_CONFIG_SOURCE="${TEST_ROOT}/config-override.php" \
  ESPOCRM_CONFIG_OWNER="$(id -u):$(id -g)" \
  ESPOCRM_VENDOR_ENTRYPOINT_BIN="${TEST_ROOT}/vendor-stub" \
  ESPOCRM_PHP_BIN="${TEST_ROOT}/php-stub" \
  ESPOCRM_APP_COMMAND="${TEST_ROOT}/command" \
  ESPOCRM_SETPRIV_BIN="${TEST_ROOT}/setpriv-stub" \
  ESPOCRM_RUNTIME_LOCK_HELPER="${LOCK_HELPER}" \
  ESPOCRM_SECRET_READER="${SECRET_READER}" \
  ESPOCRM_SETUP_SNAPSHOT_PARENT="${TEST_ROOT}" \
  ESPOCRM_BOOTSTRAP_TERM_TIMEOUT=1 \
  PATH="${TEST_ROOT}:${PATH}" \
  /bin/bash "${WRAPPER}" "$@"
}

static_contract() {
  python3 - "${TEST_REPO_ROOT}" <<'PY'
from pathlib import Path
import sys
import yaml

root = Path(sys.argv[1])
app = yaml.safe_load((root / 'EspoCRM/docker-compose.app.yaml').read_text())
bootstrap = yaml.safe_load((root / 'templates/espocrm-bootstrap/docker-compose.espocrm-bootstrap.yaml').read_text())
service = app['services']['app']
job = bootstrap['services']['espocrm-bootstrap']
if 'espocrm-bootstrap' not in app['x-required-services']:
    raise SystemExit('bootstrap template is not required')
if service['secrets'] != ['ESPOCRM_OIDC_CLIENT_ID', 'ESPOCRM_OIDC_CLIENT_SECRET']:
    raise SystemExit('web runtime secret set is not OIDC-only')
if service['command'] != ['--runtime', 'apache2-foreground']:
    raise SystemExit('web runtime mode is not explicit')
if service['depends_on']['espocrm-bootstrap']['condition'] != 'service_completed_successfully':
    raise SystemExit('web runtime does not require successful bootstrap completion')
if not any('espocrm-secret-reader.pl' in item for item in service['volumes']):
    raise SystemExit('descriptor-bound secret reader is not mounted')
if set(job['secrets']) != {'MARIADB_PASSWORD', 'ESPOCRM_ADMIN_PASSWORD', 'ESPOCRM_OIDC_CLIENT_ID', 'ESPOCRM_OIDC_CLIENT_SECRET'}:
    raise SystemExit('finite bootstrap secret set is incomplete')
if job.get('restart') != 'no' or job.get('networks') != ['backend']:
    raise SystemExit('finite bootstrap lifecycle/network boundary is wrong')
if job.get('stop_signal') != 'SIGTERM':
    raise SystemExit('finite bootstrap does not override the inherited SIGWINCH')
if job.get('healthcheck', {}).get('disable') is not True:
    raise SystemExit('finite bootstrap must not use daemon health semantics')
for relative in (
    'templates/espocrm-daemon/docker-compose.espocrm-daemon.yaml',
    'templates/espocrm-websocket/docker-compose.espocrm-websocket.yaml',
):
    text = (root / relative).read_text()
    if 'secrets: *app_common_secrets' not in text or 'MARIADB_PASSWORD' in text:
        raise SystemExit(f'{relative}: runtime secrets are not inherited OIDC-only')
websocket_text = (root / 'templates/espocrm-websocket/docker-compose.espocrm-websocket.yaml').read_text()
if 'Path(`/wss`)' not in websocket_text or 'PathPrefix(`/wss`)' in websocket_text:
    raise SystemExit('WebSocket router is not restricted to the exact /wss path')
reader_text = (root / 'EspoCRM/scripts/espocrm-secret-reader.pl').read_text()
if 'use Time::HiRes qw(stat lstat);' not in reader_text:
    raise SystemExit('secret reader metadata comparisons are not high-resolution')
if 'defined($seek_result) && $seek_result == 0' not in reader_text:
    raise SystemExit('secret reader does not reject an undefined rewind result')

env_text = (root / 'EspoCRM/.env').read_text()
override_text = (root / 'EspoCRM/scripts/config-override-internal.php').read_text()
main_readme = (root / 'EspoCRM/README.md').read_text()
bootstrap_readme = (root / 'templates/espocrm-bootstrap/README.md').read_text()
daemon_readme = (root / 'templates/espocrm-daemon/README.md').read_text()
websocket_readme = (root / 'templates/espocrm-websocket/README.md').read_text()

if 'ESPOCRM_OIDC_USERNAME_CLAIM=sub' not in env_text or "?: 'sub'" not in override_text:
    raise SystemExit('OIDC username identity is not bound to the immutable sub default')
for required in (
    'Authorization Code',
    'offline_access',
    'Bæsed on the User\'s hæshed ID',
    'API users',
    'EspoCRM Portæls',
    'appdata/data/config.php',
    './run.sh EspoCRM --update',
    '--no-build --pull never',
    'service_completed_successfully',
):
    if required not in main_readme:
        raise SystemExit(f'EspoCRM README is missing lifecycle/security boundary: {required}')
for template in ('mariadb', 'mariadb_maintenance', 'espocrm-bootstrap', 'espocrm-daemon', 'espocrm-websocket'):
    if f'- {template}' not in main_readme:
        raise SystemExit(f'EspoCRM README omits required template {template}')
if 'This deployment uses `preferred_username`' in main_readme:
    raise SystemExit('EspoCRM README still claims the retired preferred_username default')
if 'docker compose --env-file .env -f docker-compose.main.yaml pull app' in main_readme:
    raise SystemExit('EspoCRM README still recommends a partial image pull')
if 'tar --acls --xattrs --numeric-owner -xzf' in main_readme:
    raise SystemExit('EspoCRM README still exposes an unsafe direct production extraction recipe')
if 'long-running root Æpæche' not in bootstrap_readme:
    raise SystemExit('bootstrap README understates long-running Apache capabilities')
if 'freshness' not in daemon_readme or 'synthetic' not in daemon_readme:
    raise SystemExit('daemon README omits scheduler-progress monitoring')
for relative, readme in (
    ('espocrm-daemon', daemon_readme),
    ('espocrm-websocket', websocket_readme),
):
    if 'mounts only `MARIADB_PASSWORD`' in readme:
        raise SystemExit(f'{relative} README still claims a MariaDB Docker-secret mount')
    if '`ESPOCRM_OIDC_CLIENT_ID` ænd `ESPOCRM_OIDC_CLIENT_SECRET`' not in readme:
        raise SystemExit(f'{relative} README omits the OIDC-only runtime secret subset')
PY
}

expect_success static-contract static_contract

reader_negative_matrix() {
  local fixture="${TEST_ROOT}/reader-matrix"
  mkdir -m 0700 -- "${fixture}"
  printf 'valid-secret-value' >"${fixture}/valid"
  "${SECRET_READER}" "${fixture}/valid" 1 >/dev/null

  ln -s -- valid "${fixture}/symlink"
  ! "${SECRET_READER}" "${fixture}/symlink" 1 >/dev/null 2>&1

  ln -- "${fixture}/valid" "${fixture}/hardlink"
  ! "${SECRET_READER}" "${fixture}/valid" 1 >/dev/null 2>&1
  rm -f -- "${fixture}/hardlink"

  mkfifo -- "${fixture}/fifo"
  ! timeout 2 "${SECRET_READER}" "${fixture}/fifo" 1 >/dev/null 2>&1

  printf '\377invalid' >"${fixture}/invalid-utf8"
  ! "${SECRET_READER}" "${fixture}/invalid-utf8" 1 >/dev/null 2>&1
}
expect_success descriptor-secret-reader-negative-matrix reader_negative_matrix

runtime_supervisor_pre_spawn_term() {
  local kind="$1"
  local script_path vendor_variable vendor_marker ready_marker release_marker supervisor_pid
  script_path="${TEST_REPO_ROOT}/templates/espocrm-${kind}/scripts/espocrm-${kind}-start.sh"
  vendor_variable="ESPOCRM_VENDOR_${kind^^}_BIN"
  vendor_variable="${vendor_variable//-/_}"
  vendor_marker="${TEST_ROOT}/${kind}-vendor-started"
  ready_marker="${TEST_ROOT}/${kind}-lock-ready"
  release_marker="${TEST_ROOT}/${kind}-lock-release"

  cat >"${TEST_ROOT}/${kind}-blocking-lock.sh" <<'LOCK'
#!/usr/bin/env bash
acquire_espocrm_runtime_lock() {
  : >"${ESPO_TEST_LOCK_READY}"
  while [[ ! -f "${ESPO_TEST_LOCK_RELEASE}" ]]; do sleep 0.05; done
}
LOCK
  cat >"${TEST_ROOT}/${kind}-vendor-stub" <<'VENDOR'
#!/usr/bin/env bash
: >"${ESPO_TEST_VENDOR_MARKER}"
VENDOR
  chmod 0755 "${TEST_ROOT}/${kind}-blocking-lock.sh" "${TEST_ROOT}/${kind}-vendor-stub"

  env \
    "${vendor_variable}=${TEST_ROOT}/${kind}-vendor-stub" \
    ESPOCRM_RUNTIME_LOCK_HELPER="${TEST_ROOT}/${kind}-blocking-lock.sh" \
    ESPO_TEST_LOCK_READY="${ready_marker}" \
    ESPO_TEST_LOCK_RELEASE="${release_marker}" \
    ESPO_TEST_VENDOR_MARKER="${vendor_marker}" \
    /bin/bash "${script_path}" &
  supervisor_pid=$!
  for _ in {1..50}; do
    [[ -f "${ready_marker}" ]] && break
    sleep 0.02
  done
  [[ -f "${ready_marker}" ]]
  kill -TERM "${supervisor_pid}"
  : >"${release_marker}"
  wait "${supervisor_pid}"
  [[ ! -e "${vendor_marker}" ]]
}
expect_success daemon-pre-spawn-term runtime_supervisor_pre_spawn_term daemon
expect_success websocket-pre-spawn-term runtime_supervisor_pre_spawn_term websocket

printf 'false' >"${STATE_FILE}"
expect_success setup-secret-snapshot-is-stable run_wrapper "${SETUP_SECRETS}" snapshot --bootstrap
printf 'strong-admin-password' >"${SETUP_SECRETS}/ESPOCRM_ADMIN_PASSWORD"
printf 'false' >"${STATE_FILE}"
expect_success fresh-bootstrap run_wrapper "${SETUP_SECRETS}" fresh --bootstrap
if [[ -f "${DATA_DIR}/.saervices-bootstrap-state" ]]; then
  pass bootstrap-marker-published
else
  fail bootstrap-marker-published
fi
expect_success runtime-without-setup-secrets run_wrapper "${RUNTIME_SECRETS}" installed --runtime apache2-foreground

ESPO_TEST_IMAGE_VERSION=10.0.1 expect_failure image-version-mismatch run_wrapper "${RUNTIME_SECRETS}" installed --runtime apache2-foreground

rm -f -- "${SETUP_SECRETS}/ESPOCRM_ADMIN_PASSWORD" "${SETUP_SECRETS}/MARIADB_PASSWORD"
expect_success installed-bootstrap-skips-setup-secrets run_wrapper "${RUNTIME_SECRETS}" installed --bootstrap

printf '\n# digest drift\n' >>"${WRAPPER}"
expect_failure stale-wrapper-marker run_wrapper "${RUNTIME_SECRETS}" installed --runtime apache2-foreground
cp -- "${TEST_REPO_ROOT}/EspoCRM/scripts/espocrm-start.sh" "${WRAPPER}"
chmod 0755 "${WRAPPER}"
expect_success republish-current-marker run_wrapper "${RUNTIME_SECRETS}" installed --bootstrap

expect_failure failed-migration run_wrapper "${RUNTIME_SECRETS}" fail --bootstrap
if [[ -e "${DATA_DIR}/.saervices-bootstrap-state" || -L "${DATA_DIR}/.saervices-bootstrap-state" ]]; then
  fail failed-migration-invalidates-marker
else
  pass failed-migration-invalidates-marker
fi
expect_failure runtime-rejects-missing-marker run_wrapper "${RUNTIME_SECRETS}" installed --runtime apache2-foreground
expect_success restore-marker-for-lock-tests run_wrapper "${RUNTIME_SECRETS}" installed --bootstrap

shared_holder() {
  ESPOCRM_DATA_DIR="${DATA_DIR}" bash -c 'source "$1"; acquire_espocrm_runtime_lock shared; sleep 1' bash "${LOCK_HELPER}" &
  local holder=$!
  sleep 0.1
  if ESPOCRM_DATA_DIR="${DATA_DIR}" bash -c 'source "$1"; acquire_espocrm_runtime_lock exclusive' bash "${LOCK_HELPER}"; then
    kill "${holder}" 2>/dev/null || true
    wait "${holder}" 2>/dev/null || true
    return 1
  fi
  wait "${holder}"
}
expect_success shared-runtime-blocks-bootstrap shared_holder

rm -f -- "${CHILD_TERM_MARKER}" "${VENDOR_MARKER}"
run_wrapper "${RUNTIME_SECRETS}" wait --bootstrap >"${TEST_ROOT}/interrupted.out" 2>&1 &
bootstrap_pid=$!
for _ in {1..50}; do
  [[ -f "${VENDOR_MARKER}" ]] && break
  sleep 0.05
done
test -f "${VENDOR_MARKER}"
kill -TERM "${bootstrap_pid}"
if wait "${bootstrap_pid}"; then
  fail interrupted-bootstrap-is-nonzero
else
  pass interrupted-bootstrap-is-nonzero
fi
test -f "${CHILD_TERM_MARKER}" && pass interrupted-child-retired || fail interrupted-child-retired
[[ ! -e "${DATA_DIR}/.saervices-bootstrap-state" ]] && pass interrupted-bootstrap-unpublished || fail interrupted-bootstrap-unpublished

expect_success restore-marker-after-interruption run_wrapper "${RUNTIME_SECRETS}" installed --bootstrap
rm -f -- "${VENDOR_MARKER}"
run_wrapper "${RUNTIME_SECRETS}" ignore-term --bootstrap >"${TEST_ROOT}/ignore-term.out" 2>&1 &
bootstrap_pid=$!
for _ in {1..50}; do
  [[ -f "${VENDOR_MARKER}" ]] && break
  sleep 0.05
done
test -f "${VENDOR_MARKER}"
kill -TERM "${bootstrap_pid}"
start_seconds="${SECONDS}"
if wait "${bootstrap_pid}"; then
  fail ignored-term-bootstrap-is-nonzero
else
  pass ignored-term-bootstrap-is-nonzero
fi
(( SECONDS - start_seconds <= 3 )) && pass ignored-term-bootstrap-is-bounded || fail ignored-term-bootstrap-is-bounded
[[ ! -e "${DATA_DIR}/.saervices-bootstrap-state" ]] && pass ignored-term-bootstrap-unpublished || fail ignored-term-bootstrap-unpublished

printf 'EspoCRM bootstrap tests: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
