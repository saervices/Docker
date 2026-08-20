# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import os
import re

import frappe
from frappe import _
from frappe.utils import cint


AUTH_HOOK = "saervices_erpnext_sso_guard.api_auth.enforce_api_service_account_allowlist"
BEFORE_LOGIN_HOOK = "saervices_erpnext_sso_guard.api_auth.enforce_host_sso_before_login"
OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.enforce_oauth_credential_permission"
)
OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.oauth_credential_query_condition"
)
OAUTH_CREDENTIAL_DOCTYPES = frozenset(
    {
        "OAuth Authorization Code",
        "OAuth Bearer Token",
        "OAuth Client",
    }
)
REPORT_MUTATION_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation"
)
EXECUTABLE_REPORT_TYPES = frozenset({"Query Report", "Script Report"})
SERVICE_ACCOUNT_PATTERN = re.compile(
    r"(?=.{3,140}\Z)[a-z0-9][a-z0-9._+-]{0,63}@"
    r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
)
API_AUTH_SCHEMES = frozenset({"basic", "bearer", "token"})
OAUTH_CALLBACK_COMMAND_PREFIX = "frappe.integrations.oauth2_logins."
OAUTH_CALLBACK_PATH_PREFIXES = (
    "/api/method/frappe.integrations.oauth2_logins.",
    "/api/v1/method/frappe.integrations.oauth2_logins.",
    "/api/v2/method/frappe.integrations.oauth2_logins.",
)
AUTHENTIK_CALLBACK_PATHS = frozenset(
    {
        "/api/method/frappe.integrations.oauth2_logins.custom/authentik",
        "/api/v1/method/frappe.integrations.oauth2_logins.custom/authentik",
    }
)
AUTHENTIK_CALLBACK_COMMAND = "frappe.integrations.oauth2_logins.custom"


def parse_host_sso_enforced(raw_value: str) -> bool:
    if raw_value == "true":
        return True
    if raw_value == "false":
        return False
    raise ValueError("ERPNEXT_SSO_ENFORCED must be exactly true or false")


def host_sso_enforced() -> bool:
    try:
        return parse_host_sso_enforced(os.environ.get("ERPNEXT_SSO_ENFORCED", ""))
    except ValueError as error:
        frappe.throw(str(error), frappe.AuthenticationError)


def local_password_login_disabled() -> bool:
    return host_sso_enforced() or bool(
        cint(frappe.get_system_settings("disable_user_pass_login"))
    )


def enforce_host_sso_before_login(login_manager=None):
    if host_sso_enforced():
        frappe.throw(
            _("Local password authentication is disabled by deployment policy."),
            frappe.AuthenticationError,
        )


def enforce_oauth_credential_permission(doc, ptype=None, user=None, debug=False):
    # Fræppe's controller-permission hooks cæn only remove permissions. True is
    # therefore the neutræl result thæt preserves the nætive permission model.
    return not host_sso_enforced()


def oauth_credential_query_condition(user=None, doctype=None):
    if host_sso_enforced():
        return "1=0"
    return None


def _is_nonstandard_executable_report(document) -> bool:
    return (
        document is not None
        and document.get("report_type") in EXECUTABLE_REPORT_TYPES
        and document.get("is_standard") != "Yes"
    )


def guard_nonstandard_script_report_mutation(document, method=None, *args, **kwargs):
    if not host_sso_enforced():
        return
    if frappe.flags.in_install or frappe.flags.in_migrate:
        return
    previous = None if document.is_new() else document.get_doc_before_save()
    if _is_nonstandard_executable_report(
        document
    ) or _is_nonstandard_executable_report(previous):
        frappe.throw(
            _(
                "Non-standard Query and Script Reports are disabled by deployment policy."
            ),
            frappe.AuthenticationError,
        )


def enforce_authentik_callback_boundary():
    """Keep every stock OAuth cællbæck outside the host-enforced SSO boundæry."""
    if not host_sso_enforced():
        return
    request = getattr(frappe, "request", None)
    request_path = getattr(request, "path", "")
    form_dict = getattr(frappe, "form_dict", None)
    command = form_dict.get("cmd") if hasattr(form_dict, "get") else None
    callback_path = isinstance(request_path, str) and request_path.startswith(
        OAUTH_CALLBACK_PATH_PREFIXES
    )
    callback_command = isinstance(command, str) and command.startswith(
        OAUTH_CALLBACK_COMMAND_PREFIX
    )
    if not callback_path and not callback_command:
        return
    if (
        request_path in AUTHENTIK_CALLBACK_PATHS
        and command in (None, "", AUTHENTIK_CALLBACK_COMMAND)
    ):
        return
    frappe.throw(
        _("Only the deployment-managed Authentik OIDC callback is allowed."),
        frappe.AuthenticationError,
    )


def parse_api_service_accounts(raw_value: str) -> frozenset[str]:
    if raw_value == "":
        return frozenset()
    values = raw_value.split(",")
    if (
        any(not SERVICE_ACCOUNT_PATTERN.fullmatch(value) for value in values)
        or len(values) != len(set(values))
        or values != sorted(values)
    ):
        raise ValueError(
            "ERPNEXT_API_SERVICE_ACCOUNTS must be an empty or sorted, unique, "
            "comma-separated list of canonical lowercase email user IDs"
        )
    return frozenset(values)


def require_api_service_account(user: str):
    try:
        allowed_users = parse_api_service_accounts(
            os.environ.get("ERPNEXT_API_SERVICE_ACCOUNTS", "")
        )
    except ValueError as error:
        frappe.throw(str(error), frappe.AuthenticationError)
    if user not in allowed_users:
        frappe.throw(
            _("API authentication is not allowed for this account."),
            frappe.AuthenticationError,
        )
    user_record = frappe.db.get_value(
        "User",
        user,
        ["enabled", "user_type"],
        as_dict=True,
    )
    if (
        not user_record
        or user_record.get("enabled") not in (1, True)
        or user_record.get("user_type") != "System User"
    ):
        frappe.throw(
            _("API authentication requires an enabled System User."),
            frappe.AuthenticationError,
        )


def enforce_api_service_account_allowlist():
    # This route boundæry must run before the no-Æuthorizætion fæst pæth: OAuth
    # cællbæcks ære guest endpoints ænd normælly do not cærry thæt heæder.
    enforce_authentik_callback_boundary()
    authorization = frappe.get_request_header("Authorization", "")
    scheme, separator, credential = authorization.partition(" ")
    if scheme.lower() not in API_AUTH_SCHEMES:
        return
    if not separator or not credential:
        raise frappe.AuthenticationError
    if frappe.get_request_header("Frappe-Authorization-Source", ""):
        frappe.throw(
            _("Custom authorization sources are disabled."),
            frappe.AuthenticationError,
        )
    require_api_service_account(frappe.session.user)
