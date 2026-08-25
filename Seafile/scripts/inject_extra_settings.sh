#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Seæfile Extræ Settings Injector
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Æutomæticælly injects settings into Seæfile configurætion files:
# 1. seahub_settings.py - "from seahub_settings_extra import *" (OÆuth, security)
# 2. seafile.conf - [virus_scan] section (ClamAV integrætion)
# 3. seafevents.conf - [SEÆSEÆRCH] section (full-text seærch)
#
# Toggles ære symmetric: when æ feæture flæg is fælse (mænuælly or viæ the
# Community-edition æuto-gæte in seafile-start.sh), æ previously injected
# [virus_scan] section is removed ænd [SEÆSEÆRCH] is disæbled in plæce.
#
# Usage: Run this script before Seafile starts (in entrypoint or as init script)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -euo pipefail
umask 077

# Never inherit the retired legæcy cleær-secret hændoff into helper processes.
unset SEAFILE_SEASEARCH_ADMIN_PASSWORD SEASEARCH_TOKEN

#ææææææææææææææææææææææææææææææææææ
# LOGGING
#ææææææææææææææææææææææææææææææææææ
log_info() { printf '[INFO] %s\n' "$*"; }
log_ok()   { printf '[OK] %s\n' "$*"; }
log_warn() { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

SEAHUB_SETTINGS="/shared/seafile/conf/seahub_settings.py"
SEAFILE_CONF="/shared/seafile/conf/seafile.conf"
SEAFEVENTS_CONF="/shared/seafile/conf/seafevents.conf"
readonly SEAHUB_IMPORT_ENFORCER="/usr/local/bin/ensure-seahub-settings-import.py"
readonly SEASEARCH_SECRET_FILE="/run/secrets/SEAFILE_SEASEARCH_ADMIN_PASSWORD"
readonly SEAFEVENTS_BASE_CONF="${SEAFEVENTS_CONF}.saervices-base"
readonly SEASEARCH_RUNTIME_DIR="/run/seafile-runtime-config"
readonly SEASEARCH_RUNTIME_CONF="${SEASEARCH_RUNTIME_DIR}/seafevents.conf"

configure_seasearch() {
    local mode="$1"
    local host="${SEAFILE_SEASEARCH_HOST:-seafile_seasearch}"
    local port="${SEAFILE_SEASEARCH_PORT:-4080}"
    local interval="${SEAFILE_SEASEARCH_INTERVAL:-10m}"
    local index_office_pdf="${SEAFILE_SEASEARCH_INDEX_OFFICE_PDF:-true}"

    /usr/bin/python3 - \
        "$mode" \
        "$SEASEARCH_SECRET_FILE" \
        "$SEAFEVENTS_CONF" \
        "$SEAFEVENTS_BASE_CONF" \
        "$SEASEARCH_RUNTIME_DIR" \
        "$SEASEARCH_RUNTIME_CONF" \
        "$host" \
        "$port" \
        "$interval" \
        "$index_office_pdf" <<'PYTHON'
import base64
import os
import re
import stat
import sys
import unicodedata


class SecureConfigurationError(RuntimeError):
    pass


def fail(message):
    raise SecureConfigurationError(message)


def signature(metadata):
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_rdev,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def identity_signature(metadata):
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_rdev,
    )


def publication_signature(metadata):
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_nlink,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_rdev,
        metadata.st_size,
    )


def lstat_optional(path):
    try:
        return os.stat(path, follow_symlinks=False)
    except FileNotFoundError:
        return None
    except OSError:
        fail('filesystem identity inspection failed')


def read_descriptor(fd, limit):
    value = bytearray()
    while len(value) <= limit:
        try:
            chunk = os.read(fd, min(65536, limit + 1 - len(value)))
        except OSError:
            fail('bounded descriptor read failed')
        if not chunk:
            break
        value.extend(chunk)
    if len(value) > limit:
        fail('input exceeds the configured byte limit')
    return bytes(value)


def read_stable_regular(path, minimum, maximum, single_line):
    path_before = lstat_optional(path)
    if path_before is None:
        fail('required input is missing')

    flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
    flags |= getattr(os, 'O_CLOEXEC', 0)
    try:
        fd = os.open(path, flags)
    except OSError:
        fail('required input could not be opened safely')

    try:
        descriptor_before = os.fstat(fd)
        if signature(path_before) != signature(descriptor_before):
            fail('input identity changed while opening')
        if not stat.S_ISREG(descriptor_before.st_mode):
            fail('input is not a regular file')
        if descriptor_before.st_nlink != 1:
            fail('input is not a single-link file')
        if not minimum <= descriptor_before.st_size <= maximum:
            fail('input has an invalid byte length')

        first_read = read_descriptor(fd, maximum)
        if len(first_read) != descriptor_before.st_size:
            fail('input size changed during the read')
        try:
            os.lseek(fd, 0, os.SEEK_SET)
        except OSError:
            fail('input is not seekable')
        second_read = read_descriptor(fd, maximum)
        if first_read != second_read:
            fail('input content changed during validation')

        descriptor_after = os.fstat(fd)
        path_after = lstat_optional(path)
        if path_after is None:
            fail('input disappeared during validation')
        if signature(descriptor_before) != signature(descriptor_after):
            fail('input metadata changed during validation')
        if signature(descriptor_after) != signature(path_after):
            fail('input path identity changed during validation')
    finally:
        os.close(fd)

    try:
        decoded = first_read.decode('utf-8', errors='strict')
    except UnicodeDecodeError:
        fail('input must be strict UTF-8')
    if '\x00' in decoded:
        fail('input contains a NUL byte')
    if single_line:
        if decoded == 'CHANGE_ME':
            fail('credential placeholder is not configured')
        if any(
            unicodedata.category(character) == 'Cc'
            or unicodedata.category(character) in {'Zl', 'Zp'}
            for character in decoded
        ):
            fail('credential contains control or line-break characters')
    return first_read, decoded, descriptor_after


def target_state(path, managed_link_target=None):
    metadata = lstat_optional(path)
    if metadata is None:
        return None
    if stat.S_ISLNK(metadata.st_mode):
        if managed_link_target is None:
            fail('target must not be a symbolic link')
        try:
            link_target = os.readlink(path)
        except OSError:
            fail('managed link could not be inspected')
        if link_target != managed_link_target:
            fail('target has an unexpected symbolic-link destination')
        return metadata
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
        fail('target must be a single-link regular file')
    return metadata


def target_state_at(directory_fd, name):
    try:
        return os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return None
    except OSError:
        fail('target identity inspection failed')


def same_optional_state(left, right):
    if left is None or right is None:
        return left is None and right is None
    return signature(left) == signature(right)


def open_stable_parent(path):
    parent = os.path.dirname(path)
    name = os.path.basename(path)
    if not parent or not name or name in {'.', '..'}:
        fail('target path is invalid')
    parent_before = lstat_optional(parent)
    if parent_before is None or not stat.S_ISDIR(parent_before.st_mode):
        fail('target parent is not a real directory')
    flags = os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0) | os.O_NOFOLLOW
    flags |= getattr(os, 'O_CLOEXEC', 0)
    try:
        directory_fd = os.open(parent, flags)
    except OSError:
        fail('target parent could not be opened safely')
    parent_descriptor = os.fstat(directory_fd)
    if identity_signature(parent_before) != identity_signature(parent_descriptor):
        os.close(directory_fd)
        fail('target parent identity changed while opening')
    return directory_fd, name, parent_descriptor


def verify_parent_stable(path, directory_fd, expected):
    current_descriptor = os.fstat(directory_fd)
    current_path = lstat_optional(os.path.dirname(path))
    if current_path is None:
        fail('target parent disappeared')
    if identity_signature(expected) != identity_signature(current_descriptor):
        fail('target parent descriptor changed')
    if identity_signature(current_descriptor) != identity_signature(current_path):
        fail('target parent path identity changed')


def write_all(fd, payload):
    offset = 0
    while offset < len(payload):
        try:
            written = os.write(fd, payload[offset:])
        except OSError:
            fail('secure target write failed')
        if written <= 0:
            fail('secure target write made no progress')
        offset += written


def atomic_write(path, payload, owner, group, mode, expected):
    directory_fd, name, parent_descriptor = open_stable_parent(path)
    temporary_name = f'.{name}.tmp.{os.getpid()}.{os.urandom(8).hex()}'
    temporary_created = False
    try:
        if not same_optional_state(target_state_at(directory_fd, name), expected):
            fail('target identity drifted before staging')
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
        flags |= getattr(os, 'O_CLOEXEC', 0)
        try:
            temporary_fd = os.open(
                temporary_name,
                flags,
                0o600,
                dir_fd=directory_fd,
            )
        except OSError:
            fail('secure staging file could not be created')
        temporary_created = True
        try:
            write_all(temporary_fd, payload)
            current = os.fstat(temporary_fd)
            if current.st_uid != owner or current.st_gid != group:
                try:
                    os.fchown(temporary_fd, owner, group)
                except OSError:
                    fail('secure staging ownership could not be applied')
            try:
                os.fchmod(temporary_fd, mode)
                os.fsync(temporary_fd)
            except OSError:
                fail('secure staging metadata could not be committed')
            staged = os.fstat(temporary_fd)
            if (
                not stat.S_ISREG(staged.st_mode)
                or staged.st_nlink != 1
                or staged.st_size != len(payload)
                or stat.S_IMODE(staged.st_mode) != mode
                or staged.st_uid != owner
                or staged.st_gid != group
            ):
                fail('secure staging postcondition failed')
        finally:
            os.close(temporary_fd)

        staged_path = target_state_at(directory_fd, temporary_name)
        if staged_path is None or signature(staged_path) != signature(staged):
            fail('secure staging identity changed')
        if not same_optional_state(target_state_at(directory_fd, name), expected):
            fail('target identity drifted before publication')
        verify_parent_stable(path, directory_fd, parent_descriptor)
        try:
            os.replace(
                temporary_name,
                name,
                src_dir_fd=directory_fd,
                dst_dir_fd=directory_fd,
            )
            os.fsync(directory_fd)
        except OSError:
            fail('secure target publication failed')
        temporary_created = False
        published = target_state_at(directory_fd, name)
        if published is None or publication_signature(published) != publication_signature(staged):
            fail('published target identity is not the staged file')
        verify_parent_stable(path, directory_fd, parent_descriptor)
        return published
    finally:
        if temporary_created:
            try:
                os.unlink(temporary_name, dir_fd=directory_fd)
            except OSError:
                pass
        os.close(directory_fd)


def atomic_symlink(path, destination, expected):
    directory_fd, name, parent_descriptor = open_stable_parent(path)
    temporary_name = f'.{name}.link.{os.getpid()}.{os.urandom(8).hex()}'
    temporary_created = False
    try:
        if not same_optional_state(target_state_at(directory_fd, name), expected):
            fail('link target identity drifted before staging')
        try:
            os.symlink(destination, temporary_name, dir_fd=directory_fd)
        except OSError:
            fail('managed link could not be staged')
        temporary_created = True
        staged = target_state_at(directory_fd, temporary_name)
        if staged is None or not stat.S_ISLNK(staged.st_mode):
            fail('managed link staging postcondition failed')
        try:
            staged_destination = os.readlink(temporary_name, dir_fd=directory_fd)
        except OSError:
            fail('managed link staging could not be verified')
        if staged_destination != destination:
            fail('managed link staging destination drifted')
        if not same_optional_state(target_state_at(directory_fd, name), expected):
            fail('link target identity drifted before publication')
        verify_parent_stable(path, directory_fd, parent_descriptor)
        try:
            os.replace(
                temporary_name,
                name,
                src_dir_fd=directory_fd,
                dst_dir_fd=directory_fd,
            )
            os.fsync(directory_fd)
        except OSError:
            fail('managed link publication failed')
        temporary_created = False
        published = target_state_at(directory_fd, name)
        if published is None or not stat.S_ISLNK(published.st_mode):
            fail('published managed link is missing')
        if os.readlink(name, dir_fd=directory_fd) != destination:
            fail('published managed link destination drifted')
        verify_parent_stable(path, directory_fd, parent_descriptor)
    finally:
        if temporary_created:
            try:
                os.unlink(temporary_name, dir_fd=directory_fd)
            except OSError:
                pass
        os.close(directory_fd)


def ensure_runtime_directory(path, owner, group):
    parent = os.path.dirname(path)
    parent_state = lstat_optional(parent)
    if parent_state is None or not stat.S_ISDIR(parent_state.st_mode):
        fail('runtime parent is not a real directory')
    state = lstat_optional(path)
    if state is None:
        try:
            os.mkdir(path, 0o700)
        except OSError:
            fail('private runtime directory could not be created')
        state = lstat_optional(path)
    if state is None or not stat.S_ISDIR(state.st_mode):
        fail('runtime path is not a real directory')
    try:
        if state.st_uid != owner or state.st_gid != group:
            os.chown(path, owner, group, follow_symlinks=False)
        os.chmod(path, 0o700, follow_symlinks=False)
    except OSError:
        fail('private runtime directory metadata could not be applied')
    final_state = lstat_optional(path)
    if (
        final_state is None
        or not stat.S_ISDIR(final_state.st_mode)
        or final_state.st_uid != owner
        or final_state.st_gid != group
        or stat.S_IMODE(final_state.st_mode) != 0o700
    ):
        fail('private runtime directory postcondition failed')


def remove_runtime_file(path):
    directory_fd, name, parent_descriptor = open_stable_parent(path)
    try:
        expected = target_state_at(directory_fd, name)
        if expected is None:
            return
        if not stat.S_ISREG(expected.st_mode) or expected.st_nlink != 1:
            try:
                os.unlink(name, dir_fd=directory_fd)
                os.fsync(directory_fd)
            except OSError:
                pass
            fail('unsafe runtime object was removed')
        flags = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW
        flags |= getattr(os, 'O_CLOEXEC', 0)
        try:
            fd = os.open(name, flags, dir_fd=directory_fd)
        except OSError:
            fail('runtime file could not be opened safely for removal')
        try:
            descriptor = os.fstat(fd)
            if signature(descriptor) != signature(expected):
                fail('runtime file identity changed before removal')
            if not same_optional_state(target_state_at(directory_fd, name), expected):
                fail('runtime file path changed before removal')
        finally:
            os.close(fd)
        verify_parent_stable(path, directory_fd, parent_descriptor)
        try:
            os.unlink(name, dir_fd=directory_fd)
            os.fsync(directory_fd)
        except OSError:
            fail('runtime file removal failed')
        if target_state_at(directory_fd, name) is not None:
            fail('runtime file remained after removal')
    finally:
        os.close(directory_fd)


def without_seasearch_section(configuration):
    output = []
    in_seasearch = False
    for line in configuration.splitlines(keepends=True):
        section = re.match(r'^\s*\[([^]]+)\]\s*(?:[#;].*)?(?:\r?\n)?$', line)
        if section:
            in_seasearch = section.group(1).strip().upper() == 'SEASEARCH'
            if in_seasearch:
                continue
        if in_seasearch:
            continue
        if re.match(r'^\s*seasearch_token\s*=', line, flags=re.IGNORECASE):
            continue
        output.append(line)
    return ''.join(output).rstrip('\r\n') + '\n'


def disable_legacy_index_files(configuration):
    output = []
    current_section = ''
    for line in configuration.splitlines(keepends=True):
        section = re.match(r'^\s*\[([^]]+)\]\s*(?:[#;].*)?(?:\r?\n)?$', line)
        if section:
            current_section = section.group(1).strip().upper()
        if current_section == 'INDEX FILES' and re.match(
            r'^\s*enabled\s*=\s*true\s*(?:\r?\n)?$',
            line,
            flags=re.IGNORECASE,
        ):
            ending = '\r\n' if line.endswith('\r\n') else '\n'
            line = 'enabled = false' + ending
        output.append(line)
    return ''.join(output)


def validate_runtime_values(host, port, interval, index_office_pdf):
    if not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9_.-]{0,251}[A-Za-z0-9])?', host):
        fail('SeaSearch host has an invalid value')
    if not re.fullmatch(r'[1-9][0-9]{0,4}', port) or int(port) > 65535:
        fail('SeaSearch port has an invalid value')
    if not re.fullmatch(r'[1-9][0-9]*[smhd]', interval):
        fail('SeaSearch interval has an invalid value')
    if index_office_pdf not in {'true', 'false'}:
        fail('SeaSearch index flag must be exactly true or false')


def main():
    if len(sys.argv) != 11:
        fail('secure configurator argument contract failed')
    (
        _,
        mode,
        secret_path,
        primary_path,
        base_path,
        runtime_directory,
        runtime_path,
        host,
        port,
        interval,
        index_office_pdf,
    ) = sys.argv
    if mode not in {'enabled', 'disabled'}:
        fail('SeaSearch mode must be explicit')
    if 'SEAFILE_SEASEARCH_ADMIN_PASSWORD' in os.environ:
        fail('plain SeaSearch credential environment must be retired')
    validate_runtime_values(host, port, interval, index_office_pdf)

    primary_state = target_state(primary_path, runtime_path)
    base_state = target_state(base_path)
    primary_is_managed_link = bool(
        primary_state is not None and stat.S_ISLNK(primary_state.st_mode)
    )
    if primary_is_managed_link:
        if base_state is None:
            fail('managed configuration is missing its persistent base')
        source_path = base_path
    elif primary_state is not None:
        source_path = primary_path
    elif base_state is not None:
        source_path = base_path
    elif mode == 'disabled':
        return
    else:
        fail('SeaSearch configuration target is missing')

    _, source_text, source_state = read_stable_regular(
        source_path,
        0,
        4 * 1024 * 1024,
        False,
    )
    persistent_text = without_seasearch_section(source_text)
    persistent_payload = persistent_text.encode('utf-8')
    if re.search(r'^\s*seasearch_token\s*=', persistent_text, re.I | re.M):
        fail('persistent SeaSearch credential removal failed')

    base_state = target_state(base_path)
    atomic_write(
        base_path,
        persistent_payload,
        source_state.st_uid,
        source_state.st_gid,
        0o640,
        base_state,
    )
    primary_state = target_state(primary_path, runtime_path)
    primary_state = atomic_write(
        primary_path,
        persistent_payload,
        source_state.st_uid,
        source_state.st_gid,
        0o640,
        primary_state,
    )

    if mode == 'disabled':
        runtime_state = lstat_optional(runtime_path)
        if runtime_state is not None:
            remove_runtime_file(runtime_path)
        return

    secret_bytes, _, _ = read_stable_regular(secret_path, 12, 4096, True)
    token = base64.b64encode(b'seasearch:' + secret_bytes).decode('ascii')
    runtime_text = disable_legacy_index_files(persistent_text)
    runtime_text = runtime_text.rstrip('\r\n') + (
        '\n\n[SEASEARCH]\n'
        'enabled = true\n'
        f'seasearch_url = http://{host}:{port}\n'
        f'seasearch_token = {token}\n'
        f'interval = {interval}\n'
        f'index_office_pdf = {index_office_pdf}\n'
    )
    runtime_payload = runtime_text.encode('utf-8')
    ensure_runtime_directory(
        runtime_directory,
        source_state.st_uid,
        source_state.st_gid,
    )
    runtime_state = target_state(runtime_path)
    atomic_write(
        runtime_path,
        runtime_payload,
        source_state.st_uid,
        source_state.st_gid,
        0o640,
        runtime_state,
    )
    primary_state = target_state(primary_path)
    atomic_symlink(primary_path, runtime_path, primary_state)


try:
    main()
except SecureConfigurationError as error:
    print(f'[seafile] ERROR: SeaSearch secure configuration failed: {error}', file=sys.stderr)
    raise SystemExit(1)
except Exception:
    print('[seafile] ERROR: SeaSearch secure configuration failed unexpectedly.', file=sys.stderr)
    raise SystemExit(1)
PYTHON
}

# Wæit for config files to exist (in cæse Seæfile creætes them on first run)
TIMEOUT=10
ELAPSED=0
while [[ ! -f "$SEAHUB_SETTINGS" ]] && [[ $ELAPSED -lt $TIMEOUT ]]; do
    log_info "Waiting for $SEAHUB_SETTINGS to be created..."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [[ ! -f "$SEAHUB_SETTINGS" ]]; then
    log_error "$SEAHUB_SETTINGS not found after ${TIMEOUT}s. Cannot inject extra settings. Please restart the Seafile service/container so extra settings can be applied."
    exit 1
fi

# --- Seæhub Settings (OÆuth, security, etc.) ---

/usr/bin/python3 "$SEAHUB_IMPORT_ENFORCER" "$SEAHUB_SETTINGS"
log_ok "Verified exactly one active extra-settings import in $SEAHUB_SETTINGS"

# --- Virus Scæn Settings (ClamAV) ---

if [[ "${ENABLE_VIRUS_SCAN:-false}" == "true" ]] && [[ -f "$SEAFILE_CONF" ]]; then
    if grep -q '\[virus_scan\]' "$SEAFILE_CONF"; then
        log_info "Virus scan settings already present in $SEAFILE_CONF"
    else
        cat >> "$SEAFILE_CONF" << EOF

[virus_scan]
scan_command = clamdscan
virus_code = 1
nonvirus_code = 0
scan_interval = ${CLAMAV_SCAN_INTERVAL:-5}
scan_size_limit = ${CLAMAV_SCAN_SIZE_LIMIT:-20}
threads = ${CLAMAV_SCAN_THREADS:-2}
EOF
        log_ok "Injected virus scan settings into $SEAFILE_CONF"
    fi
elif [[ "${ENABLE_VIRUS_SCAN:-false}" == "true" ]]; then
    log_warn "ENABLE_VIRUS_SCAN=true but $SEAFILE_CONF not found. Restart the container to apply virus scan settings."
elif [[ -f "$SEAFILE_CONF" ]] && grep -q '\[virus_scan\]' "$SEAFILE_CONF"; then
    # Virus scæn is off (flæg or Community æuto-gæte): remove the previously injected section
    VIRUS_TMP="${SEAFILE_CONF}.inject.$$"
    awk 'BEGIN{skip=0} /^\[virus_scan\]$/{skip=1;next} /^\[/{skip=0} skip==0{print}' "$SEAFILE_CONF" > "$VIRUS_TMP"
    cat "$VIRUS_TMP" > "$SEAFILE_CONF"
    rm -f "$VIRUS_TMP"
    log_ok "Removed [virus_scan] section from $SEAFILE_CONF (virus scan disabled)"
fi

# --- SeaSearch Settings (Full-Text Seærch) ---

case "${ENABLE_SEASEARCH:-false}" in
    true)
        configure_seasearch enabled
        log_ok "Published SeaSearch settings only in the locked runtime configuration"
        ;;
    false)
        configure_seasearch disabled
        log_ok "Removed SeaSearch credentials from persistent and runtime configuration"
        ;;
    *)
        log_error "ENABLE_SEASEARCH must be exactly true or false."
        exit 1
        ;;
esac
