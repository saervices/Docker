#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail
umask 077

# Docker mounts compose secrets with permissive modes; OpenSSH rejects those for -i.
readonly CERTS_DUMPER_SSH_SECRET="/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD"
readonly CERTS_DUMPER_SSH_IDENTITY_FILE="/tmp/.ssh/certs_dumper_identity"
readonly CERTS_DUMPER_SSH_STATE_ROOT="/state"
readonly CERTS_DUMPER_SSH_STATE_DIR="${CERTS_DUMPER_SSH_STATE_ROOT}/.ssh"
readonly CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE="${CERTS_DUMPER_SSH_STATE_DIR}/known_hosts"
readonly CERTS_DUMPER_MAILCOW_LOCK_FILE="${CERTS_DUMPER_SSH_STATE_ROOT}/mailcow-rollover.lock"
readonly CERTS_DUMPER_SAFE_READER="/usr/local/bin/certs-dumper-safe-reader"
readonly CERTS_DUMPER_DNS_TOKEN_FILE="/run/secrets/DNS_API_TOKEN"
readonly CERTS_DUMPER_DNS_TOKEN_RUNTIME_PREFIX="/tmp/.ssh/dns-api-token."
readonly CERTS_DUMPER_CF_API_BASE="${CLOUDFLARE_API_BASE:-https://api.cloudflare.com/client/v4}"
readonly CERTS_DUMPER_DESEC_API_BASE="${DESEC_API_BASE:-https://desec.io/api/v1}"
readonly CERTS_DUMPER_CERT_WAIT_SECONDS=60
readonly CERTS_DUMPER_DNS_POLL_SECONDS=5
readonly CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS=5
readonly CERTS_DUMPER_DNS_MAX_TIME_SECONDS=30
readonly CERTS_DUMPER_SMTP_WAIT_SECONDS=60
readonly CERTS_DUMPER_SMTP_POLL_SECONDS=5
readonly CERTS_DUMPER_SMTP_ATTEMPT_SECONDS=5
readonly CERTS_DUMPER_SSH_SECRET_MAX_BYTES=65536
readonly CERTS_DUMPER_SSH_KNOWN_HOSTS_MAX_BYTES=1048576
readonly CERTS_DUMPER_DNS_TOKEN_MAX_BYTES=4096
readonly CERTS_DUMPER_SSH_CONNECT_TIMEOUT_SECONDS=10
readonly CERTS_DUMPER_SSH_SERVER_ALIVE_INTERVAL_SECONDS=10
readonly CERTS_DUMPER_SSH_SERVER_ALIVE_COUNT_MAX=2
readonly CERTS_DUMPER_CHILD_TERMINATION_SECONDS=5
readonly CERTS_DUMPER_SSH_READ_TIMEOUT_SECONDS=60
readonly CERTS_DUMPER_SCP_TRANSFER_TIMEOUT_SECONDS=90
readonly CERTS_DUMPER_SSH_MUTATION_TIMEOUT_SECONDS=120
readonly CERTS_DUMPER_SSH_ROLLBACK_RESTORE_TIMEOUT_SECONDS=45
readonly CERTS_DUMPER_SSH_ROLLBACK_RESTART_TIMEOUT_SECONDS=45
readonly CERTS_DUMPER_SMTP_ROLLBACK_WAIT_SECONDS=40
readonly CERTS_DUMPER_MAILCOW_STOP_GRACE_SECONDS=180
readonly MAILCOW_PROJECT_PATH="/opt/mailcow-dockerized"
readonly MAILCOW_DANE_TTL_SAFETY_SECONDS=60
readonly MAILCOW_DANE_VALIDATING_RESOLVER="1.1.1.1"
readonly MAILCOW_SMTP_HOSTNAME_INPUT="${MAILCOW_SMTP_HOSTNAME:-}"
readonly MAILCOW_DNS_ZONE_INPUT="${MAILCOW_DNS_ZONE:-}"
readonly MAILCOW_SSH_HOST_INPUT="${MAILCOW_SSH_HOST:-}"
readonly MAILCOW_SSH_USER_INPUT="${MAILCOW_SSH_USER:-}"
MAILCOW_CERT_MAIN_DOMAIN=''
MAILCOW_SMTP_HOSTNAME=''
MAILCOW_DNS_ZONE_NAME=''
MAILCOW_TLSA_RECORD_NAME=''
MAILCOW_DANE_TTL_SECONDS=''
MAILCOW_DNS_PROVIDER=''
MAILCOW_SSH_RESOLVED_ADDRESS=''
MAILCOW_SSH_HOST_KEY_ALIAS=''
MAILCOW_ROLLBACK_ARMED=false
MAILCOW_ROLLBACK_DEST_HOST=''
MAILCOW_ROLLBACK_DEST_USER=''
MAILCOW_ROLLBACK_PROJECT_PATH=''
MAILCOW_ROLLBACK_SSH_KEY=''
MAILCOW_ROLLBACK_TRANSACTION_ID=''
MAILCOW_ROLLBACK_EXPECTED_SPKI=''
MAILCOW_ROLLBACK_EXPECTED_LEAF=''
CERTS_DUMPER_SSH_STATE_DIR_IDENTITY=''
CERTS_DUMPER_SSH_KNOWN_HOSTS_IDENTITY=''
CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT=''
CERTS_DUMPER_SSH_IDENTITY_IDENTITY=''
CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE=''
CERTS_DUMPER_DNS_TOKEN_IDENTITY=''
MAILCOW_TEMPORARY_FILES=''
MAILCOW_BOUNDED_CHILD_PID=''

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Prints æn informætionæl messæge to stdout.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info()  { printf '[INFO]  %s\n' "$*"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Prints æ success messæge to stdout.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok()    { printf '[OK]    %s\n' "$*"; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Prints æ wærning messæge to stderr.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn()  { printf '[WARN]  %s\n' "$*" >&2; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Prints æn error messæge to stderr ænd exits with code 1.
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DEPENDENCY CHECK
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_dependencies
#   Verifies required runtime tools ære present in the imæge.
#   Ærguments:
#     $@ - dependency commænd næmes
#ææææææææææææææææææææææææææææææææææ
check_dependencies() {
  local dep

  for dep in "$@"; do
    command -v "$dep" >/dev/null 2>&1 || log_error "Required dependency missing: ${dep}"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: harden_directory_no_follow
#   Creætes or pins one reæl directory ænd enforces owner-only mode viæ its descriptor.
#   Ærguments:
#     $1 - directory pæth
#ææææææææææææææææææææææææææææææææææ
harden_directory_no_follow() {
  local directory_path="$1"

  "$CERTS_DUMPER_SAFE_READER" --harden-directory "$directory_path" \
    || log_error "Could not descriptor-safely create or harden SSH directory: ${directory_path}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: harden_regular_file_no_follow
#   Creætes or pins one regulær single-link file ænd enforces owner-only mode.
#   Ærguments:
#     $1 - file pæth
#ææææææææææææææææææææææææææææææææææ
harden_regular_file_no_follow() {
  local file_path="$1"

  "$CERTS_DUMPER_SAFE_READER" --harden-state-file "$file_path" \
    || log_error "Could not descriptor-safely create or harden SSH state file: ${file_path}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_ssh_directory
#   Prepæres tmpfs identity storæge ænd persistent known_hosts stæte.
#ææææææææææææææææææææææææææææææææææ
prepare_ssh_directory() {
  harden_directory_no_follow /tmp/.ssh
  "$CERTS_DUMPER_SAFE_READER" --prepare-ssh-state "$CERTS_DUMPER_SSH_STATE_ROOT" \
    || log_error "Could not prepare SSH state below the inherited locked state root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stable_regular_file_metadata
#   Returns full no-follow identity, size, ownership, mode, ænd ns timestamps.
#   Ærguments:
#     $1 - regulær file pæth
#ææææææææææææææææææææææææææææææææææ
stable_regular_file_metadata() {
  local file_path="$1"
  local file_metadata
  local metadata_tail
  local raw_mode

  [ ! -L "$file_path" ] && [ -f "$file_path" ] \
    || log_error "Bounded source must be a regular non-symlink file: ${file_path}"
  file_metadata="$(LC_ALL=C stat -c '%d|%i|%s|%h|%f|%u|%g|%y|%z' -- "$file_path")" \
    || log_error "Could not inspect bounded regular-file metadata: ${file_path}"
  metadata_tail="${file_metadata#*|}"
  metadata_tail="${metadata_tail#*|}"
  metadata_tail="${metadata_tail#*|}"
  metadata_tail="${metadata_tail#*|}"
  raw_mode="${metadata_tail%%|*}"
  case "$raw_mode" in
    8[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
    *) log_error "Bounded source changed to a non-regular node: ${file_path}" ;;
  esac
  printf '%s' "$file_metadata"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_bounded_regular_file_to_stage
#   Copies one stæble regulær single-link source through the descriptor-bæsed reæder.
#   Ærguments:
#     $1 - source pæth
#     $2 - mæximum source bytes
#     $3 - pre-creæted privæte stæge pæth
#     $4 - expected stæge device/inode identity
#     $5 - bounded reæder source kind
#ææææææææææææææææææææææææææææææææææ
copy_bounded_regular_file_to_stage() {
  local source_path="$1"
  local maximum_bytes="$2"
  local stage_path="$3"
  local stage_identity="$4"
  local source_kind="$5"
  local stage_metadata
  local metadata_tail
  local stage_size

  case "$source_kind:$maximum_bytes" in
    dns-token:$CERTS_DUMPER_DNS_TOKEN_MAX_BYTES | \
    ssh-key:$CERTS_DUMPER_SSH_SECRET_MAX_BYTES | \
    known-hosts:$CERTS_DUMPER_SSH_KNOWN_HOSTS_MAX_BYTES) ;;
    *) log_error "Bounded source kind and size contract do not match" ;;
  esac
  [ ! -L "$stage_path" ] && [ -f "$stage_path" ] \
    && [ "$(stat -c '%d:%i' -- "$stage_path")" = "$stage_identity" ] \
    || log_error "Private validation stage changed before copy"
  chmod 0600 -- "$stage_path" || log_error "Could not protect private validation stage"
  "$CERTS_DUMPER_SAFE_READER" \
    --kind "$source_kind" \
    --source "$source_path" \
    --destination "$stage_path" \
    --destination-identity "$stage_identity" \
    || log_error "Could not copy bounded source safely: ${source_path}"
  stage_metadata="$(stable_regular_file_metadata "$stage_path")"
  metadata_tail="${stage_metadata#*|}"
  metadata_tail="${metadata_tail#*|}"
  stage_size="${metadata_tail%%|*}"
  [ "$(stat -c '%d:%i' -- "$stage_path")" = "$stage_identity" ] \
    && [ "$(stat -c '%h:%a' -- "$stage_path")" = "1:600" ] \
    && [ "$stage_size" -ge 0 ] \
    && [ "$stage_size" -le "$maximum_bytes" ] \
    || log_error "Private validation stage changed or has unsafe metadata"
  if [ "$source_kind" != known-hosts ]; then
    [ "$stage_size" -ge 1 ] \
      || log_error "Private validation stage is unexpectedly empty"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailcow_ssh_private_key_stage
#   Vælidætes one private stæge without re-opening the Docker secret source.
#   Ærguments:
#     $1 - privæte-key stæge pæth
#ææææææææææææææææææææææææææææææææææ
validate_mailcow_ssh_private_key_stage() {
  local stage_path="$1"
  local stage_metadata_before
  local stage_metadata_after
  local stage_size
  local metadata_tail
  local placeholder_candidate=''

  stage_metadata_before="$(stable_regular_file_metadata "$stage_path")"
  metadata_tail="${stage_metadata_before#*|}"
  metadata_tail="${metadata_tail#*|}"
  stage_size="${metadata_tail%%|*}"
  if [ "$stage_size" -eq 9 ]; then
    placeholder_candidate="$(LC_ALL=C dd if="$stage_path" bs=10 count=1 \
      iflag=fullblock,nofollow,nonblock status=none 2>/dev/null)" \
      || log_error "Could not read the private-key validation stage safely"
    [ "$placeholder_candidate" != CHANGE_ME ] \
      || log_error "SSH private key secret still contains the exact CHANGE_ME placeholder"
  fi
  if ! LC_ALL=C dd if="$stage_path" \
    bs=$((CERTS_DUMPER_SSH_SECRET_MAX_BYTES + 1)) count=1 \
    iflag=fullblock,nofollow,nonblock status=none 2>/dev/null \
    | awk '
      NR == 1 {
        expected_end = $0
        if ($0 != "-----BEGIN OPENSSH PRIVATE KEY-----" &&
          $0 != "-----BEGIN RSA PRIVATE KEY-----" &&
          $0 != "-----BEGIN DSA PRIVATE KEY-----" &&
          $0 != "-----BEGIN EC PRIVATE KEY-----" &&
          $0 != "-----BEGIN PRIVATE KEY-----") exit 1
        sub("BEGIN", "END", expected_end)
      }
      /^-----BEGIN / { begin_count++ }
      /^-----END / {
        end_count++
        if ($0 != expected_end) exit 1
        end_line = NR
      }
      END {
        if (begin_count != 1 || end_count != 1 || end_line != NR) exit 1
      }
    ' >/dev/null; then
    log_error "SSH private key secret must contain exactly one supported private-key block"
  fi
  ssh-keygen -y -P '' -f "$stage_path" >/dev/null 2>&1 \
    || log_error "SSH private key secret must contain one valid unencrypted private key"
  stage_metadata_after="$(stable_regular_file_metadata "$stage_path")"
  [ "$stage_metadata_after" = "$stage_metadata_before" ] \
    || log_error "Private-key validation stage changed while it was inspected"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailcow_ssh_private_key_secret
#   Copies the source once into privæte tmpfs, then vælidætes only thæt stæge.
#ææææææææææææææææææææææææææææææææææ
validate_mailcow_ssh_private_key_secret() (
  local stage_path
  local stage_identity
  local stage_parent_identity

  stage_path="$(mktemp /tmp/certs-dumper-key-preflight.XXXXXX)" \
    || log_error "Could not create private-key preflight stage"
  stage_identity="$(stat -c '%d:%i' -- "$stage_path")" \
    || log_error "Could not inspect private-key preflight stage"
  stage_parent_identity="$(stat -c '%d:%i' -- "${stage_path%/*}")" \
    || log_error "Could not pin private-key preflight parent"
  trap 'cleanup_mailcow_identity_stage "$stage_path" "$stage_identity" "$stage_parent_identity"' EXIT
  copy_bounded_regular_file_to_stage \
    "$CERTS_DUMPER_SSH_SECRET" "$CERTS_DUMPER_SSH_SECRET_MAX_BYTES" \
    "$stage_path" "$stage_identity" ssh-key
  validate_mailcow_ssh_private_key_stage "$stage_path"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_mailcow_identity_stage
#   Removes only one exæct identity-pinned privæte vælidætion stæge.
#   Ærguments:
#     $1 - temporæry identity pæth
#     $2 - expected device/inode identity
#     $3 - expected pærent device/inode identity
#ææææææææææææææææææææææææææææææææææ
cleanup_mailcow_identity_stage() {
  local stage_path="$1"
  local expected_identity="$2"
  local expected_parent_identity="$3"

  [ -n "$stage_path" ] || return 0
  "$CERTS_DUMPER_SAFE_READER" \
    --remove-private-file "$stage_path" \
    --remove-private-identity "$expected_identity" \
    --remove-private-parent-identity "$expected_parent_identity" \
    || {
      log_warn "Preserving identity-drifted private file during descriptor-based cleanup: ${stage_path}"
      return 1
    }
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: register_mailcow_temporary_file
#   Registers one immediætely identity-pinned temporæry file for exit cleanup.
#ææææææææææææææææææææææææææææææææææ
register_mailcow_temporary_file() {
  local stage_path="$1"
  local stage_identity="$2"
  local parent_identity="$3"
  local registry_entry="${stage_path}|${stage_identity}|${parent_identity}"

  if [ -n "$MAILCOW_TEMPORARY_FILES" ]; then
    MAILCOW_TEMPORARY_FILES="${MAILCOW_TEMPORARY_FILES}
${registry_entry}"
  else
    MAILCOW_TEMPORARY_FILES="$registry_entry"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: unregister_mailcow_temporary_file
#   Removes one exæct entry from the in-memory cleanup registry.
#ææææææææææææææææææææææææææææææææææ
unregister_mailcow_temporary_file() {
  local registry_target="${1}|${2}|${3}"
  local registry_entry
  local remaining_entries=''
  local previous_ifs="$IFS"

  IFS='
'
  for registry_entry in $MAILCOW_TEMPORARY_FILES; do
    [ "$registry_entry" = "$registry_target" ] && continue
    if [ -n "$remaining_entries" ]; then
      remaining_entries="${remaining_entries}
${registry_entry}"
    else
      remaining_entries="$registry_entry"
    fi
  done
  IFS="$previous_ifs"
  MAILCOW_TEMPORARY_FILES="$remaining_entries"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_registered_mailcow_temporary_file
#   Descriptor-sæfely removes ænd unregisters one temporæry file.
#ææææææææææææææææææææææææææææææææææ
cleanup_registered_mailcow_temporary_file() {
  local stage_path="$1"
  local stage_identity="$2"
  local parent_identity="$3"

  cleanup_mailcow_identity_stage "$stage_path" "$stage_identity" "$parent_identity" \
    || return 1
  unregister_mailcow_temporary_file "$stage_path" "$stage_identity" "$parent_identity"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_all_mailcow_temporary_files
#   Best-effort descriptor-sæfely cleæns every registered file.
#ææææææææææææææææææææææææææææææææææ
cleanup_all_mailcow_temporary_files() {
  local registry="$MAILCOW_TEMPORARY_FILES"
  local registry_entry
  local stage_path
  local identity_tail
  local stage_identity
  local parent_identity
  local previous_ifs="$IFS"

  MAILCOW_TEMPORARY_FILES=''
  IFS='
'
  for registry_entry in $registry; do
    stage_path="${registry_entry%%|*}"
    identity_tail="${registry_entry#*|}"
    stage_identity="${identity_tail%%|*}"
    parent_identity="${identity_tail##*|}"
    cleanup_mailcow_identity_stage "$stage_path" "$stage_identity" "$parent_identity" || true
  done
  IFS="$previous_ifs"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: terminate_mailcow_bounded_child
#   Terminætes ænd reæps the complete tracked network-process group before exit.
#   Ærguments:
#     $1 - signæl-derived shell exit stætus
#ææææææææææææææææææææææææææææææææææ
terminate_mailcow_bounded_child() {
  local exit_status="$1"
  local child_pid="$MAILCOW_BOUNDED_CHILD_PID"

  trap - HUP INT TERM
  if [ -n "$child_pid" ]; then
    kill -TERM "-${child_pid}" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
  fi
  MAILCOW_BOUNDED_CHILD_PID=''
  exit "$exit_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_mailcow_bounded_command
#   Runs one network phæse in æ dedicæted session ænd reæps it on signæls.
#   Ærguments:
#     $1 - totæl deædline in seconds
#     $@ - option-sæfe commænd ænd ærguments
#ææææææææææææææææææææææææææææææææææ
run_mailcow_bounded_command() {
  local deadline_seconds="$1"
  local command_status=0
  shift

  [ -z "$MAILCOW_BOUNDED_CHILD_PID" ] \
    || log_error "A bounded Mailcow network child is already active"
  setsid -w timeout "$deadline_seconds" "$@" &
  MAILCOW_BOUNDED_CHILD_PID="$!"
  trap 'terminate_mailcow_bounded_child 129' HUP
  trap 'terminate_mailcow_bounded_child 130' INT
  trap 'terminate_mailcow_bounded_child 143' TERM
  wait "$MAILCOW_BOUNDED_CHILD_PID" || command_status=$?
  MAILCOW_BOUNDED_CHILD_PID=''
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  return "$command_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_ssh_identity_from_secret
#   Publishes one re-vælidæted SSH identity ætomicælly into tmpfs.
#ææææææææææææææææææææææææææææææææææ
prepare_ssh_identity_from_secret() (
  local secret_size
  local stage_path=''
  local stage_identity=''
  local stage_parent_identity=''

  stage_path="$(mktemp "${CERTS_DUMPER_SSH_IDENTITY_FILE}.tmp.XXXXXX")" \
    || log_error "Could not create SSH identity stage in tmpfs"
  stage_identity="$(stat -c '%d:%i' -- "$stage_path")" \
    || log_error "Could not inspect SSH identity stage"
  stage_parent_identity="$(stat -c '%d:%i' -- "${stage_path%/*}")" \
    || log_error "Could not pin SSH identity-stage parent"
  trap 'cleanup_mailcow_identity_stage "$stage_path" "$stage_identity" "$stage_parent_identity"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  copy_bounded_regular_file_to_stage \
    "$CERTS_DUMPER_SSH_SECRET" "$CERTS_DUMPER_SSH_SECRET_MAX_BYTES" \
    "$stage_path" "$stage_identity" ssh-key
  validate_mailcow_ssh_private_key_stage "$stage_path"
  secret_size="$(stat -c '%s' -- "$stage_path")" \
    || log_error "Could not inspect validated SSH identity stage size"
  if [ -e "$CERTS_DUMPER_SSH_IDENTITY_FILE" ] || [ -L "$CERTS_DUMPER_SSH_IDENTITY_FILE" ]; then
    [ ! -L "$CERTS_DUMPER_SSH_IDENTITY_FILE" ] \
      && [ -f "$CERTS_DUMPER_SSH_IDENTITY_FILE" ] \
      && [ "$(stat -c '%h' -- "$CERTS_DUMPER_SSH_IDENTITY_FILE")" -eq 1 ] \
      || log_error "Existing SSH identity target must be a regular single-link file"
  fi
  mv -f -- "$stage_path" "$CERTS_DUMPER_SSH_IDENTITY_FILE" \
    || log_error "Could not publish the validated SSH identity"
  stage_path=''
  stage_identity=''
  trap - EXIT HUP INT TERM
  [ ! -L "$CERTS_DUMPER_SSH_IDENTITY_FILE" ] \
    && [ -f "$CERTS_DUMPER_SSH_IDENTITY_FILE" ] \
    && [ "$(stat -c '%s:%h:%a' -- "$CERTS_DUMPER_SSH_IDENTITY_FILE")" = "${secret_size}:1:600" ] \
    || log_error "Published SSH identity is not a protected regular single-link file"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pin_ssh_runtime_state
#   Pins the prepæred SSH directory, host-trust file, ænd privæte identity.
#ææææææææææææææææææææææææææææææææææ
pin_ssh_runtime_state() {
  CERTS_DUMPER_SSH_STATE_DIR_IDENTITY="$(stat -c '%d:%i:%u:%g' -- "$CERTS_DUMPER_SSH_STATE_DIR")" \
    || log_error "Could not pin the persistent SSH state directory"
  CERTS_DUMPER_SSH_KNOWN_HOSTS_IDENTITY="$(stat -c '%d:%i:%u:%g' -- "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE")" \
    || log_error "Could not pin the persistent SSH known_hosts file"
  CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT="$(snapshot_ssh_known_hosts)" \
    || log_error "Could not pin the persistent SSH known_hosts content"
  CERTS_DUMPER_SSH_IDENTITY_IDENTITY="$(stable_regular_file_metadata "$CERTS_DUMPER_SSH_IDENTITY_FILE")" \
    || log_error "Could not pin the tmpfs SSH identity"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: snapshot_ssh_known_hosts
#   Returns one stable metædætæ ænd content digest for the pinned trust file.
#ææææææææææææææææææææææææææææææææææ
snapshot_ssh_known_hosts() {
  local metadata_before
  local metadata_after
  local metadata_tail
  local known_hosts_size
  local known_hosts_links
  local content_digest

  [ -r "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" ] \
    || log_error "Persistent SSH known_hosts is not readable"
  metadata_before="$(stable_regular_file_metadata "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE")"
  metadata_tail="${metadata_before#*|}"
  metadata_tail="${metadata_tail#*|}"
  known_hosts_size="${metadata_tail%%|*}"
  metadata_tail="${metadata_tail#*|}"
  known_hosts_links="${metadata_tail%%|*}"
  [ "$known_hosts_links" -eq 1 ] \
    || log_error "Persistent SSH known_hosts must have exactly one link"
  [ "$known_hosts_size" -ge 0 ] \
    && [ "$known_hosts_size" -le "$CERTS_DUMPER_SSH_KNOWN_HOSTS_MAX_BYTES" ] \
    || log_error "Persistent SSH known_hosts exceeds its bounded size"
  content_digest="$("$CERTS_DUMPER_SAFE_READER" \
    --kind known-hosts \
    --source "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" \
    --digest)" \
    || log_error "Could not digest persistent SSH known_hosts safely"
  metadata_after="$(stable_regular_file_metadata "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE")"
  [ "$metadata_after" = "$metadata_before" ] \
    || log_error "Persistent SSH known_hosts changed while it was digested"
  printf '%s|%s' "$metadata_before" "$content_digest"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_ssh_runtime_state
#   Re-vælidætes every pinned SSH pæth immediætely æround network use.
#   Ærguments:
#     $1 - expected tmpfs SSH identity pæth
#ææææææææææææææææææææææææææææææææææ
validate_ssh_runtime_state() {
  local ssh_key="$1"
  local identity_metadata

  [ "$ssh_key" = "$CERTS_DUMPER_SSH_IDENTITY_FILE" ] \
    || log_error "SSH calls must use the pinned certs-dumper identity"
  [ -n "$CERTS_DUMPER_SSH_STATE_DIR_IDENTITY" ] \
    && [ -n "$CERTS_DUMPER_SSH_KNOWN_HOSTS_IDENTITY" ] \
    && [ -n "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" ] \
    && [ -n "$CERTS_DUMPER_SSH_IDENTITY_IDENTITY" ] \
    || log_error "SSH runtime state was not pinned before use"
  [ ! -L "$CERTS_DUMPER_SSH_STATE_DIR" ] \
    && [ -d "$CERTS_DUMPER_SSH_STATE_DIR" ] \
    && [ "$(stat -c '%d:%i:%u:%g:%a' -- "$CERTS_DUMPER_SSH_STATE_DIR")" = "${CERTS_DUMPER_SSH_STATE_DIR_IDENTITY}:700" ] \
    || log_error "Persistent SSH state directory changed or is not mode 0700"
  [ ! -L "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" ] \
    && [ -f "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" ] \
    && [ "$(stat -c '%d:%i:%u:%g' -- "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE")" = "$CERTS_DUMPER_SSH_KNOWN_HOSTS_IDENTITY" ] \
    && [ "$(stat -c '%h:%a' -- "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE")" = "1:600" ] \
    || log_error "Persistent SSH known_hosts changed or is not one mode-0600 single-link file"
  [ ! -L "$ssh_key" ] && [ -f "$ssh_key" ] \
    || log_error "SSH identity changed type before use"
  identity_metadata="$(stable_regular_file_metadata "$ssh_key")" \
    || log_error "Could not inspect the SSH identity before use"
  [ "$identity_metadata" = "$CERTS_DUMPER_SSH_IDENTITY_IDENTITY" ] \
    || log_error "SSH identity changed after it was prepared"
  [ "$(snapshot_ssh_known_hosts)" = "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" ] \
    || log_error "Persistent SSH known_hosts content changed between network calls"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_known_host_binding
#   Requires the successful SSH peer to exist in the pinned trust file.
#   Ærguments:
#     $1 - vælidæted SSH host
#ææææææææææææææææææææææææææææææææææ
require_known_host_binding() {
  local ssh_host="$1"

  known_host_binding_exists "$ssh_host" \
    || log_error "Successful SSH connection did not persist the exact host-key binding"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_known_hosts_to_private_snapshot
#   Copies one ælreædy-pinned trust stæte through the descriptor-bæsed reæder.
#   Ærguments:
#     $1 - expected known_hosts snæpshot
#     $2 - pre-creæted privæte copy pæth
#     $3 - expected copy device/inode identity
#ææææææææææææææææææææææææææææææææææ
copy_known_hosts_to_private_snapshot() {
  local expected_snapshot="$1"
  local snapshot_path="$2"
  local snapshot_identity="$3"
  local source_snapshot_before
  local source_snapshot_after
  local expected_digest
  local expected_size
  local metadata_tail
  local copied_digest

  source_snapshot_before="$(snapshot_ssh_known_hosts)"
  [ "$source_snapshot_before" = "$expected_snapshot" ] \
    || log_error "Persistent SSH known_hosts drifted before private snapshot copy"
  metadata_tail="${expected_snapshot#*|}"
  metadata_tail="${metadata_tail#*|}"
  expected_size="${metadata_tail%%|*}"
  expected_digest="${expected_snapshot##*|}"
  [ ! -L "$snapshot_path" ] && [ -f "$snapshot_path" ] \
    && [ "$(stat -c '%d:%i' -- "$snapshot_path")" = "$snapshot_identity" ] \
    || log_error "Private known_hosts snapshot changed before copy"
  chmod 0600 -- "$snapshot_path" \
    || log_error "Could not protect private known_hosts snapshot"
  copy_bounded_regular_file_to_stage \
    "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" \
    "$CERTS_DUMPER_SSH_KNOWN_HOSTS_MAX_BYTES" \
    "$snapshot_path" "$snapshot_identity" known-hosts
  source_snapshot_after="$(snapshot_ssh_known_hosts)"
  [ "$source_snapshot_after" = "$expected_snapshot" ] \
    || log_error "Persistent SSH known_hosts changed during private snapshot copy"
  [ ! -L "$snapshot_path" ] && [ -f "$snapshot_path" ] \
    && [ "$(stat -c '%d:%i' -- "$snapshot_path")" = "$snapshot_identity" ] \
    && [ "$(stat -c '%s:%h:%a' -- "$snapshot_path")" = "${expected_size}:1:600" ] \
    || log_error "Private known_hosts snapshot has unsafe metadata"
  copied_digest="$("$CERTS_DUMPER_SAFE_READER" \
    --kind known-hosts \
    --source "$snapshot_path" \
    --digest)" \
    || log_error "Could not digest private known_hosts snapshot"
  [ "$copied_digest" = "$expected_digest" ] \
    || log_error "Private known_hosts snapshot content does not match its pinned source"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_accept_new_known_hosts_delta
#   Requires accept-new to append only one exæct configured host binding.
#   Ærguments:
#     $1 - privæte pre-cæll known_hosts copy
#     $2 - expected pre-cæll copy identity
#     $3 - privæte post-cæll known_hosts copy
#     $4 - expected post-cæll copy identity
#     $5 - expected configured host-key æliæs
#ææææææææææææææææææææææææææææææææææ
validate_accept_new_known_hosts_delta() (
  local before_path="$1"
  local before_identity="$2"
  local after_path="$3"
  local after_identity="$4"
  local ssh_host="$5"
  local before_size
  local after_size
  local appended_size
  local appended_path
  local appended_identity
  local appended_parent_identity

  cleanup_accept_new_delta_stage() {
    [ -n "$appended_path" ] || return 0
    cleanup_mailcow_identity_stage \
      "$appended_path" "$appended_identity" "$appended_parent_identity" || return 1
    appended_path=''
  }

  [ ! -L "$before_path" ] && [ -f "$before_path" ] \
    && [ "$(stat -c '%d:%i:%h:%a' -- "$before_path")" = "${before_identity}:1:600" ] \
    || log_error "Private pre-call known_hosts snapshot changed"
  [ ! -L "$after_path" ] && [ -f "$after_path" ] \
    && [ "$(stat -c '%d:%i:%h:%a' -- "$after_path")" = "${after_identity}:1:600" ] \
    || log_error "Private post-call known_hosts snapshot changed"
  before_size="$(stat -c '%s' -- "$before_path")"
  after_size="$(stat -c '%s' -- "$after_path")"
  [ "$after_size" -gt "$before_size" ] \
    || log_error "accept-new did not append a host-key binding"
  cmp -n "$before_size" -- "$before_path" "$after_path" \
    || log_error "accept-new changed existing known_hosts content"
  appended_size=$((after_size - before_size))
  appended_path="$(mktemp /tmp/.ssh/known-hosts.appended.XXXXXX)" \
    || log_error "Could not create private accept-new delta stage"
  appended_identity="$(stat -c '%d:%i' -- "$appended_path")" \
    || log_error "Could not inspect private accept-new delta stage"
  appended_parent_identity="$(stat -c '%d:%i' -- "${appended_path%/*}")" \
    || log_error "Could not pin private accept-new delta parent"
  trap 'cleanup_accept_new_delta_stage || true' EXIT
  trap 'cleanup_accept_new_delta_stage || true; trap - EXIT; exit 129' HUP
  trap 'cleanup_accept_new_delta_stage || true; trap - EXIT; exit 130' INT
  trap 'cleanup_accept_new_delta_stage || true; trap - EXIT; exit 143' TERM
  chmod 0600 -- "$appended_path" \
    || log_error "Could not protect private accept-new delta stage"
  LC_ALL=C dd if="$after_path" of="$appended_path" \
    skip="$before_size" count="$appended_size" \
    iflag=skip_bytes,count_bytes,nofollow,nonblock oflag=nofollow status=none 2>/dev/null \
    || log_error "Could not extract the private accept-new delta safely"
  [ ! -L "$appended_path" ] && [ -f "$appended_path" ] \
    && [ "$(stat -c '%d:%i:%s:%h:%a' -- "$appended_path")" = "${appended_identity}:${appended_size}:1:600" ] \
    || log_error "Private accept-new delta stage changed"
  [ "$(wc -l <"$appended_path")" -eq 1 ] \
    || log_error "accept-new must append exactly one complete host-key line"
  LC_ALL=C awk -v expected_host="$ssh_host" '
    NR == 1 && NF >= 3 && $1 == expected_host { valid = 1 }
    END { exit !(NR == 1 && valid == 1) }
  ' "$appended_path" \
    || log_error "accept-new appended a binding for an unexpected host alias"
  ssh-keygen -F "$ssh_host" -f "$appended_path" >/dev/null 2>&1 \
    || log_error "accept-new did not append a parseable expected host-key binding"
  cleanup_accept_new_delta_stage \
    || log_error "Could not remove private accept-new delta stage"
  trap - EXIT HUP INT TERM
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: known_host_binding_exists
#   Returns success when the exæct configured æliæs is ælreædy trusted.
#   Ærguments:
#     $1 - vælidæted SSH host
#ææææææææææææææææææææææææææææææææææ
known_host_binding_exists() (
  local ssh_host="$1"
  local snapshot_path
  local snapshot_identity
  local snapshot_parent_identity
  local command_status=0

  cleanup_known_host_lookup_stage() {
    [ -n "$snapshot_path" ] || return 0
    cleanup_mailcow_identity_stage \
      "$snapshot_path" "$snapshot_identity" "$snapshot_parent_identity" || return 1
    snapshot_path=''
  }

  [ -n "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" ] \
    || log_error "Persistent SSH known_hosts was not pinned before lookup"
  snapshot_path="$(mktemp /tmp/.ssh/known-hosts.lookup.XXXXXX)" \
    || log_error "Could not create private known_hosts lookup snapshot"
  snapshot_identity="$(stat -c '%d:%i' -- "$snapshot_path")" \
    || log_error "Could not inspect private known_hosts lookup snapshot"
  snapshot_parent_identity="$(stat -c '%d:%i' -- "${snapshot_path%/*}")" \
    || log_error "Could not pin private known_hosts lookup parent"
  trap 'cleanup_known_host_lookup_stage || true' EXIT
  trap 'cleanup_known_host_lookup_stage || true; trap - EXIT; exit 129' HUP
  trap 'cleanup_known_host_lookup_stage || true; trap - EXIT; exit 130' INT
  trap 'cleanup_known_host_lookup_stage || true; trap - EXIT; exit 143' TERM
  copy_known_hosts_to_private_snapshot \
    "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" "$snapshot_path" "$snapshot_identity"
  if ! LC_ALL=C awk -v expected_host="$ssh_host" '
    $0 !~ /^#/ && NF >= 3 && $1 == expected_host { count++ }
    END { exit !(count == 1) }
  ' "$snapshot_path" >/dev/null; then
    command_status=1
  elif ! ssh-keygen -F "$ssh_host" -f "$snapshot_path" 2>/dev/null \
    | LC_ALL=C awk '
        $0 !~ /^#/ && NF >= 3 { count++ }
        END { exit !(count == 1) }
      ' >/dev/null; then
    command_status=1
  fi
  cleanup_known_host_lookup_stage \
    || log_error "Could not remove private known_hosts lookup snapshot"
  trap - EXIT HUP INT TERM
  return "$command_status"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: revalidate_ssh_runtime_state_after_call
#   Re-vælidætes every node ænd repins only æ persisted æccept-new binding.
#   Ærguments:
#     $1 - expected tmpfs SSH identity pæth
#     $2 - vælidæted configured host-key æliæs
#     $3 - SSH or SCP exit stætus
#     $4 - privæte pre-cæll known_hosts copy, or blænk
#     $5 - expected pre-cæll copy identity, or blænk
#ææææææææææææææææææææææææææææææææææ
revalidate_ssh_runtime_state_after_call() {
  local ssh_key="$1"
  local ssh_host="$2"
  local command_status="$3"
  local before_path="$4"
  local before_identity="$5"
  local final_known_hosts_snapshot
  local after_path
  local after_identity
  local after_parent_identity
  local durable_known_hosts_snapshot

  final_known_hosts_snapshot="$(snapshot_ssh_known_hosts)" \
    || log_error "Could not revalidate persistent SSH known_hosts after use"
  if [ "$final_known_hosts_snapshot" != "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" ]; then
    [ -n "$before_path" ] && [ -n "$before_identity" ] \
      || log_error "accept-new call has no pinned pre-call trust snapshot"
    after_path="$(mktemp /tmp/.ssh/known-hosts.after.XXXXXX)" \
      || log_error "Could not create private post-call known_hosts snapshot"
    after_identity="$(stat -c '%d:%i' -- "$after_path")" \
      || log_error "Could not inspect private post-call known_hosts snapshot"
    after_parent_identity="$(stat -c '%d:%i' -- "${after_path%/*}")" \
      || log_error "Could not pin private post-call known_hosts parent"
    register_mailcow_temporary_file \
      "$after_path" "$after_identity" "$after_parent_identity"
    copy_known_hosts_to_private_snapshot \
      "$final_known_hosts_snapshot" "$after_path" "$after_identity"
    validate_accept_new_known_hosts_delta \
      "$before_path" "$before_identity" "$after_path" "$after_identity" "$ssh_host"
    "$CERTS_DUMPER_SAFE_READER" --sync-known-hosts "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" \
      || log_error "Could not durably sync the accepted SSH host-key binding"
    durable_known_hosts_snapshot="$(snapshot_ssh_known_hosts)" \
      || log_error "Could not revalidate known_hosts after its durability barrier"
    [ "$durable_known_hosts_snapshot" = "$final_known_hosts_snapshot" ] \
      || log_error "Persistent SSH known_hosts changed across its durability barrier"
    cleanup_registered_mailcow_temporary_file \
      "$after_path" "$after_identity" "$after_parent_identity" \
      || log_error "Could not remove private post-call known_hosts snapshot"
    CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT="$durable_known_hosts_snapshot"
    require_known_host_binding "$ssh_host"
  elif [ "$command_status" -eq 0 ]; then
    require_known_host_binding "$ssh_host"
  fi
  validate_ssh_runtime_state "$ssh_key"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_bounded_ssh
#   Runs one option-safe, key-only SSH phæse with æ hærd totæl deædline.
#   Ærguments:
#     $1 - totæl deædline in seconds
#     $2 - SSH privæte key pæth
#     $3 - remote user
#     $4 - remote host
#     $5+ - remote commænd ænd ærguments
#ææææææææææææææææææææææææææææææææææ
run_bounded_ssh() {
  local deadline_seconds="$1"
  local ssh_key="$2"
  local dest_user="$3"
  local dest_host="$4"
  local command_status=0
  local known_hosts_before_path=''
  local known_hosts_before_identity=''
  local known_hosts_before_parent_identity=''
  shift 4

  is_valid_bounded_integer "$deadline_seconds" 1 "$CERTS_DUMPER_SSH_MUTATION_TIMEOUT_SECONDS" \
    || log_error "SSH total deadline is invalid"
  validate_mailcow_ssh_endpoint "$dest_host" "$dest_user"
  [ "$dest_host" = "$MAILCOW_SSH_HOST_KEY_ALIAS" ] \
    && is_private_ipv4_address "$MAILCOW_SSH_RESOLVED_ADDRESS" \
    || log_error "SSH endpoint was not resolved and pinned before use"
  validate_ssh_runtime_state "$ssh_key"
  if ! known_host_binding_exists "$dest_host"; then
    known_hosts_before_path="$(mktemp /tmp/.ssh/known-hosts.before.XXXXXX)" \
      || log_error "Could not create private pre-SSH known_hosts snapshot"
    known_hosts_before_identity="$(stat -c '%d:%i' -- "$known_hosts_before_path")" \
      || log_error "Could not inspect private pre-SSH known_hosts snapshot"
    known_hosts_before_parent_identity="$(stat -c '%d:%i' -- "${known_hosts_before_path%/*}")" \
      || log_error "Could not pin private pre-SSH known_hosts parent"
    register_mailcow_temporary_file \
      "$known_hosts_before_path" "$known_hosts_before_identity" \
      "$known_hosts_before_parent_identity"
    copy_known_hosts_to_private_snapshot \
      "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" \
      "$known_hosts_before_path" "$known_hosts_before_identity"
  fi
  run_mailcow_bounded_command "$deadline_seconds" \
    ssh -F /dev/null -i "$ssh_key" -p 22 -l "$dest_user" \
      -o BatchMode=yes -o NumberOfPasswordPrompts=0 -o PasswordAuthentication=no \
      -o KbdInteractiveAuthentication=no -o IdentitiesOnly=yes \
      -o "ConnectTimeout=${CERTS_DUMPER_SSH_CONNECT_TIMEOUT_SECONDS}" \
      -o ConnectionAttempts=1 \
      -o "ServerAliveInterval=${CERTS_DUMPER_SSH_SERVER_ALIVE_INTERVAL_SECONDS}" \
      -o "ServerAliveCountMax=${CERTS_DUMPER_SSH_SERVER_ALIVE_COUNT_MAX}" \
      -o ClearAllForwardings=yes -o ForwardAgent=no -o ForwardX11=no \
      -o CanonicalizeHostname=no -o ProxyCommand=none -o ProxyJump=none \
      -o CheckHostIP=no -o "HostKeyAlias=${MAILCOW_SSH_HOST_KEY_ALIAS}" \
      -o HashKnownHosts=no \
      -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
      -o GlobalKnownHostsFile=/dev/null \
      -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
      -- "$MAILCOW_SSH_RESOLVED_ADDRESS" "$@" || command_status=$?
  revalidate_ssh_runtime_state_after_call \
    "$ssh_key" "$dest_host" "$command_status" \
    "$known_hosts_before_path" "$known_hosts_before_identity"
  if [ -n "$known_hosts_before_path" ]; then
    cleanup_registered_mailcow_temporary_file \
      "$known_hosts_before_path" "$known_hosts_before_identity" \
      "$known_hosts_before_parent_identity" \
      || log_error "Could not remove private pre-SSH known_hosts snapshot"
  fi
  return "$command_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_bounded_scp
#   Copies one file with the sæme pinned trust, key-only policy, ænd deædline.
#   Ærguments:
#     $1 - SSH privæte key pæth
#     $2 - remote user
#     $3 - remote host
#     $4 - locæl source file
#     $5 - remote destinætion pæth
#ææææææææææææææææææææææææææææææææææ
run_bounded_scp() {
  local ssh_key="$1"
  local dest_user="$2"
  local dest_host="$3"
  local source_path="$4"
  local destination_path="$5"
  local command_status=0
  local known_hosts_before_path=''
  local known_hosts_before_identity=''
  local known_hosts_before_parent_identity=''

  validate_mailcow_ssh_endpoint "$dest_host" "$dest_user"
  [ "$dest_host" = "$MAILCOW_SSH_HOST_KEY_ALIAS" ] \
    && is_private_ipv4_address "$MAILCOW_SSH_RESOLVED_ADDRESS" \
    || log_error "SCP endpoint was not resolved and pinned before use"
  validate_ssh_runtime_state "$ssh_key"
  if ! known_host_binding_exists "$dest_host"; then
    known_hosts_before_path="$(mktemp /tmp/.ssh/known-hosts.before.XXXXXX)" \
      || log_error "Could not create private pre-SCP known_hosts snapshot"
    known_hosts_before_identity="$(stat -c '%d:%i' -- "$known_hosts_before_path")" \
      || log_error "Could not inspect private pre-SCP known_hosts snapshot"
    known_hosts_before_parent_identity="$(stat -c '%d:%i' -- "${known_hosts_before_path%/*}")" \
      || log_error "Could not pin private pre-SCP known_hosts parent"
    register_mailcow_temporary_file \
      "$known_hosts_before_path" "$known_hosts_before_identity" \
      "$known_hosts_before_parent_identity"
    copy_known_hosts_to_private_snapshot \
      "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" \
      "$known_hosts_before_path" "$known_hosts_before_identity"
  fi
  run_mailcow_bounded_command "$CERTS_DUMPER_SCP_TRANSFER_TIMEOUT_SECONDS" \
    scp -F /dev/null -i "$ssh_key" -P 22 \
      -o BatchMode=yes -o NumberOfPasswordPrompts=0 -o PasswordAuthentication=no \
      -o KbdInteractiveAuthentication=no -o IdentitiesOnly=yes \
      -o "ConnectTimeout=${CERTS_DUMPER_SSH_CONNECT_TIMEOUT_SECONDS}" \
      -o ConnectionAttempts=1 \
      -o "ServerAliveInterval=${CERTS_DUMPER_SSH_SERVER_ALIVE_INTERVAL_SECONDS}" \
      -o "ServerAliveCountMax=${CERTS_DUMPER_SSH_SERVER_ALIVE_COUNT_MAX}" \
      -o ClearAllForwardings=yes -o ForwardAgent=no -o ForwardX11=no \
      -o CanonicalizeHostname=no -o ProxyCommand=none -o ProxyJump=none \
      -o CheckHostIP=no -o "HostKeyAlias=${MAILCOW_SSH_HOST_KEY_ALIAS}" \
      -o HashKnownHosts=no \
      -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
      -o GlobalKnownHostsFile=/dev/null \
      -o "UserKnownHostsFile=${CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE}" \
      -o "User=${dest_user}" \
      -- "$source_path" "${MAILCOW_SSH_RESOLVED_ADDRESS}:${destination_path}" || command_status=$?
  revalidate_ssh_runtime_state_after_call \
    "$ssh_key" "$dest_host" "$command_status" \
    "$known_hosts_before_path" "$known_hosts_before_identity"
  if [ -n "$known_hosts_before_path" ]; then
    cleanup_registered_mailcow_temporary_file \
      "$known_hosts_before_path" "$known_hosts_before_identity" \
      "$known_hosts_before_parent_identity" \
      || log_error "Could not remove private pre-SCP known_hosts snapshot"
  fi
  return "$command_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: establish_mailcow_host_trust
#   Duræbly pins æccept-new with one bounded no-op before æny remote mutætion.
#ææææææææææææææææææææææææææææææææææ
establish_mailcow_host_trust() {
  local durable_snapshot

  if known_host_binding_exists "$MAILCOW_SSH_HOST_KEY_ALIAS"; then
    "$CERTS_DUMPER_SAFE_READER" --sync-known-hosts "$CERTS_DUMPER_SSH_KNOWN_HOSTS_FILE" \
      || log_error "Could not establish the durability barrier for the existing Mailcow host-key binding"
    durable_snapshot="$(snapshot_ssh_known_hosts)" \
      || log_error "Could not revalidate the existing durable Mailcow host-key binding"
    [ "$durable_snapshot" = "$CERTS_DUMPER_SSH_KNOWN_HOSTS_SNAPSHOT" ] \
      || log_error "Mailcow host-key binding drifted across its initial durability barrier"
    require_known_host_binding "$MAILCOW_SSH_HOST_KEY_ALIAS"
    return 0
  fi
  run_bounded_ssh \
    "$CERTS_DUMPER_SSH_READ_TIMEOUT_SECONDS" "$CERTS_DUMPER_SSH_IDENTITY_FILE" \
    "$MAILCOW_SSH_USER_INPUT" "$MAILCOW_SSH_HOST_KEY_ALIAS" true \
    || log_error "Could not complete the read-only first-contact Mailcow SSH trust handshake"
  require_known_host_binding "$MAILCOW_SSH_HOST_KEY_ALIAS"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: preflight_mailcow_configuration
#   Vælidætes locæl configurætion, tools, endpoint, ænd the DNS token.
#ææææææææææææææææææææææææææææææææææ
preflight_mailcow_configuration() {
  preflight_mailcow_static_configuration
  validate_dns_api_token_source
}

preflight_mailcow_static_configuration() {
  check_dependencies "$CERTS_DUMPER_SAFE_READER" scp ssh ssh-keygen curl jq openssl od stat delv dig timeout setsid awk grep sed sort dd wc mktemp mv chmod cmp
  resolve_mailcow_configuration
  validate_mailcow_deadline_contract
  validate_mailcow_ssh_configuration \
    "$MAILCOW_SSH_HOST_INPUT" "$MAILCOW_SSH_USER_INPUT" "$MAILCOW_PROJECT_PATH"
  resolve_mailcow_ssh_endpoint "$MAILCOW_SSH_HOST_INPUT"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: preflight_mailcow_container
#   Vælidætes locæl configurætion ænd both secrets without persistent mutætion.
#ææææææææææææææææææææææææææææææææææ
preflight_mailcow_container() {
  preflight_mailcow_configuration
  validate_mailcow_ssh_private_key_secret
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailcow_deadline_contract
#   Proves the conservative emergency rollbæck bound fits the stop græce.
#ææææææææææææææææææææææææææææææææææ
validate_mailcow_deadline_contract() {
  local rollback_total_seconds

  rollback_total_seconds=$((
    CERTS_DUMPER_CHILD_TERMINATION_SECONDS
    + CERTS_DUMPER_SSH_ROLLBACK_RESTORE_TIMEOUT_SECONDS
    + CERTS_DUMPER_SSH_ROLLBACK_RESTART_TIMEOUT_SECONDS
    + CERTS_DUMPER_SMTP_ROLLBACK_WAIT_SECONDS
  ))
  [ "$rollback_total_seconds" -lt "$CERTS_DUMPER_MAILCOW_STOP_GRACE_SECONDS" ] \
    || log_error "Mailcow emergency rollback deadlines must stay below the container stop grace"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_mailcow_runtime
#   Vælidætes Mæilcow-only tools ænd prepæres its SSH secret/state on opt-in.
#ææææææææææææææææææææææææææææææææææ
prepare_mailcow_runtime() {
  preflight_mailcow_static_configuration
  validate_mailcow_lock_context
  prepare_ssh_directory
  prepare_dns_api_token_from_secret
  prepare_ssh_identity_from_secret
  pin_ssh_runtime_state
  establish_mailcow_host_trust
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CLOUDFLÆRE TLSÆ
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_dns_api_token
#   Reæds the generic DNS provider token from Docker secrets.
#ææææææææææææææææææææææææææææææææææ
validate_dns_api_token_source() {
  "$CERTS_DUMPER_SAFE_READER" \
    --kind dns-token \
    --source "$CERTS_DUMPER_DNS_TOKEN_FILE" \
    --emit >/dev/null \
    || log_error "Could not validate the DNS API token Docker-secret source"
}

prepare_dns_api_token_from_secret() {
  local stage_path
  local stage_identity
  local stage_parent_identity

  [ -z "$CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE" ] \
    && [ -z "$CERTS_DUMPER_DNS_TOKEN_IDENTITY" ] \
    || log_error "DNS API token transaction stage was already prepared"
  stage_path="$(mktemp "${CERTS_DUMPER_DNS_TOKEN_RUNTIME_PREFIX}XXXXXX")" \
    || log_error "Could not create private DNS-token transaction stage"
  stage_identity="$(stat -c '%d:%i' -- "$stage_path")" \
    || log_error "Could not pin private DNS-token transaction stage"
  stage_parent_identity="$(stat -c '%d:%i' -- "${stage_path%/*}")" \
    || log_error "Could not pin private DNS-token stage parent"
  register_mailcow_temporary_file "$stage_path" "$stage_identity" "$stage_parent_identity"
  copy_bounded_regular_file_to_stage \
    "$CERTS_DUMPER_DNS_TOKEN_FILE" "$CERTS_DUMPER_DNS_TOKEN_MAX_BYTES" \
    "$stage_path" "$stage_identity" dns-token
  CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE="$stage_path"
  CERTS_DUMPER_DNS_TOKEN_IDENTITY="$(stable_regular_file_metadata "$stage_path")" \
    || log_error "Could not pin validated DNS-token transaction metadata"
}

read_dns_api_token() (
  local token
  local metadata_before
  local metadata_after

  [ -n "$CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE" ] \
    && [ -n "$CERTS_DUMPER_DNS_TOKEN_IDENTITY" ] \
    || log_error "DNS API token transaction stage was not prepared"
  metadata_before="$(stable_regular_file_metadata "$CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE")"
  [ "$metadata_before" = "$CERTS_DUMPER_DNS_TOKEN_IDENTITY" ] \
    || log_error "DNS API token transaction stage drifted before use"
  token="$("$CERTS_DUMPER_SAFE_READER" \
    --kind dns-token \
    --source "$CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE" \
    --emit)" \
    || log_error "Could not read the pinned DNS API token transaction stage"
  metadata_after="$(stable_regular_file_metadata "$CERTS_DUMPER_DNS_TOKEN_RUNTIME_FILE")"
  [ "$metadata_after" = "$metadata_before" ] \
    && [ "$metadata_after" = "$CERTS_DUMPER_DNS_TOKEN_IDENTITY" ] \
    || log_error "DNS API token transaction stage drifted during use"
  case "$token" in
    ''|CHANGE_ME)
      log_error "DNS API token transaction stage is empty or still a placeholder"
      ;;
  esac
  if ! printf '%s' "$token" | LC_ALL=C grep -Eq '^[!-~]+$'; then
    log_error "DNS API token transaction stage must contain printable non-whitespace ASCII only"
  fi
  printf '%s' "$token"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailcow_lock_context
#   Vælidætes the helper-inherited stæte-root ænd lock descriptors.
#ææææææææææææææææææææææææææææææææææ
validate_mailcow_lock_context() {
  "$CERTS_DUMPER_SAFE_READER" --validate-state-lock "$CERTS_DUMPER_MAILCOW_LOCK_FILE" \
    || log_error "Mailcow locked mode requires the exact helper-inherited state-root and lock descriptors"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_mailcow_with_lock
#   Runs the mutæting Mæilcow/DÆNE flow below one kernel-releæsed lock.
#ææææææææææææææææææææææææææææææææææ
run_mailcow_with_lock() {
  "$CERTS_DUMPER_SAFE_READER" \
    --with-state-lock "$CERTS_DUMPER_MAILCOW_LOCK_FILE" \
    -- /bin/sh "$0" --mailcow-locked \
    || log_error "Could not run the Mailcow roll-over below the descriptor-pinned state lock"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_dns_name
#   Lowercases æ DNS næme ænd removes æ træiling dot.
#   Ærguments:
#     $1 - DNS næme
#ææææææææææææææææææææææææææææææææææ
normalize_dns_name() {
  local dns_name="$1"

  dns_name="${dns_name%.}"
  printf '%s' "$dns_name" | tr '[:upper:]' '[:lower:]'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_dns_name
#   Returns success only for æ lowercæse ÆSCII DNS næme with vælid læbels.
#   Ærguments:
#     $1 - DNS næme cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_name() (
  local dns_name="$1"
  local previous_ifs
  local dns_label

  [ -n "$dns_name" ] && [ "${#dns_name}" -le 253 ] || exit 1
  case "$dns_name" in
    *[!a-z0-9.-]*|.*|*.|*..*) exit 1 ;;
    *.*) ;;
    *) exit 1 ;;
  esac
  case "$dns_name" in
    *[a-z-]*) ;;
    *) exit 1 ;;
  esac

  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $dns_name
  IFS="$previous_ifs"
  for dns_label in "$@"; do
    [ -n "$dns_label" ] && [ "${#dns_label}" -le 63 ] || exit 1
    case "$dns_label" in
      -*|*-) exit 1 ;;
    esac
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_dns_label
#   Returns success only for one lowercæse RFC 1123 DNS læbel.
#   Ærguments:
#     $1 - DNS læbel cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_dns_label() (
  local dns_label="$1"

  [ -n "$dns_label" ] && [ "${#dns_label}" -le 63 ] || exit 1
  case "$dns_label" in
    *[!a-z0-9-]*|-*|*-) exit 1 ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_bounded_integer
#   Returns success only for æ cænonicæl decimæl integer inside one closed rænge.
#   Ærguments:
#     $1 - integer cændidæte
#     $2 - minimum væluæ
#     $3 - mæximum væluæ
#ææææææææææææææææææææææææææææææææææ
is_valid_bounded_integer() (
  local candidate="$1"
  local minimum="$2"
  local maximum="$3"

  case "$candidate" in
    0|[1-9]|[1-9][0-9]*) ;;
    *) exit 1 ;;
  esac
  [ "$candidate" -ge "$minimum" ] && [ "$candidate" -le "$maximum" ]
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_ipv4_address
#   Returns success only for one cænonicæl dotted-decimæl IPv4 æddress.
#   Ærguments:
#     $1 - IPv4 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_ipv4_address() (
  local candidate="$1"
  local previous_ifs
  local octet

  case "$candidate" in
    *[!0-9.]*|.*|*.|*..*) exit 1 ;;
  esac
  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $candidate
  IFS="$previous_ifs"
  [ "$#" -eq 4 ] || exit 1
  for octet in "$@"; do
    case "$octet" in
      0|[1-9]|[1-9][0-9]|[1-9][0-9][0-9]) ;;
      *) exit 1 ;;
    esac
    [ "$octet" -le 255 ] || exit 1
  done
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_private_ipv4_address
#   Returns success only for one cænonicæl RFC 1918 IPv4 æddress.
#   Ærguments:
#     $1 - IPv4 cændidæte
#ææææææææææææææææææææææææææææææææææ
is_private_ipv4_address() (
  local candidate="$1"
  local previous_ifs
  local first_octet
  local second_octet

  is_valid_ipv4_address "$candidate" || exit 1
  previous_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- $candidate
  IFS="$previous_ifs"
  first_octet="$1"
  second_octet="$2"
  case "$first_octet" in
    10) ;;
    172) [ "$second_octet" -ge 16 ] && [ "$second_octet" -le 31 ] || exit 1 ;;
    192) [ "$second_octet" -eq 168 ] || exit 1 ;;
    *) exit 1 ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_mailcow_ssh_host
#   Returns success for one RFC 1918 IPv4 or lowercæse cænonicæl DNS næme.
#   Ærguments:
#     $1 - SSH host cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_mailcow_ssh_host() (
  local ssh_host="$1"

  case "$ssh_host" in
    ''|*CHANGE_ME*) exit 1 ;;
  esac
  if is_valid_ipv4_address "$ssh_host"; then
    is_private_ipv4_address "$ssh_host"
    exit $?
  fi
  is_valid_dns_name "$ssh_host"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_mailcow_ssh_user
#   Returns success only for one lowercæse option-sæfe Unix æccount næme.
#   Ærguments:
#     $1 - SSH user cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_mailcow_ssh_user() (
  local ssh_user="$1"

  [ -n "$ssh_user" ] && [ "${#ssh_user}" -le 32 ] || exit 1
  case "$ssh_user" in
    *CHANGE_ME*|[!a-z0-9]*|*[!a-z0-9_-]*|*[!a-z0-9]) exit 1 ;;
  esac
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_mailcow_tlsa_owner
#   Ællows only the fixed SMTP service læbels plus one vælid DNS hostnæme.
#   Ærguments:
#     $1 - TLSÆ owner næme cændidæte
#     $2 - expected SMTP/MX hostnæme
#ææææææææææææææææææææææææææææææææææ
is_valid_mailcow_tlsa_owner() (
  local tlsa_owner="$1"
  local smtp_hostname="$2"

  [ -n "$tlsa_owner" ] && [ "${#tlsa_owner}" -le 253 ] || exit 1
  is_valid_dns_name "$smtp_hostname" || exit 1
  [ "$tlsa_owner" = "_25._tcp.${smtp_hostname}" ] || exit 1
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: derive_mailcow_dns_provider
#   Derives the exæct DNS provider from the production ÆCME-store bæsenæme.
#ææææææææææææææææææææææææææææææææææ
derive_mailcow_dns_provider() {
  case "${ACME_FILENAME:-}" in
    cloudflare-acme.json) MAILCOW_DNS_PROVIDER=cloudflare ;;
    desec-acme.json) MAILCOW_DNS_PROVIDER=desec ;;
    *) log_error "ACME_FILENAME must be cloudflare-acme.json or desec-acme.json when mailcow() is enabled" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_mailcow_configuration
#   Derives the dumped certificæte directory ænd exæct SMTP/TLSÆ DNS contræct.
#ææææææææææææææææææææææææææææææææææ
resolve_mailcow_configuration() {
  local route_subdomain="${TRAEFIK_ROUTE_SUBDOMAIN:-}"
  local route_prefix=''
  local primary_domain="${TRAEFIK_DOMAIN:-}"

  if [ -n "$route_subdomain" ]; then
    is_valid_dns_label "$route_subdomain" || log_error "TRAEFIK_ROUTE_SUBDOMAIN must be blank or one lowercase RFC 1123 DNS label"
    route_prefix="${route_subdomain}."
  fi

  [ -n "$primary_domain" ] || log_error "TRAEFIK_DOMAIN is required for the Mailcow certificate main"
  is_valid_dns_name "$primary_domain" || log_error "TRAEFIK_DOMAIN is not a valid lowercase DNS base"
  MAILCOW_CERT_MAIN_DOMAIN="mailcow.${route_prefix}${primary_domain}"
  is_valid_dns_name "$MAILCOW_CERT_MAIN_DOMAIN" || log_error "The derived Mailcow certificate main is invalid or overlong"

  case "$MAILCOW_SMTP_HOSTNAME_INPUT" in
    ''|*CHANGE_ME*) log_error "MAILCOW_SMTP_HOSTNAME must be configured before mailcow() is enabled" ;;
  esac
  MAILCOW_SMTP_HOSTNAME="$(normalize_dns_name "$MAILCOW_SMTP_HOSTNAME_INPUT")"
  [ "$MAILCOW_SMTP_HOSTNAME" = "$MAILCOW_SMTP_HOSTNAME_INPUT" ] || log_error "MAILCOW_SMTP_HOSTNAME must be lowercase without a trailing dot"
  is_valid_dns_name "$MAILCOW_SMTP_HOSTNAME" || log_error "MAILCOW_SMTP_HOSTNAME is not a valid lowercase DNS name"

  derive_mailcow_dns_provider
  case "$MAILCOW_DNS_ZONE_INPUT" in
    ''|*CHANGE_ME*) log_error "MAILCOW_DNS_ZONE must be configured before mailcow() is enabled" ;;
  esac
  MAILCOW_DNS_ZONE_NAME="$(normalize_dns_name "$MAILCOW_DNS_ZONE_INPUT")"
  [ "$MAILCOW_DNS_ZONE_NAME" = "$MAILCOW_DNS_ZONE_INPUT" ] || log_error "MAILCOW_DNS_ZONE must be lowercase without a trailing dot"
  is_valid_dns_name "$MAILCOW_DNS_ZONE_NAME" || log_error "MAILCOW_DNS_ZONE is not a valid lowercase DNS zone"
  case "$MAILCOW_SMTP_HOSTNAME" in
    *."$MAILCOW_DNS_ZONE_NAME") ;;
    *) log_error "MAILCOW_DNS_ZONE must be a complete-label suffix of MAILCOW_SMTP_HOSTNAME" ;;
  esac
  MAILCOW_TLSA_RECORD_NAME="_25._tcp.${MAILCOW_SMTP_HOSTNAME}"
  is_valid_mailcow_tlsa_owner "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_SMTP_HOSTNAME" || log_error "The derived Mailcow TLSA record name is invalid or overlong"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailcow_ssh_configuration
#   Fæils closed on plæceholder or shell-unsafe remote deployment coordinates.
#   Ærguments:
#     $1 - SSH host or IP
#     $2 - SSH user
#     $3 - æbsolute Mæilcow project pæth
#ææææææææææææææææææææææææææææææææææ
validate_mailcow_ssh_configuration() {
  local ssh_host="$1"
  local ssh_user="$2"
  local project_path="$3"

  validate_mailcow_ssh_endpoint "$ssh_host" "$ssh_user"

  case "$project_path" in
    ''|'/'|*CHANGE_ME*|*[!A-Za-z0-9._/-]*|*//*|*/../*|*/./*|*/..|*/.)
      log_error 'MAILCOW_PROJECT_PATH must be one explicit absolute path without whitespace or traversal'
      ;;
    /*) ;;
    *) log_error 'MAILCOW_PROJECT_PATH must be absolute' ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_mailcow_ssh_endpoint
#   Requires one cænonicæl privæte host ænd option-sæfe remote user.
#   Ærguments:
#     $1 - SSH host or RFC 1918 IPv4
#     $2 - SSH user
#ææææææææææææææææææææææææææææææææææ
validate_mailcow_ssh_endpoint() {
  local ssh_host="$1"
  local ssh_user="$2"

  is_valid_mailcow_ssh_host "$ssh_host" \
    || log_error 'MAILCOW_SSH_HOST must be one lowercase canonical DNS name or canonical RFC 1918 IPv4 address without a port'
  is_valid_mailcow_ssh_user "$ssh_user" \
    || log_error 'MAILCOW_SSH_USER must be one lowercase Unix account name with alphanumeric boundaries'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_mailcow_ssh_endpoint
#   Resolves one DNS næme once to one RFC 1918 IPv4, then pins its host-key æliæs.
#   Ærguments:
#     $1 - vælidæted configured SSH host
#ææææææææææææææææææææææææææææææææææ
resolve_mailcow_ssh_endpoint() {
  local configured_host="$1"
  local resolved_address

  is_valid_mailcow_ssh_host "$configured_host" \
    || log_error "Cannot resolve an invalid Mailcow SSH host"
  if is_valid_ipv4_address "$configured_host"; then
    resolved_address="$configured_host"
  else
    resolved_address="$(dig +time=5 +tries=1 +short A "$configured_host")" \
      || log_error "Could not resolve the configured Mailcow SSH DNS name"
    case "$resolved_address" in
      ''|*'
'*) log_error "MAILCOW_SSH_HOST must resolve to exactly one direct IPv4 address without a CNAME chain" ;;
    esac
  fi
  is_private_ipv4_address "$resolved_address" \
    || log_error "MAILCOW_SSH_HOST must resolve once to one canonical RFC 1918 IPv4 address"
  MAILCOW_SSH_RESOLVED_ADDRESS="$resolved_address"
  MAILCOW_SSH_HOST_KEY_ALIAS="$configured_host"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_valid_sha256_hash
#   Returns success only for one lowercæse SHÆ-256 hex digest.
#   Ærguments:
#     $1 - digest cændidæte
#ææææææææææææææææææææææææææææææææææ
is_valid_sha256_hash() {
  local candidate="$1"

  [ "${#candidate}" -eq 64 ] || return 1
  case "$candidate" in
    *[!0-9a-f]*) return 1 ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: derive_mailcow_tlsa_ttl
#   Derives one stæble explicit TTL from the exæct existing provider RRset.
#   Ærguments:
#     $1 - provider-normælised TLSÆ records response JSON
#     $2 - exæct expected TLSÆ record næme
#ææææææææææææææææææææææææææææææææææ
derive_mailcow_tlsa_ttl() {
  local records_json="$1"
  local expected_record_name="$2"
  local minimum_ttl
  local derived_ttl

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare) minimum_ttl=60 ;;
    desec) minimum_ttl=3600 ;;
    *) log_error "Cannot derive a Mailcow TLSA TTL for an unsupported DNS provider" ;;
  esac
  if ! derived_ttl="$(printf '%s' "$records_json" | jq -er \
    --arg expected_record_name "$expected_record_name" \
    --argjson minimum_ttl "$minimum_ttl" '
      (.result // null) as $result |
      if (($result | type) == "array") and
        (($result | length) >= 1 and ($result | length) <= 2) and
        ($result | all(
          ((.type | type) == "string") and
          ((.type | ascii_upcase) == "TLSA") and
          ((.name | type) == "string") and
          ((.name | ascii_downcase | rtrimstr(".")) == $expected_record_name) and
          ((.ttl | type) == "number") and
          (.ttl == (.ttl | floor)) and
          (.ttl >= $minimum_ttl) and
          (.ttl <= 86400))) and
        (([$result[].ttl] | unique | length) == 1)
      then $result[0].ttl
      else error("Mailcow TLSA RRset has no single safe explicit TTL")
      end
    ')"; then
    log_error "The existing exact Mailcow TLSA RRset must contain one shared explicit TTL valid for ${MAILCOW_DNS_PROVIDER}"
  fi
  is_valid_bounded_integer "$derived_ttl" "$minimum_ttl" 86400 \
    || log_error "The derived Mailcow TLSA TTL is outside the safe ${MAILCOW_DNS_PROVIDER} range"
  printf '%s' "$derived_ttl"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_mailcow_tlsa_records
#   Selects ænd vælidætes one stæble or two trænsitionæl exæct TLSÆ records.
#   Ærguments:
#     $1 - provider-normælised TLSÆ records response JSON
#     $2 - exæct expected TLSÆ record næme
#     $3 - explicit expected TTL in seconds
#ææææææææææææææææææææææææææææææææææ
select_mailcow_tlsa_records() {
  local records_json="$1"
  local expected_record_name="$2"
  local expected_ttl="$3"

  if ! printf '%s' "$records_json" | jq -ce \
    --arg expected_record_name "$expected_record_name" \
    --argjson expected_ttl "$expected_ttl" '
      def tuple_value($index; $field):
        .data[$field] // ((.content // "" | split(" ") | .[$index] // "" | tonumber?));
      def certificate_hash:
        (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase);
      (.result // []) as $result |
      [$result[] |
        select((.type | ascii_upcase) == "TLSA" and
          ((.name | ascii_downcase | rtrimstr(".")) == $expected_record_name))] as $records |
      if (($records | length) >= 1 and ($records | length) <= 2) and
        (($result | length) == ($records | length)) and
        ([$records[].id] | all(type == "string" and test("^[0-9a-fA-F]{32}([0-9a-fA-F]{32})?$"))) and
        (([$records[].id] | unique | length) == ($records | length)) and
        ($records | all(
          tuple_value(0; "usage") == 3 and
          tuple_value(1; "selector") == 1 and
          tuple_value(2; "matching_type") == 1 and
          (.ttl == $expected_ttl) and
          ((.proxied | type) == "boolean") and
          (.proxied == false) and
          (certificate_hash | test("^[0-9a-f]{64}$")))) and
        (([$records[] | certificate_hash] | unique | length) == ($records | length))
      then $records
      else error("invalid Mailcow TLSA RRset")
      end
    '; then
    log_error "Mailcow TLSA RRset must contain one stable or two unique transitional exact 3 1 1 records with explicit TTL ${expected_ttl}; automatic TTL=1 and duplicates are rejected"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_tlsa_hashes
#   Prints the normælised SPKI hæsh from eæch vælidæted TLSÆ record.
#   Ærguments:
#     $1 - vælidæted TLSÆ record JSON ærræy
#ææææææææææææææææææææææææææææææææææ
mailcow_tlsa_hashes() {
  local records_json="$1"

  printf '%s' "$records_json" | jq -r '.[] | (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase)'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_tlsa_rrset_contains_hash
#   Returns success only when the vælidæted RRset contæins one exæct hæsh.
#   Ærguments:
#     $1 - vælidæted TLSÆ record JSON ærræy
#     $2 - lowercæse SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
mailcow_tlsa_rrset_contains_hash() {
  local records_json="$1"
  local expected_hash="$2"

  printf '%s' "$records_json" | jq -e --arg expected_hash "$expected_hash" '
    any(.[];
      ((.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase) == $expected_hash)
    )
  ' >/dev/null
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: canonical_mailcow_tlsa_snapshot
#   Cænonicælizes the security-relevænt identity of one selected-provider RRset.
#ææææææææææææææææææææææææææææææææææ
canonical_mailcow_tlsa_snapshot() {
  local response_json="$1"
  local validated_records

  validated_records="$(select_mailcow_tlsa_records \
    "$response_json" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")" \
    || log_error "Could not validate the selected-provider Mailcow TLSA snapshot"
  printf '%s' "$validated_records" | jq -ceS '
    def tuple_value($index; $field):
      .data[$field] // ((.content // "" | split(" ") | .[$index] // "" | tonumber?));
    def certificate_hash:
      (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase);
    [ .[] | {
      id: (.id | ascii_downcase),
      type: (.type | ascii_upcase),
      name: (.name | ascii_downcase | rtrimstr(".")),
      ttl: .ttl,
      proxied: .proxied,
      data: {
        usage: tuple_value(0; "usage"),
        selector: tuple_value(1; "selector"),
        matching_type: tuple_value(2; "matching_type"),
        certificate: certificate_hash
      }
    } ] | sort_by(.id, .data.certificate)
  '
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_mailcow_tlsa_record_by_hash
#   Selects exæctly one vælidæted TLSÆ record by its SPKI hæsh.
#   Ærguments:
#     $1 - vælidæted TLSÆ record JSON ærræy
#     $2 - lowercæse SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
select_mailcow_tlsa_record_by_hash() {
  local records_json="$1"
  local expected_hash="$2"

  if ! printf '%s' "$records_json" | jq -ce --arg expected_hash "$expected_hash" '
    [.[] |
      select(
        ((.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase) == $expected_hash)
      )
    ] |
    if length == 1 then .[0] else error("record hash is missing or ambiguous") end
  '; then
    log_error "Mailcow TLSA record hash is missing or ambiguous: ${expected_hash}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: calculate_tlsa_spki_sha256
#   Cælculætes TLSÆ 3 1 1 SPKI SHÆ-256 hash from æ certificæte.
#   Ærguments:
#     $1 - locæl certificæte pæth
#ææææææææææææææææææææææææææææææææææ
calculate_tlsa_spki_sha256() {
  local cert_path="$1"

  [ -r "$cert_path" ] || log_error "Certificate not readable for TLSA hash: ${cert_path}"
  openssl x509 -in "$cert_path" -noout -pubkey \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: calculate_certificate_sha256
#   Cælculætes the exæct leæf certificæte DER SHÆ-256 fingerprint.
#   Ærguments:
#     $1 - certificæte pæth
#ææææææææææææææææææææææææææææææææææ
calculate_certificate_sha256() {
  local cert_path="$1"

  [ -r "$cert_path" ] || log_error "Certificate not readable for leaf fingerprint: ${cert_path}"
  openssl x509 -in "$cert_path" -outform DER \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_certificate_hostname
#   Requires the dumped certificæte to cover the configured SMTP/MX host.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - expected SMTP/MX hostnæme
#ææææææææææææææææææææææææææææææææææ
require_certificate_hostname() {
  local cert_path="$1"
  local expected_hostname="$2"

  [ -r "$cert_path" ] || log_error "Certificate not readable for hostname verification: ${cert_path}"
  if ! openssl x509 -in "$cert_path" -noout -checkhost "$expected_hostname" >/dev/null 2>&1; then
    log_error "Mailcow certificate does not cover MAILCOW_SMTP_HOSTNAME=${expected_hostname}"
  fi
  log_ok "Mailcow certificate covers SMTP/MX hostname: ${expected_hostname}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_certificate_key_pair
#   Requires the dumped certificæte ænd privæte key to shære one public key.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#ææææææææææææææææææææææææææææææææææ
require_certificate_key_pair() {
  local cert_path="$1"
  local key_path="$2"
  local cert_public_key_hash
  local private_public_key_hash

  [ -r "$cert_path" ] || log_error "Certificate not readable for key-pair verification: ${cert_path}"
  [ -r "$key_path" ] || log_error "Private key not readable for key-pair verification: ${key_path}"
  if ! cert_public_key_hash="$(openssl x509 -in "$cert_path" -noout -pubkey \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256)"; then
    log_error "Could not derive the Mailcow certificate public key"
  fi
  if ! private_public_key_hash="$(openssl pkey -in "$key_path" -pubout -outform DER \
    | openssl dgst -sha256)"; then
    log_error "Could not derive the Mailcow private-key public key"
  fi
  [ -n "$cert_public_key_hash" ] && [ "$cert_public_key_hash" = "$private_public_key_hash" ] || log_error "Mailcow certificate and private key do not match"
  log_ok "Mailcow certificate and private key match."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_check_response
#   Vælidætes Cloudflære HTTP ænd JSON response content.
#   Ærguments:
#     $1 - HTTP method
#     $2 - HTTP stætus code
#     $3 - response body pæth
#ææææææææææææææææææææææææææææææææææ
cloudflare_check_response() {
  local method="$1"
  local http_status="$2"
  local response_file="$3"
  local error_message

  case "$http_status" in
    2*) ;;
    *)
      log_error "Cloudflare API ${method} HTTP ${http_status}: $(cat "$response_file")"
      ;;
  esac

  if ! jq -e '.success == true' "$response_file" >/dev/null; then
    error_message="$(jq -r '[.errors[]?.message] | join("; ")' "$response_file")"
    [ -n "$error_message" ] || error_message="$(cat "$response_file")"
    log_error "Cloudflare API ${method} failed: ${error_message}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_zones_by_name
#   Lists Cloudflære zones mætching æ domain næme.
#   Ærguments:
#     $1 - zone næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_zones_by_name() (
  local zone_name="$1"
  local token
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/cloudflare-get-zone.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT

  if ! http_status="$(curl -sS \
    --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
    -o "$response_file" -w '%{http_code}' --get \
    --header "Authorization: Bearer ${token}" \
    --data-urlencode "name=${zone_name}" \
    --data-urlencode "per_page=50" \
    "${CERTS_DUMPER_CF_API_BASE}/zones")"; then
    log_error "Cloudflare API zone lookup failed: $(cat "$response_file" 2>/dev/null || true)"
  fi

  cloudflare_check_response "GET zones" "$http_status" "$response_file"
  cat "$response_file"
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_find_zone_id
#   Resolves one Cloudflære zone ID from the explicit Mæilcow zone.
#   Ærguments:
#     $1 - zone næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_find_zone_id() {
  local zone_name="$1"
  local zones_json
  local matching_zones_json
  local zone_count

  zones_json="$(cloudflare_get_zones_by_name "$zone_name")"
  matching_zones_json="$(printf '%s' "$zones_json" | jq -c --arg zone_name "$zone_name" \
    '.result | map(select((.name | ascii_downcase | rtrimstr(".")) == $zone_name))')"
  zone_count="$(printf '%s' "$matching_zones_json" | jq -r 'length')"

  case "$zone_count" in
    1)
      if ! printf '%s' "$matching_zones_json" | jq -er '
        .[0] |
        if (.status == "active" and (.id | type == "string" and test("^[0-9a-fA-F]{32}$")))
        then .id
        else error("zone is inactive or its ID is invalid")
        end
      '; then
        log_error "Configured Mailcow Cloudflare zone must be active and return one valid zone ID: ${zone_name}"
      fi
      ;;
    0)
      log_error "Configured Mailcow Cloudflare zone not found: ${zone_name}"
      ;;
    *)
      log_error "Multiple Cloudflare zones found for configured Mailcow zone ${zone_name}; refusing to guess"
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_dnssec
#   Fetches DNSSEC stætus for one exæct Cloudflære zone.
#   Ærguments:
#     $1 - Cloudflære zone ID
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_dnssec() (
  local zone_id="$1"
  local token
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/cloudflare-get-dnssec.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT
  if ! http_status="$(curl -sS \
    --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
    -o "$response_file" -w '%{http_code}' \
    --header "Authorization: Bearer ${token}" \
    "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dnssec")"; then
    log_error "Cloudflare API DNSSEC lookup failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  cloudflare_check_response "GET DNSSEC" "$http_status" "$response_file"
  cat "$response_file"
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_dnssec_active
#   Requires Cloudflære änd the pærent delegætion to report DNSSEC æctive.
#   Ærguments:
#     $1 - Cloudflære zone ID
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_dnssec_active() {
  local zone_id="$1"
  local dnssec_json

  dnssec_json="$(cloudflare_get_dnssec "$zone_id")"
  if ! printf '%s' "$dnssec_json" | jq -e '.result.status == "active"' >/dev/null; then
    log_error "Cloudflare DNSSEC must be active before the Mailcow DANE workflow mutates DNS or certificates"
  fi
  log_ok "Cloudflare DNSSEC is active for the configured Mailcow zone."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_get_tlsa_records
#   Lists Cloudflære TLSÆ records with one exæct DNS næme in æ zone.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - exæct TLSÆ record næme
#ææææææææææææææææææææææææææææææææææ
cloudflare_get_tlsa_records() (
  local zone_id="$1"
  local record_name="$2"
  local token
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/cloudflare-get-tlsa.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT

  if ! http_status="$(curl -sS \
    --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
    -o "$response_file" -w '%{http_code}' --get \
    --header "Authorization: Bearer ${token}" \
    --data-urlencode "type=TLSA" \
    --data-urlencode "name=${record_name}" \
    --data-urlencode "per_page=50" \
    "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records")"; then
    log_error "Cloudflare API GET failed: $(cat "$response_file" 2>/dev/null || true)"
  fi

  cloudflare_check_response "GET" "$http_status" "$response_file"
  cat "$response_file"
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_canonical_tlsa_snapshot
#   Cænonicælizes every security-relevænt field of one exæct RRset.
#   Ærguments:
#     $1 - Cloudflære TLSÆ response JSON
#     $2 - exæct TLSÆ owner
#     $3 - exæct TTL
#ææææææææææææææææææææææææææææææææææ
cloudflare_canonical_tlsa_snapshot() {
  local response_json="$1"
  local record_name="$2"
  local record_ttl="$3"
  local validated_records

  validated_records="$(select_mailcow_tlsa_records \
    "$response_json" "$record_name" "$record_ttl")" \
    || log_error "Could not validate the Cloudflare TLSA snapshot"
  printf '%s' "$validated_records" | jq -ceS '
    def tuple_value($index; $field):
      .data[$field] // ((.content // "" | split(" ") | .[$index] // "" | tonumber?));
    def certificate_hash:
      (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase);
    [ .[] | {
      id: (.id | ascii_downcase),
      type: (.type | ascii_upcase),
      name: (.name | ascii_downcase | rtrimstr(".")),
      ttl: .ttl,
      proxied: .proxied,
      data: {
        usage: tuple_value(0; "usage"),
        selector: tuple_value(1; "selector"),
        matching_type: tuple_value(2; "matching_type"),
        certificate: certificate_hash
      }
    } ] | sort_by(.id, .data.certificate)
  '
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_cloudflare_tlsa_snapshot_unchanged
#   Re-fetches ænd compæres the exæct RRset immediætely before mutation.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - exæct TLSÆ owner
#     $3 - exæct TTL
#     $4 - previously vælidæted Cloudflære response JSON
#ææææææææææææææææææææææææææææææææææ
require_cloudflare_tlsa_snapshot_unchanged() {
  local zone_id="$1"
  local record_name="$2"
  local record_ttl="$3"
  local expected_response_json="$4"
  local expected_snapshot
  local final_response_json
  local final_snapshot

  expected_snapshot="$(cloudflare_canonical_tlsa_snapshot \
    "$expected_response_json" "$record_name" "$record_ttl")" \
    || log_error "Could not canonicalize the expected Cloudflare TLSA snapshot"
  final_response_json="$(cloudflare_get_tlsa_records "$zone_id" "$record_name")" \
    || log_error "Could not re-fetch the Cloudflare TLSA RRset immediately before mutation"
  final_snapshot="$(cloudflare_canonical_tlsa_snapshot \
    "$final_response_json" "$record_name" "$record_ttl")" \
    || log_error "Could not canonicalize the final Cloudflare TLSA snapshot"
  [ "$final_snapshot" = "$expected_snapshot" ] \
    || log_error "Cloudflare TLSA RRset changed after it was read; refusing a stale mutation"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cloudflare_mutate_record
#   Creætes or deletes one exæct Cloudflære DNS record.
#   Ærguments:
#     $1 - HTTP method (POST or DELETE)
#     $2 - request URL
#     $3 - JSON pæyloæd for POST, blænk for DELETE
#ææææææææææææææææææææææææææææææææææ
cloudflare_mutate_record() (
  local method="$1"
  local url="$2"
  local payload="$3"
  local token
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/cloudflare-write-tlsa.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT

  case "$method" in
    POST)
      if ! http_status="$(curl -sS \
        --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
        --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
        -o "$response_file" -w '%{http_code}' \
        --request POST \
        --header "Authorization: Bearer ${token}" \
        --header "Content-Type: application/json" \
        --data "$payload" \
        "$url")"; then
        log_error "Cloudflare API POST failed: $(cat "$response_file" 2>/dev/null || true)"
      fi
      ;;
    DELETE)
      [ -z "$payload" ] || log_error "Cloudflare DELETE payload must be blank"
      if ! http_status="$(curl -sS \
        --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
        --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
        -o "$response_file" -w '%{http_code}' \
        --request DELETE \
        --header "Authorization: Bearer ${token}" \
        "$url")"; then
        log_error "Cloudflare API DELETE failed: $(cat "$response_file" 2>/dev/null || true)"
      fi
      ;;
    *) log_error "Unsupported Cloudflare mutation method: ${method}" ;;
  esac

  cloudflare_check_response "$method" "$http_status" "$response_file"
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_tlsa_payload
#   Builds one exæct Cloudflære TLSÆ 3 1 1 record pæyloæd.
#   Ærguments:
#     $1 - exæct TLSÆ owner
#     $2 - explicit TTL in seconds
#     $3 - TLSÆ SPKI SHÆ-256 hæsh
#ææææææææææææææææææææææææææææææææææ
build_tlsa_payload() {
  local record_name="$1"
  local record_ttl="$2"
  local certificate_hash="$3"

  jq -n \
    --arg record_name "$record_name" \
    --argjson record_ttl "$record_ttl" \
    --arg certificate "$certificate_hash" \
    '{
      type: "TLSA",
      name: $record_name,
      ttl: $record_ttl,
      data: {
        usage: 3,
        selector: 1,
        matching_type: 1,
        certificate: $certificate
      }
    }'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_cloudflare_tlsa_record
#   Ædds the future SPKI hæsh without replæcing the current TLSÆ record.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - exæct TLSÆ record næme
#     $3 - explicit TTL in seconds
#     $4 - future SPKI hæsh
#     $5 - previously vælidæted normælized TLSÆ RRset response
#ææææææææææææææææææææææææææææææææææ
create_cloudflare_tlsa_record() {
  local zone_id="$1"
  local record_name="$2"
  local record_ttl="$3"
  local certificate_hash="$4"
  local expected_rrset_json="$5"
  local expected_snapshot
  local payload

  expected_snapshot="$(cloudflare_canonical_tlsa_snapshot \
    "$expected_rrset_json" "$record_name" "$record_ttl")" \
    || log_error "Could not canonicalize the pre-create Cloudflare TLSA snapshot"
  if ! printf '%s' "$expected_snapshot" | jq -e --arg certificate_hash "$certificate_hash" \
    'length == 1 and all(.[]; .data.certificate != $certificate_hash)' >/dev/null; then
    log_error "Cloudflare TLSA create requires one prior record and one distinct future SPKI hash"
  fi
  require_cloudflare_tlsa_snapshot_unchanged \
    "$zone_id" "$record_name" "$record_ttl" "$expected_rrset_json"
  payload="$(build_tlsa_payload "$record_name" "$record_ttl" "$certificate_hash")"
  log_info "Publishing future Mailcow TLSA 3 1 1 record alongside the active key..."
  cloudflare_mutate_record "POST" "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records" "$payload"
  log_ok "Future Mailcow TLSA record published: ${record_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: delete_cloudflare_tlsa_record
#   Deletes one identity-proven obsolete TLSÆ record by its exæct ID.
#   Ærguments:
#     $1 - Cloudflære zone ID
#     $2 - obsolete Cloudflære TLSÆ record ID
#     $3 - previously vælidæted Cloudflære response JSON
#ææææææææææææææææææææææææææææææææææ
delete_cloudflare_tlsa_record() {
  local zone_id="$1"
  local record_id="$2"
  local expected_rrset_json="$3"
  local expected_snapshot

  case "$record_id" in
    *[!0-9a-f]*|'') log_error "Refusing to delete an invalid Cloudflare TLSA record ID" ;;
  esac
  [ "${#record_id}" -eq 32 ] || log_error "Refusing to delete a non-canonical Cloudflare TLSA record ID"
  expected_snapshot="$(cloudflare_canonical_tlsa_snapshot \
    "$expected_rrset_json" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")" \
    || log_error "Could not canonicalize the pre-delete Cloudflare TLSA snapshot"
  if ! printf '%s' "$expected_snapshot" | jq -e --arg record_id "$record_id" \
    'length == 2 and any(.[]; .id == $record_id)' >/dev/null; then
    log_error "Cloudflare TLSA delete requires the exact selected record in a two-record snapshot"
  fi
  require_cloudflare_tlsa_snapshot_unchanged \
    "$zone_id" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" \
    "$expected_rrset_json"
  cloudflare_mutate_record "DELETE" "${CERTS_DUMPER_CF_API_BASE}/zones/${zone_id}/dns_records/${record_id}" ''
  log_ok "Obsolete Mailcow TLSA record deleted after verified overlap."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DESEC TLSÆ
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_tlsa_subname
#   Derives the deSEC RRset subnæme from the TLSÆ owner ænd zone.
#   Ærguments:
#     $1 - exæct TLSÆ owner
#     $2 - configured DNS zone
#ææææææææææææææææææææææææææææææææææ
desec_tlsa_subname() {
  local record_name="$1"
  local zone_name="$2"

  case "$record_name" in
    *."$zone_name") printf '%s' "${record_name%.${zone_name}}" ;;
    *) log_error "Mailcow TLSA owner is not under the configured deSEC zone ${zone_name}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_check_response
#   Vælidætes deSEC HTTP responses; GET 404 is handled by the cæller.
#   Ærguments:
#     $1 - HTTP method
#     $2 - HTTP stætus code
#     $3 - response body pæth
#ææææææææææææææææææææææææææææææææææ
desec_check_response() {
  local method="$1"
  local http_status="$2"
  local response_file="$3"

  case "$http_status" in
    2*) ;;
    *) log_error "deSEC API ${method} HTTP ${http_status}: $(cat "$response_file")" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_require_domain
#   Confirms the configured zone exists æt deSEC.
#   Ærguments:
#     $1 - DNS zone næme
#ææææææææææææææææææææææææææææææææææ
desec_require_domain() (
  local zone_name="$1"
  local token
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/desec-get-domain.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT
  if ! http_status="$(curl -sS \
    --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
    -o "$response_file" -w '%{http_code}' \
    --header "Authorization: Token ${token}" \
    "${CERTS_DUMPER_DESEC_API_BASE}/domains/${zone_name}/")"; then
    log_error "deSEC API domain lookup failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  case "$http_status" in
    200) ;;
    404) log_error "Configured Mailcow deSEC zone not found: ${zone_name}" ;;
    *) desec_check_response "GET domain" "$http_status" "$response_file" ;;
  esac
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
  printf '%s' "$zone_name"
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_normalize_tlsa_rrset
#   Mæps æ deSEC TLSÆ RRset onto the shæred Mæilcow record JSON shæpe.
#   Ærguments:
#     $1 - deSEC RRset JSON, or empty for æ missing RRset
#     $2 - exæct TLSÆ owner
#     $3 - exæct deSEC RRset subnæme
#ææææææææææææææææææææææææææææææææææ
desec_normalize_tlsa_rrset() {
  local rrset_json="$1"
  local record_name="$2"
  local expected_subname="$3"

  if [ -z "$rrset_json" ]; then
    jq -nc \
      --arg expected_name "$record_name" \
      --arg expected_subname "$expected_subname" \
      '{
        success: true,
        identity: {
          exists: false,
          subname: $expected_subname,
          type: "TLSA",
          name: $expected_name
        },
        result: []
      }'
    return 0
  fi
  printf '%s' "$rrset_json" | jq -ce \
    --arg expected_name "$record_name" \
    --arg expected_subname "$expected_subname" '
    . as $rrset |
    if (($rrset | type) == "object")
      and (($rrset.subname | type) == "string")
      and ($rrset.subname == $expected_subname)
      and (($rrset.type | type) == "string")
      and ($rrset.type == "TLSA")
      and (($rrset.name | type) == "string")
      and (($rrset.name | ascii_downcase | rtrimstr(".")) == $expected_name)
      and (($rrset.records | type) == "array")
    then
      {
        success: true,
        identity: {
          exists: true,
          subname: $rrset.subname,
          type: $rrset.type,
          name: ($rrset.name | ascii_downcase | rtrimstr("."))
        },
        result: [
          $rrset.records[] |
          split(" ") as $parts |
          {
            id: ($parts[3] // "" | ascii_downcase),
            type: $rrset.type,
            name: ($rrset.name | ascii_downcase | rtrimstr(".")),
            ttl: $rrset.ttl,
            proxied: false,
            content: .,
            data: {
              usage: ($parts[0] | tonumber),
              selector: ($parts[1] | tonumber),
              matching_type: ($parts[2] | tonumber),
              certificate: ($parts[3] // "" | ascii_downcase)
            }
          }
        ]
      }
    else
      error("deSEC RRset identity does not match the exact requested subname, type, and owner")
    end
  '
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_canonical_tlsa_snapshot
#   Cænonicælizes every security-relevænt field of one normælized deSEC RRset.
#   Ærguments:
#     $1 - normælized TLSÆ RRset JSON
#ææææææææææææææææææææææææææææææææææ
desec_canonical_tlsa_snapshot() {
  local rrset_json="$1"

  printf '%s' "$rrset_json" | jq -ceS '
    if .success != true
      or ((.identity | type) != "object")
      or ((.identity.exists | type) != "boolean")
      or ((.identity.subname | type) != "string")
      or ((.identity.type | type) != "string")
      or ((.identity.name | type) != "string")
    then
      error("invalid normalized deSEC RRset")
    else
      {
        success: true,
        identity: {
          exists: .identity.exists,
          subname: .identity.subname,
          type: .identity.type,
          name: .identity.name
        },
        result: [
          (.result // [])[] |
          {
            id: .id,
            type: .type,
            name: .name,
            ttl: .ttl,
            proxied: .proxied,
            content: .content,
            data: .data
          }
        ] | sort_by(.id, .content)
      }
    end
  '
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_get_tlsa_records
#   Fetches the TLSÆ RRset for one exæct owner from deSEC.
#   Ærguments:
#     $1 - DNS zone næme
#     $2 - exæct TLSÆ record næme
#ææææææææææææææææææææææææææææææææææ
desec_get_tlsa_records() (
  local zone_name="$1"
  local record_name="$2"
  local subname
  local token
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  subname="$(desec_tlsa_subname "$record_name" "$zone_name")"
  token="$(read_dns_api_token)"
  response_file="$(mktemp /tmp/desec-get-tlsa.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT
  if ! http_status="$(curl -sS \
    --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
    -o "$response_file" -w '%{http_code}' \
    --header "Authorization: Token ${token}" \
    "${CERTS_DUMPER_DESEC_API_BASE}/domains/${zone_name}/rrsets/${subname}/TLSA/")"; then
    log_error "deSEC API GET failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  case "$http_status" in
    200)
      desec_normalize_tlsa_rrset \
        "$(cat "$response_file")" "$record_name" "$subname"
      ;;
    404)
      desec_normalize_tlsa_rrset '' "$record_name" "$subname"
      ;;
    *) desec_check_response "GET TLSA" "$http_status" "$response_file" ;;
  esac
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: desec_put_tlsa_rrset
#   Replæces the complete TLSÆ RRset æt deSEC.
#   Ærguments:
#     $1 - DNS zone næme
#     $2 - exæct TLSÆ record næme
#     $3 - explicit TTL in seconds
#     $4 - JSON ærræy of TLSÆ content strings
#     $5 - normælized RRset snæpshot from which the replæcement wæs derived
#ææææææææææææææææææææææææææææææææææ
desec_put_tlsa_rrset() (
  local zone_name="$1"
  local record_name="$2"
  local record_ttl="$3"
  local records_json="$4"
  local expected_rrset_json="$5"
  local subname
  local token
  local payload
  local expected_snapshot
  local final_snapshot
  local final_rrset_json
  local response_file
  local response_identity
  local response_parent_identity
  local http_status

  subname="$(desec_tlsa_subname "$record_name" "$zone_name")"
  token="$(read_dns_api_token)"
  expected_snapshot="$(desec_canonical_tlsa_snapshot "$expected_rrset_json")" \
    || log_error "Could not canonicalize the expected deSEC TLSA RRset snapshot"
  final_rrset_json="$(desec_get_tlsa_records "$zone_name" "$record_name")" \
    || log_error "Could not re-fetch the deSEC TLSA RRset immediately before replacement"
  final_snapshot="$(desec_canonical_tlsa_snapshot "$final_rrset_json")" \
    || log_error "Could not canonicalize the final deSEC TLSA RRset snapshot"
  [ "$final_snapshot" = "$expected_snapshot" ] \
    || log_error "deSEC TLSA RRset changed after it was read; refusing a stale full-RRset replacement"
  payload="$(jq -n \
    --arg subname "$subname" \
    --arg type TLSA \
    --argjson ttl "$record_ttl" \
    --argjson records "$records_json" \
    '{subname: $subname, type: $type, ttl: $ttl, records: $records}')"
  response_file="$(mktemp /tmp/desec-put-tlsa.XXXXXX)"
  response_identity="$(stat -c '%d:%i' -- "$response_file")"
  response_parent_identity="$(stat -c '%d:%i' -- "${response_file%/*}")"
  trap 'cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"' EXIT
  if ! http_status="$(curl -sS \
    --connect-timeout "$CERTS_DUMPER_DNS_CONNECT_TIMEOUT_SECONDS" \
    --max-time "$CERTS_DUMPER_DNS_MAX_TIME_SECONDS" \
    -o "$response_file" -w '%{http_code}' \
    --request PUT \
    --header "Authorization: Token ${token}" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    "${CERTS_DUMPER_DESEC_API_BASE}/domains/${zone_name}/rrsets/${subname}/TLSA/")"; then
    log_error "deSEC API PUT failed: $(cat "$response_file" 2>/dev/null || true)"
  fi
  desec_check_response "PUT TLSA" "$http_status" "$response_file"
  cleanup_mailcow_identity_stage "$response_file" "$response_identity" "$response_parent_identity"
  response_file=''
  trap - EXIT
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_desec_tlsa_record
#   Ædds the future SPKI hæsh without dropping the current TLSÆ records.
#   Ærguments:
#     $1 - DNS zone næme
#     $2 - exæct TLSÆ record næme
#     $3 - explicit TTL in seconds
#     $4 - future SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
create_desec_tlsa_record() {
  local zone_name="$1"
  local record_name="$2"
  local record_ttl="$3"
  local certificate_hash="$4"
  local current_json="$5"
  local records_json

  records_json="$(printf '%s' "$current_json" | jq -c --arg certificate "$certificate_hash" '
    [(.result // [])[] | .content] + ["3 1 1 " + $certificate]
  ')"
  log_info "Publishing future Mailcow TLSA 3 1 1 record alongside the active key..."
  desec_put_tlsa_rrset \
    "$zone_name" "$record_name" "$record_ttl" "$records_json" "$current_json"
  log_ok "Future Mailcow TLSA record published: ${record_name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: delete_desec_tlsa_record
#   Removes one identity-proven obsolete TLSÆ hæsh from the deSEC RRset.
#   Ærguments:
#     $1 - DNS zone næme
#     $2 - obsolete TLSÆ record ID (the SPKI hæsh)
#     $3 - exæct TLSÆ record næme
#     $4 - explicit TTL in seconds
#     $5 - previously vælidæted normælized TLSÆ RRset response
#ææææææææææææææææææææææææææææææææææ
delete_desec_tlsa_record() {
  local zone_name="$1"
  local record_id="$2"
  local record_name="$3"
  local record_ttl="$4"
  local current_json="$5"
  local records_json
  local remaining_count

  is_valid_sha256_hash "$record_id" || log_error "Refusing to delete an invalid deSEC TLSA record ID"
  records_json="$(printf '%s' "$current_json" | jq -c --arg retired "$record_id" '
    [(.result // [])[] | select((.id | ascii_downcase) != $retired) | .content]
  ')"
  remaining_count="$(printf '%s' "$records_json" | jq -r 'length')"
  [ "$remaining_count" -ge 1 ] || log_error "Refusing to delete the last Mailcow TLSA record at deSEC"
  desec_put_tlsa_rrset \
    "$zone_name" "$record_name" "$record_ttl" "$records_json" "$current_json"
  log_ok "Obsolete Mailcow TLSA record deleted after verified overlap."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DNS PROVIDER DISPATCH
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dns_require_zone
#   Resolves the provider-specific zone hændle for Mæilcow TLSÆ mutætion.
#   Ærguments:
#     $1 - configured DNS zone næme
#ææææææææææææææææææææææææææææææææææ
dns_require_zone() {
  local zone_name="$1"

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare) cloudflare_find_zone_id "$zone_name" ;;
    desec) desec_require_domain "$zone_name" ;;
    *) log_error "Unsupported derived DNS provider for Mailcow TLSA: ${MAILCOW_DNS_PROVIDER}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dns_require_dnssec
#   Requires DNSSEC to be æctive before TLSÆ mutætion.
#   Ærguments:
#     $1 - provider zone hændle
#ææææææææææææææææææææææææææææææææææ
dns_require_dnssec() {
  local zone_handle="$1"

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare) require_cloudflare_dnssec_active "$zone_handle" ;;
    desec) log_ok "deSEC DNSSEC is always active for the configured Mailcow zone." ;;
    *) log_error "Unsupported derived DNS provider for Mailcow DNSSEC: ${MAILCOW_DNS_PROVIDER}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dns_get_tlsa_records
#   Lists TLSÆ records for one exæct owner through the selected provider.
#   Ærguments:
#     $1 - provider zone hændle
#     $2 - exæct TLSÆ record næme
#ææææææææææææææææææææææææææææææææææ
dns_get_tlsa_records() {
  local zone_handle="$1"
  local record_name="$2"

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare) cloudflare_get_tlsa_records "$zone_handle" "$record_name" ;;
    desec) desec_get_tlsa_records "$zone_handle" "$record_name" ;;
    *) log_error "Unsupported derived DNS provider for Mailcow TLSA lookup: ${MAILCOW_DNS_PROVIDER}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dns_create_tlsa_record
#   Publishes the future TLSÆ hæsh through the selected provider.
#   Ærguments:
#     $1 - provider zone hændle
#     $2 - exæct TLSÆ record næme
#     $3 - explicit TTL in seconds
#     $4 - future SPKI hæsh
#     $5 - previously vælidæted provider response used by the stæleness guærd
#ææææææææææææææææææææææææææææææææææ
dns_create_tlsa_record() {
  local zone_handle="$1"
  local record_name="$2"
  local record_ttl="$3"
  local certificate_hash="$4"
  local expected_rrset_json="$5"

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare) create_cloudflare_tlsa_record \
      "$zone_handle" "$record_name" "$record_ttl" "$certificate_hash" "$expected_rrset_json" ;;
    desec) create_desec_tlsa_record "$zone_handle" "$record_name" "$record_ttl" "$certificate_hash" "$expected_rrset_json" ;;
    *) log_error "Unsupported derived DNS provider for Mailcow TLSA create: ${MAILCOW_DNS_PROVIDER}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dns_delete_tlsa_record
#   Retires one proven obsolete TLSÆ record through the selected provider.
#   Ærguments:
#     $1 - provider zone hændle
#     $2 - obsolete record ID
#     $3 - previously vælidæted provider response used by the stæleness guærd
#ææææææææææææææææææææææææææææææææææ
dns_delete_tlsa_record() {
  local zone_handle="$1"
  local record_id="$2"
  local expected_rrset_json="$3"

  case "$MAILCOW_DNS_PROVIDER" in
    cloudflare) delete_cloudflare_tlsa_record "$zone_handle" "$record_id" "$expected_rrset_json" ;;
    desec) delete_desec_tlsa_record \
      "$zone_handle" "$record_id" "$MAILCOW_TLSA_RECORD_NAME" \
      "$MAILCOW_DANE_TTL_SECONDS" "$expected_rrset_json" ;;
    *) log_error "Unsupported derived DNS provider for Mailcow TLSA delete: ${MAILCOW_DNS_PROVIDER}" ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: dnssec_tlsa_rrset_matches
#   Locælly vælidætes one exæct DNSSEC RRset from æ recursive DNS server.
#   Ærguments:
#     $1 - TLSÆ owner
#     $2 - configured mæximum TTL
#     $3+ - exæct expected SPKI hæshes
#ææææææææææææææææææææææææææææææææææ
dnssec_tlsa_rrset_matches() {
  local record_name="$1"
  local expected_ttl="$2"
  shift 2
  local delv_output
  local actual_hashes
  local expected_hashes
  local expected_hash

  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || return 1
  for expected_hash in "$@"; do
    is_valid_sha256_hash "$expected_hash" || return 1
  done
  if ! delv_output="$(timeout 20 delv \
    "@${MAILCOW_DANE_VALIDATING_RESOLVER}" +tcp +nosplit +nodnssec \
    +noall +comments +trust +ttl +class "$record_name" TLSA 2>/dev/null)"; then
    return 1
  fi
  printf '%s\n' "$delv_output" | grep -Eq '^; fully validated$' || return 1
  if ! actual_hashes="$(printf '%s\n' "$delv_output" | awk \
    -v expected_name="$record_name" -v maximum_ttl="$expected_ttl" '
      BEGIN { count = 0; valid = 1 }
      $1 !~ /^;/ && toupper($4) == "TLSA" {
        owner = tolower($1); sub(/[.]$/, "", owner)
        digest = tolower($8)
        if (owner != expected_name || $2 !~ /^[0-9]+$/ || $2 < 1 || $2 > maximum_ttl ||
            $5 != 3 || $6 != 1 || $7 != 1 || length(digest) != 64 || digest !~ /^[0-9a-f]+$/) {
          valid = 0
        }
        print digest
        count++
      }
      END { if (!valid || count < 1 || count > 2) exit 1 }
    ')"; then
    return 1
  fi
  expected_hashes="$(printf '%s\n' "$@" | sort -u)"
  actual_hashes="$(printf '%s\n' "$actual_hashes" | sort -u)"
  [ "$actual_hashes" = "$expected_hashes" ]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_dnssec_tlsa_rrset
#   Polls until the exæct DNSSEC-æuthenticæted RRset is visible or fæils closed.
#   Ærguments:
#     $1 - TLSÆ owner
#     $2 - configured mæximum TTL
#     $3 - mæximum wæit in seconds
#     $4+ - exæct expected SPKI hæshes
#ææææææææææææææææææææææææææææææææææ
wait_for_dnssec_tlsa_rrset() {
  local record_name="$1"
  local expected_ttl="$2"
  local maximum_wait="$3"
  shift 3
  local waited=0

  while [ "$waited" -le "$maximum_wait" ]; do
    if dnssec_tlsa_rrset_matches "$record_name" "$expected_ttl" "$@"; then
      log_ok "DNSSEC-validating resolver sees the expected Mailcow TLSA RRset."
      return 0
    fi
    [ "$waited" -lt "$maximum_wait" ] || break
    sleep "$CERTS_DUMPER_DNS_POLL_SECONDS"
    waited=$((waited + CERTS_DUMPER_DNS_POLL_SECONDS))
  done
  log_error "Expected DNSSEC-authenticated Mailcow TLSA RRset was not visible within ${maximum_wait}s"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_dane_window
#   Wæits one explicit RFC 7671 roll-over window.
#   Ærguments:
#     $1 - phæse description
#     $2 - wæit time in seconds
#ææææææææææææææææææææææææææææææææææ
wait_for_dane_window() {
  local phase="$1"
  local wait_seconds="$2"

  log_info "Mailcow DANE ${phase}: waiting ${wait_seconds}s."
  sleep "$wait_seconds"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTIFICÆTE FILES
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: wait_for_certificate_files
#   Wæits until the dumped certificæte/key files exist ænd ære non-empty.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#ææææææææææææææææææææææææææææææææææ
wait_for_certificate_files() {
  local cert_path="$1"
  local key_path="$2"
  local waited=0

  while [ "$waited" -lt "$CERTS_DUMPER_CERT_WAIT_SECONDS" ]; do
    if [ -s "$cert_path" ] && [ -s "$key_path" ]; then
      return 0
    fi

    if [ "$waited" -eq 0 ]; then
      log_info "Waiting for dumped certificate files..."
    fi

    sleep 1
    waited=$((waited + 1))
  done

  log_error "Dumped certificate files not ready after ${CERTS_DUMPER_CERT_WAIT_SECONDS}s: ${cert_path}, ${key_path}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTIFICÆTE COPY
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_certificates
#   Copies æ certificæte/key pæir to æ remote host viæ scp.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote certificæte pæth
#     $6 - remote key pæth
#     $7 - SSH privæte key pæth
#ææææææææææææææææææææææææææææææææææ
copy_certificates() {
  local src_cert="$1"
  local src_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local dest_cert_path="$5"
  local dest_key_path="$6"
  local ssh_key="$7"

  log_info "Copying certs to ${dest_user}@${dest_host}..."

  if ! run_bounded_scp \
    "$ssh_key" "$dest_user" "$dest_host" "$src_cert" "$dest_cert_path"; then
    log_error "Failed to copy certificate to ${dest_host}:${dest_cert_path}"
  fi
  if ! run_bounded_scp \
    "$ssh_key" "$dest_user" "$dest_host" "$src_key" "$dest_key_path"; then
    log_error "Failed to copy key to ${dest_host}:${dest_key_path}"
  fi

  log_ok "Certificates copied to ${dest_user}@${dest_host}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_remote_mailcow_certificate
#   Stæges ænd vælidætes the new pæir beside the æctive files ænd keeps one bæckup.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote Mæilcow project pæth
#     $6 - SSH privæte key pæth
#     $7 - new leæf SHÆ-256 trænsæction ID
#     $8 - new SPKI SHÆ-256 hæsh
#     $9 - prior SPKI SHÆ-256 hæsh
#     $10 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
stage_remote_mailcow_certificate() {
  local src_cert="$1"
  local src_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local project_path="$5"
  local ssh_key="$6"
  local transaction_id="$7"
  local expected_new_spki="$8"
  local expected_prior_spki="$9"
  local expected_prior_leaf="${10}"
  local transaction_path="${project_path}/data/assets/ssl/.certs-dumper-rollover-${transaction_id}"

  log_info "Preparing remote Mailcow certificate transaction ${transaction_id}..."
  if ! run_bounded_ssh \
    "$CERTS_DUMPER_SSH_MUTATION_TIMEOUT_SECONDS" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- "$project_path" "$transaction_id" <<'REMOTE_PREPARE'
set -eu
umask 077
project_path="$1"
transaction_id="$2"
ssl_path="${project_path}/data/assets/ssl"
transaction_path="${ssl_path}/.certs-dumper-rollover-${transaction_id}"
active_cert="${ssl_path}/cert.pem"
active_key="${ssl_path}/key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"

case "$project_path" in
  /*) ;;
  *) exit 71 ;;
esac
case "$transaction_id" in
  *[!0-9a-f]*|'') exit 72 ;;
esac
[ "${#transaction_id}" -eq 64 ] || exit 73
[ -d "$ssl_path" ] && [ ! -L "$ssl_path" ] || exit 74
[ -f "$active_cert" ] && [ ! -L "$active_cert" ] || exit 75
[ -f "$active_key" ] && [ ! -L "$active_key" ] || exit 76
if [ ! -e "$transaction_path" ] && [ ! -L "$transaction_path" ]; then
  mkdir -m 0700 -- "$transaction_path" || exit 77
fi
[ -d "$transaction_path" ] && [ ! -L "$transaction_path" ] || exit 78
chmod 0700 -- "$transaction_path" || exit 79
if { [ -e "$backup_cert" ] || [ -L "$backup_cert" ]; } || { [ -e "$backup_key" ] || [ -L "$backup_key" ]; }; then
  [ -f "$backup_cert" ] && [ ! -L "$backup_cert" ] || exit 80
  [ -f "$backup_key" ] && [ ! -L "$backup_key" ] || exit 81
else
  cp -p -- "$active_cert" "$backup_cert" || exit 82
  cp -p -- "$active_key" "$backup_key" || exit 83
fi
REMOTE_PREPARE
  then
    return 1
  fi
  if ! run_bounded_scp \
    "$ssh_key" "$dest_user" "$dest_host" "$src_cert" \
    "${transaction_path}/incoming-cert.pem"; then
    return 1
  fi
  if ! run_bounded_scp \
    "$ssh_key" "$dest_user" "$dest_host" "$src_key" \
    "${transaction_path}/incoming-key.pem"; then
    return 1
  fi
  if ! run_bounded_ssh \
    "$CERTS_DUMPER_SSH_READ_TIMEOUT_SECONDS" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- "$project_path" "$transaction_id" \
    "$expected_new_spki" "$expected_prior_spki" "$expected_prior_leaf" <<'REMOTE_VALIDATE'
set -eu
project_path="$1"
transaction_id="$2"
expected_new_spki="$3"
expected_prior_spki="$4"
expected_prior_leaf="$5"
transaction_path="${project_path}/data/assets/ssl/.certs-dumper-rollover-${transaction_id}"
incoming_cert="${transaction_path}/incoming-cert.pem"
incoming_key="${transaction_path}/incoming-key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"

for file_path in "$incoming_cert" "$incoming_key" "$backup_cert" "$backup_key"; do
  [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 84
done
chmod 0600 -- "$incoming_cert" "$incoming_key" "$backup_cert" "$backup_key" || exit 85
cert_hash="$(openssl x509 -in "$incoming_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 86
key_hash="$(openssl pkey -in "$incoming_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 87
cert_leaf="$(openssl x509 -in "$incoming_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 88
backup_spki="$(openssl x509 -in "$backup_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 89
backup_key_spki="$(openssl pkey -in "$backup_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 90
backup_leaf="$(openssl x509 -in "$backup_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || exit 91
[ "$cert_hash" = "$expected_new_spki" ] && [ "$key_hash" = "$expected_new_spki" ] || exit 92
[ "$cert_leaf" = "$transaction_id" ] || exit 93
[ "$backup_spki" = "$expected_prior_spki" ] && [ "$backup_key_spki" = "$expected_prior_spki" ] || exit 94
[ "$backup_leaf" = "$expected_prior_leaf" ] || exit 95
REMOTE_VALIDATE
  then
    return 1
  fi
  log_ok "Remote Mailcow certificate pair staged with a retained backup."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: activate_remote_mailcow_certificate
#   Æctivætes the stæged pæir through one rollbæck-guærded remote trænsæction.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - new leæf SHÆ-256 trænsæction ID
#     $6 - new SPKI SHÆ-256 hæsh
#     $7 - prior SPKI SHÆ-256 hæsh
#     $8 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
activate_remote_mailcow_certificate() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local transaction_id="$5"
  local expected_new_spki="$6"
  local expected_prior_spki="$7"
  local expected_prior_leaf="$8"

  if ! run_bounded_ssh \
    "$CERTS_DUMPER_SSH_MUTATION_TIMEOUT_SECONDS" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- "$project_path" "$transaction_id" "$expected_new_spki" \
    "$expected_prior_spki" "$expected_prior_leaf" <<'REMOTE_ACTIVATE'
set -eu
umask 077
project_path="$1"
transaction_id="$2"
expected_new_spki="$3"
expected_prior_spki="$4"
expected_prior_leaf="$5"
ssl_path="${project_path}/data/assets/ssl"
transaction_path="${ssl_path}/.certs-dumper-rollover-${transaction_id}"
active_cert="${ssl_path}/cert.pem"
active_key="${ssl_path}/key.pem"
incoming_cert="${transaction_path}/incoming-cert.pem"
incoming_key="${transaction_path}/incoming-key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"
next_cert="${transaction_path}/activate-cert.pem"
next_key="${transaction_path}/activate-key.pem"
committed=false

require_pair_identity() {
  pair_cert="$1"
  pair_key="$2"
  pair_expected_spki="$3"
  pair_expected_leaf="$4"
  pair_cert_spki="$(openssl x509 -in "$pair_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || return 1
  pair_key_spki="$(openssl pkey -in "$pair_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || return 1
  pair_leaf="$(openssl x509 -in "$pair_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || return 1
  [ "$pair_cert_spki" = "$pair_expected_spki" ] \
    && [ "$pair_key_spki" = "$pair_expected_spki" ] \
    && [ "$pair_leaf" = "$pair_expected_leaf" ]
}

rollback_pair() {
  [ "$committed" = false ] || return 0
  require_pair_identity "$backup_cert" "$backup_key" "$expected_prior_spki" "$expected_prior_leaf" || return 1
  cp -- "$backup_cert" "${transaction_path}/rollback-cert.pem" || return 1
  cp -- "$backup_key" "${transaction_path}/rollback-key.pem" || return 1
  chmod 0600 -- "${transaction_path}/rollback-cert.pem" "${transaction_path}/rollback-key.pem" || return 1
  require_pair_identity \
    "${transaction_path}/rollback-cert.pem" "${transaction_path}/rollback-key.pem" \
    "$expected_prior_spki" "$expected_prior_leaf" || return 1
  mv -f -- "${transaction_path}/rollback-cert.pem" "$active_cert" || return 1
  mv -f -- "${transaction_path}/rollback-key.pem" "$active_key" || return 1
  require_pair_identity "$active_cert" "$active_key" "$expected_prior_spki" "$expected_prior_leaf"
}

for file_path in "$active_cert" "$active_key" "$incoming_cert" "$incoming_key" "$backup_cert" "$backup_key"; do
  [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 91
  [ "$(stat -c '%h' -- "$file_path")" -eq 1 ] || exit 92
done
require_pair_identity "$backup_cert" "$backup_key" "$expected_prior_spki" "$expected_prior_leaf" || exit 93
require_pair_identity "$incoming_cert" "$incoming_key" "$expected_new_spki" "$transaction_id" || exit 94
require_pair_identity "$active_cert" "$active_key" "$expected_prior_spki" "$expected_prior_leaf" || exit 95
cp -- "$incoming_cert" "$next_cert" || exit 96
cp -- "$incoming_key" "$next_key" || exit 97
chmod 0600 -- "$next_cert" "$next_key" || exit 98
require_pair_identity "$next_cert" "$next_key" "$expected_new_spki" "$transaction_id" || exit 99
trap 'rollback_pair' EXIT
trap 'trap - EXIT; rollback_pair; exit 129' HUP
trap 'trap - EXIT; rollback_pair; exit 130' INT
trap 'trap - EXIT; rollback_pair; exit 143' TERM
mv -f -- "$next_cert" "$active_cert" || exit 100
mv -f -- "$next_key" "$active_key" || exit 101
require_pair_identity "$active_cert" "$active_key" "$expected_new_spki" "$transaction_id" || exit 102
committed=true
trap - EXIT HUP INT TERM
REMOTE_ACTIVATE
  then
    return 1
  fi
  log_ok "Remote Mailcow certificate pair activated from staged files."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_remote_mailcow_certificate
#   Restores the retained remote pæir ænd verifies its exæct prior identity.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - new leæf SHÆ-256 trænsæction ID
#     $6 - prior SPKI SHÆ-256 hæsh
#     $7 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
rollback_remote_mailcow_certificate() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local transaction_id="$5"
  local expected_spki="$6"
  local expected_leaf="$7"

  run_bounded_ssh \
    "$CERTS_DUMPER_SSH_ROLLBACK_RESTORE_TIMEOUT_SECONDS" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- \
    "$project_path" "$transaction_id" "$expected_spki" "$expected_leaf" <<'REMOTE_ROLLBACK'
set -eu
umask 077
project_path="$1"
transaction_id="$2"
expected_spki="$3"
expected_leaf="$4"
ssl_path="${project_path}/data/assets/ssl"
transaction_path="${ssl_path}/.certs-dumper-rollover-${transaction_id}"
active_cert="${ssl_path}/cert.pem"
active_key="${ssl_path}/key.pem"
backup_cert="${transaction_path}/backup-cert.pem"
backup_key="${transaction_path}/backup-key.pem"
rollback_cert="${transaction_path}/rollback-cert.pem"
rollback_key="${transaction_path}/rollback-key.pem"

require_pair_identity() {
  pair_cert="$1"
  pair_key="$2"
  pair_expected_spki="$3"
  pair_expected_leaf="$4"
  pair_cert_spki="$(openssl x509 -in "$pair_cert" -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || return 1
  pair_key_spki="$(openssl pkey -in "$pair_key" -pubout -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || return 1
  pair_leaf="$(openssl x509 -in "$pair_cert" -outform DER | openssl dgst -sha256 -binary | od -An -tx1 | tr -d ' \n')" || return 1
  [ "$pair_cert_spki" = "$pair_expected_spki" ] \
    && [ "$pair_key_spki" = "$pair_expected_spki" ] \
    && [ "$pair_leaf" = "$pair_expected_leaf" ]
}

for file_path in "$backup_cert" "$backup_key"; do
  [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 100
  [ "$(stat -c '%h' -- "$file_path")" -eq 1 ] || exit 101
done
require_pair_identity "$backup_cert" "$backup_key" "$expected_spki" "$expected_leaf" || exit 102
cp -- "$backup_cert" "$rollback_cert" || exit 103
cp -- "$backup_key" "$rollback_key" || exit 104
chmod 0600 -- "$rollback_cert" "$rollback_key" || exit 105
require_pair_identity "$rollback_cert" "$rollback_key" "$expected_spki" "$expected_leaf" || exit 106
mv -f -- "$rollback_cert" "$active_cert" || exit 107
mv -f -- "$rollback_key" "$active_key" || exit 108
require_pair_identity "$active_cert" "$active_key" "$expected_spki" "$expected_leaf"
REMOTE_ROLLBACK
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_remote_mailcow_transaction
#   Removes only the deterministic proven roll-over stæging directory.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - leæf SHÆ-256 trænsæction ID
#ææææææææææææææææææææææææææææææææææ
cleanup_remote_mailcow_transaction() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local transaction_id="$5"

  if ! run_bounded_ssh \
    "$CERTS_DUMPER_SSH_READ_TIMEOUT_SECONDS" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- "$project_path" "$transaction_id" <<'REMOTE_CLEANUP'
set -eu
project_path="$1"
transaction_id="$2"
transaction_path="${project_path}/data/assets/ssl/.certs-dumper-rollover-${transaction_id}"
[ -e "$transaction_path" ] || exit 0
[ -d "$transaction_path" ] && [ ! -L "$transaction_path" ] || exit 109
for file_name in backup-cert.pem backup-key.pem incoming-cert.pem incoming-key.pem activate-cert.pem activate-key.pem rollback-cert.pem rollback-key.pem; do
  file_path="${transaction_path}/${file_name}"
  if [ -e "$file_path" ] || [ -L "$file_path" ]; then
    [ -f "$file_path" ] && [ ! -L "$file_path" ] || exit 110
    rm -- "$file_path" || exit 111
  fi
done
rmdir -- "$transaction_path"
REMOTE_CLEANUP
  then
    return 1
  fi
  log_ok "Remote Mailcow roll-over backup removed after final DNS verification."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REMOTE SERVICE RESTÆRT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restart_remote_docker_compose
#   Restærts æ Docker Compose project on æ remote host viæ ssh.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote project pæth
#     $4 - SSH privæte key pæth
#     $5+ - optionæl: service næmes (e.g. postfix-mailcow); if omitted, restærts æll services.
#ææææææææææææææææææææææææææææææææææ
restart_remote_docker_compose() {
  local dest_host="$1"
  local dest_user="$2"
  local remote_project_path="$3"
  local ssh_key="$4"
  shift 4
  if [ "$#" -gt 0 ]; then
    log_info "Restarting Docker Compose services ($*) at ${remote_project_path} on ${dest_host}..."
  else
    log_info "Restarting Docker Compose at ${remote_project_path} on ${dest_host}..."
  fi

  if ! run_bounded_ssh \
    "$CERTS_DUMPER_SSH_MUTATION_TIMEOUT_SECONDS" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- "$remote_project_path" "$@" <<'REMOTE_COMPOSE_RESTART'
set -eu
project_path="$1"
shift
case "$project_path" in
  ''|'/'|*//*|*/../*|*/./*|*/..|*/.) exit 120 ;;
  /*) ;;
  *) exit 121 ;;
esac
for service_name in "$@"; do
  case "$service_name" in
    ''|*[!a-zA-Z0-9_-]*) exit 122 ;;
  esac
done
cd -- "$project_path"
docker compose restart "$@"
REMOTE_COMPOSE_RESTART
  then
    log_error "Failed to restart Docker Compose on ${dest_host}:${remote_project_path}"
  fi

  if [ "$#" -gt 0 ]; then
    log_ok "Docker Compose services ($*) restarted on ${dest_host}"
  else
    log_ok "Docker Compose restarted on ${dest_host}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restart_remote_mailcow_services
#   Restærts only the three Mæilcow TLS consumers; returns non-zero for rollbæck.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - optionæl totæl SSH deædline; defæult normæl mutætion bound
#ææææææææææææææææææææææææææææææææææ
restart_remote_mailcow_services() {
  local dest_host="$1"
  local dest_user="$2"
  local project_path="$3"
  local ssh_key="$4"
  local deadline_seconds="${5:-$CERTS_DUMPER_SSH_MUTATION_TIMEOUT_SECONDS}"

  log_info "Restarting Mailcow TLS services on ${dest_host}..."
  run_bounded_ssh \
    "$deadline_seconds" "$ssh_key" "$dest_user" "$dest_host" \
    sh -s -- "$project_path" <<'REMOTE_RESTART'
set -eu
project_path="$1"
cd -- "$project_path"
docker compose restart postfix-mailcow dovecot-mailcow nginx-mailcow
REMOTE_RESTART
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fetch_remote_smtp_identity
#   Reæds the leæf/SPKI identity currently served over SMTP STÆRTTLS.
#   Ærguments:
#     $1 - SMTP server æddress
#     $2 - expected SMTP TLS server næme
#ææææææææææææææææææææææææææææææææææ
fetch_remote_smtp_identity() {
  local smtp_address="$1"
  local smtp_hostname="$2"
  local smtp_output
  local served_spki
  local served_leaf

  if ! smtp_output="$(timeout "$CERTS_DUMPER_SMTP_ATTEMPT_SECONDS" openssl s_client -starttls smtp \
    -connect "${smtp_address}:25" -servername "$smtp_hostname" -name "$smtp_hostname" \
    -showcerts </dev/null 2>/dev/null)"; then
    return 1
  fi
  if ! served_spki="$(printf '%s\n' "$smtp_output" \
    | openssl x509 -noout -pubkey 2>/dev/null \
    | openssl pkey -pubin -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n')"; then
    return 1
  fi
  if ! served_leaf="$(printf '%s\n' "$smtp_output" \
    | openssl x509 -outform DER 2>/dev/null \
    | openssl dgst -sha256 -binary \
    | od -An -tx1 \
    | tr -d ' \n')"; then
    return 1
  fi
  is_valid_sha256_hash "$served_spki" && is_valid_sha256_hash "$served_leaf" || return 1
  printf '%s\n%s\n' "$served_spki" "$served_leaf"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_remote_smtp_identity
#   Wæits for one readable SMTP STÆRTTLS leæf/SPKI identity.
#   Ærguments:
#     $1 - SMTP server æddress
#     $2 - expected SMTP TLS server næme
#     $3 - optionæl mæximum totæl wæit in seconds
#ææææææææææææææææææææææææææææææææææ
get_remote_smtp_identity() {
  local smtp_address="$1"
  local smtp_hostname="$2"
  local maximum_wait="${3:-$CERTS_DUMPER_SMTP_WAIT_SECONDS}"
  local attempt=1
  local maximum_attempts
  local identity

  is_valid_bounded_integer "$maximum_wait" "$CERTS_DUMPER_SMTP_ATTEMPT_SECONDS" "$CERTS_DUMPER_SMTP_WAIT_SECONDS" \
    || return 1
  maximum_attempts=$((maximum_wait / (CERTS_DUMPER_SMTP_ATTEMPT_SECONDS + CERTS_DUMPER_SMTP_POLL_SECONDS)))
  [ "$maximum_attempts" -ge 1 ] || maximum_attempts=1
  while [ "$attempt" -le "$maximum_attempts" ]; do
    if identity="$(fetch_remote_smtp_identity "$smtp_address" "$smtp_hostname")"; then
      printf '%s\n' "$identity"
      return 0
    fi
    [ "$attempt" -lt "$maximum_attempts" ] || break
    sleep "$CERTS_DUMPER_SMTP_POLL_SECONDS"
    attempt=$((attempt + 1))
  done
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: verify_remote_smtp_identity
#   Requires SMTP STÆRTTLS to serve the exæct expected leæf ænd SPKI.
#   Ærguments:
#     $1 - SMTP server æddress
#     $2 - expected SMTP TLS server næme
#     $3 - expected SPKI SHÆ-256 hæsh
#     $4 - expected leæf SHÆ-256 fingerprint
#     $5 - optionæl mæximum totæl wæit in seconds
#ææææææææææææææææææææææææææææææææææ
verify_remote_smtp_identity() {
  local smtp_address="$1"
  local smtp_hostname="$2"
  local expected_spki="$3"
  local expected_leaf="$4"
  local maximum_wait="${5:-$CERTS_DUMPER_SMTP_WAIT_SECONDS}"
  local identity
  local served_spki
  local served_leaf

  identity="$(get_remote_smtp_identity "$smtp_address" "$smtp_hostname" "$maximum_wait")" || return 1
  served_spki="$(printf '%s\n' "$identity" | sed -n '1p')"
  served_leaf="$(printf '%s\n' "$identity" | sed -n '2p')"
  [ "$served_spki" = "$expected_spki" ] && [ "$served_leaf" = "$expected_leaf" ]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mailcow_emergency_rollback
#   Restores the prior remote pæir on every known post-æctivætion fæilure.
#ææææææææææææææææææææææææææææææææææ
mailcow_emergency_rollback() {
  local exit_status="$1"

  [ "$MAILCOW_ROLLBACK_ARMED" = true ] || return "$exit_status"
  MAILCOW_ROLLBACK_ARMED=false
  log_warn "Mailcow certificate activation did not complete verification; attempting the retained-pair rollback."
  if rollback_remote_mailcow_certificate \
    "$MAILCOW_ROLLBACK_DEST_HOST" "$MAILCOW_ROLLBACK_DEST_USER" \
    "$MAILCOW_ROLLBACK_PROJECT_PATH" "$MAILCOW_ROLLBACK_SSH_KEY" \
    "$MAILCOW_ROLLBACK_TRANSACTION_ID" "$MAILCOW_ROLLBACK_EXPECTED_SPKI" \
    "$MAILCOW_ROLLBACK_EXPECTED_LEAF" \
    && restart_remote_mailcow_services \
      "$MAILCOW_ROLLBACK_DEST_HOST" "$MAILCOW_ROLLBACK_DEST_USER" \
      "$MAILCOW_ROLLBACK_PROJECT_PATH" "$MAILCOW_ROLLBACK_SSH_KEY" \
      "$CERTS_DUMPER_SSH_ROLLBACK_RESTART_TIMEOUT_SECONDS" \
    && verify_remote_smtp_identity \
      "$MAILCOW_SSH_RESOLVED_ADDRESS" "$MAILCOW_SMTP_HOSTNAME" \
      "$MAILCOW_ROLLBACK_EXPECTED_SPKI" "$MAILCOW_ROLLBACK_EXPECTED_LEAF" \
      "$CERTS_DUMPER_SMTP_ROLLBACK_WAIT_SECONDS"; then
    log_warn "Mailcow rollback restored and re-verified the prior SMTP certificate; the transitional TLSA RRset remains published for a safe retry."
  else
    log_warn "Mailcow rollback could not be fully verified. Keep both TLSA records and inspect the deterministic remote transaction backup before manual intervention."
  fi
  return "$exit_status"
}

mailcow_cleanup_only_dispatcher() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  cleanup_all_mailcow_temporary_files
  return "$exit_status"
}

mailcow_exit_dispatcher() {
  local exit_status="$?"

  trap - EXIT HUP INT TERM
  cleanup_all_mailcow_temporary_files
  if [ "$MAILCOW_ROLLBACK_ARMED" = true ]; then
    trap 'mailcow_cleanup_only_dispatcher' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mailcow_emergency_rollback "$exit_status" || true
    trap - EXIT HUP INT TERM
  fi
  return "$exit_status"
}

install_mailcow_transaction_traps() {
  trap 'mailcow_exit_dispatcher' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: arm_mailcow_rollback
#   Ærms exit ænd signæl træps before the first remote æctivætion mutætion.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote Mæilcow project pæth
#     $4 - SSH privæte key pæth
#     $5 - new leæf SHÆ-256 trænsæction ID
#     $6 - prior SPKI SHÆ-256 hæsh
#     $7 - prior leæf SHÆ-256 fingerprint
#ææææææææææææææææææææææææææææææææææ
arm_mailcow_rollback() {
  MAILCOW_ROLLBACK_DEST_HOST="$1"
  MAILCOW_ROLLBACK_DEST_USER="$2"
  MAILCOW_ROLLBACK_PROJECT_PATH="$3"
  MAILCOW_ROLLBACK_SSH_KEY="$4"
  MAILCOW_ROLLBACK_TRANSACTION_ID="$5"
  MAILCOW_ROLLBACK_EXPECTED_SPKI="$6"
  MAILCOW_ROLLBACK_EXPECTED_LEAF="$7"
  MAILCOW_ROLLBACK_ARMED=true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: disarm_mailcow_rollback
#   Disærms the retained-pæir rollbæck only æfter exæct SMTP verificætion.
#ææææææææææææææææææææææææææææææææææ
disarm_mailcow_rollback() {
  MAILCOW_ROLLBACK_ARMED=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: revalidate_mailcow_pre_activation_state
#   Rechecks remote identity ænd the exæct provider/DNSSEC overlap after stæging.
#ææææææææææææææææææææææææææææææææææ
revalidate_mailcow_pre_activation_state() {
  local transition_required="$1"
  local zone_handle="$2"
  local expected_response="$3"
  local expected_old_spki="$4"
  local expected_new_spki="$5"
  local expected_remote_spki="$6"
  local expected_remote_leaf="$7"
  local refreshed_zone
  local refreshed_response
  local expected_snapshot
  local refreshed_snapshot

  verify_remote_smtp_identity \
    "$MAILCOW_SSH_RESOLVED_ADDRESS" "$MAILCOW_SMTP_HOSTNAME" \
    "$expected_remote_spki" "$expected_remote_leaf" "$CERTS_DUMPER_SMTP_ATTEMPT_SECONDS" \
    || log_error "Mailcow SMTP identity drifted while the new pair was staged"
  [ "$transition_required" = true ] || return 0
  refreshed_zone="$(dns_require_zone "$MAILCOW_DNS_ZONE_NAME")"
  [ "$refreshed_zone" = "$zone_handle" ] \
    || log_error "Selected-provider Mailcow zone identity drifted before certificate activation"
  dns_require_dnssec "$refreshed_zone"
  expected_snapshot="$(canonical_mailcow_tlsa_snapshot "$expected_response")"
  refreshed_response="$(dns_get_tlsa_records "$refreshed_zone" "$MAILCOW_TLSA_RECORD_NAME")"
  refreshed_snapshot="$(canonical_mailcow_tlsa_snapshot "$refreshed_response")"
  [ "$refreshed_snapshot" = "$expected_snapshot" ] \
    || log_error "Selected-provider Mailcow TLSA RRset drifted before certificate activation"
  dnssec_tlsa_rrset_matches \
    "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" \
    "$expected_old_spki" "$expected_new_spki" \
    || log_error "DNSSEC-validating resolver lost the exact Mailcow TLSA overlap before certificate activation"
  verify_remote_smtp_identity \
    "$MAILCOW_SSH_RESOLVED_ADDRESS" "$MAILCOW_SMTP_HOSTNAME" \
    "$expected_remote_spki" "$expected_remote_leaf" "$CERTS_DUMPER_SMTP_ATTEMPT_SECONDS" \
    || log_error "Mailcow SMTP identity changed immediately before certificate activation"
  refreshed_response="$(dns_get_tlsa_records "$refreshed_zone" "$MAILCOW_TLSA_RECORD_NAME")"
  refreshed_snapshot="$(canonical_mailcow_tlsa_snapshot "$refreshed_response")"
  [ "$refreshed_snapshot" = "$expected_snapshot" ] \
    || log_error "Selected-provider Mailcow TLSA RRset changed immediately before certificate activation"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: deploy_mailcow_certificate_pair
#   Stæges, æctivætes, restærts ænd verifies one Mæilcow pæir under rollbæck guærd.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote Mæilcow project pæth
#     $6 - SSH privæte key pæth
#     $7 - new SPKI SHÆ-256 hæsh
#     $8 - new leæf SHÆ-256 fingerprint
#     $9 - prior SPKI SHÆ-256 hæsh
#     $10 - prior leæf SHÆ-256 fingerprint
#     $11 - whether exæct two-record DÆNE overlæp is required
#     $12 - selected-provider zone hændle
#     $13 - exæct expected provider response snæpshot
#     $14 - prior DÆNE SPKI hæsh
#ææææææææææææææææææææææææææææææææææ
deploy_mailcow_certificate_pair() {
  local local_cert="$1"
  local local_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local project_path="$5"
  local ssh_key="$6"
  local new_spki="$7"
  local new_leaf="$8"
  local prior_spki="$9"
  local prior_leaf="${10}"
  local transition_required="${11}"
  local zone_handle="${12}"
  local expected_records_response="${13}"
  local prior_dane_spki="${14}"

  if ! stage_remote_mailcow_certificate \
    "$local_cert" "$local_key" "$dest_host" "$dest_user" "$project_path" \
    "$ssh_key" "$new_leaf" "$new_spki" "$prior_spki" "$prior_leaf"; then
    log_error "Could not stage and validate the remote Mailcow certificate transaction"
  fi
  revalidate_mailcow_pre_activation_state \
    "$transition_required" "$zone_handle" "$expected_records_response" \
    "$prior_dane_spki" "$new_spki" "$prior_spki" "$prior_leaf"
  arm_mailcow_rollback \
    "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
    "$new_leaf" "$prior_spki" "$prior_leaf"
  if ! activate_remote_mailcow_certificate \
    "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
    "$new_leaf" "$new_spki" "$prior_spki" "$prior_leaf"; then
    log_error "Could not activate the staged Mailcow certificate transaction"
  fi
  if ! restart_remote_mailcow_services "$dest_host" "$dest_user" "$project_path" "$ssh_key"; then
    log_error "Could not restart all targeted Mailcow TLS consumers"
  fi
  if ! verify_remote_smtp_identity "$MAILCOW_SSH_RESOLVED_ADDRESS" "$MAILCOW_SMTP_HOSTNAME" "$new_spki" "$new_leaf"; then
    log_error "Mailcow SMTP STARTTLS did not serve the exact newly activated leaf and SPKI"
  fi
  disarm_mailcow_rollback
  log_ok "Mailcow SMTP STARTTLS serves the exact renewed certificate and SPKI."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆILCOW ENTRYPOINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mæilcow
#   Runs one resumæble RFC 7671 Mæilcow/DÆNE certificæte roll-over.
#ææææææææææææææææææææææææææææææææææ
mailcow() {
  [ "$#" -eq 0 ] || log_error "mailcow does not accept arguments"
  run_mailcow_with_lock
}

mailcow_locked() {
  local ssh_key="$CERTS_DUMPER_SSH_IDENTITY_FILE"
  local dest_host="$MAILCOW_SSH_HOST_INPUT"
  local dest_user="$MAILCOW_SSH_USER_INPUT"
  local project_path="$MAILCOW_PROJECT_PATH"
  local local_cert
  local local_key
  local local_spki
  local local_leaf
  local dns_zone_handle
  local records_response
  local records_json
  local record_count
  local first_hash
  local second_hash=''
  local old_hash=''
  local old_record
  local old_record_id
  local remote_identity
  local remote_spki
  local remote_leaf
  local observation_wait
  local overlap_wait

  validate_mailcow_lock_context
  install_mailcow_transaction_traps
  prepare_mailcow_runtime
  [ "${CERTS_DUMPER_OUTPUT_GENERATION:-}" = /run/certs-dumper/vendor-output ] \
    || log_error "Mailcow requires one supervisor-pinned certificate generation"
  local_cert="${CERTS_DUMPER_OUTPUT_GENERATION}/${MAILCOW_CERT_MAIN_DOMAIN}/certificate.pem"
  local_key="${CERTS_DUMPER_OUTPUT_GENERATION}/${MAILCOW_CERT_MAIN_DOMAIN}/privatekey.pem"
  wait_for_certificate_files "$local_cert" "$local_key"
  require_certificate_key_pair "$local_cert" "$local_key"
  require_certificate_hostname "$local_cert" "$MAILCOW_SMTP_HOSTNAME"
  local_spki="$(calculate_tlsa_spki_sha256 "$local_cert")"
  local_leaf="$(calculate_certificate_sha256 "$local_cert")"
  is_valid_sha256_hash "$local_spki" || log_error "Could not derive a canonical Mailcow TLSA SPKI hash"
  is_valid_sha256_hash "$local_leaf" || log_error "Could not derive a canonical Mailcow leaf fingerprint"
  read_dns_api_token >/dev/null

  dns_zone_handle="$(dns_require_zone "$MAILCOW_DNS_ZONE_NAME")"
  dns_require_dnssec "$dns_zone_handle"

  records_response="$(dns_get_tlsa_records "$dns_zone_handle" "$MAILCOW_TLSA_RECORD_NAME")"
  MAILCOW_DANE_TTL_SECONDS="$(derive_mailcow_tlsa_ttl \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME")"
  records_json="$(select_mailcow_tlsa_records \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
  observation_wait=$((MAILCOW_DANE_TTL_SECONDS + MAILCOW_DANE_TTL_SAFETY_SECONDS))
  overlap_wait=$((2 * MAILCOW_DANE_TTL_SECONDS + MAILCOW_DANE_TTL_SAFETY_SECONDS))
  record_count="$(printf '%s' "$records_json" | jq -r 'length')"
  first_hash="$(printf '%s' "$records_json" | jq -r \
    '.[0] | (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase)')"
  if [ "$record_count" -eq 2 ]; then
    second_hash="$(printf '%s' "$records_json" | jq -r \
      '.[1] | (.data.certificate // ((.content // "" | split(" ") | .[3] // "")) | ascii_downcase)')"
    wait_for_dnssec_tlsa_rrset \
      "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
      "$first_hash" "$second_hash"
  else
    wait_for_dnssec_tlsa_rrset \
      "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
      "$first_hash"
  fi

  remote_identity="$(get_remote_smtp_identity "$MAILCOW_SSH_RESOLVED_ADDRESS" "$MAILCOW_SMTP_HOSTNAME")" \
    || log_error "Could not read the current Mailcow SMTP STARTTLS certificate identity"
  remote_spki="$(printf '%s\n' "$remote_identity" | sed -n '1p')"
  remote_leaf="$(printf '%s\n' "$remote_identity" | sed -n '2p')"
  if ! is_valid_sha256_hash "$remote_spki" || ! is_valid_sha256_hash "$remote_leaf"; then
    log_error "Mailcow SMTP STARTTLS returned a non-canonical certificate identity"
  fi
  mailcow_tlsa_rrset_contains_hash "$records_json" "$remote_spki" \
    || log_error "The active Mailcow SMTP SPKI is not protected by the current exact TLSA RRset"

  case "$record_count" in
    1)
      [ "$remote_spki" = "$first_hash" ] \
        || log_error "The stable Mailcow TLSA record does not match the active SMTP SPKI"
      if [ "$local_spki" = "$remote_spki" ]; then
        if [ "$local_leaf" != "$remote_leaf" ]; then
          log_info "Mailcow renewal keeps the existing SPKI; deploying the renewed leaf without DNS mutation."
          deploy_mailcow_certificate_pair \
            "$local_cert" "$local_key" "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
            "$local_spki" "$local_leaf" "$remote_spki" "$remote_leaf" \
            false "$dns_zone_handle" "$records_response" "$remote_spki"
        else
          log_ok "Mailcow already serves the exact dumped leaf and SPKI; no deployment is needed."
        fi
        cleanup_remote_mailcow_transaction \
          "$dest_host" "$dest_user" "$project_path" "$ssh_key" "$local_leaf"
        return 0
      fi

      old_hash="$remote_spki"
      dns_create_tlsa_record \
        "$dns_zone_handle" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" \
        "$local_spki" "$records_response"
      records_response="$(dns_get_tlsa_records "$dns_zone_handle" "$MAILCOW_TLSA_RECORD_NAME")"
      records_json="$(select_mailcow_tlsa_records \
        "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
      [ "$(printf '%s' "$records_json" | jq -r 'length')" -eq 2 ] \
        || log_error "DNS provider did not return the expected two-record transitional Mailcow TLSA RRset"
      if ! mailcow_tlsa_rrset_contains_hash "$records_json" "$old_hash" \
        || ! mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki"; then
        log_error "The transitional Mailcow TLSA RRset does not contain exactly the prior and future SPKI hashes"
      fi
      wait_for_dnssec_tlsa_rrset \
        "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
        "$old_hash" "$local_spki"
      wait_for_dane_window "pre-deployment overlap" "$overlap_wait"
      ;;
    2)
      mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki" \
        || log_error "The resumable transitional Mailcow TLSA RRset does not contain the dumped certificate SPKI"
      if [ "$first_hash" = "$local_spki" ]; then
        old_hash="$second_hash"
      else
        old_hash="$first_hash"
      fi
      if [ "$remote_spki" != "$local_spki" ]; then
        [ "$remote_spki" = "$old_hash" ] \
          || log_error "The active SMTP SPKI matches neither side of the transitional Mailcow TLSA RRset"
        log_info "Resuming a pre-deployment Mailcow DANE transition with both TLSA records already published."
        wait_for_dane_window "resumed pre-deployment overlap" "$overlap_wait"
      else
        log_info "Resuming a post-deployment Mailcow DANE transition with both TLSA records still published."
      fi
      ;;
    *) log_error "Unexpected Mailcow TLSA RRset cardinality after validation" ;;
  esac

  if [ "$remote_leaf" != "$local_leaf" ] || [ "$remote_spki" != "$local_spki" ]; then
    deploy_mailcow_certificate_pair \
      "$local_cert" "$local_key" "$dest_host" "$dest_user" "$project_path" "$ssh_key" \
      "$local_spki" "$local_leaf" "$remote_spki" "$remote_leaf" \
      true "$dns_zone_handle" "$records_response" "$old_hash"
  else
    log_ok "Mailcow already serves the exact new leaf and SPKI; continuing the resumable DNS retirement phase."
  fi

  wait_for_dane_window "post-deployment overlap" "$overlap_wait"
  records_response="$(dns_get_tlsa_records "$dns_zone_handle" "$MAILCOW_TLSA_RECORD_NAME")"
  records_json="$(select_mailcow_tlsa_records \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
  [ "$(printf '%s' "$records_json" | jq -r 'length')" -eq 2 ] \
    || log_error "The Mailcow TLSA RRset changed before retirement of the prior key"
  if ! mailcow_tlsa_rrset_contains_hash "$records_json" "$old_hash" \
    || ! mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki"; then
    log_error "The Mailcow TLSA RRset no longer contains the proven prior/new hash pair"
  fi
  wait_for_dnssec_tlsa_rrset \
    "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
    "$old_hash" "$local_spki"
  verify_remote_smtp_identity "$MAILCOW_SSH_RESOLVED_ADDRESS" "$MAILCOW_SMTP_HOSTNAME" "$local_spki" "$local_leaf" \
    || log_error "Mailcow SMTP STARTTLS identity changed before retirement of the prior TLSA record"

  old_record="$(select_mailcow_tlsa_record_by_hash "$records_json" "$old_hash")"
  old_record_id="$(printf '%s' "$old_record" | jq -r '.id')"
  dns_delete_tlsa_record "$dns_zone_handle" "$old_record_id" "$records_response"
  records_response="$(dns_get_tlsa_records "$dns_zone_handle" "$MAILCOW_TLSA_RECORD_NAME")"
  records_json="$(select_mailcow_tlsa_records \
    "$records_response" "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS")"
  if [ "$(printf '%s' "$records_json" | jq -r 'length')" -ne 1 ] \
    || ! mailcow_tlsa_rrset_contains_hash "$records_json" "$local_spki"; then
    log_error "DNS provider did not converge to the one-record final Mailcow TLSA RRset"
  fi
  wait_for_dnssec_tlsa_rrset \
    "$MAILCOW_TLSA_RECORD_NAME" "$MAILCOW_DANE_TTL_SECONDS" "$observation_wait" \
    "$local_spki"
  cleanup_remote_mailcow_transaction \
    "$dest_host" "$dest_user" "$project_path" "$ssh_key" "$local_leaf"
  log_ok "Mailcow DANE roll-over completed with the exact new TLSA 3 1 1 record."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: example_other_service
#   Templæte function for ædditionæl destinætions.
#   Clone ænd ædæpt for eæch remote host.
#ææææææææææææææææææææææææææææææææææ
example_other_service() {
  local ssh_key="$CERTS_DUMPER_SSH_IDENTITY_FILE"
  local dest_host="192.168.20.121"
  local dest_user="root"
  local project_path="/opt/other-service"
  local local_cert="${CERTS_DUMPER_OUTPUT_GENERATION:?Supervisor generation required}/other.domain.tld/certificate.pem"
  local local_key="${CERTS_DUMPER_OUTPUT_GENERATION}/other.domain.tld/privatekey.pem"
  local remote_cert="${project_path}/certs/cert.pem"
  local remote_key="${project_path}/certs/key.pem"

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

if [ "${CERTS_DUMPER_POST_HOOK_LIBRARY_ONLY:-false}" != true ]; then
  check_dependencies printf
  case "${1:-}" in
    '')
# if true; then mailcow; fi
      ;;
    --mailcow-locked)
      [ "$#" -eq 1 ] || log_error "--mailcow-locked does not accept additional arguments"
      mailcow_locked
      ;;
    --preflight)
      [ "$#" -eq 1 ] || log_error "--preflight does not accept additional arguments"
      ;;
    --preflight-mailcow)
      [ "$#" -eq 1 ] || log_error "--preflight-mailcow does not accept additional arguments"
      preflight_mailcow_container
      ;;
    *) log_error "Unsupported post-hook argument" ;;
  esac
  log_ok "All post-hook tasks completed."
fi
