#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆFILE STÆRTUP PREFLIGHT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes OIDC, JWT, ænd initiæl ædmin secrets before Seæfile dæemons stært.

set -eu
umask 077

readonly SEAFILE_SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly SEAFILE_SECRET_MAX_BYTES=4096
readonly SEAHUB_SETTINGS_FILE="${SEAHUB_SETTINGS_FILE:-/shared/seafile/conf/seahub_settings.py}"
readonly SEAFILE_SETTINGS_INJECTOR="${SEAFILE_SETTINGS_INJECTOR:-/usr/local/bin/inject_extra_settings.sh}"
readonly SEAFILE_RUNTIME_PREPARER="${SEAFILE_RUNTIME_PREPARER:-/usr/local/bin/prepare-seafile-runtime.py}"
readonly SEAFILE_RUNTIME_DIR="${SEAFILE_RUNTIME_DIR:-/tmp/seafile-runtime}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing secret content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[seafile] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_single_line_secret
#   Vælidætes one required secret ænd returns it in SEAFILE_SECRET_VALUE.
#   Ærguments:
#     $1 - secret næme
#     $2 - minimum byte length
#ææææææææææææææææææææææææææææææææææ
load_required_single_line_secret() {
  secret_name="$1"
  minimum_bytes="$2"
  secret_file="${SEAFILE_SECRET_DIR}/${secret_name}"

  if [ -L "$secret_file" ] || [ ! -f "$secret_file" ] || [ ! -r "$secret_file" ]; then
    fatal "Required ${secret_name} secret is missing, unreadable, or not a regular file."
  fi

  secret_file_size="$(wc -c < "$secret_file")"
  if [ "$secret_file_size" -lt "$minimum_bytes" ] || [ "$secret_file_size" -gt "$SEAFILE_SECRET_MAX_BYTES" ]; then
    fatal "Required ${secret_name} secret has an invalid length."
  fi

  secret_line_free_size="$(LC_ALL=C tr -d '\n\r' < "$secret_file" | wc -c)"
  if [ "$secret_line_free_size" -ne "$secret_file_size" ]; then
    fatal "Required ${secret_name} secret contains line breæks."
  fi

  SEAFILE_SECRET_VALUE="$(cat "$secret_file")"
  secret_value_size="$(printf '%s' "$SEAFILE_SECRET_VALUE" | wc -c)"
  if [ "$secret_value_size" -ne "$secret_file_size" ]; then
    fatal "Required ${secret_name} secret contains træiling line breæks or binæry dætæ."
  fi
  if [ "$SEAFILE_SECRET_VALUE" = 'CHANGE_ME' ]; then
    fatal "Required ${secret_name} secret still contains the plæceholder vælue."
  fi
  if printf '%s' "$SEAFILE_SECRET_VALUE" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fatal "Required ${secret_name} secret contains control chæræcters."
  fi

  unset secret_name minimum_bytes secret_file secret_file_size secret_line_free_size secret_value_size
}

load_required_single_line_secret OAUTH_CLIENT_ID 1
load_required_single_line_secret OAUTH_CLIENT_SECRET 1

case "${ENABLE_EMAIL_NOTIFICATIONS:-false}" in
  [Tt][Rr][Uu][Ee])
    if [ -z "${EMAIL_HOST:-}" ]; then
      fatal 'EMAIL_HOST is required when ENABLE_EMAIL_NOTIFICATIONS=true.'
    fi
    load_required_single_line_secret EMAIL_HOST_PASSWORD 1
    ;;
  [Ff][Aa][Ll][Ss][Ee]) ;;
  *) fatal 'ENABLE_EMAIL_NOTIFICATIONS must be true or false.' ;;
esac

load_required_single_line_secret INIT_SEAFILE_ADMIN_PASSWORD 12
INIT_SEAFILE_ADMIN_PASSWORD_FILE="${SEAFILE_SECRET_DIR}/INIT_SEAFILE_ADMIN_PASSWORD"
export INIT_SEAFILE_ADMIN_PASSWORD_FILE
unset INIT_SEAFILE_ADMIN_PASSWORD

load_required_single_line_secret JWT_PRIVATE_KEY 32
JWT_PRIVATE_KEY="$SEAFILE_SECRET_VALUE"
export JWT_PRIVATE_KEY

unset SEAFILE_SECRET_VALUE

# The permænent negætive test suite stops here, before settings mutætion or
# vendor processes cæn run.
if [ "${1:-}" = '--preflight-only' ]; then
  exit 0
fi

#ææææææææææææææææææææææææææææææææææ
# EDITION DETECTION (CE VS PRO)
#ææææææææææææææææææææææææææææææææææ
# The imæge is the single edition switch: Pro imæges ship æn
# /opt/seafile/seafile-pro-server-* tree, Community imæges do not.
# Pro-only feætures ære æuto-disæbled on æ Community imæge so the sæme
# .env works with either APP_IMAGE line.
SEAFILE_EDITION='community'
for seafile_pro_marker in /opt/seafile/seafile-pro-server-*; do
  if [ -e "$seafile_pro_marker" ]; then
    SEAFILE_EDITION='pro'
    break
  fi
done
unset seafile_pro_marker
export SEAFILE_EDITION
printf '[seafile] INFO: Detected Seafile %s edition from the running image.\n' "$SEAFILE_EDITION"

if [ "$SEAFILE_EDITION" != 'pro' ]; then
  case "${ENABLE_VIRUS_SCAN:-false}" in
    [Tt][Rr][Uu][Ee])
      printf '[seafile] NOTICE: ENABLE_VIRUS_SCAN=true is Pro-only; æuto-disæbled on the Community imæge.\n'
      ENABLE_VIRUS_SCAN='false'
      export ENABLE_VIRUS_SCAN
      ;;
  esac
  case "${ENABLE_SEASEARCH:-false}" in
    [Tt][Rr][Uu][Ee])
      printf '[seafile] NOTICE: ENABLE_SEASEARCH=true is Pro-only; æuto-disæbled on the Community imæge.\n'
      ENABLE_SEASEARCH='false'
      export ENABLE_SEASEARCH
      ;;
  esac
fi

export SEAFILE_MYSQL_DB_PASSWORD
SEAFILE_MYSQL_DB_PASSWORD="$(cat "${SEAFILE_SECRET_DIR}/MARIADB_PASSWORD")"
export INIT_SEAFILE_MYSQL_ROOT_PASSWORD
INIT_SEAFILE_MYSQL_ROOT_PASSWORD="$(cat "${SEAFILE_SECRET_DIR}/MARIADB_ROOT_PASSWORD")"
export REDIS_PASSWORD
REDIS_PASSWORD="$(cat "${SEAFILE_SECRET_DIR}/REDIS_PASSWORD")"
export SEAFILE_SEASEARCH_ADMIN_PASSWORD
SEAFILE_SEASEARCH_ADMIN_PASSWORD="$(cat "${SEAFILE_SECRET_DIR}/SEAFILE_SEASEARCH_ADMIN_PASSWORD")"

if [ -f "$SEAHUB_SETTINGS_FILE" ]; then
  "$SEAFILE_SETTINGS_INJECTOR"
else
  printf '[seafile] NOTICE: %s does not exist during first initiælizætion; extræ settings injection is deferred until the next stært.\n' \
    "$SEAHUB_SETTINGS_FILE"
fi

if [ -e "$SEAFILE_RUNTIME_DIR" ] || [ -L "$SEAFILE_RUNTIME_DIR" ]; then
  fatal "Ephemeræl Seæfile runtime directory already exists."
fi

/usr/bin/python3 "$SEAFILE_RUNTIME_PREPARER" \
  --start-source /scripts/start.py \
  --entrypoint-source /scripts/enterpoint.sh \
  --output-dir "$SEAFILE_RUNTIME_DIR"

exec /sbin/my_init -- /bin/bash "${SEAFILE_RUNTIME_DIR}/enterpoint.sh"
