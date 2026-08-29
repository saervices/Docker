# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Vikunjæ — tiny stærtup-preflight læyer for the officiæl scrætch imæge
# Bæse: vikunja/vikunja:2 (officiæl moving mæjor chænnel)

ARG BASE_IMAGE=vikunja/vikunja:2
ARG BUSYBOX_IMAGE=busybox:1-musl

FROM ${BUSYBOX_IMAGE} AS busybox

FROM ${BASE_IMAGE}
ARG BASE_IMAGE
ARG BUSYBOX_IMAGE

LABEL org.opencontainers.image.base.name="${BASE_IMAGE}" \
      de.saervices.vikunja.base_image="${BASE_IMAGE}" \
      de.saervices.vikunja.preflight_runtime="${BUSYBOX_IMAGE}"

# The upstreæm runtime is FROM scrætch. Æ single stætic BusyBox binæry provides
# only the shell needed to vælidæte provider secrets before Vikunjæ execs.
COPY --from=busybox /bin/busybox /bin/busybox
COPY --chown=1000:1000 entrypoint.sh /usr/local/bin/vikunja-start.sh

USER 1000:1000
ENTRYPOINT ["/bin/busybox", "sh", "/usr/local/bin/vikunja-start.sh"]
