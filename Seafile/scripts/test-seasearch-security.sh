#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly REPO_ROOT
readonly INJECTOR_SOURCE="${SCRIPT_DIR}/inject_extra_settings.sh"
readonly IMPORT_ENFORCER_SOURCE="${SCRIPT_DIR}/ensure-seahub-settings-import.py"
readonly SEASEARCH_ENTRYPOINT_SOURCE="${REPO_ROOT}/templates/seafile_seasearch/scripts/seasearch-start.sh"

TEST_ROOT=''
TEST_ROOT_ID=''
TEST_ROOT_PARENT="$(readlink -e -- "${TMPDIR:-/tmp}")"
readonly TEST_ROOT_PARENT
TEST_ROOT_PARENT_ID="$(stat -Lc '%d:%i' -- "${TEST_ROOT_PARENT}")"
readonly TEST_ROOT_PARENT_ID
tests_passed=0
tests_failed=0

cleanup() {
    local status=$?
    local current_id
    local current_parent_id

    trap - EXIT INT TERM
    if [[ -n "${TEST_ROOT}" && ( -e "${TEST_ROOT}" || -L "${TEST_ROOT}" ) ]]; then
        current_id="$(stat -Lc '%d:%i' -- "${TEST_ROOT}" 2>/dev/null || true)"
        current_parent_id="$(stat -Lc '%d:%i' -- "${TEST_ROOT_PARENT}" 2>/dev/null || true)"
        if [[ ! -L "${TEST_ROOT}" && -d "${TEST_ROOT}" \
          && "${current_id}" == "${TEST_ROOT_ID}" \
          && "${current_parent_id}" == "${TEST_ROOT_PARENT_ID}" \
          && "${TEST_ROOT%/*}" == "${TEST_ROOT_PARENT}" \
          && "${TEST_ROOT##*/}" =~ ^seasearch-security\.[A-Za-z0-9]+$ ]]; then
            find -P "${TEST_ROOT}" -xdev -depth -mindepth 1 -delete
            rmdir -- "${TEST_ROOT}"
        else
            printf 'FAIL seasearch-security: preserving drifted fixture %s\n' "${TEST_ROOT}" >&2
            status=1
        fi
    fi
    exit "${status}"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

TEST_ROOT="$(mktemp -d "${TEST_ROOT_PARENT}/seasearch-security.XXXXXX")"
TEST_ROOT_ID="$(stat -Lc '%d:%i' -- "${TEST_ROOT}")"

pass() {
    tests_passed=$((tests_passed + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    tests_failed=$((tests_failed + 1))
    printf '[FAIL] %s\n' "$1" >&2
}

assert_not_contains() {
    local needle="$1"
    local file="$2"

    if grep -Fq -- "$needle" "$file"; then
        return 1
    fi
}

require_success() {
    local name="$1"
    local status
    shift
    set +e
    (set -e; "$@")
    status=$?
    set -e
    if (( status == 0 )); then
        pass "$name"
    else
        fail "$name"
    fi
}

require_failure() {
    local name="$1"
    local status
    shift
    set +e
    (set -e; "$@")
    status=$?
    set -e
    if (( status == 0 )); then
        fail "${name} unexpectedly succeeded"
    else
        pass "$name"
    fi
}

prepare_injector_fixture() {
    local fixture="$1"
    local conf_dir="${fixture}/shared/seafile/conf"
    local runtime_root="${fixture}/run"

    mkdir -p -- "${conf_dir}" "${runtime_root}/secrets"
    cp -- "$IMPORT_ENFORCER_SOURCE" "${fixture}/ensure-seahub-settings-import.py"
    chmod 600 "${fixture}/ensure-seahub-settings-import.py"
    printf '%s\n' '# vendor settings' >"${conf_dir}/seahub_settings.py"
    printf '%s\n' '[general]' 'enabled = true' >"${conf_dir}/seafile.conf"
    printf '%s\n' \
        '[INDEX FILES]' \
        'enabled = true' \
        '' \
        '[SEASEARCH]' \
        'enabled = true' \
        'seasearch_token = stale-persistent-token' \
        >"${conf_dir}/seafevents.conf"

    python3 - "$INJECTOR_SOURCE" "${fixture}/inject_extra_settings.sh" "$fixture" <<'PYTHON'
from pathlib import Path
import os
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
destination = Path(sys.argv[2])
root = Path(sys.argv[3])
replacements = {
    'SEAHUB_SETTINGS="/shared/seafile/conf/seahub_settings.py"':
        f'SEAHUB_SETTINGS="{root}/shared/seafile/conf/seahub_settings.py"',
    'SEAFILE_CONF="/shared/seafile/conf/seafile.conf"':
        f'SEAFILE_CONF="{root}/shared/seafile/conf/seafile.conf"',
    'SEAFEVENTS_CONF="/shared/seafile/conf/seafevents.conf"':
        f'SEAFEVENTS_CONF="{root}/shared/seafile/conf/seafevents.conf"',
    'readonly SEASEARCH_SECRET_FILE="/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"':
        f'readonly SEASEARCH_SECRET_FILE="{root}/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"',
    'readonly SEASEARCH_RUNTIME_DIR="/run/seafile-runtime-config"':
        f'readonly SEASEARCH_RUNTIME_DIR="{root}/run/seafile-runtime-config"',
    'readonly SEAHUB_IMPORT_ENFORCER="/usr/local/bin/ensure-seahub-settings-import.py"':
        f'readonly SEAHUB_IMPORT_ENFORCER="{root}/ensure-seahub-settings-import.py"',
}

for old, new in replacements.items():
    if source.count(old) != 1:
        raise SystemExit(f'injector fixture contract drifted: {old}')
    source = source.replace(old, new, 1)
destination.write_text(source, encoding='utf-8')
os.chmod(destination, 0o700)
PYTHON
}

prepare_entrypoint_fixture() {
    local fixture="$1"

    mkdir -p -- "$fixture"
    python3 - "$SEASEARCH_ENTRYPOINT_SOURCE" "${fixture}/seasearch-start.sh" \
        "${fixture}/secret-SEAFILE_SEASEARCH_ADMIN_PASSWORD" <<'PYTHON'
from pathlib import Path
import os
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
destination = Path(sys.argv[2])
secret_path = sys.argv[3]
contract = 'readonly PASSWORD_FILE="/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"'
if source.count(contract) != 1:
    raise SystemExit('SeaSearch entrypoint fixed-secret-path contract drifted')
source = source.replace(
    contract,
    f'readonly PASSWORD_FILE="{secret_path}"',
    1,
)
destination.write_text(source, encoding='utf-8')
os.chmod(destination, 0o700)
PYTHON
}

run_injector() {
    local fixture="$1"
    local enabled="$2"
    local log_file="${fixture}/injector.log"

    if ! env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        ENABLE_SEASEARCH="$enabled" \
        SEAFILE_SEASEARCH_ADMIN_PASSWORD='legacy-environment-canary' \
        /bin/bash "${fixture}/inject_extra_settings.sh" \
        >"${log_file}" 2>&1; then
        sed -n '1,80p' "$log_file" >&2
        return 1
    fi
}

test_injector_enabled_and_disabled() {
    local fixture="${TEST_ROOT}/injector-lifecycle"
    local secret='vælid-seasearch-password-42'
    local token
    local primary
    local base
    local runtime
    local log_file

    prepare_injector_fixture "$fixture"
    printf '%s' "$secret" >"${fixture}/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
    run_injector "$fixture" true

    token="$(printf 'seasearch:%s' "$secret" | base64 -w 0)"
    primary="${fixture}/shared/seafile/conf/seafevents.conf"
    base="${primary}.saervices-base"
    runtime="${fixture}/run/seafile-runtime-config/seafevents.conf"
    log_file="${fixture}/injector.log"

    [[ -L "$primary" ]]
    [[ "$(readlink -- "$primary")" == "$runtime" ]]
    [[ -f "$base" && ! -L "$base" && "$(stat -Lc '%a' -- "$base")" == 640 ]]
    [[ -f "$runtime" && ! -L "$runtime" && "$(stat -Lc '%a' -- "$runtime")" == 640 ]]
    grep -Fq -- "seasearch_token = ${token}" "$runtime"
    grep -Fq -- 'enabled = false' "$runtime"
    assert_not_contains 'seasearch_token' "$base"
    assert_not_contains "$secret" "$base"
    assert_not_contains "$secret" "$runtime"
    assert_not_contains "$secret" "$log_file"
    assert_not_contains "$token" "$log_file"
    assert_not_contains 'legacy-environment-canary' "$log_file"

    run_injector "$fixture" true
    [[ -L "$primary" && "$(readlink -- "$primary")" == "$runtime" ]]
    [[ "$(grep -Fc -- 'seasearch_token = ' "$runtime")" == 1 ]]

    find -P "${fixture}/run/secrets" -depth -mindepth 1 -delete
    run_injector "$fixture" false
    [[ -f "$primary" && ! -L "$primary" ]]
    [[ ! -e "$runtime" && ! -L "$runtime" ]]
    assert_not_contains 'seasearch_token' "$primary"
    assert_not_contains '[SEASEARCH]' "$primary"
    assert_not_contains "$token" "$base"
    assert_not_contains 'legacy-environment-canary' "$log_file"
}

test_injector_disabled_removes_legacy_token_without_secret() {
    local fixture="${TEST_ROOT}/injector-disabled"
    local primary

    prepare_injector_fixture "$fixture"
    run_injector "$fixture" false
    primary="${fixture}/shared/seafile/conf/seafevents.conf"
    [[ -f "$primary" && ! -L "$primary" ]]
    assert_not_contains 'seasearch_token' "$primary"
    assert_not_contains 'stale-persistent-token' "${primary}.saervices-base"
    [[ ! -e "${fixture}/run/seafile-runtime-config/seafevents.conf" ]]
}

run_injector_negative_case() {
    local name="$1"
    local fixture="${TEST_ROOT}/injector-negative-${name}"
    local secret_path
    local log_file

    prepare_injector_fixture "$fixture"
    secret_path="${fixture}/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
    log_file="${fixture}/injector.log"
    case "$name" in
        missing) ;;
        placeholder) printf '%s' CHANGE_ME >"$secret_path" ;;
        symlink)
            printf '%s' 'valid-symlink-target-password' >"${fixture}/outside-secret"
            ln -s -- "${fixture}/outside-secret" "$secret_path"
            ;;
        fifo) mkfifo -- "$secret_path" ;;
        hardlink)
            printf '%s' 'valid-hardlink-target-password' >"${fixture}/outside-secret"
            ln -- "${fixture}/outside-secret" "$secret_path"
            ;;
        multiline) printf 'valid-first-line\nsecond-line' >"$secret_path" ;;
        invalid-utf8) printf 'invalid-utf8-\377' >"$secret_path" ;;
        control) printf 'invalid-control-\001-byte' >"$secret_path" ;;
        *) return 2 ;;
    esac

    if timeout 5 env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        ENABLE_SEASEARCH=true \
        SEAFILE_SEASEARCH_ADMIN_PASSWORD='legacy-environment-canary' \
        /bin/bash "${fixture}/inject_extra_settings.sh" \
        >"${log_file}" 2>&1; then
        return 1
    fi
    assert_not_contains 'legacy-environment-canary' "$log_file"
    assert_not_contains 'valid-symlink-target-password' "$log_file"
    assert_not_contains 'valid-hardlink-target-password' "$log_file"
    assert_not_contains 'valid-first-line' "$log_file"
}

prepare_entrypoint_secret() {
    local fixture="$1"
    prepare_entrypoint_fixture "$fixture"
    mkdir -p -- "${fixture}/data"
    printf '%s' 'valid-entrypoint-password-42' \
        >"${fixture}/secret-SEAFILE_SEASEARCH_ADMIN_PASSWORD"
}

run_entrypoint_preflight() {
    local fixture="$1"
    /bin/bash "${fixture}/seasearch-start.sh" --preflight-only
}

run_entrypoint_negative_case() {
    local name="$1"
    local fixture="${TEST_ROOT}/entrypoint-negative-${name}"
    local secret_path
    local log_file="${fixture}/entrypoint.log"

    prepare_entrypoint_fixture "$fixture"
    secret_path="${fixture}/secret-SEAFILE_SEASEARCH_ADMIN_PASSWORD"
    case "$name" in
        missing) ;;
        placeholder) printf '%s' CHANGE_ME >"$secret_path" ;;
        symlink)
            printf '%s' 'valid-symlink-target-password' >"${fixture}/outside-secret"
            ln -s -- "${fixture}/outside-secret" "$secret_path"
            ;;
        fifo) mkfifo -- "$secret_path" ;;
        hardlink)
            printf '%s' 'valid-hardlink-target-password' >"${fixture}/outside-secret"
            ln -- "${fixture}/outside-secret" "$secret_path"
            ;;
        multiline) printf 'valid-first-line\nsecond-line' >"$secret_path" ;;
        invalid-utf8) printf 'invalid-utf8-\377' >"$secret_path" ;;
        control) printf 'invalid-control-\001-byte' >"$secret_path" ;;
        *) return 2 ;;
    esac

    if timeout 5 env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        SEASEARCH_PASSWORD_FILE='legacy-redirect-must-be-ignored' \
        /bin/bash "${fixture}/seasearch-start.sh" --preflight-only \
        >"${log_file}" 2>&1; then
        return 1
    fi
    assert_not_contains 'valid-symlink-target-password' "$log_file"
    assert_not_contains 'valid-hardlink-target-password' "$log_file"
    assert_not_contains 'valid-first-line' "$log_file"
}

AUTH_BROKER_PID=''
RUNTIME_CLEANUP_FIXTURE=''
RUNTIME_CLEANUP_PORT_FILE=''
RUNTIME_CLEANUP_LOG_FILE=''
RUNTIME_CLEANUP_BROKER_LOG=''
RUNTIME_CLEANUP_BROKER_PID=''
RUNTIME_CLEANUP_ENTRYPOINT_PID=''

start_auth_broker() {
    local port_file="$1"
    local auth_state="$2"
    local events_file="$3"
    local log_file="$4"

    /usr/bin/perl - "$port_file" "$auth_state" "$events_file" <<'PERL' \
        >"$log_file" 2>&1 &
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use IO::Socket::INET;

my ($port_file, $auth_state, $events_file) = @ARGV;
exit 2 if !defined $events_file || @ARGV != 3;

my $server = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Proto => 'tcp',
    Listen => 16,
) or exit 2;

open(my $port_handle, '>', $port_file) or exit 2;
print {$port_handle} $server->sockport(), "\n" or exit 2;
close($port_handle) or exit 2;

$SIG{TERM} = sub { close($server); exit 0 };
$SIG{INT} = sub { close($server); exit 0 };
$SIG{PIPE} = 'IGNORE';

sub record_event {
    my ($event) = @_;
    open(my $event_handle, '>>', $events_file) or return;
    print {$event_handle} "${event}\n";
    close($event_handle);
}

sub current_digest {
    open(my $state_handle, '<', $auth_state) or return;
    my $digest = <$state_handle>;
    close($state_handle) or return;
    return if !defined $digest;
    chomp($digest);
    return if $digest !~ /\A[0-9a-f]{64}\z/;
    return $digest;
}

while (1) {
    my $client = $server->accept();
    next if !defined $client;
    binmode($client, ':raw');

    my $request = q{};
    my $read_ok = eval {
        local $SIG{ALRM} = sub { die };
        alarm 3;
        while (length($request) <= 16384 && index($request, "\r\n\r\n") < 0) {
            my $count = sysread($client, my $chunk, 2048);
            die if !defined $count || $count == 0;
            $request .= $chunk;
        }
        alarm 0;
        die if length($request) > 16384 || index($request, "\r\n\r\n") < 0;
        1;
    };
    alarm 0;

    my $status = 400;
    if ($read_ok && $request =~ m{\AGET[ ]([^ ]+)[ ]HTTP/1\.[01]\r\n}) {
        my $path = $1;
        if ($path ne '/api/index') {
            $status = 404;
        } else {
            my $expected = current_digest();
            if (!defined $expected) {
                $status = 503;
                record_event('unready');
            } elsif ($request =~ /^Authorization:[ ]*Basic[ ]+([^\r\n ]+)[ ]*\r$/mi
                && sha256_hex($1) eq $expected) {
                $status = 200;
                record_event('valid');
            } else {
                $status = 401;
                record_event('invalid');
            }
        }
    }

    my %reason = (
        200 => 'OK',
        400 => 'Bad Request',
        401 => 'Unauthorized',
        404 => 'Not Found',
        503 => 'Service Unavailable',
    );
    my $body = $status == 200 ? '{"status":"ok"}' : '{"status":"denied"}';
    my $challenge = $status == 401
        ? "WWW-Authenticate: Basic realm=\"seasearch\"\r\n"
        : q{};
    my $response = "HTTP/1.1 ${status} $reason{$status}\r\n"
        . "Content-Type: application/json\r\n"
        . "Content-Length: " . length($body) . "\r\n"
        . $challenge
        . "Connection: close\r\n\r\n"
        . $body;
    my $offset = 0;
    while ($offset < length($response)) {
        my $written = syswrite($client, $response, length($response) - $offset, $offset);
        last if !defined $written || $written == 0;
        $offset += $written;
    }
    close($client);
}
PERL
    AUTH_BROKER_PID=$!
}

wait_for_file() {
    local file="$1"
    local process_id="$2"
    local attempts="$3"
    local attempt

    for ((attempt = 0; attempt < attempts; attempt++)); do
        if [[ -s "$file" ]]; then
            return 0
        fi
        if ! kill -0 "$process_id" 2>/dev/null; then
            return 1
        fi
        sleep 0.1
    done
    return 1
}

probe_auth_endpoint() {
    local port="$1"
    local mode="$2"
    local expected_status="$3"
    local secret="$4"

    /usr/bin/perl - "$port" "$mode" "$expected_status" \
        3< <(printf '%s' "$secret") <<'PERL'
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

my ($port, $mode, $expected_status) = @ARGV;
exit 2 if !defined $expected_status || @ARGV != 3;
open(my $secret_handle, '<&=3') or exit 2;
binmode($secret_handle, ':raw') or exit 2;
my $password = q{};
while (1) {
    my $count = sysread($secret_handle, my $chunk, 4097 - length($password));
    exit 2 if !defined $count;
    last if $count == 0;
    $password .= $chunk;
    exit 2 if length($password) > 4096;
}
close($secret_handle) or exit 2;
exit 2 if length($password) < 12;
if ($mode eq 'invalid') {
    $password .= '-invalid-test-probe';
} elsif ($mode ne 'valid') {
    exit 2;
}

my $authorization = base64_encode("seasearch:${password}");
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
    my $request = "GET /api/index HTTP/1.1\r\n"
        . "Host: 127.0.0.1:${port}\r\n"
        . "Authorization: Basic ${authorization}\r\n"
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
    die if !defined $status_line || $status_line !~ m{\AHTTP/1\.[01] ([0-9]{3})};
    $status = int($1);
    close($socket);
    alarm 0;
    1;
};
alarm 0;
exit 1 if !$completed || !defined $status || $status != $expected_status;
exit 0;
PERL
}

test_entrypoint_bootstrap_and_final_scrub() {
    local fixture="${TEST_ROOT}/entrypoint-runtime"
    # Prefix + credentiæl is deliberætely not divisible by three so the
    # entrypoint's dependency-free Bæse64 pædding is exercised æs well.
    local secret='runtime-seasearch-password-42x'
    local fake_binary="${fixture}/fake-seasearch"
    local log_file="${fixture}/entrypoint.log"
    local broker_log="${fixture}/broker.log"
    local port_file="${fixture}/broker.port"
    local auth_state="${fixture}/auth-state"
    local events_file="${fixture}/auth-events"
    local broker_pid=''
    local entrypoint_pid=''
    local ready_port
    local entrypoint_script="${fixture}/seasearch-start.sh"

    # shellcheck disable=SC2329 # Invoked indirectly by the local signal/exit trap.
    runtime_cleanup() {
        local status=$?
        trap - EXIT INT TERM
        if (( status != 0 )); then
            printf '[DEBUG] SeaSearch runtime fixture files:\n' >&2
            find -P "${RUNTIME_CLEANUP_FIXTURE}" -maxdepth 2 -type f \
                -printf '%P (%s bytes)\n' \
                2>/dev/null | sort >&2 || true
            if [[ -s "${RUNTIME_CLEANUP_PORT_FILE}" ]]; then
                printf '[DEBUG] Reserved readiness port: ' >&2
                sed -n '1p' "${RUNTIME_CLEANUP_PORT_FILE}" >&2
            fi
            sed -n '1,80p' "${RUNTIME_CLEANUP_LOG_FILE}" >&2 2>/dev/null || true
            sed -n '1,80p' "${RUNTIME_CLEANUP_BROKER_LOG}" >&2 2>/dev/null || true
        fi
        if [[ -n "${RUNTIME_CLEANUP_ENTRYPOINT_PID}" ]] \
          && kill -0 "${RUNTIME_CLEANUP_ENTRYPOINT_PID}" 2>/dev/null; then
            kill -TERM "${RUNTIME_CLEANUP_ENTRYPOINT_PID}" 2>/dev/null || true
            wait "${RUNTIME_CLEANUP_ENTRYPOINT_PID}" 2>/dev/null || true
        fi
        if [[ -n "${RUNTIME_CLEANUP_BROKER_PID}" ]] \
          && kill -0 "${RUNTIME_CLEANUP_BROKER_PID}" 2>/dev/null; then
            kill -TERM "${RUNTIME_CLEANUP_BROKER_PID}" 2>/dev/null || true
            wait "${RUNTIME_CLEANUP_BROKER_PID}" 2>/dev/null || true
        fi
        exit "$status"
    }
    RUNTIME_CLEANUP_FIXTURE="$fixture"
    RUNTIME_CLEANUP_PORT_FILE="$port_file"
    RUNTIME_CLEANUP_LOG_FILE="$log_file"
    RUNTIME_CLEANUP_BROKER_LOG="$broker_log"
    prepare_entrypoint_fixture "$fixture"
    trap runtime_cleanup EXIT INT TERM

    mkdir -p -- "${fixture}/data" "${fixture}/output"
    printf '%s' "$secret" >"${fixture}/secret-SEAFILE_SEASEARCH_ADMIN_PASSWORD"
    cat >"$fake_binary" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${ZINC_FIRST_ADMIN_PASSWORD:-}" ]]; then
    [[ "${ZINC_FIRST_ADMIN_USER:-}" == seasearch ]]
    printf '%s' initialized >"${SS_DATA_PATH}/_metadata.bolt"
    printf '%s' present >"${FAKE_OUTPUT_DIR}/bootstrap-secret-present"

    # Model the real persistence race: the marker exists before the admin
    # credential is committed and usable through the authenticated API.
    sleep 2
    /usr/bin/perl -MDigest::SHA=sha256_hex \
        - "${FAKE_AUTH_STATE}" <<'PERL'
use strict;
use warnings;
use Fcntl qw(O_CREAT O_EXCL O_WRONLY);

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

my $destination = shift @ARGV;
exit 2 if !defined $destination || @ARGV;
my $password = $ENV{ZINC_FIRST_ADMIN_PASSWORD};
exit 2 if !defined $password || length($password) < 12;
my $authorization = base64_encode("seasearch:${password}");
my $temporary = "${destination}.tmp.$$";
sysopen(my $handle, $temporary, O_WRONLY | O_CREAT | O_EXCL, 0600) or exit 2;
print {$handle} sha256_hex($authorization), "\n" or exit 2;
close($handle) or exit 2;
rename($temporary, $destination) or exit 2;
PERL
    exec /usr/bin/perl -e '
        use strict;
        use warnings;
        $SIG{TERM} = sub {
            open(my $handle, q{>}, $ENV{FAKE_TERM_MARKER}) or exit 2;
            print {$handle} q{term};
            close($handle) or exit 2;
            exit 0;
        };
        while (1) { select(undef, undef, undef, 0.25) }
    '
fi

LC_ALL=C tr '\0' '\n' <"/proc/${BASHPID}/environ" >"${FAKE_OUTPUT_DIR}/final.environ"
LC_ALL=C tr '\0' ' ' <"/proc/${BASHPID}/cmdline" >"${FAKE_OUTPUT_DIR}/final.cmdline"
printf '%s' final >"${FAKE_OUTPUT_DIR}/final-started"
exec /usr/bin/perl -e '
    use strict;
    use warnings;
    $SIG{TERM} = sub {
        open(my $handle, q{>}, $ENV{FAKE_FINAL_TERM}) or exit 2;
        print {$handle} q{term};
        close($handle) or exit 2;
        exit 0;
    };
    while (1) { select(undef, undef, undef, 0.25) }
'
FAKE
    chmod 700 "$fake_binary"

    start_auth_broker "$port_file" "$auth_state" "$events_file" "$broker_log"
    broker_pid="$AUTH_BROKER_PID"
    RUNTIME_CLEANUP_BROKER_PID="$broker_pid"
    if ! wait_for_file "$port_file" "$broker_pid" 50; then
        sed -n '1,80p' "$broker_log" >&2
        return 1
    fi
    IFS= read -r ready_port <"$port_file"
    [[ "$ready_port" =~ ^[1-9][0-9]{0,4}$ ]]
    (( ready_port <= 65535 ))

    env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        SS_DATA_PATH="${fixture}/data" \
        SEASEARCH_BIN="$fake_binary" \
        SEASEARCH_BOOTSTRAP_TIMEOUT=8 \
        SEASEARCH_BOOTSTRAP_STOP_TIMEOUT=2 \
        SEASEARCH_READY_PORT="$ready_port" \
        FAKE_OUTPUT_DIR="${fixture}/output" \
        FAKE_TERM_MARKER="${fixture}/output/bootstrap-term" \
        FAKE_FINAL_TERM="${fixture}/output/final-term" \
        FAKE_AUTH_STATE="$auth_state" \
        LEAK_CANARY="$secret" \
        /bin/bash "$entrypoint_script" \
        >"$log_file" 2>&1 &
    entrypoint_pid=$!
    RUNTIME_CLEANUP_ENTRYPOINT_PID="$entrypoint_pid"
    if ! wait_for_file "${fixture}/output/final-started" "$entrypoint_pid" 120; then
        sed -n '1,80p' "$log_file" >&2
        sed -n '1,80p' "$broker_log" >&2
        return 1
    fi

    [[ -s "${fixture}/output/bootstrap-secret-present" ]]
    [[ -s "${fixture}/output/bootstrap-term" ]]
    grep -Fq -- 'unready' "$events_file"
    grep -Fq -- 'valid' "$events_file"
    grep -Fq -- 'invalid' "$events_file"
    probe_auth_endpoint "$ready_port" valid 200 "$secret"
    probe_auth_endpoint "$ready_port" invalid 401 "$secret"
    env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        SEASEARCH_READY_PORT="$ready_port" \
        SEAFILE_SEASEARCH_ADMIN_PASSWORD='legacy-environment-canary' \
        SEASEARCH_PASSWORD_FILE='legacy-redirect-must-be-ignored' \
        /bin/bash "$entrypoint_script" --healthcheck

    kill -TERM "$entrypoint_pid"
    wait "$entrypoint_pid"
    entrypoint_pid=''
    RUNTIME_CLEANUP_ENTRYPOINT_PID=''
    [[ -s "${fixture}/output/final-term" ]]

    find -P "${fixture}/output" -maxdepth 1 -type f \
        -name 'final-started' -delete
    env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        SS_DATA_PATH="${fixture}/data" \
        SEASEARCH_BIN="$fake_binary" \
        SEASEARCH_READY_PORT="$ready_port" \
        FAKE_OUTPUT_DIR="${fixture}/output" \
        FAKE_TERM_MARKER="${fixture}/output/bootstrap-term-restart" \
        FAKE_FINAL_TERM="${fixture}/output/final-term-restart" \
        FAKE_AUTH_STATE="$auth_state" \
        /bin/bash "$entrypoint_script" \
        >"${fixture}/restart.log" 2>&1 &
    entrypoint_pid=$!
    RUNTIME_CLEANUP_ENTRYPOINT_PID="$entrypoint_pid"
    if ! wait_for_file "${fixture}/output/final-started" "$entrypoint_pid" 50; then
        sed -n '1,80p' "${fixture}/restart.log" >&2
        return 1
    fi
    [[ ! -e "${fixture}/output/bootstrap-term-restart" ]]
    probe_auth_endpoint "$ready_port" valid 200 "$secret"
    probe_auth_endpoint "$ready_port" invalid 401 "$secret"
    env -i \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        SEASEARCH_READY_PORT="$ready_port" \
        SEAFILE_SEASEARCH_ADMIN_PASSWORD='legacy-environment-canary' \
        SEASEARCH_PASSWORD_FILE='legacy-redirect-must-be-ignored' \
        /bin/bash "$entrypoint_script" --healthcheck

    assert_not_contains "$secret" "${fixture}/output/final.environ"
    assert_not_contains "$secret" "${fixture}/output/final.cmdline"
    assert_not_contains 'SEAFILE_SEASEARCH_ADMIN_PASSWORD' "${fixture}/output/final.environ"
    assert_not_contains 'SEAFILE_SEASEARCH_ADMIN_PASSWORD' "${fixture}/output/final.cmdline"
    assert_not_contains 'SEASEARCH_PASSWORD_FILE' "${fixture}/output/final.environ"
    assert_not_contains 'SEASEARCH_PASSWORD_FILE' "${fixture}/output/final.cmdline"
    assert_not_contains 'ZINC_FIRST_ADMIN_USER' "${fixture}/output/final.environ"
    assert_not_contains 'ZINC_FIRST_ADMIN_PASSWORD' "${fixture}/output/final.environ"
    assert_not_contains "$secret" "$log_file"
    assert_not_contains "$secret" "${fixture}/restart.log"
    assert_not_contains "$secret" "$broker_log"
    assert_not_contains 'SEAFILE_SEASEARCH_ADMIN_PASSWORD' "$log_file"
    assert_not_contains 'SEAFILE_SEASEARCH_ADMIN_PASSWORD' "${fixture}/restart.log"

    kill -TERM "$entrypoint_pid"
    wait "$entrypoint_pid"
    entrypoint_pid=''
    RUNTIME_CLEANUP_ENTRYPOINT_PID=''
    [[ -s "${fixture}/output/final-term-restart" ]]

    kill -TERM "$broker_pid"
    wait "$broker_pid"
    broker_pid=''
    RUNTIME_CLEANUP_BROKER_PID=''
    trap - EXIT INT TERM
}

require_success 'injector: enabled runtime-only token and disabled cleanup' \
    test_injector_enabled_and_disabled
require_success 'injector: disabled mode removes legacy token without secret' \
    test_injector_disabled_removes_legacy_token_without_secret
for case_name in missing placeholder symlink fifo hardlink multiline invalid-utf8 control; do
    require_success "injector: ${case_name} credential rejected" \
        run_injector_negative_case "$case_name"
done

prepare_entrypoint_secret "${TEST_ROOT}/entrypoint-valid"
require_success 'entrypoint: valid credential accepted' \
    run_entrypoint_preflight "${TEST_ROOT}/entrypoint-valid"
for case_name in missing placeholder symlink fifo hardlink multiline invalid-utf8 control; do
    require_success "entrypoint: ${case_name} credential rejected" \
        run_entrypoint_negative_case "$case_name"
done
require_success 'entrypoint: bootstrap TERM and final environment scrub' \
    test_entrypoint_bootstrap_and_final_scrub

if (( tests_failed != 0 )); then
    printf '[SUMMARY] seasearch-security: %d passed, %d failed\n' \
        "$tests_passed" "$tests_failed" >&2
    exit 1
fi
printf '[SUMMARY] seasearch-security: %d passed, 0 failed\n' "$tests_passed"
