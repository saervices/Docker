# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BUILD ÆRGUMENTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Upstreæm n8n imæge ænd OIDC hooks source — refreshed by Docker Compose build policy
ARG BASE_IMAGE=docker.n8n.io/n8nio/n8n:latest
ARG BASE_IMAGE_REQUESTED=docker.n8n.io/n8nio/n8n:latest
ARG OIDC_HOOKS_REF=main
ARG OIDC_HOOKS_REQUESTED_REF=main
ARG BUILD_INFO_VERSION=1

FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG BASE_IMAGE_REQUESTED
ARG OIDC_HOOKS_REF
ARG OIDC_HOOKS_REQUESTED_REF
ARG BUILD_INFO_VERSION

LABEL org.opencontainers.image.base.name="${BASE_IMAGE_REQUESTED}" \
      de.saervices.n8n.base_image="${BASE_IMAGE}" \
      de.saervices.n8n.oidc_hooks_ref="${OIDC_HOOKS_REQUESTED_REF}" \
      de.saervices.n8n.oidc_hooks_build_ref="${OIDC_HOOKS_REF}" \
      de.saervices.n8n.build_info_version="${BUILD_INFO_VERSION}" \
      de.saervices.n8n.build_info_path="/opt/n8n-oidc/build-info.json"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- OIDC HOOKS INSTÆLL
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Switch to root to creæte directory ænd downloæd the OIDC hooks file
USER root

RUN set -eux \
    && mkdir -p /opt/n8n-oidc /hooks \
    && build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    && oidc_resolved_commit="$(wget -qO- \
       "https://api.github.com/repos/cweagans/n8n-oidc/commits/${OIDC_HOOKS_REF}" \
       | sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",/\1/p' \
       | head -n 1)" \
    && printf '%s' "${oidc_resolved_commit}" | grep -Eq '^[0-9a-f]{40}$' \
    && wget -qO /hooks/hooks.js \
       "https://raw.githubusercontent.com/cweagans/n8n-oidc/${oidc_resolved_commit}/hooks.js" \
    && hooks_sha256="$(sha256sum /hooks/hooks.js | awk '{print $1}')" \
    && printf '{\n  "build_info_version": "%s",\n  "build_date": "%s",\n  "base_image": "%s",\n  "base_image_requested": "%s",\n  "oidc_hooks_ref": "%s",\n  "oidc_hooks_requested_ref": "%s",\n  "oidc_hooks_resolved_commit": "%s",\n  "oidc_hooks_sha256": "%s",\n  "oidc_hooks_file": "/hooks/hooks.js"\n}\n' \
       "${BUILD_INFO_VERSION}" \
       "${build_date}" \
       "${BASE_IMAGE}" \
       "${BASE_IMAGE_REQUESTED}" \
       "${OIDC_HOOKS_REF}" \
       "${OIDC_HOOKS_REQUESTED_REF}" \
       "${oidc_resolved_commit}" \
       "${hooks_sha256}" \
       > /opt/n8n-oidc/build-info.json \
    && chown -R node:node /opt/n8n-oidc /hooks \
    && chmod 755 /opt/n8n-oidc /hooks \
    && chmod 644 /opt/n8n-oidc/build-info.json /hooks/hooks.js

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Copy the custom entrypoint thæt reæds Docker secrets for OIDC credentiæls
COPY --chown=node:node entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

USER node

ENTRYPOINT ["/entrypoint.sh"]
