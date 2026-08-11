#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENVIRONMENT VÆRIÆBLES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
MARIADB_ROOT_USER="${MARIADB_ROOT_USER:-root}"
MARIADB_DATABASE="${MARIADB_DATABASE:?MARIADB_DATABASE is required}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:?MARIADB_ROOT_PASSWORD_FILE is required}"
MARIADB_DB_HOST="${MARIADB_DB_HOST:-mariadb}"
MARIADB_BACKUP_RETENTION_DAYS="${MARIADB_BACKUP_RETENTION_DAYS:-7}"

BACKUP_DIR="${MARIADB_BACKUP_DIR:-/backup}"
TMP_PARENT="${BACKUP_DIR}/.tmp"
TMP_DIR=""
TODAY="${MARIADB_BACKUP_DATE:-$(date +'%Y%m%d')}"
DEBUG="${MARIADB_BACKUP_DEBUG:-false}"
DRY_RUN="${DRY_RUN:-false}"
MAINTENANCE_LOCK_DIR="/backup"
TMP_CREATED=false
TMP_PARENT_CREATED=false
TMP_IDENTITY=""
TMP_PARENT_IDENTITY=""
CREATED_ARCHIVE=""
BACKUP_IDENTITY=""
CANONICAL_TMP_PARENT=""
SECURE_TEMP_FILE=""
SECURE_TEMP_IDENTITY=""
VALIDATED_CHAIN_PREDECESSOR=""
ACTIVE_CHILD_PID=""
MARIADB_CLIENT_OPTION_ROOT="/tmp"
MARIADB_CLIENT_OPTION_ROOT_IDENTITY=""
MARIADB_CLIENT_OPTION_DIR=""
MARIADB_CLIENT_OPTION_DIR_IDENTITY=""
MARIADB_CLIENT_OPTION_FILE=""
MARIADB_CLIENT_OPTION_FILE_INODE=""
MARIADB_CLIENT_OPTION_FILE_IDENTITY=""
MARIADB_CLIENT_OPTION_FILE_DIGEST=""
MARIADB_CLIENT_OPTION_ARGUMENT=""
MARIADB_CLIENT_OPTION_ACTIVE=false
PUBLISHED_BUNDLE_FILES=()
PUBLISHED_BUNDLE_IDENTITIES=()
BUNDLE_PUBLICATION_COMMITTED=true
PHYSICAL_FULL_CANDIDATES=()
readonly SUCCESS_FILE="/backup/.mariadb-maintenance-last-success"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
log_info() {
  printf '[INFO] %s\n' "$*"
}

log_ok() {
  printf '[OK] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    printf '[DEBUG] %s\n' "$*"
  fi
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

log_fatal() {
  printf '[FATAL] %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: usage
#   Prints supported bæckup modes ænd stændærd flægs
#ææææææææææææææææææææææææææææææææææ
usage() {
  cat <<'EOF'
Usage: backup.sh [full|incremental|dump] [--debug] [--dry-run]

The default backup mode is "full".
  full         Physical full database backup
  incremental  Physical backup based on the immediate predecessor
  dump         Raw logical SQL database dump
EOF
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_work_dir
#   Vælidætes thæt æ work pæth is not broæd enough to remove user dætæ
#   Ærguments:
#     $1 - work directory pæth
#ææææææææææææææææææææææææææææææææææ
is_safe_work_dir() {
  local path="$1"
  local canonical_path=""
  local current_identity=""
  local current_parent_identity=""

  case "$path" in
    ""|"/"|"/tmp"|"/tmp/"|"$BACKUP_DIR"|"$BACKUP_DIR/"|"$TMP_PARENT"|"$TMP_PARENT/")
      return 1
      ;;
    "$TMP_PARENT"/mariadb_backup.*)
      ;;
    *)
      return 1
      ;;
  esac
  [[ -d "$path" && ! -L "$path" ]] || return 1
  [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || return 1
  current_parent_identity=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || return 1
  [[ -n "$TMP_PARENT_IDENTITY" && "$current_parent_identity" == "$TMP_PARENT_IDENTITY" ]] || return 1
  canonical_path=$(realpath -e -- "$path") || return 1
  case "$canonical_path" in
    "$CANONICAL_TMP_PARENT"/mariadb_backup.*)
      [[ -n "${canonical_path#"$CANONICAL_TMP_PARENT"/mariadb_backup.}" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  current_identity=$(stat -Lc '%d:%i' -- "$path") || return 1
  [[ -n "$TMP_IDENTITY" && "$current_identity" == "$TMP_IDENTITY" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_backup_dir
#   Requires the dedicæted `/backup` mount to keep its vælidæted identity
#ææææææææææææææææææææææææææææææææææ
is_safe_backup_dir() {
  local current_identity=""
  [[ "$BACKUP_DIR" == "/backup" ]] || return 1
  [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || return 1
  [[ "$(realpath -e -- "$BACKUP_DIR")" == "/backup" ]] || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$BACKUP_DIR") || return 1
  [[ -z "$BACKUP_IDENTITY" || "$current_identity" == "$BACKUP_IDENTITY" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_configuration
#   Fæils fæst for unsafe pæths or unsupported booleæn vælues
#ææææææææææææææææææææææææææææææææææ
validate_configuration() {
  local protected_path=""
  local protected_identity=""
  local restore_identity=""
  local data_identity=""
  local required_command=""

  for required_command in chmod find findmnt flock grep id mariadb-backup mariadb-dump mktemp mv realpath sha256sum setsid stat sync tar wc zstd; do
    command -v "$required_command" >/dev/null 2>&1 || log_fatal "Required command is unavailable: $required_command"
  done
  [[ -f "$MARIADB_ROOT_PASSWORD_FILE" && ! -L "$MARIADB_ROOT_PASSWORD_FILE" ]] || log_fatal "MariaDB root password file must be a regular non-symlink file"

  [[ "$BACKUP_DIR" == "/backup" ]] || log_fatal "Backup directory must be the dedicated /backup mount"
  [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" ]] || log_fatal "Backup directory must be a regular directory"
  [[ "$(realpath -e -- "$BACKUP_DIR")" == "/backup" ]] || log_fatal "Backup directory contains a symlink or non-canonical component"
  BACKUP_IDENTITY=$(stat -Lc '%d:%i' -- "$BACKUP_DIR") || log_fatal "Cannot inspect backup directory"
  is_safe_backup_dir || log_fatal "Backup directory identity changed during validation"
  for protected_path in "/restore" "/var/lib/mysql"; do
    [[ -d "$protected_path" && ! -L "$protected_path" ]] || log_fatal "Required protected mount is unavailable or unsafe: $protected_path"
    [[ "$(realpath -e -- "$protected_path")" == "$protected_path" ]] || log_fatal "Protected mount contains a symlink or non-canonical component: $protected_path"
    protected_identity=$(stat -Lc '%d:%i' -- "$protected_path") || log_fatal "Cannot inspect protected mount: $protected_path"
    [[ "$BACKUP_IDENTITY" != "$protected_identity" ]] || log_fatal "Backup mount aliases protected path: $protected_path"
    if [[ "$protected_path" == "/restore" ]]; then
      restore_identity="$protected_identity"
    else
      data_identity="$protected_identity"
    fi
  done
  [[ "$restore_identity" != "$data_identity" ]] || log_fatal "Restore and MariaDB data mounts must have different identities"

  CANONICAL_TMP_PARENT=$(realpath -m -- "$TMP_PARENT") || log_fatal "Cannot resolve backup workspace parent"
  [[ "$CANONICAL_TMP_PARENT" == "/backup/.tmp" ]] || log_fatal "Backup workspace parent escaped /backup"
  if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
    [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Backup workspace parent must be a regular directory"
    [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Backup workspace parent changed during validation"
    TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect backup workspace parent"
  fi
  [[ "$TODAY" =~ ^[0-9]{8}$ ]] || log_fatal "MARIADB_BACKUP_DATE must use YYYYMMDD format"
  [[ "$MARIADB_BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ ]] || log_fatal "MARIADB_BACKUP_RETENTION_DAYS must be a non-negative integer"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only this process' temporæry workspæce
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  trap - INT TERM
  local index=0
  local current_identity=""
  local workspace_mounts=()

  if ! remove_mariadb_client_option_file; then
    log_error "Cannot safely remove the private MariaDB client option file; preserving it for inspection"
    return 1
  fi

  if [[ "$BUNDLE_PUBLICATION_COMMITTED" != "true" && ${#PUBLISHED_BUNDLE_FILES[@]} -gt 0 ]]; then
    index=$((${#PUBLISHED_BUNDLE_FILES[@]} - 1))
    while (( index >= 0 )); do
      if [[ -f "${PUBLISHED_BUNDLE_FILES[$index]}" && ! -L "${PUBLISHED_BUNDLE_FILES[$index]}" ]]; then
        current_identity=$(stat -Lc '%d:%i' -- "${PUBLISHED_BUNDLE_FILES[$index]}" 2>/dev/null || true)
        if [[ "$current_identity" == "${PUBLISHED_BUNDLE_IDENTITIES[$index]}" ]]; then
          rm -f -- "${PUBLISHED_BUNDLE_FILES[$index]}" || log_error "Cannot roll back incomplete bundle artifact: ${PUBLISHED_BUNDLE_FILES[$index]}"
        else
          log_error "Refusing to remove changed incomplete bundle artifact: ${PUBLISHED_BUNDLE_FILES[$index]}"
        fi
      elif [[ -e "${PUBLISHED_BUNDLE_FILES[$index]}" || -L "${PUBLISHED_BUNDLE_FILES[$index]}" ]]; then
        log_error "Refusing to remove unsafe incomplete bundle artifact: ${PUBLISHED_BUNDLE_FILES[$index]}"
      fi
      index=$((index - 1))
    done
  fi
  exec 7>&- 2>/dev/null || true
  if [[ -n "$SECURE_TEMP_FILE" ]]; then
    rm -f -- "$SECURE_TEMP_FILE"
  fi
  if [[ "$TMP_CREATED" == "true" ]] && is_safe_work_dir "$TMP_DIR"; then
    if ! capture_mount_inventory workspace_mounts "$TMP_DIR"; then
      log_error "Cannot inspect backup-workspace mounts; preserving it: $TMP_DIR"
      return
    fi
    if (( ${#workspace_mounts[@]} > 0 )); then
      log_error "Backup workspace contains a mount; preserving it: $TMP_DIR"
      return
    fi
    find "$TMP_DIR" -xdev -depth -mindepth 1 -delete || {
      log_error "Cannot remove backup workspace without crossing filesystems: $TMP_DIR"
      return
    }
    rmdir -- "$TMP_DIR" || {
      log_error "Backup workspace is not empty; preserving it: $TMP_DIR"
      return
    }
    if [[ "$TMP_PARENT_CREATED" == "true" ]]; then
      rmdir -- "$TMP_PARENT" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_signal
#   Terminætes ænd reæps the complete æctive tool process group
#ææææææææææææææææææææææææææææææææææ
handle_signal() {
  local exit_code="$1"
  trap - INT TERM
  if [[ -n "$ACTIVE_CHILD_PID" ]] && kill -0 "$ACTIVE_CHILD_PID" 2>/dev/null; then
    kill -s TERM -- "-$ACTIVE_CHILD_PID" 2>/dev/null || kill -s TERM "$ACTIVE_CHILD_PID" 2>/dev/null || true
    wait "$ACTIVE_CHILD_PID" 2>/dev/null || true
  fi
  ACTIVE_CHILD_PID=""
  exit "$exit_code"
}
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_backup_child
#   Runs one long tool in its own session for deterministic signæl forwarding
#ææææææææææææææææææææææææææææææææææ
run_backup_child() {
  local status=0
  setsid --wait -- "$@" &
  ACTIVE_CHILD_PID=$!
  wait "$ACTIVE_CHILD_PID" || status=$?
  ACTIVE_CHILD_PID=""
  return "$status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_backup_inventory
#   Cæptures NUL-delimited `find` output ænd explicitly checks find/sort stætus
#   Ærguments:
#     $1 - output ærræy næme
#     $2 - sort mode (`none`, `version`, or `version-reverse`)
#     $@ - find pæth ænd predicates, without `-print0`
#ææææææææææææææææææææææææææææææææææ
capture_backup_inventory() {
  local -n output_array="$1"
  local sort_mode="$2"
  local inventory_fd=""
  local inventory_pid=""
  local status=0
  shift 2
  output_array=()

  coproc MARIADB_BACKUP_INVENTORY {
    case "$sort_mode" in
      none)
        find "$@" -print0
        ;;
      version)
        set -o pipefail
        find "$@" -print0 | sort -z -V
        ;;
      version-reverse)
        set -o pipefail
        find "$@" -print0 | sort -z -Vr
        ;;
      *)
        exit 97
        ;;
    esac
  }
  inventory_fd="${MARIADB_BACKUP_INVENTORY[0]}"
  inventory_pid="$MARIADB_BACKUP_INVENTORY_PID"
  mapfile -d '' -t output_array <&"$inventory_fd" || status=$?
  exec {inventory_fd}<&-
  if ! wait "$inventory_pid"; then
    status=1
  fi
  unset MARIADB_BACKUP_INVENTORY MARIADB_BACKUP_INVENTORY_PID 2>/dev/null || true
  (( status == 0 )) || log_fatal "Failed to capture a complete MariaDB backup filesystem inventory"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_mount_inventory
#   Distinguishes `findmnt`'s no-mætch stætus from reæl inventory errors
#   Ærguments:
#     $1 - output ærræy næme
#     $2 - directory to inspect recursively
#ææææææææææææææææææææææææææææææææææ
capture_mount_inventory() {
  local -n output_array="$1"
  local path="$2"
  local output=""
  local status=0
  output_array=()
  output=$(findmnt -rn -o TARGET -R -- "$path" 2>/dev/null) || status=$?
  if (( status != 0 )); then
    [[ "$status" == "1" && -z "$output" ]] || return 1
    return 0
  fi
  [[ -n "$output" ]] && mapfile -t output_array <<<"$output"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_mariadb_client_option_file
#   Bridges the root secret through one inode-pinned privæte client file
#ææææææææææææææææææææææææææææææææææ
create_mariadb_client_option_file() {
  local password=""
  local escaped_password=""
  local root_canonical=""
  local directory_device=""
  local file_digest=""
  local secret_digest=""
  local current_secret_digest=""
  local secret_identity=""
  local current_secret_identity=""
  local secret_size=""
  local newline_count=""
  local grep_status=0
  local inventory=""
  local opened_inode=""
  local current_inode=""
  local expected_uid=""
  local expected_gid=""
  local descriptor_path="/proc/${BASHPID}/fd/8"

  [[ "$MARIADB_CLIENT_OPTION_ACTIVE" == "false" ]] || log_fatal "MariaDB client option file is already active"
  [[ -d "$MARIADB_CLIENT_OPTION_ROOT" && ! -L "$MARIADB_CLIENT_OPTION_ROOT" ]] || log_fatal "MariaDB client option root must be a real directory"
  root_canonical=$(realpath -e -- "$MARIADB_CLIENT_OPTION_ROOT") || log_fatal "Cannot resolve MariaDB client option root"
  [[ "$root_canonical" == "$MARIADB_CLIENT_OPTION_ROOT" ]] || log_fatal "MariaDB client option root is not canonical"
  MARIADB_CLIENT_OPTION_ROOT_IDENTITY=$(stat -Lc '%d:%i:%u:%g' -- "$MARIADB_CLIENT_OPTION_ROOT") || log_fatal "Cannot inspect MariaDB client option root"
  expected_uid=$(id -u) || log_fatal "Cannot determine MariaDB maintenance UID"
  expected_gid=$(id -g) || log_fatal "Cannot determine MariaDB maintenance GID"

  [[ -r "$MARIADB_ROOT_PASSWORD_FILE" && -f "$MARIADB_ROOT_PASSWORD_FILE" && ! -L "$MARIADB_ROOT_PASSWORD_FILE" ]] || log_fatal "MariaDB root password secret must be a readable regular non-symlink file"
  secret_identity=$(stat -Lc '%d:%i:%s:%u:%g:%a' -- "$MARIADB_ROOT_PASSWORD_FILE") || log_fatal "Cannot inspect MariaDB root password secret"
  secret_size=$(stat -Lc '%s' -- "$MARIADB_ROOT_PASSWORD_FILE") || log_fatal "Cannot inspect MariaDB root password secret size"
  [[ "$secret_size" =~ ^[0-9]+$ ]] && (( secret_size > 0 && secret_size <= 4096 )) || log_fatal "MariaDB root password secret must contain 1-4096 bytes"
  newline_count=$(LC_ALL=C wc -l < "$MARIADB_ROOT_PASSWORD_FILE") || log_fatal "Cannot inspect MariaDB root password secret line count"
  [[ "$newline_count" =~ ^[[:space:]]*0[[:space:]]*$ ]] || log_fatal "MariaDB root password secret must not contain line breaks"
  if LC_ALL=C grep -q '[[:cntrl:]]' "$MARIADB_ROOT_PASSWORD_FILE"; then
    log_fatal "MariaDB root password secret must not contain control characters"
  else
    grep_status=$?
    (( grep_status == 1 )) || log_fatal "Cannot validate MariaDB root password secret bytes"
  fi
  secret_digest=$(sha256sum -- "$MARIADB_ROOT_PASSWORD_FILE") || log_fatal "Cannot checksum MariaDB root password secret"
  secret_digest="${secret_digest%% *}"
  password=$(<"$MARIADB_ROOT_PASSWORD_FILE")
  current_secret_identity=$(stat -Lc '%d:%i:%s:%u:%g:%a' -- "$MARIADB_ROOT_PASSWORD_FILE") || log_fatal "Cannot re-inspect MariaDB root password secret"
  current_secret_digest=$(sha256sum -- "$MARIADB_ROOT_PASSWORD_FILE") || log_fatal "Cannot re-checksum MariaDB root password secret"
  current_secret_digest="${current_secret_digest%% *}"
  [[ "$current_secret_identity" == "$secret_identity" && "$current_secret_digest" == "$secret_digest" ]] || log_fatal "MariaDB root password secret changed while being read"
  [[ -n "$password" ]] || log_fatal "MariaDB root password secret is empty"

  MARIADB_CLIENT_OPTION_DIR=$(mktemp -d "$MARIADB_CLIENT_OPTION_ROOT/.mariadb-maintenance-client.XXXXXX") || log_fatal "Cannot create private MariaDB client option directory"
  MARIADB_CLIENT_OPTION_DIR_IDENTITY=$(stat -Lc '%d:%i:%a:%u:%g:%h' -- "$MARIADB_CLIENT_OPTION_DIR") || log_fatal "Cannot inspect new MariaDB client option directory"
  MARIADB_CLIENT_OPTION_ACTIVE=true
  chmod 0700 -- "$MARIADB_CLIENT_OPTION_DIR" || log_fatal "Cannot restrict MariaDB client option directory"
  [[ -d "$MARIADB_CLIENT_OPTION_DIR" && ! -L "$MARIADB_CLIENT_OPTION_DIR" ]] || log_fatal "MariaDB client option directory is unsafe"
  [[ "$(realpath -e -- "$MARIADB_CLIENT_OPTION_DIR")" == "$MARIADB_CLIENT_OPTION_DIR" ]] || log_fatal "MariaDB client option directory is not canonical"
  MARIADB_CLIENT_OPTION_DIR_IDENTITY=$(stat -Lc '%d:%i:%a:%u:%g:%h' -- "$MARIADB_CLIENT_OPTION_DIR") || log_fatal "Cannot inspect MariaDB client option directory"
  [[ "$MARIADB_CLIENT_OPTION_DIR_IDENTITY" == *":700:${expected_uid}:${expected_gid}:2" ]] || log_fatal "MariaDB client option directory metadata is not private"
  directory_device="${MARIADB_CLIENT_OPTION_DIR_IDENTITY%%:*}"

  MARIADB_CLIENT_OPTION_FILE=$(mktemp "$MARIADB_CLIENT_OPTION_DIR/client.cnf.XXXXXX") || log_fatal "Cannot create private MariaDB client option file"
  MARIADB_CLIENT_OPTION_FILE_INODE=$(stat -Lc '%d:%i' -- "$MARIADB_CLIENT_OPTION_FILE") || log_fatal "Cannot inspect new MariaDB client option file inode"
  chmod 0600 -- "$MARIADB_CLIENT_OPTION_FILE" || log_fatal "Cannot restrict MariaDB client option file"
  [[ -f "$MARIADB_CLIENT_OPTION_FILE" && ! -L "$MARIADB_CLIENT_OPTION_FILE" && "${MARIADB_CLIENT_OPTION_FILE%/*}" == "$MARIADB_CLIENT_OPTION_DIR" ]] || log_fatal "MariaDB client option file is unsafe"
  [[ "$(realpath -e -- "$MARIADB_CLIENT_OPTION_FILE")" == "$MARIADB_CLIENT_OPTION_FILE" ]] || log_fatal "MariaDB client option file is not canonical"
  exec 8<>"$MARIADB_CLIENT_OPTION_FILE" || log_fatal "Cannot open MariaDB client option file"
  opened_inode=$(stat -Lc '%d:%i' -- "$descriptor_path") || log_fatal "Cannot inspect MariaDB client option descriptor"
  current_inode=$(stat -Lc '%d:%i' -- "$MARIADB_CLIENT_OPTION_FILE") || log_fatal "Cannot re-inspect MariaDB client option path"
  [[ "$opened_inode" == "$MARIADB_CLIENT_OPTION_FILE_INODE" && "$current_inode" == "$MARIADB_CLIENT_OPTION_FILE_INODE" ]] || log_fatal "MariaDB client option file identity changed while opening"
  escaped_password="${password//\\/\\\\}"
  escaped_password="${escaped_password//\"/\\\"}"
  printf '[client]\npassword="%s"\n' "$escaped_password" >&8 || log_fatal "Cannot write MariaDB client option file"
  sync -f -- "$descriptor_path" || log_fatal "Cannot durably flush MariaDB client option file"
  MARIADB_CLIENT_OPTION_FILE_IDENTITY=$(stat -Lc '%d:%i:%s:%a:%u:%g:%h' -- "$descriptor_path") || log_fatal "Cannot inspect completed MariaDB client option file"
  [[ "$MARIADB_CLIENT_OPTION_FILE_IDENTITY" == "${directory_device}:"*":600:${expected_uid}:${expected_gid}:1" ]] || log_fatal "MariaDB client option file metadata is not private"
  file_digest=$(sha256sum -- "$descriptor_path") || log_fatal "Cannot checksum MariaDB client option file"
  MARIADB_CLIENT_OPTION_FILE_DIGEST="${file_digest%% *}"
  current_inode=$(stat -Lc '%d:%i' -- "$MARIADB_CLIENT_OPTION_FILE") || log_fatal "Cannot re-inspect completed MariaDB client option file"
  [[ "$current_inode" == "$MARIADB_CLIENT_OPTION_FILE_INODE" ]] || log_fatal "MariaDB client option path identity changed after writing"
  file_digest=$(sha256sum -- "$MARIADB_CLIENT_OPTION_FILE") || log_fatal "Cannot verify MariaDB client option path bytes"
  file_digest="${file_digest%% *}"
  [[ "$file_digest" == "$MARIADB_CLIENT_OPTION_FILE_DIGEST" ]] || log_fatal "MariaDB client option file bytes changed after writing"
  exec 8>&-
  inventory=$(find "$MARIADB_CLIENT_OPTION_DIR" -xdev -mindepth 1 -maxdepth 1 -printf '.') || log_fatal "Cannot inventory MariaDB client option directory"
  [[ "$inventory" == "." ]] || log_fatal "MariaDB client option directory inventory is not exact"
  MARIADB_CLIENT_OPTION_ARGUMENT="--defaults-extra-file=$MARIADB_CLIENT_OPTION_FILE"
  password=""
  escaped_password=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_mariadb_client_option_file
#   Removes only the proven option-file inode ænd its proven privæte directory
#ææææææææææææææææææææææææææææææææææ
remove_mariadb_client_option_file() {
  local current_identity=""
  local current_inode=""
  local opened_inode=""
  local current_digest=""
  local inventory=""
  local descriptor_path="/proc/${BASHPID}/fd/8"
  local option_inode_number=""

  [[ "$MARIADB_CLIENT_OPTION_ACTIVE" == "true" ]] || return 0
  { exec 8>&-; } 2>/dev/null || true
  [[ -d "$MARIADB_CLIENT_OPTION_ROOT" && ! -L "$MARIADB_CLIENT_OPTION_ROOT" ]] || return 1
  [[ "$(realpath -e -- "$MARIADB_CLIENT_OPTION_ROOT" 2>/dev/null)" == "$MARIADB_CLIENT_OPTION_ROOT" ]] || return 1
  current_identity=$(stat -Lc '%d:%i:%u:%g' -- "$MARIADB_CLIENT_OPTION_ROOT" 2>/dev/null) || return 1
  [[ "$current_identity" == "$MARIADB_CLIENT_OPTION_ROOT_IDENTITY" ]] || return 1
  [[ -d "$MARIADB_CLIENT_OPTION_DIR" && ! -L "$MARIADB_CLIENT_OPTION_DIR" ]] || return 1
  [[ "$(realpath -e -- "$MARIADB_CLIENT_OPTION_DIR" 2>/dev/null)" == "$MARIADB_CLIENT_OPTION_DIR" ]] || return 1
  current_identity=$(stat -Lc '%d:%i:%a:%u:%g:%h' -- "$MARIADB_CLIENT_OPTION_DIR" 2>/dev/null) || return 1
  [[ "$current_identity" == "$MARIADB_CLIENT_OPTION_DIR_IDENTITY" ]] || return 1

  if [[ -n "$MARIADB_CLIENT_OPTION_FILE" ]]; then
    [[ -n "$MARIADB_CLIENT_OPTION_FILE_INODE" && -f "$MARIADB_CLIENT_OPTION_FILE" && ! -L "$MARIADB_CLIENT_OPTION_FILE" && "${MARIADB_CLIENT_OPTION_FILE%/*}" == "$MARIADB_CLIENT_OPTION_DIR" ]] || return 1
    [[ "$(realpath -e -- "$MARIADB_CLIENT_OPTION_FILE" 2>/dev/null)" == "$MARIADB_CLIENT_OPTION_FILE" ]] || return 1
    inventory=$(find "$MARIADB_CLIENT_OPTION_DIR" -xdev -mindepth 1 -maxdepth 1 -printf '.' 2>/dev/null) || return 1
    [[ "$inventory" == "." ]] || return 1
    exec 8<>"$MARIADB_CLIENT_OPTION_FILE" || return 1
    opened_inode=$(stat -Lc '%d:%i' -- "$descriptor_path" 2>/dev/null) || { exec 8>&-; return 1; }
    current_inode=$(stat -Lc '%d:%i' -- "$MARIADB_CLIENT_OPTION_FILE" 2>/dev/null) || { exec 8>&-; return 1; }
    [[ "$opened_inode" == "$MARIADB_CLIENT_OPTION_FILE_INODE" && "$current_inode" == "$MARIADB_CLIENT_OPTION_FILE_INODE" ]] || { exec 8>&-; return 1; }
    option_inode_number="${MARIADB_CLIENT_OPTION_FILE_INODE#*:}"
    [[ "$option_inode_number" =~ ^[0-9]+$ ]] || { exec 8>&-; return 1; }
    if [[ -n "$MARIADB_CLIENT_OPTION_FILE_IDENTITY" ]]; then
      current_identity=$(stat -Lc '%d:%i:%s:%a:%u:%g:%h' -- "$descriptor_path" 2>/dev/null) || { exec 8>&-; return 1; }
      [[ "$current_identity" == "$MARIADB_CLIENT_OPTION_FILE_IDENTITY" ]] || { exec 8>&-; return 1; }
    fi
    if [[ -n "$MARIADB_CLIENT_OPTION_FILE_DIGEST" ]]; then
      current_digest=$(sha256sum -- "$descriptor_path" 2>/dev/null) || { exec 8>&-; return 1; }
      current_digest="${current_digest%% *}"
      [[ "$current_digest" == "$MARIADB_CLIENT_OPTION_FILE_DIGEST" ]] || { exec 8>&-; return 1; }
    fi
    find "$MARIADB_CLIENT_OPTION_DIR" -xdev -mindepth 1 -maxdepth 1 -type f -inum "$option_inode_number" -delete || { exec 8>&-; return 1; }
    [[ ! -e "$MARIADB_CLIENT_OPTION_FILE" && ! -L "$MARIADB_CLIENT_OPTION_FILE" ]] || { exec 8>&-; return 1; }
    [[ "$(stat -Lc '%h' -- "$descriptor_path" 2>/dev/null)" == "0" ]] || { exec 8>&-; return 1; }
    exec 8>&-
  fi

  inventory=$(find "$MARIADB_CLIENT_OPTION_DIR" -xdev -mindepth 1 -maxdepth 1 -printf '.' 2>/dev/null) || return 1
  [[ -z "$inventory" ]] || return 1
  current_identity=$(stat -Lc '%d:%i:%a:%u:%g:%h' -- "$MARIADB_CLIENT_OPTION_DIR" 2>/dev/null) || return 1
  [[ "$current_identity" == "$MARIADB_CLIENT_OPTION_DIR_IDENTITY" ]] || return 1
  rmdir -- "$MARIADB_CLIENT_OPTION_DIR" || return 1
  [[ ! -e "$MARIADB_CLIENT_OPTION_DIR" && ! -L "$MARIADB_CLIENT_OPTION_DIR" ]] || return 1
  MARIADB_CLIENT_OPTION_ROOT_IDENTITY=""
  MARIADB_CLIENT_OPTION_DIR=""
  MARIADB_CLIENT_OPTION_DIR_IDENTITY=""
  MARIADB_CLIENT_OPTION_FILE=""
  MARIADB_CLIENT_OPTION_FILE_INODE=""
  MARIADB_CLIENT_OPTION_FILE_IDENTITY=""
  MARIADB_CLIENT_OPTION_FILE_DIGEST=""
  MARIADB_CLIENT_OPTION_ARGUMENT=""
  MARIADB_CLIENT_OPTION_ACTIVE=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_maintenance_lock
#   Serializes bæckup ænd restore operætions æcross contæiners
#ææææææææææææææææææææææææææææææææææ
acquire_maintenance_lock() {
  local expected_identity=""
  local opened_identity=""
  local descriptor_path="/proc/self/fd/9"

  [[ -d "$MAINTENANCE_LOCK_DIR" ]] || log_fatal "Maintenance lock directory is unavailable: $MAINTENANCE_LOCK_DIR"
  [[ ! -L "$MAINTENANCE_LOCK_DIR" ]] || log_fatal "Maintenance lock directory must not be a symlink: $MAINTENANCE_LOCK_DIR"
  expected_identity=$(stat -Lc '%d:%i' -- "$MAINTENANCE_LOCK_DIR") || log_fatal "Cannot inspect maintenance lock directory"
  [[ "$expected_identity" == "$BACKUP_IDENTITY" ]] || log_fatal "Maintenance lock directory does not match the validated backup mount"
  exec 9<"$MAINTENANCE_LOCK_DIR" || log_fatal "Cannot open maintenance lock directory: $MAINTENANCE_LOCK_DIR"
  [[ -d "$descriptor_path" ]] || log_fatal "Maintenance lock descriptor is not a directory"
  opened_identity=$(stat -Lc '%d:%i' -- "$descriptor_path") || log_fatal "Cannot inspect maintenance lock descriptor"
  [[ "$opened_identity" == "$expected_identity" ]] || log_fatal "Maintenance lock directory changed while being opened"
  flock -n 9 || log_fatal "Another MariaDB maintenance operation is already running"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP HELPER FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_tmp_dir
#   Creætes this process' unique bæckup workspæce
#ææææææææææææææææææææææææææææææææææ
prepare_tmp_dir() {
  if [[ "$TMP_CREATED" == "false" ]]; then
    is_safe_backup_dir || log_fatal "Backup directory identity changed before workspace creation"
    if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
      [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Unsafe backup workspace parent"
    else
      mkdir -- "$TMP_PARENT" || log_fatal "Cannot create backup workspace parent"
      TMP_PARENT_CREATED=true
      TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect created backup workspace parent"
    fi
    [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Backup workspace parent changed before use"
    [[ "$(stat -Lc '%d:%i' -- "$TMP_PARENT")" == "$TMP_PARENT_IDENTITY" ]] || log_fatal "Backup workspace parent identity changed before use"
    TMP_DIR=$(mktemp -d "$TMP_PARENT/mariadb_backup.XXXXXX") || log_fatal "Cannot create unique backup workspace"
    TMP_CREATED=true
    chmod 0700 -- "$TMP_DIR" || log_fatal "Cannot restrict backup workspace"
    TMP_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_DIR") || log_fatal "Cannot inspect backup workspace"
    is_safe_work_dir "$TMP_DIR" || log_fatal "Unsafe backup workspace: $TMP_DIR"
    log_debug "Created $TMP_DIR"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_backup_day_dir
#   Creætes or vælidætes one direct YYYYMMDD child of `/backup`
#   Ærguments:
#     $1 - dæted bæckup directory
#ææææææææææææææææææææææææææææææææææ
ensure_backup_day_dir() {
  local directory="$1"
  local name="${directory##*/}"

  is_safe_backup_dir || log_fatal "Backup directory identity changed"
  [[ "${directory%/*}" == "/backup" && "$name" =~ ^[0-9]{8}$ ]] || log_fatal "Unsafe dated backup directory: $directory"
  if [[ -e "$directory" || -L "$directory" ]]; then
    [[ -d "$directory" && ! -L "$directory" ]] || log_fatal "Dated backup path must be a regular directory: $directory"
  else
    mkdir -- "$directory" || log_fatal "Cannot create dated backup directory: $directory"
  fi
  [[ "$(realpath -e -- "$directory")" == "$directory" ]] || log_fatal "Dated backup directory contains a symlink"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: open_secure_temp_file
#   Opens æ rændom O_EXCL temporæry file on descriptor 7 without truncætion
#   Ærguments:
#     $1 - finæl publicætion pæth
#ææææææææææææææææææææææææææææææææææ
open_secure_temp_file() {
  local destination="$1"
  local directory="${destination%/*}"
  local name="${destination##*/}"
  local opened_identity=""

  ensure_backup_day_dir "$directory"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || log_fatal "Unsafe backup artifact name: $name"
  [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Refusing to overwrite existing artifact: $destination"
  SECURE_TEMP_FILE=$(mktemp "$directory/.${name}.tmp.XXXXXX") || log_fatal "Cannot create secure temporary artifact"
  [[ -f "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" ]] || log_fatal "Temporary artifact is not a regular file"
  SECURE_TEMP_IDENTITY=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE") || log_fatal "Cannot inspect temporary artifact"
  exec 7<>"$SECURE_TEMP_FILE" || log_fatal "Cannot open temporary artifact"
  [[ -f /proc/self/fd/7 ]] || log_fatal "Temporary artifact descriptor is not a regular file"
  opened_identity=$(stat -Lc '%d:%i' -- /proc/self/fd/7) || log_fatal "Cannot inspect temporary artifact descriptor"
  [[ "$opened_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Temporary artifact changed while being opened"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: discard_secure_temp_file
#   Closes ænd removes only the current rændom temporæry ærtifæct
#ææææææææææææææææææææææææææææææææææ
discard_secure_temp_file() {
  exec 7>&- 2>/dev/null || true
  if [[ -n "$SECURE_TEMP_FILE" ]]; then
    rm -f -- "$SECURE_TEMP_FILE"
  fi
  SECURE_TEMP_FILE=""
  SECURE_TEMP_IDENTITY=""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_secure_temp_file
#   Ætomicælly publishes the vælidæted inode without overwriting æ target
#   Ærguments:
#     $1 - finæl publicætion pæth
#ææææææææææææææææææææææææææææææææææ
publish_secure_temp_file() {
  local destination="$1"
  local current_identity=""
  local move_status=0

  exec 7>&-
  [[ -f "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" ]] || log_fatal "Temporary artifact disappeared before publication"
  current_identity=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE") || log_fatal "Cannot re-inspect temporary artifact"
  [[ "$current_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Temporary artifact changed before publication"
  [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Backup artifact target appeared concurrently: $destination"
  mv -T --no-clobber -- "$SECURE_TEMP_FILE" "$destination" || move_status=$?
  if [[ ! -e "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" && -f "$destination" && ! -L "$destination" ]]; then
    current_identity=$(stat -Lc '%d:%i' -- "$destination") || log_fatal "Cannot inspect published backup artifact: $destination"
    [[ "$current_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Published backup artifact has an unexpected identity: $destination"
    PUBLISHED_BUNDLE_FILES+=("$destination")
    PUBLISHED_BUNDLE_IDENTITIES+=("$current_identity")
    SECURE_TEMP_FILE=""
    SECURE_TEMP_IDENTITY=""
    if (( move_status != 0 )); then
      log_warn "Publication rename reported status $move_status after the expected inode reached ${destination##*/}; treating the verified rename as complete"
    fi
    return 0
  fi
  if [[ -e "$SECURE_TEMP_FILE" || -L "$SECURE_TEMP_FILE" ]]; then
    discard_secure_temp_file
  fi
  log_fatal "Cannot publish backup artifact without a verified atomic rename: $destination"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reset_work_subdir
#   Recreætes one sæfe child directory inside the process workspæce
#   Ærguments:
#     $1 - child directory næme
#ææææææææææææææææææææææææææææææææææ
reset_work_subdir() {
  local name="$1"
  local target=""
  local target_mounts=()
  [[ "$name" =~ ^[a-z0-9_-]+$ ]] || log_fatal "Unsafe workspace child name: $name"
  prepare_tmp_dir
  target="$TMP_DIR/$name"
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -d "$target" && ! -L "$target" ]] || log_fatal "Unsafe workspace child: $target"
    [[ "$(realpath -e -- "$target")" == "$TMP_DIR/$name" ]] || log_fatal "Workspace child escaped its parent: $target"
    capture_mount_inventory target_mounts "$target" || log_fatal "Cannot inspect workspace-child mounts: $target"
    (( ${#target_mounts[@]} == 0 )) || log_fatal "Workspace child contains a mount and cannot be reset: $target"
    find "$target" -xdev -depth -mindepth 1 -delete || log_fatal "Cannot reset workspace child without crossing filesystems: $target"
  else
    mkdir -- "$target" || log_fatal "Cannot create workspace child: $target"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: next_sequence
#   Returns one greæter thæn the highest existing numeric suffix
#   Ærguments:
#     $1 - directory to scæn
#     $2 - filenæme prefix
#     $3 - filenæme extension
#     $4 - bundle-mænifest prefix
#ææææææææææææææææææææææææææææææææææ
next_sequence() {
  local directory="$1"
  local prefix="$2"
  local extension="$3"
  local bundle_prefix="$4"
  local maximum=0
  local file=""
  local name=""
  local sequence=""
  local numeric=0
  local candidates=()

  if [[ -d "$directory" && ! -L "$directory" ]]; then
    capture_backup_inventory candidates none "$directory" -xdev -mindepth 1 -maxdepth 1 \( -name "${prefix}*${extension}" -o -name "${prefix}*${extension}.sha256" -o -name "${bundle_prefix}*.sha256" \)
    for file in "${candidates[@]}"; do
      name="${file##*/}"
      sequence=""
      if [[ "$name" == "$prefix"*"$extension" ]]; then
        sequence="${name#"$prefix"}"
        sequence="${sequence%"$extension"}"
      elif [[ "$name" == "$prefix"*"${extension}.sha256" ]]; then
        sequence="${name#"$prefix"}"
        sequence="${sequence%"${extension}.sha256"}"
      elif [[ "$name" == "$bundle_prefix"*'.sha256' ]]; then
        sequence="${name#"$bundle_prefix"}"
        sequence="${sequence%.sha256}"
      fi
      [[ "$sequence" =~ ^[0-9]{1,9}$ ]] || continue
      numeric=$((10#$sequence))
      if (( numeric > maximum )); then
        maximum=$numeric
      fi
    done
  fi

  printf '%02d\n' "$((maximum + 1))"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: sequence_is_available
#   Requires every output pæth for one bundle suffix to be unoccupied
#   Ærguments:
#     $1 - ærchive pæth
#     $2 - bundle mænifest pæth
#ææææææææææææææææææææææææææææææææææ
sequence_is_available() {
  local archive="$1"
  local manifest="$2"
  [[ ! -e "$archive" && ! -L "$archive" && ! -e "${archive}.sha256" && ! -L "${archive}.sha256" && ! -e "$manifest" && ! -L "$manifest" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: begin_bundle_publication
#   Stærts one rollbæck-træcked three-file bundle publicætion
#ææææææææææææææææææææææææææææææææææ
begin_bundle_publication() {
  PUBLISHED_BUNDLE_FILES=()
  PUBLISHED_BUNDLE_IDENTITIES=()
  BUNDLE_PUBLICATION_COMMITTED=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: commit_bundle_publication
#   Commits the complete, revælidæted ærchive/sidecær/mænifest set
#ææææææææææææææææææææææææææææææææææ
commit_bundle_publication() {
  (( ${#PUBLISHED_BUNDLE_FILES[@]} == 3 )) || log_fatal "A backup bundle must publish exactly an archive, checksum sidecar, and bundle manifest"
  BUNDLE_PUBLICATION_COMMITTED=true
  PUBLISHED_BUNDLE_FILES=()
  PUBLISHED_BUNDLE_IDENTITIES=()
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: archive_directory
#   Creætes æ zstd-compressed tær ærchive without overwriting existing dætæ
#   Ærguments:
#     $1 - source directory
#     $2 - finæl ærchive pæth
#ææææææææææææææææææææææææææææææææææ
archive_directory() {
  local source_dir="$1"
  local destination="$2"
  shift 2
  local tar_options=("$@")

  open_secure_temp_file "$destination"
  log_info "Compressing backup -> ${destination##*/}"

  run_backup_child bash -o pipefail -c '
    source_dir="$1"
    shift
    tar "$@" -cf - -C "$source_dir" . | zstd -q -T0 --stdout >&7
  ' backup-compress "$source_dir" "${tar_options[@]}" || {
    discard_secure_temp_file
    log_fatal "Failed to compress backup"
  }
  publish_secure_temp_file "$destination"
  CREATED_ARCHIVE="$destination"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_checksum
#   Writes æ SHA256 sidecær using only the ærchive bæsenæme
#   Ærguments:
#     $1 - ærchive pæth
#ææææææææææææææææææææææææææææææææææ
write_checksum() {
  local archive="$1"
  local directory="${archive%/*}"
  local name="${archive##*/}"
  local checksum="${archive}.sha256"

  open_secure_temp_file "$checksum"
  (
    cd -- "$directory"
    sha256sum "$name"
  ) >&7 || {
    discard_secure_temp_file
    log_fatal "Failed to create checksum for $name"
  }
  publish_secure_temp_file "$checksum"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_checksum_record
#   Requires one strict SHÆ256 record tied to the expected ærchive bæsenæme
#   Ærguments:
#     $1 - checksum record
#     $2 - expected ærchive pæth
#     $3 - record source læbel
#ææææææææææææææææææææææææææææææææææ
validate_checksum_record() {
  local record="$1"
  local archive="$2"
  local source_label="$3"
  local expected=""
  local referenced=""
  local actual=""

  (( ${#record} >= 67 )) || log_fatal "Invalid SHA256 record in $source_label"
  expected="${record:0:64}"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || log_fatal "Invalid SHA256 value in $source_label"
  [[ "${record:64:2}" == "  " ]] || log_fatal "Invalid SHA256 record separator in $source_label"
  referenced="${record:66}"
  [[ "$referenced" =~ ^[A-Za-z0-9._-]+$ ]] || log_fatal "Unsafe artifact name in $source_label"
  [[ "$referenced" == "${archive##*/}" ]] || log_fatal "SHA256 record in $source_label references unexpected artifact: $referenced"
  actual=$(sha256sum -- "$archive")
  actual="${actual%% *}"
  [[ "${expected,,}" == "$actual" ]] || log_fatal "Checksum mismatch for ${archive##*/} in $source_label"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: verify_archive_checksum
#   Requires one strict sidecær tied to its regulær non-symlink ærchive
#   Ærguments:
#     $1 - ærchive pæth
#ææææææææææææææææææææææææææææææææææ
verify_archive_checksum() {
  local archive="$1"
  local sidecar="${archive}.sha256"
  local directory="${archive%/*}"
  local canonical_record=""
  local records=()

  [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Archive must be a regular non-symlink file: ${archive##*/}"
  [[ -f "$sidecar" && ! -L "$sidecar" ]] || log_fatal "Missing safe checksum sidecar: ${sidecar##*/}"
  canonical_record=$(cd -- "$directory" && sha256sum "${archive##*/}") || log_fatal "Cannot calculate canonical checksum record: ${archive##*/}"
  cmp -s -- "$sidecar" <(printf '%s\n' "$canonical_record") || log_fatal "Checksum sidecar is not one canonical newline-terminated record: ${sidecar##*/}"
  mapfile -t records < "$sidecar" || log_fatal "Cannot read checksum sidecar: ${sidecar##*/}"
  (( ${#records[@]} == 1 )) || log_fatal "Checksum sidecar must contain exactly one record: ${sidecar##*/}"
  validate_checksum_record "${records[0]}" "$archive" "${sidecar##*/}"
  log_info "Checksum verified: ${archive##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_archive_payload
#   Enforces the restore policy for compression, pæths, links ænd entry types
#   Ærguments:
#     $1 - compressed tær ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_tar_archive_payload() {
  local archive="$1"
  local entry=""
  local clean=""
  local listing=""
  local entry_type=""

  zstd -t -q "$archive" || log_fatal "Corrupt zstd archive: ${archive##*/}"
  zstd -d -q --stdout "$archive" | tar --list --absolute-names --file=- > /dev/null || log_fatal "Invalid tar archive: ${archive##*/}"

  while IFS= read -r entry; do
    clean="${entry#./}"
    [[ -n "$clean" ]] || continue
    [[ "$clean" != /* ]] || log_fatal "Archive contains an absolute path: ${archive##*/}"
    case "/$clean/" in
      */../*)
        log_fatal "Archive contains parent traversal: ${archive##*/}"
        ;;
    esac
  done < <(zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --absolute-names --quoting-style=escape --file=-)

  while IFS= read -r listing; do
    entry_type="${listing:0:1}"
    case "$entry_type" in
      -|d)
        ;;
      l|h)
        log_fatal "Archive contains a forbidden symbolic or hard link: ${archive##*/}"
        ;;
      *)
        log_fatal "Archive contains an unsupported special entry: ${archive##*/}"
        ;;
    esac
  done < <(zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --verbose --absolute-names --numeric-owner --quoting-style=escape --file=-)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_predecessor_archive
#   Verifies one physicæl chæin ærchive, sidecær ænd restore-safe structure
#   Ærguments:
#     $1 - physicæl predecessor ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_predecessor_archive() {
  local archive="$1"
  verify_archive_checksum "$archive"
  validate_tar_archive_payload "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_bundle_manifest
#   Writes the cænonicæl mænifest for one dætæbæse ærchive
#   Ærguments:
#     $1 - mænifest pæth
#     $2 - dætæbæse ærchive to include
#ææææææææææææææææææææææææææææææææææ
write_bundle_manifest() {
  local manifest="$1"
  local archive="$2"
  local directory="${manifest%/*}"

  open_secure_temp_file "$manifest"
  (
    cd -- "$directory"
    sha256sum "${archive##*/}"
  ) >&7 || {
    discard_secure_temp_file
    log_fatal "Failed to create bundle manifest"
  }
  publish_secure_temp_file "$manifest"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_bundle_manifest
#   Vælidætes exæct one-ærchive mænifest membership
#   Ærguments:
#     $1 - bundle mænifest pæth
#     $2 - expected dætæbæse ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_bundle_manifest() {
  local manifest="$1"
  local database_archive="$2"
  local directory="${manifest%/*}"
  local records=()

  [[ -f "$manifest" && ! -L "$manifest" ]] || log_fatal "Missing safe bundle manifest: ${manifest##*/}"
  [[ "${database_archive%/*}" == "$directory" ]] || log_fatal "Bundle artifact escaped its manifest directory"
  cmp -s -- "$manifest" <(
    cd -- "$directory" && sha256sum "${database_archive##*/}"
  ) || log_fatal "Bundle manifest is not canonical and newline-terminated: ${manifest##*/}"
  mapfile -t records < "$manifest" || log_fatal "Cannot read bundle manifest: ${manifest##*/}"
  (( ${#records[@]} == 1 )) || log_fatal "Bundle manifest must contain exactly one database archive: ${manifest##*/}"
  validate_checksum_record "${records[0]}" "$database_archive" "${manifest##*/}"
  log_info "Bundle manifest verified: ${manifest##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_physical_bundle
#   Vælidætes one physicæl ærchive, sidecær ænd mænifest
#   Ærguments:
#     $1 - bundle type (full|incremental)
#     $2 - bundle ID
#     $3 - physicæl dætæbæse ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_physical_bundle() {
  local bundle_type="$1"
  local bundle_id="$2"
  local database_archive="$3"
  local directory="${database_archive%/*}"
  local manifest="$directory/bundle_${bundle_type}_${bundle_id}.sha256"

  [[ "$bundle_type" == "full" || "$bundle_type" == "incremental" ]] || log_fatal "Unsupported physical bundle type: $bundle_type"
  [[ "${database_archive##*/}" == "${bundle_type}_${bundle_id}.zst" ]] || log_fatal "Unexpected physical archive name: ${database_archive##*/}"
  validate_predecessor_archive "$database_archive"
  validate_bundle_manifest "$manifest" "$database_archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_dump_bundle
#   Re-vælidætes one logicæl dump, sidecær ænd mænifest
#   Ærguments:
#     $1 - dump bundle ID
#     $2 - logicæl dump ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_dump_bundle() {
  local bundle_id="$1"
  local database_archive="$2"
  local directory="${database_archive%/*}"
  local manifest="$directory/bundle_dump_${bundle_id}.sha256"

  [[ "$bundle_id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid dump bundle ID: $bundle_id"
  [[ "${database_archive##*/}" == "dump_${bundle_id}.sql.zst" ]] || log_fatal "Unexpected logical dump name: ${database_archive##*/}"
  verify_archive_checksum "$database_archive"
  zstd -t -q "$database_archive" || log_fatal "Corrupt logical dump: ${database_archive##*/}"
  validate_bundle_manifest "$manifest" "$database_archive"
  log_ok "Logical dump bundle fully verified: ${database_archive##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_physical_full_candidates
#   Loæds every matching full node only æfter the complete inventory is sæfe
#ææææææææææææææææææææææææææææææææææ
load_physical_full_candidates() {
  local candidate=""
  local directory=""
  local day=""

  capture_backup_inventory PHYSICAL_FULL_CANDIDATES version-reverse "$BACKUP_DIR" -xdev -mindepth 2 -maxdepth 2 -name 'full_*.zst'
  for candidate in "${PHYSICAL_FULL_CANDIDATES[@]}"; do
    directory="${candidate%/*}"
    day="${directory##*/}"
    [[ "$day" =~ ^[0-9]{8}$ && "${directory%/*}" == "$BACKUP_DIR" ]] || log_fatal "Physical full candidate escaped a dated backup directory: $candidate"
    [[ -d "$directory" && ! -L "$directory" && "$(realpath -e -- "$directory")" == "$directory" ]] || log_fatal "Physical full candidate directory is unsafe: $directory"
    [[ -f "$candidate" && ! -L "$candidate" ]] || log_fatal "Physical full candidate must be a regular non-symlink file: ${candidate##*/}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_latest_valid_full
#   Scæns newest-to-oldest ænd returns the first complete vælid physicæl chæin
#ææææææææææææææææææææææææææææææææææ
get_latest_valid_full() {
  local candidate=""

  load_physical_full_candidates
  for candidate in "${PHYSICAL_FULL_CANDIDATES[@]}"; do
    if ( validate_physical_chain "$candidate" ) >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
    log_warn "Skipping invalid physical chain during newest-to-oldest selection: ${candidate##*/}"
  done
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: full_backup_id
#   Extræcts YYYYMMDD_SEQUENCE from æ full ærchive filenæme
#   Ærguments:
#     $1 - full ærchive pæth
#ææææææææææææææææææææææææææææææææææ
full_backup_id() {
  local name="${1##*/}"
  name="${name#full_}"
  printf '%s\n' "${name%.zst}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_incremental_artifact_inventory
#   Rejects orphan sidecærs or mænifests in the selected chæin
#   Ærguments:
#     $1 - directory contæining the chæin
#     $2 - full bæckup ID
#ææææææææææææææææææææææææææææææææææ
validate_incremental_artifact_inventory() {
  local directory="$1"
  local full_id="$2"
  local artifact=""
  local name=""
  local suffix=""
  local database_archive=""
  local sidecars=()
  local manifests=()

  capture_backup_inventory sidecars none "$directory" -xdev -mindepth 1 -maxdepth 1 -name "incremental_${full_id}_*.zst.sha256"
  for artifact in "${sidecars[@]}"; do
    [[ -f "$artifact" && ! -L "$artifact" ]] || log_fatal "Incremental checksum sidecar must be a regular non-symlink file: ${artifact##*/}"
    database_archive="${artifact%.sha256}"
    [[ -e "$database_archive" || -L "$database_archive" ]] || log_fatal "Orphan incremental checksum sidecar: ${artifact##*/}"
  done

  capture_backup_inventory manifests none "$directory" -xdev -mindepth 1 -maxdepth 1 -name "bundle_incremental_${full_id}_*.sha256"
  for artifact in "${manifests[@]}"; do
    [[ -f "$artifact" && ! -L "$artifact" ]] || log_fatal "Incremental bundle manifest must be a regular non-symlink file: ${artifact##*/}"
    name="${artifact##*/}"
    suffix="${name#bundle_incremental_}"
    suffix="${suffix%.sha256}"
    database_archive="$directory/incremental_${suffix}.zst"
    [[ -e "$database_archive" || -L "$database_archive" ]] || log_fatal "Orphan incremental bundle manifest: $name"
  done

}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_physical_chain
#   Fully vælidætes the selected full ænd every incrementæl before extension or retention
#   Ærguments:
#     $1 - selected full bæckup ærchive
#ææææææææææææææææææææææææææææææææææ
validate_physical_chain() {
  local full_archive="$1"
  local directory="${full_archive%/*}"
  local full_id=""
  local chain_day=""
  local archives=()
  local archive=""
  local name=""
  local incremental_id=""
  local sequence=""
  local expected=1

  full_id=$(full_backup_id "$full_archive")
  [[ "$full_id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid full backup ID: $full_id"
  chain_day="${full_id%%_*}"
  [[ "$directory" == "$BACKUP_DIR/$chain_day" ]] || log_fatal "Full backup is outside its dated chain directory: ${full_archive##*/}"
  validate_physical_bundle "full" "$full_id" "$full_archive"
  VALIDATED_CHAIN_PREDECESSOR="$full_archive"

  capture_backup_inventory archives version "$directory" -xdev -mindepth 1 -maxdepth 1 -name "incremental_${full_id}_*.zst"
  for archive in "${archives[@]}"; do
    name="${archive##*/}"
    incremental_id="${name#incremental_}"
    incremental_id="${incremental_id%.zst}"
    sequence="${incremental_id##*_}"
    [[ "$sequence" =~ ^[0-9]{1,9}$ && "$incremental_id" == "${full_id}_${sequence}" ]] || log_fatal "Invalid incremental archive name: $name"
    [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Incremental candidate must be a regular non-symlink file: $name"
    if (( 10#$sequence != expected )); then
      log_fatal "Incremental chain for $full_id is incomplete at sequence $(printf '%02d' "$expected")"
    fi
    validate_physical_bundle "incremental" "$incremental_id" "$archive"
    VALIDATED_CHAIN_PREDECESSOR="$archive"
    expected=$((expected + 1))
  done
  validate_incremental_artifact_inventory "$directory" "$full_id"
  log_ok "Physical backup chain fully verified through ${VALIDATED_CHAIN_PREDECESSOR##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: extract_physical_archive
#   Extræcts one physicæl bæckup into æ freshly reset work directory
#   Ærguments:
#     $1 - ærchive pæth
#     $2 - work directory næme
#ææææææææææææææææææææææææææææææææææ
extract_physical_archive() {
  local archive="$1"
  local work_name="$2"
  local target=""

  validate_predecessor_archive "$archive"
  reset_work_subdir "$work_name"
  target="$TMP_DIR/$work_name"
  log_info "Extracting predecessor ${archive##*/}"
  run_backup_child bash -o pipefail -c '
    zstd -d -q --stdout "$1" | tar -xf - -C "$2"
  ' backup-extract "$archive" "$target" || log_fatal "Failed to extract predecessor archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_success_status
#   Ætomicælly records the Unix epoch only æfter æ complete bundle publicætion
#ææææææææææææææææææææææææææææææææææ
write_success_status() {
  local epoch=""
  local opened_identity=""
  local current_identity=""

  is_safe_backup_dir || log_fatal "Backup directory identity changed before success-status publication"
  [[ "$SUCCESS_FILE" == "$BACKUP_DIR/.mariadb-maintenance-last-success" ]] || log_fatal "Unsafe backup success-status path"
  if [[ -e "$SUCCESS_FILE" || -L "$SUCCESS_FILE" ]]; then
    [[ -f "$SUCCESS_FILE" && ! -L "$SUCCESS_FILE" ]] || log_fatal "Backup success status must be a regular non-symlink file"
  fi
  [[ -z "$SECURE_TEMP_FILE" ]] || log_fatal "Internal error: temporary artifact still active before success-status publication"

  epoch=$(date +'%s')
  [[ "$epoch" =~ ^[0-9]+$ ]] || log_fatal "Cannot create a numeric backup success timestamp"
  SECURE_TEMP_FILE=$(mktemp "$BACKUP_DIR/.mariadb-maintenance-last-success.tmp.XXXXXX") || log_fatal "Cannot create temporary backup success status"
  [[ -f "$SECURE_TEMP_FILE" && ! -L "$SECURE_TEMP_FILE" ]] || log_fatal "Temporary backup success status is not a regular file"
  SECURE_TEMP_IDENTITY=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE") || log_fatal "Cannot inspect temporary backup success status"
  exec 7<>"$SECURE_TEMP_FILE" || log_fatal "Cannot open temporary backup success status"
  opened_identity=$(stat -Lc '%d:%i' -- /proc/self/fd/7) || log_fatal "Cannot inspect backup success-status descriptor"
  [[ "$opened_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Temporary backup success status changed while being opened"
  printf '%s' "$epoch" >&7 || log_fatal "Cannot write backup success timestamp"
  exec 7>&-

  current_identity=$(stat -Lc '%d:%i' -- "$SECURE_TEMP_FILE") || log_fatal "Cannot re-inspect temporary backup success status"
  [[ "$current_identity" == "$SECURE_TEMP_IDENTITY" ]] || log_fatal "Temporary backup success status changed before publication"
  if [[ -e "$SUCCESS_FILE" || -L "$SUCCESS_FILE" ]]; then
    [[ -f "$SUCCESS_FILE" && ! -L "$SUCCESS_FILE" ]] || log_fatal "Backup success status became unsafe before publication"
  fi
  mv -T -- "$SECURE_TEMP_FILE" "$SUCCESS_FILE" || log_fatal "Cannot publish backup success status"
  SECURE_TEMP_FILE=""
  SECURE_TEMP_IDENTITY=""

  [[ -f "$SUCCESS_FILE" && ! -L "$SUCCESS_FILE" ]] || log_fatal "Published backup success status is unsafe"
  [[ "$(<"$SUCCESS_FILE")" == "$epoch" ]] || log_fatal "Published backup success status failed verification"
  log_ok "Backup success status updated"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- BÆCKUP OPERÆTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_full_backup
#   Executes æ full physicæl dætæbæse bæckup
#ææææææææææææææææææææææææææææææææææ
perform_full_backup() {
  local day_dir="$BACKUP_DIR/$TODAY"
  local sequence=""
  local bundle_id=""
  local database_archive=""

  sequence=$(next_sequence "$day_dir" "full_${TODAY}_" ".zst" "bundle_full_${TODAY}_")
  bundle_id="${TODAY}_${sequence}"
  while ! sequence_is_available "$day_dir/full_${bundle_id}.zst" "$day_dir/bundle_full_${bundle_id}.sha256"; do
    sequence=$(printf '%02d' "$((10#$sequence + 1))")
    bundle_id="${TODAY}_${sequence}"
  done
  reset_work_subdir "full"

  log_info "Creating FULL backup with ID $bundle_id"
  run_backup_child mariadb-backup \
    "$MARIADB_CLIENT_OPTION_ARGUMENT" \
    --backup \
    --target-dir="$TMP_DIR/full" \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" > /dev/null 2>&1 || log_fatal "MariaDB full backup failed"

  begin_bundle_publication
  archive_directory "$TMP_DIR/full" "$day_dir/full_${bundle_id}.zst"
  database_archive="$CREATED_ARCHIVE"
  write_checksum "$database_archive"
  write_bundle_manifest "$day_dir/bundle_full_${bundle_id}.sha256" "$database_archive"
  validate_physical_bundle "full" "$bundle_id" "$database_archive"
  commit_bundle_publication

  log_ok "Full backup saved as $database_archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_incremental_backup
#   Bæses eæch new incrementæl on the immediæte predecessor
#ææææææææææææææææææææææææææææææææææ
perform_incremental_backup() {
  local latest_full=""
  local full_id=""
  local chain_dir=""
  local predecessor=""
  local sequence=""
  local archive=""
  local full_candidates=()

  load_physical_full_candidates
  full_candidates=("${PHYSICAL_FULL_CANDIDATES[@]}")
  if (( ${#full_candidates[@]} == 0 )); then
    log_info "No full backup found. Creating one instead."
    perform_full_backup
    return 0
  fi
  latest_full=$(get_latest_valid_full) || log_fatal "No valid physical full-backup chain exists; refusing to extend corrupted backup history"
  [[ -f "$latest_full" && ! -L "$latest_full" ]] || log_fatal "Latest full backup candidate is not a regular non-symlink file: ${latest_full##*/}"

  full_id=$(full_backup_id "$latest_full")
  [[ "$full_id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid full backup ID: $full_id"
  chain_dir="${latest_full%/*}"
  validate_physical_chain "$latest_full"
  predecessor="$VALIDATED_CHAIN_PREDECESSOR"
  sequence=$(next_sequence "$chain_dir" "incremental_${full_id}_" ".zst" "bundle_incremental_${full_id}_")
  while ! sequence_is_available "$chain_dir/incremental_${full_id}_${sequence}.zst" "$chain_dir/bundle_incremental_${full_id}_${sequence}.sha256"; do
    sequence=$(printf '%02d' "$((10#$sequence + 1))")
  done

  log_info "Using ${predecessor##*/} as immediate incremental predecessor"
  extract_physical_archive "$predecessor" "base"
  reset_work_subdir "incremental"

  run_backup_child mariadb-backup \
    "$MARIADB_CLIENT_OPTION_ARGUMENT" \
    --backup \
    --target-dir="$TMP_DIR/incremental" \
    --incremental-basedir="$TMP_DIR/base" \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" > /dev/null 2>&1 || log_fatal "MariaDB incremental backup failed"

  archive="$chain_dir/incremental_${full_id}_${sequence}.zst"
  begin_bundle_publication
  archive_directory "$TMP_DIR/incremental" "$archive"
  write_checksum "$archive"
  write_bundle_manifest "$chain_dir/bundle_incremental_${full_id}_${sequence}.sha256" "$archive"
  validate_physical_bundle "incremental" "${full_id}_${sequence}" "$archive"
  commit_bundle_publication
  log_ok "Incremental backup saved as $archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: perform_dump_backup
#   Creætes æ ræw `.sql.zst` dætæbæse dump
#ææææææææææææææææææææææææææææææææææ
perform_dump_backup() {
  local day_dir="$BACKUP_DIR/$TODAY"
  local sequence=""
  local bundle_id=""
  local database_archive=""

  sequence=$(next_sequence "$day_dir" "dump_${TODAY}_" ".sql.zst" "bundle_dump_${TODAY}_")
  bundle_id="${TODAY}_${sequence}"
  while ! sequence_is_available "$day_dir/dump_${bundle_id}.sql.zst" "$day_dir/bundle_dump_${bundle_id}.sha256"; do
    sequence=$(printf '%02d' "$((10#$sequence + 1))")
    bundle_id="${TODAY}_${sequence}"
  done
  database_archive="$day_dir/dump_${bundle_id}.sql.zst"
  begin_bundle_publication
  open_secure_temp_file "$database_archive"

  log_info "Creating logical DUMP with ID $bundle_id"
  run_backup_child bash -o pipefail -c '
    mariadb-dump \
      "$1" \
      --host="$2" \
      --user="$3" \
      --databases "$4" \
      --single-transaction \
      --routines \
      --triggers \
      --events \
      --add-drop-database \
      --add-drop-table \
      --create-options \
      --extended-insert \
      --quick \
      --net_buffer_length=1M \
      2>/dev/null | zstd -q -T0 --stdout >&7
  ' backup-dump "$MARIADB_CLIENT_OPTION_ARGUMENT" "$MARIADB_DB_HOST" "$MARIADB_ROOT_USER" "$MARIADB_DATABASE" || {
      discard_secure_temp_file
      log_fatal "Failed to create SQL dump"
    }
  publish_secure_temp_file "$database_archive"
  write_checksum "$database_archive"
  write_bundle_manifest "$day_dir/bundle_dump_${bundle_id}.sha256" "$database_archive"

  validate_dump_bundle "$bundle_id" "$database_archive"
  commit_bundle_publication

  log_ok "Logical dump saved as $database_archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_expired_backup_dir
#   Removes one inode-pinned dæted directory without crossing æ filesystem
#   Ærguments:
#     $1 - direct dæted child of `/backup`
#     $2 - vælidæted directory identity
#ææææææææææææææææææææææææææææææææææ
remove_expired_backup_dir() {
  local dir="$1"
  local expected_identity="$2"
  local current_identity=""
  local mount_target=""
  local mount_targets=()

  [[ "${dir%/*}" == "$BACKUP_DIR" && "${dir##*/}" =~ ^[0-9]{8}$ ]] || log_fatal "Unsafe retention target: $dir"
  [[ -d "$dir" && ! -L "$dir" && "$(realpath -e -- "$dir")" == "$dir" ]] || log_fatal "Retention target changed or became unsafe: $dir"
  current_identity=$(stat -Lc '%d:%i' -- "$dir") || log_fatal "Cannot inspect retention target: $dir"
  [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Retention target identity changed before deletion: $dir"
  is_safe_backup_dir || log_fatal "Backup directory identity changed before retention deletion"

  capture_mount_inventory mount_targets "$dir" || log_fatal "Cannot inspect nested mounts below $dir"
  for mount_target in "${mount_targets[@]}"; do
    [[ -z "$mount_target" ]] || log_fatal "Retention target contains a mount and will not be removed: $mount_target"
  done

  log_info "Removing expired backup directory: $dir"
  find "$dir" -xdev -depth -mindepth 1 -delete || log_fatal "Failed to remove expired backup contents without crossing filesystems: $dir"
  current_identity=$(stat -Lc '%d:%i' -- "$dir") || log_fatal "Retention target disappeared or changed during deletion: $dir"
  [[ "$current_identity" == "$expected_identity" ]] || log_fatal "Retention target identity changed during deletion: $dir"
  rmdir -- "$dir" || log_fatal "Retention target is not empty after bounded deletion: $dir"
  [[ ! -e "$dir" && ! -L "$dir" ]] || log_fatal "Retention target remained after deletion: $dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_old_backups
#   Protects the newest vælid physicæl chæin ænd fæils closed before deletion
#ææææææææææææææææææææææææææææææææææ
remove_old_backups() {
  local dated_nodes=()
  local old_dirs=()
  local old_identities=()
  local full_candidates=()
  local dir=""
  local latest_full=""
  local protected_day_dir=""
  local index=0
  local expired_match=()

  is_safe_backup_dir || log_fatal "Backup directory identity changed before retention"
  load_physical_full_candidates
  full_candidates=("${PHYSICAL_FULL_CANDIDATES[@]}")
  (( ${#full_candidates[@]} > 0 )) || log_fatal "No physical full-backup chain exists; refusing retention and success-status publication"
  latest_full=$(get_latest_valid_full) || log_fatal "No valid physical backup chain exists; refusing retention and success-status publication"
  validate_physical_chain "$latest_full"
  protected_day_dir="${latest_full%/*}"

  capture_backup_inventory dated_nodes none "$BACKUP_DIR" -xdev -mindepth 1 -maxdepth 1 -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
  for dir in "${dated_nodes[@]}"; do
    [[ -d "$dir" && ! -L "$dir" && "$(realpath -e -- "$dir")" == "$dir" ]] || log_fatal "Dated backup node must be a regular non-symlink directory: $dir"
    capture_backup_inventory expired_match none "$dir" -xdev -maxdepth 0 -mtime +"$MARIADB_BACKUP_RETENTION_DAYS"
    if (( ${#expired_match[@]} > 0 )); then
      old_dirs+=("$dir")
      old_identities+=("$(stat -Lc '%d:%i' -- "$dir")")
    fi
  done
  if (( ${#old_dirs[@]} == 0 )); then
    return 0
  fi

  for index in "${!old_dirs[@]}"; do
    dir="${old_dirs[$index]}"
    if [[ -n "$protected_day_dir" && "$dir" == "$protected_day_dir" ]]; then
      log_info "Protecting latest successful full-backup chain from retention: $dir"
      continue
    fi
    remove_expired_backup_dir "$dir" "${old_identities[$index]}"
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Hændles flægs, locking, retention ænd bæckup mode execution
#   Ærguments:
#     $@ - bæckup mode ænd optionæl stændærd flægs
#ææææææææææææææææææææææææææææææææææ
main() {
  local backup_type="full"
  local argument=""

  for argument in "$@"; do
    case "$argument" in
      full|incremental|dump)
        backup_type="$argument"
        ;;
      --debug)
        DEBUG=true
        ;;
      --dry-run)
        DRY_RUN=true
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        log_fatal "Invalid argument: $argument"
        ;;
    esac
  done

  validate_configuration
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run: would create a $backup_type backup under $BACKUP_DIR/$TODAY"
    return 0
  fi

  if [[ "$DEBUG" != "true" ]]; then
    exec > >(grep -E '^\[(INFO|OK|WARN|ERROR|FATAL)\] ') 2>&1
  fi

  acquire_maintenance_lock
  create_mariadb_client_option_file
  case "$backup_type" in
    full)
      perform_full_backup
      ;;
    incremental)
      perform_incremental_backup
      ;;
    dump)
      perform_dump_backup
      ;;
  esac
  remove_old_backups
  write_success_status
}

main "$@"
