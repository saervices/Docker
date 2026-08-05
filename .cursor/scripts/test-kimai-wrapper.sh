#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- KIMÆI WRÆPPER REGRESSION SUITE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly TEST_REPO_ROOT="$(cd -- "${TEST_SCRIPT_DIR}/../.." &>/dev/null && pwd)"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kimai-wrapper.XXXXXX")"
readonly TRANSACTION_HELPER="${TEST_REPO_ROOT}/Kimai/scripts/kimai-plugin-transactions.sh"
readonly START_SCRIPT="${TEST_REPO_ROOT}/Kimai/scripts/kimai-start.sh"
readonly COMPOSE_FILE="${TEST_REPO_ROOT}/Kimai/docker-compose.app.yaml"
readonly PRE_COMMIT_HOOK="${TEST_REPO_ROOT}/.githooks/pre-commit"
readonly AUDIT_COMMAND="${TEST_REPO_ROOT}/.cursor/commands/audit.md"
readonly CURSOR_README="${TEST_REPO_ROOT}/.cursor/README.md"
readonly VALIDATION_RULE="${TEST_REPO_ROOT}/.cursor/rules/validation.mdc"

PASS=0
FAIL=0
PLUGINS_DIR=''
KIMAI_PLUGIN_MANAGED_NAMES=(AlphaBundle BetaBundle FreshBundle)
_KIMAI_PLUGIN_TRANSACTIONS=()

# shellcheck source=../../Kimai/scripts/kimai-plugin-transactions.sh
source "${TRANSACTION_HELPER}"

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes the isolæted test tree unless evidence retention is requested.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
    if [[ "${KEEP_TEST_OUTPUT:-false}" == true ]]; then
        printf 'Evidence retained: %s\n' "${TEST_ROOT}"
    else
        rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_success
#   Runs one cæse in æ strict subshell ænd records its result.
#   Ærguments:
#     $1 - cæse næme
#     $2 - cæse function
#ææææææææææææææææææææææææææææææææææ
expect_success() {
    local name="$1"
    local status
    shift
    set +e
    ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
    status=$?
    set -e
    if (( status == 0 )); then
        ((PASS += 1))
        printf 'PASS %s\n' "${name}"
    else
        ((FAIL += 1))
        printf 'FAIL %s\n' "${name}" >&2
        sed -n '1,80p' "${TEST_ROOT}/${name}.out" >&2 || true
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: reset_fixture
#   Creætes one empty plugin root ænd resets bætch globæls.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
reset_fixture() {
    PLUGINS_DIR="${TEST_ROOT}/$1/plugins"
    mkdir -p -- "${PLUGINS_DIR}"
    _KIMAI_PLUGIN_TRANSACTIONS=()
    KIMAI_PLUGIN_BATCH_TRANSACTIONS=()
    KIMAI_PLUGIN_BATCH_PHASE=''
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_plugin
#   Creætes deterministic visible ænd hidden plugin content.
#   Ærguments:
#     $1 - plugin directory
#     $2 - content læbel
#ææææææææææææææææææææææææææææææææææ
create_plugin() {
    local plugin_dir="$1"
    local label="$2"

    mkdir -p -- "${plugin_dir}/nested"
    printf '%s\n' "${label}" >"${plugin_dir}/payload.txt"
    printf '%s\n' ".${label}" >"${plugin_dir}/.hidden"
    printf '%s\n' "nested-${label}" >"${plugin_dir}/nested/data.txt"
    chmod 0750 "${plugin_dir}" "${plugin_dir}/nested"
    chmod 0640 "${plugin_dir}/payload.txt" "${plugin_dir}/.hidden" "${plugin_dir}/nested/data.txt"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: plugin_fingerprint
#   Fingerprints relætive pæths, modes, ænd file bytes.
#   Ærguments:
#     $1 - plugin directory
#ææææææææææææææææææææææææææææææææææ
plugin_fingerprint() {
    local plugin_dir="$1"

    (
        cd -- "${plugin_dir}"
        while IFS= read -r -d '' entry; do
            if [[ -d "${entry}" ]]; then
                printf 'd %s %s\n' "$(stat -c '%a' "${entry}")" "${entry}"
            else
                printf 'f %s %s ' "$(stat -c '%a' "${entry}")" "${entry}"
                sha256sum -- "${entry}" | awk '{print $1}'
            fi
        done < <(find . -mindepth 1 -print0 | sort -z)
    ) | sha256sum | awk '{print $1}'
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_transaction
#   Creætes æ trusted stæged trænsæction for one plugin.
#   Ærguments:
#     $1 - plugin næme
#     $2 - new content læbel
#ææææææææææææææææææææææææææææææææææ
prepare_transaction() {
    local name="$1"
    local label="$2"
    local had_previous=false

    [[ -d "${PLUGINS_DIR}/${name}" ]] && had_previous=true
    TEST_TRANSACTION_DIR=$(mktemp -d "${PLUGINS_DIR}/.saervices-update-${name}.XXXXXX")
    mkdir -- "${TEST_TRANSACTION_DIR}/extracted"
    create_plugin "${TEST_TRANSACTION_DIR}/extracted/${name}" "${label}"
    printf 'fixture-archive' >"${TEST_TRANSACTION_DIR}/plugin.zip"
    printf 'plugin=%s\nphase=staged\nhad_previous=%s\n' \
        "${name}" "${had_previous}" >"${TEST_TRANSACTION_DIR}/.saervices-transaction"
    TEST_STAGED_DIR="${TEST_TRANSACTION_DIR}/extracted/${name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: activate_transaction
#   Registers then swæps one prepared plugin trænsæction.
#   Ærguments:
#     $1 - plugin næme
#     $2 - new content læbel
#ææææææææææææææææææææææææææææææææææ
activate_transaction() {
    local name="$1"
    local label="$2"

    prepare_transaction "${name}" "${label}"
    _KIMAI_PLUGIN_TRANSACTIONS+=("${TEST_TRANSACTION_DIR}")
    _kimai_plugin_write_batch_marker active
    _kimai_plugin_swap_staged "${name}" "${TEST_STAGED_DIR}" "${TEST_TRANSACTION_DIR}"
}

reload_success() { return 0; }
RELOAD_CALLS=0
reload_fail_once() {
    ((RELOAD_CALLS += 1))
    (( RELOAD_CALLS > 1 ))
}
reload_always_fails() { return 1; }

case_successful_batch_commit() {
    reset_fixture successful-commit
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    create_plugin "${PLUGINS_DIR}/BetaBundle" old-beta
    activate_transaction AlphaBundle new-alpha
    activate_transaction BetaBundle new-beta
    [[ -d "${_KIMAI_PLUGIN_TRANSACTIONS[0]}/previous" ]]
    [[ -d "${_KIMAI_PLUGIN_TRANSACTIONS[1]}/previous" ]]
    _kimai_plugin_complete_batch reload_success
    [[ "$(<"${PLUGINS_DIR}/AlphaBundle/payload.txt")" == new-alpha ]]
    [[ "$(<"${PLUGINS_DIR}/BetaBundle/payload.txt")" == new-beta ]]
    [[ ! -e "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
    [[ -z "$(find "${PLUGINS_DIR}" -maxdepth 1 -name '.saervices-update-*' -print -quit)" ]]
}

case_reload_failure_rolls_back_batch() {
    local alpha_before beta_before status
    reset_fixture reload-failure
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    create_plugin "${PLUGINS_DIR}/BetaBundle" old-beta
    alpha_before=$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")
    beta_before=$(plugin_fingerprint "${PLUGINS_DIR}/BetaBundle")
    activate_transaction AlphaBundle new-alpha
    activate_transaction BetaBundle new-beta
    RELOAD_CALLS=0
    set +e
    _kimai_plugin_complete_batch reload_fail_once
    status=$?
    set -e
    (( status == 10 && RELOAD_CALLS == 2 ))
    [[ "$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")" == "${alpha_before}" ]]
    [[ "$(plugin_fingerprint "${PLUGINS_DIR}/BetaBundle")" == "${beta_before}" ]]
    [[ ! -e "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
}

case_fresh_plugin_removed_on_failure() {
    local status
    reset_fixture fresh-rollback
    activate_transaction FreshBundle fresh-new
    RELOAD_CALLS=0
    set +e
    _kimai_plugin_complete_batch reload_fail_once
    status=$?
    set -e
    (( status == 10 ))
    [[ ! -e "${PLUGINS_DIR}/FreshBundle" ]]
    [[ ! -e "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
}

case_active_restart_recovers_old_batch() {
    local before
    reset_fixture active-restart
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    before=$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")
    activate_transaction AlphaBundle new-alpha
    _KIMAI_PLUGIN_TRANSACTIONS=()
    _kimai_plugin_recover_batch
    [[ "$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")" == "${before}" ]]
    [[ ! -e "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
}

case_committed_restart_keeps_new_batch() {
    reset_fixture committed-restart
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    activate_transaction AlphaBundle new-alpha
    _kimai_plugin_write_batch_marker committed
    _KIMAI_PLUGIN_TRANSACTIONS=()
    _kimai_plugin_recover_batch
    [[ "$(<"${PLUGINS_DIR}/AlphaBundle/payload.txt")" == new-alpha ]]
    [[ ! -e "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
}

case_mid_swap_restart_recovers_old_plugin() {
    local before
    reset_fixture mid-swap
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    before=$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")
    prepare_transaction AlphaBundle new-alpha
    _KIMAI_PLUGIN_TRANSACTIONS+=("${TEST_TRANSACTION_DIR}")
    _kimai_plugin_write_batch_marker active
    mv -T -- "${PLUGINS_DIR}/AlphaBundle" "${TEST_TRANSACTION_DIR}/previous"
    _KIMAI_PLUGIN_TRANSACTIONS=()
    _kimai_plugin_recover_batch
    [[ "$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")" == "${before}" ]]
}

case_unsafe_marker_fails_closed() {
    local before
    reset_fixture unsafe-marker
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    before=$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")
    printf 'version=1\nphase=active\ntransaction=.saervices-update-EvilBundle.ABC123\n' \
        >"${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}"
    if _kimai_plugin_recover_batch; then
        return 1
    fi
    [[ "$(plugin_fingerprint "${PLUGINS_DIR}/AlphaBundle")" == "${before}" ]]
    [[ -f "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
}

case_cleanup_failure_retries_committed_batch() {
    reset_fixture cleanup-retry
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    activate_transaction AlphaBundle new-alpha
    _kimai_plugin_write_batch_marker committed
    _KIMAI_PLUGIN_TRANSACTIONS=()
    rm() {
        if [[ "$*" == *'.saervices-update-'* ]]; then return 1; fi
        command rm "$@"
    }
    _kimai_plugin_recover_batch
    unset -f rm
    [[ -f "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
    [[ "$(<"${PLUGINS_DIR}/AlphaBundle/payload.txt")" == new-alpha ]]
    _kimai_plugin_recover_batch
    [[ ! -e "${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}" ]]
}

case_unsafe_rollback_is_nonzero() {
    reset_fixture unsafe-rollback
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    prepare_transaction AlphaBundle new-alpha
    _KIMAI_PLUGIN_TRANSACTIONS+=("${TEST_TRANSACTION_DIR}")
    _kimai_plugin_write_batch_marker active
    rm -f -- "${TEST_TRANSACTION_DIR}/.saervices-transaction"
    if _kimai_plugin_recover_batch; then
        return 1
    fi
    [[ -d "${PLUGINS_DIR}/AlphaBundle" ]]
    [[ -d "${TEST_TRANSACTION_DIR}" ]]
}

case_failed_rollback_reload_is_nonzero() {
    reset_fixture failed-old-reload
    create_plugin "${PLUGINS_DIR}/AlphaBundle" old-alpha
    activate_transaction AlphaBundle new-alpha
    if _kimai_plugin_complete_batch reload_always_fails; then
        return 1
    fi
    [[ "$(<"${PLUGINS_DIR}/AlphaBundle/payload.txt")" == old-alpha ]]
}

case_static_security_contracts() {
    grep -F 'MAILER_SMTP_ENCRYPTION: ${MAILER_SMTP_ENCRYPTION-tls}' "${COMPOSE_FILE}" >/dev/null
    grep -F './scripts/kimai-plugin-transactions.sh:/kimai-plugin-transactions.sh:ro' "${COMPOSE_FILE}" >/dev/null
    grep -F 'unset ADMINPASS APP_SECRET KIMAI_SECRET_VALUE _mailer_smtp_password' "${START_SCRIPT}" >/dev/null
    grep -F 'exec /bin/bash -- "${KIMAI_PATCHED_VENDOR_ENTRYPOINT}" "$@"' "${START_SCRIPT}" >/dev/null
    grep -F '%%env(file:KIMAI_APP_SECRET_FILE)%%' "${START_SCRIPT}" >/dev/null
    grep -F 'readonly KIMAI_RUNTIME_SECRET_DIR="${KIMAI_RUNTIME_SECRET_DIR:-/run/saervices-kimai}"' "${START_SCRIPT}" >/dev/null
    grep -F 'chmod 0440 "${staged_secret}"' "${START_SCRIPT}" >/dev/null
    grep -F 'kimai_wrapper_regressions_required=true' "${PRE_COMMIT_HOOK}" >/dev/null
    grep -F '".cursor/scripts/test-kimai-wrapper.sh"' "${PRE_COMMIT_HOOK}" >/dev/null
    grep -F 'Required staged checker is missing or not a regular file:' "${PRE_COMMIT_HOOK}" >/dev/null
    grep -F 'test-kimai-wrapper.sh' "${AUDIT_COMMAND}" >/dev/null
    grep -F 'test-kimai-wrapper.sh' "${CURSOR_README}" >/dev/null
    grep -F 'test-kimai-wrapper.sh' "${VALIDATION_RULE}" >/dev/null
    if grep -v '^[[:space:]]*#' "${START_SCRIPT}" | grep -F 'doctrine:migrations:version' >/dev/null; then
        return 1
    fi
    [[ "$(grep -c "fatal '.*migrætions fæiled; no migrætion version wæs mærked" "${START_SCRIPT}")" -eq 3 ]]
}

expect_success successful-batch-commit case_successful_batch_commit
expect_success reload-failure-rolls-back-batch case_reload_failure_rolls_back_batch
expect_success fresh-plugin-removed-on-failure case_fresh_plugin_removed_on_failure
expect_success active-restart-recovers-old-batch case_active_restart_recovers_old_batch
expect_success committed-restart-keeps-new-batch case_committed_restart_keeps_new_batch
expect_success mid-swap-restart-recovers-old-plugin case_mid_swap_restart_recovers_old_plugin
expect_success unsafe-marker-fails-closed case_unsafe_marker_fails_closed
expect_success cleanup-failure-retries-committed-batch case_cleanup_failure_retries_committed_batch
expect_success unsafe-rollback-is-nonzero case_unsafe_rollback_is_nonzero
expect_success failed-rollback-reload-is-nonzero case_failed_rollback_reload_is_nonzero
expect_success static-security-contracts case_static_security_contracts

printf 'Kimai wrapper tests: %d passed, %d failed\n' "${PASS}" "${FAIL}"
(( FAIL == 0 ))
