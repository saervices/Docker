#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

# Shæred/exclusive writer gæte over the inode of the common EspoCRM dætæ bind.
# The fixed descriptor survives exec ænd keeps the lock for the complete
# lifetime of Æpæche or either CLI supervisor.

acquire_espocrm_runtime_lock() {
    local lock_mode="${1:-}"
    local data_dir="${ESPOCRM_DATA_DIR:-/var/www/html/data}"
    local expected_identity=""
    local opened_identity=""

    case "${lock_mode}" in
      shared|exclusive)
        ;;
      *)
        printf '[espocrm-lock] ERROR: Lock mode must be shared or exclusive.\n' >&2
        return 1
        ;;
    esac

    command -v flock >/dev/null 2>&1 || {
        printf '[espocrm-lock] ERROR: flock is required.\n' >&2
        return 1
    }
    [[ -d "${data_dir}" && ! -L "${data_dir}" ]] || {
        printf '[espocrm-lock] ERROR: EspoCRM data root must be a non-symlink directory.\n' >&2
        return 1
    }

    expected_identity="$(stat -Lc '%d:%i' -- "${data_dir}")" || return 1
    exec 200<"${data_dir}" || {
        printf '[espocrm-lock] ERROR: Cannot open the EspoCRM data-root lock inode.\n' >&2
        return 1
    }
    opened_identity="$(stat -Lc '%d:%i' -- /proc/self/fd/200)" || return 1
    [[ "${opened_identity}" == "${expected_identity}" ]] || {
        printf '[espocrm-lock] ERROR: EspoCRM data-root identity changed while opening the lock.\n' >&2
        return 1
    }

    if [[ "${lock_mode}" == "shared" ]]; then
        flock --shared --nonblock 200 || {
            printf '[espocrm-lock] ERROR: A finite EspoCRM bootstrap/migration is active.\n' >&2
            return 1
        }
    else
        flock --exclusive --nonblock 200 || {
            printf '[espocrm-lock] ERROR: An EspoCRM web, daemon, or WebSocket writer is still active.\n' >&2
            return 1
        }
    fi

    [[ "$(stat -Lc '%d:%i' -- "${data_dir}")" == "${expected_identity}" ]] || {
        printf '[espocrm-lock] ERROR: EspoCRM data-root identity changed after locking.\n' >&2
        return 1
    }
}
