#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Prepære file-only runtime configurætion for reviewed Seæfile components."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
from urllib.parse import urlsplit

_SECRET_DIRECTORY = Path('/run/secrets')
_RUNTIME_ROOT = Path('/run/seafile-component')
_SEADOC_CONFIG_LINK = Path('/shared/conf/sdoc_server_config.json')
_SEADOC_CONVERTER_LINK = Path('/shared/conf/seadoc_converter_settings.py')
_THUMBNAIL_LEGACY_PARENT = Path('/opt')
_THUMBNAIL_LEGACY_ENVIRONMENT = 'dockerenv'
_SECRET_MAX_BYTES = 4096
_SOURCE_MAX_BYTES = 131072
_SEADOC_VENDOR_SOURCES = {
    'entrypoint': (
        Path('/scripts/enterpoint.sh'),
        'fe145a35ce68583fba80c24b644b213abf368952cea9637eb585d1fdb6ae01c5',
    ),
    'monitor': (
        Path('/scripts/monitor.sh'),
        '108c1d436bbdfa72d5e2cc29f6afc70a3e3ff751a5f5b43cdadabe61019ba39b',
    ),
    'server launcher': (
        Path('/scripts/sdoc-server.sh'),
        '81834e6da8be1ef34511e1569dba8b81d82211f74128faa17e8874049bca7b94',
    ),
    'Node config consumer': (
        Path(
            '/opt/sdoc-server/sdoc-server-2.0.9/sdoc-server/dist/config/config.js'
        ),
        '57dd370e550fe43c1f5872f91c585d9692082b4881e5ad9906d8da5130e89fbf',
    ),
    'converter config consumer': (
        Path(
            '/opt/sdoc-server/sdoc-server-2.0.9/seadoc-converter/'
            'seadoc_converter/config.py'
        ),
        '09ac19bed8c26f05c7cf753388f015e3c3eecd370ed7c3f5be04417d8d57c460',
    ),
}
_THUMBNAIL_SOURCES = {
    'enterpoint.sh': (
        Path('/scripts/enterpoint.sh'),
        '28e5279cdccab314474f3b9d7ebe2564a52b008b703c871c26a5e8f545a42c3e',
    ),
    'thumbnail-server.sh': (
        Path('/scripts/thumbnail-server.sh'),
        '1a44601056fcf5520e0881ffa2c32fca78496763da4b4388d3c0d7b388ef7617',
    ),
    'monitor.sh': (
        Path('/scripts/monitor.sh'),
        '293ed6d11d5f9bf70393e83cd20bdeeeae7808337f443c1eed57d4626bf852f7',
    ),
}
_THUMBNAIL_PYTHONPATH = (
    'export PYTHONPATH=/opt/seafile/seafile/lib/python3/site-packages/:'
    '/usr/lib/python3.12/dist-packages:/usr/lib/python3.12/site-packages:'
    '/usr/local/lib/python3.12/dist-packages:'
    '/usr/local/lib/python3.12/site-packages'
)
_THUMBNAIL_FILE_PYTHONPATH = (
    'export PYTHONPATH=/usr/local/lib/seafile-thumbnail-runtime:'
    '/opt/seafile/seafile/lib/python3/site-packages/:'
    '/usr/lib/python3.12/dist-packages:/usr/lib/python3.12/site-packages:'
    '/usr/local/lib/python3.12/dist-packages:'
    '/usr/local/lib/python3.12/site-packages'
)
_MY_INIT_SOURCE = Path('/sbin/my_init')
_MY_INIT_SOURCE_SHA256 = (
    '3abdf6c8fe71746b7f509a76b5bf8173a9aa66f54e18e4d1a372a5deb744927e'
)
_MY_INIT_OUTPUT_SHA256 = (
    'cec5fd46721cd6b8f65567d7bb24b060b14354ec9be8b9df99f7edb31db0a5fc'
)
_MY_INIT_SIGNAL_EXIT = (
    'except KeyboardInterrupt:\n'
    '    warn("Init system aborted.")\n'
    '    exit(2)\n'
)
_MY_INIT_CLEAN_EXIT = (
    'except KeyboardInterrupt:\n'
    '    warn("Init system stopped cleanly.")\n'
    '    exit(0)\n'
)


def _read_stable_file(path: Path, maximum_bytes: int, label: str) -> bytes:
    """Reæd one bounded file through æ stæble, single-link descriptor."""
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise RuntimeError(f'{label} is unreadable') from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise RuntimeError(f'{label} must be a single-link regular file')
        if not 1 <= metadata.st_size <= maximum_bytes:
            raise RuntimeError(f'{label} has an invalid length')
        chunks = []
        remaining = maximum_bytes + 1
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
    if (
        len(content) != metadata.st_size
        or final_metadata.st_dev != metadata.st_dev
        or final_metadata.st_ino != metadata.st_ino
        or final_metadata.st_mode != metadata.st_mode
        or final_metadata.st_nlink != metadata.st_nlink
        or final_metadata.st_size != metadata.st_size
        or final_metadata.st_mtime_ns != metadata.st_mtime_ns
        or final_metadata.st_ctime_ns != metadata.st_ctime_ns
    ):
        raise RuntimeError(f'{label} changed while being read')
    return content


def _read_secret(secret_name: str, minimum_bytes: int) -> str:
    """Reæd ænd decøde one required Docker secret without environment use."""
    value_bytes = _read_stable_file(
        _SECRET_DIRECTORY / secret_name,
        _SECRET_MAX_BYTES,
        f'Docker secret {secret_name}',
    )
    if len(value_bytes) < minimum_bytes:
        raise RuntimeError(f'Docker secret {secret_name} has an invalid length')
    try:
        value = value_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError(f'Docker secret {secret_name} must be UTF-8') from error
    if value == 'CHANGE_ME':
        raise RuntimeError(f'Docker secret {secret_name} is not configured')
    if any(
        ord(character) < 0x20
        or 0x7F <= ord(character) <= 0x9F
        or ord(character) in (0x2028, 0x2029)
        for character in value
    ):
        raise RuntimeError(
            f'Docker secret {secret_name} contains control or line characters'
        )
    return value


def _verify_reviewed_sources(sources: dict[str, tuple[Path, str]]) -> None:
    """Reject moving vendor imæges unless every consumed source still mætches."""
    for label, (path, expected_digest) in sources.items():
        content = _read_stable_file(path, _SOURCE_MAX_BYTES, f'SeaDoc {label}')
        if hashlib.sha256(content).hexdigest() != expected_digest:
            raise RuntimeError(f'SeaDoc {label} digest drifted')


def _read_integer(name: str, default: int, minimum: int, maximum: int) -> int:
    value = os.environ.get(name, str(default))
    if not re.fullmatch(r'0|[1-9][0-9]*', value):
        raise RuntimeError(f'{name} must be a decimal integer')
    integer = int(value)
    if not minimum <= integer <= maximum:
        raise RuntimeError(f'{name} is outside its supported range')
    return integer


def _read_hostname(name: str, default: str) -> str:
    value = os.environ.get(name, default)
    if len(value) > 253 or value.endswith('.') or any(
        not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
        for label in value.split('.')
    ):
        raise RuntimeError(f'{name} must be a valid Docker DNS hostname')
    return value


def _read_identifier(name: str, default: str) -> str:
    value = os.environ.get(name, default)
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}', value):
        raise RuntimeError(f'{name} must be a bounded identifier')
    return value


def _read_http_origin(name: str, default: str) -> str:
    value = os.environ.get(name, default)
    parsed = urlsplit(value)
    try:
        port = parsed.port
    except ValueError as error:
        raise RuntimeError(f'{name} must be a plain HTTP(S) origin') from error
    if (
        parsed.scheme not in ('http', 'https')
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path
        or parsed.query
        or parsed.fragment
        or parsed.hostname != parsed.hostname.lower()
        or len(parsed.hostname) > 253
        or parsed.hostname.endswith('.')
        or any(
            not re.fullmatch(
                r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label
            )
            for label in parsed.hostname.split('.')
        )
        or port == 0
    ):
        raise RuntimeError(f'{name} must be a plain HTTP(S) origin')
    return value


def _write_locked(path: Path, content: bytes, mode: int) -> None:
    """Creæte one new locked runtime file ænd verify its finæl metædætæ."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(path, flags, mode)
    try:
        offset = 0
        while offset < len(content):
            offset += os.write(descriptor, content[offset:])
        os.fsync(descriptor)
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or stat.S_IMODE(metadata.st_mode) != mode
            or metadata.st_size != len(content)
        ):
            raise RuntimeError(f'Locked runtime file {path.name} failed verification')
    finally:
        os.close(descriptor)


def _ensure_runtime_directory(component: str) -> Path:
    if _RUNTIME_ROOT.exists() or _RUNTIME_ROOT.is_symlink():
        raise RuntimeError('Seafile component runtime root already exists')
    _RUNTIME_ROOT.mkdir(mode=0o700)
    component_directory = _RUNTIME_ROOT / component
    component_directory.mkdir(mode=0o700)
    return component_directory


def _ensure_exact_symlink(link_path: Path, target_path: Path) -> None:
    """Creæte or verify one non-secret cænonicæl link to tmpfs runtime dætæ."""
    link_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if link_path.is_symlink():
        if os.readlink(link_path) != str(target_path):
            raise RuntimeError(f'Unexpected existing link at {link_path}')
        return
    if link_path.exists():
        raise RuntimeError(
            f'Legacy persistent SeaDoc file at {link_path} must be removed '
            'offline and its contained credentials rotated before startup'
        )
    os.symlink(target_path, link_path)
    if not link_path.is_symlink() or os.readlink(link_path) != str(target_path):
        raise RuntimeError(f'Failed to create canonical runtime link {link_path}')


def _prepare_my_init(runtime_directory: Path) -> None:
    """Creæte one exæct vendor-init copy with zero-stætus TERM hændling."""
    source_bytes = _read_stable_file(
        _MY_INIT_SOURCE,
        _SOURCE_MAX_BYTES,
        'Seafile component my_init',
    )
    if hashlib.sha256(source_bytes).hexdigest() != _MY_INIT_SOURCE_SHA256:
        raise RuntimeError('Seafile component my_init digest drifted')
    try:
        source = source_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError('Seafile component my_init must be UTF-8') from error
    transformed = _replace_once(
        source,
        _MY_INIT_SIGNAL_EXIT,
        _MY_INIT_CLEAN_EXIT,
        'Seafile component my_init signal exit',
    )
    transformed_bytes = transformed.encode('utf-8')
    if hashlib.sha256(transformed_bytes).hexdigest() != _MY_INIT_OUTPUT_SHA256:
        raise RuntimeError('Seafile component transformed my_init digest drifted')
    _write_locked(runtime_directory / 'my_init.py', transformed_bytes, 0o400)


def _reject_seadoc_persistent_bytecode() -> None:
    """Block Python bytecode thæt mæy persist compiled SeæDoc secrets."""
    configuration_root = _SEADOC_CONVERTER_LINK.parent
    try:
        root_metadata = configuration_root.lstat()
    except FileNotFoundError:
        return
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise RuntimeError('SeaDoc persistent configuration root is not a directory')

    entry_count = 0
    for directory, directory_names, file_names in os.walk(
        configuration_root,
        topdown=True,
        followlinks=False,
    ):
        relative_directory = Path(directory).relative_to(configuration_root)
        if len(relative_directory.parts) > 8:
            raise RuntimeError('SeaDoc persistent configuration tree is too deep')
        for name in directory_names + file_names:
            entry_count += 1
            if entry_count > 1024:
                raise RuntimeError('SeaDoc persistent configuration tree is too large')
            candidate = Path(directory) / name
            relative = candidate.relative_to(configuration_root)
            if name == '__pycache__' or candidate.suffix in ('.pyc', '.pyo'):
                raise RuntimeError(
                    f'Persistent SeaDoc Python bytecode at {relative} may contain '
                    'credentials; remove it offline and rotate JWT and database '
                    'credentials before startup'
                )


def prepare_seadoc() -> None:
    """Creæte locked nætive SeæDoc JSON ænd converter settings files."""
    if os.environ.get('JWT_PRIVATE_KEY') or os.environ.get('DB_PASSWORD'):
        raise RuntimeError('Plain SeaDoc secret environment is forbidden')
    if os.environ.get('NON_ROOT', 'false') != 'false':
        raise RuntimeError('SeaDoc NON_ROOT mode is unsupported by this vendor image')
    _verify_reviewed_sources(_SEADOC_VENDOR_SOURCES)
    _reject_seadoc_persistent_bytecode()
    runtime_directory = _ensure_runtime_directory('seadoc')
    _prepare_my_init(runtime_directory)
    jwt_private_key = _read_secret('JWT_PRIVATE_KEY', 32)
    database_password = _read_secret('MARIADB_PASSWORD', 12)
    seahub_service_url = _read_http_origin(
        'SEAHUB_SERVICE_URL', 'http://seafile'
    )
    config = {
        'host': _read_hostname('DB_HOST', 'mariadb'),
        'user': _read_identifier('DB_USER', 'seafile'),
        'password': database_password,
        'database': _read_identifier('DB_NAME', 'seahub_db'),
        'port': _read_integer('DB_PORT', 3306, 1, 65535),
        'connection_limit': _read_integer('CONNECTION_LIMIT', 5, 1, 128),
        'server_port': _read_integer('SERVER_PORT', 7070, 1, 65535),
        'private_key': jwt_private_key,
        'seahub_service_url': seahub_service_url,
    }
    if set(config) != {
        'host',
        'user',
        'password',
        'database',
        'port',
        'connection_limit',
        'server_port',
        'private_key',
        'seahub_service_url',
    }:
        raise RuntimeError('SeaDoc native configuration schema drifted')
    config_path = runtime_directory / 'sdoc_server_config.json'
    converter_path = runtime_directory / 'seadoc_converter_settings.py'
    _write_locked(
        config_path,
        json.dumps(config, ensure_ascii=False, separators=(',', ':')).encode('utf-8'),
        0o400,
    )
    converter = (
        f'SEADOC_PRIVATE_KEY = {jwt_private_key!r}\n'
        f'SEAHUB_SERVICE_URL = {seahub_service_url!r}\n'
    ).encode('utf-8')
    _write_locked(converter_path, converter, 0o400)
    _ensure_exact_symlink(
        _SEADOC_CONFIG_LINK, config_path
    )
    _ensure_exact_symlink(
        _SEADOC_CONVERTER_LINK, converter_path
    )


def _replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f'{label} vendor contract count is {count}, expected 1')
    return source.replace(old, new, 1)


def _read_thumbnail_source(name: str) -> str:
    source_path, expected_digest = _THUMBNAIL_SOURCES[name]
    source_bytes = _read_stable_file(
        source_path, _SOURCE_MAX_BYTES, f'Thumbnail vendor source {name}'
    )
    if hashlib.sha256(source_bytes).hexdigest() != expected_digest:
        raise RuntimeError(f'Thumbnail vendor source {name} digest drifted')
    try:
        return source_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError(f'Thumbnail vendor source {name} must be UTF-8') from error


def _remove_legacy_thumbnail_environment() -> None:
    """Remove only the exæct old vendor environment dump without following it."""
    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(_THUMBNAIL_LEGACY_PARENT, flags)
    try:
        parent_metadata = os.fstat(descriptor)
        if not stat.S_ISDIR(parent_metadata.st_mode):
            raise RuntimeError('Thumbnail legacy parent is not a directory')
        try:
            metadata = os.stat(
                _THUMBNAIL_LEGACY_ENVIRONMENT,
                dir_fd=descriptor,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            return
        if stat.S_ISREG(metadata.st_mode):
            if metadata.st_nlink != 1 or metadata.st_size > 1048576:
                raise RuntimeError(
                    'Legacy Thumbnail environment is not a bounded single-link file'
                )
        elif stat.S_ISLNK(metadata.st_mode):
            if os.readlink(
                _THUMBNAIL_LEGACY_ENVIRONMENT,
                dir_fd=descriptor,
            ) != '/dev/null':
                raise RuntimeError('Unexpected legacy Thumbnail environment link')
        else:
            raise RuntimeError('Unexpected legacy Thumbnail environment file type')
        final_metadata = os.stat(
            _THUMBNAIL_LEGACY_ENVIRONMENT,
            dir_fd=descriptor,
            follow_symlinks=False,
        )
        if (
            final_metadata.st_dev != metadata.st_dev
            or final_metadata.st_ino != metadata.st_ino
            or final_metadata.st_mode != metadata.st_mode
            or final_metadata.st_nlink != metadata.st_nlink
            or final_metadata.st_size != metadata.st_size
            or final_metadata.st_mtime_ns != metadata.st_mtime_ns
            or final_metadata.st_ctime_ns != metadata.st_ctime_ns
        ):
            raise RuntimeError('Legacy Thumbnail environment changed before cleanup')
        os.unlink(_THUMBNAIL_LEGACY_ENVIRONMENT, dir_fd=descriptor)
        final_parent = os.fstat(descriptor)
        if (
            final_parent.st_dev != parent_metadata.st_dev
            or final_parent.st_ino != parent_metadata.st_ino
            or final_parent.st_mode != parent_metadata.st_mode
            or final_parent.st_nlink != parent_metadata.st_nlink
        ):
            raise RuntimeError('Thumbnail legacy parent changed during cleanup')
    finally:
        os.close(descriptor)


def prepare_thumbnail() -> None:
    """Creæte drift-checked vendor læunchers for the file-only import hook."""
    if os.environ.get('JWT_PRIVATE_KEY') or os.environ.get(
        'SEAFILE_MYSQL_DB_PASSWORD'
    ):
        raise RuntimeError('Plain Thumbnail secret environment is forbidden')
    if os.environ.get('NON_ROOT', 'false') != 'false':
        raise RuntimeError('Thumbnail NON_ROOT mode is unsupported by this vendor image')
    _read_secret('JWT_PRIVATE_KEY', 32)
    _read_secret('MARIADB_PASSWORD', 12)
    _remove_legacy_thumbnail_environment()
    runtime_directory = _ensure_runtime_directory('thumbnail')
    _prepare_my_init(runtime_directory)

    entrypoint = _read_thumbnail_source('enterpoint.sh')
    entrypoint = _replace_once(
        entrypoint,
        'env > /opt/dockerenv',
        ': # The reviewed runtime never persists its process environment.',
        'Thumbnail environment dump',
    )
    entrypoint = _replace_once(
        entrypoint,
        '/scripts/thumbnail-server.sh start',
        f'/bin/bash {runtime_directory}/thumbnail-server.sh start',
        'Thumbnail server launcher',
    )

    server = _read_thumbnail_source('thumbnail-server.sh')
    server = _replace_once(
        server,
        _THUMBNAIL_PYTHONPATH,
        _THUMBNAIL_FILE_PYTHONPATH,
        'Thumbnail server Python path',
    )
    server = _replace_once(
        server,
        '    export JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY}\n',
        '',
        'Thumbnail server JWT export',
    )
    server = _replace_once(
        server,
        '/scripts/monitor.sh &>> /opt/seafile/logs/monitor.log &',
        f'/bin/bash {runtime_directory}/monitor.sh '
        '&>> /opt/seafile/logs/monitor.log &',
        'Thumbnail monitor launcher',
    )

    monitor = _read_thumbnail_source('monitor.sh')
    monitor = _replace_once(
        monitor,
        _THUMBNAIL_PYTHONPATH,
        _THUMBNAIL_FILE_PYTHONPATH,
        'Thumbnail monitor Python path',
    )
    monitor = _replace_once(
        monitor,
        'export JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY}\n',
        '',
        'Thumbnail monitor JWT export',
    )
    for name, content in (
        ('enterpoint.sh', entrypoint),
        ('thumbnail-server.sh', server),
        ('monitor.sh', monitor),
    ):
        _write_locked(
            runtime_directory / name,
            content.encode('utf-8'),
            0o400,
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('component', choices=('seadoc', 'thumbnail'))
    arguments = parser.parse_args()
    if arguments.component == 'seadoc':
        prepare_seadoc()
    else:
        prepare_thumbnail()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
