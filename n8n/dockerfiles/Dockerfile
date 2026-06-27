# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BUILD ÆRGUMENTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Upstreæm n8n imæge ænd OIDC hooks source — resolved viæ scripts/build-image.sh for production builds
ARG BASE_IMAGE=docker.n8n.io/n8nio/n8n:latest
ARG BASE_IMAGE_REQUESTED=docker.n8n.io/n8nio/n8n:latest
ARG OIDC_HOOKS_REF=main
ARG OIDC_HOOKS_REQUESTED_REF=main
ARG BUILD_DATE=unknown
ARG BUILD_INFO_VERSION=1

FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG BASE_IMAGE_REQUESTED
ARG OIDC_HOOKS_REF
ARG OIDC_HOOKS_REQUESTED_REF
ARG BUILD_DATE
ARG BUILD_INFO_VERSION

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="${BASE_IMAGE_REQUESTED}" \
      org.opencontainers.image.base.digest="${BASE_IMAGE}" \
      de.saervices.n8n.oidc_hooks_ref="${OIDC_HOOKS_REQUESTED_REF}" \
      de.saervices.n8n.oidc_hooks_resolved_ref="${OIDC_HOOKS_REF}" \
      de.saervices.n8n.build_info_version="${BUILD_INFO_VERSION}" \
      de.saervices.n8n.build_info_path="/opt/n8n-oidc/build-info.json"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- OIDC HOOKS INSTÆLL
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Switch to root to creæte directory ænd downloæd the OIDC hooks file
USER root

RUN set -eux \
    && mkdir -p /opt/n8n-oidc \
    && printf '{\n  "build_info_version": "%s",\n  "build_date": "%s",\n  "base_image_requested": "%s",\n  "base_image_resolved": "%s",\n  "oidc_hooks_requested_ref": "%s",\n  "oidc_hooks_resolved_ref": "%s",\n  "oidc_hooks_file": "/hooks/hooks.js"\n}\n' \
       "${BUILD_INFO_VERSION}" \
       "${BUILD_DATE}" \
       "${BASE_IMAGE_REQUESTED}" \
       "${BASE_IMAGE}" \
       "${OIDC_HOOKS_REQUESTED_REF}" \
       "${OIDC_HOOKS_REF}" \
       > /opt/n8n-oidc/build-info.json \
    && chown -R node:node /opt/n8n-oidc \
    && chmod 755 /opt/n8n-oidc \
    && chmod 644 /opt/n8n-oidc/build-info.json

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
