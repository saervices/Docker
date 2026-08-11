# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import os
import re
import stat
import unicodedata
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


SITES_ROOT = Path("/home/frappe/frappe-bench/sites")
MAX_SECRET_BYTES = 4096
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


def require_timezone(name):
    value = require_env(name, r"[A-Za-z0-9_+./-]{1,255}")
    try:
        ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError):
        fail(f"{name} is not a valid IANA timezone")
    return value


def reject_reserved_domain(value, label):
    labels = value.split(".")
    if any(value == suffix or value.endswith(f".{suffix}") for suffix in RESERVED_DNS_SUFFIXES):
        fail(f"{label} uses a reserved example or local-only DNS suffix")
    if any(not item for item in labels):
        fail(f"{label} contains an empty DNS label")


def read_secret(path, label, minimum=1):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            fail(f"{label} must be a regular file")
        if metadata.st_size < minimum or metadata.st_size > MAX_SECRET_BYTES:
            fail(f"{label} has an invalid length")
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


def existing_sites():
    result = []
    for entry in SITES_ROOT.iterdir():
        if entry.name.startswith(".") or entry.name in {"assets"}:
            continue
        try:
            metadata = entry.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(metadata.st_mode):
            fail("site entries must not be symbolic links")
        if stat.S_ISDIR(metadata.st_mode) and (entry / "site_config.json").exists():
            result.append(entry.name)
    return sorted(result)


def validate_site_config(site_name, database_name, database_host, database_password):
    config_path = SITES_ROOT / site_name / "site_config.json"
    metadata = os.lstat(config_path)
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("site config must be a regular file")
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(config_path, flags)
    try:
        payload = os.read(descriptor, 1024 * 1024 + 1)
    finally:
        os.close(descriptor)
    try:
        config = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("site config is not valid UTF-8 JSON") from error
    expected = {
        "db_name": database_name,
        "db_password": database_password,
        "db_host": database_host,
        "db_type": "mariadb",
    }
    if not isinstance(config, dict) or any(config.get(key) != value for key, value in expected.items()):
        fail("site database configuration does not match the deployment contract")
    if config.get("db_user", database_name) != database_name:
        fail("site database user does not match the deployment contract")
    os.chmod(config_path, 0o600, follow_symlinks=False)


def verify_frappe_state(site_name, expected_timezone):
    import frappe
    from frappe.utils.logger import set_log_level
    from frappe.utils.scheduler import enable_scheduler, is_scheduler_inactive

    try:
        frappe.init(site_name, sites_path=str(SITES_ROOT))
        set_log_level("ERROR")
        frappe.connect()
        installed = set(frappe.get_installed_apps())
        if "frappe" not in installed or "erpnext" not in installed:
            fail("required Frappe applications are not installed")
        if not frappe.db.exists("User", "Administrator"):
            fail("Administrator postcondition is missing")
        if (
            frappe.db.get_single_value("System Settings", "time_zone")
            != expected_timezone
        ):
            fail("persisted ERPNext site timezone does not match ERPNEXT_SITE_TIMEZONE")
        if frappe.db.get_single_value("Print Settings", "pdf_generator") != "chrome":
            frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")
            frappe.db.commit()
        if frappe.db.get_single_value("Print Settings", "pdf_generator") != "chrome":
            fail("ERPNext Print Settings PDF generator postcondition failed")
        if is_scheduler_inactive(verbose=False):
            enable_scheduler()
            frappe.db.commit()
        if is_scheduler_inactive(verbose=False):
            fail("scheduler enablement postcondition failed")
    finally:
        frappe.destroy()


def initialize_site_timezone(site_name, timezone):
    import frappe

    try:
        frappe.init(site_name, sites_path=str(SITES_ROOT))
        frappe.connect()
        frappe.db.set_single_value("System Settings", "time_zone", timezone)
        frappe.db.set_value(
            "User",
            {"name": ("in", frappe.STANDARD_USERS)},
            "time_zone",
            timezone,
        )
        frappe.cache.delete_value("time_zone")
        frappe.db.commit()
    except Exception:
        if getattr(frappe.local, "db", None):
            frappe.db.rollback()
        raise
    finally:
        frappe.destroy()


def main():
    os.umask(0o077)
    site_name = require_env(
        "ERPNEXT_SITE_NAME",
        r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
    )
    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")
    site_timezone = require_timezone("ERPNEXT_SITE_TIMEZONE")
    database_name = require_env("ERPNEXT_DATABASE_NAME", r"[A-Za-z0-9_-]{1,64}")
    database_host = require_env("ERPNEXT_DATABASE_HOST", r"[a-z0-9][a-z0-9-]{0,252}")
    database_password = read_secret("/run/secrets/MARIADB_PASSWORD", "MariaDB password")
    admin_password = read_secret(
        "/run/secrets/ERPNEXT_ADMIN_PASSWORD", "ERPNext Administrator password", minimum=12
    )
    root_metadata = os.lstat(SITES_ROOT)
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        fail("sites root must be a real directory")
    # Fræppe v16 resolves its shæred `../logs` pæth from the sites working
    # directory. Keep both fresh-site ænd idempotent existing-site brænches on
    # thæt vendor contræct before æny Fræppe import or dætæbæse connection.
    os.chdir(SITES_ROOT)
    sites = existing_sites()
    if sites and sites != [site_name]:
        fail("single-site deployment contains an unexpected site")
    site_path = SITES_ROOT / site_name
    if site_path.exists():
        validate_site_config(site_name, database_name, database_host, database_password)
        verify_frappe_state(site_name, site_timezone)
        print("[OK] ERPNext site is already initialized")
        return
    import frappe
    from frappe.installer import _new_site
    from frappe.utils.logger import set_log_level

    try:
        # Fræppe v16's public `bench new-site` commænd mærks the site æs new
        # before delegæting to `_new_site`. Without this initiælizætion,
        # `get_site_config` rejects the intentionælly not-yet-creæted site.
        frappe.init(
            site_name,
            sites_path=str(SITES_ROOT),
            new_site=True,
        )
        # Fræppe's WARNING dætæbæse logger includes full DDL; setup/restore
        # DDL cæn embed the æpplicætion-dætæbæse secret in IDENTIFIED BY.
        set_log_level("ERROR")
        _new_site(
            db_name=database_name,
            site=site_name,
            admin_password=admin_password,
            install_apps=["erpnext"],
            db_password=database_password,
            db_type="mariadb",
            db_host=database_host,
            db_port=3306,
            db_user=database_name,
            setup_db=False,
        )
    finally:
        frappe.destroy()
    initialize_site_timezone(site_name, site_timezone)
    validate_site_config(site_name, database_name, database_host, database_password)
    verify_frappe_state(site_name, site_timezone)
    if existing_sites() != [site_name]:
        fail("single-site postcondition failed")
    print("[OK] ERPNext site bootstrap completed")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[FATAL] ERPNext site bootstrap failed: {error}", file=os.sys.stderr)
        raise SystemExit(1) from None
