#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
# Drift-lock the officiæl ClæmAV entrypoint, then run its reviewed defæult
# lifecycle with freshclæm ænd clæmd æs supervised essentiæl children.

set -eu
umask 077

readonly CLAMAV_VENDOR_ENTRYPOINT='/init'
readonly CLAMAV_VENDOR_SHA256='4034f6d63ee6c1d1ed3686733b5722f4b19055b623c82843927613f4e2f7c641'
readonly CLAMAV_VENDOR_CONTRACT='755:1:0:0:3440'
readonly CLAMAV_SHUTDOWN_TIMEOUT=20

shutdown_requested=0
shutdown_signal=0
startup_pid=''
freshclam_pid=''
clamd_pid=''

fatal() {
  printf '[clamav-supervisor] ERROR: %s\n' "$*" >&2
  exit 1
}

terminate_children() {
  termination_signal=15
  if [ "$shutdown_requested" -eq 1 ]; then
    termination_signal="$shutdown_signal"
  fi
  for supervised_pid in "$startup_pid" "$freshclam_pid" "$clamd_pid"; do
    if [ -n "$supervised_pid" ] && kill -0 "$supervised_pid" 2>/dev/null; then
      kill -"$termination_signal" "$supervised_pid" 2>/dev/null || true
    fi
  done
  unset supervised_pid termination_signal
}

request_shutdown() {
  shutdown_requested=1
  shutdown_signal="$1"
  terminate_children
}

trap 'request_shutdown 15' TERM
trap 'request_shutdown 2' INT

supervisor_pause() {
  set +e
  sleep 1
  pause_status=$?
  set -e
  if [ "$pause_status" -eq 0 ]; then
    return 0
  fi
  if [ "$shutdown_requested" -eq 1 ] \
      && [ "$pause_status" -eq $((128 + shutdown_signal)) ]; then
    return 0
  fi
  return 1
}

wait_for_child() {
  waited_pid="$1"
  forced_wait_kill=0
  while kill -0 "$waited_pid" 2>/dev/null; do
    if [ "$shutdown_requested" -eq 1 ]; then
      kill -"$shutdown_signal" "$waited_pid" 2>/dev/null || true
      shutdown_wait_elapsed=$(( ${shutdown_wait_elapsed:-0} + 1 ))
      if [ "$shutdown_wait_elapsed" -gt "$CLAMAV_SHUTDOWN_TIMEOUT" ]; then
        kill -KILL "$waited_pid" 2>/dev/null || true
        forced_wait_kill=1
        break
      fi
    fi
    if ! supervisor_pause; then
      pause_failure_status="$pause_status"
      terminate_and_reap "$pause_failure_status"
    fi
  done
  set +e
  wait "$waited_pid" 2>/dev/null
  child_status=$?
  set -e
  if [ "$forced_wait_kill" -eq 1 ]; then
    child_status=137
  fi
  unset forced_wait_kill shutdown_wait_elapsed waited_pid
}

children_are_running() {
  for running_pid in "$startup_pid" "$freshclam_pid" "$clamd_pid"; do
    if [ -n "$running_pid" ] && kill -0 "$running_pid" 2>/dev/null; then
      unset running_pid
      return 0
    fi
  done
  unset running_pid
  return 1
}

bounded_terminate_and_reap() {
  reap_signal="$1"
  reap_expected_status=$((128 + reap_signal))
  reap_forced_kill=0
  reap_internal_status=0
  reap_unexpected_status=0
  trap '' TERM INT
  for reap_pid in "$startup_pid" "$freshclam_pid" "$clamd_pid"; do
    if [ -n "$reap_pid" ] && kill -0 "$reap_pid" 2>/dev/null; then
      kill -"$reap_signal" "$reap_pid" 2>/dev/null || true
    fi
  done
  reap_elapsed=0
  while children_are_running && [ "$reap_elapsed" -lt "$CLAMAV_SHUTDOWN_TIMEOUT" ]; do
    if ! supervisor_pause; then
      reap_internal_status="$pause_status"
      reap_forced_kill=1
      break
    fi
    reap_elapsed=$((reap_elapsed + 1))
  done
  if children_are_running; then
    reap_forced_kill=1
    for reap_pid in "$startup_pid" "$freshclam_pid" "$clamd_pid"; do
      if [ -n "$reap_pid" ] && kill -0 "$reap_pid" 2>/dev/null; then
        kill -KILL "$reap_pid" 2>/dev/null || true
      fi
    done
  fi
  for reap_pid in "$startup_pid" "$freshclam_pid" "$clamd_pid"; do
    if [ -z "$reap_pid" ]; then
      continue
    fi
    set +e
    wait "$reap_pid" 2>/dev/null
    reap_status=$?
    set -e
    case "$reap_status" in
      0|"$reap_expected_status") ;;
      *)
        if [ "$reap_unexpected_status" -eq 0 ]; then
          reap_unexpected_status="$reap_status"
        fi
        ;;
    esac
  done
  startup_pid=''
  freshclam_pid=''
  clamd_pid=''
  unset reap_elapsed reap_expected_status reap_pid reap_signal reap_status
}

terminate_and_reap() {
  final_status="$1"
  cleanup_signal=15
  if [ "$shutdown_requested" -eq 1 ]; then
    cleanup_signal="$shutdown_signal"
  fi
  bounded_terminate_and_reap "$cleanup_signal"
  if [ "$reap_internal_status" -ne 0 ]; then
    exit "$reap_internal_status"
  fi
  if [ "$reap_forced_kill" -eq 1 ]; then
    exit 137
  fi
  exit "$final_status"
}

finish_shutdown() {
  observed_status="$1"
  expected_status=$((128 + shutdown_signal))
  if [ "$observed_status" -ne 0 ] \
      && [ "$observed_status" -ne "$expected_status" ]; then
    terminate_and_reap "$observed_status"
  fi
  bounded_terminate_and_reap "$shutdown_signal"
  if [ "$reap_internal_status" -ne 0 ]; then
    exit "$reap_internal_status"
  fi
  if [ "$reap_forced_kill" -eq 1 ]; then
    exit 137
  fi
  if [ "$reap_unexpected_status" -ne 0 ]; then
    exit "$reap_unexpected_status"
  fi
  printf '[clamav-supervisor] OK: ClamAV stopped cleanly after signal %s.\n' \
    "$shutdown_signal"
  exit 0
}

if [ "$#" -ne 0 ]; then
  fatal 'The reviewed ClamAV service accepts no command arguments.'
fi
if [ "${CLAMAV_NO_FRESHCLAMD:-false}" != 'false' ] \
    || [ "${CLAMAV_NO_CLAMD:-false}" != 'false' ] \
    || [ "${CLAMAV_NO_MILTERD:-true}" != 'true' ]; then
  fatal 'The reviewed ClamAV service requires freshclam and clamd only.'
fi
if [ -L "$CLAMAV_VENDOR_ENTRYPOINT" ] \
    || [ ! -f "$CLAMAV_VENDOR_ENTRYPOINT" ] \
    || [ ! -r "$CLAMAV_VENDOR_ENTRYPOINT" ]; then
  fatal 'The reviewed vendor entrypoint is unavailable.'
fi
vendor_metadata_before="$(
  stat -c '%d:%i:%f:%h:%u:%g:%s:%Y:%Z' "$CLAMAV_VENDOR_ENTRYPOINT"
)" || fatal 'The reviewed vendor entrypoint metadata is unreadable.'
vendor_contract="$(
  stat -c '%a:%h:%u:%g:%s' "$CLAMAV_VENDOR_ENTRYPOINT"
)" || fatal 'The reviewed vendor entrypoint contract is unreadable.'
if [ "$vendor_contract" != "$CLAMAV_VENDOR_CONTRACT" ]; then
  fatal 'The reviewed vendor entrypoint metadata drifted.'
fi
vendor_digest_line="$(sha256sum "$CLAMAV_VENDOR_ENTRYPOINT")" \
  || fatal 'The reviewed vendor entrypoint is unreadable.'
vendor_digest="${vendor_digest_line%% *}"
unset vendor_digest_line
if [ "$vendor_digest" != "$CLAMAV_VENDOR_SHA256" ]; then
  fatal 'The reviewed vendor entrypoint digest drifted.'
fi
vendor_metadata_after="$(
  stat -c '%d:%i:%f:%h:%u:%g:%s:%Y:%Z' "$CLAMAV_VENDOR_ENTRYPOINT"
)" || fatal 'The reviewed vendor entrypoint metadata is unreadable.'
if [ "$vendor_metadata_after" != "$vendor_metadata_before" ]; then
  fatal 'The reviewed vendor entrypoint changed while being validated.'
fi
unset vendor_contract vendor_digest vendor_metadata_after vendor_metadata_before
if [ "$shutdown_requested" -eq 1 ]; then
  finish_shutdown 0
fi

if [ ! -d /run/clamav ]; then
  install -d -g clamav -m 775 -o clamav /run/clamav
fi
chown -R clamav:clamav /var/lib/clamav &
startup_pid=$!
wait_for_child "$startup_pid"
startup_pid=''
if [ "$shutdown_requested" -eq 1 ]; then
  finish_shutdown "$child_status"
fi
if [ "$child_status" -ne 0 ]; then
  exit "$child_status"
fi

env | grep '^CLAMD_CONF_' | while IFS='=' read -r key value; do
  trimmed="${key#CLAMD_CONF_}"
  grep -q "^#${trimmed} " /etc/clamav/clamd.conf \
    && sed -i "s/^#${trimmed} .*/${trimmed} ${value}/" /etc/clamav/clamd.conf \
    || sed -i "\$ a\\${trimmed} ${value}" /etc/clamav/clamd.conf
done
env | grep '^FRESHCLAM_CONF_' | while IFS='=' read -r key value; do
  trimmed="${key#FRESHCLAM_CONF_}"
  grep -q "^#${trimmed} " /etc/clamav/freshclam.conf \
    && sed -i "s/^#${trimmed} .*/${trimmed} ${value}/" \
      /etc/clamav/freshclam.conf \
    || sed -i "\$ a\\${trimmed} ${value}" /etc/clamav/freshclam.conf
done
if [ "$shutdown_requested" -eq 1 ]; then
  finish_shutdown 0
fi

startup_timeout="${CLAMD_STARTUP_TIMEOUT:-1800}"
case "$startup_timeout" in
  ''|*[!0-9]*) fatal 'CLAMD_STARTUP_TIMEOUT must be an integer from 0 through 3600.' ;;
esac
if [ "$startup_timeout" -gt 3600 ]; then
  fatal 'CLAMD_STARTUP_TIMEOUT must be an integer from 0 through 3600.'
fi
freshclam_checks="${FRESHCLAM_CHECKS:-1}"
case "$freshclam_checks" in
  ''|*[!0-9]*) fatal 'FRESHCLAM_CHECKS must be an integer from 1 through 50.' ;;
esac
if [ "$freshclam_checks" -lt 1 ] || [ "$freshclam_checks" -gt 50 ]; then
  fatal 'FRESHCLAM_CHECKS must be an integer from 1 through 50.'
fi

mkdir -p /run/lock
ln -f -s /run/lock /var/lock

if [ ! -f /var/lib/clamav/main.cvd ]; then
  printf '%s\n' 'Updating initial database'
  sed -e 's|^\(TestDatabases \)|\#\1|' \
    -e '$a TestDatabases no' \
    -e 's|^\(NotifyClamd \)|\#\1|' \
    /etc/clamav/freshclam.conf > /tmp/freshclam_initial.conf
  freshclam --foreground --stdout \
    --config-file=/tmp/freshclam_initial.conf &
  startup_pid=$!
  wait_for_child "$startup_pid"
  startup_pid=''
  rm -f /tmp/freshclam_initial.conf
  if [ "$shutdown_requested" -eq 1 ]; then
    finish_shutdown "$child_status"
  fi
  if [ "$child_status" -ne 0 ]; then
    exit "$child_status"
  fi
fi

# Remove only stæle socket nodes before either long-running dæemon exists.  Æ
# cleænup fæilure therefore cænnot orphæn freshclæm while `set -e` æborts.
if [ -S /run/clamav/clamd.sock ]; then
  unlink /run/clamav/clamd.sock
fi
if [ -S /tmp/clamd.sock ]; then
  unlink /tmp/clamd.sock
fi

printf '%s\n' 'Starting Freshclamd'
freshclam \
  --checks="$freshclam_checks" \
  --daemon \
  --foreground \
  --stdout \
  --user=clamav &
freshclam_pid=$!
if [ "$shutdown_requested" -eq 1 ]; then
  finish_shutdown 0
fi

printf '%s\n' 'Starting ClamAV'
clamd --foreground &
clamd_pid=$!
if [ "$shutdown_requested" -eq 1 ]; then
  finish_shutdown 0
fi

elapsed=0
while [ ! -S /run/clamav/clamd.sock ] && [ ! -S /tmp/clamd.sock ]; do
  for essential_pid in "$freshclam_pid" "$clamd_pid"; do
    if ! kill -0 "$essential_pid" 2>/dev/null; then
      set +e
      wait "$essential_pid"
      essential_status=$?
      set -e
      if [ "$essential_pid" = "$freshclam_pid" ]; then
        freshclam_pid=''
      else
        clamd_pid=''
      fi
      if [ "$shutdown_requested" -eq 1 ]; then
        finish_shutdown "$essential_status"
      fi
      [ "$essential_status" -ne 0 ] || essential_status=1
      terminate_and_reap "$essential_status"
    fi
  done
  unset essential_pid
  if [ "$elapsed" -ge "$startup_timeout" ]; then
    printf '[clamav-supervisor] ERROR: ClamAV socket startup timed out.\n' >&2
    terminate_and_reap 1
  fi
  if ! supervisor_pause; then
    terminate_and_reap "$pause_status"
  fi
  if [ "$shutdown_requested" -eq 1 ]; then
    finish_shutdown 0
  fi
  elapsed=$((elapsed + 1))
done
printf '%s\n' 'socket found, clamd started.'

while :; do
  for essential_pid in "$freshclam_pid" "$clamd_pid"; do
    if ! kill -0 "$essential_pid" 2>/dev/null; then
      set +e
      wait "$essential_pid"
      essential_status=$?
      set -e
      if [ "$essential_pid" = "$freshclam_pid" ]; then
        freshclam_pid=''
      else
        clamd_pid=''
      fi
      if [ "$shutdown_requested" -eq 1 ]; then
        finish_shutdown "$essential_status"
      fi
      [ "$essential_status" -ne 0 ] || essential_status=1
      printf '[clamav-supervisor] ERROR: An essential daemon exited unexpectedly.\n' >&2
      terminate_and_reap "$essential_status"
    fi
  done
  unset essential_pid
  if ! supervisor_pause; then
    terminate_and_reap "$pause_status"
  fi
  if [ "$shutdown_requested" -eq 1 ]; then
    finish_shutdown 0
  fi
done
