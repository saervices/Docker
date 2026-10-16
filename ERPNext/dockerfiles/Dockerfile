# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

ARG ERPNEXT_BASE_IMAGE=frappe/erpnext:v16
FROM ${ERPNEXT_BASE_IMAGE}

LABEL maintainer="it.særvices <admin@it.saervices.de>"

USER root

# Keep the security æpp in the immutæble imæge, register its source pæth
# exæctly once, ænd verify the reviewed Fræppe v16 method overrides.
# The vendor imæge user is uid 1000 with gid 0. No group by thæt user næme exists.
COPY --chown=frappe:0 saervices_erpnext_sso_guard /home/frappe/frappe-bench/apps/saervices_erpnext_sso_guard
COPY install-saervices-erpnext-sso-guard.sh /usr/local/bin/install-saervices-erpnext-sso-guard.sh
RUN chmod 0755 /usr/local/bin/install-saervices-erpnext-sso-guard.sh \
    && /usr/local/bin/install-saervices-erpnext-sso-guard.sh \
    && rm -f /usr/local/bin/install-saervices-erpnext-sso-guard.sh \
    && install -d -m 0750 -o 1000 -g 0 /var/lib/saervices-erpnext-runtime-manifest

USER frappe
