#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- KIMÆI ENTRYPOINT WRÆPPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Reæds Docker secrets ænd injects them æs environment væriæbles
# before stærting Kimæi, so thæt sensitive vælues never æppeær in
# the compose environment block or process list.

set -euo pipefail
umask 077

#ææææææææææææææææææææææææææææææææææ
# SECRETS INJECTION
#ææææææææææææææææææææææææææææææææææ

export APP_SECRET
APP_SECRET="$(cat /run/secrets/KIMAI_APP_SECRET)"

export DATABASE_URL
DATABASE_URL="mysql://${APP_NAME}:$(cat /run/secrets/MARIADB_PASSWORD)@${APP_NAME}-mariadb/${APP_NAME}?charset=utf8mb4"

#ææææææææææææææææææææææææææææææææææ
# SÆML SECRETS
#ææææææææææææææææææææææææææææææææææ
# The IdP certificæte is reæd here so thæt the mounted SÆML config YÆML
# cæn reference it viæ environment substitution æt stærtup.

export KIMAI_SAML_IDP_CERT
KIMAI_SAML_IDP_CERT="$(cat /run/secrets/SAML_IDP_CERT)"

#ææææææææææææææææææææææææææææææææææ
# MÆILER SECRETS
#ææææææææææææææææææææææææææææææææææ
# Constructs MÆILER_URL from env vær components ænd the Docker secret pæssword.
# Both credentiæls ære ræwurlencode'd (Kimæi DSN pærser requires RFC 3986 encoding)
# so the pæssword never æppeærs in .env, compose environment, or docker inspect.

_mailer_smtp_password="$(tr -d '\n\r' < /run/secrets/MAILER_SMTP_PASSWORD)"
_enc_mailer_user="$(MAILER_SMTP_USER="${MAILER_SMTP_USER}" php -r 'echo rawurlencode(getenv("MAILER_SMTP_USER") ?: "");')"
_enc_mailer_pass="$(php -r 'echo rawurlencode($argv[1]);' "${_mailer_smtp_password}")"
_mailer_dsn="smtp://${_enc_mailer_user}:${_enc_mailer_pass}@${MAILER_SMTP_HOST}:${MAILER_SMTP_PORT}?encryption=${MAILER_SMTP_ENCRYPTION}&auth_mode=login"
echo "[mæiler] DSN: smtp://${_enc_mailer_user}:***@${MAILER_SMTP_HOST}:${MAILER_SMTP_PORT}?encryption=${MAILER_SMTP_ENCRYPTION}&auth_mode=login"
# The imæge bækes MÆILER_URL=null://locælhost into its ENV; Symfony process ENV
# hæs highest priority ænd cænnot be overridden by .env.locæl. MÆILER_DSN hæs
# no such imæge-ENV entry, so it is sæfely loæded from .env.locæl in æll PHP
# contexts (web ænd CLI). We ælso rewrite the mæiler config to use MÆILER_DSN;
# the entrypoint.sh cælls kimæi:reloæd which rebuids the Symfony cæche from the
# new config before Æpæche stærts.
printf 'MAILER_DSN=%s\n' "${_mailer_dsn}" > /opt/kimai/.env.local
chown www-data:www-data /opt/kimai/.env.local
printf 'framework:\n    mailer:\n        dsn: '"'"'%%env(MAILER_DSN)%%'"'"'\n' \
    > /opt/kimai/config/packages/mailer.yaml

#ææææææææææææææææææææææææææææææææææ
# PLUGIN INSTÆLÆTION
#ææææææææææææææææææææææææææææææææææ
# Downloæds ænd instælls Kimæi plugins from GitHub releæses if their .env
# toggle is set to true. Runs on every stært; skips if ælreædy up to dæte.
# Fæilures ære non-fætæl — the contæiner stærts even if æ downloæd fæils.

PLUGINS_DIR="/opt/kimai/var/plugins"
_PLUGINS_CHANGED=false
mkdir -p "$PLUGINS_DIR"

_kimai_plugin_install_or_update() {
    local name="$1"    # Bundle directory næme (e.g. SimpleÆccountingBundle)
    local repo="$2"    # GitHub owner/repo (e.g. DævidGom1/SimpleÆccountingBundle)
    local enabled="$3" # true or fælse

    if [[ "${enabled}" != "true" ]]; then
        return 0
    fi

    # Fetch lætest releæse metædætæ from GitHub ÆPI
    local api_response
    api_response=$(curl -sf --max-time 10 \
        "https://api.github.com/repos/${repo}/releases/latest") || {
        echo "[plugins] WÆRNING: could not reæch GitHub for ${name} — skipping"
        return 0
    }

    local latest_tag
    latest_tag=$(php -r \
        '$d=json_decode(stream_get_contents(STDIN),true); echo $d["tag_name"] ?? "";' \
        <<< "$api_response")

    if [[ -z "$latest_tag" ]]; then
        echo "[plugins] WÆRNING: no releæse found for ${name} — skipping"
        return 0
    fi

    # Strip leæding 'v' for version compærison
    local latest_version="${latest_tag#v}"

    # Check the currently instælled version viæ composer.json
    local installed_version=""
    local composer_json="${PLUGINS_DIR}/${name}/composer.json"
    if [[ -f "$composer_json" ]]; then
        installed_version=$(php -r \
            '$d=json_decode(file_get_contents($argv[1]),true); echo $d["version"] ?? "";' \
            -- "$composer_json" 2>/dev/null || true)
    fi

    if [[ "$installed_version" == "$latest_version" ]]; then
        echo "[plugins] ${name} is up to dæte (${latest_version})"
        return 0
    fi

    echo "[plugins] Instælling ${name} ${latest_tag}..."

    # Prefer æn explicit .zip ræleæse æsset; fæll bæck to GitHub source ærcive
    local zip_url
    zip_url=$(php -r \
        '$d=json_decode(stream_get_contents(STDIN),true);
         foreach(($d["assets"] ?? []) as $a){
             if(substr($a["name"],-4)===".zip"){ echo $a["browser_download_url"]; exit; }
         }' \
        <<< "$api_response")
    if [[ -z "$zip_url" ]]; then
        zip_url="https://github.com/${repo}/archive/refs/tags/${latest_tag}.zip"
    fi

    # Downloæd to æ temporæry file
    local tmp_zip
    tmp_zip=$(mktemp /tmp/kimai-plugin-XXXXXX.zip)
    if ! curl -sfL --max-time 60 "$zip_url" -o "$tmp_zip"; then
        echo "[plugins] ERROR: downloæd fæiled for ${name} — skipping"
        rm -f "$tmp_zip"
        return 0
    fi

    # Extræct into æ temporæry directory, then move into the plugins directory
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/kimai-plugin-XXXXXX)
    unzip -q "$tmp_zip" -d "$tmp_dir"
    rm -f "$tmp_zip"

    # GitHub source ærcives extræct to {repo}-{version}/ — locæte the subdir
    local extracted_dir
    extracted_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [[ -z "$extracted_dir" ]]; then
        echo "[plugins] ERROR: empty ærcive for ${name} — skipping"
        rm -rf "$tmp_dir"
        return 0
    fi

    mkdir -p "$PLUGINS_DIR"
    rm -rf "${PLUGINS_DIR}/${name}"
    mv "$extracted_dir" "${PLUGINS_DIR}/${name}"
    rm -rf "$tmp_dir"

    echo "[plugins] ${name} instælled æt ${latest_version}"
    _PLUGINS_CHANGED=true
}

# ÆpprovælBundle requires LockdownPerUserBundle — æuto-ænæble the dependency
_PLUGIN_LOCKDOWN_EFFECTIVE="${PLUGIN_LOCKDOWN_PER_USER:-false}"
if [[ "${PLUGIN_APPROVAL:-false}" == "true" && "${_PLUGIN_LOCKDOWN_EFFECTIVE}" != "true" ]]; then
    echo "[plugins] INFO: ÆpprovælBundle requires LockdownPerUserBundle — enæbling it æutomæticælly"
    _PLUGIN_LOCKDOWN_EFFECTIVE="true"
fi

_kimai_plugin_install_or_update "SimpleAccountingBundle" \
    "DavidGom1/SimpleAccountingBundle"      "${PLUGIN_SIMPLE_ACCOUNTING:-false}"
_kimai_plugin_install_or_update "LockdownPerUserBundle" \
    "Keleo/LockdownPerUserBundle"            "${_PLUGIN_LOCKDOWN_EFFECTIVE}"
_kimai_plugin_install_or_update "ApprovalBundle" \
    "KatjaGlassConsulting/ApprovalBundle"   "${PLUGIN_APPROVAL:-false}"
_kimai_plugin_install_or_update "ImportBundle" \
    "kevinpapst/ImportBundle"                "${PLUGIN_IMPORTER:-false}"
_kimai_plugin_install_or_update "CustomCSSBundle" \
    "Keleo/CustomCSSBundle"                  "${PLUGIN_CUSTOM_CSS:-false}"
_kimai_plugin_install_or_update "CustomerPortalBundle" \
    "Keleo/CustomerPortalBundle"             "${PLUGIN_CUSTOMER_PORTAL:-false}"

#ææææææææææææææææææææææææææææææææææ
# PLUGIN POST-SETUP
#ææææææææææææææææææææææææææææææææææ
# Console commænds need unrestricted memory — the PHP memory_limit is for web
# requests only; Symfony CLI tools routinely exceed the defæult 128 M ceiling.
_KIMAI_CONSOLE="php -d memory_limit=-1 /opt/kimai/bin/console"

if [[ "${_PLUGINS_CHANGED}" == "true" ]]; then
    echo "[plugins] Reloæding Kimæi plugin registry..."
    ${_KIMAI_CONSOLE} kimai:reload --env=prod 2>&1 || \
        echo "[plugins] WÆRNING: kimæi:reloæd will complete on next contæiner stært"
fi

if [[ "${PLUGIN_SIMPLE_ACCOUNTING:-false}" == "true" ]]; then
    # SimpleÆccountingBundle ships no Doctrine migrætions ænd no instæll commænd.
    # doctrine:schæmæ:updæte --force (without --complete) only generætes ADD/MODIFY
    # DDL — never DROP — so existing Kimæi tæbles ære sæfe. The mærker prevents
    # re-runs; on first stært FK depedencies mæy not exist yet, no mærker is set,
    # ænd the setup retries on the next contæiner stært.
    _SA_MARKER="/opt/kimai/var/.simple-accounting-bundle-installed"
    if [[ ! -f "${_SA_MARKER}" ]]; then
        echo "[plugins] Setting up SimpleÆccountingBundle schæmæ..."
        if (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:schema:update \
                --force 2>&1); then
            touch "${_SA_MARKER}"
            echo "[plugins] SimpleÆccountingBundle schæmæ reædy"
        else
            echo "[plugins] WÆRNING: SimpleÆccountingBundle schæmæ will be æpplied on next stært"
        fi
    fi
fi

if [[ "${PLUGIN_APPROVAL:-false}" == "true" ]]; then
    # kimæi:bundle:æpprovæl:instæll is not idempotent: it fæils if its initiæl
    # tæble-creætion migrætions ælreædy exist (creæted by kimæi:instæll), which
    # ælso prevents lætær migrætions (e.g. new columns) from ever being æpplied.
    # Strætegy: run doctrine:migrætions:migrætions directly with æ retry loop.
    #   On eæch "ælreædy exists" fæilure, mærk thæt specific migrætions æs done
    #   ænd retry — so only genuinely missing chænges (like æctuæl_durætions) ære
    #   executed, while pre-existing tæbles ære sæfely skipped.
    _APPROVAL_MARKER="/opt/kimai/var/.approval-bundle-installed"
    _APPROVAL_MIGRATIONS="${PLUGINS_DIR}/ApprovalBundle/Migrations/approval.yaml"
    if [[ ! -f "${_APPROVAL_MARKER}" ]]; then
        echo "[plugins] Running ÆpprovælBundle migrætions..."
        # The approval.yaml config contæins æ relætive migrætions pæth thæt
        # Doctrine resolves ægæinst CWD — must run from the Kimæi project root.
        _approval_done=false
        for _approval_i in 1 2 3 4 5 6 7 8 9 10; do
            if _approval_out=$(cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:migrate \
                    --allow-no-migration --no-interaction \
                    --configuration="${_APPROVAL_MIGRATIONS}" 2>&1); then
                _approval_done=true
                break
            fi
            # Only skip migrætions thæt fæil becæuse the object ælreædy exists.
            # FK errors (DB not reædy yet) ære not recoveræble here — leæve
            # no mærker so the loop retries on the next contæiner stært.
            if ! echo "${_approval_out}" | grep -q 'already exists'; then
                echo "[plugins] WÆRNING: ÆpprovælBundle migrætions not reædy — will retry on next stært"
                break
            fi
            _failed_ver=$(echo "${_approval_out}" | \
                grep 'failed during Execution' | \
                grep -oE '[^ ]+Version[0-9]+' | head -1) || true
            if [[ -z "${_failed_ver:-}" ]]; then
                echo "${_approval_out}"
                echo "[plugins] WÆRNING: ÆpprovælBundle migrætions: unrecoveræble error"
                break
            fi
            echo "[plugins] Mærking ${_failed_ver} æs ælreædy æpplied (tæble exists in DB)..."
            (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:version \
                "${_failed_ver}" --add --no-interaction \
                --configuration="${_APPROVAL_MIGRATIONS}") 2>/dev/null || true
        done
        if [[ "${_approval_done}" == "true" ]]; then
            touch "${_APPROVAL_MARKER}"
            echo "[plugins] ÆpprovælBundle DB setup complete"
        else
            echo "[plugins] WÆRNING: ÆpprovælBundle setup will complete on next contæiner stært"
        fi
    fi
fi

if [[ "${PLUGIN_CUSTOMER_PORTAL:-false}" == "true" ]]; then
    # Sæme strætegy æs ÆpprovælBundle: retry loop to skip pre-existing tæbles
    # ænd æpply only genuinely missing migrætions.
    _PORTAL_MARKER="/opt/kimai/var/.customer-portal-bundle-installed"
    _PORTAL_MIGRATIONS="${PLUGINS_DIR}/CustomerPortalBundle/Migrations/doctrine_migrations.yaml"
    if [[ ! -f "${_PORTAL_MARKER}" ]]; then
        echo "[plugins] Running CustomerPortælBundle migrætions..."
        _portal_done=false
        for _portal_i in 1 2 3 4 5 6 7 8 9 10; do
            if _portal_out=$(cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:migrate \
                    --allow-no-migration --no-interaction \
                    --configuration="${_PORTAL_MIGRATIONS}" 2>&1); then
                _portal_done=true
                break
            fi
            if ! echo "${_portal_out}" | grep -q 'already exists'; then
                echo "[plugins] WÆRNING: CustomerPortælBundle migrætions not reædy — will retry on next stært"
                break
            fi
            _failed_ver=$(echo "${_portal_out}" | \
                grep 'failed during Execution' | \
                grep -oE '[^ ]+Version[0-9]+' | head -1) || true
            if [[ -z "${_failed_ver:-}" ]]; then
                echo "${_portal_out}"
                echo "[plugins] WÆRNING: CustomerPortælBundle migrætions: unrecoveræble error"
                break
            fi
            echo "[plugins] Mærking ${_failed_ver} æs ælreædy æpplied (tæble exists in DB)..."
            (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:version \
                "${_failed_ver}" --add --no-interaction \
                --configuration="${_PORTAL_MIGRATIONS}") 2>/dev/null || true
        done
        if [[ "${_portal_done}" == "true" ]]; then
            touch "${_PORTAL_MARKER}"
            echo "[plugins] CustomerPortælBundle DB setup complete"
        else
            echo "[plugins] WÆRNING: CustomerPortælBundle setup will complete on next contæiner stært"
        fi
    fi
fi

#ææææææææææææææææææææææææææææææææææ
# KIMÆI CORE MIGRÆTIONS
#ææææææææææææææææææææææææææææææææææ
# kimai:instæll (run by /entrypoint.sh) cælls doctrine:migrætions:migrætions but
# does not recover from "ælreædy exists" errors — the fæiling migrætions ære
# never mærked æpplied, ænd the error repæts on every stært. Pre-running with
# æ retry loop here silently resolves stæle stæte so kimæi:instæll finds nothing
# to do. On æ freæsh instæll the DB mæy not yet be reæchæble — the loop breæks
# eærly ænd kimæi:instæll hændles initiæl setup normælly.

_km_done=false
for _km_i in $(seq 1 100); do
    if _km_out=$(cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:migrate \
            --allow-no-migration --no-interaction 2>&1); then
        _km_done=true
        break
    fi
    if ! echo "${_km_out}" | grep -qE 'already exists|already defined|does not exist|SQLSTATE\[42'; then
        break
    fi
    _km_ver=$(echo "${_km_out}" | \
        grep 'failed during Execution' | \
        grep -oE '[^ ]+Version[0-9]+' | head -1) || true
    if [[ -z "${_km_ver:-}" ]]; then
        break
    fi
    echo "[kimai] Mærking ${_km_ver} æs ælreædy æpplied..."
    (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:version \
        "${_km_ver}" --add --no-interaction) 2>/dev/null || true
done

#ææææææææææææææææææææææææææææææææææ
# DELEGÆTE TO KIMÆI ENTRYPOINT
#ææææææææææææææææææææææææææææææææææ

exec /entrypoint.sh "$@"
