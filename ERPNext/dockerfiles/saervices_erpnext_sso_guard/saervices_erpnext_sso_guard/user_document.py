# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import frappe
from frappe import _
from frappe.utils import cint

from saervices_erpnext_sso_guard.api_auth import (
    host_sso_enforced,
    local_password_login_disabled,
)
from saervices_erpnext_sso_guard.password_login import _require_local_password_login


USER_BEFORE_VALIDATE_HOOK = (
    "saervices_erpnext_sso_guard.user_document.guard_user_password_fields"
)
USER_CONTROLLER_EXTENSION = (
    "saervices_erpnext_sso_guard.user_document.UserSSOGuardMixin"
)
SOCIAL_LOGIN_KEY_MUTATION_HOOK = (
    "saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation"
)
SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG = (
    "saervices_erpnext_sso_guard_social_login_key_bootstrap"
)
AUTHENTIK_BINDING_CALLBACK_FLAG = (
    "saervices_erpnext_sso_guard_authentik_binding_callback"
)


class UserSSOGuardMixin:
    def _reset_password(self, send_email=False, password_expired=False):
        _require_local_password_login()
        return super()._reset_password(
            send_email=send_email,
            password_expired=password_expired,
        )

    def set_new_password(self, new_password=None):
        if new_password:
            _require_local_password_login()
        return super().set_new_password(new_password=new_password)


def guard_user_password_fields(document, method=None):
    guard_user_api_credentials(document)
    guard_user_social_login_bindings(document)
    if not local_password_login_disabled():
        return
    if document.get("new_password"):
        frappe.throw(
            _("Local password changes are unavailable while SSO-only login is active."),
            frappe.AuthenticationError,
        )
    if document.is_new() and cint(document.get("send_welcome_email")):
        frappe.throw(
            _("Welcome password-reset emails are unavailable while SSO-only login is active."),
            frappe.AuthenticationError,
        )


def guard_user_api_credentials(document):
    if not host_sso_enforced():
        return

    current_credentials = (
        document.get("api_key"),
        document.get("api_secret"),
    )
    if document.is_new():
        credentials_changed = any(
            value not in (None, "") for value in current_credentials
        )
    else:
        previous = document.get_doc_before_save()
        credentials_changed = previous is None or current_credentials != (
            previous.get("api_key"),
            previous.get("api_secret"),
        )

    if credentials_changed:
        frappe.throw(
            _(
                "API credentials are deployment-managed while SSO-only login is active."
            ),
            frappe.AuthenticationError,
        )


def _social_login_identity(row):
    return (
        row.get("provider"),
        row.get("username") or None,
        row.get("userid"),
    )


def guard_user_social_login_bindings(document):
    if not host_sso_enforced():
        return
    current = tuple(
        _social_login_identity(row) for row in (document.get("social_logins") or ())
    )
    persisted = ()
    if not document.is_new():
        persisted = tuple(
            _social_login_identity(row)
            for row in frappe.get_all(
                "User Social Login",
                filters={
                    "parent": document.name,
                    "parenttype": "User",
                    "parentfield": "social_logins",
                },
                fields=["provider", "username", "userid"],
                order_by="idx asc",
            )
        )
    if current == persisted:
        return
    callback_binding = getattr(
        frappe.flags,
        AUTHENTIK_BINDING_CALLBACK_FLAG,
        None,
    )
    callback_subject = (
        callback_binding[1]
        if isinstance(callback_binding, tuple) and len(callback_binding) == 2
        else None
    )
    expected_addition = (
        "authentik",
        None,
        callback_subject,
    )
    if (
        not isinstance(callback_binding, tuple)
        or len(callback_binding) != 2
        or callback_binding[0] != document.name
        or any(row[0] == "authentik" for row in persisted)
        or len(current) != len(persisted) + 1
        or current[:-1] != persisted
        or current[-1] != expected_addition
    ):
        frappe.throw(
            _("User social-login bindings are deployment-managed while SSO-only login is active."),
            frappe.AuthenticationError,
        )


def guard_social_login_key_mutation(document, method=None, *args, **kwargs):
    if not local_password_login_disabled():
        return
    if getattr(frappe.flags, SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG, False) is True:
        return
    frappe.throw(
        _("Social Login Key changes are deployment-managed while SSO-only login is active."),
        frappe.AuthenticationError,
    )
