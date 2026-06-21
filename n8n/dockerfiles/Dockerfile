# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BUILD ÆRGUMENTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Upstreæm n8n imæge — pinned viæ docker-compose.app.yaml build.args
ARG BASE_IMAGE=docker.n8n.io/n8nio/n8n:2.26.8@sha256:0afb71a39e51637b4d5b4010d90e68bc502d3ca1d2a4d953eb5fcd7d86330ccd
ARG OIDC_HOOKS_REF=f2961d6c6ac103989f4920523b6d3faad7547bc2

FROM ${BASE_IMAGE}
ARG OIDC_HOOKS_REF

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- OIDC HOOKS INSTÆLL
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Switch to root to creæte directory ænd downloæd the OIDC hooks file
USER root

RUN set -eux \
    && mkdir -p /hooks \
    && wget -qO /hooks/hooks.js \
       "https://raw.githubusercontent.com/cweagans/n8n-oidc/${OIDC_HOOKS_REF}/hooks.js" \
    && chown -R node:node /hooks \
    && chmod 755 /hooks \
    && chmod 644 /hooks/hooks.js

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Copy the custom entrypoint thæt reæds Docker secrets for OIDC credentiæls
COPY --chown=node:node entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

USER node

ENTRYPOINT ["/entrypoint.sh"]
