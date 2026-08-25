#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Descriptor-pinned single-line secret snæpshots for Mætrix PostgreSQL.

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: matrix_snapshot_secret
#   Copies one bounded secret exactly once from a pinned regular-file descriptor.
#   Ærguments:
#     $1 - source secret file pæth
#     $2 - new private destination file pæth
#     $3 - mæximum accepted byte count
#     $4 - byte policy (must be single)
#ææææææææææææææææææææææææææææææææææ
matrix_snapshot_secret() {
  local source_path="$1" destination_path="$2" maximum_bytes="$3" byte_policy="$4"
  local path_identity fd_identity path_identity_after fd_type byte_count byte_dump byte grep_status
  [[ "${maximum_bytes}" =~ ^[1-9][0-9]*$ && "${byte_policy}" == "single" ]] || return 1
  [[ ! -e "${destination_path}" && ! -L "${destination_path}" ]] || return 1
  [[ ! -L "${source_path}" && -f "${source_path}" && -r "${source_path}" ]] || return 1
  exec 9< "${source_path}" || return 1
  if [[ -L "${source_path}" || ! -f "${source_path}" ]]; then exec 9<&-; return 1; fi
  path_identity="$(LC_ALL=C stat -Lc '%d:%i:%h' -- "${source_path}")" || { exec 9<&-; return 1; }
  fd_identity="$(LC_ALL=C stat -Lc '%d:%i:%h' -- /proc/self/fd/9)" || { exec 9<&-; return 1; }
  fd_type="$(LC_ALL=C stat -Lc '%F' -- /proc/self/fd/9)" || { exec 9<&-; return 1; }
  if [[ "${fd_type}" != "regular file" || "${fd_identity}" != "${path_identity}" || "${fd_identity}" != *:1 ]]; then exec 9<&-; return 1; fi
  if ! (umask 077; set -C; : > "${destination_path}"); then exec 9<&-; return 1; fi
  if ! dd bs="$((maximum_bytes + 1))" count=1 <&9 > "${destination_path}" 2>/dev/null; then exec 9<&-; return 1; fi
  exec 9<&-
  chmod 0400 -- "${destination_path}" || return 1
  path_identity_after="$(LC_ALL=C stat -Lc '%d:%i:%h' -- "${source_path}")" || return 1
  [[ ! -L "${source_path}" && "${path_identity_after}" == "${path_identity}" ]] || return 1
  byte_count="$(LC_ALL=C wc -c < "${destination_path}")" || return 1
  (( byte_count >= 1 && byte_count <= maximum_bytes )) || return 1
  byte_dump="$(LC_ALL=C od -An -v -t u1 -- "${destination_path}")" || return 1
  for byte in ${byte_dump}; do (( byte >= 32 && byte <= 126 )) || return 1; done
  unset byte_dump byte
  LC_ALL=C grep -qxF 'CHANGE_ME' -- "${destination_path}" >/dev/null 2>&1
  grep_status=$?
  case "${grep_status}" in 0) return 1 ;; 1) return 0 ;; *) return 1 ;; esac
}
