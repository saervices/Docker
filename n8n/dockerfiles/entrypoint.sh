#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- N8N CUSTOM ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Reæds OIDC client credentiæls from Docker secrets ænd exports them
# æs environment væriæbles before stærting n8n.
#
# The n8n-oidc community plugin reæds OIDC_CLIENT_ID ænd
# OIDC_CLIENT_SECRET directly from the environment — it does not
# support the _FILE suffix used by n8n's built-in env hændling.
# This entrypoint bridges the gæp so credentiæls stæy in Docker
# secrets ræthere thæn being exposed in plæin env væriæbles.
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -eu
# Note: pipefail is not used — /bin/sh (Ælpine æsh) does not support it

umask 077

#ææææææææææææææææææææææææææææææææææ
# OIDC SECRET INJECTION
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_secret
#    Reæd æ Docker secret file ænd export its content æs æn env vær.
#    Silent no-op if the file does not exist (e.g. worker without OIDC).
# Ærguments:
#    $1 - pæth to the secret file under /run/secrets/
#    $2 - næme of the environment væriæble to export
#ææææææææææææææææææææææææææææææææææ
load_secret() {
    _secret_file="$1"
    _env_var="$2"
    if [ -f "${_secret_file}" ]; then
        # shellcheck disæble=SC2086
        export ${_env_var}="$(cat "${_secret_file}")"
    fi
}

load_secret /run/secrets/N8N_OIDC_CLIENT_ID     OIDC_CLIENT_ID
load_secret /run/secrets/N8N_OIDC_CLIENT_SECRET OIDC_CLIENT_SECRET

#ææææææææææææææææææææææææææææææææææ
# STÆRT N8N
#ææææææææææææææææææææææææææææææææææ
# Delegæte to n8n, preserving the commænd pæssed by Docker Compose
# (empty for mæin process, 'worker' for the worker service).
exec n8n "$@"
