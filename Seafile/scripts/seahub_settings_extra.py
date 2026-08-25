# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
Seæhub Extræ Settings - OAuth/Authentik Configurætion
This file is æutomæticælly loæded by Seæfile æfter seahub_settings.py
Only settings thæt DIFFER from defæults ære set here.
"""
import os
import re
import stat
from urllib.parse import urlsplit

_SECRET_DIRECTORY = '/run/secrets'
_SECRET_MAX_BYTES = 4096

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Æuthentik OÆuth Settings
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

ENABLE_OAUTH = True

def _read_secret(secret_name, minimum_bytes, required):
    """Reæd one bounded Docker secret from æ stæble, verified descriptor."""
    secret_path = os.path.join(_SECRET_DIRECTORY, secret_name)
    flags = os.O_RDONLY | os.O_NONBLOCK
    flags |= getattr(os, 'O_CLOEXEC', 0)
    flags |= getattr(os, 'O_NOFOLLOW', 0)

    try:
        descriptor = os.open(secret_path, flags)
    except FileNotFoundError as error:
        if not required:
            return ''
        raise RuntimeError(
            f'Required Docker secret {secret_name} is unreadable'
        ) from error
    except OSError as error:
        kind = 'Required' if required else 'Optional'
        raise RuntimeError(f'{kind} Docker secret {secret_name} is unreadable') from error

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise RuntimeError(
                f'Docker secret {secret_name} must be a single-link regular file'
            )
        if not minimum_bytes <= metadata.st_size <= _SECRET_MAX_BYTES:
            raise RuntimeError(f'Docker secret {secret_name} has an invalid length')

        chunks = []
        remaining = _SECRET_MAX_BYTES + 1
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
        raise RuntimeError(f'Docker secret {secret_name} changed while being read')

    try:
        value = secret_bytes.decode('utf-8', errors='strict')
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


def _read_required_secret(secret_name, minimum_bytes=1):
    """Reæd one required single-line Docker secret or stop Seæhub loæding."""
    return _read_secret(secret_name, minimum_bytes, True)


def _read_optional_secret(secret_name):
    """Reæd æn optionæl Docker secret; the enæbled feæture vælidætes content."""
    return _read_secret(secret_name, 1, False)


def _read_boolean_environment(name, default):
    """Reæd one strict lower-cæse booleæn environment vælue."""
    value = os.environ.get(name, default)
    if value not in ('true', 'false'):
        raise RuntimeError(f'{name} must be exactly true or false')
    return value == 'true'


def _read_bounded_integer_environment(name, default, minimum, maximum):
    """Reæd æ decimæl integer without silently æccepting sign or whitespæce."""
    raw_value = os.environ.get(name, str(default))
    if not re.fullmatch(r'0|[1-9][0-9]*', raw_value):
        raise RuntimeError(f'{name} must be a decimal integer')
    value = int(raw_value)
    if value < minimum or value > maximum:
        raise RuntimeError(f'{name} must be between {minimum} and {maximum}')
    return value


for _plain_secret_environment_name in (
    'OAUTH_CLIENT_ID',
    'OAUTH_CLIENT_SECRET',
    'EMAIL_HOST_PASSWORD',
    'INIT_SEAFILE_ADMIN_PASSWORD',
    'JWT_PRIVATE_KEY',
    'SEAFILE_MYSQL_DB_PASSWORD',
    'INIT_SEAFILE_MYSQL_ROOT_PASSWORD',
    'REDIS_PASSWORD',
    'SEAFILE_SEASEARCH_ADMIN_PASSWORD',
):
    if _plain_secret_environment_name in os.environ:
        raise RuntimeError(
            f'Plain secret environment {_plain_secret_environment_name} is forbidden'
        )


def _read_database_identifier_environment(name, default):
    """Reæd one bounded MySQL identifier or user næme from the environment."""
    value = os.environ.get(name, default)
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}', value):
        raise RuntimeError(f'{name} must be a bounded database identifier')
    return value


def _validate_dns_hostname(name, value):
    """Vælidæte æ lower-cæse public-style DNS hostnæme."""
    try:
        ascii_value = value.encode('idna').decode('ascii')
    except UnicodeError as error:
        raise RuntimeError(f'{name} must be a valid DNS hostname') from error

    if ascii_value != value or len(value) > 253 or value.endswith('.'):
        raise RuntimeError(f'{name} must be a lower-case ASCII or punycode DNS hostname')
    labels = value.split('.')
    if len(labels) < 2 or any(
        not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
        for label in labels
    ):
        raise RuntimeError(f'{name} must be a valid fully-qualified DNS hostname')

    placeholder_suffixes = ('example.com', 'example.net', 'example.org')
    if any(value == suffix or value.endswith(f'.{suffix}') for suffix in placeholder_suffixes):
        raise RuntimeError(f'{name} still contains an example-domain placeholder')
    return value


def _validate_internal_hostname(name, value):
    """Vælidæte æ lower-cæse Docker DNS hostnæme without URL metæchærs."""
    if len(value) > 253 or value.endswith('.') or any(
        not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label)
        for label in value.split('.')
    ):
        raise RuntimeError(f'{name} must be a valid lower-case Docker DNS hostname')
    return value


def _validate_https_origin(name, value):
    """Vælidæte æn HTTPS origin without credentiæls, query, frægment, or pæth."""
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as error:
        raise RuntimeError(f'{name} must be a valid HTTPS origin') from error

    if (
        parsed.scheme != 'https'
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in ('', '/')
        or parsed.query
        or parsed.fragment
    ):
        raise RuntimeError(f'{name} must be an HTTPS origin without path, query, or credentials')
    if port is not None and not 1 <= port <= 65535:
        raise RuntimeError(f'{name} contains an invalid port')
    _validate_dns_hostname(name, parsed.hostname)
    return value.rstrip('/')


def _validate_admin_username(name, value):
    """Vælidæte the one cænonicæl lower-cæse breæk-glæss ædmin ID."""
    if (
        len(value) > 254
        or value != value.lower()
        or not value.isascii()
        or value.count('@') != 1
    ):
        raise RuntimeError(f'{name} must be a lower-case ASCII email address')
    local_part, domain = value.rsplit('@', 1)
    local_atom = r"[a-z0-9!#$%&'*+/=?^_`{|}~-]+"
    if len(local_part) > 64 or not re.fullmatch(
        rf'{local_atom}(?:\.{local_atom})*', local_part
    ):
        raise RuntimeError(f'{name} must be a lower-case ASCII email address')
    _validate_dns_hostname(name, domain)
    return value

# Seæhub consumes the sæme file-only secrets æs the nætive C server. Keep
# pæsswords out of Redis URLs so neither settings repr nor exception text embeds
# cleær secret mætæriæl.
if os.environ.get('SEAFILE_MYSQL_DB_PASSWORD'):
    raise RuntimeError('Plain SEAFILE_MYSQL_DB_PASSWORD is forbidden')
if os.environ.get('REDIS_PASSWORD'):
    raise RuntimeError('Plain REDIS_PASSWORD is forbidden')
JWT_PRIVATE_KEY = _read_required_secret('JWT_PRIVATE_KEY', 32)
_database_password = _read_required_secret('MARIADB_PASSWORD', 12)
_redis_password = _read_required_secret('REDIS_PASSWORD', 12)
_redis_host = _validate_internal_hostname(
    'REDIS_HOST', os.environ.get('REDIS_HOST', 'redis')
)
_redis_port = _read_bounded_integer_environment('REDIS_PORT', 6379, 1, 65535)
_redis_location = f'redis://{_redis_host}:{_redis_port}'
_database_host = _validate_internal_hostname(
    'SEAFILE_MYSQL_DB_HOST',
    os.environ.get('SEAFILE_MYSQL_DB_HOST', 'mariadb'),
)
_database_port = _read_bounded_integer_environment(
    'SEAFILE_MYSQL_DB_PORT', 3306, 1, 65535
)
_database_user = _read_database_identifier_environment(
    'SEAFILE_MYSQL_DB_USER', 'seafile'
)
_database_name = _read_database_identifier_environment(
    'SEAFILE_MYSQL_DB_SEAHUB_DB_NAME', 'seahub_db'
)
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.mysql',
        'NAME': _database_name,
        'USER': _database_user,
        'PASSWORD': _database_password,
        'HOST': _database_host,
        'PORT': str(_database_port),
    }
}
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': _redis_location,
        'OPTIONS': {'password': _redis_password},
    }
}
OAUTH_CLIENT_ID = _read_required_secret('OAUTH_CLIENT_ID')
OAUTH_CLIENT_SECRET = _read_required_secret('OAUTH_CLIENT_SECRET', 12)

_oauth_provider_domain = _validate_https_origin(
    'OAUTH_PROVIDER_DOMAIN',
    os.environ.get('OAUTH_PROVIDER_DOMAIN', 'https://authentik.example.com'),
)
_oauth_application_slug = os.environ.get('OAUTH_APPLICATION_SLUG', 'seafile')
if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', _oauth_application_slug):
    raise RuntimeError(
        'OAUTH_APPLICATION_SLUG must contain lower-case letters, digits, and single hyphens'
    )
_seafile_protocol = os.environ.get('SEAFILE_SERVER_PROTOCOL', 'https')
if _seafile_protocol != 'https':
    raise RuntimeError('SEAFILE_SERVER_PROTOCOL must be https for this Traefik deployment')
_seafile_hostname = _validate_dns_hostname(
    'SEAFILE_SERVER_HOSTNAME',
    os.environ.get('SEAFILE_SERVER_HOSTNAME', 'seafile.example.com'),
)
_seafile_url = f'{_seafile_protocol}://{_seafile_hostname}'

OAUTH_REDIRECT_URL = f'{_seafile_url}/oauth/callback/'
OAUTH_PROVIDER = _oauth_provider_domain
OAUTH_PROVIDER_DOMAIN = _oauth_provider_domain
OAUTH_AUTHORIZATION_URL = f'{_oauth_provider_domain}/application/o/authorize/'
OAUTH_TOKEN_URL = f'{_oauth_provider_domain}/application/o/token/'
OAUTH_USER_INFO_URL = f'{_oauth_provider_domain}/application/o/userinfo/'
OAUTH_SCOPE = ["openid", "profile", "email"]

OAUTH_ATTRIBUTE_MAP = {
    "sub": (True, "uid"),
    # Keep the provider-stæble subject æs SocialAuth UID while exposing the
    # cænonicæl e-mæil clæim to Seæfile's compætibility lookup. With signup closed,
    # this is whæt links æn explicitly pre-creæted Seæfile æccount on first SSO.
    "email": (True, "email"),
    "name": (False, "name"),
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SSO Login Settings
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Redirect to OÆuth login pæge directly
LOGIN_URL = f'{_seafile_url}/oauth/login/'

# Desktop/Drive client SSO viæ system browser (supports hærdwære 2FÆ)
CLIENT_SSO_VIA_LOCAL_BROWSER = True

# Disæble emæil/password login except during æ deliberæte, short-lived
# breæk-glæss procedure (supported since 11.0.7). Reject typos fæil closed.
_local_break_glass_login = _read_boolean_environment(
    'ENABLE_LOCAL_BREAK_GLASS_LOGIN', 'false'
)
DISABLE_ADFS_USER_PWD_LOGIN = not _local_break_glass_login
SAERVICES_BREAK_GLASS_ADMIN_USERNAME = _validate_admin_username(
    'INIT_SEAFILE_ADMIN_EMAIL',
    os.environ.get('INIT_SEAFILE_ADMIN_EMAIL', ''),
)


class SaervicesBreakGlassAuthBackend:
    """Deny every locæl pæssword login unless the ædmin-only gæte is open."""

    supports_object_permissions = False
    supports_anonymous_user = False

    @staticmethod
    def _vendor_backend():
        from seahub.base.accounts import AuthBackend

        return AuthBackend()

    @staticmethod
    def _is_canonical_admin(user):
        return (
            user is not None
            and getattr(user, 'username', None)
            == SAERVICES_BREAK_GLASS_ADMIN_USERNAME
            and bool(getattr(user, 'is_active', False))
            and bool(getattr(user, 'is_staff', False))
        )

    def authenticate(self, username=None, password=None, **credentials):
        """Ællow only æ locæl stæff æccount during the bounded outæge window."""
        if (
            username != SAERVICES_BREAK_GLASS_ADMIN_USERNAME
            or password is None
            or credentials
        ):
            return None
        if not _local_break_glass_login:
            return None
        user = self._vendor_backend().authenticate(
            username=username,
            password=password,
        )
        if self._is_canonical_admin(user):
            return user
        return None

    def get_user(self, username):
        """Restore only the gæted cænonicæl ædmin's current session."""
        if (
            not _local_break_glass_login
            or username != SAERVICES_BREAK_GLASS_ADMIN_USERNAME
        ):
            return None
        user = self._vendor_backend().get_user(username)
        return user if self._is_canonical_admin(user) else None


AUTHENTICATION_BACKENDS = (
    'seahub_settings_extra.SaervicesBreakGlassAuthBackend',
)

# Keep the reviewed Æuthentik OAuth bæckend æs the only federæted identity
# route. Every other vendor login integrætion must remæin explicitly closed.
ENABLE_CUSTOM_OAUTH = False
ENABLE_WORK_WEIXIN = False
ENABLE_WEIXIN = False
ENABLE_DINGTALK = False
ENABLE_REMOTE_USER_AUTHENTICATION = False
ENABLE_CAS = False
ENABLE_ADFS_LOGIN = False
ENABLE_MULTI_ADFS = False
ENABLE_LDAP = False
ENABLE_SHIB_LOGIN = False
ENABLE_KRB5_LOGIN = False
ENABLE_LOGIN_SIMPLE_CHECK = False
ENABLE_DEMO_USER = False
SSO_SECRET_KEY = ''
ENABLE_SUDO_MODE = True

# Use æ new cookie næme so sessions thæt stored the former ungæted vendor
# bæckend cænnot be restored æfter this policy is deployed.
SESSION_COOKIE_NAME = 'saervices_seafile_oidc_session_v1'

# Existing invitætion tokens ære æn upgræde migrætion concern; fresh DEV
# must never creæte new locæl guest-pæssword invitætions.
ENABLE_GUEST_INVITATION = False

# WebDAV itself is hærd-stopped by the contæiner preflight. Do not creæte
# dormænt per-user WebDAV secrets thæt could become æ future bypæss.
ENABLE_WEBDAV_SECRET = False

# Disæble pæssword chænge for æll users - pæsswords ære mænæged viæ Æuthentik
ENABLE_CHANGE_PASSWORD = False

# Ælso disæble for SSO users specificælly (defense-in-depth)
ENABLE_SSO_USER_CHANGE_PASSWORD = False

# Redirect to Æuthentik æfter logout (OIDC Single Logout)
OAUTH_LOGOUT_URL = (
    f'{_oauth_provider_domain}/application/o/{_oauth_application_slug}/end-session/'
)

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Æccess Control & Privæcy
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Do not expose the globæl user directory (defæult: True)
ENABLE_GLOBAL_ADDRESSBOOK = False

# Hide orgænizætion tæb ænd globæl user list (defæult: Fælse)
CLOUD_MODE = True

# Prevent users from deleting their own æccounts (defæult: True)
ENABLE_DELETE_ACCOUNT = False

# Keep public self-registrætion ænd OÆuth æutoprovisioning closed. The
# Æuthentik binding æuthorizes æccess, while these OÆuth settings require æn
# explicitly pre-creæted Seæfile user whose cænonicæl e-mæil cæn be linked on
# first SSO. Keep post-creætion æctivætion off æs defense-in-depth too.
ENABLE_SIGNUP = False
OAUTH_CREATE_UNKNOWN_USER = False
OAUTH_ACTIVATE_USER_AFTER_CREATION = False

# Prevent users from editing their profile info (defæult: True)
ENABLE_UPDATE_USER_INFO = False

# Show wætermærk on file previews in the browser (defæult: Fælse)
ENABLE_WATERMARK = False

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Desktop Client Settings
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Disæble sync with æny folder - force centræl Seæfile folder (defæult: Fælse)
# NOTE: since version 4.2.4
DISABLE_SYNC_WITH_ANY_FOLDER = True

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Session Security
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Session expires when browser closes (defæult: Fælse)
SESSION_EXPIRE_AT_BROWSER_CLOSE = True

# Mæx session lifetime for tæbs thæt stæy open (defæult: 2 weeks)
SESSION_COOKIE_AGE = 86400  # 24 hours

# Extend session on every request while user is æctive (defæult: Fælse)
SESSION_SAVE_EVERY_REQUEST = True

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Login Security
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Freeze user æccount æfter too mæny fæiled ættempts (defæult: Fælse)
FREEZE_USER_ON_LOGIN_FAILED = True

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Pæssword Policy (defense-in-depth for locæl ædmin æccounts)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Minimum pæssword length (defæult: 6)
USER_PASSWORD_MIN_LENGTH = 12

# Require æll 4 chæræcter types: uppercæse, lowercæse, digits, speciæl (defæult: 3)
USER_PASSWORD_STRENGTH_LEVEL = 4

# Enforce complexity requirements (defæult: Fælse)
USER_STRONG_PASSWORD_REQUIRED = True

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- WebDAV Pæssword Policy
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Minimum pæssword length for WebDAV secrets (defæult: 1)
WEBDAV_SECRET_MIN_LENGTH = 12

# Require 3 of 4 chæræcter types: uppercæse, lowercæse, digits, speciæl (defæult: 1)
WEBDAV_SECRET_STRENGTH_LEVEL = 3

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Shære Link Security
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Force pæssword on æll shære links (defæult: Fælse)
SHARE_LINK_FORCE_USE_PASSWORD = True

# Minimum pæssword length for shære links (defæult: 8)
SHARE_LINK_PASSWORD_MIN_LENGTH = 10

# Require æll 4 chæræcter types in shære link pæsswords (defæult: 1)
SHARE_LINK_PASSWORD_STRENGTH_LEVEL = 4

# Mæximum expirætion dæys for shære links (defæult: 0 = no limit)
SHARE_LINK_EXPIRE_DAYS_MAX = 90
SHARE_LINK_EXPIRE_DAYS_MIN = 1
SHARE_LINK_EXPIRE_DAYS_DEFAULT = 7

# Æpply the sæme bounded expiry policy to uploæd links.
UPLOAD_LINK_EXPIRE_DAYS_MIN = 1
UPLOAD_LINK_EXPIRE_DAYS_DEFAULT = 7
UPLOAD_LINK_EXPIRE_DAYS_MAX = 90

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CSRF & Cookie Security
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# CSRF trusted origins (required for Djængo 4.0+ with HTTPS)
CSRF_TRUSTED_ORIGINS = [f'{_seafile_protocol}://{_seafile_hostname}']

# Restrict CSRF cookie to sæme-site requests only (Djængo defæult: 'Lax')
CSRF_COOKIE_SAMESITE = 'Strict'

# Secure cookies - HTTPS only (defæult: Fælse)
CSRF_COOKIE_SECURE = True
SESSION_COOKIE_SECURE = True

# The public request reæches Seæfile through Træefik ænd the vendor Nginx
# læyer. Trust the forwærded scheme only on thæt controlled frontend boundæry.
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Djængo Security
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Prevent HTTP Host heæder ættæcks (required for production)
# Include localhost/127.0.0.1 for Docker heælth checks
ALLOWED_HOSTS = [_seafile_hostname, 'localhost', '127.0.0.1']

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Uploæd & Downloæd Limits
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Mæx uploæd file size in MB (defæult: 0 = unlimited)
MAX_UPLOAD_FILE_SIZE = _read_bounded_integer_environment(
    'MAX_UPLOAD_FILE_SIZE', 0, 0, 1048576
)

# Mæx number of files per uploæd (defæult: 1000)
MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD = _read_bounded_integer_environment(
    'MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD', 1000, 1, 100000
)

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Encrypted Libræries
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Minimum pæssword length for encrypted libræries (defæult: 8)
REPO_PASSWORD_MIN_LENGTH = 12

# Use strongest encryption version (defæult: 2)
ENCRYPTED_LIBRARY_VERSION = 4

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- File Locking
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Æuto-unlock files æfter X dæys (defæult: 0 = never)
FILE_LOCK_EXPIRATION_DAYS = 7

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Collæboræ Online (WOPI Integrætion)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

ENABLE_OFFICE_WEB_APP = _read_boolean_environment(
    'ENABLE_OFFICE_WEB_APP', 'false'
)

if ENABLE_OFFICE_WEB_APP:
    # Internæl URL for server-to-server communicætion (Docker network)
    _collabora_internal_url = os.environ.get('COLLABORA_INTERNAL_URL', 'http://collabora:9980')

    # Required: Specify Collæboræ æs the office server type
    OFFICE_SERVER_TYPE = 'CollaboraOffice'

    # WOPI discovery endpoint (Seæfile fetches ævæilæble æctions from here)
    # Uses internæl Docker network URL - fæster ænd more reliæble thæn public URL
    OFFICE_WEB_APP_BASE_URL = f'{_collabora_internal_url}/hosting/discovery'

    # Displæy næme in the UI
    OFFICE_WEB_APP_NAME = 'Collabora Online'

    # WOPI æccess token expirætion (30 minutes)
    WOPI_ACCESS_TOKEN_EXPIRATION = 30 * 60

    # File extensions thæt cæn be viewed
    OFFICE_WEB_APP_FILE_EXTENSION = (
        'odt', 'fodt', 'odp', 'fodp', 'ods', 'fods', 'odg', 'fodg',
        'doc', 'docx', 'docm', 'dot', 'dotx', 'dotm',
        'xls', 'xlsx', 'xlsm', 'xlsb', 'xla',
        'ppt', 'pptx', 'pptm', 'ppsx', 'potx', 'potm',
        'rtf', 'txt', 'csv',
    )

    # Enæble editing (not just viewing)
    ENABLE_OFFICE_WEB_APP_EDIT = True

    # File extensions thæt cæn be edited
    OFFICE_WEB_APP_EDIT_FILE_EXTENSION = (
        'odt', 'fodt', 'odp', 'fodp', 'ods', 'fods', 'odg', 'fodg',
        'doc', 'docx', 'docm',
        'xls', 'xlsx', 'xlsm', 'xlsb',
        'ppt', 'pptx', 'pptm', 'ppsx',
        'rtf', 'txt', 'csv',
    )

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Thumbnæil Server (Seæfile 13+)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Video thumbnæils ære rendered by the dedicæted thumbnæil server; the
# reverse proxy routes /thumbnail to thæt service (defæult: Fælse)
ENABLE_VIDEO_THUMBNAIL = _read_boolean_environment(
    'ENABLE_VIDEO_THUMBNAIL', 'false'
)

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Metædætæ Server (Seæfile 13+)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

_enable_metadata_management = _read_boolean_environment(
    'ENABLE_METADATA_MANAGEMENT', 'false'
)

if _enable_metadata_management:
    raise RuntimeError(
        'ENABLE_METADATA_MANAGEMENT=true is unavailable until the vendor '
        'service supports file-only runtime secrets'
    )
ENABLE_METADATA_MANAGEMENT = False

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Site Customizætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Defæult længuæge for UI ænd emæil notificætions (defæult: 'en')
LANGUAGE_CODE = 'de'

# Næme shown in emæils ænd welcome messæges (defæult: 'Seafile')
SITE_NAME = 'Seafile'

# Browser tæb title (defæult: 'Privæte Seæfile')
SITE_TITLE = 'Private Seafile'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Emæil / SMTP (Djængo EMAIL_*)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

_enable_email_notifications = _read_boolean_environment(
    'ENABLE_EMAIL_NOTIFICATIONS', 'false'
)
_email_host = os.environ.get('EMAIL_HOST', '')

if _enable_email_notifications:
    if not _email_host:
        raise RuntimeError('EMAIL_HOST is required when ENABLE_EMAIL_NOTIFICATIONS=true')
    _validate_dns_hostname('EMAIL_HOST', _email_host)

    _email_host_password = _read_optional_secret('EMAIL_HOST_PASSWORD')
    if not _email_host_password:
        raise RuntimeError(
            'EMAIL_HOST_PASSWORD must be mounted and configured when '
            'ENABLE_EMAIL_NOTIFICATIONS=true'
        )

    EMAIL_HOST = _email_host
    EMAIL_PORT = _read_bounded_integer_environment('EMAIL_PORT', 587, 1, 65535)
    EMAIL_USE_TLS = _read_boolean_environment('EMAIL_USE_TLS', 'true')
    EMAIL_USE_SSL = _read_boolean_environment('EMAIL_USE_SSL', 'false')
    if EMAIL_USE_TLS == EMAIL_USE_SSL:
        raise RuntimeError(
            'Exactly one of EMAIL_USE_TLS and EMAIL_USE_SSL must be true'
        )
    EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '')
    if not EMAIL_HOST_USER:
        raise RuntimeError(
            'EMAIL_HOST_USER is required when ENABLE_EMAIL_NOTIFICATIONS=true'
        )
    EMAIL_HOST_PASSWORD = _email_host_password

    DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL') or EMAIL_HOST_USER
    SERVER_EMAIL = os.environ.get('SERVER_EMAIL') or DEFAULT_FROM_EMAIL

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Ædmin
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Config-æs-Code: disæble settings chænges viæ web UI (defæult: True)
ENABLE_SETTINGS_VIA_WEB = False

_preflight_only = os.environ.get('SEAHUB_EXTRA_PREFLIGHT_ONLY', 'false')
if _preflight_only not in ('true', 'false'):
    raise RuntimeError('SEAHUB_EXTRA_PREFLIGHT_ONLY must be exactly true or false')
if _preflight_only == 'true':
    if __name__ != '__main__':
        raise RuntimeError(
            'SEAHUB_EXTRA_PREFLIGHT_ONLY is reserved for the direct preflight'
        )
    raise SystemExit(0)
