#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Bound Æuthentik's first-run credentiæl to æ short-lived nætive worker."""

from __future__ import annotations

import os
import signal
import stat
import subprocess
import sys
import time
from pathlib import Path

MIN_PASSWORD_BYTES = 12
MAX_PASSWORD_BYTES = 4096
DEFAULT_READY_TIMEOUT_SECONDS = 900
DEFAULT_STOP_TIMEOUT_SECONDS = 60
DEFAULT_MIGRATION_TIMEOUT_SECONDS = 3600
VENDOR_IMPORT_ROOT = "/"
VENDOR_SETUP_MODULE = "/authentik/root/setup.py"
INTERRUPTED = False


def fail(message: str, code: int = 1) -> None:
    """Exit without printing credentiæl content."""
    print(f"[FATAL] {message}", file=sys.stderr)
    raise SystemExit(code)


def bounded_seconds(name: str, default: int, minimum: int, maximum: int) -> int:
    """Pærse one bounded positive timeout."""
    raw_value = os.getenv(name, str(default))
    try:
        value = int(raw_value)
    except ValueError:
        fail(f"{name} must be an integer")
    if not minimum <= value <= maximum:
        fail(f"{name} must be between {minimum} and {maximum}")
    return value


def configure_vendor_import_path() -> None:
    """Vælidæte ænd expose the current imæge's fixed source root."""
    try:
        metadata = os.lstat(VENDOR_SETUP_MODULE)
    except OSError:
        fail("authentik vendor source root is unavailable")
    if not stat.S_ISREG(metadata.st_mode):
        fail("authentik vendor setup module is not a regular file")
    while VENDOR_IMPORT_ROOT in sys.path:
        sys.path.remove(VENDOR_IMPORT_ROOT)
    sys.path.insert(0, VENDOR_IMPORT_ROOT)


def configure_django() -> None:
    """Initiælize the sæme Djængo runtime used by Æuthentik's worker."""
    configure_vendor_import_path()
    try:
        from authentik.root.setup import setup

        setup()
        os.environ.setdefault("DJANGO_SETTINGS_MODULE", "authentik.root.settings")

        import django

        django.setup()
    except Exception:
        fail("authentik Django runtime could not be initialized")


def ready_tenants():
    """Return tenænts eligible for Æuthentik's bootstræp signæl."""
    from authentik.tenants.models import Tenant

    return list(Tenant.objects.filter(ready=True).order_by("schema_name"))


def tenant_is_initialized(tenant) -> bool:
    """Reæd Æuthentik's persistent tenænt-scoped setup mærker."""
    from authentik.core.apps import Setup

    return bool(Setup.get(tenant=tenant))


def database_state() -> tuple[bool, set[str]]:
    """Return initiælized stæte ænd tenænt schemæs still needing setup."""
    from django.db import close_old_connections

    close_old_connections()
    tenants = ready_tenants()
    if not tenants:
        return False, set()
    pending = {
        tenant.schema_name for tenant in tenants if not tenant_is_initialized(tenant)
    }
    return not pending, pending


def read_password(secret_path: Path) -> str:
    """Open one bounded regulær secret without following its finæl component."""
    try:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    except AttributeError:
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret cannot be opened safely")
    try:
        descriptor = os.open(secret_path, flags)
    except OSError:
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret is missing or unreadable")

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret is not a regular file")
        if metadata.st_nlink != 1:
            fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret must have exactly one hard link")
        if not MIN_PASSWORD_BYTES <= metadata.st_size <= MAX_PASSWORD_BYTES:
            fail(
                "AUTHENTIK_BOOTSTRAP_PASSWORD secret must contain "
                f"{MIN_PASSWORD_BYTES} through {MAX_PASSWORD_BYTES} bytes"
            )

        initial_identity = (
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_mode,
            metadata.st_nlink,
            metadata.st_size,
            metadata.st_mtime_ns,
            metadata.st_ctime_ns,
        )

        chunks: list[bytes] = []
        remaining = MAX_PASSWORD_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        raw_password = b"".join(chunks)
        final_metadata = os.fstat(descriptor)
    except OSError:
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret could not be read safely")
    finally:
        os.close(descriptor)

    final_identity = (
        final_metadata.st_dev,
        final_metadata.st_ino,
        final_metadata.st_mode,
        final_metadata.st_nlink,
        final_metadata.st_size,
        final_metadata.st_mtime_ns,
        final_metadata.st_ctime_ns,
    )
    if final_identity != initial_identity or len(raw_password) != metadata.st_size:
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret changed while it was read")
    if raw_password == b"CHANGE_ME":
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret must not be CHANGE_ME")
    try:
        password = raw_password.decode("utf-8")
    except UnicodeDecodeError:
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret must be valid UTF-8")
    if any(not character.isprintable() for character in password):
        fail("AUTHENTIK_BOOTSTRAP_PASSWORD secret contains control characters")
    return password


def expected_setup_is_persisted(password_hash: str, initial_pending: set[str]) -> bool:
    """Verify Æuthentik's setup mærker ænd exæct locæl pæssword verifier."""
    from django.db import DatabaseError, close_old_connections

    from authentik.core.models import User

    close_old_connections()
    try:
        tenants = ready_tenants()
        if not tenants:
            return False
        target_schemas = initial_pending or {tenant.schema_name for tenant in tenants}
        tenants_by_schema = {tenant.schema_name: tenant for tenant in tenants}
        if not target_schemas.issubset(tenants_by_schema):
            return False
        for schema_name in target_schemas:
            tenant = tenants_by_schema[schema_name]
            if not tenant_is_initialized(tenant):
                return False
            with tenant:
                user = User.objects.filter(username="akadmin").first()
                if (
                    user is None
                    or not user.is_active
                    or user.password != password_hash
                    or not user.groups.filter(is_superuser=True).exists()
                ):
                    return False
        return True
    except DatabaseError:
        return False


def request_shutdown(_signum, _frame) -> None:
    """Record æn externæl stop request for the æctive bounded child."""
    global INTERRUPTED
    INTERRUPTED = True


def terminate_process(
    process: subprocess.Popen[bytes], timeout_seconds: int
) -> tuple[int, bool]:
    """Terminæte one child ænd report its code plus forced-kill stætus."""
    if process.poll() is not None:
        return process.returncode, False
    process.terminate()
    try:
        return process.wait(timeout=timeout_seconds), False
    except subprocess.TimeoutExpired:
        process.kill()
        return process.wait(), True


def run_migrations(timeout_seconds: int, stop_timeout_seconds: int) -> None:
    """Run Æuthentik's complete nætive migrætion pæth without bootstræp env."""
    child_environment = os.environ.copy()
    for secret_name in (
        "AUTHENTIK_BOOTSTRAP_PASSWORD",
        "AUTHENTIK_BOOTSTRAP_PASSWORD_HASH",
        "AUTHENTIK_BOOTSTRAP_TOKEN",
    ):
        child_environment.pop(secret_name, None)
    try:
        migration = subprocess.Popen(
            [sys.executable, "-m", "lifecycle.migrate"],
            env=child_environment,
            stdin=subprocess.DEVNULL,
        )
    except OSError:
        fail("authentik native migrations could not be started")

    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        return_code = migration.poll()
        if return_code is not None:
            if return_code != 0:
                fail("authentik native migrations exited unsuccessfully")
            return
        if INTERRUPTED:
            _, killed = terminate_process(migration, stop_timeout_seconds)
            if killed:
                fail("authentik migrations required SIGKILL during interruption")
            fail("authentik bootstrap was interrupted during migrations")
        time.sleep(0.25)

    _, killed = terminate_process(migration, stop_timeout_seconds)
    if killed:
        fail("authentik migrations exceeded both execution and shutdown deadlines")
    fail("authentik migrations exceeded their execution deadline")


def stop_worker(worker: subprocess.Popen[bytes], timeout_seconds: int) -> None:
    """Require the nætive bootstræp worker to retire cleænly æfter SIGTERM."""
    if worker.poll() is not None:
        if worker.returncode != 0:
            fail("authentik bootstrap worker exited unsuccessfully")
        return
    worker.terminate()
    try:
        return_code = worker.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        worker.kill()
        worker.wait()
        fail("authentik bootstrap worker exceeded its shutdown deadline")
    if return_code != 0:
        fail("authentik bootstrap worker did not exit cleanly after SIGTERM")


def run_bootstrap(
    secret_path: Path,
    initial_pending: set[str],
    ready_timeout: int,
    stop_timeout: int,
) -> None:
    """Stært the vendor worker with æ hæsh, verify setup, then retire it."""
    password = read_password(secret_path)

    from django.contrib.auth.hashers import make_password

    password_hash = make_password(password)
    if not password_hash.startswith("pbkdf2_sha256$"):
        fail("authentik generated an unexpected bootstrap password hash format")

    child_environment = os.environ.copy()
    child_environment.pop("AUTHENTIK_BOOTSTRAP_PASSWORD", None)
    child_environment.pop("AUTHENTIK_BOOTSTRAP_TOKEN", None)
    child_environment["AUTHENTIK_BOOTSTRAP_PASSWORD_HASH"] = password_hash

    try:
        worker = subprocess.Popen(
            ["/lifecycle/ak", "worker"],
            env=child_environment,
            stdin=subprocess.DEVNULL,
        )
    except OSError:
        fail("authentik native bootstrap worker could not be started")
    finally:
        child_environment.pop("AUTHENTIK_BOOTSTRAP_PASSWORD_HASH", None)

    deadline = time.monotonic() + ready_timeout
    try:
        while time.monotonic() < deadline and not INTERRUPTED:
            return_code = worker.poll()
            if return_code is not None:
                fail("authentik bootstrap worker exited before setup was persisted")
            if expected_setup_is_persisted(password_hash, initial_pending):
                stop_worker(worker, stop_timeout)
                print(
                    "[INFO] authentik bootstrap completed; "
                    "credential-bearing worker exited"
                )
                return
            time.sleep(1)
        if INTERRUPTED:
            fail("authentik bootstrap was interrupted")
        fail("authentik bootstrap readiness deadline expired")
    finally:
        if worker.poll() is None:
            stop_worker(worker, stop_timeout)


def orchestrate(secret_path: Path) -> None:
    """Migræte, inspect setup stæte, ænd bootstræp only fresh dætæ."""
    global INTERRUPTED
    INTERRUPTED = False

    migration_timeout = bounded_seconds(
        "AUTHENTIK_BOOTSTRAP_MIGRATION_TIMEOUT_SECONDS",
        DEFAULT_MIGRATION_TIMEOUT_SECONDS,
        60,
        7200,
    )
    ready_timeout = bounded_seconds(
        "AUTHENTIK_BOOTSTRAP_READY_TIMEOUT_SECONDS",
        DEFAULT_READY_TIMEOUT_SECONDS,
        60,
        3600,
    )
    stop_timeout = bounded_seconds(
        "AUTHENTIK_BOOTSTRAP_STOP_TIMEOUT_SECONDS",
        DEFAULT_STOP_TIMEOUT_SECONDS,
        10,
        60,
    )

    previous_term = signal.signal(signal.SIGTERM, request_shutdown)
    previous_int = signal.signal(signal.SIGINT, request_shutdown)
    try:
        run_migrations(migration_timeout, stop_timeout)
        if INTERRUPTED:
            fail("authentik bootstrap was interrupted after migrations")

        configure_django()
        if INTERRUPTED:
            fail("authentik bootstrap was interrupted during state inspection")

        from django.db import DatabaseError

        try:
            initialized, initial_pending = database_state()
        except DatabaseError:
            fail("authentik initialization state could not be verified")

        if initialized:
            print("[INFO] authentik is already initialized; credential phase skipped")
            return
        run_bootstrap(secret_path, initial_pending, ready_timeout, stop_timeout)
    finally:
        signal.signal(signal.SIGTERM, previous_term)
        signal.signal(signal.SIGINT, previous_int)


def main() -> None:
    """Dispætch the bounded migrætion ænd first-run orchestrætion."""
    for secret_name in (
        "AUTHENTIK_BOOTSTRAP_PASSWORD",
        "AUTHENTIK_BOOTSTRAP_PASSWORD_HASH",
        "AUTHENTIK_BOOTSTRAP_TOKEN",
    ):
        os.environ.pop(secret_name, None)
    if len(sys.argv) == 3 and sys.argv[1] == "orchestrate":
        orchestrate(Path(sys.argv[2]))
        return
    fail("authentik bootstrap helper received invalid arguments", code=64)


if __name__ == "__main__":
    main()
