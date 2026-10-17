# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

import argparse
import hashlib
import hmac
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


MANIFEST_SCHEMA = 1
# Instæll order. Læter æpps declære the eærlier ones æs required_æpps.
# The tuple is the bæked code list. Site instællætion follows the swiches.
CANONICAL_APPS = (
    "frappe",
    "erpnext",
    "erpnext_germany",
    "eu_einvoice",
    "erpnext_datev",
    "payments",
    "hrms",
    "lms",
    "education",
    "lending",
    "healthcare",
    "webshop",
    "whatsapp",
    "telephony",
    "helpdesk",
    "builder",
    "wiki",
    "drive",
    "studio",
    "print_designer",
    "gameplan",
    "saervices_erpnext_sso_guard",
)
EXPECTED_APPS = frozenset(CANONICAL_APPS)
FIXED_APPS = ("frappe", "erpnext", "saervices_erpnext_sso_guard")
# Optionæl æpps in the sæme order æs CANONICAL_APPS. True is the fresh-site defæult.
OPTIONAL_APP_DEFAULTS = (
    ("erpnext_germany", True),
    ("eu_einvoice", True),
    ("erpnext_datev", False),
    ("payments", True),
    ("hrms", True),
    ("lms", False),
    ("education", False),
    ("lending", False),
    ("healthcare", False),
    ("webshop", False),
    ("whatsapp", False),
    ("telephony", False),
    ("helpdesk", False),
    ("builder", False),
    ("wiki", False),
    ("drive", False),
    ("studio", False),
    ("print_designer", True),
    ("gameplan", False),
)
APP_REQUIREMENTS = {
    "webshop": ("payments",),
    "lms": ("payments",),
    "helpdesk": ("telephony",),
}
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_INVENTORY_FILE_BYTES = 1024 * 1024 * 1024
BENCH_ROOT = Path("/home/frappe/frappe-bench")
DPKG_STATUS_PATH = Path("/var/lib/dpkg/status")
VERSION_PATTERN = re.compile(r"[0-9]+(?:\.[0-9]+)+(?:[a-z0-9.+-]*)?")


def canonical_apps_payload():
    return ("\n".join(CANONICAL_APPS) + "\n").encode("ascii")


def _fail(message):
    raise RuntimeError(message)


def app_switch_name(app_name):
    return "ERPNEXT_ENABLE_" + app_name.upper()


def assert_app_contract():
    optional_names = tuple(name for name, _default in OPTIONAL_APP_DEFAULTS)
    if CANONICAL_APPS[:2] != ("frappe", "erpnext"):
        _fail("baked application order must start with frappe and erpnext")
    if CANONICAL_APPS[-1] != "saervices_erpnext_sso_guard":
        _fail("baked application order must end with the SSO guard")
    if CANONICAL_APPS[2:-1] != optional_names:
        _fail("optional application order drifted")
    if set(APP_REQUIREMENTS) - set(optional_names):
        _fail("application requirement names an unknown optional application")
    for app_name, requirements in APP_REQUIREMENTS.items():
        for requirement in requirements:
            if requirement not in CANONICAL_APPS:
                _fail("application requirement is not baked")
            if CANONICAL_APPS.index(requirement) > CANONICAL_APPS.index(app_name):
                _fail("application requirement is ordered after its dependent application")


def resolve_enabled_apps(environ):
    assert_app_contract()
    enabled = []
    for app_name, default in OPTIONAL_APP_DEFAULTS:
        raw = environ.get(app_switch_name(app_name))
        if raw is None or raw == "":
            enabled_now = default
        elif raw == "true":
            enabled_now = True
        elif raw == "false":
            enabled_now = False
        else:
            _fail(f"{app_switch_name(app_name)} must be true or false")
        if enabled_now:
            enabled.append(app_name)
    return tuple(enabled)


def selected_apps(enabled):
    chosen = set(FIXED_APPS) | set(enabled)
    return tuple(app_name for app_name in CANONICAL_APPS if app_name in chosen)


def require_enabled_dependencies(enabled, already_installed):
    available = set(selected_apps(enabled)) | set(already_installed)
    for app_name in enabled:
        for requirement in APP_REQUIREMENTS.get(app_name, ()):
            if requirement not in available:
                _fail(
                    f"{app_switch_name(app_name)} requires "
                    f"{app_switch_name(requirement)} or an already installed dependency"
                )


def missing_selected_apps(enabled, installed):
    present = set(installed)
    return tuple(
        app_name for app_name in selected_apps(enabled) if app_name not in present
    )


def fresh_site_install_apps(enabled):
    return tuple(
        app_name for app_name in selected_apps(enabled) if app_name != "frappe"
    )


def assert_installed_selection(installed, enabled, previously_installed):
    if len(installed) != len(set(installed)):
        _fail("installed Frappe applications are not unique")
    installed_set = set(installed)
    if installed_set - set(CANONICAL_APPS):
        _fail("installed Frappe applications differ from the baked runtime set")
    if set(selected_apps(enabled)) - installed_set:
        _fail("enabled Frappe applications are not installed")
    disabled_new = (installed_set - set(previously_installed)) - set(selected_apps(enabled))
    if disabled_new:
        _fail("a disabled Frappe application was installed")


def _read_regular_bytes(path, label, maximum):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
            _fail(f"{label} must be a bounded regular file")
        payload = bytearray()
        while len(payload) <= maximum:
            chunk = os.read(descriptor, min(1024 * 1024, maximum + 1 - len(payload)))
            if not chunk:
                break
            payload.extend(chunk)
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
        _fail(f"{label} changed while it was read")
    return bytes(payload)


def _canonical_version(value, label):
    if not isinstance(value, str) or not VERSION_PATTERN.fullmatch(value):
        _fail(f"{label} version is not canonical")
    return value


def _hash_regular_file(path, label, maximum):
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
            _fail(f"{label} must be a bounded regular file")
        digest = hashlib.sha256()
        total = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            if total > maximum:
                _fail(f"{label} is oversized")
            digest.update(chunk)
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if (
        total != before.st_size
        or before.st_dev != after.st_dev
        or before.st_ino != after.st_ino
        or before.st_size != after.st_size
        or before.st_mtime_ns != after.st_mtime_ns
    ):
        _fail(f"{label} changed while it was read")
    return digest.digest()


def _is_excluded(relative_path):
    return (
        ".git" in relative_path.parts
        or "__pycache__" in relative_path.parts
        or relative_path.name.endswith(".pyc")
    )


def _inventory_tree(root, label):
    root_metadata = os.lstat(root)
    if not stat.S_ISDIR(root_metadata.st_mode) or stat.S_ISLNK(root_metadata.st_mode):
        _fail(f"{label} tree root must be a real directory")

    entries = []
    pending = [Path(".")]
    while pending:
        relative_directory = pending.pop()
        directory = root if relative_directory == Path(".") else root / relative_directory
        with os.scandir(directory) as iterator:
            children = sorted(iterator, key=lambda item: os.fsencode(item.name))
        for child in children:
            relative_path = (
                Path(child.name)
                if relative_directory == Path(".")
                else relative_directory / child.name
            )
            if _is_excluded(relative_path):
                continue
            metadata = child.stat(follow_symlinks=False)
            if stat.S_ISDIR(metadata.st_mode):
                pending.append(relative_path)
                continue
            path_bytes = os.fsencode(relative_path.as_posix())
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISREG(metadata.st_mode):
                content_digest = _hash_regular_file(
                    root / relative_path,
                    f"{label} tree member",
                    MAX_INVENTORY_FILE_BYTES,
                )
                entries.append((b"F", path_bytes, mode, content_digest))
                continue
            if stat.S_ISLNK(metadata.st_mode):
                target = os.fsencode(os.readlink(root / relative_path))
                entries.append((b"L", path_bytes, mode, target))
                continue
            _fail(f"{label} tree contains an unsupported filesystem object")

    digest = hashlib.sha256()
    for kind, path_bytes, mode, payload in sorted(
        entries, key=lambda item: (item[1], item[0])
    ):
        digest.update(kind)
        digest.update(len(path_bytes).to_bytes(8, "big"))
        digest.update(path_bytes)
        digest.update(mode.to_bytes(4, "big"))
        digest.update(len(payload).to_bytes(8, "big"))
        digest.update(payload)
    return {"entries": len(entries), "sha256": digest.hexdigest()}


def _pip_freeze_all():
    environment = {
        "HOME": "/nonexistent",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        "PIP_DISABLE_PIP_VERSION_CHECK": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    result = subprocess.run(
        [sys.executable, "-m", "pip", "freeze", "--all"],
        check=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        text=True,
        encoding="utf-8",
        timeout=120,
    )
    if len(result.stdout.encode("utf-8")) > MAX_MANIFEST_BYTES:
        _fail("pip freeze inventory is oversized")
    lines = result.stdout.splitlines()
    if (
        not lines
        or any(not line or len(line.encode("utf-8")) > 4096 for line in lines)
        or len(lines) != len(set(lines))
    ):
        _fail("pip freeze inventory is not canonical")
    return sorted(lines)


def build_manifest_bytes(bench_root=None):
    import erpnext
    import frappe

    if bench_root is None:
        bench_root = BENCH_ROOT
    apps_root = Path(bench_root) / "apps"
    dpkg_status = _read_regular_bytes(
        DPKG_STATUS_PATH,
        "dpkg status",
        MAX_INVENTORY_FILE_BYTES,
    )
    document = {
        "apps": sorted(EXPECTED_APPS),
        "dpkg_status_sha256": hashlib.sha256(dpkg_status).hexdigest(),
        "pip_freeze_all": _pip_freeze_all(),
        "schema": MANIFEST_SCHEMA,
        "trees": {
            app_name: _inventory_tree(apps_root / app_name, app_name)
            for app_name in CANONICAL_APPS
        },
        "versions": {
            "erpnext": _canonical_version(erpnext.__version__, "ERPNext"),
            "frappe": _canonical_version(frappe.__version__, "Frappe"),
        },
    }
    payload = (
        json.dumps(document, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("ascii")
    if len(payload) > MAX_MANIFEST_BYTES:
        _fail("runtime manifest is oversized")
    validate_manifest_bytes(payload)
    return payload


def validate_manifest_bytes(payload):
    if not payload or len(payload) > MAX_MANIFEST_BYTES or not payload.endswith(b"\n"):
        _fail("runtime manifest bytes are not canonical")
    try:
        document = json.loads(payload.decode("ascii"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("runtime manifest is not canonical JSON") from error
    if (
        not isinstance(document, dict)
        or document.get("schema") != MANIFEST_SCHEMA
        or set(document)
        != {"apps", "dpkg_status_sha256", "pip_freeze_all", "schema", "trees", "versions"}
        or document.get("apps") != sorted(EXPECTED_APPS)
        or set(document.get("trees", {})) != set(CANONICAL_APPS)
        or set(document.get("versions", {})) != {"erpnext", "frappe"}
    ):
        _fail("runtime manifest schema is invalid")
    canonical = (
        json.dumps(document, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
        + "\n"
    ).encode("ascii")
    if canonical != payload:
        _fail("runtime manifest encoding is not canonical")
    for name, inventory in document["trees"].items():
        if (
            not isinstance(inventory, dict)
            or set(inventory) != {"entries", "sha256"}
            or not isinstance(inventory["entries"], int)
            or isinstance(inventory["entries"], bool)
            or inventory["entries"] <= 0
            or not re.fullmatch(r"[0-9a-f]{64}", inventory["sha256"])
        ):
            _fail(f"runtime manifest {name} inventory is invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", document["dpkg_status_sha256"]):
        _fail("runtime manifest dpkg digest is invalid")
    lines = document["pip_freeze_all"]
    if (
        not isinstance(lines, list)
        or not lines
        or any(not isinstance(line, str) or not line for line in lines)
        or lines != sorted(lines)
        or len(lines) != len(set(lines))
    ):
        _fail("runtime manifest pip inventory is invalid")
    for name, version in document["versions"].items():
        _canonical_version(version, name)
    return document


def write_runtime_manifest(path):
    target = Path(path)
    parent_metadata = os.lstat(target.parent)
    if not stat.S_ISDIR(parent_metadata.st_mode) or stat.S_ISLNK(parent_metadata.st_mode):
        _fail("runtime manifest parent must be a real directory")
    try:
        target_metadata = os.lstat(target)
    except FileNotFoundError:
        target_metadata = None
    if target_metadata is not None and (
        not stat.S_ISREG(target_metadata.st_mode)
        or stat.S_ISLNK(target_metadata.st_mode)
    ):
        _fail("runtime manifest target is unsafe")
    payload = build_manifest_bytes()
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{target.name}.",
        dir=target.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, target)
        directory_descriptor = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            temporary_path.unlink()
        except FileNotFoundError:
            pass
    if _read_regular_bytes(target, "runtime manifest", MAX_MANIFEST_BYTES) != payload:
        _fail("runtime manifest publication postcondition failed")


def compare_runtime_manifests(expected_path, actual_path):
    expected = _read_regular_bytes(
        expected_path,
        "image runtime manifest",
        MAX_MANIFEST_BYTES,
    )
    actual = _read_regular_bytes(
        actual_path,
        "shared runtime manifest",
        MAX_MANIFEST_BYTES,
    )
    validate_manifest_bytes(expected)
    validate_manifest_bytes(actual)
    if not hmac.compare_digest(expected, actual):
        _fail("ERPNext runtime manifest mismatch")


assert_app_contract()


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("command", choices=("compare",))
    parser.add_argument("expected")
    parser.add_argument("actual")
    arguments = parser.parse_args()
    if arguments.command == "compare":
        compare_runtime_manifests(arguments.expected, arguments.actual)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"ERPNext runtime manifest validation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None
