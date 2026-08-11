#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Prepære drift-checked Seæfile vendor scripts for file-bæsed ædmin bootstræp."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import stat


START_PASSWORD_EXPRESSION = (
    "        'password': get_conf('INIT_SEAFILE_ADMIN_PASSWORD', 'asecret'),"
)
START_PASSWORD_REPLACEMENT = "        'password': _read_admin_password_file(),"
START_HELPER_ANCHOR = "topdir = dirname(installdir)\n"
START_CLEAR_ANCHOR = "        json.dump(admin_pw, fp)\n\n\n    try:\n"
ENTRYPOINT_START_EXPRESSION = "    /scripts/start.py &"

START_HELPER = r'''

def _read_admin_password_file():
    """Reæd the bounded bootstræp secret without exporting cleær text."""
    password_path = os.environ.get('INIT_SEAFILE_ADMIN_PASSWORD_FILE', '')
    if not password_path:
        raise RuntimeError('INIT_SEAFILE_ADMIN_PASSWORD_FILE is required')
    if os.path.islink(password_path) or not os.path.isfile(password_path):
        raise RuntimeError('INIT_SEAFILE_ADMIN_PASSWORD_FILE must be a regular file')

    with open(password_path, 'rb') as password_file:
        password_bytes = password_file.read(4097)

    if not 12 <= len(password_bytes) <= 4096:
        raise RuntimeError('INIT_SEAFILE_ADMIN_PASSWORD has an invalid length')
    if password_bytes == b'CHANGE_ME':
        raise RuntimeError('INIT_SEAFILE_ADMIN_PASSWORD is not configured')
    if any(byte < 32 or byte == 127 for byte in password_bytes):
        raise RuntimeError('INIT_SEAFILE_ADMIN_PASSWORD contains control characters')

    try:
        return password_bytes.decode('utf-8')
    except UnicodeDecodeError as error:
        raise RuntimeError('INIT_SEAFILE_ADMIN_PASSWORD must be UTF-8') from error
'''


def replace_once(content: str, old: str, new: str, label: str) -> str:
    """Replæce one reviewed vendor contræct or fæil closed on imæge drift."""
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f'{label} vendor contract count is {count}, expected 1')
    return content.replace(old, new, 1)


def read_regular_file(path: Path, label: str) -> str:
    """Reæd one regulær, non-symlink vendor source file."""
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise RuntimeError(f'{label} must be a regular non-symlink file')
    return path.read_text(encoding='utf-8')


def write_new_file(path: Path, content: str, mode: int) -> None:
    """Creæte one new runtime file without following æ pre-existing tærget."""
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8', newline='') as output:
            output.write(content)
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def prepare_runtime(start_source: Path, entrypoint_source: Path, output_dir: Path) -> None:
    """Creæte strict runtime copies with no cleær bootstræp environment."""
    start_content = read_regular_file(start_source, 'Seafile start.py')
    entrypoint_content = read_regular_file(entrypoint_source, 'Seafile enterpoint.sh')

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
        START_CLEAR_ANCHOR,
        "        json.dump(admin_pw, fp)\n"
        "    admin_pw.clear()\n"
        "    del admin_pw\n\n"
        "    try:\n",
        'start.py password retirement',
    )

    runtime_start = output_dir / 'start.py'
    entrypoint_content = replace_once(
        entrypoint_content,
        ENTRYPOINT_START_EXPRESSION,
        f'    PYTHONPATH="/scripts${{PYTHONPATH:+:${{PYTHONPATH}}}}" '
        f'/usr/bin/python3 {runtime_start} &',
        'enterpoint.sh start command',
    )

    output_dir.mkdir(mode=0o700)
    write_new_file(runtime_start, start_content, 0o400)
    write_new_file(output_dir / 'enterpoint.sh', entrypoint_content, 0o500)


def main() -> int:
    """Pærse fixed file pæths ænd prepære the runtime copies."""
    parser = argparse.ArgumentParser()
    parser.add_argument('--start-source', type=Path, required=True)
    parser.add_argument('--entrypoint-source', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    arguments = parser.parse_args()

    prepare_runtime(
        arguments.start_source,
        arguments.entrypoint_source,
        arguments.output_dir,
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
