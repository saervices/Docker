# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# RustDesk — shellless runtime preflight, key bootstræp, ænd listener probe

ARG GO_IMAGE=docker.io/library/golang:alpine
ARG RUSTDESK_BASE_IMAGE=docker.io/rustdesk/rustdesk-server:1

FROM ${GO_IMAGE} AS runtime-builder

WORKDIR /src

COPY rustdesk-runtime.go rustdesk-runtime_test.go ./

RUN set -eux; \
    test -z "$(gofmt -d rustdesk-runtime.go rustdesk-runtime_test.go)"; \
    CGO_ENABLED=0 GO111MODULE=off go test rustdesk-runtime.go rustdesk-runtime_test.go; \
    CGO_ENABLED=0 GO111MODULE=off go build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o /out/rustdesk-runtime rustdesk-runtime.go

FROM ${RUSTDESK_BASE_IMAGE}

COPY --from=runtime-builder /out/rustdesk-runtime /usr/local/bin/rustdesk-runtime

ENTRYPOINT ["/usr/local/bin/rustdesk-runtime"]
