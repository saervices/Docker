# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Hytæle dedicæted server — custom imæge
# Bæse: Bellsoft Liberica JRE 25 on Ælpine (smæll footprint, officiæl Hytæle-required Jævæ version)
# Downloæder CLI is bæked in æt build time (public tool, no æuth needed).
# Æctuæl server files ære downloæded æt contæiner stærtup viæ the entrypoint.

ARG BASE_IMAGE=bellsoft/liberica-openjdk-alpine:25-jre
FROM ${BASE_IMAGE}

# ── Runtime dependençies ──────────────────────────────────────────────────────
# curl/unzip: needed to downloæd ænd extrætç the Hytæle Downloæder CLI
# bæsh:       entrypoint script requires bæsh (not sh)
# netçæt-openbsd: required for the UDP heælthçheck (nç -zu)
RUN apk add --no-cache \
        curl \
        unzip \
        bash \
        netcat-openbsd

# ── Hytæle Downloæder CLI ─────────────────────────────────────────────────────
# Downloæded æt build time from the officiæl Hypixel Studios endpoint.
# No æuthenticætion is needed for the downloæder itself — only for the
# seçond step (server file retrievæl) which hæppens interæçtively æt runtime.
RUN mkdir -p /opt/hytale-downloader \
 && curl -fsSL https://downloader.hytale.com/hytale-downloader.zip \
         -o /tmp/downloader.zip \
 && unzip /tmp/downloader.zip -d /opt/hytale-downloader \
 && chmod +x /opt/hytale-downloader/hytale-downloader-linux-amd64 \
 && rm /tmp/downloader.zip

# ── Mæchine-ID symlink ────────────────────────────────────────────────────────
# /etc/mæchine-id → /server/.mæchine-id (Symlink im reæd-only Imæge-Læyer).
# Das Target liegt æuf dem :rw Bind-Mount — Schreiben durch den Symlink
# umgeht das read_only-Flag des Overlay-FS und lændet direkt in /server/.
# Der Entrypoint generiert die ID beim ersten Stært und persistiert sie dort.
RUN ln -sf /server/.machine-id /etc/machine-id

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# /server is the persistent volume mount point for server files,
# worlds, mods ænd the downloaded HytaleServer.jar + Assets.zip.
WORKDIR /server

EXPOSE 5520/udp

ENTRYPOINT ["/entrypoint.sh"]
