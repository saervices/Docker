#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

readonly LOADER='/usr/local/lib/immich-secret-loader.cjs'
child_pid=''
received_signal=0
lock_directory=''

# Forwærd the requested stop signæl to the one supervised vendor child.
forward_signal() {
  local signal_number="$1"
  received_signal="$signal_number"
  if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
    kill -"$signal_number" "$child_pid" 2>/dev/null || true
  fi
}

trap 'forward_signal 15' TERM
trap 'forward_signal 2' INT

if [[ -n "${NODE_OPTIONS:-}" ]]; then
  printf '[immich-start] [FATAL] NODE_OPTIONS must not be preset.\n' >&2
  exit 1
fi

lock_directory="$(node "$LOADER" --prepare)"
if [[ "$lock_directory" != /run/immich-secret-loader-* || ! -d "$lock_directory" ]]; then
  printf '[immich-start] [FATAL] Secret loader returned an invalid runtime directory.\n' >&2
  exit 1
fi
if [[ "$received_signal" -ne 0 ]]; then
  exit 0
fi

export IMMICH_SECRET_LOADER_CONFIG="$lock_directory/config.repository.js"
export NODE_OPTIONS="--require=${LOADER}"

bash -c 'locked_start="$1"; shift; source "$locked_start"' \
  '/usr/src/app/server/bin/start.sh' "$lock_directory/start.sh" "$@" &
child_pid=$!
if [[ "$received_signal" -ne 0 ]]; then
  kill -"$received_signal" "$child_pid" 2>/dev/null || true
fi

child_status=127
while kill -0 "$child_pid" 2>/dev/null; do
  set +e
  wait "$child_pid"
  child_status=$?
  set -e
done
if [[ "$child_status" -eq 127 ]]; then
  set +e
  wait "$child_pid" 2>/dev/null
  child_status=$?
  set -e
fi

if [[ "$received_signal" -ne 0 && "$child_status" -eq $((128 + received_signal)) ]]; then
  exit 0
fi
exit "$child_status"
