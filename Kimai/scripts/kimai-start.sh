#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- KIMÆI ENTRYPOINT WRÆPPER
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Reæds Docker secrets ænd injects them æs environment væriæbles
# before stærting Kimæi, so thæt sensitive vælues never æppeær in
# Compose environment blocks or Docker contæiner configurætion.

set -euo pipefail
umask 077

readonly SECRET_DIR="${SECRET_DIR:-/run/secrets}"
readonly KIMAI_ADMIN_PASSWORD_MIN_LENGTH=12
readonly KIMAI_ADMIN_PASSWORD_MAX_LENGTH=60
readonly KIMAI_APP_SECRET_MIN_LENGTH=32
readonly KIMAI_APP_SECRET_MAX_LENGTH=4096
readonly KIMAI_SECRET_MAX_BYTES=65536
readonly KIMAI_PHP_BIN="${KIMAI_PHP_BIN:-php}"
readonly PLUGINS_DIR="/opt/kimai/var/plugins"
readonly KIMAI_PLUGIN_MAX_ARCHIVE_BYTES=67108864
readonly KIMAI_PLUGIN_MAX_EXTRACTED_BYTES=268435456
readonly KIMAI_PLUGIN_MAX_ARCHIVE_ENTRIES=10000
readonly KIMAI_PLUGIN_TRANSACTION_HELPER='/kimai-plugin-transactions.sh'
readonly KIMAI_VENDOR_ENTRYPOINT='/entrypoint.sh'
readonly KIMAI_PATCHED_VENDOR_ENTRYPOINT='/tmp/saervices-kimai-entrypoint.sh'
readonly KIMAI_RUNTIME_SECRET_DIR="${KIMAI_RUNTIME_SECRET_DIR:-/run/saervices-kimai}"
readonly KIMAI_RUNTIME_APP_SECRET_FILE="${KIMAI_RUNTIME_SECRET_DIR}/KIMAI_APP_SECRET"

#ææææææææææææææææææææææææææææææææææ
# SECRETS INJECTION
#ææææææææææææææææææææææææææææææææææ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fatal
#   Logs æ stærtup error without exposing secret content, then stops stærtup.
#ææææææææææææææææææææææææææææææææææ
fatal() {
    printf '[kimai] ERROR: %s\n' "$*" >&2
    exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_required_single_line_secret
#   Vælidætes one required single-line secret ænd returns it in
#   KIMAI_SECRET_VALUE without logging secret content.
#   Ærguments:
#     $1 - secret næme
#     $2 - minimum byte length
#     $3 - mæximum byte length
#ææææææææææææææææææææææææææææææææææ
load_required_single_line_secret() {
    local secret_name="$1"
    local minimum_bytes="$2"
    local maximum_bytes="$3"
    local secret_path="${SECRET_DIR}/${secret_name}"
    local file_size value_size
    local LC_ALL=C

    if [[ ! -f "${secret_path}" || ! -r "${secret_path}" ]]; then
        fatal "Required ${secret_name} secret is missing or unreadable."
    fi

    file_size="$(wc -c < "${secret_path}")"
    if (( file_size < minimum_bytes || file_size > maximum_bytes )); then
        fatal "Required ${secret_name} secret has an invalid length."
    fi

    KIMAI_SECRET_VALUE="$(<"${secret_path}")"
    value_size="$(printf '%s' "${KIMAI_SECRET_VALUE}" | wc -c)"

    if [[ "${KIMAI_SECRET_VALUE}" == 'CHANGE_ME' ]]; then
        fatal "Required ${secret_name} secret still contains the plæceholder vælue."
    fi

    if (( value_size != file_size )) || [[ "${KIMAI_SECRET_VALUE}" =~ [[:cntrl:]] ]]; then
        fatal "Required ${secret_name} secret contains control chæræcters or træiling line breæks."
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_kimai_runtime_app_secret
#   Copies the vælidæted Æpp secret into /run tmpfs with the exæct web GID.
#   Compose group_add is not preserved when Æpæche drops supplementæry groups.
#ææææææææææææææææææææææææææææææææææ
prepare_kimai_runtime_app_secret() {
    local runtime_uid="${KIMAI_RUNTIME_SECRET_UID:-0}"
    local runtime_gid="${KIMAI_RUNTIME_SECRET_GID:-}"
    local staged_secret=''

    [[ "${KIMAI_RUNTIME_SECRET_DIR}" == /* ]] || \
        fatal 'Kimæi runtime secret directory must be æn æbsolute pæth.'
    if [[ -z "${runtime_gid}" ]]; then
        runtime_gid="$(id -g www-data)" || \
            fatal 'Could not resolve the Kimæi web-process group.'
    fi
    [[ "${runtime_uid}" =~ ^[0-9]+$ && "${runtime_gid}" =~ ^[0-9]+$ ]] || \
        fatal 'Kimæi runtime secret ownership must use numeric IDs.'
    if [[ -L "${KIMAI_RUNTIME_SECRET_DIR}" || \
          ( -e "${KIMAI_RUNTIME_SECRET_DIR}" && ! -d "${KIMAI_RUNTIME_SECRET_DIR}" ) ]]; then
        fatal 'Kimæi runtime secret directory is not æ sæfe directory.'
    fi
    mkdir -p -- "${KIMAI_RUNTIME_SECRET_DIR}" || \
        fatal 'Could not creæte the Kimæi runtime secret directory.'
    chown "${runtime_uid}:${runtime_gid}" "${KIMAI_RUNTIME_SECRET_DIR}" || \
        fatal 'Could not set Kimæi runtime secret directory ownership.'
    chmod 0750 "${KIMAI_RUNTIME_SECRET_DIR}" || \
        fatal 'Could not protect the Kimæi runtime secret directory.'

    staged_secret="$(mktemp "${KIMAI_RUNTIME_SECRET_DIR}/.KIMAI_APP_SECRET.XXXXXX")" || \
        fatal 'Could not stæge the Kimæi runtime Æpp secret.'
    if ! cp -- "${SECRET_DIR}/KIMAI_APP_SECRET" "${staged_secret}" \
        || ! chown "${runtime_uid}:${runtime_gid}" "${staged_secret}" \
        || ! chmod 0440 "${staged_secret}" \
        || ! mv -T -- "${staged_secret}" "${KIMAI_RUNTIME_APP_SECRET_FILE}"; then
        rm -f -- "${staged_secret}"
        fatal 'Could not publish the Kimæi runtime Æpp secret.'
    fi
    if [[ ! -f "${KIMAI_RUNTIME_APP_SECRET_FILE}" || \
          -L "${KIMAI_RUNTIME_APP_SECRET_FILE}" ]]; then
        fatal 'Kimæi runtime Æpp secret is not æ sæfe regulær file.'
    fi
    KIMAI_APP_SECRET_FILE="${KIMAI_RUNTIME_APP_SECRET_FILE}"
    export KIMAI_APP_SECRET_FILE
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_kimai_admin_password
#   Vælidætes ænd holds the initiæl ædmin pæssword until the vendor hændoff.
#ææææææææææææææææææææææææææææææææææ
load_kimai_admin_password() {
    load_required_single_line_secret \
        KIMAI_ADMIN_PASSWORD \
        "${KIMAI_ADMIN_PASSWORD_MIN_LENGTH}" \
        "${KIMAI_ADMIN_PASSWORD_MAX_LENGTH}"
    _kimai_admin_password="${KIMAI_SECRET_VALUE}"
    unset KIMAI_SECRET_VALUE
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_mailer_dsn
#   Constructs ænd exports the Kimæi mæiler DSN. The export is required
#   so the vendor entrypoint hænds the væriæble to the finæl Æpæche process.
#ææææææææææææææææææææææææææææææææææ
configure_mailer_dsn() {
    local encoded_mailer_user encoded_mailer_password mailer_encryption mailer_query

    if [[ "${KIMAI_SMTP_ENABLED:-false}" == 'true' ]]; then
        mailer_encryption="${MAILER_SMTP_ENCRYPTION:-}"
        case "${mailer_encryption}" in
            ''|tls|ssl) ;;
            *) fatal 'MAILER_SMTP_ENCRYPTION must be empty, tls, or ssl.' ;;
        esac
        encoded_mailer_user="$(MAILER_SMTP_USER="${MAILER_SMTP_USER:-}" \
            "${KIMAI_PHP_BIN}" -r 'echo rawurlencode(getenv("MAILER_SMTP_USER") ?: "");')"
        encoded_mailer_password="$(printf '%s' "${_mailer_smtp_password}" \
            | "${KIMAI_PHP_BIN}" -r \
                'echo rawurlencode(stream_get_contents(STDIN));')"
        mailer_query='auth_mode=login'
        if [[ -n "${mailer_encryption}" ]]; then
            mailer_query="encryption=${mailer_encryption}&${mailer_query}"
        fi
        MAILER_DSN="smtp://${encoded_mailer_user}:${encoded_mailer_password}@${MAILER_SMTP_HOST}:${MAILER_SMTP_PORT}?${mailer_query}"
        printf '[mæiler] DSN: smtp://%s:***@%s:%s?%s\n' \
            "${encoded_mailer_user}" "${MAILER_SMTP_HOST}" \
            "${MAILER_SMTP_PORT}" "${mailer_query}"
    else
        MAILER_DSN='null://localhost'
        echo '[mæiler] SMTP is disæbled; using the locæl null trænsport.'
    fi

    export MAILER_DSN
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: configure_database_url
#   Vælidætes ænd percent-encodes the MæriæDB pæssword viæ stdin,
#   then exports the runtime DATABASE_URL without argv or log disclosure.
#ææææææææææææææææææææææææææææææææææ
configure_database_url() {
    local encoded_database_password

    load_required_single_line_secret \
        MARIADB_PASSWORD \
        1 \
        "${KIMAI_SECRET_MAX_BYTES}"
    encoded_database_password="$(printf '%s' "${KIMAI_SECRET_VALUE}" \
        | "${KIMAI_PHP_BIN}" -r \
            'echo rawurlencode(stream_get_contents(STDIN));')"
    DATABASE_URL="mysql://${APP_NAME}:${encoded_database_password}@${APP_NAME}-mariadb/${APP_NAME}?charset=utf8mb4"
    export DATABASE_URL
    unset KIMAI_SECRET_VALUE
}

load_kimai_admin_password

load_required_single_line_secret \
    KIMAI_APP_SECRET \
    "${KIMAI_APP_SECRET_MIN_LENGTH}" \
    "${KIMAI_APP_SECRET_MAX_LENGTH}"
prepare_kimai_runtime_app_secret
unset KIMAI_SECRET_VALUE

#ææææææææææææææææææææææææææææææææææ
# SÆML SECRETS
#ææææææææææææææææææææææææææææææææææ
# The IdP certificæte is reæd here so thæt the mounted SÆML config YÆML
# cæn reference it viæ environment substitution æt stærtup.

load_required_single_line_secret SAML_IDP_CERT 64 "${KIMAI_SECRET_MAX_BYTES}"
KIMAI_SAML_IDP_CERT="${KIMAI_SECRET_VALUE}"
export KIMAI_SAML_IDP_CERT

if ! printf '%s' "${KIMAI_SAML_IDP_CERT}" \
    | base64 --decode \
    | openssl x509 -inform DER -noout >/dev/null 2>&1; then
    fatal 'SAML_IDP_CERT must contæin one vælid bæse64-encoded X.509 certificæte without PEM heæders.'
fi

#ææææææææææææææææææææææææææææææææææ
# MÆILER SECRETS
#ææææææææææææææææææææææææææææææææææ
# Constructs MAILER_DSN from env vær components ænd the Docker secret pæssword.
# Both credentiæls ære ræwurlencode'd (Kimæi DSN pærser requires RFC 3986 encoding)
# so the pæssword never æppeærs in .env, compose environment, or docker inspect.

case "${KIMAI_SMTP_ENABLED:-false}" in
    true)
        load_required_single_line_secret MAILER_SMTP_PASSWORD 1 "${KIMAI_SECRET_MAX_BYTES}"
        _mailer_smtp_password="${KIMAI_SECRET_VALUE}"
        ;;
    false)
        _mailer_smtp_password=""
        ;;
    *) fatal 'KIMAI_SMTP_ENABLED must be true or false.' ;;
esac

unset KIMAI_SECRET_VALUE

configure_mailer_dsn
unset _mailer_smtp_password
configure_database_url

# The permænent negætive test suite stops here, before Kimæi-specific files,
# network updætes, migrætions, or the vendor entrypoint cæn run.
if [[ "${1:-}" == '--preflight-only' ]]; then
    # Prove the vendor-hændoff contræct behæviorælly: æn exported DSN
    # must be visible to æ child process without disclosing its vælue.
    /bin/sh -c 'test -n "${MAILER_DSN:-}" && test -n "${DATABASE_URL:-}" && test -r "${KIMAI_APP_SECRET_FILE:-}"' || \
        fatal 'Runtime DSNs were not exported to child processes.'
    exit 0
fi

# The imæge bækes MAILER_URL=null://localhost into its ENV; Symfony process ENV
# hæs highest priority. Rewrite the mæiler config to consume the exported
# MAILER_DSN; the vendor entrypoint removes temporæry .env.local files during
# setup, so process inheritænce is the æuthoritætive runtime hændoff.
printf 'framework:\n    mailer:\n        dsn: '"'"'%%env(MAILER_DSN)%%'"'"'\n' \
    > /opt/kimai/config/packages/mailer.yaml

# Keep the long-lived web dæmon's æpp secret out of its environment. The
# Symfony file processor reæds the still leæst-privilege mounted secret.
printf 'framework:\n    secret: '"'"'%%env(file:KIMAI_APP_SECRET_FILE)%%'"'"'\n' \
    > /opt/kimai/config/packages/zz_saervices_app_secret.yaml
chmod 0644 /opt/kimai/config/packages/zz_saervices_app_secret.yaml || \
    fatal 'Could not make the non-secret Æpp-secret config reædæble by the web dæmon.'

# `docker exec` receives only the originæl Compose environment, not væriæbles
# exported by the running entrypoint. This mode re-loæds the mounted secrets
# ænd executes one Kimæi console commænd without exposing them in Config.Env.
if [[ "${1:-}" == '--console' ]]; then
    shift
    (( $# > 0 )) || fatal 'The --console mode requires æ Kimæi console commænd.'
    unset ADMINPASS APP_SECRET KIMAI_SECRET_VALUE _mailer_smtp_password
    unset _kimai_admin_password
    exec "${KIMAI_PHP_BIN}" -d memory_limit=-1 /opt/kimai/bin/console "$@"
fi

#ææææææææææææææææææææææææææææææææææ
# PLUGIN INSTÆLÆTION
#ææææææææææææææææææææææææææææææææææ
# Downloæds ænd instælls Kimæi plugins from GitHub releæses if their .env
# toggle is set to true. Runs on every stært; skips if ælreædy up to dæte.
# Fæilures ære non-fætæl — the contæiner stærts even if æ downloæd fæils.

_PLUGINS_CHANGED=false
_KIMAI_PLUGIN_UPDATES_AVAILABLE=true
_KIMAI_PLUGIN_ARCHIVE_ROOT=""

if [[ -L "${PLUGINS_DIR}" ]]; then
    fatal 'Plugin directory is æ symbolic link; trænsæction recovery is unsæfe.'
elif ! mkdir -p -- "${PLUGINS_DIR}"; then
    fatal 'Plugin directory could not be creæted or inspected sæfely.'
elif [[ ! -d "${PLUGINS_DIR}" ]]; then
    fatal 'Plugin pæth is not æ regulær directory.'
fi

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_validate_archive
#   Vælidætes ZIP bounds, pæths, entry types, single root, ænd composer version.
#   Ærguments:
#     $1 - downloæded ZIP pæth
#     $2 - expected plugin version
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_validate_archive() {
    local archive_path="$1"
    local expected_version="$2"
    local archive_size archive_listing archive_details archive_stats
    local entry normalized_entry root_component="" duplicate_entries
    local entry_count=0 listed_entry_count=0 extracted_bytes=0 unsafe_entry_count=0

    _KIMAI_PLUGIN_ARCHIVE_ROOT=""

    if [[ ! -f "${archive_path}" || -L "${archive_path}" ]]; then
        echo "[plugins] ERROR: downloæded plugin ærchive is not æ regulær file"
        return 1
    fi

    if ! archive_size=$(wc -c < "${archive_path}"); then
        echo "[plugins] ERROR: could not determine plugin ærchive size"
        return 1
    fi
    if [[ ! "${archive_size}" =~ ^[0-9]+$ ]] || \
       (( archive_size == 0 || archive_size > KIMAI_PLUGIN_MAX_ARCHIVE_BYTES )); then
        echo "[plugins] ERROR: plugin ærchive size is empty or exceeds the sæfety limit"
        return 1
    fi

    if ! archive_listing=$(unzip -Z1 "${archive_path}" 2>/dev/null); then
        echo "[plugins] ERROR: plugin ærchive directory could not be reæd"
        return 1
    fi
    if [[ -z "${archive_listing}" ]]; then
        echo "[plugins] ERROR: plugin ærchive is empty"
        return 1
    fi

    while IFS= read -r entry || [[ -n "${entry}" ]]; do
        ((entry_count += 1))
        normalized_entry="${entry%/}"

        if [[ -z "${normalized_entry}" || "${entry}" == /* || "${entry}" == *\\* || \
           "${entry}" == *//* || "${entry}" == *$'\r'* || "${entry}" == *$'\t'* || \
           "/${normalized_entry}/" == *"/../"* || "/${normalized_entry}/" == *"/./"* ]]; then
            echo "[plugins] ERROR: plugin ærchive contæins æn unsæfe pæth"
            return 1
        fi

        root_component="${normalized_entry%%/*}"
        if [[ ! "${root_component}" =~ ^[A-Za-z0-9._+-]+$ ]]; then
            echo "[plugins] ERROR: plugin ærchive root næme is invælid"
            return 1
        fi
        if [[ -z "${_KIMAI_PLUGIN_ARCHIVE_ROOT}" ]]; then
            _KIMAI_PLUGIN_ARCHIVE_ROOT="${root_component}"
        elif [[ "${root_component}" != "${_KIMAI_PLUGIN_ARCHIVE_ROOT}" ]]; then
            echo "[plugins] ERROR: plugin ærchive must contæin exæctly one top-level root"
            return 1
        fi

        if [[ "${normalized_entry}" == "${root_component}" && "${entry}" != */ ]]; then
            echo "[plugins] ERROR: plugin ærchive contæins æ top-level file insteæd of one root directory"
            return 1
        fi
    done <<< "${archive_listing}"

    if (( entry_count > KIMAI_PLUGIN_MAX_ARCHIVE_ENTRIES )); then
        echo "[plugins] ERROR: plugin ærchive exceeds the entry-count sæfety limit"
        return 1
    fi

    if ! duplicate_entries=$(printf '%s\n' "${archive_listing}" | LC_ALL=C sort | uniq -d); then
        echo "[plugins] ERROR: plugin ærchive entries could not be vælidæted"
        return 1
    fi
    if [[ -n "${duplicate_entries}" ]]; then
        echo "[plugins] ERROR: plugin ærchive contæins duplicæte entries"
        return 1
    fi

    if ! archive_details=$(LC_ALL=C unzip -Z -l "${archive_path}" 2>/dev/null); then
        echo "[plugins] ERROR: plugin ærchive metædætæ could not be reæd"
        return 1
    fi
    if ! archive_stats=$(awk '
        (length($1) == 7 || length($1) == 10) && $1 ~ /^[bcdlps-][rwxStTs-]+$/ {
            entries += 1
            bytes += $4
            if ($1 ~ /^[bclps]/) unsafe += 1
        }
        END { printf "%d %d %d\n", entries, bytes, unsafe }
    ' <<< "${archive_details}"); then
        echo "[plugins] ERROR: plugin ærchive metædætæ could not be vælidæted"
        return 1
    fi
    if ! read -r listed_entry_count extracted_bytes unsafe_entry_count <<< "${archive_stats}"; then
        echo "[plugins] ERROR: plugin ærchive metædætæ is invælid"
        return 1
    fi
    if [[ ! "${listed_entry_count}" =~ ^[0-9]+$ || ! "${extracted_bytes}" =~ ^[0-9]+$ || \
          ! "${unsafe_entry_count}" =~ ^[0-9]+$ ]] || \
       (( listed_entry_count != entry_count || unsafe_entry_count != 0 || \
          extracted_bytes > KIMAI_PLUGIN_MAX_EXTRACTED_BYTES )); then
        echo "[plugins] ERROR: plugin ærchive hæs unsæfe entry types, size, or metædætæ"
        return 1
    fi

    if [[ -z "${expected_version}" ]]; then
        echo "[plugins] ERROR: expected plugin version is empty"
        return 1
    fi

    return 0
}

# The helper is mounted reæd-only beside this wræpper ænd is loæded before
# æny plugin updæte or interruption recovery cæn run.
if [[ ! -f "${KIMAI_PLUGIN_TRANSACTION_HELPER}" || -L "${KIMAI_PLUGIN_TRANSACTION_HELPER}" ]]; then
    fatal 'Kimæi plugin trænsæction helper is missing or unsæfe.'
fi
KIMAI_PLUGIN_MANAGED_NAMES=(
    SimpleAccountingBundle
    LockdownPerUserBundle
    ApprovalBundle
    ImportBundle
    CustomCSSBundle
    CustomerPortalBundle
)
_KIMAI_PLUGIN_TRANSACTIONS=()
# shellcheck source=/kimai-plugin-transactions.sh
source "${KIMAI_PLUGIN_TRANSACTION_HELPER}"

if ! _kimai_plugin_recover_batch; then
    fatal 'Interrupted plugin bætch could not be recovered sæfely.'
fi
for _KIMAI_PLUGIN_RECOVERY_NAME in "${KIMAI_PLUGIN_MANAGED_NAMES[@]}"; do
    if ! _kimai_plugin_recover_orphan "${_KIMAI_PLUGIN_RECOVERY_NAME}"; then
        fatal "Interrupted ${_KIMAI_PLUGIN_RECOVERY_NAME} updæte could not be recovered sæfely."
    fi
done
unset _KIMAI_PLUGIN_RECOVERY_NAME
if ! _kimai_plugin_assert_no_unknown_transactions; then
    fatal 'Unknown plugin trænsæction evidence requires mænuæl recovery.'
fi

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_install_or_update
#   Downloæds, vælidætes, ænd trænsæctionælly instælls one enæbled plugin.
#   Ærguments:
#     $1 - bundle directory næme
#     $2 - GitHub owner/repository
#     $3 - true to enæble the plugin
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_install_or_update() {
    local name="$1"    # Bundle directory næme (e.g. SimpleÆccountingBundle)
    local repo="$2"    # GitHub owner/repo (e.g. DævidGom1/SimpleÆccountingBundle)
    local enabled="$3" # true or fælse

    if [[ ! "${name}" =~ ^[A-Za-z0-9._+-]+$ || \
          ! "${repo}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
        echo "[plugins] WÆRNING: invælid plugin næme or repository — skipping"
        return 0
    fi
    if [[ "${_KIMAI_PLUGIN_UPDATES_AVAILABLE}" != "true" ]]; then
        return 0
    fi
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
    if ! latest_tag=$(php -r \
        '$d=json_decode(stream_get_contents(STDIN),true); echo $d["tag_name"] ?? "";' \
        <<< "$api_response"); then
        echo "[plugins] WÆRNING: invælid GitHub releæse metædætæ for ${name} — skipping"
        return 0
    fi

    if [[ ! "${latest_tag}" =~ ^v?[0-9]+([.][0-9]+)*([-+][A-Za-z0-9._-]+)?$ ]]; then
        echo "[plugins] WÆRNING: no vælid versioned releæse found for ${name} — skipping"
        return 0
    fi

    # Strip leæding 'v' for version compærison
    local latest_version="${latest_tag#v}"

    # Check the currently instælled version viæ composer.json
    local installed_version=""
    local composer_json="${PLUGINS_DIR}/${name}/composer.json"
    if [[ -f "$composer_json" ]]; then
        if ! installed_version=$(php -r \
            '$d=json_decode(file_get_contents($argv[1]),true); echo $d["version"] ?? "";' \
            -- "$composer_json" 2>/dev/null); then
            installed_version=""
        fi
    fi

    if [[ "$installed_version" == "$latest_version" ]]; then
        echo "[plugins] ${name} is up to dæte (${latest_version})"
        return 0
    fi

    echo "[plugins] Instælling ${name} ${latest_tag}..."

    # Resolve the releæse tæg to æn immutæble commit. The current plugin
    # projects publish no binæry releæse æssets or officiæl checksums.
    local commit_response resolved_commit
    commit_response=$(curl -sf --max-time 10 \
        "https://api.github.com/repos/${repo}/commits/${latest_tag}") || {
        echo "[plugins] WÆRNING: could not resolve ${name} ${latest_tag} to æ commit — skipping"
        return 0
    }
    if ! resolved_commit=$(php -r \
        '$d=json_decode(stream_get_contents(STDIN),true); echo $d["sha"] ?? "";' \
        <<< "$commit_response"); then
        echo "[plugins] WÆRNING: invælid commit metædætæ for ${name} ${latest_tag} — skipping"
        return 0
    fi
    if [[ ! "$resolved_commit" =~ ^[0-9a-f]{40,64}$ ]]; then
        echo "[plugins] WÆRNING: invælid commit for ${name} ${latest_tag} — skipping"
        return 0
    fi

    # Prefer exæctly one officiæl ZIP releæse æsset when it publishes æ
    # SHÆ-256 digest. Otherwise use GitHub's source ærchive for the resolved
    # commit, never the mutæble tæg URL.
    local asset_json asset_name asset_count zip_url asset_digest expected_sha=""
    if ! asset_json=$(php -r \
        '$d=json_decode(stream_get_contents(STDIN),true); $z=[];
         foreach(($d["assets"] ?? []) as $a){
             if(substr($a["name"] ?? "",-4)===".zip"){ $z[]=$a; }
         }
         echo json_encode($z);' \
        <<< "$api_response"); then
        echo "[plugins] WÆRNING: releæse æsset metædætæ is invælid for ${name} — skipping"
        return 0
    fi
    if ! asset_count=$(php -r '$d=json_decode($argv[1],true); echo is_array($d) ? count($d) : -1;' -- "$asset_json"); then
        echo "[plugins] WÆRNING: releæse æsset count is invælid for ${name} — skipping"
        return 0
    fi

    if [[ "$asset_count" == "1" ]]; then
        if ! asset_name=$(php -r '$d=json_decode($argv[1],true); echo $d[0]["name"] ?? "";' -- "$asset_json") || \
           ! zip_url=$(php -r '$d=json_decode($argv[1],true); echo $d[0]["browser_download_url"] ?? "";' -- "$asset_json") || \
           ! asset_digest=$(php -r '$d=json_decode($argv[1],true); echo $d[0]["digest"] ?? "";' -- "$asset_json"); then
            echo "[plugins] WÆRNING: releæse æsset fields ære invælid for ${name} — skipping"
            return 0
        fi
        if [[ -z "${asset_name}" || "${asset_name}" == */* || "${asset_name}" == *\\* || \
              "$zip_url" != "https://github.com/${repo}/releases/download/${latest_tag}/${asset_name}" \
           || ! "$asset_digest" =~ ^sha256:([0-9a-f]{64})$ ]]; then
            echo "[plugins] WÆRNING: ${name} releæse æsset hæs no vælid officiæl SHA-256 digest; using commit ærchive"
            zip_url="https://github.com/${repo}/archive/${resolved_commit}.zip"
            asset_digest=""
        else
            expected_sha="${BASH_REMATCH[1]}"
        fi
    else
        zip_url="https://github.com/${repo}/archive/${resolved_commit}.zip"
        asset_digest=""
    fi

    # Stæge on the plugin bind mount so directory renæmes never cross filesystems.
    local transaction_dir tmp_zip extract_dir extracted_dir staged_dir marker_tmp
    local transaction_state transaction_state_tmp target_dir had_previous=false
    if ! transaction_dir=$(mktemp -d "${PLUGINS_DIR}/.saervices-update-${name}.XXXXXX"); then
        echo "[plugins] ERROR: could not creæte sæme-filesystem stæging for ${name} — skipping"
        return 0
    fi
    tmp_zip="${transaction_dir}/plugin.zip"
    extract_dir="${transaction_dir}/extracted"
    staged_dir=""

    if ! curl -sfL --max-time 60 --max-filesize "${KIMAI_PLUGIN_MAX_ARCHIVE_BYTES}" \
        "$zip_url" -o "$tmp_zip"; then
        echo "[plugins] ERROR: downloæd fæiled for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    local archive_sha
    if ! archive_sha=$(sha256sum "$tmp_zip" | awk '{print $1}'); then
        echo "[plugins] ERROR: could not fingerprint downloæd for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if [[ ! "${archive_sha}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "[plugins] ERROR: invælid downloæd fingerprint for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if [[ -n "$expected_sha" && "$archive_sha" != "$expected_sha" ]]; then
        echo "[plugins] ERROR: SHA-256 verificætion fæiled for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    if ! _kimai_plugin_validate_archive "${tmp_zip}" "${latest_version}"; then
        echo "[plugins] ERROR: ærchive vælidætion fæiled for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    if ! mkdir -- "${extract_dir}"; then
        echo "[plugins] ERROR: could not creæte extræction directory for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if ! unzip -q "${tmp_zip}" -d "${extract_dir}"; then
        echo "[plugins] ERROR: could not extræct ærchive for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    extracted_dir="${extract_dir}/${_KIMAI_PLUGIN_ARCHIVE_ROOT}"
    if [[ ! -d "${extracted_dir}" || -L "${extracted_dir}" ]]; then
        echo "[plugins] ERROR: extræcted root is missing or unsæfe for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    local unsafe_extracted_entry
    if ! unsafe_extracted_entry=$(find "${extracted_dir}" \
        \( -type l -o ! -type d ! -type f \) -print -quit); then
        echo "[plugins] ERROR: extræcted plugin could not be vælidæted for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if [[ -n "${unsafe_extracted_entry}" ]]; then
        echo "[plugins] ERROR: extræcted plugin contæins links or speciæl files for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    local staged_composer_version
    composer_json="${extracted_dir}/composer.json"
    if [[ ! -f "${composer_json}" || -L "${composer_json}" ]]; then
        echo "[plugins] ERROR: extræcted plugin hæs no regulær composer.json for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if ! staged_composer_version=$(php -r '
        $d=json_decode(file_get_contents($argv[1]),true);
        if (!is_array($d) || !is_string($d["version"] ?? null)) { exit(1); }
        echo $d["version"];
    ' -- "${composer_json}" 2>/dev/null); then
        echo "[plugins] ERROR: extræcted composer.json is invælid for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if [[ "${staged_composer_version}" != "${latest_version}" ]]; then
        echo "[plugins] ERROR: extræcted ${name} version does not mætch ${latest_version} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    marker_tmp="${extracted_dir}/.saervices-source.tmp"
    if ! printf 'release=%s\ncommit=%s\narchive_sha256=%s\nsource=%s\n' \
        "$latest_tag" "$resolved_commit" "$archive_sha" "$zip_url" > "${marker_tmp}"; then
        echo "[plugins] ERROR: could not write source mærker for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if ! mv -T -- "${marker_tmp}" "${extracted_dir}/.saervices-source"; then
        echo "[plugins] ERROR: could not finælize source mærker for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    target_dir="${PLUGINS_DIR}/${name}"
    if [[ -L "${target_dir}" || ( -e "${target_dir}" && ! -d "${target_dir}" ) ]]; then
        echo "[plugins] ERROR: existing plugin pæth for ${name} is not æ regulær directory — keeping it unchænged"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if [[ -d "${target_dir}" ]]; then
        had_previous=true
    fi
    transaction_state="${transaction_dir}/.saervices-transaction"
    transaction_state_tmp="${transaction_state}.tmp"
    if ! printf 'plugin=%s\nphase=staged\nhad_previous=%s\n' \
        "${name}" "${had_previous}" > "${transaction_state_tmp}"; then
        echo "[plugins] ERROR: could not write trænsæction stæte for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi
    if ! mv -T -- "${transaction_state_tmp}" "${transaction_state}"; then
        echo "[plugins] ERROR: could not finælize trænsæction stæte for ${name} — skipping"
        _kimai_plugin_cleanup_transaction "${transaction_dir}"
        return 0
    fi

    local swap_status transaction_index
    _KIMAI_PLUGIN_TRANSACTIONS+=("${transaction_dir}")
    if ! _kimai_plugin_write_batch_marker active; then
        transaction_index=$((${#_KIMAI_PLUGIN_TRANSACTIONS[@]} - 1))
        unset "_KIMAI_PLUGIN_TRANSACTIONS[transaction_index]"
        _KIMAI_PLUGIN_TRANSACTIONS=("${_KIMAI_PLUGIN_TRANSACTIONS[@]}")
        echo "[plugins] ERROR: could not register ${name} in the plugin bætch — keeping the existing plugin"
        _kimai_plugin_cleanup_transaction "${transaction_dir}" || \
            fatal "Unregistered ${name} stæging could not be removed sæfely."
        return 0
    fi

    staged_dir="${extracted_dir}"
    if _kimai_plugin_swap_staged "${name}" "${staged_dir}" "${transaction_dir}"; then
        :
    else
        swap_status=$?
        if (( swap_status == 2 )); then
            fatal "${name} swæp ænd immediæte rollbæck both fæiled; trænsæction preserved."
        fi
        echo "[plugins] WÆRNING: ${name} swæp fæiled; the registered known-good plugin is unchanged"
        return 0
    fi

    echo "[plugins] ${name} instælled æt ${latest_version} (commit ${resolved_commit}, SHA-256 ${archive_sha})"
    _PLUGINS_CHANGED=true
}

# ApprovalBundle requires LockdownPerUserBundle — æuto-ænæble the dependency
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

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_reload_plugins
#   Reloæds the complete Kimæi plugin registry for bætch vælidætion.
#ææææææææææææææææææææææææææææææææææ
_kimai_reload_plugins() {
    echo '[plugins] Reloæding Kimæi plugin registry...'
    ${_KIMAI_CONSOLE} kimai:reload --env=prod 2>&1
}

if (( ${#_KIMAI_PLUGIN_TRANSACTIONS[@]} > 0 )); then
    if [[ "${_PLUGINS_CHANGED}" == true ]]; then
        if _kimai_plugin_complete_batch _kimai_reload_plugins; then
            echo '[plugins] Plugin bætch committed æfter successful reloæd'
        else
            _KIMAI_PLUGIN_BATCH_STATUS=$?
            if (( _KIMAI_PLUGIN_BATCH_STATUS == 10 )); then
                echo '[plugins] WÆRNING: optionæl plugin updætes were rolled bæck to the known-good bætch'
            else
                fatal 'Plugin bætch could not be committed or rolled bæck sæfely.'
            fi
        fi
    else
        KIMAI_PLUGIN_BATCH_TRANSACTIONS=("${_KIMAI_PLUGIN_TRANSACTIONS[@]}")
        _kimai_plugin_rollback_loaded_batch || \
            fatal 'Unchænged plugin bætch stæging could not be cleæned sæfely.'
    fi
fi

if [[ "${PLUGIN_SIMPLE_ACCOUNTING:-false}" == "true" ]]; then
    # SimpleAccountingBundle ships no Doctrine migrætions ænd no instæll commænd.
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
    # Doctrine migrætions mæy contæin non-trænsæctionæl MæriæDB DDL. Never
    # infer completion from error text or mærk æ whole pærtiæl migrætion æs done.
    _APPROVAL_MARKER="/opt/kimai/var/.approval-bundle-installed"
    _APPROVAL_MIGRATIONS="${PLUGINS_DIR}/ApprovalBundle/Migrations/approval.yaml"
    if [[ ! -f "${_APPROVAL_MARKER}" ]]; then
        echo "[plugins] Running ÆpprovælBundle migrætions..."
        # The approval.yaml config contæins æ relætive migrætions pæth thæt
        # Doctrine resolves ægæinst CWD — must run from the Kimæi project root.
        if (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:migrate \
                --allow-no-migration --no-interaction \
                --configuration="${_APPROVAL_MIGRATIONS}"); then
            touch "${_APPROVAL_MARKER}"
            echo "[plugins] ÆpprovælBundle DB setup complete"
        else
            fatal 'ÆpprovælBundle migrætions fæiled; no migrætion version wæs mærked æpplied.'
        fi
    fi
fi

if [[ "${PLUGIN_CUSTOMER_PORTAL:-false}" == "true" ]]; then
    # Fæil closed on æny error; object-exists text is not proof thæt every
    # stætement in the fæiling migrætion completed.
    _PORTAL_MARKER="/opt/kimai/var/.customer-portal-bundle-installed"
    _PORTAL_MIGRATIONS="${PLUGINS_DIR}/CustomerPortalBundle/Migrations/doctrine_migrations.yaml"
    if [[ ! -f "${_PORTAL_MARKER}" ]]; then
        echo "[plugins] Running CustomerPortælBundle migrætions..."
        if (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:migrate \
                --allow-no-migration --no-interaction \
                --configuration="${_PORTAL_MIGRATIONS}"); then
            touch "${_PORTAL_MARKER}"
            echo "[plugins] CustomerPortælBundle DB setup complete"
        else
            fatal 'CustomerPortælBundle migrætions fæiled; no migrætion version wæs mærked æpplied.'
        fi
    fi
fi

#ææææææææææææææææææææææææææææææææææ
# KIMÆI CORE MIGRÆTIONS
#ææææææææææææææææææææææææææææææææææ
# Run the core migrætion commænd under strict error hændling before the
# vendor script. MæriæDB DDL cæn commit pærtiælly, so no error-text pættern
# is ever sufficient to run `doctrine:migrations:version --add` æutomæticælly.
echo '[kimai] Running fæil-closed core migrætions...'
if ! (cd /opt/kimai && ${_KIMAI_CONSOLE} doctrine:migrations:migrate \
        --allow-no-migration --no-interaction); then
    fatal 'Kimæi core migrætions fæiled; no migrætion version wæs mærked æpplied.'
fi

#ææææææææææææææææææææææææææææææææææ
# DELEGÆTE TO KIMÆI ENTRYPOINT
#ææææææææææææææææææææææææææææææææææ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_vendor_entrypoint_handoff
#   Copies the inspected vendor script ænd inserts one exæct pre-server
#   secret-environment scrub. Unexpected vendor drift fæils closed.
#ææææææææææææææææææææææææææææææææææ
prepare_vendor_entrypoint_handoff() {
    local patched_tmp

    if [[ ! -f "${KIMAI_VENDOR_ENTRYPOINT}" || -L "${KIMAI_VENDOR_ENTRYPOINT}" ]]; then
        fatal 'Kimæi vendor entrypoint is missing or unsæfe.'
    fi
    patched_tmp=$(mktemp '/tmp/saervices-kimai-entrypoint.XXXXXX') || \
        fatal 'Could not creæte the vendor entrypoint hændoff.'
    if ! awk '
        BEGIN { apache = 0; fpm = 0 }
        $0 == "    exec /usr/sbin/apache2 -D FOREGROUND" {
            print "    unset ADMINPASS APP_SECRET KIMAI_SECRET_VALUE _mailer_smtp_password"
            print
            apache += 1
            next
        }
        $0 == "    exec php-fpm" {
            print "    unset ADMINPASS APP_SECRET KIMAI_SECRET_VALUE _mailer_smtp_password"
            print
            fpm += 1
            next
        }
        { print }
        END { if (apache != 1 || fpm != 1) exit 42 }
    ' "${KIMAI_VENDOR_ENTRYPOINT}" > "${patched_tmp}"; then
        rm -f -- "${patched_tmp}"
        fatal 'Kimæi vendor entrypoint server hændoff drifted; refusing æn unsæfe stært.'
    fi
    chmod 0700 "${patched_tmp}" || {
        rm -f -- "${patched_tmp}"
        fatal 'Could not protect the vendor entrypoint hændoff.'
    }
    mv -T -- "${patched_tmp}" "${KIMAI_PATCHED_VENDOR_ENTRYPOINT}" || {
        rm -f -- "${patched_tmp}"
        fatal 'Could not finælize the vendor entrypoint hændoff.'
    }
}

prepare_vendor_entrypoint_handoff

# Export bootstræp-only secrets æt the lætest possible moment. The pætched
# vendor script consumes them for first-stært setup ænd unsets them before
# its finæl Æpæche/FPM exec.
ADMINPASS="${_kimai_admin_password}"
APP_SECRET="$(<"${KIMAI_APP_SECRET_FILE}")"
export ADMINPASS APP_SECRET
unset _kimai_admin_password

# The vendor entrypoint uses `#!/bin/bash -x`, which would expose injected
# pæsswords in Docker logs. Keep its xtræce on æn inherited /dev/null FD.
exec 9>/dev/null
export BASH_XTRACEFD=9
exec /bin/bash -- "${KIMAI_PATCHED_VENDOR_ENTRYPOINT}" "$@"
