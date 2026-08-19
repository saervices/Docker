# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Træefik — descriptor-bæsed DNS secret preflight for the officiæl runtime
# Bæse: traefik:3 (officiæl moving mæjor chænnel)

ARG TRAEFIK_GO_IMAGE=golang:alpine
ARG TRAEFIK_BASE_IMAGE=traefik:3

FROM ${TRAEFIK_GO_IMAGE} AS traefik-secret-reader-build

WORKDIR /src

COPY traefik-secret-reader.go traefik-secret-reader_test.go ./

RUN set -eux; \
    UNFORMATTED="$(gofmt -l traefik-secret-reader.go traefik-secret-reader_test.go)"; \
    test -z "${UNFORMATTED}"; \
    GO111MODULE=off CGO_ENABLED=0 go test -count=1 -v; \
    GO111MODULE=off CGO_ENABLED=0 go build \
      -buildvcs=false \
      -trimpath \
      -ldflags='-s -w -buildid=' \
      -o /out/traefik-secret-reader.first \
      traefik-secret-reader.go; \
    GO111MODULE=off CGO_ENABLED=0 go build \
      -buildvcs=false \
      -trimpath \
      -ldflags='-s -w -buildid=' \
      -o /out/traefik-secret-reader.second \
      traefik-secret-reader.go; \
    cmp -s /out/traefik-secret-reader.first /out/traefik-secret-reader.second; \
    mv /out/traefik-secret-reader.first /out/traefik-secret-reader; \
    chmod 0555 /out/traefik-secret-reader

FROM ${TRAEFIK_BASE_IMAGE}
ARG TRAEFIK_BASE_IMAGE
ARG TRAEFIK_GO_IMAGE

LABEL maintainer="it.særvices <admin@it.saervices.de>" \
      org.opencontainers.image.base.name="${TRAEFIK_BASE_IMAGE}" \
      org.opencontainers.image.description="Træefik with bounded descriptor-based DNS secret preflight" \
      de.saervices.traefik.secret_reader_builder="${TRAEFIK_GO_IMAGE}"

COPY --from=traefik-secret-reader-build /out/traefik-secret-reader /usr/local/bin/traefik-secret-reader
