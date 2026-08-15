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
readonly TRAEFIK_DEV_FORWARD_TEMPLATE="${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/dev-traefik-forward.yaml.template"
readonly CERTS_DUMPER_SCRIPT="${TEST_REPO_ROOT}/templates/traefik_certs-dumper/dockerfiles/entrypoint.traefik_certs-dumper.sh"
readonly VIKUNJA_SCRIPT="${TEST_REPO_ROOT}/Vikunja/dockerfiles/entrypoint.sh"
readonly GITEA_SCRIPT="${TEST_REPO_ROOT}/Gitea/scripts/gitea-start.sh"
readonly GITEA_OIDC_SCRIPT="${TEST_REPO_ROOT}/Gitea/scripts/gitea-register-oidc.sh"
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
  'if [ -n "${TRAEFIK_ROUTE_MARKER:-}" ]; then' \
  '  {' \
  '    printf "TRAEFIK_ROUTE_SUBDOMAIN=%s\n" "${TRAEFIK_ROUTE_SUBDOMAIN:-}"' \
  '    printf "TRAEFIK_ROUTE_DOMAIN=%s\n" "${TRAEFIK_ROUTE_DOMAIN:-}"' \
  '    printf "TRAEFIK_ROUTE_DOMAIN_1=%s\n" "${TRAEFIK_ROUTE_DOMAIN_1:-}"' \
  '    printf "TRAEFIK_ROUTE_DOMAIN_2=%s\n" "${TRAEFIK_ROUTE_DOMAIN_2:-}"' \
  '    printf "TRAEFIK_ROUTE_DOMAIN_3=%s\n" "${TRAEFIK_ROUTE_DOMAIN_3:-}"' \
  '    printf "TRAEFIK_ROUTE_DOMAIN_4=%s\n" "${TRAEFIK_ROUTE_DOMAIN_4:-}"' \
  '  } >"$TRAEFIK_ROUTE_MARKER"' \
  'fi' \
  'exit 0' >"${TEST_BIN}/traefik"
printf '%s\n' '#!/bin/sh' '[ -z "${CERTS_DUMPER_MARKER:-}" ] || : >"$CERTS_DUMPER_MARKER"' 'exit 0' >"${TEST_BIN}/traefik-certs-dumper"
printf '%s\n' \
  '#!/bin/sh' \
  'stub_url=""' \
  'for stub_arg in "$@"; do stub_url="$stub_arg"; done' \
  '[ -z "${CF_STUB_CALLS:-}" ] || printf "%s\n" "$stub_url" >>"$CF_STUB_CALLS"' \
  'case "$stub_url" in' \
  '  *ips-v4*) [ -z "${CF_STUB_FAIL_V4:-}" ] || exit 1; stub_src="${CF_STUB_V4:-}" ;;' \
  '  *ips-v6*) [ -z "${CF_STUB_FAIL_V6:-}" ] || exit 1; stub_src="${CF_STUB_V6:-}" ;;' \
  '  *) exit 1 ;;' \
  'esac' \
  '[ -n "$stub_src" ] && [ -f "$stub_src" ] || exit 1' \
  'cat "$stub_src"' \
  'exit 0' >"${TEST_BIN}/wget"
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
  "${TEST_BIN}/wget" \
  "${TEST_BIN}/authentik-bootstrap-python" \
  "${TEST_BIN}/factorio-capture" \
  "${TEST_BIN}/kimai-php"

#ææææææææææææææææææææææææææææææææææ
# Officiæl-style Cloudflære IP list fixtures for the CLOUDFLARE_IPS=true switch
#ææææææææææææææææææææææææææææææææææ
readonly TRAEFIK_CF_IPS_DIR="${TEST_ROOT}/cf-ips"
mkdir -p -- "$TRAEFIK_CF_IPS_DIR"
printf '%s\n' \
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 \
  108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 \
  162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22 \
  >"${TRAEFIK_CF_IPS_DIR}/ips-v4"
printf '%s\n' \
  2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 \
  2a06:98c0::/29 2c0f:f248::/32 \
  >"${TRAEFIK_CF_IPS_DIR}/ips-v6"
printf '173.245.48.0/20\r\n103.21.244.0/22\r\n' >"${TRAEFIK_CF_IPS_DIR}/ips-v4-crlf"
: >"${TRAEFIK_CF_IPS_DIR}/ips-v4-empty"
printf 'not-an-ip\ngarbage\n' >"${TRAEFIK_CF_IPS_DIR}/ips-v4-garbage"
awk 'BEGIN { for (i = 0; i < 640; i++) printf "10.%d.%d.0/24\n", int(i / 256), i % 256 }' \
  >"${TRAEFIK_CF_IPS_DIR}/ips-v4-oversized"
awk 'BEGIN { for (i = 0; i < 200; i++) printf "10.0.%d.0/24\n", i }' \
  >"${TRAEFIK_CF_IPS_DIR}/ips-v4-too-many"

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
  mkdir -p -- "${fixture}/secrets" "${fixture}/acme" "${fixture}/dynamic"
  cp -- "$TRAEFIK_DEV_FORWARD_TEMPLATE" "${fixture}/dynamic/dev-traefik-forward.yaml.template"
  printf 'cloudflare-token' >"${fixture}/secrets/CF_DNS_API_TOKEN"
  printf '{"store":"production"}' >"${fixture}/acme/cloudflare-acme.json"
  printf '{"store":"staging"}' >"${fixture}/acme/cloudflare-staging-acme.json"
  chmod 0660 "${fixture}/acme/cloudflare-acme.json" "${fixture}/acme/cloudflare-staging-acme.json"
}

invoke_traefik() {
  local fixture="$1"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_ROUTE_SUBDOMAIN= TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
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
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER='../cloudflare' CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_ROUTE_SUBDOMAIN= TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

case_traefik_acme_symlink() {
  local fixture="${TEST_ROOT}/traefik-acme-symlink"
  prepare_traefik "$fixture"
  mv -- "${fixture}/acme/cloudflare-acme.json" "${fixture}/outside-acme.json"
  ln -s -- "${fixture}/outside-acme.json" "${fixture}/acme/cloudflare-acme.json"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_ROUTE_SUBDOMAIN= TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
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
#     $6 - Optionæl DEV DNS prefix
#     $7 - Optionæl route subdomæin
#ææææææææææææææææææææææææææææææææææ
run_traefik_forward_settings() {
  local fixture="$1"
  local enabled="$2"
  local domain="$3"
  local target="$4"
  local trusted_ips="$5"
  local prefix="${6:-dev}"
  local route_subdomain="${7:-}"
  prepare_traefik "$fixture"
  if [[ "$enabled" == true ]]; then
    cp -- "${fixture}/dynamic/dev-traefik-forward.yaml.template" "${fixture}/dynamic/dev-traefik-forward.yaml"
  fi
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_DEV_FORWARD_ENABLED="$enabled" TRAEFIK_DOMAIN="$domain" \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    TRAEFIK_DEV_FORWARD_PREFIX="$prefix" \
    TRAEFIK_DEV_FORWARD_TARGET_ADDRESS="$target" \
    TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS="$trusted_ips" \
    TRAEFIK_ROUTE_SUBDOMAIN="$route_subdomain" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_traefik_route_subdomain_settings
#   Runs the Træefik wræpper with one route-subdomæin ænd domæin mætrix.
#   Ærguments:
#     $1 - Fixture root
#     $2 - Optionæl route subdomæin
#     $3 - Internæl bæse domæin
#     $4 - Optionæl domæin 1
#     $5 - Optionæl domæin 2
#     $6 - Optionæl domæin 3
#     $7 - Optionæl domæin 4
#     $8 - Optionæl ræw-bæse wildcærd certificæte flæg
#ææææææææææææææææææææææææææææææææææ
run_traefik_route_subdomain_settings() {
  local fixture="$1"
  local route_subdomain="$2"
  local domain="$3"
  local domain_1="$4"
  local domain_2="$5"
  local domain_3="$6"
  local domain_4="$7"
  local base_wildcard_enabled="${8:-false}"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ROUTE_MARKER="${fixture}/traefik-route-environment" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_ROUTE_SUBDOMAIN="$route_subdomain" TRAEFIK_DOMAIN="$domain" \
    TRAEFIK_DOMAIN_1="$domain_1" TRAEFIK_DOMAIN_2="$domain_2" \
    TRAEFIK_DOMAIN_3="$domain_3" TRAEFIK_DOMAIN_4="$domain_4" \
    TRAEFIK_BASE_WILDCARD_CERT_ENABLED="$base_wildcard_enabled" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_route_subdomain_empty
#   Proves æ blænk route subdomæin preserves every configured bæse domæin.
#ææææææææææææææææææææææææææææææææææ
case_traefik_route_subdomain_empty() {
  local fixture="${TEST_ROOT}/traefik-route-subdomain-empty"
  run_traefik_route_subdomain_settings \
    "$fixture" '' xn--lb-1ia.de xn--srvices-mxa.de saervices.de '' itsaervices.de
  printf '%s\n' \
    'TRAEFIK_ROUTE_SUBDOMAIN=' \
    'TRAEFIK_ROUTE_DOMAIN=xn--lb-1ia.de' \
    'TRAEFIK_ROUTE_DOMAIN_1=xn--srvices-mxa.de' \
    'TRAEFIK_ROUTE_DOMAIN_2=saervices.de' \
    'TRAEFIK_ROUTE_DOMAIN_3=' \
    'TRAEFIK_ROUTE_DOMAIN_4=itsaervices.de' \
    | cmp -s - "${fixture}/traefik-route-environment"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_route_subdomain_it
#   Proves `it` is prepended once while empty optionæl domæins remæin empty.
#ææææææææææææææææææææææææææææææææææ
case_traefik_route_subdomain_it() {
  local fixture="${TEST_ROOT}/traefik-route-subdomain-it"
  run_traefik_route_subdomain_settings \
    "$fixture" it xn--lb-1ia.de xn--srvices-mxa.de saervices.de '' itsaervices.de
  printf '%s\n' \
    'TRAEFIK_ROUTE_SUBDOMAIN=it' \
    'TRAEFIK_ROUTE_DOMAIN=it.xn--lb-1ia.de' \
    'TRAEFIK_ROUTE_DOMAIN_1=it.xn--srvices-mxa.de' \
    'TRAEFIK_ROUTE_DOMAIN_2=it.saervices.de' \
    'TRAEFIK_ROUTE_DOMAIN_3=' \
    'TRAEFIK_ROUTE_DOMAIN_4=it.itsaervices.de' \
    | cmp -s - "${fixture}/traefik-route-environment"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_base_wildcard_with_route_subdomain
#   Proves the ræw-bæse wildcærd opt-in is vælid only outside the exæct æpp spæce.
#ææææææææææææææææææææææææææææææææææ
case_traefik_base_wildcard_with_route_subdomain() {
  local fixture="${TEST_ROOT}/traefik-base-wildcard-with-route-subdomain"
  run_traefik_route_subdomain_settings \
    "$fixture" it xn--lb-1ia.de xn--srvices-mxa.de saervices.de it-saervices.de itsaervices.de true
  grep -qx -- '--version' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_route_effective_host_too_long
#   Proves the complete æpp host, not only its suffix, must fit DNS limits.
#ææææææææææææææææææææææææææææææææææ
case_traefik_route_effective_host_too_long() {
  local label_60 label_58 overlong_base
  printf -v label_60 '%060d' 0
  printf -v label_58 '%058d' 0
  overlong_base="${label_60}.${label_60}.${label_60}.${label_58}"
  run_traefik_route_subdomain_settings \
    "${TEST_ROOT}/traefik-route-effective-host-too-long" '' "$overlong_base" '' '' '' ''
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_route_dev_collision_disabled
#   Proves equæl route ænd DEV prefixes ære vælid while forwærding is disæbled.
#ææææææææææææææææææææææææææææææææææ
case_traefik_route_dev_collision_disabled() {
  local fixture="${TEST_ROOT}/traefik-route-dev-collision-disabled"
  run_traefik_forward_settings "$fixture" false internal.example CHANGE_ME:443 '' dev dev
  grep -qx -- '--version' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_route_dev_prefixes_distinct
#   Proves distinct route ænd DEV prefixes ære vælid while forwærding is enæbled.
#ææææææææææææææææææææææææææææææææææ
case_traefik_route_dev_prefixes_distinct() {
  local fixture="${TEST_ROOT}/traefik-route-dev-prefixes-distinct"
  run_traefik_forward_settings "$fixture" true internal.example 192.168.10.100:443 '' dev it
  grep -qx -- '--version' "${fixture}/traefik-started"
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
# FUNCTION: case_traefik_dev_forward_custom_prefix
#   Proves æ vælid custom DNS læbel is æccepted.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_custom_prefix() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-custom-prefix"
  run_traefik_forward_settings "$fixture" true it.saervices.de 192.168.10.100:443 '' staging-dev
  grep -qx -- '--version' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_missing_live_file
#   Proves the environment opt-in ælone cænnot enæble the route.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_missing_live_file() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-missing-live-file"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_DEV_FORWARD_ENABLED=true TRAEFIK_DOMAIN=it.saervices.de \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    TRAEFIK_DEV_FORWARD_PREFIX=dev TRAEFIK_DEV_FORWARD_TARGET_ADDRESS=192.168.10.100:443 \
    TRAEFIK_ROUTE_SUBDOMAIN= \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_disabled_live_file
#   Proves the copied route file cænnot remæin æctive while the environment opt-in is false.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_disabled_live_file() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-disabled-live-file"
  prepare_traefik "$fixture"
  cp -- "${fixture}/dynamic/dev-traefik-forward.yaml.template" "${fixture}/dynamic/dev-traefik-forward.yaml"
  invoke_traefik "$fixture"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_stale_live_file
#   Proves æ modified or stæle live copy fæils before Træefik stærts.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_stale_live_file() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-stale-live-file"
  prepare_traefik "$fixture"
  cp -- "${fixture}/dynamic/dev-traefik-forward.yaml.template" "${fixture}/dynamic/dev-traefik-forward.yaml"
  printf '\n# stale\n' >>"${fixture}/dynamic/dev-traefik-forward.yaml"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_DEV_FORWARD_ENABLED=true TRAEFIK_DOMAIN=it.saervices.de \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    TRAEFIK_DEV_FORWARD_PREFIX=dev TRAEFIK_DEV_FORWARD_TARGET_ADDRESS=192.168.10.100:443 \
    TRAEFIK_ROUTE_SUBDOMAIN= \
    /bin/sh "$TRAEFIK_SCRIPT" --version
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
# FUNCTION: run_traefik_forwarded_header_settings
#   Runs the Træefik wræpper with one explicit forwærded-heæder trust configurætion.
#   Ærguments:
#     $1 - Fixture root
#     $2 - LOCAL_IPS vælue
#     $3 - CLOUDFLARE_IPS vælue
#ææææææææææææææææææææææææææææææææææ
run_traefik_forwarded_header_settings() {
  local fixture="$1"
  local local_ips="$2"
  local cloudflare_ips="$3"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_ROUTE_SUBDOMAIN= TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    LOCAL_IPS="$local_ips" CLOUDFLARE_IPS="$cloudflare_ips" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_forwarded_header_local_only
#   Proves loopbæck-only trust becomes one identicæl web ænd websecure ærgument.
#ææææææææææææææææææææææææææææææææææ
case_traefik_forwarded_header_local_only() {
  local fixture="${TEST_ROOT}/traefik-forwarded-header-local-only"
  run_traefik_forwarded_header_settings "$fixture" 127.0.0.1/32 ''
  [[ "$(grep -Fxc -- '--entrypoints.web.forwardedheaders.trustedips=127.0.0.1/32' "${fixture}/traefik-started")" == 1 ]]
  [[ "$(grep -Fxc -- '--entrypoints.websecure.forwardedheaders.trustedips=127.0.0.1/32' "${fixture}/traefik-started")" == 1 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_forwarded_header_combined
#   Proves locæl ænd Cloudflære IPv4/IPv6 CIDRs merge in stæble order.
#ææææææææææææææææææææææææææææææææææ
case_traefik_forwarded_header_combined() {
  local fixture="${TEST_ROOT}/traefik-forwarded-header-combined"
  local expected='--entrypoints.websecure.forwardedheaders.trustedips=127.0.0.1/32,103.21.244.0/22,2400:cb00::/32'
  run_traefik_forwarded_header_settings "$fixture" 127.0.0.1/32 '103.21.244.0/22,2400:cb00::/32'
  [[ "$(grep -Fxc -- "$expected" "${fixture}/traefik-started")" == 1 ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_forwarded_header_blank
#   Proves fully blænk lists æppend no forwærded-heæder trust ærgument.
#ææææææææææææææææææææææææææææææææææ
case_traefik_forwarded_header_blank() {
  local fixture="${TEST_ROOT}/traefik-forwarded-header-blank"
  run_traefik_forwarded_header_settings "$fixture" '' ''
  grep -qx -- '--version' "${fixture}/traefik-started"
  ! grep -q -- 'forwardedheaders.trustedips' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_traefik_cloudflare_switch
#   Runs the Træefik wræpper with one CLOUDFLARE_IPS switch ænd fetch stubs.
#   Ærguments:
#     $1 - Fixture root
#     $2 - CLOUDFLARE_IPS switch (false, true, or æ pinned CIDR list)
#     $3 - Optionæl CF_STUB_V4 source pæth
#     $4 - Optionæl CF_STUB_V6 source pæth
#     $5 - Optionæl CF_STUB_FAIL_V4 flæg
#     $6 - Optionæl CF_STUB_FAIL_V6 flæg
#     $7 - Optionæl CF_STUB_CALLS log pæth
#ææææææææææææææææææææææææææææææææææ
run_traefik_cloudflare_switch() {
  local fixture="$1"
  local switch="$2"
  local stub_v4="${3:-}"
  local stub_v6="${4:-}"
  local stub_fail_v4="${5:-}"
  local stub_fail_v6="${6:-}"
  local stub_calls="${7:-}"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_ROUTE_SUBDOMAIN= TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    LOCAL_IPS=127.0.0.1/32 CLOUDFLARE_IPS="$switch" \
    CF_STUB_V4="$stub_v4" CF_STUB_V6="$stub_v6" \
    CF_STUB_FAIL_V4="$stub_fail_v4" CF_STUB_FAIL_V6="$stub_fail_v6" \
    CF_STUB_CALLS="$stub_calls" \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_cloudflare_switch_fetch
#   Proves true fetches both officiæl lists into one bounded trust ærgument.
#ææææææææææææææææææææææææææææææææææ
case_traefik_cloudflare_switch_fetch() {
  local fixture="${TEST_ROOT}/traefik-cloudflare-switch-fetch"
  local expected_entries=23
  local actual_entries
  run_traefik_cloudflare_switch "$fixture" true \
    "${TRAEFIK_CF_IPS_DIR}/ips-v4" "${TRAEFIK_CF_IPS_DIR}/ips-v6"
  grep -qx -- '--version' "${fixture}/traefik-started"
  grep -q -- '--entrypoints.web.forwardedheaders.trustedips=127.0.0.1/32,173.245.48.0/20,' "${fixture}/traefik-started"
  grep -q -- '173.245.48.0/20' "${fixture}/traefik-started"
  grep -q -- '2400:cb00::/32' "${fixture}/traefik-started"
  actual_entries="$(grep -m1 -- '--entrypoints.websecure.forwardedheaders.trustedips=' "${fixture}/traefik-started" \
    | sed 's/.*trustedips=//' | tr ',' '\n' | grep -c .)"
  [[ "$actual_entries" == "$expected_entries" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_cloudflare_switch_crlf
#   Proves CRLF-terminæted upstreæm lists normælise without blænk entries.
#ææææææææææææææææææææææææææææææææææ
case_traefik_cloudflare_switch_crlf() {
  local fixture="${TEST_ROOT}/traefik-cloudflare-switch-crlf"
  run_traefik_cloudflare_switch "$fixture" true \
    "${TRAEFIK_CF_IPS_DIR}/ips-v4-crlf" "${TRAEFIK_CF_IPS_DIR}/ips-v6"
  grep -q -- '--entrypoints.websecure.forwardedheaders.trustedips=127.0.0.1/32,173.245.48.0/20,103.21.244.0/22,2400:cb00::/32,' "${fixture}/traefik-started"
  ! grep -q -- ',,' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_cloudflare_switch_false_skips_fetch
#   Proves false trusts only LOCAL_IPS ænd never contæcts the upstreæm list.
#ææææææææææææææææææææææææææææææææææ
case_traefik_cloudflare_switch_false_skips_fetch() {
  local fixture="${TEST_ROOT}/traefik-cloudflare-switch-false"
  run_traefik_cloudflare_switch "$fixture" false \
    "${TRAEFIK_CF_IPS_DIR}/ips-v4" "${TRAEFIK_CF_IPS_DIR}/ips-v6" 1 1 "${fixture}/wget-calls"
  grep -qx -- '--entrypoints.web.forwardedheaders.trustedips=127.0.0.1/32' "${fixture}/traefik-started"
  [[ ! -e "${fixture}/wget-calls" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_cloudflare_switch_pinned
#   Proves æ mænuælly pinned CIDR list is trusted without æny fetch.
#ææææææææææææææææææææææææææææææææææ
case_traefik_cloudflare_switch_pinned() {
  local fixture="${TEST_ROOT}/traefik-cloudflare-switch-pinned"
  run_traefik_cloudflare_switch "$fixture" '203.0.113.0/24,2001:db8::/32' \
    '' '' '' '' "${fixture}/wget-calls"
  grep -qx -- '--entrypoints.websecure.forwardedheaders.trustedips=127.0.0.1/32,203.0.113.0/24,2001:db8::/32' "${fixture}/traefik-started"
  [[ ! -e "${fixture}/wget-calls" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_dev_forward_rejects_before_mutation
#   Proves invælid forwærding stops before ÆCME file mode normælisætion.
#ææææææææææææææææææææææææææææææææææ
case_traefik_dev_forward_rejects_before_mutation() {
  local fixture="${TEST_ROOT}/traefik-dev-forward-rejects-before-mutation"
  prepare_traefik "$fixture"
  cp -- "${fixture}/dynamic/dev-traefik-forward.yaml.template" "${fixture}/dynamic/dev-traefik-forward.yaml"
  if PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" \
    TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_DEV_FORWARD_ENABLED=true TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    TRAEFIK_DEV_FORWARD_TARGET_ADDRESS=CHANGE_ME:443 \
    TRAEFIK_ROUTE_SUBDOMAIN= \
    /bin/sh "$TRAEFIK_SCRIPT" --version; then
    return 1
  fi
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-acme.json")" == 660 ]]
  [[ "$(stat -c '%a' "${fixture}/acme/cloudflare-staging-acme.json")" == 660 ]]
  [[ ! -e "${fixture}/traefik-started" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_traefik_canonical_settings
#   Runs the Træefik wræpper with one explicit cænonicæl redirect configurætion.
#   Ærguments:
#     $1 - Fixture root
#     $2 - Internæl TRAEFIK_DOMAIN
#     $3 - Cænonicæl TRAEFIK_DOMAIN_1
#     $4 - Source TRAEFIK_DOMAIN_2
#     $5 - Source TRAEFIK_DOMAIN_3
#     $6 - Source TRAEFIK_DOMAIN_4
#ææææææææææææææææææææææææææææææææææ
run_traefik_canonical_settings() {
  local fixture="$1"
  local internal_domain="$2"
  local target_domain="$3"
  local source_domain_2="$4"
  local source_domain_3="$5"
  local source_domain_4="$6"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL=true TRAEFIK_DOMAIN="$internal_domain" \
    TRAEFIK_DOMAIN_1="$target_domain" TRAEFIK_DOMAIN_2="$source_domain_2" \
    TRAEFIK_DOMAIN_3="$source_domain_3" TRAEFIK_DOMAIN_4="$source_domain_4" \
    TRAEFIK_ROUTE_SUBDOMAIN= \
    /bin/sh "$TRAEFIK_SCRIPT" --version
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_canonical_redirect_valid
#   Proves the internæl domæin, public tærget, ænd three unique sources ære æccepted.
#ææææææææææææææææææææææææææææææææææ
case_traefik_canonical_redirect_valid() {
  local fixture="${TEST_ROOT}/traefik-canonical-redirect-valid"
  run_traefik_canonical_settings "$fixture" xn--lb-1ia.de xn--srvices-mxa.de saervices.de it-saervices.de itsaervices.de
  grep -qx -- '--version' "${fixture}/traefik-started"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_canonical_route_subdomain_preserved
#   Proves the cænonicæl redirect replæces only the bæse-domæin suffix.
#ææææææææææææææææææææææææææææææææææ
case_traefik_canonical_route_subdomain_preserved() {
  python3 - "${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/canonical-domain-redirect.yaml" <<'PY'
import re
import sys
from pathlib import Path

canonical_path = Path(sys.argv[1])
canonical_text = canonical_path.read_text(encoding="utf-8")
required_regex = "((?:[A-Za-z0-9-]+\\.)*)({{ $canonicalRedirectRegexDomains | join \"|\" }})"
required_replacement = "https://${1}{{ env \"TRAEFIK_DOMAIN_1\" }}${3}${4}"
if required_regex not in canonical_text or required_replacement not in canonical_text:
    raise SystemExit(f"{canonical_path}: canonical host-prefix capture contract drifted")

source_domains = ("saervices.de", "it-saervices.de", "itsaervices.de")
source_pattern = "|".join(re.escape(domain) for domain in source_domains)
redirect_pattern = re.compile(
    rf"^https://((?:[A-Za-z0-9-]+\.)*)({source_pattern})(:[0-9]+)?(/.*)?$"
)
request_url = (
    "https://authentik.it.saervices.de:443/path/"
    "marcel.hennke@it.saervices.de/item?next=mail.it.saervices.de"
)
match = redirect_pattern.fullmatch(request_url)
if match is None:
    raise SystemExit("canonical route-subdomain fixture did not match")
redirect_url = (
    f"https://{match.group(1)}xn--srvices-mxa.de"
    f"{match.group(3) or ''}{match.group(4) or ''}"
)
expected_url = (
    "https://authentik.it.xn--srvices-mxa.de:443/path/"
    "marcel.hennke@it.saervices.de/item?next=mail.it.saervices.de"
)
if redirect_url != expected_url:
    raise SystemExit(f"canonical redirect changed non-host content: {redirect_url!r}")
PY
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: case_traefik_canonical_mailcow_mta_sts_policy
#   Proves only the exæct MTA-STS policy request fælls through to Mæilcow.
#ææææææææææææææææææææææææææææææææææ
case_traefik_canonical_mailcow_mta_sts_policy() {
  python3 - \
    "${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/canonical-domain-redirect.yaml" \
    "${TEST_REPO_ROOT}/Traefik/appdata/config/conf.d/mailcow.yaml.template" <<'PY'
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

canonical_path = Path(sys.argv[1])
mailcow_path = Path(sys.argv[2])
canonical_text = canonical_path.read_text(encoding="utf-8")
mailcow_text = mailcow_path.read_text(encoding="utf-8")


def extract_router_block(config_text, router_name):
    lines = config_text.splitlines()
    for line_index, line in enumerate(lines):
        if not line.lstrip().startswith(f"{router_name}:"):
            continue
        router_indent = len(line) - len(line.lstrip())
        block = [line]
        for block_line in lines[line_index + 1:]:
            if block_line.strip():
                block_indent = len(block_line) - len(block_line.lstrip())
                if block_indent <= router_indent:
                    break
            block.append(block_line)
        return "\n".join(block)
    raise SystemExit(f"missing router block {router_name}")


def extract_folded_rule(router_block, router_name):
    lines = router_block.splitlines()
    for line_index, line in enumerate(lines):
        if re.match(r"^\s+rule:\s+>-", line) is None:
            continue
        rule_indent = len(line) - len(line.lstrip())
        rule_lines = []
        for rule_line in lines[line_index + 1:]:
            if rule_line.strip():
                line_indent = len(rule_line) - len(rule_line.lstrip())
                if line_indent <= rule_indent:
                    break
                rule_lines.append(rule_line.strip())
        return " ".join(rule_lines)
    raise SystemExit(f"missing folded rule for {router_name}")


canonical_router = extract_router_block(canonical_text, "canonical-domain-redirect-rtr")
mailcow_router = extract_router_block(mailcow_text, "mailcow-rtr")
if canonical_text.count("canonical-domain-redirect-rtr:") != 1:
    raise SystemExit(f"{canonical_path}: MTA-STS exception must not add another router")
if re.search(r"^\s+priority:\s+10000\s+", canonical_router, flags=re.MULTILINE) is None:
    raise SystemExit(f"{canonical_path}: canonical router must keep explicit priority 10000")
if "\n      tls:" in canonical_router or "certResolver:" in canonical_router:
    raise SystemExit(f"{canonical_path}: MTA-STS exception must not add TLS/certificate scope")
if re.search(r"^\s+service:\s+mailcow-svc\s+", mailcow_router, flags=re.MULTILINE) is None:
    raise SystemExit(f"{mailcow_path}: MTA-STS policy must still use mailcow-svc")
if 'url: "http://192.168.20.120/"' not in mailcow_text:
    raise SystemExit(f"{mailcow_path}: Mailcow service target drifted")

canonical_rule = extract_folded_rule(
    canonical_router,
    "canonical-domain-redirect-rtr",
)
mailcow_rule_template = extract_folded_rule(mailcow_router, "mailcow-rtr")
canonical_domain_range = (
    '{{ range $index, $domain := $canonicalRedirectDomains }}'
    '{{ if gt $index 0 }} || {{ end }}'
    'Host(`{{ $domain }}`) || '
    'HostRegexp(`^.+\\.{{ regexQuoteMeta $domain }}$`){{ end }}'
)
canonical_policy_host_range = (
    '{{ range $index, $host := $canonicalMtaStsPolicyHosts }}'
    '{{ if gt $index 0 }} || {{ end }}Host(`{{ $host }}`){{ end }}'
)
expected_canonical_rule = (
    f"({canonical_domain_range}) && !(({canonical_policy_host_range}) && "
    "Path(`/.well-known/mta-sts.txt`))"
)
if canonical_rule != expected_canonical_rule:
    raise SystemExit(
        f"{canonical_path}: canonical rule must exempt only exact MTA-STS host plus exact policy path"
    )

raw_domains = {
    "TRAEFIK_DOMAIN": "xn--lb-1ia.de",
    "TRAEFIK_DOMAIN_1": "xn--srvices-mxa.de",
    "TRAEFIK_DOMAIN_2": "saervices.de",
    "TRAEFIK_DOMAIN_3": "it-saervices.de",
    "TRAEFIK_DOMAIN_4": "itsaervices.de",
}
route_domains = {
    name.replace("TRAEFIK_DOMAIN", "TRAEFIK_ROUTE_DOMAIN"): f"it.{domain}"
    for name, domain in raw_domains.items()
}
environment = {**raw_domains, **route_domains}
source_domains = tuple(raw_domains[f"TRAEFIK_DOMAIN_{index}"] for index in (2, 3, 4))
policy_hosts = tuple(
    f"mta-sts.{route_domains[f'TRAEFIK_ROUTE_DOMAIN_{index}']}"
    for index in (2, 3, 4)
)
rendered_domain_range = " || ".join(
    f"Host(`{domain}`) || HostRegexp(`^.+\\.{re.escape(domain)}$`)"
    for domain in source_domains
)
rendered_policy_hosts = " || ".join(f"Host(`{host}`)" for host in policy_hosts)
canonical_rendered_rule = canonical_rule.replace(
    canonical_domain_range,
    rendered_domain_range,
).replace(
    canonical_policy_host_range,
    rendered_policy_hosts,
)
if "{{" in canonical_rendered_rule:
    raise SystemExit(f"{canonical_path}: canonical rule fixture did not render completely")


def render_mailcow_rule(rule_template):
    conditional_pattern = re.compile(
        r'\{\{-?\s*if env "(?P<name>[A-Z0-9_]+)"\s*\}\}'
        r'(?P<body>.*?)\{\{\s*end\s*\}\}',
        flags=re.DOTALL,
    )
    rendered = conditional_pattern.sub(
        lambda match: match.group("body") if environment.get(match.group("name"), "") else "",
        rule_template,
    )
    rendered = re.sub(
        r'\{\{\s*env "(?P<name>[A-Z0-9_]+)"\s*\}\}',
        lambda match: environment.get(match.group("name"), ""),
        rendered,
    )
    if "{{" in rendered:
        raise SystemExit(f"{mailcow_path}: Mailcow rule fixture did not render completely")
    return rendered


mailcow_rendered_rule = render_mailcow_rule(mailcow_rule_template)
if 10000 <= len(mailcow_rendered_rule):
    raise SystemExit(f"{canonical_path}: canonical priority no longer wins service overlaps")


def evaluate_rule(rule, host, path):
    expression = re.sub(
        r'HostRegexp\(`([^`]*)`\)',
        lambda match: str(re.fullmatch(match.group(1), host) is not None),
        rule,
    )
    expression = re.sub(
        r'Host\(`([^`]*)`\)',
        lambda match: str(host == match.group(1)),
        expression,
    )
    expression = re.sub(
        r'PathPrefix\(`([^`]*)`\)',
        lambda match: str(path.startswith(match.group(1))),
        expression,
    )
    expression = re.sub(
        r'Path\(`([^`]*)`\)',
        lambda match: str(path == match.group(1)),
        expression,
    )
    expression = expression.replace("&&", " and ").replace("||", " or ")
    expression = re.sub(r"!(?!=)", " not ", expression)
    unsafe_remainder = re.sub(
        r"\b(?:True|False|and|or|not)\b|[()\s]",
        "",
        expression,
    )
    if unsafe_remainder:
        raise SystemExit(f"unsupported rendered Traefik rule fragment {unsafe_remainder!r}")
    return bool(eval(expression, {"__builtins__": {}}, {}))


redirect_pattern = re.compile(
    rf"^https://((?:[A-Za-z0-9-]+\.)*)({'|'.join(re.escape(domain) for domain in source_domains)})(:[0-9]+)?(/.*)?$"
)


def route_request(request_url):
    request = urlsplit(request_url)
    host = request.hostname or ""
    canonical_match = evaluate_rule(canonical_rendered_rule, host, request.path)
    mailcow_match = evaluate_rule(mailcow_rendered_rule, host, request.path)
    if canonical_match:
        redirect_match = redirect_pattern.fullmatch(request_url)
        if redirect_match is None:
            raise SystemExit(f"canonical matcher lacked redirectRegex coverage for {request_url}")
        location = (
            f"https://{redirect_match.group(1)}{raw_domains['TRAEFIK_DOMAIN_1']}"
            f"{redirect_match.group(3) or ''}{redirect_match.group(4) or ''}"
        )
        return "redirect", location, mailcow_match
    if mailcow_match:
        return "mailcow-svc", None, True
    return "404", None, False


for policy_host in policy_hosts:
    for query in ("", "?mode=enforce&domain=it.saervices.de"):
        policy_url = f"https://{policy_host}/.well-known/mta-sts.txt{query}"
        outcome, location, mailcow_match = route_request(policy_url)
        if outcome != "mailcow-svc" or location is not None or not mailcow_match:
            raise SystemExit(
                f"{canonical_path}: exact MTA-STS policy request did not reach mailcow-svc"
            )

redirect_cases = {
    "https://mta-sts.it.saervices.de/":
        "https://mta-sts.it.xn--srvices-mxa.de/",
    "https://mta-sts.it.saervices.de/.well-known/mta-sts.txt/":
        "https://mta-sts.it.xn--srvices-mxa.de/.well-known/mta-sts.txt/",
    "https://mta-sts.it.saervices.de/.well-known/MTA-STS.txt?domain=it.saervices.de":
        "https://mta-sts.it.xn--srvices-mxa.de/.well-known/MTA-STS.txt?domain=it.saervices.de",
    "https://mail.it.saervices.de/.well-known/acme-challenge/token?domain=it.saervices.de":
        "https://mail.it.xn--srvices-mxa.de/.well-known/acme-challenge/token?domain=it.saervices.de",
    "https://autodiscover.it.saervices.de/autodiscover/autodiscover.xml?domain=it.saervices.de":
        "https://autodiscover.it.xn--srvices-mxa.de/autodiscover/autodiscover.xml?domain=it.saervices.de",
    "https://autoconfig.it.saervices.de/mail/config-v1.1.xml?domain=it.saervices.de":
        "https://autoconfig.it.xn--srvices-mxa.de/mail/config-v1.1.xml?domain=it.saervices.de",
    "https://mail.it.saervices.de:443/archive/it.saervices.de/marcel@it.saervices.de?next=mta-sts.it.saervices.de":
        "https://mail.it.xn--srvices-mxa.de:443/archive/it.saervices.de/marcel@it.saervices.de?next=mta-sts.it.saervices.de",
}
for request_url, expected_location in redirect_cases.items():
    outcome, location, _ = route_request(request_url)
    if outcome != "redirect" or location != expected_location:
        raise SystemExit(
            f"{canonical_path}: redirect exception broadened or path/query suffix changed for {request_url}"
        )
PY
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_traefik_forward_auth_address
#   Runs the Træefik wræpper with one explicit Forwærd Æuth endpoint.
#   Ærguments:
#     $1 - Fixture root
#     $2 - Forwærd Æuth URL
#ææææææææææææææææææææææææææææææææææ
run_traefik_forward_auth_address() {
  local fixture="$1"
  local address="$2"
  prepare_traefik "$fixture"
  PATH="${TEST_BIN}:${PATH}" TRAEFIK_MARKER="${fixture}/traefik-started" \
    TRAEFIK_ACME_STORAGE_DIR="${fixture}/acme" TRAEFIK_DYNAMIC_CONFIG_DIR="${fixture}/dynamic" \
    CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    AUTHENTIK_FORWARD_AUTH_ADDRESS="$address" \
    TRAEFIK_ROUTE_SUBDOMAIN= TRAEFIK_DOMAIN=example.com \
    TRAEFIK_DOMAIN_1= TRAEFIK_DOMAIN_2= TRAEFIK_DOMAIN_3= TRAEFIK_DOMAIN_4= \
    /bin/sh "$TRAEFIK_SCRIPT" --version
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
expect_success traefik-route-subdomain-empty case_traefik_route_subdomain_empty
expect_success traefik-route-subdomain-it case_traefik_route_subdomain_it
expect_success traefik-base-wildcard-with-route-subdomain case_traefik_base_wildcard_with_route_subdomain
expect_failure traefik-base-wildcard-without-route-subdomain run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-base-wildcard-without-route-subdomain" '' internal.example '' '' '' '' true
expect_failure traefik-base-wildcard-invalid-boolean run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-base-wildcard-invalid-boolean" it internal.example '' '' '' '' TRUE
expect_failure traefik-route-subdomain-uppercase run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-route-subdomain-uppercase" IT internal.example '' '' '' ''
expect_failure traefik-route-subdomain-dot run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-route-subdomain-dot" it.dev internal.example '' '' '' ''
expect_failure traefik-route-subdomain-wildcard run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-route-subdomain-wildcard" '*' internal.example '' '' '' ''
expect_failure traefik-route-subdomain-leading-hyphen run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-route-subdomain-leading-hyphen" -it internal.example '' '' '' ''
expect_failure traefik-route-subdomain-trailing-hyphen run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-route-subdomain-trailing-hyphen" it- internal.example '' '' '' ''
expect_failure traefik-route-subdomain-too-long run_traefik_route_subdomain_settings "${TEST_ROOT}/traefik-route-subdomain-too-long" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa internal.example '' '' '' ''
expect_failure traefik-route-effective-host-too-long case_traefik_route_effective_host_too_long
expect_success traefik-route-dev-collision-disabled case_traefik_route_dev_collision_disabled
expect_success traefik-route-dev-prefixes-distinct case_traefik_route_dev_prefixes_distinct
expect_failure traefik-route-dev-collision-enabled run_traefik_forward_settings "${TEST_ROOT}/traefik-route-dev-collision-enabled" true internal.example 192.168.10.100:443 '' dev dev
expect_success traefik-dev-forward-disabled case_traefik_dev_forward_disabled
expect_success traefik-dev-forward-enabled case_traefik_dev_forward_enabled
expect_success traefik-dev-forward-fqdn-enabled case_traefik_dev_forward_fqdn_enabled
expect_success traefik-dev-forward-custom-prefix case_traefik_dev_forward_custom_prefix
expect_failure traefik-dev-forward-missing-live-file case_traefik_dev_forward_missing_live_file
expect_failure traefik-dev-forward-disabled-live-file case_traefik_dev_forward_disabled_live_file
expect_failure traefik-dev-forward-stale-live-file case_traefik_dev_forward_stale_live_file
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
expect_failure traefik-dev-forward-prefix-uppercase run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-prefix-uppercase" true it.saervices.de 192.168.10.100:443 '' DEV
expect_failure traefik-dev-forward-prefix-dot run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-prefix-dot" true it.saervices.de 192.168.10.100:443 '' dev.edge
expect_failure traefik-dev-forward-prefix-leading-hyphen run_traefik_forward_settings "${TEST_ROOT}/traefik-dev-forward-prefix-leading-hyphen" true it.saervices.de 192.168.10.100:443 '' -dev
expect_failure traefik-proxy-protocol-missing-mask run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-missing-mask" false example.com CHANGE_ME:443 192.168.20.100
expect_failure traefik-proxy-protocol-broad-mask run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-broad-mask" false example.com CHANGE_ME:443 192.168.20.0/24
expect_failure traefik-proxy-protocol-unspecified run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-unspecified" false example.com CHANGE_ME:443 0.0.0.0/32
expect_failure traefik-proxy-protocol-whitespace run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-whitespace" false example.com CHANGE_ME:443 '192.168.20.100/32, 192.168.20.101/32'
expect_failure traefik-proxy-protocol-malformed-ipv4 run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-malformed-ipv4" false example.com CHANGE_ME:443 999.999.999.999/32
expect_failure traefik-proxy-protocol-duplicate run_traefik_forward_settings "${TEST_ROOT}/traefik-proxy-protocol-duplicate" false example.com CHANGE_ME:443 '192.168.20.100/32,192.168.20.100/32'
expect_success traefik-forwarded-header-local-only case_traefik_forwarded_header_local_only
expect_success traefik-forwarded-header-combined case_traefik_forwarded_header_combined
expect_success traefik-forwarded-header-blank case_traefik_forwarded_header_blank
expect_failure traefik-forwarded-header-trust-all-ipv4 run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-trust-all-ipv4" 0.0.0.0/0 ''
expect_failure traefik-forwarded-header-trust-all-ipv6 run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-trust-all-ipv6" '' ::/0
expect_failure traefik-forwarded-header-malformed-ipv4 run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-malformed-ipv4" 999.999.999.999/32 ''
expect_failure traefik-forwarded-header-whitespace run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-whitespace" '127.0.0.1/32, 10.0.0.0/8' ''
expect_failure traefik-forwarded-header-duplicate run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-duplicate" 127.0.0.1/32 127.0.0.1/32
expect_failure traefik-forwarded-header-nonnumeric-prefix run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-nonnumeric-prefix" 10.0.0.0/xx ''
expect_failure traefik-forwarded-header-ipv6-prefix-overflow run_traefik_forwarded_header_settings "${TEST_ROOT}/traefik-forwarded-header-ipv6-prefix-overflow" '' 2400:cb00::/200
expect_success traefik-cloudflare-switch-fetch case_traefik_cloudflare_switch_fetch
expect_success traefik-cloudflare-switch-crlf case_traefik_cloudflare_switch_crlf
expect_success traefik-cloudflare-switch-false-skips-fetch case_traefik_cloudflare_switch_false_skips_fetch
expect_success traefik-cloudflare-switch-pinned case_traefik_cloudflare_switch_pinned
expect_failure traefik-cloudflare-switch-uppercase run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-uppercase" TRUE
expect_failure traefik-cloudflare-switch-yes run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-yes" yes
expect_failure traefik-cloudflare-switch-fetch-v6-error run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-fetch-v6-error" true "${TRAEFIK_CF_IPS_DIR}/ips-v4" "${TRAEFIK_CF_IPS_DIR}/ips-v6" '' 1
expect_failure traefik-cloudflare-switch-empty-payload run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-empty-payload" true "${TRAEFIK_CF_IPS_DIR}/ips-v4-empty" "${TRAEFIK_CF_IPS_DIR}/ips-v6"
expect_failure traefik-cloudflare-switch-garbage run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-garbage" true "${TRAEFIK_CF_IPS_DIR}/ips-v4-garbage" "${TRAEFIK_CF_IPS_DIR}/ips-v6"
expect_failure traefik-cloudflare-switch-oversized run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-oversized" true "${TRAEFIK_CF_IPS_DIR}/ips-v4-oversized" "${TRAEFIK_CF_IPS_DIR}/ips-v6"
expect_failure traefik-cloudflare-switch-too-many run_traefik_cloudflare_switch "${TEST_ROOT}/traefik-cloudflare-switch-too-many" true "${TRAEFIK_CF_IPS_DIR}/ips-v4-too-many" "${TRAEFIK_CF_IPS_DIR}/ips-v6"
expect_success traefik-canonical-redirect-valid case_traefik_canonical_redirect_valid
expect_success traefik-canonical-route-subdomain-preserved case_traefik_canonical_route_subdomain_preserved
expect_success traefik-canonical-mailcow-mta-sts-policy case_traefik_canonical_mailcow_mta_sts_policy
expect_failure traefik-canonical-redirect-missing-target run_traefik_canonical_settings "${TEST_ROOT}/traefik-canonical-redirect-missing-target" xn--lb-1ia.de '' saervices.de '' ''
expect_failure traefik-canonical-redirect-missing-source run_traefik_canonical_settings "${TEST_ROOT}/traefik-canonical-redirect-missing-source" xn--lb-1ia.de xn--srvices-mxa.de '' '' ''
expect_failure traefik-canonical-redirect-duplicate-source run_traefik_canonical_settings "${TEST_ROOT}/traefik-canonical-redirect-duplicate-source" xn--lb-1ia.de xn--srvices-mxa.de saervices.de saervices.de ''
expect_failure traefik-canonical-redirect-target-loop run_traefik_canonical_settings "${TEST_ROOT}/traefik-canonical-redirect-target-loop" internal.example xn--srvices-mxa.saervices.de saervices.de '' ''
expect_failure traefik-canonical-redirect-internal-collision run_traefik_canonical_settings "${TEST_ROOT}/traefik-canonical-redirect-internal-collision" private.saervices.de xn--srvices-mxa.de saervices.de '' ''
expect_success traefik-forward-auth-same-docker run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-same-docker" http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik
expect_success traefik-forward-auth-private-https run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-private-https" https://10.20.30.12:9443/outpost.goauthentik.io/auth/traefik
expect_success traefik-forward-auth-internal-dns-https run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-internal-dns-https" https://authentik.internal.example:9443/outpost.goauthentik.io/auth/traefik
expect_failure traefik-forward-auth-cross-lxc-http run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-cross-lxc-http" http://10.20.30.12:9000/outpost.goauthentik.io/auth/traefik
expect_failure traefik-forward-auth-public-ip run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-public-ip" https://203.0.113.12:9443/outpost.goauthentik.io/auth/traefik
expect_failure traefik-forward-auth-missing-port run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-missing-port" https://authentik.internal.example/outpost.goauthentik.io/auth/traefik
expect_failure traefik-forward-auth-wrong-path run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-wrong-path" https://authentik.internal.example:9443/outpost.goauthentik.io/ping
expect_failure traefik-forward-auth-query run_traefik_forward_auth_address "${TEST_ROOT}/traefik-forward-auth-query" 'https://authentik.internal.example:9443/outpost.goauthentik.io/auth/traefik?unsafe=1'
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
# --- GITEÆ
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_gitea() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets" "${fixture}/run"
  printf 'postgres-password' >"${fixture}/secrets/POSTGRES_PASSWORD"
  printf 'redis:@/?#%%+ password' >"${fixture}/secrets/REDIS_PASSWORD"
  printf 'gitea-secret-key-value-32bytes-min' >"${fixture}/secrets/GITEA_SECRET_KEY"
  printf 'gitea-internal-token-value-32b' >"${fixture}/secrets/GITEA_INTERNAL_TOKEN"
  printf 'gitea-lfs-jwt-secret-value-32b' >"${fixture}/secrets/GITEA_LFS_JWT_SECRET"
  printf 'gitea-oauth2-jwt-secret-32byte' >"${fixture}/secrets/GITEA_OAUTH2_JWT_SECRET"
  printf 'smtp-password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD"
  printf 'provider-client-id' >"${fixture}/secrets/GITEA_OIDC_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/GITEA_OIDC_CLIENT_SECRET"
}

run_gitea() {
  local fixture="$1"
  SECRET_DIR="${fixture}/secrets" \
    GITEA_RUNTIME_DIR="${fixture}/run" \
    GITEA_REDIS_HOST=gitea-redis \
    GITEA_REDIS_PORT=6379 \
    GITEA_SMTP_ENABLED=true \
    GITEA_OIDC_ENABLED=true \
    /bin/sh "$GITEA_SCRIPT" --preflight-only
}

run_gitea_without_smtp_secret() {
  local fixture="${TEST_ROOT}/gitea-no-smtp"
  prepare_gitea "$fixture"
  rm -f -- "${fixture}/secrets/MAILER_SMTP_PASSWORD"
  SECRET_DIR="${fixture}/secrets" \
    GITEA_RUNTIME_DIR="${fixture}/run" \
    GITEA_REDIS_HOST=gitea-redis \
    GITEA_SMTP_ENABLED=false \
    GITEA_OIDC_ENABLED=true \
    /bin/sh "$GITEA_SCRIPT" --preflight-only
}

run_gitea_without_oidc_secret() {
  local fixture="${TEST_ROOT}/gitea-no-oidc"
  prepare_gitea "$fixture"
  rm -f -- "${fixture}/secrets/GITEA_OIDC_CLIENT_ID" "${fixture}/secrets/GITEA_OIDC_CLIENT_SECRET"
  SECRET_DIR="${fixture}/secrets" \
    GITEA_RUNTIME_DIR="${fixture}/run" \
    GITEA_REDIS_HOST=gitea-redis \
    GITEA_SMTP_ENABLED=false \
    GITEA_OIDC_ENABLED=false \
    /bin/sh "$GITEA_SCRIPT" --preflight-only
}

case_gitea_redis_url_encoding() {
  local fixture="${TEST_ROOT}/gitea-redis-url"
  prepare_gitea "$fixture"
  printf 'p@ss=word/#' >"${fixture}/secrets/REDIS_PASSWORD"
  SECRET_DIR="${fixture}/secrets" \
    GITEA_RUNTIME_DIR="${fixture}/run" \
    GITEA_REDIS_HOST=gitea-redis \
    GITEA_REDIS_PORT=6379 \
    GITEA_SMTP_ENABLED=false \
    GITEA_OIDC_ENABLED=true \
    /bin/sh "$GITEA_SCRIPT" --preflight-only
  [[ "$(cat "${fixture}/run/redis.url")" == 'redis://:p%40ss%3Dword%2F%23@gitea-redis:6379/0' ]]
}

case_gitea_preflight_does_not_exec_vendor() {
  local fixture="${TEST_ROOT}/gitea-no-vendor"
  prepare_gitea "$fixture"
  printf '%s\n' '#!/bin/sh' 'printf ran >"$GITEA_VENDOR_MARKER"' 'exit 0' \
    >"${fixture}/vendor.sh"
  chmod 0700 "${fixture}/vendor.sh"
  SECRET_DIR="${fixture}/secrets" \
    GITEA_RUNTIME_DIR="${fixture}/run" \
    GITEA_REDIS_HOST=gitea-redis \
    GITEA_SMTP_ENABLED=false \
    GITEA_OIDC_ENABLED=true \
    GITEA_VENDOR_ENTRYPOINT="${fixture}/vendor.sh" \
    GITEA_VENDOR_MARKER="${fixture}/vendor.ran" \
    /bin/sh "$GITEA_SCRIPT" --preflight-only
  [[ ! -e "${fixture}/vendor.ran" ]]
}

case_gitea_symlink_secret() {
  local fixture="${TEST_ROOT}/gitea-symlink"
  prepare_gitea "$fixture"
  rm -f -- "${fixture}/secrets/GITEA_SECRET_KEY"
  ln -s /etc/hostname "${fixture}/secrets/GITEA_SECRET_KEY"
  run_gitea "$fixture"
}

case_gitea_oversized_secret() {
  local fixture="${TEST_ROOT}/gitea-oversized"
  prepare_gitea "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/GITEA_SECRET_KEY"
  run_gitea "$fixture"
}

run_gitea_register_oidc() {
  local fixture="$1"
  SECRET_DIR="${fixture}/secrets" \
    AUTHENTIK_DOMAIN=authentik.example.test \
    APP_DOMAIN=gitea.example.test \
    GITEA_OIDC_NAME=authentik \
    GITEA_OIDC_SLUG=gitea \
    /bin/sh "$GITEA_OIDC_SCRIPT" --preflight-only
}

case_gitea_register_oidc_bad_domain() {
  local fixture="${TEST_ROOT}/gitea-oidc-bad-domain"
  prepare_gitea "$fixture"
  SECRET_DIR="${fixture}/secrets" \
    AUTHENTIK_DOMAIN='https://authentik.example.test' \
    APP_DOMAIN=gitea.example.test \
    /bin/sh "$GITEA_OIDC_SCRIPT" --preflight-only
}

prepare_gitea "${TEST_ROOT}/gitea-valid"
expect_success gitea-valid run_gitea "${TEST_ROOT}/gitea-valid"
expect_success gitea-disabled-smtp-does-not-require-secret run_gitea_without_smtp_secret
expect_success gitea-disabled-oidc-does-not-require-secret run_gitea_without_oidc_secret
expect_success gitea-redis-url-encoding case_gitea_redis_url_encoding
expect_success gitea-preflight-does-not-exec-vendor case_gitea_preflight_does_not_exec_vendor
expect_success gitea-register-oidc-preflight run_gitea_register_oidc "${TEST_ROOT}/gitea-valid"
expect_failure gitea-register-oidc-bad-domain case_gitea_register_oidc_bad_domain
expect_failure gitea-symlink-secret case_gitea_symlink_secret
expect_failure gitea-oversized-secret case_gitea_oversized_secret
exercise_secret_matrix gitea-postgres prepare_gitea run_gitea POSTGRES_PASSWORD
exercise_secret_matrix gitea-redis prepare_gitea run_gitea REDIS_PASSWORD
exercise_secret_matrix gitea-secret-key prepare_gitea run_gitea GITEA_SECRET_KEY
exercise_secret_matrix gitea-internal-token prepare_gitea run_gitea GITEA_INTERNAL_TOKEN
exercise_secret_matrix gitea-lfs-jwt prepare_gitea run_gitea GITEA_LFS_JWT_SECRET
exercise_secret_matrix gitea-oauth2-jwt prepare_gitea run_gitea GITEA_OAUTH2_JWT_SECRET
exercise_secret_matrix gitea-smtp prepare_gitea run_gitea MAILER_SMTP_PASSWORD
exercise_secret_matrix gitea-oidc-id prepare_gitea run_gitea GITEA_OIDC_CLIENT_ID
exercise_secret_matrix gitea-oidc-secret prepare_gitea run_gitea GITEA_OIDC_CLIENT_SECRET

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
from collections import Counter
import contextlib
import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import tempfile
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
    (
        root / "Gitea/docker-compose.app.yaml",
        "MAILER_SMTP_PASSWORD",
        "GITEA_SMTP_ENABLED",
        "${GITEA_SMTP_ENABLED:-false}",
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
    if "TZ" in (service.get("environment") or {}):
        raise SystemExit(f"{path}: Authentik processes must keep the vendor UTC timezone")

generation_lengths = authentik_document.get("x-secret-generation-lengths") or {}
if generation_lengths.get("POSTGRES_PASSWORD") != 99:
    raise SystemExit(
        f"{authentik_path}: POSTGRES_PASSWORD generation length must stay at Authentik's documented 99-char maximum"
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
    if (service.get("healthcheck") or {}).get("start_period") != "60s":
        raise SystemExit(f"{path}: Authentik daemon healthcheck must keep the vendor 60s start period")
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
lxc_proxy_cidrs = "127.0.0.0/8,10.20.30.11/32,::1/128"
if server_wrapper.parse_trusted_proxy_cidrs(lxc_proxy_cidrs) != tuple(lxc_proxy_cidrs.split(",")):
    raise SystemExit(f"{server_wrapper_path}: valid exact LXC proxy source was rejected")
ula_proxy_cidrs = "127.0.0.0/8,::1/128,fd42:4d3:2a1::/64"
if server_wrapper.parse_trusted_proxy_cidrs(ula_proxy_cidrs) != tuple(ula_proxy_cidrs.split(",")):
    raise SystemExit(f"{server_wrapper_path}: valid IPv6 ULA proxy network was rejected")
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
    "127.0.0.0/8,10.20.0.0/15,::1/128",
    "127.0.0.0/8,172.20.0.0/15,::1/128",
    "127.0.0.0/8,172.30.1.1/16",
    "127.0.0.0/8,172.30.0.0/16,172.30.1.0/24",
    "127.0.0.0/8,8.8.8.8/32,::1/128",
    "127.0.0.0/8,2606:4700:4700::1111/128,::1/128",
    "127.0.0.0/8,100.64.0.1/32,::1/128",
    "127.0.0.0/8,192.0.2.0/24,::1/128",
    "127.0.0.0/8,198.18.0.0/16,::1/128",
    "127.0.0.0/8,198.51.100.0/24,::1/128",
    "127.0.0.0/8,203.0.113.0/24,::1/128",
    "127.0.0.0/8,2001:db8::/64,::1/128",
    "127.0.0.0/8,fd42:4d3::/48,::1/128",
    "127.0.0.0/8,fc00::/7,::1/128",
    "127.0.0.0/8,0.0.0.0/0,::1/128",
    "127.0.0.0/8,::/0,::1/128",
    "127.0.0.0/8,224.0.0.0/4,::1/128",
    "127.0.0.0/8,ff00::/8,::1/128",
    "127.0.0.0/8,169.254.0.0/16,::1/128",
    "127.0.0.0/8,fe80::/64,::1/128",
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
traefik_service = traefik_document["services"]["app"]
traefik_command = traefik_service.get("command") or []
if "--providers.docker.network=frontend" not in traefik_command:
    raise SystemExit(f"{traefik_path}: Docker-provider routing must stay pinned to frontend")
for required_tls_argument in (
    "--entrypoints.websecure.http.tls=true",
    "--entrypoints.websecure.http.tls.certresolver=${CERTRESOLVER}",
    "--entrypoints.websecure.http.tls.options=${TLSOPTIONS}",
):
    if required_tls_argument not in traefik_command:
        raise SystemExit(
            f"{traefik_path}: app routers require the websecure TLS default "
            f"{required_tls_argument!r}"
        )
traefik_labels = set(traefik_service.get("labels") or [])
for required_dashboard_label in (
    "traefik.http.routers.${APP_NAME}-rtr.tls=true",
    "traefik.http.routers.${APP_NAME}-rtr.tls.certresolver=${CERTRESOLVER}",
    "traefik.http.routers.${APP_NAME}-rtr.tls.options=${TLSOPTIONS}",
):
    if required_dashboard_label not in traefik_labels:
        raise SystemExit(
            f"{traefik_path}: dashboard router must keep {required_dashboard_label!r}"
        )
for entrypoint in ("web", "websecure"):
    required_underscore_strategy = (
        f"--entrypoints.{entrypoint}.http.underscoreheadersstrategy=delete"
    )
    if required_underscore_strategy not in traefik_command:
        raise SystemExit(
            f"{traefik_path}: public EntryPoint {entrypoint} must delete underscore request headers"
        )
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
if traefik_environment.get("TRAEFIK_ROUTE_SUBDOMAIN") != "${TRAEFIK_ROUTE_SUBDOMAIN:-}":
    raise SystemExit(
        f"{traefik_path}: optional TRAEFIK_ROUTE_SUBDOMAIN must default to blank"
    )
if traefik_environment.get("TRAEFIK_BASE_WILDCARD_CERT_ENABLED") != "${TRAEFIK_BASE_WILDCARD_CERT_ENABLED:-false}":
    raise SystemExit(
        f"{traefik_path}: raw-base wildcard certificate opt-in must default to false"
    )
expected_dev_forward_environment = {
    "TRAEFIK_DEV_FORWARD_ENABLED": "${TRAEFIK_DEV_FORWARD_ENABLED:-false}",
    "TRAEFIK_DEV_FORWARD_PREFIX": "${TRAEFIK_DEV_FORWARD_PREFIX:-dev}",
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
    "TRAEFIK_ROUTE_SUBDOMAIN": "",
    "TRAEFIK_BASE_WILDCARD_CERT_ENABLED": "false",
    "TRAEFIK_DEV_FORWARD_ENABLED": "false",
    "TRAEFIK_DEV_FORWARD_PREFIX": "dev",
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
dev_forward_path = root / "Traefik/appdata/config/conf.d/dev-traefik-forward.yaml.template"
dev_forward_text = dev_forward_path.read_text(encoding="utf-8")
for required_fragment in (
    '{{ if eq (env "TRAEFIK_DEV_FORWARD_ENABLED") "true" }}',
    'HostSNI(`{{ env "TRAEFIK_DEV_FORWARD_PREFIX" }}.{{ env "TRAEFIK_DOMAIN" }}`)',
    'HostSNIRegexp(`^[^.]+\\.{{ regexQuoteMeta (env "TRAEFIK_DEV_FORWARD_PREFIX") }}\\.{{ regexQuoteMeta (env "TRAEFIK_DOMAIN") }}$`)',
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
dev_forward_live_path = root / "Traefik/appdata/config/conf.d/dev-traefik-forward.yaml"
if dev_forward_live_path.exists() or dev_forward_live_path.is_symlink():
    raise SystemExit(f"{dev_forward_live_path}: DEV forwarding must ship inert by default")
gitignore_text = (root / ".gitignore").read_text(encoding="utf-8")
if "/Traefik/appdata/config/conf.d/dev-traefik-forward.yaml" not in gitignore_text:
    raise SystemExit(f"{root / '.gitignore'}: generated DEV forwarding activation must stay ignored")

canonical_path = root / "Traefik/appdata/config/conf.d/canonical-domain-redirect.yaml"
canonical_text = canonical_path.read_text(encoding="utf-8")
for required_fragment in (
    '{{ with env "TRAEFIK_DOMAIN_2" }}',
    '{{ with env "TRAEFIK_DOMAIN_3" }}',
    '{{ with env "TRAEFIK_DOMAIN_4" }}',
    'HostRegexp(`^.+\\.{{ regexQuoteMeta $domain }}$`)',
    'regex: \'^https://((?:[A-Za-z0-9-]+\\.)*)({{ $canonicalRedirectRegexDomains | join "|" }})(:[0-9]+)?(/.*)?$\'',
    'replacement: \'https://${1}{{ env "TRAEFIK_DOMAIN_1" }}${3}${4}\'',
    "canonical-domain-redirect:",
):
    if required_fragment not in canonical_text:
        raise SystemExit(
            f"{canonical_path}: missing required canonical redirect fragment {required_fragment!r}"
        )
route_template_directory = root / "Traefik/appdata/config/conf.d"
route_template_reference = route_template_directory / "template.yaml.template"
reference_url_lines = [
    line
    for line in route_template_reference.read_text(encoding="utf-8").splitlines()
    if re.match(r"^\s*-\s+url:\s+", line)
]
if len(reference_url_lines) != 1 or "#" not in reference_url_lines[0]:
    raise SystemExit(
        f"{route_template_reference}: canonical route template must have exactly one commented server URL"
    )
expected_url_comment = reference_url_lines[0].rpartition("#")[2].strip()
fixed_target_url_comments = {
    "rustdesk.yaml.template": "Docker DNS on rustdesk-proxy; never publish this trusted listener",
    "rustdesk-pro.yaml.template": "Docker DNS on rustdesk-proxy; host exposure remæins loopbæck-only",
}
for route_template_path in sorted(route_template_directory.glob("*.yaml.template")):
    expected_route_url_comment = fixed_target_url_comments.get(
        route_template_path.name, expected_url_comment
    )
    for line_number, line in enumerate(
        route_template_path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        if not re.match(r"^\s*-\s+url:\s+", line):
            continue
        actual_url_comment = line.rpartition("#")[2].strip() if "#" in line else ""
        if actual_url_comment != expected_route_url_comment:
            raise SystemExit(
                f"{route_template_path}:{line_number}: server URL comment must match "
                f"the canonical or fixed-target text: {expected_route_url_comment!r}"
            )

excluded_route_templates = {
    "dev-traefik-forward.yaml.template",
    "mailcow.yaml.template",
}
app_route_templates = [
    path
    for path in sorted(route_template_directory.glob("*.yaml.template"))
    if path.name not in excluded_route_templates
]
expected_route_domains = {
    "TRAEFIK_ROUTE_DOMAIN",
    "TRAEFIK_ROUTE_DOMAIN_1",
    "TRAEFIK_ROUTE_DOMAIN_2",
    "TRAEFIK_ROUTE_DOMAIN_3",
    "TRAEFIK_ROUTE_DOMAIN_4",
}
route_host_pattern = re.compile(
    r'^(?P<application>[a-z0-9-]+)\.\{\{\s*env "'
    r'(?P<domain>TRAEFIK_ROUTE_DOMAIN(?:_[1-4])?)"\s*\}\}$'
)
route_application_names = set()
for route_template_path in app_route_templates:
    route_template_text = route_template_path.read_text(encoding="utf-8")
    if "TRAEFIK_ROUTE_SUBDOMAIN" in route_template_text:
        raise SystemExit(
            f"{route_template_path}: route subdomain must be derived once by the startup wrapper"
        )
    legacy_domain_references = re.findall(
        r'env "TRAEFIK_DOMAIN(?:_[1-4])?"',
        route_template_text,
    )
    if legacy_domain_references:
        raise SystemExit(
            f"{route_template_path}: app routes must use only derived route domains"
        )
    route_domain_references = set(
        re.findall(
            r'(?<=env ")TRAEFIK_ROUTE_DOMAIN(?:_[1-4])?(?=")',
            route_template_text,
        )
    )
    if route_domain_references != expected_route_domains:
        raise SystemExit(
            f"{route_template_path}: incomplete route-domain matrix "
            f"{sorted(route_domain_references)!r}"
        )
    application_names = set()
    host_rules = re.findall(r'Host\(`([^`]+)`\)', route_template_text)
    if not host_rules:
        raise SystemExit(f"{route_template_path}: missing exact per-app Host rules")
    for host_rule in host_rules:
        host_match = route_host_pattern.fullmatch(host_rule)
        if host_match is None:
            raise SystemExit(
                f"{route_template_path}: non-exact per-app Host rule {host_rule!r}"
            )
        application_names.add(host_match.group("application"))
    if len(application_names) != 1:
        raise SystemExit(
            f"{route_template_path}: one app template must use one hostname prefix"
        )
    application_name = next(iter(application_names))
    route_application_names.add(application_name)
    route_lines = route_template_text.splitlines()
    router_host_sets = []
    for route_line_index, route_line in enumerate(route_lines):
        if re.match(r"^\s+rule:\s+>-", route_line) is None:
            continue
        rule_indent = len(route_line) - len(route_line.lstrip())
        rule_body = []
        for rule_body_line in route_lines[route_line_index + 1:]:
            if rule_body_line.strip():
                body_indent = len(rule_body_line) - len(rule_body_line.lstrip())
                if body_indent <= rule_indent:
                    break
            rule_body.append(rule_body_line)
        rule_hosts = re.findall(r'Host\(`([^`]+)`\)', "\n".join(rule_body))
        if rule_hosts:
            router_host_sets.append(set(rule_hosts))
    expected_router_host_set = {
        f'{application_name}.{{{{env "{route_domain}"}}}}'
        for route_domain in expected_route_domains
    }
    if not router_host_sets or any(
        router_host_set != expected_router_host_set
        for router_host_set in router_host_sets
    ):
        raise SystemExit(
            f"{route_template_path}: every app router must repeat the complete exact host set"
        )
    for optional_route_domain in sorted(expected_route_domains - {"TRAEFIK_ROUTE_DOMAIN"}):
        optional_guard = re.compile(
            rf'\{{\{{-?\s*if\s+env\s+"{optional_route_domain}"\s*\}}\}}'
        )
        if optional_guard.search(route_template_text) is None:
            raise SystemExit(
                f"{route_template_path}: {optional_route_domain} must stay optional"
            )

traefik_start_path = root / "Traefik/scripts/traefik-start.sh"
traefik_start_text = traefik_start_path.read_text(encoding="utf-8")
route_prefixes_match = re.search(
    r"^readonly TRAEFIK_ROUTE_APPLICATION_PREFIXES='([^']+)'$",
    traefik_start_text,
    flags=re.MULTILINE,
)
if route_prefixes_match is None:
    raise SystemExit(f"{traefik_start_path}: missing route application prefix inventory")
wrapper_route_prefixes = route_prefixes_match.group(1).split()
if (
    len(wrapper_route_prefixes) != len(set(wrapper_route_prefixes))
    or set(wrapper_route_prefixes) != route_application_names
):
    raise SystemExit(
        f"{traefik_start_path}: route prefix inventory must match all normal app templates"
    )

mailcow_route_path = route_template_directory / "mailcow.yaml.template"
mailcow_route_text = mailcow_route_path.read_text(encoding="utf-8")
legacy_mailcow_domains = set(
    re.findall(
        r'(?<=env ")TRAEFIK_DOMAIN(?:_[1-4])?(?=")',
        mailcow_route_text,
    )
)
if legacy_mailcow_domains:
    raise SystemExit(
        f"{mailcow_route_path}: Mailcow routes must use only wrapper-derived route domains"
    )
mailcow_route_domains = set(
    re.findall(
        r'(?<=env ")TRAEFIK_ROUTE_DOMAIN(?:_[1-4])?(?=")',
        mailcow_route_text,
    )
)
if mailcow_route_domains != expected_route_domains:
    raise SystemExit(
        f"{mailcow_route_path}: Mailcow must consume the complete derived domain matrix"
    )
if "HostRegexp(" in mailcow_route_text:
    raise SystemExit(f"{mailcow_route_path}: Mailcow aliases must remain exact Host rules")

def mailcow_host(label, route_domain):
    return f'{label}.{{{{env "{route_domain}"}}}}'

expected_mailcow_host_patterns = [
    mailcow_host(label, "TRAEFIK_ROUTE_DOMAIN")
    for label in ("mailcow", "mail", "mta-sts", "autodiscover", "autoconfig")
]
for optional_route_domain in (
    "TRAEFIK_ROUTE_DOMAIN_1",
    "TRAEFIK_ROUTE_DOMAIN_2",
    "TRAEFIK_ROUTE_DOMAIN_3",
    "TRAEFIK_ROUTE_DOMAIN_4",
):
    expected_mailcow_host_patterns.extend(
        mailcow_host(label, optional_route_domain)
        for label in ("mail", "mta-sts", "autodiscover", "autoconfig")
    )
    optional_guard = re.compile(
        rf'\{{\{{-?\s*if\s+env\s+"{optional_route_domain}"\s*\}}\}}'
    )
    if optional_guard.search(mailcow_route_text) is None:
        raise SystemExit(
            f"{mailcow_route_path}: {optional_route_domain} aliases must stay optional"
        )
mailcow_host_patterns = re.findall(r'Host\(`([^`]+)`\)', mailcow_route_text)
if Counter(mailcow_host_patterns) != Counter(expected_mailcow_host_patterns):
    raise SystemExit(
        f"{mailcow_route_path}: Mailcow must preserve its exact primary/optional alias matrix"
    )
primary_acme_host = mailcow_host("mail", "TRAEFIK_ROUTE_DOMAIN")
primary_acme_fragment = (
    f"(Host(`{primary_acme_host}`) && "
    "PathPrefix(`/.well-known/acme-challenge/`))"
)
if primary_acme_fragment not in mailcow_route_text:
    raise SystemExit(
        f"{mailcow_route_path}: the primary mail alias must stay ACME-path-only"
    )

raw_mailcow_domains = {
    "TRAEFIK_ROUTE_DOMAIN": "xn--lb-1ia.de",
    "TRAEFIK_ROUTE_DOMAIN_1": "xn--srvices-mxa.de",
    "TRAEFIK_ROUTE_DOMAIN_2": "saervices.de",
    "TRAEFIK_ROUTE_DOMAIN_3": "it-saervices.de",
    "TRAEFIK_ROUTE_DOMAIN_4": "itsaervices.de",
}

def render_mailcow_hosts(route_subdomain):
    route_prefix = f"{route_subdomain}." if route_subdomain else ""
    rendered_domains = {
        name: f"{route_prefix}{domain}"
        for name, domain in raw_mailcow_domains.items()
    }
    rendered_hosts = set()
    for host_pattern in mailcow_host_patterns:
        host_match = route_host_pattern.fullmatch(host_pattern)
        if host_match is None:
            raise SystemExit(
                f"{mailcow_route_path}: invalid exact host pattern {host_pattern!r}"
            )
        rendered_hosts.add(
            f"{host_match.group('application')}."
            f"{rendered_domains[host_match.group('domain')]}"
        )
    return rendered_hosts

expected_mailcow_hosts_without_prefix = {
    f"{label}.xn--lb-1ia.de"
    for label in ("mailcow", "mail", "mta-sts", "autodiscover", "autoconfig")
}
for optional_domain in (
    "xn--srvices-mxa.de",
    "saervices.de",
    "it-saervices.de",
    "itsaervices.de",
):
    expected_mailcow_hosts_without_prefix.update(
        f"{label}.{optional_domain}"
        for label in ("mail", "mta-sts", "autodiscover", "autoconfig")
    )
rendered_mailcow_hosts_without_prefix = render_mailcow_hosts("")
if rendered_mailcow_hosts_without_prefix != expected_mailcow_hosts_without_prefix:
    raise SystemExit(
        f"{mailcow_route_path}: blank route subdomain must preserve every previous Mailcow host"
    )
rendered_mailcow_hosts_with_prefix = render_mailcow_hosts("it")
expected_mailcow_hosts_with_prefix = {
    f"{label}.it.{host_suffix}"
    for host in expected_mailcow_hosts_without_prefix
    for label, host_suffix in [host.split(".", maxsplit=1)]
}
if rendered_mailcow_hosts_with_prefix != expected_mailcow_hosts_with_prefix:
    raise SystemExit(
        f"{mailcow_route_path}: route subdomain must be inserted after every Mailcow label"
    )
if rendered_mailcow_hosts_with_prefix & expected_mailcow_hosts_without_prefix:
    raise SystemExit(
        f"{mailcow_route_path}: prefixed mode still routes legacy unprefixed hosts instead of 404"
    )

mailcow_prefixes_match = re.search(
    r"^readonly TRAEFIK_ROUTE_MAILCOW_PREFIXES='([^']+)'$",
    traefik_start_text,
    flags=re.MULTILINE,
)
expected_mailcow_prefixes = {"autoconfig", "autodiscover", "mail", "mailcow", "mta-sts"}
if mailcow_prefixes_match is None:
    raise SystemExit(f"{traefik_start_path}: missing separate Mailcow prefix inventory")
wrapper_mailcow_prefixes = mailcow_prefixes_match.group(1).split()
if (
    len(wrapper_mailcow_prefixes) != len(set(wrapper_mailcow_prefixes))
    or set(wrapper_mailcow_prefixes) != expected_mailcow_prefixes
):
    raise SystemExit(
        f"{traefik_start_path}: Mailcow prefix inventory must match every fixed alias"
    )
if "TRAEFIK_ROUTE_" in dev_forward_text:
    raise SystemExit(f"{dev_forward_path}: DEV forwarding must stay independent of app routes")

apex_cert_path = route_template_directory / "traefik-apex-cert.yaml"
apex_cert_text = apex_cert_path.read_text(encoding="utf-8")
if "TRAEFIK_ROUTE_" in apex_cert_text or "*." in apex_cert_text:
    raise SystemExit(
        f"{apex_cert_path}: apex certificate router must stay exact and route-independent"
    )
wildcard_cert_path = route_template_directory / "traefik-wildcard-cert.yaml"
wildcard_cert_text = wildcard_cert_path.read_text(encoding="utf-8")
wildcard_condition = '{{ if eq (env "TRAEFIK_BASE_WILDCARD_CERT_ENABLED") "true" }}'
if wildcard_cert_text.count(wildcard_condition) != 1:
    raise SystemExit(
        f"{wildcard_cert_path}: raw-base wildcard router must use one exact opt-in condition"
    )
if "TRAEFIK_ROUTE_" in wildcard_cert_text:
    raise SystemExit(
        f"{wildcard_cert_path}: route-derived or deeper wildcards are forbidden"
    )
expected_raw_wildcard_domains = Counter(
    [f"TRAEFIK_DOMAIN{suffix}" for suffix in ("", "_1", "_2", "_3", "_4")]
)
actual_raw_wildcard_domains = Counter(
    re.findall(
        r'"\*\.\{\{env "(TRAEFIK_DOMAIN(?:_[1-4])?)"\}\}"',
        wildcard_cert_text,
    )
)
if actual_raw_wildcard_domains != expected_raw_wildcard_domains:
    raise SystemExit(
        f"{wildcard_cert_path}: only one wildcard per raw TRAEFIK_DOMAIN[_1..4] is allowed"
    )
for optional_domain in ("TRAEFIK_DOMAIN_1", "TRAEFIK_DOMAIN_2", "TRAEFIK_DOMAIN_3", "TRAEFIK_DOMAIN_4"):
    if f'{{{{ if env "{optional_domain}" }}}}' not in wildcard_cert_text:
        raise SystemExit(f"{wildcard_cert_path}: {optional_domain} wildcard must stay optional")
for dynamic_config_path in route_template_directory.glob("*.yaml*"):
    if dynamic_config_path == wildcard_cert_path:
        continue
    dynamic_config_text = dynamic_config_path.read_text(encoding="utf-8")
    if re.search(r'^[ \t]*(?:main:|-)[ \t]+["\']\*\.', dynamic_config_text, flags=re.MULTILINE):
        raise SystemExit(
            f"{dynamic_config_path}: origin wildcard certificates belong only in {wildcard_cert_path.name}"
        )

def render_wildcard_template(environment):
    rendered = wildcard_cert_text
    conditional_pattern = re.compile(
        r'\{\{ if (?P<expression>eq \(env "[A-Z0-9_]+"\) "[^"]*"|env "[A-Z0-9_]+") \}\}'
        r'(?P<body>(?:(?!\{\{ if |\{\{ end \}\}).)*)\{\{ end \}\}',
        flags=re.DOTALL,
    )
    while conditional_pattern.search(rendered):
        def replace_condition(match):
            expression = match.group("expression")
            equal_match = re.fullmatch(
                r'eq \(env "(?P<name>[A-Z0-9_]+)"\) "(?P<value>[^"]*)"',
                expression,
            )
            if equal_match:
                enabled = environment.get(equal_match.group("name"), "") == equal_match.group("value")
            else:
                name_match = re.fullmatch(r'env "(?P<name>[A-Z0-9_]+)"', expression)
                if name_match is None:
                    raise SystemExit(f"{wildcard_cert_path}: unsupported conditional expression")
                enabled = bool(environment.get(name_match.group("name"), ""))
            return match.group("body") if enabled else ""
        rendered = conditional_pattern.sub(replace_condition, rendered)
    if "{{ if " in rendered or "{{ end }}" in rendered:
        raise SystemExit(f"{wildcard_cert_path}: wildcard fixture left an unrendered condition")
    return re.sub(
        r'\{\{env "(?P<name>[A-Z0-9_]+)"\}\}',
        lambda match: environment.get(match.group("name"), ""),
        rendered,
    )

wildcard_render_environment = {
    "TRAEFIK_BASE_WILDCARD_CERT_ENABLED": "false",
    "TRAEFIK_DOMAIN": "xn--lb-1ia.de",
    "TRAEFIK_DOMAIN_1": "xn--srvices-mxa.de",
    "TRAEFIK_DOMAIN_2": "saervices.de",
    "TRAEFIK_DOMAIN_3": "it-saervices.de",
    "TRAEFIK_DOMAIN_4": "itsaervices.de",
    "TRAEFIK_ROUTE_DOMAIN": "it.xn--lb-1ia.de",
    "CERTRESOLVER": "cloudflare",
    "TLSOPTIONS": "tls-options@file",
}
disabled_wildcard_render = render_wildcard_template(wildcard_render_environment)
if re.search(r"^http:\s*$", disabled_wildcard_render, flags=re.MULTILINE):
    raise SystemExit(f"{wildcard_cert_path}: false opt-in must render no wildcard router")
enabled_wildcard_render = render_wildcard_template(
    {**wildcard_render_environment, "TRAEFIK_BASE_WILDCARD_CERT_ENABLED": "true"}
)
if enabled_wildcard_render.count("traefik-base-wildcard-cert-rtr:") != 1:
    raise SystemExit(f"{wildcard_cert_path}: true opt-in must render exactly one wildcard router")
rendered_wildcards = Counter(re.findall(r'["\'](\*\.[^"\']+)["\']', enabled_wildcard_render))
expected_rendered_wildcards = Counter(
    {
        "*.xn--lb-1ia.de": 1,
        "*.xn--srvices-mxa.de": 1,
        "*.saervices.de": 1,
        "*.it-saervices.de": 1,
        "*.itsaervices.de": 1,
    }
)
if rendered_wildcards != expected_rendered_wildcards or "*.it." in enabled_wildcard_render:
    raise SystemExit(
        f"{wildcard_cert_path}: enabled render must contain raw-base wildcards, never route wildcards"
    )
middlewares_path = root / "Traefik/appdata/config/conf.d/middlewares.yaml"
middlewares_text = middlewares_path.read_text(encoding="utf-8")
for forbidden_fragment in (
    "canonical-domain-redirect:",
    "global-cors:",
    "websocket-security-headers:",
    'X-Forwarded-Proto: "https"',
    "X-Download-Options:",
    "permissionsPolicy:",
    "interest-cohort=()",
    "vr=()",
):
    if forbidden_fragment in middlewares_text:
        raise SystemExit(
            f"{middlewares_path}: obsolete or relocated middleware fragment remains {forbidden_fragment!r}"
        )
for required_fragment in (
    'X-Powered-By: ""',
    'X-Permitted-Cross-Domain-Policies: "none"',
    'customBrowserXSSValue: "0"',
):
    if required_fragment not in middlewares_text:
        raise SystemExit(
            f"{middlewares_path}: missing hardened middleware fragment {required_fragment!r}"
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
if set(certs_document.get("secrets") or {}) != {"TRAEFIK_CERTS_DUMPER_PASSWORD"}:
    raise SystemExit(f"{certs_path}: certs-dumper must declare only its existing SSH-key secret")
expected_certs_secrets = {"TRAEFIK_CERTS_DUMPER_PASSWORD", "CF_DNS_API_TOKEN"}
if set(certs_service.get("secrets") or []) != expected_certs_secrets:
    raise SystemExit(f"{certs_path}: integrated post-hook must mount SSH key plus existing Cloudflare token")
certs_volumes = set(certs_service.get("volumes") or [])
if "./scripts/post-hook.sh:/config/post-hook.sh:ro" not in certs_volumes:
    raise SystemExit(f"{certs_path}: existing certs-dumper post-hook mount is missing")
if "./appdata/certs-dumper-state:/state:rw" not in certs_volumes:
    raise SystemExit(f"{certs_path}: persistent SSH host-key state bind is missing")
certs_env_path = certs_path.parent / ".env"
certs_env_text = certs_env_path.read_text(encoding="utf-8")
certs_directories_match = re.search(
    r"^TRAEFIK_CERTS_DUMPER_DIRECTORIES=([^#\n]+)",
    certs_env_text,
    flags=re.MULTILINE,
)
certs_directories = (
    certs_directories_match.group(1).strip() if certs_directories_match else ""
)
if certs_directories != "appdata/certs-dumper-state":
    raise SystemExit(
        f"{certs_env_path}: run.sh must create only the dedicated certs-dumper state directory"
    )
certs_environment = certs_service.get("environment") or {}
if certs_service.get("stop_grace_period") != "180s":
    raise SystemExit(
        f"{certs_path}: certs-dumper needs 180s for bounded Mailcow rollback before SIGKILL"
    )
if certs_environment.get("CF_DNS_API_TOKEN_FILE") != "/run/secrets/CF_DNS_API_TOKEN":
    raise SystemExit(f"{certs_path}: certs-dumper must reuse the existing Cloudflare token secret")
expected_mailcow_environment = {
    "TRAEFIK_DOMAIN": "${TRAEFIK_DOMAIN:?Traefik domæin required}",
    "TRAEFIK_DOMAIN_1": "${TRAEFIK_DOMAIN_1:-}",
    "TRAEFIK_DOMAIN_2": "${TRAEFIK_DOMAIN_2:-}",
    "TRAEFIK_DOMAIN_3": "${TRAEFIK_DOMAIN_3:-}",
    "TRAEFIK_DOMAIN_4": "${TRAEFIK_DOMAIN_4:-}",
    "TRAEFIK_ROUTE_SUBDOMAIN": "${TRAEFIK_ROUTE_SUBDOMAIN:-}",
    "MAILCOW_SMTP_HOSTNAME": "${TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME:-CHANGE_ME}",
    "MAILCOW_CLOUDFLARE_ZONE": "${TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE:-CHANGE_ME}",
    "MAILCOW_DANE_TTL_SECONDS": "${TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_TTL_SECONDS:-300}",
    "MAILCOW_DANE_TTL_SAFETY_SECONDS": "${TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_TTL_SAFETY_SECONDS:-60}",
    "MAILCOW_DANE_VALIDATING_RESOLVER": "${TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_VALIDATING_RESOLVER:-1.1.1.1}",
}
for environment_name, expected_value in expected_mailcow_environment.items():
    if certs_environment.get(environment_name) != expected_value:
        raise SystemExit(
            f"{certs_path}: invalid Mailcow environment wiring for {environment_name}"
        )
if re.search(r"(?:SSH_)?KNOWN_HOSTS", certs_text, flags=re.IGNORECASE):
    raise SystemExit(
        f"{certs_path}: known_hosts content must stay file-backed, not become a Compose secret or environment value"
    )

exporter_spellings = (
    "TRAEFIK_CERTS_" + "EXPORTER",
    "traefik-certs-" + "exporter",
    "traefik_certs-" + "exporter",
    "traefik_certs_" + "exporter",
)
for production_directory in (root / "Traefik", certs_path.parent):
    for production_file in production_directory.rglob("*"):
        if not production_file.is_file():
            continue
        if (
            production_file.name != ".env"
            and production_file.suffix.lower()
            not in {".md", ".sh", ".template", ".yaml", ".yml"}
            and not production_file.name.lower().startswith("dockerfile")
        ):
            continue
        production_text = production_file.read_text(encoding="utf-8", errors="ignore")
        if any(spelling in production_text for spelling in exporter_spellings):
            raise SystemExit(
                f"{production_file}: separate certs-exporter references are forbidden"
            )

certs_entrypoint_path = root / "templates/traefik_certs-dumper/dockerfiles/entrypoint.traefik_certs-dumper.sh"
certs_entrypoint = certs_entrypoint_path.read_text(encoding="utf-8")
if '--post-hook "sh /config/post-hook.sh"' not in certs_entrypoint:
    raise SystemExit(f"{certs_entrypoint_path}: existing post-hook must be enabled on the dumper watcher")

certs_hook_path = root / "templates/traefik_certs-dumper/scripts/post-hook.sh"
certs_hook = certs_hook_path.read_text(encoding="utf-8")
for required_fragment in (
    'CERTS_DUMPER_SSH_SECRET="/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD"',
    'CERTS_DUMPER_SSH_STATE_ROOT="/state"',
    'CERTS_DUMPER_SSH_STATE_DIR="${CERTS_DUMPER_SSH_STATE_ROOT}/.ssh"',
    'CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE="${CERTS_DUMPER_SSH_STATE_DIR}/known_hosts"',
    'CERTS_DUMPER_CF_TOKEN_FILE="${CF_DNS_API_TOKEN_FILE:-/run/secrets/CF_DNS_API_TOKEN}"',
    'MAILCOW_SMTP_HOSTNAME_INPUT="${MAILCOW_SMTP_HOSTNAME:-}"',
    'MAILCOW_CLOUDFLARE_ZONE_INPUT="${MAILCOW_CLOUDFLARE_ZONE:-}"',
    'MAILCOW_DANE_TTL_SECONDS_INPUT="${MAILCOW_DANE_TTL_SECONDS:-300}"',
    'MAILCOW_DANE_TTL_SAFETY_SECONDS_INPUT="${MAILCOW_DANE_TTL_SAFETY_SECONDS:-60}"',
    'MAILCOW_DANE_VALIDATING_RESOLVER_INPUT="${MAILCOW_DANE_VALIDATING_RESOLVER:-1.1.1.1}"',
    'MAILCOW_TLSA_RECORD_NAME="_25._tcp.${MAILCOW_SMTP_HOSTNAME}"',
    'CERTS_DUMPER_MAILCOW_LOCK_FILE="${CERTS_DUMPER_SSH_STATE_ROOT}/mailcow-rollover.lock"',
    'flock -n 7 || log_error "Another Mailcow/DANE certificate roll-over is already active"',
    'read_cloudflare_token >/dev/null',
    'timeout 20 delv \\',
    '+noall +comments +trust +ttl +class "$record_name" TLSA',
    'CERTS_DUMPER_SMTP_ATTEMPT_SECONDS=5',
    '--data-urlencode "type=TLSA"',
    '--data-urlencode "name=${record_name}"',
    '(.type | ascii_upcase) == "TLSA"',
    'select_mailcow_tlsa_records() {',
    'require_cloudflare_dnssec_active "$zone_id"',
    'require_certificate_key_pair "$local_cert" "$local_key"',
    'require_certificate_hostname "$local_cert" "$MAILCOW_SMTP_HOSTNAME"',
    'create_cloudflare_tlsa_record \\',
    'deploy_mailcow_certificate_pair \\',
    'wait_for_dane_window "post-deployment overlap" "$overlap_wait"',
    'delete_cloudflare_tlsa_record "$zone_id" "$old_record_id"',
    'verify_remote_smtp_identity "$dest_host" "$MAILCOW_SMTP_HOSTNAME" "$local_spki" "$local_leaf"',
    "StrictHostKeyChecking=accept-new",
    "UpdateHostKeys=no",
    'UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}',
    "stat -Lc '%d:%i' -- /proc/self/fd/9",
    "stat -Lc '%d:%i' -- /proc/self/fd/8",
    'local_cert="/data/files/${MAILCOW_CERT_MAIN_DOMAIN}/certificate.pem"',
    'rollback_remote_mailcow_certificate \\',
    "postfix-mailcow dovecot-mailcow nginx-mailcow",
    "# if true; then mailcow; fi",
):
    if required_fragment not in certs_hook:
        raise SystemExit(f"{certs_hook_path}: missing integrated Mailcow/TLSA fragment {required_fragment!r}")
if "/tmp/.ssh/known_hosts" in certs_hook:
    raise SystemExit(f"{certs_hook_path}: known_hosts must persist under /state, never tmpfs")
ssh_transfer_count = len(
    re.findall(r"^[ \t]*(?:if ! )?(?:scp|ssh) -i ", certs_hook, flags=re.MULTILINE)
)
for ssh_option in (
    "ConnectTimeout=10",
    "ConnectionAttempts=1",
    "StrictHostKeyChecking=accept-new",
    "UpdateHostKeys=no",
    'UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}',
):
    if ssh_transfer_count == 0 or certs_hook.count(ssh_option) != ssh_transfer_count:
        raise SystemExit(
            f"{certs_hook_path}: every SSH/SCP transfer must use the persistent fail-closed host-key options"
        )
if len(re.findall(r"^# if true; then mailcow; fi$", certs_hook, flags=re.MULTILINE)) != 1:
    raise SystemExit(f"{certs_hook_path}: Mailcow must have exactly one commented upstream call")
if re.search(r"^[ \t]*(?!#)(?:if[ ;].*[ ;]then[ ;]+)?mailcow(?:[ ;]|$)", certs_hook, flags=re.MULTILINE):
    raise SystemExit(f"{certs_hook_path}: Mailcow must not be active upstream")
mailcow_body_match = re.search(r"^mailcow\(\) \{\n(?P<body>.*?)^\}$", certs_hook, flags=re.MULTILINE | re.DOTALL)
if not mailcow_body_match:
    raise SystemExit(f"{certs_hook_path}: integrated mailcow function is missing")
mailcow_body = mailcow_body_match.group("body")
ordered_mailcow_steps = (
    "acquire_mailcow_lock",
    "resolve_mailcow_configuration",
    "wait_for_certificate_files",
    "require_certificate_key_pair",
    "require_certificate_hostname",
    "calculate_tlsa_spki_sha256",
    "calculate_certificate_sha256",
    "read_cloudflare_token",
    "cloudflare_find_zone_id",
    "require_cloudflare_dnssec_active",
    "cloudflare_get_tlsa_records",
    "get_remote_smtp_identity",
)
positions = [mailcow_body.find(step) for step in ordered_mailcow_steps]
if any(position < 0 for position in positions) or positions != sorted(positions):
    raise SystemExit(
        f"{certs_hook_path}: Mailcow must preflight certificate, zone, DNSSEC, exact TLSA RRset, then SMTP identity"
    )
if "COPY_ONLY" in certs_hook or "TLSA_ENABLED" in certs_hook or "DANE_ENABLED" in certs_hook:
    raise SystemExit(f"{certs_hook_path}: integrated Mailcow hook must not expose a copy-only switch")
if "--request PATCH" in certs_hook:
    raise SystemExit(f"{certs_hook_path}: Mailcow DANE rollover must add/delete exact records, never PATCH in place")

hook_main_matches = list(
    re.finditer(r"^check_dependencies [^\n]+$", certs_hook, flags=re.MULTILINE)
)
if len(hook_main_matches) != 1:
    raise SystemExit(f"{certs_hook_path}: unable to isolate the post-hook function library")
hook_library = certs_hook[:hook_main_matches[0].start()]

def run_ssh_state_hook_fixture(state_root, body="prepare_ssh_directory"):
    state_library = hook_library.replace(
        'readonly CERTS_DUMPER_SSH_STATE_ROOT="/state"',
        f'readonly CERTS_DUMPER_SSH_STATE_ROOT="{state_root}"',
        1,
    )
    state_library = state_library.replace(
        "  harden_directory_no_follow /tmp/.ssh",
        '  harden_directory_no_follow "${CERTS_DUMPER_SSH_STATE_ROOT}/identity-tmp"',
        1,
    )
    if (
        'readonly CERTS_DUMPER_SSH_STATE_ROOT="/state"' in state_library
        or "  harden_directory_no_follow /tmp/.ssh" in state_library
    ):
        raise SystemExit(f"{certs_hook_path}: unable to replace the isolated SSH state root")
    with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state-script.") as fixture_name:
        fixture = Path(fixture_name)
        fixture_script = fixture / "post-hook-fixture.sh"
        fixture_script.write_text(f"{state_library}\n{body}\n", encoding="utf-8")
        return subprocess.run(
            ["/bin/bash", str(fixture_script)],
            cwd=fixture,
            env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LC_ALL": "C"},
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )

with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state.") as state_fixture_name:
    state_root = Path(state_fixture_name) / "state"
    state_root.mkdir(mode=0o770)
    first_state_prepare = run_ssh_state_hook_fixture(state_root)
    state_directory = state_root / ".ssh"
    known_hosts_file = state_directory / "known_hosts"
    if first_state_prepare.returncode != 0:
        raise SystemExit(f"{certs_hook_path}: first persistent SSH state preparation failed")
    if (
        state_directory.is_symlink()
        or not state_directory.is_dir()
        or (state_directory.stat().st_mode & 0o777) != 0o700
    ):
        raise SystemExit(f"{certs_hook_path}: persistent SSH state directory must be real mode 0700")
    if (
        known_hosts_file.is_symlink()
        or not known_hosts_file.is_file()
        or (known_hosts_file.stat().st_mode & 0o777) != 0o600
    ):
        raise SystemExit(f"{certs_hook_path}: persistent known_hosts must be regular mode 0600")
    persisted_host_key = b"mail.example ssh-ed25519 AAAATESTHOSTKEY\n"
    known_hosts_file.write_bytes(persisted_host_key)
    state_directory.chmod(0o770)
    known_hosts_file.chmod(0o660)
    second_state_prepare = run_ssh_state_hook_fixture(state_root)
    if second_state_prepare.returncode != 0:
        raise SystemExit(f"{certs_hook_path}: restart-style SSH state preparation failed")
    if known_hosts_file.read_bytes() != persisted_host_key:
        raise SystemExit(f"{certs_hook_path}: restart-style preparation replaced the accepted host key")
    if (state_directory.stat().st_mode & 0o777) != 0o700:
        raise SystemExit(f"{certs_hook_path}: restart-style preparation did not restore mode 0700")
    if (known_hosts_file.stat().st_mode & 0o777) != 0o600:
        raise SystemExit(f"{certs_hook_path}: restart-style preparation did not restore mode 0600")

with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state-root-link.") as state_fixture_name:
    fixture = Path(state_fixture_name)
    outside_directory = fixture / "outside"
    outside_directory.mkdir()
    outside_sentinel = outside_directory / "sentinel"
    outside_sentinel.write_bytes(b"unchanged")
    state_root = fixture / "state"
    state_root.symlink_to(outside_directory, target_is_directory=True)
    linked_root_case = run_ssh_state_hook_fixture(state_root)
    if linked_root_case.returncode == 0 or outside_sentinel.read_bytes() != b"unchanged":
        raise SystemExit(f"{certs_hook_path}: symlinked SSH state root must fail closed")

with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state-dir-link.") as state_fixture_name:
    fixture = Path(state_fixture_name)
    state_root = fixture / "state"
    outside_directory = fixture / "outside"
    state_root.mkdir()
    outside_directory.mkdir()
    outside_sentinel = outside_directory / "sentinel"
    outside_sentinel.write_bytes(b"unchanged")
    (state_root / ".ssh").symlink_to(outside_directory, target_is_directory=True)
    linked_directory_case = run_ssh_state_hook_fixture(state_root)
    if linked_directory_case.returncode == 0 or outside_sentinel.read_bytes() != b"unchanged":
        raise SystemExit(f"{certs_hook_path}: symlinked SSH state directory must fail closed")

with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state-file-link.") as state_fixture_name:
    fixture = Path(state_fixture_name)
    state_root = fixture / "state"
    state_directory = state_root / ".ssh"
    outside_file = fixture / "outside-known-hosts"
    state_directory.mkdir(parents=True, mode=0o700)
    outside_file.write_bytes(b"outside")
    outside_file.chmod(0o644)
    (state_directory / "known_hosts").symlink_to(outside_file)
    linked_file_case = run_ssh_state_hook_fixture(state_root)
    if (
        linked_file_case.returncode == 0
        or outside_file.read_bytes() != b"outside"
        or (outside_file.stat().st_mode & 0o777) != 0o644
    ):
        raise SystemExit(f"{certs_hook_path}: symlinked known_hosts must fail without target mutation")

with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state-fifo.") as state_fixture_name:
    state_root = Path(state_fixture_name) / "state"
    state_directory = state_root / ".ssh"
    state_directory.mkdir(parents=True, mode=0o700)
    os.mkfifo(state_directory / "known_hosts", mode=0o600)
    fifo_case = run_ssh_state_hook_fixture(state_root)
    if fifo_case.returncode == 0:
        raise SystemExit(f"{certs_hook_path}: FIFO known_hosts must fail closed")

with tempfile.TemporaryDirectory(prefix="certs-dumper-ssh-state-hardlink.") as state_fixture_name:
    fixture = Path(state_fixture_name)
    state_root = fixture / "state"
    state_directory = state_root / ".ssh"
    outside_file = fixture / "outside-known-hosts"
    state_directory.mkdir(parents=True, mode=0o700)
    outside_file.write_bytes(b"outside")
    outside_file.chmod(0o644)
    os.link(outside_file, state_directory / "known_hosts")
    hardlink_case = run_ssh_state_hook_fixture(state_root)
    if (
        hardlink_case.returncode == 0
        or outside_file.read_bytes() != b"outside"
        or (outside_file.stat().st_mode & 0o777) != 0o644
    ):
        raise SystemExit(f"{certs_hook_path}: multiply linked known_hosts must fail without mutation")

with tempfile.TemporaryDirectory(prefix="certs-dumper-mailcow-lock.") as state_fixture_name:
    state_root = Path(state_fixture_name) / "state"
    state_root.mkdir(mode=0o700)
    lock_case = run_ssh_state_hook_fixture(
        state_root,
        r'''prepare_ssh_directory
acquire_mailcow_lock
if flock -n "$CERTS_DUMPER_MAILCOW_LOCK_FILE" -c true; then
  exit 1
fi''',
    )
    if lock_case.returncode != 0:
        raise SystemExit(
            f"{certs_hook_path}: Mailcow kernel lock must reject a concurrent holder without stale-lock files"
        )

def run_mailcow_hook_fixture(body, environment):
    with tempfile.TemporaryDirectory(prefix="mailcow-post-hook.") as fixture_name:
        fixture = Path(fixture_name)
        fixture_script = fixture / "post-hook-fixture.sh"
        fixture_script.write_text(f"{hook_library}\n{body}\n", encoding="utf-8")
        fixture_environment = {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "LC_ALL": "C",
            **environment,
        }
        return subprocess.run(
            ["/bin/bash", str(fixture_script)],
            cwd=fixture,
            env=fixture_environment,
            check=False,
            capture_output=True,
            text=True,
        )

mailcow_route_environment = {
    "TRAEFIK_DOMAIN": "xn--lb-1ia.de",
    "TRAEFIK_DOMAIN_1": "xn--srvices-mxa.de",
    "TRAEFIK_DOMAIN_2": "saervices.de",
    "TRAEFIK_DOMAIN_3": "it-saervices.de",
    "TRAEFIK_DOMAIN_4": "itsaervices.de",
    "TRAEFIK_ROUTE_SUBDOMAIN": "it",
    "MAILCOW_SMTP_HOSTNAME": "mail.it.saervices.de",
    "MAILCOW_CLOUDFLARE_ZONE": "saervices.de",
    "MAILCOW_DANE_TTL_SECONDS": "300",
    "MAILCOW_DANE_TTL_SAFETY_SECONDS": "60",
    "MAILCOW_DANE_VALIDATING_RESOLVER": "1.1.1.1",
}
mailcow_resolver_case = run_mailcow_hook_fixture(
    r'''resolve_mailcow_configuration
printf '%s\n' \
  "$MAILCOW_CERT_MAIN_DOMAIN" \
  "$MAILCOW_SMTP_HOSTNAME" \
  "$MAILCOW_CLOUDFLARE_ZONE_NAME" \
  "$MAILCOW_TLSA_RECORD_NAME"''',
    mailcow_route_environment,
)
expected_mailcow_resolution = "\n".join(
    (
        "mailcow.it.xn--lb-1ia.de",
        "mail.it.saervices.de",
        "saervices.de",
        "_25._tcp.mail.it.saervices.de",
        "",
    )
)
if (
    mailcow_resolver_case.returncode != 0
    or mailcow_resolver_case.stdout != expected_mailcow_resolution
):
    raise SystemExit(
        f"{certs_hook_path}: SMTP, explicit Cloudflare zone, TLSA owner, or certificate main resolved incorrectly"
    )

unprefixed_smtp_environment = {
    **mailcow_route_environment,
    "MAILCOW_SMTP_HOSTNAME": "mail.saervices.de",
}
unprefixed_smtp_case = run_mailcow_hook_fixture(
    "resolve_mailcow_configuration",
    unprefixed_smtp_environment,
)
if unprefixed_smtp_case.returncode == 0:
    raise SystemExit(
        f"{certs_hook_path}: prefixed mode must reject the legacy unprefixed SMTP host"
    )

placeholder_zone_case = run_mailcow_hook_fixture(
    "resolve_mailcow_configuration",
    {**mailcow_route_environment, "MAILCOW_CLOUDFLARE_ZONE": "CHANGE_ME"},
)
if placeholder_zone_case.returncode == 0:
    raise SystemExit(
        f"{certs_hook_path}: active Mailcow hook must reject an unconfigured Cloudflare zone"
    )

if True:
  tlsa_owner = "_25._tcp.mail.it.saervices.de"
  old_spki = "a" * 64
  new_spki = "b" * 64
  old_leaf = "c" * 64
  new_leaf = "d" * 64
  old_record_id = "1" * 32
  new_record_id = "2" * 32

  def tlsa_record(record_id, certificate_hash, *, owner=tlsa_owner, ttl=300, usage=3):
    return {
        "id": record_id,
        "type": "TLSA",
        "name": owner,
        "ttl": ttl,
        "proxied": False,
        "data": {
            "usage": usage,
            "selector": 1,
            "matching_type": 1,
            "certificate": certificate_hash,
        },
    }

  stable_rrset = {"success": True, "result": [tlsa_record(old_record_id, old_spki)]}
  transitional_rrset = {
    "success": True,
    "result": [
        tlsa_record(old_record_id, old_spki),
        tlsa_record(new_record_id, new_spki),
    ],
  }
  content_rrset = {
    "success": True,
    "result": [{
        "id": new_record_id,
        "type": "TLSA",
        "name": tlsa_owner,
        "ttl": 300,
        "proxied": False,
        "content": f"3 1 1 {new_spki}",
    }],
  }
  for rrset_name, rrset, expected_count in (
    ("stable", stable_rrset, 1),
    ("transitional", transitional_rrset, 2),
    ("content", content_rrset, 1),
  ):
    selector_case = run_mailcow_hook_fixture(
        'select_mailcow_tlsa_records "$TLSA_RECORDS" "$TLSA_OWNER" 300 | jq -er "length"',
        {
            "TLSA_RECORDS": json.dumps(rrset, separators=(",", ":")),
            "TLSA_OWNER": tlsa_owner,
        },
    )
    if selector_case.returncode != 0 or selector_case.stdout != f"{expected_count}\n":
      raise SystemExit(
          f"{certs_hook_path}: valid {rrset_name} Mailcow TLSA RRset was rejected"
      )

  invalid_rrsets = {
    "automatic TTL": {"success": True, "result": [tlsa_record(old_record_id, old_spki, ttl=1)]},
    "wrong tuple": {"success": True, "result": [tlsa_record(old_record_id, old_spki, usage=2)]},
    "wrong owner": {
        "success": True,
        "result": [tlsa_record(old_record_id, old_spki, owner=f"{tlsa_owner}.evil")],
    },
    "duplicate hash": {
        "success": True,
        "result": [
            tlsa_record(old_record_id, old_spki),
            tlsa_record(new_record_id, old_spki),
        ],
    },
    "three records": {
        "success": True,
        "result": [
            tlsa_record(old_record_id, old_spki),
            tlsa_record(new_record_id, new_spki),
            tlsa_record("3" * 32, "e" * 64),
        ],
    },
  }
  for rrset_name, rrset in invalid_rrsets.items():
    selector_case = run_mailcow_hook_fixture(
        'select_mailcow_tlsa_records "$TLSA_RECORDS" "$TLSA_OWNER" 300 >/dev/null',
        {
            "TLSA_RECORDS": json.dumps(rrset, separators=(",", ":")),
            "TLSA_OWNER": tlsa_owner,
        },
    )
    if selector_case.returncode == 0:
      raise SystemExit(
          f"{certs_hook_path}: invalid {rrset_name} Mailcow TLSA RRset must fail closed"
      )

  cloudflare_zone_case = run_mailcow_hook_fixture(
    r'''cloudflare_get_zones_by_name() {
  printf '%s' '{"result":[{"id":"99999999999999999999999999999999","name":"internal.example","status":"active"},{"id":"11111111111111111111111111111111","name":"SAERVICES.DE.","status":"active"}]}'
}
cloudflare_find_zone_id 'saervices.de' ''',
    {},
  )
  if cloudflare_zone_case.returncode != 0 or cloudflare_zone_case.stdout != f"{'1' * 32}\n":
    raise SystemExit(
        f"{certs_hook_path}: explicit active Cloudflare zone lookup trusted a non-exact API result"
    )

  dnssec_active_case = run_mailcow_hook_fixture(
    "cloudflare_get_dnssec() { printf '%s' '{\"result\":{\"status\":\"active\"}}'; }\n"
    "require_cloudflare_dnssec_active 11111111111111111111111111111111",
    {},
  )
  dnssec_inactive_case = run_mailcow_hook_fixture(
    "cloudflare_get_dnssec() { printf '%s' '{\"result\":{\"status\":\"pending\"}}'; }\n"
    "require_cloudflare_dnssec_active 11111111111111111111111111111111",
    {},
  )
  if dnssec_active_case.returncode != 0 or dnssec_inactive_case.returncode == 0:
    raise SystemExit(f"{certs_hook_path}: Cloudflare DNSSEC active gate is not fail closed")

  locally_validated_rrset_case = run_mailcow_hook_fixture(
    r'''MAILCOW_DANE_VALIDATING_RESOLVER=1.1.1.1
timeout() { shift; "$@"; }
delv() {
  printf '%s\n' '; fully validated' \
    "_25._tcp.mail.it.saervices.de. 300 IN TLSA 3 1 1 ${TLSA_HASH}"
}
dnssec_tlsa_rrset_matches _25._tcp.mail.it.saervices.de 300 "$TLSA_HASH"''',
    {"TLSA_HASH": old_spki},
  )
  forged_ad_rrset_case = run_mailcow_hook_fixture(
    r'''MAILCOW_DANE_VALIDATING_RESOLVER=1.1.1.1
timeout() { shift; "$@"; }
delv() {
  printf '%s\n' ';; flags: qr rd ra ad;' \
    "_25._tcp.mail.it.saervices.de. 300 IN TLSA 3 1 1 ${TLSA_HASH}"
}
dnssec_tlsa_rrset_matches _25._tcp.mail.it.saervices.de 300 "$TLSA_HASH"''',
    {"TLSA_HASH": old_spki},
  )
  if locally_validated_rrset_case.returncode != 0 or forged_ad_rrset_case.returncode == 0:
    raise SystemExit(
        f"{certs_hook_path}: local delv validation must accept fully validated DNSSEC and reject a forged AD bit"
    )

  automatic_ttl_case = run_mailcow_hook_fixture(
    "resolve_mailcow_configuration",
    {**mailcow_route_environment, "MAILCOW_DANE_TTL_SECONDS": "1"},
  )
  if automatic_ttl_case.returncode == 0:
    raise SystemExit(f"{certs_hook_path}: Cloudflare automatic TLSA TTL=1 must fail closed")

  with tempfile.TemporaryDirectory(prefix="mailcow-cf-token.") as token_fixture_name:
    token_fixture = Path(token_fixture_name)
    token_path = token_fixture / "token"
    for token_name, token_bytes, expected_success in (
        ("valid", b"valid_token-123\n", True),
        ("empty", b"", False),
        ("placeholder", b"CHANGE_ME", False),
        ("multiline", b"first\nsecond\n", False),
        ("CRLF multiline", b"first\r\nsecond\r\n", False),
        ("whitespace", b"token value\n", False),
    ):
      token_path.write_bytes(token_bytes)
      token_case = run_mailcow_hook_fixture(
          "read_cloudflare_token",
          {"CF_DNS_API_TOKEN_FILE": str(token_path)},
      )
      if (token_case.returncode == 0) != expected_success:
        raise SystemExit(
            f"{certs_hook_path}: Cloudflare token {token_name} line contract is incorrect"
        )

with tempfile.TemporaryDirectory(prefix="mailcow-key-pair.") as key_pair_fixture_name:
    key_pair_fixture = Path(key_pair_fixture_name)
    matching_key = key_pair_fixture / "matching.key"
    matching_cert = key_pair_fixture / "matching.crt"
    other_key = key_pair_fixture / "other.key"
    other_cert = key_pair_fixture / "other.crt"
    for key_path, cert_path, common_name in (
        (matching_key, matching_cert, "mail.it.saervices.de"),
        (other_key, other_cert, "unrelated.example"),
    ):
        generated = subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-subj", f"/CN={common_name}", "-days", "1",
                "-keyout", str(key_path), "-out", str(cert_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if generated.returncode != 0:
            raise SystemExit(f"{certs_hook_path}: could not create local key-pair fixture")
    matching_key_pair_case = run_mailcow_hook_fixture(
        'require_certificate_key_pair "$CERT_PATH" "$KEY_PATH"',
        {"CERT_PATH": str(matching_cert), "KEY_PATH": str(matching_key)},
    )
    if matching_key_pair_case.returncode != 0:
        raise SystemExit(f"{certs_hook_path}: matching certificate/private-key pair was rejected")
    mismatched_key_pair_case = run_mailcow_hook_fixture(
        'require_certificate_key_pair "$CERT_PATH" "$KEY_PATH"',
        {"CERT_PATH": str(matching_cert), "KEY_PATH": str(other_key)},
    )
    if mismatched_key_pair_case.returncode == 0:
        raise SystemExit(f"{certs_hook_path}: mismatched certificate/private-key pair was accepted")

if True:
  mailcow_flow_body = r'''trace_event() { printf '%s\n' "$1" >>"$MAILCOW_TEST_TRACE"; }
acquire_mailcow_lock() { trace_event "lock"; }
read_cloudflare_token() { trace_event "token"; printf 'test-token'; }
wait_for_certificate_files() { trace_event "cert-files|$1|$2"; }
require_certificate_key_pair() { trace_event "cert-key|$1|$2"; }
require_certificate_hostname() { trace_event "cert-host|$1|$2"; }
calculate_tlsa_spki_sha256() { printf '%s' "$MAILCOW_TEST_NEW_SPKI"; }
calculate_certificate_sha256() { printf '%s' "$MAILCOW_TEST_NEW_LEAF"; }
cloudflare_find_zone_id() { trace_event "zone|$1"; printf '11111111111111111111111111111111'; }
require_cloudflare_dnssec_active() { trace_event "dnssec|$1"; }
cloudflare_get_tlsa_records() {
  trace_event "get-rrset|$(cat "$MAILCOW_TEST_STATE")"
  case "$(cat "$MAILCOW_TEST_STATE")" in
    stable-old)
      jq -nc --arg owner "$MAILCOW_TLSA_RECORD_NAME" --arg hash "$MAILCOW_TEST_OLD_SPKI" '{success:true,result:[{id:("1"*32),type:"TLSA",name:$owner,ttl:300,proxied:false,data:{usage:3,selector:1,matching_type:1,certificate:$hash}}]}'
      ;;
    stable-new|final-new)
      jq -nc --arg owner "$MAILCOW_TLSA_RECORD_NAME" --arg hash "$MAILCOW_TEST_NEW_SPKI" '{success:true,result:[{id:("2"*32),type:"TLSA",name:$owner,ttl:300,proxied:false,data:{usage:3,selector:1,matching_type:1,certificate:$hash}}]}'
      ;;
    transitional)
      jq -nc --arg owner "$MAILCOW_TLSA_RECORD_NAME" --arg old "$MAILCOW_TEST_OLD_SPKI" --arg new "$MAILCOW_TEST_NEW_SPKI" '{success:true,result:[{id:("1"*32),type:"TLSA",name:$owner,ttl:300,proxied:false,data:{usage:3,selector:1,matching_type:1,certificate:$old}},{id:("2"*32),type:"TLSA",name:$owner,ttl:300,proxied:false,data:{usage:3,selector:1,matching_type:1,certificate:$new}}]}'
      ;;
    *) return 71 ;;
  esac
}
wait_for_dnssec_tlsa_rrset() { trace_event "dns-view|$*"; }
create_cloudflare_tlsa_record() {
  trace_event "create|$1|$2|$3|$4"
  printf 'transitional' >"$MAILCOW_TEST_STATE"
}
delete_cloudflare_tlsa_record() {
  trace_event "delete|$1|$2"
  printf 'final-new' >"$MAILCOW_TEST_STATE"
}
wait_for_dane_window() { trace_event "window|$1|$2"; }
get_remote_smtp_identity() { trace_event "smtp-get|$1|$2"; cat "$MAILCOW_TEST_IDENTITY"; }
deploy_mailcow_certificate_pair() {
  trace_event "deploy|$7|$8|$9|${10}"
  printf '%s\n%s\n' "$7" "$8" >"$MAILCOW_TEST_IDENTITY"
}
verify_remote_smtp_identity() {
  trace_event "smtp-verify|$3|$4"
  actual_spki="$(sed -n '1p' "$MAILCOW_TEST_IDENTITY")"
  actual_leaf="$(sed -n '2p' "$MAILCOW_TEST_IDENTITY")"
  [ "$actual_spki" = "$3" ] && [ "$actual_leaf" = "$4" ]
}
cleanup_remote_mailcow_transaction() { trace_event "cleanup|$5"; }
mailcow'''

  def assert_trace_order(trace, required_steps, scenario):
    position = -1
    for required_step in required_steps:
      try:
        position = next(
            index for index in range(position + 1, len(trace))
            if trace[index].startswith(required_step)
        )
      except StopIteration as error:
        raise SystemExit(
            f"{certs_hook_path}: {scenario} flow missed or misordered {required_step!r}: {trace}"
        ) from error

  def run_mailcow_flow(fixture, scenario, initial_state, remote_spki, remote_leaf):
    trace_path = fixture / f"{scenario}.trace"
    state_path = fixture / f"{scenario}.state"
    identity_path = fixture / f"{scenario}.identity"
    state_path.write_text(initial_state, encoding="utf-8")
    identity_path.write_text(f"{remote_spki}\n{remote_leaf}\n", encoding="utf-8")
    result = run_mailcow_hook_fixture(
        mailcow_flow_body,
        {
            **mailcow_route_environment,
            "MAILCOW_TEST_TRACE": str(trace_path),
            "MAILCOW_TEST_STATE": str(state_path),
            "MAILCOW_TEST_IDENTITY": str(identity_path),
            "MAILCOW_TEST_OLD_SPKI": old_spki,
            "MAILCOW_TEST_NEW_SPKI": new_spki,
            "MAILCOW_TEST_NEW_LEAF": new_leaf,
        },
    )
    trace = trace_path.read_text(encoding="utf-8").splitlines() if trace_path.is_file() else []
    if result.returncode != 0:
      raise SystemExit(
          f"{certs_hook_path}: {scenario} Mailcow flow failed: {result.stderr.strip()} trace={trace}"
      )
    return trace, state_path.read_text(encoding="utf-8")

  with tempfile.TemporaryDirectory(prefix="mailcow-dane-flow.") as flow_fixture_name:
    flow_fixture = Path(flow_fixture_name)
    same_spki_trace, same_spki_state = run_mailcow_flow(
        flow_fixture, "same-spki", "stable-new", new_spki, old_leaf
    )
    assert_trace_order(
        same_spki_trace,
        ("lock", "token", "dnssec|", "dns-view|", "deploy|", "cleanup|"),
        "same-SPKI renewal",
    )
    if (
        same_spki_state != "stable-new"
        or any(event.startswith(("create|", "delete|", "window|")) for event in same_spki_trace)
    ):
      raise SystemExit(
          f"{certs_hook_path}: same-SPKI renewal must deploy the leaf with zero DNS mutation/wait"
      )

    new_key_trace, new_key_state = run_mailcow_flow(
        flow_fixture, "new-key", "stable-old", old_spki, old_leaf
    )
    assert_trace_order(
        new_key_trace,
        (
            "dns-view|", "create|", "dns-view|", "window|pre-deployment overlap|660",
            "deploy|", "window|post-deployment overlap|660", "smtp-verify|", "delete|",
            "dns-view|", "cleanup|",
        ),
        "new-SPKI renewal",
    )
    if new_key_state != "final-new" or sum(event.startswith("delete|") for event in new_key_trace) != 1:
      raise SystemExit(f"{certs_hook_path}: new-SPKI renewal did not retire exactly one old record")

    resume_pre_trace, resume_pre_state = run_mailcow_flow(
        flow_fixture, "resume-pre", "transitional", old_spki, old_leaf
    )
    assert_trace_order(
        resume_pre_trace,
        (
            "dns-view|", "window|resumed pre-deployment overlap|660", "deploy|",
            "window|post-deployment overlap|660", "delete|", "cleanup|",
        ),
        "resumed pre-deployment transition",
    )
    if resume_pre_state != "final-new" or any(event.startswith("create|") for event in resume_pre_trace):
      raise SystemExit(f"{certs_hook_path}: pre-deployment resume duplicated TLSA publication")

    resume_post_trace, resume_post_state = run_mailcow_flow(
        flow_fixture, "resume-post", "transitional", new_spki, new_leaf
    )
    assert_trace_order(
        resume_post_trace,
        ("dns-view|", "window|post-deployment overlap|660", "delete|", "cleanup|"),
        "resumed post-deployment transition",
    )
    if (
        resume_post_state != "final-new"
        or any(event.startswith(("create|", "deploy|", "window|resumed pre")) for event in resume_post_trace)
    ):
      raise SystemExit(f"{certs_hook_path}: post-deployment resume repeated publication or deployment")

  with tempfile.TemporaryDirectory(prefix="mailcow-dane-rollback.") as rollback_fixture_name:
    rollback_fixture = Path(rollback_fixture_name)
    rollback_trace_path = rollback_fixture / "trace"
    rollback_identity_path = rollback_fixture / "identity"
    rollback_counter_path = rollback_fixture / "counter"
    rollback_identity_path.write_text(f"{old_spki}\n{old_leaf}\n", encoding="utf-8")
    rollback_case = run_mailcow_hook_fixture(
        r'''trace_event() { printf '%s\n' "$1" >>"$MAILCOW_TEST_TRACE"; }
stage_remote_mailcow_certificate() { trace_event "stage"; }
activate_remote_mailcow_certificate() {
  trace_event "activate"
  printf '%s\n%s\n' "$6" "$5" >"$MAILCOW_TEST_IDENTITY"
}
restart_remote_mailcow_services() { trace_event "restart"; }
rollback_remote_mailcow_certificate() {
  trace_event "rollback"
  printf '%s\n%s\n' "$6" "$7" >"$MAILCOW_TEST_IDENTITY"
}
verify_remote_smtp_identity() {
  trace_event "verify|$3|$4"
  if [ ! -e "$MAILCOW_TEST_COUNTER" ]; then
    : >"$MAILCOW_TEST_COUNTER"
    return 1
  fi
  [ "$(sed -n '1p' "$MAILCOW_TEST_IDENTITY")" = "$3" ] &&
    [ "$(sed -n '2p' "$MAILCOW_TEST_IDENTITY")" = "$4" ]
}
MAILCOW_SMTP_HOSTNAME=mail.it.saervices.de
deploy_mailcow_certificate_pair cert key 192.168.20.120 root /opt/mailcow-dockerized key \
  "$MAILCOW_TEST_NEW_SPKI" "$MAILCOW_TEST_NEW_LEAF" \
  "$MAILCOW_TEST_OLD_SPKI" "$MAILCOW_TEST_OLD_LEAF"''',
        {
            "MAILCOW_TEST_TRACE": str(rollback_trace_path),
            "MAILCOW_TEST_IDENTITY": str(rollback_identity_path),
            "MAILCOW_TEST_COUNTER": str(rollback_counter_path),
            "MAILCOW_TEST_OLD_SPKI": old_spki,
            "MAILCOW_TEST_OLD_LEAF": old_leaf,
            "MAILCOW_TEST_NEW_SPKI": new_spki,
            "MAILCOW_TEST_NEW_LEAF": new_leaf,
        },
    )
    rollback_trace = rollback_trace_path.read_text(encoding="utf-8").splitlines()
    assert_trace_order(
        rollback_trace,
        ("stage", "activate", "restart", f"verify|{new_spki}|{new_leaf}", "rollback", "restart", f"verify|{old_spki}|{old_leaf}"),
        "post-activation rollback",
    )
    if rollback_case.returncode == 0:
      raise SystemExit(f"{certs_hook_path}: failed new SMTP verification must remain a failed hook after rollback")

certs_dockerfile_path = root / "templates/traefik_certs-dumper/dockerfiles/dockerfile.traefik-certs-dumper.scp"
certs_dockerfile = certs_dockerfile_path.read_text(encoding="utf-8")
for required_package in ("openssh-client", "jq", "curl", "openssl", "bind-tools", "util-linux", "tzdata"):
    if required_package not in certs_dockerfile:
        raise SystemExit(f"{certs_dockerfile_path}: missing post-hook package {required_package}")

certs_key_path = certs_path.parent / "secrets/TRAEFIK_CERTS_DUMPER_PASSWORD"
if certs_key_path.read_bytes() != b"CHANGE_ME":
    raise SystemExit(f"{certs_key_path}: SSH-key placeholder must be exact 9-byte CHANGE_ME")
traefik_path = root / "Traefik/docker-compose.app.yaml"
traefik_document = yaml.safe_load(traefik_path.read_text(encoding="utf-8"))
if "traefik_certs-dumper" not in set(traefik_document.get("x-required-services") or []):
    raise SystemExit(f"{traefik_path}: existing certs-dumper must remain required")
if "TRAEFIK_CERTS_DUMPER_PASSWORD" not in set(traefik_document.get("x-secret-generation-exclusions") or []):
    raise SystemExit(f"{traefik_path}: form-bound SSH key must remain generation-excluded")
PY
}

expect_success compose-disabled-features-have-no-secret-mount check_disabled_feature_mounts

printf '\nSecret preflight tests: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
"${TEST_REPO_ROOT}/.cursor/scripts/test-crowdsec-agent-wrapper.sh"
