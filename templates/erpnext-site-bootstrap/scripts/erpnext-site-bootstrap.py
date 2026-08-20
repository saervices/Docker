# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import hashlib
import os
import re
import stat
import tempfile
import unicodedata
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


SITES_ROOT = Path("/home/frappe/frappe-bench/sites")
APPS_PATH = SITES_ROOT / "apps.txt"
COMMON_SITE_CONFIG_PATH = SITES_ROOT / "common_site_config.json"
SSO_GUARD_APP = "saervices_erpnext_sso_guard"
EXPECTED_APPS = frozenset({"frappe", "erpnext", SSO_GUARD_APP})
SSO_GUARD_ROOT = Path("/home/frappe/frappe-bench/apps") / SSO_GUARD_APP
IMAGE_RUNTIME_MANIFEST = Path("/usr/local/share/saervices-erpnext-runtime-manifest")
RUNTIME_MANIFEST_ANCHOR_ROOT = Path("/var/lib/saervices-erpnext-runtime-manifest")
SHARED_RUNTIME_MANIFEST = RUNTIME_MANIFEST_ANCHOR_ROOT / "manifest.json"
BOOTSTRAP_STATE_PATH = SITES_ROOT / ".saervices-erpnext-site-bootstrap-state"
MAX_SECRET_BYTES = 4096
MAX_RUNTIME_MANIFEST_BYTES = 1024 * 1024
MAX_BOOTSTRAP_STATE_BYTES = 4096
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


def require_host_sso_enforced():
    value = os.environ.get("ERPNEXT_SSO_ENFORCED", "")
    if value == "true":
        return True
    if value == "false":
        return False
    fail("ERPNEXT_SSO_ENFORCED must be exactly true or false")


def validate_server_script_policy(host_sso_enforced):
    if not host_sso_enforced:
        return
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(COMMON_SITE_CONFIG_PATH, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 1024 * 1024:
            fail("common site config must be a bounded regular file")
        payload = os.read(descriptor, 1024 * 1024 + 1)
    finally:
        os.close(descriptor)
    try:
        config = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("common site config is not valid UTF-8 JSON") from error
    if (
        not isinstance(config, dict)
        or config.get("disable_render_safe_exec") is not False
        or config.get("server_script_enabled") is not False
    ):
        fail(
            "host-enforced SSO requires disable_render_safe_exec=false "
            "and server_script_enabled=false"
        )


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


def ensure_sso_guard_on_bench():
    try:
        app_metadata = os.lstat(SSO_GUARD_ROOT)
    except FileNotFoundError:
        fail("immutable ERPNext SSO guard application is missing")
    if not stat.S_ISDIR(app_metadata.st_mode) or stat.S_ISLNK(app_metadata.st_mode):
        fail("immutable ERPNext SSO guard application path is unsafe")
    required_files = (
        "__init__.py",
        "api_auth.py",
        "hooks.py",
        "modules.txt",
        "password_login.py",
        "patches.txt",
        "runtime_manifest.py",
        "user_document.py",
    )
    package_root = SSO_GUARD_ROOT / SSO_GUARD_APP
    for name in required_files:
        metadata = os.lstat(package_root / name)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail(f"immutable ERPNext SSO guard file is unsafe: {name}")

    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(APPS_PATH, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 65536:
            fail("Frappe apps.txt must be a bounded regular file")
        payload = os.read(descriptor, 65537)
    finally:
        os.close(descriptor)
    try:
        apps = payload.decode("utf-8").splitlines()
    except UnicodeDecodeError as error:
        raise RuntimeError("Frappe apps.txt is not valid UTF-8") from error
    if (
        not apps
        or any(not re.fullmatch(r"[a-z][a-z0-9_]*", app) for app in apps)
        or len(apps) != len(set(apps))
    ):
        fail("Frappe apps.txt is not a canonical unique application list")
    if apps != ["frappe", "erpnext", SSO_GUARD_APP]:
        fail("Frappe apps.txt contains an unexpected application")


def read_runtime_manifest(path, label, maximum=MAX_RUNTIME_MANIFEST_BYTES):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        before = os.fstat(descriptor)
        if (
            not stat.S_ISREG(before.st_mode)
            or before.st_size < 1
            or before.st_size > maximum
        ):
            fail(f"{label} must be a bounded regular file")
        payload = os.read(descriptor, maximum + 1)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if (
        len(payload) != before.st_size
        or before.st_dev != after.st_dev
        or before.st_ino != after.st_ino
        or before.st_size != after.st_size
        or before.st_mtime_ns != after.st_mtime_ns
    ):
        fail(f"{label} changed while it was read")
    return payload


def canonical_bootstrap_state(site_name, database_name):
    return (
        json.dumps(
            {
                "database": database_name,
                "phase": "creating",
                "schema": 1,
                "site": site_name,
            },
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        + b"\n"
    )


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def path_entry_exists(path):
    try:
        os.lstat(path)
    except FileNotFoundError:
        return False
    return True


def reject_unfinished_bootstrap_state(site_name, database_name):
    if not path_entry_exists(BOOTSTRAP_STATE_PATH):
        return
    try:
        payload = read_runtime_manifest(
            BOOTSTRAP_STATE_PATH,
            "site-bootstrap state marker",
            MAX_BOOTSTRAP_STATE_BYTES,
        )
    except Exception as error:
        raise RuntimeError(
            "site-bootstrap state marker is unsafe; manual recovery is required"
        ) from error
    if (
        payload != canonical_bootstrap_state(site_name, database_name)
    ):
        fail("unknown site-bootstrap state marker requires manual recovery")
    fail("an interrupted site bootstrap requires manual database recovery")


def publish_bootstrap_state(site_name, database_name):
    if path_entry_exists(BOOTSTRAP_STATE_PATH):
        fail("site-bootstrap state marker already exists")
    payload = canonical_bootstrap_state(site_name, database_name)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{BOOTSTRAP_STATE_PATH.name}.",
        dir=SITES_ROOT,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.link(temporary_path, BOOTSTRAP_STATE_PATH, follow_symlinks=False)
        temporary_path.unlink()
        fsync_directory(SITES_ROOT)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
    if read_runtime_manifest(
        BOOTSTRAP_STATE_PATH,
        "site-bootstrap state marker",
        MAX_BOOTSTRAP_STATE_BYTES,
    ) != payload:
        fail("site-bootstrap state marker publication postcondition failed")


def clear_bootstrap_state():
    metadata = os.lstat(BOOTSTRAP_STATE_PATH)
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("site-bootstrap state marker is unsafe")
    BOOTSTRAP_STATE_PATH.unlink()
    fsync_directory(SITES_ROOT)


def database_is_empty(database_name, database_host, database_password):
    import pymysql

    try:
        connection = pymysql.connect(
            host=database_host,
            port=3306,
            user=database_name,
            password=database_password,
            database=database_name,
            connect_timeout=10,
            read_timeout=10,
            write_timeout=10,
        )
        try:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        (SELECT COUNT(*) FROM information_schema.tables
                         WHERE table_schema = %s)
                      + (SELECT COUNT(*) FROM information_schema.routines
                         WHERE routine_schema = %s)
                      + (SELECT COUNT(*) FROM information_schema.events
                         WHERE event_schema = %s)
                      + (SELECT COUNT(*) FROM information_schema.triggers
                         WHERE trigger_schema = %s)
                    """,
                    (database_name,) * 4,
                )
                row = cursor.fetchone()
        finally:
            connection.close()
    except Exception as error:
        raise RuntimeError("target database emptiness could not be verified") from error
    return bool(row and row[0] == 0)


def validate_manifest_anchor_root():
    metadata = os.lstat(RUNTIME_MANIFEST_ANCHOR_ROOT)
    if (
        not stat.S_ISDIR(metadata.st_mode)
        or stat.S_ISLNK(metadata.st_mode)
        or stat.S_IMODE(metadata.st_mode) != 0o750
        or metadata.st_uid != 1000
        or metadata.st_gid != 1000
    ):
        fail("runtime-manifest anchor mount has an unsafe identity or mode")


def publish_runtime_manifest(*, mode):
    from saervices_erpnext_sso_guard.runtime_manifest import validate_manifest_bytes

    if mode not in {"existing", "fresh", "rotate"}:
        fail("unknown runtime-manifest reconciliation mode")
    validate_manifest_anchor_root()
    payload = read_runtime_manifest(IMAGE_RUNTIME_MANIFEST, "image runtime manifest")
    validate_manifest_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    approval = os.environ.get("ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256", "")
    if approval and not re.fullmatch(r"[0-9a-f]{64}", approval):
        fail("ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256 is invalid")
    if mode == "rotate" and approval != digest:
        fail("runtime-manifest rotation requires approval for the exact image digest")
    if mode != "rotate" and approval:
        fail("runtime-manifest approval is accepted only in explicit rotation mode")
    try:
        target_metadata = os.lstat(SHARED_RUNTIME_MANIFEST)
    except FileNotFoundError:
        target_metadata = None
    if target_metadata is not None and (
        not stat.S_ISREG(target_metadata.st_mode)
        or stat.S_ISLNK(target_metadata.st_mode)
    ):
        fail("shared runtime manifest target is unsafe")

    current_payload = None
    if target_metadata is not None:
        try:
            current_payload = read_runtime_manifest(
                SHARED_RUNTIME_MANIFEST,
                "shared runtime manifest",
            )
            validate_manifest_bytes(current_payload)
        except Exception:
            current_payload = None
    if current_payload == payload:
        return
    if mode == "existing":
        fail("existing site runtime manifest is missing, invalid, or mismatched")
    if mode == "fresh" and target_metadata is not None:
        fail("fresh-site runtime manifest conflicts with the existing trust anchor")

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{SHARED_RUNTIME_MANIFEST.name}.",
        dir=RUNTIME_MANIFEST_ANCHOR_ROOT,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, SHARED_RUNTIME_MANIFEST)
        fsync_directory(RUNTIME_MANIFEST_ANCHOR_ROOT)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
    if read_runtime_manifest(
        SHARED_RUNTIME_MANIFEST,
        "shared runtime manifest",
    ) != payload:
        fail("shared runtime manifest publication postcondition failed")


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


def verify_frappe_state(site_name, expected_timezone, expected_admin_password):
    import frappe
    from frappe.installer import install_app
    from frappe.utils.logger import set_log_level
    from frappe.utils.password import check_password
    from frappe.utils.scheduler import enable_scheduler, is_scheduler_inactive

    try:
        frappe.init(site_name, sites_path=str(SITES_ROOT))
        set_log_level("ERROR")
        frappe.connect()
        if (
            require_host_sso_enforced()
            and (
                frappe.conf.get("disable_render_safe_exec") is not False
                or frappe.conf.get("server_script_enabled") is not False
            )
        ):
            fail("cached Frappe config does not enforce the safe-exec policy")
        installed_values = list(frappe.get_installed_apps())
        installed = set(installed_values)
        if SSO_GUARD_APP not in installed:
            if len(installed_values) != 2 or installed != {"frappe", "erpnext"}:
                fail("unexpected installed Frappe application before guard install")
            install_app(SSO_GUARD_APP)
            installed_values = list(frappe.get_installed_apps())
            installed = set(installed_values)
        if len(installed_values) != len(EXPECTED_APPS) or installed != EXPECTED_APPS:
            fail("installed Frappe applications differ from the exact runtime set")
        if not frappe.db.exists("User", "Administrator"):
            fail("Administrator postcondition is missing")
        try:
            check_password(
                "Administrator",
                expected_admin_password,
                delete_tracker_cache=False,
            )
        except frappe.AuthenticationError:
            fail("ERPNext Administrator password does not match the deployment secret")
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


def main(arguments=None):
    os.umask(0o077)
    arguments = [] if arguments is None else list(arguments)
    if arguments == ["--rotate-runtime-manifest"]:
        publish_runtime_manifest(mode="rotate")
        print("[OK] ERPNext runtime-manifest trust anchor rotated")
        return
    if arguments:
        fail("unsupported site-bootstrap argument")
    host_sso_enforced = require_host_sso_enforced()
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
    validate_server_script_policy(host_sso_enforced)
    reject_unfinished_bootstrap_state(site_name, database_name)
    sites = existing_sites()
    ensure_sso_guard_on_bench()
    if sites and sites != [site_name]:
        fail("single-site deployment contains an unexpected site")
    site_path = SITES_ROOT / site_name
    if path_entry_exists(site_path):
        if site_name not in sites:
            fail("unrecognized partial site directory requires manual recovery")
        publish_runtime_manifest(mode="existing")
        validate_site_config(site_name, database_name, database_host, database_password)
        verify_frappe_state(site_name, site_timezone, admin_password)
        publish_runtime_manifest(mode="existing")
        print("[OK] ERPNext site is already initialized")
        return
    if not database_is_empty(database_name, database_host, database_password):
        fail("non-empty target database without a complete site requires manual recovery")
    publish_bootstrap_state(site_name, database_name)
    import frappe
    from frappe.installer import _new_site
    from frappe.utils import CallbackManager
    from frappe.utils.logger import set_log_level

    rollback_callback = CallbackManager()
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
            install_apps=["erpnext", SSO_GUARD_APP],
            db_password=database_password,
            db_type="mariadb",
            db_host=database_host,
            db_port=3306,
            db_user=database_name,
            setup_db=False,
            rollback_callback=rollback_callback,
        )
    except Exception:
        recovery_clean = False
        try:
            rollback_callback.run()
            recovery_clean = (
                not path_entry_exists(site_path)
                and database_is_empty(
                    database_name,
                    database_host,
                    database_password,
                )
            )
        except Exception:
            recovery_clean = False
        if recovery_clean:
            clear_bootstrap_state()
        raise
    else:
        rollback_callback.reset()
    finally:
        frappe.destroy()
    initialize_site_timezone(site_name, site_timezone)
    validate_site_config(site_name, database_name, database_host, database_password)
    verify_frappe_state(site_name, site_timezone, admin_password)
    if existing_sites() != [site_name]:
        fail("single-site postcondition failed")
    publish_runtime_manifest(mode="fresh")
    clear_bootstrap_state()
    print("[OK] ERPNext site bootstrap completed")


if __name__ == "__main__":
    try:
        main(os.sys.argv[1:])
    except Exception as error:
        print(f"[FATAL] ERPNext site bootstrap failed: {error}", file=os.sys.stderr)
        raise SystemExit(1) from None
