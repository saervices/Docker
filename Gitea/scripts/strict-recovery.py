#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

"""Creæte, vælidæte, stæge, ænd ætomicælly switch strict recovery ærchives."""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import secrets
import signal
import stat
import sys
import tarfile
from dataclasses import asdict, dataclass, fields
from pathlib import Path, PurePosixPath
from typing import BinaryIO


MAXIMUM_MEMBERS = 2_000_000
MAXIMUM_PAYLOAD_BYTES = 8 * 1024**4
READ_BUFFER_BYTES = 1024 * 1024
EXPECTED_ROOT = Path(__file__).resolve().parent.parent.name
AT_FDCWD = -100
RENAME_NOREPLACE = 1
RENAME_EXCHANGE = 2
MAXIMUM_JOURNAL_BYTES = 64 * 1024
MAXIMUM_MANIFEST_BYTES = 1024 * 1024
MANIFEST_NAME = "SHA256SUMS"
COMPLETION_MARKER_NAME = "RECOVERY_COMPLETE"
COMPLETION_SCHEMA = "strict-recovery-bundle-v1"
LIBC = ctypes.CDLL(None, use_errno=True)


class RecoveryError(RuntimeError):
    """Æ fæil-closed recovery contræct violætion."""


@dataclass(frozen=True)
class Identity:
    device: int
    inode: int
    mode: int
    links: int
    size: int
    uid: int
    gid: int
    mtime_ns: int
    ctime_ns: int


def identity(value: os.stat_result) -> Identity:
    return Identity(
        device=value.st_dev,
        inode=value.st_ino,
        mode=value.st_mode,
        links=value.st_nlink,
        size=value.st_size,
        uid=value.st_uid,
        gid=value.st_gid,
        mtime_ns=value.st_mtime_ns,
        ctime_ns=value.st_ctime_ns,
    )


def same_node(left: Identity, right: Identity) -> bool:
    return (
        left.device == right.device
        and left.inode == right.inode
        and left.mode == right.mode
        and left.uid == right.uid
        and left.gid == right.gid
    )


def identity_payload(value: Identity) -> dict[str, int]:
    return {key: int(item) for key, item in asdict(value).items()}


def identity_from_payload(value: object) -> Identity:
    expected_keys = {field.name for field in fields(Identity)}
    if not isinstance(value, dict) or set(value) != expected_keys:
        raise RecoveryError("recovery journal contains an invalid identity")
    if any(type(value[key]) is not int or value[key] < 0 for key in expected_keys):
        raise RecoveryError("recovery journal identity values must be non-negative integers")
    return Identity(**{key: value[key] for key in expected_keys})


def lstat_identity(path: Path) -> Identity:
    try:
        return identity(path.lstat())
    except OSError as error:
        raise RecoveryError(f"cannot inspect {path}") from error


def require_plain_directory(path: Path) -> Identity:
    value = lstat_identity(path)
    if not stat.S_ISDIR(value.mode):
        raise RecoveryError(f"required directory is not a plain directory: {path}")
    return value


def require_regular_single_link(path: Path) -> Identity:
    value = lstat_identity(path)
    if not stat.S_ISREG(value.mode) or value.links != 1:
        raise RecoveryError(f"required file is not a single-link regular file: {path}")
    return value


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def archive_name(relative: PurePosixPath) -> str:
    if str(relative) == ".":
        return EXPECTED_ROOT
    return f"{EXPECTED_ROOT}/{relative.as_posix()}"


def source_inventory(source_root: Path) -> dict[PurePosixPath, Identity]:
    root_identity = require_plain_directory(source_root)
    inventory: dict[PurePosixPath, Identity] = {PurePosixPath("."): root_identity}
    pending = [source_root]
    while pending:
        directory = pending.pop()
        try:
            children = sorted(os.scandir(directory), key=lambda child: child.name)
        except OSError as error:
            raise RecoveryError(f"cannot inventory {directory}") from error
        for child in children:
            child_path = Path(child.path)
            relative = PurePosixPath(child_path.relative_to(source_root).as_posix())
            value = lstat_identity(child_path)
            if stat.S_ISDIR(value.mode):
                pending.append(child_path)
            elif stat.S_ISREG(value.mode):
                if value.links != 1:
                    raise RecoveryError(f"hard-linked source file is forbidden: {child_path}")
            else:
                raise RecoveryError(f"link or special source node is forbidden: {child_path}")
            if value.mode & 0o7000:
                raise RecoveryError(f"set-id or sticky source mode is forbidden: {child_path}")
            inventory[relative] = value
            if len(inventory) > MAXIMUM_MEMBERS:
                raise RecoveryError("source member count exceeds the safety limit")
    return inventory


class StableFile(BinaryIO):
    """Æ descriptor-bound reæder thæt verifies identity æfter tær consumed it."""

    def __init__(self, path: Path, expected: Identity) -> None:
        self._path = path
        self._expected = expected
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
        try:
            descriptor = os.open(path, flags)
        except OSError as error:
            raise RecoveryError(f"cannot safely open source file: {path}") from error
        self._file = os.fdopen(descriptor, "rb", buffering=0)
        if identity(os.fstat(descriptor)) != expected:
            self._file.close()
            raise RecoveryError(f"source file changed while opening: {path}")

    def read(self, size: int = -1) -> bytes:
        return self._file.read(size)

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return False

    def close_and_verify(self) -> None:
        descriptor = self._file.fileno()
        opened_after = identity(os.fstat(descriptor))
        path_after = lstat_identity(self._path)
        self._file.close()
        if opened_after != self._expected or path_after != self._expected:
            raise RecoveryError(f"source file changed while archiving: {self._path}")


def tar_info(relative: PurePosixPath, value: Identity) -> tarfile.TarInfo:
    member = tarfile.TarInfo(archive_name(relative))
    member.mode = stat.S_IMODE(value.mode)
    member.uid = value.uid
    member.gid = value.gid
    member.uname = ""
    member.gname = ""
    member.mtime = value.mtime_ns // 1_000_000_000
    member.pax_headers = {"mtime": f"{value.mtime_ns / 1_000_000_000:.9f}"}
    if stat.S_ISDIR(value.mode):
        member.type = tarfile.DIRTYPE
        member.size = 0
    else:
        member.type = tarfile.REGTYPE
        member.size = value.size
    return member


def validate_member_name(name: str) -> PurePosixPath:
    if (
        not name
        or "\\" in name
        or "\x00" in name
        or name.startswith("/")
        or name.endswith("/")
        or "//" in name
        or any(part in ("", ".", "..") for part in name.split("/"))
    ):
        raise RecoveryError("archive contains an invalid member name")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise RecoveryError(f"archive path traversal is forbidden: {name!r}")
    if not path.parts or path.parts[0] != EXPECTED_ROOT:
        raise RecoveryError(f"archive member is outside the {EXPECTED_ROOT} root: {name!r}")
    return path


def validate_archive(archive_path: Path) -> list[tarfile.TarInfo]:
    archive_identity = require_regular_single_link(archive_path)
    members: list[tarfile.TarInfo] = []
    normalized_names: set[PurePosixPath] = set()
    payload_bytes = 0
    try:
        descriptor = os.open(
            archive_path,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
        )
        with os.fdopen(descriptor, "rb", buffering=0) as archive_file:
            if identity(os.fstat(descriptor)) != archive_identity:
                raise RecoveryError("archive changed while opening")
            with tarfile.open(fileobj=archive_file, mode="r:") as archive:
                for member in archive:
                    normalized = validate_member_name(member.name)
                    if normalized in normalized_names:
                        raise RecoveryError(f"archive contains a duplicate member: {member.name!r}")
                    normalized_names.add(normalized)
                    if not (member.isdir() or member.isreg()):
                        raise RecoveryError(f"archive links and special nodes are forbidden: {member.name!r}")
                    if member.isdir() and member.size != 0:
                        raise RecoveryError(f"archive directory has a payload: {member.name!r}")
                    if member.mode & 0o7000:
                        raise RecoveryError(f"archive set-id or sticky mode is forbidden: {member.name!r}")
                    if member.size < 0:
                        raise RecoveryError(f"archive contains a negative member size: {member.name!r}")
                    payload_bytes += member.size
                    if payload_bytes > MAXIMUM_PAYLOAD_BYTES:
                        raise RecoveryError("archive payload exceeds the safety limit")
                    members.append(member)
                    if len(members) > MAXIMUM_MEMBERS:
                        raise RecoveryError("archive member count exceeds the safety limit")
            if identity(os.fstat(descriptor)) != archive_identity:
                raise RecoveryError("archive changed while validating")
    except (OSError, tarfile.TarError) as error:
        raise RecoveryError("archive cannot be parsed completely") from error
    root = PurePosixPath(EXPECTED_ROOT)
    if root not in normalized_names:
        raise RecoveryError(f"archive does not contain the required {EXPECTED_ROOT} root")
    root_member = next(member for member in members if PurePosixPath(member.name) == root)
    if not root_member.isdir():
        raise RecoveryError(f"archive root {EXPECTED_ROOT} is not a directory")
    if lstat_identity(archive_path) != archive_identity:
        raise RecoveryError("archive path changed while validating")
    return members


def validate_volume_member_name(name: str) -> PurePosixPath:
    if name == ".":
        return PurePosixPath(".")
    if not name.startswith("./"):
        raise RecoveryError(f"volume archive member lacks the required dot root: {name!r}")
    relative = name[2:]
    if (
        not relative
        or "\\" in relative
        or "\x00" in relative
        or relative.startswith("/")
        or relative.endswith("/")
        or "//" in relative
        or any(part in ("", ".", "..") for part in relative.split("/"))
    ):
        raise RecoveryError(f"volume archive contains an invalid member name: {name!r}")
    return PurePosixPath(relative)


def validate_volume_archive(archive_path: Path) -> list[tarfile.TarInfo]:
    archive_identity = require_regular_single_link(archive_path)
    members: list[tarfile.TarInfo] = []
    normalized_names: set[PurePosixPath] = set()
    payload_bytes = 0
    try:
        descriptor = os.open(
            archive_path,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
        )
        with os.fdopen(descriptor, "rb", buffering=0) as archive_file:
            if identity(os.fstat(descriptor)) != archive_identity:
                raise RecoveryError("volume archive changed while opening")
            with tarfile.open(fileobj=archive_file, mode="r:") as archive:
                for member in archive:
                    normalized = validate_volume_member_name(member.name)
                    if normalized in normalized_names:
                        raise RecoveryError(f"volume archive contains a duplicate member: {member.name!r}")
                    normalized_names.add(normalized)
                    if not (member.isdir() or member.isreg()):
                        raise RecoveryError(f"volume archive links and special nodes are forbidden: {member.name!r}")
                    if member.isdir() and member.size != 0:
                        raise RecoveryError(f"volume archive directory has a payload: {member.name!r}")
                    if member.mode & 0o7000:
                        raise RecoveryError(f"volume archive set-id or sticky mode is forbidden: {member.name!r}")
                    if member.size < 0:
                        raise RecoveryError(f"volume archive contains a negative member size: {member.name!r}")
                    payload_bytes += member.size
                    if payload_bytes > MAXIMUM_PAYLOAD_BYTES:
                        raise RecoveryError("volume archive payload exceeds the safety limit")
                    members.append(member)
                    if len(members) > MAXIMUM_MEMBERS:
                        raise RecoveryError("volume archive member count exceeds the safety limit")
            if identity(os.fstat(descriptor)) != archive_identity:
                raise RecoveryError("volume archive changed while validating")
    except (OSError, tarfile.TarError) as error:
        raise RecoveryError("volume archive cannot be parsed completely") from error
    if PurePosixPath(".") not in normalized_names:
        raise RecoveryError("volume archive does not contain the required dot root")
    root_member = next(member for member in members if member.name == ".")
    if not root_member.isdir():
        raise RecoveryError("volume archive dot root is not a directory")
    if lstat_identity(archive_path) != archive_identity:
        raise RecoveryError("volume archive path changed while validating")
    return members


def create_archive(source_root: Path, archive_path: Path) -> None:
    require_plain_directory(source_root)
    source_root = source_root.resolve(strict=True)
    if source_root.name != EXPECTED_ROOT:
        raise RecoveryError(f"source root basename must be exactly {EXPECTED_ROOT}")
    if archive_path.exists() or archive_path.is_symlink():
        raise RecoveryError(f"archive destination already exists: {archive_path}")
    archive_parent = archive_path.parent.resolve(strict=True)
    require_plain_directory(archive_parent)
    before = source_inventory(source_root)
    total_payload = sum(value.size for value in before.values() if stat.S_ISREG(value.mode))
    if total_payload > MAXIMUM_PAYLOAD_BYTES:
        raise RecoveryError("source payload exceeds the safety limit")
    temporary = archive_parent / f".{archive_path.name}.partial.{os.getpid()}.{secrets.token_hex(8)}"
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            with tarfile.open(fileobj=output, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for relative in sorted(before, key=lambda item: item.parts):
                    value = before[relative]
                    member = tar_info(relative, value)
                    if stat.S_ISDIR(value.mode):
                        archive.addfile(member)
                        continue
                    source_path = source_root / Path(relative.as_posix())
                    opened = StableFile(source_path, value)
                    try:
                        archive.addfile(member, opened)
                    finally:
                        opened.close_and_verify()
            output.flush()
            os.fsync(output.fileno())
        if source_inventory(source_root) != before:
            raise RecoveryError("source tree changed while the archive was created")
        validate_archive(temporary)
        try:
            os.link(temporary, archive_path, follow_symlinks=False)
        except OSError as error:
            raise RecoveryError(f"cannot publish archive without clobbering: {archive_path}") from error
        os.unlink(temporary)
        fsync_directory(archive_parent)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def safe_output_path(stage_root: Path, member_name: str) -> Path:
    normalized = validate_member_name(member_name)
    relative_parts = normalized.parts[1:]
    destination = stage_root.joinpath(*relative_parts)
    if destination != stage_root and stage_root not in destination.parents:
        raise RecoveryError(f"archive destination escaped the stage: {member_name!r}")
    return destination


def require_safe_parent(stage_root: Path, destination: Path) -> None:
    current = stage_root
    for part in destination.relative_to(stage_root).parts[:-1]:
        current /= part
        if current.exists() or current.is_symlink():
            require_plain_directory(current)
        else:
            current.mkdir(mode=0o700)


def apply_metadata(path: Path, member: tarfile.TarInfo) -> None:
    if os.geteuid() == 0:
        os.chown(path, member.uid, member.gid, follow_symlinks=False)
    elif member.uid != os.geteuid() or member.gid != os.getegid():
        raise RecoveryError("root is required to preserve archive ownership")
    os.chmod(path, member.mode & 0o777, follow_symlinks=False)
    timestamp_ns = int(float(member.pax_headers.get("mtime", str(member.mtime))) * 1_000_000_000)
    os.utime(path, ns=(timestamp_ns, timestamp_ns), follow_symlinks=False)


def fsync_staged_file(path: Path, member: tarfile.TarInfo) -> None:
    before = require_regular_single_link(path)
    if (
        before.size != member.size
        or stat.S_IMODE(before.mode) != (member.mode & 0o777)
        or before.uid != member.uid
        or before.gid != member.gid
    ):
        raise RecoveryError(f"staged file metadata does not match the archive: {path}")
    descriptor = os.open(
        path,
        os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
    )
    try:
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError(f"staged file changed while opening for fsync: {path}")
        os.fsync(descriptor)
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError(f"staged file changed while fsyncing: {path}")
    finally:
        os.close(descriptor)
    if lstat_identity(path) != before:
        raise RecoveryError(f"staged file path changed while fsyncing: {path}")


def stage_archive(archive_path: Path, stage_root: Path) -> None:
    archive_path = archive_path.resolve(strict=True)
    if stage_root.exists() or stage_root.is_symlink():
        raise RecoveryError(f"stage destination already exists: {stage_root}")
    stage_parent = stage_root.parent.resolve(strict=True)
    require_plain_directory(stage_parent)
    archive_identity = require_regular_single_link(archive_path)
    members = validate_archive(archive_path)
    stage_root.mkdir(mode=0o700)
    completed = False
    try:
        descriptor = os.open(
            archive_path,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
        )
        with os.fdopen(descriptor, "rb", buffering=0) as archive_file:
            if identity(os.fstat(descriptor)) != archive_identity:
                raise RecoveryError("archive changed between validation and staging")
            with tarfile.open(fileobj=archive_file, mode="r:") as archive:
                for member in members:
                    destination = safe_output_path(stage_root, member.name)
                    if destination == stage_root:
                        continue
                    require_safe_parent(stage_root, destination)
                    if member.isdir():
                        if destination.exists() or destination.is_symlink():
                            require_plain_directory(destination)
                        else:
                            destination.mkdir(mode=0o700)
                        continue
                    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC
                    output_descriptor = os.open(destination, flags, 0o600)
                    extracted = archive.extractfile(member)
                    if extracted is None:
                        os.close(output_descriptor)
                        raise RecoveryError(f"regular member has no payload: {member.name!r}")
                    written = 0
                    with os.fdopen(output_descriptor, "wb", buffering=0) as output:
                        while True:
                            chunk = extracted.read(READ_BUFFER_BYTES)
                            if not chunk:
                                break
                            output.write(chunk)
                            written += len(chunk)
                        os.fsync(output.fileno())
                    if written != member.size:
                        raise RecoveryError(f"archive member size changed while extracting: {member.name!r}")
                    apply_metadata(destination, member)
                    fsync_staged_file(destination, member)
            if identity(os.fstat(descriptor)) != archive_identity:
                raise RecoveryError("archive changed while staging")
        directories = [member for member in members if member.isdir()]
        for member in sorted(directories, key=lambda item: len(PurePosixPath(item.name).parts), reverse=True):
            destination = safe_output_path(stage_root, member.name)
            if destination != stage_root:
                apply_metadata(destination, member)
        root_member = next(member for member in members if PurePosixPath(member.name) == PurePosixPath(EXPECTED_ROOT))
        apply_metadata(stage_root, root_member)
        staged_inventory = source_inventory(stage_root)
        expected_paths = {
            PurePosixPath(".")
            if PurePosixPath(member.name) == PurePosixPath(EXPECTED_ROOT)
            else PurePosixPath(*PurePosixPath(member.name).parts[1:])
            for member in members
        }
        if set(staged_inventory) != expected_paths:
            raise RecoveryError("staged tree does not match the validated archive inventory")
        if lstat_identity(archive_path) != archive_identity:
            raise RecoveryError("archive path changed while staging")
        for relative, value in staged_inventory.items():
            if stat.S_ISDIR(value.mode):
                destination = stage_root if str(relative) == "." else stage_root / Path(relative.as_posix())
                fsync_directory(destination)
        fsync_directory(stage_root)
        fsync_directory(stage_parent)
        completed = True
    finally:
        if not completed:
            raise RecoveryError(f"staging failed; inspect and remove the incomplete private stage: {stage_root}")


def renameat2(source: Path, destination: Path, flags: int) -> None:
    function = getattr(LIBC, "renameat2", None)
    if function is None:
        raise RecoveryError("libc renameat2 is unavailable; refusing a non-atomic root switch")
    function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    function.restype = ctypes.c_int
    result = function(
        AT_FDCWD,
        os.fsencode(source),
        AT_FDCWD,
        os.fsencode(destination),
        flags,
    )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number), f"{source} -> {destination}")


def exchange_paths(left: Path, right: Path) -> None:
    renameat2(left, right, RENAME_EXCHANGE)


def rename_no_replace(source: Path, destination: Path) -> None:
    renameat2(source, destination, RENAME_NOREPLACE)


def read_stable_file(path: Path, maximum_bytes: int) -> tuple[bytes, Identity]:
    before = require_regular_single_link(path)
    if before.size < 1 or before.size > maximum_bytes:
        raise RecoveryError(f"required file has an invalid length: {path}")
    descriptor = os.open(
        path,
        os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
    )
    try:
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError(f"required file changed while opening: {path}")
        chunks: list[bytes] = []
        remaining = before.size
        while remaining:
            chunk = os.read(descriptor, min(READ_BUFFER_BYTES, remaining))
            if not chunk:
                raise RecoveryError(f"required file ended while reading: {path}")
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise RecoveryError(f"required file grew while reading: {path}")
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError(f"required file changed while reading: {path}")
    finally:
        os.close(descriptor)
    if lstat_identity(path) != before:
        raise RecoveryError(f"required file path changed while reading: {path}")
    return b"".join(chunks), before


def parse_checksum_manifest(payload: bytes) -> dict[str, str]:
    try:
        text = payload.decode("ascii", errors="strict")
    except UnicodeDecodeError as error:
        raise RecoveryError("checksum manifest is not strict ASCII") from error
    if not text.endswith("\n") or "\r" in text or "\x00" in text:
        raise RecoveryError("checksum manifest has invalid line framing")
    checksums: dict[str, str] = {}
    for line in text.splitlines():
        if len(line) < 67 or line[64:66] != "  ":
            raise RecoveryError("checksum manifest has an invalid record")
        digest, name = line[:64], line[66:]
        if (
            any(character not in "0123456789abcdef" for character in digest)
            or not name
            or len(name.encode("ascii", errors="strict")) > 255
            or name in (MANIFEST_NAME, COMPLETION_MARKER_NAME)
            or name.endswith(".partial")
            or any(character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" for character in name)
            or name in (".", "..")
            or name in checksums
        ):
            raise RecoveryError("checksum manifest contains an unsafe record")
        checksums[name] = digest
    if not checksums:
        raise RecoveryError("checksum manifest is empty")
    return checksums


def hash_stable_file(path: Path, expected_digest: str, durable: bool) -> None:
    before = require_regular_single_link(path)
    descriptor = os.open(
        path,
        os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
    )
    digest = hashlib.sha256()
    try:
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError(f"bundle file changed while opening: {path}")
        while True:
            chunk = os.read(descriptor, READ_BUFFER_BYTES)
            if not chunk:
                break
            digest.update(chunk)
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError(f"bundle file changed while hashing: {path}")
        if digest.hexdigest() != expected_digest:
            raise RecoveryError(f"bundle checksum mismatch: {path.name}")
        if durable:
            os.fsync(descriptor)
            if identity(os.fstat(descriptor)) != before:
                raise RecoveryError(f"bundle file changed while syncing: {path}")
    finally:
        os.close(descriptor)
    if lstat_identity(path) != before:
        raise RecoveryError(f"bundle file path changed while hashing: {path}")


def validate_bundle_inventory(
    bundle_root: Path, *, marker_required: bool, durable: bool
) -> tuple[bytes, Identity]:
    root_identity = require_plain_directory(bundle_root)
    if root_identity.uid != os.geteuid() or stat.S_IMODE(root_identity.mode) != 0o700:
        raise RecoveryError("bundle directory must be owned by the caller with mode 0700")
    inventory = source_inventory(bundle_root)
    if any(str(relative) != "." and len(relative.parts) != 1 for relative in inventory):
        raise RecoveryError("bundle must contain regular files in one flat directory")
    manifest_payload, manifest_identity = read_stable_file(
        bundle_root / MANIFEST_NAME, MAXIMUM_MANIFEST_BYTES
    )
    checksums = parse_checksum_manifest(manifest_payload)
    expected = {PurePosixPath("."), PurePosixPath(MANIFEST_NAME)}
    expected.update(PurePosixPath(name) for name in checksums)
    if marker_required:
        expected.add(PurePosixPath(COMPLETION_MARKER_NAME))
    if set(inventory) != expected:
        raise RecoveryError("bundle inventory does not exactly match its checksum manifest")
    for name, digest in checksums.items():
        hash_stable_file(bundle_root / name, digest, durable)
    if durable:
        descriptor = os.open(
            bundle_root / MANIFEST_NAME,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
        )
        try:
            if identity(os.fstat(descriptor)) != manifest_identity:
                raise RecoveryError("checksum manifest changed before syncing")
            os.fsync(descriptor)
            if identity(os.fstat(descriptor)) != manifest_identity:
                raise RecoveryError("checksum manifest changed while syncing")
        finally:
            os.close(descriptor)
        if lstat_identity(bundle_root / MANIFEST_NAME) != manifest_identity:
            raise RecoveryError("checksum manifest path changed while syncing")
    return manifest_payload, root_identity


def seal_bundle(stage_root: Path, final_root: Path) -> None:
    if not stage_root.is_absolute() or not final_root.is_absolute():
        raise RecoveryError("bundle stage and final paths must be absolute")
    parent = stage_root.parent.resolve(strict=True)
    if final_root.parent.resolve(strict=True) != parent:
        raise RecoveryError("bundle stage and final paths must be siblings")
    stage_root = parent / stage_root.name
    final_root = parent / final_root.name
    if final_root.name in ("", ".", "..") or final_root.name.endswith(".partial"):
        raise RecoveryError("final bundle name is invalid or reserved for an incomplete stage")
    if stage_root.name != f"{final_root.name}.partial":
        raise RecoveryError("bundle stage name must be the final name plus .partial")
    if final_root.exists() or final_root.is_symlink():
        raise RecoveryError(f"final bundle already exists: {final_root}")
    manifest_payload, stage_identity = validate_bundle_inventory(
        stage_root, marker_required=False, durable=True
    )
    marker = stage_root / COMPLETION_MARKER_NAME
    marker_payload = (
        f"{COMPLETION_SCHEMA} sha256:{hashlib.sha256(manifest_payload).hexdigest()}\n"
    ).encode("ascii")
    descriptor = os.open(
        marker,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
    )
    try:
        if os.write(descriptor, marker_payload) != len(marker_payload):
            raise RecoveryError("completion marker write was incomplete")
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    require_regular_single_link(marker)
    fsync_directory(stage_root)
    if not same_node(require_plain_directory(stage_root), stage_identity):
        raise RecoveryError("bundle stage changed before publication")
    try:
        rename_no_replace(stage_root, final_root)
    except OSError as error:
        raise RecoveryError("cannot publish bundle without replacing a destination") from error
    fsync_directory(parent)
    fsync_directory(final_root)
    verify_bundle(final_root)


def verify_bundle(bundle_root: Path) -> None:
    if not bundle_root.is_absolute() or bundle_root.name.endswith(".partial"):
        raise RecoveryError("only an absolute, published bundle path may be verified")
    manifest_payload, _root_identity = validate_bundle_inventory(
        bundle_root, marker_required=True, durable=False
    )
    marker_payload, _marker_identity = read_stable_file(
        bundle_root / COMPLETION_MARKER_NAME, 256
    )
    expected = (
        f"{COMPLETION_SCHEMA} sha256:{hashlib.sha256(manifest_payload).hexdigest()}\n"
    ).encode("ascii")
    if marker_payload != expected:
        raise RecoveryError("completion marker does not bind the checksum manifest")


def write_journal(path: Path, payload: dict[str, object]) -> None:
    if path.exists() or path.is_symlink():
        require_regular_single_link(path)
    temporary = path.with_name(
        f".{path.name}.partial.{os.getpid()}.{secrets.token_hex(8)}"
    )
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(payload, output, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def read_journal(path: Path) -> dict[str, object]:
    before = require_regular_single_link(path)
    if before.size < 1 or before.size > MAXIMUM_JOURNAL_BYTES:
        raise RecoveryError("recovery journal has an invalid length")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        if identity(os.fstat(descriptor)) != before:
            raise RecoveryError("recovery journal changed while opening")
        payload_bytes = os.read(descriptor, MAXIMUM_JOURNAL_BYTES + 1)
        if len(payload_bytes) != before.size or identity(os.fstat(descriptor)) != before:
            raise RecoveryError("recovery journal changed while reading")
    finally:
        os.close(descriptor)
    if lstat_identity(path) != before:
        raise RecoveryError("recovery journal path changed while reading")
    try:
        payload = json.loads(payload_bytes.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RecoveryError("recovery journal is not valid UTF-8 JSON") from error
    if not isinstance(payload, dict):
        raise RecoveryError("recovery journal root must be an object")
    return payload


def optional_directory_identity(path: Path) -> Identity | None:
    try:
        value = identity(path.lstat())
    except FileNotFoundError:
        return None
    except OSError as error:
        raise RecoveryError(f"cannot inspect recovery path {path}") from error
    if not stat.S_ISDIR(value.mode):
        raise RecoveryError(f"recovery path is not a plain directory: {path}")
    return value


def canonical_exchange_paths(
    stage_root: Path,
    live_root: Path,
    rollback_root: Path,
    journal: Path,
) -> tuple[Path, Path, Path, Path]:
    paths = (stage_root, live_root, rollback_root, journal)
    if any(not path.is_absolute() for path in paths):
        raise RecoveryError("recovery exchange paths must be absolute")
    try:
        parents = tuple(path.parent.resolve(strict=True) for path in paths)
    except OSError as error:
        raise RecoveryError("cannot resolve every recovery exchange parent") from error
    parent = parents[1]
    if any(candidate != parent for candidate in parents):
        raise RecoveryError("recovery exchange paths must be siblings")
    canonical = tuple(parent / path.name for path in paths)
    names = tuple(path.name for path in canonical)
    if any(name in ("", ".", "..") for name in names) or len(set(names)) != 4:
        raise RecoveryError("recovery exchange paths must be distinct siblings")
    return canonical


def journal_contract(
    payload: dict[str, object], journal: Path
) -> tuple[Path, Path, Path, Path, Identity, Identity]:
    if payload.get("schema") != "strict-recovery-root-exchange-v2":
        raise RecoveryError("unsupported recovery journal schema")
    path_keys = ("stage_root", "live_root", "rollback_root")
    if any(not isinstance(payload.get(key), str) for key in path_keys):
        raise RecoveryError("recovery journal paths are invalid")
    stage_root, live_root, rollback_root = (
        Path(str(payload[key])) for key in path_keys
    )
    stage_root, live_root, rollback_root, journal = canonical_exchange_paths(
        stage_root, live_root, rollback_root, journal
    )
    stage_identity = identity_from_payload(payload.get("stage_identity"))
    live_identity = identity_from_payload(payload.get("live_identity"))
    if stage_identity.device != live_identity.device:
        raise RecoveryError("recovery journal crosses filesystems")
    return stage_root, live_root, rollback_root, journal, stage_identity, live_identity


def exchange_state(
    stage_root: Path,
    live_root: Path,
    rollback_root: Path,
    stage_identity: Identity,
    live_identity: Identity,
) -> str:
    stage_now = optional_directory_identity(stage_root)
    live_now = optional_directory_identity(live_root)
    rollback_now = optional_directory_identity(rollback_root)
    if (
        stage_now is not None
        and live_now is not None
        and rollback_now is None
        and same_node(stage_now, stage_identity)
        and same_node(live_now, live_identity)
    ):
        return "prepared"
    if (
        stage_now is not None
        and live_now is not None
        and rollback_now is None
        and same_node(stage_now, live_identity)
        and same_node(live_now, stage_identity)
    ):
        return "exchanged"
    if (
        stage_now is None
        and live_now is not None
        and rollback_now is not None
        and same_node(live_now, stage_identity)
        and same_node(rollback_now, live_identity)
    ):
        return "committed"
    if (
        stage_now is None
        and live_now is not None
        and rollback_now is not None
        and same_node(live_now, live_identity)
        and same_node(rollback_now, stage_identity)
    ):
        return "rolled-back"
    raise RecoveryError("recovery paths do not match any journalled identity state")


def reconcile_exchange(journal: Path, action: str) -> str:
    payload = read_journal(journal)
    (
        stage_root,
        live_root,
        rollback_root,
        journal,
        stage_identity,
        live_identity,
    ) = journal_contract(payload, journal)
    state = exchange_state(
        stage_root, live_root, rollback_root, stage_identity, live_identity
    )
    parent = live_root.parent
    if action == "commit":
        if state == "prepared":
            exchange_paths(stage_root, live_root)
            fsync_directory(parent)
            state = "exchanged"
        if state == "exchanged":
            rename_no_replace(stage_root, rollback_root)
            fsync_directory(parent)
            state = "committed"
        elif state == "rolled-back":
            exchange_paths(live_root, rollback_root)
            fsync_directory(parent)
            state = "committed"
    elif action == "rollback":
        if state == "exchanged":
            exchange_paths(stage_root, live_root)
            fsync_directory(parent)
            state = "prepared"
        elif state == "committed":
            exchange_paths(live_root, rollback_root)
            fsync_directory(parent)
            state = "rolled-back"
        if state == "prepared":
            state = "rolled-back-before-commit"
    else:
        raise RecoveryError("recovery action must be commit or rollback")
    payload["status"] = state
    payload["last_action"] = action
    write_journal(journal, payload)
    return state


def swap_roots(stage_root: Path, live_root: Path, rollback_root: Path, journal: Path) -> None:
    stage_root, live_root, rollback_root, journal = canonical_exchange_paths(
        stage_root, live_root, rollback_root, journal
    )
    stage_identity = require_plain_directory(stage_root)
    live_identity = require_plain_directory(live_root)
    parent = live_root.parent
    if stage_identity.device != live_identity.device:
        raise RecoveryError("stage and live roots are not on the same filesystem")
    if rollback_root.exists() or rollback_root.is_symlink():
        raise RecoveryError(f"rollback destination already exists: {rollback_root}")
    if journal.exists() or journal.is_symlink():
        raise RecoveryError("journal must be a new sibling of the live root")

    old_handlers: dict[signal.Signals, object] = {}

    def interrupt_handler(signum: int, _frame: object) -> None:
        raise InterruptedError(f"received signal {signum}")

    payload = {
        "schema": "strict-recovery-root-exchange-v2",
        "status": "prepared",
        "live_root": str(live_root),
        "stage_root": str(stage_root),
        "rollback_root": str(rollback_root),
        "stage_identity": identity_payload(stage_identity),
        "live_identity": identity_payload(live_identity),
    }
    write_journal(journal, payload)
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        old_handlers[signum] = signal.signal(signum, interrupt_handler)
    try:
        payload["status"] = "exchanging"
        write_journal(journal, payload)
        exchange_paths(stage_root, live_root)
        fsync_directory(parent)
        payload["status"] = "exchanged"
        write_journal(journal, payload)
        rename_no_replace(stage_root, rollback_root)
        fsync_directory(parent)
        payload["status"] = "committed"
        write_journal(journal, payload)
    except BaseException as error:
        for signum in old_handlers:
            signal.signal(signum, signal.SIG_IGN)
        try:
            reconcile_exchange(journal, "rollback")
        except BaseException as rollback_error:
            raise RecoveryError(
                "root exchange failed and automatic rollback is incomplete; preserve the journal and run recover"
            ) from rollback_error
        raise RecoveryError("root exchange failed and was rolled back") from error
    finally:
        for signum, handler in old_handlers.items():
            signal.signal(signum, handler)


def parse_arguments(arguments: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="create a no-link deployment archive")
    create.add_argument("--source-root", type=Path, required=True)
    create.add_argument("--archive", type=Path, required=True)

    validate = subparsers.add_parser("validate", help="validate an archive without extracting")
    validate.add_argument("--archive", type=Path, required=True)

    validate_volume = subparsers.add_parser(
        "validate-volume", help="validate a dot-rooted Docker-volume archive without extracting"
    )
    validate_volume.add_argument("--archive", type=Path, required=True)

    stage = subparsers.add_parser("stage", help="validate and extract into a new private stage")
    stage.add_argument("--archive", type=Path, required=True)
    stage.add_argument("--stage-root", type=Path, required=True)

    swap = subparsers.add_parser("swap", help="atomically switch sibling roots with rollback")
    swap.add_argument("--stage-root", type=Path, required=True)
    swap.add_argument("--live-root", type=Path, required=True)
    swap.add_argument("--rollback-root", type=Path, required=True)
    swap.add_argument("--journal", type=Path, required=True)

    recover = subparsers.add_parser(
        "recover", help="idempotently reconcile an interrupted root exchange"
    )
    recover.add_argument("--journal", type=Path, required=True)
    recover.add_argument("--action", choices=("rollback", "commit"), required=True)

    seal = subparsers.add_parser(
        "seal-bundle", help="durably publish one complete no-clobber recovery bundle"
    )
    seal.add_argument("--stage-root", type=Path, required=True)
    seal.add_argument("--final-root", type=Path, required=True)

    verify = subparsers.add_parser(
        "verify-bundle", help="verify one published recovery bundle and completion marker"
    )
    verify.add_argument("--bundle-root", type=Path, required=True)
    return parser.parse_args(arguments)


def main(arguments: list[str]) -> int:
    try:
        options = parse_arguments(arguments)
        if options.command == "create":
            create_archive(options.source_root, options.archive)
        elif options.command == "validate":
            validate_archive(options.archive)
        elif options.command == "validate-volume":
            validate_volume_archive(options.archive)
        elif options.command == "stage":
            stage_archive(options.archive, options.stage_root)
        elif options.command == "swap":
            swap_roots(options.stage_root, options.live_root, options.rollback_root, options.journal)
        elif options.command == "recover":
            reconcile_exchange(options.journal, options.action)
        elif options.command == "seal-bundle":
            seal_bundle(options.stage_root, options.final_root)
        elif options.command == "verify-bundle":
            verify_bundle(options.bundle_root)
        else:
            raise RecoveryError("unsupported command")
    except RecoveryError as error:
        print(f"strict-recovery: ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
