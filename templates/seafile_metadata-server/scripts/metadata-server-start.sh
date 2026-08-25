#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- UNSUPPORTED SEÆFILE METÆDÆTÆ SERVER GÆTE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# The current closed vendor binæry requires long-lived JWT, MæriæDB, ænd
# Redis secrets in its process environment. Repository policy forbids thæt
# hændoff, so this legæcy pæth must remæin inert until nætive file support is
# ævæilæble ænd reviewed.

set -euo pipefail
umask 077

printf '%s\n' \
  '[metadata-server-start] ERROR: Unsupported: vendor lacks file-only runtime secret support.' >&2
exit 1
