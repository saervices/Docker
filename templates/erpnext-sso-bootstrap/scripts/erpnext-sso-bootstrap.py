# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import os
import re
import stat
import unicodedata
from pathlib import Path


SITES_ROOT = Path("/home/frappe/frappe-bench/sites")
APPS_PATH = SITES_ROOT / "apps.txt"
MAX_SECRET_BYTES = 4096
REDIS_SCAN_BATCH_SIZE = 256
REDIS_DELETE_MAX_PASSES = 32
PROVIDER_NAME = "Authentik"
PROVIDER_KEY = "authentik"
EXPECTED_APPS = frozenset({"frappe", "erpnext", "saervices_erpnext_sso_guard"})
EXPECTED_AUTH_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.enforce_api_service_account_allowlist"
)
EXPECTED_BEFORE_LOGIN_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.enforce_host_sso_before_login"
)
EXPECTED_USER_BEFORE_VALIDATE_HOOK = (
    "saervices_erpnext_sso_guard.user_document.guard_user_password_fields"
)
EXPECTED_SOCIAL_LOGIN_KEY_MUTATION_HOOK = (
    "saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation"
)
EXPECTED_SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG = (
    "saervices_erpnext_sso_guard_social_login_key_bootstrap"
)
EXPECTED_USER_CONTROLLER_EXTENSION = (
    "saervices_erpnext_sso_guard.user_document.UserSSOGuardMixin"
)
EXPECTED_OAUTH_CREDENTIAL_DOCTYPES = frozenset(
    {
        "OAuth Authorization Code",
        "OAuth Bearer Token",
        "OAuth Client",
    }
)
EXPECTED_OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.enforce_oauth_credential_permission"
)
EXPECTED_OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.oauth_credential_query_condition"
)
EXPECTED_REPORT_MUTATION_HOOK = (
    "saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation"
)
EXPECTED_AUTH_OVERRIDES = {
    "frappe.core.doctype.user.user.reset_password": (
        "saervices_erpnext_sso_guard.password_login.reset_password"
    ),
    "frappe.core.doctype.user.user.update_password": (
        "saervices_erpnext_sso_guard.password_login.update_password"
    ),
    "frappe.integrations.oauth2.get_token": (
        "saervices_erpnext_sso_guard.password_login.get_token"
    ),
    "frappe.core.api.user_invitation.accept_invitation": (
        "saervices_erpnext_sso_guard.password_login.accept_invitation"
    ),
    "frappe.integrations.doctype.ldap_settings.ldap_settings.login": (
        "saervices_erpnext_sso_guard.password_login.ldap_login"
    ),
    "frappe.www.login.login_via_key": (
        "saervices_erpnext_sso_guard.password_login.login_via_key"
    ),
    "frappe.core.doctype.user.user.impersonate": (
        "saervices_erpnext_sso_guard.password_login.impersonate"
    ),
    "frappe.core.doctype.user.user.generate_keys": (
        "saervices_erpnext_sso_guard.password_login.generate_keys"
    ),
    "frappe.client.get_password": (
        "saervices_erpnext_sso_guard.password_login.get_password"
    ),
    "frappe.desk.doctype.system_console.system_console.execute_code": (
        "saervices_erpnext_sso_guard.password_login.execute_system_console_code"
    ),
    "frappe.desk.doctype.system_console.system_console.show_processlist": (
        "saervices_erpnext_sso_guard.password_login.show_processlist"
    ),
    "frappe.desk.query_report.run": (
        "saervices_erpnext_sso_guard.password_login.run_query_report"
    ),
    "frappe.desk.page.setup_wizard.setup_wizard.setup_complete": (
        "saervices_erpnext_sso_guard.password_login.setup_complete"
    ),
    "frappe.desk.page.setup_wizard.setup_wizard.initialize_system_settings_and_user": (
        "saervices_erpnext_sso_guard.password_login.initialize_system_settings_and_user"
    ),
    "frappe.integrations.oauth2_logins.custom": (
        "saervices_erpnext_sso_guard.password_login.authentik_custom_login"
    ),
}
SERVICE_ACCOUNT_PATTERN = re.compile(
    r"(?=.{3,140}\Z)[a-z0-9][a-z0-9._+-]{0,63}@"
    r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
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


def fail(message):
    raise RuntimeError(message)


def require_env(name, pattern):
    value = os.environ.get(name, "")
    if not value or value != value.strip() or not re.fullmatch(pattern, value):
        fail(f"{name} is missing or invalid")
    if any(unicodedata.category(char).startswith("C") for char in value):
        fail(f"{name} contains control characters")
    return value


def reject_reserved_domain(value, label):
    labels = value.split(".")
    if any(value == suffix or value.endswith(f".{suffix}") for suffix in RESERVED_DNS_SUFFIXES):
        fail(f"{label} uses a reserved example or local-only DNS suffix")
    if any(not item for item in labels):
        fail(f"{label} contains an empty DNS label")


def read_secret(path, label):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or not 1 <= metadata.st_size <= MAX_SECRET_BYTES:
            fail(f"{label} must be a bounded regular file")
        payload = os.read(descriptor, MAX_SECRET_BYTES + 1)
    finally:
        os.close(descriptor)
    if len(payload) != metadata.st_size:
        fail(f"{label} changed while it was read")
    try:
        value = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"{label} is not valid UTF-8") from error
    if value == "CHANGE_ME" or value != value.strip():
        fail(f"{label} is unset or non-canonical")
    if any(unicodedata.category(char).startswith("C") for char in value):
        fail(f"{label} contains control characters")
    return value


def require_binary_setting(value, label):
    if value in (None, "", 0, "0", False):
        return 0
    if value in (1, "1", True):
        return 1
    fail(f"{label} is not a canonical binary setting")


def require_host_sso_enforced():
    value = os.environ.get("ERPNEXT_SSO_ENFORCED", "")
    if value == "true":
        return True
    if value == "false":
        return False
    fail("ERPNEXT_SSO_ENFORCED must be exactly true or false")


def parse_api_service_accounts(raw_value):
    if raw_value == "":
        return frozenset()
    values = raw_value.split(",")
    if (
        any(not SERVICE_ACCOUNT_PATTERN.fullmatch(value) for value in values)
        or len(values) != len(set(values))
        or values != sorted(values)
    ):
        fail(
            "ERPNEXT_API_SERVICE_ACCOUNTS must be an empty or sorted, unique, "
            "comma-separated list of canonical lowercase email user IDs"
        )
    return frozenset(values)


def verify_exact_app_boundary(frappe):
    from saervices_erpnext_sso_guard.runtime_manifest import (
        EXPECTED_APPS as MANIFEST_EXPECTED_APPS,
    )

    if MANIFEST_EXPECTED_APPS != EXPECTED_APPS:
        fail("ERPNext runtime-manifest application boundary drifted")
    installed = list(frappe.get_installed_apps())
    if len(installed) != len(EXPECTED_APPS) or set(installed) != EXPECTED_APPS:
        fail("installed Frappe applications differ from the exact runtime set")
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(APPS_PATH, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 4096:
            fail("Frappe apps.txt must be a bounded regular file")
        payload = os.read(descriptor, 4097)
    finally:
        os.close(descriptor)
    if payload != b"frappe\nerpnext\nsaervices_erpnext_sso_guard\n":
        fail("Frappe apps.txt differs from the exact runtime application set")


def verify_api_auth_boundary(frappe, allowed_users, get_decrypted_password):
    from saervices_erpnext_sso_guard.api_auth import (
        AUTH_HOOK,
        BEFORE_LOGIN_HOOK,
        OAUTH_CREDENTIAL_DOCTYPES,
        OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK,
        OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK,
        parse_api_service_accounts as parse_runtime_service_accounts,
        parse_host_sso_enforced as parse_runtime_host_sso_enforced,
    )

    if AUTH_HOOK != EXPECTED_AUTH_HOOK:
        fail("ERPNext SSO guard authentication hook identity drifted")
    if BEFORE_LOGIN_HOOK != EXPECTED_BEFORE_LOGIN_HOOK:
        fail("ERPNext SSO guard before-login hook identity drifted")
    if (
        OAUTH_CREDENTIAL_DOCTYPES != EXPECTED_OAUTH_CREDENTIAL_DOCTYPES
        or OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK
        != EXPECTED_OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK
        or OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK
        != EXPECTED_OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK
    ):
        fail("ERPNext OAuth credential permission-hook identity drifted")
    if parse_runtime_host_sso_enforced(
        os.environ.get("ERPNEXT_SSO_ENFORCED", "")
    ) != require_host_sso_enforced():
        fail("ERPNext SSO guard host-policy parser drifted")
    if parse_runtime_service_accounts(",".join(sorted(allowed_users))) != allowed_users:
        fail("ERPNext SSO guard service-account parser drifted")
    if tuple(frappe.get_hooks("auth_hooks", [])) != (EXPECTED_AUTH_HOOK,):
        fail("unexpected Frappe auth_hooks are installed")
    if tuple(frappe.get_hooks("before_login", [])) != (
        EXPECTED_BEFORE_LOGIN_HOOK,
    ):
        fail("unexpected Frappe before_login hooks are installed")
    effective_doc_hooks = frappe.get_doc_hooks()
    if (
        tuple(
            effective_doc_hooks.get("User", {}).get("before_validate", [])
        )
        != (EXPECTED_USER_BEFORE_VALIDATE_HOOK,)
        or tuple(
            effective_doc_hooks.get("*", {}).get("before_validate", [])
        )
    ):
        fail("unexpected effective User before_validate authentication hooks")
    extension_hooks = frappe.get_hooks("extend_doctype_class", {})
    if tuple(extension_hooks.get("User", [])) != (
        EXPECTED_USER_CONTROLLER_EXTENSION,
    ):
        fail("unexpected User controller extension hooks are installed")
    has_permission_hooks = frappe.get_hooks("has_permission", {})
    query_condition_hooks = frappe.get_hooks(
        "permission_query_conditions", {}
    )
    for doctype in EXPECTED_OAUTH_CREDENTIAL_DOCTYPES:
        if tuple(has_permission_hooks.get(doctype, [])) != (
            EXPECTED_OAUTH_CREDENTIAL_HAS_PERMISSION_HOOK,
        ) or tuple(query_condition_hooks.get(doctype, [])) != (
            EXPECTED_OAUTH_CREDENTIAL_QUERY_CONDITION_HOOK,
        ):
            fail("unexpected OAuth credential permission hooks are installed")
    from frappe.model.base_document import get_controller
    from saervices_erpnext_sso_guard.user_document import (
        SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG,
        SOCIAL_LOGIN_KEY_MUTATION_HOOK,
        UserSSOGuardMixin,
    )

    if (
        SOCIAL_LOGIN_KEY_MUTATION_HOOK
        != EXPECTED_SOCIAL_LOGIN_KEY_MUTATION_HOOK
        or SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG
        != EXPECTED_SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG
    ):
        fail("ERPNext Social Login Key guard identity drifted")
    for event in ("before_validate", "before_rename", "on_trash"):
        if tuple(
            effective_doc_hooks.get("Social Login Key", {}).get(event, [])
        ) != (EXPECTED_SOCIAL_LOGIN_KEY_MUTATION_HOOK,):
            fail("unexpected effective Social Login Key authentication hooks")
        if tuple(effective_doc_hooks.get("Report", {}).get(event, [])) != (
            EXPECTED_REPORT_MUTATION_HOOK,
        ):
            fail("unexpected effective Report security hooks")

    user_controller = get_controller("User")
    if (
        user_controller._reset_password is not UserSSOGuardMixin._reset_password
        or user_controller.set_new_password is not UserSSOGuardMixin.set_new_password
    ):
        fail("effective User controller password guard methods drifted")
    method_overrides = frappe.get_hooks("override_whitelisted_methods", {})
    for original, replacement in EXPECTED_AUTH_OVERRIDES.items():
        if (
            tuple(method_overrides.get(original, [])) != (replacement,)
            or frappe.override_whitelisted_method(original) != replacement
        ):
            fail(f"ERPNext SSO guard method override drifted for {original}")

    executable_report_rows = frappe.get_all(
        "Report",
        fields=["name", "report_type", "is_standard"],
    )
    if any(
        row.get("report_type") in {"Query Report", "Script Report"}
        and row.get("is_standard") != "Yes"
        for row in executable_report_rows
    ):
        fail("non-standard Query or Script Reports must be removed")

    verify_service_accounts_have_no_authentik_bindings(frappe, allowed_users)

    user_rows = frappe.get_all(
        "User",
        fields=["name", "enabled", "user_type", "api_key"],
    )
    users_by_name = {row.get("name"): row for row in user_rows}
    invalid_allowed_users = sorted(
        user
        for user in allowed_users
        if user not in users_by_name
        or require_binary_setting(
            users_by_name[user].get("enabled"), f"User.enabled for {user}"
        )
        != 1
        or users_by_name[user].get("user_type") != "System User"
    )
    if invalid_allowed_users:
        fail(
            "API service-account allowlist entries must be enabled System Users: "
            + ", ".join(invalid_allowed_users)
        )

    api_key_credential_users = set()
    for row in user_rows:
        user = row.get("name")
        if (
            user
            and row.get("api_key")
            and get_decrypted_password(
                "User",
                user,
                "api_secret",
                raise_exception=False,
            )
        ):
            api_key_credential_users.add(user)

    active_bearer_users = set()
    bearer_rows = frappe.get_all(
        "OAuth Bearer Token",
        fields=["user", "status"],
    )
    for row in bearer_rows:
        user = row.get("user")
        if row.get("status") == "Revoked":
            continue
        if not user:
            fail("non-revoked OAuth Bearer Token is missing its user")
        active_bearer_users.add(user)

    unexpected_users = sorted(
        (api_key_credential_users | active_bearer_users) - allowed_users
    )
    if unexpected_users:
        fail(
            "stored API or non-revoked OAuth credentials exist outside "
            "ERPNEXT_API_SERVICE_ACCOUNTS: "
            + ", ".join(unexpected_users)
        )


def verify_service_accounts_have_no_authentik_bindings(frappe, allowed_users):
    bindings = frappe.get_all(
        "User Social Login",
        filters={"provider": PROVIDER_KEY},
        fields=["parent", "parenttype", "parentfield"],
    )
    if any(
        row.get("parent") in allowed_users for row in bindings
    ):
        fail("API service accounts must not have Authentik login bindings")


def revoke_password_reset_keys(frappe):
    # Keep revocætion in the sæme dætæbæse trænsæction æs the verified
    # finæl SSO policy; no credentiæl or user identifier is logged.
    frappe.db.sql(
        """
        UPDATE `tabUser`
        SET `reset_password_key` = '',
            `last_reset_password_key_generated_on` = NULL
        WHERE COALESCE(`reset_password_key`, '') != ''
           OR `last_reset_password_key_generated_on` IS NOT NULL
        """
    )
    remaining = frappe.db.sql(
        """
        SELECT COUNT(*)
        FROM `tabUser`
        WHERE COALESCE(`reset_password_key`, '') != ''
           OR `last_reset_password_key_generated_on` IS NOT NULL
        """
    )[0][0]
    if remaining != 0:
        fail("password-reset key revocation postcondition failed")


def revoke_non_administrator_passwords(frappe):
    frappe.db.sql(
        """
        DELETE FROM `__Auth`
        WHERE `doctype` = 'User'
          AND `fieldname` = 'password'
          AND COALESCE(`name`, '') <> 'Administrator'
        """
    )
    remaining = frappe.db.sql(
        """
        SELECT COUNT(*)
        FROM `__Auth`
        WHERE `doctype` = 'User'
          AND `fieldname` = 'password'
          AND COALESCE(`name`, '') <> 'Administrator'
        """
    )[0][0]
    if remaining != 0:
        fail("non-Administrator password revocation postcondition failed")


def revoke_pending_user_invitations(frappe):
    frappe.db.sql(
        """
        UPDATE `tabUser Invitation`
        SET `status` = CASE
                WHEN `status` = 'Pending' THEN 'Cancelled'
                ELSE `status`
            END,
            `key` = NULL
        WHERE `status` = 'Pending'
           OR `key` IS NOT NULL
        """
    )
    remaining = frappe.db.sql(
        """
        SELECT COUNT(*)
        FROM `tabUser Invitation`
        WHERE `status` = 'Pending'
           OR `key` IS NOT NULL
        """
    )[0][0]
    if remaining != 0:
        fail("pending user-invitation revocation postcondition failed")


def revoke_oauth_authorization_codes(frappe):
    frappe.db.sql(
        """
        UPDATE `tabOAuth Authorization Code`
        SET `validity` = 'Invalid'
        WHERE `validity` = 'Valid'
        """
    )
    remaining = frappe.db.sql(
        """
        SELECT COUNT(*)
        FROM `tabOAuth Authorization Code`
        WHERE `validity` = 'Valid'
        """
    )[0][0]
    if remaining != 0:
        fail("OAuth authorization-code revocation postcondition failed")


def revoke_all_database_sessions(frappe):
    frappe.db.sql("DELETE FROM `tabSessions`")
    remaining = frappe.db.sql("SELECT COUNT(*) FROM `tabSessions`")[0][0]
    if remaining != 0:
        fail("database session revocation postcondition failed")


def revoke_all_cached_sessions(frappe):
    session_cache_key = frappe.cache.make_key("session")
    frappe.cache.ping()
    frappe.cache.delete(session_cache_key)
    frappe.local.cache.pop(session_cache_key, None)
    frappe.cache.ping()
    if frappe.cache.hlen(session_cache_key) != 0:
        fail("Redis session revocation postcondition failed")


def postcondition_all_sessions_revoked(frappe):
    if frappe.db.sql("SELECT COUNT(*) FROM `tabSessions`")[0][0] != 0:
        fail("post-commit database session revocation postcondition failed")
    session_cache_key = frappe.cache.make_key("session")
    frappe.cache.ping()
    if frappe.cache.hlen(session_cache_key) != 0:
        fail("post-commit Redis session revocation postcondition failed")
    frappe.cache.ping()


def scan_raw_cache_keys(cache, pattern):
    cursor = 0
    while True:
        cursor, keys = cache.scan(
            cursor=cursor,
            match=pattern,
            count=REDIS_SCAN_BATCH_SIZE,
        )
        if not isinstance(cursor, int) or cursor < 0 or not isinstance(keys, list | tuple):
            fail("Redis raw scan returned an invalid response")
        yield tuple(keys)
        if cursor == 0:
            return


def revoke_all_email_link_keys(frappe):
    pattern = frappe.cache.make_key("one_time_login_key:*")
    frappe.cache.ping()
    for _pass_number in range(1, REDIS_DELETE_MAX_PASSES + 1):
        seen = 0
        deleted = 0
        for keys in scan_raw_cache_keys(frappe.cache, pattern):
            if not keys:
                continue
            seen += len(keys)
            removed = frappe.cache.unlink(*keys)
            if (
                not isinstance(removed, int)
                or isinstance(removed, bool)
                or removed < 0
                or removed > len(keys)
            ):
                fail("Redis raw unlink returned an invalid response")
            deleted += removed
            for key in keys:
                frappe.local.cache.pop(key, None)
        if seen == 0:
            frappe.cache.ping()
            return
        if deleted == 0:
            fail("email-link login token revocation made no progress")
    fail("email-link login token revocation exceeded its bounded pass limit")


def main():
    os.umask(0o077)
    site_name = require_env(
        "ERPNEXT_SITE_NAME",
        r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
    )
    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")
    authentik_domain = require_env(
        "ERPNEXT_AUTHENTIK_DOMAIN",
        r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
    )
    reject_reserved_domain(authentik_domain, "ERPNEXT_AUTHENTIK_DOMAIN")
    sign_ups = require_env("ERPNEXT_SSO_SIGNUPS", r"Deny")
    host_sso_enforced = require_host_sso_enforced()
    api_service_accounts = parse_api_service_accounts(
        os.environ.get("ERPNEXT_API_SERVICE_ACCOUNTS", "")
    )
    client_id = read_secret("/run/secrets/ERPNEXT_OIDC_CLIENT_ID", "OIDC client ID")
    client_secret = read_secret("/run/secrets/ERPNEXT_OIDC_CLIENT_SECRET", "OIDC client secret")
    authentik_origin = f"https://{authentik_domain}"
    redirect_url = "/api/method/frappe.integrations.oauth2_logins.custom/authentik"
    expected = {
        "enable_social_login": 1,
        "social_login_provider": "Custom",
        "provider_name": PROVIDER_NAME,
        "client_id": client_id,
        "icon": None,
        "base_url": authentik_origin,
        "custom_base_url": 1,
        "authorize_url": "/application/o/authorize/",
        "access_token_url": "/application/o/token/",
        "redirect_url": redirect_url,
        "api_endpoint": "/application/o/userinfo/",
        "api_endpoint_args": None,
        "auth_url_data": json.dumps(
            {"response_type": "code", "scope": "openid email profile"},
            separators=(",", ":"),
            sort_keys=True,
        ),
        "user_id_property": "sub",
        "sign_ups": sign_ups,
        "show_in_resource_metadata": 0,
    }
    os.chdir(SITES_ROOT)
    import frappe

    try:
        frappe.init(site_name, sites_path=str(SITES_ROOT))
        frappe.connect()
        from frappe.utils.password import get_decrypted_password

        verify_exact_app_boundary(frappe)
        if (
            host_sso_enforced
            and (
                frappe.conf.get("disable_render_safe_exec") is not False
                or frappe.conf.get("server_script_enabled") is not False
            )
        ):
            fail("cached Frappe config does not enforce the safe-exec policy")
        if "authentik_login" in frappe.conf:
            fail("file-based Authentik OAuth override must be absent")
        # Setup Wizærd cæn low-level set æ pæssword ænd creæte æ session, but
        # Fræppe v16 mækes those operætions no-ops once setup is complete.
        # Enforce thæt persisted boundæry before æny SSO-policy mutætion.
        if host_sso_enforced and not require_binary_setting(
            frappe.db.get_single_value("System Settings", "setup_complete"),
            "System Settings.setup_complete",
        ):
            fail("SSO-only policy requires the ERPNext setup wizard to be complete")
        # Fræppe v16's custom cællbæck æccepts every existing key; the enæble
        # flæg only controls whether thæt key is rendered on the login pæge.
        social_login_keys = list(frappe.get_all("Social Login Key", pluck="name"))
        if social_login_keys not in ([], [PROVIDER_KEY]):
            fail(
                "alternative Social Login Key records must be removed before "
                "Authentik-only login can be enforced"
            )
        verify_api_auth_boundary(
            frappe,
            api_service_accounts,
            get_decrypted_password,
        )
        exists = bool(frappe.db.exists("Social Login Key", PROVIDER_KEY))
        if exists:
            document = frappe.get_doc("Social Login Key", PROVIDER_KEY)
        else:
            document = frappe.new_doc("Social Login Key")
        persisted_secret = (
            get_decrypted_password(
                "Social Login Key",
                PROVIDER_KEY,
                "client_secret",
                raise_exception=False,
            )
            if exists
            else None
        )
        changed = not exists or any(document.get(key) != value for key, value in expected.items())
        changed = changed or persisted_secret != client_secret
        if changed:
            document.update(expected)
            document.client_secret = client_secret
            from saervices_erpnext_sso_guard.user_document import (
                SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG,
            )

            if getattr(frappe.flags, SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG, False):
                fail("Social Login Key bootstrap bypass flag was already active")
            setattr(frappe.flags, SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG, True)
            try:
                document.save(ignore_permissions=True)
            finally:
                frappe.flags.pop(SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG, None)
            if getattr(frappe.flags, SOCIAL_LOGIN_KEY_BOOTSTRAP_FLAG, False):
                fail("Social Login Key bootstrap bypass flag remained active")
        if "authentik_login" in frappe.conf:
            fail("file-based Authentik OAuth override postcondition failed")

        # Preserve the lockout-sensitive pæssword setting. The operætor turns
        # it off only æfter two pre-provisioned mænægers hæve proven OIDC.
        frappe.db.set_single_value(
            "System Settings",
            "disable_user_pass_login",
            int(host_sso_enforced),
        )
        if host_sso_enforced:
            revoke_non_administrator_passwords(frappe)
            revoke_password_reset_keys(frappe)
            revoke_pending_user_invitations(frappe)
            revoke_oauth_authorization_codes(frappe)
            revoke_all_database_sessions(frappe)
        frappe.db.set_single_value("System Settings", "login_with_email_link", 0)
        frappe.db.set_single_value("Website Settings", "disable_signup", 1)
        frappe.db.set_single_value("LDAP Settings", "enabled", 0)
        frappe.db.set_single_value(
            "OAuth Settings",
            "enable_dynamic_client_registration",
            0,
        )

        persisted = frappe.get_doc("Social Login Key", PROVIDER_KEY)
        for key, value in expected.items():
            if persisted.get(key) != value:
                fail(f"Social Login Key postcondition failed for {key}")
        if persisted.get_password("client_secret", raise_exception=False) != client_secret:
            fail("Social Login Key secret postcondition failed")
        if list(frappe.get_all("Social Login Key", pluck="name")) != [PROVIDER_KEY]:
            fail("exclusive Authentik Social Login Key postcondition failed")
        if "authentik_login" in frappe.conf:
            fail("file-based Authentik OAuth override postcondition failed")
        if require_binary_setting(
            frappe.db.get_single_value("System Settings", "login_with_email_link"),
            "System Settings.login_with_email_link",
        ):
            fail("email-link login disablement postcondition failed")
        if not require_binary_setting(
            frappe.db.get_single_value("Website Settings", "disable_signup"),
            "Website Settings.disable_signup",
        ):
            fail("website signup disablement postcondition failed")
        if require_binary_setting(
            frappe.db.get_single_value("LDAP Settings", "enabled"),
            "LDAP Settings.enabled",
        ):
            fail("LDAP disablement postcondition failed")
        if require_binary_setting(
            frappe.db.get_single_value(
                "OAuth Settings",
                "enable_dynamic_client_registration",
            ),
            "OAuth Settings.enable_dynamic_client_registration",
        ):
            fail("OAuth dynamic client registration disablement postcondition failed")
        if (
            require_binary_setting(
                frappe.db.get_single_value("System Settings", "disable_user_pass_login"),
                "System Settings.disable_user_pass_login",
            )
            != int(host_sso_enforced)
        ):
            fail("username/password login setting does not match host policy")
        if host_sso_enforced and not require_binary_setting(
            frappe.db.get_single_value("System Settings", "setup_complete"),
            "System Settings.setup_complete",
        ):
            fail("ERPNext setup-complete postcondition failed")
        verify_service_accounts_have_no_authentik_bindings(
            frappe,
            api_service_accounts,
        )
        frappe.db.commit()
        # Publish invælidætions only æfter committed reæders cæn observe the new
        # vælues, then revoke sessions ænd links from the previous policy.
        for doctype in (
            "System Settings",
            "Website Settings",
            "LDAP Settings",
            "OAuth Settings",
        ):
            frappe.clear_cache(doctype=doctype)
        if host_sso_enforced:
            revoke_all_cached_sessions(frappe)
            postcondition_all_sessions_revoked(frappe)
        revoke_all_email_link_keys(frappe)
    except BaseException:
        if getattr(frappe.local, "db", None):
            frappe.db.rollback()
        raise
    finally:
        frappe.destroy()
    print("[OK] ERPNext Authentik Social Login Key is ready")
    if host_sso_enforced:
        print("[OK] ERPNext SSO-only login restrictions are active")
    else:
        print("[INFO] Username/password login remains enabled for staged SSO onboarding")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[FATAL] ERPNext SSO bootstrap failed: {error}", file=os.sys.stderr)
        raise SystemExit(1) from None
