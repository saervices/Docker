#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS ÆND TEST HÆRNESS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/secret-preflights.XXXXXX")"
readonly TEST_BIN="${TEST_ROOT}/bin"
readonly TEST_CRYPTO="${TEST_ROOT}/crypto"

readonly ACTUALBUDGET_SCRIPT="${TEST_REPO_ROOT}/ActualBudget/scripts/actual-start.sh"
readonly AUTHENTIK_BOOTSTRAP_ENTRYPOINT="${TEST_REPO_ROOT}/templates/authentik-bootstrap/scripts/authentik-bootstrap-entrypoint.sh"
readonly AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT="${TEST_REPO_ROOT}/templates/authentik-bootstrap/scripts/authentik-bootstrap.py"
readonly REDIS_SCRIPT="${TEST_REPO_ROOT}/templates/redis/scripts/redis-start.sh"
readonly ELASTICSEARCH_SCRIPT="${TEST_REPO_ROOT}/templates/elasticsearch/scripts/elasticsearch-start.sh"
readonly SEASEARCH_SCRIPT="${TEST_REPO_ROOT}/templates/seafile_seasearch/scripts/seasearch-start.sh"
readonly FACTORIO_SCRIPT="${TEST_REPO_ROOT}/Factorio/dockerfiles/entrypoint.sh"
readonly ESPOCRM_SCRIPT="${TEST_REPO_ROOT}/EspoCRM/scripts/espocrm-start.sh"
readonly VAULTWARDEN_SCRIPT="${TEST_REPO_ROOT}/Vaultwarden/scripts/vaultwarden.d/10-database-url.sh"
readonly VAULTWARDEN_COMPOSE="${TEST_REPO_ROOT}/Vaultwarden/docker-compose.app.yaml"
readonly VAULTWARDEN_IMMUTABLE_CONFIG_FILE='/etc/vaultwarden.d/config.json'
readonly N8N_SCRIPT="${TEST_REPO_ROOT}/n8n/dockerfiles/entrypoint.sh"
readonly TRAEFIK_SCRIPT="${TEST_REPO_ROOT}/Traefik/scripts/traefik-start.sh"
readonly CERTS_DUMPER_SCRIPT="${TEST_REPO_ROOT}/templates/traefik_certs-dumper/dockerfiles/entrypoint.traefik_certs-dumper.sh"
readonly VIKUNJA_SCRIPT="${TEST_REPO_ROOT}/Vikunja/dockerfiles/entrypoint.sh"
readonly KIMAI_SCRIPT="${TEST_REPO_ROOT}/Kimai/scripts/kimai-start.sh"
readonly SEAFILE_SCRIPT="${TEST_REPO_ROOT}/Seafile/scripts/seafile-start.sh"
readonly SEAFILE_RUNTIME_PREPARER="${TEST_REPO_ROOT}/Seafile/scripts/prepare-seafile-runtime.py"

PASS=0
FAIL=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes disposæble fixtures unless evidence retention is requested.
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
#   Records one fæiled regression cæse ænd prints its cæptured output.
#ææææææææææææææææææææææææææææææææææ
fail() {
  local name="$1"
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$name"
  sed -n '1,40p' "${TEST_ROOT}/${name}.out" >&2 || true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_success
#   Runs one cæse in æ strict isolæted subshell ænd expects exit zero.
#ææææææææææææææææææææææææææææææææææ
expect_success() {
  local name="$1"
  local status
  shift
  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_failure
#   Runs one cæse in æ strict isolæted subshell ænd expects non-zero.
#ææææææææææææææææææææææææææææææææææ
expect_failure() {
  local name="$1"
  local status
  shift
  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status != 0 )); then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: exercise_secret_matrix
#   Exercises missing, empty, exæct CHANGE_ME, multi-line, ænd control-chæræcter fixtures.
#   Ærguments:
#     $1 - suite næme
#     $2 - fixture-prepærætion function
#     $3 - wrapper-runner function
#     $4 - secret filenæme
#ææææææææææææææææææææææææææææææææææ
exercise_secret_matrix() {
  local suite="$1"
  local prepare_fixture="$2"
  local run_wrapper="$3"
  local secret_name="$4"
  local variant fixture secret_file

  for variant in missing empty change-me multi-line control-char; do
    fixture="${TEST_ROOT}/${suite}-${variant}"
    "$prepare_fixture" "$fixture"
    secret_file="${fixture}/secrets/${secret_name}"
    case "$variant" in
      missing) rm -f -- "$secret_file" ;;
      empty) : >"$secret_file" ;;
      change-me) printf 'CHANGE_ME' >"$secret_file" ;;
      multi-line) printf 'line-one\nline-two' >"$secret_file" ;;
      control-char) printf 'vælid\001secret' >"$secret_file" ;;
    esac
    expect_failure "${suite}-${variant}" "$run_wrapper" "$fixture"
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SHÆRED FIXTURES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
mkdir -p -- "$TEST_BIN" "$TEST_CRYPTO"

printf '%s\n' '#!/bin/sh' 'exit 0' >"${TEST_BIN}/n8n"
printf '%s\n' \
  '#!/bin/sh' \
  '[ -z "${TRAEFIK_MARKER:-}" ] || printf "%s\n" "$@" >"$TRAEFIK_MARKER"' \
  'exit 0' >"${TEST_BIN}/traefik"
printf '%s\n' '#!/bin/sh' '[ -z "${CERTS_DUMPER_MARKER:-}" ] || : >"$CERTS_DUMPER_MARKER"' 'exit 0' >"${TEST_BIN}/traefik-certs-dumper"
printf '%s\n' \
  '#!/bin/sh' \
  'printf "%s\n" "$*" >>"$AUTHENTIK_BOOTSTRAP_STUB_MARKER"' \
  'if [ "$1" = "$AUTHENTIK_BOOTSTRAP_HELPER" ] && [ "$2" = orchestrate ]; then' \
  '  test -r "$3"' \
  '  exit "${AUTHENTIK_BOOTSTRAP_STUB_ORCHESTRATE_STATUS:-0}"' \
  'fi' \
  'exit 97' >"${TEST_BIN}/authentik-bootstrap-python"
printf '%s\n' \
  '#!/bin/sh' \
  'env >"$FACTORIO_CAPTURE_ENV"' \
  'printf "%s\\n" "$@" >"$FACTORIO_CAPTURE_ARGV"' \
  'exit 0' >"${TEST_BIN}/factorio-capture"
printf '%s\n' \
  '#!/usr/bin/env python3' \
  'import os' \
  'import sys' \
  'from urllib.parse import quote' \
  'if len(sys.argv) != 3: raise SystemExit("secret or unexpected argument reached php argv")' \
  'source = " ".join(sys.argv)' \
  'value = os.environ.get("MAILER_SMTP_USER", "") if "getenv" in source else sys.stdin.read()' \
  'print(quote(value, safe=""), end="")' >"${TEST_BIN}/kimai-php"
chmod 0700 \
  "${TEST_BIN}/n8n" \
  "${TEST_BIN}/traefik" \
  "${TEST_BIN}/traefik-certs-dumper" \
  "${TEST_BIN}/authentik-bootstrap-python" \
  "${TEST_BIN}/factorio-capture" \
  "${TEST_BIN}/kimai-php"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=preflight.test' \
  -keyout "${TEST_CRYPTO}/idp.key" -out "${TEST_CRYPTO}/idp.pem" >/dev/null 2>&1
openssl x509 -in "${TEST_CRYPTO}/idp.pem" -outform DER \
  | openssl base64 -A >"${TEST_CRYPTO}/idp.der.b64"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ÆCTUÆL BUDGET
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_actualbudget() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'provider-client-id' >"${fixture}/secrets/ACTUALBUDGET_OPENID_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET"
}

run_actualbudget() {
  local fixture="$1"
  ACTUALBUDGET_OPENID_CLIENT_ID_FILE="${fixture}/secrets/ACTUALBUDGET_OPENID_CLIENT_ID" \
    ACTUALBUDGET_OPENID_CLIENT_SECRET_FILE="${fixture}/secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET" \
    /bin/sh "$ACTUALBUDGET_SCRIPT" /bin/true
}

case_actualbudget_oversized_secret() {
  local fixture="${TEST_ROOT}/actualbudget-secret-oversized"
  prepare_actualbudget "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET"
  run_actualbudget "$fixture"
}

prepare_actualbudget "${TEST_ROOT}/actualbudget-valid"
expect_success actualbudget-valid run_actualbudget "${TEST_ROOT}/actualbudget-valid"
exercise_secret_matrix actualbudget-oidc-id prepare_actualbudget run_actualbudget ACTUALBUDGET_OPENID_CLIENT_ID
exercise_secret_matrix actualbudget-oidc-secret prepare_actualbudget run_actualbudget ACTUALBUDGET_OPENID_CLIENT_SECRET
expect_failure actualbudget-secret-oversized case_actualbudget_oversized_secret

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ÆUTHENTIK ONE-SHOT BOOTSTRÆP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_authentik_bootstrap() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'strong-bootstrap-password' >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
}

run_authentik_bootstrap_secret_preflight() {
  local fixture="$1"
  python3 - "$AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT" \
    "${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD" <<'PY'
import importlib.util
import sys
from pathlib import Path

helper_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("authentik_bootstrap_preflight", helper_path)
if spec is None or spec.loader is None:
    raise SystemExit(1)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
password = module.read_password(Path(sys.argv[2]))
if password != "strong-bootstrap-password":
    raise SystemExit(1)
PY
}

run_authentik_bootstrap_entrypoint() {
  local fixture="$1"
  local marker="${fixture}/entrypoint.calls"
  : >"$marker"
  AUTHENTIK_BOOTSTRAP_PASSWORD_FILE="${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD" \
    AUTHENTIK_BOOTSTRAP_PYTHON="${TEST_BIN}/authentik-bootstrap-python" \
    AUTHENTIK_BOOTSTRAP_HELPER="$AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT" \
    AUTHENTIK_BOOTSTRAP_STUB_MARKER="$marker" \
    /bin/sh "$AUTHENTIK_BOOTSTRAP_ENTRYPOINT" bootstrap
}

case_authentik_bootstrap_short_password() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-short"
  prepare_authentik_bootstrap "$fixture"
  printf 'too-short' >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_bootstrap_secret_preflight "$fixture"
}

case_authentik_bootstrap_oversized_password() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-oversized"
  prepare_authentik_bootstrap "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_bootstrap_secret_preflight "$fixture"
}

case_authentik_bootstrap_symlink_password() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-symlink"
  prepare_authentik_bootstrap "$fixture"
  printf 'strong-bootstrap-password' >"${fixture}/bootstrap-target"
  rm -f -- "${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  ln -s -- ../bootstrap-target "${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_bootstrap_secret_preflight "$fixture"
}

case_authentik_bootstrap_fifo_password() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-fifo"
  prepare_authentik_bootstrap "$fixture"
  rm -f -- "${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  mkfifo -- "${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_bootstrap_secret_preflight "$fixture"
}

case_authentik_bootstrap_invalid_utf8_password() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-invalid-utf8"
  prepare_authentik_bootstrap "$fixture"
  printf '\377abcdefghijk' >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_bootstrap_secret_preflight "$fixture"
}

case_authentik_bootstrap_entrypoint_handoff() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-entrypoint-handoff"
  local marker="${fixture}/entrypoint.calls"
  prepare_authentik_bootstrap "$fixture"
  run_authentik_bootstrap_entrypoint "$fixture"
  printf '%s\n' \
    "$AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT orchestrate ${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD" \
    | cmp -s - "$marker"
}

case_authentik_bootstrap_entrypoint_failure() {
  local fixture="${TEST_ROOT}/authentik-bootstrap-entrypoint-failure"
  local marker="${fixture}/entrypoint.calls"
  prepare_authentik_bootstrap "$fixture"
  : >"$marker"
  AUTHENTIK_BOOTSTRAP_PASSWORD_FILE="${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD" \
    AUTHENTIK_BOOTSTRAP_PYTHON="${TEST_BIN}/authentik-bootstrap-python" \
    AUTHENTIK_BOOTSTRAP_HELPER="$AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT" \
    AUTHENTIK_BOOTSTRAP_STUB_MARKER="$marker" \
    AUTHENTIK_BOOTSTRAP_STUB_ORCHESTRATE_STATUS=31 \
    /bin/sh "$AUTHENTIK_BOOTSTRAP_ENTRYPOINT" bootstrap
}

case_authentik_bootstrap_orchestration() {
  python3 - "$AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT" <<'PY'
import importlib.util
import sys
import types
from pathlib import Path

helper_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("authentik_bootstrap_orchestration", helper_path)
if spec is None or spec.loader is None:
    raise SystemExit(1)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

django = types.ModuleType("django")
django_db = types.ModuleType("django.db")
class DatabaseError(Exception):
    pass
django_db.DatabaseError = DatabaseError
django.db = django_db
sys.modules["django"] = django
sys.modules["django.db"] = django_db

module.bounded_seconds = lambda _name, default, _minimum, _maximum: default

calls = []
module.run_migrations = lambda migration_timeout, stop_timeout: calls.append(
    ("migrate", migration_timeout, stop_timeout)
)
module.configure_django = lambda: calls.append(("configure",))
module.database_state = lambda: (True, set())
module.run_bootstrap = lambda *_args: calls.append(("unexpected-bootstrap",))
module.orchestrate(Path("/missing-secret-is-not-read"))
if calls != [("migrate", 3600, 60), ("configure",)]:
    raise SystemExit(f"initialized orchestration drifted: {calls!r}")

calls.clear()
module.database_state = lambda: (False, {"public"})
module.run_bootstrap = lambda secret, pending, ready, stop: calls.append(
    ("bootstrap", str(secret), pending, ready, stop)
)
module.orchestrate(Path("/fresh-secret"))
if calls != [
    ("migrate", 3600, 60),
    ("configure",),
    ("bootstrap", "/fresh-secret", {"public"}, 900, 60),
]:
    raise SystemExit(f"fresh orchestration drifted: {calls!r}")

calls.clear()
def interrupt_during_migration(_migration_timeout, _stop_timeout):
    calls.append(("migrate-interrupted",))
    module.INTERRUPTED = True
module.run_migrations = interrupt_during_migration
module.configure_django = lambda: calls.append(("unexpected-configure",))
try:
    module.orchestrate(Path("/interrupt-secret"))
except SystemExit as error:
    if error.code == 0:
        raise SystemExit("interrupted one-shot exited successfully")
else:
    raise SystemExit("interrupted one-shot did not fail")
if calls != [("migrate-interrupted",)]:
    raise SystemExit(f"interrupted orchestration released later phases: {calls!r}")
PY
}

case_authentik_bootstrap_process_contracts() {
  python3 - "$AUTHENTIK_BOOTSTRAP_HELPER_SCRIPT" <<'PY'
import importlib.util
import os
import subprocess
import sys
import types
from pathlib import Path

helper_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("authentik_bootstrap_contracts", helper_path)
if spec is None or spec.loader is None:
    raise SystemExit(1)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def expect_nonzero(function, message):
    try:
        function()
    except SystemExit as error:
        if error.code == 0:
            raise SystemExit(message)
    else:
        raise SystemExit(message)


if module.VENDOR_IMPORT_ROOT != "/":
    raise SystemExit("authentik vendor import root drifted")
if module.VENDOR_SETUP_MODULE != "/authentik/root/setup.py":
    raise SystemExit("authentik vendor setup module path drifted")
original_lstat = module.os.lstat
module.os.lstat = lambda path: types.SimpleNamespace(st_mode=0o100444)
while "/" in sys.path:
    sys.path.remove("/")
module.configure_vendor_import_path()
if not sys.path or sys.path[0] != "/":
    raise SystemExit("validated authentik vendor source root was not prepended")
sys.path.append(sys.path.pop(0))
module.configure_vendor_import_path()
if sys.path[0] != "/" or sys.path.count("/") != 1:
    raise SystemExit("existing authentik vendor source root did not get deterministic precedence")
module.os.lstat = lambda path: types.SimpleNamespace(st_mode=0o040755)
expect_nonzero(
    module.configure_vendor_import_path,
    "non-regular authentik vendor setup module was accepted",
)
module.os.lstat = original_lstat


django = types.ModuleType("django")
django.__path__ = []
django_db = types.ModuleType("django.db")


class DatabaseError(Exception):
    pass


django_db.DatabaseError = DatabaseError
django_db.close_old_connections = lambda: None
django.db = django_db
django_contrib = types.ModuleType("django.contrib")
django_contrib.__path__ = []
django_auth = types.ModuleType("django.contrib.auth")
django_auth.__path__ = []
django_hashers = types.ModuleType("django.contrib.auth.hashers")
django_hashers.make_password = lambda _password: "pbkdf2_sha256$fixture"
django.contrib = django_contrib
django_contrib.auth = django_auth
django_auth.hashers = django_hashers
sys.modules["django"] = django
sys.modules["django.db"] = django_db
sys.modules["django.contrib"] = django_contrib
sys.modules["django.contrib.auth"] = django_auth
sys.modules["django.contrib.auth.hashers"] = django_hashers

authentik = types.ModuleType("authentik")
authentik.__path__ = []
authentik_core = types.ModuleType("authentik.core")
authentik_core.__path__ = []
authentik_models = types.ModuleType("authentik.core.models")
authentik.core = authentik_core
authentik_core.models = authentik_models
sys.modules["authentik"] = authentik
sys.modules["authentik.core"] = authentik_core
sys.modules["authentik.core.models"] = authentik_models


class Tenant:
    schema_name = "public"

    def __enter__(self):
        return self

    def __exit__(self, _exc_type, _exc, _traceback):
        return False


class Groups:
    def __init__(self, superuser):
        self.superuser = superuser

    def filter(self, **query):
        if query != {"is_superuser": True}:
            raise AssertionError(query)
        return self

    def exists(self):
        return self.superuser


class UserRow:
    def __init__(self, *, active=True, password="pbkdf2_sha256$fixture", superuser=True):
        self.is_active = active
        self.password = password
        self.groups = Groups(superuser)


user_state = {"row": UserRow()}


class UserManager:
    def filter(self, **query):
        if query != {"username": "akadmin"}:
            raise AssertionError(query)
        return self

    def first(self):
        return user_state["row"]


class User:
    objects = UserManager()


authentik_models.User = User
tenant = Tenant()
module.ready_tenants = lambda: [tenant]
module.tenant_is_initialized = lambda _tenant: True
if not module.expected_setup_is_persisted("pbkdf2_sha256$fixture", {"public"}):
    raise SystemExit("exact persisted setup verifier was rejected")
for row in (
    None,
    UserRow(active=False),
    UserRow(password="pbkdf2_sha256$wrong"),
    UserRow(superuser=False),
):
    user_state["row"] = row
    if module.expected_setup_is_persisted("pbkdf2_sha256$fixture", {"public"}):
        raise SystemExit("invalid persisted setup state was accepted")
user_state["row"] = UserRow()
if module.expected_setup_is_persisted("pbkdf2_sha256$fixture", {"missing"}):
    raise SystemExit("unknown pending tenant schema was accepted")
module.tenant_is_initialized = lambda _tenant: False
if module.expected_setup_is_persisted("pbkdf2_sha256$fixture", {"public"}):
    raise SystemExit("missing persistent setup marker was accepted")
module.tenant_is_initialized = lambda _tenant: True


class WorkerProcess:
    def __init__(self, returncode=None):
        self.returncode = returncode
        self.terminated = 0
        self.killed = 0

    def poll(self):
        return self.returncode

    def terminate(self):
        self.terminated += 1

    def kill(self):
        self.killed += 1
        self.returncode = -9

    def wait(self, timeout=None):
        del timeout
        if self.returncode is None:
            self.returncode = 0
        return self.returncode


module.read_password = lambda _path: "strong-bootstrap-password"
module.expected_setup_is_persisted = lambda _hash, _pending: True
captured = {}
successful_worker = WorkerProcess()


def start_successful_worker(arguments, *, env, stdin):
    captured["arguments"] = arguments
    captured["environment"] = env.copy()
    captured["stdin"] = stdin
    return successful_worker


module.subprocess.Popen = start_successful_worker
module.INTERRUPTED = False
module.run_bootstrap(Path("/unused"), {"public"}, 60, 10)
if captured["arguments"] != ["/lifecycle/ak", "worker"]:
    raise SystemExit("native worker command drifted")
if captured["stdin"] is not subprocess.DEVNULL:
    raise SystemExit("native worker inherited stdin")
child_environment = captured["environment"]
if child_environment.get("AUTHENTIK_BOOTSTRAP_PASSWORD_HASH") != "pbkdf2_sha256$fixture":
    raise SystemExit("native worker did not receive the generated verifier")
if {"AUTHENTIK_BOOTSTRAP_PASSWORD", "AUTHENTIK_BOOTSTRAP_TOKEN"} & set(child_environment):
    raise SystemExit("plaintext bootstrap credential reached native worker")
if successful_worker.terminated != 1 or successful_worker.killed != 0:
    raise SystemExit("verified native worker was not retired cleanly")

early_worker = WorkerProcess(returncode=23)
module.subprocess.Popen = lambda *_args, **_kwargs: early_worker
module.INTERRUPTED = False
expect_nonzero(
    lambda: module.run_bootstrap(Path("/unused"), {"public"}, 60, 10),
    "early native-worker exit released one-shot successfully",
)

interrupted_worker = WorkerProcess()
module.subprocess.Popen = lambda *_args, **_kwargs: interrupted_worker
module.INTERRUPTED = True
expect_nonzero(
    lambda: module.run_bootstrap(Path("/unused"), {"public"}, 60, 10),
    "interrupted native worker released one-shot successfully",
)
if interrupted_worker.terminated != 1 or interrupted_worker.killed != 0:
    raise SystemExit("interrupted native worker was not retired cleanly")


class MigrationProcess(WorkerProcess):
    pass


class StuckProcess(WorkerProcess):
    def wait(self, timeout=None):
        if self.killed:
            return self.returncode
        raise subprocess.TimeoutExpired("authentik-test-child", timeout)


stuck_process = StuckProcess()
return_code, required_kill = module.terminate_process(stuck_process, 10)
if return_code != -9 or not required_kill:
    raise SystemExit("bounded child termination did not report forced kill")
if stuck_process.terminated != 1 or stuck_process.killed != 1:
    raise SystemExit("bounded child termination did not TERM then KILL")

stuck_worker = StuckProcess()
expect_nonzero(
    lambda: module.stop_worker(stuck_worker, 10),
    "stuck native worker was accepted after its shutdown deadline",
)
if stuck_worker.terminated != 1 or stuck_worker.killed != 1:
    raise SystemExit("stuck native worker did not TERM then KILL")


for secret_name in (
    "AUTHENTIK_BOOTSTRAP_PASSWORD",
    "AUTHENTIK_BOOTSTRAP_PASSWORD_HASH",
    "AUTHENTIK_BOOTSTRAP_TOKEN",
):
    os.environ[secret_name] = "must-not-reach-migrations"
migration_capture = {}


def start_successful_migration(arguments, *, env, stdin):
    migration_capture["arguments"] = arguments
    migration_capture["environment"] = env.copy()
    migration_capture["stdin"] = stdin
    return MigrationProcess(returncode=0)


module.subprocess.Popen = start_successful_migration
module.INTERRUPTED = False
module.run_migrations(60, 10)
if migration_capture["arguments"] != [sys.executable, "-m", "lifecycle.migrate"]:
    raise SystemExit("native migration command drifted")
if migration_capture["stdin"] is not subprocess.DEVNULL:
    raise SystemExit("native migration inherited stdin")
if any(name in migration_capture["environment"] for name in (
    "AUTHENTIK_BOOTSTRAP_PASSWORD",
    "AUTHENTIK_BOOTSTRAP_PASSWORD_HASH",
    "AUTHENTIK_BOOTSTRAP_TOKEN",
)):
    raise SystemExit("bootstrap credential reached native migrations")

failed_migration = MigrationProcess(returncode=17)
module.subprocess.Popen = lambda *_args, **_kwargs: failed_migration
module.INTERRUPTED = False
expect_nonzero(
    lambda: module.run_migrations(60, 10),
    "failed migration released one-shot successfully",
)

interrupted_migration = MigrationProcess()
module.subprocess.Popen = lambda *_args, **_kwargs: interrupted_migration
module.INTERRUPTED = True
expect_nonzero(
    lambda: module.run_migrations(60, 10),
    "interrupted migration released one-shot successfully",
)
if interrupted_migration.terminated != 1 or interrupted_migration.killed != 0:
    raise SystemExit("interrupted migration was not retired cleanly")

os.environ["AUTHENTIK_BOOTSTRAP_STOP_TIMEOUT_SECONDS"] = "61"
expect_nonzero(
    lambda: module.bounded_seconds(
        "AUTHENTIK_BOOTSTRAP_STOP_TIMEOUT_SECONDS", 60, 10, 60
    ),
    "stop timeout beyond Compose grace margin was accepted",
)
PY
}

prepare_authentik_bootstrap "${TEST_ROOT}/authentik-bootstrap-valid"
expect_success authentik-bootstrap-valid run_authentik_bootstrap_secret_preflight "${TEST_ROOT}/authentik-bootstrap-valid"
exercise_secret_matrix authentik-bootstrap-password prepare_authentik_bootstrap run_authentik_bootstrap_secret_preflight AUTHENTIK_BOOTSTRAP_PASSWORD
expect_failure authentik-bootstrap-password-short case_authentik_bootstrap_short_password
expect_failure authentik-bootstrap-password-oversized case_authentik_bootstrap_oversized_password
expect_failure authentik-bootstrap-password-symlink case_authentik_bootstrap_symlink_password
expect_failure authentik-bootstrap-password-fifo case_authentik_bootstrap_fifo_password
expect_failure authentik-bootstrap-password-invalid-utf8 case_authentik_bootstrap_invalid_utf8_password
expect_success authentik-bootstrap-entrypoint-handoff case_authentik_bootstrap_entrypoint_handoff
expect_failure authentik-bootstrap-entrypoint-failure case_authentik_bootstrap_entrypoint_failure
expect_success authentik-bootstrap-orchestration case_authentik_bootstrap_orchestration
expect_success authentik-bootstrap-process-contracts case_authentik_bootstrap_process_contracts

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REDIS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_redis() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'strong-redis-password' >"${fixture}/secrets/REDIS_PASSWORD"
}

run_redis() {
  local fixture="$1"
  REDIS_PASSWORD_FILE="${fixture}/secrets/REDIS_PASSWORD" \
    /bin/sh "$REDIS_SCRIPT" --preflight-only
}

case_redis_short_password() {
  local fixture="${TEST_ROOT}/redis-short"
  prepare_redis "$fixture"
  printf 'too-short' >"${fixture}/secrets/REDIS_PASSWORD"
  run_redis "$fixture"
}

case_redis_oversized_password() {
  local fixture="${TEST_ROOT}/redis-oversized"
  prepare_redis "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/REDIS_PASSWORD"
  run_redis "$fixture"
}

prepare_redis "${TEST_ROOT}/redis-valid"
expect_success redis-valid run_redis "${TEST_ROOT}/redis-valid"
exercise_secret_matrix redis-password prepare_redis run_redis REDIS_PASSWORD
expect_failure redis-password-short case_redis_short_password
expect_failure redis-password-oversized case_redis_oversized_password

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ELÆSTICSEÆRCH
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_elasticsearch() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'strong-elasticsearch-password' >"${fixture}/secrets/ELASTICSEARCH_PASSWORD"
}

run_elasticsearch() {
  local fixture="$1"
  ELASTIC_PASSWORD_FILE="${fixture}/secrets/ELASTICSEARCH_PASSWORD" \
    /bin/bash "$ELASTICSEARCH_SCRIPT" --preflight-only
}

case_elasticsearch_short_password() {
  local fixture="${TEST_ROOT}/elasticsearch-short"
  prepare_elasticsearch "$fixture"
  printf 'too-short' >"${fixture}/secrets/ELASTICSEARCH_PASSWORD"
  run_elasticsearch "$fixture"
}

case_elasticsearch_oversized_password() {
  local fixture="${TEST_ROOT}/elasticsearch-oversized"
  prepare_elasticsearch "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/ELASTICSEARCH_PASSWORD"
  run_elasticsearch "$fixture"
}

prepare_elasticsearch "${TEST_ROOT}/elasticsearch-valid"
expect_success elasticsearch-valid run_elasticsearch "${TEST_ROOT}/elasticsearch-valid"
exercise_secret_matrix elasticsearch-password prepare_elasticsearch run_elasticsearch ELASTICSEARCH_PASSWORD
expect_failure elasticsearch-password-short case_elasticsearch_short_password
expect_failure elasticsearch-password-oversized case_elasticsearch_oversized_password

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- FÆCTORIO
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_factorio() {
  local fixture="$1"
  local factorio_root="${fixture}/factorio"
  mkdir -p -- \
    "${factorio_root}/config" \
    "${factorio_root}/mods" \
    "${factorio_root}/saves" \
    "${factorio_root}/scenarios" \
    "${factorio_root}/script-output" \
    "${fixture}/runtime" \
    "${fixture}/secrets"
  cp -- "${TEST_REPO_ROOT}/Factorio/appdata/config/server-settings.json" "${factorio_root}/config/server-settings.json"
  cp -- "${TEST_REPO_ROOT}/Factorio/appdata/config/map-gen-settings.json" "${factorio_root}/config/map-gen-settings.json"
  cp -- "${TEST_REPO_ROOT}/Factorio/appdata/config/map-settings.json" "${factorio_root}/config/map-settings.json"
  cp -- "${TEST_REPO_ROOT}/Factorio/appdata/mods/mod-list.json" "${factorio_root}/mods/mod-list.json"
  printf '[]\n' >"${factorio_root}/config/server-adminlist.json"
  printf '[]\n' >"${factorio_root}/config/server-banlist.json"
  printf '[]\n' >"${factorio_root}/config/server-whitelist.json"
  printf 'factorio-account-name' >"${fixture}/secrets/FACTORIO_USERNAME"
  printf 'factorio-provider-token' >"${fixture}/secrets/FACTORIO_TOKEN"
  printf 'strong-game-password' >"${fixture}/secrets/FACTORIO_GAME_PASSWORD"
  printf 'strong-rcon-password' >"${fixture}/secrets/FACTORIO_RCON_PASSWORD"
}

run_factorio() {
  local fixture="$1"
  FACTORIO_BIN=/bin/true \
    FACTORIO_VOL="${fixture}/factorio" \
    RUNTIME_DIR="${fixture}/runtime" \
    UPDATE_MODS_ON_START=true \
    FACTORIO_USERNAME_FILE="${fixture}/secrets/FACTORIO_USERNAME" \
    FACTORIO_TOKEN_FILE="${fixture}/secrets/FACTORIO_TOKEN" \
    FACTORIO_GAME_PASSWORD_FILE="${fixture}/secrets/FACTORIO_GAME_PASSWORD" \
    FACTORIO_RCON_PASSWORD_FILE="${fixture}/secrets/FACTORIO_RCON_PASSWORD" \
    /bin/bash "$FACTORIO_SCRIPT" --preflight-only
}

case_factorio_oversized_secret() {
  local fixture="${TEST_ROOT}/factorio-rcon-oversized"
  prepare_factorio "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/FACTORIO_RCON_PASSWORD"
  run_factorio "$fixture"
}

case_factorio_final_process_drops_portal_credentials() {
  local fixture="${TEST_ROOT}/factorio-final-process"
  local capture_env="${fixture}/factorio.env"
  local capture_argv="${fixture}/factorio.argv"
  local token='factorio-provider-token'
  local username='factorio-account-name'

  prepare_factorio "$fixture"
  : >"${fixture}/factorio/saves/existing.zip"

  FACTORIO_BIN="${TEST_BIN}/factorio-capture" \
    FACTORIO_CAPTURE_ENV="$capture_env" \
    FACTORIO_CAPTURE_ARGV="$capture_argv" \
    FACTORIO_VOL="${fixture}/factorio" \
    RUNTIME_DIR="${fixture}/runtime" \
    UPDATE_MODS_ON_START=false \
    DOWNLOAD_MISSING_MODS_ON_START=false \
    FACTORIO_USERNAME_FILE="${fixture}/secrets/FACTORIO_USERNAME" \
    FACTORIO_TOKEN_FILE="${fixture}/secrets/FACTORIO_TOKEN" \
    FACTORIO_GAME_PASSWORD_FILE="${fixture}/secrets/FACTORIO_GAME_PASSWORD" \
    FACTORIO_RCON_PASSWORD_FILE="${fixture}/secrets/FACTORIO_RCON_PASSWORD" \
    /bin/bash "$FACTORIO_SCRIPT"

  ! grep -Fq -- "$token" "$capture_env"
  ! grep -Fq -- "$username" "$capture_env"
  ! grep -Fq -- "$token" "$capture_argv"
  ! grep -Fq -- "$username" "$capture_argv"
  grep -Fxq -- '--server-settings' "$capture_argv"
}

prepare_factorio "${TEST_ROOT}/factorio-valid"
expect_success factorio-valid run_factorio "${TEST_ROOT}/factorio-valid"
exercise_secret_matrix factorio-username prepare_factorio run_factorio FACTORIO_USERNAME
exercise_secret_matrix factorio-token prepare_factorio run_factorio FACTORIO_TOKEN
exercise_secret_matrix factorio-game-password prepare_factorio run_factorio FACTORIO_GAME_PASSWORD
exercise_secret_matrix factorio-rcon-password prepare_factorio run_factorio FACTORIO_RCON_PASSWORD
expect_failure factorio-rcon-oversized case_factorio_oversized_secret
expect_success factorio-final-process-drops-portal-credentials case_factorio_final_process_drops_portal_credentials

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ESPOCRM
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_espocrm() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'provider-client-id' >"${fixture}/secrets/ESPOCRM_OIDC_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/ESPOCRM_OIDC_CLIENT_SECRET"
  printf 'strong-admin-password' >"${fixture}/secrets/ESPOCRM_ADMIN_PASSWORD"
  printf 'strong-database-password' >"${fixture}/secrets/MARIADB_PASSWORD"
}

run_espocrm() {
  local fixture="$1"
  SECRET_DIR="${fixture}/secrets" \
    ESPOCRM_ADMIN_PASSWORD_FILE="${fixture}/secrets/ESPOCRM_ADMIN_PASSWORD" \
    ESPOCRM_DATABASE_PASSWORD_FILE="${fixture}/secrets/MARIADB_PASSWORD" \
    /bin/bash "$ESPOCRM_SCRIPT" --preflight-only
}

case_espocrm_malformed_secret() {
  local fixture="${TEST_ROOT}/espocrm-secret-malformed"
  prepare_espocrm "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/ESPOCRM_OIDC_CLIENT_SECRET"
  run_espocrm "$fixture"
}

case_espocrm_final_process_drops_setup_credentials() {
  local fixture="${TEST_ROOT}/espocrm-final-process"
  local current_owner
  prepare_espocrm "$fixture"
  mkdir -p -- "${fixture}/data"
  printf '%s\n' '<?php return [];' >"${fixture}/config-override-internal.php"

  cat >"${fixture}/vendor-entrypoint" <<'EOF'
#!/bin/sh
set -eu
test "$1" = apache2ctl
test "$2" = -t
test -r "$ESPOCRM_ADMIN_PASSWORD_FILE"
test -r "$ESPOCRM_DATABASE_PASSWORD_FILE"
test "$(cat "$ESPOCRM_ADMIN_PASSWORD_FILE")" = strong-admin-password
test "$(cat "$ESPOCRM_DATABASE_PASSWORD_FILE")" = strong-database-password
: >"$ESPOCRM_SETUP_MARKER"
EOF
  cat >"${fixture}/apache2-foreground" <<'EOF'
#!/bin/sh
set -eu
test -f "$ESPOCRM_SETUP_MARKER"
test -z "${ESPOCRM_ADMIN_PASSWORD+x}"
test -z "${ESPOCRM_ADMIN_PASSWORD_FILE+x}"
test -z "${ESPOCRM_DATABASE_PASSWORD+x}"
test -z "${ESPOCRM_DATABASE_PASSWORD_FILE+x}"
EOF
  chmod 0700 "${fixture}/vendor-entrypoint" "${fixture}/apache2-foreground"
  current_owner="$(id -u):$(id -g)"

  PATH="${fixture}:${PATH}" \
    SECRET_DIR="${fixture}/secrets" \
    ESPOCRM_ADMIN_PASSWORD_FILE="${fixture}/secrets/ESPOCRM_ADMIN_PASSWORD" \
    ESPOCRM_DATABASE_PASSWORD_FILE="${fixture}/secrets/MARIADB_PASSWORD" \
    ESPOCRM_OIDC_CONFIG_SOURCE="${fixture}/config-override-internal.php" \
    ESPOCRM_DATA_DIR="${fixture}/data" \
    ESPOCRM_CONFIG_OWNER="${current_owner}" \
    ESPOCRM_VENDOR_ENTRYPOINT_BIN="${fixture}/vendor-entrypoint" \
    ESPOCRM_SETUP_MARKER="${fixture}/setup-complete" \
    /bin/bash "$ESPOCRM_SCRIPT" apache2-foreground
}

prepare_espocrm "${TEST_ROOT}/espocrm-valid"
expect_success espocrm-valid run_espocrm "${TEST_ROOT}/espocrm-valid"
exercise_secret_matrix espocrm-oidc-id prepare_espocrm run_espocrm ESPOCRM_OIDC_CLIENT_ID
exercise_secret_matrix espocrm-oidc-secret prepare_espocrm run_espocrm ESPOCRM_OIDC_CLIENT_SECRET
exercise_secret_matrix espocrm-admin-password prepare_espocrm run_espocrm ESPOCRM_ADMIN_PASSWORD
exercise_secret_matrix espocrm-database-password prepare_espocrm run_espocrm MARIADB_PASSWORD
expect_failure espocrm-oidc-secret-malformed case_espocrm_malformed_secret
expect_success espocrm-final-process-drops-setup-credentials case_espocrm_final_process_drops_setup_credentials

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- VÆULTWÆRDEN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_vaultwarden
#   Creætes one complete Væultwærden secret fixture.
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
prepare_vaultwarden() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'postgres-password' >"${fixture}/secrets/POSTGRES_PASSWORD"
  printf '%s' '$argon2id$v=19$m=19456,t=2,p=1$7TOiOl0XgqiRZT2/MiQqPmZYpNdo+tNo57uGqpSrlyg$VmnhwdS8VfgNVGt0O0jqiePV1tXHqKb6Bp/o8/g+v7s' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  printf 'smtp-password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD"
  printf 'provider-client-id' >"${fixture}/secrets/VAULTWARDEN_SSO_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/VAULTWARDEN_SSO_CLIENT_SECRET"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_vaultwarden_with_trusted_proxies
#   Sources the hook with one proxy-trust vælue ænd cleæns its runtime file.
#   Ærguments:
#     $1 - fixture root
#     $2 - trusted-proxy CIDR list
#ææææææææææææææææææææææææææææææææææ
run_vaultwarden_with_trusted_proxies() {
  local fixture="$1"
  local trusted_proxies="$2"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    IP_HEADER_TRUSTED_PROXIES="$trusted_proxies" \
    /bin/sh -c '. "$1"; test -f "$DATABASE_URL_FILE"; rm -f -- "$DATABASE_URL_FILE"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_vaultwarden
#   Sources the Væultwærden hook with one exæct LXC proxy peer.
#   Ærguments:
#     $1 - fixture root
#ææææææææææææææææææææææææææææææææææ
run_vaultwarden() {
  local fixture="$1"
  run_vaultwarden_with_trusted_proxies "$fixture" 192.0.2.10/32
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_malformed_admin
#   Rejects æn ædmin token thæt is not æn Ærgon2id PHC hæsh.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_malformed_admin() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-malformed"
  prepare_vaultwarden "$fixture"
  printf 'not-an-argon2id-phc-hash' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_parse_invalid_admin
#   Rejects æ PHC-shæped token whose sælt/output fields ære vendor-invælid.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_parse_invalid_admin() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-parse-invalid"
  prepare_vaultwarden "$fixture"
  printf '%s' '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$ZGlnZXN0' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_weak_admin
#   Rejects structurælly vælid Ærgon2id pæræmeters below the OWÆSP preset.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_weak_admin() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-weak"
  prepare_vaultwarden "$fixture"
  printf '%s' '$argon2id$v=19$m=4096,t=1,p=1$7TOiOl0XgqiRZT2/MiQqPmZYpNdo+tNo57uGqpSrlyg$VmnhwdS8VfgNVGt0O0jqiePV1tXHqKb6Bp/o8/g+v7s' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_noncanonical_admin_cost
#   Rejects leæding-zero Ærgon2id cost pæræmeters before numeric evæluætion.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_noncanonical_admin_cost() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-noncanonical-cost"
  prepare_vaultwarden "$fixture"
  printf '%s' '$argon2id$v=19$m=019456,t=2,p=1$7TOiOl0XgqiRZT2/MiQqPmZYpNdo+tNo57uGqpSrlyg$VmnhwdS8VfgNVGt0O0jqiePV1tXHqKb6Bp/o8/g+v7s' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_oversized_admin_cost
#   Rejects overlong integers without relying on shell ærithmetic overflow.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_oversized_admin_cost() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-oversized-cost"
  prepare_vaultwarden "$fixture"
  printf '%s' '$argon2id$v=19$m=999999999999999999999999,t=2,p=1$7TOiOl0XgqiRZT2/MiQqPmZYpNdo+tNo57uGqpSrlyg$VmnhwdS8VfgNVGt0O0jqiePV1tXHqKb6Bp/o8/g+v7s' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_excessive_admin_cost
#   Rejects structurælly vælid but resource-exhæusting Ærgon2id costs.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_excessive_admin_cost() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-excessive-cost"
  prepare_vaultwarden "$fixture"
  printf '%s' '$argon2id$v=19$m=131073,t=11,p=5$7TOiOl0XgqiRZT2/MiQqPmZYpNdo+tNo57uGqpSrlyg$VmnhwdS8VfgNVGt0O0jqiePV1tXHqKb6Bp/o8/g+v7s' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_vaultwarden_proxy_fixture
#   Prepæres æ fixture ænd runs one explicit proxy-trust cæse.
#   Ærguments:
#     $1 - fixture root
#     $2 - trusted-proxy CIDR list
#ææææææææææææææææææææææææææææææææææ
run_vaultwarden_proxy_fixture() {
  local fixture="$1"
  local trusted_proxies="$2"
  prepare_vaultwarden "$fixture"
  run_vaultwarden_with_trusted_proxies "$fixture" "$trusted_proxies"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_missing_trusted_proxies
#   Rejects missing proxy trust before creæting æ DATABASE_URL file.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_missing_trusted_proxies() {
  local fixture="${TEST_ROOT}/vaultwarden-trusted-proxies-missing"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    /bin/sh -c 'unset IP_HEADER_TRUSTED_PROXIES; . "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_postgres_secret_type
#   Replæces the PostgreSQL secret with one unsæfe filesystem type.
#   Ærguments:
#     $1 - fixture root
#     $2 - symlink, fifo, or socket
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_postgres_secret_type() {
  local fixture="$1"
  local secret_type="$2"
  local secret_path="${fixture}/secrets/POSTGRES_PASSWORD"
  prepare_vaultwarden "$fixture"
  case "$secret_type" in
    symlink)
      mv -- "$secret_path" "${secret_path}.target"
      ln -s -- POSTGRES_PASSWORD.target "$secret_path"
      ;;
    fifo)
      rm -f -- "$secret_path"
      mkfifo -- "$secret_path"
      ;;
    socket)
      rm -f -- "$secret_path"
      python3 - "$secret_path" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(sys.argv[1])
sock.close()
PY
      ;;
    *) return 1 ;;
  esac
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_postgres_secret_device
#   Rejects æ direct chæræcter-device secret pæth.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_postgres_secret_device() {
  local fixture="${TEST_ROOT}/vaultwarden-postgres-secret-device"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    POSTGRES_PASSWORD_FILE=/dev/null \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 \
    /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_postgres_secret_oversized
#   Rejects æ secret beyond the bounded 4096-byte contræct.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_postgres_secret_oversized() {
  local fixture="${TEST_ROOT}/vaultwarden-postgres-secret-oversized"
  prepare_vaultwarden "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/POSTGRES_PASSWORD"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_database_url_file_contract
#   Proves byte-exæct URL encoding, mode 0600, ænd no dæemon-environment leæk.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_database_url_file_contract() {
  local fixture="${TEST_ROOT}/vaultwarden-database-url-file-contract"
  prepare_vaultwarden "$fixture"
  mkdir -p -- "${fixture}/untrusted-tmp"
  printf '%s' 'p@ss:/?#[]% !+$&*' >"${fixture}/secrets/POSTGRES_PASSWORD"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    IP_HEADER_TRUSTED_PROXIES='172.18.0.0/16,192.0.2.10/32' \
    TMPDIR="${fixture}/untrusted-tmp" \
    VAULTWARDEN_ASSERTION_DIR="$fixture" VAULTWARDEN_HOOK="$VAULTWARDEN_SCRIPT" \
    /bin/sh <<'SH'
set -eu
database_url_path=''
cleanup_database_url() {
  [ -z "$database_url_path" ] || rm -f -- "$database_url_path"
}
trap cleanup_database_url EXIT HUP INT TERM
. "$VAULTWARDEN_HOOK"
database_url_path="$DATABASE_URL_FILE"
case "$database_url_path" in
  /tmp/vaultwarden-database-url.*) ;;
  *) exit 1 ;;
esac
[ -f "$database_url_path" ]
[ ! -L "$database_url_path" ]
[ "$(stat -c '%a' "$database_url_path")" = 600 ]
expected_url='postgresql://vaultwarden:p%40ss%3A%2F%3F%23%5B%5D%25%20%21%2B%24%26%2A@vaultwarden-postgresql:5432/vaultwarden'
printf '%s' "$expected_url" >"${VAULTWARDEN_ASSERTION_DIR}/expected-database-url"
cmp -s -- "${VAULTWARDEN_ASSERTION_DIR}/expected-database-url" "$database_url_path"
env >"${VAULTWARDEN_ASSERTION_DIR}/final-environment"
grep -Fqx -- "DATABASE_URL_FILE=${database_url_path}" "${VAULTWARDEN_ASSERTION_DIR}/final-environment"
grep -Fqx -- "CONFIG_FILE=/etc/vaultwarden.d/config.json" "${VAULTWARDEN_ASSERTION_DIR}/final-environment"
! grep -q '^DATABASE_URL=' "${VAULTWARDEN_ASSERTION_DIR}/final-environment"
! grep -Fq -- 'p@ss:/?#[]% !+$&*' "${VAULTWARDEN_ASSERTION_DIR}/final-environment"
! grep -Fq -- 'p%40ss%3A%2F%3F%23%5B%5D%25%20%21%2B%24%26%2A' "${VAULTWARDEN_ASSERTION_DIR}/final-environment"
SH
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_inline_secret_environment
#   Rejects æ direct PostgreSQL secret environment vælue.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_inline_secret_environment() {
  local fixture="${TEST_ROOT}/vaultwarden-inline-secret-environment"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 POSTGRES_PASSWORD=inline-secret \
    /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_preconfigured_database_url
#   Rejects æ preconfigured cleærtext DATABASE_URL.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_preconfigured_database_url() {
  local fixture="${TEST_ROOT}/vaultwarden-preconfigured-database-url"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 DATABASE_URL=postgresql://must-not-survive \
    /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_sso_verification_value
#   Runs one SSO emæil-verificætion trust cæse.
#   Ærguments:
#     $1 - fixture root
#     $2 - SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION vælue
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_sso_verification_value() {
  local fixture="$1"
  local verification_value="$2"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION="$verification_value" \
    IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 \
    /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_sso_verification_missing
#   Rejects missing explicit emæil-verificætion trust hærdening.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_sso_verification_missing() {
  local fixture="${TEST_ROOT}/vaultwarden-sso-verification-missing"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED=true IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 \
    /bin/sh -c 'unset SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION; . "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_sso_enabled_value
#   Rejects æny SSO enæblement vælue other thæn exæct lowercæse true.
#   Ærguments:
#     $1 - fixture root
#     $2 - SSO_ENABLED vælue
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_sso_enabled_value() {
  local fixture="$1"
  local enabled_value="$2"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ENABLED="$enabled_value" SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false \
    IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 \
    /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_sso_enabled_missing
#   Rejects missing SSO enæblement for this Æuthentik-nætive stæck.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_sso_enabled_missing() {
  local fixture="${TEST_ROOT}/vaultwarden-sso-enabled-missing"
  prepare_vaultwarden "$fixture"
  SECRET_DIR="${fixture}/secrets" CONFIG_FILE="$VAULTWARDEN_IMMUTABLE_CONFIG_FILE" \
    APP_NAME=vaultwarden SMTP_HOST=mail.example.test \
    SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false IP_HEADER_TRUSTED_PROXIES=192.0.2.10/32 \
    /bin/sh -c 'unset SSO_ENABLED; . "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_config_file_value
#   Runs one explicit CONFIG_FILE vælue; only the locked pæth is permitted.
#   Ærguments:
#     $1 - CONFIG_FILE vælue
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_config_file_value() {
  local config_file="$1"
  CONFIG_FILE="$config_file" /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_missing_config_file
#   Rejects æ missing CONFIG_FILE before æny secret is reæd.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_missing_config_file() {
  env -u CONFIG_FILE /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_legacy_data_config_ignored
#   Proves æn unsæfe legacy /data config does not chænge the locked hook pæth.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_legacy_data_config_ignored() {
  local fixture="${TEST_ROOT}/vaultwarden-legacy-data-config"
  prepare_vaultwarden "$fixture"
  mkdir -p -- "${fixture}/data"
  printf '%s' '{"sso_enabled":false,"ip_header_trusted_proxies":"all","admin_token":"stale-inline"}' \
    >"${fixture}/expected-config.json"
  cp -- "${fixture}/expected-config.json" "${fixture}/data/config.json"
  DATA_FOLDER="${fixture}/data" run_vaultwarden "$fixture"
  cmp -s -- "${fixture}/expected-config.json" "${fixture}/data/config.json"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_healthcheck_static_contract
#   Pins the direct loopbæck probe; the reæl-imæge æudit proves reused-dætæ behævior.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_healthcheck_static_contract() {
  python3 - "$VAULTWARDEN_COMPOSE" <<'PY'
from pathlib import Path
import sys
import yaml

compose_path = Path(sys.argv[1])
document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
healthcheck = document["services"]["app"].get("healthcheck") or {}
actual = healthcheck.get("test")
expected = [
    "CMD",
    "/usr/bin/curl",
    "--noproxy",
    "*",
    "--proto",
    "=http",
    "--fail",
    "--silent",
    "--show-error",
    "--connect-timeout",
    "2",
    "--max-time",
    "4",
    "--output",
    "/dev/null",
    "http://127.0.0.1:${TRAEFIK_PORT:?Port required}/alive",
]
if actual != expected:
    raise SystemExit(
        f"{compose_path}: Vaultwarden healthcheck must remain the exact direct exec-form /alive probe"
    )
probe_text = " ".join(str(part) for part in actual)
for forbidden in (
    "/healthcheck.sh",
    "CONFIG_FILE",
    "DATA_FOLDER",
    "DOMAIN",
    "/data/config.json",
):
    if forbidden in probe_text:
        raise SystemExit(
            f"{compose_path}: Vaultwarden healthcheck must not consume legacy config input {forbidden}"
        )
PY
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_locked_config_object
#   Rejects one filesystem object æt the exæct locked config pæth.
#   Ærguments:
#     $1 - fixture root
#     $2 - file, directory, symlink, or fifo
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_locked_config_object() {
  local fixture="$1"
  local object_type="$2"
  local locked_path="${fixture}/locked/config.json"
  local hook_path="${fixture}/10-database-url.sh"
  mkdir -p -- "${fixture}/locked"
  sed "s|^readonly VAULTWARDEN_IMMUTABLE_CONFIG_FILE='/etc/vaultwarden.d/config.json'$|readonly VAULTWARDEN_IMMUTABLE_CONFIG_FILE='${locked_path}'|" \
    "$VAULTWARDEN_SCRIPT" >"$hook_path"
  grep -Fqx -- "readonly VAULTWARDEN_IMMUTABLE_CONFIG_FILE='${locked_path}'" "$hook_path"
  case "$object_type" in
    file) : >"$locked_path" ;;
    directory) mkdir -- "$locked_path" ;;
    symlink) ln -s -- missing-target "$locked_path" ;;
    fifo) mkfifo -- "$locked_path" ;;
    *) return 1 ;;
  esac
  CONFIG_FILE="$locked_path" /bin/sh -c '. "$1"' _ "$hook_path"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_invalid_utf8_secret_rejected
#   Requires the dedicæted UTF-8 rejection for one secret.
#   Ærguments:
#     $1 - fixture root
#     $2 - secret filenæme
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_invalid_utf8_secret_rejected() {
  local fixture="$1"
  local secret_name="$2"
  local output="${fixture}.out"
  prepare_vaultwarden "$fixture"
  printf '\377' >"${fixture}/secrets/${secret_name}"
  if run_vaultwarden "$fixture" >"$output" 2>&1; then
    return 1
  fi
  grep -Fq -- "Required secret ${secret_name} is not vælid UTF-8." "$output"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_valid_unicode_secret
#   Proves æ vælid multi-byte UTF-8 secret remæins æccepted.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_valid_unicode_secret() {
  local fixture="${TEST_ROOT}/vaultwarden-valid-unicode-secret"
  prepare_vaultwarden "$fixture"
  printf '%s' 'gültiges-pæsswort' >"${fixture}/secrets/MAILER_SMTP_PASSWORD"
  run_vaultwarden "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_unicode_control_secret_rejected
#   Rejects one vælid UTF-8 control or Unicode line-sepærætor fixture.
#   Ærguments:
#     $1 - fixture root
#     $2 - U+0080, U+0085, U+009F, U+2028, or U+2029 fixture selector
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_unicode_control_secret_rejected() {
  local fixture="$1"
  local unicode_fixture="$2"
  local output="${fixture}.out"
  prepare_vaultwarden "$fixture"
  case "$unicode_fixture" in
    u0080) printf 'smtp\302\200password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD" ;;
    u0085) printf 'smtp\302\205password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD" ;;
    u009f) printf 'smtp\302\237password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD" ;;
    u2028) printf 'smtp\342\200\250password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD" ;;
    u2029) printf 'smtp\342\200\251password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD" ;;
    *) return 1 ;;
  esac
  if run_vaultwarden "$fixture" >"$output" 2>&1; then
    return 1
  fi
  grep -Fq -- 'Required secret MAILER_SMTP_PASSWORD contains control chæræcters.' "$output"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_vaultwarden_control_scanner_failure
#   Requires æn injected octet-scænner fæilure to stop stærtup.
#ææææææææææææææææææææææææææææææææææ
case_vaultwarden_control_scanner_failure() {
  local fixture="${TEST_ROOT}/vaultwarden-control-scanner-failure"
  local output="${fixture}.out"
  prepare_vaultwarden "$fixture"
  mkdir -p -- "${fixture}/bin"
  printf '#!/bin/sh\nexit 1\n' >"${fixture}/bin/od"
  chmod 0755 "${fixture}/bin/od"
  if PATH="${fixture}/bin:${PATH}" run_vaultwarden "$fixture" >"$output" 2>&1; then
    return 1
  fi
  grep -Fq -- 'Required secret POSTGRES_PASSWORD could not be inspected for control chæræcters.' "$output"
}

expect_success vaultwarden-valid prepare_vaultwarden "${TEST_ROOT}/vaultwarden-valid-fixture"
expect_success vaultwarden-valid-run run_vaultwarden "${TEST_ROOT}/vaultwarden-valid-fixture"
exercise_secret_matrix vaultwarden-admin prepare_vaultwarden run_vaultwarden VAULTWARDEN_ADMIN_TOKEN
exercise_secret_matrix vaultwarden-smtp prepare_vaultwarden run_vaultwarden MAILER_SMTP_PASSWORD
exercise_secret_matrix vaultwarden-sso-id prepare_vaultwarden run_vaultwarden VAULTWARDEN_SSO_CLIENT_ID
exercise_secret_matrix vaultwarden-sso-secret prepare_vaultwarden run_vaultwarden VAULTWARDEN_SSO_CLIENT_SECRET
expect_failure vaultwarden-admin-malformed case_vaultwarden_malformed_admin
expect_failure vaultwarden-admin-parse-invalid case_vaultwarden_parse_invalid_admin
expect_failure vaultwarden-admin-weak case_vaultwarden_weak_admin
expect_failure vaultwarden-admin-noncanonical-cost case_vaultwarden_noncanonical_admin_cost
expect_failure vaultwarden-admin-oversized-cost case_vaultwarden_oversized_admin_cost
expect_failure vaultwarden-admin-excessive-cost case_vaultwarden_excessive_admin_cost
expect_failure vaultwarden-postgres-secret-symlink case_vaultwarden_postgres_secret_type "${TEST_ROOT}/vaultwarden-postgres-secret-symlink" symlink
expect_failure vaultwarden-postgres-secret-fifo case_vaultwarden_postgres_secret_type "${TEST_ROOT}/vaultwarden-postgres-secret-fifo" fifo
expect_failure vaultwarden-postgres-secret-socket case_vaultwarden_postgres_secret_type "${TEST_ROOT}/vaultwarden-postgres-secret-socket" socket
expect_failure vaultwarden-postgres-secret-device case_vaultwarden_postgres_secret_device
expect_failure vaultwarden-postgres-secret-oversized case_vaultwarden_postgres_secret_oversized
expect_success vaultwarden-database-url-file-contract case_vaultwarden_database_url_file_contract
expect_success vaultwarden-trusted-proxies-list run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-list" '172.18.0.0/16,192.0.2.10/32'
expect_failure vaultwarden-trusted-proxies-missing case_vaultwarden_missing_trusted_proxies
expect_failure vaultwarden-trusted-proxies-placeholder run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-placeholder" CHANGE_ME
expect_failure vaultwarden-trusted-proxies-local run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-local" local
expect_failure vaultwarden-trusted-proxies-all run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-all" all
expect_failure vaultwarden-trusted-proxies-whitespace run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-whitespace" '192.0.2.10/32, 192.0.2.11/32'
expect_failure vaultwarden-trusted-proxies-malformed run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-malformed" 999.0.2.10/32
expect_failure vaultwarden-trusted-proxies-leading-zero run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-leading-zero" 192.000.2.10/32
expect_failure vaultwarden-trusted-proxies-noncanonical run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-noncanonical" 172.18.1.1/16
expect_failure vaultwarden-trusted-proxies-broad run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-broad" 10.0.0.0/8
expect_failure vaultwarden-trusted-proxies-duplicate run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-duplicate" '192.0.2.10/32,192.0.2.10/32'
expect_failure vaultwarden-trusted-proxies-overlap run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-overlap" '172.18.0.0/16,172.18.1.0/24'
expect_failure vaultwarden-trusted-proxies-multicast run_vaultwarden_proxy_fixture "${TEST_ROOT}/vaultwarden-trusted-proxies-multicast" 224.0.0.1/32
expect_failure vaultwarden-inline-secret-environment case_vaultwarden_inline_secret_environment
expect_failure vaultwarden-preconfigured-database-url case_vaultwarden_preconfigured_database_url
expect_failure vaultwarden-sso-enabled-missing case_vaultwarden_sso_enabled_missing
expect_failure vaultwarden-sso-enabled-false case_vaultwarden_sso_enabled_value "${TEST_ROOT}/vaultwarden-sso-enabled-false" false
expect_failure vaultwarden-sso-enabled-malformed case_vaultwarden_sso_enabled_value "${TEST_ROOT}/vaultwarden-sso-enabled-malformed" TRUE
expect_failure vaultwarden-sso-verification-missing case_vaultwarden_sso_verification_missing
expect_failure vaultwarden-sso-verification-true case_vaultwarden_sso_verification_value "${TEST_ROOT}/vaultwarden-sso-verification-true" true
expect_failure vaultwarden-sso-verification-malformed case_vaultwarden_sso_verification_value "${TEST_ROOT}/vaultwarden-sso-verification-malformed" FALSE
expect_failure vaultwarden-config-file-missing case_vaultwarden_missing_config_file
expect_failure vaultwarden-config-file-data-path case_vaultwarden_config_file_value /data/config.json
expect_success vaultwarden-legacy-data-config-ignored case_vaultwarden_legacy_data_config_ignored
expect_success vaultwarden-healthcheck-static-contract case_vaultwarden_healthcheck_static_contract
expect_failure vaultwarden-locked-config-file case_vaultwarden_locked_config_object "${TEST_ROOT}/vaultwarden-locked-config-file" file
expect_failure vaultwarden-locked-config-directory case_vaultwarden_locked_config_object "${TEST_ROOT}/vaultwarden-locked-config-directory" directory
expect_failure vaultwarden-locked-config-symlink case_vaultwarden_locked_config_object "${TEST_ROOT}/vaultwarden-locked-config-symlink" symlink
expect_failure vaultwarden-locked-config-fifo case_vaultwarden_locked_config_object "${TEST_ROOT}/vaultwarden-locked-config-fifo" fifo
expect_success vaultwarden-valid-unicode-secret case_vaultwarden_valid_unicode_secret
expect_success vaultwarden-smtp-u0080-control-rejected case_vaultwarden_unicode_control_secret_rejected "${TEST_ROOT}/vaultwarden-smtp-u0080-control" u0080
expect_success vaultwarden-smtp-u0085-control-rejected case_vaultwarden_unicode_control_secret_rejected "${TEST_ROOT}/vaultwarden-smtp-u0085-control" u0085
expect_success vaultwarden-smtp-u009f-control-rejected case_vaultwarden_unicode_control_secret_rejected "${TEST_ROOT}/vaultwarden-smtp-u009f-control" u009f
expect_success vaultwarden-smtp-u2028-separator-rejected case_vaultwarden_unicode_control_secret_rejected "${TEST_ROOT}/vaultwarden-smtp-u2028-separator" u2028
expect_success vaultwarden-smtp-u2029-separator-rejected case_vaultwarden_unicode_control_secret_rejected "${TEST_ROOT}/vaultwarden-smtp-u2029-separator" u2029
expect_success vaultwarden-control-scanner-failure case_vaultwarden_control_scanner_failure
expect_success vaultwarden-postgres-invalid-utf8-rejected case_vaultwarden_invalid_utf8_secret_rejected "${TEST_ROOT}/vaultwarden-postgres-invalid-utf8" POSTGRES_PASSWORD
expect_success vaultwarden-admin-invalid-utf8-rejected case_vaultwarden_invalid_utf8_secret_rejected "${TEST_ROOT}/vaultwarden-admin-invalid-utf8" VAULTWARDEN_ADMIN_TOKEN
expect_success vaultwarden-smtp-invalid-utf8-rejected case_vaultwarden_invalid_utf8_secret_rejected "${TEST_ROOT}/vaultwarden-smtp-invalid-utf8" MAILER_SMTP_PASSWORD
expect_success vaultwarden-sso-id-invalid-utf8-rejected case_vaultwarden_invalid_utf8_secret_rejected "${TEST_ROOT}/vaultwarden-sso-id-invalid-utf8" VAULTWARDEN_SSO_CLIENT_ID
expect_success vaultwarden-sso-secret-invalid-utf8-rejected case_vaultwarden_invalid_utf8_secret_rejected "${TEST_ROOT}/vaultwarden-sso-secret-invalid-utf8" VAULTWARDEN_SSO_CLIENT_SECRET

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- N8N
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_n8n() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'provider-client-id' >"${fixture}/secrets/N8N_OIDC_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/N8N_OIDC_CLIENT_SECRET"
  printf 'smtp-password' >"${fixture}/secrets/N8N_SMTP_PASS"
}

run_n8n() {
  local fixture="$1"
  PATH="${TEST_BIN}:${PATH}" SECRET_DIR="${fixture}/secrets" N8N_EMAIL_MODE=smtp \
    /bin/sh "$N8N_SCRIPT"
}

run_n8n_worker_without_main_secrets() {
  local fixture="${TEST_ROOT}/n8n-worker"
  mkdir -p -- "${fixture}/secrets"
  PATH="${TEST_BIN}:${PATH}" SECRET_DIR="${fixture}/secrets" N8N_EMAIL_MODE=smtp \
    /bin/sh "$N8N_SCRIPT" worker
}

prepare_n8n "${TEST_ROOT}/n8n-valid"
expect_success n8n-valid run_n8n "${TEST_ROOT}/n8n-valid"
expect_success n8n-worker-does-not-require-main-secrets run_n8n_worker_without_main_secrets
exercise_secret_matrix n8n-oidc-id prepare_n8n run_n8n N8N_OIDC_CLIENT_ID
exercise_secret_matrix n8n-oidc-secret prepare_n8n run_n8n N8N_OIDC_CLIENT_SECRET
exercise_secret_matrix n8n-smtp prepare_n8n run_n8n N8N_SMTP_PASS

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TRÆFIK ÆND CERTS-DUMPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_traefik() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets" "${fixture}/acme"
  printf 'cloudflare-token' >"${fixture}/secrets/CF_DNS_API_TOKEN"
  printf '{"store":"production"}' >"${fixture}/acme/cloudflare-acme.json"
  printf '{"store":"staging"}' >"${fixture}/acme/cloudflare-staging-acme.json"
  chmod 0660 "${fixture}/acme/cloudflare-acme.json" "${fixture}/acme/cloudflare-staging-acme.json"
}

invoke_traefik() {
  local fixture="$1"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

run_traefik() {
  local fixture="$1"
  invoke_traefik "$fixture"
  grep -qx -- '--version' "${fixture}/traefik-started"
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-acme.json")" == 600 ]]
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-staging-acme.json")" == 600 ]]
  grep -qx -- '{"store":"production"}' "${fixture}/acme/cloudflare-acme.json"
  grep -qx -- '{"store":"staging"}' "${fixture}/acme/cloudflare-staging-acme.json"
}

case_traefik_unsafe_resolver() {
  local fixture="${TEST_ROOT}/traefik-unsafe-resolver"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    CERTRESOLVER='../cloudflare' CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

case_traefik_acme_symlink() {
  local fixture="${TEST_ROOT}/traefik-acme-symlink"
  prepare_traefik "$fixture"
  mv -- "${fixture}/acme/cloudflare-acme.json" "${fixture}/outside-acme.json"
  ln -s -- "${fixture}/outside-acme.json" "${fixture}/acme/cloudflare-acme.json"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

case_traefik_missing_acme_stores() {
  local fixture="${TEST_ROOT}/traefik-missing-acme-stores"
  prepare_traefik "$fixture"
  rm -f -- "${fixture}/acme/cloudflare-acme.json" "${fixture}/acme/cloudflare-staging-acme.json"
  invoke_traefik "$fixture"
  [[ -f "${fixture}/acme/cloudflare-acme.json" ]]
  [[ -f "${fixture}/acme/cloudflare-staging-acme.json" ]]
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-acme.json")" == 600 ]]
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-staging-acme.json")" == 600 ]]
  [[ ! -s "${fixture}/acme/cloudflare-acme.json" ]]
  [[ ! -s "${fixture}/acme/cloudflare-staging-acme.json" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_traefik_forward_settings
#   Runs the Træefik wræpper with one explicit DEV-forwærd configurætion.
#   Ærguments:
#     $1 - Fixture root
#     $2 - Forwærd-enæbled booleæn
#     $3 - Bæse domæin
#     $4 - DEV Træefik tærget
#     $5 - Trusted PROXY-protocol IPv4 sources
#ææææææææææææææææææææææææææææææææææ
run_traefik_forward_settings() {
  local fixture="$1"
  local enabled="$2"
  local domain="$3"
  local target="$4"
  local trusted_ips="$5"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_DEV_FORWARD_ENABLED="$enabled" TRAEFIK_DOMAIN="$domain" \
    TRAEFIK_DEV_FORWARD_TARGET_ADDRESS="$target" \
    TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS="$trusted_ips" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_disabled
#   Proves the disæbled feæture tolerætes its visible tærget plæceholder.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_disabled() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-disabled"
  run_traefik_forward_settings "$fixture" false example.com CHANGE_ME:443 ''
  grep -qx -- '--version' "${fixture}/traefik-started"
  ! grep -q -- '--entrypoints.websecure.proxyprotocol' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_enabled
#   Proves æ vælid IPv4 DEV tærget does not enæble inbound PROXY trust.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_enabled() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-enabled"
  run_traefik_forward_settings "$fixture" true it.saervices.de 192.168.10.100:443 ''
  grep -qx -- '--version' "${fixture}/traefik-started"
  ! grep -q -- '--entrypoints.websecure.proxyprotocol' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_fqdn_enabled
#   Proves æ vælid fully quælified internæl DNS tærget is æccepted.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_fqdn_enabled() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-fqdn-enabled"
  run_traefik_forward_settings "$fixture" true it.saervices.de dev-traefik.internal:443 ''
  grep -qx -- '--version' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_proxy_protocol_trust
#   Proves exæct unique IPv4 /32 sources become one lowercæse CLI ærgument.
#ææææææææææææææææææææææææææææææææææ
case_traefik_proxy_protocol_trust() {
  local fixture="${TEST_ROOT}/traefik-proxy-protocol-trust"
  local expected='--entrypoints.websecure.proxyprotocol.trustedips=192.168.20.100/32,192.168.20.101/32'
  run_traefik_forward_settings "$fixture" false example.com CHANGE_ME:443 '192.168.20.100/32,192.168.20.101/32'
  [[ "$(grep -Fxc -- "$expected" "${fixture}/traefik-started")" == 1 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_rejects_before_mutation
#   Proves invælid forwærding stops before ÆCME file mode normælisætion.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_rejects_before_mutation() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-rejects-before-mutation"
  prepare_traefik "$fixture"
  if PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_DEV_FORWARD_ENABLED=true TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DEV_FORWARD_TARGET_ADDRESS=CHANGE_ME:443 \
    /bin/sh "$TRAEFIK_SCRIPT" --version; then
    return 1
  fi
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-acme.json")" == 660 ]]
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-staging-acme.json")" == 660 ]]
  [[ ! -e "${fixture}/traefik-started" ]]
}

prepare_certs_dumper() {
  local fixture="$1"
  mkdir -p -- "${fixture}/data"
  printf '{"cloudflare":{"Account":{},"Certificates":[{"domain":{"main":"example.test"}}]}}' >"${fixture}/data/acme.json"
}

run_certs_dumper() {
  local fixture="$1"
  local -a shell_runner=(/bin/sh)
  if [[ -x /usr/lib/initcpio/busybox ]]; then
    shell_runner=(/usr/lib/initcpio/busybox sh)
  elif command -v busybox >/dev/null 2>&1; then
    shell_runner=(busybox sh)
  fi
  PATH="${TEST_BIN}:${PATH}" \
    CERTS_DUMPER_MARKER="${fixture}/dumper-started" \
    ACME_DIR="${fixture}/data" ACME_FILENAME=acme.json \
    "${shell_runner[@]}" "$CERTS_DUMPER_SCRIPT"
}

run_certs_dumper_with_filename() {
  local fixture="$1"
  local filename="$2"
  local -a shell_runner=(/bin/sh)
  if [[ -x /usr/lib/initcpio/busybox ]]; then
    shell_runner=(/usr/lib/initcpio/busybox sh)
  elif command -v busybox >/dev/null 2>&1; then
    shell_runner=(busybox sh)
  fi
  PATH="${TEST_BIN}:${PATH}" ACME_DIR="${fixture}/data" ACME_FILENAME="$filename" \
    "${shell_runner[@]}" "$CERTS_DUMPER_SCRIPT"
}

case_certs_dumper_waits_for_valid_store() {
  local fixture="${TEST_ROOT}/certs-dumper-readiness"
  local pid
  prepare_certs_dumper "$fixture"
  rm -f -- "${fixture}/data/acme.json" "${fixture}/dumper-started"

  run_certs_dumper "$fixture" &
  pid=$!
  sleep 1.1
  kill -0 "$pid"
  [[ ! -e "${fixture}/dumper-started" ]]

  printf '{invalid' >"${fixture}/data/acme.json"
  sleep 1.1
  kill -0 "$pid"
  [[ ! -e "${fixture}/dumper-started" ]]

  : >"${fixture}/data/acme.json"
  sleep 1.1
  kill -0 "$pid"
  [[ ! -e "${fixture}/dumper-started" ]]

  printf '{"cloudflare":{"Account":{},"Certificates":[]}}' >"${fixture}/data/acme.json"
  sleep 1.1
  kill -0 "$pid"
  [[ ! -e "${fixture}/dumper-started" ]]

  printf '{"cloudflare":{"Account":{},"Certificates":[{"domain":{"main":"example.test"}}]}}' >"${fixture}/data/acme.json"
  chmod 000 "${fixture}/data/acme.json"
  sleep 1.1
  kill -0 "$pid"
  [[ ! -e "${fixture}/dumper-started" ]]

  chmod 600 "${fixture}/data/acme.json"
  wait "$pid"
  [[ -f "${fixture}/dumper-started" ]]
}

prepare_traefik "${TEST_ROOT}/traefik-valid"
expect_success traefik-valid run_traefik "${TEST_ROOT}/traefik-valid"
exercise_secret_matrix traefik-token prepare_traefik run_traefik CF_DNS_API_TOKEN
expect_failure traefik-unsafe-resolver case_traefik_unsafe_resolver
expect_failure traefik-acme-symlink case_traefik_acme_symlink
expect_success traefik-missing-acme-stores case_traefik_missing_acme_stores
expect_success traefik-dev-forward-disabled case_traefik_dev_forward_disabled
expect_success traefik-dev-forward-enabled case_traefik_dev_forward_enabled
expect_success traefik-dev-forward-fqdn-enabled case_traefik_dev_forward_fqdn_enabled
expect_success traefik-proxy-protocol-trust case_traefik_proxy_protocol_trust
expect_success traefik-dev-forward-rejects-before-mutation case_traefik_dev_forward_rejects_before_mutation
expect_failure traefik-dev-forward-invalid-boolean run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-invalid-boolean" TRUE it.saervices.de 192.168.10.100:443 ''
expect_failure traefik-dev-forward-empty-target run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-empty-target" true it.saervices.de '' ''
expect_failure traefik-dev-forward-placeholder-target run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-placeholder-target" true it.saervices.de CHANGE_ME:443 ''
expect_failure traefik-dev-forward-placeholder-domain run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-placeholder-domain" true example.com 192.168.10.100:443 ''
expect_failure traefik-dev-forward-invalid-host run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-invalid-host" true it.saervices.de 'https://192.168.10.100:443' ''
expect_failure traefik-dev-forward-malformed-ipv4 run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-malformed-ipv4" true it.saervices.de 999.999.999.999:443 ''
expect_failure traefik-dev-forward-single-label-host run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-single-label-host" true it.saervices.de localhost:443 ''
expect_failure traefik-dev-forward-missing-port run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-missing-port" true it.saervices.de 192.168.10.100 ''
expect_failure traefik-dev-forward-nonnumeric-port run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-nonnumeric-port" true it.saervices.de 192.168.10.100:https ''
expect_failure traefik-dev-forward-port-zero run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-port-zero" true it.saervices.de 192.168.10.100:0 ''
expect_failure traefik-dev-forward-leading-zero-port run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-leading-zero-port" true it.saervices.de 192.168.10.100:0443 ''
expect_failure traefik-dev-forward-port-overflow run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-port-overflow" true it.saervices.de 192.168.10.100:65536 ''
expect_failure traefik-proxy-protocol-missing-mask run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-missing-mask" false example.com CHANGE_ME:443 192.168.20.100
expect_failure traefik-proxy-protocol-broad-mask run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-broad-mask" false example.com CHANGE_ME:443 192.168.20.0/24
expect_failure traefik-proxy-protocol-unspecified run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-unspecified" false example.com CHANGE_ME:443 0.0.0.0/32
expect_failure traefik-proxy-protocol-whitespace run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-whitespace" false example.com CHANGE_ME:443 '192.168.20.100/32, 192.168.20.101/32'
expect_failure traefik-proxy-protocol-malformed-ipv4 run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-malformed-ipv4" false example.com CHANGE_ME:443 999.999.999.999/32
expect_failure traefik-proxy-protocol-duplicate run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-duplicate" false example.com CHANGE_ME:443 '192.168.20.100/32,192.168.20.100/32'
prepare_certs_dumper "${TEST_ROOT}/certs-dumper-valid"
expect_success certs-dumper-valid run_certs_dumper "${TEST_ROOT}/certs-dumper-valid"
expect_success certs-dumper-waits-for-valid-store case_certs_dumper_waits_for_valid_store
expect_failure certs-dumper-filename-empty run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" ''
expect_failure certs-dumper-filename-dot run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" '.'
expect_failure certs-dumper-filename-dotdot run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" '..'
expect_failure certs-dumper-filename-parent run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" '../acme.json'
expect_failure certs-dumper-filename-subdir run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" 'subdir/acme.json'
expect_failure certs-dumper-filename-backslash run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" 'subdir\acme.json'
expect_failure certs-dumper-filename-whitespace run_certs_dumper_with_filename "${TEST_ROOT}/certs-dumper-valid" 'acme store.json'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- VIKUNJÆ
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_vikunja() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf '0123456789abcdef0123456789abcdef' >"${fixture}/secrets/VIKUNJA_APP_SECRET"
  printf 'smtp-password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD"
  printf 'provider-client-id' >"${fixture}/secrets/VIKUNJA_OIDC_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/VIKUNJA_OIDC_CLIENT_SECRET"
}

run_vikunja() {
  local fixture="$1"
  VIKUNJA_BUSYBOX='' VIKUNJA_MAILER_ENABLED=true VIKUNJA_AUTH_OPENID_ENABLED=true \
    VIKUNJA_SERVICE_SECRET_FILE="${fixture}/secrets/VIKUNJA_APP_SECRET" \
    VIKUNJA_MAILER_PASSWORD_FILE="${fixture}/secrets/MAILER_SMTP_PASSWORD" \
    VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTID_FILE="${fixture}/secrets/VIKUNJA_OIDC_CLIENT_ID" \
    VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTSECRET_FILE="${fixture}/secrets/VIKUNJA_OIDC_CLIENT_SECRET" \
    /bin/sh "$VIKUNJA_SCRIPT" /bin/true
}

run_vikunja_without_smtp_secret() {
  local fixture="${TEST_ROOT}/vikunja-no-smtp"
  prepare_vikunja "$fixture"
  rm -f -- "${fixture}/secrets/MAILER_SMTP_PASSWORD"
  VIKUNJA_BUSYBOX='' VIKUNJA_MAILER_ENABLED=false VIKUNJA_AUTH_OPENID_ENABLED=true \
    VIKUNJA_SERVICE_SECRET_FILE="${fixture}/secrets/VIKUNJA_APP_SECRET" \
    VIKUNJA_MAILER_PASSWORD_FILE="${fixture}/secrets/MAILER_SMTP_PASSWORD" \
    VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTID_FILE="${fixture}/secrets/VIKUNJA_OIDC_CLIENT_ID" \
    VIKUNJA_AUTH_OPENID_PROVIDERS_AUTHENTIK_CLIENTSECRET_FILE="${fixture}/secrets/VIKUNJA_OIDC_CLIENT_SECRET" \
    /bin/sh "$VIKUNJA_SCRIPT" /bin/sh -c 'test -z "${VIKUNJA_MAILER_PASSWORD_FILE+x}"'
}

case_vikunja_short_app_secret() {
  local fixture="${TEST_ROOT}/vikunja-app-short"
  prepare_vikunja "$fixture"
  printf 'too-short' >"${fixture}/secrets/VIKUNJA_APP_SECRET"
  run_vikunja "$fixture"
}

case_vikunja_oversized_app_secret() {
  local fixture="${TEST_ROOT}/vikunja-app-oversized"
  prepare_vikunja "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/VIKUNJA_APP_SECRET"
  run_vikunja "$fixture"
}

prepare_vikunja "${TEST_ROOT}/vikunja-valid"
expect_success vikunja-valid run_vikunja "${TEST_ROOT}/vikunja-valid"
expect_success vikunja-disabled-smtp-does-not-require-secret run_vikunja_without_smtp_secret
exercise_secret_matrix vikunja-app-secret prepare_vikunja run_vikunja VIKUNJA_APP_SECRET
expect_failure vikunja-app-short case_vikunja_short_app_secret
expect_failure vikunja-app-oversized case_vikunja_oversized_app_secret
exercise_secret_matrix vikunja-smtp prepare_vikunja run_vikunja MAILER_SMTP_PASSWORD
exercise_secret_matrix vikunja-oidc-id prepare_vikunja run_vikunja VIKUNJA_OIDC_CLIENT_ID
exercise_secret_matrix vikunja-oidc-secret prepare_vikunja run_vikunja VIKUNJA_OIDC_CLIENT_SECRET

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- KIMÆI
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_kimai() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'strong-admin-password' >"${fixture}/secrets/KIMAI_ADMIN_PASSWORD"
  printf '0123456789abcdef0123456789abcdef' >"${fixture}/secrets/KIMAI_APP_SECRET"
  printf 'database:@/?#%%+ password' >"${fixture}/secrets/MARIADB_PASSWORD"
  cp -- "${TEST_CRYPTO}/idp.der.b64" "${fixture}/secrets/SAML_IDP_CERT"
  printf 'smtp:@/?#%%+ password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD"
}

run_kimai() {
  local fixture="$1"
  local encryption="${2-tls}"
  SECRET_DIR="${fixture}/secrets" APP_NAME=kimai-test \
    KIMAI_RUNTIME_SECRET_DIR="${fixture}/runtime-secrets" \
    KIMAI_RUNTIME_SECRET_UID="$(id -u)" KIMAI_RUNTIME_SECRET_GID="$(id -g)" \
    KIMAI_PHP_BIN="${TEST_BIN}/kimai-php" \
    KIMAI_SMTP_ENABLED=true MAILER_SMTP_HOST=mail.example.test \
    MAILER_SMTP_PORT=587 MAILER_SMTP_USER='mailer+test@example.test' \
    MAILER_SMTP_ENCRYPTION="${encryption}" \
    /bin/bash "$KIMAI_SCRIPT" --preflight-only
}

run_kimai_without_smtp_secret() {
  local fixture="${TEST_ROOT}/kimai-no-smtp"
  prepare_kimai "$fixture"
  rm -f -- "${fixture}/secrets/MAILER_SMTP_PASSWORD"
  SECRET_DIR="${fixture}/secrets" APP_NAME=kimai-test \
    KIMAI_RUNTIME_SECRET_DIR="${fixture}/runtime-secrets" \
    KIMAI_RUNTIME_SECRET_UID="$(id -u)" KIMAI_RUNTIME_SECRET_GID="$(id -g)" \
    KIMAI_PHP_BIN="${TEST_BIN}/kimai-php" \
    KIMAI_SMTP_ENABLED=false \
    /bin/bash "$KIMAI_SCRIPT" --preflight-only
}

case_kimai_runtime_app_secret_copy() {
  local fixture="${TEST_ROOT}/kimai-runtime-app-secret"
  prepare_kimai "$fixture"
  run_kimai "$fixture"
  cmp -- "${fixture}/secrets/KIMAI_APP_SECRET" \
    "${fixture}/runtime-secrets/KIMAI_APP_SECRET"
  [[ "$(stat -c '%a' "${fixture}/runtime-secrets/KIMAI_APP_SECRET")" == 440 ]]
  [[ "$(stat -c '%u:%g' "${fixture}/runtime-secrets/KIMAI_APP_SECRET")" == "$(id -u):$(id -g)" ]]
}

case_kimai_mailer_output_redaction() {
  local fixture="${TEST_ROOT}/kimai-mailer-redaction"
  local database_password output smtp_password
  prepare_kimai "$fixture"
  output="$(run_kimai "$fixture")"
  database_password="$(<"${fixture}/secrets/MARIADB_PASSWORD")"
  smtp_password="$(<"${fixture}/secrets/MAILER_SMTP_PASSWORD")"
  [[ "$output" == *'mailer%2Btest%40example.test:***@mail.example.test:587'* ]]
  [[ "$output" != *"$database_password"* ]]
  [[ "$output" != *"$smtp_password"* ]]
}

case_kimai_plain_relay_omits_encryption() {
  local fixture="${TEST_ROOT}/kimai-plain-relay"
  local output
  prepare_kimai "$fixture"
  output="$(run_kimai "$fixture" '')"
  [[ "$output" == *'mail.example.test:587?auth_mode=login'* ]]
  [[ "$output" != *'encryption='* ]]
}

case_kimai_invalid_mailer_encryption() {
  local fixture="${TEST_ROOT}/kimai-invalid-encryption"
  prepare_kimai "$fixture"
  run_kimai "$fixture" starttls
}

case_kimai_mailer_handoff_contract() {
  python3 - "$KIMAI_SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
assignment = text.find("MAILER_DSN=")
export = text.find("export MAILER_DSN")
preflight = text.find("if [[ \"${1:-}\" == '--preflight-only' ]]")
handoff = text.find('exec /bin/bash -- "${KIMAI_PATCHED_VENDOR_ENTRYPOINT}" "$@"')
console = text.find("if [[ \"${1:-}\" == '--console' ]]")
plugins = text.find("# PLUGIN INSTÆLÆTION")

if min(assignment, export, preflight, handoff, console, plugins) < 0:
    raise SystemExit("Kimai mæiler/runtime hændoff contræct is incomplete")
if not assignment < export < preflight < console < plugins < handoff:
    raise SystemExit("Kimai mæiler/runtime hændoff ordering is unsæfe")
if 'test -n "${MAILER_DSN:-}" && test -n "${DATABASE_URL:-}"' not in text:
    raise SystemExit("Kimai preflight does not prove child-process DSN inheritænce")
if "rawurlencode($argv[1])" in text:
    raise SystemExit("Kimai secret encoding must not use PHP argv")
if '$(cat "${SECRET_DIR}/MARIADB_PASSWORD")' in text:
    raise SystemExit("Kimai DÆTÆBÆSE_URL must percent-encode the pæssword")
if text.count("rawurlencode(stream_get_contents(STDIN))") < 2:
    raise SystemExit("Kimai SMTP ænd MæriæDB secrets must be encoded viæ stdin")
if "MAILER_SMTP_ENCRYPTION must be empty, tls, or ssl" not in text:
    raise SystemExit("Kimai SMTP encryption ællowlist is missing")
if "unset ADMINPASS APP_SECRET KIMAI_SECRET_VALUE _mailer_smtp_password" not in text:
    raise SystemExit("Kimai vendor hændoff does not scrub bootstræp secrets")
if "%%env(file:KIMAI_APP_SECRET_FILE)%%" not in text:
    raise SystemExit("Kimai runtime æpp secret does not use the mounted file processor")
if "chmod 0440" not in text or "/run/saervices-kimai" not in text:
    raise SystemExit("Kimai runtime æpp-secret copy is not leæst privilege")
late_app_secret = text.find('APP_SECRET="$(<"${KIMAI_APP_SECRET_FILE}")"')
if late_app_secret < 0 or not plugins < late_app_secret < handoff:
    raise SystemExit("Kimai ÆPP_SECRET is not exported only æt the vendor hændoff")
PY
}

case_kimai_malformed_certificate() {
  local fixture="${TEST_ROOT}/kimai-saml-malformed"
  prepare_kimai "$fixture"
  printf '%080d' 0 >"${fixture}/secrets/SAML_IDP_CERT"
  run_kimai "$fixture"
}

case_kimai_short_admin_password() {
  local fixture="${TEST_ROOT}/kimai-admin-short"
  prepare_kimai "$fixture"
  printf 'too-short' >"${fixture}/secrets/KIMAI_ADMIN_PASSWORD"
  run_kimai "$fixture"
}

case_kimai_short_app_secret() {
  local fixture="${TEST_ROOT}/kimai-app-short"
  prepare_kimai "$fixture"
  printf 'too-short' >"${fixture}/secrets/KIMAI_APP_SECRET"
  run_kimai "$fixture"
}

case_kimai_oversized_app_secret() {
  local fixture="${TEST_ROOT}/kimai-app-oversized"
  prepare_kimai "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/KIMAI_APP_SECRET"
  run_kimai "$fixture"
}

prepare_kimai "${TEST_ROOT}/kimai-valid"
expect_success kimai-valid run_kimai "${TEST_ROOT}/kimai-valid"
expect_success kimai-runtime-app-secret-copy case_kimai_runtime_app_secret_copy
expect_success kimai-disabled-smtp-does-not-require-secret run_kimai_without_smtp_secret
expect_success kimai-mailer-output-redaction case_kimai_mailer_output_redaction
expect_success kimai-plain-relay-omits-encryption case_kimai_plain_relay_omits_encryption
expect_failure kimai-invalid-mailer-encryption case_kimai_invalid_mailer_encryption
expect_success kimai-mailer-handoff-contract case_kimai_mailer_handoff_contract
exercise_secret_matrix kimai-admin prepare_kimai run_kimai KIMAI_ADMIN_PASSWORD
exercise_secret_matrix kimai-app-secret prepare_kimai run_kimai KIMAI_APP_SECRET
exercise_secret_matrix kimai-saml prepare_kimai run_kimai SAML_IDP_CERT
exercise_secret_matrix kimai-smtp prepare_kimai run_kimai MAILER_SMTP_PASSWORD
expect_failure kimai-saml-malformed case_kimai_malformed_certificate
expect_failure kimai-admin-short case_kimai_short_admin_password
expect_failure kimai-app-short case_kimai_short_app_secret
expect_failure kimai-app-oversized case_kimai_oversized_app_secret

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆFILE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_seafile() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'provider-client-id' >"${fixture}/secrets/OAUTH_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/OAUTH_CLIENT_SECRET"
  printf 'smtp-password' >"${fixture}/secrets/EMAIL_HOST_PASSWORD"
  printf 'strong-admin-password' >"${fixture}/secrets/INIT_SEAFILE_ADMIN_PASSWORD"
  printf '0123456789abcdef0123456789abcdef' >"${fixture}/secrets/JWT_PRIVATE_KEY"
}

run_seafile() {
  local fixture="$1"
  SECRET_DIR="${fixture}/secrets" ENABLE_EMAIL_NOTIFICATIONS=false \
    /bin/sh "$SEAFILE_SCRIPT" --preflight-only
}

run_seafile_smtp() {
  local fixture="$1"
  SECRET_DIR="${fixture}/secrets" ENABLE_EMAIL_NOTIFICATIONS=true \
    EMAIL_HOST=smtp.example.test \
    /bin/sh "$SEAFILE_SCRIPT" --preflight-only
}

run_seafile_without_smtp_secret() {
  local fixture="${TEST_ROOT}/seafile-no-smtp"
  prepare_seafile "$fixture"
  rm -f -- "${fixture}/secrets/EMAIL_HOST_PASSWORD"
  run_seafile "$fixture"
}

case_seafile_smtp_missing_host() {
  local fixture="${TEST_ROOT}/seafile-smtp-missing-host"
  prepare_seafile "$fixture"
  SECRET_DIR="${fixture}/secrets" ENABLE_EMAIL_NOTIFICATIONS=true \
    /bin/sh "$SEAFILE_SCRIPT" --preflight-only
}

case_seafile_short_admin_password() {
  local fixture="${TEST_ROOT}/seafile-admin-short"
  prepare_seafile "$fixture"
  printf 'too-short' >"${fixture}/secrets/INIT_SEAFILE_ADMIN_PASSWORD"
  run_seafile "$fixture"
}

case_seafile_short_jwt() {
  local fixture="${TEST_ROOT}/seafile-jwt-short"
  prepare_seafile "$fixture"
  printf 'too-short' >"${fixture}/secrets/JWT_PRIVATE_KEY"
  run_seafile "$fixture"
}

case_seafile_vendor_runtime_transform() {
  local fixture="${TEST_ROOT}/seafile-vendor-runtime"
  local output="${fixture}/output"
  mkdir -p -- "$fixture"
  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'topdir = dirname(installdir)' \
    '' \
    'def main():' \
    '    admin_pw = {' \
    "        'email': get_conf('INIT_SEAFILE_ADMIN_EMAIL', 'me@example.com')," \
    "        'password': get_conf('INIT_SEAFILE_ADMIN_PASSWORD', 'asecret')," \
    '    }' \
    "    password_file = join(topdir, 'conf', 'admin.txt')" \
    "    with open(password_file, 'w') as fp:" \
    '        json.dump(admin_pw, fp)' \
    '' \
    '' \
    '    try:' \
    '        pass' \
    >"${fixture}/start.py"
  printf '%s\n' \
    '#!/bin/bash' \
    'else' \
    '    /scripts/start.py &' \
    'fi' \
    >"${fixture}/enterpoint.sh"

  python3 "$SEAFILE_RUNTIME_PREPARER" \
    --start-source "${fixture}/start.py" \
    --entrypoint-source "${fixture}/enterpoint.sh" \
    --output-dir "$output"

  grep -Fq '_read_admin_password_file()' "${output}/start.py"
  grep -Fq 'admin_pw.clear()' "${output}/start.py"
  grep -Fq 'INIT_SEAFILE_ADMIN_PASSWORD_FILE' "${output}/start.py"
  ! grep -Fq "get_conf('INIT_SEAFILE_ADMIN_PASSWORD'" "${output}/start.py"
  grep -Fq 'PYTHONPATH="/scripts${PYTHONPATH:+:${PYTHONPATH}}" /usr/bin/python3' \
    "${output}/enterpoint.sh"
  [[ "$(stat -c '%a' "${output}/start.py")" == 400 ]]
  [[ "$(stat -c '%a' "${output}/enterpoint.sh")" == 500 ]]

  sed -i "s/get_conf('INIT_SEAFILE_ADMIN_PASSWORD', 'asecret')/get_conf('DRIFTED_ADMIN_PASSWORD', 'asecret')/" \
    "${fixture}/start.py"
  ! python3 "$SEAFILE_RUNTIME_PREPARER" \
    --start-source "${fixture}/start.py" \
    --entrypoint-source "${fixture}/enterpoint.sh" \
    --output-dir "${fixture}/drift-output"
}

prepare_seafile "${TEST_ROOT}/seafile-valid"
expect_success seafile-valid run_seafile "${TEST_ROOT}/seafile-valid"
expect_success seafile-smtp-valid run_seafile_smtp "${TEST_ROOT}/seafile-valid"
expect_success seafile-disabled-smtp-does-not-require-secret run_seafile_without_smtp_secret
exercise_secret_matrix seafile-oidc-id prepare_seafile run_seafile OAUTH_CLIENT_ID
exercise_secret_matrix seafile-oidc-secret prepare_seafile run_seafile OAUTH_CLIENT_SECRET
exercise_secret_matrix seafile-smtp prepare_seafile run_seafile_smtp EMAIL_HOST_PASSWORD
exercise_secret_matrix seafile-admin prepare_seafile run_seafile INIT_SEAFILE_ADMIN_PASSWORD
exercise_secret_matrix seafile-jwt prepare_seafile run_seafile JWT_PRIVATE_KEY
expect_failure seafile-smtp-missing-host case_seafile_smtp_missing_host
expect_failure seafile-admin-short case_seafile_short_admin_password
expect_failure seafile-jwt-short case_seafile_short_jwt
expect_success seafile-vendor-runtime-transform case_seafile_vendor_runtime_transform

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆSEÆRCH
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_seasearch() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'strong-seasearch-password' >"${fixture}/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
}

run_seasearch() {
  local fixture="$1"
  SEASEARCH_PASSWORD_FILE="${fixture}/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD" \
    /bin/bash "$SEASEARCH_SCRIPT" --preflight-only
}

case_seasearch_short_password() {
  local fixture="${TEST_ROOT}/seasearch-short"
  prepare_seasearch "$fixture"
  printf 'too-short' >"${fixture}/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
  run_seasearch "$fixture"
}

case_seasearch_oversized_password() {
  local fixture="${TEST_ROOT}/seasearch-oversized"
  prepare_seasearch "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
  run_seasearch "$fixture"
}

prepare_seasearch "${TEST_ROOT}/seasearch-valid"
expect_success seasearch-valid run_seasearch "${TEST_ROOT}/seasearch-valid"
exercise_secret_matrix seasearch-password prepare_seasearch run_seasearch SEAFILE_SEASEARCH_ADMIN_PASSWORD
expect_failure seasearch-password-short case_seasearch_short_password
expect_failure seasearch-password-oversized case_seasearch_oversized_password

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DISÆBLED-FEÆTURE COMPOSE POLICY
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
check_disabled_feature_mounts() {
  python3 - "$TEST_REPO_ROOT" <<'PY'
from pathlib import Path
import contextlib
import importlib.util
import io
import re
import sys
import yaml

root = Path(sys.argv[1])

checks = (
    (
        root / "Vikunja/docker-compose.app.yaml",
        "MAILER_SMTP_PASSWORD",
        "VIKUNJA_MAILER_ENABLED",
        "${VIKUNJA_EMAIL_ENABLED:-false}",
    ),
    (
        root / "Kimai/docker-compose.app.yaml",
        "MAILER_SMTP_PASSWORD",
        "KIMAI_SMTP_ENABLED",
        "${KIMAI_SMTP_ENABLED:-false}",
    ),
    (
        root / "Seafile/docker-compose.app.yaml",
        "EMAIL_HOST_PASSWORD",
        "ENABLE_EMAIL_NOTIFICATIONS",
        "${ENABLE_EMAIL_NOTIFICATIONS:-false}",
    ),
)

for path, secret_name, env_name, expected_default in checks:
    document = yaml.safe_load(path.read_text(encoding="utf-8"))
    if secret_name not in document.get("secrets", {}):
        raise SystemExit(f"{path}: top-level {secret_name} declaration is missing")
    mounted = document["services"]["app"].get("secrets", [])
    mounted_names = {
        item if isinstance(item, str) else item.get("source")
        for item in mounted
    }
    if secret_name in mounted_names:
        raise SystemExit(f"{path}: disabled {secret_name} is mounted into services.app")
    actual_default = document["services"]["app"]["environment"].get(env_name)
    if actual_default != expected_default:
        raise SystemExit(
            f"{path}: {env_name} must default to false, got {actual_default!r}"
        )

    if path.name == "docker-compose.app.yaml" and path.parent.name == "Vikunja":
        mailer_file = document["services"]["app"]["environment"].get(
            "VIKUNJA_MAILER_PASSWORD_FILE"
        )
        if mailer_file != "":
            raise SystemExit(
                f"{path}: disabled SMTP must expose an empty "
                f"VIKUNJA_MAILER_PASSWORD_FILE to direct health and CLI processes"
            )

authentik_path = root / "Authentik/docker-compose.app.yaml"
authentik_document = yaml.safe_load(authentik_path.read_text(encoding="utf-8"))
authentik_secret = "AUTHENTIK_EMAIL_PASSWORD"
if authentik_secret not in authentik_document.get("secrets", {}):
    raise SystemExit(f"{authentik_path}: top-level {authentik_secret} declaration is missing")
authentik_app = authentik_document["services"]["app"]
authentik_app_mounts = {
    item if isinstance(item, str) else item.get("source")
    for item in authentik_app.get("secrets", [])
}
if authentik_secret in authentik_app_mounts:
    raise SystemExit(f"{authentik_path}: disabled {authentik_secret} is mounted into services.app")
if any(str(key).startswith("AUTHENTIK_EMAIL__") for key in authentik_app.get("environment", {})):
    raise SystemExit(f"{authentik_path}: disabled Authentik SMTP environment is active")

worker_path = root / "templates/authentik-worker/docker-compose.authentik-worker.yaml"
worker_document = yaml.safe_load(worker_path.read_text(encoding="utf-8"))
worker_service = worker_document["services"]["authentik-worker"]
worker_raw_mounts = {
    item if isinstance(item, str) else item.get("source")
    for item in worker_service.get("secrets", [])
}
worker_mounts = (
    authentik_app_mounts if worker_raw_mounts == {"secrets"} else worker_raw_mounts
)
if authentik_secret in worker_mounts:
    raise SystemExit(f"{worker_path}: disabled {authentik_secret} is mounted into services.authentik-worker")
if any(str(key).startswith("AUTHENTIK_EMAIL__") for key in worker_service.get("environment", {})):
    raise SystemExit(f"{worker_path}: disabled Authentik SMTP environment is active")

bootstrap_path = root / "templates/authentik-bootstrap/docker-compose.authentik-bootstrap.yaml"
bootstrap_document = yaml.safe_load(bootstrap_path.read_text(encoding="utf-8"))
bootstrap_service = bootstrap_document["services"]["authentik-bootstrap"]
bootstrap_mounts = {
    item if isinstance(item, str) else item.get("source")
    for item in bootstrap_service.get("secrets", [])
}
if authentik_secret in bootstrap_mounts:
    raise SystemExit(f"{bootstrap_path}: disabled {authentik_secret} is mounted into bootstrap")
if any(str(key).startswith("AUTHENTIK_EMAIL__") for key in bootstrap_service.get("environment", {})):
    raise SystemExit(f"{bootstrap_path}: disabled Authentik SMTP environment is active")

for path, document, service in (
    (authentik_path, authentik_document, authentik_app),
    (worker_path, worker_document, worker_service),
    (bootstrap_path, bootstrap_document, bootstrap_service),
):
    required_services = set(document.get("x-required-services", []))
    service_secrets = {
        item if isinstance(item, str) else item.get("source")
        for item in service.get("secrets", [])
    }
    if path == worker_path and service_secrets == {"secrets"}:
        service_secrets = authentik_app_mounts
    top_level_secrets = set((document.get("secrets") or {}).keys())
    dependencies = set((service.get("depends_on") or {}).keys())
    environment_keys = {str(key) for key in service.get("environment", {})}
    if {"redis", "valkey"} & (required_services | dependencies):
        raise SystemExit(f"{path}: Authentik 2025.10+ must not depend on Redis or Valkey")
    if "REDIS_PASSWORD" in service_secrets | top_level_secrets:
        raise SystemExit(f"{path}: obsolete Authentik Redis secret remains active")
    if any(key.startswith("AUTHENTIK_REDIS__") for key in environment_keys):
        raise SystemExit(f"{path}: obsolete AUTHENTIK_REDIS__ environment remains active")
    if "POSTGRES_PASSWORD" not in service_secrets:
        raise SystemExit(f"{path}: Authentik service must mount POSTGRES_PASSWORD")
    if service.get("environment", {}).get("AUTHENTIK_POSTGRESQL__PASSWORD") != "file:///run/secrets/POSTGRES_PASSWORD":
        raise SystemExit(
            f"{path}: Authentik PostgreSQL password must use the Docker secret file"
        )

generation_lengths = authentik_document.get("x-secret-generation-lengths") or {}
if generation_lengths.get("POSTGRES_PASSWORD") != 64:
    raise SystemExit(
        f"{authentik_path}: POSTGRES_PASSWORD generation length must stay at tested value 64"
    )
required_authentik_services = {
    "postgresql",
    "postgresql_maintenance",
    "authentik-bootstrap",
    "authentik-worker",
}
if not required_authentik_services <= set(authentik_document.get("x-required-services", [])):
    raise SystemExit(f"{authentik_path}: required PostgreSQL and worker services are incomplete")
if "POSTGRES_PASSWORD" not in (authentik_document.get("secrets") or {}):
    raise SystemExit(f"{authentik_path}: POSTGRES_PASSWORD declaration is missing")
if "POSTGRES_PASSWORD" in set(authentik_document.get("x-secret-generation-exclusions", [])):
    raise SystemExit(f"{authentik_path}: POSTGRES_PASSWORD must remain locally generatable")
if "authentik-worker" in (authentik_app.get("depends_on") or {}):
    raise SystemExit(
        f"{authentik_path}: server availability must not depend on worker health"
    )
for path, service in (
    (authentik_path, authentik_app),
    (worker_path, worker_service),
):
    bootstrap_dependency = (service.get("depends_on") or {}).get("authentik-bootstrap")
    if not isinstance(bootstrap_dependency, dict) or bootstrap_dependency.get("condition") != "service_completed_successfully":
        raise SystemExit(
            f"{path}: final Authentik services must wait for successful one-shot bootstrap completion"
        )
if authentik_app.get("environment", {}).get("AUTHENTIK_ERROR_REPORTING__ENABLED") != "${AUTHENTIK_ERROR_REPORTING__ENABLED:-false}":
    raise SystemExit(f"{authentik_path}: error reporting must default to false")
expected_server_private_listeners = {
    "AUTHENTIK_LISTEN__METRICS": "127.0.0.1:9300",
    "AUTHENTIK_LISTEN__DEBUG": "127.0.0.1:9900",
    "AUTHENTIK_LISTEN__DEBUG_PY": "127.0.0.1:9901",
}
for key, expected_value in expected_server_private_listeners.items():
    if authentik_app.get("environment", {}).get(key) != expected_value:
        raise SystemExit(f"{authentik_path}: server listener {key} must stay on loopback")

trusted_proxy_key = "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS"
if authentik_app.get("environment", {}).get(trusted_proxy_key) != "${AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS:?Trusted proxy CIDRs required}":
    raise SystemExit(f"{authentik_path}: trusted proxy CIDRs must be explicit and required")
authentik_networks = authentik_app.get("networks")
if not isinstance(authentik_networks, dict):
    raise SystemExit(f"{authentik_path}: Authentik networks must support a frontend-only DNS alias")
frontend_network = authentik_networks.get("frontend")
backend_network = authentik_networks.get("backend")
if not isinstance(frontend_network, dict) or frontend_network.get("aliases") != ["authentik-frontend"]:
    raise SystemExit(f"{authentik_path}: frontend must define only the Authentik Forward Auth alias")
if isinstance(backend_network, dict) and "authentik-frontend" in (backend_network.get("aliases") or []):
    raise SystemExit(f"{authentik_path}: Forward Auth alias must not be registered on backend")
expected_server_entrypoint = [
    "python3",
    "/usr/local/lib/authentik-server-entrypoint.py",
]
if authentik_app.get("entrypoint") != expected_server_entrypoint:
    raise SystemExit(f"{authentik_path}: trusted-proxy preflight entrypoint is missing")
if authentik_app.get("command") != ["server"]:
    raise SystemExit(f"{authentik_path}: server command contract changed")

server_wrapper_path = root / "Authentik/scripts/authentik-server-entrypoint.py"
server_wrapper_spec = importlib.util.spec_from_file_location(
    "authentik_server_entrypoint",
    server_wrapper_path,
)
if server_wrapper_spec is None or server_wrapper_spec.loader is None:
    raise SystemExit(f"{server_wrapper_path}: could not load trusted-proxy preflight")
server_wrapper = importlib.util.module_from_spec(server_wrapper_spec)
server_wrapper_spec.loader.exec_module(server_wrapper)
valid_proxy_cidrs = "127.0.0.0/8,172.30.0.0/16,::1/128"
if server_wrapper.parse_trusted_proxy_cidrs(valid_proxy_cidrs) != tuple(valid_proxy_cidrs.split(",")):
    raise SystemExit(f"{server_wrapper_path}: valid exact proxy networks were rejected")
narrow_proxy_cidrs = "127.0.0.0/8,192.168.42.0/24,::1/128"
if server_wrapper.parse_trusted_proxy_cidrs(narrow_proxy_cidrs) != tuple(narrow_proxy_cidrs.split(",")):
    raise SystemExit(f"{server_wrapper_path}: valid narrow proxy network was rejected")
for invalid_proxy_cidrs in (
    "",
    "CHANGE_ME",
    "172.30.0.0/16",
    "127.0.0.0/8,::1/128",
    "127.0.0.0/8,172.30.0.0/16",
    "172.30.0.0/16,::1/128",
    "127.0.0.1/32,172.30.0.0/16,::1/128",
    "127.0.0.0/8,10.0.0.0/8",
    "127.0.0.0/8,172.16.0.0/12",
    "127.0.0.0/8,192.168.0.0/16,::1/128",
    "127.0.0.0/8,192.168.0.0/15",
    "127.0.0.0/8,172.30.1.1/16",
    "127.0.0.0/8,172.30.0.0/16,172.30.1.0/24",
    "127.0.0.0/8,fe80::/64",
):
    try:
        server_wrapper.parse_trusted_proxy_cidrs(invalid_proxy_cidrs)
    except ValueError:
        continue
    raise SystemExit(
        f"{server_wrapper_path}: unsafe trusted proxy fixture was accepted"
    )

exec_calls = []
original_execvp = server_wrapper.os.execvp
original_proxy_value = server_wrapper.os.environ.get(trusted_proxy_key)
try:
    server_wrapper.os.environ[trusted_proxy_key] = valid_proxy_cidrs
    server_wrapper.os.execvp = lambda executable, argv: exec_calls.append(
        (executable, list(argv))
    )
    if server_wrapper.main(["server"]) != 127:
        raise SystemExit(f"{server_wrapper_path}: valid handoff did not reach vendor exec")
    if exec_calls != [("ak", ["ak", "server"])]:
        raise SystemExit(f"{server_wrapper_path}: vendor handoff contract changed")
    exec_calls.clear()
    server_wrapper.os.environ[trusted_proxy_key] = "CHANGE_ME"
    with contextlib.redirect_stderr(io.StringIO()):
        if server_wrapper.main(["server"]) != 78 or exec_calls:
            raise SystemExit(f"{server_wrapper_path}: placeholder did not fail before vendor exec")
        if server_wrapper.main(["worker"]) != 64 or exec_calls:
            raise SystemExit(f"{server_wrapper_path}: unexpected command did not fail closed")
finally:
    server_wrapper.os.execvp = original_execvp
    if original_proxy_value is None:
        server_wrapper.os.environ.pop(trusted_proxy_key, None)
    else:
        server_wrapper.os.environ[trusted_proxy_key] = original_proxy_value

def volume_targets(service):
    targets = set()
    for item in service.get("volumes", []):
        if isinstance(item, dict):
            targets.add(str(item.get("target", "")))
        else:
            fields = str(item).split(":")
            if len(fields) >= 2:
                targets.add(fields[1])
    return targets

server_wrapper_target = "/usr/local/lib/authentik-server-entrypoint.py"
if server_wrapper_target not in volume_targets(authentik_app):
    raise SystemExit(f"{authentik_path}: trusted-proxy preflight helper is not mounted")
if server_wrapper_target in volume_targets(worker_service):
    raise SystemExit(f"{worker_path}: non-routing worker must not mount the server preflight")

if "/certs" in volume_targets(authentik_app):
    raise SystemExit(f"{authentik_path}: /certs belongs only on the Authentik worker")
if "/certs" not in volume_targets(worker_service):
    raise SystemExit(f"{worker_path}: worker must retain the Authentik certificate import mount")
if "AUTHENTIK_BOOTSTRAP_PASSWORD" in authentik_app_mounts:
    raise SystemExit(f"{authentik_path}: bootstrap password must not be mounted into the server")
if "AUTHENTIK_BOOTSTRAP_PASSWORD" in worker_mounts:
    raise SystemExit(f"{worker_path}: bootstrap password must not reach the final worker")
expected_runtime_mounts = {
    "POSTGRES_PASSWORD",
    "AUTHENTIK_SECRET_KEY_PASSWORD",
}
if authentik_app_mounts != expected_runtime_mounts:
    raise SystemExit(f"{authentik_path}: server runtime secret set must stay exact")
if worker_mounts != expected_runtime_mounts:
    raise SystemExit(f"{worker_path}: final worker runtime secret set must stay exact")
expected_bootstrap_mounts = {
    "POSTGRES_PASSWORD",
    "AUTHENTIK_SECRET_KEY_PASSWORD",
    "AUTHENTIK_BOOTSTRAP_PASSWORD",
}
if bootstrap_mounts != expected_bootstrap_mounts:
    raise SystemExit(
        f"{bootstrap_path}: one-shot bootstrap secret set must stay exact"
    )
for path, service in (
    (authentik_path, authentik_app),
    (worker_path, worker_service),
):
    bootstrap_environment = {
        str(key) for key in service.get("environment", {})
        if str(key).startswith("AUTHENTIK_BOOTSTRAP_")
    }
    if bootstrap_environment:
        raise SystemExit(
            f"{path}: final service exposes bootstrap environment {sorted(bootstrap_environment)}"
        )
    if any("authentik-bootstrap" in str(volume) for volume in service.get("volumes", [])):
        raise SystemExit(f"{path}: final service must not mount bootstrap helpers")
bootstrap_environment = set(bootstrap_service.get("environment", {}))
for forbidden_bootstrap_key in (
    "AUTHENTIK_BOOTSTRAP_PASSWORD",
    "AUTHENTIK_BOOTSTRAP_PASSWORD_HASH",
    "AUTHENTIK_BOOTSTRAP_TOKEN",
):
    if forbidden_bootstrap_key in bootstrap_environment:
        raise SystemExit(
            f"{bootstrap_path}: credential value must not be rendered into bootstrap environment"
        )
if bootstrap_service.get("restart") != "no":
    raise SystemExit(f"{bootstrap_path}: bootstrap must remain a restart-disabled one-shot")
if bootstrap_service.get("command") != ["bootstrap"]:
    raise SystemExit(f"{bootstrap_path}: bootstrap command contract changed")
if bootstrap_service.get("entrypoint") != [
    "/bin/sh",
    "/usr/local/bin/authentik-bootstrap-entrypoint.sh",
]:
    raise SystemExit(f"{bootstrap_path}: bootstrap entrypoint contract changed")
if bootstrap_service.get("healthcheck") != {"disable": True}:
    raise SystemExit(
        f"{bootstrap_path}: one-shot must disable the image daemon healthcheck"
    )
if bootstrap_service.get("networks") != ["backend"]:
    raise SystemExit(f"{bootstrap_path}: one-shot must stay backend-only")
if set((bootstrap_document.get("networks") or {}).keys()) != {"backend"}:
    raise SystemExit(f"{bootstrap_path}: one-shot template must declare only backend")
if worker_service.get("networks") != ["backend"]:
    raise SystemExit(f"{worker_path}: final worker must stay backend-only")
if set((worker_document.get("networks") or {}).keys()) != {"backend"}:
    raise SystemExit(f"{worker_path}: worker template must declare only backend")
expected_private_listeners = {
    "AUTHENTIK_LISTEN__HTTP": "127.0.0.1:9000",
    "AUTHENTIK_LISTEN__METRICS": "127.0.0.1:9300",
    "AUTHENTIK_LISTEN__DEBUG_PY": "127.0.0.1:9901",
}
for path, service in (
    (bootstrap_path, bootstrap_service),
    (worker_path, worker_service),
):
    environment = service.get("environment") or {}
    for key, expected_value in expected_private_listeners.items():
        if environment.get(key) != expected_value:
            raise SystemExit(
                f"{path}: non-routing listener {key} must stay on loopback"
            )
for exposure_key in ("ports", "expose", "labels"):
    if bootstrap_service.get(exposure_key):
        raise SystemExit(
            f"{bootstrap_path}: one-shot must not activate {exposure_key} exposure"
        )
    if worker_service.get(exposure_key):
        raise SystemExit(
            f"{worker_path}: final worker must not activate {exposure_key} exposure"
        )
postgres_dependency = (bootstrap_service.get("depends_on") or {}).get("postgresql")
if not isinstance(postgres_dependency, dict) or postgres_dependency.get("condition") != "service_healthy":
    raise SystemExit(f"{bootstrap_path}: bootstrap must wait for healthy PostgreSQL")
if worker_service.get("stop_grace_period") != "60s":
    raise SystemExit(f"{worker_path}: worker stop_grace_period must stay at tested value 60s")
if bootstrap_service.get("stop_grace_period") != "90s":
    raise SystemExit(f"{bootstrap_path}: bootstrap stop_grace_period must stay at tested value 90s")
if worker_service.get("environment", {}).get("AUTHENTIK_ERROR_REPORTING__ENABLED") != "${AUTHENTIK_ERROR_REPORTING__ENABLED:-false}":
    raise SystemExit(f"{worker_path}: error reporting must default to false")
if bootstrap_service.get("environment", {}).get("AUTHENTIK_ERROR_REPORTING__ENABLED") != "${AUTHENTIK_ERROR_REPORTING__ENABLED:-false}":
    raise SystemExit(f"{bootstrap_path}: error reporting must default to false")

authentik_env = root / "Authentik/.env"
trusted_proxy_match = re.search(
    r"^AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=([^#\n]+)",
    authentik_env.read_text(encoding="utf-8"),
    flags=re.MULTILINE,
)
if not trusted_proxy_match or trusted_proxy_match.group(1).strip() != "CHANGE_ME":
    raise SystemExit(
        f"{authentik_env}: trusted proxy CIDRs must remain an explicit deployment placeholder"
    )
traefik_env = root / "Traefik/.env"
traefik_path = root / "Traefik/docker-compose.app.yaml"
traefik_document = yaml.safe_load(traefik_path.read_text(encoding="utf-8"))
traefik_command = traefik_document["services"]["app"].get("command") or []
if "--providers.docker.network=frontend" not in traefik_command:
    raise SystemExit(f"{traefik_path}: Docker-provider routing must stay pinned to frontend")
forward_auth_match = re.search(
    r"^AUTHENTIK_FORWARD_AUTH_ADDRESS=([^#\n]+)",
    traefik_env.read_text(encoding="utf-8"),
    flags=re.MULTILINE,
)
expected_forward_auth_address = (
    "http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik"
)
if not forward_auth_match or forward_auth_match.group(1).strip() != expected_forward_auth_address:
    raise SystemExit(
        f"{traefik_env}: Forward Auth must use the frontend-only Authentik alias"
    )
traefik_environment = traefik_document["services"]["app"].get("environment") or {}
expected_dev_forward_environment = {
    "TRAEFIK_DEV_FORWARD_ENABLED": "${TRAEFIK_DEV_FORWARD_ENABLED:-false}",
    "TRAEFIK_DEV_FORWARD_TARGET_ADDRESS": "${TRAEFIK_DEV_FORWARD_TARGET_ADDRESS:-}",
    "TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS": "${TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS:-}",
}
for key, expected_value in expected_dev_forward_environment.items():
    if traefik_environment.get(key) != expected_value:
        raise SystemExit(
            f"{traefik_path}: {key} must stay wired to its fail-closed Compose default"
        )
traefik_env_text = traefik_env.read_text(encoding="utf-8")
for key, expected_value in {
    "TRAEFIK_DEV_FORWARD_ENABLED": "false",
    "TRAEFIK_DEV_FORWARD_TARGET_ADDRESS": "CHANGE_ME:443",
    "TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS": "",
}.items():
    assignment = re.search(
        rf"^{re.escape(key)}=([^#\n]*)",
        traefik_env_text,
        flags=re.MULTILINE,
    )
    if assignment is None or assignment.group(1).strip() != expected_value:
        raise SystemExit(f"{traefik_env}: {key} must keep its safe repository default")
dev_forward_path = root / "Traefik/appdata/config/conf.d/dev-traefik-forward.yaml"
dev_forward_text = dev_forward_path.read_text(encoding="utf-8")
for required_fragment in (
    '{{ if eq (env "TRAEFIK_DEV_FORWARD_ENABLED") "true" }}',
    'HostSNI(`dev.{{ env "TRAEFIK_DOMAIN" }}`)',
    'HostSNIRegexp(`^[^.]+\\.dev\\.{{ regexQuoteMeta (env "TRAEFIK_DOMAIN") }}$`)',
    "passthrough: true",
    "serversTransports:",
    "serversTransport: dev-traefik-forward-transport",
    "proxyProtocol:",
    "version: 2",
    "TRAEFIK_DEV_FORWARD_TARGET_ADDRESS",
):
    if required_fragment not in dev_forward_text:
        raise SystemExit(
            f"{dev_forward_path}: missing required DEV forwarding fragment {required_fragment!r}"
        )
if "proxyprotocol.insecure" in dev_forward_text.lower():
    raise SystemExit(f"{dev_forward_path}: PROXY protocol must never use insecure mode")
if re.search(r"loadBalancer:\s*\n\s+proxyProtocol:", dev_forward_text):
    raise SystemExit(
        f"{dev_forward_path}: deprecated service-local PROXY protocol configuration is forbidden"
    )
app_directories_match = re.search(
    r"^APP_DIRECTORIES=([^#\n]+)",
    authentik_env.read_text(encoding="utf-8"),
    flags=re.MULTILINE,
)
app_directories = {
    item.strip()
    for item in (app_directories_match.group(1) if app_directories_match else "").split(",")
    if item.strip()
}
expected_authentik_directories = {
    "appdata/data",
    "appdata/custom-templates",
    "appdata/certs",
}
if app_directories != expected_authentik_directories:
    raise SystemExit(
        f"{authentik_env}: APP_DIRECTORIES must list exact Authentik writable leaves"
    )

certs_path = root / "templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml"
certs_text = certs_path.read_text(encoding="utf-8")
certs_document = yaml.safe_load(certs_text)
certs_service = certs_document["services"]["traefik_certs-dumper"]
if certs_document.get("secrets"):
    raise SystemExit(f"{certs_path}: secretless certs-dumper must declare no active top-level secret")
if certs_service.get("secrets"):
    raise SystemExit(f"{certs_path}: local-only certs-dumper must mount no Docker secret")
if any("CF_DNS_API_TOKEN" in str(key) for key in certs_service.get("environment", {})):
    raise SystemExit(f"{certs_path}: local-only certs-dumper must receive no DNS-provider token")
if "CF_DNS_API_TOKEN" in certs_text:
    raise SystemExit(f"{certs_path}: stale secret remnant CF_DNS_API_TOKEN must be removed")
service_secret_scaffold = re.compile(
    r"^    # secrets:[ \t]*(?:#.*)?$\n"
    r"^    #   - TRAEFIK_CERTS_DUMPER_PASSWORD[ \t]*(?:#.*)?$",
    flags=re.MULTILINE,
)
top_level_secret_scaffold = re.compile(
    r"^# secrets:[ \t]*(?:#.*)?$\n"
    r"^#   TRAEFIK_CERTS_DUMPER_PASSWORD:[ \t]*(?:#.*)?$\n"
    r"^#     file: \$\{TRAEFIK_CERTS_DUMPER_PASSWORD_PATH:\?Secret path required\}/"
    r"\$\{TRAEFIK_CERTS_DUMPER_PASSWORD_FILENAME:\?Secret filename required\}[ \t]*(?:#.*)?$",
    flags=re.MULTILINE,
)
if not service_secret_scaffold.search(certs_text):
    raise SystemExit(f"{certs_path}: secretless service must retain its commented least-privilege secret scaffold")
if not top_level_secret_scaffold.search(certs_text):
    raise SystemExit(f"{certs_path}: secretless template must retain its commented top-level secret scaffold")
if (certs_path.parent / "secrets").exists():
    raise SystemExit(f"{certs_path.parent}: secretless template must not ship a secrets directory")
PY
}

expect_success compose-disabled-features-have-no-secret-mount check_disabled_feature_mounts

printf '\nSecret preflight tests: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
"${TEST_REPO_ROOT}/.cursor/scripts/test-crowdsec-agent-wrapper.sh"
