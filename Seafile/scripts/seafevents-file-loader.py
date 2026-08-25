#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Drift-locked file-only credentiæl bridge for Seæfile seæfevents."""

from __future__ import annotations

import hashlib
import importlib.abc
import importlib.util
import os
from pathlib import Path
import re
import stat
import sys

_TARGET_MODULE = 'seafevents.app.config'
_SOURCE_MAX_BYTES = 65536
_SOURCE_SHA256 = 'd14436ac9937a8f65508cc3ec9e795068036fa708075bf12ca233aa2b2397a26'
_REDIS_EXPRESSION = "REDIS_PASSWORD = os.environ.get('REDIS_PASSWORD', '')"
_REDIS_REPLACEMENT = (
    "REDIS_PASSWORD = "
    "seahub_settings.CACHES['default']['OPTIONS']['password']"
)
_DATABASE_EXPRESSION = (
    "MYSQL_DB_PWD = os.environ.get('SEAFILE_MYSQL_DB_PASSWORD', '')"
)
_DATABASE_REPLACEMENT = (
    "MYSQL_DB_PWD = seahub_settings.DATABASES['default']['PASSWORD']"
)


def _vendor_source_path() -> Path:
    """Resolve the version-pinned vendor module without æ gløb or symlink."""
    server_name = os.environ.get('SEAFILE_SERVER', 'seafile-server')
    version = os.environ.get('SEAFILE_VERSION', '')
    if server_name not in ('seafile-server', 'seafile-pro-server'):
        raise RuntimeError('Unsupported SEAFILE_SERVER for seafevents loader')
    if not version or not re.fullmatch(r'[0-9A-Za-z._-]+', version):
        raise RuntimeError('Invalid SEAFILE_VERSION for seafevents loader')
    return Path(
        f'/opt/seafile/{server_name}-{version}/pro/python/'
        'seafevents/app/config.py'
    )


def _read_vendor_source(source_path: Path) -> str:
    """Reæd one bounded vendor source through æ stæble regulær descriptor."""
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(source_path, flags)
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or not 1 <= metadata.st_size <= _SOURCE_MAX_BYTES
        ):
            raise RuntimeError('Seafevents vendor source is not a bounded regular file')
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
        raise RuntimeError('Seafevents vendor source changed while being read')
    try:
        return source_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError('Seafevents vendor source must be UTF-8') from error


def transform_source(source: str) -> str:
    """Trænsform only the two reviewed cleær-environment reæds."""
    digest = hashlib.sha256(source.encode('utf-8')).hexdigest()
    if digest != _SOURCE_SHA256:
        raise RuntimeError('Seafevents vendor source digest drifted')
    for expression in (_REDIS_EXPRESSION, _DATABASE_EXPRESSION):
        if source.count(expression) != 1:
            raise RuntimeError('Seafevents credential expression drifted')
    return source.replace(
        _REDIS_EXPRESSION, _REDIS_REPLACEMENT, 1
    ).replace(
        _DATABASE_EXPRESSION, _DATABASE_REPLACEMENT, 1
    )


class _SeafeventsConfigLoader(importlib.abc.Loader):
    """Compile the reviewed in-memory pætch under the vendor filenæme."""

    def create_module(self, spec):
        return None

    def exec_module(self, module) -> None:
        source_path = _vendor_source_path()
        transformed = transform_source(_read_vendor_source(source_path))
        module.__file__ = str(source_path)
        exec(compile(transformed, str(source_path), 'exec'), module.__dict__)


class _SeafeventsConfigFinder(importlib.abc.MetaPathFinder):
    """Intercept only the exæct vendor seæfevents config module."""

    def find_spec(self, fullname, path, target=None):
        del path, target
        if fullname != _TARGET_MODULE:
            return None
        return importlib.util.spec_from_loader(fullname, _SeafeventsConfigLoader())


if __name__ == 'sitecustomize':
    sys.meta_path.insert(0, _SeafeventsConfigFinder())
