#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SEÆSEÆRCH BOOTSTRÆP SECRET LIFETIME
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -euo pipefail
umask 077

readonly PASSWORD_FILE="/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
readonly DATA_PATH="${SS_DATA_PATH:-/opt/seasearch/data}"
readonly INITIALIZATION_MARKER="${DATA_PATH}/_metadata.bolt"
readonly SEASEARCH_BIN="${SEASEARCH_BIN:-/opt/seasearch/seasearch}"
readonly BOOTSTRAP_TIMEOUT="${SEASEARCH_BOOTSTRAP_TIMEOUT:-120}"
readonly BOOTSTRAP_STOP_TIMEOUT="${SEASEARCH_BOOTSTRAP_STOP_TIMEOUT:-30}"
readonly READY_PORT="${SEASEARCH_READY_PORT:-4080}"

bootstrap_pid=''
SEASEARCH_SECRET_VALUE=''
export -n SEASEARCH_SECRET_VALUE 2>/dev/null || true

fatal() {
  printf '[seasearch] ERROR: %s\n' "$*" >&2
  exit 1
}

require_positive_integer() {
  local name="$1"
  local value="$2"

  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]] || (( value > 86400 )); then
    fatal "${name} must be an integer between 1 and 86400."
  fi
}

stop_bootstrap() {
  local attempt
  local max_attempts

  if [[ -z "${bootstrap_pid}" ]] || ! kill -0 "${bootstrap_pid}" 2>/dev/null; then
    if [[ -n "${bootstrap_pid}" ]]; then
      wait "${bootstrap_pid}" 2>/dev/null || true
      bootstrap_pid=''
    fi
    return 0
  fi

  kill -TERM "${bootstrap_pid}" 2>/dev/null || true
  max_attempts=$((BOOTSTRAP_STOP_TIMEOUT * 10))
  for ((attempt = 0; attempt < max_attempts; attempt++)); do
    if ! kill -0 "${bootstrap_pid}" 2>/dev/null; then
      wait "${bootstrap_pid}" 2>/dev/null || true
      bootstrap_pid=''
      return 0
    fi
    sleep 0.1
  done

  kill -KILL "${bootstrap_pid}" 2>/dev/null || true
  wait "${bootstrap_pid}" 2>/dev/null || true
  bootstrap_pid=''
  return 1
}

cleanup() {
  local status=$?

  trap - EXIT INT TERM
  if ! stop_bootstrap && (( status == 0 )); then
    status=1
  fi
  exit "${status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

load_password() {
  local loaded_password

  if ! loaded_password="$(/usr/bin/perl - "${PASSWORD_FILE}" <<'PERL'
use strict;
use warnings;
use Fcntl qw(O_RDONLY O_NONBLOCK O_NOFOLLOW F_SETFD FD_CLOEXEC :mode);

sub fail_closed {
    die "credential validation failed\n";
}

sub signature {
    my (@value) = @_;
    return join("\0", map { defined $value[$_] ? $value[$_] : q{} }
        (0, 1, 2, 3, 4, 5, 6, 7, 9, 10));
}

sub read_bounded {
    my ($handle, $limit) = @_;
    my $value = q{};
    while (length($value) <= $limit) {
        my $remaining = $limit + 1 - length($value);
        my $count = sysread($handle, my $chunk, $remaining);
        fail_closed() if !defined $count;
        last if $count == 0;
        $value .= $chunk;
    }
    fail_closed() if length($value) > $limit;
    return $value;
}

sub strict_single_line_utf8 {
    my ($value) = @_;
    return if $value eq 'CHANGE_ME';
    my @byte = unpack('C*', $value);
    my $offset = 0;
    while ($offset < @byte) {
        my $first = $byte[$offset];
        my ($codepoint, $width);
        if ($first <= 0x7f) {
            ($codepoint, $width) = ($first, 1);
        } elsif ($first >= 0xc2 && $first <= 0xdf) {
            return if $offset + 1 >= @byte
                || $byte[$offset + 1] < 0x80 || $byte[$offset + 1] > 0xbf;
            $codepoint = (($first & 0x1f) << 6) | ($byte[$offset + 1] & 0x3f);
            $width = 2;
        } elsif ($first >= 0xe0 && $first <= 0xef) {
            return if $offset + 2 >= @byte;
            my ($second, $third) = @byte[$offset + 1, $offset + 2];
            return if $third < 0x80 || $third > 0xbf;
            return if $first == 0xe0 && ($second < 0xa0 || $second > 0xbf);
            return if $first == 0xed && ($second < 0x80 || $second > 0x9f);
            return if $first != 0xe0 && $first != 0xed
                && ($second < 0x80 || $second > 0xbf);
            $codepoint = (($first & 0x0f) << 12)
                | (($second & 0x3f) << 6)
                | ($third & 0x3f);
            $width = 3;
        } elsif ($first >= 0xf0 && $first <= 0xf4) {
            return if $offset + 3 >= @byte;
            my ($second, $third, $fourth) = @byte[$offset + 1, $offset + 2, $offset + 3];
            return if $third < 0x80 || $third > 0xbf
                || $fourth < 0x80 || $fourth > 0xbf;
            return if $first == 0xf0 && ($second < 0x90 || $second > 0xbf);
            return if $first == 0xf4 && ($second < 0x80 || $second > 0x8f);
            return if $first != 0xf0 && $first != 0xf4
                && ($second < 0x80 || $second > 0xbf);
            $codepoint = (($first & 0x07) << 18)
                | (($second & 0x3f) << 12)
                | (($third & 0x3f) << 6)
                | ($fourth & 0x3f);
            $width = 4;
        } else {
            return;
        }
        return if $codepoint <= 0x1f
            || ($codepoint >= 0x7f && $codepoint <= 0x9f)
            || $codepoint == 0x2028
            || $codepoint == 0x2029;
        $offset += $width;
    }
    return 1;
}

my $path = shift @ARGV;
fail_closed() if !defined $path || @ARGV;

my @path_before = lstat($path);
fail_closed() if !@path_before;
sysopen(my $secret_handle, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    or fail_closed();
fcntl($secret_handle, F_SETFD, FD_CLOEXEC) or fail_closed();
binmode($secret_handle, ':raw') or fail_closed();

my @descriptor_before = stat($secret_handle);
fail_closed() if !@descriptor_before;
fail_closed() if signature(@path_before) ne signature(@descriptor_before);
fail_closed() if !S_ISREG($descriptor_before[2]) || $descriptor_before[3] != 1;
fail_closed() if $descriptor_before[7] < 12 || $descriptor_before[7] > 4096;

my $first_read = read_bounded($secret_handle, 4096);
fail_closed() if length($first_read) != $descriptor_before[7];
sysseek($secret_handle, 0, 0) == 0 or fail_closed();
my $second_read = read_bounded($secret_handle, 4096);
fail_closed() if $first_read ne $second_read;

my @descriptor_after = stat($secret_handle);
my @path_after = lstat($path);
fail_closed() if !@descriptor_after || !@path_after;
fail_closed() if signature(@descriptor_before) ne signature(@descriptor_after);
fail_closed() if signature(@descriptor_after) ne signature(@path_after);

strict_single_line_utf8($first_read) or fail_closed();

close($secret_handle) or fail_closed();
binmode(STDOUT, ':raw') or fail_closed();
print STDOUT $first_read or fail_closed();
PERL
)"; then
    fatal 'The SeaSearch bootstrap credential is missing, unsafe, or malformed.'
  fi

  SEASEARCH_SECRET_VALUE="${loaded_password}"
  unset loaded_password
}

initialization_marker_exists() {
  if [[ -L "${INITIALIZATION_MARKER}" ]]; then
    fatal 'The SeaSearch initialization marker must not be a symbolic link.'
  fi
  if [[ -e "${INITIALIZATION_MARKER}" ]] && [[ ! -f "${INITIALIZATION_MARKER}" ]]; then
    fatal 'The SeaSearch initialization marker is not a regular file.'
  fi
  [[ -s "${INITIALIZATION_MARKER}" ]]
}

authenticated_readiness() {
  /usr/bin/perl - "${READY_PORT}" \
    3< <(printf '%s' "${SEASEARCH_SECRET_VALUE}") <<'PERL'
use strict;
use warnings;
use IO::Socket::INET;

sub base64_encode {
    my ($value) = @_;
    my $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    my $encoded = q{};
    for (my $offset = 0; $offset < length($value); $offset += 3) {
        my $chunk = substr($value, $offset, 3);
        my @byte = unpack('C*', $chunk);
        my $bits = ($byte[0] << 16)
            | ((defined $byte[1] ? $byte[1] : 0) << 8)
            | (defined $byte[2] ? $byte[2] : 0);
        $encoded .= substr($alphabet, ($bits >> 18) & 63, 1);
        $encoded .= substr($alphabet, ($bits >> 12) & 63, 1);
        $encoded .= defined $byte[1]
            ? substr($alphabet, ($bits >> 6) & 63, 1)
            : '=';
        $encoded .= defined $byte[2]
            ? substr($alphabet, $bits & 63, 1)
            : '=';
    }
    return $encoded;
}

sub read_secret {
    open(my $secret_handle, '<&=3') or return;
    binmode($secret_handle, ':raw') or return;
    my $value = q{};
    while (length($value) <= 4096) {
        my $remaining = 4097 - length($value);
        my $count = sysread($secret_handle, my $chunk, $remaining);
        return if !defined $count;
        last if $count == 0;
        $value .= $chunk;
    }
    close($secret_handle) or return;
    return if length($value) < 12 || length($value) > 4096;
    return $value;
}

sub request_status {
    my ($port, $authorization) = @_;
    my $status;
    my $completed = eval {
        local $SIG{ALRM} = sub { die };
        local $SIG{PIPE} = 'IGNORE';
        alarm 3;
        my $socket = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
            Proto => 'tcp',
            Timeout => 2,
        );
        die if !defined $socket;
        binmode($socket, ':raw') or die;

        my $request = "GET /api/index HTTP/1.1\r\n"
            . "Host: 127.0.0.1:${port}\r\n"
            . "Authorization: Basic ${authorization}\r\n"
            . "Accept: application/json\r\n"
            . "Connection: close\r\n\r\n";
        my $offset = 0;
        while ($offset < length($request)) {
            my $written = syswrite($socket, $request, length($request) - $offset, $offset);
            die if !defined $written || $written == 0;
            $offset += $written;
        }

        my $headers = q{};
        while (length($headers) <= 8192 && index($headers, "\r\n") < 0) {
            my $count = sysread($socket, my $chunk, 1024);
            die if !defined $count || $count == 0;
            $headers .= $chunk;
        }
        die if length($headers) > 8192;
        my ($status_line) = split(/\r\n/, $headers, 2);
        die if !defined $status_line
            || $status_line !~ m{\AHTTP/1\.[01] ([0-9]{3})(?:[ ]|\z)};
        $status = int($1);
        close($socket) or die;
        alarm 0;
        1;
    };
    alarm 0;
    return if !$completed;
    return $status;
}

my $port = shift @ARGV;
exit 1 if !defined $port || @ARGV || $port !~ /\A[1-9][0-9]{0,4}\z/ || $port > 65535;
my $password = read_secret();
exit 1 if !defined $password;

my $valid_authorization = base64_encode("seasearch:${password}");
my $invalid_authorization = base64_encode(
    "seasearch:${password}-invalid-readiness-probe",
);
my $valid_status = request_status($port, $valid_authorization);
my $invalid_status = request_status($port, $invalid_authorization);
exit 1 if !defined $valid_status || $valid_status != 200;
exit 1 if !defined $invalid_status || ($invalid_status != 401 && $invalid_status != 403);
exit 0;
PERL
}

scrub_final_environment() {
  local environment_name
  local environment_value

  while IFS= read -r environment_name; do
    [[ "${environment_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || continue
    environment_value="${!environment_name-}"
    if [[ "${environment_name}" == *SEAFILE_SEASEARCH_ADMIN_PASSWORD* ]] \
      || [[ "${environment_name}" == *SEASEARCH_PASSWORD_FILE* ]] \
      || [[ "${environment_name}" == ZINC_FIRST_ADMIN_* ]] \
      || [[ "${environment_value}" == *SEAFILE_SEASEARCH_ADMIN_PASSWORD* ]] \
      || { [[ -n "${SEASEARCH_SECRET_VALUE}" ]] \
        && [[ "${environment_value}" == *"${SEASEARCH_SECRET_VALUE}"* ]]; }; then
      unset "${environment_name}"
    fi
  done < <(compgen -e)

  unset SEASEARCH_PASSWORD_FILE SEAFILE_SEASEARCH_ADMIN_PASSWORD
  unset ZINC_FIRST_ADMIN_USER ZINC_FIRST_ADMIN_PASSWORD
}

# Retire legæcy cleær-text ænd redirectæble secret inputs before æny child
# process is stærted. The only supported credentiæl source is PASSWORD_FILE.
scrub_final_environment

require_positive_integer SEASEARCH_BOOTSTRAP_TIMEOUT "${BOOTSTRAP_TIMEOUT}"
require_positive_integer SEASEARCH_BOOTSTRAP_STOP_TIMEOUT "${BOOTSTRAP_STOP_TIMEOUT}"
require_positive_integer SEASEARCH_READY_PORT "${READY_PORT}"
if (( READY_PORT > 65535 )); then
  fatal 'SEASEARCH_READY_PORT must be between 1 and 65535.'
fi

if [[ "${1:-}" == '--preflight-only' ]]; then
  load_password
  SEASEARCH_SECRET_VALUE=''
  unset SEASEARCH_SECRET_VALUE
  exit 0
fi
if [[ "${1:-}" == '--healthcheck' ]]; then
  load_password
  scrub_final_environment
  health_status=1
  if authenticated_readiness; then
    health_status=0
  fi
  SEASEARCH_SECRET_VALUE=''
  unset SEASEARCH_SECRET_VALUE
  trap - EXIT INT TERM
  exit "${health_status}"
fi
if (( $# != 0 )); then
  fatal 'Unsupported SeaSearch entrypoint arguments.'
fi

if [[ ! -x "${SEASEARCH_BIN}" ]]; then
  fatal 'The SeaSearch vendor binary is missing or not executable.'
fi

mkdir -p "${DATA_PATH}"
if [[ -L "${DATA_PATH}" || ! -d "${DATA_PATH}" ]]; then
  fatal 'The SeaSearch data path is not a real directory.'
fi

if ! initialization_marker_exists; then
  load_password
  scrub_final_environment
  printf '[seasearch] INFO: Running bounded first-start credential bootstrap.\n'
  ZINC_FIRST_ADMIN_USER=seasearch \
    ZINC_FIRST_ADMIN_PASSWORD="${SEASEARCH_SECRET_VALUE}" \
    "${SEASEARCH_BIN}" &
  bootstrap_pid="$!"

  ready=false
  for ((attempt = 1; attempt <= BOOTSTRAP_TIMEOUT; attempt++)); do
    if ! kill -0 "${bootstrap_pid}" 2>/dev/null; then
      wait "${bootstrap_pid}" 2>/dev/null || true
      bootstrap_pid=''
      fatal 'SeaSearch exited before first-start bootstrap completed.'
    fi

    if initialization_marker_exists && authenticated_readiness; then
      ready=true
      break
    fi
    sleep 1
  done

  if [[ "${ready}" != true ]]; then
    fatal 'SeaSearch first-start bootstrap timed out.'
  fi
  if ! stop_bootstrap; then
    fatal 'SeaSearch bootstrap did not stop cleanly after SIGTERM.'
  fi
  printf '[seasearch] INFO: First-start credential bootstrap completed; restarting with æ scrubbed environment.\n'
fi

scrub_final_environment
SEASEARCH_SECRET_VALUE=''
unset SEASEARCH_SECRET_VALUE
trap - EXIT INT TERM

exec "${SEASEARCH_BIN}"
