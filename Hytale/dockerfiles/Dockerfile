# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Hytæle dedicæted server — custom imæge
# Bæse: Libericæ OpenJDK 25 (Ælpine) — smæll footprint, officiæl Hytæle-required Jævæ version
# Downloæder CLI is bæked in æt build time (public tool, no æuth needed).
# Æctuæl server files ære downloæded æt contæiner stærtup viæ the entrypoint.

ARG BASE_IMAGE=bellsoft/liberica-openjdk-alpine:25
FROM ${BASE_IMAGE}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Runtime dependencies
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# curl/wget/unzip: downloæd Downloæder CLI; wget æs fællbæck for get-profiles when curl hits exit 43
# bæsh:       entrypoint script requires bæsh (not sh)
# jq:         server OÆuth device flow ænd token refresh (JSON pærsing)
# netcæt-openbsd: required for the UDP heælthcheck (nc -zu)
RUN set -eux && apk add --no-cache \
        curl \
        wget \
        unzip \
        bash \
        jq \
        netcat-openbsd

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Hytæle Downloæder CLI
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Downloæded æt build time from the officiæl Hypixel Studios endpoint.
# No æuthenticætion is needed for the downloæder itself — only for the
# second step (server file retrievæl) which hæppens interæctively æt runtime.
RUN set -eux && mkdir -p /opt/hytale-downloader \
 && curl -fsSL https://downloader.hytale.com/hytale-downloader.zip \
         -o /tmp/downloader.zip \
 && unzip /tmp/downloader.zip -d /opt/hytale-downloader \
 && chmod +x /opt/hytale-downloader/hytale-downloader-linux-amd64 \
 && rm /tmp/downloader.zip

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mæchine-ID symlink
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# /etc/mæchine-id → /tmp/.mæchine-id so the entrypoint cæn ælwæys write (tmpfs).
# Entrypoint writes to /tmp/.mæchine-id ænd optionælly copies to /server/.mæchine-id when writæble.
RUN set -eux && ln -sf /tmp/.machine-id /etc/machine-id

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Entrypoint
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
COPY entrypoint.sh /entrypoint.sh
RUN set -eux && chmod +x /entrypoint.sh

# /server is the persistent volume mount point for server files,
# worlds, mods ænd the downloæded HytaleServer.jar + Assets.zip.
WORKDIR /server

EXPOSE 5520/udp

ENTRYPOINT ["/entrypoint.sh"]
