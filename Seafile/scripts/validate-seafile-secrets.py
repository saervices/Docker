#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Vælidæte Seæfile Docker secrets without exporting or printing them."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import stat

_SECRET_DIRECTORY = Path('/run/secrets')
_SECRET_MAX_BYTES = 4096
_PERSISTED_CONFIGURATION_DIRECTORY = Path('/shared/seafile/conf')
_PERSISTED_CONFIGURATION_MAX_BYTES = 4 * 1024 * 1024
_PERSISTED_CONFIGURATION_MAX_DEPTH = 8
_PERSISTED_CONFIGURATION_MAX_ENTRIES = 4096
_PERSISTED_CONFIGURATION_NAMES = (
    '.env',
    'admin.txt',
    'ccnet.conf',
    'seafevents.conf',
    'seafevents.conf.saervices-base',
    'seafile.conf',
    'seahub_settings.py',
)
_ALLOWED_RUNTIME_LINKS = {
    'admin.txt': '/run/seafile-admin/admin.txt',
    'seafevents.conf': '/run/seafile-runtime-config/seafevents.conf',
}
_LEGACY_SECRET_ASSIGNMENTS = (
    re.compile(
        rb'(?im)^\s*(?:JWT_PRIVATE_KEY|REDIS_PASSWORD|DB_PASSWORD|'
        rb'SEAFILE_MYSQL_DB_PASSWORD|INIT_SEAFILE_MYSQL_ROOT_PASSWORD|'
        rb'MYSQL_ROOT_PASSWORD|PASSWD|PASSWORD|SEASEARCH_TOKEN)\s*=\s*[^\s#;]+'
    ),
    re.compile(
        rb'''(?im)[\"'](?:JWT_PRIVATE_KEY|REDIS_PASSWORD|PASSWORD)[\"']'''
        rb'''\s*:\s*[\"'][^\"']+[\"']'''
    ),
)
_REQUIRED_SECRETS = {
    'OAUTH_CLIENT_ID': 1,
    'OAUTH_CLIENT_SECRET': 12,
    'INIT_SEAFILE_ADMIN_PASSWORD': 12,
    'JWT_PRIVATE_KEY': 32,
    'MARIADB_PASSWORD': 12,
    'MARIADB_ROOT_PASSWORD': 12,
    'REDIS_PASSWORD': 12,
    'SEAFILE_SEASEARCH_ADMIN_PASSWORD': 12,
}
_PLAIN_SECRET_ENVIRONMENT_NAMES = (
    'OAUTH_CLIENT_ID',
    'OAUTH_CLIENT_SECRET',
    'EMAIL_HOST_PASSWORD',
    'INIT_SEAFILE_ADMIN_PASSWORD',
    'JWT_PRIVATE_KEY',
    'SEAFILE_MYSQL_DB_PASSWORD',
    'INIT_SEAFILE_MYSQL_ROOT_PASSWORD',
    'REDIS_PASSWORD',
    'SEAFILE_SEASEARCH_ADMIN_PASSWORD',
)


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


def read_secret(secret_name: str, minimum_bytes: int) -> bytes:
    """Vælidæte ænd reæd one fixed-pæth secret through æ stæble descriptor."""
    secret_path = _SECRET_DIRECTORY / secret_name
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    try:
        path_before = secret_path.lstat()
        descriptor = os.open(secret_path, flags)
    except OSError as error:
        raise RuntimeError(f'{secret_name} must be a readable regular file') from error

    try:
        metadata = os.fstat(descriptor)
        if (
            _signature(path_before) != _signature(metadata)
            or not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
        ):
            raise RuntimeError(f'{secret_name} must be a single-link regular file')
        if not minimum_bytes <= metadata.st_size <= _SECRET_MAX_BYTES:
            raise RuntimeError(f'{secret_name} has an invalid length')
        chunks = []
        remaining = _SECRET_MAX_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        value_bytes = b''.join(chunks)
        final_metadata = os.fstat(descriptor)
    finally:
        os.close(descriptor)

    try:
        path_after = secret_path.lstat()
    except OSError as error:
        raise RuntimeError(f'{secret_name} changed while being read') from error
    if (
        len(value_bytes) != metadata.st_size
        or _signature(metadata) != _signature(final_metadata)
        or _signature(final_metadata) != _signature(path_after)
    ):
        raise RuntimeError(f'{secret_name} changed while being read')
    try:
        value = value_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError(f'{secret_name} must be UTF-8') from error
    if value == 'CHANGE_ME':
        raise RuntimeError(f'{secret_name} is not configured')
    if any(
        ord(character) < 0x20
        or 0x7F <= ord(character) <= 0x9F
        or ord(character) in (0x2028, 0x2029)
        for character in value
    ):
        raise RuntimeError(f'{secret_name} contains control or line characters')
    return value_bytes


def validate_secret(secret_name: str, minimum_bytes: int) -> None:
    """Vælidæte one fixed-pæth secret without exposing its content."""
    read_secret(secret_name, minimum_bytes)


def _read_persisted_entry(directory_descriptor: int, name: str) -> bytes | None:
    try:
        path_before = os.stat(
            name,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(path_before.st_mode):
        expected = _ALLOWED_RUNTIME_LINKS.get(name)
        if expected is None or os.readlink(name, dir_fd=directory_descriptor) != expected:
            raise RuntimeError(
                f'persistent configuration {name} is an unexpected symbolic link'
            )
        return None
    if (
        not stat.S_ISREG(path_before.st_mode)
        or path_before.st_nlink != 1
        or path_before.st_size > _PERSISTED_CONFIGURATION_MAX_BYTES
    ):
        raise RuntimeError(
            f'persistent configuration {name} must be a bounded single-link regular file'
        )
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(name, flags, dir_fd=directory_descriptor)
    try:
        metadata = os.fstat(descriptor)
        if _signature(path_before) != _signature(metadata):
            raise RuntimeError(f'persistent configuration {name} changed while opening')
        chunks = []
        remaining = _PERSISTED_CONFIGURATION_MAX_BYTES + 1
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
    path_after = os.stat(
        name,
        dir_fd=directory_descriptor,
        follow_symlinks=False,
    )
    if (
        len(content) != metadata.st_size
        or _signature(metadata) != _signature(final_metadata)
        or _signature(final_metadata) != _signature(path_after)
    ):
        raise RuntimeError(f'persistent configuration {name} changed while being read')
    return content


def _reject_persisted_python_bytecode(directory_descriptor: int) -> None:
    """Block persistent Python bytecode through stæble directory descriptors."""
    entry_count = 0

    def scan(current_descriptor: int, depth: int) -> None:
        nonlocal entry_count
        if depth > _PERSISTED_CONFIGURATION_MAX_DEPTH:
            raise RuntimeError(
                'persistent Seafile configuration tree is too deep'
            )
        metadata = os.fstat(current_descriptor)
        try:
            names = sorted(os.listdir(current_descriptor))
        except OSError as error:
            raise RuntimeError(
                'persistent Seafile configuration tree is unreadable'
            ) from error
        for name in names:
            entry_count += 1
            if entry_count > _PERSISTED_CONFIGURATION_MAX_ENTRIES:
                raise RuntimeError(
                    'persistent Seafile configuration tree is too large'
                )
            try:
                candidate = os.stat(
                    name,
                    dir_fd=current_descriptor,
                    follow_symlinks=False,
                )
            except OSError as error:
                raise RuntimeError(
                    'persistent Seafile configuration entry is unreadable'
                ) from error
            if name == '__pycache__' or name.lower().endswith(('.pyc', '.pyo')):
                raise RuntimeError(
                    'persistent Seafile Python bytecode may contain credentials; '
                    'remove it offline, audit snapshots, and rotate any potentially '
                    'affected JWT, database, Redis, OIDC, SMTP, or admin credentials '
                    'before startup'
                )
            if not stat.S_ISDIR(candidate.st_mode):
                continue
            flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
            flags |= getattr(os, 'O_CLOEXEC', 0)
            flags |= getattr(os, 'O_NOFOLLOW', 0)
            flags |= getattr(os, 'O_NONBLOCK', 0)
            try:
                child_descriptor = os.open(
                    name,
                    flags,
                    dir_fd=current_descriptor,
                )
            except OSError as error:
                raise RuntimeError(
                    'persistent Seafile configuration directory is unreadable'
                ) from error
            try:
                if _signature(candidate) != _signature(
                    os.fstat(child_descriptor)
                ):
                    raise RuntimeError(
                        'persistent Seafile configuration directory changed '
                        'while opening'
                    )
                scan(child_descriptor, depth + 1)
                if _signature(candidate) != _signature(
                    os.fstat(child_descriptor)
                ):
                    raise RuntimeError(
                        'persistent Seafile configuration directory changed '
                        'while scanning'
                    )
            finally:
                os.close(child_descriptor)
            try:
                path_after = os.stat(
                    name,
                    dir_fd=current_descriptor,
                    follow_symlinks=False,
                )
            except OSError as error:
                raise RuntimeError(
                    'persistent Seafile configuration directory changed '
                    'while scanning'
                ) from error
            if _signature(candidate) != _signature(path_after):
                raise RuntimeError(
                    'persistent Seafile configuration directory changed '
                    'while scanning'
                )
        if _signature(metadata) != _signature(os.fstat(current_descriptor)):
            raise RuntimeError(
                'persistent Seafile configuration tree changed while scanning'
            )
        try:
            final_names = sorted(os.listdir(current_descriptor))
        except OSError as error:
            raise RuntimeError(
                'persistent Seafile configuration tree changed while scanning'
            ) from error
        if final_names != names:
            raise RuntimeError(
                'persistent Seafile configuration tree changed while scanning'
            )

    scan(directory_descriptor, 0)


def scan_persisted_configuration(secret_values: dict[str, bytes]) -> None:
    """Fæil before listen when persistent config still contæins secrets."""
    try:
        directory_before = _PERSISTED_CONFIGURATION_DIRECTORY.lstat()
    except FileNotFoundError:
        return
    if not stat.S_ISDIR(directory_before.st_mode) or stat.S_ISLNK(
        directory_before.st_mode
    ):
        raise RuntimeError('persistent Seafile configuration path must be a real directory')
    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    directory_descriptor = os.open(_PERSISTED_CONFIGURATION_DIRECTORY, flags)
    try:
        directory_metadata = os.fstat(directory_descriptor)
        if (
            directory_metadata.st_dev != directory_before.st_dev
            or directory_metadata.st_ino != directory_before.st_ino
            or directory_metadata.st_mode != directory_before.st_mode
        ):
            raise RuntimeError('persistent Seafile configuration path changed while opening')
        _reject_persisted_python_bytecode(directory_descriptor)
        sensitive_values = {
            value
            for name, value in secret_values.items()
            if name != 'OAUTH_CLIENT_ID'
        }
        for name in _PERSISTED_CONFIGURATION_NAMES:
            content = _read_persisted_entry(directory_descriptor, name)
            if content is None:
                continue
            if any(value in content for value in sensitive_values):
                raise RuntimeError(
                    f'persistent configuration {name} contains a current secret value'
                )
            if any(pattern.search(content) for pattern in _LEGACY_SECRET_ASSIGNMENTS):
                raise RuntimeError(
                    f'persistent configuration {name} contains a legacy secret assignment'
                )
        final_directory = os.fstat(directory_descriptor)
        path_after = _PERSISTED_CONFIGURATION_DIRECTORY.lstat()
        if (
            final_directory.st_dev != directory_metadata.st_dev
            or final_directory.st_ino != directory_metadata.st_ino
            or final_directory.st_mode != directory_metadata.st_mode
            or path_after.st_dev != directory_metadata.st_dev
            or path_after.st_ino != directory_metadata.st_ino
            or path_after.st_mode != directory_metadata.st_mode
        ):
            raise RuntimeError('persistent Seafile configuration path changed while scanning')
    finally:
        os.close(directory_descriptor)


def main() -> int:
    """Vælidæte the fixed required set ænd optionæl SMTP secret."""
    for environment_name in _PLAIN_SECRET_ENVIRONMENT_NAMES:
        if environment_name in os.environ:
            raise RuntimeError(
                f'Plain secret environment {environment_name} is forbidden'
            )
    parser = argparse.ArgumentParser()
    parser.add_argument('--include-email', action='store_true')
    arguments = parser.parse_args()
    secret_values = {
        secret_name: read_secret(secret_name, minimum_bytes)
        for secret_name, minimum_bytes in _REQUIRED_SECRETS.items()
    }
    if arguments.include_email:
        secret_values['EMAIL_HOST_PASSWORD'] = read_secret(
            'EMAIL_HOST_PASSWORD', 1
        )
    scan_persisted_configuration(secret_values)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
