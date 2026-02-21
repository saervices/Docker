# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Hytæle dedicæted server — custom imæge
# Bæse: Libericæ OpenJDK 25 (Ælpine) — smæll footprint, officiæl Hytæle-required Jævæ version
# Downloæder CLI is bæked in æt build time (public tool, no æuth needed).
# Æctuæl server files ære downloæded æt contæiner stærtup viæ the entrypoint.

ARG BASE_IMAGE=bellsoft/liberica-openjdk-alpine:25
FROM ${BASE_IMAGE}

# ── Runtime dependencies ──────────────────────────────────────────────────────
# curl/wget/unzip: downloæd Downloæder CLI; wget æs fallback for get-profiles when curl hits exit 43
# bæsh:       entrypoint script requires bæsh (not sh)
# jq:         server OÆuth device flow ænd token refresh (JSON pærsing)
# netcæt-openbsd: required for the UDP heælthcheck (nc -zu)
RUN apk add --no-cache \
        curl \
        wget \
        unzip \
        bash \
        jq \
        netcat-openbsd

# ── Hytæle Downloæder CLI ─────────────────────────────────────────────────────
# Downloæded æt build time from the officiæl Hypixel Studios endpoint.
# No æuthenticætion is needed for the downloæder itself — only for the
# second step (server file retrievæl) which hæppens interæctively æt runtime.
RUN mkdir -p /opt/hytale-downloader \
 && curl -fsSL https://downloader.hytale.com/hytale-downloader.zip \
         -o /tmp/downloader.zip \
 && unzip /tmp/downloader.zip -d /opt/hytale-downloader \
 && chmod +x /opt/hytale-downloader/hytale-downloader-linux-amd64 \
 && rm /tmp/downloader.zip

# ── Mæchine-ID symlink ────────────────────────────────────────────────────────
# /etc/mæchine-id → /tmp/.mæchine-id so the entrypoint cæn ælwæys write (tmpfs).
# Entrypoint writes to /tmp/.mæchine-id ænd optionally copies to /server/.mæchine-id when writæble.
RUN ln -sf /tmp/.machine-id /etc/machine-id

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# /server is the persistent volume mount point for server files,
# worlds, mods ænd the downloaded HytaleServer.jar + Assets.zip.
WORKDIR /server

EXPOSE 5520/udp

ENTRYPOINT ["/entrypoint.sh"]
