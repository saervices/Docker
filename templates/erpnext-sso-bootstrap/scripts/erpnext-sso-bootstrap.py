# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import os
import re
import stat
import unicodedata
from pathlib import Path


SITES_ROOT = Path("/home/frappe/frappe-bench/sites")
MAX_SECRET_BYTES = 4096
PROVIDER_NAME = "Authentik"
PROVIDER_KEY = "authentik"
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
    client_id = read_secret("/run/secrets/ERPNEXT_OIDC_CLIENT_ID", "OIDC client ID")
    client_secret = read_secret("/run/secrets/ERPNEXT_OIDC_CLIENT_SECRET", "OIDC client secret")
    authentik_origin = f"https://{authentik_domain}"
    redirect_url = "/api/method/frappe.integrations.oauth2_logins.custom/authentik"
    expected = {
        "enable_social_login": 1,
        "social_login_provider": "Custom",
        "provider_name": PROVIDER_NAME,
        "client_id": client_id,
        "icon": "fa fa-lock",
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
            document.save(ignore_permissions=True)
            frappe.db.commit()
        persisted = frappe.get_doc("Social Login Key", PROVIDER_KEY)
        for key, value in expected.items():
            if persisted.get(key) != value:
                fail(f"Social Login Key postcondition failed for {key}")
        if persisted.get_password("client_secret", raise_exception=False) != client_secret:
            fail("Social Login Key secret postcondition failed")
    except BaseException:
        if getattr(frappe.local, "db", None):
            frappe.db.rollback()
        raise
    finally:
        frappe.destroy()
    print("[OK] ERPNext Authentik Social Login Key is ready")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[FATAL] ERPNext SSO bootstrap failed: {error}", file=os.sys.stderr)
        raise SystemExit(1) from None
