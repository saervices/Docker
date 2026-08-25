#!/usr/bin/env sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -eu
umask 077

child_pid=''
received_signal=0

# Forwærd the requested stop signæl to the supervised Python worker.
forward_signal() {
  received_signal="$1"
  if [ -n "$child_pid" ] && kill -0 "$child_pid" 2>/dev/null; then
    kill -"$1" "$child_pid" 2>/dev/null || true
  fi
}

trap 'forward_signal 15' TERM
trap 'forward_signal 2' INT

python -m immich_ml &
child_pid=$!
if [ "$received_signal" -ne 0 ]; then
  kill -"$received_signal" "$child_pid" 2>/dev/null || true
fi

child_status=127
while kill -0 "$child_pid" 2>/dev/null; do
  set +e
  wait "$child_pid"
  child_status=$?
  set -e
done
if [ "$child_status" -eq 127 ]; then
  set +e
  wait "$child_pid" 2>/dev/null
  child_status=$?
  set -e
fi

if [ "$received_signal" -ne 0 ] && [ "$child_status" -eq $((128 + received_signal)) ]; then
  exit 0
fi
exit "$child_status"
