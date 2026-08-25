#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Prepære drift-checked Seæfile vendor scripts for file-bæsed ædmin bootstræp."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shlex
import stat


START_PASSWORD_EXPRESSION = (
    "        'password': get_conf('INIT_SEAFILE_ADMIN_PASSWORD', 'asecret'),"
)
START_PASSWORD_REPLACEMENT = "        'password': _read_admin_password_file(),"
START_IMPORT_ANCHOR = "import os\n"
START_HELPER_ANCHOR = "topdir = dirname(installdir)\n"
START_ADMIN_WRITE_EXPRESSION = (
    "    password_file = join(topdir, 'conf', 'admin.txt')\n"
    "    with open(password_file, 'w') as fp:\n"
    "        json.dump(admin_pw, fp)\n"
)
START_ADMIN_CLEANUP_EXPRESSION = (
    "        if exists(password_file):\n"
    "            os.unlink(password_file)\n"
)
START_DATABASE_LOAD_ANCHOR = "    wait_for_mysql()\n"
START_DATABASE_ROOT_RETIRE_ANCHOR = "    init_seafile_server()\n"
START_DATABASE_RETIRE_ANCHOR = "    check_upgrade()\n"
START_INJECTOR_PATH = '/usr/local/bin/inject_extra_settings.sh'
START_EFFECTIVE_SETTINGS_VALIDATOR = (
    '/usr/local/bin/validate-seahub-effective-settings.py'
)
START_SOURCE_SHA256 = (
    '9266289a7ce4ad43839060e227cafe13b34a3de80f8b618c0747a9dabc8ace9a'
)
ENTRYPOINT_SOURCE_SHA256 = (
    'd89cc4d35fa4c6dae16bc25b560954019f1c0bcb8f05eb8691d05f6880c51cbe'
)
SEAFILE_SCRIPT_SOURCE_SHA256 = (
    '41f57548248b9aa8e4c1408ffd113e7302a843a9480600bd3eb7bb67c91ac44c'
)
MONITOR_SCRIPT_SOURCE_SHA256 = (
    'b264dbd9e17b6d7d93ab48af1ace373b294fc520f9d24898c93e15be6350dd89'
)
SEAHUB_SCRIPT_SOURCE_SHA256 = (
    '9bb44214b9787aa47b7a08b27bc29e876928fbbdef54f15af5a1046617691368'
)
MY_INIT_SOURCE_SHA256 = (
    '3abdf6c8fe71746b7f509a76b5bf8173a9aa66f54e18e4d1a372a5deb744927e'
)
MY_INIT_OUTPUT_SHA256 = (
    'cec5fd46721cd6b8f65567d7bb24b060b14354ec9be8b9df99f7edb31db0a5fc'
)
MY_INIT_SIGNAL_EXIT = (
    'except KeyboardInterrupt:\n'
    '    warn("Init system aborted.")\n'
    '    exit(2)\n'
)
MY_INIT_CLEAN_EXIT = (
    'except KeyboardInterrupt:\n'
    '    warn("Init system stopped cleanly.")\n'
    '    exit(0)\n'
)
SCRIPTS_TREE_ENTRY_COUNT = 12
SCRIPTS_TREE_SHA256 = (
    'ed9fcea01b7645967bbac4d686fcc94011a86fc44442c55edb43b86c80753774'
)
VENDOR_BOOTSTRAP_ENTRY_COUNT = 345
VENDOR_BOOTSTRAP_SHA256 = (
    'b00ac2c0a1d7a864da4f10f720ab5d8b19afc9e7a3f5751602fe6ba389b725c9'
)
VENDOR_BOOTSTRAP_PATHS = (
    'setup-seafile-mysql.sh',
    'setup-seafile-mysql.py',
    'check_init_admin.py',
    'sql/mysql/ccnet.sql',
    'sql/mysql/seafile.sql',
    'seahub/sql/mysql.sql',
    'seahub/tools/secret_key_generator.py',
    'upgrade',
    'seahub/seahub/auth',
    'seahub/seahub/api2',
    'seahub/seahub/base/accounts.py',
    'seahub/seahub/settings.py',
    'seahub/seahub/urls.py',
    'seahub/seahub/oauth',
    'seahub/seahub/invitations',
    'seahub/seahub/utils/auth.py',
    'seahub/seahub/views',
)
VENDOR_SOURCE_MAX_BYTES = 262144
ENTRYPOINT_LIFECYCLE_ANCHOR = "# start cluster server\n"
SCRIPT_PATH_EXPRESSION = 'SCRIPT=$(readlink -f "$0")'
SEAFILE_ENV_SECTION_END = "function validate_central_conf_dir () {"
MONITOR_ENV_SECTION_END = "# log function"
SEAHUB_ENV_SECTION_END = "function prepare_env() {"
ENV_SECTION_START = "function set_env_config () {"
SEAFILE_ENV_SECTION_SHA256 = (
    'fdfa44a1065ba87a38beb34443d166487a1cda8ccc550551c74b96f89f3d2982'
)
MONITOR_ENV_SECTION_SHA256 = SEAFILE_ENV_SECTION_SHA256
SEAHUB_ENV_SECTION_SHA256 = (
    '055f12032ba7cd016a9b7549dfcdb42eeb524a582b02bb4e5d39fbac8ec5bf27'
)
SEAF_SERVER_COMMAND = (
    '        LD_LIBRARY_PATH=${SEAFILE_LD_LIBRARY_PATH} '
    '${INSTALLPATH}/seafile/bin/seaf-server \\\n'
)
SEAF_SERVER_FILE_COMMAND = (
    '        LD_PRELOAD=/usr/local/lib/libseafile-jwt-file.so '
    'LD_LIBRARY_PATH=${SEAFILE_LD_LIBRARY_PATH} '
    '${INSTALLPATH}/seafile/bin/seaf-server \\\n'
)
SEAFEVENTS_COMMAND = '    $PYTHON -m seafevents.main \\\n'
SEAFEVENTS_FILE_COMMAND = (
    '    PYTHONPATH=/usr/local/lib/seafile-runtime:${PYTHONPATH} '
    '$PYTHON -m seafevents.main \\\n'
)
FILE_ONLY_ENV_SECTION = '''function set_env_config () {
    if [ -n "${JWT_PRIVATE_KEY:-}" ]; then
        echo "Error: Plain JWT_PRIVATE_KEY is forbidden." >&2
        exit 1
    fi
    if [ -n "${SEAFILE_MYSQL_DB_PASSWORD:-}" ]; then
        echo "Error: Plain SEAFILE_MYSQL_DB_PASSWORD is forbidden." >&2
        exit 1
    fi
    if [ -n "${REDIS_PASSWORD:-}" ]; then
        echo "Error: Plain REDIS_PASSWORD is forbidden." >&2
        exit 1
    fi
    if [ "${JWT_PRIVATE_KEY_FILE:-}" != "/run/secrets/JWT_PRIVATE_KEY" ]; then
        echo "Error: JWT_PRIVATE_KEY_FILE must use the reviewed Docker-secret path." >&2
        exit 1
    fi
    if [ "${SEAFILE_MYSQL_DB_PASSWORD_FILE:-}" != "/run/secrets/MARIADB_PASSWORD" ]; then
        echo "Error: SEAFILE_MYSQL_DB_PASSWORD_FILE must use the reviewed Docker-secret path." >&2
        exit 1
    fi
    if [ "${REDIS_PASSWORD_FILE:-}" != "/run/secrets/REDIS_PASSWORD" ]; then
        echo "Error: REDIS_PASSWORD_FILE must use the reviewed Docker-secret path." >&2
        exit 1
    fi
}

'''

START_HELPER = r'''

_RUNTIME_SECRET_MAX_BYTES = 4096
_RUNTIME_SECRET_DIRECTORY = '/run/secrets'
_DATABASE_ENVIRONMENT_KEYS = (
    'SEAFILE_MYSQL_DB_PASSWORD',
    'INIT_SEAFILE_MYSQL_ROOT_PASSWORD',
)
_SEAFILE_DATA_DIRECTORY = '/shared/seafile/seafile-data'
_ADMIN_RUNTIME_PARENT = '/run'
_ADMIN_RUNTIME_DIRECTORY_NAME = 'seafile-admin'
_ADMIN_RUNTIME_DIRECTORY = '/run/seafile-admin'
_ADMIN_RUNTIME_FILENAME = 'admin.txt'
_ADMIN_CANONICAL_PARENT = '/shared/seafile/conf'


def _read_runtime_secret(secret_name, minimum_bytes):
    """Reæd one bounded Docker secret from its verified descriptor."""
    secret_path = os.path.join(_RUNTIME_SECRET_DIRECTORY, secret_name)
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)

    try:
        descriptor = os.open(secret_path, flags)
    except OSError as error:
        raise RuntimeError(f'{secret_name} must be a readable regular file') from error

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
        secret_bytes = b''.join(chunks)
        final_metadata = os.fstat(descriptor)
    finally:
        os.close(descriptor)

    if (
        len(secret_bytes) != metadata.st_size
        or final_metadata.st_dev != metadata.st_dev
        or final_metadata.st_ino != metadata.st_ino
        or final_metadata.st_mode != metadata.st_mode
        or final_metadata.st_nlink != metadata.st_nlink
        or final_metadata.st_size != metadata.st_size
        or final_metadata.st_mtime_ns != metadata.st_mtime_ns
        or final_metadata.st_ctime_ns != metadata.st_ctime_ns
    ):
        raise RuntimeError(f'{secret_name} changed while being read')
    if secret_bytes == b'CHANGE_ME':
        raise RuntimeError(f'{secret_name} is not configured')

    try:
        secret_value = secret_bytes.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError(f'{secret_name} must be UTF-8') from error

    if any(
        ord(character) < 0x20
        or 0x7F <= ord(character) <= 0x9F
        or ord(character) in (0x2028, 0x2029)
        for character in secret_value
    ):
        raise RuntimeError(f'{secret_name} contains control or line characters')
    return secret_value


def _read_admin_password_file():
    """Reæd the bounded bootstræp secret without exporting cleær text."""
    return _read_runtime_secret('INIT_SEAFILE_ADMIN_PASSWORD', 12)


def _load_database_runtime_secrets():
    """Provide only the vendor keys needed by the current startup phase."""
    for environment_key in _DATABASE_ENVIRONMENT_KEYS:
        if os.environ.get(environment_key):
            raise RuntimeError(f'Plain {environment_key} is forbidden')
    os.environ['SEAFILE_MYSQL_DB_PASSWORD'] = _read_runtime_secret(
        'MARIADB_PASSWORD', 12
    )
    try:
        data_metadata = os.lstat(_SEAFILE_DATA_DIRECTORY)
    except FileNotFoundError:
        os.environ['INIT_SEAFILE_MYSQL_ROOT_PASSWORD'] = _read_runtime_secret(
            'MARIADB_ROOT_PASSWORD', 12
        )
    else:
        if not stat.S_ISDIR(data_metadata.st_mode):
            raise RuntimeError(
                'Existing Seafile data path must be a real directory'
            )


def _retire_database_root_secret():
    """Remove the fresh-install root key immediately after vendor setup."""
    os.environ.pop('INIT_SEAFILE_MYSQL_ROOT_PASSWORD', None)


def _retire_database_runtime_secrets():
    """Remove the remaining startup key before dæemons ære spawned."""
    _retire_database_root_secret()
    os.environ.pop('SEAFILE_MYSQL_DB_PASSWORD', None)


def _same_file_metadata(left, right):
    """Compære identity, type, link count, size, ænd content timestamps."""
    return all(
        getattr(left, attribute) == getattr(right, attribute)
        for attribute in (
            'st_dev',
            'st_ino',
            'st_mode',
            'st_nlink',
            'st_size',
            'st_mtime_ns',
            'st_ctime_ns',
        )
    )


def _same_directory_identity(left, right):
    """Compære directory identity without mutable child timestamps."""
    return all(
        getattr(left, attribute) == getattr(right, attribute)
        for attribute in ('st_dev', 'st_ino', 'st_mode', 'st_nlink')
    )


def _open_runtime_directory(parent_descriptor):
    """Creæte the private tmpfs directory without following links."""
    os.mkdir(
        _ADMIN_RUNTIME_DIRECTORY_NAME,
        mode=0o700,
        dir_fd=parent_descriptor,
    )
    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(
        _ADMIN_RUNTIME_DIRECTORY_NAME,
        flags,
        dir_fd=parent_descriptor,
    )
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o700:
        os.close(descriptor)
        raise RuntimeError('Admin runtime directory is not locked')
    return descriptor, metadata


def _open_canonical_admin_parent():
    """Open the fixed persistent parent through one no-follow descriptor."""
    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(_ADMIN_CANONICAL_PARENT, flags)
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode):
        os.close(descriptor)
        raise RuntimeError('Admin canonical parent is not a directory')
    return descriptor, metadata


def _write_admin_password_file(admin_password):
    """Publish one locked tmpfs password file through æ fixed cænonicæl link."""
    payload = json.dumps(
        admin_password,
        ensure_ascii=False,
        separators=(',', ':'),
    ).encode('utf-8')
    if not 1 <= len(payload) <= _RUNTIME_SECRET_MAX_BYTES * 2:
        raise RuntimeError('Admin bootstrap payload has an invalid length')

    directory_flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0)
    directory_flags |= getattr(os, 'O_CLOEXEC', 0)
    directory_flags |= getattr(os, 'O_NOFOLLOW', 0)
    run_descriptor = os.open(_ADMIN_RUNTIME_PARENT, directory_flags)
    runtime_descriptor = None
    canonical_descriptor = None
    file_descriptor = None
    file_metadata = None
    link_metadata = None
    try:
        runtime_descriptor, runtime_metadata = _open_runtime_directory(
            run_descriptor
        )
        file_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        file_flags |= getattr(os, 'O_CLOEXEC', 0)
        file_flags |= getattr(os, 'O_NOFOLLOW', 0)
        file_descriptor = os.open(
            _ADMIN_RUNTIME_FILENAME,
            file_flags,
            0o600,
            dir_fd=runtime_descriptor,
        )
        offset = 0
        while offset < len(payload):
            offset += os.write(file_descriptor, payload[offset:])
        os.fsync(file_descriptor)
        file_metadata = os.fstat(file_descriptor)
        if (
            not stat.S_ISREG(file_metadata.st_mode)
            or file_metadata.st_nlink != 1
            or stat.S_IMODE(file_metadata.st_mode) != 0o600
            or file_metadata.st_size != len(payload)
        ):
            raise RuntimeError('Admin runtime file failed verification')
        os.close(file_descriptor)
        file_descriptor = None

        canonical_descriptor, canonical_metadata = _open_canonical_admin_parent()
        try:
            existing = os.stat(
                _ADMIN_RUNTIME_FILENAME,
                dir_fd=canonical_descriptor,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            os.symlink(
                os.path.join(
                    _ADMIN_RUNTIME_DIRECTORY,
                    _ADMIN_RUNTIME_FILENAME,
                ),
                _ADMIN_RUNTIME_FILENAME,
                dir_fd=canonical_descriptor,
            )
        else:
            if (
                not stat.S_ISLNK(existing.st_mode)
                or os.readlink(
                    _ADMIN_RUNTIME_FILENAME,
                    dir_fd=canonical_descriptor,
                )
                != os.path.join(
                    _ADMIN_RUNTIME_DIRECTORY,
                    _ADMIN_RUNTIME_FILENAME,
                )
            ):
                raise RuntimeError('Unexpected existing admin bootstrap path')
        link_metadata = os.stat(
            _ADMIN_RUNTIME_FILENAME,
            dir_fd=canonical_descriptor,
            follow_symlinks=False,
        )
        if (
            not stat.S_ISLNK(link_metadata.st_mode)
            or link_metadata.st_nlink != 1
            or not _same_directory_identity(
                canonical_metadata, os.fstat(canonical_descriptor)
            )
        ):
            raise RuntimeError('Admin canonical link failed verification')
        return (
            run_descriptor,
            runtime_descriptor,
            runtime_metadata,
            file_metadata,
            canonical_descriptor,
            canonical_metadata,
            link_metadata,
        )
    except BaseException:
        if file_descriptor is not None:
            os.close(file_descriptor)
        if canonical_descriptor is not None:
            try:
                current_link = os.stat(
                    _ADMIN_RUNTIME_FILENAME,
                    dir_fd=canonical_descriptor,
                    follow_symlinks=False,
                )
                expected_link = os.path.join(
                    _ADMIN_RUNTIME_DIRECTORY,
                    _ADMIN_RUNTIME_FILENAME,
                )
                if (
                    stat.S_ISLNK(current_link.st_mode)
                    and os.readlink(
                        _ADMIN_RUNTIME_FILENAME,
                        dir_fd=canonical_descriptor,
                    )
                    == expected_link
                    and (
                        link_metadata is None
                        or _same_file_metadata(link_metadata, current_link)
                    )
                ):
                    os.unlink(
                        _ADMIN_RUNTIME_FILENAME,
                        dir_fd=canonical_descriptor,
                    )
            except (FileNotFoundError, OSError):
                pass
        if runtime_descriptor is not None and file_metadata is not None:
            try:
                current_file = os.stat(
                    _ADMIN_RUNTIME_FILENAME,
                    dir_fd=runtime_descriptor,
                    follow_symlinks=False,
                )
                if _same_file_metadata(file_metadata, current_file):
                    os.unlink(
                        _ADMIN_RUNTIME_FILENAME,
                        dir_fd=runtime_descriptor,
                    )
            except (FileNotFoundError, OSError):
                pass
        if canonical_descriptor is not None:
            os.close(canonical_descriptor)
        if runtime_descriptor is not None:
            os.close(runtime_descriptor)
            try:
                os.rmdir(_ADMIN_RUNTIME_DIRECTORY_NAME, dir_fd=run_descriptor)
            except OSError:
                pass
        os.close(run_descriptor)
        raise


def _remove_admin_password_file(handle):
    """Remove only the exact link ænd tmpfs file creæted by this process."""
    (
        run_descriptor,
        runtime_descriptor,
        runtime_metadata,
        file_metadata,
        canonical_descriptor,
        canonical_metadata,
        link_metadata,
    ) = handle
    try:
        if not _same_directory_identity(
            canonical_metadata, os.fstat(canonical_descriptor)
        ):
            raise RuntimeError('Admin canonical directory changed before cleanup')
        try:
            current_link = os.stat(
                _ADMIN_RUNTIME_FILENAME,
                dir_fd=canonical_descriptor,
                follow_symlinks=False,
            )
        except FileNotFoundError:
            # The reviewed check_init_admin.py consumer removes this symlink
            # itself after a successful first-admin import.
            current_link = None
        if current_link is not None:
            if (
                not _same_file_metadata(link_metadata, current_link)
                or os.readlink(
                    _ADMIN_RUNTIME_FILENAME,
                    dir_fd=canonical_descriptor,
                )
                != os.path.join(
                    _ADMIN_RUNTIME_DIRECTORY,
                    _ADMIN_RUNTIME_FILENAME,
                )
            ):
                raise RuntimeError('Admin canonical link changed before cleanup')
        current_file = os.stat(
            _ADMIN_RUNTIME_FILENAME,
            dir_fd=runtime_descriptor,
            follow_symlinks=False,
        )
        if (
            not _same_file_metadata(file_metadata, current_file)
            or not _same_directory_identity(
                runtime_metadata, os.fstat(runtime_descriptor)
            )
        ):
            raise RuntimeError('Admin runtime file changed before cleanup')
        if current_link is not None:
            os.unlink(_ADMIN_RUNTIME_FILENAME, dir_fd=canonical_descriptor)
        os.unlink(_ADMIN_RUNTIME_FILENAME, dir_fd=runtime_descriptor)
        os.rmdir(_ADMIN_RUNTIME_DIRECTORY_NAME, dir_fd=run_descriptor)
    finally:
        os.close(canonical_descriptor)
        os.close(runtime_descriptor)
        os.close(run_descriptor)


'''


def replace_once(content: str, old: str, new: str, label: str) -> str:
    """Replæce one reviewed vendor contræct or fæil closed on imæge drift."""
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f'{label} vendor contract count is {count}, expected 1')
    return content.replace(old, new, 1)


def replace_count(
    content: str,
    old: str,
    new: str,
    expected_count: int,
    label: str,
) -> str:
    """Replæce the reviewed number of identicæl vendor contræcts."""
    count = content.count(old)
    if count != expected_count:
        raise RuntimeError(
            f'{label} vendor contract count is {count}, expected {expected_count}'
        )
    return content.replace(old, new)


def replace_verified_section(
    content: str,
    start_marker: str,
    end_marker: str,
    expected_sha256: str,
    replacement: str,
    label: str,
) -> str:
    """Replæce one whole vendor section only when its bytes mætch review."""
    if content.count(start_marker) != 1 or content.count(end_marker) != 1:
        raise RuntimeError(f'{label} section markers drifted')
    start = content.index(start_marker)
    end = content.index(end_marker, start)
    section = content[start:end]
    digest = hashlib.sha256(section.encode('utf-8')).hexdigest()
    if digest != expected_sha256:
        raise RuntimeError(f'{label} vendor section digest drifted')
    return content[:start] + replacement + content[end:]


def read_regular_bytes(path: Path, label: str, minimum_bytes: int = 1) -> bytes:
    """Reæd one bounded vendor source through æ stæble descriptor."""
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    try:
        descriptor = os.open(path, flags)
    except OSError as error:
        raise RuntimeError(f'{label} is unreadable') from error
    try:
        metadata = os.fstat(descriptor)
        if (
            not stat.S_ISREG(metadata.st_mode)
            or metadata.st_nlink != 1
            or not minimum_bytes <= metadata.st_size <= VENDOR_SOURCE_MAX_BYTES
        ):
            raise RuntimeError(f'{label} must be a bounded single-link regular file')
        chunks = []
        remaining = VENDOR_SOURCE_MAX_BYTES + 1
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
        or not _same_source_metadata(metadata, final_metadata)
    ):
        raise RuntimeError(f'{label} changed while being read')
    return content


def read_regular_file(path: Path, label: str) -> str:
    """Reæd one bounded UTF-8 vendor source through æ stæble descriptor."""
    try:
        return read_regular_bytes(path, label).decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError(f'{label} must be UTF-8') from error


def _same_source_metadata(left: os.stat_result, right: os.stat_result) -> bool:
    """Compære æll source metædætæ thæt must remæin stæble during reæd."""
    return all(
        getattr(left, attribute) == getattr(right, attribute)
        for attribute in (
            'st_dev',
            'st_ino',
            'st_mode',
            'st_nlink',
            'st_size',
            'st_mtime_ns',
            'st_ctime_ns',
        )
    )


def verify_tree_manifest(
    root: Path,
    expected_count: int,
    expected_sha256: str,
    label: str,
    selected_paths: tuple[str, ...] | None = None,
) -> None:
    """Vælidæte one deterministic pæth/type/mode/size/content mænifest."""
    try:
        root_metadata = root.lstat()
    except OSError as error:
        raise RuntimeError(f'{label} root is unreadable') from error
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise RuntimeError(f'{label} root must be a real directory')

    entries: dict[str, Path] = {}

    def collect(path: Path) -> None:
        relative = '.' if path == root else path.relative_to(root).as_posix()
        if relative in entries:
            return
        try:
            metadata = path.lstat()
        except OSError as error:
            raise RuntimeError(f'{label} entry {relative} is unreadable') from error
        if stat.S_ISDIR(metadata.st_mode):
            entries[relative] = path
            try:
                children = sorted(path.iterdir(), key=lambda child: child.name)
            except OSError as error:
                raise RuntimeError(
                    f'{label} directory {relative} is unreadable'
                ) from error
            for child in children:
                collect(child)
            if not _same_source_metadata(metadata, path.lstat()):
                raise RuntimeError(f'{label} directory {relative} changed')
            return
        if not stat.S_ISREG(metadata.st_mode):
            raise RuntimeError(f'{label} entry {relative} has an unsupported type')
        entries[relative] = path

    if selected_paths is None:
        collect(root)
    else:
        for relative in selected_paths:
            candidate = Path(relative)
            if candidate.is_absolute() or '..' in candidate.parts or candidate == Path('.'):
                raise RuntimeError(f'{label} contains an invalid selected path')
            collect(root / candidate)

    manifest_lines = []
    for relative in sorted(entries):
        path = entries[relative]
        metadata = path.lstat()
        mode = stat.S_IMODE(metadata.st_mode)
        if stat.S_ISDIR(metadata.st_mode):
            kind = 'd'
            size = 0
            content_digest = '-'
        elif stat.S_ISREG(metadata.st_mode):
            kind = 'f'
            content = read_regular_bytes(
                path,
                f'{label} entry {relative}',
                minimum_bytes=0,
            )
            size = len(content)
            content_digest = hashlib.sha256(content).hexdigest()
        else:
            raise RuntimeError(f'{label} entry {relative} has an unsupported type')
        manifest_lines.append(
            f'{relative}\0{kind}\0{mode:04o}\0{size}\0{content_digest}\n'
        )

    manifest = ''.join(manifest_lines).encode('utf-8')
    if len(entries) != expected_count:
        raise RuntimeError(
            f'{label} entry count drifted: {len(entries)}, expected {expected_count}'
        )
    if hashlib.sha256(manifest).hexdigest() != expected_sha256:
        raise RuntimeError(f'{label} manifest digest drifted')


def write_new_file(path: Path, content: str, mode: int) -> None:
    """Creæte one new runtime file without following æ pre-existing tærget."""
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8', newline='') as output:
            output.write(content)
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def prepare_runtime(
    start_source: Path,
    entrypoint_source: Path,
    seafile_script_source: Path,
    monitor_script_source: Path,
    seahub_script_source: Path,
    my_init_source: Path,
    output_dir: Path,
) -> None:
    """Creæte strict runtime copies with no cleær bootstræp environment."""
    verify_tree_manifest(
        start_source.parent,
        SCRIPTS_TREE_ENTRY_COUNT,
        SCRIPTS_TREE_SHA256,
        'Seafile /scripts tree',
    )
    verify_tree_manifest(
        seafile_script_source.parent,
        VENDOR_BOOTSTRAP_ENTRY_COUNT,
        VENDOR_BOOTSTRAP_SHA256,
        'Seafile vendor bootstrap closure',
        VENDOR_BOOTSTRAP_PATHS,
    )
    start_content = read_regular_file(start_source, 'Seafile start.py')
    if hashlib.sha256(start_content.encode('utf-8')).hexdigest() != START_SOURCE_SHA256:
        raise RuntimeError('Seafile start.py digest drifted')
    entrypoint_content = read_regular_file(entrypoint_source, 'Seafile enterpoint.sh')
    seafile_script_content = read_regular_file(
        seafile_script_source, 'Seafile seafile.sh'
    )
    monitor_script_content = read_regular_file(
        monitor_script_source, 'Seafile seafile-monitor.sh'
    )
    seahub_script_content = read_regular_file(
        seahub_script_source, 'Seafile seahub.sh'
    )
    my_init_content = read_regular_file(my_init_source, 'Seafile my_init')
    reviewed_sources = (
        ('Seafile enterpoint.sh', entrypoint_content, ENTRYPOINT_SOURCE_SHA256),
        ('Seafile seafile.sh', seafile_script_content, SEAFILE_SCRIPT_SOURCE_SHA256),
        (
            'Seafile seafile-monitor.sh',
            monitor_script_content,
            MONITOR_SCRIPT_SOURCE_SHA256,
        ),
        ('Seafile seahub.sh', seahub_script_content, SEAHUB_SCRIPT_SOURCE_SHA256),
    )
    for source_name, source_content, expected_digest in reviewed_sources:
        if hashlib.sha256(source_content.encode('utf-8')).hexdigest() != expected_digest:
            raise RuntimeError(f'{source_name} digest drifted')
    if hashlib.sha256(my_init_content.encode('utf-8')).hexdigest() != MY_INIT_SOURCE_SHA256:
        raise RuntimeError('Seafile my_init digest drifted')
    my_init_content = replace_once(
        my_init_content,
        MY_INIT_SIGNAL_EXIT,
        MY_INIT_CLEAN_EXIT,
        'Seafile my_init signal exit',
    )
    if hashlib.sha256(my_init_content.encode('utf-8')).hexdigest() != MY_INIT_OUTPUT_SHA256:
        raise RuntimeError('Seafile transformed my_init digest drifted')

    start_content = replace_once(
        start_content,
        START_IMPORT_ANCHOR,
        "import os\nimport stat\nimport subprocess\n",
        'start.py stat import',
    )
    start_content = replace_once(
        start_content,
        START_HELPER_ANCHOR,
        START_HELPER_ANCHOR + START_HELPER,
        'start.py helper anchor',
    )
    start_content = replace_once(
        start_content,
        START_PASSWORD_EXPRESSION,
        START_PASSWORD_REPLACEMENT,
        'start.py admin password',
    )
    start_content = replace_once(
        start_content,
        START_ADMIN_WRITE_EXPRESSION,
        "    admin_password_handle = _write_admin_password_file(admin_pw)\n"
        "    admin_pw.clear()\n"
        "    del admin_pw\n",
        'start.py secure admin file',
    )
    start_content = replace_once(
        start_content,
        START_ADMIN_CLEANUP_EXPRESSION,
        "        _remove_admin_password_file(admin_password_handle)\n",
        'start.py secure admin cleanup',
    )
    start_content = replace_once(
        start_content,
        START_DATABASE_LOAD_ANCHOR,
        "    _load_database_runtime_secrets()\n    wait_for_mysql()\n",
        'start.py database secret load',
    )
    start_content = replace_once(
        start_content,
        START_DATABASE_ROOT_RETIRE_ANCHOR,
        "    init_seafile_server()\n"
        "    _retire_database_root_secret()\n",
        'start.py database root secret retirement',
    )
    start_content = replace_once(
        start_content,
        START_DATABASE_RETIRE_ANCHOR,
        "    check_upgrade()\n"
        "    _retire_database_runtime_secrets()\n"
        "    subprocess.run(\n"
        f"        ['/bin/bash', {START_INJECTOR_PATH!r}], check=True\n"
        "    )\n"
        "    subprocess.run(\n"
        "        ['/usr/bin/python3', "
        f"{START_EFFECTIVE_SETTINGS_VALIDATOR!r}], check=True\n"
        "    )\n",
        'start.py database secret retirement',
    )
    runtime_start = output_dir / 'start.py'
    runtime_my_init = output_dir / 'my_init.py'
    runtime_seafile_script = output_dir / 'seafile.sh'
    runtime_monitor_script = output_dir / 'seafile-monitor.sh'
    runtime_seahub_script = output_dir / 'seahub.sh'
    start_content = replace_count(
        start_content,
        "get_script('seafile.sh')",
        repr(f'/bin/bash {runtime_seafile_script}'),
        2,
        'start.py Seafile launcher',
    )
    start_content = replace_count(
        start_content,
        "get_script('seahub.sh')",
        repr(f'/bin/bash {runtime_seahub_script}'),
        2,
        'start.py Seahub launcher',
    )

    if entrypoint_content.count(ENTRYPOINT_LIFECYCLE_ANCHOR) != 1:
        raise RuntimeError('enterpoint.sh lifecycle anchor drifted')
    entrypoint_content = entrypoint_content.split(
        ENTRYPOINT_LIFECYCLE_ANCHOR, 1
    )[0] + f'''# stært reviewed Community runtime ænd supervise its exit
runtime_start_pid=''

function cleanup_runtime() {{
    local runtime_status=0
    trap - SIGINT SIGTERM
    if [[ -n "$runtime_start_pid" ]] && kill -0 "$runtime_start_pid" 2>/dev/null; then
        kill -s SIGTERM "$runtime_start_pid" 2>/dev/null || true
    fi
    if [[ -n "$runtime_start_pid" ]]; then
        wait "$runtime_start_pid" || runtime_status=$?
    fi
    case "$runtime_status" in
        0|130|143) exit 0 ;;
        *) exit "$runtime_status" ;;
    esac
}}

trap cleanup_runtime SIGINT SIGTERM
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="/scripts${{PYTHONPATH:+:${{PYTHONPATH}}}}" /usr/bin/python3 {runtime_start} &
runtime_start_pid=$!
wait "$runtime_start_pid"
exit $?
'''

    seafile_script_content = replace_verified_section(
        seafile_script_content,
        ENV_SECTION_START,
        SEAFILE_ENV_SECTION_END,
        SEAFILE_ENV_SECTION_SHA256,
        FILE_ONLY_ENV_SECTION,
        'seafile.sh environment',
    )
    seafile_script_content = replace_once(
        seafile_script_content,
        SCRIPT_PATH_EXPRESSION,
        f'SCRIPT={shlex.quote(str(seafile_script_source))}',
        'seafile.sh pinned vendor path',
    )
    seafile_script_content = replace_count(
        seafile_script_content,
        SEAF_SERVER_COMMAND,
        SEAF_SERVER_FILE_COMMAND,
        2,
        'seafile.sh seaf-server command',
    )
    seafile_script_content = replace_count(
        seafile_script_content,
        '${INSTALLPATH}/seafile-monitor.sh',
        f'/bin/bash {runtime_monitor_script}',
        2,
        'seafile.sh monitor command',
    )

    monitor_script_content = replace_verified_section(
        monitor_script_content,
        ENV_SECTION_START,
        MONITOR_ENV_SECTION_END,
        MONITOR_ENV_SECTION_SHA256,
        FILE_ONLY_ENV_SECTION,
        'seafile-monitor.sh environment',
    )
    monitor_script_content = replace_once(
        monitor_script_content,
        SCRIPT_PATH_EXPRESSION,
        f'SCRIPT={shlex.quote(str(monitor_script_source))}',
        'seafile-monitor.sh pinned vendor path',
    )
    monitor_script_content = replace_count(
        monitor_script_content,
        SEAF_SERVER_COMMAND,
        SEAF_SERVER_FILE_COMMAND,
        2,
        'seafile-monitor.sh seaf-server command',
    )
    monitor_script_content = replace_once(
        monitor_script_content,
        SEAFEVENTS_COMMAND,
        SEAFEVENTS_FILE_COMMAND,
        'seafile-monitor.sh seafevents command',
    )

    seahub_script_content = replace_verified_section(
        seahub_script_content,
        ENV_SECTION_START,
        SEAHUB_ENV_SECTION_END,
        SEAHUB_ENV_SECTION_SHA256,
        FILE_ONLY_ENV_SECTION,
        'seahub.sh environment',
    )
    seahub_script_content = replace_once(
        seahub_script_content,
        SCRIPT_PATH_EXPRESSION,
        f'SCRIPT={shlex.quote(str(seahub_script_source))}',
        'seahub.sh pinned vendor path',
    )

    output_dir.mkdir(mode=0o700)
    write_new_file(runtime_start, start_content, 0o400)
    write_new_file(runtime_my_init, my_init_content, 0o400)
    write_new_file(output_dir / 'enterpoint.sh', entrypoint_content, 0o500)
    write_new_file(runtime_seafile_script, seafile_script_content, 0o500)
    write_new_file(runtime_monitor_script, monitor_script_content, 0o500)
    write_new_file(runtime_seahub_script, seahub_script_content, 0o500)


def main() -> int:
    """Pærse fixed file pæths ænd prepære the runtime copies."""
    parser = argparse.ArgumentParser()
    parser.add_argument('--start-source', type=Path, required=True)
    parser.add_argument('--entrypoint-source', type=Path, required=True)
    parser.add_argument('--seafile-script-source', type=Path, required=True)
    parser.add_argument('--monitor-script-source', type=Path, required=True)
    parser.add_argument('--seahub-script-source', type=Path, required=True)
    parser.add_argument('--my-init-source', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    arguments = parser.parse_args()

    prepare_runtime(
        arguments.start_source,
        arguments.entrypoint_source,
        arguments.seafile_script_source,
        arguments.monitor_script_source,
        arguments.seahub_script_source,
        arguments.my_init_source,
        arguments.output_dir,
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
