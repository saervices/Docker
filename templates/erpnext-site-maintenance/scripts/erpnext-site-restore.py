#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Strict ERPNext bundle verifier, no-clobber publisher, ænd in-process restore bridge.

import argparse
import contextlib
import ctypes
import datetime
import errno
import gzip
import hashlib
import inspect
import json
import os
import re
import secrets
import shlex
import stat
import tarfile
import tempfile
import unicodedata
from pathlib import Path, PurePosixPath


BACKUP_ROOT = Path("/backup")
STAGING_ROOT = BACKUP_ROOT / ".erpnext-site-staging"
SITES_ROOT = Path("/home/frappe/frappe-bench/sites")
BENCH_ROOT = Path("/home/frappe/frappe-bench")
MANIFEST_NAME = "bundle.manifest"
MANIFEST_CHECKSUM_NAME = "bundle.manifest.sha256"
MANIFEST_FORMAT = "erpnext-site-bundle-v1"
MARIADB_CLIENT_OPTION_ROOT = Path("/tmp")
MARIADB_CLIENT_OPTION_PREFIX = ".erpnext-site-restore."
MARIADB_CLIENT_OPTION_NAME = "client.cnf"
MAX_CONFIG_BYTES = 1024 * 1024
MAX_SECRET_BYTES = 4096
MIN_SECRET_BYTES = 12
MAX_DATABASE_EXPANDED_BYTES = 2 * 1024**4
MAX_ARCHIVE_EXPANDED_BYTES = 2 * 1024**4
MAX_ARCHIVE_MEMBER_BYTES = 1024**4
MAX_ARCHIVE_MEMBERS = 1_000_000
RENAME_NOREPLACE = 1
AT_FDCWD = -100
BUNDLE_PATTERN = re.compile(r"erpnext-[0-9]{8}T[0-9]{6}Z")
SITE_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}[A-Za-z0-9]")
SAFE_NAME_PATTERN = re.compile(r"[A-Za-z0-9._-]+")
DIGEST_PATTERN = re.compile(r"[a-f0-9]{64}")
VENDOR_PREFIX_PATTERN = re.compile(r"[0-9]{8}_[0-9]{6}-[A-Za-z0-9_-]+")
MANIFEST_KEYS = (
    "FORMAT",
    "BUNDLE_ID",
    "SITE",
    "CREATED_AT_UTC",
    "DATABASE_FILE",
    "DATABASE_SHA256",
    "SITE_CONFIG_FILE",
    "SITE_CONFIG_SHA256",
    "PUBLIC_FILES_FILE",
    "PUBLIC_FILES_SHA256",
    "PRIVATE_FILES_FILE",
    "PRIVATE_FILES_SHA256",
)


def fail(message):
    raise RuntimeError(message)


def require_real_directory(path, exact_mode=None):
    try:
        metadata = os.lstat(path)
    except FileNotFoundError as error:
        raise RuntimeError("required directory is missing") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("required directory must be a real directory")
    if exact_mode is not None and stat.S_IMODE(metadata.st_mode) != exact_mode:
        fail("directory mode does not match the private bundle contract")
    if Path(path).resolve(strict=True) != Path(path):
        fail("directory path contains symbolic or non-canonical components")
    return metadata


def open_regular(path, exact_mode=None):
    try:
        before = os.lstat(path)
    except FileNotFoundError as error:
        raise RuntimeError("required regular file is missing") from error
    if not stat.S_ISREG(before.st_mode) or stat.S_ISLNK(before.st_mode):
        fail("bundle members must be regular non-symlink files")
    if exact_mode is not None and stat.S_IMODE(before.st_mode) != exact_mode:
        fail("bundle member mode must be exactly 0600")
    flags = os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    after = os.fstat(descriptor)
    if not stat.S_ISREG(after.st_mode):
        os.close(descriptor)
        fail("opened bundle member is not a regular file")
    before_identity = (before.st_dev, before.st_ino, before.st_size, before.st_mode)
    after_identity = (after.st_dev, after.st_ino, after.st_size, after.st_mode)
    if before_identity != after_identity:
        os.close(descriptor)
        fail("bundle member identity changed while it was opened")
    return descriptor, after


def read_regular(path, maximum_bytes, exact_mode=None):
    descriptor, metadata = open_regular(path, exact_mode=exact_mode)
    try:
        if metadata.st_size > maximum_bytes:
            fail("regular file exceeds its bounded size limit")
        payload = bytearray()
        while len(payload) <= maximum_bytes:
            chunk = os.read(descriptor, min(65536, maximum_bytes + 1 - len(payload)))
            if not chunk:
                break
            payload.extend(chunk)
        final_metadata = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if len(payload) != metadata.st_size or len(payload) > maximum_bytes:
        fail("regular file changed while it was read")
    initial_identity = (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mode)
    final_identity = (
        final_metadata.st_dev,
        final_metadata.st_ino,
        final_metadata.st_size,
        final_metadata.st_mode,
    )
    if initial_identity != final_identity:
        fail("regular file identity changed while it was read")
    return bytes(payload)


def sha256_file(path, exact_mode=None):
    descriptor, metadata = open_regular(path, exact_mode=exact_mode)
    digest = hashlib.sha256()
    consumed = 0
    try:
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            consumed += len(chunk)
            digest.update(chunk)
        final_metadata = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if consumed != metadata.st_size:
        fail("bundle member changed while it was hashed")
    if (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mode) != (
        final_metadata.st_dev,
        final_metadata.st_ino,
        final_metadata.st_size,
        final_metadata.st_mode,
    ):
        fail("bundle member identity changed while it was hashed")
    return digest.hexdigest()


def parse_site_config(path, exact_mode=None):
    payload = read_regular(path, MAX_CONFIG_BYTES, exact_mode=exact_mode)
    try:
        config = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError("site configuration backup is not valid UTF-8 JSON") from error
    if not isinstance(config, dict):
        fail("site configuration backup must contain one JSON object")
    required_strings = ("db_name", "db_password", "db_type", "encryption_key")
    for key in required_strings:
        value = config.get(key)
        if not isinstance(value, str) or not value or len(value.encode("utf-8")) > MAX_SECRET_BYTES:
            fail("site configuration backup lacks a required bounded string")
        if any(unicodedata.category(character).startswith("C") for character in value):
            fail("site configuration backup contains a control character in a required value")
    if config["db_type"] != "mariadb":
        fail("site configuration backup is not for the required MariaDB topology")
    return config, payload


def validate_database_archive(path, exact_mode=None):
    descriptor, metadata = open_regular(path, exact_mode=exact_mode)
    expanded = 0
    marker_found = False
    carry = b""
    try:
        with os.fdopen(descriptor, "rb", closefd=True) as raw_input:
            with gzip.GzipFile(fileobj=raw_input, mode="rb") as database_input:
                while True:
                    chunk = database_input.read(1024 * 1024)
                    if not chunk:
                        break
                    expanded += len(chunk)
                    if expanded > MAX_DATABASE_EXPANDED_BYTES:
                        fail("expanded database backup exceeds the bounded size limit")
                    sample = carry + chunk
                    if b"__Auth" in sample:
                        marker_found = True
                    carry = sample[-16:]
            final_metadata = os.fstat(raw_input.fileno())
    except (OSError, EOFError) as error:
        raise RuntimeError("database backup is not a complete valid gzip stream") from error
    if expanded == 0 or not marker_found:
        fail("database backup is empty or lacks the required Frappe authentication table")
    if (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mode) != (
        final_metadata.st_dev,
        final_metadata.st_ino,
        final_metadata.st_size,
        final_metadata.st_mode,
    ):
        fail("database backup identity changed during decompression")


def validate_archive_member_name(name, visibility, is_directory):
    clean_name = name[:-1] if is_directory and name.endswith("/") else name
    if not clean_name or clean_name.startswith("/") or "\\" in clean_name or "\x00" in clean_name:
        fail("file archive contains an unsafe member name")
    raw_parts = clean_name.split("/")
    # Fræppe v16's nætive `bench bæckup --with-files` writes members æs
    # `./<site>/<public|privæte>/files/...`. Æccept thæt one exæct leæding
    # dot component while continuing to reject every other empty, dot, or
    # træversæl component. The vendor restore strips exæctly `./<site>`.
    if len(raw_parts) < 4 or raw_parts[0] != ".":
        fail("file archive does not match the vendor path-prefix contract")
    if any(part in ("", ".", "..") for part in raw_parts[1:]):
        fail("file archive contains traversal or non-canonical members")
    if any(any(unicodedata.category(character).startswith("C") for character in part) for part in raw_parts[1:]):
        fail("file archive contains control characters in a member name")
    stripped = raw_parts[2:]
    if len(stripped) < 2 or stripped[0] != visibility or stripped[1] != "files":
        fail("file archive member escapes its expected public or private files tree")
    relative_parts = stripped[2:]
    return PurePosixPath(*relative_parts) if relative_parts else PurePosixPath(".")


def validate_file_archive(path, visibility, exact_mode=None):
    descriptor, metadata = open_regular(path, exact_mode=exact_mode)
    member_count = 0
    expanded = 0
    names = set()
    expected_directories = set()
    expected_files = {}
    try:
        with os.fdopen(descriptor, "rb", closefd=True) as raw_input:
            with tarfile.open(fileobj=raw_input, mode="r:gz") as archive:
                for member in archive:
                    member_count += 1
                    if member_count > MAX_ARCHIVE_MEMBERS:
                        fail("file archive exceeds the bounded member-count limit")
                    relative_path = validate_archive_member_name(member.name, visibility, member.isdir())
                    normalized_name = member.name[:-1] if member.isdir() and member.name.endswith("/") else member.name
                    if normalized_name in names:
                        fail("file archive contains duplicate member names")
                    names.add(normalized_name)
                    if not (member.isdir() or member.isfile()):
                        fail("file archive contains links or special nodes")
                    if member.size < 0 or member.size > MAX_ARCHIVE_MEMBER_BYTES:
                        fail("file archive member exceeds the bounded size limit")
                    expanded += member.size
                    if expanded > MAX_ARCHIVE_EXPANDED_BYTES:
                        fail("expanded file archive exceeds the bounded size limit")
                    if relative_path != PurePosixPath("."):
                        for parent in relative_path.parents:
                            if parent != PurePosixPath("."):
                                expected_directories.add(parent.as_posix())
                    if member.isdir() and relative_path != PurePosixPath("."):
                        expected_directories.add(relative_path.as_posix())
                    if member.isfile():
                        extracted = archive.extractfile(member)
                        if extracted is None:
                            fail("file archive member cannot be decompressed")
                        consumed = 0
                        digest = hashlib.sha256()
                        while True:
                            chunk = extracted.read(1024 * 1024)
                            if not chunk:
                                break
                            consumed += len(chunk)
                            digest.update(chunk)
                            if consumed > member.size:
                                fail("file archive member expanded beyond its declared size")
                        if consumed != member.size:
                            fail("file archive member ended before its declared size")
                        relative_name = relative_path.as_posix()
                        if relative_name in expected_files:
                            fail("file archive normalizes multiple members to one live path")
                        expected_files[relative_name] = (member.size, digest.hexdigest())
            final_metadata = os.fstat(raw_input.fileno())
    except (tarfile.TarError, OSError, EOFError) as error:
        raise RuntimeError("file archive is not a complete valid compressed tar stream") from error
    if member_count == 0:
        fail("file archive contains no members")
    if (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mode) != (
        final_metadata.st_dev,
        final_metadata.st_ino,
        final_metadata.st_size,
        final_metadata.st_mode,
    ):
        fail("file archive identity changed during decompression")
    return expected_directories, expected_files


def vendor_preflight(site, database_path):
    previous_directory = Path.cwd()
    # Bench v16 executes Fræppe commænds from the sites directory. Fræppe's
    # logger resolves ../logs relætive to thæt working directory.
    os.chdir(SITES_ROOT)
    try:
        import frappe
        from frappe.installer import is_downgrade, is_partial, validate_database_sql

        frappe.init(site, sites_path=str(SITES_ROOT))
        if is_partial(str(database_path)):
            fail("vendor preflight identified a partial database backup")
        validate_database_sql(str(database_path), _raise=True)
        if is_downgrade(str(database_path), verbose=False):
            fail("vendor preflight rejects an implicit Frappe downgrade")
    finally:
        try:
            import frappe

            frappe.destroy()
        except Exception:
            pass
        os.chdir(previous_directory)


def validate_artifact_names(database, site_config, public_files, private_files):
    names = (database.name, site_config.name, public_files.name, private_files.name)
    if len(set(names)) != 4 or any(not SAFE_NAME_PATTERN.fullmatch(name) for name in names):
        fail("vendor backup artifact names are unsafe or duplicate")
    suffixes = (
        (database.name, "-database.sql.gz"),
        (site_config.name, "-site_config_backup.json"),
        (public_files.name, "-files.tgz"),
        (private_files.name, "-private-files.tgz"),
    )
    prefixes = []
    for name, suffix in suffixes:
        if not name.endswith(suffix):
            fail("vendor backup artifact suffix is unexpected")
        prefixes.append(name[: -len(suffix)])
    if len(set(prefixes)) != 1 or not VENDOR_PREFIX_PATTERN.fullmatch(prefixes[0]):
        fail("vendor backup artifacts do not originate from one coherent run")
    if "-partial-" in database.name:
        fail("partial database backups are not accepted")


def verify_artifacts(site, database, site_config, public_files, private_files, exact_mode=None):
    if not SITE_PATTERN.fullmatch(site) or ".." in site:
        fail("site name is not strict or path-safe")
    paths = tuple(Path(value) for value in (database, site_config, public_files, private_files))
    if len({path.parent for path in paths}) != 1:
        fail("backup artifacts must share one staging or bundle directory")
    validate_artifact_names(paths[0], paths[1], paths[2], paths[3])
    config, _ = parse_site_config(paths[1], exact_mode=exact_mode)
    if config.get("db_type") != "mariadb":
        fail("site configuration database type does not match the stack")
    validate_database_archive(paths[0], exact_mode=exact_mode)
    validate_file_archive(paths[2], "public", exact_mode=exact_mode)
    validate_file_archive(paths[3], "private", exact_mode=exact_mode)
    vendor_preflight(site, paths[0])
    return config


def parse_manifest(bundle, bundle_id, site):
    payload = read_regular(bundle / MANIFEST_NAME, MAX_CONFIG_BYTES, exact_mode=0o600)
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError("bundle manifest is not valid UTF-8") from error
    if not text.endswith("\n") or "\r" in text or "\x00" in text:
        fail("bundle manifest line structure is non-canonical")
    manifest = {}
    observed_keys = []
    for line in text.splitlines():
        if line.count("=") != 1:
            fail("bundle manifest contains a malformed assignment")
        key, value = line.split("=", 1)
        if key in manifest or not value:
            fail("bundle manifest contains duplicate or empty values")
        observed_keys.append(key)
        manifest[key] = value
    if tuple(observed_keys) != MANIFEST_KEYS:
        fail("bundle manifest keys or ordering do not match the strict contract")
    if manifest["FORMAT"] != MANIFEST_FORMAT:
        fail("bundle manifest format is unsupported")
    if manifest["BUNDLE_ID"] != bundle_id or manifest["SITE"] != site:
        fail("bundle manifest identity does not match the explicit restore selection")
    if not BUNDLE_PATTERN.fullmatch(bundle_id) or not SITE_PATTERN.fullmatch(site) or ".." in site:
        fail("bundle or site identity is not strict")
    try:
        datetime.datetime.strptime(manifest["CREATED_AT_UTC"], "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise RuntimeError("bundle manifest timestamp is non-canonical") from error
    for key in ("DATABASE_SHA256", "SITE_CONFIG_SHA256", "PUBLIC_FILES_SHA256", "PRIVATE_FILES_SHA256"):
        if not DIGEST_PATTERN.fullmatch(manifest[key]):
            fail("bundle manifest contains a malformed digest")
    for key in ("DATABASE_FILE", "SITE_CONFIG_FILE", "PUBLIC_FILES_FILE", "PRIVATE_FILES_FILE"):
        if not SAFE_NAME_PATTERN.fullmatch(manifest[key]):
            fail("bundle manifest contains an unsafe artifact name")
    return manifest


def validate_sidecar(bundle, artifact_name, digest):
    sidecar_name = f"{artifact_name}.sha256"
    payload = read_regular(bundle / sidecar_name, 256, exact_mode=0o600)
    expected = f"{digest}  {artifact_name}\n".encode("ascii")
    if payload != expected:
        fail("artifact checksum sidecar is non-canonical or mismatched")


def verify_bundle(bundle_value, bundle_id, site):
    bundle = Path(bundle_value)
    require_real_directory(BACKUP_ROOT)
    require_real_directory(bundle, exact_mode=0o700)
    if bundle.parent not in (BACKUP_ROOT, STAGING_ROOT):
        fail("bundle directory is outside the approved backup roots")
    if bundle.parent == BACKUP_ROOT and bundle.name != bundle_id:
        fail("published bundle path does not match its explicit identifier")
    manifest = parse_manifest(bundle, bundle_id, site)
    manifest_digest = sha256_file(bundle / MANIFEST_NAME, exact_mode=0o600)
    expected_manifest_sidecar = f"{manifest_digest}  {MANIFEST_NAME}\n".encode("ascii")
    actual_manifest_sidecar = read_regular(bundle / MANIFEST_CHECKSUM_NAME, 256, exact_mode=0o600)
    if actual_manifest_sidecar != expected_manifest_sidecar:
        fail("bundle manifest checksum sidecar is invalid")

    artifacts = {
        manifest["DATABASE_FILE"]: manifest["DATABASE_SHA256"],
        manifest["SITE_CONFIG_FILE"]: manifest["SITE_CONFIG_SHA256"],
        manifest["PUBLIC_FILES_FILE"]: manifest["PUBLIC_FILES_SHA256"],
        manifest["PRIVATE_FILES_FILE"]: manifest["PRIVATE_FILES_SHA256"],
    }
    if len(artifacts) != 4:
        fail("bundle manifest artifact names are duplicate")
    expected_members = {MANIFEST_NAME, MANIFEST_CHECKSUM_NAME}
    for artifact_name, expected_digest in artifacts.items():
        expected_members.add(artifact_name)
        expected_members.add(f"{artifact_name}.sha256")
        actual_digest = sha256_file(bundle / artifact_name, exact_mode=0o600)
        if actual_digest != expected_digest:
            fail("manifest-bound artifact checksum does not match")
        validate_sidecar(bundle, artifact_name, expected_digest)

    actual_members = set()
    with os.scandir(bundle) as entries:
        for entry in entries:
            if entry.name in actual_members:
                fail("bundle contains duplicate members")
            actual_members.add(entry.name)
            metadata = entry.stat(follow_symlinks=False)
            if not stat.S_ISREG(metadata.st_mode) or entry.is_symlink():
                fail("bundle contains directories, links, or special nodes")
            if stat.S_IMODE(metadata.st_mode) != 0o600:
                fail("every published bundle member must be mode 0600")
    if actual_members != expected_members:
        fail("bundle inventory contains missing or unknown members")

    database = bundle / manifest["DATABASE_FILE"]
    site_config = bundle / manifest["SITE_CONFIG_FILE"]
    public_files = bundle / manifest["PUBLIC_FILES_FILE"]
    private_files = bundle / manifest["PRIVATE_FILES_FILE"]
    config = verify_artifacts(
        site,
        database,
        site_config,
        public_files,
        private_files,
        exact_mode=0o600,
    )
    return manifest, config


def fsync_bundle(bundle):
    with os.scandir(bundle) as entries:
        for entry in entries:
            descriptor, _ = open_regular(Path(bundle) / entry.name, exact_mode=0o600)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    directory_descriptor = os.open(bundle, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_descriptor)
    finally:
        os.close(directory_descriptor)


def rename_noreplace(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    try:
        renameat2 = libc.renameat2
    except AttributeError as error:
        raise RuntimeError("Linux renameat2 is required for atomic no-clobber publication") from error
    renameat2.argtypes = (ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint)
    renameat2.restype = ctypes.c_int
    result = renameat2(
        AT_FDCWD,
        os.fsencode(source),
        AT_FDCWD,
        os.fsencode(destination),
        RENAME_NOREPLACE,
    )
    if result != 0:
        error_number = ctypes.get_errno()
        if error_number == errno.EEXIST:
            fail("bundle destination already exists; publication is no-clobber")
        raise OSError(error_number, os.strerror(error_number))


def publish_bundle(source_value, destination_value, bundle_id, site):
    source = Path(source_value)
    destination = Path(destination_value)
    require_real_directory(STAGING_ROOT, exact_mode=0o700)
    if source.parent != STAGING_ROOT or not source.name.startswith(".erpnext-site-stage."):
        fail("publication source is outside the private staging contract")
    require_real_directory(source, exact_mode=0o700)
    require_real_directory(BACKUP_ROOT)
    if destination.parent != BACKUP_ROOT or destination.name != bundle_id:
        fail("publication destination does not match the strict bundle identifier")
    if os.path.lexists(destination):
        fail("publication destination already exists")
    if os.lstat(source).st_dev != os.lstat(BACKUP_ROOT).st_dev:
        fail("publication source and destination are not on one filesystem")
    verify_bundle(source, bundle_id, site)
    fsync_bundle(source)
    rename_noreplace(source, destination)
    parent_descriptor = os.open(BACKUP_ROOT, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(parent_descriptor)
    finally:
        os.close(parent_descriptor)


def read_secret(path_value, label):
    payload = bytearray(read_regular(Path(path_value), MAX_SECRET_BYTES))
    if len(payload) < MIN_SECRET_BYTES or len(payload) > MAX_SECRET_BYTES:
        fail(f"{label} has an invalid bounded length")
    try:
        value = bytes(payload).decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError(f"{label} is not valid UTF-8") from error
    finally:
        payload[:] = b"\x00" * len(payload)
    if value == "CHANGE_ME" or value != value.strip():
        fail(f"{label} is unset or non-canonical")
    if any(unicodedata.category(character).startswith("C") for character in value):
        fail(f"{label} contains control characters")
    return value


def regular_file_identity(path):
    metadata = os.lstat(path)
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("restore file identity is not a regular non-symlink file")
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
    )


def encode_mariadb_option_value(value):
    if not isinstance(value, str) or not value:
        fail("MariaDB client option value must be a non-empty string")
    if len(value.encode("utf-8")) > MAX_SECRET_BYTES:
        fail("MariaDB client option value exceeds its bounded size limit")
    if "\n" in value or "\r" in value:
        fail("MariaDB client option value must remain on one line")
    if any(unicodedata.category(character).startswith("C") for character in value):
        fail("MariaDB client option value contains a control character")
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def private_directory_identity(metadata, exact_mode):
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("MariaDB client option directory is not a real directory")
    if stat.S_IMODE(metadata.st_mode) != exact_mode:
        fail("MariaDB client option directory mode is not exact")
    return (
        metadata.st_dev,
        metadata.st_ino,
        stat.S_IMODE(metadata.st_mode),
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
    )


def private_option_file_identity(metadata):
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("MariaDB client option file is not a regular non-symlink file")
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        stat.S_IMODE(metadata.st_mode),
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
    )


def sha256_descriptor(descriptor):
    os.lseek(descriptor, 0, os.SEEK_SET)
    digest = hashlib.sha256()
    consumed = 0
    while True:
        chunk = os.read(descriptor, 65536)
        if not chunk:
            break
        consumed += len(chunk)
        digest.update(chunk)
    return digest.hexdigest(), consumed


def create_mariadb_client_option_file(password):
    root_metadata = require_real_directory(MARIADB_CLIENT_OPTION_ROOT)
    option_value = encode_mariadb_option_value(password)
    payload = f"[client]\npassword={option_value}\n".encode("utf-8")
    parent_flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, "O_CLOEXEC", 0)
    if hasattr(os, "O_NOFOLLOW"):
        parent_flags |= os.O_NOFOLLOW
    root_descriptor = os.open(MARIADB_CLIENT_OPTION_ROOT, parent_flags)
    opened_root_metadata = os.fstat(root_descriptor)
    root_identity = (
        root_metadata.st_dev,
        root_metadata.st_ino,
        stat.S_IMODE(root_metadata.st_mode),
        root_metadata.st_uid,
        root_metadata.st_gid,
    )
    if root_identity != (
        opened_root_metadata.st_dev,
        opened_root_metadata.st_ino,
        stat.S_IMODE(opened_root_metadata.st_mode),
        opened_root_metadata.st_uid,
        opened_root_metadata.st_gid,
    ):
        os.close(root_descriptor)
        fail("MariaDB client option root identity changed while it was opened")

    private_name = None
    private_descriptor = None
    private_identity = None
    created_private_identity = None
    file_descriptor = None
    try:
        for _ in range(128):
            candidate = f"{MARIADB_CLIENT_OPTION_PREFIX}{secrets.token_hex(16)}"
            try:
                os.mkdir(candidate, 0o700, dir_fd=root_descriptor)
                private_name = candidate
                break
            except FileExistsError:
                continue
        if private_name is None:
            fail("could not allocate an exclusive MariaDB client option directory")

        private_entry = os.stat(
            private_name,
            dir_fd=root_descriptor,
            follow_symlinks=False,
        )
        created_private_identity = (private_entry.st_dev, private_entry.st_ino)
        private_descriptor = os.open(private_name, parent_flags, dir_fd=root_descriptor)
        opened_private = os.fstat(private_descriptor)
        if (opened_private.st_dev, opened_private.st_ino) != created_private_identity:
            fail("MariaDB client option directory identity changed while it was opened")
        os.fchmod(private_descriptor, 0o700)
        opened_private = os.fstat(private_descriptor)
        expected_private_identity = (
            root_identity[0],
            opened_private.st_ino,
            0o700,
            os.geteuid(),
            os.getegid(),
            2,
        )
        private_identity = private_directory_identity(opened_private, 0o700)
        if private_identity != expected_private_identity:
            fail("MariaDB client option directory metadata is not private and canonical")
        repeated_private_entry = os.stat(
            private_name,
            dir_fd=root_descriptor,
            follow_symlinks=False,
        )
        if private_directory_identity(repeated_private_entry, 0o700) != private_identity:
            fail("MariaDB client option directory path identity changed after opening")

        flags = os.O_RDWR | os.O_CREAT | os.O_EXCL | getattr(os, "O_CLOEXEC", 0)
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        file_descriptor = os.open(
            MARIADB_CLIENT_OPTION_NAME,
            flags,
            0o600,
            dir_fd=private_descriptor,
        )
        os.fchmod(file_descriptor, 0o600)
        offset = 0
        while offset < len(payload):
            written = os.write(file_descriptor, payload[offset:])
            if written <= 0:
                fail("MariaDB client option file write made no progress")
            offset += written
        os.fsync(file_descriptor)
        os.fsync(private_descriptor)
        os.fsync(root_descriptor)

        file_metadata = os.fstat(file_descriptor)
        file_identity = private_option_file_identity(file_metadata)
        expected_file_identity = (
            root_identity[0],
            file_metadata.st_ino,
            len(payload),
            0o600,
            os.geteuid(),
            os.getegid(),
            1,
        )
        if file_identity != expected_file_identity:
            fail("MariaDB client option file metadata is not private and canonical")
        file_entry = os.stat(
            MARIADB_CLIENT_OPTION_NAME,
            dir_fd=private_descriptor,
            follow_symlinks=False,
        )
        if private_option_file_identity(file_entry) != file_identity:
            fail("MariaDB client option file identity changed after creation")
        private_path = MARIADB_CLIENT_OPTION_ROOT / private_name
        file_path = private_path / MARIADB_CLIENT_OPTION_NAME
        if private_path.resolve(strict=True) != private_path or file_path.resolve(strict=True) != file_path:
            fail("MariaDB client option file path is not canonical")
        if os.listdir(private_descriptor) != [MARIADB_CLIENT_OPTION_NAME]:
            fail("MariaDB client option directory inventory is not exact")
        digest, consumed = sha256_descriptor(file_descriptor)
        if consumed != len(payload) or digest != hashlib.sha256(payload).hexdigest():
            fail("MariaDB client option file bytes changed after creation")
        return {
            "canonical_path": file_path,
            "private_path": private_path,
            "private_name": private_name,
            "file_name": MARIADB_CLIENT_OPTION_NAME,
            "file_descriptor": file_descriptor,
            "private_descriptor": private_descriptor,
            "root_descriptor": root_descriptor,
            "root_identity": root_identity,
            "private_identity": private_identity,
            "file_identity": file_identity,
            "digest": digest,
        }
    except BaseException as creation_error:
        cleanup_errors = []
        if file_descriptor is not None and private_descriptor is not None:
            try:
                opened_file = os.fstat(file_descriptor)
                file_entry = os.stat(
                    MARIADB_CLIENT_OPTION_NAME,
                    dir_fd=private_descriptor,
                    follow_symlinks=False,
                )
                if (opened_file.st_dev, opened_file.st_ino) != (
                    file_entry.st_dev,
                    file_entry.st_ino,
                ):
                    fail("failed MariaDB option-file creation changed path identity")
                os.unlink(MARIADB_CLIENT_OPTION_NAME, dir_fd=private_descriptor)
                if os.fstat(file_descriptor).st_nlink != 0:
                    fail("failed MariaDB option-file creation did not unlink its proven inode")
                os.fsync(private_descriptor)
            except Exception as error:
                cleanup_errors.append(error)
        if (
            private_name is not None
            and private_descriptor is None
            and created_private_identity is not None
        ):
            try:
                private_descriptor = os.open(
                    private_name,
                    parent_flags,
                    dir_fd=root_descriptor,
                )
                opened_private = os.fstat(private_descriptor)
                if (opened_private.st_dev, opened_private.st_ino) != created_private_identity:
                    fail("failed MariaDB option-directory creation changed path identity")
            except Exception as error:
                cleanup_errors.append(error)
        if private_name is not None and private_descriptor is not None:
            try:
                opened_private = os.fstat(private_descriptor)
                private_entry = os.stat(
                    private_name,
                    dir_fd=root_descriptor,
                    follow_symlinks=False,
                )
                if (opened_private.st_dev, opened_private.st_ino) != (
                    private_entry.st_dev,
                    private_entry.st_ino,
                ):
                    fail("failed MariaDB option-directory creation changed path identity")
                if os.listdir(private_descriptor):
                    fail("failed MariaDB option-directory creation left unknown entries")
                os.rmdir(private_name, dir_fd=root_descriptor)
                if os.fstat(private_descriptor).st_nlink != 0:
                    fail("failed MariaDB option-directory creation did not remove its proven inode")
                os.fsync(root_descriptor)
            except Exception as error:
                cleanup_errors.append(error)
        if file_descriptor is not None:
            os.close(file_descriptor)
        if private_descriptor is not None:
            os.close(private_descriptor)
        os.close(root_descriptor)
        if cleanup_errors:
            raise RuntimeError(
                "MariaDB client option-file creation failed and exact cleanup also failed"
            ) from creation_error
        raise


def remove_mariadb_client_option_file(state):
    file_descriptor = state["file_descriptor"]
    private_descriptor = state["private_descriptor"]
    root_descriptor = state["root_descriptor"]
    try:
        root_metadata = os.fstat(root_descriptor)
        root_identity = (
            root_metadata.st_dev,
            root_metadata.st_ino,
            stat.S_IMODE(root_metadata.st_mode),
            root_metadata.st_uid,
            root_metadata.st_gid,
        )
        if root_identity != state["root_identity"]:
            fail("MariaDB client option root directory identity changed")
        opened_private = os.fstat(private_descriptor)
        if private_directory_identity(opened_private, 0o700) != state["private_identity"]:
            fail("MariaDB client option private directory identity changed")
        private_entry = os.stat(
            state["private_name"],
            dir_fd=root_descriptor,
            follow_symlinks=False,
        )
        if private_directory_identity(private_entry, 0o700) != state["private_identity"]:
            fail("MariaDB client option private directory path identity changed")
        if os.listdir(private_descriptor) != [state["file_name"]]:
            fail("MariaDB client option private directory inventory changed")
        opened_file = os.fstat(file_descriptor)
        if private_option_file_identity(opened_file) != state["file_identity"]:
            fail("MariaDB client option file descriptor identity changed")
        file_entry = os.stat(
            state["file_name"],
            dir_fd=private_descriptor,
            follow_symlinks=False,
        )
        if private_option_file_identity(file_entry) != state["file_identity"]:
            fail("MariaDB client option file path identity changed")
        digest, consumed = sha256_descriptor(file_descriptor)
        if digest != state["digest"] or consumed != state["file_identity"][2]:
            fail("MariaDB client option file bytes changed before cleanup")
        os.unlink(state["file_name"], dir_fd=private_descriptor)
        if os.fstat(file_descriptor).st_nlink != 0:
            fail("MariaDB client option file unlink did not remove its proven inode")
        os.fsync(private_descriptor)
        if os.path.lexists(state["canonical_path"]):
            fail("MariaDB client option file path reappeared during cleanup")
        if os.listdir(private_descriptor):
            fail("MariaDB client option directory is not empty after file cleanup")
        if private_directory_identity(os.fstat(private_descriptor), 0o700) != state["private_identity"]:
            fail("MariaDB client option private directory changed before removal")
        os.rmdir(state["private_name"], dir_fd=root_descriptor)
        if os.fstat(private_descriptor).st_nlink != 0:
            fail("MariaDB client option private directory removal did not remove its proven inode")
        os.fsync(root_descriptor)
        if os.path.lexists(state["private_path"]):
            fail("MariaDB client option private directory reappeared during cleanup")
    finally:
        os.close(file_descriptor)
        os.close(private_descriptor)
        os.close(root_descriptor)


def exact_signature_shape(callable_value):
    return tuple(
        (name, parameter.kind, parameter.default)
        for name, parameter in inspect.signature(callable_value).parameters.items()
    )


def contains_password_token(value):
    lowered = value.casefold()
    if "--password" in lowered or "mysql_pwd=" in lowered or "mariadb_pwd=" in lowered:
        return True
    if "mysql_password=" in lowered or "mariadb_password=" in lowered:
        return True
    return re.search(r"(?:^|[\s;|])-[pP](?:[^\s;|]*)", value) is not None


@contextlib.contextmanager
def guarded_mariadb_vendor_restore(
    database_module,
    database_manager_module,
    frappe_utils_module,
    database_class,
    ddl_query_types,
    expected_call,
    expected_password,
    root_password,
    expected_database_path,
):
    required_call_keys = {"socket", "host", "port", "user", "db_name", "extra", "dump"}
    if set(expected_call) != required_call_keys:
        fail("MariaDB restore command expectation is incomplete")
    if expected_call["dump"] is not False or expected_call["extra"] is not None:
        fail("MariaDB restore command expectation is not the non-dump vendor call")
    if expected_call["socket"] not in (None, ""):
        fail("MariaDB restore command unexpectedly uses a local socket")
    if (
        not isinstance(expected_call["host"], str)
        or not expected_call["host"]
        or expected_call["port"] != 3306
        or not isinstance(expected_call["user"], str)
        or not expected_call["user"]
        or expected_call["user"] != expected_call["db_name"]
    ):
        fail("MariaDB restore command topology is outside the reviewed network contract")
    if not isinstance(expected_password, str) or not isinstance(root_password, str):
        fail("MariaDB restore credentials are not strings")
    encode_mariadb_option_value(expected_password)
    encode_mariadb_option_value(root_password)
    expected_database_path = Path(expected_database_path)
    if not expected_database_path.is_absolute() or expected_database_path.resolve(strict=True) != expected_database_path:
        fail("MariaDB restore database path is not canonical")
    exact_ddl_types = frozenset(("alter", "drop", "create", "truncate", "rename"))
    if frozenset(ddl_query_types) != exact_ddl_types:
        fail("Frappe DDL query types changed outside the reviewed restore contract")

    option_state = create_mariadb_client_option_file(expected_password)
    original_get_command = database_module.get_command
    original_execute_in_shell = frappe_utils_module.execute_in_shell
    original_log_query = database_class.__dict__.get("_log_query")
    if not all(
        callable(value)
        for value in (original_get_command, original_execute_in_shell, original_log_query)
    ):
        remove_mariadb_client_option_file(option_state)
        fail("Frappe restore hooks are missing or inherited unexpectedly")

    empty = inspect.Parameter.empty
    positional = inspect.Parameter.POSITIONAL_OR_KEYWORD
    expected_get_command_signature = (
        ("socket", positional, None),
        ("host", positional, None),
        ("port", positional, None),
        ("user", positional, None),
        ("password", positional, None),
        ("db_name", positional, None),
        ("extra", positional, None),
        ("dump", positional, False),
    )
    expected_execute_signature = (
        ("cmd", positional, empty),
        ("verbose", positional, False),
        ("low_priority", positional, False),
        ("check_exit_code", positional, False),
    )
    expected_log_signature = (
        ("self", positional, empty),
        ("mogrified_query", positional, empty),
        ("query_type", positional, empty),
        ("debug", positional, False),
        ("unmogrified_query", positional, ""),
    )
    if exact_signature_shape(original_get_command) != expected_get_command_signature:
        remove_mariadb_client_option_file(option_state)
        fail("Frappe get_command signature changed outside the reviewed restore contract")
    if exact_signature_shape(original_execute_in_shell) != expected_execute_signature:
        remove_mariadb_client_option_file(option_state)
        fail("Frappe execute_in_shell signature changed outside the reviewed restore contract")
    if exact_signature_shape(original_log_query) != expected_log_signature:
        remove_mariadb_client_option_file(option_state)
        fail("Frappe DDL logger signature changed outside the reviewed restore contract")

    manager_get_command_present = "get_command" in database_manager_module.__dict__
    manager_execute_present = "execute_in_shell" in database_manager_module.__dict__
    if manager_get_command_present and database_manager_module.get_command is not original_get_command:
        remove_mariadb_client_option_file(option_state)
        fail("Frappe db_manager has an unexpected bound get_command")
    if manager_execute_present and database_manager_module.execute_in_shell is not original_execute_in_shell:
        remove_mariadb_client_option_file(option_state)
        fail("Frappe db_manager has an unexpected bound execute_in_shell")

    bridge_state = {
        "uses": 0,
        "file_probe_uses": 0,
        "sql_validation_uses": 0,
        "spawn_uses": 0,
        "option_path": option_state["canonical_path"],
        "client_suffix": None,
    }
    forbidden_secrets = tuple(dict.fromkeys((expected_password, root_password)))

    def guarded_get_command(
        socket=None,
        host=None,
        port=None,
        user=None,
        password=None,
        db_name=None,
        extra=None,
        dump=False,
    ):
        observed_call = {
            "socket": socket,
            "host": host,
            "port": port,
            "user": user,
            "db_name": db_name,
            "extra": extra,
            "dump": dump,
        }
        if bridge_state["uses"] != 0:
            fail("Frappe requested the MariaDB restore command more than once")
        if observed_call != expected_call or password != expected_password:
            fail("Frappe requested an unexpected database command during restore")
        binary, arguments, binary_name = original_get_command(
            socket=socket,
            host=host,
            port=port,
            user=user,
            password=None,
            db_name=db_name,
            extra=extra,
            dump=dump,
        )
        returned_values = (binary, binary_name, *(arguments if isinstance(arguments, list) else ()))
        if any(
            isinstance(value, str) and any(secret in value for secret in forbidden_secrets)
            for value in returned_values
        ):
            fail("Frappe returned a secret-bearing MariaDB client command")
        if (
            not isinstance(binary, str)
            or not os.path.isabs(binary)
            or Path(binary).name != "mariadb"
            or binary_name != "mariadb"
            or not isinstance(arguments, list)
        ):
            fail("Frappe returned an unexpected MariaDB client command")
        expected_arguments = [f"--user={user}", f"--host={host}", f"--port={port}"]
        expected_arguments.extend(("--pager=less -SFX", "--safe-updates", "--no-auto-rehash", db_name))
        if arguments != expected_arguments or any(contains_password_token(value) for value in arguments):
            fail("Frappe returned unsafe or duplicate MariaDB client arguments")
        option_argument = f"--defaults-extra-file={option_state['canonical_path']}"
        injected_arguments = [option_argument, *arguments]
        bridge_state["client_suffix"] = f"{binary} {shlex.join(injected_arguments)}"
        bridge_state["uses"] = 1
        return binary, injected_arguments, binary_name

    def guarded_execute_in_shell(
        cmd,
        verbose=False,
        low_priority=False,
        check_exit_code=False,
    ):
        if isinstance(cmd, list):
            if any(not isinstance(value, str) for value in cmd):
                fail("Frappe requested a non-string shell command")
            rendered = shlex.join(cmd)
        elif isinstance(cmd, str):
            rendered = cmd
        else:
            fail("Frappe requested an unsupported shell command")
        if any(
            secret in rendered or shlex.quote(secret) in rendered
            for secret in forbidden_secrets
        ):
            fail("Frappe requested a secret-bearing child process")
        if contains_password_token(rendered):
            fail("Frappe requested a password-bearing child-process option")

        expected_file_probe = f"file {expected_database_path}"
        expected_sql_validation = f"/usr/bin/zgrep -m1 __Auth {expected_database_path}"
        if rendered == expected_file_probe:
            if (
                bridge_state["file_probe_uses"] != 0
                or bridge_state["sql_validation_uses"] != 0
                or bridge_state["uses"] != 0
                or bridge_state["spawn_uses"] != 0
                or verbose is not False
                or low_priority is not False
                or check_exit_code is not True
            ):
                fail("Frappe requested an unexpected database-file probe")
            bridge_state["file_probe_uses"] = 1
        elif rendered == expected_sql_validation:
            if (
                bridge_state["file_probe_uses"] != 1
                or bridge_state["sql_validation_uses"] != 0
                or bridge_state["uses"] != 0
                or bridge_state["spawn_uses"] != 0
                or verbose is not False
                or low_priority is not False
                or check_exit_code is not True
            ):
                fail("Frappe requested an unexpected database-content validation")
            bridge_state["sql_validation_uses"] = 1
        else:
            option_argument = f"--defaults-extra-file={option_state['canonical_path']}"
            client_suffix = bridge_state["client_suffix"]
            if (
                bridge_state["file_probe_uses"] != 1
                or bridge_state["sql_validation_uses"] != 1
                or bridge_state["uses"] != 1
                or bridge_state["spawn_uses"] != 0
                or not isinstance(cmd, str)
                or rendered.count("--defaults-extra-file=") != 1
                or rendered.count(option_argument) != 1
                or not isinstance(client_suffix, str)
                or not rendered.endswith(client_suffix)
                or verbose is not None
                or low_priority is not False
                or check_exit_code is not True
            ):
                fail("Frappe requested an unexpected restore child process")
            bridge_state["spawn_uses"] = 1
        return original_execute_in_shell(
            cmd,
            verbose=verbose,
            low_priority=low_priority,
            check_exit_code=check_exit_code,
        )

    def guarded_log_query(
        self,
        mogrified_query,
        query_type,
        debug=False,
        unmogrified_query="",
    ):
        if query_type in exact_ddl_types:
            return None
        return original_log_query(
            self,
            mogrified_query,
            query_type,
            debug,
            unmogrified_query,
        )

    installed_hooks = []
    active_error = None
    try:
        database_module.get_command = guarded_get_command
        installed_hooks.append((database_module, "get_command", original_get_command, guarded_get_command))
        if manager_get_command_present:
            database_manager_module.get_command = guarded_get_command
            installed_hooks.append(
                (database_manager_module, "get_command", original_get_command, guarded_get_command)
            )
        frappe_utils_module.execute_in_shell = guarded_execute_in_shell
        installed_hooks.append(
            (
                frappe_utils_module,
                "execute_in_shell",
                original_execute_in_shell,
                guarded_execute_in_shell,
            )
        )
        if manager_execute_present:
            database_manager_module.execute_in_shell = guarded_execute_in_shell
            installed_hooks.append(
                (
                    database_manager_module,
                    "execute_in_shell",
                    original_execute_in_shell,
                    guarded_execute_in_shell,
                )
            )
        database_class._log_query = guarded_log_query
        installed_hooks.append((database_class, "_log_query", original_log_query, guarded_log_query))
        yield bridge_state
        if (
            bridge_state["uses"] != 1
            or bridge_state["file_probe_uses"] != 1
            or bridge_state["sql_validation_uses"] != 1
            or bridge_state["spawn_uses"] != 1
        ):
            fail("Frappe did not use the guarded MariaDB restore path exactly once")
    except BaseException as error:
        active_error = error
        raise
    finally:
        cleanup_errors = []
        for owner, attribute, original, guarded in reversed(installed_hooks):
            try:
                if getattr(owner, attribute) is not guarded:
                    fail("Frappe restore hook identity changed before restoration")
                setattr(owner, attribute, original)
                if getattr(owner, attribute) is not original:
                    fail("Frappe restore hook original was not restored")
            except Exception as error:
                cleanup_errors.append(error)
        try:
            remove_mariadb_client_option_file(option_state)
        except Exception as error:
            cleanup_errors.append(error)
        if cleanup_errors:
            cleanup_failure = RuntimeError(
                "Frappe restore guard cleanup or hook restoration failed"
            )
            if active_error is not None:
                raise cleanup_failure from active_error
            raise cleanup_failure from cleanup_errors[0]


def write_live_site_config(state, config_payload, expected_config):
    site_root = state["site_root"]
    target = state["config_live"]
    original = state["config_old"]
    require_real_directory(SITES_ROOT)
    require_real_directory(site_root)
    current_config, _ = parse_site_config(target, exact_mode=0o600)
    topology_keys = ("db_name", "db_user", "db_host", "db_port", "db_type")
    for key in topology_keys:
        if current_config.get(key) != expected_config.get(key):
            fail("bundle site configuration does not match the current deployment topology")
    if regular_file_identity(target) != state["config_old_identity"]:
        fail("live site configuration identity changed before quarantine")
    if sha256_file(target, exact_mode=0o600) != state["config_old_digest"]:
        fail("live site configuration bytes changed before quarantine")

    os.rename(target, original)
    state["config_old_moved"] = True
    if regular_file_identity(original) != state["config_old_identity"]:
        fail("quarantined site configuration identity changed during rename")
    if sha256_file(original, exact_mode=0o600) != state["config_old_digest"]:
        fail("quarantined site configuration bytes changed during rename")
    fsync_directory(state["quarantine"])
    fsync_directory(site_root)

    descriptor, temporary_name = tempfile.mkstemp(prefix=".site_config.restore.", dir=site_root)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb", closefd=True) as output:
            output.write(config_payload)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_name, target)
        state["config_new_live"] = True
        fsync_directory(site_root)
        persisted_config, persisted_payload = parse_site_config(target, exact_mode=0o600)
        if persisted_payload != config_payload or persisted_config != expected_config:
            fail("bundle site configuration postcondition failed before vendor restore")
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def directory_identity(path):
    metadata = os.lstat(path)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        fail("restore directory identity is not a real directory")
    return metadata.st_dev, metadata.st_ino


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def remove_proven_directory(path, expected_identity):
    if directory_identity(path) != expected_identity:
        fail("restore cleanup directory identity changed")
    root_device = expected_identity[0]

    def remove_children(directory):
        with os.scandir(directory) as entries:
            children = list(entries)
        for entry in children:
            metadata = entry.stat(follow_symlinks=False)
            child_path = Path(directory) / entry.name
            if metadata.st_dev != root_device:
                fail("restore cleanup encountered a filesystem boundary")
            if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
                child_identity = (metadata.st_dev, metadata.st_ino)
                remove_children(child_path)
                if directory_identity(child_path) != child_identity:
                    fail("restore cleanup child directory identity changed")
                os.rmdir(child_path)
            elif stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
                os.unlink(child_path)
            else:
                fail("restore cleanup encountered a special node")

    remove_children(path)
    if directory_identity(path) != expected_identity:
        fail("restore cleanup root directory identity changed")
    os.rmdir(path)


def live_tree_inventory(root):
    require_real_directory(root)
    root_device, _ = directory_identity(root)
    directories = set()
    files = {}

    def inspect(directory, relative_parent):
        with os.scandir(directory) as entries:
            children = sorted(entries, key=lambda entry: entry.name)
        for entry in children:
            if any(unicodedata.category(character).startswith("C") for character in entry.name):
                fail("restored live tree contains control characters in a name")
            metadata = entry.stat(follow_symlinks=False)
            if metadata.st_dev != root_device:
                fail("restored live tree crosses a filesystem boundary")
            relative = relative_parent / entry.name
            relative_name = relative.as_posix()
            path = Path(directory) / entry.name
            if stat.S_ISDIR(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
                directories.add(relative_name)
                inspect(path, relative)
            elif stat.S_ISREG(metadata.st_mode) and not stat.S_ISLNK(metadata.st_mode):
                files[relative_name] = (metadata.st_size, sha256_file(path))
            else:
                fail("restored live tree contains links or special nodes")

    inspect(root, PurePosixPath("."))
    return directories, files


def prepare_empty_file_trees(site, bundle_id):
    site_root = SITES_ROOT / site
    config_live = site_root / "site_config.json"
    public_parent = site_root / "public"
    private_parent = site_root / "private"
    public_live = public_parent / "files"
    private_live = private_parent / "files"
    for directory in (site_root, public_parent, private_parent, public_live, private_live):
        require_real_directory(directory)
    site_device, _ = directory_identity(site_root)
    if any(directory_identity(path)[0] != site_device for path in (public_parent, private_parent, public_live, private_live)):
        fail("site file trees are not on one filesystem")
    parse_site_config(config_live, exact_mode=0o600)
    config_old_identity = regular_file_identity(config_live)
    if config_old_identity[0] != site_device:
        fail("site configuration is not on the site filesystem")
    config_old_digest = sha256_file(config_live, exact_mode=0o600)

    quarantine = site_root / f".erpnext-site-restore-quarantine.{bundle_id}"
    public_replacement = public_parent / f".files.erpnext-site-replacement.{bundle_id}"
    private_replacement = private_parent / f".files.erpnext-site-replacement.{bundle_id}"
    for path in (quarantine, public_replacement, private_replacement):
        if os.path.lexists(path):
            fail("restore quarantine or replacement path already exists")

    public_mode = stat.S_IMODE(os.lstat(public_live).st_mode)
    private_mode = stat.S_IMODE(os.lstat(private_live).st_mode)
    os.mkdir(quarantine, 0o700)
    quarantine_identity = directory_identity(quarantine)
    try:
        os.mkdir(public_replacement, public_mode)
        os.mkdir(private_replacement, private_mode)
    except BaseException:
        try:
            if os.path.lexists(public_replacement):
                remove_proven_directory(public_replacement, directory_identity(public_replacement))
            if os.path.lexists(private_replacement):
                remove_proven_directory(private_replacement, directory_identity(private_replacement))
            os.rmdir(quarantine)
        finally:
            raise

    state = {
        "site_root": site_root,
        "quarantine": quarantine,
        "quarantine_identity": quarantine_identity,
        "config_live": config_live,
        "config_old": quarantine / "site_config.original.json",
        "config_old_identity": config_old_identity,
        "config_old_digest": config_old_digest,
        "config_old_moved": False,
        "config_new_live": False,
        "public_live": public_live,
        "private_live": private_live,
        "public_replacement": public_replacement,
        "private_replacement": private_replacement,
        "public_replacement_identity": directory_identity(public_replacement),
        "private_replacement_identity": directory_identity(private_replacement),
        "public_old": quarantine / "public-files",
        "private_old": quarantine / "private-files",
        "public_old_identity": directory_identity(public_live),
        "private_old_identity": directory_identity(private_live),
        "public_old_moved": False,
        "public_new_live": False,
        "private_old_moved": False,
        "private_new_live": False,
    }
    try:
        os.rename(public_live, state["public_old"])
        state["public_old_moved"] = True
        os.rename(public_replacement, public_live)
        state["public_new_live"] = True
        os.rename(private_live, state["private_old"])
        state["private_old_moved"] = True
        os.rename(private_replacement, private_live)
        state["private_new_live"] = True
        fsync_directory(public_parent)
        fsync_directory(private_parent)
        fsync_directory(site_root)
    except BaseException:
        rollback_file_trees(state)
        raise
    return state


def rollback_site_config(state):
    if not state["config_old_moved"]:
        return
    original = state["config_old"]
    target = state["config_live"]
    if regular_file_identity(original) != state["config_old_identity"]:
        fail("restore rollback site-configuration identity changed")
    if sha256_file(original, exact_mode=0o600) != state["config_old_digest"]:
        fail("restore rollback site-configuration bytes changed")
    if os.path.lexists(target):
        target_metadata = os.lstat(target)
        if not stat.S_ISREG(target_metadata.st_mode) or stat.S_ISLNK(target_metadata.st_mode):
            fail("restore rollback site-configuration destination is unsafe")
        if target_metadata.st_dev != state["config_old_identity"][0]:
            fail("restore rollback site-configuration destination crossed a filesystem boundary")
    os.replace(original, target)
    state["config_old_moved"] = False
    state["config_new_live"] = False
    if regular_file_identity(target) != state["config_old_identity"]:
        fail("restored original site-configuration identity changed")
    if sha256_file(target, exact_mode=0o600) != state["config_old_digest"]:
        fail("restored original site-configuration bytes changed")
    fsync_directory(state["site_root"])


def rollback_file_trees(state):
    for prefix in ("private", "public"):
        live = state[f"{prefix}_live"]
        old = state[f"{prefix}_old"]
        replacement = state[f"{prefix}_replacement"]
        if state[f"{prefix}_new_live"]:
            remove_proven_directory(live, state[f"{prefix}_replacement_identity"])
            state[f"{prefix}_new_live"] = False
        elif os.path.lexists(replacement):
            remove_proven_directory(replacement, state[f"{prefix}_replacement_identity"])
        if state[f"{prefix}_old_moved"]:
            if os.path.lexists(live):
                fail("restore rollback live-tree destination is unexpectedly occupied")
            if directory_identity(old) != state[f"{prefix}_old_identity"]:
                fail("restore rollback quarantine identity changed")
            os.rename(old, live)
            state[f"{prefix}_old_moved"] = False
    if os.path.lexists(state["quarantine"]):
        if directory_identity(state["quarantine"]) != state["quarantine_identity"]:
            fail("restore quarantine identity changed during rollback")
        os.rmdir(state["quarantine"])
    fsync_directory(state["site_root"])


def commit_site_config_replacement(state):
    if not state["config_old_moved"]:
        fail("site-configuration replacement was not prepared for commit")
    original = state["config_old"]
    if regular_file_identity(original) != state["config_old_identity"]:
        fail("quarantined original site-configuration identity changed before commit")
    if sha256_file(original, exact_mode=0o600) != state["config_old_digest"]:
        fail("quarantined original site-configuration bytes changed before commit")
    os.unlink(original)
    state["config_old_moved"] = False
    fsync_directory(state["quarantine"])


def verify_restored_file_trees(state, public_archive, private_archive):
    expected_public = validate_file_archive(public_archive, "public", exact_mode=0o600)
    expected_private = validate_file_archive(private_archive, "private", exact_mode=0o600)
    actual_public = live_tree_inventory(state["public_live"])
    actual_private = live_tree_inventory(state["private_live"])
    if actual_public != expected_public or actual_private != expected_private:
        fail("restored live file trees do not exactly match the selected archives")


def commit_file_tree_replacement(state):
    if directory_identity(state["public_live"]) != state["public_replacement_identity"]:
        fail("restored public files tree identity changed before commit")
    if directory_identity(state["private_live"]) != state["private_replacement_identity"]:
        fail("restored private files tree identity changed before commit")
    commit_site_config_replacement(state)
    remove_proven_directory(state["private_old"], state["private_old_identity"])
    state["private_old_moved"] = False
    remove_proven_directory(state["public_old"], state["public_old_identity"])
    state["public_old_moved"] = False
    if directory_identity(state["quarantine"]) != state["quarantine_identity"]:
        fail("restore quarantine identity changed before final cleanup")
    os.rmdir(state["quarantine"])
    fsync_directory(state["site_root"])


def require_vendor_copy_destinations_absent(site_root, archives):
    for archive in archives:
        destination = site_root / archive.name
        if os.path.lexists(destination):
            fail("vendor restore archive-copy destination is already occupied")


def cleanup_vendor_archive_copies(site_root, archives):
    changed = False
    for archive in archives:
        destination = site_root / archive.name
        if not os.path.lexists(destination):
            continue
        metadata = os.lstat(destination)
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            fail("vendor restore left an unsafe archive-copy destination")
        if sha256_file(destination) != sha256_file(archive, exact_mode=0o600):
            fail("vendor restore archive copy does not match the selected bundle")
        os.unlink(destination)
        changed = True
    if changed:
        fsync_directory(site_root)


def restore_bundle(
    bundle_value,
    bundle_id,
    site,
    secret_file,
    application_secret_file,
):
    bundle = Path(bundle_value)
    manifest, expected_config = verify_bundle(bundle, bundle_id, site)
    config_path = bundle / manifest["SITE_CONFIG_FILE"]
    expected_config, config_payload = parse_site_config(config_path, exact_mode=0o600)
    public_archive = bundle / manifest["PUBLIC_FILES_FILE"]
    private_archive = bundle / manifest["PRIVATE_FILES_FILE"]
    site_root = SITES_ROOT / site
    require_vendor_copy_destinations_absent(site_root, (public_archive, private_archive))
    deployment_password = read_secret(
        application_secret_file,
        "Current MariaDB application secret",
    )
    if not secrets.compare_digest(deployment_password, expected_config["db_password"]):
        fail(
            "Selected bundle database credential does not match the current deployment secret"
        )
    deployment_password = None
    root_password = read_secret(secret_file, "MariaDB root secret")
    previous_directory = Path.cwd()
    file_state = None
    # Mirror Bench v16's sites working directory so vendor log pæths resolve
    # to the shæred bench logs volume insteæd of /home/frappe/logs.
    os.chdir(SITES_ROOT)
    try:
        file_state = prepare_empty_file_trees(site, bundle_id)
        try:
            write_live_site_config(file_state, config_payload, expected_config)
            import frappe
            import frappe.database
            import frappe.database.db_manager as frappe_database_manager
            import frappe.utils as frappe_utils
            from frappe.commands.site import _restore
            from frappe.database.database import DDL_QUERY_TYPES, Database
            from frappe.utils.logger import set_log_level
            from frappe.utils.synchronization import filelock

            frappe.init(site, sites_path=str(SITES_ROOT))
            expected_user = expected_config.get("db_user", expected_config["db_name"])
            expected_host = expected_config.get("db_host")
            expected_port = expected_config.get("db_port", 3306)
            expected_runtime_config = {
                "db_name": expected_config["db_name"],
                "db_user": expected_user,
                "db_host": expected_host,
                "db_port": expected_port,
                "db_socket": expected_config.get("db_socket"),
                "db_type": "mariadb",
                "db_password": expected_config["db_password"],
            }
            if any(
                frappe.conf.get(key) != value
                for key, value in expected_runtime_config.items()
            ):
                fail("Frappe runtime database topology does not match the selected bundle")
            expected_command = {
                "socket": frappe.conf.get("db_socket"),
                "host": frappe.conf.get("db_host"),
                "port": frappe.conf.get("db_port"),
                "user": frappe.conf.get("db_user"),
                "db_name": frappe.conf.get("db_name"),
                "extra": None,
                "dump": False,
            }
            # Keep ERROR æs defense-in-depth. The bounded guærd below suppresses
            # secret-beæring DDL before Fræppe's forced WARNING logger sees it.
            set_log_level("ERROR")
            with filelock("site_restore", timeout=1):
                # Fræppe's vendor restore destructively replæces the dætæbæse ænd
                # cænnot provide æ cross-filesystem trænsæction. The controller
                # cæn roll bæck its own pre-dætæbæse config/file mutætions, but æ
                # fæiled dætæbæse replæcement still requires the documented
                # dætæbæse recovery source or hypervisor snæpshot.
                database_path = bundle / manifest["DATABASE_FILE"]
                with guarded_mariadb_vendor_restore(
                    frappe.database,
                    frappe_database_manager,
                    frappe_utils,
                    Database,
                    DDL_QUERY_TYPES,
                    expected_command,
                    expected_config["db_password"],
                    root_password,
                    database_path,
                ):
                    _restore(
                        site=site,
                        sql_file_path=str(database_path),
                        db_root_username="root",
                        db_root_password=root_password,
                        force=False,
                        with_public_files=str(public_archive),
                        with_private_files=str(private_archive),
                    )
            cleanup_vendor_archive_copies(site_root, (public_archive, private_archive))
            verify_restored_file_trees(file_state, public_archive, private_archive)
            restored_config, _ = parse_site_config(
                site_root / "site_config.json", exact_mode=0o600
            )
            for key in ("db_name", "db_password", "db_type", "encryption_key"):
                if restored_config.get(key) != expected_config.get(key):
                    fail("restored site configuration no longer matches its bundle")
        except BaseException as restore_error:
            rollback_errors = []
            try:
                cleanup_vendor_archive_copies(site_root, (public_archive, private_archive))
            except Exception as cleanup_error:
                rollback_errors.append(cleanup_error)
            try:
                if file_state is not None:
                    rollback_site_config(file_state)
            except Exception as rollback_error:
                rollback_errors.append(rollback_error)
            try:
                if file_state is not None:
                    rollback_file_trees(file_state)
            except Exception as rollback_error:
                rollback_errors.append(rollback_error)
            if rollback_errors:
                raise RuntimeError(
                    "ERPNext restore failed and exact config/file-tree rollback or cleanup also failed"
                ) from restore_error
            raise
        commit_file_tree_replacement(file_state)
    finally:
        root_password = None
        try:
            import frappe

            frappe.destroy()
        except Exception:
            pass
        os.chdir(previous_directory)


def build_parser():
    parser = argparse.ArgumentParser(prog="erpnext-site-restore.py")
    subparsers = parser.add_subparsers(dest="operation", required=True)

    artifacts = subparsers.add_parser("verify-artifacts")
    artifacts.add_argument("--site", required=True)
    artifacts.add_argument("--database", required=True)
    artifacts.add_argument("--site-config", required=True)
    artifacts.add_argument("--public-files", required=True)
    artifacts.add_argument("--private-files", required=True)

    for operation in ("verify-bundle", "publish", "restore"):
        command = subparsers.add_parser(operation)
        command.add_argument("--bundle-id", required=True)
        command.add_argument("--site", required=True)
        if operation == "verify-bundle":
            command.add_argument("--bundle", required=True)
        elif operation == "publish":
            command.add_argument("--source", required=True)
            command.add_argument("--destination", required=True)
        else:
            command.add_argument("--bundle", required=True)
            command.add_argument("--secret-file", required=True)
            command.add_argument("--application-secret-file", required=True)
    return parser


def main():
    os.umask(0o077)
    arguments = build_parser().parse_args()
    if arguments.operation == "verify-artifacts":
        verify_artifacts(
            arguments.site,
            arguments.database,
            arguments.site_config,
            arguments.public_files,
            arguments.private_files,
        )
    elif arguments.operation == "verify-bundle":
        verify_bundle(arguments.bundle, arguments.bundle_id, arguments.site)
    elif arguments.operation == "publish":
        publish_bundle(
            arguments.source,
            arguments.destination,
            arguments.bundle_id,
            arguments.site,
        )
    elif arguments.operation == "restore":
        restore_bundle(
            arguments.bundle,
            arguments.bundle_id,
            arguments.site,
            arguments.secret_file,
            arguments.application_secret_file,
        )
    else:
        fail("unsupported helper operation")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[erpnext-site-maintenance] ERROR: {error}", file=os.sys.stderr)
        raise SystemExit(1) from None
