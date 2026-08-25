#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ENVIRONMENT VÆRIÆBLES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
MARIADB_ROOT_USER="${MARIADB_ROOT_USER:-root}"
MARIADB_DATABASE="${MARIADB_DATABASE:-}"
MARIADB_ROOT_PASSWORD_FILE="${MARIADB_ROOT_PASSWORD_FILE:-/run/secrets/MARIADB_ROOT_PASSWORD}"
MARIADB_DB_HOST="${MARIADB_DB_HOST:-mariadb}"
MARIADB_MAINTENANCE_MODE="${MARIADB_MAINTENANCE_MODE:-schedule}"
MARIADB_RESTORE_DRY_RUN="${MARIADB_RESTORE_DRY_RUN:-false}"
MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED="${MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED:-false}"
MARIADB_RESTORE_CONSUME_ARCHIVES="${MARIADB_RESTORE_CONSUME_ARCHIVES:-false}"
MARIADB_RESTORE_REQUIRE_CHECKSUM="${MARIADB_RESTORE_REQUIRE_CHECKSUM:-true}"
MARIADB_RESTORE_BACKUP_ID="${MARIADB_RESTORE_BACKUP_ID:-}"
MARIADB_RESTORE_RECREATE_DATABASE="${MARIADB_RESTORE_RECREATE_DATABASE:-false}"
MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT="${MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT:-false}"

RESTORE_DIR="${MARIADB_RESTORE_DIR:-/restore}"
TMP_PARENT="${RESTORE_DIR}/.tmp"
TMP_BASE=""
MARIADB_DIR="${MARIADB_DATA_DIR:-/var/lib/mysql}"
EXPECTED_MARIADB_DATA_DIR="/var/lib/mysql"
SUPERCRONIC_BIN="${MARIADB_SUPERCRONIC_BIN:-/usr/local/bin/supercronic}"
DEBUG="${MARIADB_RESTORE_DEBUG:-false}"
MAINTENANCE_LOCK_DIR="/backup"
TMP_CREATED=false
TMP_PARENT_CREATED=false
TMP_IDENTITY=""
TMP_PARENT_IDENTITY=""
RESTORE_CHAIN=()
BUNDLE_MANIFESTS=()
ORIGINAL_RESTORE_CHAIN=()
ORIGINAL_BUNDLE_MANIFESTS=()
CONSUMED_ARCHIVES=()
BUNDLE_CONSUME_FILES=()
BUNDLE_CONSUME_IDENTITIES=()
MOVED_BUNDLE_SOURCES=()
MOVED_BUNDLE_DESTINATIONS=()
CANONICAL_RESTORE_DIR=""
CANONICAL_TMP_PARENT=""
MARIADB_DATA_IDENTITY=""
RESTORE_IDENTITY=""
BACKUP_IDENTITY=""
BUNDLE_DATABASE_ARCHIVE=""
MANIFEST_ENTRY_CHECKSUM=""
MANIFEST_ENTRY_NAME=""
CONSUME_COMMITTED=false
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
RESTORE_STAGE_DIR=""
RESTORE_STAGE_IDENTITY=""
RESTORE_OLD_DIR=""
RESTORE_OLD_IDENTITY=""
RESTORE_SWITCH_JOURNAL=""
RESTORE_SWITCH_ACTIVE=false
RESTORE_SWITCH_COMMITTED=false
RESTORE_SWITCH_FINALIZED=false
RESTORE_JOURNAL_STATE=""
RESTORE_OLD_SOURCES=()
RESTORE_OLD_DESTINATIONS=()
RESTORE_OLD_IDENTITIES=()
RESTORE_NEW_SOURCES=()
RESTORE_NEW_DESTINATIONS=()
RESTORE_NEW_IDENTITIES=()

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

log_dry() {
  printf '[DRY RUN] %s\n' "$*"
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
#   Prints explicit scheduler ænd restore modes
#ææææææææææææææææææææææææææææææææææ
usage() {
  cat <<'EOF'
Usage: entrypoint.sh [schedule|restore|restore-dump] [options]

  schedule             Run Supercronic (default)
  restore              Restore one physical full/incremental chain; DB must be stopped
  restore-dump         Import one raw .sql.zst dump; DB must be running

Options:
  --dry-run  Validate and print the plan without creating, deleting, or modifying files
  --debug    Enable verbose logging
  -h, --help Show this help
EOF
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_boolean
#   Rejects non-booleæn environment vælues
#   Ærguments:
#     $1 - væriæble næme
#     $2 - væriæble vælue
#ææææææææææææææææææææææææææææææææææ
validate_boolean() {
  local name="$1"
  local value="$2"
  [[ "$value" == "true" || "$value" == "false" ]] || log_fatal "$name must be true or false"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_tmp_base
#   Vælidætes thæt only æ unique child of `/restore/.tmp` cæn be removed
#ææææææææææææææææææææææææææææææææææ
is_safe_tmp_base() {
  local canonical_base=""
  local current_identity=""
  local current_parent_identity=""

  case "$TMP_BASE" in
    "$TMP_PARENT"/restore_chain.*)
      [[ -n "${TMP_BASE#"$TMP_PARENT"/restore_chain.}" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  [[ -d "$TMP_BASE" && ! -L "$TMP_BASE" ]] || return 1
  [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || return 1
  current_parent_identity=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || return 1
  [[ -n "$TMP_PARENT_IDENTITY" && "$current_parent_identity" == "$TMP_PARENT_IDENTITY" ]] || return 1
  canonical_base=$(realpath -e -- "$TMP_BASE") || return 1
  case "$canonical_base" in
    "$CANONICAL_TMP_PARENT"/restore_chain.*)
      [[ -n "${canonical_base#"$CANONICAL_TMP_PARENT"/restore_chain.}" ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  current_identity=$(stat -Lc '%d:%i' -- "$TMP_BASE") || return 1
  [[ -n "$TMP_IDENTITY" && "$current_identity" == "$TMP_IDENTITY" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_safe_data_dir
#   Rejects broæd or symlinked dætæbæse restore tærgets
#ææææææææææææææææææææææææææææææææææ
is_safe_data_dir() {
  local canonical_data_dir=""
  local current_identity=""
  local protected_path=""
  local protected_identity=""

  [[ "$MARIADB_DIR" == "$EXPECTED_MARIADB_DATA_DIR" ]] || return 1
  [[ -d "$MARIADB_DIR" && ! -L "$MARIADB_DIR" ]] || return 1
  canonical_data_dir=$(realpath -e -- "$MARIADB_DIR") || return 1
  [[ "$canonical_data_dir" == "$EXPECTED_MARIADB_DATA_DIR" ]] || return 1
  current_identity=$(stat -Lc '%d:%i' -- "$MARIADB_DIR") || return 1
  if [[ -n "$MARIADB_DATA_IDENTITY" && "$current_identity" != "$MARIADB_DATA_IDENTITY" ]]; then
    return 1
  fi
  for protected_path in "/backup" "$RESTORE_DIR"; do
    [[ -d "$protected_path" ]] || continue
    protected_identity=$(stat -Lc '%d:%i' -- "$protected_path") || return 1
    [[ "$current_identity" != "$protected_identity" ]] || return 1
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_configuration
#   Vælidætes shared restore configuration without mutæting files
#ææææææææææææææææææææææææææææææææææ
validate_configuration() {
  local requested_restore_dir="${RESTORE_DIR%/}"
  local requested_tmp_parent="${TMP_PARENT%/}"
  local required_command=""

  for required_command in chmod find findmnt flock grep id mariadb mariadb-admin mariadb-backup mktemp mv realpath sha256sum setsid stat sync tar wc zstd; do
    command -v "$required_command" >/dev/null 2>&1 || log_fatal "Required command is unavailable: $required_command"
  done
  [[ -f "$MARIADB_ROOT_PASSWORD_FILE" && ! -L "$MARIADB_ROOT_PASSWORD_FILE" ]] || log_fatal "MariaDB root password file must be a regular non-symlink file"

  validate_boolean "MARIADB_RESTORE_DRY_RUN" "$MARIADB_RESTORE_DRY_RUN"
  validate_boolean "MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED" "$MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED"
  validate_boolean "MARIADB_RESTORE_CONSUME_ARCHIVES" "$MARIADB_RESTORE_CONSUME_ARCHIVES"
  validate_boolean "MARIADB_RESTORE_REQUIRE_CHECKSUM" "$MARIADB_RESTORE_REQUIRE_CHECKSUM"
  validate_boolean "MARIADB_RESTORE_RECREATE_DATABASE" "$MARIADB_RESTORE_RECREATE_DATABASE"
  validate_boolean "MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT" "$MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT"
  [[ -n "$MARIADB_DATABASE" && ${#MARIADB_DATABASE} -le 64 && ! "$MARIADB_DATABASE" =~ [[:cntrl:]] ]] || log_fatal "MARIADB_DATABASE must contain 1-64 characters without control characters"
  [[ "$RESTORE_DIR" == "/restore" ]] || log_fatal "Restore directory must be the dedicated /restore mount"
  [[ -d "$RESTORE_DIR" ]] || log_fatal "Restore directory does not exist: $RESTORE_DIR"
  [[ ! -L "$RESTORE_DIR" ]] || log_fatal "Restore directory must not be a symlink: $RESTORE_DIR"
  CANONICAL_RESTORE_DIR=$(realpath -e -- "$RESTORE_DIR") || log_fatal "Cannot resolve restore directory: $RESTORE_DIR"
  [[ "$requested_restore_dir" == "/restore" && "$CANONICAL_RESTORE_DIR" == "/restore" ]] || log_fatal "Restore directory contains a symlink or non-canonical component: $RESTORE_DIR"
  RESTORE_IDENTITY=$(stat -Lc '%d:%i' -- "$RESTORE_DIR") || log_fatal "Cannot inspect restore directory"

  [[ -d "/backup" && ! -L "/backup" ]] || log_fatal "Backup mount is unavailable"
  [[ "$(realpath -e -- /backup)" == "/backup" ]] || log_fatal "Backup mount contains a symlink or non-canonical component"
  BACKUP_IDENTITY=$(stat -Lc '%d:%i' -- /backup) || log_fatal "Cannot inspect backup mount"
  [[ "$RESTORE_IDENTITY" != "$BACKUP_IDENTITY" ]] || log_fatal "Restore and backup mounts must have different identities"

  CANONICAL_TMP_PARENT=$(realpath -m -- "$TMP_PARENT") || log_fatal "Cannot resolve restore workspace parent"
  [[ "$requested_tmp_parent" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Restore workspace parent contains a symlink or non-canonical component"
  [[ "$CANONICAL_TMP_PARENT" == "$CANONICAL_RESTORE_DIR/.tmp" ]] || log_fatal "Restore workspace parent escaped the restore directory"
  if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
    [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Restore workspace parent must be a regular directory"
    [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Restore workspace parent changed during validation"
    TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect restore workspace parent"
  fi

  RESTORE_DIR="$CANONICAL_RESTORE_DIR"
  TMP_PARENT="$CANONICAL_TMP_PARENT"

  is_safe_data_dir || log_fatal "MariaDB data directory must be the dedicated canonical /var/lib/mysql mount"
  MARIADB_DATA_IDENTITY=$(stat -Lc '%d:%i' -- "$MARIADB_DIR") || log_fatal "Cannot inspect MariaDB data directory"
  is_safe_data_dir || log_fatal "MariaDB data directory identity changed during validation"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only this process' unique workspæce
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  trap - INT TERM
  local index=0
  local preserve_workspace=false
  local expected_identity=""
  local restored_identity=""
  local workspace_mounts=()

  if ! remove_mariadb_client_option_file; then
    log_error "Cannot safely remove the private MariaDB client option file; preserving it for inspection"
    return 1
  fi

  if [[ "$RESTORE_SWITCH_ACTIVE" == "true" && "$RESTORE_SWITCH_COMMITTED" != "true" ]]; then
    if ! rollback_restore_switch; then
      preserve_workspace=true
      log_error "MariaDB data-directory rollback is uncertain; preserving the recovery journal and workspace: $TMP_BASE"
    fi
  fi

  if [[ "$RESTORE_SWITCH_COMMITTED" == "true" && "$RESTORE_SWITCH_FINALIZED" != "true" ]]; then
    finalize_committed_restore || preserve_workspace=true
  elif [[ "$RESTORE_SWITCH_ACTIVE" != "true" ]]; then
    remove_restore_transaction_dir "$RESTORE_STAGE_DIR" "$RESTORE_STAGE_IDENTITY" || preserve_workspace=true
    remove_restore_transaction_dir "$RESTORE_OLD_DIR" "$RESTORE_OLD_IDENTITY" || preserve_workspace=true
    RESTORE_STAGE_DIR=""
    RESTORE_STAGE_IDENTITY=""
    RESTORE_OLD_DIR=""
    RESTORE_OLD_IDENTITY=""
  fi

  if [[ "$CONSUME_COMMITTED" != "true" && ${#MOVED_BUNDLE_SOURCES[@]} -gt 0 ]]; then
    index=$((${#MOVED_BUNDLE_SOURCES[@]} - 1))
    while (( index >= 0 )); do
      expected_identity="${BUNDLE_CONSUME_IDENTITIES[$index]:-}"
      if [[ -z "$expected_identity" ]]; then
        preserve_workspace=true
        index=$((index - 1))
        continue
      fi
      if [[ -f "${MOVED_BUNDLE_SOURCES[$index]}" && ! -L "${MOVED_BUNDLE_SOURCES[$index]}" && ! -e "${MOVED_BUNDLE_DESTINATIONS[$index]}" && ! -L "${MOVED_BUNDLE_DESTINATIONS[$index]}" ]]; then
        restored_identity=$(stat -Lc '%d:%i:%s' -- "${MOVED_BUNDLE_SOURCES[$index]}" 2>/dev/null || true)
        [[ "$restored_identity" == "$expected_identity" ]] || preserve_workspace=true
        index=$((index - 1))
        continue
      fi
      if [[ -e "${MOVED_BUNDLE_SOURCES[$index]}" || -L "${MOVED_BUNDLE_SOURCES[$index]}" || ! -f "${MOVED_BUNDLE_DESTINATIONS[$index]}" || -L "${MOVED_BUNDLE_DESTINATIONS[$index]}" ]]; then
        preserve_workspace=true
        index=$((index - 1))
        continue
      fi
      restored_identity=$(stat -Lc '%d:%i:%s' -- "${MOVED_BUNDLE_DESTINATIONS[$index]}" 2>/dev/null || true)
      if [[ "$restored_identity" != "$expected_identity" ]]; then
        preserve_workspace=true
        index=$((index - 1))
        continue
      fi
      mv -T --no-clobber -- "${MOVED_BUNDLE_DESTINATIONS[$index]}" "${MOVED_BUNDLE_SOURCES[$index]}" 2>/dev/null || true
      restored_identity=$(stat -Lc '%d:%i:%s' -- "${MOVED_BUNDLE_SOURCES[$index]}" 2>/dev/null || true)
      if [[ -e "${MOVED_BUNDLE_DESTINATIONS[$index]}" || -L "${MOVED_BUNDLE_DESTINATIONS[$index]}" || ! -f "${MOVED_BUNDLE_SOURCES[$index]}" || -L "${MOVED_BUNDLE_SOURCES[$index]}" || "$restored_identity" != "$expected_identity" ]]; then
        preserve_workspace=true
      fi
      index=$((index - 1))
    done
    if [[ "$preserve_workspace" == "true" ]]; then
      log_error "Bundle-consumption rollback failed; preserving private workspace for manual recovery: $TMP_BASE"
    else
      MOVED_BUNDLE_SOURCES=()
      MOVED_BUNDLE_DESTINATIONS=()
    fi
  fi

  if [[ "$preserve_workspace" == "true" && "$TMP_CREATED" == "true" ]]; then
    log_error "Preserving private restore workspace for manual recovery: $TMP_BASE"
  fi

  if [[ "$preserve_workspace" != "true" && "$TMP_CREATED" == "true" ]] && is_safe_tmp_base; then
    if ! capture_mount_inventory workspace_mounts "$TMP_BASE"; then
      log_error "Cannot inspect restore-workspace mounts; preserving it: $TMP_BASE"
      return
    fi
    if (( ${#workspace_mounts[@]} > 0 )); then
      log_error "Restore workspace contains a mount; preserving it: $TMP_BASE"
      return
    fi
    find "$TMP_BASE" -xdev -depth -mindepth 1 -delete || {
      log_error "Cannot remove restore workspace without crossing filesystems: $TMP_BASE"
      return
    }
    rmdir -- "$TMP_BASE" || {
      log_error "Restore workspace is not empty; preserving it: $TMP_BASE"
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
#   Terminætes ænd reæps the complete æctive restore process group
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
# FUNCTION: run_restore_child
#   Runs one long tool in its own session for deterministic signæl forwarding
#ææææææææææææææææææææææææææææææææææ
run_restore_child() {
  local status=0
  setsid --wait -- "$@" &
  ACTIVE_CHILD_PID=$!
  wait "$ACTIVE_CHILD_PID" || status=$?
  ACTIVE_CHILD_PID=""
  return "$status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_restore_inventory
#   Cæptures NUL-delimited `find` output ænd explicitly checks find/sort stætus
#   Ærguments:
#     $1 - output ærræy næme
#     $2 - sort mode (`none`, `version`, or `version-reverse`)
#     $@ - find pæth ænd predicates, without `-print0`
#ææææææææææææææææææææææææææææææææææ
capture_restore_inventory() {
  local -n output_array="$1"
  local sort_mode="$2"
  local inventory_fd=""
  local inventory_pid=""
  local status=0
  shift 2
  output_array=()

  coproc MARIADB_RESTORE_INVENTORY {
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
  inventory_fd="${MARIADB_RESTORE_INVENTORY[0]}"
  inventory_pid="$MARIADB_RESTORE_INVENTORY_PID"
  mapfile -d '' -t output_array <&"$inventory_fd" || status=$?
  exec {inventory_fd}<&-
  if ! wait "$inventory_pid"; then
    status=$?
    (( status != 0 )) || status=1
  fi
  unset MARIADB_RESTORE_INVENTORY MARIADB_RESTORE_INVENTORY_PID 2>/dev/null || true
  (( status == 0 )) || log_fatal "Failed to capture a complete MariaDB restore filesystem inventory"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_mount_inventory
#   Distinguishes `findmnt`'s no-mætch stætus from reæl inventory errors
#   Ærguments:
#     $1 - output ærræy næme
#     $2 - directory to inspect recursively
#ææææææææææææææææææææææææææææææææææ
capture_mount_inventory() {
  # ShellCheck cænnot infer thæt this næmeref remæins æn ærræy æcross mæpfile.
  # shellcheck disable=SC2034,SC2178
  local -n output_array="$1"
  local path="$2"
  local output=""
  local status=0
  output_array=()
  output=$(findmnt -rn -o TARGET -R -- "$path" 2>/dev/null) || status=$?
  if (( status != 0 )); then
    # `findmnt` returns one for æ vælid pæth with no mætching mount.
    [[ "$status" == "1" && -z "$output" ]] || return 1
    return 0
  fi
  # shellcheck disable=SC2034
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

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_tmp_base
#   Creætes æ unique workspæce only for non-dry-run operætions
#ææææææææææææææææææææææææææææææææææ
create_tmp_base() {
  [[ "$MARIADB_RESTORE_DRY_RUN" != "true" ]] || log_fatal "Internal error: dry-run attempted to create a workspace"
  if [[ -e "$TMP_PARENT" || -L "$TMP_PARENT" ]]; then
    [[ -d "$TMP_PARENT" && ! -L "$TMP_PARENT" ]] || log_fatal "Unsafe restore workspace parent: $TMP_PARENT"
  else
    mkdir -- "$TMP_PARENT" || log_fatal "Cannot create restore workspace parent"
    TMP_PARENT_CREATED=true
    TMP_PARENT_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_PARENT") || log_fatal "Cannot inspect created restore workspace parent"
  fi
  [[ "$(realpath -e -- "$TMP_PARENT")" == "$CANONICAL_TMP_PARENT" ]] || log_fatal "Restore workspace parent changed before use"
  [[ "$(stat -Lc '%d:%i' -- "$TMP_PARENT")" == "$TMP_PARENT_IDENTITY" ]] || log_fatal "Restore workspace parent identity changed before use"
  TMP_BASE=$(mktemp -d "$TMP_PARENT/restore_chain.XXXXXX") || log_fatal "Cannot create private restore workspace"
  TMP_CREATED=true
  chmod 0700 -- "$TMP_BASE" || log_fatal "Cannot restrict private restore workspace"
  TMP_IDENTITY=$(stat -Lc '%d:%i' -- "$TMP_BASE") || log_fatal "Cannot inspect private restore workspace"
  is_safe_tmp_base || log_fatal "Unsafe restore workspace: $TMP_BASE"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- VÆLIDÆTION FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: verify_checksum
#   Verifies one ærchive ægæinst its SHA256 sidecær
#   Ærguments:
#     $1 - ærchive pæth
#ææææææææææææææææææææææææææææææææææ
verify_checksum() {
  local archive="$1"
  local sidecar="${archive}.sha256"
  local directory="${archive%/*}"
  local canonical_record=""
  local records=()
  local record=""
  local expected=""
  local referenced=""
  local actual=""

  [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Archive must be a regular non-symlink file: ${archive##*/}"
  if [[ ! -e "$sidecar" && ! -L "$sidecar" ]]; then
    if [[ "$MARIADB_RESTORE_REQUIRE_CHECKSUM" == "true" ]]; then
      log_fatal "Missing checksum sidecar: ${sidecar##*/}"
    fi
    log_warn "Checksum verification disabled for legacy archive: ${archive##*/}"
    return 0
  fi

  [[ -f "$sidecar" && ! -L "$sidecar" ]] || log_fatal "Checksum sidecar must be a regular non-symlink file: ${sidecar##*/}"
  canonical_record=$(cd -- "$directory" && sha256sum "${archive##*/}") || log_fatal "Cannot calculate canonical checksum record: ${archive##*/}"
  cmp -s -- "$sidecar" <(printf '%s\n' "$canonical_record") || log_fatal "Checksum sidecar is not one canonical newline-terminated record: ${sidecar##*/}"
  mapfile -t records < "$sidecar" || log_fatal "Cannot read checksum sidecar: ${sidecar##*/}"
  (( ${#records[@]} == 1 )) || log_fatal "Checksum sidecar must contain exactly one record: ${sidecar##*/}"
  record="${records[0]}"
  (( ${#record} >= 67 )) || log_fatal "Invalid checksum sidecar: ${sidecar##*/}"
  expected="${record:0:64}"
  [[ "$expected" =~ ^[a-fA-F0-9]{64}$ ]] || log_fatal "Invalid SHA256 value in ${sidecar##*/}"
  [[ "${record:64:2}" == "  " ]] || log_fatal "Invalid SHA256 separator in ${sidecar##*/}"
  referenced="${record:66}"
  [[ "$referenced" =~ ^[A-Za-z0-9._-]+$ ]] || log_fatal "Unsafe archive name in ${sidecar##*/}"
  [[ "$referenced" == "${archive##*/}" ]] || log_fatal "Checksum sidecar references an unexpected archive: $referenced"
  actual=$(sha256sum -- "$archive")
  actual="${actual%% *}"
  [[ "$actual" == "${expected,,}" ]] || log_fatal "Checksum mismatch: ${archive##*/}"
  log_info "Checksum verified: ${archive##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_entries
#   Rejects æbsolute or pærent-træversæl pæths before extræction
#   Ærguments:
#     $1 - compressed tær ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_tar_entries() {
  local archive="$1"
  local entry=""
  local clean=""

  while IFS= read -r entry; do
    clean="${entry#./}"
    [[ "$clean" != /* ]] || log_fatal "Archive contains an absolute path: $entry"
    case "/$clean/" in
      */../*)
        log_fatal "Archive contains parent traversal: $entry"
        ;;
    esac
  done < <(zstd -d -q --stdout "$archive" | LC_ALL=C tar --list --absolute-names --quoting-style=escape --file=-)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_tar_entry_types
#   Rejects links ænd speciæl files so no link tærget cæn escæpe stæging
#   Ærguments:
#     $1 - compressed tær ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_tar_entry_types() {
  local archive="$1"
  local listing=""
  local entry_type=""

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
# FUNCTION: validate_tar_archive
#   Verifies checksum, compression streæm ænd tær entry pæths
#   Ærguments:
#     $1 - compressed tær ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_tar_archive() {
  local archive="$1"
  verify_checksum "$archive"
  zstd -t -q "$archive" || log_fatal "Corrupt zstd archive: ${archive##*/}"
  zstd -d -q --stdout "$archive" | tar -tf - > /dev/null || log_fatal "Invalid tar archive: ${archive##*/}"
  validate_tar_entries "$archive"
  validate_tar_entry_types "$archive"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_incremental_chain
#   Ensures incrementæl sequences stært æt 01 ænd hæve no gæps
#   Ærguments:
#     $1 - physicæl full bæckup ID
#ææææææææææææææææææææææææææææææææææ
validate_incremental_chain() {
  local full_id="$1"
  local expected=1
  local archive=""
  local name=""
  local sequence=""

  for archive in "${RESTORE_CHAIN[@]:1}"; do
    name="${archive##*/}"
    sequence="${name%.zst}"
    sequence="${sequence##*_}"
    [[ "$sequence" =~ ^[0-9]{1,9}$ ]] || log_fatal "Invalid incremental sequence in archive name: $name"
    if (( 10#$sequence != expected )); then
      log_fatal "Incremental chain for $full_id is incomplete at sequence $(printf '%02d' "$expected")"
    fi
    expected=$((expected + 1))
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: set_bundle_expected_artifacts
#   Derives the only permitted dætæbæse entry for one mænifest
#   Ærguments:
#     $1 - bundle mænifest pæth
#ææææææææææææææææææææææææææææææææææ
set_bundle_expected_artifacts() {
  local manifest_name="${1##*/}"
  local bundle_id=""

  BUNDLE_DATABASE_ARCHIVE=""
  if [[ "$manifest_name" =~ ^bundle_full_([0-9]{8}_[0-9]{1,9})\.sha256$ ]]; then
    bundle_id="${BASH_REMATCH[1]}"
    BUNDLE_DATABASE_ARCHIVE="full_${bundle_id}.zst"
  elif [[ "$manifest_name" =~ ^bundle_incremental_([0-9]{8}_[0-9]{1,9}_[0-9]{1,9})\.sha256$ ]]; then
    bundle_id="${BASH_REMATCH[1]}"
    BUNDLE_DATABASE_ARCHIVE="incremental_${bundle_id}.zst"
  elif [[ "$manifest_name" =~ ^bundle_dump_([0-9]{8}_[0-9]{1,9})\.sha256$ ]]; then
    bundle_id="${BASH_REMATCH[1]}"
    BUNDLE_DATABASE_ARCHIVE="dump_${bundle_id}.sql.zst"
  else
    log_fatal "Invalid bundle manifest name: $manifest_name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_manifest_line
#   Pærses one strict `sha256sum` line ænd exposes its checksum ænd filenæme
#   Ærguments:
#     $1 - mænifest line
#     $2 - mænifest filenæme for errors
#     $3 - one-bæsed line number
#ææææææææææææææææææææææææææææææææææ
validate_manifest_line() {
  local line="$1"
  local manifest_name="$2"
  local line_number="$3"

  [[ "$line" =~ ^([a-fA-F0-9]{64})\ \ ([A-Za-z0-9][A-Za-z0-9._-]*)$ ]] || log_fatal "Invalid bundle manifest line ${line_number} in $manifest_name"
  MANIFEST_ENTRY_CHECKSUM="${BASH_REMATCH[1],,}"
  MANIFEST_ENTRY_NAME="${BASH_REMATCH[2]}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_bundle_manifest
#   Vælidætes one strict bundle mænifest ænd every referenced ærchive hæsh
#   Ærguments:
#     $1 - bundle mænifest pæth
#     $2 - selected restore ærchive pæth
#ææææææææææææææææææææææææææææææææææ
validate_bundle_manifest() {
  local manifest="$1"
  local selected_archive="$2"
  local directory="${manifest%/*}"
  local manifest_name="${manifest##*/}"
  local selected_name="${selected_archive##*/}"
  local line=""
  local line_number=0
  local entry_path=""
  local actual=""
  local database_entries=0

  [[ -f "$manifest" && ! -L "$manifest" ]] || log_fatal "Bundle manifest must be a regular non-symlink file: $manifest_name"
  [[ "${selected_archive%/*}" == "$directory" ]] || log_fatal "Bundle manifest and selected archive must share one snapshot directory"
  set_bundle_expected_artifacts "$manifest"
  [[ "$selected_name" == "$BUNDLE_DATABASE_ARCHIVE" ]] || log_fatal "Bundle manifest $manifest_name does not match selected database archive $selected_name"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    validate_manifest_line "$line" "$manifest_name" "$line_number"
    case "$MANIFEST_ENTRY_NAME" in
      "$BUNDLE_DATABASE_ARCHIVE")
        database_entries=$((database_entries + 1))
        (( database_entries == 1 )) || log_fatal "Duplicate database entry in bundle manifest: $manifest_name"
        ;;
      *)
        log_fatal "Unexpected archive in bundle manifest $manifest_name: $MANIFEST_ENTRY_NAME"
        ;;
    esac
    entry_path="$directory/$MANIFEST_ENTRY_NAME"
    [[ -f "$entry_path" && ! -L "$entry_path" ]] || log_fatal "Bundle archive must be a regular non-symlink file: $MANIFEST_ENTRY_NAME"
    actual=$(sha256sum -- "$entry_path")
    actual="${actual%% *}"
    [[ "$actual" == "$MANIFEST_ENTRY_CHECKSUM" ]] || log_fatal "Bundle manifest checksum mismatch: $MANIFEST_ENTRY_NAME"
    verify_checksum "$entry_path"
  done < "$manifest"

  (( database_entries == 1 )) || log_fatal "Bundle manifest does not contain its database archive: $manifest_name"
  cmp -s -- "$manifest" <(
    cd -- "$directory" && sha256sum "$BUNDLE_DATABASE_ARCHIVE"
  ) || log_fatal "Bundle manifest is not canonical and newline-terminated: $manifest_name"
  log_info "Bundle manifest verified: $manifest_name"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_bundle_manifests
#   Vælidætes the one-to-one mænifest mætching every selected restore ærchive
#ææææææææææææææææææææææææææææææææææ
validate_bundle_manifests() {
  local index=0

  (( ${#RESTORE_CHAIN[@]} == ${#BUNDLE_MANIFESTS[@]} )) || log_fatal "Every selected archive requires exactly one bundle manifest"
  while (( index < ${#RESTORE_CHAIN[@]} )); do
    validate_bundle_manifest "${BUNDLE_MANIFESTS[$index]}" "${RESTORE_CHAIN[$index]}"
    index=$((index + 1))
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- RESTORE SELECTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_restore_candidate_inventory
#   Rejects every matching symlink or non-regulær restore node before selection
#   Ærguments:
#     $1 - cændidæte kind (`physical` or `dump`)
#ææææææææææææææææææææææææææææææææææ
validate_restore_candidate_inventory() {
  local kind="$1"
  local candidates=()
  local candidate=""
  local name=""

  case "$kind" in
    physical)
      capture_restore_inventory candidates none "$RESTORE_DIR" -xdev -mindepth 1 -maxdepth 1 \( -name 'full_*.zst' -o -name 'incremental_*.zst' \)
      ;;
    dump)
      capture_restore_inventory candidates none "$RESTORE_DIR" -xdev -mindepth 1 -maxdepth 1 -name 'dump_*.sql.zst'
      ;;
    *)
      log_fatal "Unsupported restore inventory kind: $kind"
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    name="${candidate##*/}"
    [[ "${candidate%/*}" == "$RESTORE_DIR" ]] || log_fatal "Restore candidate escaped $RESTORE_DIR: $candidate"
    [[ -f "$candidate" && ! -L "$candidate" ]] || log_fatal "Restore candidate must be a regular non-symlink file: $name"
    if [[ "$kind" == "physical" ]]; then
      [[ "$name" =~ ^full_[0-9]{8}_[0-9]{1,9}\.zst$ || "$name" =~ ^incremental_[0-9]{8}_[0-9]{1,9}_[0-9]{1,9}\.zst$ ]] || log_fatal "Physical restore candidate has an invalid name: $name"
    else
      [[ "$name" =~ ^dump_[0-9]{8}_[0-9]{1,9}\.sql\.zst$ ]] || log_fatal "Logical restore candidate has an invalid name: $name"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: find_restore_chain
#   Selects one full bæckup ænd its contiguous incrementæls
#ææææææææææææææææææææææææææææææææææ
find_restore_chain() {
  local full=""
  local full_id=""
  local incrementals=()
  local fulls=()

  validate_restore_candidate_inventory physical

  if [[ -n "$MARIADB_RESTORE_BACKUP_ID" ]]; then
    [[ "$MARIADB_RESTORE_BACKUP_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid requested physical backup ID"
    full="$RESTORE_DIR/full_${MARIADB_RESTORE_BACKUP_ID}.zst"
    [[ -f "$full" && ! -L "$full" ]] || log_fatal "Requested full backup not found or unsafe: ${full##*/}"
  else
    capture_restore_inventory fulls version "$RESTORE_DIR" -xdev -mindepth 1 -maxdepth 1 -name 'full_*.zst'
    (( ${#fulls[@]} > 0 )) || log_fatal "No physical full backup found in $RESTORE_DIR"
    full="${fulls[-1]}"
  fi

  full_id="${full##*/}"
  full_id="${full_id#full_}"
  full_id="${full_id%.zst}"
  [[ "$full_id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid physical backup ID: $full_id"
  capture_restore_inventory incrementals version "$RESTORE_DIR" -xdev -mindepth 1 -maxdepth 1 -name "incremental_${full_id}_*.zst"
  RESTORE_CHAIN=("$full" "${incrementals[@]}")
  validate_incremental_chain "$full_id"

  log_info "Selected physical restore chain:"
  local archive=""
  for archive in "${RESTORE_CHAIN[@]}"; do
    log_info " - ${archive##*/}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_dump_archive
#   Selects one ræw `.sql.zst` dump
#ææææææææææææææææææææææææææææææææææ
select_dump_archive() {
  local archive=""
  local dumps=()
  validate_restore_candidate_inventory dump
  if [[ -n "$MARIADB_RESTORE_BACKUP_ID" ]]; then
    [[ "$MARIADB_RESTORE_BACKUP_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]] || log_fatal "Invalid requested logical backup ID"
    archive="$RESTORE_DIR/dump_${MARIADB_RESTORE_BACKUP_ID}.sql.zst"
    [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Requested logical dump not found or unsafe: ${archive##*/}"
  else
    capture_restore_inventory dumps version "$RESTORE_DIR" -xdev -mindepth 1 -maxdepth 1 -name 'dump_*.sql.zst'
    (( ${#dumps[@]} > 0 )) || log_fatal "No logical dump found in $RESTORE_DIR"
    archive="${dumps[-1]}"
  fi
  [[ "${archive##*/}" =~ ^dump_[0-9]{8}_[0-9]{1,9}\.sql\.zst$ ]] || log_fatal "Invalid logical dump archive name"
  RESTORE_CHAIN=("$archive")
  log_info "Selected logical dump: ${archive##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_bundle_manifests
#   Selects the mændætory bundle mænifest mætching eæch restore ærchive
#ææææææææææææææææææææææææææææææææææ
select_bundle_manifests() {
  local archive=""
  local archive_name=""
  local bundle_name=""
  local manifest=""

  BUNDLE_MANIFESTS=()
  for archive in "${RESTORE_CHAIN[@]}"; do
    archive_name="${archive##*/}"
    if [[ "$archive_name" =~ ^full_([0-9]{8}_[0-9]{1,9})\.zst$ ]]; then
      bundle_name="full_${BASH_REMATCH[1]}"
    elif [[ "$archive_name" =~ ^incremental_([0-9]{8}_[0-9]{1,9}_[0-9]{1,9})\.zst$ ]]; then
      bundle_name="incremental_${BASH_REMATCH[1]}"
    elif [[ "$archive_name" =~ ^dump_([0-9]{8}_[0-9]{1,9})\.sql\.zst$ ]]; then
      bundle_name="dump_${BASH_REMATCH[1]}"
    else
      log_fatal "Cannot derive bundle manifest for selected archive: $archive_name"
    fi
    manifest="$RESTORE_DIR/bundle_${bundle_name}.sha256"
    [[ -f "$manifest" && ! -L "$manifest" ]] || log_fatal "Required bundle manifest is missing or unsafe: ${manifest##*/}"
    BUNDLE_MANIFESTS+=("$manifest")
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_snapshot_artifact
#   Copies one stæble top-level restore ærchive into the privæte workspæce
#   Ærguments:
#     $1 - originæl ærchive or sidecær pæth
#     $2 - privæte snæpshot directory
#ææææææææææææææææææææææææææææææææææ
copy_snapshot_artifact() {
  local source="$1"
  local snapshot_dir="$2"
  local destination="$snapshot_dir/${source##*/}"
  local source_identity=""
  local current_identity=""

  [[ "${source%/*}" == "$RESTORE_DIR" ]] || log_fatal "Refusing to snapshot artifact outside $RESTORE_DIR: $source"
  [[ -f "$source" && ! -L "$source" ]] || log_fatal "Snapshot source must be a regular non-symlink file: ${source##*/}"
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ -f "$destination" && ! -L "$destination" ]] || log_fatal "Unsafe duplicate snapshot artifact: ${destination##*/}"
    return 0
  fi
  source_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot inspect snapshot source: ${source##*/}"
  run_restore_child cp --reflink=never --no-preserve=mode,ownership,timestamps -- "$source" "$destination" || log_fatal "Cannot snapshot restore artifact: ${source##*/}"
  current_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot re-inspect snapshot source: ${source##*/}"
  [[ "$current_identity" == "$source_identity" ]] || log_fatal "Restore artifact changed while being copied: ${source##*/}"
  [[ -f "$destination" && ! -L "$destination" ]] || log_fatal "Unsafe copied restore artifact: ${destination##*/}"
  chmod 0600 -- "$destination" || log_fatal "Cannot restrict copied restore artifact: ${destination##*/}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: snapshot_selected_artifacts
#   Copies mænifests ænd every referenced ærchive before vælidætion or use
#ææææææææææææææææææææææææææææææææææ
snapshot_selected_artifacts() {
  local snapshot_dir="$TMP_BASE/artifacts"
  local manifest=""
  local snapshot_manifest=""
  local line=""
  local line_number=0
  local source=""
  local sidecar=""
  local archive=""

  mkdir -- "$snapshot_dir" || log_fatal "Cannot create private restore-artifact snapshot"
  chmod 0700 -- "$snapshot_dir" || log_fatal "Cannot restrict restore-artifact snapshot"
  for manifest in "${ORIGINAL_BUNDLE_MANIFESTS[@]}"; do
    copy_snapshot_artifact "$manifest" "$snapshot_dir"
  done

  BUNDLE_MANIFESTS=()
  for manifest in "${ORIGINAL_BUNDLE_MANIFESTS[@]}"; do
    snapshot_manifest="$snapshot_dir/${manifest##*/}"
    BUNDLE_MANIFESTS+=("$snapshot_manifest")
    set_bundle_expected_artifacts "$snapshot_manifest"
    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_number=$((line_number + 1))
      validate_manifest_line "$line" "${snapshot_manifest##*/}" "$line_number"
      case "$MANIFEST_ENTRY_NAME" in
        "$BUNDLE_DATABASE_ARCHIVE")
          ;;
        *)
          log_fatal "Unexpected archive in bundle manifest ${snapshot_manifest##*/}: $MANIFEST_ENTRY_NAME"
          ;;
      esac
      source="$RESTORE_DIR/$MANIFEST_ENTRY_NAME"
      copy_snapshot_artifact "$source" "$snapshot_dir"
      sidecar="${source}.sha256"
      if [[ -e "$sidecar" || -L "$sidecar" ]]; then
        copy_snapshot_artifact "$sidecar" "$snapshot_dir"
      fi
    done < "$snapshot_manifest"
  done

  RESTORE_CHAIN=()
  for archive in "${ORIGINAL_RESTORE_CHAIN[@]}"; do
    archive="$snapshot_dir/${archive##*/}"
    [[ -f "$archive" && ! -L "$archive" ]] || log_fatal "Bundle manifest does not select restore archive: ${archive##*/}"
    RESTORE_CHAIN+=("$archive")
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_selected_artifacts
#   Preserves originæls ænd vælidætes only privæte copies outside dry-run
#ææææææææææææææææææææææææææææææææææ
prepare_selected_artifacts() {
  select_bundle_manifests
  ORIGINAL_RESTORE_CHAIN=("${RESTORE_CHAIN[@]}")
  ORIGINAL_BUNDLE_MANIFESTS=("${BUNDLE_MANIFESTS[@]}")
  if [[ "$MARIADB_RESTORE_DRY_RUN" != "true" ]]; then
    create_tmp_base
    snapshot_selected_artifacts
  fi
  validate_bundle_manifests
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DÆTÆBÆSE STÆTE CHECKS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: database_is_alive
#   Detects æ live server even when æuthenticætion is unævæilæble or denied
#ææææææææææææææææææææææææææææææææææ
database_is_alive() {
  mariadb-admin --no-defaults ping \
    --silent \
    --connect-timeout=5 \
    --protocol=tcp \
    --host="$MARIADB_DB_HOST" \
    --user='__mariadb_maintenance_liveness_probe__' \
    > /dev/null 2>&1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_database_stopped
#   Prevents physicæl copy-bæck while MæriæDB is running
#ææææææææææææææææææææææææææææææææææ
require_database_stopped() {
  [[ "$MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED" == "true" ]] || log_fatal "Physical restore requires explicit MARIADB_RESTORE_CONFIRM_DATABASE_STOPPED=true after stopping every database writer"
  if database_is_alive; then
    log_fatal "MariaDB is reachable. Stop it before a physical restore."
  fi
  if pgrep -x mariadbd > /dev/null; then
    log_fatal "A local mariadbd process is running. Aborting physical restore."
  fi
  log_warn "MariaDB did not answer the alive probe; proceeding only because the operator supplied explicit stop confirmation"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_database_running
#   Requires æ running MæriæDB endpoint for logicæl dump import
#ææææææææææææææææææææææææææææææææææ
require_database_running() {
  [[ -r "$MARIADB_ROOT_PASSWORD_FILE" ]] || log_fatal "Root password secret is not readable: $MARIADB_ROOT_PASSWORD_FILE"
  database_is_alive || log_fatal "MariaDB is unreachable; refusing logical dump restore"
  mariadb \
    "$MARIADB_CLIENT_OPTION_ARGUMENT" \
    --batch \
    --skip-column-names \
    --connect-timeout=5 \
    --host="$MARIADB_DB_HOST" \
    --user="$MARIADB_ROOT_USER" \
    --execute='SELECT 1' > /dev/null 2>&1 || log_fatal "MariaDB authentication check failed; refusing logical dump restore"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: database_exists
#   Checks whether the configured restore target exists without interpolating its name into SQL
#ææææææææææææææææææææææææææææææææææ
database_exists() {
  local databases=""
  local database=""

  if ! databases="$(mariadb \
      "$MARIADB_CLIENT_OPTION_ARGUMENT" \
      --batch \
      --skip-column-names \
      --connect-timeout=5 \
      --host="$MARIADB_DB_HOST" \
      --user="$MARIADB_ROOT_USER" \
      --execute='SHOW DATABASES')"; then
    log_fatal "Could not inspect MariaDB databases before logical restore"
  fi
  while IFS= read -r database; do
    [[ "$database" == "$MARIADB_DATABASE" ]] && return 0
  done <<< "$databases"
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: count_database_objects
#   Counts tables, views, routines, triggers, ænd events in the configured target
#ææææææææææææææææææææææææææææææææææ
count_database_objects() {
  local count=""

  if ! database_exists; then
    printf '0\n'
    return 0
  fi
  if ! count="$(mariadb \
      "$MARIADB_CLIENT_OPTION_ARGUMENT" \
      --batch \
      --skip-column-names \
      --connect-timeout=5 \
      --host="$MARIADB_DB_HOST" \
      --user="$MARIADB_ROOT_USER" \
      --database="$MARIADB_DATABASE" \
      --execute='SELECT
        (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()) +
        (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()) +
        (SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE()) +
        (SELECT COUNT(*) FROM information_schema.EVENTS WHERE EVENT_SCHEMA = DATABASE())')"; then
    log_fatal "Could not inspect logical restore target $MARIADB_DATABASE"
  fi
  [[ "$count" =~ ^[0-9]+$ ]] || log_fatal "Logical restore target inspection returned an invalid object count"
  printf '%s\n' "$count"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_dump_target
#   Requires æ cleæn target or explicitly removes the configured dætæbæse before import
#ææææææææææææææææææææææææææææææææææ
prepare_dump_target() {
  local object_count=""
  local target_exists=false

  database_exists && target_exists=true
  object_count="$(count_database_objects)"
  log_info "Logical restore target $MARIADB_DATABASE exists=${target_exists} and contains ${object_count} object(s)"

  if [[ "$MARIADB_RESTORE_RECREATE_DATABASE" == "false" ]]; then
    (( object_count == 0 )) || log_fatal "Logical restore target $MARIADB_DATABASE is not empty; no database changes were applied. Stop every writer and set MARIADB_RESTORE_RECREATE_DATABASE=true plus MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true for an explicit replacement."
    return 0
  fi

  [[ "$MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT" == "true" ]] || log_fatal "Database replacement requires MARIADB_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true after every writer is stopped"
  if [[ "$MARIADB_RESTORE_DRY_RUN" == "true" ]]; then
    if [[ "$target_exists" == "true" ]]; then
      log_dry "Would drop $MARIADB_DATABASE; the verified dump would recreate and populate it"
    else
      log_dry "Target $MARIADB_DATABASE does not exist; the verified dump would create and populate it"
    fi
    return 0
  fi

  if [[ "$target_exists" == "true" ]]; then
    log_warn "Replacing database $MARIADB_DATABASE; every existing object will be removed"
    mariadb-admin \
      "$MARIADB_CLIENT_OPTION_ARGUMENT" \
      --connect-timeout=5 \
      --host="$MARIADB_DB_HOST" \
      --user="$MARIADB_ROOT_USER" \
      --force \
      drop "$MARIADB_DATABASE" || log_fatal "Failed to drop logical restore target $MARIADB_DATABASE"
    database_exists && log_fatal "Logical restore target $MARIADB_DATABASE still exists after drop"
    log_ok "Database $MARIADB_DATABASE removed; the verified dump will recreate it"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: test_database_dir_writable
#   Tests the physicæl restore tærget without touching it during dry-run
#ææææææææææææææææææææææææææææææææææ
test_database_dir_writable() {
  local testfile=""
  local testfile_identity=""
  local current_identity=""
  is_safe_data_dir || log_fatal "Unsafe MariaDB data directory: $MARIADB_DIR"
  [[ -d "$MARIADB_DIR" ]] || log_fatal "MariaDB data directory does not exist: $MARIADB_DIR"
  testfile=$(mktemp "$MARIADB_DIR/.restore-writetest.XXXXXX") || log_fatal "MariaDB data directory is not writable: $MARIADB_DIR"
  [[ -f "$testfile" && ! -L "$testfile" ]] || log_fatal "Unsafe MariaDB writability-test artifact"
  testfile_identity=$(stat -c '%d:%i' -- "$testfile") || log_fatal "Cannot inspect MariaDB writability-test artifact"
  current_identity=$(stat -c '%d:%i' -- "$testfile") || log_fatal "Cannot re-inspect MariaDB writability-test artifact"
  [[ "$current_identity" == "$testfile_identity" && -f "$testfile" && ! -L "$testfile" ]] || log_fatal "MariaDB writability-test artifact changed concurrently"
  rm -f -- "$testfile"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- PHYSICÆL RESTORE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_node_identity
#   Returns æ stæble device, inode, ænd file-type identity without dereferencing links
#   Ærguments:
#     $1 - filesystem node
#ææææææææææææææææææææææææææææææææææ
restore_node_identity() {
  stat -c '%d:%i:%f' -- "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_restore_identity
#   Vælidætes the device, inode, ænd file-type journæl formæt
#   Ærguments:
#     $1 - encoded filesystem-node identity
#ææææææææææææææææææææææææææææææææææ
is_restore_identity() {
  [[ "$1" =~ ^[0-9]+:[0-9]+:[0-9a-fA-F]+$ ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: clear_restore_transaction_plan
#   Clears in-memory inode plæns only æfter persistent recovery is complete
#ææææææææææææææææææææææææææææææææææ
clear_restore_transaction_plan() {
  RESTORE_JOURNAL_STATE=""
  RESTORE_OLD_SOURCES=()
  RESTORE_OLD_DESTINATIONS=()
  RESTORE_OLD_IDENTITIES=()
  RESTORE_NEW_SOURCES=()
  RESTORE_NEW_DESTINATIONS=()
  RESTORE_NEW_IDENTITIES=()
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_node_matches
#   Tests one pæth ægæinst its pre-journæled inode identity
#   Ærguments:
#     $1 - filesystem node
#     $2 - expected identity
#ææææææææææææææææææææææææææææææææææ
restore_node_matches() {
  local path="$1"
  local expected="$2"
  local current=""
  [[ -e "$path" || -L "$path" ]] || return 1
  current=$(restore_node_identity "$path") || return 1
  [[ "$current" == "$expected" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_restore_basename
#   Rejects empty, pærent, slash, or control-chæræcter journæl næmes
#   Ærguments:
#     $1 - decoded top-level bæsenæme
#ææææææææææææææææææææææææææææææææææ
validate_restore_basename() {
  local name="$1"
  [[ -n "$name" && "$name" != "." && "$name" != ".." && "$name" != */* && ! "$name" =~ [[:cntrl:]] ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: encode_restore_basename
#   Encodes one top-level næme into æ single journæl field
#   Ærguments:
#     $1 - top-level bæsenæme
#ææææææææææææææææææææææææææææææææææ
encode_restore_basename() {
  validate_restore_basename "$1" || log_fatal "Unsafe top-level MariaDB data name cannot be journaled"
  printf '%s' "$1" | base64 -w 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: decode_restore_basename
#   Decodes ænd vælidætes one journæl næme field
#   Ærguments:
#     $1 - bæse64 journæl field
#ææææææææææææææææææææææææææææææææææ
decode_restore_basename() {
  local encoded="$1"
  local decoded=""
  [[ "$encoded" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
  decoded=$(printf '%s' "$encoded" | base64 -d 2>/dev/null) || return 1
  validate_restore_basename "$decoded" || return 1
  printf '%s\n' "$decoded"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_restore_transaction_dir
#   Removes only one inode-pinned stæge/quæræntine directory without crossing mounts
#   Ærguments:
#     $1 - direct transaction child of the dætæ root
#     $2 - expected directory identity, or `pending` before first journæl updæte
#ææææææææææææææææææææææææææææææææææ
remove_restore_transaction_dir() {
  local path="$1"
  local expected="$2"
  local name=""
  local current=""
  local mount_target=""
  local mount_targets=()
  local pending_nodes=()

  [[ -n "$path" ]] || return 0
  name="${path##*/}"
  [[ "${path%/*}" == "$MARIADB_DIR" && "$name" =~ ^\.mariadb-restore-(stage|old)\.[A-Za-z0-9._-]+$ ]] || {
    log_error "Refusing unsafe MariaDB transaction cleanup path: $path"
    return 1
  }
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi
  [[ -d "$path" && ! -L "$path" ]] || {
    log_error "MariaDB transaction path is not a regular directory: $path"
    return 1
  }
  current=$(restore_node_identity "$path") || return 1
  [[ "$expected" == "pending" || -z "$expected" || "$current" == "$expected" ]] || {
    log_error "MariaDB transaction directory identity changed: $path"
    return 1
  }
  if [[ "$expected" == "pending" ]]; then
    capture_restore_inventory pending_nodes none "$path" -xdev -mindepth 1 -maxdepth 1
    if (( ${#pending_nodes[@]} > 0 )); then
      log_error "Pending MariaDB transaction directory is unexpectedly non-empty; preserving it: $path"
      return 1
    fi
  fi
  capture_mount_inventory mount_targets "$path" || {
    log_error "Cannot inspect nested mounts below $path"
    return 1
  }
  for mount_target in "${mount_targets[@]}"; do
    [[ -z "$mount_target" ]] || {
      log_error "MariaDB transaction directory contains a mount: $mount_target"
      return 1
    }
  done
  run_restore_child find "$path" -xdev -depth -mindepth 1 -delete || return 1
  current=$(restore_node_identity "$path") || return 1
  [[ "$expected" == "pending" || -z "$expected" || "$current" == "$expected" ]] || return 1
  rmdir -- "$path" || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_restore_journal
#   Ætomicælly persists the complete top-level switch plæn inside the dætæ volume
#   Ærguments:
#     $1 - transaction stæte (`initializing`, `staging`, `switching`, or `committed`)
#ææææææææææææææææææææææææææææææææææ
write_restore_journal() {
  local state="$1"
  local temporary=""
  local temporary_identity=""
  local current_identity=""
  local index=0
  local name=""
  local move_status=0

  [[ "$state" == "initializing" || "$state" == "staging" || "$state" == "switching" || "$state" == "committed" ]] || log_fatal "Invalid MariaDB restore-journal state: $state"
  is_safe_data_dir || log_fatal "MariaDB data directory changed before journal publication"
  RESTORE_SWITCH_JOURNAL="$MARIADB_DIR/.mariadb-restore-journal"
  if [[ -e "$RESTORE_SWITCH_JOURNAL" || -L "$RESTORE_SWITCH_JOURNAL" ]]; then
    [[ -f "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]] || log_fatal "Persistent MariaDB restore journal became unsafe"
  fi
  temporary=$(mktemp "$MARIADB_DIR/.mariadb-restore-journal.tmp.XXXXXX") || log_fatal "Cannot create temporary MariaDB restore journal"
  temporary_identity=$(restore_node_identity "$temporary") || log_fatal "Cannot inspect temporary MariaDB restore journal"
  {
    printf 'MARIADB_RESTORE_JOURNAL_V1\n'
    printf 'STATE\t%s\n' "$state"
    printf 'DATA\t%s\n' "$MARIADB_DATA_IDENTITY"
    if [[ -n "$RESTORE_STAGE_DIR" ]]; then
      printf 'STAGE\t%s\t%s\n' "$(encode_restore_basename "${RESTORE_STAGE_DIR##*/}")" "${RESTORE_STAGE_IDENTITY:-pending}"
    else
      printf 'STAGE\t-\t-\n'
    fi
    if [[ -n "$RESTORE_OLD_DIR" ]]; then
      printf 'OLD_DIR\t%s\t%s\n' "$(encode_restore_basename "${RESTORE_OLD_DIR##*/}")" "${RESTORE_OLD_IDENTITY:-pending}"
    else
      printf 'OLD_DIR\t-\t-\n'
    fi
    for index in "${!RESTORE_OLD_SOURCES[@]}"; do
      name="${RESTORE_OLD_SOURCES[$index]##*/}"
      printf 'OLD_ENTRY\t%s\t%s\n' "$(encode_restore_basename "$name")" "${RESTORE_OLD_IDENTITIES[$index]}"
    done
    for index in "${!RESTORE_NEW_SOURCES[@]}"; do
      name="${RESTORE_NEW_SOURCES[$index]##*/}"
      printf 'NEW_ENTRY\t%s\t%s\n' "$(encode_restore_basename "$name")" "${RESTORE_NEW_IDENTITIES[$index]}"
    done
    printf 'END\n'
  } >"$temporary" || log_fatal "Cannot write temporary MariaDB restore journal"
  chmod 0600 -- "$temporary" || log_fatal "Cannot restrict temporary MariaDB restore journal"
  sync -f -- "$temporary" || log_fatal "Cannot durably flush temporary MariaDB restore journal"
  current_identity=$(restore_node_identity "$temporary") || log_fatal "Cannot re-inspect temporary MariaDB restore journal"
  [[ "$current_identity" == "$temporary_identity" ]] || log_fatal "Temporary MariaDB restore journal changed before publication"
  mv -T -- "$temporary" "$RESTORE_SWITCH_JOURNAL" || move_status=$?
  if [[ ! -e "$temporary" && ! -L "$temporary" && -f "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]]; then
    current_identity=$(restore_node_identity "$RESTORE_SWITCH_JOURNAL") || log_fatal "Cannot inspect published MariaDB restore journal"
    [[ "$current_identity" == "$temporary_identity" ]] || log_fatal "Published MariaDB restore journal has an unexpected identity"
  else
    log_fatal "Cannot publish persistent MariaDB restore journal"
  fi
  (( move_status == 0 )) || log_warn "Journal rename reported status $move_status after the expected inode was published"
  sync -f -- "$RESTORE_SWITCH_JOURNAL" || log_fatal "Cannot durably flush MariaDB restore journal"
  sync -f -- "$MARIADB_DIR" || log_fatal "Cannot durably flush MariaDB data-directory metadata"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_restore_journal
#   Pærses the persistent journæl without executing its contents
#ææææææææææææææææææææææææææææææææææ
load_restore_journal() {
  local header=""
  local kind=""
  local field1=""
  local field2=""
  local extra=""
  local state=""
  local data_identity=""
  local stage_name=""
  local old_name=""
  local decoded=""
  local existing=""
  local line_number=0
  local saw_end=false
  local saw_state=false
  local saw_data=false
  local saw_stage=false
  local saw_old=false

  RESTORE_SWITCH_JOURNAL="$MARIADB_DIR/.mariadb-restore-journal"
  [[ -f "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]] || log_fatal "Persistent MariaDB restore journal is missing or unsafe"
  IFS= read -r header <"$RESTORE_SWITCH_JOURNAL" || log_fatal "Cannot read persistent MariaDB restore journal"
  [[ "$header" == "MARIADB_RESTORE_JOURNAL_V1" ]] || log_fatal "Unsupported or corrupt MariaDB restore journal header"

  RESTORE_OLD_SOURCES=()
  RESTORE_OLD_DESTINATIONS=()
  RESTORE_OLD_IDENTITIES=()
  RESTORE_NEW_SOURCES=()
  RESTORE_NEW_DESTINATIONS=()
  RESTORE_NEW_IDENTITIES=()
  while IFS=$'\t' read -r kind field1 field2 extra; do
    line_number=$((line_number + 1))
    [[ -z "$extra" ]] || log_fatal "MariaDB restore journal contains an unexpected field"
    if [[ "$saw_end" == "true" ]]; then
      log_fatal "MariaDB restore journal contains data after its terminator"
    fi
    case "$kind" in
      MARIADB_RESTORE_JOURNAL_V1)
        [[ "$line_number" == "1" && -z "$field1" && -z "$field2" ]] || log_fatal "Duplicate or misplaced MariaDB restore-journal header"
        continue
        ;;
      STATE)
        [[ "$saw_state" == "false" && -n "$field1" && -z "$field2" ]] || log_fatal "Duplicate or malformed restore-journal state"
        state="$field1"
        saw_state=true
        ;;
      DATA)
        [[ "$saw_data" == "false" && -n "$field1" && -z "$field2" ]] || log_fatal "Duplicate or malformed restore-journal data identity"
        data_identity="$field1"
        saw_data=true
        ;;
      STAGE)
        [[ "$saw_stage" == "false" && -n "$field1" && -n "$field2" ]] || log_fatal "Duplicate or malformed restore-journal stage"
        if [[ "$field1" != "-" ]]; then
          stage_name=$(decode_restore_basename "$field1") || log_fatal "Invalid stage name in MariaDB restore journal"
          RESTORE_STAGE_DIR="$MARIADB_DIR/$stage_name"
          RESTORE_STAGE_IDENTITY="$field2"
        else
          [[ "$field2" == "-" ]] || log_fatal "Malformed empty stage in MariaDB restore journal"
          RESTORE_STAGE_DIR=""
          RESTORE_STAGE_IDENTITY=""
        fi
        saw_stage=true
        ;;
      OLD_DIR)
        [[ "$saw_old" == "false" && -n "$field1" && -n "$field2" ]] || log_fatal "Duplicate or malformed restore-journal old directory"
        if [[ "$field1" != "-" ]]; then
          old_name=$(decode_restore_basename "$field1") || log_fatal "Invalid old-directory name in MariaDB restore journal"
          RESTORE_OLD_DIR="$MARIADB_DIR/$old_name"
          RESTORE_OLD_IDENTITY="$field2"
        else
          [[ "$field2" == "-" ]] || log_fatal "Malformed empty old directory in MariaDB restore journal"
          RESTORE_OLD_DIR=""
          RESTORE_OLD_IDENTITY=""
        fi
        saw_old=true
        ;;
      OLD_ENTRY)
        [[ "$saw_old" == "true" && -n "$RESTORE_OLD_DIR" && -n "$field1" && -n "$field2" ]] || log_fatal "Malformed or out-of-order old entry in MariaDB restore journal"
        decoded=$(decode_restore_basename "$field1") || log_fatal "Invalid old-entry name in MariaDB restore journal"
        is_restore_identity "$field2" || log_fatal "Invalid old-entry identity in MariaDB restore journal"
        for existing in "${RESTORE_OLD_SOURCES[@]}"; do
          [[ "${existing##*/}" != "$decoded" ]] || log_fatal "Duplicate old-entry name in MariaDB restore journal"
        done
        RESTORE_OLD_SOURCES+=("$MARIADB_DIR/$decoded")
        RESTORE_OLD_DESTINATIONS+=("$RESTORE_OLD_DIR/$decoded")
        RESTORE_OLD_IDENTITIES+=("$field2")
        ;;
      NEW_ENTRY)
        [[ "$saw_stage" == "true" && -n "$RESTORE_STAGE_DIR" && -n "$field1" && -n "$field2" ]] || log_fatal "Malformed or out-of-order new entry in MariaDB restore journal"
        decoded=$(decode_restore_basename "$field1") || log_fatal "Invalid new-entry name in MariaDB restore journal"
        is_restore_identity "$field2" || log_fatal "Invalid new-entry identity in MariaDB restore journal"
        for existing in "${RESTORE_NEW_SOURCES[@]}"; do
          [[ "${existing##*/}" != "$decoded" ]] || log_fatal "Duplicate new-entry name in MariaDB restore journal"
        done
        RESTORE_NEW_SOURCES+=("$RESTORE_STAGE_DIR/$decoded")
        RESTORE_NEW_DESTINATIONS+=("$MARIADB_DIR/$decoded")
        RESTORE_NEW_IDENTITIES+=("$field2")
        ;;
      END)
        [[ -z "$field1" && -z "$field2" && "$saw_end" == "false" ]] || log_fatal "Malformed restore-journal terminator"
        saw_end=true
        ;;
      '')
        log_fatal "MariaDB restore journal contains an empty line"
        ;;
      *)
        log_fatal "Unknown MariaDB restore-journal record: $kind"
        ;;
    esac
  done <"$RESTORE_SWITCH_JOURNAL"

  [[ "$saw_state" == "true" && "$saw_data" == "true" && "$saw_stage" == "true" && "$saw_old" == "true" && "$saw_end" == "true" ]] || log_fatal "MariaDB restore journal is incomplete"
  [[ "$state" == "initializing" || "$state" == "staging" || "$state" == "switching" || "$state" == "committed" ]] || log_fatal "MariaDB restore journal contains an invalid state"
  [[ "$data_identity" =~ ^[0-9]+:[0-9]+$ ]] || log_fatal "MariaDB restore journal contains an invalid data-directory identity"
  [[ "$data_identity" == "$MARIADB_DATA_IDENTITY" ]] || log_fatal "MariaDB restore journal belongs to a different data-directory inode"
  if [[ -n "$RESTORE_STAGE_DIR" ]]; then
    [[ "${RESTORE_STAGE_DIR##*/}" =~ ^\.mariadb-restore-stage\.[A-Za-z0-9._-]+$ ]] || log_fatal "Unsafe stage path in MariaDB restore journal"
    [[ "$RESTORE_STAGE_IDENTITY" == "pending" ]] || is_restore_identity "$RESTORE_STAGE_IDENTITY" || log_fatal "Invalid stage identity in MariaDB restore journal"
  fi
  if [[ -n "$RESTORE_OLD_DIR" ]]; then
    [[ "${RESTORE_OLD_DIR##*/}" =~ ^\.mariadb-restore-old\.[A-Za-z0-9._-]+$ ]] || log_fatal "Unsafe old-directory path in MariaDB restore journal"
    [[ "$RESTORE_OLD_IDENTITY" == "pending" ]] || is_restore_identity "$RESTORE_OLD_IDENTITY" || log_fatal "Invalid old-directory identity in MariaDB restore journal"
  fi
  if [[ "$state" == "initializing" ]]; then
    [[ -n "$RESTORE_STAGE_DIR" && "$RESTORE_STAGE_IDENTITY" == "pending" && -z "$RESTORE_OLD_DIR" && ${#RESTORE_OLD_SOURCES[@]} -eq 0 && ${#RESTORE_NEW_SOURCES[@]} -eq 0 ]] || log_fatal "MariaDB initializing journal contains an inconsistent transaction plan"
  elif [[ "$state" == "staging" ]]; then
    [[ -n "$RESTORE_STAGE_DIR" && "$RESTORE_STAGE_IDENTITY" != "pending" && ${#RESTORE_OLD_SOURCES[@]} -eq 0 && ${#RESTORE_NEW_SOURCES[@]} -eq 0 ]] || log_fatal "MariaDB staging journal contains an inconsistent transaction plan"
  fi
  if [[ "$state" == "switching" || "$state" == "committed" ]]; then
    [[ -n "$RESTORE_STAGE_DIR" && -n "$RESTORE_OLD_DIR" && "$RESTORE_STAGE_IDENTITY" != "pending" && "$RESTORE_OLD_IDENTITY" != "pending" && ${#RESTORE_NEW_SOURCES[@]} -gt 0 ]] || log_fatal "MariaDB switch journal lacks a complete stage/old plan"
  fi
  RESTORE_JOURNAL_STATE="$state"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_restore_artifact_inventory
#   Requires every reserved top-level node to belong to the loaded transaction
#ææææææææææææææææææææææææææææææææææ
validate_restore_artifact_inventory() {
  local artifacts=()
  local artifact=""

  capture_restore_inventory artifacts none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*'
  for artifact in "${artifacts[@]}"; do
    if [[ "$artifact" == "$RESTORE_SWITCH_JOURNAL" ]]; then
      [[ -f "$artifact" && ! -L "$artifact" ]] || return 1
    elif [[ "${artifact##*/}" == .mariadb-restore-journal.tmp.* ]]; then
      [[ -f "$artifact" && ! -L "$artifact" ]] || return 1
    elif [[ -n "$RESTORE_STAGE_DIR" && "$artifact" == "$RESTORE_STAGE_DIR" ]]; then
      [[ -d "$artifact" && ! -L "$artifact" ]] || return 1
    elif [[ -n "$RESTORE_OLD_DIR" && "$artifact" == "$RESTORE_OLD_DIR" ]]; then
      [[ -d "$artifact" && ! -L "$artifact" ]] || return 1
    else
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: move_restore_node
#   Executes one no-clobber renæme ænd trusts only the verified finæl inode position
#   Ærguments:
#     $1 - source pæth
#     $2 - destinætion pæth
#     $3 - expected inode identity
#ææææææææææææææææææææææææææææææææææ
move_restore_node() {
  local source="$1"
  local destination="$2"
  local expected="$3"
  local move_status=0

  restore_node_matches "$source" "$expected" || return 1
  [[ ! -e "$destination" && ! -L "$destination" ]] || return 1
  mv -T --no-clobber -- "$source" "$destination" || move_status=$?
  if [[ ! -e "$source" && ! -L "$source" ]] && restore_node_matches "$destination" "$expected"; then
    (( move_status == 0 )) || log_warn "Rename reported status $move_status after the expected MariaDB inode reached ${destination##*/}"
    return 0
  fi
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_restore_journal_artifacts
#   Removes only the vælid persistent journæl ænd its regulær temporæry siblings
#ææææææææææææææææææææææææææææææææææ
remove_restore_journal_artifacts() {
  local artifact=""
  local artifacts=()

  capture_restore_inventory artifacts none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-journal.tmp.*'
  for artifact in "${artifacts[@]}"; do
    [[ -f "$artifact" && ! -L "$artifact" ]] || return 1
    rm -f -- "$artifact" || return 1
  done
  if [[ -e "$RESTORE_SWITCH_JOURNAL" || -L "$RESTORE_SWITCH_JOURNAL" ]]; then
    [[ -f "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]] || return 1
    rm -f -- "$RESTORE_SWITCH_JOURNAL" || return 1
  fi
  sync -f -- "$MARIADB_DIR" || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_restore_switch
#   Restores every old inode in reverse order from any pre-committed position
#ææææææææææææææææææææææææææææææææææ
rollback_restore_switch() {
  local index=0
  local source=""
  local destination=""
  local expected=""

  if [[ ${#RESTORE_NEW_SOURCES[@]} -gt 0 ]]; then
    index=$((${#RESTORE_NEW_SOURCES[@]} - 1))
    while (( index >= 0 )); do
      source="${RESTORE_NEW_SOURCES[$index]}"
      destination="${RESTORE_NEW_DESTINATIONS[$index]}"
      expected="${RESTORE_NEW_IDENTITIES[$index]}"
      if restore_node_matches "$source" "$expected"; then
        :
      elif restore_node_matches "$destination" "$expected" && [[ ! -e "$source" && ! -L "$source" ]]; then
        move_restore_node "$destination" "$source" "$expected" || return 1
      else
        return 1
      fi
      index=$((index - 1))
    done
  fi

  if [[ ${#RESTORE_OLD_SOURCES[@]} -gt 0 ]]; then
    index=$((${#RESTORE_OLD_SOURCES[@]} - 1))
    while (( index >= 0 )); do
      source="${RESTORE_OLD_SOURCES[$index]}"
      destination="${RESTORE_OLD_DESTINATIONS[$index]}"
      expected="${RESTORE_OLD_IDENTITIES[$index]}"
      if restore_node_matches "$source" "$expected" && [[ ! -e "$destination" && ! -L "$destination" ]]; then
        :
      elif restore_node_matches "$destination" "$expected" && [[ ! -e "$source" && ! -L "$source" ]]; then
        move_restore_node "$destination" "$source" "$expected" || return 1
      else
        return 1
      fi
      index=$((index - 1))
    done
  fi

  sync -f -- "$MARIADB_DIR" || return 1
  remove_restore_transaction_dir "$RESTORE_STAGE_DIR" "$RESTORE_STAGE_IDENTITY" || return 1
  remove_restore_transaction_dir "$RESTORE_OLD_DIR" "$RESTORE_OLD_IDENTITY" || return 1
  remove_restore_journal_artifacts || return 1
  RESTORE_SWITCH_ACTIVE=false
  RESTORE_STAGE_DIR=""
  RESTORE_STAGE_IDENTITY=""
  RESTORE_OLD_DIR=""
  RESTORE_OLD_IDENTITY=""
  clear_restore_transaction_plan
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: finalize_committed_restore
#   Verifies the complete new tree before removing old dætæ ænd the stært blocker
#ææææææææææææææææææææææææææææææææææ
finalize_committed_restore() {
  local index=0
  local new_index=0
  local replacement_found=false

  for index in "${!RESTORE_NEW_DESTINATIONS[@]}"; do
    restore_node_matches "${RESTORE_NEW_DESTINATIONS[$index]}" "${RESTORE_NEW_IDENTITIES[$index]}" || return 1
    [[ ! -e "${RESTORE_NEW_SOURCES[$index]}" && ! -L "${RESTORE_NEW_SOURCES[$index]}" ]] || return 1
  done
  for index in "${!RESTORE_OLD_DESTINATIONS[@]}"; do
    if [[ -e "${RESTORE_OLD_DESTINATIONS[$index]}" || -L "${RESTORE_OLD_DESTINATIONS[$index]}" ]]; then
      restore_node_matches "${RESTORE_OLD_DESTINATIONS[$index]}" "${RESTORE_OLD_IDENTITIES[$index]}" || return 1
    fi
    if [[ -e "${RESTORE_OLD_SOURCES[$index]}" || -L "${RESTORE_OLD_SOURCES[$index]}" ]]; then
      replacement_found=false
      for new_index in "${!RESTORE_NEW_DESTINATIONS[@]}"; do
        if [[ "${RESTORE_NEW_DESTINATIONS[$new_index]}" == "${RESTORE_OLD_SOURCES[$index]}" ]]; then
          replacement_found=true
          break
        fi
      done
      [[ "$replacement_found" == "true" ]] || return 1
    fi
  done
  remove_restore_transaction_dir "$RESTORE_OLD_DIR" "$RESTORE_OLD_IDENTITY" || return 1
  remove_restore_transaction_dir "$RESTORE_STAGE_DIR" "$RESTORE_STAGE_IDENTITY" || return 1
  remove_restore_journal_artifacts || return 1
  RESTORE_SWITCH_ACTIVE=false
  RESTORE_SWITCH_COMMITTED=true
  RESTORE_SWITCH_FINALIZED=true
  RESTORE_STAGE_DIR=""
  RESTORE_STAGE_IDENTITY=""
  RESTORE_OLD_DIR=""
  RESTORE_OLD_IDENTITY=""
  clear_restore_transaction_plan
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: recover_orphan_initial_journal_temps
#   Cleæns only pre-mutætion journæl temps when no other restore ærtifæct exists
#ææææææææææææææææææææææææææææææææææ
recover_orphan_initial_journal_temps() {
  local artifacts=()
  local identities=()
  local remaining=()
  local artifact=""
  local index=0

  is_safe_data_dir || return 1
  RESTORE_SWITCH_JOURNAL="$MARIADB_DIR/.mariadb-restore-journal"
  [[ ! -e "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]] || return 1
  capture_restore_inventory artifacts none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*'
  (( ${#artifacts[@]} > 0 )) || return 1

  for artifact in "${artifacts[@]}"; do
    [[ "${artifact##*/}" == .mariadb-restore-journal.tmp.* ]] || return 1
    [[ -f "$artifact" && ! -L "$artifact" ]] || return 1
    identities+=("$(restore_node_identity "$artifact")")
  done

  [[ ! -e "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]] || return 1
  for index in "${!artifacts[@]}"; do
    restore_node_matches "${artifacts[$index]}" "${identities[$index]}" || return 1
  done
  for index in "${!artifacts[@]}"; do
    rm -f -- "${artifacts[$index]}" || return 1
    [[ ! -e "${artifacts[$index]}" && ! -L "${artifacts[$index]}" ]] || return 1
  done
  sync -f -- "$MARIADB_DIR" || return 1
  capture_restore_inventory remaining none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*'
  (( ${#remaining[@]} == 0 ))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: recover_interrupted_restore
#   Recovers or finælizes one persisted transaction before æ new restore cæn stært
#ææææææææææææææææææææææææææææææææææ
recover_interrupted_restore() {
  local artifacts=()

  capture_restore_inventory artifacts none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*'
  (( ${#artifacts[@]} > 0 )) || return 0
  RESTORE_SWITCH_JOURNAL="$MARIADB_DIR/.mariadb-restore-journal"
  if [[ ! -e "$RESTORE_SWITCH_JOURNAL" && ! -L "$RESTORE_SWITCH_JOURNAL" ]]; then
    recover_orphan_initial_journal_temps || log_fatal "Restore artifacts exist without the primary MariaDB journal; ambiguous evidence was preserved"
    log_ok "Removed orphan pre-mutation MariaDB journal temporary file(s)"
    return 0
  fi
  load_restore_journal
  validate_restore_artifact_inventory || log_fatal "Reserved MariaDB restore artifacts do not match the persistent journal; evidence was preserved"
  RESTORE_SWITCH_ACTIVE=true
  if [[ "$RESTORE_JOURNAL_STATE" == "committed" ]]; then
    RESTORE_SWITCH_COMMITTED=true
    finalize_committed_restore || log_fatal "Committed MariaDB restore could not be verified/finalized; evidence was preserved and database startup remains blocked"
    log_ok "Finalized a previously committed MariaDB restore transaction"
  else
    RESTORE_SWITCH_COMMITTED=false
    rollback_restore_switch || log_fatal "Interrupted MariaDB restore could not be rolled back deterministically; evidence was preserved and database startup remains blocked"
    log_ok "Rolled back an interrupted MariaDB restore transaction"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fix_backup_cnf
#   Points extræcted physicæl metædætæ æt the configured restore tærget
#   Ærguments:
#     $1 - directory contæining backup-my.cnf
#ææææææææææææææææææææææææææææææææææ
fix_backup_cnf() {
  local directory="$1"
  local file="$directory/backup-my.cnf"
  [[ -f "$file" ]] || return 0
  sed -i "s|^datadir=.*|datadir=$MARIADB_DIR|" "$file"
  sed -i "s|^innodb_data_home_dir=.*|innodb_data_home_dir=$MARIADB_DIR|" "$file"
  sed -i "s|^innodb_log_group_home_dir=.*|innodb_log_group_home_dir=$MARIADB_DIR|" "$file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: extract_restore_chain
#   Extræcts the full bæckup ænd eæch incrementæl into sepæræte directories
#ææææææææææææææææææææææææææææææææææ
extract_restore_chain() {
  local index=0
  local archive=""
  local target=""

  for archive in "${RESTORE_CHAIN[@]}"; do
    if (( index == 0 )); then
      target="$TMP_BASE/full"
    else
      target="$TMP_BASE/incremental_$(printf '%02d' "$index")"
    fi
    mkdir -p -- "$target"
    log_info "Extracting ${archive##*/}"
    run_restore_child bash -o pipefail -c '
      zstd -d -q --stdout "$1" | tar -xf - -C "$2"
    ' restore-extract "$archive" "$target" || log_fatal "Extraction failed: ${archive##*/}"
    fix_backup_cnf "$target"
    index=$((index + 1))
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_restore_chain
#   Æpplies full ænd immediæte-predecessor incrementæls in correct order
#ææææææææææææææææææææææææææææææææææ
prepare_restore_chain() {
  local incremental_count=$((${#RESTORE_CHAIN[@]} - 1))
  local index=1

  log_info "Preparing full backup"
  run_restore_child mariadb-backup --prepare --target-dir="$TMP_BASE/full" || log_fatal "Failed to prepare full backup"
  while (( index <= incremental_count )); do
    log_info "Applying incremental $(printf '%02d' "$index") of $(printf '%02d' "$incremental_count")"
    run_restore_child mariadb-backup \
      --prepare \
      --target-dir="$TMP_BASE/full" \
      --incremental-dir="$TMP_BASE/incremental_$(printf '%02d' "$index")" || log_fatal "Failed to apply incremental $(printf '%02d' "$index")"
    index=$((index + 1))
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: begin_restore_stage
#   Persists the stært blocker before creæting æ sæme-volume complete new tree
#ææææææææææææææææææææææææææææææææææ
begin_restore_stage() {
  local token=""
  local artifacts=()

  is_safe_data_dir || log_fatal "Unsafe MariaDB data directory: $MARIADB_DIR"
  capture_restore_inventory artifacts none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*'
  (( ${#artifacts[@]} == 0 )) || log_fatal "Unrecovered MariaDB restore artifacts block a new transaction"
  clear_restore_transaction_plan
  token="$(date +%s).$$.${RANDOM}"
  RESTORE_STAGE_DIR="$MARIADB_DIR/.mariadb-restore-stage.$token"
  [[ ! -e "$RESTORE_STAGE_DIR" && ! -L "$RESTORE_STAGE_DIR" ]] || log_fatal "MariaDB restore-stage name collision"
  RESTORE_STAGE_IDENTITY="pending"
  RESTORE_SWITCH_ACTIVE=true
  RESTORE_SWITCH_COMMITTED=false
  RESTORE_SWITCH_FINALIZED=false
  write_restore_journal initializing
  mkdir -- "$RESTORE_STAGE_DIR" || log_fatal "Cannot create same-volume MariaDB restore stage"
  chmod 0700 -- "$RESTORE_STAGE_DIR" || log_fatal "Cannot restrict MariaDB restore stage"
  RESTORE_STAGE_IDENTITY=$(restore_node_identity "$RESTORE_STAGE_DIR") || log_fatal "Cannot inspect MariaDB restore stage"
  [[ "$(stat -c '%d' -- "$RESTORE_STAGE_DIR")" == "$(stat -c '%d' -- "$MARIADB_DIR")" ]] || log_fatal "MariaDB restore stage is not on the data volume"
  write_restore_journal staging
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_prepared_restore
#   Copies the prepæred bæckup completely before æctive dætæ is touched
#ææææææææææææææææææææææææææææææææææ
stage_prepared_restore() {
  local staged_nodes=()
  begin_restore_stage
  log_info "Staging prepared MariaDB data on the database volume"
  run_restore_child mariadb-backup --copy-back --target-dir="$TMP_BASE/full" --datadir="$RESTORE_STAGE_DIR" || log_fatal "MariaDB stage copy-back failed"
  capture_restore_inventory staged_nodes none "$RESTORE_STAGE_DIR" -xdev -mindepth 1 -maxdepth 1
  (( ${#staged_nodes[@]} > 0 )) || log_fatal "MariaDB restore stage is unexpectedly empty"
  sync -f -- "$RESTORE_STAGE_DIR" || log_fatal "Cannot durably flush staged MariaDB data"
  write_restore_journal staging
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: plan_restore_switch
#   Journæls every old ænd new top-level inode before the first renæme
#ææææææææææææææææææææææææææææææææææ
plan_restore_switch() {
  local token="${RESTORE_STAGE_DIR##*.mariadb-restore-stage.}"
  local nodes=()
  local node=""
  local name=""
  local mount_target=""
  local canonical_target=""
  local mount_targets=()

  is_safe_data_dir || log_fatal "MariaDB data directory changed before switch planning"
  capture_mount_inventory mount_targets "$MARIADB_DIR" || log_fatal "Cannot inspect nested mounts below $MARIADB_DIR"
  for mount_target in "${mount_targets[@]}"; do
    [[ -n "$mount_target" ]] || continue
    canonical_target=$(realpath -m -- "$mount_target") || log_fatal "Cannot resolve MariaDB data-volume mount inventory"
    [[ "$canonical_target" == "$MARIADB_DIR" ]] || log_fatal "MariaDB data directory contains a nested mount that cannot be switched safely: $mount_target"
  done

  RESTORE_OLD_DIR="$MARIADB_DIR/.mariadb-restore-old.$token"
  RESTORE_OLD_IDENTITY="pending"
  [[ ! -e "$RESTORE_OLD_DIR" && ! -L "$RESTORE_OLD_DIR" ]] || log_fatal "MariaDB old-data quarantine name collision"
  write_restore_journal staging
  mkdir -- "$RESTORE_OLD_DIR" || log_fatal "Cannot create MariaDB old-data quarantine"
  chmod 0700 -- "$RESTORE_OLD_DIR" || log_fatal "Cannot restrict MariaDB old-data quarantine"
  RESTORE_OLD_IDENTITY=$(restore_node_identity "$RESTORE_OLD_DIR") || log_fatal "Cannot inspect MariaDB old-data quarantine"

  RESTORE_OLD_SOURCES=()
  RESTORE_OLD_DESTINATIONS=()
  RESTORE_OLD_IDENTITIES=()
  capture_restore_inventory nodes none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1
  for node in "${nodes[@]}"; do
    if [[ "$node" == "$RESTORE_STAGE_DIR" || "$node" == "$RESTORE_OLD_DIR" || "$node" == "$RESTORE_SWITCH_JOURNAL" || "${node##*/}" == .mariadb-restore-journal.tmp.* ]]; then
      continue
    fi
    name="${node##*/}"
    validate_restore_basename "$name" || log_fatal "Unsafe active MariaDB top-level name cannot be switched"
    [[ "$name" != .mariadb-restore-* ]] || log_fatal "Unexpected MariaDB restore artifact in active data inventory: $name"
    RESTORE_OLD_SOURCES+=("$node")
    RESTORE_OLD_DESTINATIONS+=("$RESTORE_OLD_DIR/$name")
    RESTORE_OLD_IDENTITIES+=("$(restore_node_identity "$node")")
  done

  RESTORE_NEW_SOURCES=()
  RESTORE_NEW_DESTINATIONS=()
  RESTORE_NEW_IDENTITIES=()
  capture_restore_inventory nodes none "$RESTORE_STAGE_DIR" -xdev -mindepth 1 -maxdepth 1
  (( ${#nodes[@]} > 0 )) || log_fatal "MariaDB restore stage contains no top-level data"
  for node in "${nodes[@]}"; do
    name="${node##*/}"
    validate_restore_basename "$name" || log_fatal "Unsafe staged MariaDB top-level name cannot be switched"
    [[ "$name" != .mariadb-restore-* ]] || log_fatal "Staged MariaDB data contains a reserved restore-artifact name"
    RESTORE_NEW_SOURCES+=("$node")
    RESTORE_NEW_DESTINATIONS+=("$MARIADB_DIR/$name")
    RESTORE_NEW_IDENTITIES+=("$(restore_node_identity "$node")")
  done
  write_restore_journal switching
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: exchange_staged_restore
#   Switches the pre-journæled top-level inodes ænd keeps the stært blocker until verified
#ææææææææææææææææææææææææææææææææææ
exchange_staged_restore() {
  local index=0

  plan_restore_switch
  require_database_stopped
  is_safe_data_dir || log_fatal "MariaDB data directory changed immediately before the top-level switch"
  for index in "${!RESTORE_OLD_SOURCES[@]}"; do
    move_restore_node "${RESTORE_OLD_SOURCES[$index]}" "${RESTORE_OLD_DESTINATIONS[$index]}" "${RESTORE_OLD_IDENTITIES[$index]}" || log_fatal "Failed to quarantine old MariaDB data inode: ${RESTORE_OLD_SOURCES[$index]##*/}"
  done
  for index in "${!RESTORE_NEW_SOURCES[@]}"; do
    move_restore_node "${RESTORE_NEW_SOURCES[$index]}" "${RESTORE_NEW_DESTINATIONS[$index]}" "${RESTORE_NEW_IDENTITIES[$index]}" || log_fatal "Failed to activate staged MariaDB data inode: ${RESTORE_NEW_SOURCES[$index]##*/}"
  done
  sync -f -- "$MARIADB_DIR" || log_fatal "Cannot durably flush the switched MariaDB data directory"
  write_restore_journal committed
  RESTORE_SWITCH_COMMITTED=true
  finalize_committed_restore || log_fatal "New MariaDB data is complete but transaction cleanup failed; startup remains blocked for deterministic recovery"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_physical
#   Vælidætes, prepæres ænd æpplies one physicæl restore chæin
#ææææææææææææææææææææææææææææææææææ
restore_physical() {
  local archive=""
  acquire_maintenance_lock
  require_database_stopped
  recover_interrupted_restore
  find_restore_chain
  prepare_selected_artifacts
  for archive in "${RESTORE_CHAIN[@]}"; do
    validate_tar_archive "$archive"
  done

  if [[ "$MARIADB_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Validated physical restore chain; would replace $MARIADB_DIR"
    return 0
  fi

  test_database_dir_writable
  extract_restore_chain
  prepare_restore_chain
  stage_prepared_restore
  exchange_staged_restore
  CONSUMED_ARCHIVES=("${ORIGINAL_RESTORE_CHAIN[@]}")
  log_ok "Physical restore completed successfully"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGICÆL RESTORE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_dump
#   Imports one verified ræw SQL dump into æ running MæriæDB instænce
#ææææææææææææææææææææææææææææææææææ
restore_dump() {
  local archive=""
  local restored_object_count=""
  local restore_artifacts=()
  acquire_maintenance_lock
  capture_restore_inventory restore_artifacts none "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*'
  (( ${#restore_artifacts[@]} == 0 )) || log_fatal "Persistent physical-restore evidence blocks logical restore; run a stopped physical recovery first"
  select_dump_archive
  prepare_selected_artifacts
  archive="${RESTORE_CHAIN[0]}"
  verify_checksum "$archive"
  zstd -t -q "$archive" || log_fatal "Corrupt logical dump: ${archive##*/}"
  create_mariadb_client_option_file
  require_database_running
  prepare_dump_target

  if [[ "$MARIADB_RESTORE_DRY_RUN" == "true" ]]; then
    log_dry "Validated logical dump and target policy; would import ${archive##*/} into $MARIADB_DB_HOST"
    return 0
  fi

  if ! run_restore_child bash -o pipefail -c '
      zstd -d -q --stdout "$2" | mariadb \
        "$1" \
        --batch \
        --binary-mode \
        --connect-timeout=5 \
        --host="$3" \
        --user="$4"
    ' restore-dump "$MARIADB_CLIENT_OPTION_ARGUMENT" "$archive" "$MARIADB_DB_HOST" "$MARIADB_ROOT_USER"; then
    log_fatal "Logical dump import failed after database mutation may have started; treat $MARIADB_DATABASE as partially restored and unusable until a complete replacement succeeds"
  fi
  database_exists || log_fatal "Logical dump import returned success but target database $MARIADB_DATABASE does not exist"
  restored_object_count="$(count_database_objects)"
  log_info "Restored logical target contains ${restored_object_count} object(s)"
  CONSUMED_ARCHIVES=("${ORIGINAL_RESTORE_CHAIN[0]}")
  log_ok "Logical dump restore completed successfully"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: append_bundle_consume_file
#   Ædds one unique, top-level originæl to the complete bundle consume set
#   Ærguments:
#     $1 - originæl bundle file pæth
#ææææææææææææææææææææææææææææææææææ
append_bundle_consume_file() {
  local candidate="$1"
  local existing=""

  [[ "${candidate%/*}" == "$RESTORE_DIR" ]] || log_fatal "Refusing to consume bundle file outside $RESTORE_DIR: $candidate"
  for existing in "${BUNDLE_CONSUME_FILES[@]}"; do
    [[ "$existing" != "$candidate" ]] || return 0
  done
  BUNDLE_CONSUME_FILES+=("$candidate")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_bundle_consumption
#   Revælidætes originæls ænd builds one complete mænifest-bound consume set
#ææææææææææææææææææææææææææææææææææ
prepare_bundle_consumption() {
  local index=0
  local original_manifest=""
  local snapshot_manifest=""
  local manifest_name=""
  local line=""
  local line_number=0
  local original_archive=""
  local snapshot_sidecar=""
  local original_sidecar=""
  local actual=""
  local selected=""
  local candidate=""
  local selected_found=false

  (( ${#ORIGINAL_BUNDLE_MANIFESTS[@]} == ${#BUNDLE_MANIFESTS[@]} )) || log_fatal "Cannot consume bundles without stable manifest snapshots"
  BUNDLE_CONSUME_FILES=()
  while (( index < ${#ORIGINAL_BUNDLE_MANIFESTS[@]} )); do
    original_manifest="${ORIGINAL_BUNDLE_MANIFESTS[$index]}"
    snapshot_manifest="${BUNDLE_MANIFESTS[$index]}"
    manifest_name="${original_manifest##*/}"
    [[ "${original_manifest%/*}" == "$RESTORE_DIR" ]] || log_fatal "Unsafe original bundle manifest path: $original_manifest"
    [[ -f "$original_manifest" && ! -L "$original_manifest" ]] || log_fatal "Original bundle manifest disappeared or became unsafe: $manifest_name"
    [[ -f "$snapshot_manifest" && ! -L "$snapshot_manifest" ]] || log_fatal "Private bundle manifest snapshot is unavailable: ${snapshot_manifest##*/}"
    cmp -s -- "$original_manifest" "$snapshot_manifest" || log_fatal "Original bundle manifest changed after snapshot: $manifest_name"
    set_bundle_expected_artifacts "$snapshot_manifest"

    line_number=0
    while IFS= read -r line || [[ -n "$line" ]]; do
      line_number=$((line_number + 1))
      validate_manifest_line "$line" "${snapshot_manifest##*/}" "$line_number"
      case "$MANIFEST_ENTRY_NAME" in
        "$BUNDLE_DATABASE_ARCHIVE")
          ;;
        *)
          log_fatal "Unexpected archive in bundle manifest ${snapshot_manifest##*/}: $MANIFEST_ENTRY_NAME"
          ;;
      esac
      original_archive="$RESTORE_DIR/$MANIFEST_ENTRY_NAME"
      [[ -f "$original_archive" && ! -L "$original_archive" ]] || log_fatal "Original bundle archive disappeared or became unsafe: $MANIFEST_ENTRY_NAME"
      actual=$(sha256sum -- "$original_archive")
      actual="${actual%% *}"
      [[ "$actual" == "$MANIFEST_ENTRY_CHECKSUM" ]] || log_fatal "Original bundle archive changed after snapshot: $MANIFEST_ENTRY_NAME"
      append_bundle_consume_file "$original_archive"

      snapshot_sidecar="${snapshot_manifest%/*}/${MANIFEST_ENTRY_NAME}.sha256"
      original_sidecar="${original_archive}.sha256"
      if [[ -e "$snapshot_sidecar" || -L "$snapshot_sidecar" ]]; then
        [[ -f "$snapshot_sidecar" && ! -L "$snapshot_sidecar" ]] || log_fatal "Unsafe private checksum snapshot: ${snapshot_sidecar##*/}"
        [[ -f "$original_sidecar" && ! -L "$original_sidecar" ]] || log_fatal "Original checksum sidecar disappeared or became unsafe: ${original_sidecar##*/}"
        cmp -s -- "$original_sidecar" "$snapshot_sidecar" || log_fatal "Original checksum sidecar changed after snapshot: ${original_sidecar##*/}"
        append_bundle_consume_file "$original_sidecar"
      elif [[ -e "$original_sidecar" || -L "$original_sidecar" ]]; then
        log_fatal "Original checksum sidecar appeared after snapshot: ${original_sidecar##*/}"
      fi
    done < "$snapshot_manifest"
    append_bundle_consume_file "$original_manifest"
    index=$((index + 1))
  done

  for selected in "${CONSUMED_ARCHIVES[@]}"; do
    selected_found=false
    for candidate in "${BUNDLE_CONSUME_FILES[@]}"; do
      if [[ "$candidate" == "$selected" ]]; then
        selected_found=true
        break
      fi
    done
    [[ "$selected_found" == "true" ]] || log_fatal "Selected original is not covered by the complete consume set: ${selected##*/}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: consume_archives
#   Quæræntines complete, revælidæted bundles before cleænup removes them
#ææææææææææææææææææææææææææææææææææ
consume_archives() {
  local quarantine=""
  local source=""
  local destination=""
  local source_device=""
  local quarantine_device=""
  local source_identity=""
  local moved_identity=""
  local index=0

  [[ "$MARIADB_RESTORE_CONSUME_ARCHIVES" == "true" ]] || return 0
  (( ${#CONSUMED_ARCHIVES[@]} > 0 )) || return 0
  [[ "$MARIADB_RESTORE_DRY_RUN" != "true" ]] || log_fatal "Internal error: dry-run attempted to consume a bundle"
  [[ "$TMP_CREATED" == "true" ]] && is_safe_tmp_base || log_fatal "Complete bundle consumption requires the private restore workspace"
  prepare_bundle_consumption
  (( ${#BUNDLE_CONSUME_FILES[@]} > 0 )) || log_fatal "Refusing empty bundle consumption"
  BUNDLE_CONSUME_IDENTITIES=()
  for source in "${BUNDLE_CONSUME_FILES[@]}"; do
    [[ -f "$source" && ! -L "$source" ]] || log_fatal "Bundle file became unsafe before consumption: ${source##*/}"
    source_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot inspect bundle file before consumption: ${source##*/}"
    BUNDLE_CONSUME_IDENTITIES+=("$source_identity")
  done

  quarantine="$TMP_BASE/consumed-bundle"
  mkdir -- "$quarantine" || log_fatal "Cannot create bundle-consumption quarantine"
  chmod 0700 -- "$quarantine" || log_fatal "Cannot restrict bundle-consumption quarantine"
  quarantine_device=$(stat -Lc '%d' -- "$quarantine") || log_fatal "Cannot inspect bundle-consumption quarantine"
  MOVED_BUNDLE_SOURCES=()
  MOVED_BUNDLE_DESTINATIONS=()
  CONSUME_COMMITTED=false

  index=0
  for source in "${BUNDLE_CONSUME_FILES[@]}"; do
    [[ -f "$source" && ! -L "$source" ]] || log_fatal "Bundle file became unsafe during consumption: ${source##*/}"
    source_identity=$(stat -Lc '%d:%i:%s' -- "$source") || log_fatal "Cannot re-inspect bundle file during consumption: ${source##*/}"
    [[ "$source_identity" == "${BUNDLE_CONSUME_IDENTITIES[$index]}" ]] || log_fatal "Bundle file identity changed during consumption: ${source##*/}"
    source_device=$(stat -Lc '%d' -- "$source") || log_fatal "Cannot inspect bundle file before consumption: ${source##*/}"
    [[ "$source_device" == "$quarantine_device" ]] || log_fatal "Bundle consumption requires atomic same-filesystem renames"
    destination="$quarantine/${source##*/}"
    [[ ! -e "$destination" && ! -L "$destination" ]] || log_fatal "Duplicate bundle file in consumption quarantine: ${source##*/}"
    # Register both endpoints before renæme; EXIT cæn then recover even if `mv` renæmes ænd reports non-zero.
    MOVED_BUNDLE_SOURCES+=("$source")
    MOVED_BUNDLE_DESTINATIONS+=("$destination")
    mv -T --no-clobber -- "$source" "$destination" || log_fatal "Failed to quarantine complete bundle file: ${source##*/}"
    [[ ! -e "$source" && ! -L "$source" ]] || log_fatal "Bundle file remained at its original path during quarantine: ${source##*/}"
    [[ -f "$destination" && ! -L "$destination" ]] || log_fatal "Quarantined bundle file became unsafe: ${source##*/}"
    moved_identity=$(stat -Lc '%d:%i:%s' -- "$destination") || log_fatal "Cannot inspect quarantined bundle file: ${source##*/}"
    [[ "$moved_identity" == "${BUNDLE_CONSUME_IDENTITIES[$index]}" ]] || log_fatal "Bundle file changed during quarantine rename: ${source##*/}"
    index=$((index + 1))
  done
  CONSUME_COMMITTED=true

  for source in "${BUNDLE_CONSUME_FILES[@]}"; do
    log_info "Consumed complete bundle file: ${source##*/}"
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Dispatches the defæult scheduler or one explicit restore mode
#   Ærguments:
#     $@ - mode ænd stændærd flægs
#ææææææææææææææææææææææææææææææææææ
main() {
  local mode="$MARIADB_MAINTENANCE_MODE"
  local argument=""

  for argument in "$@"; do
    case "$argument" in
      schedule|restore|restore-dump)
        mode="$argument"
        ;;
      --dry-run)
        MARIADB_RESTORE_DRY_RUN=true
        ;;
      --debug)
        DEBUG=true
        ;;
      -h|--help)
        usage
        return 0
        ;;
      default)
        mode="schedule"
        ;;
      *)
        log_fatal "Invalid argument: $argument"
        ;;
    esac
  done

  if [[ "$mode" == "schedule" ]]; then
    log_info "Starting Supercronic with /usr/local/bin/backup.cron"
    exec "$SUPERCRONIC_BIN" /usr/local/bin/backup.cron
  fi

  validate_configuration
  case "$mode" in
    restore)
      restore_physical
      ;;
    restore-dump)
      restore_dump
      ;;
    *)
      log_fatal "Invalid maintenance mode: $mode"
      ;;
  esac
  consume_archives
}

main "$@"
