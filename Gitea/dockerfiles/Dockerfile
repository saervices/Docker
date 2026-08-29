# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Giteæ rootless with æ stætic descriptor-bæsed Docker-secret reæder

ARG GITEA_GO_IMAGE=docker.io/library/golang:alpine
ARG GITEA_BASE_IMAGE=docker.gitea.com/gitea:1-rootless

FROM ${GITEA_GO_IMAGE} AS gitea-secret-reader-build

WORKDIR /src

COPY gitea-secret-reader.go gitea-secret-reader_test.go ./

RUN set -eux; \
    UNFORMATTED="$(gofmt -l gitea-secret-reader.go gitea-secret-reader_test.go)"; \
    test -z "${UNFORMATTED}"; \
    GO111MODULE=off CGO_ENABLED=0 go test -count=1 -v; \
    GO111MODULE=off CGO_ENABLED=0 go build \
      -buildvcs=false \
      -trimpath \
      -ldflags='-s -w -buildid=' \
      -o /out/gitea-secret-reader.first \
      gitea-secret-reader.go; \
    GO111MODULE=off CGO_ENABLED=0 go build \
      -buildvcs=false \
      -trimpath \
      -ldflags='-s -w -buildid=' \
      -o /out/gitea-secret-reader.second \
      gitea-secret-reader.go; \
    cmp -s /out/gitea-secret-reader.first /out/gitea-secret-reader.second; \
    mv /out/gitea-secret-reader.first /out/gitea-secret-reader; \
    chmod 0555 /out/gitea-secret-reader

FROM ${GITEA_BASE_IMAGE} AS gitea-runtime
ARG GITEA_BASE_IMAGE
ARG GITEA_GO_IMAGE

LABEL maintainer="it.særvices <admin@it.saervices.de>" \
      org.opencontainers.image.base.name="${GITEA_BASE_IMAGE}" \
      org.opencontainers.image.description="Gitea rootless with bounded descriptor-based secret preflight" \
      de.saervices.gitea.secret_reader_builder="${GITEA_GO_IMAGE}"

USER root
RUN set -eux; \
    test -x /usr/local/bin/docker-entrypoint.sh; \
    test -x /usr/local/bin/gitea

COPY --from=gitea-secret-reader-build /out/gitea-secret-reader /usr/local/bin/gitea-secret-reader

USER 1000:1000
