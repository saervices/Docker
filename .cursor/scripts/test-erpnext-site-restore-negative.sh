#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Reæl-imæge ERPNext site-restore negætive mætrix.
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Responsibilities
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Responsibilities:
#   1. Run the deployæble restore controller inside the reæl custom
#      site-mæintenænce imæge ægæinst hostile bundle inputs in æn isolæted
#      /tmp fixture.
#   2. Prove every negætive cæse fæils closed with æ non-zero exit ænd the
#      documented fæil-closed messæge before æny site or bundle mutætion.
#   3. Derive the shæred runtime-mænifest fixture from the selected imæge's
#      exæct embedded mænifest ænd mount it reæd-only for every cæse.
#   4. Prove the mounted bæckup tree is pæth-, type-, mode-, ænd byte-identicæl
#      æfter the complete mætrix, then remove the fixture exæctly.

set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
readonly MAINTENANCE_SCRIPT="${REPO_ROOT}/templates/erpnext-site-maintenance/scripts/erpnext-site-maintenance.sh"
readonly RESTORE_HELPER="${REPO_ROOT}/templates/erpnext-site-maintenance/scripts/erpnext-site-restore.py"
readonly MAINTENANCE_BUILD_CONTEXT="${REPO_ROOT}/templates/erpnext-site-maintenance/dockerfiles"
readonly MAINTENANCE_DOCKERFILE="${MAINTENANCE_BUILD_CONTEXT}/dockerfile.erpnext-site-maintenance"
readonly PREBUILT_TEST_IMAGE="${ERPNEXT_RESTORE_NEGATIVE_IMAGE:-saervices/erpnext-site-maintenance:v16}"
readonly BUILD_TEST_IMAGE="${ERPNEXT_RESTORE_NEGATIVE_BUILD:-true}"
readonly PULL_BUILD_BASES="${ERPNEXT_RESTORE_NEGATIVE_PULL:-false}"
readonly ERPNEXT_BASE_IMAGE="${ERPNEXT_RESTORE_NEGATIVE_BASE_IMAGE:-frappe/erpnext:v16}"
readonly SUPERCRONIC_FETCH_IMAGE="${ERPNEXT_RESTORE_NEGATIVE_FETCH_IMAGE:-alpine:3}"
readonly AUDIT_IMAGE_REPOSITORY='saervices/erpnext-site-maintenance-audit'
readonly IMAGE_RUNTIME_MANIFEST='/usr/local/share/saervices-erpnext-runtime-manifest'
readonly SHARED_RUNTIME_MANIFEST_DIR='/var/lib/saervices-erpnext-runtime-manifest'
readonly BENCH_PYTHON='/home/frappe/frappe-bench/env/bin/python'
readonly MAX_RUNTIME_MANIFEST_BYTES=1048576
readonly FIXTURE_PARENT='/tmp'
readonly TEST_SITE_NAME='erpnext.audit-fixture.net'
readonly HOST_UID="$(id -u)"
readonly HOST_GID="$(id -g)"

FIXTURE_DIR=''
FIXTURE_FD=''
FIXTURE_ID=''
FIXTURE_PARENT_ID=''
ACTIVE_TEST_IMAGE=''
GENERATED_TEST_IMAGE=''
GENERATED_TEST_IMAGE_ID=''
GENERATED_TEST_IIDFILE=''
GENERATED_TEST_IIDFILE_ID=''
TEST_IMAGE_ID=''
PROBED_IMAGE_STATE=''
PROBED_IMAGE_ID=''
FAILURES=0

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge.
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '[test-erpnext-site-restore-negative] INFO: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ wærning without recording æ test fæilure.
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  printf '[test-erpnext-site-restore-negative] WARN: %s\n' "$*" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ pæssed check.
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '[test-erpnext-site-restore-negative] OK: %s\n' "$*"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æ fæiled check ænd records the fæilure.
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '[test-erpnext-site-restore-negative] ERROR: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ fætæl setup fæilure ænd exits immediætely.
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  printf '[test-erpnext-site-restore-negative] FATAL: %s\n' "$*" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: path_identity
#   Returns one no-follow device/inode identity.
#   Ærguments:
#     $1 - Existing pæth
#ææææææææææææææææææææææææææææææææææ
path_identity() {
  stat -c '%d:%i' -- "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: descriptor_identity
#   Returns the device/inode identity held by one open descriptor.
#   Ærguments:
#     $1 - Open descriptor number
#ææææææææææææææææææææææææææææææææææ
descriptor_identity() {
  local descriptor="$1"
  local descriptor_path="/proc/$$/fd/${descriptor}"

  [[ -d "$descriptor_path" ]] || return 1
  stat -Lc '%d:%i' -- "$descriptor_path"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: adopt_generated_image_identity
#   Recovers the build-produced imæge ID from its privæte IID file.
#ææææææææææææææææææææææææææææææææææ
adopt_generated_image_identity() {
  local current_iidfile_id=''
  local iidfile_metadata=''
  local recovered_image_id=''

  [[ -n "$FIXTURE_DIR" && -n "$FIXTURE_ID" \
    && "$GENERATED_TEST_IIDFILE" == "${FIXTURE_DIR}/build-image.id" \
    && -f "$GENERATED_TEST_IIDFILE" && ! -L "$GENERATED_TEST_IIDFILE" ]] \
    || return 1
  [[ "$(path_identity "$FIXTURE_DIR")" == "$FIXTURE_ID" \
    && "$(descriptor_identity "$FIXTURE_FD")" == "$FIXTURE_ID" ]] \
    || return 1
  iidfile_metadata="$(stat -c '%u:%a:%s' -- "$GENERATED_TEST_IIDFILE")" \
    || return 1
  [[ "$iidfile_metadata" =~ ^${HOST_UID}:600:([1-9][0-9]?)$ ]] || return 1
  current_iidfile_id="$(path_identity "$GENERATED_TEST_IIDFILE")" || return 1
  recovered_image_id="$(< "$GENERATED_TEST_IIDFILE")"
  [[ "$recovered_image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
  [[ "$(path_identity "$GENERATED_TEST_IIDFILE")" == "$current_iidfile_id" ]] \
    || return 1
  GENERATED_TEST_IIDFILE_ID="$current_iidfile_id"
  GENERATED_TEST_IMAGE_ID="$recovered_image_id"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: probe_image_reference
#   Resolves one locæl imæge reference to present or æbsent without conflæting
#   inspect fæilure with Docker dæemon fæilure.
#   Ærguments:
#     $1 - Exæct locæl imæge reference
#ææææææææææææææææææææææææææææææææææ
probe_image_reference() {
  local image_reference="$1"
  local inspected_image_id=''
  local listed_image_ids=''

  PROBED_IMAGE_STATE=''
  PROBED_IMAGE_ID=''
  if inspected_image_id="$(docker image inspect --format '{{.Id}}' \
    "$image_reference" 2>/dev/null)"; then
    [[ "$inspected_image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || return 1
    PROBED_IMAGE_STATE='present'
    PROBED_IMAGE_ID="$inspected_image_id"
    return 0
  fi
  listed_image_ids="$(docker image ls --no-trunc --quiet "$image_reference")" \
    || return 1
  [[ -z "$listed_image_ids" ]] || return 1
  PROBED_IMAGE_STATE='absent'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_generated_image
#   Removes only the unique æudit tæg still bound to its proven imæge ID.
#ææææææææææææææææææææææææææææææææææ
cleanup_generated_image() {
  local removal_status=0

  [[ -n "$GENERATED_TEST_IMAGE" ]] || return 0
  probe_image_reference "$GENERATED_TEST_IMAGE" || {
    printf '[test-erpnext-site-restore-negative] ERROR: Unable to establish the audit-tag state before cleanup.\n' >&2
    return 1
  }
  if [[ "$PROBED_IMAGE_STATE" == 'absent' ]]; then
    GENERATED_TEST_IMAGE=''
    GENERATED_TEST_IMAGE_ID=''
    GENERATED_TEST_IIDFILE=''
    GENERATED_TEST_IIDFILE_ID=''
    return 0
  fi
  if [[ -z "$GENERATED_TEST_IMAGE_ID" ]]; then
    adopt_generated_image_identity || {
      printf '[test-erpnext-site-restore-negative] ERROR: Unable to recover the build-produced audit-image identity.\n' >&2
      return 1
    }
  fi
  [[ -n "$GENERATED_TEST_IIDFILE_ID" \
    && "$(path_identity "$GENERATED_TEST_IIDFILE")" == "$GENERATED_TEST_IIDFILE_ID" ]] || {
    printf '[test-erpnext-site-restore-negative] ERROR: Refusing ambiguous audit-image cleanup.\n' >&2
    return 1
  }
  if [[ "$PROBED_IMAGE_ID" != "$GENERATED_TEST_IMAGE_ID" ]]; then
    printf '[test-erpnext-site-restore-negative] ERROR: Refusing drifted audit-image cleanup.\n' >&2
    return 1
  fi
  docker image rm "$GENERATED_TEST_IMAGE" >/dev/null || removal_status=$?
  probe_image_reference "$GENERATED_TEST_IMAGE" || {
    printf '[test-erpnext-site-restore-negative] ERROR: Unable to establish the audit-tag state after cleanup.\n' >&2
    return 1
  }
  if [[ "$PROBED_IMAGE_STATE" != 'absent' ]]; then
    if [[ "$PROBED_IMAGE_ID" != "$GENERATED_TEST_IMAGE_ID" ]]; then
      printf '[test-erpnext-site-restore-negative] ERROR: The audit tag drifted during cleanup.\n' >&2
    elif (( removal_status != 0 )); then
      printf '[test-erpnext-site-restore-negative] ERROR: Docker failed to remove the exact audit tag, which remains present.\n' >&2
    else
      printf '[test-erpnext-site-restore-negative] ERROR: The exact audit tag remains present after Docker reported successful removal.\n' >&2
    fi
    return 1
  fi
  if (( removal_status != 0 )); then
    log_warn 'Docker reported a removal error, but the independently probed unique audit tag is absent.'
  fi
  GENERATED_TEST_IMAGE=''
  GENERATED_TEST_IMAGE_ID=''
  GENERATED_TEST_IIDFILE=''
  GENERATED_TEST_IIDFILE_ID=''
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only the identity-pinned fixture ænd proven unique æudit tæg.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  local current_descriptor_id=''
  local current_fixture_id=''
  local current_parent_id=''
  local cleanup_status=0

  cleanup_generated_image || cleanup_status=1
  if (( cleanup_status == 0 )) && [[ -n "$FIXTURE_DIR" ]]; then
    if [[ "$FIXTURE_DIR" != /tmp/erpnext-site-restore-negative.* \
      || ! -d "$FIXTURE_DIR" || -L "$FIXTURE_DIR" \
      || ! "$FIXTURE_FD" =~ ^[0-9]+$ ]]; then
      printf '[test-erpnext-site-restore-negative] ERROR: Refusing unsafe fixture cleanup.\n' >&2
      cleanup_status=1
    else
      current_parent_id="$(path_identity "$FIXTURE_PARENT")" || cleanup_status=1
      current_fixture_id="$(path_identity "$FIXTURE_DIR")" || cleanup_status=1
      current_descriptor_id="$(descriptor_identity "$FIXTURE_FD")" || cleanup_status=1
      if (( cleanup_status == 0 )) \
        && [[ "$current_parent_id" == "$FIXTURE_PARENT_ID" \
          && "$current_fixture_id" == "$FIXTURE_ID" \
          && "$current_descriptor_id" == "$FIXTURE_ID" ]]; then
        if ! (
          cd -- "/proc/$$/fd/${FIXTURE_FD}" \
            && find -P . -xdev -depth -mindepth 1 -delete
        ); then
          cleanup_status=1
        fi
        current_fixture_id="$(path_identity "$FIXTURE_DIR")" || cleanup_status=1
        current_descriptor_id="$(descriptor_identity "$FIXTURE_FD")" || cleanup_status=1
        if (( cleanup_status == 0 )) \
          && [[ "$current_fixture_id" == "$FIXTURE_ID" \
            && "$current_descriptor_id" == "$FIXTURE_ID" ]] \
          && rmdir -- "$FIXTURE_DIR"; then
          exec {FIXTURE_FD}<&-
          FIXTURE_DIR=''
          FIXTURE_FD=''
          FIXTURE_ID=''
        else
          cleanup_status=1
        fi
      else
        printf '[test-erpnext-site-restore-negative] ERROR: Refusing identity-drifted fixture cleanup.\n' >&2
        cleanup_status=1
      fi
    fi
  fi
  return "$cleanup_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: handle_exit
#   Preserves the originæl stætus while enforcing exæct fixture cleænup.
#   Ærguments:
#     $1 - Originæl exit stætus
#ææææææææææææææææææææææææææææææææææ
handle_exit() {
  local status="$1"

  trap - EXIT
  trap '' HUP INT TERM
  cleanup || status=1
  exit "$status"
}

trap 'handle_exit $?' EXIT
trap 'handle_exit 129' HUP
trap 'handle_exit 130' INT
trap 'handle_exit 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_test_image
#   Builds one current-source æudit imæge or selects explicit prebuilt mode.
#ææææææææææææææææææææææææææææææææææ
prepare_test_image() {
  local build_iidfile="${FIXTURE_DIR}/build-image.id"

  [[ "$BUILD_TEST_IMAGE" == 'true' || "$BUILD_TEST_IMAGE" == 'false' ]] \
    || log_fatal 'ERPNEXT_RESTORE_NEGATIVE_BUILD must be exactly true or false.'
  [[ "$PULL_BUILD_BASES" == 'true' || "$PULL_BUILD_BASES" == 'false' ]] \
    || log_fatal 'ERPNEXT_RESTORE_NEGATIVE_PULL must be exactly true or false.'
  if [[ "$BUILD_TEST_IMAGE" == 'true' ]]; then
    if [[ "$PULL_BUILD_BASES" == 'true' ]]; then
      log_info 'Explicit base pull enabled; refreshing the configured ERPNext and fetch-image major tags.'
      docker pull "$ERPNEXT_BASE_IMAGE" >/dev/null \
        || log_fatal "Unable to pull the ERPNext build base ${ERPNEXT_BASE_IMAGE}."
      docker pull "$SUPERCRONIC_FETCH_IMAGE" >/dev/null \
        || log_fatal "Unable to pull the Supercronic fetch base ${SUPERCRONIC_FETCH_IMAGE}."
    else
      probe_image_reference "$ERPNEXT_BASE_IMAGE" \
        || log_fatal "Unable to establish the local build-base state for ${ERPNEXT_BASE_IMAGE}."
      [[ "$PROBED_IMAGE_STATE" == 'present' ]] \
        || log_fatal "The local build base ${ERPNEXT_BASE_IMAGE} is missing. Pull it manually or set ERPNEXT_RESTORE_NEGATIVE_PULL=true."
      probe_image_reference "$SUPERCRONIC_FETCH_IMAGE" \
        || log_fatal "Unable to establish the local build-base state for ${SUPERCRONIC_FETCH_IMAGE}."
      [[ "$PROBED_IMAGE_STATE" == 'present' ]] \
        || log_fatal "The local build base ${SUPERCRONIC_FETCH_IMAGE} is missing. Pull it manually or set ERPNEXT_RESTORE_NEGATIVE_PULL=true."
    fi
    ACTIVE_TEST_IMAGE="${AUDIT_IMAGE_REPOSITORY}:audit-${HOST_UID}-${BASHPID}-${RANDOM}"
    probe_image_reference "$ACTIVE_TEST_IMAGE" \
      || log_fatal 'Unable to establish the unique audit-tag state before the build.'
    [[ "$PROBED_IMAGE_STATE" == 'absent' ]] \
      || log_fatal 'The unique audit-image tag unexpectedly already exists.'
    GENERATED_TEST_IMAGE="$ACTIVE_TEST_IMAGE"
    GENERATED_TEST_IIDFILE="$build_iidfile"
    log_info "Building unique current-source audit image ${ACTIVE_TEST_IMAGE} with --pull=false --no-cache."
    log_info 'The standalone maintenance context needs no run.sh generator; its moving Supercronic build step still requires network access.'
    docker build --pull=false --no-cache --tag "$ACTIVE_TEST_IMAGE" \
      --iidfile "$build_iidfile" \
      --build-arg "ERPNEXT_BASE_IMAGE=${ERPNEXT_BASE_IMAGE}" \
      --build-arg "ERPNEXT_SITE_MAINTENANCE_SUPERCRONIC_FETCH_IMAGE=${SUPERCRONIC_FETCH_IMAGE}" \
      --file "$MAINTENANCE_DOCKERFILE" "$MAINTENANCE_BUILD_CONTEXT" \
      || log_fatal 'Unable to build the unique current-source audit image.'
    adopt_generated_image_identity \
      || log_fatal 'The audit build did not publish a safe private image-ID file.'
    TEST_IMAGE_ID="$GENERATED_TEST_IMAGE_ID"
    probe_image_reference "$ACTIVE_TEST_IMAGE" \
      || log_fatal 'Unable to establish the current-source audit-image state.'
    [[ "$PROBED_IMAGE_STATE" == 'present' \
      && "$PROBED_IMAGE_ID" == "$TEST_IMAGE_ID" ]] \
      || log_fatal 'The unique audit tag drifted from the build-produced image ID.'
  else
    [[ "$PULL_BUILD_BASES" == 'false' ]] \
      || log_fatal 'ERPNEXT_RESTORE_NEGATIVE_PULL is incompatible with prebuilt mode.'
    ACTIVE_TEST_IMAGE="$PREBUILT_TEST_IMAGE"
    probe_image_reference "$ACTIVE_TEST_IMAGE" \
      || log_fatal "Unable to establish the local prebuilt-image state for ${ACTIVE_TEST_IMAGE}."
    [[ "$PROBED_IMAGE_STATE" == 'present' ]] \
      || log_fatal "The local prebuilt image ${ACTIVE_TEST_IMAGE} is missing."
    TEST_IMAGE_ID="$PROBED_IMAGE_ID"
    log_warn 'Prebuilt mode is offline-capable but does not bind the result to the current source tree; do not use it as release evidence.'
  fi

  [[ "$TEST_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]] \
    || log_fatal 'Docker returned an unexpected local image identity.'
  log_info "Resolved ${ACTIVE_TEST_IMAGE} to one local image ID for this test process."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_runtime_manifest_fixture
#   Extræcts ænd vælidætes the selected imæge's exæct runtime mænifest.
#ææææææææææææææææææææææææææææææææææ
create_runtime_manifest_fixture() {
  local fixture_manifest_dir="${FIXTURE_DIR}/runtime-manifest"
  local fixture_manifest="${fixture_manifest_dir}/manifest.json"
  local temporary_manifest="${fixture_manifest_dir}/.manifest.json.new"
  local manifest_size=''

  install -d -m 0700 "$fixture_manifest_dir" \
    || log_fatal 'Unable to create the private runtime-manifest fixture.'
  manifest_size="$(docker run --rm --pull never --network none --read-only \
    --entrypoint bash "$TEST_IMAGE_ID" -c \
    'set -eu; manifest=$1; test -f "$manifest"; test ! -L "$manifest"; stat -c "%s" -- "$manifest"' \
    _ "$IMAGE_RUNTIME_MANIFEST")" \
    || log_fatal 'The selected image lacks a safe embedded runtime manifest.'
  [[ "$manifest_size" =~ ^[1-9][0-9]*$ ]] \
    || log_fatal 'The embedded runtime-manifest size is invalid.'
  (( manifest_size <= MAX_RUNTIME_MANIFEST_BYTES )) \
    || log_fatal 'The embedded runtime manifest exceeds the one-MiB bound.'
  docker run --rm --pull never --network none --read-only \
    --entrypoint cat "$TEST_IMAGE_ID" "$IMAGE_RUNTIME_MANIFEST" \
    > "$temporary_manifest" \
    || log_fatal 'The selected image lacks a readable embedded runtime manifest.'
  [[ -s "$temporary_manifest" && -f "$temporary_manifest" && ! -L "$temporary_manifest" ]] \
    || log_fatal 'The extracted image runtime manifest is empty or unsafe.'
  [[ "$(stat -c '%s' -- "$temporary_manifest")" == "$manifest_size" ]] \
    || log_fatal 'The extracted runtime-manifest size drifted from the image preflight.'
  chmod 0600 "$temporary_manifest" \
    || log_fatal 'Unable to secure the extracted runtime manifest.'
  mv -T -- "$temporary_manifest" "$fixture_manifest" \
    || log_fatal 'Unable to publish the private runtime-manifest fixture.'

  docker run --rm --pull never --network none --read-only \
    -u "${HOST_UID}:${HOST_GID}" \
    -e PYTHONDONTWRITEBYTECODE=1 \
    -v "${fixture_manifest_dir}:${SHARED_RUNTIME_MANIFEST_DIR}:ro" \
    --entrypoint "$BENCH_PYTHON" "$TEST_IMAGE_ID" \
    -m saervices_erpnext_sso_guard.runtime_manifest compare \
    "$IMAGE_RUNTIME_MANIFEST" "${SHARED_RUNTIME_MANIFEST_DIR}/manifest.json" \
    >/dev/null \
    || log_fatal 'The selected image guard module rejected its extracted runtime manifest.'
  log_ok 'Custom image guard module and exact read-only runtime-manifest fixture validated.'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: snapshot_backup_tree
#   Records NUL-delimited pæths, types, modes, ænd regulær-file digests.
#   Ærguments:
#     $1 - Output inventory file
#ææææææææææææææææææææææææææææææææææ
snapshot_backup_tree() {
  local output_file="$1"
  local backup_root="${FIXTURE_DIR}/backup"
  local path_inventory=''
  local relative_path=''
  local full_path=''
  local metadata=''
  local digest_line=''
  local digest='-'

  path_inventory="$(mktemp "${FIXTURE_DIR}/.backup-paths.XXXXXX")" || return 1
  if ! find -P "$backup_root" -xdev -mindepth 0 -printf '%P\0' > "$path_inventory"; then
    rm -f -- "$path_inventory"
    return 1
  fi
  if ! sort -z -o "$path_inventory" -- "$path_inventory"; then
    rm -f -- "$path_inventory"
    return 1
  fi
  : > "$output_file" || {
    rm -f -- "$path_inventory"
    return 1
  }
  while IFS= read -r -d '' relative_path; do
    full_path="$backup_root"
    [[ -z "$relative_path" ]] || full_path="${backup_root}/${relative_path}"
    if [[ -d "$full_path" && ! -L "$full_path" ]]; then
      digest='-'
    elif [[ -f "$full_path" && ! -L "$full_path" ]]; then
      digest_line="$(sha256sum -- "$full_path")" || {
        rm -f -- "$path_inventory"
        return 1
      }
      digest="${digest_line%% *}"
      [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || {
        rm -f -- "$path_inventory"
        return 1
      }
    else
      rm -f -- "$path_inventory"
      return 1
    fi
    metadata="$(stat -c '%F|%a' -- "$full_path")" || {
      rm -f -- "$path_inventory"
      return 1
    }
    printf '%s\0%s|%s\0' "$relative_path" "$metadata" "$digest" \
      >> "$output_file" || {
      rm -f -- "$path_inventory"
      return 1
    }
  done < "$path_inventory"
  rm -f -- "$path_inventory"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_restore_case
#   Runs one hostile restore invocætion ænd æsserts fæil-closed behævior.
#   Ærguments:
#     $1 - Cæse læbel
#     $2 - ERPNEXT_SITE_RESTORE_BUNDLE_ID vælue
#     $3 - Required fæil-closed messæge fragment
#ææææææææææææææææææææææææææææææææææ
run_restore_case() {
  local case_label="$1"
  local bundle_id="$2"
  local expected_fragment="$3"
  local output=''
  local status=0

  output="$(docker run --rm --pull never --network none --init \
    -u "${HOST_UID}:${HOST_GID}" --read-only --cap-drop ALL \
    --security-opt no-new-privileges:true --pids-limit 128 \
    --tmpfs "/tmp:rw,nosuid,nodev,size=64m,uid=${HOST_UID},gid=${HOST_GID}" \
    --tmpfs "/home/frappe/frappe-bench/sites:rw,nosuid,nodev,size=16m,uid=${HOST_UID},gid=${HOST_GID},mode=0770" \
    --tmpfs "/run:rw,nosuid,nodev,size=16m,uid=${HOST_UID},gid=${HOST_GID},mode=0770" \
    -v "${MAINTENANCE_SCRIPT}:/usr/local/bin/erpnext-site-maintenance.sh:ro" \
    -v "${RESTORE_HELPER}:/usr/local/bin/erpnext-site-restore.py:ro" \
    -v "${FIXTURE_DIR}/runtime-manifest:${SHARED_RUNTIME_MANIFEST_DIR}:ro" \
    -v "${FIXTURE_DIR}/backup:/backup:rw" \
    -e "ERPNEXT_SITE_NAME=${TEST_SITE_NAME}" \
    -e "ERPNEXT_SITE_RESTORE_BUNDLE_ID=${bundle_id}" \
    -e ERPNEXT_SITE_RESTORE_DRY_RUN=true \
    --entrypoint bash "$TEST_IMAGE_ID" -c \
    "mkdir -p /home/frappe/frappe-bench/sites/${TEST_SITE_NAME} \
      && echo {} > /home/frappe/frappe-bench/sites/${TEST_SITE_NAME}/site_config.json \
      && exec /usr/local/bin/erpnext-site-maintenance.sh restore" 2>&1)" || status=$?

  if (( status == 0 )); then
    log_error "${case_label}: hostile restore input unexpectedly succeeded"
    return 0
  fi
  if [[ "$output" == *'ModuleNotFoundError'* \
    || "$output" == *'ERPNext runtime manifest validation failed:'* \
    || "$output" == *'ERPNext runtime image differs from the site-bootstrap manifest.'* ]]; then
    log_error "${case_label}: an earlier guard-module or runtime-manifest failure masked the intended branch"
    printf '%s\n' "$output" >&2
    return 0
  fi
  if [[ "${output}" != *"${expected_fragment}"* ]]; then
    log_error "${case_label}: expected fail-closed message fragment was not emitted"
    printf '%s\n' "${output}" >&2
    return 0
  fi
  log_ok "${case_label}: rejected with exit ${status} and the documented message"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Setup
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
command -v docker >/dev/null 2>&1 || log_fatal 'Docker is required for the real-image negative matrix.'
[[ -f "${MAINTENANCE_SCRIPT}" && -f "${RESTORE_HELPER}" ]] \
  || log_fatal 'The deployable maintenance controller or restore helper is missing.'
[[ -f "$MAINTENANCE_DOCKERFILE" ]] \
  || log_fatal 'The deployable maintenance Dockerfile is missing.'

[[ -d "$FIXTURE_PARENT" && ! -L "$FIXTURE_PARENT" ]] \
  || log_fatal 'The fixture parent is missing or symbolic.'
FIXTURE_PARENT_ID="$(path_identity "$FIXTURE_PARENT")" \
  || log_fatal 'Unable to pin the fixture-parent identity.'
trap '' HUP INT TERM
FIXTURE_DIR="$(mktemp -d /tmp/erpnext-site-restore-negative.XXXXXX)" \
  || log_fatal 'Unable to allocate the private /tmp fixture.'
if ! exec {FIXTURE_FD}< "$FIXTURE_DIR"; then
  if ! rmdir -- "$FIXTURE_DIR"; then
    log_fatal 'Unable to open or remove the new private fixture directory.'
  fi
  FIXTURE_DIR=''
  log_fatal 'Unable to hold the private fixture directory open.'
fi
FIXTURE_ID="$(descriptor_identity "$FIXTURE_FD")" \
  || log_fatal 'Unable to pin the private fixture descriptor identity.'
[[ "$(descriptor_identity "$FIXTURE_FD")" == "$FIXTURE_ID" ]] \
  || log_fatal 'The private fixture descriptor identity is unexpected.'
[[ "$(path_identity "$FIXTURE_DIR")" == "$FIXTURE_ID" ]] \
  || log_fatal 'The private fixture pathname identity is unexpected.'
[[ "$(stat -c '%u:%a' -- "$FIXTURE_DIR")" == "${HOST_UID}:700" ]] \
  || log_fatal 'The private fixture owner or mode is unsafe.'
trap 'handle_exit 129' HUP
trap 'handle_exit 130' INT
trap 'handle_exit 143' TERM
prepare_test_image
create_runtime_manifest_fixture
readonly HOSTILE_MODE_BUNDLE='erpnext-20260101T000000Z'
readonly MALFORMED_MANIFEST_BUNDLE='erpnext-20260101T000001Z'
mkdir -p "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}" \
  "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}"

# Hostile-mode bundle: world-listæble directory violætes the privæte contræct.
printf 'placeholder\n' > "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}/bundle.manifest"
printf '%s  bundle.manifest\n' \
  '0000000000000000000000000000000000000000000000000000000000000000' \
  > "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}/bundle.manifest.sha256"
chmod 0755 "${FIXTURE_DIR}/backup/${HOSTILE_MODE_BUNDLE}"

# Mælformed-mænifest bundle: contræct-conformænt modes, hostile mænifest bytes.
printf 'not-an-assignment\n' \
  > "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest"
printf '%s  bundle.manifest\n' \
  '0000000000000000000000000000000000000000000000000000000000000000' \
  > "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest.sha256"
chmod 0700 "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}"
chmod 0600 "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest" \
  "${FIXTURE_DIR}/backup/${MALFORMED_MANIFEST_BUNDLE}/bundle.manifest.sha256"

snapshot_backup_tree "${FIXTURE_DIR}/inventory-before.bin" \
  || log_fatal 'Unable to create the pre-matrix byte-and-mode inventory.'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Negætive mætrix
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
log_info "Running the real-image restore negative matrix against ${ACTIVE_TEST_IMAGE}."
run_restore_case 'invalid-bundle-id' 'bogus-id' \
  'Restore requires one explicit strict ERPNEXT_SITE_RESTORE_BUNDLE_ID.'
run_restore_case 'missing-bundle' 'erpnext-20990101T000000Z' \
  'Selected restore bundle is missing or symbolic.'
run_restore_case 'hostile-bundle-mode' "${HOSTILE_MODE_BUNDLE}" \
  'directory mode does not match the private bundle contract'
run_restore_case 'malformed-manifest' "${MALFORMED_MANIFEST_BUNDLE}" \
  'bundle manifest contains a malformed assignment'

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Null-mutætion proof ænd verdict
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
snapshot_backup_tree "${FIXTURE_DIR}/inventory-after.bin" \
  || log_fatal 'Unable to create the post-matrix byte-and-mode inventory.'
if cmp -s -- "${FIXTURE_DIR}/inventory-before.bin" "${FIXTURE_DIR}/inventory-after.bin"; then
  log_ok 'Backup tree is path-, type-, mode-, and byte-identical after the complete matrix.'
else
  log_error 'Backup tree changed during the negative matrix.'
fi

if (( FAILURES > 0 )); then
  log_fatal "${FAILURES} negative-matrix check(s) failed."
fi
log_ok 'PASS: 4 real-image negative cases rejected fail-closed with a null-mutation backup tree.'
