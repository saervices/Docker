#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Fæil closed unless effective Seæhub settings include the reviewed policy."""

from __future__ import annotations

import hmac
import importlib
import os
from pathlib import Path
import re
import stat
import sys


_SECRET_DIRECTORY = Path('/run/secrets')
_SECRET_MAX_BYTES = 4096


def _fatal(message: str) -> None:
    raise RuntimeError(message)


def _read_secret(name: str, minimum_bytes: int = 1) -> str:
    """Reæd one bounded Docker secret through æ stæble descriptor."""
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)
    try:
        descriptor = os.open(_SECRET_DIRECTORY / name, flags)
    except OSError as error:
        raise RuntimeError(f'Docker secret {name} is unreadable') from error
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            _fatal(f'Docker secret {name} must be a single-link regular file')
        if not minimum_bytes <= metadata.st_size <= _SECRET_MAX_BYTES:
            _fatal(f'Docker secret {name} has an invalid length')
        chunks = []
        remaining = _SECRET_MAX_BYTES + 1
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
        _fatal(f'Docker secret {name} changed while being read')
    try:
        value = content.decode('utf-8', errors='strict')
    except UnicodeDecodeError as error:
        raise RuntimeError(f'Docker secret {name} must be UTF-8') from error
    if value == 'CHANGE_ME':
        _fatal(f'Docker secret {name} is not configured')
    if any(
        ord(character) < 0x20
        or 0x7F <= ord(character) <= 0x9F
        or ord(character) in (0x2028, 0x2029)
        for character in value
    ):
        _fatal(f'Docker secret {name} contains control or line characters')
    return value


def _require_equal(actual: object, expected: object, label: str) -> None:
    if actual != expected:
        _fatal(f'Effective Seahub setting {label} is not active')


def _require_secret_equal(actual: object, secret_name: str) -> None:
    if not isinstance(actual, str) or not hmac.compare_digest(
        actual, _read_secret(secret_name)
    ):
        _fatal(f'Effective Seahub secret mapping {secret_name} is not active')


def _prepare_vendor_import(vendor_root: Path | None = None) -> None:
    """Prepære the exæct drift-gæted vendor Python import environment."""
    server_name = os.environ.get('SEAFILE_SERVER', 'seafile-server')
    version = os.environ.get('SEAFILE_VERSION', '')
    if server_name not in ('seafile-server', 'seafile-pro-server'):
        _fatal('SEAFILE_SERVER does not identify a supported vendor tree')
    if not re.fullmatch(r'[0-9A-Za-z._-]+', version):
        _fatal('SEAFILE_VERSION is invalid')
    root = Path('/opt/seafile') if vendor_root is None else vendor_root
    install_path = root / f'{server_name}-{version}'
    required_paths = (
        install_path / 'seafile/lib/python3/site-packages',
        install_path / 'seahub',
        install_path / 'seahub/thirdpart',
        install_path / 'pro/python',
    )
    for path in required_paths:
        if not path.is_dir():
            _fatal(f'Required Seafile vendor import path is unavailable: {path}')
    optional_paths = (install_path / 'seafile/lib64/python3/site-packages',)
    import_paths = required_paths[:1] + optional_paths + required_paths[1:3]
    for path in reversed(import_paths):
        if path.is_dir():
            sys.path.insert(0, str(path))
    pro_python = install_path / 'pro/python'
    sys.path.append(str(pro_python))

    exact_environment = {
        'SEAHUB_DIR': str(install_path / 'seahub'),
        'SEAFES_DIR': str(pro_python / 'seafes'),
    }
    for name, expected in exact_environment.items():
        inherited = os.environ.get(name)
        if inherited is not None and inherited != expected:
            _fatal(f'{name} does not match the reviewed Seafile vendor path')
        os.environ[name] = expected

    os.environ['SEAFILE_DATA_DIR'] = str(root / 'seafile-data')
    os.environ['SEAFILE_CENTRAL_CONF_DIR'] = str(root / 'conf')
    os.environ['SEAFILE_RPC_PIPE_PATH'] = str(install_path / 'runtime')
    os.environ['DJANGO_SETTINGS_MODULE'] = 'seahub.settings'


def main() -> int:
    for name in (
        'JWT_PRIVATE_KEY',
        'SEAFILE_MYSQL_DB_PASSWORD',
        'REDIS_PASSWORD',
        'OAUTH_CLIENT_ID',
        'OAUTH_CLIENT_SECRET',
        'EMAIL_HOST_PASSWORD',
    ):
        if name in os.environ:
            _fatal(f'Plain secret environment {name} is forbidden')
    if 'SEAHUB_EXTRA_PREFLIGHT_ONLY' in os.environ:
        _fatal('SEAHUB_EXTRA_PREFLIGHT_ONLY is reserved for the direct preflight')

    break_glass = os.environ.get('ENABLE_LOCAL_BREAK_GLASS_LOGIN', 'false')
    if break_glass not in ('true', 'false'):
        _fatal('ENABLE_LOCAL_BREAK_GLASS_LOGIN must be exactly true or false')

    _prepare_vendor_import()
    settings = importlib.import_module('seahub.settings')
    expected_booleans = {
        'ENABLE_OAUTH': True,
        'ENABLE_SIGNUP': False,
        'OAUTH_CREATE_UNKNOWN_USER': False,
        'OAUTH_ACTIVATE_USER_AFTER_CREATION': False,
        'DISABLE_ADFS_USER_PWD_LOGIN': break_glass == 'false',
        'ENABLE_CHANGE_PASSWORD': False,
        'ENABLE_SSO_USER_CHANGE_PASSWORD': False,
        'ENABLE_GUEST_INVITATION': False,
        'ENABLE_WEBDAV_SECRET': False,
        'ENABLE_CUSTOM_OAUTH': False,
        'ENABLE_WORK_WEIXIN': False,
        'ENABLE_WEIXIN': False,
        'ENABLE_DINGTALK': False,
        'ENABLE_REMOTE_USER_AUTHENTICATION': False,
        'ENABLE_CAS': False,
        'ENABLE_ADFS_LOGIN': False,
        'ENABLE_MULTI_ADFS': False,
        'ENABLE_LDAP': False,
        'ENABLE_SHIB_LOGIN': False,
        'ENABLE_KRB5_LOGIN': False,
        'ENABLE_LOGIN_SIMPLE_CHECK': False,
        'ENABLE_DEMO_USER': False,
        'ENABLE_SUDO_MODE': True,
    }
    for name, expected in expected_booleans.items():
        _require_equal(getattr(settings, name, None), expected, name)

    provider_domain = os.environ.get('OAUTH_PROVIDER_DOMAIN', '')
    _require_equal(
        getattr(settings, 'OAUTH_PROVIDER_DOMAIN', None),
        provider_domain,
        'OAUTH_PROVIDER_DOMAIN',
    )
    _require_equal(
        getattr(settings, 'OAUTH_PROVIDER', None),
        provider_domain,
        'OAUTH_PROVIDER',
    )
    authentication_backends = tuple(
        getattr(settings, 'AUTHENTICATION_BACKENDS', ())
    )
    _require_equal(
        authentication_backends,
        (
            'seahub_settings_extra.SaervicesBreakGlassAuthBackend',
            'seahub.oauth.backends.OauthRemoteUserBackend',
        ),
        'AUTHENTICATION_BACKENDS exact policy',
    )
    _require_equal(
        getattr(settings, 'SAERVICES_BREAK_GLASS_ADMIN_USERNAME', None),
        os.environ.get('INIT_SEAFILE_ADMIN_EMAIL', ''),
        'SAERVICES_BREAK_GLASS_ADMIN_USERNAME',
    )
    _require_equal(
        getattr(settings, 'SESSION_COOKIE_NAME', None),
        'saervices_seafile_oidc_session_v1',
        'SESSION_COOKIE_NAME migration gate',
    )
    _require_equal(getattr(settings, 'SSO_SECRET_KEY', None), '', 'SSO_SECRET_KEY')

    database = getattr(settings, 'DATABASES', {}).get('default', {})
    cache = getattr(settings, 'CACHES', {}).get('default', {})
    cache_options = cache.get('OPTIONS', {})
    _require_secret_equal(database.get('PASSWORD'), 'MARIADB_PASSWORD')
    _require_secret_equal(cache_options.get('password'), 'REDIS_PASSWORD')
    _require_secret_equal(getattr(settings, 'JWT_PRIVATE_KEY', None), 'JWT_PRIVATE_KEY')
    _require_secret_equal(getattr(settings, 'OAUTH_CLIENT_ID', None), 'OAUTH_CLIENT_ID')
    _require_secret_equal(
        getattr(settings, 'OAUTH_CLIENT_SECRET', None), 'OAUTH_CLIENT_SECRET'
    )
    if 'PASSWORD' in cache_options:
        _fatal('Effective Seahub Redis options contain a legacy password key')
    if _read_secret('REDIS_PASSWORD') in str(cache.get('LOCATION', '')):
        _fatal('Effective Seahub Redis URL contains clear secret material')
    print('[seahub-effective-settings] OK: reviewed effective policy is active.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
