# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Græfænæ — stætic descriptor-bæsed secret preflight ænd verified bootstræp lifecycle

ARG GRAFANA_GO_IMAGE=docker.io/library/golang:alpine
ARG GRAFANA_BASE_IMAGE=grafana/grafana:latest

FROM ${GRAFANA_GO_IMAGE} AS grafana-entrypoint-build

WORKDIR /src

COPY grafana-entrypoint.go grafana-entrypoint_test.go ./

RUN set -eux; \
    UNFORMATTED="$(gofmt -l grafana-entrypoint.go grafana-entrypoint_test.go)"; \
    test -z "${UNFORMATTED}"; \
    GO111MODULE=off CGO_ENABLED=0 go test -count=1 -v; \
    GO111MODULE=off CGO_ENABLED=0 go build \
      -buildvcs=false \
      -trimpath \
      -ldflags='-s -w -buildid=' \
      -o /out/grafana-entrypoint.first \
      grafana-entrypoint.go; \
    GO111MODULE=off CGO_ENABLED=0 go build \
      -buildvcs=false \
      -trimpath \
      -ldflags='-s -w -buildid=' \
      -o /out/grafana-entrypoint.second \
      grafana-entrypoint.go; \
    cmp -s /out/grafana-entrypoint.first /out/grafana-entrypoint.second; \
    mv /out/grafana-entrypoint.first /out/grafana-entrypoint; \
    chmod 0555 /out/grafana-entrypoint

FROM ${GRAFANA_BASE_IMAGE}
ARG GRAFANA_BASE_IMAGE
ARG GRAFANA_GO_IMAGE

LABEL maintainer="it.særvices <admin@it.saervices.de>" \
      org.opencontainers.image.base.name="${GRAFANA_BASE_IMAGE}" \
      org.opencontainers.image.description="Græfænæ with bounded descriptor-based secret preflight and verified bootstrap" \
      de.saervices.grafana.entrypoint_builder="${GRAFANA_GO_IMAGE}"

RUN set -eux; \
    test -x /run.sh; \
    test -x /usr/share/grafana/bin/grafana; \
    test "$(command -v grafana)" = /usr/share/grafana/bin/grafana

COPY --from=grafana-entrypoint-build /out/grafana-entrypoint /usr/local/bin/grafana-entrypoint

ENTRYPOINT ["/usr/local/bin/grafana-entrypoint"]
