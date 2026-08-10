#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mariadb-maintenance-safety.XXXXXX")"
readonly RESTORE_SCRIPT="${TEST_REPO_ROOT}/templates/mariadb_maintenance/dockerfiles/entrypoint.mariadb_maintenance.sh"
readonly BACKUP_SCRIPT="${TEST_REPO_ROOT}/templates/mariadb_maintenance/dockerfiles/backup.mariadb_maintenance.sh"
readonly GUARD_SCRIPT="${TEST_REPO_ROOT}/templates/mariadb/dockerfiles/entrypoint.mariadb.sh"

PASS=0
FAIL=0

cleanup_test_root() {
  if [[ "${KEEP_TEST_OUTPUT:-false}" == "true" ]]; then
    printf 'Evidence retained: %s\n' "$TEST_ROOT"
  else
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup_test_root EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  local name="$1"
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$name"
  sed -n '1,100p' "${TEST_ROOT}/${name}.out" >&2 || true
}

expect_success() {
  local name="$1"
  local status=0
  shift
  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then pass "$name"; else fail "$name"; fi
}

expect_failure() {
  local name="$1"
  local status=0
  shift
  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status != 0 )); then pass "$name"; else fail "$name"; fi
}

load_restore_script() {
  export MARIADB_ROOT_PASSWORD_FILE=/dev/null
  # shellcheck disable=SC1090
  source <(sed '$d' "$RESTORE_SCRIPT")
  trap - EXIT INT TERM
}

load_backup_script() {
  export MARIADB_ROOT_PASSWORD_FILE=/dev/null
  export MARIADB_DATABASE=testdb
  # shellcheck disable=SC1090
  source <(sed '$d' "$BACKUP_SCRIPT")
  trap - EXIT INT TERM
}

configure_restore_fixture() {
  local root="$1"
  mkdir -p -- "$root/data" "$root/restore/.tmp" "$root/backup"
  EXPECTED_MARIADB_DATA_DIR="$root/data"
  MARIADB_DIR="$EXPECTED_MARIADB_DATA_DIR"
  RESTORE_DIR="$root/restore"
  TMP_PARENT="$RESTORE_DIR/.tmp"
  CANONICAL_RESTORE_DIR="$(realpath -e -- "$RESTORE_DIR")"
  CANONICAL_TMP_PARENT="$(realpath -e -- "$TMP_PARENT")"
  TMP_PARENT_IDENTITY="$(stat -Lc '%d:%i' -- "$TMP_PARENT")"
  TMP_BASE="$(mktemp -d "$TMP_PARENT/restore_chain.XXXXXX")"
  TMP_IDENTITY="$(stat -Lc '%d:%i' -- "$TMP_BASE")"
  TMP_CREATED=true
  MARIADB_DATA_IDENTITY="$(stat -Lc '%d:%i' -- "$MARIADB_DIR")"
  RESTORE_IDENTITY="$(stat -Lc '%d:%i' -- "$RESTORE_DIR")"
  BACKUP_IDENTITY="$(stat -Lc '%d:%i' -- "$root/backup")"
  MAINTENANCE_LOCK_DIR="$root/backup"
}

configure_backup_fixture() {
  local root="$1"
  mkdir -p -- "$root/backup"
  BACKUP_DIR="$root/backup"
  TMP_PARENT="$BACKUP_DIR/.tmp"
  CANONICAL_TMP_PARENT="$TMP_PARENT"
  BACKUP_IDENTITY="$(stat -Lc '%d:%i' -- "$BACKUP_DIR")"
  is_safe_backup_dir() {
    [[ -d "$BACKUP_DIR" && ! -L "$BACKUP_DIR" && "$(stat -Lc '%d:%i' -- "$BACKUP_DIR")" == "$BACKUP_IDENTITY" ]]
  }
}

configure_client_option_fixture() {
  local root="$1"
  local secret="$2"
  mkdir -p -- "$root/client-tmp"
  printf '%s' "$secret" >"$root/root-secret"
  chmod 0640 -- "$root/root-secret"
  MARIADB_ROOT_PASSWORD_FILE="$root/root-secret"
  MARIADB_CLIENT_OPTION_ROOT="$root/client-tmp"
}

write_fake_mariadb_client() {
  local destination="$1"
  cat >"$destination" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_MARIADB_ARGV_FILE:?}"
printf '%s\0' "$@" >"$FAKE_MARIADB_ARGV_FILE"
[[ "${1:-}" == --defaults-extra-file=* ]]
option_file="${1#--defaults-extra-file=}"
[[ -f "$option_file" && ! -L "$option_file" ]]
[[ "$(stat -c '%a' -- "$option_file")" == "600" ]]
exit "${FAKE_MARIADB_EXIT_STATUS:-0}"
EOF
  chmod 0755 -- "$destination"
}

case_client_option_success_cleanup() {
  local kind="$1"
  local root="$TEST_ROOT/client-option-${kind}"
  local secret='p a#;=ss\word"quote'
  local option_dir=""
  local option_file=""
  local expected=""
  local argument=""
  local arguments=()
  mkdir -p -- "$root/bin"
  case "$kind" in
    backup) load_backup_script ;;
    restore) load_restore_script ;;
    *) return 2 ;;
  esac
  configure_client_option_fixture "$root" "$secret"
  write_fake_mariadb_client "$root/bin/fake-mariadb"
  create_mariadb_client_option_file
  option_dir="$MARIADB_CLIENT_OPTION_DIR"
  option_file="$MARIADB_CLIENT_OPTION_FILE"
  argument="$MARIADB_CLIENT_OPTION_ARGUMENT"
  [[ "$(stat -c '%a' -- "$option_dir")" == "700" ]]
  [[ "$(stat -c '%a' -- "$option_file")" == "600" ]]
  [[ "$argument" == "--defaults-extra-file=$option_file" ]]
  expected="$root/expected.cnf"
  printf '[client]\npassword="p a#;=ss\\\\word\\"quote"\n' >"$expected"
  cmp -s -- "$expected" "$option_file"
  if [[ "$kind" == "backup" ]]; then
    FAKE_MARIADB_ARGV_FILE="$root/argv" run_backup_child \
      "$root/bin/fake-mariadb" "$argument" --host=database --user=root
  else
    FAKE_MARIADB_ARGV_FILE="$root/argv" run_restore_child \
      "$root/bin/fake-mariadb" "$argument" --host=database --user=root
  fi
  mapfile -d '' -t arguments <"$root/argv"
  [[ "${arguments[0]}" == "$argument" ]]
  [[ "${#arguments[@]}" == "3" ]]
  ! grep -F -- "$secret" "$root/argv" >/dev/null
  ! grep -F -- '--password' "$root/argv" >/dev/null
  remove_mariadb_client_option_file
  [[ "$MARIADB_CLIENT_OPTION_ACTIVE" == "false" ]]
  [[ ! -e "$option_file" && ! -L "$option_file" && ! -e "$option_dir" && ! -L "$option_dir" ]]
}

case_client_option_child_failure_cleanup() {
  local root="$TEST_ROOT/client-option-child-failure"
  local secret='failure-secret\with"quote'
  local status=0
  local option_dir=""
  mkdir -p -- "$root/bin"
  write_fake_mariadb_client "$root/bin/fake-mariadb"
  set +e
  (
    load_backup_script
    configure_client_option_fixture "$root" "$secret"
    trap cleanup EXIT
    create_mariadb_client_option_file
    printf '%s' "$MARIADB_CLIENT_OPTION_DIR" >"$root/option-dir"
    FAKE_MARIADB_ARGV_FILE="$root/argv" FAKE_MARIADB_EXIT_STATUS=42 run_backup_child \
      "$root/bin/fake-mariadb" "$MARIADB_CLIENT_OPTION_ARGUMENT" --host=database --user=root
  )
  status=$?
  set -e
  (( status == 42 ))
  option_dir="$(<"$root/option-dir")"
  [[ ! -e "$option_dir" && ! -L "$option_dir" ]]
  ! grep -F -- "$secret" "$root/argv" >/dev/null
}

case_client_option_digest_drift_preserved() {
  local root="$TEST_ROOT/client-option-digest-drift"
  local option_dir=""
  local option_file=""
  load_backup_script
  configure_client_option_fixture "$root" 'digest-drift-secret'
  create_mariadb_client_option_file
  option_dir="$MARIADB_CLIENT_OPTION_DIR"
  option_file="$MARIADB_CLIENT_OPTION_FILE"
  printf 'drift' >>"$option_file"
  if remove_mariadb_client_option_file; then
    return 1
  fi
  [[ -d "$option_dir" && -f "$option_file" ]]
}

case_client_option_rejects_line_break() {
  local root="$TEST_ROOT/client-option-line-break"
  load_backup_script
  mkdir -p -- "$root/client-tmp"
  printf 'line-one\nline-two' >"$root/root-secret"
  MARIADB_ROOT_PASSWORD_FILE="$root/root-secret"
  MARIADB_CLIENT_OPTION_ROOT="$root/client-tmp"
  create_mariadb_client_option_file
}

case_client_option_rejects_control_byte() {
  local root="$TEST_ROOT/client-option-control-byte"
  load_restore_script
  mkdir -p -- "$root/client-tmp"
  printf 'tab\tsecret' >"$root/root-secret"
  MARIADB_ROOT_PASSWORD_FILE="$root/root-secret"
  MARIADB_CLIENT_OPTION_ROOT="$root/client-tmp"
  create_mariadb_client_option_file
}

case_client_option_mode_drift_preserved() {
  local root="$TEST_ROOT/client-option-mode-drift"
  local option_dir=""
  local option_file=""
  load_restore_script
  configure_client_option_fixture "$root" 'mode-drift-secret'
  create_mariadb_client_option_file
  option_dir="$MARIADB_CLIENT_OPTION_DIR"
  option_file="$MARIADB_CLIENT_OPTION_FILE"
  chmod 0644 -- "$option_file"
  if remove_mariadb_client_option_file; then
    return 1
  fi
  [[ -d "$option_dir" && -f "$option_file" ]]
}

case_client_option_symlink_swap_preserved() {
  local root="$TEST_ROOT/client-option-symlink-swap"
  local option_dir=""
  local option_file=""
  load_backup_script
  configure_client_option_fixture "$root" 'symlink-swap-secret'
  create_mariadb_client_option_file
  option_dir="$MARIADB_CLIENT_OPTION_DIR"
  option_file="$MARIADB_CLIENT_OPTION_FILE"
  mv -- "$option_file" "${option_file}.original"
  ln -s -- "${option_file##*/}.original" "$option_file"
  if remove_mariadb_client_option_file; then
    return 1
  fi
  [[ -d "$option_dir" && -L "$option_file" && -f "${option_file}.original" ]]
}

assert_mariadb_client_argv_contract() {
  local backup_source="$1"
  local restore_source="$2"
  if rg -n -- '--password(?:=|[[:space:]])|MYSQL_PWD' "$backup_source" "$restore_source" >/dev/null; then
    return 1
  fi
  if rg -n 'backup-dump.*MARIADB_ROOT_PASSWORD_FILE|restore-dump.*MARIADB_ROOT_PASSWORD_FILE|run_(backup|restore)_child.*MARIADB_ROOT_PASSWORD_FILE' "$backup_source" "$restore_source" >/dev/null; then
    return 1
  fi
  if rg -n 'run_backup_child mariadb-backup[[:space:]]+--backup' "$backup_source" >/dev/null; then
    return 1
  fi
  rg -U 'run_backup_child mariadb-backup \\\n    "\$MARIADB_CLIENT_OPTION_ARGUMENT" \\\n    --backup' "$backup_source" >/dev/null || return 1
  rg -U 'mariadb-dump \\\n      "\$1" \\' "$backup_source" >/dev/null || return 1
  rg -U 'mariadb \\\n    "\$MARIADB_CLIENT_OPTION_ARGUMENT" \\\n    --batch' "$restore_source" >/dev/null || return 1
  rg -U 'mariadb-admin \\\n      "\$MARIADB_CLIENT_OPTION_ARGUMENT" \\\n      --connect-timeout' "$restore_source" >/dev/null || return 1
  rg -U 'zstd -d -q --stdout "\$2" \| mariadb \\\n        "\$1" \\' "$restore_source" >/dev/null || return 1
  rg -F 'mariadb-admin --no-defaults ping \' "$restore_source" >/dev/null || return 1
  rg -F -- "--user='__mariadb_maintenance_liveness_probe__' \\" "$restore_source" >/dev/null || return 1
}

case_client_argv_negative_mutations() {
  local root="$TEST_ROOT/client-argv-mutations"
  local backup_copy="$root/backup.sh"
  local restore_copy="$root/restore.sh"
  mkdir -p -- "$root"
  cp -- "$BACKUP_SCRIPT" "$backup_copy"
  cp -- "$RESTORE_SCRIPT" "$restore_copy"
  assert_mariadb_client_argv_contract "$backup_copy" "$restore_copy"

  printf '\nmariadb --password=leak\n' >>"$backup_copy"
  ! assert_mariadb_client_argv_contract "$backup_copy" "$restore_copy"
  cp -- "$BACKUP_SCRIPT" "$backup_copy"

  printf '\nMYSQL_PWD=leak mariadb\n' >>"$restore_copy"
  ! assert_mariadb_client_argv_contract "$backup_copy" "$restore_copy"
  cp -- "$RESTORE_SCRIPT" "$restore_copy"

  printf '\nrun_backup_child mariadb-backup "$(<"$MARIADB_ROOT_PASSWORD_FILE")"\n' >>"$backup_copy"
  ! assert_mariadb_client_argv_contract "$backup_copy" "$restore_copy"
  cp -- "$BACKUP_SCRIPT" "$backup_copy"

  printf '\nrun_backup_child mariadb-backup --backup "$MARIADB_CLIENT_OPTION_ARGUMENT"\n' >>"$backup_copy"
  ! assert_mariadb_client_argv_contract "$backup_copy" "$restore_copy"
}

publish_physical_bundle() {
  local archive="$1"
  local stem="${archive##*/}"
  local source="${archive}.source"
  local checksum=""
  stem="${stem%.zst}"
  mkdir -p -- "${archive%/*}" "$source"
  printf 'fixture\n' >"$source/data"
  tar -cf - -C "$source" . | zstd -q --stdout >"$archive"
  rm -rf -- "$source"
  checksum="$(sha256sum -- "$archive")"
  checksum="${checksum%% *}"
  printf '%s  %s\n' "$checksum" "${archive##*/}" >"${archive}.sha256"
  printf '%s  %s\n' "$checksum" "${archive##*/}" >"${archive%/*}/bundle_${stem}.sha256"
}

case_data_target_broad() {
  load_restore_script
  EXPECTED_MARIADB_DATA_DIR="$TEST_ROOT/expected"
  MARIADB_DIR=/
  is_safe_data_dir
}

case_data_target_symlink() {
  local root="$TEST_ROOT/data-symlink"
  load_restore_script
  mkdir -p -- "$root/real" "$root/restore"
  ln -s -- "$root/real" "$root/data"
  EXPECTED_MARIADB_DATA_DIR="$root/data"
  MARIADB_DIR="$EXPECTED_MARIADB_DATA_DIR"
  RESTORE_DIR="$root/restore"
  is_safe_data_dir
}

case_data_target_identity_swap() {
  local root="$TEST_ROOT/data-swap"
  load_restore_script
  configure_restore_fixture "$root"
  mv -- "$MARIADB_DIR" "$root/original"
  mkdir -- "$MARIADB_DIR"
  is_safe_data_dir
}

case_restore_candidate_symlink() {
  local root="$TEST_ROOT/restore-symlink"
  load_restore_script
  configure_restore_fixture "$root"
  printf target >"$root/target"
  ln -s -- "$root/target" "$RESTORE_DIR/full_20260804_01.zst"
  validate_restore_candidate_inventory physical
}

case_dump_candidate_fifo() {
  local root="$TEST_ROOT/dump-fifo"
  load_restore_script
  configure_restore_fixture "$root"
  mkfifo -- "$RESTORE_DIR/dump_20260804_01.sql.zst"
  validate_restore_candidate_inventory dump
}

case_restore_find_failure() {
  local root="$TEST_ROOT/restore-find-failure"
  load_restore_script
  configure_restore_fixture "$root"
  find() { return 71; }
  validate_restore_candidate_inventory physical
}

case_restore_sort_failure() {
  local root="$TEST_ROOT/restore-sort-failure"
  load_restore_script
  configure_restore_fixture "$root"
  : >"$RESTORE_DIR/full_20260804_01.zst"
  sort() { return 72; }
  find_restore_chain
}

case_sequence_highest_all_outputs() {
  local root="$TEST_ROOT/sequence"
  local sequence=""
  load_backup_script
  configure_backup_fixture "$root"
  mkdir -p -- "$BACKUP_DIR/20260804"
  : >"$BACKUP_DIR/20260804/full_20260804_01.zst"
  : >"$BACKUP_DIR/20260804/full_20260804_07.zst.sha256"
  : >"$BACKUP_DIR/20260804/bundle_full_20260804_12.sha256"
  sequence="$(next_sequence "$BACKUP_DIR/20260804" 'full_20260804_' '.zst' 'bundle_full_20260804_')"
  [[ "$sequence" == "13" ]]
  ! sequence_is_available "$BACKUP_DIR/20260804/full_20260804_07.zst" "$BACKUP_DIR/20260804/bundle_full_20260804_07.sha256"
  sequence_is_available "$BACKUP_DIR/20260804/full_20260804_13.zst" "$BACKUP_DIR/20260804/bundle_full_20260804_13.sha256"
}

case_sequence_find_failure() {
  local root="$TEST_ROOT/sequence-find-failure"
  load_backup_script
  configure_backup_fixture "$root"
  find() { return 73; }
  next_sequence "$BACKUP_DIR" full_ .zst bundle_full_
}

case_chain_sort_failure() {
  local root="$TEST_ROOT/chain-sort-failure"
  load_backup_script
  configure_backup_fixture "$root"
  publish_physical_bundle "$BACKUP_DIR/20260804/full_20260804_01.zst"
  sort() { return 74; }
  validate_physical_chain "$BACKUP_DIR/20260804/full_20260804_01.zst"
}

case_publication_rename_then_error() {
  local root="$TEST_ROOT/publication-rename-error"
  local destination=""
  load_backup_script
  configure_backup_fixture "$root"
  ensure_backup_day_dir() {
    mkdir -p -- "$1"
  }
  destination="$BACKUP_DIR/20260804/full_20260804_01.zst"
  mkdir -p -- "${destination%/*}"
  open_secure_temp_file "$destination"
  printf payload >&7
  mv() {
    command mv "$@"
    return 75
  }
  publish_secure_temp_file "$destination"
  [[ -f "$destination" && "$(<"$destination")" == payload && ${#PUBLISHED_BUNDLE_FILES[@]} == 1 ]]
}

case_publication_no_clobber() {
  local root="$TEST_ROOT/publication-no-clobber"
  local destination=""
  load_backup_script
  configure_backup_fixture "$root"
  ensure_backup_day_dir() {
    mkdir -p -- "$1"
  }
  destination="$BACKUP_DIR/20260804/full_20260804_01.zst"
  mkdir -p -- "${destination%/*}"
  printf existing >"$destination"
  open_secure_temp_file "$destination"
}

case_consume_rename_then_error_rollback() {
  local root="$TEST_ROOT/consume-rename-error"
  local source=""
  local destination=""
  load_restore_script
  configure_restore_fixture "$root"
  source="$RESTORE_DIR/archive.zst"
  destination="$TMP_BASE/consumed-bundle/archive.zst"
  printf payload >"$source"
  MARIADB_RESTORE_CONSUME_ARCHIVES=true
  MARIADB_RESTORE_DRY_RUN=false
  CONSUMED_ARCHIVES=("$source")
  prepare_bundle_consumption() {
    BUNDLE_CONSUME_FILES=("$source")
  }
  set +e
  (
    trap cleanup EXIT
    mv() {
      command mv "$@"
      return 76
    }
    consume_archives
  )
  local status=$?
  set -e
  (( status != 0 ))
  [[ -f "$source" && "$(<"$source")" == payload && ! -e "$destination" ]]
}

case_term_backup_reaps_child() {
  local root="$TEST_ROOT/term-backup"
  local worker_pid=""
  local child_pid=""
  local status=0
  mkdir -p -- "$root/bin"
  sed "s#PID_FILE#$root/child.pid#g" >"$root/bin/backup-child" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >PID_FILE
trap 'exit 143' TERM INT
sleep 300 &
wait
EOF
  chmod 0755 "$root/bin/backup-child"
  (
    load_backup_script
    configure_backup_fixture "$root"
    configure_client_option_fixture "$root" 'term-signal-secret'
    trap cleanup EXIT
    trap 'handle_signal 130' INT
    trap 'handle_signal 143' TERM
    create_mariadb_client_option_file
    printf '%s' "$MARIADB_CLIENT_OPTION_DIR" >"$root/option-dir"
    run_backup_child "$root/bin/backup-child" "$MARIADB_CLIENT_OPTION_ARGUMENT"
  ) &
  worker_pid=$!
  for _ in {1..100}; do [[ -s "$root/child.pid" ]] && break; sleep 0.05; done
  [[ -s "$root/child.pid" ]]
  child_pid="$(<"$root/child.pid")"
  kill -TERM "$worker_pid"
  set +e
  wait "$worker_pid"
  status=$?
  set -e
  (( status == 143 ))
  ! kill -0 "$child_pid" 2>/dev/null
  [[ ! -e "$(<"$root/option-dir")" && ! -L "$(<"$root/option-dir")" ]]
}

case_retention_no_physical_full() {
  local root="$TEST_ROOT/retention-no-full"
  load_backup_script
  configure_backup_fixture "$root"
  mkdir -p -- "$BACKUP_DIR/20200101"
  printf preserve >"$BACKUP_DIR/20200101/dump_20200101_01.sql.zst"
  touch -d '2020-01-02 UTC' "$BACKUP_DIR/20200101"
  MARIADB_BACKUP_RETENTION_DAYS=1
  remove_old_backups
}

case_retention_latest_valid_behind_invalid() {
  local root="$TEST_ROOT/retention-valid-behind-invalid"
  local latest=""
  load_backup_script
  configure_backup_fixture "$root"
  publish_physical_bundle "$BACKUP_DIR/20200101/full_20200101_01.zst"
  mkdir -p -- "$BACKUP_DIR/20200102"
  printf corrupt >"$BACKUP_DIR/20200102/full_20200102_01.zst"
  printf invalid >"$BACKUP_DIR/20200102/full_20200102_01.zst.sha256"
  printf invalid >"$BACKUP_DIR/20200102/bundle_full_20200102_01.sha256"
  latest="$(get_latest_valid_full)"
  [[ "$latest" == "$BACKUP_DIR/20200101/full_20200101_01.zst" ]]
  touch -d '2020-01-03 UTC' "$BACKUP_DIR/20200101" "$BACKUP_DIR/20200102"
  MARIADB_BACKUP_RETENTION_DAYS=1
  remove_old_backups
  [[ -d "$BACKUP_DIR/20200101" && ! -e "$BACKUP_DIR/20200102" ]]
}

case_retention_xdev_delete() {
  local root="$TEST_ROOT/retention-xdev"
  local dir=""
  local identity=""
  load_backup_script
  configure_backup_fixture "$root"
  dir="$BACKUP_DIR/20200101"
  mkdir -- "$dir"
  printf old >"$dir/file"
  identity="$(stat -Lc '%d:%i' -- "$dir")"
  find() {
    printf '%s\n' "$*" >"$root/find-args"
    return 77
  }
  set +e
  ( remove_expired_backup_dir "$dir" "$identity" )
  local status=$?
  set -e
  (( status != 0 ))
  grep -F -- '-xdev -depth -mindepth 1 -delete' "$root/find-args" >/dev/null
  [[ -f "$dir/file" ]]
}

case_retention_find_failure() {
  local root="$TEST_ROOT/retention-find-failure"
  load_backup_script
  configure_backup_fixture "$root"
  publish_physical_bundle "$BACKUP_DIR/20260804/full_20260804_01.zst"
  find() { return 78; }
  remove_old_backups
}

case_switch_rename_then_error() {
  local root="$TEST_ROOT/switch-rename-error"
  load_restore_script
  configure_restore_fixture "$root"
  printf old >"$MARIADB_DIR/old"
  begin_restore_stage
  printf new >"$RESTORE_STAGE_DIR/new"
  plan_restore_switch
  local source="${RESTORE_OLD_SOURCES[0]}"
  local destination="${RESTORE_OLD_DESTINATIONS[0]}"
  local identity="${RESTORE_OLD_IDENTITIES[0]}"
  mv() {
    command mv "$@"
    return 79
  }
  move_restore_node "$source" "$destination" "$identity"
  restore_node_matches "$destination" "$identity"
}

case_switch_rollback_partial() {
  local root="$TEST_ROOT/switch-rollback"
  load_restore_script
  configure_restore_fixture "$root"
  printf old-a >"$MARIADB_DIR/a"
  printf old-b >"$MARIADB_DIR/b"
  begin_restore_stage
  printf new-a >"$RESTORE_STAGE_DIR/a"
  printf new-c >"$RESTORE_STAGE_DIR/c"
  plan_restore_switch
  move_restore_node "${RESTORE_OLD_SOURCES[0]}" "${RESTORE_OLD_DESTINATIONS[0]}" "${RESTORE_OLD_IDENTITIES[0]}"
  rollback_restore_switch
  [[ "$(<"$MARIADB_DIR/a")" == old-a && "$(<"$MARIADB_DIR/b")" == old-b && ! -e "$MARIADB_DIR/c" ]]
  ! find "$MARIADB_DIR" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*' | grep -q .
}

prepare_crash_state() {
  local root="$1"
  local phase="$2"
  load_restore_script
  configure_restore_fixture "$root"
  printf old-a >"$MARIADB_DIR/a"
  printf old-b >"$MARIADB_DIR/b"
  begin_restore_stage
  printf new-a >"$RESTORE_STAGE_DIR/a"
  printf new-c >"$RESTORE_STAGE_DIR/c"
  if [[ "$phase" == "stage" ]]; then
    write_restore_journal staging
    kill -KILL "$BASHPID"
  fi
  plan_restore_switch
  move_restore_node "${RESTORE_OLD_SOURCES[0]}" "${RESTORE_OLD_DESTINATIONS[0]}" "${RESTORE_OLD_IDENTITIES[0]}"
  if [[ "$phase" == "old-move" ]]; then
    kill -KILL "$BASHPID"
  fi
  for index in "${!RESTORE_OLD_SOURCES[@]}"; do
    restore_node_matches "${RESTORE_OLD_DESTINATIONS[$index]}" "${RESTORE_OLD_IDENTITIES[$index]}" || move_restore_node "${RESTORE_OLD_SOURCES[$index]}" "${RESTORE_OLD_DESTINATIONS[$index]}" "${RESTORE_OLD_IDENTITIES[$index]}"
  done
  for index in "${!RESTORE_NEW_SOURCES[@]}"; do
    move_restore_node "${RESTORE_NEW_SOURCES[$index]}" "${RESTORE_NEW_DESTINATIONS[$index]}" "${RESTORE_NEW_IDENTITIES[$index]}"
    if [[ "$phase" == "new-move" ]]; then
      kill -KILL "$BASHPID"
    fi
  done
  write_restore_journal committed
  if [[ "$phase" == "finalize-old" ]]; then
    remove_restore_transaction_dir "$RESTORE_OLD_DIR" "$RESTORE_OLD_IDENTITY"
    kill -KILL "$BASHPID"
  fi
  if [[ "$phase" == "finalize-stage" ]]; then
    remove_restore_transaction_dir "$RESTORE_OLD_DIR" "$RESTORE_OLD_IDENTITY"
    remove_restore_transaction_dir "$RESTORE_STAGE_DIR" "$RESTORE_STAGE_IDENTITY"
    kill -KILL "$BASHPID"
  fi
  kill -KILL "$BASHPID"
}

recover_crash_state() {
  local root="$1"
  load_restore_script
  configure_restore_fixture_reuse "$root"
  recover_interrupted_restore
  (( ${#RESTORE_OLD_SOURCES[@]} == 0 && ${#RESTORE_NEW_SOURCES[@]} == 0 ))
}

case_journal_rejects_duplicate_entry() {
  local root="$TEST_ROOT/journal-duplicate"
  local journal=""
  local duplicate=""
  local line=""
  load_restore_script
  configure_restore_fixture "$root"
  printf old >"$MARIADB_DIR/old"
  begin_restore_stage
  printf new >"$RESTORE_STAGE_DIR/new"
  plan_restore_switch
  journal="$MARIADB_DIR/.mariadb-restore-journal"
  duplicate="$(rg '^OLD_ENTRY' "$journal")"
  [[ -n "$duplicate" ]]
  while IFS= read -r line; do
    if [[ "$line" == "END" ]]; then
      printf '%s\n' "$duplicate"
    fi
    printf '%s\n' "$line"
  done <"$journal" >"${journal}.invalid"
  mv -T -- "${journal}.invalid" "$journal"
  load_restore_journal
}

prepare_initial_journal_publish_crash() {
  local root="$1"
  load_restore_script
  configure_restore_fixture "$root"
  mv() {
    local destination="${!#}"
    if [[ "$destination" == "$MARIADB_DIR/.mariadb-restore-journal" ]]; then
      kill -KILL "$BASHPID"
    fi
    command mv "$@"
  }
  begin_restore_stage
}

case_sigkill_initial_journal_publish_recovery() {
  local root="$TEST_ROOT/sigkill-initial-journal"
  local status=0
  set +e
  ( prepare_initial_journal_publish_crash "$root" )
  status=$?
  set -e
  (( status == 137 ))
  [[ ! -e "$root/data/.mariadb-restore-journal" ]]
  find "$root/data" -xdev -mindepth 1 -maxdepth 1 -type f -name '.mariadb-restore-journal.tmp.*' -print -quit | grep -q .

  load_restore_script
  configure_restore_fixture_reuse "$root"
  recover_interrupted_restore
  ! find "$root/data" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*' -print -quit | grep -q .

  prepare_guard_copy "$root"
  "$root/guard" mariadbd --recovery-probe
  [[ "$(<"$root/vendor-called")" == 'mariadbd --recovery-probe' ]]
}

case_orphan_temp_with_artifact_blocks() {
  local kind="$1"
  local root="$TEST_ROOT/orphan-temp-${kind}"
  local temp=""
  local status=0
  local guard_status=0
  load_restore_script
  configure_restore_fixture "$root"
  temp="$MARIADB_DIR/.mariadb-restore-journal.tmp.fixture"
  : >"$temp"
  case "$kind" in
    stage) mkdir -- "$MARIADB_DIR/.mariadb-restore-stage.fixture" ;;
    old) mkdir -- "$MARIADB_DIR/.mariadb-restore-old.fixture" ;;
    unknown) : >"$MARIADB_DIR/.mariadb-restore-unknown" ;;
    *) return 2 ;;
  esac
  set +e
  ( recover_interrupted_restore ) >/dev/null 2>&1
  status=$?
  set -e
  (( status != 0 ))
  [[ -f "$temp" ]]

  prepare_guard_copy "$root"
  set +e
  "$root/guard" mariadbd >/dev/null 2>&1
  guard_status=$?
  set -e
  (( guard_status == 78 ))
  [[ ! -e "$root/vendor-called" ]]
}

configure_restore_fixture_reuse() {
  local root="$1"
  EXPECTED_MARIADB_DATA_DIR="$root/data"
  MARIADB_DIR="$EXPECTED_MARIADB_DATA_DIR"
  RESTORE_DIR="$root/restore"
  TMP_PARENT="$RESTORE_DIR/.tmp"
  CANONICAL_RESTORE_DIR="$(realpath -e -- "$RESTORE_DIR")"
  CANONICAL_TMP_PARENT="$(realpath -e -- "$TMP_PARENT")"
  TMP_PARENT_IDENTITY="$(stat -Lc '%d:%i' -- "$TMP_PARENT")"
  TMP_BASE="$(find "$TMP_PARENT" -xdev -mindepth 1 -maxdepth 1 -type d -print -quit)"
  TMP_IDENTITY="$(stat -Lc '%d:%i' -- "$TMP_BASE")"
  TMP_CREATED=true
  MARIADB_DATA_IDENTITY="$(stat -Lc '%d:%i' -- "$MARIADB_DIR")"
}

case_sigkill_recovery() {
  local phase="$1"
  local root="$TEST_ROOT/sigkill-${phase}"
  local status=0
  set +e
  ( prepare_crash_state "$root" "$phase" )
  status=$?
  set -e
  (( status == 137 ))
  [[ -f "$root/data/.mariadb-restore-journal" ]]
  recover_crash_state "$root"
  if [[ "$phase" == "committed" || "$phase" == "finalize-old" || "$phase" == "finalize-stage" ]]; then
    [[ "$(<"$root/data/a")" == new-a && "$(<"$root/data/c")" == new-c && ! -e "$root/data/b" ]]
  else
    [[ "$(<"$root/data/a")" == old-a && "$(<"$root/data/b")" == old-b && ! -e "$root/data/c" ]]
  fi
  ! find "$root/data" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*' | grep -q .
}

case_term_stage_reaps_child() {
  local root="$TEST_ROOT/term-stage"
  local worker_pid=""
  local child_pid=""
  local status=0
  mkdir -p -- "$root/bin"
  sed "s#PID_FILE#$root/child.pid#g" >"$root/bin/mariadb-backup" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >PID_FILE
trap 'exit 143' TERM INT
sleep 300 &
wait
EOF
  chmod 0755 "$root/bin/mariadb-backup"
  (
    PATH="$root/bin:$PATH"
    load_restore_script
    configure_restore_fixture "$root"
    trap cleanup EXIT
    trap 'handle_signal 130' INT
    trap 'handle_signal 143' TERM
    printf old >"$MARIADB_DIR/old"
    mkdir -p -- "$TMP_BASE/full"
    stage_prepared_restore
  ) &
  worker_pid=$!
  for _ in {1..100}; do [[ -s "$root/child.pid" ]] && break; sleep 0.05; done
  [[ -s "$root/child.pid" ]]
  child_pid="$(<"$root/child.pid")"
  kill -TERM "$worker_pid"
  set +e
  wait "$worker_pid"
  status=$?
  set -e
  (( status == 143 ))
  ! kill -0 "$child_pid" 2>/dev/null
  [[ "$(<"$root/data/old")" == old ]]
  ! find "$root/data" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*' | grep -q .
}

case_term_restore_phase_reaps_child() {
  local phase="$1"
  local root="$TEST_ROOT/term-${phase}"
  local worker_pid=""
  local child_pid=""
  local status=0
  local helper_name="mariadb-backup"
  [[ "$phase" != "extract" ]] || helper_name="zstd"
  mkdir -p -- "$root/bin"
  sed "s#PID_FILE#$root/child.pid#g" >"$root/bin/$helper_name" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >PID_FILE
trap 'exit 143' TERM INT
sleep 300 &
wait
EOF
  chmod 0755 "$root/bin/$helper_name"
  (
    PATH="$root/bin:$PATH"
    load_restore_script
    configure_restore_fixture "$root"
    trap cleanup EXIT
    trap 'handle_signal 130' INT
    trap 'handle_signal 143' TERM
    printf old >"$MARIADB_DIR/old"
    case "$phase" in
      extract)
        RESTORE_CHAIN=("$RESTORE_DIR/full_20260804_01.zst")
        : >"${RESTORE_CHAIN[0]}"
        extract_restore_chain
        ;;
      prepare)
        RESTORE_CHAIN=("$RESTORE_DIR/full_20260804_01.zst")
        mkdir -p -- "$TMP_BASE/full"
        prepare_restore_chain
        ;;
      switch)
        begin_restore_stage
        printf new >"$RESTORE_STAGE_DIR/new"
        plan_restore_switch
        move_restore_node "${RESTORE_OLD_SOURCES[0]}" "${RESTORE_OLD_DESTINATIONS[0]}" "${RESTORE_OLD_IDENTITIES[0]}"
        run_restore_child sleep 300
        ;;
      *) return 2 ;;
    esac
  ) &
  worker_pid=$!
  if [[ "$phase" == "switch" ]]; then
    for _ in {1..100}; do [[ -f "$root/data/.mariadb-restore-journal" && ! -e "$root/data/old" ]] && break; sleep 0.05; done
    child_pid="$(pgrep -P "$worker_pid" -n || true)"
  else
    for _ in {1..100}; do [[ -s "$root/child.pid" ]] && break; sleep 0.05; done
    [[ -s "$root/child.pid" ]]
    child_pid="$(<"$root/child.pid")"
  fi
  kill -TERM "$worker_pid"
  set +e
  wait "$worker_pid"
  status=$?
  set -e
  (( status == 143 ))
  [[ -z "$child_pid" ]] || ! kill -0 "$child_pid" 2>/dev/null
  [[ "$(<"$root/data/old")" == old ]]
  ! find "$root/data" -xdev -mindepth 1 -maxdepth 1 -name '.mariadb-restore-*' | grep -q .
}

prepare_guard_copy() {
  local root="$1"
  sed \
    -e "s#MARIADB_DATA_ROOT=/var/lib/mysql#MARIADB_DATA_ROOT=$root/data#" \
    -e "s#MARIADB_VENDOR_ENTRYPOINT=/usr/local/bin/docker-entrypoint.sh#MARIADB_VENDOR_ENTRYPOINT=$root/vendor#" \
    "$GUARD_SCRIPT" >"$root/guard"
  chmod 0755 "$root/guard"
  cat >"$root/vendor" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >"$root/vendor-called"
EOF
  chmod 0755 "$root/vendor"
  mkdir -p -- "$root/data"
}

case_guard_handoff() {
  local root="$TEST_ROOT/guard-handoff"
  mkdir -p -- "$root"
  prepare_guard_copy "$root"
  "$root/guard" mariadbd --test-flag
  [[ "$(<"$root/vendor-called")" == 'mariadbd --test-flag' ]]
}

case_guard_blocks_marker() {
  local root="$TEST_ROOT/guard-block"
  local status=0
  mkdir -p -- "$root"
  prepare_guard_copy "$root"
  : >"$root/data/.mariadb-restore-journal"
  set +e
  "$root/guard" mariadbd
  status=$?
  set -e
  (( status == 78 ))
  [[ ! -e "$root/vendor-called" ]]
}

case_guard_rejects_unsafe_root() {
  local root="$TEST_ROOT/guard-unsafe-root"
  local status=0
  mkdir -p -- "$root"
  prepare_guard_copy "$root"
  rmdir -- "$root/data"
  ln -s -- "$root" "$root/data"
  set +e
  "$root/guard" mariadbd
  status=$?
  set -e
  (( status == 78 ))
  [[ ! -e "$root/vendor-called" ]]
}

case_guard_find_error_blocks() {
  local root="$TEST_ROOT/guard-find-error"
  local status=0
  mkdir -p -- "$root/bin"
  prepare_guard_copy "$root"
  cat >"$root/bin/find" <<'EOF'
#!/bin/sh
exit 91
EOF
  chmod 0755 "$root/bin/find"
  set +e
  PATH="$root/bin:$PATH" "$root/guard" mariadbd
  status=$?
  set -e
  (( status == 78 ))
  [[ ! -e "$root/vendor-called" ]]
}

case_guard_rejects_invalid_binlog_retention() {
  local root="$TEST_ROOT/guard-binlog-retention"
  local value=""
  local status=0
  mkdir -p -- "$root"
  prepare_guard_copy "$root"
  for value in 0 3599 31536001 invalid; do
    rm -f -- "$root/vendor-called"
    set +e
    MARIADB_BINLOG_EXPIRE_LOGS_SECONDS="$value" "$root/guard" mariadbd
    status=$?
    set -e
    (( status == 78 ))
    [[ ! -e "$root/vendor-called" ]]
  done
  MARIADB_BINLOG_EXPIRE_LOGS_SECONDS=604800 "$root/guard" mariadbd
  [[ "$(<"$root/vendor-called")" == mariadbd ]]
}

case_guard_rejects_invalid_purge_replica_threshold() {
  local root="$TEST_ROOT/guard-purge-replica-threshold"
  local value=""
  local status=0
  mkdir -p -- "$root"
  prepare_guard_copy "$root"
  for value in invalid -1 4294967296; do
    rm -f -- "$root/vendor-called"
    set +e
    MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE="$value" "$root/guard" mariadbd
    status=$?
    set -e
    (( status == 78 ))
    [[ ! -e "$root/vendor-called" ]]
  done
  MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE=0 "$root/guard" mariadbd
  [[ "$(<"$root/vendor-called")" == mariadbd ]]
}

case_static_destructive_bounds() {
  ! rg -n 'find "\$MARIADB_DIR".*rm -rf|rm -rf -- "\$MARIADB_DIR"' "$RESTORE_SCRIPT"
  rg -F 'find "$path" -xdev -depth -mindepth 1 -delete' "$RESTORE_SCRIPT" >/dev/null
  rg -F 'find "$dir" -xdev -depth -mindepth 1 -delete' "$BACKUP_SCRIPT" >/dev/null
  rg -F 'MOVED_BUNDLE_SOURCES+=("$source")' "$RESTORE_SCRIPT" >/dev/null
}

expect_failure data-target-broad case_data_target_broad
expect_failure data-target-symlink case_data_target_symlink
expect_failure data-target-identity-swap case_data_target_identity_swap
expect_failure restore-candidate-symlink case_restore_candidate_symlink
expect_failure dump-candidate-fifo case_dump_candidate_fifo
expect_failure restore-find-failure case_restore_find_failure
expect_failure restore-sort-failure case_restore_sort_failure
expect_success sequence-highest-all-outputs case_sequence_highest_all_outputs
expect_failure sequence-find-failure case_sequence_find_failure
expect_failure chain-sort-failure case_chain_sort_failure
expect_success client-option-backup-success-cleanup case_client_option_success_cleanup backup
expect_success client-option-restore-success-cleanup case_client_option_success_cleanup restore
expect_success client-option-child-failure-cleanup case_client_option_child_failure_cleanup
expect_success client-option-digest-drift-preserved case_client_option_digest_drift_preserved
expect_failure client-option-rejects-line-break case_client_option_rejects_line_break
expect_failure client-option-rejects-control-byte case_client_option_rejects_control_byte
expect_success client-option-mode-drift-preserved case_client_option_mode_drift_preserved
expect_success client-option-symlink-swap-preserved case_client_option_symlink_swap_preserved
expect_success client-argv-negative-mutations case_client_argv_negative_mutations
expect_success publication-rename-then-error case_publication_rename_then_error
expect_failure publication-no-clobber case_publication_no_clobber
expect_success consume-rename-then-error-rollback case_consume_rename_then_error_rollback
expect_failure retention-no-physical-full case_retention_no_physical_full
expect_success retention-latest-valid-behind-invalid case_retention_latest_valid_behind_invalid
expect_success retention-xdev-delete case_retention_xdev_delete
expect_failure retention-find-failure case_retention_find_failure
expect_success switch-rename-then-error case_switch_rename_then_error
expect_success switch-rollback-partial case_switch_rollback_partial
expect_failure journal-rejects-duplicate-entry case_journal_rejects_duplicate_entry
expect_success sigkill-initial-journal-publish-recovery case_sigkill_initial_journal_publish_recovery
expect_success orphan-temp-plus-stage-blocks case_orphan_temp_with_artifact_blocks stage
expect_success orphan-temp-plus-old-blocks case_orphan_temp_with_artifact_blocks old
expect_success orphan-temp-plus-unknown-blocks case_orphan_temp_with_artifact_blocks unknown
expect_success sigkill-stage-recovery case_sigkill_recovery stage
expect_success sigkill-old-move-recovery case_sigkill_recovery old-move
expect_success sigkill-new-move-recovery case_sigkill_recovery new-move
expect_success sigkill-committed-finalize case_sigkill_recovery committed
expect_success sigkill-finalize-after-old-cleanup case_sigkill_recovery finalize-old
expect_success sigkill-finalize-after-stage-cleanup case_sigkill_recovery finalize-stage
expect_success term-stage-reaps-child case_term_stage_reaps_child
expect_success term-extract-reaps-child case_term_restore_phase_reaps_child extract
expect_success term-prepare-reaps-child case_term_restore_phase_reaps_child prepare
expect_success term-switch-rolls-back case_term_restore_phase_reaps_child switch
expect_success term-backup-reaps-child case_term_backup_reaps_child
expect_success guard-vendor-handoff case_guard_handoff
expect_success guard-blocks-marker case_guard_blocks_marker
expect_success guard-rejects-unsafe-root case_guard_rejects_unsafe_root
expect_success guard-find-error-blocks case_guard_find_error_blocks
expect_success guard-rejects-invalid-binlog-retention case_guard_rejects_invalid_binlog_retention
expect_success guard-rejects-invalid-purge-replica-threshold case_guard_rejects_invalid_purge_replica_threshold
expect_success static-destructive-bounds case_static_destructive_bounds

printf '\nMariaDB maintenance safety: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
