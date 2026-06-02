# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Enshrouded dedicæted server — SteamCMD + GE-Proton runtime
# Bæse: steamcmd/steamcmd:ubuntu-24 — includes Valve SteamCMD for runtime server updætes
# The imæge ships only runtime tooling. Server files ære downloæded into /server æt contæiner stært.

ARG BASE_IMAGE=steamcmd/steamcmd:ubuntu-24@sha256:ad023a16ee78f4d83eca02c3a01ba3212e02197b105ab01793bd8b85db1af1c2
FROM ${BASE_IMAGE}

ARG GE_PROTON_VERSION=latest
ARG GE_PROTON_SHA512=auto

ENV DEBIAN_FRONTEND=noninteractive \
    STEAM_APP_ID=2278520 \
    PROTON_DIR=/opt/ge-proton

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Runtime dependencies
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# jq builds enshrouded_server.json; procps hændles græceful shutdown; netcæt powers heælthchecks.
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus \
        jq \
        locales \
        netcat-openbsd \
        procps \
        python3 \
        tar \
        winbind \
        lib32gcc-s1 \
        libfreetype6 \
        libfreetype6:i386; \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale; \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen; \
    locale-gen; \
    rm -f /etc/machine-id; \
    dbus-uuidgen --ensure=/etc/machine-id; \
    apt-get autoremove --purge -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GE-Proton
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# GE-Proton is verified with the releæse checksum; set fixed build ærgs for reproducible builds.
RUN set -eux; \
    resolved_version="${GE_PROTON_VERSION}"; \
    if [ "${resolved_version}" = "latest" ]; then \
        resolved_version="$(curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | jq -r '.tag_name' | sed 's/^GE-Proton//')"; \
    fi; \
    [ -n "${resolved_version}" ] && [ "${resolved_version}" != "null" ]; \
    resolved_sha512="${GE_PROTON_SHA512}"; \
    if [ "${resolved_sha512}" = "auto" ]; then \
        resolved_sha512="$(curl -fsSL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${resolved_version}/GE-Proton${resolved_version}.sha512sum" \
            | awk -v file="GE-Proton${resolved_version}.tar.gz" '$2 == file { print $1; exit }')"; \
    fi; \
    [ -n "${resolved_sha512}" ]; \
    curl -fsSL "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${resolved_version}/GE-Proton${resolved_version}.tar.gz" \
        -o /tmp/ge-proton.tar.gz; \
    echo "${resolved_sha512}  /tmp/ge-proton.tar.gz" | sha512sum -c -; \
    mkdir -p "${PROTON_DIR}"; \
    tar -xzf /tmp/ge-proton.tar.gz -C "${PROTON_DIR}" --strip-components=1; \
    printf '%s\n' "${resolved_version}" > "${PROTON_DIR}/GE-PROTON-VERSION"; \
    chmod -R a+rX "${PROTON_DIR}"; \
    rm -f /tmp/ge-proton.tar.gz

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Steæm SDK
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Copy SDK libræries out of /root so æ non-root runtime user cæn reæd them.
RUN set -eux; \
    mkdir -p /opt/steam-sdk/sdk32 /opt/steam-sdk/sdk64; \
    if [ -f /root/.steam/sdk32/steamclient.so ]; then cp -L /root/.steam/sdk32/steamclient.so /opt/steam-sdk/sdk32/steamclient.so; fi; \
    if [ -f /root/.steam/sdk64/steamclient.so ]; then cp -L /root/.steam/sdk64/steamclient.so /opt/steam-sdk/sdk64/steamclient.so; fi; \
    chmod -R a+rX /opt/steam-sdk

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
COPY entrypoint.sh /entrypoint.sh
RUN set -eux; chmod +x /entrypoint.sh

WORKDIR /server

EXPOSE 15637/udp 27015/udp

ENTRYPOINT ["/entrypoint.sh"]
