#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# POSIX descriptor-pinned secret snæpshots for the Ælpine LiveKit imæge.

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: matrix_snapshot_secret
#   Copies one bounded ASCII secret exactly once from a pinned descriptor.
#   Ærguments:
#     $1 - source secret file pæth
#     $2 - new private destination file pæth
#     $3 - mæximum accepted byte count
#     $4 - byte policy (must be single)
#ææææææææææææææææææææææææææææææææææ
matrix_snapshot_secret() {
  matrix_source_path="$1"
  matrix_destination_path="$2"
  matrix_maximum_bytes="$3"
  matrix_byte_policy="$4"
  case "${matrix_maximum_bytes}" in ''|*[!0-9]*|0) return 1 ;; esac
  [ "${matrix_byte_policy}" = single ] || return 1
  [ ! -e "${matrix_destination_path}" ] && [ ! -L "${matrix_destination_path}" ] || return 1
  [ ! -L "${matrix_source_path}" ] && [ -f "${matrix_source_path}" ] && [ -r "${matrix_source_path}" ] || return 1
  exec 9< "${matrix_source_path}" || return 1
  if [ -L "${matrix_source_path}" ] || [ ! -f "${matrix_source_path}" ]; then exec 9<&-; return 1; fi
  matrix_path_identity="$(LC_ALL=C stat -L -c '%d:%i:%h' "${matrix_source_path}")" || { exec 9<&-; return 1; }
  matrix_fd_identity="$(LC_ALL=C stat -L -c '%d:%i:%h' /proc/self/fd/9)" || { exec 9<&-; return 1; }
  matrix_fd_type="$(LC_ALL=C stat -L -c '%F' /proc/self/fd/9)" || { exec 9<&-; return 1; }
  if [ "${matrix_fd_type}" != "regular file" ] || [ "${matrix_fd_identity}" != "${matrix_path_identity}" ]; then exec 9<&-; return 1; fi
  case "${matrix_fd_identity}" in *:1) : ;; *) exec 9<&-; return 1 ;; esac
  if ! (umask 077; set -C; : > "${matrix_destination_path}"); then exec 9<&-; return 1; fi
  if ! dd bs="$((matrix_maximum_bytes + 1))" count=1 <&9 > "${matrix_destination_path}" 2>/dev/null; then exec 9<&-; return 1; fi
  exec 9<&-
  chmod 0400 "${matrix_destination_path}" || return 1
  matrix_path_identity_after="$(LC_ALL=C stat -L -c '%d:%i:%h' "${matrix_source_path}")" || return 1
  [ ! -L "${matrix_source_path}" ] && [ "${matrix_path_identity_after}" = "${matrix_path_identity}" ] || return 1
  matrix_byte_count="$(LC_ALL=C wc -c < "${matrix_destination_path}")" || return 1
  [ "${matrix_byte_count}" -ge 1 ] && [ "${matrix_byte_count}" -le "${matrix_maximum_bytes}" ] || return 1
  matrix_byte_dump="$(LC_ALL=C od -An -v -t u1 "${matrix_destination_path}")" || return 1
  for matrix_byte in ${matrix_byte_dump}; do
    [ "${matrix_byte}" -ge 32 ] && [ "${matrix_byte}" -le 126 ] || return 1
  done
  unset matrix_byte_dump matrix_byte
  LC_ALL=C grep -qxF 'CHANGE_ME' "${matrix_destination_path}" >/dev/null 2>&1
  matrix_grep_status=$?
  case "${matrix_grep_status}" in 0) return 1 ;; 1) return 0 ;; *) return 1 ;; esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: matrix_yaml_squote
#   Prints one ASCII string æs a YAML single-quoted scalar without tools.
#   Ærguments:
#     $1 - validated string value
#ææææææææææææææææææææææææææææææææææ
matrix_yaml_squote() {
  matrix_yaml_value="$1"
  printf "'"
  while [ -n "${matrix_yaml_value}" ]; do
    matrix_yaml_rest="${matrix_yaml_value#?}"
    matrix_yaml_character="${matrix_yaml_value%"${matrix_yaml_rest}"}"
    if [ "${matrix_yaml_character}" = "'" ]; then printf "''"; else printf '%s' "${matrix_yaml_character}"; fi
    matrix_yaml_value="${matrix_yaml_rest}"
  done
  printf "'"
}
