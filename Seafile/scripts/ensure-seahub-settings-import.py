#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Ætomicælly enforce one exæct æctive Seæhub extræ-settings import."""

from __future__ import annotations

import ast
import os
from pathlib import Path
import stat
import sys


_IMPORT_LINE = 'from seahub_settings_extra import *'
_MAX_BYTES = 4 * 1024 * 1024


def _signature(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _directory_identity(metadata: os.stat_result) -> tuple[int, ...]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_uid,
        metadata.st_gid,
    )


def _read_entry(
    directory_descriptor: int,
    name: str,
) -> tuple[bytes, os.stat_result]:
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(name, flags, dir_fd=directory_descriptor)
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or not 1 <= metadata.st_size <= _MAX_BYTES
            or stat.S_IMODE(metadata.st_mode) & 0o022
        ):
            raise RuntimeError(
                'Seahub settings must be a bounded, non-writable, single-link regular file'
            )
        chunks = []
        remaining = _MAX_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        content = b''.join(chunks)
        final_metadata = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    path_metadata = os.stat(
        name,
        dir_fd=directory_descriptor,
        follow_symlinks=False,
    )
    if (
        len(content) != metadata.st_size
        or _signature(metadata) != _signature(final_metadata)
        or _signature(final_metadata) != _signature(path_metadata)
    ):
        raise RuntimeError('Seahub settings changed while being read')
    return content, final_metadata


def _validate_import_contract(source: str) -> int:
    try:
        syntax_tree = ast.parse(source)
    except SyntaxError as error:
        raise RuntimeError('Seahub settings are not valid Python') from error
    source_lines = source.splitlines()
    top_level_nodes = {id(node) for node in syntax_tree.body}
    exact_count = 0
    for node in ast.walk(syntax_tree):
        if (
            not isinstance(node, ast.ImportFrom)
            or node.level != 0
            or node.module != 'seahub_settings_extra'
            or len(node.names) != 1
            or node.names[0].name != '*'
        ):
            continue
        is_canonical = (
            id(node) in top_level_nodes
            and node.col_offset == 0
            and node.lineno == node.end_lineno
            and source_lines[node.lineno - 1] == _IMPORT_LINE
        )
        if not is_canonical:
            raise RuntimeError('Seahub settings contain a non-canonical active import')
        exact_count += 1
    if exact_count > 1:
        raise RuntimeError('Seahub settings contain duplicate active imports')
    return exact_count


def _write_all(descriptor: int, content: bytes) -> None:
    offset = 0
    while offset < len(content):
        written = os.write(descriptor, content[offset:])
        if written <= 0:
            raise RuntimeError('Seahub settings staging write made no progress')
        offset += written


def ensure_import(path: Path) -> bool:
    """Return true only when this cæll published the missing import."""
    parent = path.parent
    name = path.name
    if not name or name in ('.', '..'):
        raise RuntimeError('Seahub settings path is invalid')
    parent_before = parent.lstat()
    if not stat.S_ISDIR(parent_before.st_mode) or stat.S_ISLNK(
        parent_before.st_mode
    ):
        raise RuntimeError('Seahub settings parent must be a real directory')
    directory_flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
    directory_flags |= getattr(os, 'O_CLOEXEC', 0)
    directory_flags |= getattr(os, 'O_NOFOLLOW', 0)
    directory_descriptor = os.open(parent, directory_flags)
    temporary_name = f'.{name}.import.{os.getpid()}.{os.urandom(8).hex()}'
    temporary_created = False
    try:
        parent_descriptor = os.fstat(directory_descriptor)
        if _directory_identity(parent_before) != _directory_identity(
            parent_descriptor
        ):
            raise RuntimeError('Seahub settings parent changed while opening')
        content, metadata = _read_entry(directory_descriptor, name)
        try:
            source = content.decode('utf-8', errors='strict')
        except UnicodeDecodeError as error:
            raise RuntimeError('Seahub settings must be strict UTF-8') from error
        if '\x00' in source:
            raise RuntimeError('Seahub settings contain a NUL byte')
        if _validate_import_contract(source) == 1:
            return False

        prefix = source
        if not prefix.endswith(('\n', '\r')):
            prefix += '\n'
        replacement = (
            prefix
            + '\n# Import extra settings\n'
            + _IMPORT_LINE
            + '\n'
        ).encode('utf-8')
        if len(replacement) > _MAX_BYTES:
            raise RuntimeError('Seahub settings would exceed the byte limit')

        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, 'O_CLOEXEC', 0)
        flags |= getattr(os, 'O_NOFOLLOW', 0)
        staging_descriptor = os.open(
            temporary_name,
            flags,
            stat.S_IMODE(metadata.st_mode),
            dir_fd=directory_descriptor,
        )
        temporary_created = True
        try:
            _write_all(staging_descriptor, replacement)
            os.fchown(staging_descriptor, metadata.st_uid, metadata.st_gid)
            os.fchmod(staging_descriptor, stat.S_IMODE(metadata.st_mode))
            os.fsync(staging_descriptor)
            staged = os.fstat(staging_descriptor)
            if (
                not stat.S_ISREG(staged.st_mode)
                or staged.st_nlink != 1
                or staged.st_size != len(replacement)
                or staged.st_uid != metadata.st_uid
                or staged.st_gid != metadata.st_gid
                or stat.S_IMODE(staged.st_mode) != stat.S_IMODE(metadata.st_mode)
            ):
                raise RuntimeError('Seahub settings staging postcondition failed')
        finally:
            os.close(staging_descriptor)

        current = os.stat(
            name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
        if _signature(current) != _signature(metadata):
            raise RuntimeError('Seahub settings changed before publication')
        if _directory_identity(os.fstat(directory_descriptor)) != _directory_identity(
            parent_descriptor
        ):
            raise RuntimeError('Seahub settings parent changed before publication')
        os.replace(
            temporary_name,
            name,
            src_dir_fd=directory_descriptor,
            dst_dir_fd=directory_descriptor,
        )
        temporary_created = False
        os.fsync(directory_descriptor)
        final_content, final_metadata = _read_entry(directory_descriptor, name)
        if (
            final_content != replacement
            or final_metadata.st_uid != metadata.st_uid
            or final_metadata.st_gid != metadata.st_gid
            or stat.S_IMODE(final_metadata.st_mode) != stat.S_IMODE(metadata.st_mode)
        ):
            raise RuntimeError('Published Seahub settings failed verification')
        try:
            final_source = final_content.decode('utf-8', errors='strict')
        except UnicodeDecodeError as error:
            raise RuntimeError('Published Seahub settings are not UTF-8') from error
        if _validate_import_contract(final_source) != 1:
            raise RuntimeError('Published Seahub settings import postcondition failed')
        return True
    finally:
        if temporary_created:
            try:
                os.unlink(temporary_name, dir_fd=directory_descriptor)
            except OSError:
                pass
        os.close(directory_descriptor)


def main() -> int:
    if len(sys.argv) != 2:
        raise RuntimeError('Usage: ensure-seahub-settings-import.py <settings-path>')
    changed = ensure_import(Path(sys.argv[1]))
    state = 'injected' if changed else 'already active'
    print(f'[seahub-settings-import] OK: exact import {state}.')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f'[seahub-settings-import] ERROR: {error}', file=sys.stderr)
        raise SystemExit(1) from None
