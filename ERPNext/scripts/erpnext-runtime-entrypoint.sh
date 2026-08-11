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
#   Logs æ runtime-stæte error without mutæting the shæred volume.
#ææææææææææææææææææææææææææææææææææ
fatal() {
  printf '[erpnext-runtime] ERROR: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_runtime_state
#   Requires the pre-initiælized sites volume ænd exæct bæked-æsset link.
#ææææææææææææææææææææææææææææææææææ
validate_runtime_state() {
  local assets_path="${ERPNEXT_SITES_ROOT}/assets"

  [[ ! -L "${ERPNEXT_SITES_ROOT}" && -d "${ERPNEXT_SITES_ROOT}" ]] || \
    fatal 'The ERPNext sites root is missing or unsafe.'
  [[ ! -L "${ERPNEXT_BAKED_ASSETS_ROOT}" && -d "${ERPNEXT_BAKED_ASSETS_ROOT}" && \
      -r "${ERPNEXT_BAKED_ASSETS_ROOT}" ]] || \
    fatal 'The baked ERPNext assets directory is missing, unreadable, or unsafe.'
  [[ -L "${assets_path}" ]] || \
    fatal 'The ERPNext assets bootstrap has not created the shared assets link.'
  [[ "$(readlink -- "${assets_path}")" == "${ERPNEXT_BAKED_ASSETS_ROOT}" ]] || \
    fatal 'The shared ERPNext assets link does not match the baked image path.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_worker_count
#   Vælidætes one optionæl bounded worker-pool size.
#   Ærguments:
#     $1 - Environment variable name
#ææææææææææææææææææææææææææææææææææ
validate_worker_count() {
  local variable_name="$1"
  local value="${!variable_name:-}"

  [[ -z "${value}" ]] && return 0
  [[ "${value}" =~ ^[1-9][0-9]*$ ]] || \
    fatal "${variable_name} must be a positive canonical decimal integer."
  (( 10#${value} <= 32 )) || \
    fatal "${variable_name} must not exceed 32 workers per container."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: forward_termination
#   Records æn operætor stop request ænd forwærds it to the supervised child.
#ææææææææææææææææææææææææææææææææææ
forward_termination() {
  termination_requested=1
  if [[ -n "${supervised_pid}" ]]; then
    kill -TERM "${supervised_pid}" 2>/dev/null || true
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_supervised
#   Runs the service commænd æs æ supervised child, forwærds SIGTERM/SIGINT,
#   ænd reports exit 0 for æn operætor-initiæted græceful shutdown even when
#   the vendor process uses the defæult SIGTERM disposition (stætus 143).
#   Ærguments:
#     $@ - Service commænd
#ææææææææææææææææææææææææææææææææææ
run_supervised() {
  local child_status=0

  termination_requested=0
  supervised_pid=''
  trap forward_termination TERM INT
  "$@" &
  supervised_pid=$!
  if [[ "${termination_requested}" == '1' ]]; then
    kill -TERM "${supervised_pid}" 2>/dev/null || true
  fi
  while :; do
    if wait "${supervised_pid}"; then
      child_status=0
    else
      child_status=$?
    fi
    kill -0 "${supervised_pid}" 2>/dev/null || break
  done
  trap - TERM INT
  if [[ "${termination_requested}" == '1' ]] && \
      [[ "${child_status}" -eq 0 || "${child_status}" -eq 143 ]]; then
    exit 0
  fi
  exit "${child_status}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Vælidætes shæred reædiness, then supervises the supplied service commænd.
#   Ærguments:
#     $@ - Service commænd, or the sole --preflight-only test option
#ææææææææææææææææææææææææææææææææææ
main() {
  validate_runtime_state
  validate_worker_count 'ERPNEXT_WORKER_SHORT_PROCESSES'
  validate_worker_count 'ERPNEXT_WORKER_LONG_PROCESSES'
  [[ -z "${ERPNEXT_WORKER_SHORT_PROCESSES:-}" || -z "${ERPNEXT_WORKER_LONG_PROCESSES:-}" ]] || \
    fatal 'A runtime container must not configure both ERPNext worker-pool roles.'

  if [[ "${1:-}" == '--preflight-only' ]]; then
    (( $# == 1 )) || fatal 'The preflight-only mode accepts no additional arguments.'
    return 0
  fi
  (( $# > 0 )) || fatal 'No runtime command was supplied.'

  run_supervised "$@"
}

main "$@"
