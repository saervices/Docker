# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import json
import os
import re
import stat
import tempfile
import unicodedata
from pathlib import Path
from urllib.parse import quote


SITES_ROOT = Path("/home/frappe/frappe-bench/sites")
APPS_ROOT = Path("/home/frappe/frappe-bench/apps")
CONFIG_PATH = SITES_ROOT / "common_site_config.json"
APPS_PATH = SITES_ROOT / "apps.txt"
MAX_SECRET_BYTES = 4096
MAX_CONFIG_BYTES = 1024 * 1024
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


def require_env(name, pattern=None):
    value = os.environ.get(name, "")
    if not value or value != value.strip():
        fail(f"{name} is missing or non-canonical")
    if any(unicodedata.category(char).startswith("C") for char in value):
        fail(f"{name} contains control characters")
    if pattern and not re.fullmatch(pattern, value):
        fail(f"{name} has an invalid format")
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
        payload = bytearray()
        while len(payload) <= MAX_SECRET_BYTES:
            chunk = os.read(descriptor, min(4096, MAX_SECRET_BYTES + 1 - len(payload)))
            if not chunk:
                break
            payload.extend(chunk)
    finally:
        os.close(descriptor)
    if len(payload) != metadata.st_size or len(payload) > MAX_SECRET_BYTES:
        fail(f"{label} changed while it was read")
    try:
        value = bytes(payload).decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"{label} is not valid UTF-8") from error
    if value == "CHANGE_ME" or value != value.strip():
        fail(f"{label} is unset or non-canonical")
    if any(unicodedata.category(char).startswith("C") for char in value):
        fail(f"{label} contains control characters")
    return value


def validate_sites_root():
    metadata = os.lstat(SITES_ROOT)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("sites root must be a real directory")


def load_config():
    try:
        metadata = os.lstat(CONFIG_PATH)
    except FileNotFoundError:
        return {}
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("common site config must be a regular file")
    if metadata.st_size > MAX_CONFIG_BYTES:
        fail("common site config exceeds the size limit")
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(CONFIG_PATH, flags)
    try:
        payload = os.read(descriptor, MAX_CONFIG_BYTES + 1)
    finally:
        os.close(descriptor)
    try:
        config = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("common site config is not valid UTF-8 JSON") from error
    if not isinstance(config, dict):
        fail("common site config must contain a JSON object")
    return config


def write_atomic(path, payload, mode):
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        metadata = None
    if metadata is not None and (not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)):
        fail(f"{path.name} must be a regular file")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=SITES_ROOT)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb", closefd=True) as output:
            output.write(payload)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_name, path)
        directory_descriptor = os.open(SITES_ROOT, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def write_config(config):
    payload = (json.dumps(config, indent=2, sort_keys=True) + "\n").encode("utf-8")
    write_atomic(CONFIG_PATH, payload, 0o600)


def discover_apps():
    metadata = os.lstat(APPS_ROOT)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("apps root must be a real directory")
    apps = []
    for entry in APPS_ROOT.iterdir():
        if entry.name.startswith("."):
            continue
        entry_metadata = entry.lstat()
        if stat.S_ISLNK(entry_metadata.st_mode):
            fail("application entries must not be symbolic links")
        if stat.S_ISDIR(entry_metadata.st_mode):
            apps.append(entry.name)
    apps.sort()
    if not {"frappe", "erpnext"}.issubset(apps):
        fail("required Frappe applications are missing from the image")
    return apps


def main():
    os.umask(0o077)
    validate_sites_root()
    app_name = require_env("ERPNEXT_DATABASE_NAME", r"[A-Za-z0-9_-]{1,64}")
    database_user = require_env("ERPNEXT_DATABASE_USER", r"[A-Za-z0-9_-]{1,64}")
    if app_name != database_user:
        fail("ERPNext database user must match the existing application database")
    site_name = require_env(
        "ERPNEXT_SITE_NAME",
        r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
    )
    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")
    database_host = require_env("ERPNEXT_DATABASE_HOST", r"[a-z0-9][a-z0-9-]{0,252}")
    cache_host = require_env("ERPNEXT_REDIS_CACHE_HOST", r"[a-z0-9][a-z0-9-]{0,252}")
    queue_host = require_env("ERPNEXT_REDIS_QUEUE_HOST", r"[a-z0-9][a-z0-9-]{0,252}")
    database_password = read_secret(
        "/run/secrets/MARIADB_PASSWORD", "MariaDB password", minimum=12
    )
    cache_password = read_secret(
        "/run/secrets/ERPNEXT_REDIS_CACHE_PASSWORD", "Redis cache password", minimum=12
    )
    queue_password = read_secret(
        "/run/secrets/ERPNEXT_REDIS_QUEUE_PASSWORD", "Redis queue password", minimum=12
    )
    expected = {
        "db_host": database_host,
        "db_port": 3306,
        "db_type": "mariadb",
        "chromium_path": "/usr/bin/chromium-headless-shell",
        "default_site": site_name,
        "redis_cache": f"redis://:{quote(cache_password, safe='')}@{cache_host}:6379/0",
        "redis_queue": f"redis://:{quote(queue_password, safe='')}@{queue_host}:6379/0",
        "redis_socketio": f"redis://:{quote(queue_password, safe='')}@{queue_host}:6379/0",
        "socketio_port": 9000,
    }
    config = load_config()
    config.update(expected)
    write_config(config)
    apps = discover_apps()
    apps_payload = ("\n".join(apps) + "\n").encode("utf-8")
    write_atomic(APPS_PATH, apps_payload, 0o644)
    persisted = load_config()
    if any(persisted.get(key) != value for key, value in expected.items()):
        fail("common site config postcondition failed")
    if stat.S_IMODE(os.lstat(CONFIG_PATH).st_mode) != 0o600:
        fail("common site config mode postcondition failed")
    if APPS_PATH.read_bytes() != apps_payload or stat.S_IMODE(os.lstat(APPS_PATH).st_mode) != 0o644:
        fail("application inventory postcondition failed")
    if not database_password:
        fail("MariaDB password postcondition failed")
    print("[OK] ERPNext common site configuration is ready")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[FATAL] ERPNext configurator failed: {error}", file=os.sys.stderr)
        raise SystemExit(1) from None
