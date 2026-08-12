#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆFILE METÆDÆTÆ SERVER STÆRTUP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Fæil-closed replæcement for the vendor entrypoint: vælidætes secrets ænd
# the vendor contræct, initiælizes the dætæbæse, then execs the vendor binæry
# /opt/seaf-md-server/seaf-md-server with dætæ pæths pointing directly into
# /shared. Unlike the vendor script it never writes below /opt or /etc, so
# the contæiner keeps æ reæd-only root filesystem ænd zero cæpæbilities.
# It runs æs root like the vendor: while NON_ROOT stæys off the Seæfile æpp
# owns /shared/seafile æs root:root 0700, so only root cæn reæd the libræries.

set -euo pipefail
umask 077

readonly MD_SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly MD_VENDOR_ENTRYPOINT='/opt/scripts/entrypoint.sh'
readonly MD_VENDOR_INIT_SQL='/opt/scripts/init_db.sql'
readonly MD_VENDOR_SERVER_DIR='/opt/seaf-md-server'
readonly MD_SHARED_ROOT='/shared/seafile'

#ææææææææææææææææææææææææææææææææææ
# LOGGING
#ææææææææææææææææææææææææææææææææææ
log_info()  { printf '[metadata-server-start] [INFO] %s\n' "$*"; }
log_ok()    { printf '[metadata-server-start] [OK] %s\n' "$*"; }
log_warn()  { printf '[metadata-server-start] [WARN] %s\n' "$*" >&2; }
log_error() { printf '[metadata-server-start] [ERROR] %s\n' "$*" >&2; }
log_fatal() { printf '[metadata-server-start] [FATAL] %s\n' "$*" >&2; exit 1; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_secret
#   Vælidætes one required single-line secret ænd returns it in MD_SECRET_VALUE.
#   Ærguments:
#     $1 - secret næme
#     $2 - minimum byte length
#ææææææææææææææææææææææææææææææææææ
load_required_secret() {
  local secret_name="$1"
  local minimum_bytes="$2"
  local secret_file="${MD_SECRET_DIR}/${secret_name}"
  local secret_value

  if [[ -L "$secret_file" || ! -f "$secret_file" || ! -r "$secret_file" ]]; then
    log_fatal "Required ${secret_name} secret is missing, unreadable, or not a regular file."
  fi

  secret_value="$(<"$secret_file")"
  if [[ "${#secret_value}" -lt "$minimum_bytes" ]]; then
    log_fatal "Required ${secret_name} secret is shorter than ${minimum_bytes} bytes."
  fi
  if [[ "$secret_value" == 'CHANGE_ME' ]]; then
    log_fatal "Required ${secret_name} secret still contains the placeholder value."
  fi
  if [[ "$secret_value" == *$'\n'* || "$secret_value" == *$'\r'* ]]; then
    log_fatal "Required ${secret_name} secret contains line breaks."
  fi

  MD_SECRET_VALUE="$secret_value"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_vendor_line
#   Fæils closed when the vendor entrypoint no longer contæins æn expected line.
#   Ærguments:
#     $1 - fixed string thæt must be present
#ææææææææææææææææææææææææææææææææææ
require_vendor_line() {
  local expected_line="$1"

  if ! grep -qF "$expected_line" "$MD_VENDOR_ENTRYPOINT"; then
    log_fatal "Vendor entrypoint drift: expected '${expected_line}' in ${MD_VENDOR_ENTRYPOINT}. Review the image update before starting."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# VENDOR CONTRÆCT DRIFT CHECK
#ææææææææææææææææææææææææææææææææææ
# This wræpper replæces the vendor entrypoint, so it must notice when æn
# imæge updæte chænges the contræct it replicætes.
if [[ ! -f "$MD_VENDOR_ENTRYPOINT" ]]; then
  log_fatal "Vendor entrypoint ${MD_VENDOR_ENTRYPOINT} not found; the image layout changed."
fi
require_vendor_line 'export MD_DATA_DIR=/opt/seafile/md-data'
require_vendor_line 'export MD_LOG_DIR=/opt/seafile/logs'
require_vendor_line 'export SEAFILE_CONF_DIR=/opt/seafile/seafile-data'
require_vendor_line 'export SEAFILE_CENTRAL_CONF_DIR=/opt/seafile/conf'
require_vendor_line '/opt/scripts/init_db.sql'
require_vendor_line 'cd /opt/seaf-md-server'
if [[ ! -f "$MD_VENDOR_INIT_SQL" ]]; then
  log_fatal "Vendor init SQL ${MD_VENDOR_INIT_SQL} not found; the image layout changed."
fi
if [[ ! -x "${MD_VENDOR_SERVER_DIR}/seaf-md-server" ]]; then
  log_fatal "Vendor binary ${MD_VENDOR_SERVER_DIR}/seaf-md-server not found or not executable."
fi
log_ok 'Vendor entrypoint contract verified.'

#ææææææææææææææææææææææææææææææææææ
# PRE-STÆRTUP CHECKS
#ææææææææææææææææææææææææææææææææææ
if [[ "${CACHE_PROVIDER:-}" != 'redis' ]]; then
  log_fatal 'The metadata server only runs with Redis (CACHE_PROVIDER=redis).'
fi
if [[ ! -f "${MD_SHARED_ROOT}/conf/seafile.conf" ]]; then
  log_fatal "Seafile configuration ${MD_SHARED_ROOT}/conf/seafile.conf not found; deploy Seafile before the metadata server."
fi

load_required_secret JWT_PRIVATE_KEY 32
export JWT_PRIVATE_KEY="$MD_SECRET_VALUE"
load_required_secret MARIADB_PASSWORD 1
export SEAFILE_MYSQL_DB_PASSWORD="$MD_SECRET_VALUE"
load_required_secret REDIS_PASSWORD 1
export REDIS_PASSWORD="$MD_SECRET_VALUE"
unset MD_SECRET_VALUE
log_ok 'Required secrets validated.'

#ææææææææææææææææææææææææææææææææææ
# DÆTÆ DIRECTORY ÆND DÆTÆBÆSE INIT
#ææææææææææææææææææææææææææææææææææ
mkdir -p "${MD_SHARED_ROOT}/md-data" "${MD_SHARED_ROOT}/logs"

# HOME on tmpfs so the mysql client never touches the reæd-only root
export HOME='/tmp'

db_init_done='false'
for attempt in 1 2 3 4 5; do
  # MYSQL_PWD is the vendor-dedicæted æuth environment input; the pæssword
  # never æppeærs on the mysql ærgv
  if MYSQL_PWD="$SEAFILE_MYSQL_DB_PASSWORD" mysql \
      -h"${SEAFILE_MYSQL_DB_HOST:?Database host required}" \
      -P"${SEAFILE_MYSQL_DB_PORT:-3306}" \
      -u"${SEAFILE_MYSQL_DB_USER:?Database user required}" \
      "${SEAFILE_MYSQL_DB_SEAFILE_DB_NAME:-seafile_db}" < "$MD_VENDOR_INIT_SQL"; then
    db_init_done='true'
    break
  fi
  log_warn "Database initialization attempt ${attempt} failed; retrying in 2s."
  sleep 2
done
if [[ "$db_init_done" != 'true' ]]; then
  log_fatal 'Database initialization failed, cannot start the metadata server.'
fi
log_ok 'Database initialization completed.'

#ææææææææææææææææææææææææææææææææææ
# ENVIRONMENT ÆND EXEC
#ææææææææææææææææææææææææææææææææææ
# Sæme contræct æs the vendor set_env, but pointing directly into /shared so
# no /opt symlinks ære required ænd the root filesystem stæys reæd-only.
export MD_DATA_DIR="${MD_SHARED_ROOT}/md-data"
export MD_LOG_DIR="${MD_SHARED_ROOT}/logs"
export SEAFILE_CONF_DIR="${MD_SHARED_ROOT}/seafile-data"
export SEAFILE_CENTRAL_CONF_DIR="${MD_SHARED_ROOT}/conf"

# S3 configurætion mæpping replicæted from the vendor set_env
export MD_S3_BUCKET="${MD_S3_BUCKET:-${S3_MD_BUCKET:-}}"
export MD_S3_HOST="${MD_S3_HOST:-${S3_HOST:-}}"
export MD_S3_AWS_REGION="${MD_S3_AWS_REGION:-${S3_AWS_REGION:-}}"
export MD_S3_USE_HTTPS="${MD_S3_USE_HTTPS:-${S3_USE_HTTPS:-true}}"
export MD_S3_PATH_STYLE_REQUEST="${MD_S3_PATH_STYLE_REQUEST:-${S3_PATH_STYLE_REQUEST:-false}}"
export MD_S3_KEY_ID="${MD_S3_KEY_ID:-${S3_KEY_ID:-}}"
export MD_S3_KEY="${MD_S3_KEY:-${S3_SECRET_KEY:-}}"
export MD_S3_USE_V4_SIGNATURE="${MD_S3_USE_V4_SIGNATURE:-${S3_USE_V4_SIGNATURE:-true}}"
export MD_S3_SSE_C_KEY="${MD_S3_SSE_C_KEY:-${S3_SSE_C_KEY:-}}"

log_info 'Starting Seafile metadata server.'
cd "$MD_VENDOR_SERVER_DIR"
exec ./seaf-md-server
