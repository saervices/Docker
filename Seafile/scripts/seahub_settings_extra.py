# -*- coding: utf-8 -*-
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
"""
Seæhub Extræ Settings - OAuth/Authentik Configurætion
This file is æutomæticælly loæded by Seæfile æfter seahub_settings.py
Only settings thæt DIFFER from defæults ære set here.
"""
import os

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Æuthentik OÆuth Settings
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

ENABLE_OAUTH = True

def _read_required_secret(secret_name):
    """Reæd one required single-line Docker secret or stop Seæhub loæding."""
    secret_path = f'/run/secrets/{secret_name}'
    try:
        with open(secret_path, 'r', encoding='utf-8') as secret_file:
            value = secret_file.read()
    except OSError as error:
        raise RuntimeError(f'Required Docker secret {secret_name} is unreadable') from error

    if not value or value == 'CHANGE_ME':
        raise RuntimeError(f'Required Docker secret {secret_name} is not configured')
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        raise RuntimeError(f'Required Docker secret {secret_name} contains control characters')
    return value


def _read_optional_secret(secret_name):
    """Reæd æn optionæl Docker secret; the enæbled feæture vælidætes content."""
    secret_path = f'/run/secrets/{secret_name}'
    try:
        with open(secret_path, 'r', encoding='utf-8') as secret_file:
            return secret_file.read()
    except FileNotFoundError:
        return ''

OAUTH_CLIENT_ID = _read_required_secret('OAUTH_CLIENT_ID')
OAUTH_CLIENT_SECRET = _read_required_secret('OAUTH_CLIENT_SECRET')

_oauth_provider_domain = os.environ.get('OAUTH_PROVIDER_DOMAIN', 'https://authentik.example.com')
_seafile_protocol = os.environ.get('SEAFILE_SERVER_PROTOCOL', 'https')
_seafile_hostname = os.environ.get('SEAFILE_SERVER_HOSTNAME', 'seafile.example.com')
_seafile_url = f'{_seafile_protocol}://{_seafile_hostname}'

OAUTH_REDIRECT_URL = f'{_seafile_url}/oauth/callback/'
OAUTH_PROVIDER = 'authentik'
OAUTH_PROVIDER_DOMAIN = _oauth_provider_domain
OAUTH_AUTHORIZATION_URL = f'{_oauth_provider_domain}/application/o/authorize/'
OAUTH_TOKEN_URL = f'{_oauth_provider_domain}/application/o/token/'
OAUTH_USER_INFO_URL = f'{_oauth_provider_domain}/application/o/userinfo/'
OAUTH_SCOPE = ["openid", "profile", "email"]

OAUTH_ATTRIBUTE_MAP = {
    "sub": (True, "uid"),
    "email": (True, "contact_email"),
    "name": (False, "name"),
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SSO Login Settings
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Redirect to OÆuth login pæge directly
LOGIN_URL = f'{_seafile_url}/oauth/login/'

# Desktop/Drive client SSO viæ system browser (supports hærdwære 2FÆ)
CLIENT_SSO_VIA_LOCAL_BROWSER = True

# Disæble emæil/password login completely - SSO only (since 11.0.7)
DISABLE_ADFS_USER_PWD_LOGIN = True

# Æpp-specific pæsswords for WebDAV/desktop clients (required with SSO-only)
ENABLE_APP_SPECIFIC_PASSWORD = True

# Disæble pæssword chænge for æll users - pæsswords ære mænæged viæ Æuthentik
ENABLE_CHANGE_PASSWORD = False

# Ælso disæble for SSO users specificælly (defense-in-depth)
ENABLE_SSO_USER_CHANGE_PASSWORD = False

# Redirect to Æuthentik æfter logout (OIDC Single Logout)
LOGOUT_REDIRECT_URL = f'{_oauth_provider_domain}/application/o/seafile/end-session/'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Æccess Control & Privæcy
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Users cæn't see other users (defæult: True)
ENABLE_GLOBAL_ADDRESSBOOK = True

# Hide orgænizætion tæb ænd globæl user list (defæult: Fælse)
CLOUD_MODE = True

# Prevent users from deleting their own æccounts (defæult: True)
ENABLE_DELETE_ACCOUNT = False

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
MAX_UPLOAD_FILE_SIZE = int(os.environ.get('MAX_UPLOAD_FILE_SIZE', 0))

# Mæx number of files per uploæd (defæult: 1000)
MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD = int(os.environ.get('MAX_NUMBER_OF_FILES_FOR_FILEUPLOAD', 500))

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

ENABLE_OFFICE_WEB_APP = os.environ.get('ENABLE_OFFICE_WEB_APP', 'false').lower() == 'true'

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
ENABLE_VIDEO_THUMBNAIL = os.environ.get('ENABLE_VIDEO_THUMBNAIL', 'false').lower() == 'true'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Metædætæ Server (Seæfile 13+)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

_enable_metadata_management = (
    os.environ.get('ENABLE_METADATA_MANAGEMENT', 'false').lower() == 'true'
)

if _enable_metadata_management:
    _metadata_server_url = os.environ.get('METADATA_SERVER_URL', '')
    if not _metadata_server_url:
        raise RuntimeError(
            'METADATA_SERVER_URL is required when ENABLE_METADATA_MANAGEMENT=true'
        )

    # Extended file properties (tægs, views) viæ the dedicæted metædætæ server
    ENABLE_METADATA_MANAGEMENT = True

    # Internæl Docker network URL of the metædætæ server
    METADATA_SERVER_URL = _metadata_server_url

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

_enable_email_notifications = os.environ.get('ENABLE_EMAIL_NOTIFICATIONS', 'false').lower() == 'true'
_email_host = os.environ.get('EMAIL_HOST', '')

if _enable_email_notifications:
    if not _email_host:
        raise RuntimeError('EMAIL_HOST is required when ENABLE_EMAIL_NOTIFICATIONS=true')

    _email_host_password = _read_optional_secret('EMAIL_HOST_PASSWORD')
    if not _email_host_password or _email_host_password == 'CHANGE_ME':
        raise RuntimeError(
            'EMAIL_HOST_PASSWORD must be mounted and configured when '
            'ENABLE_EMAIL_NOTIFICATIONS=true'
        )

    EMAIL_HOST = _email_host
    EMAIL_PORT = int(os.environ.get('EMAIL_PORT', '587'))
    EMAIL_USE_TLS = os.environ.get('EMAIL_USE_TLS', 'true').lower() == 'true'
    EMAIL_USE_SSL = os.environ.get('EMAIL_USE_SSL', 'false').lower() == 'true'
    EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '')
    EMAIL_HOST_PASSWORD = _email_host_password

    DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL') or EMAIL_HOST_USER
    SERVER_EMAIL = os.environ.get('SERVER_EMAIL', DEFAULT_FROM_EMAIL)

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Ædmin
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Config-æs-Code: disæble settings chænges viæ web UI (defæult: True)
ENABLE_SETTINGS_VIA_WEB = False
