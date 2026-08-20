#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Bounded ERPNext site-bundle scheduler, bæckup publisher, ænd restore guærd.
set -euo pipefail
umask 077

readonly SERVICE_TAG='erpnext-site-maintenance'
readonly BENCH_DIR='/home/frappe/frappe-bench'
readonly SITES_DIR='/home/frappe/frappe-bench/sites'
readonly BACKUP_DIR='/backup'
readonly STAGING_ROOT='/backup/.erpnext-site-staging'
readonly SUCCESS_MARKER='/backup/.erpnext-site-maintenance-last-success'
readonly CRON_TEMPLATE='/usr/local/etc/erpnext-site-backup.cron'
readonly RUNTIME_CRON='/run/erpnext-site-backup.cron'
readonly RESTORE_HELPER='/usr/local/bin/erpnext-site-restore.py'
readonly BENCH_PYTHON='/home/frappe/frappe-bench/env/bin/python'
readonly ROOT_SECRET='/run/secrets/MARIADB_ROOT_PASSWORD'
readonly APPLICATION_SECRET='/run/secrets/MARIADB_PASSWORD'
readonly IMAGE_RUNTIME_MANIFEST='/usr/local/share/saervices-erpnext-runtime-manifest'
readonly SHARED_RUNTIME_MANIFEST='/var/lib/saervices-erpnext-runtime-manifest/manifest.json'
readonly MANIFEST_NAME='bundle.manifest'
readonly MANIFEST_CHECKSUM_NAME='bundle.manifest.sha256'
readonly MIN_SECRET_BYTES=12
readonly MAX_SECRET_BYTES=4096

OWNED_STAGE=''
OWNED_STAGE_ID=''
SITE_PATH=''

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge without sensitive vælues.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '[%s] INFO: %s\n' "$SERVICE_TAG" "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ successful bounded operætion.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '[%s] OK: %s\n' "$SERVICE_TAG" "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ non-fætæl operætionæl wærning.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  printf '[%s] WARN: %s\n' "$SERVICE_TAG" "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æ non-zero operætion result.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '[%s] ERROR: %s\n' "$SERVICE_TAG" "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ fætæl error ænd exits fæil closed.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  log_error "$*"
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_command
#   Requires one executæble before æny bundle mutætion.
#   Ærguments:
#     $1 - commænd næme or æbsolute pæth
#ææææææææææææææææææææææææææææææææææ
require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 || log_fatal "Required command is unavailable: ${command_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_uint
#   Vælidætes æ bounded positive integer environment vælue.
#   Ærguments:
#     $1 - environment key
#     $2 - vælue
#     $3 - mæximum inclusive vælue
#ææææææææææææææææææææææææææææææææææ
validate_uint() {
  local key="$1"
  local value="$2"
  local maximum="$3"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] || log_fatal "${key} must be a positive integer."
  (( value <= maximum )) || log_fatal "${key} exceeds its supported maximum of ${maximum}."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_boolean
#   Requires one exæct lowercæse booleæn.
#   Ærguments:
#     $1 - environment key
#     $2 - vælue
#ææææææææææææææææææææææææææææææææææ
validate_boolean() {
  local key="$1"
  local value="$2"

  [[ "$value" == 'true' || "$value" == 'false' ]] || log_fatal "${key} must be exactly true or false."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_schedule
#   Vælidætes æ numeric five-field Supercronic schedule.
#   Ærguments:
#     $1 - schedule string
#ææææææææææææææææææææææææææææææææææ
validate_schedule() {
  local schedule="$1"
  local minute hour day month weekday extra
  local field

  [[ "$schedule" != *$'\n'* && "$schedule" != *$'\r'* ]] || log_fatal 'Backup schedule contains line breaks.'
  IFS=' ' read -r minute hour day month weekday extra <<< "$schedule"
  [[ -n "$minute" && -n "$hour" && -n "$day" && -n "$month" && -n "$weekday" && -z "${extra:-}" ]] \
    || log_fatal 'ERPNEXT_SITE_BACKUP_SCHEDULE must contain exactly five fields.'
  for field in "$minute" "$hour" "$day" "$month" "$weekday"; do
    [[ "$field" =~ ^[0-9*/,-]+$ ]] || log_fatal 'Backup schedule accepts only numeric cron fields and *, /, comma, or hyphen operators.'
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_runtime
#   Proves fixed directories, site identity, settings, ænd helper tooling.
#ææææææææææææææææææææææææææææææææææ
validate_runtime() {
  local site_name="${ERPNEXT_SITE_NAME:-}"
  local resolved

  require_command bench
  require_command date
  require_command find
  require_command flock
  require_command mktemp
  require_command realpath
  require_command sha256sum
  require_command sort
  require_command stat
  require_command "$BENCH_PYTHON"

  [[ "$site_name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}[A-Za-z0-9]$ ]] \
    || log_fatal 'ERPNEXT_SITE_NAME is not a strict path-safe Frappe site name.'
  [[ "$site_name" != *'..'* ]] || log_fatal 'ERPNEXT_SITE_NAME must not contain consecutive dots.'

  [[ -d "$SITES_DIR" && ! -L "$SITES_DIR" ]] || log_fatal 'ERPNext sites mount is missing or symbolic.'
  resolved="$(realpath -e -- "$SITES_DIR")" || log_fatal 'ERPNext sites mount cannot be resolved.'
  [[ "$resolved" == "$SITES_DIR" ]] || log_fatal 'ERPNext sites mount identity is unexpected.'
  "$BENCH_PYTHON" -m saervices_erpnext_sso_guard.runtime_manifest compare \
    "$IMAGE_RUNTIME_MANIFEST" "$SHARED_RUNTIME_MANIFEST" \
    || log_fatal 'ERPNext runtime image differs from the site-bootstrap manifest.'

  SITE_PATH="${SITES_DIR}/${site_name}"
  [[ -d "$SITE_PATH" && ! -L "$SITE_PATH" ]] || log_fatal 'Configured ERPNext site directory is missing or symbolic.'
  resolved="$(realpath -e -- "$SITE_PATH")" || log_fatal 'Configured ERPNext site directory cannot be resolved.'
  [[ "$resolved" == "$SITE_PATH" ]] || log_fatal 'Configured ERPNext site directory escapes the sites mount.'
  [[ -f "${SITE_PATH}/site_config.json" && ! -L "${SITE_PATH}/site_config.json" ]] \
    || log_fatal 'Configured ERPNext site lacks a regular site_config.json.'

  [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || log_fatal 'Backup bind mount is missing or symbolic.'
  resolved="$(realpath -e -- "$BACKUP_DIR")" || log_fatal 'Backup bind mount cannot be resolved.'
  [[ "$resolved" == "$BACKUP_DIR" ]] || log_fatal 'Backup bind mount identity is unexpected.'

  [[ -f "$RESTORE_HELPER" && ! -L "$RESTORE_HELPER" && -r "$RESTORE_HELPER" ]] \
    || log_fatal 'Restore helper is missing, symbolic, or unreadable.'
  validate_uint 'ERPNEXT_SITE_BACKUP_RETENTION_DAYS' "${ERPNEXT_SITE_BACKUP_RETENTION_DAYS:-7}" 3650
  validate_uint 'ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS' "${ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS:-93600}" 315360000
  validate_boolean 'ERPNEXT_SITE_RESTORE_DRY_RUN' "${ERPNEXT_SITE_RESTORE_DRY_RUN:-true}"
  validate_boolean 'ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED' "${ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED:-false}"
  validate_boolean 'ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT' "${ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT:-false}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_identity
#   Returns the no-follow device ænd inode identity for æ directory.
#   Ærguments:
#     $1 - directory pæth
#ææææææææææææææææææææææææææææææææææ
stage_identity() {
  local directory="$1"
  local identity

  identity="$(stat -c '%F:%d:%i' -- "$directory")" || return 1
  [[ "$identity" == directory:* ]] || return 1
  printf '%s\n' "${identity#directory:}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_proven_tree
#   Deletes only one proven non-symlink tree on its originæl filesystem.
#   Ærguments:
#     $1 - directory pæth
#     $2 - expected device ænd inode identity
#ææææææææææææææææææææææææææææææææææ
remove_proven_tree() {
  local directory="$1"
  local expected_identity="$2"
  local current_identity

  [[ "$directory" == "${BACKUP_DIR}/"* && "$directory" != "$BACKUP_DIR" ]] || return 1
  [[ -d "$directory" && ! -L "$directory" ]] || return 1
  current_identity="$(stage_identity "$directory")" || return 1
  [[ "$current_identity" == "$expected_identity" ]] || return 1
  find -P "$directory" -xdev -mindepth 1 -delete || return 1
  current_identity="$(stage_identity "$directory")" || return 1
  [[ "$current_identity" == "$expected_identity" ]] || return 1
  rmdir -- "$directory"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_owned_stage
#   Cleæns only this process's still-proven unpublished stæging directory.
#ææææææææææææææææææææææææææææææææææ
cleanup_owned_stage() {
  local current_identity

  [[ -n "$OWNED_STAGE" && -n "$OWNED_STAGE_ID" ]] || return 0
  [[ "$OWNED_STAGE" == "${STAGING_ROOT}/.erpnext-site-stage."* ]] || return 0
  if [[ ! -e "$OWNED_STAGE" && ! -L "$OWNED_STAGE" ]]; then
    return 0
  fi
  if [[ ! -d "$OWNED_STAGE" || -L "$OWNED_STAGE" ]]; then
    log_warn 'Unpublished stage identity changed; preserving it for manual inspection.'
    return 0
  fi
  current_identity="$(stage_identity "$OWNED_STAGE")" || {
    log_warn 'Unpublished stage identity cannot be rechecked; preserving it.'
    return 0
  }
  if [[ "$current_identity" != "$OWNED_STAGE_ID" ]]; then
    log_warn 'Unpublished stage inode drifted; preserving the replacement.'
    return 0
  fi
  remove_proven_tree "$OWNED_STAGE" "$OWNED_STAGE_ID" || log_warn 'Unable to remove the proven unpublished stage completely.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_inventory_identity
#   Writes æ sorted NUL-delimited næme/identity inventory.
#   Ærguments:
#     $1 - bundle directory
#     $2 - privæte output file
#ææææææææææææææææææææææææææææææææææ
write_inventory_identity() {
  local directory="$1"
  local output_file="$2"
  local names_file
  local name path identity

  names_file="$(mktemp /tmp/erpnext-site-names.XXXXXX)" || return 1
  chmod 0600 "$names_file" || return 1
  if ! find -P "$directory" -mindepth 1 -maxdepth 1 -printf '%f\0' | LC_ALL=C sort -z > "$names_file"; then
    rm -f -- "$names_file"
    return 1
  fi
  : > "$output_file" || {
    rm -f -- "$names_file"
    return 1
  }
  chmod 0600 "$output_file" || {
    rm -f -- "$names_file"
    return 1
  }
  while IFS= read -r -d '' name; do
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
      rm -f -- "$names_file"
      return 1
    }
    path="${directory}/${name}"
    [[ -f "$path" && ! -L "$path" ]] || {
      rm -f -- "$names_file"
      return 1
    }
    identity="$(stat -c '%F:%d:%i:%s:%f' -- "$path")" || {
      rm -f -- "$names_file"
      return 1
    }
    [[ "$identity" == 'regular file:'* ]] || {
      rm -f -- "$names_file"
      return 1
    }
    printf '%s\0%s\0' "$name" "${identity#regular file:}" >> "$output_file" || {
      rm -f -- "$names_file"
      return 1
    }
  done < "$names_file"
  rm -f -- "$names_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: classify_vendor_outputs
#   Requires one coherent four-file Bench backup result.
#   Ærguments:
#     $1 - stæging directory
#     $2 - output directory for shell væriæble æssignments
#ææææææææææææææææææææææææææææææææææ
classify_vendor_outputs() {
  local directory="$1"
  local output_file="$2"
  local inventory_file path name
  local database='' public_files='' private_files='' site_config=''
  local database_prefix='' public_prefix='' private_prefix='' config_prefix=''
  local count=0

  inventory_file="$(mktemp /tmp/erpnext-site-vendor-inventory.XXXXXX)" || return 1
  chmod 0600 "$inventory_file" || return 1
  if ! find -P "$directory" -mindepth 1 -maxdepth 1 -print0 > "$inventory_file"; then
    rm -f -- "$inventory_file"
    return 1
  fi
  while IFS= read -r -d '' path; do
    (( count += 1 ))
    [[ -f "$path" && ! -L "$path" ]] || {
      rm -f -- "$inventory_file"
      return 1
    }
    name="${path##*/}"
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
      rm -f -- "$inventory_file"
      return 1
    }
    case "$name" in
      *-private-files.tgz)
        [[ -z "$private_files" ]] || return 1
        private_files="$name"
        private_prefix="${name%-private-files.tgz}"
        ;;
      *-files.tgz)
        [[ -z "$public_files" ]] || return 1
        public_files="$name"
        public_prefix="${name%-files.tgz}"
        ;;
      *-database.sql.gz)
        [[ "$name" != *-partial-database.sql.gz && -z "$database" ]] || return 1
        database="$name"
        database_prefix="${name%-database.sql.gz}"
        ;;
      *-site_config_backup.json)
        [[ -z "$site_config" ]] || return 1
        site_config="$name"
        config_prefix="${name%-site_config_backup.json}"
        ;;
      *)
        rm -f -- "$inventory_file"
        return 1
        ;;
    esac
  done < "$inventory_file"
  rm -f -- "$inventory_file"

  [[ "$count" -eq 4 && -n "$database" && -n "$public_files" && -n "$private_files" && -n "$site_config" ]] || return 1
  [[ "$database_prefix" == "$public_prefix" && "$database_prefix" == "$private_prefix" && "$database_prefix" == "$config_prefix" ]] || return 1
  [[ "$database_prefix" =~ ^[0-9]{8}_[0-9]{6}-[A-Za-z0-9_-]+$ ]] || return 1

  {
    printf 'DATABASE_FILE=%q\n' "$database"
    printf 'PUBLIC_FILES_FILE=%q\n' "$public_files"
    printf 'PRIVATE_FILES_FILE=%q\n' "$private_files"
    printf 'SITE_CONFIG_FILE=%q\n' "$site_config"
  } > "$output_file"
  chmod 0600 "$output_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_checksum_sidecar
#   Writes one canonical SHÆ256 sidecær for æ regulær ærtefæct.
#   Ærguments:
#     $1 - ærtefæct pæth
#ææææææææææææææææææææææææææææææææææ
write_checksum_sidecar() {
  local artifact="$1"
  local name="${artifact##*/}"
  local digest_line digest

  digest_line="$(sha256sum -- "$artifact")" || return 1
  digest="${digest_line%% *}"
  [[ "$digest" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s  %s\n' "$digest" "$name" > "${artifact}.sha256" || return 1
  chmod 0600 "$artifact" "${artifact}.sha256"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: checksum_for
#   Returns the canonical digest from one previously written sidecær.
#   Ærguments:
#     $1 - ærtefæct pæth
#ææææææææææææææææææææææææææææææææææ
checksum_for() {
  local artifact="$1"
  local line digest expected

  IFS= read -r line < "${artifact}.sha256" || return 1
  digest="${line%% *}"
  expected="${digest}  ${artifact##*/}"
  [[ "$line" == "$expected" && "$digest" =~ ^[a-f0-9]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_success_marker
#   Ætomicælly replæces the numeric successful-bæckup heælth mærker.
#ææææææææææææææææææææææææææææææææææ
publish_success_marker() {
  local marker_stage now

  now="$(date +%s)" || return 1
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  marker_stage="$(mktemp "${BACKUP_DIR}/.erpnext-site-marker.XXXXXX")" || return 1
  printf '%s\n' "$now" > "$marker_stage" || return 1
  chmod 0600 "$marker_stage" || return 1
  sync -f "$marker_stage" || return 1
  mv -Tf -- "$marker_stage" "$SUCCESS_MARKER" || return 1
  sync -d "$BACKUP_DIR" || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_retention
#   Removes only strict expired bundles ænd ælwæys preserves the new bundle.
#   Ærguments:
#     $1 - newly published bundle identifier
#ææææææææææææææææææææææææææææææææææ
apply_retention() {
  local newest_bundle="$1"
  local retention_days="${ERPNEXT_SITE_BACKUP_RETENTION_DAYS:-7}"
  local retention_minutes=$(( retention_days * 1440 ))
  local candidates_file candidate name identity resolved

  candidates_file="$(mktemp /tmp/erpnext-site-retention.XXXXXX)" || return 1
  chmod 0600 "$candidates_file" || return 1
  if ! find -P "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mmin "+${retention_minutes}" -name 'erpnext-????????T??????Z' -print0 > "$candidates_file"; then
    rm -f -- "$candidates_file"
    return 1
  fi
  while IFS= read -r -d '' candidate; do
    name="${candidate##*/}"
    [[ "$name" =~ ^erpnext-[0-9]{8}T[0-9]{6}Z$ ]] || continue
    [[ "$name" != "$newest_bundle" ]] || continue
    [[ -d "$candidate" && ! -L "$candidate" ]] || return 1
    resolved="$(realpath -e -- "$candidate")" || return 1
    [[ "$resolved" == "$candidate" ]] || return 1
    identity="$(stage_identity "$candidate")" || return 1
    remove_proven_tree "$candidate" "$identity" || return 1
    log_info "Expired bundle removed: ${name}"
  done < "$candidates_file"
  rm -f -- "$candidates_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_backup_locked
#   Creætes, vælidætes, ænd ætomicælly publishes one coherent site bundle.
#ææææææææææææææææææææææææææææææææææ
run_backup_locked() {
  local bundle_id created_at published_bundle
  local classification_file inventory_before
  local database_path public_path private_path config_path
  local database_digest public_digest private_digest config_digest manifest_digest

  mkdir -p -- "$STAGING_ROOT"
  [[ -d "$STAGING_ROOT" && ! -L "$STAGING_ROOT" ]] || log_fatal 'Private staging root is not a regular directory.'
  chmod 0700 "$STAGING_ROOT"
  [[ "$(realpath -e -- "$STAGING_ROOT")" == "$STAGING_ROOT" ]] || log_fatal 'Private staging root identity is unexpected.'

  bundle_id="erpnext-$(date -u +%Y%m%dT%H%M%SZ)" || log_fatal 'Unable to derive the deterministic bundle identifier.'
  [[ "$bundle_id" =~ ^erpnext-[0-9]{8}T[0-9]{6}Z$ ]] || log_fatal 'Derived bundle identifier is invalid.'
  published_bundle="${BACKUP_DIR}/${bundle_id}"
  [[ ! -e "$published_bundle" && ! -L "$published_bundle" ]] || log_fatal 'Bundle identifier already exists; refusing to clobber it.'

  OWNED_STAGE="$(mktemp -d "${STAGING_ROOT}/.erpnext-site-stage.XXXXXX")" || log_fatal 'Unable to create private same-filesystem staging.'
  chmod 0700 "$OWNED_STAGE"
  OWNED_STAGE_ID="$(stage_identity "$OWNED_STAGE")" || log_fatal 'Unable to pin private staging identity.'
  trap cleanup_owned_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  log_info 'Starting vendor-supported ERPNext database, configuration, public-file, and private-file backup.'
  cd "$BENCH_DIR"
  bench --site "${ERPNEXT_SITE_NAME}" backup --with-files --compress --backup-path "$OWNED_STAGE"

  classification_file="$(mktemp /tmp/erpnext-site-classification.XXXXXX)" || log_fatal 'Unable to create private classification state.'
  chmod 0600 "$classification_file"
  classify_vendor_outputs "$OWNED_STAGE" "$classification_file" || log_fatal 'Bench output is missing, ambiguous, unsafe, partial, or not one coherent compressed run.'
  # shellcheck disable=SC1090
  source "$classification_file"
  rm -f -- "$classification_file"

  database_path="${OWNED_STAGE}/${DATABASE_FILE}"
  public_path="${OWNED_STAGE}/${PUBLIC_FILES_FILE}"
  private_path="${OWNED_STAGE}/${PRIVATE_FILES_FILE}"
  config_path="${OWNED_STAGE}/${SITE_CONFIG_FILE}"
  "$BENCH_PYTHON" "$RESTORE_HELPER" verify-artifacts \
    --site "${ERPNEXT_SITE_NAME}" \
    --database "$database_path" \
    --public-files "$public_path" \
    --private-files "$private_path" \
    --site-config "$config_path"

  write_checksum_sidecar "$database_path" || log_fatal 'Unable to create the database checksum sidecar.'
  write_checksum_sidecar "$config_path" || log_fatal 'Unable to create the site-configuration checksum sidecar.'
  write_checksum_sidecar "$public_path" || log_fatal 'Unable to create the public-files checksum sidecar.'
  write_checksum_sidecar "$private_path" || log_fatal 'Unable to create the private-files checksum sidecar.'
  database_digest="$(checksum_for "$database_path")" || log_fatal 'Database checksum sidecar is malformed.'
  config_digest="$(checksum_for "$config_path")" || log_fatal 'Site-configuration checksum sidecar is malformed.'
  public_digest="$(checksum_for "$public_path")" || log_fatal 'Public-files checksum sidecar is malformed.'
  private_digest="$(checksum_for "$private_path")" || log_fatal 'Private-files checksum sidecar is malformed.'
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || log_fatal 'Unable to create the manifest timestamp.'

  {
    printf 'FORMAT=erpnext-site-bundle-v1\n'
    printf 'BUNDLE_ID=%s\n' "$bundle_id"
    printf 'SITE=%s\n' "${ERPNEXT_SITE_NAME}"
    printf 'CREATED_AT_UTC=%s\n' "$created_at"
    printf 'DATABASE_FILE=%s\n' "$DATABASE_FILE"
    printf 'DATABASE_SHA256=%s\n' "$database_digest"
    printf 'SITE_CONFIG_FILE=%s\n' "$SITE_CONFIG_FILE"
    printf 'SITE_CONFIG_SHA256=%s\n' "$config_digest"
    printf 'PUBLIC_FILES_FILE=%s\n' "$PUBLIC_FILES_FILE"
    printf 'PUBLIC_FILES_SHA256=%s\n' "$public_digest"
    printf 'PRIVATE_FILES_FILE=%s\n' "$PRIVATE_FILES_FILE"
    printf 'PRIVATE_FILES_SHA256=%s\n' "$private_digest"
  } > "${OWNED_STAGE}/${MANIFEST_NAME}"
  chmod 0600 "${OWNED_STAGE}/${MANIFEST_NAME}"
  manifest_digest="$(sha256sum -- "${OWNED_STAGE}/${MANIFEST_NAME}")" || log_fatal 'Unable to checksum the strict bundle manifest.'
  manifest_digest="${manifest_digest%% *}"
  [[ "$manifest_digest" =~ ^[a-f0-9]{64}$ ]] || log_fatal 'Bundle manifest digest is malformed.'
  printf '%s  %s\n' "$manifest_digest" "$MANIFEST_NAME" > "${OWNED_STAGE}/${MANIFEST_CHECKSUM_NAME}"
  chmod 0600 "${OWNED_STAGE}/${MANIFEST_CHECKSUM_NAME}"

  "$BENCH_PYTHON" "$RESTORE_HELPER" verify-bundle \
    --bundle "$OWNED_STAGE" --bundle-id "$bundle_id" --site "${ERPNEXT_SITE_NAME}"
  inventory_before="$(mktemp /tmp/erpnext-site-publish-inventory.XXXXXX)" || log_fatal 'Unable to allocate private publication identity state.'
  write_inventory_identity "$OWNED_STAGE" "$inventory_before" || log_fatal 'Unable to inventory the staged bundle with NUL delimiters.'
  "$BENCH_PYTHON" "$RESTORE_HELPER" publish \
    --source "$OWNED_STAGE" --destination "$published_bundle" \
    --bundle-id "$bundle_id" --site "${ERPNEXT_SITE_NAME}"
  rm -f -- "$inventory_before"
  OWNED_STAGE=''
  OWNED_STAGE_ID=''
  trap - EXIT HUP INT TERM

  apply_retention "$bundle_id" || log_fatal 'Retention failed after publication; success marker was not advanced.'
  publish_success_marker || log_fatal 'Bundle published but successful-backup marker could not be advanced.'
  log_ok "Published complete ERPNext site bundle: ${bundle_id}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_backup
#   Seriælizes one bounded bæckup on the verified bind-mount inode.
#ææææææææææææææææææææææææææææææææææ
run_backup() (
  local backup_lock_fd

  validate_runtime
  exec {backup_lock_fd}< "$BACKUP_DIR"
  flock -n "$backup_lock_fd" || log_fatal 'Another ERPNext site maintenance operation is already running.'
  run_backup_locked
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_root_secret
#   Fæils closed on malformed MæriæDB root-secret input before restore.
#ææææææææææææææææææææææææææææææææææ
validate_root_secret() {
  local secret_size line_free_size

  [[ -f "$ROOT_SECRET" && ! -L "$ROOT_SECRET" && -r "$ROOT_SECRET" ]] \
    || log_fatal 'MariaDB root secret is missing, symbolic, or unreadable.'
  secret_size="$(wc -c < "$ROOT_SECRET")" || log_fatal 'Unable to size the MariaDB root secret.'
  (( secret_size >= MIN_SECRET_BYTES && secret_size <= MAX_SECRET_BYTES )) \
    || log_fatal 'MariaDB root secret must contain 12 through 4096 bytes.'
  if (( secret_size == 9 )) && [[ "$(cat "$ROOT_SECRET")" == 'CHANGE_ME' ]]; then
    log_fatal 'MariaDB root secret still contains the placeholder value.'
  fi
  line_free_size="$(LC_ALL=C tr -d '\n\r' < "$ROOT_SECRET" | wc -c)" || log_fatal 'Unable to validate MariaDB root-secret line structure.'
  (( line_free_size == secret_size )) || log_fatal 'MariaDB root secret contains line breaks.'
  if LC_ALL=C grep -q '[[:cntrl:]]' "$ROOT_SECRET"; then
    log_fatal 'MariaDB root secret contains control characters.'
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_application_secret
#   Fæils closed on mælformed current æpplicætion-secret input before restore.
#ææææææææææææææææææææææææææææææææææ
validate_application_secret() {
  local secret_size line_free_size

  [[ -f "$APPLICATION_SECRET" && ! -L "$APPLICATION_SECRET" && -r "$APPLICATION_SECRET" ]] \
    || log_fatal 'Current MariaDB application secret is missing, symbolic, or unreadable.'
  secret_size="$(wc -c < "$APPLICATION_SECRET")" || log_fatal 'Unable to size the current MariaDB application secret.'
  (( secret_size >= MIN_SECRET_BYTES && secret_size <= MAX_SECRET_BYTES )) \
    || log_fatal 'Current MariaDB application secret must contain 12 through 4096 bytes.'
  if (( secret_size == 9 )) && [[ "$(cat "$APPLICATION_SECRET")" == 'CHANGE_ME' ]]; then
    log_fatal 'Current MariaDB application secret still contains the placeholder value.'
  fi
  line_free_size="$(LC_ALL=C tr -d '\n\r' < "$APPLICATION_SECRET" | wc -c)" || log_fatal 'Unable to validate current MariaDB application-secret line structure.'
  (( line_free_size == secret_size )) || log_fatal 'Current MariaDB application secret contains line breaks.'
  if LC_ALL=C grep -q '[[:cntrl:]]' "$APPLICATION_SECRET"; then
    log_fatal 'Current MariaDB application secret contains control characters.'
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_restore
#   Performs no-op dry-run or guærded destructive vendor restore.
#ææææææææææææææææææææææææææææææææææ
run_restore() (
  local backup_lock_fd
  local bundle_id="${ERPNEXT_SITE_RESTORE_BUNDLE_ID:-}"
  local bundle_path before_identity after_identity

  validate_runtime
  [[ "$bundle_id" =~ ^erpnext-[0-9]{8}T[0-9]{6}Z$ ]] \
    || log_fatal 'Restore requires one explicit strict ERPNEXT_SITE_RESTORE_BUNDLE_ID.'
  bundle_path="${BACKUP_DIR}/${bundle_id}"
  [[ -d "$bundle_path" && ! -L "$bundle_path" ]] || log_fatal 'Selected restore bundle is missing or symbolic.'
  [[ "$(realpath -e -- "$bundle_path")" == "$bundle_path" ]] || log_fatal 'Selected restore bundle identity is unexpected.'

  exec {backup_lock_fd}< "$BACKUP_DIR"
  flock -n "$backup_lock_fd" || log_fatal 'Another ERPNext site maintenance operation is already running.'
  before_identity="$(mktemp /tmp/erpnext-site-restore-before.XXXXXX)" || log_fatal 'Unable to allocate private restore identity state.'
  after_identity="$(mktemp /tmp/erpnext-site-restore-after.XXXXXX)" || log_fatal 'Unable to allocate private restore recheck state.'
  write_inventory_identity "$bundle_path" "$before_identity" || log_fatal 'Unable to inventory the selected bundle with NUL delimiters.'
  "$BENCH_PYTHON" "$RESTORE_HELPER" verify-bundle \
    --bundle "$bundle_path" --bundle-id "$bundle_id" --site "${ERPNEXT_SITE_NAME}"

  if [[ "${ERPNEXT_SITE_RESTORE_DRY_RUN:-true}" == 'true' ]]; then
    write_inventory_identity "$bundle_path" "$after_identity" || log_fatal 'Unable to re-inventory the dry-run bundle.'
    cmp -s -- "$before_identity" "$after_identity" || log_fatal 'Bundle identity changed during restore dry-run.'
    rm -f -- "$before_identity" "$after_identity"
    log_ok "Dry-run completed without site, database, bundle, or success-marker mutation: ${bundle_id}"
    exit 0
  fi

  [[ "${ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED:-false}" == 'true' ]] \
    || log_fatal 'Real restore requires explicit confirmation that every documented writer is stopped.'
  [[ "${ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT:-false}" == 'true' ]] \
    || log_fatal 'Real restore requires independent confirmation that current site data may be replaced.'
  validate_root_secret
  validate_application_secret
  write_inventory_identity "$bundle_path" "$after_identity" || log_fatal 'Unable to re-inventory the bundle before apply.'
  cmp -s -- "$before_identity" "$after_identity" || log_fatal 'Bundle identity changed after validation; refusing restore.'
  rm -f -- "$before_identity" "$after_identity"

  log_warn 'Beginning destructive vendor restore after both explicit operator guards.'
  "$BENCH_PYTHON" "$RESTORE_HELPER" restore \
    --bundle "$bundle_path" --bundle-id "$bundle_id" \
    --site "${ERPNEXT_SITE_NAME}" --secret-file "$ROOT_SECRET" \
    --application-secret-file "$APPLICATION_SECRET"
  log_ok "ERPNext site restore completed from immutable bundle: ${bundle_id}"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: render_runtime_cron
#   Renders the vælidæted schedule into æ locked unique /run cron file.
#ææææææææææææææææææææææææææææææææææ
render_runtime_cron() {
  local schedule="${ERPNEXT_SITE_BACKUP_SCHEDULE:-0 2 * * *}"
  local template_line

  validate_schedule "$schedule"
  [[ -f "$CRON_TEMPLATE" && ! -L "$CRON_TEMPLATE" && -r "$CRON_TEMPLATE" ]] \
    || log_fatal 'ERPNext site backup cron template is missing, symbolic, or unreadable.'
  template_line="$(tail -n 1 -- "$CRON_TEMPLATE")" || log_fatal 'Unable to read the cron template.'
  [[ "$template_line" == '@ERPNEXT_SITE_BACKUP_SCHEDULE@ /usr/local/bin/erpnext-site-maintenance.sh backup' ]] \
    || log_fatal 'ERPNext site backup cron template contract has drifted.'
  printf '%s %s\n' "$schedule" '/usr/local/bin/erpnext-site-maintenance.sh backup' > "$RUNTIME_CRON"
  chmod 0600 "$RUNTIME_CRON"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_schedule
#   Produces one initiæl bundle, then execs Supercronic for the dæily schedule.
#ææææææææææææææææææææææææææææææææææ
run_schedule() {
  require_command supercronic
  validate_schedule "${ERPNEXT_SITE_BACKUP_SCHEDULE:-0 2 * * *}"
  render_runtime_cron
  supercronic -test "$RUNTIME_CRON" || log_fatal 'Supercronic rejected the rendered backup schedule; no initial backup was started.'
  log_info 'Creating the synchronous initial bundle before scheduler startup.'
  # Keep this æs æ simple commænd. Cælling the function in æn `||` or `!`
  # condition disæbles Bæsh errexit within its compound body ænd could let æ
  # fæiled bundle vælidætion ædvænce the success mærker.
  run_backup
  log_ok 'Initial bundle is healthy; starting Supercronic with the locked runtime schedule.'
  exec supercronic "$RUNTIME_CRON"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
[[ "$#" -eq 1 ]] || log_fatal 'Exactly one mode is required: schedule, backup, or restore.'
case "$1" in
  schedule)
    run_schedule
    ;;
  backup)
    run_backup
    ;;
  restore)
    run_restore
    ;;
  *)
    log_fatal 'Unsupported mode; expected schedule, backup, or restore.'
    ;;
esac
