#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Docker-freie, fæil-closed ERPNext-Stæckregression mit negætiven /tmp-Fixtures."""

from __future__ import annotations

import ast
import copy
import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable

import yaml


REPO_ROOT = Path(__file__).resolve().parents[2]

EXPECTED_REQUIRED_SERVICES = (
    "mariadb",
    "mariadb_maintenance",
    "erpnext-redis-cache",
    "erpnext-redis-queue",
    "erpnext-assets-bootstrap",
    "erpnext-configurator",
    "erpnext-site-bootstrap",
    "erpnext-migrator",
    "erpnext-sso-bootstrap",
    "erpnext-backend",
    "erpnext-websocket",
    "erpnext-worker-short",
    "erpnext-worker-long",
    "erpnext-scheduler",
    "erpnext-site-maintenance",
)

EXPECTED_ERPNEXT_TEMPLATES = frozenset(
    service for service in EXPECTED_REQUIRED_SERVICES if service.startswith("erpnext-")
)

STOCK_FRAPPE_SERVICES = (
    "app",
    "erpnext-assets-bootstrap",
    "erpnext-configurator",
    "erpnext-site-bootstrap",
    "erpnext-migrator",
    "erpnext-sso-bootstrap",
    "erpnext-backend",
    "erpnext-websocket",
    "erpnext-worker-short",
    "erpnext-worker-long",
    "erpnext-scheduler",
)

ROOT_RUNTIME_WRAPPER_SERVICES = frozenset(
    {
        "erpnext-configurator",
        "erpnext-site-bootstrap",
        "erpnext-migrator",
        "erpnext-sso-bootstrap",
        "erpnext-backend",
        "erpnext-websocket",
        "erpnext-worker-short",
        "erpnext-worker-long",
        "erpnext-scheduler",
    }
)

ONE_SHOT_SERVICES = frozenset(
    {
        "erpnext-assets-bootstrap",
        "erpnext-configurator",
        "erpnext-site-bootstrap",
        "erpnext-migrator",
        "erpnext-sso-bootstrap",
    }
)

LONG_RUNNING_FRAPPE_SERVICES = frozenset(
    {
        "app",
        "erpnext-backend",
        "erpnext-websocket",
        "erpnext-worker-short",
        "erpnext-worker-long",
        "erpnext-scheduler",
        "erpnext-site-maintenance",
    }
)

EXPECTED_DEPENDENCIES: dict[str, dict[str, str]] = {
    "app": {
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
        "erpnext-sso-bootstrap": "service_completed_successfully",
        "erpnext-backend": "service_healthy",
        "erpnext-websocket": "service_healthy",
    },
    "erpnext-redis-cache": {},
    "erpnext-redis-queue": {},
    "erpnext-assets-bootstrap": {},
    "erpnext-configurator": {
        "erpnext-assets-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-site-bootstrap": {
        "erpnext-configurator": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-migrator": {
        "erpnext-site-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-sso-bootstrap": {
        "erpnext-migrator": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-backend": {
        "erpnext-sso-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-websocket": {
        "erpnext-sso-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-worker-short": {
        "erpnext-sso-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-worker-long": {
        "erpnext-sso-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-scheduler": {
        "erpnext-sso-bootstrap": "service_completed_successfully",
        "mariadb": "service_healthy",
        "erpnext-redis-cache": "service_healthy",
        "erpnext-redis-queue": "service_healthy",
    },
    "erpnext-site-maintenance": {
        "mariadb": "service_healthy",
        "erpnext-site-bootstrap": "service_completed_successfully",
        "erpnext-migrator": "service_completed_successfully",
        "erpnext-sso-bootstrap": "service_completed_successfully",
    },
}

EXPECTED_SERVICE_SECRETS: dict[str, frozenset[str]] = {
    "app": frozenset(),
    "mariadb": frozenset({"MARIADB_PASSWORD", "MARIADB_ROOT_PASSWORD"}),
    "mariadb_maintenance": frozenset({"MARIADB_ROOT_PASSWORD"}),
    "erpnext-redis-cache": frozenset({"ERPNEXT_REDIS_CACHE_PASSWORD"}),
    "erpnext-redis-queue": frozenset({"ERPNEXT_REDIS_QUEUE_PASSWORD"}),
    "erpnext-assets-bootstrap": frozenset(),
    "erpnext-configurator": frozenset(
        {
            "MARIADB_PASSWORD",
            "ERPNEXT_REDIS_CACHE_PASSWORD",
            "ERPNEXT_REDIS_QUEUE_PASSWORD",
        }
    ),
    "erpnext-site-bootstrap": frozenset(
        {"MARIADB_PASSWORD", "ERPNEXT_ADMIN_PASSWORD"}
    ),
    "erpnext-migrator": frozenset(),
    "erpnext-sso-bootstrap": frozenset(
        {"ERPNEXT_OIDC_CLIENT_ID", "ERPNEXT_OIDC_CLIENT_SECRET"}
    ),
    "erpnext-backend": frozenset(),
    "erpnext-websocket": frozenset(),
    "erpnext-worker-short": frozenset(),
    "erpnext-worker-long": frozenset(),
    "erpnext-scheduler": frozenset(),
    "erpnext-site-maintenance": frozenset(),
}

BOOTSTRAP_SECRET_NAMES = frozenset(
    {
        "MARIADB_PASSWORD",
        "MARIADB_ROOT_PASSWORD",
        "ERPNEXT_ADMIN_PASSWORD",
        "ERPNEXT_OIDC_CLIENT_ID",
        "ERPNEXT_OIDC_CLIENT_SECRET",
        "ERPNEXT_REDIS_CACHE_PASSWORD",
        "ERPNEXT_REDIS_QUEUE_PASSWORD",
    }
)

EXPECTED_ROOT_SECRET_FILES = frozenset(
    {
        "ERPNEXT_ADMIN_PASSWORD",
        "ERPNEXT_OIDC_CLIENT_ID",
        "ERPNEXT_OIDC_CLIENT_SECRET",
    }
)

EXPECTED_ROOT_EXCLUSIONS = (
    "ERPNEXT_OIDC_CLIENT_ID",
    "ERPNEXT_OIDC_CLIENT_SECRET",
)

PRIVATE_FRAPPE_CONFIG_TMPFS = (
    "/home/frappe/frappe-bench/config:rw,noexec,nosuid,nodev,size=1m,"
    "uid=${APP_UID:-1000},gid=${APP_GID:-1000},mode=0700"
)

RESTORE_ROLLBACK_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
OIDC_RESERVED_DOMAIN_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
ARCHIVE_VALIDATION_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
SCHEDULE_ERREXIT_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
SITE_DOMAIN_GUARD_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
MARIADB_BINLOG_GUARD_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
MARIADB_VENDOR_BRIDGE_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
CREDENTIAL_ROTATION_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}
SITE_BOOTSTRAP_CWD_FIXTURE_CACHE: dict[str, tuple[bool, str]] = {}


class UniqueKeyLoader(yaml.SafeLoader):
    """Lædt YÆML ohne stilles Überschreiben duplizierter Schlüssel."""


def _construct_unique_mapping(
    loader: UniqueKeyLoader,
    node: yaml.nodes.MappingNode,
    deep: bool = False,
) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            duplicate = key in mapping
        except TypeError as error:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                "found an unhashable mapping key",
                key_node.start_mark,
            ) from error
        if duplicate:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)


@dataclass
class ValidationResult:
    errors: list[str]
    assertions: int


@dataclass(frozen=True)
class NegativeCase:
    name: str
    expected_error: str
    mutate: Callable[[Path], None]


class Contract:
    """Sæmmelt ælle Vertrægsverletzungen, ohne Folgeprüfungen zu verstecken."""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.assertions = 0

    def expect(self, condition: bool, message: str) -> None:
        self.assertions += 1
        if not condition:
            self.errors.append(message)


def _regular_text(path: Path, contract: Contract, label: str) -> str:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        contract.expect(False, f"[{label}] missing file: {path}")
        return ""
    contract.expect(
        stat.S_ISREG(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode),
        f"[{label}] file must be a regular non-symlink: {path}",
    )
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        return ""
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        contract.expect(False, f"[{label}] could not read UTF-8 file {path}: {error}")
        return ""


def _load_yaml(path: Path, contract: Contract, label: str) -> dict[str, Any]:
    source = _regular_text(path, contract, label)
    if not source:
        return {}
    try:
        documents = list(yaml.load_all(source, Loader=UniqueKeyLoader))
    except yaml.YAMLError as error:
        contract.expect(False, f"[{label}] invalid or ambiguous YAML in {path}: {error}")
        return {}
    contract.expect(
        len(documents) == 1 and isinstance(documents[0], dict),
        f"[{label}] {path} must contain exactly one YAML mapping document",
    )
    if len(documents) != 1 or not isinstance(documents[0], dict):
        return {}
    return documents[0]


def _source_env_path(root: Path) -> Path:
    app_env = root / "ERPNext/app.env"
    return app_env if app_env.exists() else root / "ERPNext/.env"


def _load_env(path: Path, contract: Contract, label: str) -> dict[str, str]:
    source = _regular_text(path, contract, label)
    values: dict[str, str] = {}
    for line_number, raw_line in enumerate(source.splitlines(), 1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)=(.*)", raw_line)
        if not match:
            contract.expect(
                False,
                f"[{label}] malformed active environment line {path}:{line_number}",
            )
            continue
        key, raw_value = match.groups()
        value = re.split(r"\s{2,}#", raw_value, maxsplit=1)[0].rstrip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        contract.expect(key not in values, f"[{label}] duplicate environment key {key}")
        if key not in values:
            values[key] = value
    return values


def _run_restore_rollback_fixture(
    restore_path: Path,
    restore_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(restore_source.encode("utf-8")).hexdigest()
    cached = RESTORE_ROLLBACK_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = r'''#!/usr/bin/env python3
import importlib.util
import json
import os
import stat
import sys
import types
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory


restore_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("erpnext_restore_fixture", restore_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

frappe = types.ModuleType("frappe")
frappe.__path__ = []
frappe.init = lambda *args, **kwargs: None
frappe.destroy = lambda: None
commands = types.ModuleType("frappe.commands")
commands.__path__ = []
site_commands = types.ModuleType("frappe.commands.site")
database = types.ModuleType("frappe.database")
database.__path__ = []
database_manager = types.ModuleType("frappe.database.db_manager")
database_implementation = types.ModuleType("frappe.database.database")
utils = types.ModuleType("frappe.utils")
utils.__path__ = []
synchronization = types.ModuleType("frappe.utils.synchronization")
logger = types.ModuleType("frappe.utils.logger")


def original_get_command(
    socket=None,
    host=None,
    port=None,
    user=None,
    password=None,
    db_name=None,
    extra=None,
    dump=False,
):
    return (
        "/usr/bin/mariadb",
        [
            f"--user={user}",
            f"--host={host}",
            f"--port={port}",
            "--pager=less -SFX",
            "--safe-updates",
            "--no-auto-rehash",
            db_name,
        ],
        "mariadb",
    )


def original_execute_in_shell(
    cmd,
    verbose=False,
    low_priority=False,
    check_exit_code=False,
):
    return None


class Database:
    def _log_query(
        self,
        mogrified_query,
        query_type,
        debug=False,
        unmogrified_query="",
    ):
        return None


original_log_query = Database._log_query


@contextmanager
def filelock(*args, **kwargs):
    yield


synchronization.filelock = filelock
logger.set_log_level = lambda *args, **kwargs: None
database.get_command = original_get_command
database.database = database_implementation
database.db_manager = database_manager
database_implementation.DDL_QUERY_TYPES = {
    "alter",
    "drop",
    "create",
    "truncate",
    "rename",
}
database_implementation.Database = Database
commands.site = site_commands
utils.execute_in_shell = original_execute_in_shell
utils.logger = logger
utils.synchronization = synchronization
frappe.commands = commands
frappe.database = database
frappe.utils = utils
sys.modules.update(
    {
        "frappe": frappe,
        "frappe.commands": commands,
        "frappe.commands.site": site_commands,
        "frappe.database": database,
        "frappe.database.database": database_implementation,
        "frappe.database.db_manager": database_manager,
        "frappe.utils": utils,
        "frappe.utils.logger": logger,
        "frappe.utils.synchronization": synchronization,
    }
)


def write_private(path, payload):
    path.write_bytes(payload)
    path.chmod(0o600)


with TemporaryDirectory(prefix="erpnext-config-rollback.", dir="/tmp") as raw_root:
    fixture_root = Path(raw_root)
    sites = fixture_root / "sites"
    bench = fixture_root / "bench"
    backup = fixture_root / "backup"
    bundle_id = "erpnext-20260808T120000Z"
    bundle = backup / bundle_id
    site_name = "erpnext.test"
    site = sites / site_name
    public_files = site / "public/files"
    private_files = site / "private/files"
    for directory in (bench, bundle, public_files, private_files):
        directory.mkdir(parents=True, exist_ok=True)

    topology = {
        "db_name": "erpnext",
        "db_user": "erpnext",
        "db_host": "erpnext-mariadb",
        "db_port": 3306,
        "db_type": "mariadb",
    }
    old_config = {
        **topology,
        "db_password": "old-database-password",
        "encryption_key": "old-encryption-key",
        "unicode_note": "Ältere Konfiguration 東京",
    }
    new_config = {
        **topology,
        "db_password": "new-database-password",
        "encryption_key": "new-encryption-key",
        "unicode_note": "Neue Konfiguration 京都",
    }
    frappe.conf = {
        **topology,
        "db_socket": None,
        "db_password": new_config["db_password"],
    }
    old_bytes = (
        json.dumps(old_config, ensure_ascii=False, indent=4).encode("utf-8") + b"\n"
    )
    new_bytes = json.dumps(
        new_config,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    config = site / "site_config.json"
    write_private(config, old_bytes)
    original_metadata = os.lstat(config)

    old_public = public_files / "Älter/angebot-旧.txt"
    old_private = private_files / "Überblick/秘密.txt"
    old_public.parent.mkdir()
    old_private.parent.mkdir()
    old_public.write_text("altes öffentliches Dokument", encoding="utf-8")
    old_private.write_text("altes privates Dokument", encoding="utf-8")

    manifest = {
        "DATABASE_FILE": "database.sql.gz",
        "SITE_CONFIG_FILE": "site_config.json",
        "PUBLIC_FILES_FILE": "public-files.tgz",
        "PRIVATE_FILES_FILE": "private-files.tgz",
    }
    for artifact_name in manifest.values():
        payload = new_bytes if artifact_name == "site_config.json" else b"fixture"
        write_private(bundle / artifact_name, payload)
    secret = fixture_root / "mariadb-root-password"
    write_private(secret, b"root-secret-1234")
    application_secret = fixture_root / "mariadb-application-password"
    write_private(application_secret, new_config["db_password"].encode("utf-8"))

    module.SITES_ROOT = sites
    module.BENCH_ROOT = bench
    module.BACKUP_ROOT = backup
    module.STAGING_ROOT = backup / ".erpnext-site-staging"
    option_root = fixture_root / "mariadb-options"
    option_root.mkdir(mode=0o700)
    module.MARIADB_CLIENT_OPTION_ROOT = option_root
    module.verify_bundle = lambda *args: (manifest, new_config)
    old_public_inventory = module.live_tree_inventory(public_files)
    old_private_inventory = module.live_tree_inventory(private_files)

    def injected_vendor_failure(**kwargs):
        injected_public = public_files / "Neu/angebot-ß.txt"
        injected_private = private_files / "新規/秘密.txt"
        injected_public.parent.mkdir()
        injected_private.parent.mkdir()
        injected_public.write_text("neue öffentliche Datei", encoding="utf-8")
        injected_private.write_text("neue private Datei", encoding="utf-8")
        raise RuntimeError("injected vendor failure")

    site_commands._restore = injected_vendor_failure
    module.verify_restored_file_trees = lambda *args: (_ for _ in ()).throw(
        AssertionError("restore verification unexpectedly ran after vendor failure")
    )
    try:
        module.restore_bundle(
            bundle,
            bundle_id,
            site_name,
            secret,
            application_secret,
        )
    except RuntimeError as error:
        if str(error) != "injected vendor failure":
            raise
    else:
        raise AssertionError("injected vendor failure was swallowed")

    restored_metadata = os.lstat(config)
    assert config.read_bytes() == old_bytes
    assert stat.S_IMODE(restored_metadata.st_mode) == 0o600
    assert restored_metadata.st_ino == original_metadata.st_ino
    assert restored_metadata.st_dev == original_metadata.st_dev
    assert restored_metadata.st_uid == original_metadata.st_uid
    assert restored_metadata.st_gid == original_metadata.st_gid
    assert module.live_tree_inventory(public_files) == old_public_inventory
    assert module.live_tree_inventory(private_files) == old_private_inventory
    assert not list(site.glob(".erpnext-site-restore-*"))
    assert not list((site / "public").glob(".files.erpnext-site-replacement.*"))
    assert not list((site / "private").glob(".files.erpnext-site-replacement.*"))
    assert not list(option_root.iterdir())
    assert database.get_command is original_get_command
    assert utils.execute_in_shell is original_execute_in_shell
    assert Database._log_query is original_log_query

print("PASS injected vendor failure restores exact config and Unicode trees")
'''
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-rollback-harness.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-config-rollback.py"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(harness), str(restore_path)],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=20,
            )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-2000:].strip()
        result = (completed.returncode == 0, diagnostic)
    RESTORE_ROLLBACK_FIXTURE_CACHE[source_digest] = result
    return result


def _run_mariadb_vendor_bridge_fixture(
    restore_path: Path,
    restore_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(restore_source.encode("utf-8")).hexdigest()
    cached = MARIADB_VENDOR_BRIDGE_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = r'''#!/usr/bin/env python3
import importlib.util
import os
import re
import shlex
import stat
import sys
import types
from pathlib import Path
from tempfile import TemporaryDirectory


restore_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("erpnext_bridge_fixture", restore_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

application_password = 'App"slash\\ dollar$ semi; quote\' 123'
root_password = 'Root"slash\\ pipe| dollar$ 456'
expected_call = {
    "socket": None,
    "host": "erpnext-mariadb",
    "port": 3306,
    "user": "erpnext",
    "db_name": "erpnext",
    "extra": None,
    "dump": False,
}


def expect_runtime_error(call, exact_message):
    try:
        call()
    except RuntimeError as error:
        assert str(error) == exact_message, (str(error), exact_message)
    else:
        raise AssertionError(f"expected RuntimeError: {exact_message}")


def build_vendor_modules():
    database = types.ModuleType("frappe.database")
    manager = types.ModuleType("frappe.database.db_manager")
    utils = types.ModuleType("frappe.utils")
    get_calls = []
    execute_calls = []
    log_calls = []

    def original_get_command(
        socket=None,
        host=None,
        port=None,
        user=None,
        password=None,
        db_name=None,
        extra=None,
        dump=False,
    ):
        get_calls.append(
            (socket, host, port, user, password, db_name, extra, dump)
        )
        return (
            "/usr/bin/mariadb",
            [
                f"--user={user}",
                f"--host={host}",
                f"--port={port}",
                "--pager=less -SFX",
                "--safe-updates",
                "--no-auto-rehash",
                db_name,
            ],
            "mariadb",
        )

    def original_execute_in_shell(
        cmd,
        verbose=False,
        low_priority=False,
        check_exit_code=False,
    ):
        execute_calls.append((cmd, verbose, low_priority, check_exit_code))
        return "delegated"

    class Database:
        def _log_query(
            self,
            mogrified_query,
            query_type,
            debug=False,
            unmogrified_query="",
        ):
            call = (
                mogrified_query,
                query_type,
                debug,
                unmogrified_query,
            )
            log_calls.append(call)
            return ("delegated-log", call)

    database.get_command = original_get_command
    manager.get_command = original_get_command
    utils.execute_in_shell = original_execute_in_shell
    manager.execute_in_shell = original_execute_in_shell
    return {
        "database": database,
        "manager": manager,
        "utils": utils,
        "Database": Database,
        "ddl": {"alter", "drop", "create", "truncate", "rename"},
        "get_calls": get_calls,
        "execute_calls": execute_calls,
        "log_calls": log_calls,
        "original_get": original_get_command,
        "original_execute": original_execute_in_shell,
        "original_log": Database._log_query,
    }


def assert_original_hooks(vendor):
    assert vendor["database"].get_command is vendor["original_get"]
    assert vendor["manager"].get_command is vendor["original_get"]
    assert vendor["utils"].execute_in_shell is vendor["original_execute"]
    assert vendor["manager"].execute_in_shell is vendor["original_execute"]
    assert vendor["Database"]._log_query is vendor["original_log"]


def guard(vendor, database_path):
    return module.guarded_mariadb_vendor_restore(
        vendor["database"],
        vendor["manager"],
        vendor["utils"],
        vendor["Database"],
        vendor["ddl"],
        expected_call,
        application_password,
        root_password,
        database_path,
    )


def exact_get_command(vendor):
    return vendor["database"].get_command(
        socket=None,
        host="erpnext-mariadb",
        port=3306,
        user="erpnext",
        password=application_password,
        db_name="erpnext",
        extra=None,
        dump=False,
    )


with TemporaryDirectory(prefix="erpnext-mariadb-bridge.", dir="/tmp") as raw_root:
    fixture_root = Path(raw_root)
    option_root = fixture_root / "options"
    option_root.mkdir(mode=0o700)
    database_path = fixture_root / "database.sql.gz"
    database_path.write_bytes(b"fixture")
    database_path.chmod(0o600)
    module.MARIADB_CLIENT_OPTION_ROOT = option_root

    vendor = build_vendor_modules()
    with guard(vendor, database_path) as bridge_state:
        assert vendor["database"].get_command is vendor["manager"].get_command
        assert vendor["database"].get_command is not vendor["original_get"]
        assert vendor["utils"].execute_in_shell is vendor["manager"].execute_in_shell
        assert vendor["utils"].execute_in_shell is not vendor["original_execute"]
        assert vendor["Database"]._log_query is not vendor["original_log"]

        private_entries = list(option_root.iterdir())
        assert len(private_entries) == 1
        private_dir = private_entries[0]
        assert re.fullmatch(r"\.erpnext-site-restore\.[a-f0-9]{32}", private_dir.name)
        assert stat.S_IMODE(os.lstat(private_dir).st_mode) == 0o700
        option_file = private_dir / "client.cnf"
        assert stat.S_IMODE(os.lstat(option_file).st_mode) == 0o600
        escaped = application_password.replace("\\", "\\\\").replace('"', '\\"')
        assert option_file.read_bytes() == (
            f'[client]\npassword="{escaped}"\n'.encode("utf-8")
        )
        assert bridge_state["option_path"] == option_file

        database_instance = vendor["Database"]()
        for ddl_type in ("alter", "drop", "create", "truncate", "rename"):
            assert database_instance._log_query("secret-bearing ddl", ddl_type) is None
        assert vendor["log_calls"] == []
        delegated_log = database_instance._log_query(
            "select 1", "select", True, "select %s"
        )
        assert delegated_log == (
            "delegated-log",
            ("select 1", "select", True, "select %s"),
        )
        assert vendor["log_calls"] == [
            ("select 1", "select", True, "select %s")
        ]

        unexpected_pipeline = (
            f"gzip -dc {database_path} | /usr/bin/mariadb "
            "--defaults-extra-file=/tmp/drift.cnf --user=erpnext"
        )
        expect_runtime_error(
            lambda: vendor["utils"].execute_in_shell(
                unexpected_pipeline,
                verbose=None,
                low_priority=False,
                check_exit_code=True,
            ),
            "Frappe requested an unexpected restore child process",
        )
        expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {database_path}"
        expect_runtime_error(
            lambda: vendor["utils"].execute_in_shell(
                expected_sql_validation,
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            ),
            "Frappe requested an unexpected database-content validation",
        )
        assert vendor["execute_calls"] == []

        expected_file_probe = f"file {database_path}"
        assert vendor["utils"].execute_in_shell(
            expected_file_probe,
            verbose=False,
            low_priority=False,
            check_exit_code=True,
        ) == "delegated"
        assert vendor["execute_calls"] == [
            (expected_file_probe, False, False, True)
        ]

        rejected_validations = (
            f"/bin/zgrep -m1 __Auth {database_path}",
            f"/usr/bin/zgrep -m1 __User {database_path}",
            f"/usr/bin/zgrep -m1 __Auth {fixture_root / 'other.sql.gz'}",
            "/bin/true",
        )
        for command in rejected_validations:
            expect_runtime_error(
                lambda command=command: vendor["utils"].execute_in_shell(
                    command,
                    verbose=False,
                    low_priority=False,
                    check_exit_code=True,
                ),
                "Frappe requested an unexpected restore child process",
            )
        for flags in (
            (None, False, True),
            (False, True, True),
            (False, False, False),
        ):
            expect_runtime_error(
                lambda flags=flags: vendor["utils"].execute_in_shell(
                    expected_sql_validation,
                    verbose=flags[0],
                    low_priority=flags[1],
                    check_exit_code=flags[2],
                ),
                "Frappe requested an unexpected database-content validation",
            )
        assert vendor["execute_calls"] == [
            (expected_file_probe, False, False, True)
        ]
        assert vendor["utils"].execute_in_shell(
            expected_sql_validation,
            verbose=False,
            low_priority=False,
            check_exit_code=True,
        ) == "delegated"
        expect_runtime_error(
            lambda: vendor["utils"].execute_in_shell(
                expected_sql_validation,
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            ),
            "Frappe requested an unexpected database-content validation",
        )
        assert vendor["execute_calls"] == [
            (expected_file_probe, False, False, True),
            (expected_sql_validation, False, False, True),
        ]

        binary, arguments, binary_name = exact_get_command(vendor)
        assert binary == "/usr/bin/mariadb" and binary_name == "mariadb"
        assert arguments[0] == f"--defaults-extra-file={option_file}"
        assert sum(value.startswith("--defaults-extra-file=") for value in arguments) == 1
        assert all(
            application_password not in value and root_password not in value
            for value in arguments
        )
        assert not any(module.contains_password_token(value) for value in arguments)
        assert vendor["get_calls"] == [
            (
                None,
                "erpnext-mariadb",
                3306,
                "erpnext",
                None,
                "erpnext",
                None,
                False,
            )
        ]
        expect_runtime_error(
            lambda: vendor["utils"].execute_in_shell(
                expected_sql_validation,
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            ),
            "Frappe requested an unexpected database-content validation",
        )
        assert vendor["execute_calls"] == [
            (expected_file_probe, False, False, True),
            (expected_sql_validation, False, False, True),
        ]

        delegated_before_rejections = len(vendor["execute_calls"])
        rejected_commands = (
            f"echo {application_password}",
            f"echo {root_password}",
            f"echo {shlex.quote(application_password)}",
            "mariadb --password=redacted",
            "mariadb -psecret",
            "MYSQL_PWD=redacted mariadb",
        )
        for command in rejected_commands:
            expected = (
                "Frappe requested a secret-bearing child process"
                if application_password in command
                or root_password in command
                or shlex.quote(application_password) in command
                else "Frappe requested a password-bearing child-process option"
            )
            expect_runtime_error(
                lambda command=command: vendor["utils"].execute_in_shell(command),
                expected,
            )
        assert len(vendor["execute_calls"]) == delegated_before_rejections

        client_suffix = f"{binary} {shlex.join(arguments)}"
        pipeline = f"gzip -dc {database_path} | {client_suffix}"
        assert vendor["utils"].execute_in_shell(
            pipeline,
            verbose=None,
            low_priority=False,
            check_exit_code=True,
        ) == "delegated"
        expect_runtime_error(
            lambda: vendor["utils"].execute_in_shell(
                expected_sql_validation,
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            ),
            "Frappe requested an unexpected database-content validation",
        )
        expect_runtime_error(
            lambda: exact_get_command(vendor),
            "Frappe requested the MariaDB restore command more than once",
        )
        assert bridge_state == {
            "uses": 1,
            "file_probe_uses": 1,
            "sql_validation_uses": 1,
            "spawn_uses": 1,
            "option_path": option_file,
            "client_suffix": client_suffix,
        }
    assert_original_hooks(vendor)
    assert list(option_root.iterdir()) == []

    vendor = build_vendor_modules()
    try:
        with guard(vendor, database_path):
            vendor["utils"].execute_in_shell(
                f"file {database_path}",
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            )
            binary, arguments, _ = exact_get_command(vendor)
            vendor["utils"].execute_in_shell(
                f"gzip -dc {database_path} | {binary} {shlex.join(arguments)}",
                verbose=None,
                low_priority=False,
                check_exit_code=True,
            )
    except RuntimeError as error:
        assert str(error) == "Frappe requested an unexpected restore child process"
    else:
        raise AssertionError("restore spawn without SQL validation was accepted")
    assert vendor["execute_calls"] == [
        (f"file {database_path}", False, False, True)
    ]
    assert_original_hooks(vendor)
    assert list(option_root.iterdir()) == []

    vendor = build_vendor_modules()
    try:
        with guard(vendor, database_path):
            vendor["utils"].execute_in_shell(
                f"file {database_path}",
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            )
            exact_get_command(vendor)
            vendor["utils"].execute_in_shell(
                f"/usr/bin/zgrep -m1 __Auth {database_path}",
                verbose=False,
                low_priority=False,
                check_exit_code=True,
            )
    except RuntimeError as error:
        assert str(error) == "Frappe requested an unexpected database-content validation"
    else:
        raise AssertionError("SQL validation after get_command was accepted")
    assert vendor["execute_calls"] == [
        (f"file {database_path}", False, False, True)
    ]
    assert_original_hooks(vendor)
    assert list(option_root.iterdir()) == []

    vendor = build_vendor_modules()
    try:
        with guard(vendor, database_path):
            raise RuntimeError("injected vendor failure")
    except RuntimeError as error:
        assert str(error) == "injected vendor failure"
    else:
        raise AssertionError("injected failure was swallowed")
    assert_original_hooks(vendor)
    assert list(option_root.iterdir()) == []

    vendor = build_vendor_modules()
    try:
        with guard(vendor, database_path):
            pass
    except RuntimeError as error:
        assert str(error) == "Frappe did not use the guarded MariaDB restore path exactly once"
    else:
        raise AssertionError("zero-use bridge drift was accepted")
    assert_original_hooks(vendor)
    assert list(option_root.iterdir()) == []

    vendor = build_vendor_modules()
    try:
        with guard(vendor, database_path):
            exact_get_command(vendor)
            exact_get_command(vendor)
    except RuntimeError as error:
        assert str(error) == "Frappe requested the MariaDB restore command more than once"
    else:
        raise AssertionError("multi-use bridge drift was accepted")
    assert_original_hooks(vendor)
    assert list(option_root.iterdir()) == []

print("PASS exact private MariaDB option bridge and hook lifecycle")
'''
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-mariadb-bridge-harness.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-mariadb-bridge.py"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(harness), str(restore_path)],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=25,
            )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-4000:].strip()
        result = (completed.returncode == 0, diagnostic)
    MARIADB_VENDOR_BRIDGE_FIXTURE_CACHE[source_digest] = result
    return result


def _run_credential_rotation_fixture(
    restore_path: Path,
    restore_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(restore_source.encode("utf-8")).hexdigest()
    cached = CREDENTIAL_ROTATION_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = r'''#!/usr/bin/env python3
import hashlib
import importlib.util
import os
import stat
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


restore_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("erpnext_rotation_fixture", restore_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReachedPrepare(RuntimeError):
    pass


def write_private(path, payload):
    path.write_bytes(payload)
    path.chmod(0o600)


def fingerprint(root):
    digest = hashlib.sha256()
    for current, directories, files in os.walk(root, topdown=True, followlinks=False):
        directories.sort()
        files.sort()
        for name in [*directories, *files]:
            path = Path(current) / name
            metadata = os.lstat(path)
            digest.update(path.relative_to(root).as_posix().encode("utf-8"))
            digest.update(oct(stat.S_IMODE(metadata.st_mode)).encode("ascii"))
            if stat.S_ISREG(metadata.st_mode):
                digest.update(path.read_bytes())
    return digest.hexdigest()


with TemporaryDirectory(prefix="erpnext-credential-rotation.", dir="/tmp") as raw_root:
    fixture_root = Path(raw_root)
    sites = fixture_root / "sites"
    site_name = "erpnext.test"
    site_root = sites / site_name
    bundle_id = "erpnext-20260808T120000Z"
    bundle = fixture_root / "backup" / bundle_id
    site_root.mkdir(parents=True)
    bundle.mkdir(parents=True)
    expected_password = "current-app-password-123"
    expected_config = {
        "db_name": "erpnext",
        "db_user": "erpnext",
        "db_host": "erpnext-mariadb",
        "db_port": 3306,
        "db_type": "mariadb",
        "db_password": expected_password,
        "encryption_key": "bundle-encryption-key",
    }
    manifest = {
        "SITE_CONFIG_FILE": "site_config.json",
        "DATABASE_FILE": "database.sql.gz",
        "PUBLIC_FILES_FILE": "public-files.tgz",
        "PRIVATE_FILES_FILE": "private-files.tgz",
    }
    for name in manifest.values():
        write_private(bundle / name, b"fixture")
    root_secret = fixture_root / "root-secret"
    write_private(root_secret, b"root-password-456")
    matching_secret = fixture_root / "matching-app-secret"
    write_private(matching_secret, expected_password.encode("utf-8"))
    mismatching_secret = fixture_root / "mismatching-app-secret"
    write_private(mismatching_secret, b"different-app-password-789")
    malformed_secret = fixture_root / "malformed-app-secret"
    write_private(malformed_secret, b"bad-password\n")
    missing_secret = fixture_root / "missing-app-secret"

    module.SITES_ROOT = sites
    module.verify_bundle = lambda *args: (manifest, expected_config)
    module.parse_site_config = lambda *args, **kwargs: (
        expected_config,
        b'{"fixture":true}',
    )
    destination_checks = []
    module.require_vendor_copy_destinations_absent = (
        lambda *args: destination_checks.append(args)
    )
    prepare_calls = []

    def reached_prepare(*args):
        prepare_calls.append(args)
        raise ReachedPrepare("rotation guard passed")

    module.prepare_empty_file_trees = reached_prepare
    original_read_secret = module.read_secret
    read_labels = []

    def observed_read_secret(path, label):
        read_labels.append(label)
        return original_read_secret(path, label)

    module.read_secret = observed_read_secret

    original_cwd = Path.cwd()
    before = fingerprint(fixture_root)
    try:
        module.restore_bundle(
            bundle,
            bundle_id,
            site_name,
            root_secret,
            matching_secret,
        )
    except ReachedPrepare as error:
        assert str(error) == "rotation guard passed"
    else:
        raise AssertionError("matching deployment credential did not reach prepare")
    assert prepare_calls == [(site_name, bundle_id)]
    assert read_labels == [
        "Current MariaDB application secret",
        "MariaDB root secret",
    ]
    assert len(destination_checks) == 1
    assert Path.cwd() == original_cwd
    assert fingerprint(fixture_root) == before

    for application_secret, expected_fragment in (
        (
            mismatching_secret,
            "Selected bundle database credential does not match the current deployment secret",
        ),
        (missing_secret, "required regular file is missing"),
        (malformed_secret, "Current MariaDB application secret is unset or non-canonical"),
    ):
        prepare_calls.clear()
        read_labels.clear()
        destination_checks.clear()
        before = fingerprint(fixture_root)
        try:
            module.restore_bundle(
                bundle,
                bundle_id,
                site_name,
                root_secret,
                application_secret,
            )
        except RuntimeError as error:
            assert expected_fragment in str(error), (str(error), expected_fragment)
        else:
            raise AssertionError(f"invalid application secret accepted: {application_secret}")
        assert prepare_calls == []
        assert read_labels == ["Current MariaDB application secret"]
        assert len(destination_checks) == 1
        assert Path.cwd() == original_cwd
        assert fingerprint(fixture_root) == before

print("PASS credential rotation guard fails before restore mutation")
'''
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-rotation-harness.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-credential-rotation.py"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(harness), str(restore_path)],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=20,
            )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-4000:].strip()
        result = (completed.returncode == 0, diagnostic)
    CREDENTIAL_ROTATION_FIXTURE_CACHE[source_digest] = result
    return result


def _run_archive_validation_fixture(
    restore_path: Path,
    restore_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(restore_source.encode("utf-8")).hexdigest()
    cached = ARCHIVE_VALIDATION_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = r'''#!/usr/bin/env python3
import hashlib
import importlib.util
import io
import sys
import tarfile
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory


restore_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("erpnext_archive_fixture", restore_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def add_directory(archive, name):
    member = tarfile.TarInfo(name)
    member.type = tarfile.DIRTYPE
    member.mode = 0o700
    member.mtime = 0
    archive.addfile(member)


def add_file(archive, name, payload):
    member = tarfile.TarInfo(name)
    member.type = tarfile.REGTYPE
    member.mode = 0o600
    member.mtime = 0
    member.size = len(payload)
    archive.addfile(member, io.BytesIO(payload))


def build_vendor_archive(path, visibility, folder, file_name, payload):
    prefix = f"./erpnext.test/{visibility}/files"
    with tarfile.open(path, "w:gz", format=tarfile.PAX_FORMAT) as archive:
        add_directory(archive, f"{prefix}/")
        add_directory(archive, f"{prefix}/{folder}/")
        add_file(archive, f"{prefix}/{folder}/{file_name}", payload)
    path.chmod(0o600)


with TemporaryDirectory(prefix="erpnext-archive-validator.", dir="/tmp") as raw_root:
    root = Path(raw_root)
    public_archive = root / "public-files.tgz"
    private_archive = root / "private-files.tgz"
    public_payload = "öffentliche Datei 東京".encode("utf-8")
    private_payload = "private Datei 秘密".encode("utf-8")
    build_vendor_archive(
        public_archive,
        "public",
        "Älter",
        "angebot-旧.txt",
        public_payload,
    )
    build_vendor_archive(
        private_archive,
        "private",
        "Geschützt",
        "vertrag-秘密.txt",
        private_payload,
    )
    public_directories, public_files = module.validate_file_archive(
        public_archive,
        "public",
        exact_mode=0o600,
    )
    private_directories, private_files = module.validate_file_archive(
        private_archive,
        "private",
        exact_mode=0o600,
    )
    assert public_directories == {"Älter"}
    assert public_files == {
        "Älter/angebot-旧.txt": (
            len(public_payload),
            hashlib.sha256(public_payload).hexdigest(),
        )
    }
    assert private_directories == {"Geschützt"}
    assert private_files == {
        "Geschützt/vertrag-秘密.txt": (
            len(private_payload),
            hashlib.sha256(private_payload).hexdigest(),
        )
    }
    assert module.validate_archive_member_name(
        "./erpnext.test/public/files/report.txt",
        "public",
        False,
    ) == PurePosixPath("report.txt")

    unsafe_names = (
        "/erpnext.test/public/files/absolute.txt",
        "././erpnext.test/public/files/extra-dot.txt",
        "",
        "./erpnext.test/public/files/../traversal.txt",
        "./erpnext.test/public/files\\backslash.txt",
        "erpnext.test/public/files/missing-dot-prefix.txt",
        "./erpnext.test//public/files/empty-component.txt",
    )
    for unsafe_name in unsafe_names:
        try:
            module.validate_archive_member_name(unsafe_name, "public", False)
        except RuntimeError:
            continue
        raise AssertionError(f"unsafe archive member was accepted: {unsafe_name!r}")

print("PASS exact Frappe ./ archive prefix and unsafe-name rejection")
'''
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-archive-harness.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-archive-validator.py"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(harness), str(restore_path)],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=20,
            )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-2000:].strip()
        result = (completed.returncode == 0, diagnostic)
    ARCHIVE_VALIDATION_FIXTURE_CACHE[source_digest] = result
    return result


def _run_schedule_errexit_fixture(schedule_source: str) -> tuple[bool, str]:
    source_digest = hashlib.sha256(schedule_source.encode("utf-8")).hexdigest()
    cached = SCHEDULE_ERREXIT_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = (
        "#!/usr/bin/env bash\n"
        "set -Eeuo pipefail\n"
        "MARKER=$1\n"
        "RUNTIME_CRON=/tmp/erpnext-fixture.cron\n"
        "require_command() { :; }\n"
        "validate_schedule() { :; }\n"
        "render_runtime_cron() { :; }\n"
        "supercronic() { :; }\n"
        "log_info() { :; }\n"
        "log_ok() { :; }\n"
        "log_fatal() { return 1; }\n"
        "run_backup() { false; : > \"$MARKER\"; }\n"
        + schedule_source
        + "\nrun_schedule\n"
    )
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-schedule-errexit.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-run-schedule.sh"
            marker = harness_root / "failure-was-swallowed"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                ["bash", str(harness), str(marker)],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=10,
            )
            marker_exists = marker.exists()
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-2000:].strip()
        result = (
            completed.returncode != 0 and not marker_exists,
            diagnostic
            or f"returncode={completed.returncode}, marker_exists={marker_exists}",
        )
    SCHEDULE_ERREXIT_FIXTURE_CACHE[source_digest] = result
    return result


def _run_site_domain_guard_fixture(
    scripts: tuple[tuple[str, Path, str], ...],
) -> tuple[bool, str]:
    digest = hashlib.sha256()
    for label, path, source in scripts:
        digest.update(label.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(path).encode("utf-8"))
        digest.update(b"\0")
        digest.update(source.encode("utf-8"))
        digest.update(b"\0")
    source_digest = digest.hexdigest()
    cached = SITE_DOMAIN_GUARD_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = r'''#!/usr/bin/env python3
import importlib.util
import os
import stat
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


CASES = (
    ("configurator", Path(sys.argv[1])),
    ("site-bootstrap", Path(sys.argv[2])),
    ("sso-bootstrap", Path(sys.argv[3])),
)
EXPECTED_ERROR = (
    "ERPNEXT_SITE_NAME uses a reserved example or local-only DNS suffix"
)


def inventory(root):
    entries = []
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        metadata = os.lstat(path)
        relative = path.relative_to(root).as_posix()
        payload = path.read_bytes() if stat.S_ISREG(metadata.st_mode) else b""
        entries.append(
            (
                relative,
                stat.S_IFMT(metadata.st_mode),
                stat.S_IMODE(metadata.st_mode),
                payload,
            )
        )
    return tuple(entries)


with TemporaryDirectory(prefix="erpnext-site-domain-guard.", dir="/tmp") as raw_root:
    fixture_root = Path(raw_root)
    original_environment = dict(os.environ)
    for case_index, (label, script_path) in enumerate(CASES):
        case_root = fixture_root / label
        sites = case_root / "sites"
        apps = case_root / "apps"
        sites.mkdir(parents=True, mode=0o700)
        apps.mkdir(mode=0o700)
        before = inventory(case_root)
        frappe_modules_before = {
            name for name in sys.modules if name == "frappe" or name.startswith("frappe.")
        }

        spec = importlib.util.spec_from_file_location(
            f"erpnext_site_domain_{case_index}",
            script_path,
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.SITES_ROOT = sites
        if hasattr(module, "APPS_ROOT"):
            module.APPS_ROOT = apps
        if hasattr(module, "CONFIG_PATH"):
            module.CONFIG_PATH = sites / "common_site_config.json"
        if hasattr(module, "APPS_PATH"):
            module.APPS_PATH = sites / "apps.txt"

        forbidden_calls = []

        def forbid(name):
            def forbidden(*args, **kwargs):
                forbidden_calls.append(name)
                raise AssertionError(f"{label} reached forbidden call {name}")

            return forbidden

        for function_name in (
            "read_secret",
            "write_atomic",
            "write_config",
            "validate_site_config",
            "verify_frappe_state",
        ):
            if hasattr(module, function_name):
                setattr(module, function_name, forbid(function_name))

        os.environ.clear()
        os.environ.update(
            {
                "ERPNEXT_DATABASE_NAME": "erpnext",
                "ERPNEXT_DATABASE_USER": "erpnext",
                "ERPNEXT_SITE_NAME": "erpnext.example.com",
                "ERPNEXT_DATABASE_HOST": "erpnext-mariadb",
                "ERPNEXT_REDIS_CACHE_HOST": "erpnext-redis-cache",
                "ERPNEXT_REDIS_QUEUE_HOST": "erpnext-redis-queue",
                "ERPNEXT_AUTHENTIK_DOMAIN": "authentik.production.internal",
                "ERPNEXT_SSO_SIGNUPS": "Deny",
            }
        )
        try:
            module.main()
        except RuntimeError as error:
            if str(error) != EXPECTED_ERROR:
                raise AssertionError(
                    f"{label} failed with the wrong diagnostic: {error}"
                ) from error
        else:
            raise AssertionError(f"{label} accepted a reserved ERPNext site domain")
        finally:
            os.environ.clear()
            os.environ.update(original_environment)

        assert not forbidden_calls, (label, forbidden_calls)
        assert inventory(case_root) == before, f"{label} mutated persistent fixture state"
        frappe_modules_after = {
            name for name in sys.modules if name == "frappe" or name.startswith("frappe.")
        }
        assert frappe_modules_after == frappe_modules_before, (
            label,
            frappe_modules_before,
            frappe_modules_after,
        )

print("PASS reserved ERPNext site domains fail before secrets, DB, or mutation")
'''
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-site-domain-harness.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-site-domain-guards.py"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(harness),
                    *(str(path) for _, path, _ in scripts),
                ],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=20,
            )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-3000:].strip()
        result = (completed.returncode == 0, diagnostic)
    SITE_DOMAIN_GUARD_FIXTURE_CACHE[source_digest] = result
    return result


def _run_existing_site_bootstrap_cwd_fixture(
    bootstrap_path: Path,
    bootstrap_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(bootstrap_source.encode("utf-8")).hexdigest()
    cached = SITE_BOOTSTRAP_CWD_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    harness_source = r'''#!/usr/bin/env python3
import importlib.util
import json
import os
import stat
import sys
import types
from pathlib import Path
from tempfile import TemporaryDirectory


bootstrap_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location(
    "erpnext_existing_site_cwd_fixture",
    bootstrap_path,
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


with TemporaryDirectory(prefix="erpnext-existing-site-cwd.", dir="/tmp") as raw_root:
    fixture_root = Path(raw_root)
    bench_root = fixture_root / "frappe-bench"
    sites_root = bench_root / "sites"
    logs_root = bench_root / "logs"
    launch_root = fixture_root / "launcher"
    site_name = "erpnext.production.internal"
    site_root = sites_root / site_name
    for directory in (site_root, logs_root, launch_root):
        directory.mkdir(parents=True, mode=0o700)

    database_password = "existing-database-password"
    site_config = site_root / "site_config.json"
    config_bytes = (
        json.dumps(
            {
                "db_name": "erpnext",
                "db_user": "erpnext",
                "db_host": "erpnext-mariadb",
                "db_type": "mariadb",
                "db_password": database_password,
            },
            ensure_ascii=False,
            sort_keys=True,
        ).encode("utf-8")
        + b"\n"
    )
    site_config.write_bytes(config_bytes)
    site_config.chmod(0o600)

    module.SITES_ROOT = sites_root
    secret_events = []

    def read_secret(path, label, minimum=1):
        secret_events.append((label, Path.cwd()))
        if label == "MariaDB password":
            return database_password
        if label == "ERPNext Administrator password":
            return "existing-admin-password"
        raise AssertionError(f"unexpected secret label: {label}")

    module.read_secret = read_secret
    existing_site_events = []
    original_existing_sites = module.existing_sites

    def observed_existing_sites():
        existing_site_events.append(Path.cwd())
        return original_existing_sites()

    module.existing_sites = observed_existing_sites

    frappe = types.ModuleType("frappe")
    frappe.__path__ = []
    frappe_events = []

    print_settings_state = {"pdf_generator": "wkhtmltopdf"}

    class FakeDatabase:
        def exists(self, doctype, name):
            frappe_events.append(("db.exists", Path.cwd(), doctype, name))
            return True

        def get_single_value(self, doctype, field):
            frappe_events.append(("db.get_single_value", Path.cwd(), doctype, field))
            if (doctype, field) == ("System Settings", "time_zone"):
                return "Europe/Berlin"
            if (doctype, field) == ("Print Settings", "pdf_generator"):
                return print_settings_state["pdf_generator"]
            raise AssertionError(f"unexpected singleton read: {(doctype, field)!r}")

        def set_single_value(self, doctype, field, value):
            frappe_events.append(
                ("db.set_single_value", Path.cwd(), doctype, field, value)
            )
            assert (doctype, field, value) == (
                "Print Settings",
                "pdf_generator",
                "chrome",
            )
            print_settings_state["pdf_generator"] = value

        def commit(self):
            frappe_events.append(("db.commit", Path.cwd()))

    frappe.db = FakeDatabase()

    def frappe_init(site, sites_path):
        frappe_events.append(("init", Path.cwd(), site, sites_path))

    def frappe_connect():
        current = Path.cwd()
        frappe_events.append(("connect", current))
        database_log = (current / "../logs/database.log").resolve()
        assert database_log == logs_root / "database.log", database_log
        database_log.write_text("existing-site logger fixture\n", encoding="utf-8")

    def frappe_destroy():
        frappe_events.append(("destroy", Path.cwd()))

    frappe.init = frappe_init
    frappe.connect = frappe_connect
    frappe.destroy = frappe_destroy
    frappe.get_installed_apps = lambda: ("frappe", "erpnext")

    utils = types.ModuleType("frappe.utils")
    utils.__path__ = []
    logger = types.ModuleType("frappe.utils.logger")
    scheduler = types.ModuleType("frappe.utils.scheduler")

    def set_log_level(level):
        frappe_events.append(("set_log_level", Path.cwd(), level))

    logger.set_log_level = set_log_level
    scheduler.is_scheduler_inactive = lambda verbose=False: False
    scheduler.enable_scheduler = lambda: (_ for _ in ()).throw(
        AssertionError("existing-site fixture unexpectedly enabled scheduler")
    )
    utils.logger = logger
    utils.scheduler = scheduler
    frappe.utils = utils
    sys.modules.update(
        {
            "frappe": frappe,
            "frappe.utils": utils,
            "frappe.utils.logger": logger,
            "frappe.utils.scheduler": scheduler,
        }
    )

    original_environment = dict(os.environ)
    os.environ.clear()
    os.environ.update(
        {
            "ERPNEXT_SITE_NAME": site_name,
            "ERPNEXT_SITE_TIMEZONE": "Europe/Berlin",
            "ERPNEXT_DATABASE_NAME": "erpnext",
            "ERPNEXT_DATABASE_HOST": "erpnext-mariadb",
        }
    )
    original_cwd = Path.cwd()
    os.chdir(launch_root)
    try:
        module.main()
        assert Path.cwd() == sites_root
    finally:
        os.chdir(original_cwd)
        os.environ.clear()
        os.environ.update(original_environment)

    assert secret_events == [
        ("MariaDB password", launch_root),
        ("ERPNext Administrator password", launch_root),
    ]
    assert existing_site_events == [sites_root]
    assert frappe_events[0] == (
        "init",
        sites_root,
        site_name,
        str(sites_root),
    )
    assert frappe_events[1] == ("set_log_level", sites_root, "ERROR")
    assert frappe_events[2] == ("connect", sites_root)
    assert all(event[1] == sites_root for event in frappe_events)
    assert [event[0] for event in frappe_events] == [
        "init",
        "set_log_level",
        "connect",
        "db.exists",
        "db.get_single_value",
        "db.get_single_value",
        "db.set_single_value",
        "db.commit",
        "db.get_single_value",
        "destroy",
    ]
    assert print_settings_state == {"pdf_generator": "chrome"}
    assert [event for event in frappe_events if event[0] == "db.commit"] == [
        ("db.commit", sites_root)
    ]
    assert (logs_root / "database.log").read_text(encoding="utf-8") == (
        "existing-site logger fixture\n"
    )
    assert site_config.read_bytes() == config_bytes
    assert stat.S_IMODE(os.lstat(site_config).st_mode) == 0o600
    assert [path for path in fixture_root.rglob("database.log")] == [
        logs_root / "database.log"
    ]

print("PASS existing-site bootstrap pins Frappe logger CWD to sites root")
'''
    try:
        with tempfile.TemporaryDirectory(
            prefix="erpnext-existing-site-cwd-harness.", dir="/tmp"
        ) as raw_harness_root:
            harness_root = Path(raw_harness_root)
            harness = harness_root / "test-existing-site-cwd.py"
            harness.write_text(harness_source, encoding="utf-8")
            completed = subprocess.run(
                [sys.executable, str(harness), str(bootstrap_path)],
                cwd=harness_root,
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "PYTHONDONTWRITEBYTECODE": "1",
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=20,
            )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-4000:].strip()
        result = (completed.returncode == 0, diagnostic)
    SITE_BOOTSTRAP_CWD_FIXTURE_CACHE[source_digest] = result
    return result


def _run_mariadb_binlog_guard_fixture(
    entrypoint_path: Path,
    entrypoint_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(entrypoint_source.encode("utf-8")).hexdigest()
    cached = MARIADB_BINLOG_GUARD_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    cases = (
        (
            "invalid-expiry-format",
            "not-a-number",
            "0",
            "MARIADB_BINLOG_EXPIRE_LOGS_SECONDS must be a whole number.",
        ),
        (
            "expiry-below-minimum",
            "3599",
            "0",
            "MARIADB_BINLOG_EXPIRE_LOGS_SECONDS must be between 3600 and 31536000.",
        ),
        (
            "invalid-purge-threshold-format",
            "604800",
            "not-a-number",
            "MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE must be a whole number.",
        ),
        (
            "purge-threshold-overflow",
            "604800",
            "4294967296",
            "MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE exceeds the supported unsigned range.",
        ),
    )
    diagnostics: list[str] = []
    try:
        for label, expiry, purge_threshold, expected_diagnostic in cases:
            completed = subprocess.run(
                ["/bin/sh", str(entrypoint_path)],
                cwd="/tmp",
                env={
                    "LC_ALL": "C.UTF-8",
                    "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    "MARIADB_BINLOG_EXPIRE_LOGS_SECONDS": expiry,
                    "MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE": purge_threshold,
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=10,
            )
            diagnostic = (completed.stderr or completed.stdout).decode(
                "utf-8", errors="replace"
            ).strip()
            diagnostics.append(f"{label}: rc={completed.returncode}: {diagnostic}")
            if not (
                completed.returncode == 78
                and diagnostic == f"[FATAL] {expected_diagnostic}"
                and "canonical data root" not in diagnostic
            ):
                result = (False, diagnostics[-1])
                MARIADB_BINLOG_GUARD_FIXTURE_CACHE[source_digest] = result
                return result
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        result = (True, "PASS " + "; ".join(diagnostics))
    MARIADB_BINLOG_GUARD_FIXTURE_CACHE[source_digest] = result
    return result


def _run_oidc_reserved_domain_fixture(
    script_path: Path,
    script_source: str,
) -> tuple[bool, str]:
    source_digest = hashlib.sha256(script_source.encode("utf-8")).hexdigest()
    cached = OIDC_RESERVED_DOMAIN_FIXTURE_CACHE.get(source_digest)
    if cached is not None:
        return cached
    try:
        completed = subprocess.run(
            [sys.executable, str(script_path)],
            cwd="/tmp",
            env={
                "ERPNEXT_SITE_NAME": "erpnext.production.internal",
                "ERPNEXT_AUTHENTIK_DOMAIN": "authentik.example.com",
                "ERPNEXT_SSO_SIGNUPS": "Deny",
                "LC_ALL": "C.UTF-8",
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "PYTHONDONTWRITEBYTECODE": "1",
            },
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError) as error:
        result = (False, f"fixture execution failed: {error}")
    else:
        diagnostic = (completed.stderr or completed.stdout).decode(
            "utf-8", errors="replace"
        )[-2000:].strip()
        result = (
            completed.returncode != 0
            and "reserved example or local-only DNS suffix" in diagnostic,
            diagnostic,
        )
    OIDC_RESERVED_DOMAIN_FIXTURE_CACHE[source_digest] = result
    return result


def _template_compose_path(root: Path, service: str) -> Path:
    return root / "templates" / service / f"docker-compose.{service}.yaml"


def _service_secret_names(service: dict[str, Any]) -> tuple[str, ...]:
    raw = service.get("secrets")
    if raw is None:
        return ()
    if not isinstance(raw, list):
        return ("<INVALID>",)
    names: list[str] = []
    for item in raw:
        if isinstance(item, str):
            names.append(item)
        elif isinstance(item, dict) and len(item) == 1:
            names.append(str(next(iter(item))))
        else:
            names.append("<INVALID>")
    return tuple(names)


def _network_names(service: dict[str, Any]) -> tuple[str, ...]:
    raw = service.get("networks")
    if isinstance(raw, list):
        return tuple(str(item) for item in raw)
    if isinstance(raw, dict):
        return tuple(str(item) for item in raw)
    return ()


def _volume_sources(service: dict[str, Any]) -> tuple[str, ...]:
    raw = service.get("volumes")
    if not isinstance(raw, list):
        return ()
    sources: list[str] = []
    for item in raw:
        if isinstance(item, str):
            sources.append(item.split(":", 1)[0])
        elif isinstance(item, dict):
            source = item.get("source")
            if source is not None:
                sources.append(str(source))
    return tuple(sources)


def _volume_targets(service: dict[str, Any]) -> tuple[str, ...]:
    raw = service.get("volumes")
    if not isinstance(raw, list):
        return ()
    targets: list[str] = []
    for item in raw:
        if isinstance(item, str):
            parts = item.split(":")
            if len(parts) >= 2:
                targets.append(parts[1])
        elif isinstance(item, dict):
            target = item.get("target")
            if target is not None:
                targets.append(str(target))
    return tuple(targets)


def _tmpfs_targets(service: dict[str, Any]) -> tuple[str, ...]:
    raw = service.get("tmpfs")
    if not isinstance(raw, list):
        return ()
    targets: list[str] = []
    for item in raw:
        if isinstance(item, str):
            targets.append(item.split(":", 1)[0])
        elif isinstance(item, dict):
            target = item.get("target")
            if target is not None:
                targets.append(str(target))
    return tuple(targets)


def _dependency_conditions(
    service: dict[str, Any], contract: Contract, service_name: str
) -> dict[str, str]:
    raw = service.get("depends_on")
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        contract.expect(False, f"[dependency] {service_name} depends_on must be a mapping")
        return {}
    result: dict[str, str] = {}
    for dependency, value in raw.items():
        if isinstance(value, dict):
            condition = value.get("condition")
        else:
            condition = value
        if not isinstance(condition, str):
            contract.expect(
                False,
                f"[dependency] {service_name}->{dependency} needs an explicit condition",
            )
            continue
        result[str(dependency)] = condition
    return result


def _iter_scalar_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, nested in value.items():
            yield from _iter_scalar_strings(key)
            yield from _iter_scalar_strings(nested)
    elif isinstance(value, (list, tuple)):
        for nested in value:
            yield from _iter_scalar_strings(nested)


def _simple_assignments(tree: ast.AST) -> dict[str, ast.AST]:
    assignments: dict[str, ast.AST] = {}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if isinstance(target, ast.Name):
            assignments[target.id] = node.value
    return assignments


def _literal(node: ast.AST | None, assignments: dict[str, ast.AST]) -> Any:
    if node is None:
        return None
    if isinstance(node, ast.Name) and node.id in assignments:
        return _literal(assignments[node.id], assignments)
    try:
        return ast.literal_eval(node)
    except (ValueError, TypeError):
        return None


def _dict_nodes(node: ast.AST | None) -> dict[str, ast.AST]:
    if not isinstance(node, ast.Dict):
        return {}
    result: dict[str, ast.AST] = {}
    for key_node, value_node in zip(node.keys, node.values):
        if isinstance(key_node, ast.Constant) and isinstance(key_node.value, str):
            result[key_node.value] = value_node
    return result


def _check_site_domain_guards(root: Path, contract: Contract) -> None:
    relative_scripts = (
        (
            "configurator",
            Path("templates/erpnext-configurator/scripts/erpnext-configurator.py"),
        ),
        (
            "site-bootstrap",
            Path(
                "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py"
            ),
        ),
        (
            "sso-bootstrap",
            Path(
                "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py"
            ),
        ),
    )
    expected_reserved_suffixes = (
        "example.com",
        "example.net",
        "example.org",
        "invalid",
        "test",
        "localhost",
    )
    fixture_scripts: list[tuple[str, Path, str]] = []
    for label, relative_path in relative_scripts:
        path = root / relative_path
        source = _regular_text(path, contract, "site-domain")
        fixture_scripts.append((label, path, source))
        try:
            tree = ast.parse(source, filename=str(path))
        except SyntaxError as error:
            contract.expect(
                False,
                f"[site-domain] {label} has invalid Python syntax: {error}",
            )
            continue
        assignments = _simple_assignments(tree)
        main_functions = [
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "main"
        ]
        guard_contract_ok = False
        if len(main_functions) == 1:
            main_function = main_functions[0]

            def is_site_assignment(statement: ast.AST) -> bool:
                return (
                    isinstance(statement, ast.Assign)
                    and len(statement.targets) == 1
                    and isinstance(statement.targets[0], ast.Name)
                    and statement.targets[0].id == "site_name"
                    and isinstance(statement.value, ast.Call)
                    and isinstance(statement.value.func, ast.Name)
                    and statement.value.func.id == "require_env"
                    and bool(statement.value.args)
                    and isinstance(statement.value.args[0], ast.Constant)
                    and statement.value.args[0].value == "ERPNEXT_SITE_NAME"
                )

            def is_exact_guard(statement: ast.AST) -> bool:
                return (
                    isinstance(statement, ast.Expr)
                    and isinstance(statement.value, ast.Call)
                    and isinstance(statement.value.func, ast.Name)
                    and statement.value.func.id == "reject_reserved_domain"
                    and len(statement.value.args) == 2
                    and isinstance(statement.value.args[0], ast.Name)
                    and statement.value.args[0].id == "site_name"
                    and isinstance(statement.value.args[1], ast.Constant)
                    and statement.value.args[1].value == "ERPNEXT_SITE_NAME"
                    and not statement.value.keywords
                )

            site_assignment_indices = [
                index
                for index, statement in enumerate(main_function.body)
                if is_site_assignment(statement)
            ]
            guard_indices = [
                index
                for index, statement in enumerate(main_function.body)
                if is_exact_guard(statement)
            ]
            sensitive_call_names = {
                "read_secret",
                "load_config",
                "write_config",
                "write_atomic",
                "discover_apps",
                "existing_sites",
                "validate_site_config",
                "verify_frappe_state",
                "_new_site",
            }
            sensitive_attribute_names = {
                "chdir",
                "connect",
                "commit",
                "save",
                "replace",
            }
            sensitive_calls = [
                node
                for node in ast.walk(main_function)
                if isinstance(node, ast.Call)
                and (
                    (
                        isinstance(node.func, ast.Name)
                        and node.func.id in sensitive_call_names
                    )
                    or (
                        isinstance(node.func, ast.Attribute)
                        and node.func.attr in sensitive_attribute_names
                    )
                )
            ]
            guard_contract_ok = (
                _literal(assignments.get("RESERVED_DNS_SUFFIXES"), assignments)
                == expected_reserved_suffixes
                and len(site_assignment_indices) == 1
                and len(guard_indices) == 1
                and guard_indices[0] == site_assignment_indices[0] + 1
                and bool(sensitive_calls)
                and main_function.body[guard_indices[0]].lineno
                < min(call.lineno for call in sensitive_calls)
            )
        contract.expect(
            guard_contract_ok,
            f"[site-domain] {label} must reject the exact reserved DNS suffix set "
            "immediately after ERPNEXT_SITE_NAME require_env and before every "
            "secret, DB, Frappe, or persistent-state call",
        )
    fixture_ok, fixture_diagnostic = _run_site_domain_guard_fixture(
        tuple(fixture_scripts)
    )
    contract.expect(
        fixture_ok,
        "[site-domain] isolated reserved-site fixtures must fail with the exact "
        "diagnostic before secret access, Frappe import, or persistent mutation"
        + (f": {fixture_diagnostic}" if fixture_diagnostic else ""),
    )


def _check_site_bootstrap(root: Path, contract: Contract) -> None:
    path = (
        root
        / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py"
    )
    source = _regular_text(path, contract, "bootstrap")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as error:
        contract.expect(False, f"[bootstrap] invalid Python syntax: {error}")
        return

    main_functions = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "main"
    ]
    bootstrap_contract_ok = False
    if len(main_functions) == 1:
        main_function = main_functions[0]
        new_site_calls = [
            node
            for node in ast.walk(main_function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "_new_site"
        ]

        def exact_new_site_init(call: ast.Call) -> bool:
            if not (
                isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "frappe"
                and call.func.attr == "init"
                and len(call.args) == 1
                and isinstance(call.args[0], ast.Name)
                and call.args[0].id == "site_name"
                and len(call.keywords) == 2
                and all(keyword.arg is not None for keyword in call.keywords)
            ):
                return False
            keywords = {keyword.arg: keyword.value for keyword in call.keywords}
            sites_path = keywords.get("sites_path")
            new_site = keywords.get("new_site")
            return (
                set(keywords) == {"sites_path", "new_site"}
                and isinstance(sites_path, ast.Call)
                and isinstance(sites_path.func, ast.Name)
                and sites_path.func.id == "str"
                and len(sites_path.args) == 1
                and isinstance(sites_path.args[0], ast.Name)
                and sites_path.args[0].id == "SITES_ROOT"
                and not sites_path.keywords
                and isinstance(new_site, ast.Constant)
                and new_site.value is True
            )

        exact_init_calls = [
            node
            for node in ast.walk(main_function)
            if isinstance(node, ast.Call) and exact_new_site_init(node)
        ]
        ordered_direct_pair = False
        for try_node in (
            node for node in ast.walk(main_function) if isinstance(node, ast.Try)
        ):
            direct_calls = [
                (index, statement.value)
                for index, statement in enumerate(try_node.body)
                if isinstance(statement, ast.Expr)
                and isinstance(statement.value, ast.Call)
            ]
            init_indices = [
                index for index, call in direct_calls if exact_new_site_init(call)
            ]
            create_indices = [
                index
                for index, call in direct_calls
                if isinstance(call.func, ast.Name) and call.func.id == "_new_site"
            ]
            if any(
                init_index < create_index
                for init_index in init_indices
                for create_index in create_indices
            ):
                ordered_direct_pair = True
                break
        bootstrap_contract_ok = (
            len(new_site_calls) == 1
            and len(exact_init_calls) == 1
            and ordered_direct_pair
        )
    contract.expect(
        bootstrap_contract_ok,
        "[bootstrap] Frappe v16 site creation must call exactly "
        "frappe.init(site_name, sites_path=str(SITES_ROOT), new_site=True) "
        "unconditionally before the sole _new_site call in the same try body",
    )

    bootstrap_cwd_contract_ok = False
    if len(main_functions) == 1:
        main_function = main_functions[0]

        def is_sites_root_lstat(statement: ast.AST) -> bool:
            return (
                isinstance(statement, ast.Assign)
                and len(statement.targets) == 1
                and isinstance(statement.targets[0], ast.Name)
                and statement.targets[0].id == "root_metadata"
                and isinstance(statement.value, ast.Call)
                and isinstance(statement.value.func, ast.Attribute)
                and isinstance(statement.value.func.value, ast.Name)
                and statement.value.func.value.id == "os"
                and statement.value.func.attr == "lstat"
                and len(statement.value.args) == 1
                and isinstance(statement.value.args[0], ast.Name)
                and statement.value.args[0].id == "SITES_ROOT"
                and not statement.value.keywords
            )

        def is_sites_root_guard(statement: ast.AST) -> bool:
            statement_source = ast.get_source_segment(source, statement) or ""
            return (
                isinstance(statement, ast.If)
                and statement_source
                == "if not stat.S_ISDIR(root_metadata.st_mode) or "
                "stat.S_ISLNK(root_metadata.st_mode):\n"
                '        fail("sites root must be a real directory")'
            )

        def is_exact_sites_chdir(call: ast.Call) -> bool:
            return (
                isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "os"
                and call.func.attr == "chdir"
                and len(call.args) == 1
                and isinstance(call.args[0], ast.Name)
                and call.args[0].id == "SITES_ROOT"
                and not call.keywords
            )

        def is_existing_sites_assignment(statement: ast.AST) -> bool:
            return (
                isinstance(statement, ast.Assign)
                and len(statement.targets) == 1
                and isinstance(statement.targets[0], ast.Name)
                and statement.targets[0].id == "sites"
                and isinstance(statement.value, ast.Call)
                and isinstance(statement.value.func, ast.Name)
                and statement.value.func.id == "existing_sites"
                and not statement.value.args
                and not statement.value.keywords
            )

        root_lstat_indices = [
            index
            for index, statement in enumerate(main_function.body)
            if is_sites_root_lstat(statement)
        ]
        root_guard_indices = [
            index
            for index, statement in enumerate(main_function.body)
            if is_sites_root_guard(statement)
        ]
        direct_chdir_indices = [
            index
            for index, statement in enumerate(main_function.body)
            if isinstance(statement, ast.Expr)
            and isinstance(statement.value, ast.Call)
            and is_exact_sites_chdir(statement.value)
        ]
        all_chdir_calls = [
            node
            for node in ast.walk(main_function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "os"
            and node.func.attr == "chdir"
        ]
        existing_sites_indices = [
            index
            for index, statement in enumerate(main_function.body)
            if is_existing_sites_assignment(statement)
        ]
        first_frappe_or_database_nodes = [
            node
            for node in ast.walk(main_function)
            if (
                isinstance(node, (ast.Import, ast.ImportFrom))
                and any(
                    alias.name == "frappe" or alias.name.startswith("frappe.")
                    for alias in node.names
                )
            )
            or (
                isinstance(node, ast.Call)
                and (
                    (
                        isinstance(node.func, ast.Name)
                        and node.func.id
                        in {
                            "existing_sites",
                            "verify_frappe_state",
                            "_new_site",
                            "initialize_site_timezone",
                        }
                    )
                    or (
                        isinstance(node.func, ast.Attribute)
                        and isinstance(node.func.value, ast.Name)
                        and node.func.value.id == "frappe"
                    )
                )
            )
        ]
        main_source = ast.get_source_segment(source, main_function) or ""
        bootstrap_cwd_contract_ok = (
            len(root_lstat_indices) == 1
            and len(root_guard_indices) == 1
            and len(direct_chdir_indices) == 1
            and len(all_chdir_calls) == 1
            and len(existing_sites_indices) == 1
            and root_guard_indices[0] == root_lstat_indices[0] + 1
            and direct_chdir_indices[0] == root_guard_indices[0] + 1
            and existing_sites_indices[0] == direct_chdir_indices[0] + 1
            and bool(first_frappe_or_database_nodes)
            and main_function.body[direct_chdir_indices[0]].lineno
            < min(node.lineno for node in first_frappe_or_database_nodes)
            and main_source.count("os.chdir(SITES_ROOT)") == 1
            and "BENCH_ROOT" not in main_source
        )
    contract.expect(
        bootstrap_cwd_contract_ok,
        "[bootstrap] existing-site CWD must perform exactly one unconditional "
        "os.chdir(SITES_ROOT) in main immediately after the lstat/real-directory "
        "guard and before existing_sites, every Frappe import, init/connect, or DB "
        "path; it must also cover the fresh branch and never use BENCH_ROOT",
    )

    cwd_fixture_ok, cwd_fixture_diagnostic = (
        _run_existing_site_bootstrap_cwd_fixture(path, source)
    )
    contract.expect(
        cwd_fixture_ok,
        "[bootstrap] existing-site CWD fixture must preserve pre-validation secret "
        "ordering, then run existing_sites, logger setup, frappe.init/connect, and "
        "relative ../logs/database.log exclusively from SITES_ROOT while repairing "
        "a drifted Print Settings.pdf_generator to chrome, committing exactly once, "
        "and proving the postcondition through a second singleton read"
        + (f": {cwd_fixture_diagnostic}" if cwd_fixture_diagnostic else ""),
    )

    bootstrap_functions = {
        node.name: node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }

    verify_function = bootstrap_functions.get("verify_frappe_state")

    def is_exact_frappe_db_call(
        call: ast.Call,
        method_name: str,
        arguments: tuple[str, ...],
    ) -> bool:
        return (
            isinstance(call.func, ast.Attribute)
            and isinstance(call.func.value, ast.Attribute)
            and isinstance(call.func.value.value, ast.Name)
            and call.func.value.value.id == "frappe"
            and call.func.value.attr == "db"
            and call.func.attr == method_name
            and len(call.args) == len(arguments)
            and all(
                isinstance(argument, ast.Constant)
                and argument.value == expected
                for argument, expected in zip(call.args, arguments)
            )
            and not call.keywords
        )

    def exact_pdf_drift_test(test: ast.AST) -> bool:
        return (
            isinstance(test, ast.Compare)
            and isinstance(test.left, ast.Call)
            and is_exact_frappe_db_call(
                test.left,
                "get_single_value",
                ("Print Settings", "pdf_generator"),
            )
            and len(test.ops) == 1
            and isinstance(test.ops[0], ast.NotEq)
            and len(test.comparators) == 1
            and isinstance(test.comparators[0], ast.Constant)
            and test.comparators[0].value == "chrome"
        )

    pdf_generator_contract_ok = False
    if verify_function is not None:
        pdf_get_calls = [
            node
            for node in ast.walk(verify_function)
            if isinstance(node, ast.Call)
            and is_exact_frappe_db_call(
                node,
                "get_single_value",
                ("Print Settings", "pdf_generator"),
            )
        ]
        pdf_set_calls = [
            node
            for node in ast.walk(verify_function)
            if isinstance(node, ast.Call)
            and is_exact_frappe_db_call(
                node,
                "set_single_value",
                ("Print Settings", "pdf_generator", "chrome"),
            )
        ]
        repair_if = None
        postcondition_if = None
        repair_index = -1
        postcondition_index = -1
        for try_node in (
            node for node in ast.walk(verify_function) if isinstance(node, ast.Try)
        ):
            matching = [
                (index, statement)
                for index, statement in enumerate(try_node.body)
                if isinstance(statement, ast.If)
                and exact_pdf_drift_test(statement.test)
            ]
            if len(matching) == 2:
                (repair_index, repair_if), (postcondition_index, postcondition_if) = matching
                break
        repair_body_ok = (
            repair_if is not None
            and not repair_if.orelse
            and len(repair_if.body) == 2
            and isinstance(repair_if.body[0], ast.Expr)
            and isinstance(repair_if.body[0].value, ast.Call)
            and is_exact_frappe_db_call(
                repair_if.body[0].value,
                "set_single_value",
                ("Print Settings", "pdf_generator", "chrome"),
            )
            and isinstance(repair_if.body[1], ast.Expr)
            and isinstance(repair_if.body[1].value, ast.Call)
            and is_exact_frappe_db_call(repair_if.body[1].value, "commit", ())
        )
        postcondition_body_ok = (
            postcondition_if is not None
            and not postcondition_if.orelse
            and len(postcondition_if.body) == 1
            and isinstance(postcondition_if.body[0], ast.Expr)
            and isinstance(postcondition_if.body[0].value, ast.Call)
            and isinstance(postcondition_if.body[0].value.func, ast.Name)
            and postcondition_if.body[0].value.func.id == "fail"
            and len(postcondition_if.body[0].value.args) == 1
            and isinstance(postcondition_if.body[0].value.args[0], ast.Constant)
            and postcondition_if.body[0].value.args[0].value
            == "ERPNext Print Settings PDF generator postcondition failed"
            and not postcondition_if.body[0].value.keywords
        )
        verify_source = ast.get_source_segment(source, verify_function) or ""
        exact_source_contract = (
            'if frappe.db.get_single_value("Print Settings", "pdf_generator") != "chrome":\n'
            '            frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")\n'
            "            frappe.db.commit()\n"
            '        if frappe.db.get_single_value("Print Settings", "pdf_generator") != "chrome":\n'
            '            fail("ERPNext Print Settings PDF generator postcondition failed")'
        )
        pdf_generator_contract_ok = (
            len(pdf_get_calls) == 2
            and len(pdf_set_calls) == 1
            and repair_body_ok
            and postcondition_body_ok
            and -1 < repair_index < postcondition_index
            and exact_source_contract in verify_source
        )
    contract.expect(
        pdf_generator_contract_ok,
        "[bootstrap] Print Settings PDF generator must read the exact singleton "
        "field, repair drift to exact chrome through set_single_value, commit only "
        "inside that repair branch, then re-read and fail closed on postcondition drift",
    )

    def logger_guard_precedes_target(function_name: str, target_name: str) -> bool:
        function = bootstrap_functions.get(function_name)
        if function is None:
            return False

        def is_frappe_init(call: ast.Call) -> bool:
            return (
                isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "frappe"
                and call.func.attr == "init"
            )

        def is_exact_logger_guard(call: ast.Call) -> bool:
            return (
                isinstance(call.func, ast.Name)
                and call.func.id == "set_log_level"
                and len(call.args) == 1
                and isinstance(call.args[0], ast.Constant)
                and call.args[0].value == "ERROR"
                and not call.keywords
            )

        def is_target(call: ast.Call) -> bool:
            if target_name == "_new_site":
                return isinstance(call.func, ast.Name) and call.func.id == target_name
            return (
                isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "frappe"
                and call.func.attr == target_name
            )

        imports = [
            statement
            for statement in function.body
            if isinstance(statement, ast.ImportFrom)
            and statement.module == "frappe.utils.logger"
            and len(statement.names) == 1
            and statement.names[0].name == "set_log_level"
            and statement.names[0].asname is None
        ]
        init_calls = [
            node
            for node in ast.walk(function)
            if isinstance(node, ast.Call) and is_frappe_init(node)
        ]
        logger_calls = [
            node
            for node in ast.walk(function)
            if isinstance(node, ast.Call) and is_exact_logger_guard(node)
        ]
        target_calls = [
            node
            for node in ast.walk(function)
            if isinstance(node, ast.Call) and is_target(node)
        ]
        ordered_direct_triple = False
        for try_node in (
            node for node in ast.walk(function) if isinstance(node, ast.Try)
        ):
            direct_calls = [
                (index, statement.value)
                for index, statement in enumerate(try_node.body)
                if isinstance(statement, ast.Expr)
                and isinstance(statement.value, ast.Call)
            ]
            init_indices = [
                index for index, call in direct_calls if is_frappe_init(call)
            ]
            logger_indices = [
                index for index, call in direct_calls if is_exact_logger_guard(call)
            ]
            target_indices = [
                index for index, call in direct_calls if is_target(call)
            ]
            if any(
                init_index < logger_index < target_index
                for init_index in init_indices
                for logger_index in logger_indices
                for target_index in target_indices
            ):
                ordered_direct_triple = True
                break
        return (
            len(imports) == 1
            and len(init_calls) == 1
            and len(logger_calls) == 1
            and len(target_calls) == 1
            and ordered_direct_triple
        )

    contract.expect(
        logger_guard_precedes_target("verify_frappe_state", "connect"),
        "[bootstrap] existing-site verification must import set_log_level exactly "
        "and call set_log_level(\"ERROR\") after frappe.init but before "
        "frappe.connect in the same direct try path",
    )
    contract.expect(
        logger_guard_precedes_target("main", "_new_site"),
        "[bootstrap] fresh-site creation must import set_log_level exactly and "
        "call set_log_level(\"ERROR\") after frappe.init but before _new_site in "
        "the same direct try path",
    )


def _check_oidc(root: Path, env: dict[str, str], contract: Contract) -> None:
    path = root / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py"
    source = _regular_text(path, contract, "oidc")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as error:
        contract.expect(False, f"[oidc] invalid Python syntax: {error}")
        return
    assignments = _simple_assignments(tree)
    contract.expect(
        _literal(assignments.get("PROVIDER_NAME"), assignments) == "Authentik",
        "[oidc] provider display name must be exactly Authentik",
    )
    contract.expect(
        _literal(assignments.get("PROVIDER_KEY"), assignments) == "authentik",
        "[oidc] provider document key must be exactly authentik",
    )
    contract.expect(
        _literal(assignments.get("RESERVED_DNS_SUFFIXES"), assignments)
        == (
            "example.com",
            "example.net",
            "example.org",
            "invalid",
            "test",
            "localhost",
        )
        and 'reject_reserved_domain(authentik_domain, "ERPNEXT_AUTHENTIK_DOMAIN")'
        in source,
        "[oidc] Authentik bootstrap must reject all reserved example/local DNS "
        "suffixes before reading secrets or importing Frappe",
    )
    reserved_ok, reserved_diagnostic = _run_oidc_reserved_domain_fixture(path, source)
    contract.expect(
        reserved_ok,
        "[oidc] isolated Authentik reserved-domain fixture must fail closed before "
        "secret access"
        + (f": {reserved_diagnostic}" if reserved_diagnostic else ""),
    )
    contract.expect(
        _literal(assignments.get("redirect_url"), assignments)
        == "/api/method/frappe.integrations.oauth2_logins.custom/authentik",
        "[oidc] native Authentik redirect path changed",
    )
    expected_nodes = _dict_nodes(assignments.get("expected"))
    expected_literals = {
        "enable_social_login": 1,
        "social_login_provider": "Custom",
        "custom_base_url": 1,
        "authorize_url": "/application/o/authorize/",
        "access_token_url": "/application/o/token/",
        "api_endpoint": "/application/o/userinfo/",
        "user_id_property": "sub",
        "show_in_resource_metadata": 0,
    }
    for key, expected_value in expected_literals.items():
        contract.expect(
            _literal(expected_nodes.get(key), assignments) == expected_value,
            f"[oidc] Social Login Key field {key} must equal {expected_value!r}",
        )
    contract.expect(
        isinstance(expected_nodes.get("provider_name"), ast.Name)
        and expected_nodes["provider_name"].id == "PROVIDER_NAME",
        "[oidc] Social Login Key must use the exact Authentik provider name",
    )
    contract.expect(
        isinstance(expected_nodes.get("redirect_url"), ast.Name)
        and expected_nodes["redirect_url"].id == "redirect_url",
        "[oidc] Social Login Key must use the exact native callback",
    )
    contract.expect(
        isinstance(expected_nodes.get("base_url"), ast.Name)
        and expected_nodes["base_url"].id == "authentik_origin",
        "[oidc] Social Login Key base URL must use the validated Authentik origin",
    )
    origin_node = assignments.get("authentik_origin")
    origin_ok = (
        isinstance(origin_node, ast.JoinedStr)
        and len(origin_node.values) == 2
        and isinstance(origin_node.values[0], ast.Constant)
        and origin_node.values[0].value == "https://"
        and isinstance(origin_node.values[1], ast.FormattedValue)
        and isinstance(origin_node.values[1].value, ast.Name)
        and origin_node.values[1].value.id == "authentik_domain"
    )
    contract.expect(origin_ok, "[oidc] Authentik origin must be strict HTTPS")
    signups_node = assignments.get("sign_ups")
    signups_ok = (
        isinstance(signups_node, ast.Call)
        and isinstance(signups_node.func, ast.Name)
        and signups_node.func.id == "require_env"
        and len(signups_node.args) >= 2
        and _literal(signups_node.args[0], assignments) == "ERPNEXT_SSO_SIGNUPS"
        and _literal(signups_node.args[1], assignments) == "Deny"
    )
    contract.expect(signups_ok, "[oidc] SSO bootstrap must accept only Sign ups Deny")
    contract.expect(
        isinstance(expected_nodes.get("sign_ups"), ast.Name)
        and expected_nodes["sign_ups"].id == "sign_ups",
        "[oidc] Social Login Key must persist the fail-closed Sign ups value",
    )
    auth_data = expected_nodes.get("auth_url_data")
    auth_data_ok = (
        isinstance(auth_data, ast.Call)
        and isinstance(auth_data.func, ast.Attribute)
        and auth_data.func.attr == "dumps"
        and bool(auth_data.args)
        and _literal(auth_data.args[0], assignments)
        == {"response_type": "code", "scope": "openid email profile"}
    )
    contract.expect(
        auth_data_ok,
        "[oidc] OIDC request must use exactly the openid email profile scopes",
    )
    contract.expect(
        env.get("ERPNEXT_SSO_SIGNUPS") == "Deny",
        "[oidc] editable root environment must keep ERPNEXT_SSO_SIGNUPS=Deny",
    )
    domain = env.get("ERPNEXT_AUTHENTIK_DOMAIN", "")
    contract.expect(
        bool(
            re.fullmatch(
                r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
                r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?",
                domain,
            )
        ),
        "[oidc] ERPNEXT_AUTHENTIK_DOMAIN must be a bare canonical DNS name",
    )


def _check_dependency_acyclic(
    dependency_map: dict[str, dict[str, str]], contract: Contract
) -> None:
    state: dict[str, int] = {}

    def visit(service: str, trail: tuple[str, ...]) -> None:
        marker = state.get(service, 0)
        if marker == 2:
            return
        if marker == 1:
            contract.expect(
                False,
                f"[dependency] cycle detected: {' -> '.join((*trail, service))}",
            )
            return
        state[service] = 1
        for dependency in dependency_map.get(service, {}):
            if dependency in dependency_map:
                visit(dependency, (*trail, service))
        state[service] = 2

    for service in dependency_map:
        visit(service, ())
    contract.expect(
        not any("cycle detected" in error for error in contract.errors),
        "[dependency] service dependency graph must be acyclic",
    )


def _check_mariadb_binlog_policy(
    root_env: dict[str, str],
    mariadb_root: Path,
    mariadb_compose: dict[str, Any],
    contract: Contract,
) -> None:
    contract.expect(
        root_env.get("MARIADB_BINLOG_EXPIRE_LOGS_SECONDS") == "604800"
        and root_env.get("MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE") == "0",
        "[database] ERPNext root must retain seven-day local binlog expiry and "
        "standalone purge threshold 0",
    )
    template_env = _load_env(mariadb_root / ".env", contract, "database")
    contract.expect(
        template_env.get("MARIADB_BINLOG_EXPIRE_LOGS_SECONDS") == "604800"
        and template_env.get("MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE") == "0",
        "[database] MariaDB template defaults must retain seven-day local binlog "
        "expiry and standalone purge threshold 0",
    )
    services = mariadb_compose.get("services")
    mariadb_service = (
        services.get("mariadb")
        if isinstance(services, dict) and isinstance(services.get("mariadb"), dict)
        else {}
    )
    command = mariadb_service.get("command")
    command_values = tuple(str(item) for item in command) if isinstance(command, list) else ()
    expected_command_values = (
        "--log-bin=binlog",
        "--binlog-format=ROW",
        "--binlog-expire-logs-seconds=${MARIADB_BINLOG_EXPIRE_LOGS_SECONDS:-604800}",
        "--slave-connections-needed-for-purge=${MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE:-0}",
    )
    environment = mariadb_service.get("environment")
    contract.expect(
        all(command_values.count(value) == 1 for value in expected_command_values)
        and isinstance(environment, dict)
        and environment.get("MARIADB_BINLOG_EXPIRE_LOGS_SECONDS")
        == "${MARIADB_BINLOG_EXPIRE_LOGS_SECONDS:-604800}"
        and environment.get("MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE")
        == "${MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE:-0}",
        "[database] MariaDB Compose must pass the validated expiry and purge "
        "controls exactly once to both wrapper environment and server arguments",
    )
    entrypoint_path = mariadb_root / "dockerfiles/entrypoint.mariadb.sh"
    entrypoint_source = _regular_text(entrypoint_path, contract, "database")
    required_guard_tokens = (
        'MARIADB_BINLOG_EXPIRE_LOGS_SECONDS="${MARIADB_BINLOG_EXPIRE_LOGS_SECONDS:-604800}"',
        'MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE="${MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE:-0}"',
        'case "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" in',
        '"$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -lt 3600',
        '"$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -gt 31536000',
        'case "$MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE" in',
        '"$MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE" -gt 4294967295',
    )
    data_root_index = entrypoint_source.find(
        'if [ ! -d "$MARIADB_DATA_ROOT" ] || [ -L "$MARIADB_DATA_ROOT" ]; then'
    )
    vendor_exec_index = entrypoint_source.find(
        'exec "$MARIADB_VENDOR_ENTRYPOINT" "$@"'
    )
    guard_positions = [entrypoint_source.find(token) for token in required_guard_tokens]
    contract.expect(
        all(position >= 0 for position in guard_positions)
        and max(guard_positions) < data_root_index < vendor_exec_index,
        "[database] MariaDB entrypoint must validate numeric expiry range and "
        "unsigned purge threshold before data-root inspection or vendor startup",
    )
    dockerfile_source = _regular_text(
        mariadb_root / "dockerfiles/dockerfile.mariadb",
        contract,
        "database",
    )
    contract.expect(
        "COPY entrypoint.mariadb.sh /usr/local/bin/entrypoint.mariadb-guard.sh"
        in dockerfile_source
        and 'ENTRYPOINT ["/usr/local/bin/entrypoint.mariadb-guard.sh"]'
        in dockerfile_source,
        "[database] MariaDB image must install and execute the reviewed startup guard",
    )
    fixture_ok, fixture_diagnostic = _run_mariadb_binlog_guard_fixture(
        entrypoint_path,
        entrypoint_source,
    )
    contract.expect(
        fixture_ok,
        "[database] MariaDB binlog policy guard must reject malformed/out-of-range "
        "expiry and purge values with exit 78 before vendor startup"
        + (f": {fixture_diagnostic}" if fixture_diagnostic else ""),
    )


def _check_maintenance(
    root: Path,
    root_env: dict[str, str],
    service: dict[str, Any],
    compose: dict[str, Any],
    contract: Contract,
) -> None:
    template_root = root / "templates/erpnext-site-maintenance"
    template_env = _load_env(template_root / ".env", contract, "maintenance")
    expected_env = {
        "ERPNEXT_SITE_MAINTENANCE_MODE": "schedule",
        "ERPNEXT_SITE_BACKUP_SCHEDULE": "0 2 * * *",
        "ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS": "93600",
        "ERPNEXT_SITE_RESTORE_BUNDLE_ID": "",
        "ERPNEXT_SITE_RESTORE_DRY_RUN": "true",
        "ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED": "false",
        "ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT": "false",
    }
    for key, value in expected_env.items():
        contract.expect(
            template_env.get(key) == value,
            f"[maintenance] template {key} must equal {value!r}",
        )
    contract.expect(
        root_env.get("ERPNEXT_SITE_BACKUP_SCHEDULE") == "0 2 * * *",
        "[maintenance] root backup schedule must remain nightly at 02:00",
    )
    contract.expect(
        root_env.get("ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS") == "93600",
        "[maintenance] root backup max-age must remain 93600 seconds",
    )
    environment = service.get("environment")
    contract.expect(
        isinstance(environment, dict),
        "[maintenance] scheduled service needs explicit environment controls",
    )
    if isinstance(environment, dict):
        expected_compose_values = {
            "ERPNEXT_SITE_BACKUP_SCHEDULE": "${ERPNEXT_SITE_BACKUP_SCHEDULE:-0 2 * * *}",
            "ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS": "${ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS:-93600}",
            "ERPNEXT_SITE_RESTORE_BUNDLE_ID": "${ERPNEXT_SITE_RESTORE_BUNDLE_ID:-}",
            "ERPNEXT_SITE_RESTORE_DRY_RUN": "${ERPNEXT_SITE_RESTORE_DRY_RUN:-true}",
            "ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED": "${ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED:-false}",
            "ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT": "${ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT:-false}",
        }
        for key, value in expected_compose_values.items():
            contract.expect(
                environment.get(key) == value,
                f"[maintenance] Compose {key} must equal {value!r}",
            )
    healthcheck = service.get("healthcheck")
    health_text = "\n".join(_iter_scalar_strings(healthcheck))
    contract.expect(
        "/backup/.erpnext-site-maintenance-last-success" in health_text,
        "[maintenance] healthcheck must use the unique success marker",
    )
    contract.expect(
        "93600" in health_text,
        "[maintenance] healthcheck fallback must match the nightly max-age",
    )
    contract.expect(
        _service_secret_names(service) == (),
        "[maintenance] scheduled service must not mount restore-only secrets",
    )
    all_active = "\n".join(_iter_scalar_strings(compose))
    contract.expect(
        "/var/run/docker.sock" not in all_active and "/run/docker.sock" not in all_active,
        "[maintenance] scheduled maintenance must never mount the Docker socket",
    )
    volume_sources = set(_volume_sources(service))
    contract.expect(
        "./appdata/erpnext-backups" in volume_sources,
        "[maintenance] backup host directory must be template-unique",
    )
    contract.expect(
        not ({"./backup", "./restore"} & volume_sources),
        "[maintenance] generic flattened backup/restore directories are forbidden",
    )
    expected_scripts = {
        "erpnext-site-backup.cron",
        "erpnext-site-maintenance.sh",
        "erpnext-site-restore.py",
    }
    scripts_root = template_root / "scripts"
    actual_scripts = {
        path.name
        for path in scripts_root.iterdir()
        if path.is_file() and not path.is_symlink()
    } if scripts_root.is_dir() else set()
    contract.expect(
        expected_scripts <= actual_scripts,
        f"[maintenance] missing unique maintenance helpers: {sorted(expected_scripts - actual_scripts)}",
    )
    contract.expect(
        "backup.cron" not in actual_scripts,
        "[maintenance] generic scripts/backup.cron would collide after flattening",
    )
    cron_source = _regular_text(
        scripts_root / "erpnext-site-backup.cron", contract, "maintenance"
    )
    contract.expect(
        cron_source.count("@ERPNEXT_SITE_BACKUP_SCHEDULE@") == 1
        and "/usr/local/bin/erpnext-site-maintenance.sh backup" in cron_source,
        "[maintenance] cron template must receive one validated runtime schedule",
    )
    wrapper_source = _regular_text(
        scripts_root / "erpnext-site-maintenance.sh", contract, "maintenance"
    )
    for token in (
        "@ERPNEXT_SITE_BACKUP_SCHEDULE@",
        "/run/erpnext-site-backup.cron",
        "/backup/.erpnext-site-maintenance-last-success",
        "/run/secrets/MARIADB_ROOT_PASSWORD",
        "/run/secrets/MARIADB_PASSWORD",
        "ERPNEXT_SITE_RESTORE_BUNDLE_ID",
        "ERPNEXT_SITE_RESTORE_DRY_RUN",
        "ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED",
        "ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT",
    ):
        contract.expect(
            token in wrapper_source,
            f"[maintenance] wrapper is missing required guard/token {token}",
        )
    schedule_match = re.search(
        r"(?ms)^run_schedule\(\) \{\n.*?^\}\n",
        wrapper_source,
    )
    schedule_source = schedule_match.group(0) if schedule_match is not None else ""
    active_schedule_lines = [
        line.strip()
        for line in schedule_source.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    preflight_index = schedule_source.find('supercronic -test "$RUNTIME_CRON"')
    initial_backup_index = schedule_source.find("\n  run_backup\n")
    scheduler_index = schedule_source.find('exec supercronic "$RUNTIME_CRON"')
    contract.expect(
        schedule_match is not None
        and active_schedule_lines.count("run_backup") == 1
        and all(
            line == "run_backup" for line in active_schedule_lines if "run_backup" in line
        )
        and -1 < preflight_index < initial_backup_index < scheduler_index,
        "[maintenance] Supercronic must validate the rendered schedule before the "
        "initial backup; run_schedule must call run_backup exactly once as a simple "
        "command without ||, if !, pipelines, or other conditional context",
    )
    schedule_fixture_ok, schedule_fixture_diagnostic = _run_schedule_errexit_fixture(
        schedule_source
    )
    contract.expect(
        schedule_fixture_ok,
        "[maintenance] run_schedule must preserve Bash errexit inside run_backup "
        "so an internal backup failure cannot advance the success path"
        + (f": {schedule_fixture_diagnostic}" if schedule_fixture_diagnostic else ""),
    )
    classifier_match = re.search(
        r"(?ms)^classify_vendor_outputs\(\) \{\n.*?^\}\n",
        wrapper_source,
    )
    contract.expect(
        classifier_match is not None,
        "[maintenance] strict vendor-output classifier function is missing",
    )
    if classifier_match is not None:
        classifier_source = classifier_match.group(0)

        def classifier_return_code(file_names: tuple[str, ...]) -> int | None:
            try:
                with tempfile.TemporaryDirectory(
                    prefix="erpnext-vendor-parser.", dir="/tmp"
                ) as raw_parser_root:
                    parser_root = Path(raw_parser_root)
                    vendor_root = parser_root / "vendor"
                    vendor_root.mkdir(mode=0o700)
                    for file_name in file_names:
                        (vendor_root / file_name).write_bytes(b"fixture")
                    harness = parser_root / "classify-vendor-outputs.sh"
                    harness.write_text(
                        "#!/usr/bin/env bash\nset -u\n"
                        + classifier_source
                        + 'classify_vendor_outputs "$1" "$2"\n',
                        encoding="utf-8",
                    )
                    completed = subprocess.run(
                        [
                            "bash",
                            str(harness),
                            str(vendor_root),
                            str(parser_root / "classified.env"),
                        ],
                        cwd=parser_root,
                        env={
                            "LC_ALL": "C",
                            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                        },
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        check=False,
                        timeout=10,
                    )
                    return completed.returncode
            except (OSError, subprocess.SubprocessError) as error:
                contract.expect(
                    False,
                    f"[maintenance] isolated vendor-parser fixture failed: {error}",
                )
                return None

        vendor_prefix = "20260808_120000-erpnext"
        valid_vendor_files = (
            f"{vendor_prefix}-database.sql.gz",
            f"{vendor_prefix}-files.tgz",
            f"{vendor_prefix}-private-files.tgz",
            f"{vendor_prefix}-site_config_backup.json",
        )
        encrypted_vendor_files = (
            f"{vendor_prefix}-enc.database.sql.gz",
            f"{vendor_prefix}-enc.files.tgz",
            f"{vendor_prefix}-enc.private-files.tgz",
            f"{vendor_prefix}-enc.site_config_backup.json",
        )
        valid_return_code = classifier_return_code(valid_vendor_files)
        encrypted_return_code = classifier_return_code(encrypted_vendor_files)
        contract.expect(
            valid_return_code == 0,
            "[maintenance] strict vendor-output parser rejected the supported "
            "four-file Frappe backup format",
        )
        contract.expect(
            encrypted_return_code not in {None, 0},
            "[maintenance] strict vendor-output parser must reject Frappe "
            "*-enc.* backup artifacts fail-closed",
        )

    documentation_contracts = {
        root / "ERPNext/README.md": (
            1,
            (
                "**Encrypt Bæckups**",
                "disæbled",
                "`*-enc.*`",
                "strict publisher rejects",
                "completely published site bundles",
                "off-host bæckup læyer",
                "key recovery",
                "restore pæth",
                "tæken online",
                "stopped-writer point-in-time",
                "concurrent file uploæds",
                "quiesce æpplicætion writers",
            ),
        ),
        template_root / "README.md": (
            2,
            (
                "**Encrypt Bæckups**",
                "disæbled",
                "`*-enc.*`",
                "strict publisher therefore rejects",
                "completed, verified bundle",
                "off-host bæckup læyer",
                "recovery key",
                "decrypt-plus-restore pæth",
                "run is online",
                "does not quiesce every web, worker, scheduler, or file writer",
                "does not clæim point-in-time or cræsh consistency",
                "stop every writer",
            ),
        ),
    }
    for readme_path, (expected_restore_runs, tokens) in documentation_contracts.items():
        readme_source = _regular_text(readme_path, contract, "maintenance")
        contract.expect(
            all(token in readme_source for token in tokens),
            "[maintenance] README must document disabled Frappe Encrypt Bæckups, "
            "*-enc.* rejection, and separately tested off-host key recovery: "
            f"{readme_path}",
        )
        bash_blocks = re.findall(r"(?ms)^```bash\n(.*?)^```$", readme_source)
        restore_run_blocks = [
            block
            for block in bash_blocks
            if "docker-compose.erpnext-site-maintenance.restore.yaml.example"
            in block
            and re.search(r"\brun\b", block)
            and "erpnext-site-maintenance" in block
        ]
        contract.expect(
            len(restore_run_blocks) == expected_restore_runs,
            "[maintenance] README restore-command inventory changed unexpectedly: "
            f"{readme_path}",
        )
        for command_index, block in enumerate(restore_run_blocks, 1):
            flattened = re.sub(r"\\\n[ \t]*", " ", block)
            shell_tokens = flattened.split()
            try:
                run_index = shell_tokens.index("run")
                service_index = shell_tokens.index(
                    "erpnext-site-maintenance", run_index + 1
                )
            except ValueError:
                run_index = -1
                service_index = -1
            no_deps_indices = [
                index
                for index, token in enumerate(shell_tokens)
                if token == "--no-deps"
            ]
            contract.expect(
                len(no_deps_indices) == 1
                and run_index < no_deps_indices[0] < service_index,
                "[maintenance] documented restore run must place exactly one "
                "--no-deps after run and before erpnext-site-maintenance "
                f"({readme_path}, command {command_index})",
            )
    restore_helper_path = scripts_root / "erpnext-site-restore.py"
    restore_source = _regular_text(restore_helper_path, contract, "maintenance")
    archive_fixture_ok, archive_fixture_diagnostic = _run_archive_validation_fixture(
        restore_helper_path,
        restore_source,
    )
    contract.expect(
        archive_fixture_ok,
        "[maintenance] file-archive validator must accept the exact Frappe v16 "
        "./<site>/<public|private>/files prefix while rejecting absolute, "
        "extra-dot, empty-component, traversal, and backslash names"
        + (f": {archive_fixture_diagnostic}" if archive_fixture_diagnostic else ""),
    )
    for token in (
        "--bundle-id",
        "--secret-file",
        "--application-secret-file",
        "sha256",
        "encryption_key",
    ):
        contract.expect(
            token in restore_source,
            f"[maintenance] restore helper is missing required guard/token {token}",
        )
    rollback_fixture_ok, rollback_fixture_diagnostic = _run_restore_rollback_fixture(
        restore_helper_path,
        restore_source,
    )
    contract.expect(
        rollback_fixture_ok,
        "[maintenance] injected vendor failure must restore original site_config "
        "bytes/mode/ownership/inode and both Unicode file trees without "
        "quarantine residue"
        + (
            f": {rollback_fixture_diagnostic}"
            if rollback_fixture_diagnostic
            else ""
        ),
    )
    try:
        restore_tree = ast.parse(restore_source)
    except SyntaxError as error:
        contract.expect(
            False,
            f"[maintenance] restore helper is not valid Python: {error}",
        )
        restore_tree = ast.Module(body=[], type_ignores=[])
    restore_functions = {
        node.name: node
        for node in restore_tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    required_restore_functions = {
        "read_secret",
        "encode_mariadb_option_value",
        "private_directory_identity",
        "private_option_file_identity",
        "sha256_descriptor",
        "create_mariadb_client_option_file",
        "remove_mariadb_client_option_file",
        "exact_signature_shape",
        "contains_password_token",
        "guarded_mariadb_vendor_restore",
        "live_tree_inventory",
        "prepare_empty_file_trees",
        "write_live_site_config",
        "rollback_site_config",
        "rollback_file_trees",
        "commit_site_config_replacement",
        "verify_restored_file_trees",
        "commit_file_tree_replacement",
        "restore_bundle",
    }
    contract.expect(
        required_restore_functions <= set(restore_functions),
        "[maintenance] restore helper is missing exact file-tree replacement functions: "
        f"{sorted(required_restore_functions - set(restore_functions))}",
    )

    def restore_function_source(function_name: str) -> str:
        function = restore_functions.get(function_name)
        return (
            ast.get_source_segment(restore_source, function) or ""
            if function is not None
            else ""
        )

    option_encoder_source = restore_function_source("encode_mariadb_option_value")
    option_create_source = restore_function_source(
        "create_mariadb_client_option_file"
    )
    option_remove_source = restore_function_source(
        "remove_mariadb_client_option_file"
    )
    bridge_source = restore_function_source("guarded_mariadb_vendor_restore")
    contract.expect(
        'MARIADB_CLIENT_OPTION_ROOT = Path("/tmp")' in restore_source
        and 'MARIADB_CLIENT_OPTION_PREFIX = ".erpnext-site-restore."'
        in restore_source
        and 'MARIADB_CLIENT_OPTION_NAME = "client.cnf"' in restore_source
        and 'value.replace("\\\\", "\\\\\\\\").replace(\'"\', \'\\\\"\')'
        in option_encoder_source
        and "return f'\"{escaped}\"'" in option_encoder_source,
        "[maintenance] MariaDB restore bridge must encode exactly one quoted, "
        "single-line client.cnf password value under its private /tmp namespace",
    )
    option_create_tokens = (
        "secrets.token_hex(16)",
        "os.mkdir(candidate, 0o700, dir_fd=root_descriptor)",
        'getattr(os, "O_CLOEXEC", 0)',
        "os.O_RDWR | os.O_CREAT | os.O_EXCL",
        'flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0)\n'
        '        if hasattr(os, "O_NOFOLLOW"):\n'
        "            flags |= os.O_NOFOLLOW",
        "os.fchmod(private_descriptor, 0o700)",
        "os.fchmod(file_descriptor, 0o600)",
        "os.geteuid()",
        "os.getegid()",
        "os.listdir(private_descriptor) != [MARIADB_CLIENT_OPTION_NAME]",
        "sha256_descriptor(file_descriptor)",
        "hashlib.sha256(payload).hexdigest()",
        '"canonical_path": file_path',
        '"private_identity": private_identity',
        '"file_identity": file_identity',
        '"digest": digest',
    )
    contract.expect(
        all(token in option_create_source for token in option_create_tokens),
        "[maintenance] MariaDB restore bridge must allocate an exclusive 0700 "
        "directory and O_EXCL/O_NOFOLLOW/O_CLOEXEC 0600 client.cnf while pinning "
        "owner, link-count, identity, inventory, and SHA-256",
    )
    option_remove_tokens = (
        'root_identity != state["root_identity"]',
        'private_directory_identity(opened_private, 0o700) != state["private_identity"]',
        'private_option_file_identity(opened_file) != state["file_identity"]',
        'digest != state["digest"]',
        'os.unlink(state["file_name"], dir_fd=private_descriptor)',
        "os.fstat(file_descriptor).st_nlink != 0",
        "os.fsync(private_descriptor)",
        'os.rmdir(state["private_name"], dir_fd=root_descriptor)',
        "os.fstat(private_descriptor).st_nlink != 0",
        "os.fsync(root_descriptor)",
        'os.path.lexists(state["canonical_path"])',
        'os.path.lexists(state["private_path"])',
    )
    contract.expect(
        all(token in option_remove_source for token in option_remove_tokens),
        "[maintenance] MariaDB restore bridge cleanup must re-prove option-file "
        "identity/digest/inventory, unlink and rmdir exact inodes, fsync both "
        "directories, and reject path reappearance",
    )
    bridge_function = restore_functions.get("guarded_mariadb_vendor_restore")
    bridge_execute_function = None
    bridge_state_assignment = None
    if bridge_function is not None:
        bridge_execute_function = next(
            (
                node
                for node in bridge_function.body
                if isinstance(node, ast.FunctionDef)
                and node.name == "guarded_execute_in_shell"
            ),
            None,
        )
        bridge_state_assignment = next(
            (
                node
                for node in bridge_function.body
                if isinstance(node, ast.Assign)
                and len(node.targets) == 1
                and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id == "bridge_state"
                and isinstance(node.value, ast.Dict)
            ),
            None,
        )

    def rendered_equals_name(node: ast.AST, name: str) -> bool:
        return (
            isinstance(node, ast.Compare)
            and isinstance(node.left, ast.Name)
            and node.left.id == "rendered"
            and len(node.ops) == 1
            and isinstance(node.ops[0], ast.Eq)
            and len(node.comparators) == 1
            and isinstance(node.comparators[0], ast.Name)
            and node.comparators[0].id == name
        )

    bridge_ast_contract_ok = False
    if (
        bridge_execute_function is not None
        and bridge_state_assignment is not None
    ):
        state_keys = tuple(
            key.value if isinstance(key, ast.Constant) else None
            for key in bridge_state_assignment.value.keys
        )
        state_values = bridge_state_assignment.value.values
        preflight_chain = next(
            (
                node
                for node in bridge_execute_function.body
                if isinstance(node, ast.If)
                and rendered_equals_name(node.test, "expected_file_probe")
            ),
            None,
        )
        sql_branch = (
            preflight_chain.orelse[0]
            if preflight_chain is not None
            and len(preflight_chain.orelse) == 1
            and isinstance(preflight_chain.orelse[0], ast.If)
            and rendered_equals_name(
                preflight_chain.orelse[0].test,
                "expected_sql_validation",
            )
            else None
        )
        expected_sql_assignments = [
            node
            for node in bridge_execute_function.body
            if isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id == "expected_sql_validation"
        ]
        sql_use_assignments = [
            node
            for node in ast.walk(sql_branch)
            if isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Subscript)
            and isinstance(node.targets[0].value, ast.Name)
            and node.targets[0].value.id == "bridge_state"
            and isinstance(node.targets[0].slice, ast.Constant)
            and node.targets[0].slice.value == "sql_validation_uses"
            and isinstance(node.value, ast.Constant)
            and node.value.value == 1
        ] if sql_branch is not None else []
        bridge_ast_contract_ok = (
            state_keys
            == (
                "uses",
                "file_probe_uses",
                "sql_validation_uses",
                "spawn_uses",
                "option_path",
                "client_suffix",
            )
            and all(
                isinstance(value, ast.Constant) and value.value == 0
                for value in state_values[:4]
            )
            and len(expected_sql_assignments) == 1
            and ast.get_source_segment(
                restore_source,
                expected_sql_assignments[0],
            )
            == 'expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path}"'
            and sql_branch is not None
            and len(sql_use_assignments) == 1
        )
    contract.expect(
        bridge_ast_contract_ok,
        "[maintenance] MariaDB restore bridge AST must model one explicit "
        "sql_validation_uses state and the exact file-then-/usr/bin/zgrep "
        "preflight branch before the generic restore-spawn branch",
    )

    vendor_probe_flag_guard = (
        "or verbose is not False\n"
        "                or low_priority is not False\n"
        "                or check_exit_code is not True"
    )
    bridge_tokens = (
        'required_call_keys = {"socket", "host", "port", "user", "db_name", "extra", "dump"}',
        'expected_call["port"] != 3306',
        'expected_call["user"] != expected_call["db_name"]',
        "exact_signature_shape(original_get_command)",
        "exact_signature_shape(original_execute_in_shell)",
        "exact_signature_shape(original_log_query)",
        "manager_get_command_present",
        "manager_execute_present",
        '"uses": 0',
        '"file_probe_uses": 0',
        '"sql_validation_uses": 0',
        '"spawn_uses": 0',
        "password=None",
        'injected_arguments = [option_argument, *arguments]',
        "contains_password_token(value)",
        "secret in rendered or shlex.quote(secret) in rendered",
        'expected_file_probe = f"file {expected_database_path}"',
        'expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path}"',
        'if rendered == expected_file_probe:\n'
        '            if (\n'
        '                bridge_state["file_probe_uses"] != 0\n'
        '                or bridge_state["sql_validation_uses"] != 0\n'
        '                or bridge_state["uses"] != 0\n'
        '                or bridge_state["spawn_uses"] != 0',
        'elif rendered == expected_sql_validation:\n'
        '            if (\n'
        '                bridge_state["file_probe_uses"] != 1\n'
        '                or bridge_state["sql_validation_uses"] != 0\n'
        '                or bridge_state["uses"] != 0\n'
        '                or bridge_state["spawn_uses"] != 0',
        'bridge_state["sql_validation_uses"] = 1',
        'fail("Frappe requested an unexpected restore child process")',
        'rendered.count("--defaults-extra-file=") != 1',
        "not rendered.endswith(client_suffix)",
        'exact_ddl_types = frozenset(("alter", "drop", "create", "truncate", "rename"))',
        "return original_log_query(",
        "for owner, attribute, original, guarded in reversed(installed_hooks):",
        "if getattr(owner, attribute) is not guarded:",
        "setattr(owner, attribute, original)",
        "remove_mariadb_client_option_file(option_state)",
        'bridge_state["uses"] != 1',
        'if (\n'
        '                bridge_state["file_probe_uses"] != 1\n'
        '                or bridge_state["sql_validation_uses"] != 1\n'
        '                or bridge_state["uses"] != 1',
        'or bridge_state["file_probe_uses"] != 1\n'
        '            or bridge_state["sql_validation_uses"] != 1\n'
        '            or bridge_state["spawn_uses"] != 1',
        'bridge_state["spawn_uses"] != 1',
    )
    contract.expect(
        all(token in bridge_source for token in bridge_tokens)
        and bridge_source.count(vendor_probe_flag_guard) == 2,
        "[maintenance] MariaDB restore bridge must pin vendor signatures/topology, "
        "require exact file -> zgrep -> get_command -> spawn ordering with identical "
        "vendor flags, inject defaults-extra-file as argv[0], guard every other "
        "child process and password token, suppress only DDL logging, require exact "
        "one-use, and restore every monkeypatch identity-safely",
    )
    bridge_fixture_ok, bridge_fixture_diagnostic = (
        _run_mariadb_vendor_bridge_fixture(restore_helper_path, restore_source)
    )
    contract.expect(
        bridge_fixture_ok,
        "[maintenance] MariaDB restore bridge isolated success/failure/zero/multi-use "
        "fixture must prove exact option bytes/modes, file/zgrep/get/spawn ordering, "
        "zgrep path/binary/pattern/flags and arbitrary child-process rejection, DDL "
        "delegation boundary, cleanup, and hook restoration"
        + (f": {bridge_fixture_diagnostic}" if bridge_fixture_diagnostic else ""),
    )

    def uses_sites_cwd_before_vendor_calls(
        function_name: str,
        require_restore_call: bool,
    ) -> bool:
        function = restore_functions.get(function_name)
        if function is None:
            return False

        def is_sites_chdir(call: ast.Call) -> bool:
            return (
                isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "os"
                and call.func.attr == "chdir"
                and len(call.args) == 1
                and isinstance(call.args[0], ast.Name)
                and call.args[0].id == "SITES_ROOT"
                and not call.keywords
            )

        direct_sites_chdirs = [
            statement.value
            for statement in function.body
            if isinstance(statement, ast.Expr)
            and isinstance(statement.value, ast.Call)
            and is_sites_chdir(statement.value)
        ]
        frappe_init_calls = [
            node
            for node in ast.walk(function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "frappe"
            and node.func.attr == "init"
        ]
        restore_calls = [
            node
            for node in ast.walk(function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "_restore"
        ]
        relevant_calls = [*frappe_init_calls, *restore_calls]
        function_source = ast.get_source_segment(restore_source, function) or ""
        return (
            len(direct_sites_chdirs) == 1
            and len(frappe_init_calls) == 1
            and len(restore_calls) == int(require_restore_call)
            and bool(relevant_calls)
            and direct_sites_chdirs[0].lineno
            < min(call.lineno for call in relevant_calls)
            and not any(
                isinstance(node, ast.Name) and node.id == "BENCH_ROOT"
                for node in ast.walk(function)
            )
            and "BENCH_ROOT" not in function_source
        )

    contract.expect(
        uses_sites_cwd_before_vendor_calls(
            "vendor_preflight",
            require_restore_call=False,
        ),
        "[maintenance] vendor_preflight must unconditionally chdir to SITES_ROOT "
        "before its sole frappe.init call and must never use BENCH_ROOT",
    )
    contract.expect(
        uses_sites_cwd_before_vendor_calls(
            "restore_bundle",
            require_restore_call=True,
        ),
        "[maintenance] restore_bundle must unconditionally chdir to SITES_ROOT "
        "before its sole frappe.init and vendor _restore calls and must never use "
        "BENCH_ROOT",
    )

    restore_bundle_function = restore_functions.get("restore_bundle")
    credential_rotation_contract_ok = False
    if restore_bundle_function is not None:
        restore_arguments = tuple(
            argument.arg for argument in restore_bundle_function.args.args
        )
        read_secret_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "read_secret"
        ]

        def exact_secret_read(
            call: ast.Call,
            path_name: str,
            label: str,
        ) -> bool:
            return (
                len(call.args) == 2
                and not call.keywords
                and isinstance(call.args[0], ast.Name)
                and call.args[0].id == path_name
                and isinstance(call.args[1], ast.Constant)
                and call.args[1].value == label
            )

        application_reads = [
            call
            for call in read_secret_calls
            if exact_secret_read(
                call,
                "application_secret_file",
                "Current MariaDB application secret",
            )
        ]
        root_reads = [
            call
            for call in read_secret_calls
            if exact_secret_read(
                call,
                "secret_file",
                "MariaDB root secret",
            )
        ]
        compare_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "secrets"
            and node.func.attr == "compare_digest"
            and len(node.args) == 2
            and not node.keywords
            and isinstance(node.args[0], ast.Name)
            and node.args[0].id == "deployment_password"
            and isinstance(node.args[1], ast.Subscript)
            and isinstance(node.args[1].value, ast.Name)
            and node.args[1].value.id == "expected_config"
            and isinstance(node.args[1].slice, ast.Constant)
            and node.args[1].slice.value == "db_password"
        ]
        prepare_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "prepare_empty_file_trees"
        ]
        persistent_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id
            in {
                "prepare_empty_file_trees",
                "write_live_site_config",
                "_restore",
                "commit_file_tree_replacement",
            }
        ]
        password_clear_assignments = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Assign)
            and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name)
            and node.targets[0].id == "deployment_password"
            and isinstance(node.value, ast.Constant)
            and node.value.value is None
        ]
        credential_rotation_contract_ok = (
            restore_arguments
            == (
                "bundle_value",
                "bundle_id",
                "site",
                "secret_file",
                "application_secret_file",
            )
            and len(read_secret_calls) == 2
            and len(application_reads) == 1
            and len(root_reads) == 1
            and len(compare_calls) == 1
            and len(prepare_calls) == 1
            and len(password_clear_assignments) == 1
            and bool(persistent_calls)
            and application_reads[0].lineno
            < compare_calls[0].lineno
            < password_clear_assignments[0].lineno
            < root_reads[0].lineno
            < min(call.lineno for call in persistent_calls)
            and "Selected bundle database credential does not match the current deployment secret"
            in restore_function_source("restore_bundle")
        )
    contract.expect(
        credential_rotation_contract_ok,
        "[maintenance] credential rotation guard must read the current application "
        "secret with its label, compare_digest it exactly against bundle db_password, "
        "clear it, and fail before root-secret access or any restore mutation",
    )

    parser_source = restore_function_source("build_parser")
    main_source = restore_function_source("main")
    contract.expect(
        parser_source.count(
            'command.add_argument("--application-secret-file", required=True)'
        )
        == 1
        and "arguments.application_secret_file" in main_source
        and re.search(
            r"restore_bundle\(\s*arguments\.bundle,\s*arguments\.bundle_id,\s*"
            r"arguments\.site,\s*arguments\.secret_file,\s*"
            r"arguments\.application_secret_file,\s*\)",
            main_source,
        )
        is not None,
        "[maintenance] credential rotation CLI must require and forward exactly one "
        "--application-secret-file into restore_bundle",
    )

    application_validator_match = re.search(
        r"(?ms)^validate_application_secret\(\) \{\n.*?^\}\n",
        wrapper_source,
    )
    run_restore_match = re.search(
        r"(?ms)^run_restore\(\) \(\n.*?^\)\n",
        wrapper_source,
    )
    application_validator_source = (
        application_validator_match.group(0)
        if application_validator_match is not None
        else ""
    )
    run_restore_source = (
        run_restore_match.group(0) if run_restore_match is not None else ""
    )
    root_validation_index = run_restore_source.find("  validate_root_secret\n")
    application_validation_index = run_restore_source.find(
        "  validate_application_secret\n"
    )
    helper_restore_index = run_restore_source.find(
        '  "$BENCH_PYTHON" "$RESTORE_HELPER" restore \\\n'
    )
    application_argument_index = run_restore_source.find(
        '    --application-secret-file "$APPLICATION_SECRET"'
    )
    validator_tokens = (
        '[[ -f "$APPLICATION_SECRET" && ! -L "$APPLICATION_SECRET" && -r "$APPLICATION_SECRET" ]]',
        'wc -c < "$APPLICATION_SECRET"',
        "secret_size >= MIN_SECRET_BYTES && secret_size <= MAX_SECRET_BYTES",
        "== 'CHANGE_ME'",
        "line_free_size == secret_size",
        "grep -q '[[:cntrl:]]' \"$APPLICATION_SECRET\"",
    )
    contract.expect(
        'readonly APPLICATION_SECRET=\'/run/secrets/MARIADB_PASSWORD\''
        in wrapper_source
        and all(token in application_validator_source for token in validator_tokens)
        and application_validator_source.count("APPLICATION_SECRET") >= 6
        and run_restore_match is not None
        and run_restore_source.count("validate_root_secret") == 1
        and run_restore_source.count("validate_application_secret") == 1
        and run_restore_source.count("--application-secret-file") == 1
        and -1
        < root_validation_index
        < application_validation_index
        < helper_restore_index
        < application_argument_index,
        "[maintenance] credential rotation shell guard must validate both mounted "
        "secret files before apply and pass the application-secret path exactly once",
    )

    rotation_fixture_ok, rotation_fixture_diagnostic = (
        _run_credential_rotation_fixture(restore_helper_path, restore_source)
    )
    contract.expect(
        rotation_fixture_ok,
        "[maintenance] credential rotation fixture must accept an exact match and "
        "reject mismatch/missing/malformed application secrets before prepare, "
        "root-secret access, vendor restore, or filesystem mutation"
        + (
            f": {rotation_fixture_diagnostic}"
            if rotation_fixture_diagnostic
            else ""
        ),
    )

    restore_logger_contract_ok = False
    if restore_bundle_function is not None:
        logger_imports = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.ImportFrom)
            and node.module == "frappe.utils.logger"
            and len(node.names) == 1
            and node.names[0].name == "set_log_level"
            and node.names[0].asname is None
        ]

        def is_restore_frappe_init(call: ast.Call) -> bool:
            return (
                isinstance(call.func, ast.Attribute)
                and isinstance(call.func.value, ast.Name)
                and call.func.value.id == "frappe"
                and call.func.attr == "init"
            )

        def is_restore_logger_guard(call: ast.Call) -> bool:
            return (
                isinstance(call.func, ast.Name)
                and call.func.id == "set_log_level"
                and len(call.args) == 1
                and isinstance(call.args[0], ast.Constant)
                and call.args[0].value == "ERROR"
                and not call.keywords
            )

        def is_vendor_restore(call: ast.Call) -> bool:
            return isinstance(call.func, ast.Name) and call.func.id == "_restore"

        restore_init_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call) and is_restore_frappe_init(node)
        ]
        restore_logger_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call) and is_restore_logger_guard(node)
        ]
        vendor_restore_calls = [
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Call) and is_vendor_restore(node)
        ]
        ordered_restore_guard = False
        for try_node in (
            node
            for node in ast.walk(restore_bundle_function)
            if isinstance(node, ast.Try)
        ):
            init_indices = [
                index
                for index, statement in enumerate(try_node.body)
                if isinstance(statement, ast.Expr)
                and isinstance(statement.value, ast.Call)
                and is_restore_frappe_init(statement.value)
            ]
            logger_indices = [
                index
                for index, statement in enumerate(try_node.body)
                if isinstance(statement, ast.Expr)
                and isinstance(statement.value, ast.Call)
                and is_restore_logger_guard(statement.value)
            ]
            restore_statement_indices = [
                index
                for index, statement in enumerate(try_node.body)
                if any(
                    isinstance(node, ast.Call) and is_vendor_restore(node)
                    for node in ast.walk(statement)
                )
            ]
            if any(
                init_index < logger_index < restore_index
                for init_index in init_indices
                for logger_index in logger_indices
                for restore_index in restore_statement_indices
            ):
                ordered_restore_guard = True
                break
        restore_logger_contract_ok = (
            len(logger_imports) == 1
            and len(restore_init_calls) == 1
            and len(restore_logger_calls) == 1
            and len(vendor_restore_calls) == 1
            and ordered_restore_guard
        )
    contract.expect(
        restore_logger_contract_ok,
        "[maintenance] restore_bundle must import set_log_level exactly and call "
        "set_log_level(\"ERROR\") after frappe.init but before vendor _restore "
        "on the same unconditional apply path",
    )

    def called_names(function_name: str) -> set[str]:
        function = restore_functions.get(function_name)
        if function is None:
            return set()
        names: set[str] = set()
        for node in ast.walk(function):
            if not isinstance(node, ast.Call):
                continue
            if isinstance(node.func, ast.Name):
                names.add(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                names.add(node.func.attr)
        return names

    restore_bundle_calls = called_names("restore_bundle")
    contract.expect(
        {
            "prepare_empty_file_trees",
            "write_live_site_config",
            "verify_restored_file_trees",
            "rollback_site_config",
            "rollback_file_trees",
            "commit_file_tree_replacement",
        }
        <= restore_bundle_calls,
        "[maintenance] restore apply must prepare, verify, rollback on failure, and "
        "commit the file-tree replacement",
    )
    restore_bundle = restore_functions.get("restore_bundle")
    rollback_in_exception = False
    if restore_bundle is not None:
        for node in ast.walk(restore_bundle):
            if not isinstance(node, ast.ExceptHandler):
                continue
            handler_source = ast.get_source_segment(restore_source, node) or ""
            config_index = handler_source.find("rollback_site_config(file_state)")
            files_index = handler_source.find("rollback_file_trees(file_state)")
            if -1 < config_index < files_index:
                rollback_in_exception = True
                break
    contract.expect(
        rollback_in_exception,
        "[maintenance] restore apply failures must rollback site_config before file "
        "trees in reverse mutation order",
    )

    config_rollback_function = restore_functions.get("rollback_site_config")
    config_rollback_source = (
        ast.get_source_segment(restore_source, config_rollback_function) or ""
        if config_rollback_function is not None
        else ""
    )
    contract.expect(
        all(
            token in config_rollback_source
            for token in (
                'regular_file_identity(original) != state["config_old_identity"]',
                'sha256_file(original, exact_mode=0o600) != state["config_old_digest"]',
                "os.replace(original, target)",
                'regular_file_identity(target) != state["config_old_identity"]',
                'sha256_file(target, exact_mode=0o600) != state["config_old_digest"]',
            )
        ),
        "[maintenance] site_config rollback must pin original identity/SHA-256 and "
        "atomically restore the quarantined inode",
    )

    prepare_function = restore_functions.get("prepare_empty_file_trees")
    prepare_source = (
        ast.get_source_segment(restore_source, prepare_function) or ""
        if prepare_function is not None
        else ""
    )
    same_filesystem_tokens = (
        "directory_identity(path)[0] != site_device",
        'f".erpnext-site-restore-quarantine.{bundle_id}"',
        'f".files.erpnext-site-replacement.{bundle_id}"',
        'os.rename(public_live, state["public_old"])',
        "os.rename(public_replacement, public_live)",
        'os.rename(private_live, state["private_old"])',
        "os.rename(private_replacement, private_live)",
    )
    token_positions = [prepare_source.find(token) for token in same_filesystem_tokens]
    contract.expect(
        all(position >= 0 for position in token_positions)
        and token_positions[3:] == sorted(token_positions[3:]),
        "[maintenance] restore must replace public/private trees through ordered "
        "same-filesystem quarantine renames",
    )

    rollback_function = restore_functions.get("rollback_file_trees")
    reverse_rollback = False
    if rollback_function is not None:
        for node in ast.walk(rollback_function):
            if not isinstance(node, ast.For) or not isinstance(node.target, ast.Name):
                continue
            if node.target.id != "prefix" or not isinstance(node.iter, ast.Tuple):
                continue
            order = tuple(
                element.value
                for element in node.iter.elts
                if isinstance(element, ast.Constant)
                and isinstance(element.value, str)
            )
            if order == ("private", "public") and len(node.iter.elts) == 2:
                reverse_rollback = True
                break
    contract.expect(
        reverse_rollback,
        "[maintenance] partially applied file trees must rollback in private/public "
        "reverse application order",
    )

    inventory_function = restore_functions.get("live_tree_inventory")
    inventory_source = (
        ast.get_source_segment(restore_source, inventory_function) or ""
        if inventory_function is not None
        else ""
    )
    contract.expect(
        all(
            token in inventory_source
            for token in (
                "unicodedata.category(character).startswith(\"C\")",
                "relative.as_posix()",
                "entry.stat(follow_symlinks=False)",
                "files[relative_name] = (metadata.st_size, sha256_file(path))",
                "restored live tree contains links or special nodes",
            )
        ),
        "[maintenance] live-tree inventory must preserve Unicode names and compare "
        "exact regular-file size/SHA-256 identities",
    )
    verify_function = restore_functions.get("verify_restored_file_trees")
    verify_source = (
        ast.get_source_segment(restore_source, verify_function) or ""
        if verify_function is not None
        else ""
    )
    contract.expect(
        "actual_public != expected_public or actual_private != expected_private"
        in verify_source,
        "[maintenance] restored public/private Unicode inventories must match both "
        "selected archives exactly",
    )
    restore_path = (
        template_root
        / "docker-compose.erpnext-site-maintenance.restore.yaml.example"
    )
    restore_compose = _load_yaml(restore_path, contract, "maintenance")
    restore_services = restore_compose.get("services")
    restore_service = (
        restore_services.get("erpnext-site-maintenance")
        if isinstance(restore_services, dict)
        else None
    )
    contract.expect(
        isinstance(restore_service, dict),
        "[maintenance] versioned restore override must target erpnext-site-maintenance",
    )
    if isinstance(restore_service, dict):
        contract.expect(
            restore_service.get("restart") == "no",
            "[maintenance] restore override must remain a bounded one-shot",
        )
        contract.expect(
            restore_service.get("command") == ["restore"],
            "[maintenance] restore override must explicitly select restore mode",
        )
        contract.expect(
            frozenset(_service_secret_names(restore_service))
            == frozenset({"MARIADB_ROOT_PASSWORD", "MARIADB_PASSWORD"})
            and len(_service_secret_names(restore_service)) == 2,
            "[maintenance] restore override must mount exactly the root and current "
            "application MariaDB credentials for the bounded rotation guard",
        )
        override_health = restore_service.get("healthcheck")
        contract.expect(
            isinstance(override_health, dict) and override_health.get("disable") is True,
            "[maintenance] restore one-shot must disable daemon health",
        )


def _check_secret_placeholders(
    root: Path,
    component_roots: dict[str, Path],
    component_documents: dict[str, dict[str, Any]],
    contract: Contract,
) -> None:
    root_secret_dir = root / "ERPNext/secrets"
    root_secret_files = {
        path.name
        for path in root_secret_dir.iterdir()
        if path.name != ".gitkeep"
    } if root_secret_dir.is_dir() else set()
    contract.expect(
        root_secret_files == EXPECTED_ROOT_SECRET_FILES,
        "[placeholder] ERPNext root must contain exactly the three bootstrap placeholders",
    )
    declared: set[str] = set()
    available: set[str] = set()
    all_roots = {"app": root / "ERPNext", **component_roots}
    for component, component_root in all_roots.items():
        document = component_documents.get(component, {})
        top_secrets = document.get("secrets")
        if isinstance(top_secrets, dict):
            declared.update(str(name) for name in top_secrets)
        secret_dir = component_root / "secrets"
        if not secret_dir.exists():
            continue
        try:
            directory_metadata = secret_dir.lstat()
        except OSError as error:
            contract.expect(False, f"[placeholder] cannot inspect {secret_dir}: {error}")
            continue
        contract.expect(
            stat.S_ISDIR(directory_metadata.st_mode)
            and not stat.S_ISLNK(directory_metadata.st_mode),
            f"[placeholder] secrets path must be a real directory: {secret_dir}",
        )
        if not stat.S_ISDIR(directory_metadata.st_mode) or stat.S_ISLNK(directory_metadata.st_mode):
            continue
        for path in sorted(secret_dir.iterdir(), key=lambda item: item.name):
            if path.name == ".gitkeep":
                continue
            try:
                metadata = path.lstat()
            except OSError as error:
                contract.expect(False, f"[placeholder] cannot inspect {path}: {error}")
                continue
            contract.expect(
                bool(re.fullmatch(r"[A-Z][A-Z0-9_]*", path.name)),
                f"[placeholder] secret filename is not uppercase: {path}",
            )
            contract.expect(
                stat.S_ISREG(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode),
                f"[placeholder] secret must be a regular non-symlink file: {path}",
            )
            contract.expect(
                not bool(metadata.st_mode & 0o111),
                f"[placeholder] secret placeholder must not be executable: {path}",
            )
            if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                continue
            try:
                payload = path.read_bytes()
            except OSError as error:
                contract.expect(False, f"[placeholder] cannot read {path}: {error}")
                continue
            contract.expect(
                payload == b"CHANGE_ME",
                f"[placeholder] secret must contain exact 9-byte CHANGE_ME: {path}",
            )
            available.add(path.name)
    contract.expect(
        declared <= available,
        f"[placeholder] declared secrets lack placeholders: {sorted(declared - available)}",
    )


def validate_stack(root: Path) -> ValidationResult:
    contract = Contract()
    app_path = root / "ERPNext/docker-compose.app.yaml"
    app_document = _load_yaml(app_path, contract, "layout")
    app_services = app_document.get("services")
    contract.expect(
        isinstance(app_services, dict) and tuple(app_services) == ("app",),
        "[layout] ERPNext root compose must contain exactly one service named app",
    )
    app_service = (
        app_services.get("app")
        if isinstance(app_services, dict) and isinstance(app_services.get("app"), dict)
        else {}
    )
    required = app_document.get("x-required-services")
    contract.expect(
        isinstance(required, list)
        and tuple(str(item) for item in required) == EXPECTED_REQUIRED_SERVICES,
        "[closure] x-required-services must equal the exact flat ERPNext closure",
    )
    contract.expect(
        app_document.get("x-secrets-use-app-gid") is True,
        "[secrets] ERPNext root must opt into APP_GID secret normalization",
    )
    exclusions = app_document.get("x-secret-generation-exclusions")
    contract.expect(
        isinstance(exclusions, list)
        and tuple(str(item) for item in exclusions) == EXPECTED_ROOT_EXCLUSIONS,
        "[secrets] only the provider-issued OIDC credentials may be generation exclusions",
    )

    templates_root = root / "templates"
    actual_erpnext_templates = {
        path.name
        for path in templates_root.glob("erpnext-*")
        if path.is_dir() and not path.is_symlink()
    }
    contract.expect(
        actual_erpnext_templates == EXPECTED_ERPNEXT_TEMPLATES,
        "[closure] templates/erpnext-* inventory must exactly match the root closure",
    )

    component_documents: dict[str, dict[str, Any]] = {"app": app_document}
    component_roots: dict[str, Path] = {}
    services: dict[str, dict[str, Any]] = {"app": app_service}
    for template_name in EXPECTED_REQUIRED_SERVICES:
        template_root = templates_root / template_name
        component_roots[template_name] = template_root
        contract.expect(
            template_root.is_dir() and not template_root.is_symlink(),
            f"[closure] required template directory missing or unsafe: {template_name}",
        )
        compose_path = _template_compose_path(root, template_name)
        matching_primary_files = (
            [
                path
                for path in template_root.glob("docker-compose.*.yaml")
                if not path.name.endswith(".restore.yaml")
            ]
            if template_root.is_dir()
            else []
        )
        contract.expect(
            matching_primary_files == [compose_path],
            f"[layout] {template_name} must have exactly one canonical primary compose file",
        )
        document = _load_yaml(compose_path, contract, "layout")
        component_documents[template_name] = document
        contract.expect(
            "x-required-services" not in document,
            f"[closure] {template_name} must not introduce recursive required services",
        )
        template_services = document.get("services")
        contract.expect(
            isinstance(template_services, dict)
            and tuple(template_services) == (template_name,),
            f"[layout] {template_name} compose must contain exactly its one service",
        )
        if (
            isinstance(template_services, dict)
            and isinstance(template_services.get(template_name), dict)
        ):
            contract.expect(
                template_name not in services,
                f"[layout] duplicate merged service name: {template_name}",
            )
            services[template_name] = template_services[template_name]

    contract.expect(
        set(services) == {"app", *EXPECTED_REQUIRED_SERVICES},
        "[closure] merged service inventory must equal app plus the flat closure",
    )

    root_env = _load_env(_source_env_path(root), contract, "versions")
    contract.expect(
        root_env.get("APP_IMAGE") == "frappe/erpnext:v16",
        "[versions] APP_IMAGE must use the moving frappe/erpnext:v16 tag",
    )
    contract.expect(
        root_env.get("MARIADB_IMAGE") == "mariadb:11.8",
        "[versions] ERPNext compatibility override must remain mariadb:11.8",
    )
    contract.expect(
        root_env.get("MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT") == "1"
        and root_env.get("MARIADB_SYNC_BINLOG") == "1",
        "[database] ERPNext production MariaDB durability must remain exact 1/1 "
        "redo-log and binary-log synchronization",
    )
    _check_mariadb_binlog_policy(
        root_env,
        component_roots["mariadb"],
        component_documents["mariadb"],
        contract,
    )
    for service_name in STOCK_FRAPPE_SERVICES:
        service = services.get(service_name, {})
        contract.expect(
            service.get("image") == "${APP_IMAGE:?Image required}",
            f"[versions] {service_name} must inherit the stock moving v16 image",
        )
    assets_service = services.get("erpnext-assets-bootstrap", {})
    contract.expect(
        assets_service.get("entrypoint") == ["/usr/local/bin/entrypoint.sh"]
        and assets_service.get("command")
        == ["/usr/local/bin/erpnext-assets-bootstrap.sh"],
        "[entrypoint] assets bootstrap must be the sole bounded owner of the "
        "vendor /usr/local/bin/entrypoint.sh",
    )
    vendor_entrypoint_owners = {
        service_name
        for service_name in STOCK_FRAPPE_SERVICES
        if services.get(service_name, {}).get("entrypoint")
        == ["/usr/local/bin/entrypoint.sh"]
    }
    contract.expect(
        vendor_entrypoint_owners == {"erpnext-assets-bootstrap"},
        "[entrypoint] exactly erpnext-assets-bootstrap may execute the "
        "asset-mutating vendor entrypoint",
    )
    contract.expect(
        app_service.get("entrypoint")
        == ["/usr/local/bin/saervices-erpnext-frontend.sh"]
        and app_service.get("command") == [],
        "[entrypoint] public frontend must use the root-owned Nginx wrapper with "
        "the image CMD disabled",
    )
    for service_name in ROOT_RUNTIME_WRAPPER_SERVICES:
        service = services.get(service_name, {})
        contract.expect(
            service.get("entrypoint")
            == ["/usr/local/bin/saervices-erpnext-runtime-entrypoint.sh"],
            f"[entrypoint] {service_name} must use the root-owned non-mutating "
            "runtime wrapper",
        )
        contract.expect(
            "./scripts/erpnext-runtime-entrypoint.sh:"
            "/usr/local/bin/saervices-erpnext-runtime-entrypoint.sh:ro"
            in tuple(
                str(item)
                for item in service.get("volumes", [])
                if isinstance(item, str)
            ),
            f"[entrypoint] {service_name} must mount the reviewed root runtime wrapper",
        )
    assets_volumes = tuple(
        str(item)
        for item in assets_service.get("volumes", [])
        if isinstance(item, str)
    )
    contract.expect(
        "erpnext_sites:/home/frappe/frappe-bench/sites:rw" in assets_volumes
        and "./scripts/erpnext-assets-bootstrap.sh:"
        "/usr/local/bin/erpnext-assets-bootstrap.sh:ro" in assets_volumes
        and assets_service.get("network_mode") == "none"
        and "networks" not in assets_service,
        "[entrypoint] assets bootstrap must be a networkless one-shot with the "
        "only vendor-writable sites/assets mount",
    )
    runtime_wrapper_source = _regular_text(
        root / "ERPNext/scripts/erpnext-runtime-entrypoint.sh",
        contract,
        "entrypoint",
    )
    active_runtime_wrapper = "\n".join(
        line.split("#", 1)[0] for line in runtime_wrapper_source.splitlines()
    )
    contract.expect(
        '[[ -L "${assets_path}" ]]' in runtime_wrapper_source
        and 'readlink -- "${assets_path}"' in runtime_wrapper_source
        and 'exec "$@"' in runtime_wrapper_source
        and not re.search(
            r"(?:^|[;&|()\s])(?:ln|mv|cp|rm|mkdir|touch|chmod|chown)(?:\s|$)",
            active_runtime_wrapper,
        ),
        "[entrypoint] root runtime wrapper must only validate the exact assets link "
        "before exec and never mutate sites/assets",
    )
    assets_wrapper_source = _regular_text(
        root
        / "templates/erpnext-assets-bootstrap/scripts/erpnext-assets-bootstrap.sh",
        contract,
        "entrypoint",
    )
    contract.expect(
        '[[ -L "${assets_path}" ]]' in assets_wrapper_source
        and 'readlink -- "${assets_path}"' in assets_wrapper_source
        and not re.search(
            r"(?m)^[ \t]*(?:ln|mv|cp|rm|mkdir|touch|chmod|chown)\b",
            assets_wrapper_source,
        ),
        "[entrypoint] assets bootstrap post-hook must validate the vendor-created "
        "link without performing a second mutation",
    )
    frontend_source = _regular_text(
        root / "ERPNext/scripts/erpnext-frontend.sh", contract, "entrypoint"
    )
    dangerous_file_location = (
        "location ~* ^/(?:private/)?files/.*\\."
        "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {"
    )
    contract.expect(
        'ERPNEXT_VENDOR_NGINX_ENTRYPOINT:-/usr/local/bin/nginx-entrypoint.sh' in frontend_source
        and 'exec "${ERPNEXT_VENDOR_NGINX_ENTRYPOINT}"' in frontend_source
        and f"require_template_marker '{dangerous_file_location}'"
        in frontend_source,
        "[entrypoint] frontend wrapper must hand off to the inspected vendor Nginx "
        "entrypoint and pin the full browser-active download regex",
    )
    frontend_volumes = set(_volume_sources(app_service))
    contract.expect(
        frontend_volumes
        == {
            "./scripts/erpnext-frontend.sh",
            "./config/nginx-frappe.conf.template",
        }
        and not ({"erpnext_sites", "erpnext_logs"} & frontend_volumes),
        "[frontend] public Nginx must mount only its wrapper/template and no "
        "shared sites or logs volume",
    )
    image_oci_volume_targets = {
        "/home/frappe/frappe-bench/sites",
        "/home/frappe/frappe-bench/logs",
    }
    frontend_tmpfs = tuple(
        str(item) for item in app_service.get("tmpfs", []) if isinstance(item, str)
    )
    expected_frontend_masks = {
        "/home/frappe/frappe-bench/sites:rw,noexec,nosuid,nodev,size=1m,"
        "uid=1000,gid=1000,mode=0700",
        "/home/frappe/frappe-bench/logs:rw,noexec,nosuid,nodev,size=4m,"
        "uid=1000,gid=1000,mode=0700",
    }
    contract.expect(
        expected_frontend_masks <= set(frontend_tmpfs)
        and not (image_oci_volume_targets & set(_volume_targets(app_service)))
        and image_oci_volume_targets <= set(_tmpfs_targets(app_service)),
        "[frontend] Root HostConfig.Tmpfs must privately mask both image-declared "
        "sites/logs OCI VOLUMEs while Compose mounts neither shared volume",
    )
    log_mask = (
        "/home/frappe/frappe-bench/logs:rw,noexec,nosuid,nodev,size=4m,"
        "uid=${APP_UID:-1000},gid=${APP_GID:-1000},mode=0700"
    )
    for service_name in ("erpnext-assets-bootstrap", "erpnext-configurator"):
        service = services.get(service_name, {})
        service_tmpfs = tuple(
            str(item)
            for item in service.get("tmpfs", [])
            if isinstance(item, str)
        )
        contract.expect(
            log_mask in service_tmpfs
            and "/home/frappe/frappe-bench/logs"
            not in set(_volume_targets(service)),
            f"[storage] {service_name} must mask its unused logs OCI VOLUME with "
            "bounded private tmpfs",
        )
    scheduler_service = services.get("erpnext-scheduler", {})
    scheduler_config_tmpfs = tuple(
        str(item)
        for item in scheduler_service.get("tmpfs", [])
        if isinstance(item, str)
        and item.split(":", 1)[0] == "/home/frappe/frappe-bench/config"
    )
    contract.expect(
        scheduler_config_tmpfs == (PRIVATE_FRAPPE_CONFIG_TMPFS,)
        and "/home/frappe/frappe-bench/config"
        not in set(_volume_targets(scheduler_service)),
        "[scheduler] read-only scheduler must have exactly one bounded private "
        "config tmpfs for the vendor scheduler_process lock",
    )
    contract.expect(
        scheduler_service.get("command")
        == [
            "/bin/sh",
            "-c",
            "set -eu; umask 077; mkdir -p "
            "/home/frappe/frappe-bench/config/pids; chmod 0700 "
            "/home/frappe/frappe-bench/config/pids; exec bench schedule",
        ],
        "[scheduler] scheduler command must fail fast while privately creating "
        "config/pids with umask 077 and mode 0700 before exec bench schedule",
    )
    for service_name in (*STOCK_FRAPPE_SERVICES, "erpnext-site-maintenance"):
        service = services.get(service_name, {})
        explicit_mount_targets = set(_volume_targets(service)) | set(
            _tmpfs_targets(service)
        )
        uncovered_oci_targets = image_oci_volume_targets - explicit_mount_targets
        contract.expect(
            not uncovered_oci_targets,
            f"[storage] {service_name} leaves known Frappe OCI VOLUMEs uncovered "
            f"and would create anonymous volumes: {sorted(uncovered_oci_targets)}",
        )
    frontend_environment = app_service.get("environment")
    contract.expect(
        isinstance(frontend_environment, dict)
        and frontend_environment.get("FRAPPE_SITE_NAME_HEADER")
        == "${ERPNEXT_SITE_NAME:?ERPNext site name required}",
        "[frontend] public Nginx must derive one fixed site Host from "
        "ERPNEXT_SITE_NAME",
    )
    nginx_source = _regular_text(
        root / "ERPNext/config/nginx-frappe.conf.template",
        contract,
        "frontend",
    )
    required_nginx_tokens = (
        "server_name ${FRAPPE_SITE_NAME_HEADER};",
        "server_tokens off;",
        "root /home/frappe/frappe-bench;",
        "proxy_set_header Host ${FRAPPE_SITE_NAME_HEADER};",
        "proxy_pass http://backend-server;",
        "proxy_pass http://socketio-server;",
        dangerous_file_location,
        "proxy_hide_header Content-Disposition;",
        'add_header Content-Disposition "attachment" always;',
    )
    forbidden_nginx_tokens = (
        "/home/frappe/frappe-bench/sites",
        "X-Use-X-Accel-Redirect",
        "proxy_set_header Host $host;",
        "proxy_set_header Host $http_host;",
    )
    contract.expect(
        all(token in nginx_source for token in required_nginx_tokens)
        and not any(token in nginx_source for token in forbidden_nginx_tokens),
        "[frontend] custom Nginx must use the fixed site Host, baked assets, and "
        "backend-proxied files without X-Accel/site-volume shortcuts",
    )
    contract.expect(
        nginx_source.count("proxy_set_header X-Forwarded-For $remote_addr;") == 3
        and "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
        not in nginx_source
        and nginx_source.count(
            "proxy_set_header Host ${FRAPPE_SITE_NAME_HEADER};"
        )
        == 3,
        "[frontend] socket.io, dangerous-file, and general proxy routes must replace "
        "X-Forwarded-For with $remote_addr and use the fixed site Host",
    )
    dangerous_files_location = re.search(
        r"(?ms)^\s*location ~\* \^/\(\?:private/\)\?files/\.\*"
        r"\\\.\(\?:htm\|html\|xht\|xhtml\|svg\|svgz\|xml\)\$ "
        r"\{\n(.*?)^\s*\}",
        nginx_source,
    )
    dangerous_files_source = (
        dangerous_files_location.group(1) if dangerous_files_location else ""
    )
    contract.expect(
        dangerous_files_location is not None
        and "proxy_hide_header Content-Disposition;" in dangerous_files_source
        and 'add_header Content-Disposition "attachment" always;'
        in dangerous_files_source
        and "proxy_set_header Host ${FRAPPE_SITE_NAME_HEADER};"
        in dangerous_files_source
        and "proxy_set_header X-Frappe-Site-Name ${FRAPPE_SITE_NAME_HEADER};"
        in dangerous_files_source
        and "proxy_pass http://backend-server;" in dangerous_files_source,
        "[frontend] public/private browser-active file types must reach the "
        "authenticated backend with forced attachment semantics",
    )
    backend_command = services.get("erpnext-backend", {}).get("command")
    contract.expect(
        isinstance(backend_command, list)
        and backend_command[-1:] == ["frappe.app:application_with_statics()"],
        "[frontend] backend Gunicorn must expose application_with_statics() for "
        "public/private file delivery without a frontend sites mount",
    )
    worker_contracts = {
        "erpnext-worker-short": {
            "queue": "short,default",
            "variable": "ERPNEXT_WORKER_SHORT_PROCESSES",
            "script": "erpnext-worker-short-healthcheck.py",
            "queue_tokens": ('generate_qname("short")', 'generate_qname("default")'),
        },
        "erpnext-worker-long": {
            "queue": "long,default,short",
            "variable": "ERPNEXT_WORKER_LONG_PROCESSES",
            "script": "erpnext-worker-long-healthcheck.py",
            "queue_tokens": (
                'generate_qname("long")',
                'generate_qname("default")',
                'generate_qname("short")',
            ),
        },
    }
    for service_name, worker_contract in worker_contracts.items():
        service = services.get(service_name, {})
        variable = worker_contract["variable"]
        script_name = worker_contract["script"]
        expected_command = [
            "/bin/sh",
            "-c",
            "set -eu; umask 077; mkdir -p "
            "/home/frappe/frappe-bench/config/pids; chmod 0700 "
            "/home/frappe/frappe-bench/config/pids; exec bench worker-pool "
            f'--queue {worker_contract["queue"]} --num-workers "$${{{variable}}}"',
        ]
        environment = service.get("environment")
        worker_env = _load_env(
            component_roots[service_name] / ".env",
            contract,
            "workers",
        )
        contract.expect(
            isinstance(environment, dict)
            and environment.get(variable) == f"${{{variable}:-1}}"
            and worker_env.get(variable) == "1",
            f"[workers] {service_name} must retain bounded worker-pool count "
            f"{variable}=1",
        )
        worker_config_tmpfs = tuple(
            str(item)
            for item in service.get("tmpfs", [])
            if isinstance(item, str)
            and item.split(":", 1)[0] == "/home/frappe/frappe-bench/config"
        )
        contract.expect(
            worker_config_tmpfs == (PRIVATE_FRAPPE_CONFIG_TMPFS,)
            and "/home/frappe/frappe-bench/config"
            not in set(_volume_targets(service)),
            f"[workers] {service_name} must have exactly one bounded private "
            "config tmpfs for Frappe's internal scheduler_process lock",
        )
        contract.expect(
            service.get("command") == expected_command,
            f"[workers] {service_name} must fail fast while privately creating "
            "config/pids with umask 077 and mode 0700 before exec of its exact "
            "bounded worker-pool queue/count command",
        )
        healthcheck = service.get("healthcheck")
        contract.expect(
            isinstance(healthcheck, dict)
            and healthcheck.get("test")
            == [
                "CMD",
                "/home/frappe/frappe-bench/env/bin/python",
                f"/usr/local/bin/{script_name}",
            ],
            f"[workers] {service_name} must execute its semantic worker healthcheck",
        )
        health_source = _regular_text(
            root / "templates" / service_name / "scripts" / script_name,
            contract,
            "workers",
        )
        required_health_tokens = (
            "get_redis_conn",
            "get_workers",
            "connection.ping() is not True",
            "expected_worker_count = int(worker_count_value)",
            "expected_worker_count > 32",
            "healthy_workers >= expected_worker_count",
            'state_name in {"idle", "busy", "started"}',
            "local_hostname = socket.gethostname()",
            "worker.hostname != local_hostname",
            'Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\\0")',
            'Path(f"/proc/{pid}/stat").read_text(encoding="ascii")',
            'b"worker-pool" in process_argv',
            'process_state in {"R", "S", "D", "I"}',
            "is_live_local_worker(worker)",
            *worker_contract["queue_tokens"],
        )
        contract.expect(
            all(token in health_source for token in required_health_tokens),
            f"[workers] {service_name} healthcheck must verify Redis, exact queues, "
            "live states, and the configured process count",
        )
    contract.expect(
        "validate_worker_count 'ERPNEXT_WORKER_SHORT_PROCESSES'"
        in runtime_wrapper_source
        and "validate_worker_count 'ERPNEXT_WORKER_LONG_PROCESSES'"
        in runtime_wrapper_source
        and "10#${value} <= 32" in runtime_wrapper_source
        and "must not configure both ERPNext worker-pool roles"
        in runtime_wrapper_source,
        "[workers] root runtime wrapper must reject non-canonical, oversized, or "
        "cross-role worker counts before process startup",
    )
    redis_expected = {
        "erpnext-redis-cache": (
            "ERPNEXT_REDIS_CACHE_IMAGE",
            "docker.io/library/redis:8-alpine",
        ),
        "erpnext-redis-queue": (
            "ERPNEXT_REDIS_QUEUE_IMAGE",
            "docker.io/library/redis:8-alpine",
        ),
    }
    for service_name, (key, expected_image) in redis_expected.items():
        values = _load_env(
            component_roots[service_name] / ".env", contract, "versions"
        )
        contract.expect(
            values.get(key) == expected_image,
            f"[versions] {service_name} must use the moving Redis 8 Alpine tag",
        )
    maintenance_values = _load_env(
        component_roots["erpnext-site-maintenance"] / ".env",
        contract,
        "versions",
    )
    contract.expect(
        maintenance_values.get("ERPNEXT_SITE_MAINTENANCE_IMAGE")
        == "frappe/erpnext:v16",
        "[versions] site-maintenance build must use the moving Frappe v16 base",
    )
    maintenance_dockerfile = _regular_text(
        component_roots["erpnext-site-maintenance"]
        / "dockerfiles/dockerfile.erpnext-site-maintenance",
        contract,
        "versions",
    )
    contract.expect(
        "ARG ERPNEXT_SITE_MAINTENANCE_IMAGE=frappe/erpnext:v16"
        in maintenance_dockerfile,
        "[versions] site-maintenance Dockerfile default must use frappe/erpnext:v16",
    )

    dependency_map: dict[str, dict[str, str]] = {}
    for service_name, expected in EXPECTED_DEPENDENCIES.items():
        service = services.get(service_name, {})
        actual = _dependency_conditions(service, contract, service_name)
        dependency_map[service_name] = actual
        contract.expect(
            actual == expected,
            f"[dependency] {service_name} dependency chain differs: {actual!r}",
        )
        for dependency, condition in actual.items():
            contract.expect(
                dependency in services,
                f"[dependency] {service_name} references unknown service {dependency}",
            )
            if dependency in ONE_SHOT_SERVICES:
                contract.expect(
                    condition == "service_completed_successfully",
                    f"[dependency] {service_name} must wait for successful {dependency} completion",
                )
    _check_dependency_acyclic(dependency_map, contract)
    for service_name in ONE_SHOT_SERVICES:
        service = services.get(service_name, {})
        contract.expect(
            service.get("restart") == "no",
            f"[dependency] {service_name} must remain a bounded restart:no one-shot",
        )
        healthcheck = service.get("healthcheck")
        contract.expect(
            isinstance(healthcheck, dict) and healthcheck.get("disable") is True,
            f"[dependency] {service_name} completion must replace daemon health",
        )
    for service_name in LONG_RUNNING_FRAPPE_SERVICES:
        service = services.get(service_name, {})
        contract.expect(
            service.get("restart") == "unless-stopped",
            f"[dependency] {service_name} must be a long-running service",
        )
        healthcheck = service.get("healthcheck")
        contract.expect(
            isinstance(healthcheck, dict)
            and bool(healthcheck.get("test"))
            and healthcheck.get("disable") is not True,
            f"[dependency] {service_name} must have an active healthcheck",
        )

    for service_name, expected in EXPECTED_SERVICE_SECRETS.items():
        service = services.get(service_name, {})
        actual_tuple = _service_secret_names(service)
        actual = frozenset(actual_tuple)
        contract.expect(
            len(actual_tuple) == len(actual),
            f"[secrets] {service_name} contains duplicate secret mounts",
        )
        contract.expect(
            actual == expected,
            f"[secrets] {service_name} least-privilege secret set differs: {sorted(actual)}",
        )
        user = str(service.get("user", ""))
        groups = service.get("group_add")
        group_values = tuple(str(item) for item in groups) if isinstance(groups, list) else ()
        if expected and "${APP_GID:-1000}" not in user:
            contract.expect(
                group_values == ("${APP_GID:-1000}",),
                f"[secrets] {service_name} needs only supplementary APP_GID secret access",
            )
    for service_name in LONG_RUNNING_FRAPPE_SERVICES:
        mounted = frozenset(_service_secret_names(services.get(service_name, {})))
        contract.expect(
            not (mounted & BOOTSTRAP_SECRET_NAMES),
            f"[secrets] long-running {service_name} received bootstrap secrets",
        )

    expected_host_values = {
        ("app", "BACKEND"): "${APP_NAME}-erpnext-backend:8000",
        ("app", "SOCKETIO"): "${APP_NAME}-erpnext-websocket:9000",
        (
            "erpnext-configurator",
            "ERPNEXT_DATABASE_HOST",
        ): "${APP_NAME:?App name required}-mariadb",
        (
            "erpnext-configurator",
            "ERPNEXT_REDIS_CACHE_HOST",
        ): "${APP_NAME:?App name required}-erpnext-redis-cache",
        (
            "erpnext-configurator",
            "ERPNEXT_REDIS_QUEUE_HOST",
        ): "${APP_NAME:?App name required}-erpnext-redis-queue",
        (
            "erpnext-site-bootstrap",
            "ERPNEXT_DATABASE_HOST",
        ): "${APP_NAME:?App name required}-mariadb",
    }
    for (service_name, key), expected_value in expected_host_values.items():
        environment = services.get(service_name, {}).get("environment")
        actual_value = environment.get(key) if isinstance(environment, dict) else None
        contract.expect(
            actual_value == expected_value,
            f"[hostnames] {service_name}.{key} must use the APP_NAME-scoped endpoint",
        )
    contract.expect(
        app_service.get("container_name") == "${APP_NAME:?App name required}"
        and app_service.get("hostname") == "${APP_NAME}",
        "[hostnames] root app identity must remain APP_NAME-scoped",
    )
    for service_name in EXPECTED_REQUIRED_SERVICES:
        service = services.get(service_name, {})
        expected_container = f"${{APP_NAME:?App name required}}-{service_name}"
        expected_hostname = f"${{APP_NAME}}-{service_name}"
        contract.expect(
            service.get("container_name") == expected_container,
            f"[hostnames] {service_name} container_name is not project-scoped",
        )
        contract.expect(
            service.get("hostname") == expected_hostname,
            f"[hostnames] {service_name} hostname is not project-scoped",
        )

    root_volumes = app_document.get("volumes")
    contract.expect(
        isinstance(root_volumes, dict)
        and set(root_volumes) == {"erpnext_sites", "erpnext_logs"},
        "[storage] root named volumes must be exactly erpnext_sites and erpnext_logs",
    )
    for service_name in ROOT_RUNTIME_WRAPPER_SERVICES:
        sources = set(_volume_sources(services.get(service_name, {})))
        contract.expect(
            "erpnext_sites" in sources,
            f"[storage] {service_name} must mount erpnext_sites",
        )
        if service_name != "erpnext-configurator":
            contract.expect(
                "erpnext_logs" in sources,
                f"[storage] {service_name} must mount erpnext_logs",
            )
    contract.expect(
        set(_volume_sources(assets_service))
        == {"erpnext_sites", "./scripts/erpnext-assets-bootstrap.sh"},
        "[storage] assets bootstrap must mount only sites plus its read-only validator",
    )
    maintenance_sources = set(
        _volume_sources(services.get("erpnext-site-maintenance", {}))
    )
    contract.expect(
        {"erpnext_sites", "erpnext_logs", "./appdata/erpnext-backups"}
        <= maintenance_sources,
        "[storage] site maintenance must retain sites, logs, and its unique backup tree",
    )
    contract.expect(
        "erpnext_redis_queue"
        in set(_volume_sources(services.get("erpnext-redis-queue", {}))),
        "[storage] Redis queue must persist its AOF/RDB data",
    )
    contract.expect(
        not any(
            source == "erpnext_redis_cache"
            for source in _volume_sources(services.get("erpnext-redis-cache", {}))
        ),
        "[storage] Redis cache must remain intentionally ephemeral",
    )
    contract.expect(
        set(_network_names(app_service)) == {"frontend", "erpnext_app"},
        "[networks] public app must join exactly frontend and erpnext_app",
    )
    root_networks = app_document.get("networks")
    root_network_ok = isinstance(root_networks, dict) and set(root_networks) == {
        "frontend",
        "erpnext_app",
        "backend",
    }
    if root_network_ok:
        root_network_ok = (
            all(
            isinstance(root_networks[name], dict)
            and root_networks[name].get("external") is True
            for name in ("frontend", "backend")
            )
            and isinstance(root_networks["erpnext_app"], dict)
            and root_networks["erpnext_app"].get("internal") is True
            and root_networks["erpnext_app"].get("name")
            == "${APP_NAME:?App name required}_erpnext_app"
        )
    contract.expect(
        root_network_ok,
        "[networks] root must declare external frontend/backend plus the named "
        "internal erpnext_app network",
    )
    application_network_members = {
        service_name
        for service_name, service in services.items()
        if "erpnext_app" in set(_network_names(service))
    }
    contract.expect(
        application_network_members == {"app", "erpnext-backend", "erpnext-websocket"},
        "[networks] internal erpnext_app membership must be exactly frontend, "
        "backend, and websocket",
    )
    for service_name in {"erpnext-backend", "erpnext-websocket"}:
        contract.expect(
            set(_network_names(services.get(service_name, {})))
            == {"erpnext_app", "backend"},
            f"[networks] {service_name} must bridge only erpnext_app and backend",
        )
    backend_only_services = set(EXPECTED_REQUIRED_SERVICES) - {
        "erpnext-assets-bootstrap",
        "erpnext-backend",
        "erpnext-websocket",
    }
    for service_name in backend_only_services:
        contract.expect(
            set(_network_names(services.get(service_name, {}))) == {"backend"},
            f"[networks] backend template {service_name} must join only backend",
        )
    contract.expect(
        assets_service.get("network_mode") == "none"
        and not _network_names(assets_service),
        "[networks] assets bootstrap must remain fully networkless",
    )
    for service_name in {"app", *EXPECTED_ERPNEXT_TEMPLATES}:
        service = services.get(service_name, {})
        contract.expect(
            "ports" not in service,
            f"[networks] {service_name} must not publish a direct host port by default",
        )

    active_compose_strings = "\n".join(
        scalar
        for document in component_documents.values()
        for scalar in _iter_scalar_strings(document)
    ).lower()
    contract.expect(
        "authentik-proxy" not in active_compose_strings
        and "forwardauth" not in active_compose_strings
        and "forward_auth" not in active_compose_strings,
        "[oidc] ERPNext must use native OIDC without active Traefik ForwardAuth",
    )
    _check_site_domain_guards(root, contract)
    _check_site_bootstrap(root, contract)
    _check_oidc(root, root_env, contract)
    _check_maintenance(
        root,
        root_env,
        services.get("erpnext-site-maintenance", {}),
        component_documents.get("erpnext-site-maintenance", {}),
        contract,
    )
    _check_secret_placeholders(root, component_roots, component_documents, contract)
    return ValidationResult(contract.errors, contract.assertions)


def _write_yaml(path: Path, mutate: Callable[[dict[str, Any]], None]) -> None:
    with path.open("r", encoding="utf-8") as handle:
        document = yaml.load(handle, Loader=UniqueKeyLoader)
    if not isinstance(document, dict):
        raise AssertionError(f"fixture YAML is not a mapping: {path}")
    mutate(document)
    path.write_text(
        yaml.safe_dump(document, sort_keys=False, allow_unicode=True),
        encoding="utf-8",
    )


def _replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise AssertionError(
            f"fixture mutation expected one occurrence in {path}: {old!r}"
        )
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def _replace_count(
    path: Path,
    old: str,
    new: str,
    expected_count: int,
) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != expected_count:
        raise AssertionError(
            f"fixture mutation expected {expected_count} occurrences in {path}: "
            f"{old!r}"
        )
    path.write_text(source.replace(old, new), encoding="utf-8")


def _move_logger_guard_after_call(
    path: Path,
    function_name: str,
    target_call_name: str,
) -> None:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))
    functions = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == function_name
    ]
    if len(functions) != 1:
        raise AssertionError(
            f"fixture mutation expected one function {function_name!r} in {path}"
        )
    function = functions[0]

    def is_logger_guard(statement: ast.AST) -> bool:
        return (
            isinstance(statement, ast.Expr)
            and isinstance(statement.value, ast.Call)
            and isinstance(statement.value.func, ast.Name)
            and statement.value.func.id == "set_log_level"
            and len(statement.value.args) == 1
            and isinstance(statement.value.args[0], ast.Constant)
            and statement.value.args[0].value == "ERROR"
            and not statement.value.keywords
        )

    def is_target(statement: ast.AST) -> bool:
        if not isinstance(statement, ast.Expr) or not isinstance(
            statement.value, ast.Call
        ):
            return False
        function_node = statement.value.func
        return (
            isinstance(function_node, ast.Name)
            and function_node.id == target_call_name
        ) or (
            isinstance(function_node, ast.Attribute)
            and function_node.attr == target_call_name
        )

    logger_statements = [node for node in ast.walk(function) if is_logger_guard(node)]
    target_statements = [node for node in ast.walk(function) if is_target(node)]
    if len(logger_statements) != 1 or len(target_statements) != 1:
        raise AssertionError(
            "fixture mutation expected one exact logger guard and one target call "
            f"{target_call_name!r} in {path}:{function_name}"
        )
    logger_statement = logger_statements[0]
    target_statement = target_statements[0]
    if logger_statement.lineno >= target_statement.lineno:
        raise AssertionError("fixture logger guard does not precede its target call")
    lines = source.splitlines(keepends=True)
    target_line = lines[target_statement.lineno - 1]
    indentation = target_line[: len(target_line) - len(target_line.lstrip())]
    logger_index = logger_statement.lineno - 1
    target_end_index = target_statement.end_lineno - 1
    lines.pop(logger_index)
    if logger_index <= target_end_index:
        target_end_index -= 1
    lines.insert(target_end_index + 1, f'{indentation}set_log_level("ERROR")\n')
    path.write_text("".join(lines), encoding="utf-8")


def _move_site_guard_after_first_secret(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))
    functions = [
        node
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "main"
    ]
    if len(functions) != 1:
        raise AssertionError(f"fixture expected one main function in {path}")
    function = functions[0]

    def is_guard(statement: ast.AST) -> bool:
        return (
            isinstance(statement, ast.Expr)
            and isinstance(statement.value, ast.Call)
            and isinstance(statement.value.func, ast.Name)
            and statement.value.func.id == "reject_reserved_domain"
            and len(statement.value.args) == 2
            and isinstance(statement.value.args[0], ast.Name)
            and statement.value.args[0].id == "site_name"
            and isinstance(statement.value.args[1], ast.Constant)
            and statement.value.args[1].value == "ERPNEXT_SITE_NAME"
        )

    def contains_secret_call(statement: ast.AST) -> bool:
        return any(
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "read_secret"
            for node in ast.walk(statement)
        )

    guard_statements = [statement for statement in function.body if is_guard(statement)]
    secret_statements = [
        statement for statement in function.body if contains_secret_call(statement)
    ]
    if len(guard_statements) != 1 or not secret_statements:
        raise AssertionError(
            f"fixture expected one site guard and at least one secret call in {path}"
        )
    guard_statement = guard_statements[0]
    secret_statement = min(secret_statements, key=lambda statement: statement.lineno)
    if guard_statement.lineno >= secret_statement.lineno:
        raise AssertionError("fixture site guard does not precede its first secret")
    lines = source.splitlines(keepends=True)
    guard_index = guard_statement.lineno - 1
    secret_end_index = secret_statement.end_lineno - 1
    lines.pop(guard_index)
    if guard_index <= secret_end_index:
        secret_end_index -= 1
    lines.insert(
        secret_end_index + 1,
        '    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")\n',
    )
    path.write_text("".join(lines), encoding="utf-8")


def _move_rotation_compare_after_prepare(path: Path) -> None:
    source = path.read_text(encoding="utf-8")
    original = (
        '    if not secrets.compare_digest(deployment_password, expected_config["db_password"]):\n'
        '        fail(\n'
        '            "Selected bundle database credential does not match the current deployment secret"\n'
        '        )\n'
        '    deployment_password = None\n'
    )
    delayed = (
        '        if not secrets.compare_digest(deployment_password, expected_config["db_password"]):\n'
        '            fail(\n'
        '                "Selected bundle database credential does not match the current deployment secret"\n'
        '            )\n'
        '        deployment_password = None\n'
    )
    prepare = "        file_state = prepare_empty_file_trees(site, bundle_id)\n"
    if source.count(original) != 1 or source.count(prepare) != 1:
        raise AssertionError(
            "fixture expected one credential comparison and one prepare call"
        )
    source = source.replace(original, "", 1)
    source = source.replace(prepare, prepare + delayed, 1)
    path.write_text(source, encoding="utf-8")


def _replace_sql_validation_branch(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    branch_start = source.find("        elif rendered == expected_sql_validation:\n")
    branch_end = source.find("\n        else:\n", branch_start)
    if branch_start < 0 or branch_end < 0:
        raise AssertionError(f"fixture could not isolate SQL validation branch in {path}")
    branch = source[branch_start:branch_end]
    if branch.count(old) != 1:
        raise AssertionError(
            f"fixture SQL validation mutation expected one occurrence in {path}: {old!r}"
        )
    branch = branch.replace(old, new, 1)
    path.write_text(
        source[:branch_start] + branch + source[branch_end:],
        encoding="utf-8",
    )


def _move_bootstrap_chdir(path: Path, destination: str) -> None:
    source = path.read_text(encoding="utf-8")
    main_start = source.find("def main():\n")
    if main_start < 0:
        raise AssertionError(f"fixture could not find bootstrap main in {path}")
    prefix = source[:main_start]
    main_source = source[main_start:]
    chdir_line = "    os.chdir(SITES_ROOT)\n"
    if main_source.count(chdir_line) != 1:
        raise AssertionError(f"fixture expected one bootstrap chdir in {path}")
    main_source = main_source.replace(chdir_line, "", 1)
    if destination == "fresh-only":
        marker = "    import frappe\n"
        replacement = chdir_line + marker
    elif destination == "after-existing-verify":
        marker = "        verify_frappe_state(site_name, site_timezone)\n"
        replacement = marker + "        os.chdir(SITES_ROOT)\n"
    else:
        raise AssertionError(f"unsupported bootstrap chdir fixture: {destination}")
    if main_source.count(marker) != 1:
        raise AssertionError(
            f"fixture expected one bootstrap destination marker in {path}: {marker!r}"
        )
    main_source = main_source.replace(marker, replacement, 1)
    path.write_text(prefix + main_source, encoding="utf-8")


def _set_env(path: Path, key: str, value: str) -> None:
    source = path.read_text(encoding="utf-8")
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    if len(pattern.findall(source)) != 1:
        raise AssertionError(f"fixture mutation expected one active {key} in {path}")
    path.write_text(pattern.sub(f"{key}={value}", source, count=1), encoding="utf-8")


def _copy_fixture(source_root: Path, fixture_root: Path) -> None:
    shutil.copytree(source_root / "ERPNext", fixture_root / "ERPNext", symlinks=True)
    (fixture_root / "templates").mkdir()
    for service in EXPECTED_REQUIRED_SERVICES:
        shutil.copytree(
            source_root / "templates" / service,
            fixture_root / "templates" / service,
            symlinks=True,
        )


def _tree_fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    selected = [root / "ERPNext"] + [
        root / "templates" / service for service in EXPECTED_REQUIRED_SERVICES
    ]
    for selected_root in selected:
        for current_root, directory_names, file_names in os.walk(
            selected_root, topdown=True, followlinks=False
        ):
            directory_names.sort()
            file_names.sort()
            current = Path(current_root)
            for name in [*directory_names, *file_names]:
                path = current / name
                relative = path.relative_to(root).as_posix().encode("utf-8")
                metadata = path.lstat()
                digest.update(relative)
                digest.update(b"\0")
                digest.update(str(stat.S_IFMT(metadata.st_mode)).encode("ascii"))
                digest.update(b":")
                digest.update(oct(stat.S_IMODE(metadata.st_mode)).encode("ascii"))
                digest.update(b"\0")
                if stat.S_ISREG(metadata.st_mode):
                    digest.update(path.read_bytes())
                elif stat.S_ISLNK(metadata.st_mode):
                    digest.update(os.readlink(path).encode("utf-8"))
                digest.update(b"\0")
    return digest.hexdigest()


def _negative_cases() -> tuple[NegativeCase, ...]:
    app_compose = Path("ERPNext/docker-compose.app.yaml")

    def yaml_case(
        name: str,
        expected_error: str,
        relative_path: Path,
        mutation: Callable[[dict[str, Any]], None],
    ) -> NegativeCase:
        return NegativeCase(
            name,
            expected_error,
            lambda root: _write_yaml(root / relative_path, mutation),
        )

    cases: list[NegativeCase] = [
        yaml_case(
            "missing-flat-closure-member",
            "[closure]",
            app_compose,
            lambda document: document["x-required-services"].remove(
                "erpnext-scheduler"
            ),
        ),
        yaml_case(
            "assets-bootstrap-missing-from-closure",
            "[closure]",
            app_compose,
            lambda document: document["x-required-services"].remove(
                "erpnext-assets-bootstrap"
            ),
        ),
        yaml_case(
            "second-service-in-template",
            "[layout]",
            Path("templates/erpnext-backend/docker-compose.erpnext-backend.yaml"),
            lambda document: document["services"].update(
                {"rogue": copy.deepcopy(document["services"]["erpnext-backend"])}
            ),
        ),
        yaml_case(
            "vendor-entrypoint-override",
            "[entrypoint]",
            Path("templates/erpnext-backend/docker-compose.erpnext-backend.yaml"),
            lambda document: document["services"]["erpnext-backend"].update(
                {"entrypoint": ["/bin/false"]}
            ),
        ),
        yaml_case(
            "second-vendor-assets-entrypoint-owner",
            "[entrypoint]",
            Path("templates/erpnext-backend/docker-compose.erpnext-backend.yaml"),
            lambda document: document["services"]["erpnext-backend"].update(
                {"entrypoint": ["/usr/local/bin/entrypoint.sh"]}
            ),
        ),
        yaml_case(
            "assets-bootstrap-vendor-entrypoint-lost",
            "[entrypoint]",
            Path(
                "templates/erpnext-assets-bootstrap/"
                "docker-compose.erpnext-assets-bootstrap.yaml"
            ),
            lambda document: document["services"]["erpnext-assets-bootstrap"].update(
                {"entrypoint": ["/usr/local/bin/saervices-erpnext-runtime-entrypoint.sh"]}
            ),
        ),
        yaml_case(
            "wrong-bootstrap-condition",
            "[dependency]",
            Path(
                "templates/erpnext-sso-bootstrap/docker-compose.erpnext-sso-bootstrap.yaml"
            ),
            lambda document: document["services"]["erpnext-sso-bootstrap"][
                "depends_on"
            ]["erpnext-migrator"].update({"condition": "service_healthy"}),
        ),
        yaml_case(
            "dependency-cycle",
            "[dependency]",
            Path("templates/erpnext-configurator/docker-compose.erpnext-configurator.yaml"),
            lambda document: document["services"]["erpnext-configurator"][
                "depends_on"
            ].update(
                {
                    "erpnext-sso-bootstrap": {
                        "condition": "service_completed_successfully"
                    }
                }
            ),
        ),
        yaml_case(
            "admin-secret-in-long-runner",
            "[secrets]",
            Path("templates/erpnext-backend/docker-compose.erpnext-backend.yaml"),
            lambda document: document["services"]["erpnext-backend"].update(
                {"secrets": ["ERPNEXT_ADMIN_PASSWORD"]}
            ),
        ),
        yaml_case(
            "redis-secret-removed-from-configurator",
            "[secrets]",
            Path("templates/erpnext-configurator/docker-compose.erpnext-configurator.yaml"),
            lambda document: document["services"]["erpnext-configurator"][
                "secrets"
            ].remove("ERPNEXT_REDIS_QUEUE_PASSWORD"),
        ),
        yaml_case(
            "forward-auth-activated",
            "[oidc]",
            app_compose,
            lambda document: document["services"]["app"]["labels"].append(
                "traefik.http.routers.erpnext.middlewares=authentik-proxy@file"
            ),
        ),
        yaml_case(
            "bare-backend-hostname",
            "[hostnames]",
            app_compose,
            lambda document: document["services"]["app"]["environment"].update(
                {"BACKEND": "erpnext-backend:8000"}
            ),
        ),
        yaml_case(
            "missing-sites-volume",
            "[storage]",
            Path("templates/erpnext-backend/docker-compose.erpnext-backend.yaml"),
            lambda document: document["services"]["erpnext-backend"]["volumes"].pop(
                0
            ),
        ),
        yaml_case(
            "frontend-gains-sites-volume",
            "[frontend]",
            app_compose,
            lambda document: document["services"]["app"]["volumes"].append(
                "erpnext_sites:/home/frappe/frappe-bench/sites:rw"
            ),
        ),
        yaml_case(
            "frontend-sites-oci-mask-removed",
            "[frontend]",
            app_compose,
            lambda document: document["services"]["app"]["tmpfs"].remove(
                "/home/frappe/frappe-bench/sites:rw,noexec,nosuid,nodev,size=1m,"
                "uid=1000,gid=1000,mode=0700"
            ),
        ),
        yaml_case(
            "frontend-logs-oci-mask-removed",
            "[frontend]",
            app_compose,
            lambda document: document["services"]["app"]["tmpfs"].remove(
                "/home/frappe/frappe-bench/logs:rw,noexec,nosuid,nodev,size=4m,"
                "uid=1000,gid=1000,mode=0700"
            ),
        ),
        yaml_case(
            "assets-bootstrap-logs-oci-mask-removed",
            "[storage]",
            Path(
                "templates/erpnext-assets-bootstrap/"
                "docker-compose.erpnext-assets-bootstrap.yaml"
            ),
            lambda document: document["services"]["erpnext-assets-bootstrap"][
                "tmpfs"
            ].remove(
                "/home/frappe/frappe-bench/logs:rw,noexec,nosuid,nodev,size=4m,"
                "uid=${APP_UID:-1000},gid=${APP_GID:-1000},mode=0700"
            ),
        ),
        yaml_case(
            "configurator-logs-oci-mask-removed",
            "[storage]",
            Path(
                "templates/erpnext-configurator/"
                "docker-compose.erpnext-configurator.yaml"
            ),
            lambda document: document["services"]["erpnext-configurator"][
                "tmpfs"
            ].remove(
                "/home/frappe/frappe-bench/logs:rw,noexec,nosuid,nodev,size=4m,"
                "uid=${APP_UID:-1000},gid=${APP_GID:-1000},mode=0700"
            ),
        ),
        yaml_case(
            "scheduler-config-lock-tmpfs-removed",
            "[scheduler]",
            Path("templates/erpnext-scheduler/docker-compose.erpnext-scheduler.yaml"),
            lambda document: document["services"]["erpnext-scheduler"][
                "tmpfs"
            ].remove(
                "/home/frappe/frappe-bench/config:rw,noexec,nosuid,nodev,size=1m,"
                "uid=${APP_UID:-1000},gid=${APP_GID:-1000},mode=0700"
            ),
        ),
        yaml_case(
            "scheduler-private-pids-initialization-removed",
            "[scheduler]",
            Path("templates/erpnext-scheduler/docker-compose.erpnext-scheduler.yaml"),
            lambda document: document["services"]["erpnext-scheduler"][
                "command"
            ].__setitem__(2, "set -eu; umask 077; exec bench schedule"),
        ),
        yaml_case(
            "frontend-gains-backend-network",
            "[networks]",
            app_compose,
            lambda document: document["services"]["app"]["networks"].append(
                "backend"
            ),
        ),
        yaml_case(
            "redis-leaks-onto-application-network",
            "[networks]",
            Path(
                "templates/erpnext-redis-cache/"
                "docker-compose.erpnext-redis-cache.yaml"
            ),
            lambda document: document["services"]["erpnext-redis-cache"][
                "networks"
            ].append("erpnext_app"),
        ),
        yaml_case(
            "backend-loses-static-file-application",
            "[frontend]",
            Path("templates/erpnext-backend/docker-compose.erpnext-backend.yaml"),
            lambda document: document["services"]["erpnext-backend"]["command"].__setitem__(
                -1, "frappe.app:application"
            ),
        ),
        yaml_case(
            "worker-pool-contract-lost",
            "[workers]",
            Path(
                "templates/erpnext-worker-short/"
                "docker-compose.erpnext-worker-short.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-short"][
                "command"
            ].__setitem__(
                2,
                document["services"]["erpnext-worker-short"]["command"][2].replace(
                    "worker-pool", "worker", 1
                ),
            ),
        ),
        yaml_case(
            "worker-short-config-lock-tmpfs-removed",
            "[workers]",
            Path(
                "templates/erpnext-worker-short/"
                "docker-compose.erpnext-worker-short.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-short"][
                "tmpfs"
            ].remove(PRIVATE_FRAPPE_CONFIG_TMPFS),
        ),
        yaml_case(
            "worker-long-config-lock-tmpfs-removed",
            "[workers]",
            Path(
                "templates/erpnext-worker-long/"
                "docker-compose.erpnext-worker-long.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-long"][
                "tmpfs"
            ].remove(PRIVATE_FRAPPE_CONFIG_TMPFS),
        ),
        yaml_case(
            "worker-short-private-pids-prep-removed",
            "[workers]",
            Path(
                "templates/erpnext-worker-short/"
                "docker-compose.erpnext-worker-short.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-short"][
                "command"
            ].__setitem__(
                2,
                document["services"]["erpnext-worker-short"]["command"][2].replace(
                    "mkdir -p /home/frappe/frappe-bench/config/pids; "
                    "chmod 0700 /home/frappe/frappe-bench/config/pids; ",
                    "",
                    1,
                ),
            ),
        ),
        yaml_case(
            "worker-long-private-pids-prep-mode-drift",
            "[workers]",
            Path(
                "templates/erpnext-worker-long/"
                "docker-compose.erpnext-worker-long.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-long"][
                "command"
            ].__setitem__(
                2,
                document["services"]["erpnext-worker-long"]["command"][2].replace(
                    "chmod 0700 /home/frappe/frappe-bench/config/pids",
                    "chmod 0770 /home/frappe/frappe-bench/config/pids",
                    1,
                ),
            ),
        ),
        yaml_case(
            "worker-short-direct-worker-pool-fallback",
            "[workers]",
            Path(
                "templates/erpnext-worker-short/"
                "docker-compose.erpnext-worker-short.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-short"].update(
                {
                    "command": [
                        "bench",
                        "worker-pool",
                        "--queue",
                        "short,default",
                        "--num-workers",
                        "${ERPNEXT_WORKER_SHORT_PROCESSES:-1}",
                    ]
                }
            ),
        ),
        yaml_case(
            "worker-long-direct-worker-pool-fallback",
            "[workers]",
            Path(
                "templates/erpnext-worker-long/"
                "docker-compose.erpnext-worker-long.yaml"
            ),
            lambda document: document["services"]["erpnext-worker-long"].update(
                {
                    "command": [
                        "bench",
                        "worker-pool",
                        "--queue",
                        "long,default,short",
                        "--num-workers",
                        "${ERPNEXT_WORKER_LONG_PROCESSES:-1}",
                    ]
                }
            ),
        ),
        yaml_case(
            "backend-on-frontend-network",
            "[networks]",
            Path("templates/erpnext-worker-long/docker-compose.erpnext-worker-long.yaml"),
            lambda document: document["services"]["erpnext-worker-long"][
                "networks"
            ].append("frontend"),
        ),
        yaml_case(
            "direct-port-published",
            "[networks]",
            Path("templates/erpnext-websocket/docker-compose.erpnext-websocket.yaml"),
            lambda document: document["services"]["erpnext-websocket"].update(
                {"ports": ["9000:9000"]}
            ),
        ),
        yaml_case(
            "generic-maintenance-backup-path",
            "[maintenance]",
            Path(
                "templates/erpnext-site-maintenance/docker-compose.erpnext-site-maintenance.yaml"
            ),
            lambda document: document["services"]["erpnext-site-maintenance"][
                "volumes"
            ].__setitem__(2, "./backup:/backup:rw"),
        ),
        yaml_case(
            "restore-application-secret-mount-removed",
            "[maintenance] restore override",
            Path(
                "templates/erpnext-site-maintenance/"
                "docker-compose.erpnext-site-maintenance.restore.yaml.example"
            ),
            lambda document: document["services"]["erpnext-site-maintenance"][
                "secrets"
            ].remove("MARIADB_PASSWORD"),
        ),
    ]
    cases.extend(
        [
            NegativeCase(
                "configurator-site-domain-guard-removed",
                "[site-domain] configurator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-configurator/scripts/erpnext-configurator.py",
                    '    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")',
                    "    pass  # reserved site-domain guard removed",
                ),
            ),
            NegativeCase(
                "configurator-site-domain-guard-after-secret",
                "[site-domain] configurator",
                lambda root: _move_site_guard_after_first_secret(
                    root
                    / "templates/erpnext-configurator/scripts/erpnext-configurator.py"
                ),
            ),
            NegativeCase(
                "site-bootstrap-site-domain-guard-removed",
                "[site-domain] site-bootstrap",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")',
                    "    pass  # reserved site-domain guard removed",
                ),
            ),
            NegativeCase(
                "site-bootstrap-site-domain-guard-after-secret",
                "[site-domain] site-bootstrap",
                lambda root: _move_site_guard_after_first_secret(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py"
                ),
            ),
            NegativeCase(
                "sso-site-domain-guard-removed",
                "[site-domain] sso-bootstrap",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py",
                    '    reject_reserved_domain(site_name, "ERPNEXT_SITE_NAME")',
                    "    pass  # reserved site-domain guard removed",
                ),
            ),
            NegativeCase(
                "sso-site-domain-guard-after-secret",
                "[site-domain] sso-bootstrap",
                lambda root: _move_site_guard_after_first_secret(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py"
                ),
            ),
            NegativeCase(
                "site-bootstrap-sites-cwd-removed",
                "[bootstrap] existing-site CWD",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "    os.chdir(SITES_ROOT)",
                    "    pass  # sites-root CWD removed",
                ),
            ),
            NegativeCase(
                "site-bootstrap-sites-cwd-fresh-only",
                "[bootstrap] existing-site CWD",
                lambda root: _move_bootstrap_chdir(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "fresh-only",
                ),
            ),
            NegativeCase(
                "site-bootstrap-sites-cwd-after-existing-verify",
                "[bootstrap] existing-site CWD",
                lambda root: _move_bootstrap_chdir(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "after-existing-verify",
                ),
            ),
            NegativeCase(
                "site-bootstrap-bench-root-cwd-regression",
                "[bootstrap] existing-site CWD",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "    os.chdir(SITES_ROOT)",
                    "    os.chdir(SITES_ROOT.parent)  # BENCH_ROOT regression",
                ),
            ),
            NegativeCase(
                "site-bootstrap-pdf-generator-repair-removed",
                "[bootstrap] Print Settings PDF generator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '            frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")',
                    "            pass  # PDF generator drift repair removed",
                ),
            ),
            NegativeCase(
                "site-bootstrap-pdf-generator-wrong-singleton",
                "[bootstrap] Print Settings PDF generator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    'frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")',
                    'frappe.db.set_single_value("System Settings", "pdf_generator", "chrome")',
                ),
            ),
            NegativeCase(
                "site-bootstrap-pdf-generator-wrong-field",
                "[bootstrap] Print Settings PDF generator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    'frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")',
                    'frappe.db.set_single_value("Print Settings", "print_format", "chrome")',
                ),
            ),
            NegativeCase(
                "site-bootstrap-pdf-generator-wrong-value",
                "[bootstrap] Print Settings PDF generator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    'frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")',
                    'frappe.db.set_single_value("Print Settings", "pdf_generator", "chromium")',
                ),
            ),
            NegativeCase(
                "site-bootstrap-pdf-generator-commit-removed",
                "[bootstrap] Print Settings PDF generator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '            frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")\n'
                    "            frappe.db.commit()",
                    '            frappe.db.set_single_value("Print Settings", "pdf_generator", "chrome")\n'
                    "            pass  # PDF generator repair commit removed",
                ),
            ),
            NegativeCase(
                "site-bootstrap-pdf-generator-postcondition-removed",
                "[bootstrap] Print Settings PDF generator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '        if frappe.db.get_single_value("Print Settings", "pdf_generator") != "chrome":\n'
                    '            fail("ERPNext Print Settings PDF generator postcondition failed")',
                    "        pass  # PDF generator postcondition removed",
                ),
            ),
            NegativeCase(
                "site-bootstrap-new-site-init-removed",
                "[bootstrap]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "        frappe.init(\n"
                    "            site_name,\n"
                    "            sites_path=str(SITES_ROOT),\n"
                    "            new_site=True,\n"
                    "        )\n",
                    "",
                ),
            ),
            NegativeCase(
                "site-bootstrap-new-site-flag-false",
                "[bootstrap]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "            new_site=True,",
                    "            new_site=False,",
                ),
            ),
            NegativeCase(
                "site-bootstrap-existing-log-guard-removed",
                "[bootstrap] existing-site verification",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '        set_log_level("ERROR")\n'
                    "        frappe.connect()",
                    "        frappe.connect()",
                ),
            ),
            NegativeCase(
                "site-bootstrap-existing-log-level-warning",
                "[bootstrap] existing-site verification",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '        set_log_level("ERROR")\n'
                    "        frappe.connect()",
                    '        set_log_level("WARNING")\n'
                    "        frappe.connect()",
                ),
            ),
            NegativeCase(
                "site-bootstrap-existing-log-guard-after-connect",
                "[bootstrap] existing-site verification",
                lambda root: _move_logger_guard_after_call(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "verify_frappe_state",
                    "connect",
                ),
            ),
            NegativeCase(
                "site-bootstrap-fresh-log-guard-removed",
                "[bootstrap] fresh-site creation",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '        set_log_level("ERROR")\n'
                    "        _new_site(",
                    "        _new_site(",
                ),
            ),
            NegativeCase(
                "site-bootstrap-fresh-log-level-warning",
                "[bootstrap] fresh-site creation",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    '        set_log_level("ERROR")\n'
                    "        _new_site(",
                    '        set_log_level("WARNING")\n'
                    "        _new_site(",
                ),
            ),
            NegativeCase(
                "site-bootstrap-fresh-log-guard-after-new-site",
                "[bootstrap] fresh-site creation",
                lambda root: _move_logger_guard_after_call(
                    root
                    / "templates/erpnext-site-bootstrap/scripts/erpnext-site-bootstrap.py",
                    "main",
                    "_new_site",
                ),
            ),
            NegativeCase(
                "wrong-provider-display-name",
                "[oidc]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py",
                    'PROVIDER_NAME = "Authentik"',
                    'PROVIDER_NAME = "Other"',
                ),
            ),
            NegativeCase(
                "wrong-provider-key",
                "[oidc]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py",
                    'PROVIDER_KEY = "authentik"',
                    'PROVIDER_KEY = "other"',
                ),
            ),
            NegativeCase(
                "reduced-oidc-scope",
                "[oidc]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py",
                    '"scope": "openid email profile"',
                    '"scope": "openid"',
                ),
            ),
            NegativeCase(
                "non-sub-user-id",
                "[oidc]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py",
                    '"user_id_property": "sub"',
                    '"user_id_property": "email"',
                ),
            ),
            NegativeCase(
                "signups-allow",
                "[oidc]",
                lambda root: _set_env(
                    _source_env_path(root), "ERPNEXT_SSO_SIGNUPS", "Allow"
                ),
            ),
            NegativeCase(
                "frappe-patch-tag",
                "[versions]",
                lambda root: _set_env(
                    _source_env_path(root), "APP_IMAGE", "frappe/erpnext:v16.31.1"
                ),
            ),
            NegativeCase(
                "redis-old-major",
                "[versions]",
                lambda root: _set_env(
                    root / "templates/erpnext-redis-cache/.env",
                    "ERPNEXT_REDIS_CACHE_IMAGE",
                    "docker.io/library/redis:7-alpine",
                ),
            ),
            NegativeCase(
                "mariadb-exception-lost",
                "[versions]",
                lambda root: _set_env(
                    _source_env_path(root), "MARIADB_IMAGE", "mariadb:12"
                ),
            ),
            NegativeCase(
                "mariadb-durability-not-one-one",
                "[database]",
                lambda root: _set_env(
                    _source_env_path(root), "MARIADB_SYNC_BINLOG", "0"
                ),
            ),
            NegativeCase(
                "mariadb-root-binlog-expiry-drift",
                "[database] ERPNext root must retain seven-day",
                lambda root: _set_env(
                    _source_env_path(root),
                    "MARIADB_BINLOG_EXPIRE_LOGS_SECONDS",
                    "86400",
                ),
            ),
            NegativeCase(
                "mariadb-root-purge-threshold-drift",
                "[database] ERPNext root must retain seven-day",
                lambda root: _set_env(
                    _source_env_path(root),
                    "MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE",
                    "1",
                ),
            ),
            NegativeCase(
                "mariadb-template-binlog-expiry-drift",
                "[database] MariaDB template defaults",
                lambda root: _set_env(
                    root / "templates/mariadb/.env",
                    "MARIADB_BINLOG_EXPIRE_LOGS_SECONDS",
                    "86400",
                ),
            ),
            NegativeCase(
                "mariadb-compose-purge-argument-removed",
                "[database] MariaDB Compose",
                lambda root: _write_yaml(
                    root / "templates/mariadb/docker-compose.mariadb.yaml",
                    lambda document: document["services"]["mariadb"]["command"].remove(
                        "--slave-connections-needed-for-purge="
                        "${MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE:-0}"
                    ),
                ),
            ),
            NegativeCase(
                "mariadb-binlog-expiry-lower-bound-removed",
                "[database] MariaDB binlog policy guard",
                lambda root: _replace_once(
                    root / "templates/mariadb/dockerfiles/entrypoint.mariadb.sh",
                    'if [ "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -lt 3600 ] || '
                    '[ "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -gt 31536000 ]; then',
                    'if [ "$MARIADB_BINLOG_EXPIRE_LOGS_SECONDS" -gt 31536000 ]; then',
                ),
            ),
            NegativeCase(
                "mariadb-purge-threshold-overflow-guard-weakened",
                "[database] MariaDB binlog policy guard",
                lambda root: _replace_once(
                    root / "templates/mariadb/dockerfiles/entrypoint.mariadb.sh",
                    'if [ "$MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE" -gt 4294967295 ]; then',
                    'if [ "$MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE" -gt 9999999999 ]; then',
                ),
            ),
            NegativeCase(
                "authentik-reserved-domain-guard-removed",
                "[oidc]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-sso-bootstrap/scripts/erpnext-sso-bootstrap.py",
                    '    reject_reserved_domain(authentik_domain, "ERPNEXT_AUTHENTIK_DOMAIN")',
                    "    pass  # reserved-domain guard removed by negative fixture",
                ),
            ),
            NegativeCase(
                "restore-bundle-id-key-removed",
                "[maintenance]",
                lambda root: _replace_once(
                    root / "templates/erpnext-site-maintenance/.env",
                    "ERPNEXT_SITE_RESTORE_BUNDLE_ID=",
                    "ERPNEXT_SITE_RESTORE_BUNDLE_REMOVED=",
                ),
            ),
            NegativeCase(
                "restore-dry-run-disabled",
                "[maintenance]",
                lambda root: _set_env(
                    root / "templates/erpnext-site-maintenance/.env",
                    "ERPNEXT_SITE_RESTORE_DRY_RUN",
                    "false",
                ),
            ),
            NegativeCase(
                "backup-schedule-drift",
                "[maintenance]",
                lambda root: _set_env(
                    root / "templates/erpnext-site-maintenance/.env",
                    "ERPNEXT_SITE_BACKUP_SCHEDULE",
                    "17 * * * *",
                ),
            ),
            NegativeCase(
                "backup-max-age-too-short",
                "[maintenance]",
                lambda root: _set_env(
                    root / "templates/erpnext-site-maintenance/.env",
                    "ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS",
                    "7200",
                ),
            ),
            NegativeCase(
                "schedule-semantic-preflight-removed",
                "[maintenance]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-maintenance.sh",
                    'supercronic -test "$RUNTIME_CRON"',
                    'true # removed Supercronic schedule preflight',
                ),
            ),
            NegativeCase(
                "schedule-backup-call-made-conditional",
                "[maintenance] Supercronic must validate",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-maintenance.sh",
                    "  run_backup\n"
                    "  log_ok 'Initial bundle is healthy; starting Supercronic with the locked runtime schedule.'",
                    "  run_backup || log_fatal 'fixture swallowed backup failure'\n"
                    "  log_ok 'Initial bundle is healthy; starting Supercronic with the locked runtime schedule.'",
                ),
            ),
            NegativeCase(
                "archive-leading-dot-prefix-rejected",
                "[maintenance] file-archive validator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'if len(raw_parts) < 4 or raw_parts[0] != ".":',
                    'if len(raw_parts) < 4 or raw_parts[0] == ".":',
                ),
            ),
            NegativeCase(
                "archive-traversal-component-guard-removed",
                "[maintenance] file-archive validator",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'if any(part in ("", ".", "..") for part in raw_parts[1:]):',
                    'if any(part in ("", ".", "..") for part in ()):',
                ),
            ),
            NegativeCase(
                "vendor-encrypted-backups-accepted",
                "[maintenance]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-maintenance.sh",
                    '    case "$name" in\n',
                    '    case "$name" in\n'
                    '      *-enc.database.sql.gz)\n'
                    '        [[ -z "$database" ]] || return 1\n'
                    '        database="$name"\n'
                    '        database_prefix="${name%-enc.database.sql.gz}"\n'
                    '        ;;\n'
                    '      *-enc.files.tgz)\n'
                    '        [[ -z "$public_files" ]] || return 1\n'
                    '        public_files="$name"\n'
                    '        public_prefix="${name%-enc.files.tgz}"\n'
                    '        ;;\n'
                    '      *-enc.private-files.tgz)\n'
                    '        [[ -z "$private_files" ]] || return 1\n'
                    '        private_files="$name"\n'
                    '        private_prefix="${name%-enc.private-files.tgz}"\n'
                    '        ;;\n'
                    '      *-enc.site_config_backup.json)\n'
                    '        [[ -z "$site_config" ]] || return 1\n'
                    '        site_config="$name"\n'
                    '        config_prefix="${name%-enc.site_config_backup.json}"\n'
                    '        ;;\n',
                ),
            ),
            NegativeCase(
                "encrypted-backup-boundary-undocumented",
                "[maintenance]",
                lambda root: _replace_once(
                    root / "ERPNext/README.md",
                    "The strict publisher rejects vendor `*-enc.*` outputs",
                    "The strict publisher rejects unsupported vendor outputs",
                ),
            ),
            NegativeCase(
                "online-backup-boundary-undocumented",
                "[maintenance]",
                lambda root: _replace_once(
                    root / "templates/erpnext-site-maintenance/README.md",
                    "does not clæim point-in-time or cræsh consistency",
                    "documents the online backup consistency model",
                ),
            ),
            NegativeCase(
                "root-restore-restarts-dependencies",
                "[maintenance]",
                lambda root: _replace_count(
                    root / "ERPNext/README.md",
                    "run --no-deps --rm --pull never erpnext-site-maintenance",
                    "run --rm --pull never erpnext-site-maintenance",
                    1,
                ),
            ),
            NegativeCase(
                "template-restore-restarts-dependencies",
                "[maintenance]",
                lambda root: _replace_count(
                    root / "templates/erpnext-site-maintenance/README.md",
                    "run --no-deps --pull never --rm erpnext-site-maintenance",
                    "run --pull never --rm erpnext-site-maintenance",
                    2,
                ),
            ),
            NegativeCase(
                "vendor-preflight-bench-root-cwd-regression",
                "[maintenance] vendor_preflight",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "    os.chdir(SITES_ROOT)\n"
                    "    try:\n"
                    "        import frappe\n"
                    "        from frappe.installer",
                    "    os.chdir(BENCH_ROOT)\n"
                    "    try:\n"
                    "        import frappe\n"
                    "        from frappe.installer",
                ),
            ),
            NegativeCase(
                "restore-bundle-bench-root-cwd-regression",
                "[maintenance] restore_bundle",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "    os.chdir(SITES_ROOT)\n"
                    "    try:\n"
                    "        file_state = prepare_empty_file_trees",
                    "    os.chdir(BENCH_ROOT)\n"
                    "    try:\n"
                    "        file_state = prepare_empty_file_trees",
                ),
            ),
            NegativeCase(
                "restore-log-guard-removed",
                "[maintenance] restore_bundle must import set_log_level",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '            set_log_level("ERROR")\n'
                    '            with filelock("site_restore", timeout=1):',
                    '            with filelock("site_restore", timeout=1):',
                ),
            ),
            NegativeCase(
                "restore-log-level-warning",
                "[maintenance] restore_bundle must import set_log_level",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '            set_log_level("ERROR")\n'
                    '            with filelock("site_restore", timeout=1):',
                    '            set_log_level("WARNING")\n'
                    '            with filelock("site_restore", timeout=1):',
                ),
            ),
            NegativeCase(
                "restore-log-guard-after-vendor-call",
                "[maintenance] restore_bundle must import set_log_level",
                lambda root: _move_logger_guard_after_call(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "restore_bundle",
                    "_restore",
                ),
            ),
            NegativeCase(
                "restore-same-filesystem-guard-inverted",
                "[maintenance]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "directory_identity(path)[0] != site_device",
                    "directory_identity(path)[0] == site_device",
                ),
            ),
            NegativeCase(
                "restore-site-config-rollback-call-removed",
                "[maintenance] injected vendor failure must restore original site_config",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "                    rollback_site_config(file_state)",
                    "                    pass  # site_config rollback removed",
                ),
            ),
            NegativeCase(
                "restore-site-config-inode-preservation-lost",
                "[maintenance] injected vendor failure must restore original site_config",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "    os.replace(original, target)",
                    "    target.write_bytes(original.read_bytes())\n"
                    "    os.unlink(original)",
                ),
            ),
            NegativeCase(
                "restore-reverse-rollback-order-lost",
                "[maintenance]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'for prefix in ("private", "public"):',
                    'for prefix in ("public", "private"):',
                ),
            ),
            NegativeCase(
                "restore-exact-inventory-verification-removed",
                "[maintenance]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "verify_restored_file_trees(file_state, public_archive, private_archive)",
                    "verify_restored_file_trees = None",
                ),
            ),
            NegativeCase(
                "restore-unicode-path-identity-lost",
                "[maintenance]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "relative_name = relative.as_posix()",
                    "relative_name = str(relative)",
                ),
            ),
            NegativeCase(
                "restore-application-secret-cli-argument-removed",
                "[maintenance] credential rotation CLI",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '            command.add_argument("--application-secret-file", required=True)',
                    "            pass  # application-secret CLI guard removed",
                ),
            ),
            NegativeCase(
                "restore-application-secret-shell-forwarding-removed",
                "[maintenance] credential rotation shell",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-maintenance.sh",
                    '    --application-secret-file "$APPLICATION_SECRET"',
                    "    # application-secret forwarding removed",
                ),
            ),
            NegativeCase(
                "restore-credential-compare-removed",
                "[maintenance] credential rotation guard",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '    if not secrets.compare_digest(deployment_password, expected_config["db_password"]):',
                    "    if False:  # credential comparison removed",
                ),
            ),
            NegativeCase(
                "restore-credential-compare-after-prepare",
                "[maintenance] credential rotation guard",
                lambda root: _move_rotation_compare_after_prepare(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py"
                ),
            ),
            NegativeCase(
                "restore-option-directory-mode-drift",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "                os.mkdir(candidate, 0o700, dir_fd=root_descriptor)",
                    "                os.mkdir(candidate, 0o750, dir_fd=root_descriptor)",
                ),
            ),
            NegativeCase(
                "restore-option-file-mode-drift",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "        os.fchmod(file_descriptor, 0o600)",
                    "        os.fchmod(file_descriptor, 0o640)",
                ),
            ),
            NegativeCase(
                "restore-option-file-o-excl-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "        flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | getattr(os, \"O_CLOEXEC\", 0)",
                    "        flags = os.O_RDWR | os.O_CREAT | getattr(os, \"O_CLOEXEC\", 0)",
                ),
            ),
            NegativeCase(
                "restore-option-file-o-nofollow-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '        if hasattr(os, "O_NOFOLLOW"):\n'
                    "            flags |= os.O_NOFOLLOW\n"
                    "        file_descriptor = os.open(",
                    "        file_descriptor = os.open(",
                ),
            ),
            NegativeCase(
                "restore-option-quoted-escaping-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '    escaped = value.replace("\\\\", "\\\\\\\\").replace(\'"\', \'\\\\"\')',
                    "    escaped = value  # quoted escaping removed",
                ),
            ),
            NegativeCase(
                "restore-option-argument-no-longer-first",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "        injected_arguments = [option_argument, *arguments]",
                    "        injected_arguments = [*arguments, option_argument]",
                ),
            ),
            NegativeCase(
                "restore-vendor-topology-port-loosened",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '        or expected_call["port"] != 3306',
                    "        or False  # fixed MariaDB port guard removed",
                ),
            ),
            NegativeCase(
                "restore-vendor-command-multi-use-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '        if bridge_state["uses"] != 0:',
                    '        if bridge_state["uses"] < 0:',
                ),
            ),
            NegativeCase(
                "restore-vendor-pre-spawn-order-guard-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '                bridge_state["file_probe_uses"] != 1\n'
                    '                or bridge_state["sql_validation_uses"] != 1\n'
                    '                or bridge_state["uses"] != 1',
                    '                False  # file-probe ordering guard removed\n'
                    '                or bridge_state["sql_validation_uses"] != 1\n'
                    '                or bridge_state["uses"] != 1',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-missing-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_count(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'or bridge_state["sql_validation_uses"] != 1',
                    "or False  # missing SQL validation accepted",
                    2,
                ),
            ),
            NegativeCase(
                "restore-sql-validation-duplicate-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_sql_validation_branch(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'bridge_state["sql_validation_uses"] != 0',
                    'bridge_state["sql_validation_uses"] < 0',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-wrong-path",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path}"',
                    'expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path.parent}"',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-wrong-binary",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path}"',
                    'expected_sql_validation = f"/bin/zgrep -m1 __Auth {expected_database_path}"',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-wrong-pattern",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path}"',
                    'expected_sql_validation = f"/usr/bin/zgrep -m1 __User {expected_database_path}"',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-flags-loosened",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_sql_validation_branch(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "or verbose is not False",
                    "or verbose is not None",
                ),
            ),
            NegativeCase(
                "restore-sql-validation-before-file-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_sql_validation_branch(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'bridge_state["file_probe_uses"] != 1',
                    'bridge_state["file_probe_uses"] < 0',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-after-get-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_sql_validation_branch(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'bridge_state["uses"] != 0',
                    'bridge_state["uses"] < 0',
                ),
            ),
            NegativeCase(
                "restore-sql-validation-after-spawn-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_sql_validation_branch(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    'bridge_state["sql_validation_uses"] != 0\n'
                    '                or bridge_state["uses"] != 0\n'
                    '                or bridge_state["spawn_uses"] != 0',
                    "False  # post-validation lifecycle guards removed",
                ),
            ),
            NegativeCase(
                "restore-arbitrary-child-process-accepted",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '                fail("Frappe requested an unexpected restore child process")',
                    "                pass  # arbitrary child process accepted",
                ),
            ),
            NegativeCase(
                "restore-vendor-raw-secret-guard-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "        if any(\n"
                    "            secret in rendered or shlex.quote(secret) in rendered\n"
                    "            for secret in forbidden_secrets\n"
                    "        ):\n"
                    '            fail("Frappe requested a secret-bearing child process")',
                    "        if False:  # raw-secret command guard removed\n"
                    '            fail("Frappe requested a secret-bearing child process")',
                ),
            ),
            NegativeCase(
                "restore-vendor-ddl-suppression-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "        if query_type in exact_ddl_types:",
                    "        if False and query_type in exact_ddl_types:",
                ),
            ),
            NegativeCase(
                "restore-vendor-non-ddl-delegation-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "        return original_log_query(\n"
                    "            self,\n"
                    "            mogrified_query,\n"
                    "            query_type,\n"
                    "            debug,\n"
                    "            unmogrified_query,\n"
                    "        )",
                    "        return None  # non-DDL delegation removed",
                ),
            ),
            NegativeCase(
                "restore-option-cleanup-digest-guard-removed",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    '        if digest != state["digest"] or consumed != state["file_identity"][2]:',
                    '        if consumed != state["file_identity"][2]:',
                ),
            ),
            NegativeCase(
                "restore-hook-original-not-restored",
                "[maintenance] MariaDB restore bridge",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py",
                    "                setattr(owner, attribute, original)",
                    "                pass  # original hook restoration removed",
                ),
            ),
            NegativeCase(
                "runtime-wrapper-mutates-assets",
                "[entrypoint]",
                lambda root: _replace_once(
                    root / "ERPNext/scripts/erpnext-runtime-entrypoint.sh",
                    '  exec "$@"',
                    '  rm -f -- "${assets_path}"\n  exec "$@"',
                ),
            ),
            NegativeCase(
                "frontend-forwards-untrusted-host",
                "[frontend]",
                lambda root: _replace_count(
                    root / "ERPNext/config/nginx-frappe.conf.template",
                    "proxy_set_header Host ${FRAPPE_SITE_NAME_HEADER};",
                    "proxy_set_header Host $host;",
                    3,
                ),
            ),
            NegativeCase(
                "frontend-exposes-nginx-version",
                "[frontend]",
                lambda root: _replace_once(
                    root / "ERPNext/config/nginx-frappe.conf.template",
                    "\tserver_tokens off;",
                    "\tserver_tokens on;",
                ),
            ),
            NegativeCase(
                "frontend-preserves-attacker-xff-chain",
                "[frontend]",
                lambda root: _replace_count(
                    root / "ERPNext/config/nginx-frappe.conf.template",
                    "proxy_set_header X-Forwarded-For $remote_addr;",
                    "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
                    3,
                ),
            ),
            NegativeCase(
                "frontend-private-dangerous-files-bypass-attachment",
                "[frontend]",
                lambda root: _replace_once(
                    root / "ERPNext/config/nginx-frappe.conf.template",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {",
                    "location ~* ^/files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {",
                ),
            ),
            NegativeCase(
                "frontend-xhtml-dangerous-file-gap",
                "[frontend]",
                lambda root: _replace_once(
                    root / "ERPNext/config/nginx-frappe.conf.template",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|svg|svgz|xml)$ {",
                ),
            ),
            NegativeCase(
                "frontend-svgz-dangerous-file-gap",
                "[frontend]",
                lambda root: _replace_once(
                    root / "ERPNext/config/nginx-frappe.conf.template",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|xml)$ {",
                ),
            ),
            NegativeCase(
                "frontend-wrapper-xhtml-marker-gap",
                "[entrypoint]",
                lambda root: _replace_once(
                    root / "ERPNext/scripts/erpnext-frontend.sh",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|svg|svgz|xml)$ {",
                ),
            ),
            NegativeCase(
                "frontend-wrapper-svgz-marker-gap",
                "[entrypoint]",
                lambda root: _replace_once(
                    root / "ERPNext/scripts/erpnext-frontend.sh",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|svgz|xml)$ {",
                    "location ~* ^/(?:private/)?files/.*\\."
                    "(?:htm|html|xht|xhtml|svg|xml)$ {",
                ),
            ),
            NegativeCase(
                "worker-count-default-invalid",
                "[workers]",
                lambda root: _set_env(
                    root / "templates/erpnext-worker-short/.env",
                    "ERPNEXT_WORKER_SHORT_PROCESSES",
                    "0",
                ),
            ),
            NegativeCase(
                "worker-health-count-bypass",
                "[workers]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-worker-long/scripts/"
                    "erpnext-worker-long-healthcheck.py",
                    "healthy_workers >= expected_worker_count",
                    "healthy_workers >= 0",
                ),
            ),
            NegativeCase(
                "worker-health-cross-container-bypass",
                "[workers]",
                lambda root: _replace_once(
                    root
                    / "templates/erpnext-worker-short/scripts/"
                    "erpnext-worker-short-healthcheck.py",
                    "    if worker.hostname != local_hostname or not isinstance(pid, int) or pid <= 1:",
                    "    if False or not isinstance(pid, int) or pid <= 1:",
                ),
            ),
            NegativeCase(
                "newline-secret-placeholder",
                "[placeholder]",
                lambda root: (
                    root
                    / "templates/erpnext-redis-cache/secrets/ERPNEXT_REDIS_CACHE_PASSWORD"
                ).write_bytes(b"CHANGE_ME\n"),
            ),
            NegativeCase(
                "frontend-vendor-handoff-removed",
                "[entrypoint]",
                lambda root: _replace_once(
                    root / "ERPNext/scripts/erpnext-frontend.sh",
                    'exec "${ERPNEXT_VENDOR_NGINX_ENTRYPOINT}"',
                    'exec /bin/false',
                ),
            ),
        ]
    )
    return tuple(cases)


def main() -> None:
    initial_fingerprint = _tree_fingerprint(REPO_ROOT)
    positive = validate_stack(REPO_ROOT)
    if positive.errors:
        print(
            f"FAIL: current ERPNext repository violates {len(positive.errors)} "
            f"of {positive.assertions} evaluated contracts"
        )
        for error in positive.errors:
            print(f"  - {error}")
        raise SystemExit(1)
    print(
        f"PASS positive: current ERPNext repository ({positive.assertions} contracts)"
    )

    negative_cases = _negative_cases()
    total_assertions = positive.assertions
    with tempfile.TemporaryDirectory(
        prefix="erpnext-stack-regression.", dir="/tmp"
    ) as raw_fixture_root:
        fixture_parent = Path(raw_fixture_root)
        for index, case in enumerate(negative_cases, 1):
            fixture_root = fixture_parent / f"case-{index:02d}-{case.name}"
            _copy_fixture(REPO_ROOT, fixture_root)
            case.mutate(fixture_root)
            result = validate_stack(fixture_root)
            total_assertions += result.assertions
            matching = [
                error for error in result.errors if case.expected_error in error
            ]
            if not matching:
                print(
                    f"FAIL negative {index:02d}/{len(negative_cases)} "
                    f"{case.name}: expected {case.expected_error}"
                )
                for error in result.errors[:20]:
                    print(f"  - {error}")
                raise SystemExit(1)
            print(
                f"PASS negative {index:02d}/{len(negative_cases)}: {case.name}"
            )

    final_fingerprint = _tree_fingerprint(REPO_ROOT)
    if final_fingerprint != initial_fingerprint:
        print("FAIL: ERPNext workspace changed during Docker-free regression")
        raise SystemExit(1)
    scenario_count = 1 + len(negative_cases) + 1
    print(
        "PASS: "
        f"{scenario_count} scenarios "
        f"(1 positive, {len(negative_cases)} negative /tmp mutations, "
        "1 workspace-immutability check); "
        f"{total_assertions} contract evaluations; Docker/network calls: 0"
    )


if __name__ == "__main__":
    main()
