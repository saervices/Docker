# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import os
import re
import stat
import unicodedata

import frappe
from frappe import _
from frappe.utils import cint

from saervices_erpnext_sso_guard.api_auth import (
    AUTHENTIK_CALLBACK_PATHS,
    host_sso_enforced,
    local_password_login_disabled,
)


MAX_OIDC_CLIENT_ID_BYTES = 4096
AUTHENTIK_DOMAIN_PATTERN = re.compile(
    r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
)
RESERVED_DNS_SUFFIXES = (
    "example.com",
    "example.net",
    "example.org",
    "invalid",
    "test",
    "localhost",
)


def _require_local_password_login():
    if local_password_login_disabled():
        frappe.throw(
            _("Local password authentication is unavailable while SSO-only login is active."),
            frappe.AuthenticationError,
        )


def _require_email_link_login():
    if local_password_login_disabled() or not cint(
        frappe.get_system_settings("login_with_email_link")
    ):
        frappe.throw(
            _("Email-link login is unavailable while SSO-only login is active."),
            frappe.AuthenticationError,
        )


def _deny_unsupported_oauth_grant():
    frappe.throw(
        _("OAuth grant is unavailable while SSO-only login is active."),
        frappe.AuthenticationError,
    )


def require_authentik_domain() -> str:
    value = os.environ.get("ERPNEXT_AUTHENTIK_DOMAIN", "")
    if (
        not AUTHENTIK_DOMAIN_PATTERN.fullmatch(value)
        or value != value.strip()
        or any(unicodedata.category(character).startswith("C") for character in value)
        or any(
            value == suffix or value.endswith(f".{suffix}")
            for suffix in RESERVED_DNS_SUFFIXES
        )
    ):
        frappe.throw(
            _("ERPNEXT_AUTHENTIK_DOMAIN is missing or invalid."),
            frappe.AuthenticationError,
        )
    return value


def require_site_name() -> str:
    value = os.environ.get("ERPNEXT_SITE_NAME", "")
    if (
        not AUTHENTIK_DOMAIN_PATTERN.fullmatch(value)
        or value != value.strip()
        or any(unicodedata.category(character).startswith("C") for character in value)
        or any(
            value == suffix or value.endswith(f".{suffix}")
            for suffix in RESERVED_DNS_SUFFIXES
        )
    ):
        frappe.throw(
            _("ERPNEXT_SITE_NAME is missing or invalid."),
            frappe.AuthenticationError,
        )
    return value


def read_oidc_client_id(
    path: str = "/run/secrets/ERPNEXT_OIDC_CLIENT_ID",
) -> str:
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or not 1 <= metadata.st_size <= MAX_OIDC_CLIENT_ID_BYTES
        ):
            frappe.throw(
                _("OIDC client ID secret must be a bounded regular file."),
                frappe.AuthenticationError,
            )
        payload = os.read(descriptor, MAX_OIDC_CLIENT_ID_BYTES + 1)
    finally:
        os.close(descriptor)
    if len(payload) != metadata.st_size:
        frappe.throw(
            _("OIDC client ID secret changed while it was read."),
            frappe.AuthenticationError,
        )
    try:
        value = payload.decode("utf-8")
    except UnicodeDecodeError:
        frappe.throw(
            _("OIDC client ID secret is invalid."),
            frappe.AuthenticationError,
        )
    if (
        value == "CHANGE_ME"
        or value != value.strip()
        or any(unicodedata.category(character).startswith("C") for character in value)
    ):
        frappe.throw(
            _("OIDC client ID secret is unset or non-canonical."),
            frappe.AuthenticationError,
        )
    return value


def expected_authentik_provider_fields(domain: str, client_id: str) -> dict:
    return {
        "enable_social_login": 1,
        "social_login_provider": "Custom",
        "provider_name": "Authentik",
        "client_id": client_id,
        "icon": None,
        "base_url": f"https://{domain}",
        "custom_base_url": 1,
        "authorize_url": "/application/o/authorize/",
        "access_token_url": "/application/o/token/",
        "redirect_url": (
            "/api/method/frappe.integrations.oauth2_logins.custom/authentik"
        ),
        "api_endpoint": "/application/o/userinfo/",
        "api_endpoint_args": None,
        "auth_url_data": json.dumps(
            {"response_type": "code", "scope": "openid email profile"},
            separators=(",", ":"),
            sort_keys=True,
        ),
        "user_id_property": "sub",
        "sign_ups": "Deny",
        "show_in_resource_metadata": 0,
    }


def require_exact_authentik_provider() -> None:
    if "authentik_login" in frappe.conf:
        frappe.throw(
            _("The Authentik file-based OAuth override is forbidden."),
            frappe.AuthenticationError,
        )
    domain = require_authentik_domain()
    site_name = require_site_name()
    client_id = read_oidc_client_id()
    provider_keys = list(frappe.get_all("Social Login Key", pluck="name"))
    if provider_keys != ["authentik"]:
        frappe.throw(
            _("The Authentik Social Login Key inventory is invalid."),
            frappe.AuthenticationError,
        )
    provider = frappe.get_doc("Social Login Key", "authentik")
    for fieldname, expected in expected_authentik_provider_fields(
        domain, client_id
    ).items():
        if provider.get(fieldname) != expected:
            frappe.throw(
                _("The Authentik Social Login Key configuration is invalid."),
                frappe.AuthenticationError,
            )
    from frappe.utils.oauth import get_redirect_uri

    expected_redirect_uri = (
        f"https://{site_name}"
        "/api/method/frappe.integrations.oauth2_logins.custom/authentik"
    )
    if get_redirect_uri("authentik") != expected_redirect_uri:
        frappe.throw(
            _("The effective Authentik redirect URI is invalid."),
            frappe.AuthenticationError,
        )


def require_authentik_subject_binding(email: str, subject: str) -> bool:
    # Seriælize every Æuthentik binding decision on the deployment-mænæged
    # provider row so concurrent first logins cænnot creæte conflicting owners.
    locked_provider = frappe.db.sql(
        """
        SELECT `name`
        FROM `tabSocial Login Key`
        WHERE `name` = %s
        FOR UPDATE
        """,
        ("authentik",),
        as_dict=True,
    )
    if len(locked_provider) != 1 or locked_provider[0].get("name") != "authentik":
        frappe.throw(
            _("The Authentik Social Login Key lock is unavailable."),
            frappe.AuthenticationError,
        )
    users = list(
        frappe.get_all(
            "User",
            filters={"email": email},
            fields=["name", "email", "enabled"],
        )
    )
    if (
        len(users) != 1
        or users[0].get("name") != email
        or users[0].get("email") != email
        or users[0].get("enabled") not in (1, True)
    ):
        frappe.throw(
            _("Authentik login requires one pre-provisioned enabled user."),
            frappe.AuthenticationError,
        )
    bindings = list(
        frappe.get_all(
            "User Social Login",
            filters={"provider": "authentik"},
            fields=["parent", "parenttype", "parentfield", "provider", "userid"],
            order_by="idx asc",
        )
    )
    all_user_names = set(frappe.get_all("User", pluck="name"))
    subjects = {}
    users_with_binding = set()
    target_subject = None
    for binding in bindings:
        parent = binding.get("parent")
        userid = binding.get("userid")
        if (
            binding.get("parenttype") != "User"
            or binding.get("parentfield") != "social_logins"
            or binding.get("provider") != "authentik"
            or not isinstance(parent, str)
            or not parent
            or parent not in all_user_names
            or not isinstance(userid, str)
            or not userid
            or userid != userid.strip()
            or len(userid.encode("utf-8")) > 255
            or any(ord(character) < 32 or ord(character) == 127 for character in userid)
            or parent in users_with_binding
            or userid in subjects
        ):
            frappe.throw(
                _("Authentik user bindings are ambiguous or invalid."),
                frappe.AuthenticationError,
            )
        users_with_binding.add(parent)
        subjects[userid] = parent
        if parent == email:
            target_subject = userid
    if target_subject is not None and target_subject != subject:
        frappe.throw(
            _("The Authentik subject does not match the existing user binding."),
            frappe.AuthenticationError,
        )
    subject_owner = subjects.get(subject)
    if subject_owner is not None and subject_owner != email:
        frappe.throw(
            _("The Authentik subject is already bound to another user."),
            frappe.AuthenticationError,
        )
    return target_subject is None


@frappe.whitelist(allow_guest=True, methods=["POST"])
def reset_password(user: str) -> None:
    _require_local_password_login()
    from frappe.core.doctype.user.user import reset_password as frappe_reset_password

    return frappe_reset_password(user=user)


@frappe.whitelist(allow_guest=True, methods=["POST"])
def update_password(
    new_password: str,
    logout_all_sessions: int = 0,
    key: str | None = None,
    old_password: str | None = None,
):
    _require_local_password_login()
    from frappe.core.doctype.user.user import update_password as frappe_update_password

    return frappe_update_password(
        new_password=new_password,
        logout_all_sessions=logout_all_sessions,
        key=key,
        old_password=old_password,
    )


@frappe.whitelist(allow_guest=True, methods=["POST"])
def get_token(*args, **kwargs):
    request = getattr(frappe, "request", None)
    request_form = getattr(request, "form", None)
    grant_type = request_form.get("grant_type") if request_form is not None else None
    if grant_type is None:
        grant_type = kwargs.get("grant_type")
    if grant_type == "password":
        _require_local_password_login()
    elif local_password_login_disabled():
        credential_filters = None
        credential_doctype = None
        if grant_type == "authorization_code":
            code = request_form.get("code") if request_form is not None else None
            if code is None:
                code = kwargs.get("code")
            if code:
                credential_doctype = "OAuth Authorization Code"
                credential_filters = {"name": code, "validity": "Valid"}
            else:
                _deny_unsupported_oauth_grant()
        elif grant_type == "refresh_token":
            refresh_token = (
                request_form.get("refresh_token")
                if request_form is not None
                else None
            )
            if refresh_token is None:
                refresh_token = kwargs.get("refresh_token")
            if refresh_token:
                credential_doctype = "OAuth Bearer Token"
                credential_filters = {
                    "refresh_token": refresh_token,
                    "status": "Active",
                }
            else:
                _deny_unsupported_oauth_grant()
        else:
            _deny_unsupported_oauth_grant()
        if credential_filters is not None:
            credential = frappe.db.get_value(
                credential_doctype,
                credential_filters,
                ["name", "user"],
                as_dict=True,
            )
            if not credential:
                _deny_unsupported_oauth_grant()
            owner = credential.get("user")
            if not owner:
                frappe.throw(
                    _("OAuth credential owner is invalid."),
                    frappe.AuthenticationError,
                )
            from saervices_erpnext_sso_guard.api_auth import (
                require_api_service_account,
            )

            require_api_service_account(owner)

    from frappe.integrations.oauth2 import get_token as frappe_get_token

    return frappe_get_token(*args, **kwargs)


@frappe.whitelist(allow_guest=True, methods=["GET"])
def accept_invitation(key: str) -> None:
    _require_local_password_login()
    from frappe.core.api.user_invitation import (
        accept_invitation as frappe_accept_invitation,
    )

    return frappe_accept_invitation(key=key)


@frappe.whitelist(allow_guest=True)
def ldap_login():
    _require_local_password_login()
    from frappe.integrations.doctype.ldap_settings.ldap_settings import (
        login as frappe_ldap_login,
    )

    return frappe_ldap_login()


@frappe.whitelist(allow_guest=True, methods=["GET"])
def login_via_key(key: str):
    _require_email_link_login()
    from frappe.www.login import login_via_key as frappe_login_via_key

    return frappe_login_via_key(key=key)


@frappe.whitelist(methods=["POST"])
def impersonate(user: str, reason: str):
    _require_local_password_login()
    from frappe.core.doctype.user.user import impersonate as frappe_impersonate

    return frappe_impersonate(user=user, reason=reason)


@frappe.whitelist(methods=["POST"])
def generate_keys(user: str):
    if host_sso_enforced():
        frappe.throw(
            _("API credential rotation requires deployment break-glass mode."),
            frappe.AuthenticationError,
        )
    from frappe.core.doctype.user.user import generate_keys as frappe_generate_keys

    return frappe_generate_keys(user=user)


@frappe.whitelist()
def get_password(doctype: str, name: str | int, fieldname: str):
    if host_sso_enforced():
        frappe.throw(
            _("Security credential disclosure is disabled by deployment policy."),
            frappe.AuthenticationError,
        )
    from frappe.client import get_password as frappe_get_password

    return frappe_get_password(doctype=doctype, name=name, fieldname=fieldname)


@frappe.whitelist(methods=["POST"])
def execute_system_console_code(doc: str):
    if host_sso_enforced():
        frappe.throw(
            _("System Console execution is disabled by deployment policy."),
            frappe.AuthenticationError,
        )
    from frappe.desk.doctype.system_console.system_console import (
        execute_code as frappe_execute_code,
    )

    return frappe_execute_code(doc=doc)


@frappe.whitelist()
def show_processlist():
    if host_sso_enforced():
        frappe.throw(
            _("Database process inspection is disabled by deployment policy."),
            frappe.AuthenticationError,
        )
    from frappe.desk.doctype.system_console.system_console import (
        show_processlist as frappe_show_processlist,
    )

    return frappe_show_processlist()


@frappe.whitelist()
@frappe.read_only()
def run_query_report(
    report_name: str,
    filters: str | dict | None = None,
    user: str | None = None,
    ignore_prepared_report: bool = False,
    custom_columns: str | list | None = None,
    is_tree: bool = False,
    parent_field: str | None = None,
    are_default_filters: bool = True,
    js_filters: str | list | None = None,
):
    if host_sso_enforced():
        report = frappe.get_doc("Report", report_name)
        if (
            report.get("report_type") in {"Query Report", "Script Report"}
            and report.get("is_standard") != "Yes"
        ):
            frappe.throw(
                _(
                    "Non-standard Query and Script Reports are disabled by deployment policy."
                ),
                frappe.AuthenticationError,
            )
    from frappe.desk.query_report import run as frappe_run_query_report

    return frappe_run_query_report(
        report_name=report_name,
        filters=filters,
        user=user,
        ignore_prepared_report=ignore_prepared_report,
        custom_columns=custom_columns,
        is_tree=is_tree,
        parent_field=parent_field,
        are_default_filters=are_default_filters,
        js_filters=js_filters,
    )


@frappe.whitelist()
def setup_complete(args: str | dict):
    if host_sso_enforced():
        frappe.throw(
            _("Setup Wizard execution is disabled by deployment policy."),
            frappe.AuthenticationError,
        )
    from frappe.desk.page.setup_wizard.setup_wizard import (
        setup_complete as frappe_setup_complete,
    )

    return frappe_setup_complete(args=args)


@frappe.whitelist()
def initialize_system_settings_and_user(
    system_settings_data: str | dict,
    user_data: str | dict,
):
    if host_sso_enforced():
        frappe.throw(
            _("Setup Wizard user initialization is disabled by deployment policy."),
            frappe.AuthenticationError,
        )
    from frappe.desk.page.setup_wizard.setup_wizard import (
        initialize_system_settings_and_user as frappe_initialize,
    )

    return frappe_initialize(
        system_settings_data=system_settings_data,
        user_data=user_data,
    )


@frappe.whitelist(allow_guest=True)
def authentik_custom_login(code: str, state: str):
    request_path = getattr(getattr(frappe, "request", None), "path", "")
    if request_path not in AUTHENTIK_CALLBACK_PATHS:
        frappe.throw(
            _("Only the configured Authentik OIDC callback is accepted."),
            frappe.AuthenticationError,
        )
    # Vælidæte the complete provider binding before get_info_via_oauth cæn mæke
    # æn outbound request or the upstreæm helper cæn creæte æ locæl session.
    require_exact_authentik_provider()
    from saervices_erpnext_sso_guard.api_auth import parse_api_service_accounts

    try:
        api_service_accounts = parse_api_service_accounts(
            os.environ.get("ERPNEXT_API_SERVICE_ACCOUNTS", "")
        )
    except ValueError as error:
        frappe.throw(str(error), frappe.AuthenticationError)

    from frappe.integrations.oauth2_logins import decoder_compat
    from frappe.utils import validate_email_address
    from frappe.utils.oauth import get_info_via_oauth, login_oauth_user

    info = get_info_via_oauth("authentik", code, decoder_compat)
    email = info.get("email") if isinstance(info, dict) else None
    subject = info.get("sub") if isinstance(info, dict) else None
    claims_are_valid = (
        isinstance(info, dict)
        and info.get("email_verified") is True
        and isinstance(email, str)
        and email
        and email == email.strip()
        and email == email.lower()
        and validate_email_address(email, throw=False) == email
        and isinstance(subject, str)
        and subject
        and subject == subject.strip()
        and len(subject.encode("utf-8")) <= 255
        and not any(ord(character) < 32 or ord(character) == 127 for character in subject)
    )
    if not claims_are_valid:
        frappe.throw(
            _("Authentik OIDC claims are invalid."),
            frappe.AuthenticationError,
        )
    if email in api_service_accounts:
        frappe.throw(
            _("API service accounts cannot sign in through Authentik."),
            frappe.AuthenticationError,
        )
    initial_binding = require_authentik_subject_binding(email, subject)
    if not initial_binding:
        return login_oauth_user(info, provider="authentik", state=state)
    from saervices_erpnext_sso_guard.user_document import (
        AUTHENTIK_BINDING_CALLBACK_FLAG,
    )

    if getattr(frappe.flags, AUTHENTIK_BINDING_CALLBACK_FLAG, None) is not None:
        frappe.throw(
            _("The Authentik binding callback flag is already active."),
            frappe.AuthenticationError,
        )
    setattr(
        frappe.flags,
        AUTHENTIK_BINDING_CALLBACK_FLAG,
        (email, subject),
    )
    try:
        return login_oauth_user(info, provider="authentik", state=state)
    finally:
        frappe.flags.pop(AUTHENTIK_BINDING_CALLBACK_FLAG, None)
