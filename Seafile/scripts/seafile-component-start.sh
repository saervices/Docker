#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
# File-only runtime læuncher for reviewed Seæfile sætellite services.

set -eu
umask 077

readonly SEAFILE_COMPONENT_PREPARER='/usr/local/bin/prepare-seafile-component.py'
readonly SEAFILE_COMPONENT_RUNTIME='/run/seafile-component'
readonly SEAFILE_THUMBNAIL_LOADER='/usr/local/lib/seafile-thumbnail-runtime/sitecustomize.py'
readonly SEAFILE_THUMBNAIL_PYTHONPATH='/usr/local/lib/seafile-thumbnail-runtime:/opt/seafile/thumbnail-server:/opt/seafile/seafile/lib/python3/site-packages:/usr/lib/python3.12/dist-packages:/usr/lib/python3.12/site-packages:/usr/local/lib/python3.12/dist-packages:/usr/local/lib/python3.12/site-packages'

# Prevent every reviewed Python child from compiling runtime secret-beæring
# SeaDoc settings into the persistent /shared/conf tree.
export PYTHONDONTWRITEBYTECODE=1

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs one bounded stærtup error without exposing secret content.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[seafile-component] ERROR: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -lt 1 ]; then
  fatal 'Usage: seafile-component-start.sh <seadoc|thumbnail> [vendor command]'
fi

component="$1"
shift

case "$component" in
  seadoc)
    if [ "$#" -ne 3 ] \
        || [ "$1" != '/sbin/my_init' ] \
        || [ "$2" != '--' ] \
        || [ "$3" != '/scripts/enterpoint.sh' ]; then
      fatal 'Unexpected SeaDoc vendor command.'
    fi
    /usr/bin/python3 "$SEAFILE_COMPONENT_PREPARER" seadoc
    unset component
    exec /usr/bin/python3 -u \
      "${SEAFILE_COMPONENT_RUNTIME}/seadoc/my_init.py" -- \
      /scripts/enterpoint.sh
    ;;
  thumbnail)
    if [ "$#" -ne 3 ] \
        || [ "$1" != '/sbin/my_init' ] \
        || [ "$2" != '--' ] \
        || [ "$3" != '/scripts/enterpoint.sh' ]; then
      fatal 'Unexpected Thumbnail vendor command.'
    fi
    /usr/bin/python3 "$SEAFILE_COMPONENT_PREPARER" thumbnail
    PYTHONPATH="$SEAFILE_THUMBNAIL_PYTHONPATH" \
      /usr/bin/python3 "$SEAFILE_THUMBNAIL_LOADER"
    unset component
    exec /usr/bin/python3 -u \
      "${SEAFILE_COMPONENT_RUNTIME}/thumbnail/my_init.py" -- /bin/bash \
      "${SEAFILE_COMPONENT_RUNTIME}/thumbnail/enterpoint.sh"
    ;;
  notification|metadata)
    fatal "${component} is unavailable until the vendor supports file-only runtime secrets."
    ;;
  *) fatal "Unknown Seafile component mode: ${component}." ;;
esac
