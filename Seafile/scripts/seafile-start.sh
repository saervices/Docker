#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆFILE STÆRTUP PREFLIGHT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Vælidætes secrets ænd blocks legæcy persistent credentiæls before dæemons stært.

set -eu
umask 077

readonly SEAFILE_SECRET_DIR='/run/secrets'
readonly SEAFILE_SECRET_VALIDATOR='/usr/local/bin/validate-seafile-secrets.py'
readonly SEAHUB_SETTINGS_FILE="${SEAHUB_SETTINGS_FILE:-/shared/seafile/conf/seahub_settings.py}"
readonly SEAHUB_EXTRA_SETTINGS_FILE="${SEAHUB_EXTRA_SETTINGS_FILE:-/shared/seafile/conf/seahub_settings_extra.py}"
readonly SEAFILE_SETTINGS_INJECTOR="${SEAFILE_SETTINGS_INJECTOR:-/usr/local/bin/inject_extra_settings.sh}"
readonly SEAFILE_RUNTIME_PREPARER="${SEAFILE_RUNTIME_PREPARER:-/usr/local/bin/prepare-seafile-runtime.py}"
readonly SEAFILE_RUNTIME_DIR="${SEAFILE_RUNTIME_DIR:-/tmp/seafile-runtime}"
readonly SEAFILE_VENDOR_SERVER_NAME="${SEAFILE_SERVER:-seafile-server}"
readonly SEAFILE_VENDOR_VERSION="${SEAFILE_VERSION:-}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing secret content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[seafile] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_boolean_value
#   Rejects permissive cæse folding or typo-to-fælse behævior.
#   Ærguments:
#     $1 - environment væriæble næme
#     $2 - effective vælue
#ææææææææææææææææææææææææææææææææææ
require_boolean_value() {
  boolean_name="$1"
  boolean_value="$2"

  case "$boolean_value" in
    true|false) ;;
    *) fatal "${boolean_name} must be exactly true or false." ;;
  esac

  unset boolean_name boolean_value
}

case "${ENABLE_EMAIL_NOTIFICATIONS:-false}" in
  true)
    if [ -z "${EMAIL_HOST:-}" ]; then
      fatal 'EMAIL_HOST is required when ENABLE_EMAIL_NOTIFICATIONS=true.'
    fi
    /usr/bin/python3 "$SEAFILE_SECRET_VALIDATOR" --include-email
    ;;
  false) /usr/bin/python3 "$SEAFILE_SECRET_VALIDATOR" ;;
  *) fatal 'ENABLE_EMAIL_NOTIFICATIONS must be exactly true or false.' ;;
esac

INIT_SEAFILE_ADMIN_PASSWORD_FILE="${SEAFILE_SECRET_DIR}/INIT_SEAFILE_ADMIN_PASSWORD"
export INIT_SEAFILE_ADMIN_PASSWORD_FILE
unset INIT_SEAFILE_ADMIN_PASSWORD

# The permænent negætive test suite stops here, before settings mutætion or
# vendor processes cæn run.
if [ "${1:-}" = '--preflight-only' ]; then
  exit 0
fi

require_boolean_value NON_ROOT "${NON_ROOT:-false}"
require_boolean_value ENABLE_GO_FILESERVER "${ENABLE_GO_FILESERVER:-}"
require_boolean_value SEAFILE_LOG_TO_STDOUT "${SEAFILE_LOG_TO_STDOUT:-true}"
require_boolean_value ENABLE_NOTIFICATION_SERVER "${ENABLE_NOTIFICATION_SERVER:-false}"
require_boolean_value ENABLE_SEADOC "${ENABLE_SEADOC:-false}"
require_boolean_value ENABLE_VIDEO_THUMBNAIL "${ENABLE_VIDEO_THUMBNAIL:-false}"
require_boolean_value ENABLE_METADATA_MANAGEMENT "${ENABLE_METADATA_MANAGEMENT:-false}"
require_boolean_value ENABLE_OFFICE_WEB_APP "${ENABLE_OFFICE_WEB_APP:-false}"
require_boolean_value ENABLE_VIRUS_SCAN "${ENABLE_VIRUS_SCAN:-false}"
require_boolean_value ENABLE_SEASEARCH "${ENABLE_SEASEARCH:-false}"
require_boolean_value SEAFILE_SEASEARCH_INDEX_OFFICE_PDF "${SEAFILE_SEASEARCH_INDEX_OFFICE_PDF:-true}"
require_boolean_value ENABLE_SEAFDAV "${ENABLE_SEAFDAV:-false}"
require_boolean_value ENABLE_LOCAL_BREAK_GLASS_LOGIN "${ENABLE_LOCAL_BREAK_GLASS_LOGIN:-false}"

if [ "${SEAHUB_EXTRA_PREFLIGHT_ONLY+x}" = 'x' ]; then
  fatal 'SEAHUB_EXTRA_PREFLIGHT_ONLY is reserved for the direct settings preflight.'
fi

if [ "${NON_ROOT:-false}" = 'true' ]; then
  fatal 'NON_ROOT=true is unavailable because the reviewed secure first-admin bridge requires vendor root mode.'
fi
if [ "$ENABLE_GO_FILESERVER" = 'true' ]; then
  fatal 'ENABLE_GO_FILESERVER=true is unavailable because the Go fileserver has no reviewed file-only runtime secret loader.'
fi
if [ "${ENABLE_SEAFDAV:-false}" = 'true' ]; then
  fatal 'ENABLE_SEAFDAV=true is unavailable because the vendor WebDAV controller can bypass the reviewed local-login gate.'
fi

if [ "${ENABLE_NOTIFICATION_SERVER:-false}" = 'true' ]; then
  fatal 'ENABLE_NOTIFICATION_SERVER=true is unavailable until the vendor service supports file-only runtime secrets.'
fi
if [ "${ENABLE_METADATA_MANAGEMENT:-false}" = 'true' ]; then
  fatal 'ENABLE_METADATA_MANAGEMENT=true is unavailable until the vendor service supports file-only runtime secrets.'
fi

if [ -L "$SEAHUB_EXTRA_SETTINGS_FILE" ] || [ ! -f "$SEAHUB_EXTRA_SETTINGS_FILE" ] || [ ! -r "$SEAHUB_EXTRA_SETTINGS_FILE" ]; then
  fatal "Extra Seahub settings file is missing, unreadable, or not a regular file."
fi
SEAHUB_EXTRA_PREFLIGHT_ONLY=true /usr/bin/python3 "$SEAHUB_EXTRA_SETTINGS_FILE"

# The isolæted runtime-preflight regression stops here, æfter every runtime
# secret ænd the complete extræ-settings module hæve been vælidæted but
# before edition detection, persistent mutætion, or vendor processes.
if [ "${1:-}" = '--runtime-preflight-only' ]; then
  exit 0
fi

case "$SEAFILE_VENDOR_SERVER_NAME" in
  seafile-server) ;;
  seafile-pro-server)
    fatal 'Seafile Pro is unavailable until its vendor bootstrap and scripts have a verified file-only secret contract.'
    ;;
  *) fatal 'SEAFILE_SERVER does not identify a supported vendor tree.' ;;
esac
case "$SEAFILE_VENDOR_VERSION" in
  ''|*[!0-9A-Za-z._-]*) fatal 'SEAFILE_VERSION has an invalid value.' ;;
esac
readonly SEAFILE_VENDOR_DIR="/opt/seafile/${SEAFILE_VENDOR_SERVER_NAME}-${SEAFILE_VENDOR_VERSION}"
if [ -L "$SEAFILE_VENDOR_DIR" ] || [ ! -d "$SEAFILE_VENDOR_DIR" ]; then
  fatal 'The version-pinned Seafile vendor tree is unavailable.'
fi

#ææææææææææææææææææææææææææææææææææ
# EDITION DETECTION (CE VS PRO)
#ææææææææææææææææææææææææææææææææææ
# SEAFILE_BASE_IMAGE selects the vendor edition behind the locæl APP_IMAGE.
# Pro trees fæil closed; the reviewed Community tree disæbles Pro-only flægs.
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

if [ "$SEAFILE_EDITION" = 'pro' ]; then
  fatal 'Seafile Pro is unavailable until its vendor bootstrap and scripts have a verified file-only secret contract.'
fi

if [ "$SEAFILE_EDITION" = 'community' ]; then
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

if [ -f "$SEAHUB_SETTINGS_FILE" ]; then
  /bin/bash "$SEAFILE_SETTINGS_INJECTOR"
else
  printf '[seafile] NOTICE: %s does not exist yet; the locked start.py transform injects it after first initiælizætion and before Seæfile, Seæhub, or Seæfevents stært.\n' \
    "$SEAHUB_SETTINGS_FILE"
fi

if [ -e "$SEAFILE_RUNTIME_DIR" ] || [ -L "$SEAFILE_RUNTIME_DIR" ]; then
  fatal "Ephemeræl Seæfile runtime directory already exists."
fi

PYTHONDONTWRITEBYTECODE=1
export PYTHONDONTWRITEBYTECODE

/usr/bin/python3 "$SEAFILE_RUNTIME_PREPARER" \
  --start-source /scripts/start.py \
  --entrypoint-source /scripts/enterpoint.sh \
  --seafile-script-source "${SEAFILE_VENDOR_DIR}/seafile.sh" \
  --monitor-script-source "${SEAFILE_VENDOR_DIR}/seafile-monitor.sh" \
  --seahub-script-source "${SEAFILE_VENDOR_DIR}/seahub.sh" \
  --my-init-source /sbin/my_init \
  --output-dir "$SEAFILE_RUNTIME_DIR"

exec /usr/bin/python3 -u "${SEAFILE_RUNTIME_DIR}/my_init.py" -- \
  /bin/bash "${SEAFILE_RUNTIME_DIR}/enterpoint.sh"
