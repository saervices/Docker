#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""Isolæted regression tests for Seæfile's fæil-closed extræ settings."""

import hashlib
import json
import os
from pathlib import Path
import runpy
import socket
import stat
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import yaml


SETTINGS_PATH = Path(__file__).with_name('seahub_settings_extra.py')
COMPOSE_PATH = SETTINGS_PATH.parent.parent / 'docker-compose.app.yaml'
COMPONENT_PREFLIGHT_PATH = Path(__file__).with_name(
    'seafile-component-start.sh'
)
COMPONENT_PREPARER_PATH = Path(__file__).with_name(
    'prepare-seafile-component.py'
)
THUMBNAIL_LOADER_PATH = Path(__file__).with_name('thumbnail-file-loader.py')
IMPORT_ENFORCER_PATH = Path(__file__).with_name(
    'ensure-seahub-settings-import.py'
)
APP_PREFLIGHT_PATH = Path(__file__).with_name('seafile-start.sh')
SECRET_VALIDATOR_PATH = Path(__file__).with_name('validate-seafile-secrets.py')
RUNTIME_PREPARER_PATH = Path(__file__).with_name('prepare-seafile-runtime.py')
SEAFEVENTS_LOADER_PATH = Path(__file__).with_name('seafevents-file-loader.py')
RUNTIME_PREPARER = runpy.run_path(str(RUNTIME_PREPARER_PATH))
SEAFEVENTS_LOADER = runpy.run_path(str(SEAFEVENTS_LOADER_PATH))
COMPONENT_PREPARER = runpy.run_path(str(COMPONENT_PREPARER_PATH))
THUMBNAIL_LOADER = runpy.run_path(str(THUMBNAIL_LOADER_PATH))
IMPORT_ENFORCER = runpy.run_path(str(IMPORT_ENFORCER_PATH))
SECRET_VALIDATOR = runpy.run_path(str(SECRET_VALIDATOR_PATH))

VALID_ENVIRONMENT = {
    'OAUTH_PROVIDER_DOMAIN': 'https://auth.example.test',
    'OAUTH_APPLICATION_SLUG': 'seafile',
    'SEAFILE_SERVER_PROTOCOL': 'https',
    'SEAFILE_SERVER_HOSTNAME': 'seafile.example.test',
    'ENABLE_LOCAL_BREAK_GLASS_LOGIN': 'false',
    'INIT_SEAFILE_ADMIN_EMAIL': 'admin@auth.example.test',
    'ENABLE_GO_FILESERVER': 'false',
    'ENABLE_OFFICE_WEB_APP': 'false',
    'ENABLE_VIDEO_THUMBNAIL': 'false',
    'ENABLE_METADATA_MANAGEMENT': 'false',
    'ENABLE_EMAIL_NOTIFICATIONS': 'false',
    'MAX_UPLOAD_FILE_SIZE': '0',
    'MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD': '1000',
}

VALID_SECRETS = {
    'JWT_PRIVATE_KEY': '0123456789abcdef0123456789abcdef',
    'OAUTH_CLIENT_ID': 'provider-client-id',
    'OAUTH_CLIENT_SECRET': 'provider-client-secret',
    'EMAIL_HOST_PASSWORD': 'smtp-password',
    'MARIADB_PASSWORD': 'database-password',
    'REDIS_PASSWORD': 'redis-password',
}
MY_INIT_FIXTURE_SOURCE = (
    '#!/usr/bin/env python3\n'
    'try:\n'
    '    main(args)\n'
    'except KeyboardInterrupt:\n'
    '    warn("Init system aborted.")\n'
    '    exit(2)\n'
)


def load_settings(
    environment=None,
    secrets=None,
    secret_modes=None,
    module_name='__main__',
):
    """Execute the settings with ephemeræl Docker-secret fixtures."""
    effective_environment = dict(VALID_ENVIRONMENT)
    if environment:
        effective_environment.update(environment)

    effective_secrets = dict(VALID_SECRETS)
    if secrets:
        for name, value in secrets.items():
            if value is None:
                effective_secrets.pop(name, None)
            else:
                effective_secrets[name] = value

    effective_modes = dict(secret_modes or {})

    with tempfile.TemporaryDirectory(prefix='seahub-settings-secrets.') as directory:
        secret_directory = Path(directory)
        for name, value in effective_secrets.items():
            secret_path = secret_directory / name
            mode = effective_modes.get(name, stat.S_IFREG | 0o400)
            kind = 'regular'
            if isinstance(value, tuple):
                kind, value = value
            value_bytes = value if isinstance(value, bytes) else value.encode('utf-8')
            file_type = stat.S_IFMT(mode)
            if kind == 'symlink' or file_type == stat.S_IFLNK:
                target = secret_directory / f'.{name}.target'
                target.write_bytes(value_bytes)
                secret_path.symlink_to(target)
            elif kind == 'fifo' or file_type == stat.S_IFIFO:
                os.mkfifo(secret_path, mode & 0o777)
            elif kind == 'hardlink':
                target = secret_directory / f'.{name}.target'
                target.write_bytes(value_bytes)
                os.link(target, secret_path)
            else:
                secret_path.write_bytes(value_bytes)
                secret_path.chmod(mode & 0o777)

        source = SETTINGS_PATH.read_text(encoding='utf-8')
        directory_contract = "_SECRET_DIRECTORY = '/run/secrets'"
        if source.count(directory_contract) != 1:
            raise AssertionError('Seahub secret-directory contract drifted')
        source = source.replace(
            directory_contract,
            f'_SECRET_DIRECTORY = {str(secret_directory)!r}',
            1,
        )
        settings_code = compile(source, str(SETTINGS_PATH), 'exec')
        namespace = {
            '__file__': str(SETTINGS_PATH),
            '__name__': module_name,
            'DATABASES': {'default': {'PASSWORD': 'vendor-value'}},
            'CACHES': {
                'default': {
                    'LOCATION': 'redis://:vendor-value@redis:6379',
                    'OPTIONS': {'PASSWORD': 'vendor-value'},
                }
            },
        }
        with mock.patch.dict(os.environ, effective_environment, clear=True):
            exec(settings_code, namespace)
        return namespace


class SeahubSettingsTests(unittest.TestCase):
    def test_main_compose_prevents_vendor_bytecode_drift(self):
        compose = yaml.safe_load(COMPOSE_PATH.read_text(encoding='utf-8'))

        self.assertEqual(
            compose['services']['app']['environment'][
                'PYTHONDONTWRITEBYTECODE'
            ],
            '1',
        )

    def test_disabled_smtp_secret_is_not_mounted(self):
        compose_text = COMPOSE_PATH.read_text(encoding='utf-8')
        compose = yaml.safe_load(compose_text)
        app = compose['services']['app']
        mounted_secrets = {
            secret if isinstance(secret, str) else secret['source']
            for secret in app['secrets']
        }

        self.assertEqual(
            app['environment']['ENABLE_EMAIL_NOTIFICATIONS'],
            '${ENABLE_EMAIL_NOTIFICATIONS:-false}',
        )
        self.assertNotIn('EMAIL_HOST_PASSWORD', mounted_secrets)
        self.assertIn('# - EMAIL_HOST_PASSWORD', compose_text)
        required_services = set(compose['x-required-services'])
        self.assertNotIn('seafile_notification-server', required_services)
        self.assertNotIn('seafile_metadata-server', required_services)
        self.assertIn('seafile_seadoc-server', required_services)
        self.assertIn('seafile_thumbnail-server', required_services)

    def test_valid_closed_signup_oidc_policy(self):
        settings = load_settings()
        self.assertEqual(
            settings['DATABASES']['default']['PASSWORD'],
            VALID_SECRETS['MARIADB_PASSWORD'],
        )
        self.assertEqual(
            settings['CACHES']['default']['LOCATION'],
            'redis://redis:6379',
        )
        self.assertEqual(
            settings['CACHES']['default']['OPTIONS']['password'],
            VALID_SECRETS['REDIS_PASSWORD'],
        )
        self.assertNotIn('PASSWORD', settings['CACHES']['default']['OPTIONS'])
        self.assertNotIn(
            VALID_SECRETS['REDIS_PASSWORD'],
            settings['CACHES']['default']['LOCATION'],
        )
        self.assertEqual(settings['OAUTH_ATTRIBUTE_MAP']['sub'], (True, 'uid'))
        self.assertEqual(settings['OAUTH_ATTRIBUTE_MAP']['email'], (True, 'email'))
        self.assertFalse(settings['ENABLE_SIGNUP'])
        self.assertFalse(settings['OAUTH_CREATE_UNKNOWN_USER'])
        self.assertFalse(settings['OAUTH_ACTIVATE_USER_AFTER_CREATION'])
        self.assertFalse(settings['ENABLE_GLOBAL_ADDRESSBOOK'])
        self.assertFalse(settings['ENABLE_WEBDAV_SECRET'])
        self.assertEqual(
            settings['OAUTH_LOGOUT_URL'],
            'https://auth.example.test/application/o/seafile/end-session/',
        )
        self.assertEqual(settings['OAUTH_PROVIDER'], 'https://auth.example.test')
        self.assertEqual(
            settings['OAUTH_PROVIDER_DOMAIN'], 'https://auth.example.test'
        )
        self.assertTrue(settings['DISABLE_ADFS_USER_PWD_LOGIN'])
        self.assertFalse(settings['ENABLE_GUEST_INVITATION'])
        for disabled_auth_setting in (
            'ENABLE_CUSTOM_OAUTH',
            'ENABLE_WORK_WEIXIN',
            'ENABLE_WEIXIN',
            'ENABLE_DINGTALK',
            'ENABLE_REMOTE_USER_AUTHENTICATION',
            'ENABLE_CAS',
            'ENABLE_ADFS_LOGIN',
            'ENABLE_MULTI_ADFS',
            'ENABLE_LDAP',
            'ENABLE_SHIB_LOGIN',
            'ENABLE_KRB5_LOGIN',
            'ENABLE_LOGIN_SIMPLE_CHECK',
            'ENABLE_DEMO_USER',
        ):
            with self.subTest(disabled_auth_setting=disabled_auth_setting):
                self.assertFalse(settings[disabled_auth_setting])
        self.assertEqual(settings['SSO_SECRET_KEY'], '')
        self.assertTrue(settings['ENABLE_SUDO_MODE'])
        self.assertEqual(
            settings['SAERVICES_BREAK_GLASS_ADMIN_USERNAME'],
            'admin@auth.example.test',
        )
        self.assertEqual(
            settings['AUTHENTICATION_BACKENDS'],
            ('seahub_settings_extra.SaervicesBreakGlassAuthBackend',),
        )
        self.assertEqual(
            settings['SESSION_COOKIE_NAME'],
            'saervices_seafile_oidc_session_v1',
        )
        self.assertEqual(
            settings['SECURE_PROXY_SSL_HEADER'],
            ('HTTP_X_FORWARDED_PROTO', 'https'),
        )
        self.assertEqual(settings['SHARE_LINK_EXPIRE_DAYS_MIN'], 1)
        self.assertEqual(settings['SHARE_LINK_EXPIRE_DAYS_DEFAULT'], 7)
        self.assertEqual(settings['SHARE_LINK_EXPIRE_DAYS_MAX'], 90)
        self.assertEqual(settings['UPLOAD_LINK_EXPIRE_DAYS_MIN'], 1)
        self.assertEqual(settings['UPLOAD_LINK_EXPIRE_DAYS_DEFAULT'], 7)
        self.assertEqual(settings['UPLOAD_LINK_EXPIRE_DAYS_MAX'], 90)
        self.assertEqual(settings['MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD'], 1000)

    def test_valid_starttls_smtp(self):
        settings = load_settings(
            {
                'ENABLE_EMAIL_NOTIFICATIONS': 'true',
                'EMAIL_HOST': 'smtp.example.test',
                'EMAIL_PORT': '587',
                'EMAIL_USE_TLS': 'true',
                'EMAIL_USE_SSL': 'false',
                'EMAIL_HOST_USER': 'seafile@example.test',
                'DEFAULT_FROM_EMAIL': 'Seafile <seafile@example.test>',
                'SERVER_EMAIL': 'errors@example.test',
            }
        )
        self.assertTrue(settings['EMAIL_USE_TLS'])
        self.assertFalse(settings['EMAIL_USE_SSL'])
        self.assertEqual(settings['EMAIL_PORT'], 587)

    def test_invalid_environment_is_rejected(self):
        cases = (
            ({'OAUTH_PROVIDER_DOMAIN': 'http://auth.example.test'}, 'HTTPS origin'),
            ({'OAUTH_PROVIDER_DOMAIN': 'https://auth.example.test/path'}, 'HTTPS origin'),
            ({'OAUTH_PROVIDER_DOMAIN': 'https://authentik.example.com'}, 'placeholder'),
            ({'OAUTH_APPLICATION_SLUG': 'Sea_File'}, 'OAUTH_APPLICATION_SLUG'),
            ({'SEAFILE_SERVER_PROTOCOL': 'http'}, 'must be https'),
            ({'SEAFILE_SERVER_HOSTNAME': 'seafile.example.com'}, 'placeholder'),
            ({'ENABLE_OFFICE_WEB_APP': 'TRUE'}, 'exactly true or false'),
            ({'ENABLE_METADATA_MANAGEMENT': 'true'}, 'unavailable'),
            ({'INIT_SEAFILE_ADMIN_EMAIL': 'Admin@auth.example.test'}, 'lower-case'),
            ({'INIT_SEAFILE_ADMIN_EMAIL': 'admin@example.com'}, 'placeholder'),
            ({'MAX_UPLOAD_FILE_SIZE': '-1'}, 'decimal integer'),
            ({'MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD': '0'}, 'between 1 and 100000'),
        )
        for environment, message in cases:
            with self.subTest(environment=environment):
                with self.assertRaisesRegex(RuntimeError, message):
                    load_settings(environment)

    def test_invalid_smtp_is_rejected(self):
        baseline = {
            'ENABLE_EMAIL_NOTIFICATIONS': 'true',
            'EMAIL_HOST': 'smtp.example.test',
            'EMAIL_PORT': '587',
            'EMAIL_USE_TLS': 'true',
            'EMAIL_USE_SSL': 'false',
            'EMAIL_HOST_USER': 'seafile@example.test',
        }
        cases = (
            ({'EMAIL_HOST': 'smtp.example.com'}, 'placeholder'),
            ({'EMAIL_PORT': '0'}, 'between 1 and 65535'),
            ({'EMAIL_USE_SSL': 'true'}, 'Exactly one'),
            ({'EMAIL_USE_TLS': 'false'}, 'Exactly one'),
            ({'EMAIL_HOST_USER': ''}, 'EMAIL_HOST_USER is required'),
        )
        for override, message in cases:
            environment = dict(baseline)
            environment.update(override)
            with self.subTest(override=override):
                with self.assertRaisesRegex(RuntimeError, message):
                    load_settings(environment)

        with self.assertRaisesRegex(RuntimeError, 'must be mounted'):
            load_settings(baseline, {'EMAIL_HOST_PASSWORD': None})

    def test_invalid_secret_files_are_rejected(self):
        cases = (
            ({'JWT_PRIVATE_KEY': 'too-short'}, {}, 'invalid length'),
            ({'OAUTH_CLIENT_ID': 'CHANGE_ME'}, {}, 'not configured'),
            ({'OAUTH_CLIENT_ID': 'line\nbreak'}, {}, 'control or line'),
            ({'OAUTH_CLIENT_ID': 'x' * 4097}, {}, 'invalid length'),
            ({}, {'OAUTH_CLIENT_ID': stat.S_IFLNK | 0o777}, 'unreadable'),
            ({'OAUTH_CLIENT_ID': ('fifo', b'ignored')}, {}, 'single-link regular'),
            ({'OAUTH_CLIENT_ID': ('hardlink', b'linked-secret')}, {}, 'single-link'),
            ({'OAUTH_CLIENT_ID': b'bad-utf8-\xff'}, {}, 'must be UTF-8'),
            ({'OAUTH_CLIENT_ID': 'control-\u0080'}, {}, 'control or line'),
            ({'OAUTH_CLIENT_ID': 'line-\u2028'}, {}, 'control or line'),
        )
        for secrets, modes, message in cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(RuntimeError, message):
                    load_settings(secrets=secrets, secret_modes=modes)

        for plain_name in (
            'SEAFILE_MYSQL_DB_PASSWORD',
            'REDIS_PASSWORD',
            'EMAIL_HOST_PASSWORD',
        ):
            with self.subTest(plain_name=plain_name):
                with self.assertRaisesRegex(RuntimeError, plain_name):
                    load_settings({plain_name: 'plain-environment-secret'})

        break_glass = load_settings(
            {'ENABLE_LOCAL_BREAK_GLASS_LOGIN': 'true'}
        )
        self.assertFalse(break_glass['DISABLE_ADFS_USER_PWD_LOGIN'])

        with self.assertRaisesRegex(RuntimeError, 'reserved for the direct preflight'):
            load_settings(
                {'SEAHUB_EXTRA_PREFLIGHT_ONLY': 'true'},
                module_name='seahub_settings_extra',
            )

    def test_break_glass_backend_is_canonical_admin_only(self):
        closed_settings = load_settings()
        closed_backend = closed_settings['SaervicesBreakGlassAuthBackend']()
        vendor_backend = mock.Mock()
        canonical = SimpleNamespace(
            username='admin@auth.example.test',
            is_active=True,
            is_staff=True,
        )
        vendor_backend.authenticate.return_value = canonical
        vendor_backend.get_user.return_value = canonical
        with mock.patch.object(
            closed_backend,
            '_vendor_backend',
            return_value=vendor_backend,
        ):
            self.assertIsNone(
                closed_backend.authenticate(
                    username='admin@auth.example.test', password='valid-password'
                )
            )
            self.assertIsNone(
                closed_backend.get_user('admin@auth.example.test')
            )
        vendor_backend.assert_not_called()

        open_settings = load_settings(
            {'ENABLE_LOCAL_BREAK_GLASS_LOGIN': 'true'}
        )
        open_backend = open_settings['SaervicesBreakGlassAuthBackend']()
        cases = (
            (canonical, canonical),
            (
                SimpleNamespace(
                    username='other-admin@auth.example.test',
                    is_active=True,
                    is_staff=True,
                ),
                None,
            ),
            (
                SimpleNamespace(
                    username='admin@auth.example.test',
                    is_active=False,
                    is_staff=True,
                ),
                None,
            ),
            (
                SimpleNamespace(
                    username='admin@auth.example.test',
                    is_active=True,
                    is_staff=False,
                ),
                None,
            ),
        )
        for user, expected in cases:
            with self.subTest(user=user):
                backend = mock.Mock()
                backend.authenticate.return_value = user
                backend.get_user.return_value = user
                with mock.patch.object(
                    open_backend,
                    '_vendor_backend',
                    return_value=backend,
                ):
                    self.assertIs(
                        open_backend.authenticate(
                            username='admin@auth.example.test',
                            password='valid-password',
                        ),
                        expected,
                    )
                    self.assertIs(
                        open_backend.get_user('admin@auth.example.test'),
                        expected,
                    )

        vendor_backend = mock.Mock()
        with mock.patch.object(
            open_backend,
            '_vendor_backend',
            return_value=vendor_backend,
        ):
            self.assertIsNone(
                open_backend.authenticate(
                    username='other-admin@auth.example.test',
                    password='valid-password',
                )
            )
            self.assertIsNone(
                open_backend.authenticate(remote_user='oidc-subject')
            )
            self.assertIsNone(
                open_backend.get_user('other-admin@auth.example.test')
            )
        vendor_backend.assert_not_called()


class ComponentPreflightTests(unittest.TestCase):
    def test_effective_validator_prepares_exact_vendor_paths(self):
        validator = runpy.run_path(
            str(Path(__file__).with_name('validate-seahub-effective-settings.py'))
        )
        prepare_vendor_import = validator['_prepare_vendor_import']
        with tempfile.TemporaryDirectory(
            prefix='seafile-effective-vendor.'
        ) as directory:
            root = Path(directory)
            install = root / 'seafile-server-13.0.25'
            for relative in (
                'seafile/lib/python3/site-packages',
                'seahub',
                'seahub/thirdpart',
                'pro/python',
            ):
                (install / relative).mkdir(parents=True, exist_ok=True)

            original_path = list(os.sys.path)
            try:
                with mock.patch.dict(
                    os.environ,
                    {
                        'SEAFILE_SERVER': 'seafile-server',
                        'SEAFILE_VERSION': '13.0.25',
                    },
                    clear=True,
                ):
                    prepare_vendor_import(root)
                    self.assertEqual(
                        os.environ['SEAHUB_DIR'], str(install / 'seahub')
                    )
                    self.assertEqual(
                        os.environ['SEAFES_DIR'], str(install / 'pro/python/seafes')
                    )
                    self.assertEqual(
                        os.environ['SEAFILE_CENTRAL_CONF_DIR'], str(root / 'conf')
                    )

                with mock.patch.dict(
                    os.environ,
                    {
                        'SEAFILE_SERVER': 'seafile-server',
                        'SEAFILE_VERSION': '13.0.25',
                        'SEAHUB_DIR': '/tmp/unreviewed-seahub',
                    },
                    clear=True,
                ):
                    with self.assertRaisesRegex(RuntimeError, 'SEAHUB_DIR'):
                        prepare_vendor_import(root)

                (install / 'seahub/thirdpart').rmdir()
                with mock.patch.dict(
                    os.environ,
                    {
                        'SEAFILE_SERVER': 'seafile-server',
                        'SEAFILE_VERSION': '13.0.25',
                    },
                    clear=True,
                ):
                    with self.assertRaisesRegex(
                        RuntimeError, 'vendor import path is unavailable'
                    ):
                        prepare_vendor_import(root)
            finally:
                os.sys.path[:] = original_path

    def test_seafevents_loader_is_drift_locked_and_file_safe(self):
        source = (
            "import os\n"
            + SEAFEVENTS_LOADER['_REDIS_EXPRESSION']
            + "\n"
            + SEAFEVENTS_LOADER['_DATABASE_EXPRESSION']
            + "\n"
        )
        loader_globals = SEAFEVENTS_LOADER['transform_source'].__globals__
        original_digest = loader_globals['_SOURCE_SHA256']
        loader_globals['_SOURCE_SHA256'] = hashlib.sha256(
            source.encode('utf-8')
        ).hexdigest()
        try:
            transformed = SEAFEVENTS_LOADER['transform_source'](source)
            self.assertNotIn("os.environ.get('REDIS_PASSWORD'", transformed)
            self.assertNotIn(
                "os.environ.get('SEAFILE_MYSQL_DB_PASSWORD'", transformed
            )
            self.assertIn("seahub_settings.CACHES['default']", transformed)
            self.assertIn("seahub_settings.DATABASES['default']", transformed)
            with self.assertRaisesRegex(RuntimeError, 'digest drifted'):
                SEAFEVENTS_LOADER['transform_source'](source + '# drift\n')
        finally:
            loader_globals['_SOURCE_SHA256'] = original_digest

        with tempfile.TemporaryDirectory(prefix='seafevents-source.') as directory:
            fixture = Path(directory)
            source_path = fixture / 'config.py'
            source_path.write_text(source, encoding='utf-8')
            self.assertEqual(
                SEAFEVENTS_LOADER['_read_vendor_source'](source_path), source
            )

            hardlink = fixture / 'hardlink.py'
            os.link(source_path, hardlink)
            with self.assertRaisesRegex(RuntimeError, 'bounded regular file'):
                SEAFEVENTS_LOADER['_read_vendor_source'](source_path)
            hardlink.unlink()

            link = fixture / 'symlink.py'
            link.symlink_to(source_path)
            with self.assertRaises(OSError):
                SEAFEVENTS_LOADER['_read_vendor_source'](link)

            original_fstat = os.fstat
            calls = 0

            def changing_fstat(descriptor):
                nonlocal calls
                metadata = original_fstat(descriptor)
                calls += 1
                if calls != 2:
                    return metadata
                return SimpleNamespace(
                    st_dev=metadata.st_dev,
                    st_ino=metadata.st_ino,
                    st_mode=metadata.st_mode,
                    st_nlink=metadata.st_nlink,
                    st_size=metadata.st_size,
                    st_mtime_ns=metadata.st_mtime_ns,
                    st_ctime_ns=metadata.st_ctime_ns + 1,
                )

            with mock.patch.object(os, 'fstat', side_effect=changing_fstat):
                with self.assertRaisesRegex(RuntimeError, 'changed while being read'):
                    SEAFEVENTS_LOADER['_read_vendor_source'](source_path)

    def test_app_runtime_is_file_only_after_shell_preflight(self):
        wrapper = APP_PREFLIGHT_PATH.read_text(encoding='utf-8')
        forbidden_handoffs = (
            'export JWT_PRIVATE_KEY',
            'export SEAFILE_MYSQL_DB_PASSWORD',
            'export INIT_SEAFILE_MYSQL_ROOT_PASSWORD',
            'export REDIS_PASSWORD',
            'export SEAFILE_SEASEARCH_ADMIN_PASSWORD',
        )
        for handoff in forbidden_handoffs:
            with self.subTest(handoff=handoff):
                self.assertNotIn(handoff, wrapper)
        self.assertIn('--my-init-source /sbin/my_init', wrapper)
        self.assertIn(
            'exec /usr/bin/python3 -u "${SEAFILE_RUNTIME_DIR}/my_init.py" --',
            wrapper,
        )

    def test_seahub_import_is_atomic_exactly_once_and_file_safe(self):
        ensure_import = IMPORT_ENFORCER['ensure_import']
        import_line = IMPORT_ENFORCER['_IMPORT_LINE']
        with tempfile.TemporaryDirectory(prefix='seahub-import.') as directory:
            fixture = Path(directory)
            settings = fixture / 'seahub_settings.py'
            settings.write_text('SERVICE_URL = "https://seafile.test"\n', encoding='utf-8')
            settings.chmod(0o640)
            self.assertTrue(ensure_import(settings))
            first_bytes = settings.read_bytes()
            first_inode = settings.stat().st_ino
            self.assertEqual(
                settings.read_text(encoding='utf-8').splitlines().count(import_line),
                1,
            )
            self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o640)
            self.assertFalse(ensure_import(settings))
            self.assertEqual(settings.read_bytes(), first_bytes)
            self.assertEqual(settings.stat().st_ino, first_inode)
            self.assertFalse(any(fixture.glob('.seahub_settings.py.import.*')))

            commented = fixture / 'commented.py'
            commented.write_text(
                f'# {import_line}\nSERVICE_URL = "https://seafile.test"\n',
                encoding='utf-8',
            )
            self.assertTrue(ensure_import(commented))
            commented_lines = commented.read_text(encoding='utf-8').splitlines()
            self.assertEqual(commented_lines.count(import_line), 1)

            multiline_string = fixture / 'multiline-string.py'
            multiline_string.write_text(
                'BANNER = """\n'
                f'{import_line}\n'
                '"""\n',
                encoding='utf-8',
            )
            self.assertTrue(ensure_import(multiline_string))
            multiline_source = multiline_string.read_text(encoding='utf-8')
            self.assertEqual(
                IMPORT_ENFORCER['_validate_import_contract'](multiline_source),
                1,
            )

            hostile_sources = (
                (f'{import_line}\n{import_line}\n', 'duplicate active'),
                (f'  {import_line}\n', 'not valid Python'),
                (f'{import_line}  # hidden drift\n', 'non-canonical active'),
            )
            for index, (source, message) in enumerate(hostile_sources):
                with self.subTest(message=message):
                    hostile = fixture / f'hostile-{index}.py'
                    hostile.write_text(source, encoding='utf-8')
                    before = hostile.read_bytes()
                    with self.assertRaisesRegex(RuntimeError, message):
                        ensure_import(hostile)
                    self.assertEqual(hostile.read_bytes(), before)

            symlink = fixture / 'symlink.py'
            symlink.symlink_to(settings)
            with self.assertRaises(OSError):
                ensure_import(symlink)

            hardlink = fixture / 'hardlink.py'
            os.link(settings, hardlink)
            with self.assertRaisesRegex(RuntimeError, 'single-link'):
                ensure_import(settings)
            hardlink.unlink()

            invalid = fixture / 'invalid.py'
            invalid.write_bytes(b'bad-utf8-\xff')
            with self.assertRaisesRegex(RuntimeError, 'strict UTF-8'):
                ensure_import(invalid)

            writable = fixture / 'writable.py'
            writable.write_text('SETTING = True\n', encoding='utf-8')
            writable.chmod(0o666)
            with self.assertRaisesRegex(RuntimeError, 'non-writable'):
                ensure_import(writable)

    def test_runtime_preparer_loads_then_retires_database_secrets(self):
        helper_namespace = {'os': os, 'stat': stat}

        with tempfile.TemporaryDirectory(prefix='seafile-runtime-secret.') as directory:
            secret_directory = Path(directory)
            data_directory = secret_directory / 'shared/seafile/seafile-data'
            helper_source = RUNTIME_PREPARER['START_HELPER'].replace(
                "_RUNTIME_SECRET_DIRECTORY = '/run/secrets'",
                f'_RUNTIME_SECRET_DIRECTORY = {str(secret_directory)!r}',
                1,
            ).replace(
                "_SEAFILE_DATA_DIRECTORY = '/shared/seafile/seafile-data'",
                f'_SEAFILE_DATA_DIRECTORY = {str(data_directory)!r}',
                1,
            )
            exec(helper_source, helper_namespace)
            (secret_directory / 'MARIADB_PASSWORD').write_bytes(
                'database-pässword'.encode('utf-8')
            )
            (secret_directory / 'MARIADB_ROOT_PASSWORD').write_bytes(
                b'database-root-password'
            )
            (secret_directory / 'INIT_SEAFILE_ADMIN_PASSWORD').write_bytes(
                b'strong-admin-password'
            )
            with mock.patch.dict(
                os.environ,
                {},
                clear=True,
            ):
                helper_namespace['_load_database_runtime_secrets']()
                self.assertEqual(
                    os.environ['SEAFILE_MYSQL_DB_PASSWORD'],
                    'database-pässword',
                )
                self.assertIn('INIT_SEAFILE_MYSQL_ROOT_PASSWORD', os.environ)
                helper_namespace['_retire_database_root_secret']()
                self.assertNotIn('INIT_SEAFILE_MYSQL_ROOT_PASSWORD', os.environ)
                self.assertIn('SEAFILE_MYSQL_DB_PASSWORD', os.environ)
                helper_namespace['_retire_database_runtime_secrets']()
                self.assertNotIn('SEAFILE_MYSQL_DB_PASSWORD', os.environ)
                self.assertNotIn('INIT_SEAFILE_MYSQL_ROOT_PASSWORD', os.environ)
                self.assertNotIn('JWT_PRIVATE_KEY', os.environ)
                self.assertEqual(
                    helper_namespace['_read_admin_password_file'](),
                    'strong-admin-password',
                )

            data_directory.mkdir(parents=True)
            with mock.patch.dict(os.environ, {}, clear=True):
                helper_namespace['_load_database_runtime_secrets']()
                self.assertEqual(
                    os.environ['SEAFILE_MYSQL_DB_PASSWORD'],
                    'database-pässword',
                )
                self.assertNotIn(
                    'INIT_SEAFILE_MYSQL_ROOT_PASSWORD', os.environ
                )
                helper_namespace['_retire_database_runtime_secrets']()

            data_directory.rmdir()
            data_directory.symlink_to(secret_directory / 'missing-data')
            with mock.patch.dict(os.environ, {}, clear=True):
                with self.assertRaisesRegex(
                    RuntimeError, 'must be a real directory'
                ):
                    helper_namespace['_load_database_runtime_secrets']()

            with mock.patch.dict(
                os.environ,
                {
                    'SEAFILE_MYSQL_DB_PASSWORD': 'plain-environment-secret',
                },
                clear=True,
            ):
                with self.assertRaisesRegex(RuntimeError, 'Plain .* is forbidden'):
                    helper_namespace['_load_database_runtime_secrets']()

            hardlink = secret_directory / 'hardlink-secret'
            os.link(secret_directory / 'MARIADB_PASSWORD', hardlink)
            with mock.patch.dict(
                os.environ,
                {},
                clear=True,
            ):
                with self.assertRaisesRegex(RuntimeError, 'single-link regular file'):
                    helper_namespace['_read_runtime_secret']('MARIADB_PASSWORD', 1)

    def test_runtime_preparer_tree_manifest_rejects_all_drift(self):
        verify = RUNTIME_PREPARER['verify_tree_manifest']

        def expected_manifest(root):
            entries = [root, *root.rglob('*')]
            lines = []
            for path in sorted(
                entries,
                key=lambda item: (
                    '.' if item == root else item.relative_to(root).as_posix()
                ),
            ):
                metadata = path.lstat()
                relative = (
                    '.' if path == root else path.relative_to(root).as_posix()
                )
                mode = stat.S_IMODE(metadata.st_mode)
                if path.is_dir():
                    kind, size, digest = 'd', 0, '-'
                else:
                    content = path.read_bytes()
                    kind = 'f'
                    size = len(content)
                    digest = hashlib.sha256(content).hexdigest()
                lines.append(
                    f'{relative}\0{kind}\0{mode:04o}\0{size}\0{digest}\n'
                )
            payload = ''.join(lines).encode('utf-8')
            return len(entries), hashlib.sha256(payload).hexdigest()

        with tempfile.TemporaryDirectory(prefix='seafile-tree-manifest.') as directory:
            root = Path(directory) / 'tree'
            nested = root / 'nested'
            nested.mkdir(parents=True)
            source = root / 'source.py'
            child = nested / 'child.sh'
            empty_marker = root / 'package.marker'
            source.write_text('reviewed = True\n', encoding='utf-8')
            child.write_text('#!/bin/sh\nexit 0\n', encoding='utf-8')
            child.chmod(0o755)
            empty_marker.touch()
            count, digest = expected_manifest(root)
            verify(root, count, digest, 'synthetic tree')

            source.write_text('reviewed = False\n', encoding='utf-8')
            with self.assertRaisesRegex(RuntimeError, 'manifest digest drifted'):
                verify(root, count, digest, 'synthetic tree')
            source.write_text('reviewed = True\n', encoding='utf-8')

            extra = root / 'unexpected.py'
            extra.write_text('unexpected = True\n', encoding='utf-8')
            with self.assertRaisesRegex(RuntimeError, 'entry count drifted'):
                verify(root, count, digest, 'synthetic tree')
            extra.unlink()

            bytecode_directory = root / '__pycache__'
            bytecode_directory.mkdir()
            bytecode = bytecode_directory / 'source.cpython-312.pyc'
            bytecode.write_bytes(b'not-reviewed-bytecode')
            with self.assertRaisesRegex(RuntimeError, 'entry count drifted'):
                verify(root, count, digest, 'synthetic tree')
            bytecode.unlink()
            bytecode_directory.rmdir()

            child.unlink()
            with self.assertRaisesRegex(RuntimeError, 'entry count drifted'):
                verify(root, count, digest, 'synthetic tree')
            child.write_text('#!/bin/sh\nexit 0\n', encoding='utf-8')
            child.chmod(0o755)

            source.unlink()
            source.symlink_to(child)
            with self.assertRaisesRegex(RuntimeError, 'unsupported type'):
                verify(root, count, digest, 'synthetic tree')

    def test_runtime_preparer_transforms_exact_vendor_contract(self):
        start_source = (
            "#!/usr/bin/env python3\n"
            "import json\n"
            "import os\n"
            "from os.path import dirname\n"
            "installdir = '/opt/seafile/server'\n"
            "topdir = dirname(installdir)\n"
            "def main():\n"
            "    wait_for_mysql()\n"
            "    init_seafile_server()\n"
            "    check_upgrade()\n"
            "    admin_pw = {\n"
            "        'password': get_conf('INIT_SEAFILE_ADMIN_PASSWORD', 'asecret'),\n"
            "    }\n"
            "    password_file = join(topdir, 'conf', 'admin.txt')\n"
            "    with open(password_file, 'w') as fp:\n"
            "        json.dump(admin_pw, fp)\n\n\n"
            "    try:\n"
            "        call('{}'.format(get_script('seafile.sh')))\n"
            "        call('{}'.format(get_script('seahub.sh')))\n"
            "        call('{}'.format(get_script('seafile.sh')))\n"
            "        call('{}'.format(get_script('seahub.sh')))\n"
            "    finally:\n"
            "        if exists(password_file):\n"
            "            os.unlink(password_file)\n"
            "    print('seafile server is running now.')\n"
        )
        entrypoint_source = (
            "#!/bin/bash\n"
            "# start cluster server\n"
            "    /scripts/start.py &\n"
            "while [ 1 ]; do sleep 60; done\n"
        )
        vendor_environment = (
            "function set_env_config () {\n"
            "    export JWT_PRIVATE_KEY=vendor-secret\n"
            "}\n\n"
        )
        vendor_script_header = 'SCRIPT=$(readlink -f "$0")\n'
        seafile_script_source = (
            vendor_script_header
            + vendor_environment
            + RUNTIME_PREPARER['SEAFILE_ENV_SECTION_END']
            + "\n"
            + RUNTIME_PREPARER['SEAF_SERVER_COMMAND'] * 2
            + "        ${INSTALLPATH}/seafile-monitor.sh &\n"
            + "        ${INSTALLPATH}/seafile-monitor.sh &>> /tmp/log\n"
        )
        monitor_script_source = (
            vendor_script_header
            + vendor_environment
            + RUNTIME_PREPARER['MONITOR_ENV_SECTION_END']
            + "\n"
            + RUNTIME_PREPARER['SEAF_SERVER_COMMAND'] * 2
            + RUNTIME_PREPARER['SEAFEVENTS_COMMAND']
        )
        seahub_script_source = (
            vendor_script_header
            + vendor_environment
            + RUNTIME_PREPARER['SEAHUB_ENV_SECTION_END']
            + "\n"
        )
        my_init_source = MY_INIT_FIXTURE_SOURCE

        with tempfile.TemporaryDirectory(prefix='seafile-runtime-transform.') as directory:
            fixture = Path(directory)
            start_path = fixture / 'start.py'
            entrypoint_path = fixture / 'enterpoint.sh'
            seafile_script_path = fixture / 'seafile.sh'
            monitor_script_path = fixture / 'seafile-monitor.sh'
            seahub_script_path = fixture / 'seahub.sh'
            my_init_path = fixture / 'my_init'
            output_path = fixture / 'runtime'
            start_path.write_text(start_source, encoding='utf-8')
            entrypoint_path.write_text(entrypoint_source, encoding='utf-8')
            seafile_script_path.write_text(seafile_script_source, encoding='utf-8')
            monitor_script_path.write_text(monitor_script_source, encoding='utf-8')
            seahub_script_path.write_text(seahub_script_source, encoding='utf-8')
            my_init_path.write_text(my_init_source, encoding='utf-8')

            preparer_globals = RUNTIME_PREPARER['prepare_runtime'].__globals__
            original_manifest_verifier = preparer_globals['verify_tree_manifest']
            original_hashes = (
                preparer_globals['START_SOURCE_SHA256'],
                preparer_globals['ENTRYPOINT_SOURCE_SHA256'],
                preparer_globals['SEAFILE_SCRIPT_SOURCE_SHA256'],
                preparer_globals['MONITOR_SCRIPT_SOURCE_SHA256'],
                preparer_globals['SEAHUB_SCRIPT_SOURCE_SHA256'],
                preparer_globals['SEAFILE_ENV_SECTION_SHA256'],
                preparer_globals['MONITOR_ENV_SECTION_SHA256'],
                preparer_globals['SEAHUB_ENV_SECTION_SHA256'],
                preparer_globals['MY_INIT_SOURCE_SHA256'],
                preparer_globals['MY_INIT_OUTPUT_SHA256'],
            )
            synthetic_hash = hashlib.sha256(
                vendor_environment.encode('utf-8')
            ).hexdigest()
            preparer_globals['SEAFILE_ENV_SECTION_SHA256'] = synthetic_hash
            preparer_globals['MONITOR_ENV_SECTION_SHA256'] = synthetic_hash
            preparer_globals['SEAHUB_ENV_SECTION_SHA256'] = synthetic_hash
            preparer_globals['verify_tree_manifest'] = lambda *args, **kwargs: None
            preparer_globals['START_SOURCE_SHA256'] = hashlib.sha256(
                start_source.encode('utf-8')
            ).hexdigest()
            preparer_globals['ENTRYPOINT_SOURCE_SHA256'] = hashlib.sha256(
                entrypoint_source.encode('utf-8')
            ).hexdigest()
            preparer_globals['SEAFILE_SCRIPT_SOURCE_SHA256'] = hashlib.sha256(
                seafile_script_source.encode('utf-8')
            ).hexdigest()
            preparer_globals['MONITOR_SCRIPT_SOURCE_SHA256'] = hashlib.sha256(
                monitor_script_source.encode('utf-8')
            ).hexdigest()
            preparer_globals['SEAHUB_SCRIPT_SOURCE_SHA256'] = hashlib.sha256(
                seahub_script_source.encode('utf-8')
            ).hexdigest()
            preparer_globals['MY_INIT_SOURCE_SHA256'] = hashlib.sha256(
                my_init_source.encode('utf-8')
            ).hexdigest()
            transformed_my_init = my_init_source.replace(
                RUNTIME_PREPARER['MY_INIT_SIGNAL_EXIT'],
                RUNTIME_PREPARER['MY_INIT_CLEAN_EXIT'],
                1,
            )
            preparer_globals['MY_INIT_OUTPUT_SHA256'] = hashlib.sha256(
                transformed_my_init.encode('utf-8')
            ).hexdigest()

            try:
                RUNTIME_PREPARER['prepare_runtime'](
                    start_path,
                    entrypoint_path,
                    seafile_script_path,
                    monitor_script_path,
                    seahub_script_path,
                    my_init_path,
                    output_path,
                )
                entrypoint_path.write_text(
                    entrypoint_source + '# unrelated vendor drift\n',
                    encoding='utf-8',
                )
                with self.assertRaisesRegex(RuntimeError, 'enterpoint.sh digest drifted'):
                    RUNTIME_PREPARER['prepare_runtime'](
                        start_path,
                        entrypoint_path,
                        seafile_script_path,
                        monitor_script_path,
                        seahub_script_path,
                        my_init_path,
                        fixture / 'drift-output',
                    )
                entrypoint_path.write_text(entrypoint_source, encoding='utf-8')
                my_init_path.write_text(
                    my_init_source + '# unrelated vendor drift\n',
                    encoding='utf-8',
                )
                with self.assertRaisesRegex(RuntimeError, 'my_init digest drifted'):
                    RUNTIME_PREPARER['prepare_runtime'](
                        start_path,
                        entrypoint_path,
                        seafile_script_path,
                        monitor_script_path,
                        seahub_script_path,
                        my_init_path,
                        fixture / 'my-init-drift-output',
                    )
                for case_name, hostile_source in (
                    (
                        'missing',
                        my_init_source.replace(
                            RUNTIME_PREPARER['MY_INIT_SIGNAL_EXIT'],
                            'except RuntimeError:\n    exit(2)\n',
                        ),
                    ),
                    (
                        'duplicate',
                        my_init_source + RUNTIME_PREPARER['MY_INIT_SIGNAL_EXIT'],
                    ),
                ):
                    with self.subTest(my_init_anchor=case_name):
                        my_init_path.write_text(hostile_source, encoding='utf-8')
                        preparer_globals['MY_INIT_SOURCE_SHA256'] = hashlib.sha256(
                            hostile_source.encode('utf-8')
                        ).hexdigest()
                        with self.assertRaisesRegex(
                            RuntimeError,
                            'my_init signal exit vendor contract count',
                        ):
                            RUNTIME_PREPARER['prepare_runtime'](
                                start_path,
                                entrypoint_path,
                                seafile_script_path,
                                monitor_script_path,
                                seahub_script_path,
                                my_init_path,
                                fixture / f'my-init-{case_name}-output',
                            )
            finally:
                (
                    preparer_globals['START_SOURCE_SHA256'],
                    preparer_globals['ENTRYPOINT_SOURCE_SHA256'],
                    preparer_globals['SEAFILE_SCRIPT_SOURCE_SHA256'],
                    preparer_globals['MONITOR_SCRIPT_SOURCE_SHA256'],
                    preparer_globals['SEAHUB_SCRIPT_SOURCE_SHA256'],
                    preparer_globals['SEAFILE_ENV_SECTION_SHA256'],
                    preparer_globals['MONITOR_ENV_SECTION_SHA256'],
                    preparer_globals['SEAHUB_ENV_SECTION_SHA256'],
                    preparer_globals['MY_INIT_SOURCE_SHA256'],
                    preparer_globals['MY_INIT_OUTPUT_SHA256'],
                ) = original_hashes
                preparer_globals['verify_tree_manifest'] = original_manifest_verifier

            transformed = (output_path / 'start.py').read_text(encoding='utf-8')
            self.assertIn('    _load_database_runtime_secrets()\n    wait_for_mysql()', transformed)
            self.assertIn(
                '    init_seafile_server()\n'
                '    _retire_database_root_secret()',
                transformed,
            )
            self.assertIn(
                '    check_upgrade()\n'
                '    _retire_database_runtime_secrets()\n'
                '    subprocess.run(\n'
                "        ['/bin/bash', '/usr/local/bin/inject_extra_settings.sh'], check=True",
                transformed,
            )
            self.assertIn(
                "['/usr/bin/python3', "
                "'/usr/local/bin/validate-seahub-effective-settings.py'], check=True",
                transformed,
            )
            transformed_entrypoint = (output_path / 'enterpoint.sh').read_text(
                encoding='utf-8'
            )
            transformed_my_init = (output_path / 'my_init.py').read_text(
                encoding='utf-8'
            )
            self.assertIn('Init system stopped cleanly.', transformed_my_init)
            self.assertIn('    exit(0)\n', transformed_my_init)
            self.assertNotIn('    exit(2)\n', transformed_my_init)
            self.assertIn('wait "$runtime_start_pid"', transformed_entrypoint)
            self.assertIn('exit "$runtime_status"', transformed_entrypoint)
            self.assertIn('PYTHONDONTWRITEBYTECODE=1', transformed_entrypoint)
            self.assertNotIn('idle script', transformed_entrypoint)
            self.assertNotIn('/scripts/start.py &', transformed_entrypoint)
            self.assertNotIn("with open(password_file, 'w')", transformed)
            self.assertIn('_write_admin_password_file(admin_pw)', transformed)
            self.assertIn('_remove_admin_password_file(admin_password_handle)', transformed)
            self.assertNotIn('_load_signing_runtime_secret', transformed)
            self.assertNotIn(
                "get_conf('INIT_SEAFILE_ADMIN_PASSWORD', 'asecret')",
                transformed,
            )
            compile(transformed, str(output_path / 'start.py'), 'exec')
            self.assertEqual(stat.S_IMODE((output_path / 'start.py').stat().st_mode), 0o400)
            self.assertEqual(stat.S_IMODE((output_path / 'enterpoint.sh').stat().st_mode), 0o500)
            for script_name in ('seafile.sh', 'seafile-monitor.sh', 'seahub.sh'):
                script = (output_path / script_name).read_text(encoding='utf-8')
                self.assertNotIn('export JWT_PRIVATE_KEY', script)
                self.assertIn('JWT_PRIVATE_KEY_FILE', script)
                self.assertNotIn('readlink -f "$0"', script)
                self.assertIn(f'SCRIPT={fixture / script_name}', script)
                self.assertEqual(
                    stat.S_IMODE((output_path / script_name).stat().st_mode),
                    0o500,
                )
            self.assertEqual(
                (output_path / 'seafile.sh').read_text(encoding='utf-8').count(
                    '/usr/local/lib/libseafile-jwt-file.so'
                ),
                2,
            )
            self.assertEqual(
                (output_path / 'seafile-monitor.sh').read_text(encoding='utf-8').count(
                    '/usr/local/lib/libseafile-jwt-file.so'
                ),
                2,
            )
            self.assertIn(
                'PYTHONPATH=/usr/local/lib/seafile-runtime:${PYTHONPATH}',
                (output_path / 'seafile-monitor.sh').read_text(encoding='utf-8'),
            )

    def run_app_runtime_preflight(
        self,
        secrets=None,
        environment=None,
        pro_marker=False,
        full_start=False,
    ):
        effective_secrets = {
            'OAUTH_CLIENT_ID': b'provider-client-id',
            'OAUTH_CLIENT_SECRET': b'provider-client-secret',
            'EMAIL_HOST_PASSWORD': b'smtp-password',
            'INIT_SEAFILE_ADMIN_PASSWORD': b'strong-admin-password',
            'JWT_PRIVATE_KEY': b'0123456789abcdef0123456789abcdef',
            'MARIADB_PASSWORD': b'database-password',
            'MARIADB_ROOT_PASSWORD': b'database-root-password',
            'REDIS_PASSWORD': b'redis-password',
            'SEAFILE_SEASEARCH_ADMIN_PASSWORD': b'seasearch-password',
        }
        if secrets:
            effective_secrets.update(secrets)

        with tempfile.TemporaryDirectory(prefix='seafile-app-test.') as directory:
            secret_directory = Path(directory)
            for name, value in effective_secrets.items():
                if value is not None:
                    (secret_directory / name).write_bytes(value)

            settings_source = SETTINGS_PATH.read_text(encoding='utf-8')
            directory_contract = "_SECRET_DIRECTORY = '/run/secrets'"
            if settings_source.count(directory_contract) != 1:
                raise AssertionError('Seahub secret-directory contract drifted')
            settings_fixture = secret_directory / 'seahub_settings_extra.py'
            settings_fixture.write_text(
                settings_source.replace(
                    directory_contract,
                    f'_SECRET_DIRECTORY = {str(secret_directory)!r}',
                    1,
                ),
                encoding='utf-8',
            )
            validator_source = SECRET_VALIDATOR_PATH.read_text(encoding='utf-8')
            validator_contract = "_SECRET_DIRECTORY = Path('/run/secrets')"
            if validator_source.count(validator_contract) != 1:
                raise AssertionError('Seafile validator directory contract drifted')
            validator_fixture = secret_directory / 'validate-seafile-secrets.py'
            validator_fixture.write_text(
                validator_source.replace(
                    validator_contract,
                    f'_SECRET_DIRECTORY = Path({str(secret_directory)!r})',
                    1,
                ),
                encoding='utf-8',
            )
            wrapper_source = APP_PREFLIGHT_PATH.read_text(encoding='utf-8')
            wrapper_source = wrapper_source.replace(
                "readonly SEAFILE_SECRET_DIR='/run/secrets'",
                f"readonly SEAFILE_SECRET_DIR='{secret_directory}'",
                1,
            ).replace(
                "readonly SEAFILE_SECRET_VALIDATOR='/usr/local/bin/validate-seafile-secrets.py'",
                f"readonly SEAFILE_SECRET_VALIDATOR='{validator_fixture}'",
                1,
            )
            if pro_marker:
                vendor_root = secret_directory / 'vendor'
                (vendor_root / 'seafile-server-13.0.25').mkdir(parents=True)
                (vendor_root / 'seafile-pro-server-marker').mkdir()
                vendor_directory_contract = (
                    'readonly SEAFILE_VENDOR_DIR="/opt/seafile/'
                    '${SEAFILE_VENDOR_SERVER_NAME}-${SEAFILE_VENDOR_VERSION}"'
                )
                marker_contract = (
                    'for seafile_pro_marker in '
                    '/opt/seafile/seafile-pro-server-*; do'
                )
                if wrapper_source.count(vendor_directory_contract) != 1:
                    raise AssertionError('Seafile vendor-directory contract drifted')
                if wrapper_source.count(marker_contract) != 1:
                    raise AssertionError('Seafile Pro-marker contract drifted')
                wrapper_source = wrapper_source.replace(
                    vendor_directory_contract,
                    'readonly SEAFILE_VENDOR_DIR="'
                    f'{vendor_root}/'
                    '${SEAFILE_VENDOR_SERVER_NAME}-${SEAFILE_VENDOR_VERSION}"',
                    1,
                ).replace(
                    marker_contract,
                    f'for seafile_pro_marker in {vendor_root}/seafile-pro-server-*; do',
                    1,
                )
            wrapper_fixture = secret_directory / 'seafile-start.sh'
            wrapper_fixture.write_text(wrapper_source, encoding='utf-8')

            effective_environment = os.environ.copy()
            effective_environment.update(VALID_ENVIRONMENT)
            effective_environment.update(
                {
                    'SEAHUB_EXTRA_SETTINGS_FILE': str(settings_fixture),
                }
            )
            if environment:
                for name, value in environment.items():
                    if value is None:
                        effective_environment.pop(name, None)
                    else:
                        effective_environment[name] = value
            return subprocess.run(
                ['/bin/sh', str(wrapper_fixture)]
                + ([] if full_start else ['--runtime-preflight-only']),
                check=False,
                capture_output=True,
                text=True,
                env=effective_environment,
            )

    def test_app_runtime_preflight_integration(self):
        valid_result = self.run_app_runtime_preflight()
        self.assertEqual(valid_result.returncode, 0, valid_result.stderr)

        invalid_secret = self.run_app_runtime_preflight(
            {'MARIADB_PASSWORD': b'database-password\n'}
        )
        self.assertNotEqual(invalid_secret.returncode, 0)
        self.assertIn('control or line characters', invalid_secret.stderr)

        invalid_boolean = self.run_app_runtime_preflight(
            environment={'ENABLE_GO_FILESERVER': 'TRUE'}
        )
        self.assertNotEqual(invalid_boolean.returncode, 0)
        self.assertIn('exactly true or false', invalid_boolean.stderr)

        inherited_preflight = self.run_app_runtime_preflight(
            environment={'SEAHUB_EXTRA_PREFLIGHT_ONLY': 'true'}
        )
        self.assertNotEqual(inherited_preflight.returncode, 0)
        self.assertIn('reserved for the direct settings preflight', inherited_preflight.stderr)

        clear_email_secret = self.run_app_runtime_preflight(
            environment={'EMAIL_HOST_PASSWORD': 'plain-environment-secret'}
        )
        self.assertNotEqual(clear_email_secret.returncode, 0)
        self.assertIn('EMAIL_HOST_PASSWORD', clear_email_secret.stderr)

        unsupported_non_root = self.run_app_runtime_preflight(
            environment={'NON_ROOT': 'true'}
        )
        self.assertNotEqual(unsupported_non_root.returncode, 0)
        self.assertIn('secure first-admin bridge', unsupported_non_root.stderr)

        unsupported_go_fileserver = self.run_app_runtime_preflight(
            environment={'ENABLE_GO_FILESERVER': 'true'}
        )
        self.assertNotEqual(unsupported_go_fileserver.returncode, 0)
        self.assertIn('Go fileserver', unsupported_go_fileserver.stderr)

        unsupported_webdav = self.run_app_runtime_preflight(
            environment={'ENABLE_SEAFDAV': 'true'}
        )
        self.assertNotEqual(unsupported_webdav.returncode, 0)
        self.assertIn('WebDAV controller', unsupported_webdav.stderr)

        missing_go_fileserver = self.run_app_runtime_preflight(
            environment={'ENABLE_GO_FILESERVER': None}
        )
        self.assertNotEqual(missing_go_fileserver.returncode, 0)
        self.assertIn('exactly true or false', missing_go_fileserver.stderr)

        disguised_pro = self.run_app_runtime_preflight(
            environment={
                'SEAFILE_SERVER': 'seafile-server',
                'SEAFILE_VERSION': '13.0.25',
            },
            pro_marker=True,
            full_start=True,
        )
        self.assertNotEqual(disguised_pro.returncode, 0)
        self.assertIn('Seafile Pro is unavailable', disguised_pro.stderr)

        invalid_origin = self.run_app_runtime_preflight(
            environment={'OAUTH_PROVIDER_DOMAIN': 'https://authentik.example.com'}
        )
        self.assertNotEqual(invalid_origin.returncode, 0)
        self.assertIn('placeholder', invalid_origin.stderr)

        for feature in ('ENABLE_NOTIFICATION_SERVER', 'ENABLE_METADATA_MANAGEMENT'):
            with self.subTest(feature=feature):
                unavailable = self.run_app_runtime_preflight(
                    environment={feature: 'true'}
                )
                self.assertNotEqual(unavailable.returncode, 0)
                self.assertIn('unavailable', unavailable.stderr)

    def test_app_validator_rejects_every_required_secret_failure(self):
        minimum_lengths = {
            'OAUTH_CLIENT_ID': 1,
            'OAUTH_CLIENT_SECRET': 12,
            'INIT_SEAFILE_ADMIN_PASSWORD': 12,
            'JWT_PRIVATE_KEY': 32,
            'MARIADB_PASSWORD': 12,
            'MARIADB_ROOT_PASSWORD': 12,
            'REDIS_PASSWORD': 12,
            'SEAFILE_SEASEARCH_ADMIN_PASSWORD': 12,
        }
        invalid_values = (
            ('missing', None),
            ('empty', b''),
            ('placeholder', b'CHANGE_ME'),
            ('multiline', b'valid-first-line\nsecond-line'),
            ('control', b'valid-control-\x01-value'),
            ('invalid-utf8', b'valid-utf8-\xff-value'),
            ('oversize', b'x' * 4097),
        )
        for secret_name, minimum_length in minimum_lengths.items():
            cases = list(invalid_values)
            if minimum_length > 1:
                cases.append(('short', b'x' * (minimum_length - 1)))
            for case_name, value in cases:
                with self.subTest(secret=secret_name, case=case_name):
                    result = self.run_app_runtime_preflight(
                        {secret_name: value}
                    )
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertNotIn('valid-first-line', result.stderr)

    def test_app_validator_rejects_hostile_secret_file_types(self):
        globals_ = SECRET_VALIDATOR['read_secret'].__globals__
        original_directory = globals_['_SECRET_DIRECTORY']
        try:
            for case_name in ('symlink', 'fifo', 'hardlink'):
                with self.subTest(case=case_name), tempfile.TemporaryDirectory(
                    prefix=f'seafile-validator-{case_name}.'
                ) as directory:
                    secret_directory = Path(directory)
                    globals_['_SECRET_DIRECTORY'] = secret_directory
                    target = secret_directory / 'target'
                    target.write_bytes(b'valid-secret-value')
                    candidate = secret_directory / 'TEST_SECRET'
                    if case_name == 'symlink':
                        candidate.symlink_to(target)
                    elif case_name == 'fifo':
                        os.mkfifo(candidate)
                    else:
                        os.link(target, candidate)
                    with self.assertRaisesRegex(
                        RuntimeError,
                        'readable regular file|single-link regular file',
                    ):
                        SECRET_VALIDATOR['read_secret']('TEST_SECRET', 12)
        finally:
            globals_['_SECRET_DIRECTORY'] = original_directory

    def test_persisted_secret_scan_blocks_legacy_upgrade_state(self):
        globals_ = SECRET_VALIDATOR['scan_persisted_configuration'].__globals__
        original_directory = globals_['_PERSISTED_CONFIGURATION_DIRECTORY']
        secret_values = {
            'JWT_PRIVATE_KEY': b'0123456789abcdef0123456789abcdef',
            'MARIADB_PASSWORD': b'database-password',
            'REDIS_PASSWORD': b'redis-password',
            'OAUTH_CLIENT_ID': b'not-sensitive-client-id',
        }
        cases = (
            (
                'current-secret',
                'seahub_settings.py',
                b'DATABASE_PASSWORD = "database-password"\n',
                'current secret value',
            ),
            (
                'rotated-legacy-secret',
                'seafile.conf',
                b'[database]\npassword = legacy-rotated-value\n',
                'legacy secret assignment',
            ),
            (
                'legacy-python-secret',
                'seahub_settings.py',
                b'DATABASES = {"default": {"PASSWORD": "legacy-value"}}\n',
                'legacy secret assignment',
            ),
        )
        try:
            with tempfile.TemporaryDirectory(
                prefix='seafile-persisted-missing.'
            ) as directory:
                globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = (
                    Path(directory) / 'missing-conf'
                )
                SECRET_VALIDATOR['scan_persisted_configuration'](secret_values)

            for root_kind in ('symlink', 'fifo'):
                with self.subTest(root=root_kind), tempfile.TemporaryDirectory(
                    prefix=f'seafile-persisted-root-{root_kind}.'
                ) as directory:
                    fixture = Path(directory)
                    configuration = fixture / 'conf'
                    if root_kind == 'symlink':
                        target = fixture / 'target'
                        target.mkdir()
                        configuration.symlink_to(target)
                    else:
                        os.mkfifo(configuration)
                    globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                    with self.assertRaisesRegex(RuntimeError, 'must be a real directory'):
                        SECRET_VALIDATOR['scan_persisted_configuration'](
                            secret_values
                        )

            with tempfile.TemporaryDirectory(
                prefix='seafile-persisted-depth.'
            ) as directory:
                configuration = Path(directory)
                nested = configuration
                for depth in range(9):
                    nested = nested / f'depth-{depth}'
                    nested.mkdir()
                globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                with self.assertRaisesRegex(RuntimeError, 'tree is too deep'):
                    SECRET_VALIDATOR['scan_persisted_configuration'](
                        secret_values
                    )

            with tempfile.TemporaryDirectory(
                prefix='seafile-persisted-count.'
            ) as directory:
                configuration = Path(directory)
                for index in range(4097):
                    (configuration / f'entry-{index:04d}').touch()
                globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                with self.assertRaisesRegex(RuntimeError, 'tree is too large'):
                    SECRET_VALIDATOR['scan_persisted_configuration'](
                        secret_values
                    )

            with tempfile.TemporaryDirectory(
                prefix='seafile-persisted-identity.'
            ) as directory:
                configuration = Path(directory)
                globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                with mock.patch.object(
                    os,
                    'listdir',
                    side_effect=([], ['changed-entry']),
                ):
                    with self.assertRaisesRegex(
                        RuntimeError,
                        'tree changed while scanning',
                    ):
                        SECRET_VALIDATOR['scan_persisted_configuration'](
                            secret_values
                        )

            with tempfile.TemporaryDirectory(
                prefix='seafile-persisted-clean.'
            ) as directory:
                configuration = Path(directory)
                globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                (configuration / 'seahub_settings.py').write_bytes(
                    b'SERVICE_URL = "https://seafile.test"\n'
                )
                (configuration / 'seafevents.conf').symlink_to(
                    '/run/seafile-runtime-config/seafevents.conf'
                )
                (configuration / 'admin.txt').symlink_to(
                    '/run/seafile-admin/admin.txt'
                )
                SECRET_VALIDATOR['scan_persisted_configuration'](secret_values)

            bytecode_cases = (
                ('cache-directory', '__pycache__', 'directory'),
                ('regular-pyc', 'module.pyc', 'regular'),
                ('nested-pyo', 'nested/module.pyo', 'regular'),
                ('symlink-pyc', 'module.pyc', 'symlink'),
                ('fifo-pyo', 'module.pyo', 'fifo'),
                ('hardlink-pyc', 'module.pyc', 'hardlink'),
            )
            for case_name, relative_name, kind in bytecode_cases:
                with self.subTest(case=case_name), tempfile.TemporaryDirectory(
                    prefix=f'seafile-persisted-bytecode-{case_name}.'
                ) as directory:
                    configuration = Path(directory)
                    globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                    candidate = configuration / relative_name
                    candidate.parent.mkdir(parents=True, exist_ok=True)
                    if kind == 'directory':
                        candidate.mkdir()
                    elif kind == 'regular':
                        candidate.write_bytes(b'unreviewed-bytecode')
                    elif kind == 'symlink':
                        target = configuration / 'target'
                        target.write_bytes(b'unreviewed-bytecode')
                        candidate.symlink_to(target)
                    elif kind == 'fifo':
                        os.mkfifo(candidate)
                    else:
                        target = configuration / 'target'
                        target.write_bytes(b'unreviewed-bytecode')
                        os.link(target, candidate)
                    with self.assertRaisesRegex(
                        RuntimeError,
                        'persistent Seafile Python bytecode',
                    ):
                        SECRET_VALIDATOR['scan_persisted_configuration'](
                            secret_values
                        )

            for case_name, file_name, content, message in cases:
                with self.subTest(case=case_name), tempfile.TemporaryDirectory(
                    prefix=f'seafile-persisted-{case_name}.'
                ) as directory:
                    configuration = Path(directory)
                    globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                    (configuration / file_name).write_bytes(content)
                    with self.assertRaisesRegex(RuntimeError, message):
                        SECRET_VALIDATOR['scan_persisted_configuration'](
                            secret_values
                        )

            for case_name in ('symlink', 'fifo', 'hardlink'):
                with self.subTest(case=case_name), tempfile.TemporaryDirectory(
                    prefix=f'seafile-persisted-{case_name}.'
                ) as directory:
                    configuration = Path(directory)
                    globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = configuration
                    target = configuration / 'outside'
                    target.write_bytes(b'clean')
                    candidate = configuration / 'seahub_settings.py'
                    if case_name == 'symlink':
                        candidate.symlink_to(target)
                    elif case_name == 'fifo':
                        os.mkfifo(candidate)
                    else:
                        os.link(target, candidate)
                    with self.assertRaisesRegex(
                        RuntimeError,
                        'unexpected symbolic link|bounded single-link regular file',
                    ):
                        SECRET_VALIDATOR['scan_persisted_configuration'](
                            secret_values
                        )
        finally:
            globals_['_PERSISTED_CONFIGURATION_DIRECTORY'] = original_directory

    def test_file_only_component_contracts_and_unsupported_gates(self):
        wrapper = COMPONENT_PREFLIGHT_PATH.read_text(encoding='utf-8')
        for forbidden in (
            'export JWT_PRIVATE_KEY',
            'export DB_PASSWORD',
            'export SEAFILE_MYSQL_DB_PASSWORD',
            'SECRET_DIR',
            'wc -c',
            'cat "$secret_file"',
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, wrapper)
        self.assertIn('prepare-seafile-component.py', wrapper)
        self.assertIn('seafile-thumbnail-runtime/sitecustomize.py', wrapper)
        self.assertIn('export PYTHONDONTWRITEBYTECODE=1', wrapper)
        self.assertEqual(wrapper.count('/usr/bin/python3 -u'), 2)
        self.assertIn('/seadoc/my_init.py" --', wrapper)
        self.assertIn('/thumbnail/my_init.py" -- /bin/bash', wrapper)

        template_root = SETTINGS_PATH.parents[2] / 'templates'
        seadoc_compose = yaml.safe_load(
            (
                template_root
                / 'seafile_seadoc-server'
                / 'docker-compose.seafile_seadoc-server.yaml'
            ).read_text(encoding='utf-8')
        )
        self.assertEqual(
            seadoc_compose['services']['seafile_seadoc-server']['environment'][
                'PYTHONDONTWRITEBYTECODE'
            ],
            '1',
        )
        for name, service_name in (
            ('seafile_notification-server', 'seafile_notification-server'),
            ('seafile_metadata-server', 'seafile_metadata-server'),
        ):
            with self.subTest(template=name):
                compose_path = template_root / name / f'docker-compose.{name}.yaml'
                compose = yaml.safe_load(compose_path.read_text(encoding='utf-8'))
                service = compose['services'][service_name]
                self.assertNotIn('secrets', service)
                self.assertEqual(service['command'], ['/bin/false'])
                self.assertIn(service['entrypoint'][-1], ('notification', 'metadata'))

        for mode in ('notification', 'metadata'):
            result = subprocess.run(
                [
                    '/bin/sh',
                    str(COMPONENT_PREFLIGHT_PATH),
                    mode,
                    '/bin/false',
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('unavailable', result.stderr)

    def test_seadoc_file_only_runtime_files(self):
        globals_ = COMPONENT_PREPARER['prepare_seadoc'].__globals__
        original = {
            name: globals_[name]
            for name in (
                '_SECRET_DIRECTORY',
                '_RUNTIME_ROOT',
                '_SEADOC_CONFIG_LINK',
                '_SEADOC_CONVERTER_LINK',
                '_SEADOC_VENDOR_SOURCES',
                '_MY_INIT_SOURCE',
                '_MY_INIT_SOURCE_SHA256',
                '_MY_INIT_OUTPUT_SHA256',
            )
        }
        with tempfile.TemporaryDirectory(prefix='seadoc-file-only.') as directory:
            fixture = Path(directory)
            secret_directory = fixture / 'secrets'
            shared_directory = fixture / 'shared/conf'
            secret_directory.mkdir()
            shared_directory.mkdir(parents=True)
            (secret_directory / 'JWT_PRIVATE_KEY').write_bytes(
                b'0123456789abcdef0123456789abcdef'
            )
            (secret_directory / 'MARIADB_PASSWORD').write_bytes(
                'database-pässword'.encode('utf-8')
            )
            globals_['_SECRET_DIRECTORY'] = secret_directory
            globals_['_RUNTIME_ROOT'] = fixture / 'run'
            globals_['_SEADOC_VENDOR_SOURCES'] = {}
            globals_['_SEADOC_CONFIG_LINK'] = (
                shared_directory / 'sdoc_server_config.json'
            )
            globals_['_SEADOC_CONVERTER_LINK'] = (
                shared_directory / 'seadoc_converter_settings.py'
            )
            my_init_source = fixture / 'my_init'
            my_init_source.write_text(MY_INIT_FIXTURE_SOURCE, encoding='utf-8')
            my_init_output = MY_INIT_FIXTURE_SOURCE.replace(
                globals_['_MY_INIT_SIGNAL_EXIT'],
                globals_['_MY_INIT_CLEAN_EXIT'],
                1,
            )
            globals_['_MY_INIT_SOURCE'] = my_init_source
            globals_['_MY_INIT_SOURCE_SHA256'] = hashlib.sha256(
                MY_INIT_FIXTURE_SOURCE.encode('utf-8')
            ).hexdigest()
            globals_['_MY_INIT_OUTPUT_SHA256'] = hashlib.sha256(
                my_init_output.encode('utf-8')
            ).hexdigest()
            environment = {
                'NON_ROOT': 'false',
                'DB_HOST': 'seafile-mariadb',
                'DB_USER': 'seafile',
                'DB_NAME': 'seahub_db',
                'DB_PORT': '3306',
                'SEAHUB_SERVICE_URL': 'http://seafile',
            }
            try:
                with mock.patch.dict(os.environ, environment, clear=True):
                    COMPONENT_PREPARER['prepare_seadoc']()
                runtime = fixture / 'run/seadoc'
                config_path = runtime / 'sdoc_server_config.json'
                converter_path = runtime / 'seadoc_converter_settings.py'
                my_init_path = runtime / 'my_init.py'
                self.assertEqual(stat.S_IMODE((fixture / 'run').stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(runtime.stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(config_path.stat().st_mode), 0o400)
                self.assertEqual(stat.S_IMODE(converter_path.stat().st_mode), 0o400)
                self.assertEqual(stat.S_IMODE(my_init_path.stat().st_mode), 0o400)
                self.assertIn(
                    'Init system stopped cleanly.',
                    my_init_path.read_text(encoding='utf-8'),
                )
                config = json.loads(config_path.read_text(encoding='utf-8'))
                self.assertEqual(config['password'], 'database-pässword')
                self.assertEqual(
                    config['private_key'],
                    '0123456789abcdef0123456789abcdef',
                )
                self.assertEqual(config['seahub_service_url'], 'http://seafile')
                self.assertEqual(
                    os.readlink(globals_['_SEADOC_CONFIG_LINK']), str(config_path)
                )
                self.assertEqual(
                    os.readlink(globals_['_SEADOC_CONVERTER_LINK']),
                    str(converter_path),
                )

                bytecode_directory = shared_directory / '__pycache__'
                bytecode_directory.mkdir()
                (bytecode_directory / 'seadoc_converter_settings.cpython-312.pyc').write_bytes(
                    b'compiled-secret-bearing-settings'
                )
                globals_['_RUNTIME_ROOT'] = fixture / 'second-run'
                with mock.patch.dict(os.environ, environment, clear=True):
                    with self.assertRaisesRegex(
                        RuntimeError,
                        'remove it offline and rotate JWT and database credentials',
                    ):
                        COMPONENT_PREPARER['prepare_seadoc']()
                self.assertFalse((fixture / 'second-run').exists())
            finally:
                globals_.update(original)

    def test_seadoc_vendor_sources_are_fully_drift_locked(self):
        verify = COMPONENT_PREPARER['_verify_reviewed_sources']
        with tempfile.TemporaryDirectory(prefix='seadoc-source-lock.') as directory:
            fixture = Path(directory)
            source = fixture / 'enterpoint.sh'
            source.write_bytes(b'#!/bin/bash\nexec reviewed\n')
            sources = {
                'entrypoint': (source, hashlib.sha256(source.read_bytes()).hexdigest())
            }
            verify(sources)
            source.write_bytes(b'#!/bin/bash\nexec reviewed\n# unrelated drift\n')
            with self.assertRaisesRegex(RuntimeError, 'entrypoint digest drifted'):
                verify(sources)

    def test_component_my_init_source_and_anchor_drift_fail_closed(self):
        prepare_my_init = COMPONENT_PREPARER['_prepare_my_init']
        globals_ = prepare_my_init.__globals__
        original = {
            name: globals_[name]
            for name in (
                '_MY_INIT_SOURCE',
                '_MY_INIT_SOURCE_SHA256',
                '_MY_INIT_OUTPUT_SHA256',
            )
        }
        with tempfile.TemporaryDirectory(prefix='component-my-init-drift.') as directory:
            fixture = Path(directory)
            source_path = fixture / 'my_init'
            output_directory = fixture / 'runtime'
            output_directory.mkdir()
            transformed = MY_INIT_FIXTURE_SOURCE.replace(
                globals_['_MY_INIT_SIGNAL_EXIT'],
                globals_['_MY_INIT_CLEAN_EXIT'],
                1,
            )
            globals_['_MY_INIT_SOURCE'] = source_path
            globals_['_MY_INIT_SOURCE_SHA256'] = hashlib.sha256(
                MY_INIT_FIXTURE_SOURCE.encode('utf-8')
            ).hexdigest()
            globals_['_MY_INIT_OUTPUT_SHA256'] = hashlib.sha256(
                transformed.encode('utf-8')
            ).hexdigest()
            try:
                source_path.write_text(
                    MY_INIT_FIXTURE_SOURCE + '# unrelated vendor drift\n',
                    encoding='utf-8',
                )
                with self.assertRaisesRegex(RuntimeError, 'my_init digest drifted'):
                    prepare_my_init(output_directory)
                for case_name, hostile_source in (
                    (
                        'missing',
                        MY_INIT_FIXTURE_SOURCE.replace(
                            globals_['_MY_INIT_SIGNAL_EXIT'],
                            'except RuntimeError:\n    exit(2)\n',
                        ),
                    ),
                    (
                        'duplicate',
                        MY_INIT_FIXTURE_SOURCE + globals_['_MY_INIT_SIGNAL_EXIT'],
                    ),
                ):
                    with self.subTest(my_init_anchor=case_name):
                        source_path.write_text(hostile_source, encoding='utf-8')
                        globals_['_MY_INIT_SOURCE_SHA256'] = hashlib.sha256(
                            hostile_source.encode('utf-8')
                        ).hexdigest()
                        with self.assertRaisesRegex(
                            RuntimeError,
                            'my_init signal exit vendor contract count',
                        ):
                            prepare_my_init(output_directory)
            finally:
                globals_.update(original)

    def test_component_secret_reader_rejects_hostile_files(self):
        globals_ = COMPONENT_PREPARER['_read_secret'].__globals__
        original_directory = globals_['_SECRET_DIRECTORY']
        cases = (
            ('missing', None, 'unreadable'),
            ('placeholder', b'CHANGE_ME', 'not configured'),
            ('multiline', b'line\nbreak', 'control or line'),
            ('invalid-utf8', b'bad-\xff', 'must be UTF-8'),
            ('c1-control', 'bad-\u0080'.encode('utf-8'), 'control or line'),
            ('unicode-line', 'bad-\u2028'.encode('utf-8'), 'control or line'),
            ('oversize', b'x' * 4097, 'invalid length'),
            ('symlink', b'x', 'unreadable'),
            ('fifo', b'', 'single-link regular'),
            ('socket', b'', 'unreadable|single-link regular'),
            ('hardlink', b'linked-secret', 'single-link regular'),
        )
        try:
            for kind, value, message in cases:
                with self.subTest(kind=kind), tempfile.TemporaryDirectory(
                    prefix=f'component-secret-{kind}.'
                ) as directory:
                    secret_directory = Path(directory)
                    globals_['_SECRET_DIRECTORY'] = secret_directory
                    path = secret_directory / 'TEST_SECRET'
                    cleanup_socket = None
                    if kind == 'symlink':
                        target = secret_directory / 'target'
                        target.write_bytes(value)
                        path.symlink_to(target)
                    elif kind == 'fifo':
                        os.mkfifo(path)
                    elif kind == 'socket':
                        cleanup_socket = socket.socket(socket.AF_UNIX)
                        try:
                            cleanup_socket.bind(str(path))
                        except PermissionError:
                            cleanup_socket.close()
                            continue
                    elif kind == 'hardlink':
                        target = secret_directory / 'target'
                        target.write_bytes(value)
                        os.link(target, path)
                    elif value is not None:
                        path.write_bytes(value)
                    try:
                        with self.assertRaisesRegex(RuntimeError, message):
                            COMPONENT_PREPARER['_read_secret']('TEST_SECRET', 1)
                    finally:
                        if cleanup_socket is not None:
                            cleanup_socket.close()
        finally:
            globals_['_SECRET_DIRECTORY'] = original_directory

    def test_thumbnail_transform_loader_and_legacy_cleanup(self):
        globals_ = COMPONENT_PREPARER['prepare_thumbnail'].__globals__
        original = {
            name: globals_[name]
            for name in (
                '_SECRET_DIRECTORY',
                '_RUNTIME_ROOT',
                '_THUMBNAIL_SOURCES',
                '_THUMBNAIL_LEGACY_PARENT',
                '_MY_INIT_SOURCE',
                '_MY_INIT_SOURCE_SHA256',
                '_MY_INIT_OUTPUT_SHA256',
            )
        }
        with tempfile.TemporaryDirectory(prefix='thumbnail-file-only.') as directory:
            fixture = Path(directory)
            secrets = fixture / 'secrets'
            sources = fixture / 'sources'
            legacy_parent = fixture / 'opt'
            secrets.mkdir()
            sources.mkdir()
            legacy_parent.mkdir()
            (secrets / 'JWT_PRIVATE_KEY').write_bytes(
                b'0123456789abcdef0123456789abcdef'
            )
            (secrets / 'MARIADB_PASSWORD').write_bytes(b'database-password')
            (legacy_parent / 'dockerenv').write_bytes(
                b'JWT_PRIVATE_KEY=old-clear-secret\n'
            )
            source_content = {
                'enterpoint.sh': (
                    '#!/bin/bash\n'
                    'env > /opt/dockerenv\n'
                    '/scripts/thumbnail-server.sh start\n'
                ),
                'thumbnail-server.sh': (
                    globals_['_THUMBNAIL_PYTHONPATH']
                    + '\n    export JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY}\n'
                    + '/scripts/monitor.sh &>> /opt/seafile/logs/monitor.log &\n'
                ),
                'monitor.sh': (
                    globals_['_THUMBNAIL_PYTHONPATH']
                    + '\nexport JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY}\n'
                ),
            }
            synthetic_sources = {}
            for name, content in source_content.items():
                path = sources / name
                path.write_text(content, encoding='utf-8')
                synthetic_sources[name] = (
                    path,
                    hashlib.sha256(content.encode('utf-8')).hexdigest(),
                )
            globals_['_SECRET_DIRECTORY'] = secrets
            globals_['_RUNTIME_ROOT'] = fixture / 'run'
            globals_['_THUMBNAIL_SOURCES'] = synthetic_sources
            globals_['_THUMBNAIL_LEGACY_PARENT'] = legacy_parent
            my_init_source = fixture / 'my_init'
            my_init_source.write_text(MY_INIT_FIXTURE_SOURCE, encoding='utf-8')
            my_init_output = MY_INIT_FIXTURE_SOURCE.replace(
                globals_['_MY_INIT_SIGNAL_EXIT'],
                globals_['_MY_INIT_CLEAN_EXIT'],
                1,
            )
            globals_['_MY_INIT_SOURCE'] = my_init_source
            globals_['_MY_INIT_SOURCE_SHA256'] = hashlib.sha256(
                MY_INIT_FIXTURE_SOURCE.encode('utf-8')
            ).hexdigest()
            globals_['_MY_INIT_OUTPUT_SHA256'] = hashlib.sha256(
                my_init_output.encode('utf-8')
            ).hexdigest()
            try:
                with mock.patch.dict(os.environ, {'NON_ROOT': 'false'}, clear=True):
                    COMPONENT_PREPARER['prepare_thumbnail']()
                self.assertFalse((legacy_parent / 'dockerenv').exists())
                runtime = fixture / 'run/thumbnail'
                entrypoint = (runtime / 'enterpoint.sh').read_text(encoding='utf-8')
                server = (runtime / 'thumbnail-server.sh').read_text(encoding='utf-8')
                monitor = (runtime / 'monitor.sh').read_text(encoding='utf-8')
                self.assertNotIn('env > /opt/dockerenv', entrypoint)
                self.assertNotIn('export JWT_PRIVATE_KEY', server + monitor)
                self.assertIn('/usr/local/lib/seafile-thumbnail-runtime', server)
                for path in runtime.iterdir():
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o400)
                (sources / 'monitor.sh').write_text(
                    source_content['monitor.sh'] + '# drift\n', encoding='utf-8'
                )
                with self.assertRaisesRegex(RuntimeError, 'digest drifted'):
                    COMPONENT_PREPARER['_read_thumbnail_source']('monitor.sh')
            finally:
                globals_.update(original)

        loader_globals = THUMBNAIL_LOADER['transform_source'].__globals__
        source = (
            loader_globals['_IMPORT_ANCHOR']
            + loader_globals['_JWT_EXPRESSION']
            + '\n'
            + loader_globals['_DATABASE_EXPRESSION']
            + '\n'
        )
        original_digest = loader_globals['_SOURCE_SHA256']
        loader_globals['_SOURCE_SHA256'] = hashlib.sha256(
            source.encode('utf-8')
        ).hexdigest()
        try:
            transformed = THUMBNAIL_LOADER['transform_source'](source)
            self.assertIn("_read_runtime_secret('JWT_PRIVATE_KEY', 32)", transformed)
            self.assertIn("_read_runtime_secret('MARIADB_PASSWORD', 12)", transformed)
            self.assertNotIn("os.getenv('JWT_PRIVATE_KEY')", transformed)
            with self.assertRaisesRegex(RuntimeError, 'digest drifted'):
                THUMBNAIL_LOADER['transform_source'](source + '# drift\n')
        finally:
            loader_globals['_SOURCE_SHA256'] = original_digest

    def test_secure_admin_bootstrap_file_and_cleanup(self):
        namespace = {'json': json, 'os': os, 'stat': stat}
        exec(RUNTIME_PREPARER['START_HELPER'], namespace)
        with tempfile.TemporaryDirectory(prefix='seafile-admin-runtime.') as directory:
            fixture = Path(directory)
            run_parent = fixture / 'run'
            canonical_parent = fixture / 'shared/seafile/conf'
            run_parent.mkdir()
            canonical_parent.mkdir(parents=True)
            namespace['_ADMIN_RUNTIME_PARENT'] = str(run_parent)
            namespace['_ADMIN_RUNTIME_DIRECTORY_NAME'] = 'seafile-admin'
            namespace['_ADMIN_RUNTIME_DIRECTORY'] = str(run_parent / 'seafile-admin')
            namespace['_ADMIN_RUNTIME_FILENAME'] = 'admin.txt'
            namespace['_ADMIN_CANONICAL_PARENT'] = str(canonical_parent)
            canonical = canonical_parent / 'admin.txt'
            runtime_file = run_parent / 'seafile-admin/admin.txt'

            handle = namespace['_write_admin_password_file'](
                {'email': 'admin@example.test', 'password': 'strong-password'}
            )
            self.assertTrue(canonical.is_symlink())
            self.assertEqual(os.readlink(canonical), str(runtime_file))
            self.assertEqual(stat.S_IMODE(runtime_file.stat().st_mode), 0o600)
            self.assertEqual(
                json.loads(runtime_file.read_text(encoding='utf-8'))['password'],
                'strong-password',
            )
            namespace['_remove_admin_password_file'](handle)
            self.assertFalse(canonical.exists())
            self.assertFalse(canonical.is_symlink())
            self.assertFalse((run_parent / 'seafile-admin').exists())

            canonical.symlink_to(runtime_file)
            handle = namespace['_write_admin_password_file'](
                {'email': 'admin@example.test', 'password': 'restart-password'}
            )
            namespace['_remove_admin_password_file'](handle)
            self.assertFalse(canonical.is_symlink())

            handle = namespace['_write_admin_password_file'](
                {'email': 'admin@example.test', 'password': 'first-start-password'}
            )
            canonical.unlink()
            namespace['_remove_admin_password_file'](handle)
            self.assertFalse(canonical.exists())
            self.assertFalse((run_parent / 'seafile-admin').exists())

            canonical.write_bytes(b'do-not-overwrite')
            with self.assertRaisesRegex(RuntimeError, 'Unexpected existing'):
                namespace['_write_admin_password_file'](
                    {'email': 'admin@example.test', 'password': 'blocked-password'}
                )
            self.assertEqual(canonical.read_bytes(), b'do-not-overwrite')


if __name__ == '__main__':
    unittest.main(verbosity=2)
