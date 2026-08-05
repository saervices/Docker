#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS ÆND TEST HÆRNESS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/secret-preflights.XXXXXX")"
readonly TEST_BIN="${TEST_ROOT}/bin"
readonly TEST_CRYPTO="${TEST_ROOT}/crypto"

readonly ACTUALBUDGET_SCRIPT="${TEST_REPO_ROOT}/ActualBudget/scripts/actual-start.sh"
readonly AUTHENTIK_WORKER_SCRIPT="${TEST_REPO_ROOT}/templates/authentik-worker/scripts/authentik-bootstrap-entrypoint.sh"
readonly REDIS_SCRIPT="${TEST_REPO_ROOT}/templates/redis/scripts/redis-start.sh"
readonly ELASTICSEARCH_SCRIPT="${TEST_REPO_ROOT}/templates/elasticsearch/scripts/elasticsearch-start.sh"
readonly SEASEARCH_SCRIPT="${TEST_REPO_ROOT}/templates/seafile_seasearch/scripts/seasearch-start.sh"
readonly FACTORIO_SCRIPT="${TEST_REPO_ROOT}/Factorio/dockerfiles/entrypoint.sh"
readonly ESPOCRM_SCRIPT="${TEST_REPO_ROOT}/EspoCRM/scripts/espocrm-start.sh"
readonly VAULTWARDEN_SCRIPT="${TEST_REPO_ROOT}/Vaultwarden/scripts/vaultwarden.d/10-database-url.sh"
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
printf '%s\n' '#!/bin/sh' '[ -z "${CERTS_DUMPER_MARKER:-}" ] || : >"$CERTS_DUMPER_MARKER"' 'exit 0' >"${TEST_BIN}/traefik-certs-dumper"
printf '%s\n' \
  '#!/bin/sh' \
  'test "$1" = -' \
  'test -r "$2"' \
  'printf "%s" "pbkdf2_sha256\$1000000\$testsalt\$dGVzdC1kaWdlc3Q="' \
  >"${TEST_BIN}/authentik-password-hasher"
printf '%s\n' \
  '#!/bin/sh' \
  'test -z "${AUTHENTIK_BOOTSTRAP_PASSWORD+x}"' \
  'test "${AUTHENTIK_BOOTSTRAP_PASSWORD_HASH:-}" = "pbkdf2_sha256\$1000000\$testsalt\$dGVzdC1kaWdlc3Q="' \
  'exit 0' >"${TEST_BIN}/authentik-lifecycle"
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
  "${TEST_BIN}/traefik-certs-dumper" \
  "${TEST_BIN}/authentik-password-hasher" \
  "${TEST_BIN}/authentik-lifecycle" \
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
# --- ÆUTHENTIK WORKER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
prepare_authentik_worker() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'strong-bootstrap-password' >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
}

run_authentik_worker() {
  local fixture="$1"
  AUTHENTIK_BOOTSTRAP_PASSWORD_FILE="${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD" \
    AUTHENTIK_PASSWORD_HASHER_BIN="${TEST_BIN}/authentik-password-hasher" \
    AUTHENTIK_LIFECYCLE_BIN="${TEST_BIN}/authentik-lifecycle" \
    /bin/sh "$AUTHENTIK_WORKER_SCRIPT" worker
}

case_authentik_worker_short_password() {
  local fixture="${TEST_ROOT}/authentik-worker-short"
  prepare_authentik_worker "$fixture"
  printf 'too-short' >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_worker "$fixture"
}

case_authentik_worker_oversized_password() {
  local fixture="${TEST_ROOT}/authentik-worker-oversized"
  prepare_authentik_worker "$fixture"
  printf '%04097d' 0 >"${fixture}/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD"
  run_authentik_worker "$fixture"
}

prepare_authentik_worker "${TEST_ROOT}/authentik-worker-valid"
expect_success authentik-worker-valid run_authentik_worker "${TEST_ROOT}/authentik-worker-valid"
exercise_secret_matrix authentik-worker-bootstrap prepare_authentik_worker run_authentik_worker AUTHENTIK_BOOTSTRAP_PASSWORD
expect_failure authentik-worker-bootstrap-short case_authentik_worker_short_password
expect_failure authentik-worker-bootstrap-oversized case_authentik_worker_oversized_password

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
prepare_vaultwarden() {
  local fixture="$1"
  mkdir -p -- "${fixture}/secrets"
  printf 'postgres-password' >"${fixture}/secrets/POSTGRES_PASSWORD"
  printf '%s' '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$ZGlnZXN0' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  printf 'smtp-password' >"${fixture}/secrets/MAILER_SMTP_PASSWORD"
  printf 'provider-client-id' >"${fixture}/secrets/VAULTWARDEN_SSO_CLIENT_ID"
  printf 'provider-client-secret' >"${fixture}/secrets/VAULTWARDEN_SSO_CLIENT_SECRET"
}

run_vaultwarden() {
  local fixture="$1"
  SECRET_DIR="${fixture}/secrets" APP_NAME=vaultwarden SMTP_HOST=mail.example.test SSO_ENABLED=true \
    /bin/sh -c '. "$1"' _ "$VAULTWARDEN_SCRIPT"
}

case_vaultwarden_malformed_admin() {
  local fixture="${TEST_ROOT}/vaultwarden-admin-malformed"
  prepare_vaultwarden "$fixture"
  printf 'not-an-argon2id-phc-hash' >"${fixture}/secrets/VAULTWARDEN_ADMIN_TOKEN"
  run_vaultwarden "$fixture"
}

expect_success vaultwarden-valid prepare_vaultwarden "${TEST_ROOT}/vaultwarden-valid-fixture"
expect_success vaultwarden-valid-run run_vaultwarden "${TEST_ROOT}/vaultwarden-valid-fixture"
exercise_secret_matrix vaultwarden-admin prepare_vaultwarden run_vaultwarden VAULTWARDEN_ADMIN_TOKEN
exercise_secret_matrix vaultwarden-smtp prepare_vaultwarden run_vaultwarden MAILER_SMTP_PASSWORD
exercise_secret_matrix vaultwarden-sso-id prepare_vaultwarden run_vaultwarden VAULTWARDEN_SSO_CLIENT_ID
exercise_secret_matrix vaultwarden-sso-secret prepare_vaultwarden run_vaultwarden VAULTWARDEN_SSO_CLIENT_SECRET
expect_failure vaultwarden-admin-malformed case_vaultwarden_malformed_admin

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
  mkdir -p -- "${fixture}/secrets"
  printf 'cloudflare-token' >"${fixture}/secrets/CF_DNS_API_TOKEN"
}

run_traefik() {
  local fixture="$1"
  CERTRESOLVER=cloudflare CF_DNS_API_TOKEN_FILE="${fixture}/secrets/CF_DNS_API_TOKEN" \
    /bin/sh "$TRAEFIK_SCRIPT" /bin/true
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
worker_mounts = {
    item if isinstance(item, str) else item.get("source")
    for item in worker_service.get("secrets", [])
}
if authentik_secret in worker_mounts:
    raise SystemExit(f"{worker_path}: disabled {authentik_secret} is mounted into services.authentik-worker")
if any(str(key).startswith("AUTHENTIK_EMAIL__") for key in worker_service.get("environment", {})):
    raise SystemExit(f"{worker_path}: disabled Authentik SMTP environment is active")

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
for obsolete_secret in ("TRAEFIK_CERTS_DUMPER_PASSWORD", "CF_DNS_API_TOKEN"):
    if obsolete_secret in certs_text:
        raise SystemExit(f"{certs_path}: stale secret remnant {obsolete_secret} must be removed")
if (certs_path.parent / "secrets").exists():
    raise SystemExit(f"{certs_path.parent}: secretless template must not ship a secrets directory")
PY
}

expect_success compose-disabled-features-have-no-secret-mount check_disabled_feature_mounts

printf '\nSecret preflight tests: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
