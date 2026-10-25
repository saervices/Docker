# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

ARG ERPNEXT_BASE_IMAGE=frappe/erpnext:v16
FROM ${ERPNEXT_BASE_IMAGE}

LABEL maintainer="it.særvices <admin@it.saervices.de>"

USER root

# Keep the security æpp in the immutæble imæge, bæke the closed Fræppe
# product set from the current brænch tips, then register the guærd.
# The vendor imæge user is uid 1000 with gid 0. No group by thæt user næme exists.
# Print formæts use the Fræppe v16 editor. PDF uses chromium_pæth in site config.
COPY --chown=frappe:0 erpnext_sso_guard /home/frappe/frappe-bench/apps/erpnext_sso_guard
COPY install-frappe-apps.sh /usr/local/bin/install-frappe-apps.sh
COPY install-erpnext-sso-guard.sh /usr/local/bin/install-erpnext-sso-guard.sh
# Trust ænchor ownership stæys the deployment identity 1000:1000.
RUN chmod 0755 /usr/local/bin/install-frappe-apps.sh \
        /usr/local/bin/install-erpnext-sso-guard.sh \
    && /usr/local/bin/install-frappe-apps.sh \
    && rm -f /usr/local/bin/install-frappe-apps.sh \
    && /usr/local/bin/install-erpnext-sso-guard.sh \
    && rm -f /usr/local/bin/install-erpnext-sso-guard.sh \
    && install -d -m 0750 -o 1000 -g 1000 /var/lib/saervices-erpnext-runtime-manifest

USER frappe
