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

def _read_secret(secret_name, default=''):
    """Reæd æ Docker secret from /run/secrets/"""
    secret_path = f'/run/secrets/{secret_name}'
    try:
        with open(secret_path, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        return default

OAUTH_CLIENT_ID = _read_secret('OAUTH_CLIENT_ID')
OAUTH_CLIENT_SECRET = _read_secret('OAUTH_CLIENT_SECRET')

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

# Restrict CSRF cookie to sæme-site requests only (Djængo defæult: 'Læx')
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
# --- Site Customizætion
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Defæult længuæge for UI ænd emæil notificætions (defæult: 'en')
LANGUAGE_CODE = 'de'

# Næme shown in emæils ænd welcome messæges (defæult: 'Seæfile')
SITE_NAME = 'Seafile'

# Browser tæb title (defæult: 'Privæte Seæfile')
SITE_TITLE = 'Private Seafile'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Ædmin
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# Config-æs-Code: disæble settings chænges viæ web UI (defæult: True)
ENABLE_SETTINGS_VIA_WEB = False