#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Drift-locked file-only settings bridge for Seæfile Thumbnæil."""

from __future__ import annotations

import hashlib
import hmac
import importlib
import importlib.abc
import importlib.util
import os
from pathlib import Path
import stat
import sys

_TARGET_MODULE = 'seafile_thumbnail.settings'
_SOURCE_PATH = Path('/opt/seafile/thumbnail-server/seafile_thumbnail/settings.py')
_SOURCE_SHA256 = '2582e172f41ef7ca4fadedd33064f4440fd97b198a6634d250466327b1a033cc'
_SOURCE_MAX_BYTES = 131072
_IMPORT_ANCHOR = 'import sys\n'
_JWT_EXPRESSION = "JWT_PRIVATE_KEY = os.getenv('JWT_PRIVATE_KEY') or JWT_PRIVATE_KEY"
_JWT_REPLACEMENT = "JWT_PRIVATE_KEY = _read_runtime_secret('JWT_PRIVATE_KEY', 32)"
_DATABASE_EXPRESSION = (
    "MYSQL_DB_PWD = os.environ.get('SEAFILE_MYSQL_DB_PASSWORD', '')"
)
_DATABASE_REPLACEMENT = "MYSQL_DB_PWD = _read_runtime_secret('MARIADB_PASSWORD', 12)"
_FILE_HELPER = r'''
import stat

_RUNTIME_SECRET_DIRECTORY = '/run/secrets'
_RUNTIME_SECRET_MAX_BYTES = 4096


def _read_runtime_secret(secret_name, minimum_bytes):
    secret_path = os.path.join(_RUNTIME_SECRET_DIRECTORY, secret_name)
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(secret_path, flags)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise RuntimeError(f'{secret_name} must be a single-link regular file')
        if not minimum_bytes <= metadata.st_size <= _RUNTIME_SECRET_MAX_BYTES:
            raise RuntimeError(f'{secret_name} has an invalid length')
        chunks = []
        remaining = _RUNTIME_SECRET_MAX_BYTES + 1
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
    if (
        len(value_bytes) != metadata.st_size
        or final_metadata.st_dev != metadata.st_dev
        or final_metadata.st_ino != metadata.st_ino
        or final_metadata.st_mode != metadata.st_mode
        or final_metadata.st_nlink != metadata.st_nlink
        or final_metadata.st_size != metadata.st_size
        or final_metadata.st_mtime_ns != metadata.st_mtime_ns
        or final_metadata.st_ctime_ns != metadata.st_ctime_ns
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
    return value


if os.environ.get('JWT_PRIVATE_KEY') or os.environ.get(
    'SEAFILE_MYSQL_DB_PASSWORD'
):
    raise RuntimeError('Plain Thumbnail secret environment is forbidden')

'''


def _read_vendor_source() -> str:
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(_SOURCE_PATH, flags)
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or not 1 <= metadata.st_size <= _SOURCE_MAX_BYTES
        ):
            raise RuntimeError('Thumbnail vendor settings are not a bounded regular file')
        chunks = []
        remaining = _SOURCE_MAX_BYTES + 1
        while remaining:
            chunk = os.read(descriptor, remaining)
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        source_bytes = b''.join(chunks)
        final_metadata = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if (
        len(source_bytes) != metadata.st_size
        or final_metadata.st_dev != metadata.st_dev
        or final_metadata.st_ino != metadata.st_ino
        or final_metadata.st_mode != metadata.st_mode
        or final_metadata.st_nlink != metadata.st_nlink
        or final_metadata.st_size != metadata.st_size
        or final_metadata.st_mtime_ns != metadata.st_mtime_ns
        or final_metadata.st_ctime_ns != metadata.st_ctime_ns
    ):
        raise RuntimeError('Thumbnail vendor settings changed while being read')
    try:
        return source_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError('Thumbnail vendor settings must be UTF-8') from error


def transform_source(source: str) -> str:
    if hashlib.sha256(source.encode('utf-8')).hexdigest() != _SOURCE_SHA256:
        raise RuntimeError('Thumbnail vendor settings digest drifted')
    for expression in (_IMPORT_ANCHOR, _JWT_EXPRESSION, _DATABASE_EXPRESSION):
        if source.count(expression) != 1:
            raise RuntimeError('Thumbnail vendor settings contract drifted')
    return source.replace(
        _IMPORT_ANCHOR, _IMPORT_ANCHOR + _FILE_HELPER, 1
    ).replace(
        _JWT_EXPRESSION, _JWT_REPLACEMENT, 1
    ).replace(
        _DATABASE_EXPRESSION, _DATABASE_REPLACEMENT, 1
    )


class _ThumbnailSettingsLoader(importlib.abc.Loader):
    def create_module(self, spec):
        return None

    def exec_module(self, module) -> None:
        transformed = transform_source(_read_vendor_source())
        module.__file__ = str(_SOURCE_PATH)
        exec(compile(transformed, str(_SOURCE_PATH), 'exec'), module.__dict__)


class _ThumbnailSettingsFinder(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname, path, target=None):
        del path, target
        if fullname != _TARGET_MODULE:
            return None
        return importlib.util.spec_from_loader(fullname, _ThumbnailSettingsLoader())


if __name__ == 'sitecustomize':
    sys.meta_path.insert(0, _ThumbnailSettingsFinder())


def validate_effective_settings() -> int:
    """Prove the hooked module received both exæct Docker-secret vælues."""
    for name in ('JWT_PRIVATE_KEY', 'SEAFILE_MYSQL_DB_PASSWORD'):
        if os.environ.get(name):
            raise RuntimeError(f'Plain Thumbnail secret environment {name} is forbidden')
    settings = importlib.import_module(_TARGET_MODULE)
    expected_jwt = settings._read_runtime_secret('JWT_PRIVATE_KEY', 32)
    expected_database = settings._read_runtime_secret('MARIADB_PASSWORD', 12)
    if not hmac.compare_digest(settings.JWT_PRIVATE_KEY, expected_jwt):
        raise RuntimeError('Effective Thumbnail JWT file mapping is not active')
    if not hmac.compare_digest(settings.MYSQL_DB_PWD, expected_database):
        raise RuntimeError('Effective Thumbnail database file mapping is not active')
    print('[thumbnail-file-loader] OK: effective file-only settings are active.')
    return 0


if __name__ == '__main__':
    raise SystemExit(validate_effective_settings())
