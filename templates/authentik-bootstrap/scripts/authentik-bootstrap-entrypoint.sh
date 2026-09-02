#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -eu
umask 077

readonly bootstrap_helper="${AUTHENTIK_BOOTSTRAP_HELPER:-/usr/local/lib/authentik-bootstrap.py}"
readonly bootstrap_python="${AUTHENTIK_BOOTSTRAP_PYTHON:-/ak-root/.venv/bin/python}"
readonly bootstrap_secret="${AUTHENTIK_BOOTSTRAP_PASSWORD_FILE:-/run/secrets/AUTHENTIK_BOOTSTRAP_PASSWORD}"

if [ "$#" -ne 1 ] || [ "$1" != 'bootstrap' ]; then
  echo "[FATAL] authentik bootstrap entrypoint requires the bootstrap command" >&2
  exit 64
fi

unset AUTHENTIK_BOOTSTRAP_PASSWORD AUTHENTIK_BOOTSTRAP_PASSWORD_HASH AUTHENTIK_BOOTSTRAP_TOKEN

if [ ! -x "$bootstrap_python" ] || [ ! -f "$bootstrap_helper" ] || [ ! -r "$bootstrap_helper" ]; then
  echo "[FATAL] authentik bootstrap runtime contract is unavailable" >&2
  exit 1
fi

exec "$bootstrap_python" "$bootstrap_helper" orchestrate "$bootstrap_secret"
