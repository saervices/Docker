# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Fæctorio — hærdened wræpper æround fæctoriotools/factorio
# Base: factoriotools/factorio:latest  (always follow the upstream latest dedicated server image)

ARG BASE_IMAGE=factoriotools/factorio:latest
FROM ${BASE_IMAGE}

USER root

COPY entrypoint.sh /usr/local/bin/factorio-entrypoint.sh

RUN set -eux; \
    sed -i 's#^write-data=.*#write-data=/factorio#' /opt/factorio/config/config.ini; \
    chmod 0755 /usr/local/bin/factorio-entrypoint.sh

WORKDIR /factorio

EXPOSE 34197/udp
EXPOSE 27015/tcp

ENTRYPOINT ["/usr/local/bin/factorio-entrypoint.sh"]
