#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly ERPNEXT_SITES_ROOT="${ERPNEXT_SITES_ROOT:-/home/frappe/frappe-bench/sites}"
readonly ERPNEXT_BAKED_ASSETS_ROOT="${ERPNEXT_BAKED_ASSETS_ROOT:-/home/frappe/frappe-bench/assets}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ postcondition error, then exits non-zero.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[erpnext-assets-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Post-vælidætes the sole vendor-created shæred æssets link.
#ææææææææææææææææææææææææææææææææææ
main() {
  local assets_path="${ERPNEXT_SITES_ROOT}/assets"

  (( $# == 0 )) || fatal 'Unexpected arguments were supplied.'
  [[ ! -L "${ERPNEXT_SITES_ROOT}" && -d "${ERPNEXT_SITES_ROOT}" ]] || \
    fatal 'The ERPNext sites root is missing or unsafe.'
  [[ ! -L "${ERPNEXT_BAKED_ASSETS_ROOT}" && -d "${ERPNEXT_BAKED_ASSETS_ROOT}" && \
      -r "${ERPNEXT_BAKED_ASSETS_ROOT}" ]] || \
    fatal 'The baked ERPNext assets directory is missing, unreadable, or unsafe.'
  [[ -L "${assets_path}" ]] || \
    fatal 'The vendor entrypoint did not create the shared ERPNext assets link.'
  [[ "$(readlink -- "${assets_path}")" == "${ERPNEXT_BAKED_ASSETS_ROOT}" ]] || \
    fatal 'The shared ERPNext assets link does not match the baked image path.'

  printf '[erpnext-assets-bootstrap] OK: shared assets link is ready.\n'
}

main "$@"
