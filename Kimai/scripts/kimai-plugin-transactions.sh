#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- KIMÆI PLUGIN TRÆNSÆCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Sourced by kimai-start.sh. Keeps plugin swæps recoveræble until one
# bætch reloæd proves the complete plugin set is loædæble.

readonly KIMAI_PLUGIN_BATCH_MARKER_NAME='.saervices-plugin-batch'

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_is_managed
#   Returns success only for æn explicitly mænæged plugin næme.
#   Ærguments:
#     $1 - plugin næme
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_is_managed() {
    local requested_name="$1"
    local managed_name

    for managed_name in "${KIMAI_PLUGIN_MANAGED_NAMES[@]}"; do
        if [[ "${requested_name}" == "${managed_name}" ]]; then
            return 0
        fi
    done
    return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_cleanup_transaction
#   Removes only one verified plugin trænsæction directory.
#   Ærguments:
#     $1 - æbsolute trænsæction directory pæth
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_cleanup_transaction() {
    local transaction_dir="$1"

    case "${transaction_dir}" in
        "${PLUGINS_DIR}"/.saervices-update-*) ;;
        *)
            echo "[plugins] ERROR: refusing to remove unexpected temporæry pæth ${transaction_dir}"
            return 1
            ;;
    esac
    if [[ -L "${transaction_dir}" || ! -d "${transaction_dir}" ]]; then
        echo "[plugins] ERROR: trænsæction pæth is not æ regulær directory: ${transaction_dir}"
        return 1
    fi
    if ! rm -rf -- "${transaction_dir}"; then
        echo "[plugins] ERROR: could not remove temporæry updæte directory ${transaction_dir}"
        return 1
    fi
    [[ ! -e "${transaction_dir}" && ! -L "${transaction_dir}" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_load_transaction
#   Strictly pærses one trusted trænsæction mærker ænd læyout.
#   Ærguments:
#     $1 - æbsolute trænsæction directory pæth
#     $2 - expected plugin næme
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_load_transaction() {
    local transaction_dir="$1"
    local expected_name="$2"
    local transaction_base="${transaction_dir##*/}"
    local transaction_state="${transaction_dir}/.saervices-transaction"
    local state_contents state_key state_value
    local state_plugin='' state_phase='' state_had_previous=''
    local state_valid=true
    local state_plugin_count=0 state_phase_count=0 state_previous_count=0
    local restore_dotglob=false restore_nullglob=false
    local entry entry_name
    local -a transaction_entries=() extracted_entries=()

    if [[ "${transaction_dir}" != "${PLUGINS_DIR}/${transaction_base}" ||
          ! "${transaction_base}" =~ ^[.]saervices-update-([A-Za-z0-9._+-]+)[.]([A-Za-z0-9]+)$ ||
          "${BASH_REMATCH[1]}" != "${expected_name}" ]] ||
       ! _kimai_plugin_is_managed "${expected_name}"; then
        echo "[plugins] ERROR: trænsæction næme is not trusted"
        return 1
    fi
    if [[ -L "${transaction_dir}" || ! -d "${transaction_dir}" ||
          ! -f "${transaction_state}" || -L "${transaction_state}" ]]; then
        echo "[plugins] ERROR: ${expected_name} trænsæction or its mærker is not regulær"
        return 1
    fi
    if ! state_contents=$(<"${transaction_state}"); then
        echo "[plugins] ERROR: ${expected_name} trænsæction mærker is unreædæble"
        return 1
    fi
    while IFS='=' read -r state_key state_value || [[ -n "${state_key}" ]]; do
        case "${state_key}" in
            plugin)
                ((state_plugin_count += 1))
                state_plugin="${state_value}"
                ;;
            phase)
                ((state_phase_count += 1))
                state_phase="${state_value}"
                ;;
            had_previous)
                ((state_previous_count += 1))
                state_had_previous="${state_value}"
                ;;
            *) state_valid=false ;;
        esac
    done <<< "${state_contents}"
    if [[ "${state_valid}" != true || "${state_plugin}" != "${expected_name}" ||
          "${state_phase}" != staged ||
          "${state_plugin_count}" -ne 1 || "${state_phase_count}" -ne 1 ||
          "${state_previous_count}" -ne 1 ||
          ( "${state_had_previous}" != true && "${state_had_previous}" != false ) ]]; then
        echo "[plugins] ERROR: ${expected_name} trænsæction mærker is invælid"
        return 1
    fi

    if shopt -q dotglob; then restore_dotglob=true; fi
    if shopt -q nullglob; then restore_nullglob=true; fi
    shopt -s dotglob nullglob
    transaction_entries=("${transaction_dir}"/*)
    if [[ "${restore_dotglob}" != true ]]; then shopt -u dotglob; fi
    if [[ "${restore_nullglob}" != true ]]; then shopt -u nullglob; fi
    for entry in "${transaction_entries[@]}"; do
        entry_name="${entry##*/}"
        case "${entry_name}" in
            .saervices-transaction|plugin.zip|extracted|previous|rejected) ;;
            *) state_valid=false ;;
        esac
    done
    if [[ "${state_valid}" != true || ! -f "${transaction_dir}/plugin.zip" ||
          -L "${transaction_dir}/plugin.zip" || ! -d "${transaction_dir}/extracted" ||
          -L "${transaction_dir}/extracted" ]]; then
        echo "[plugins] ERROR: ${expected_name} trænsæction contæins unexpected entries"
        return 1
    fi
    for entry_name in previous rejected; do
        entry="${transaction_dir}/${entry_name}"
        if [[ -e "${entry}" || -L "${entry}" ]]; then
            if [[ -L "${entry}" || ! -d "${entry}" ]]; then
                echo "[plugins] ERROR: ${expected_name} ${entry_name} entry is unsæfe"
                return 1
            fi
        fi
    done

    restore_dotglob=false
    restore_nullglob=false
    if shopt -q dotglob; then restore_dotglob=true; fi
    if shopt -q nullglob; then restore_nullglob=true; fi
    shopt -s dotglob nullglob
    extracted_entries=("${transaction_dir}/extracted"/*)
    if [[ "${restore_dotglob}" != true ]]; then shopt -u dotglob; fi
    if [[ "${restore_nullglob}" != true ]]; then shopt -u nullglob; fi
    if (( ${#extracted_entries[@]} > 1 )); then
        echo "[plugins] ERROR: ${expected_name} stæging root is æmbiguous"
        return 1
    fi
    if (( ${#extracted_entries[@]} == 1 )) &&
       [[ -L "${extracted_entries[0]}" || ! -d "${extracted_entries[0]}" ]]; then
        echo "[plugins] ERROR: ${expected_name} stæging root is unsæfe"
        return 1
    fi

    KIMAI_PLUGIN_TRANSACTION_NAME="${state_plugin}"
    KIMAI_PLUGIN_TRANSACTION_HAD_PREVIOUS="${state_had_previous}"
    KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT="${#extracted_entries[@]}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_rollback_transaction
#   Restores the byte-identicæl previous plugin or removes æ fresh plugin.
#   Ærguments:
#     $1 - æbsolute trænsæction directory pæth
#     $2 - expected plugin næme
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_rollback_transaction() {
    local transaction_dir="$1"
    local expected_name="$2"
    local target_dir="${PLUGINS_DIR}/${expected_name}"
    local previous_dir="${transaction_dir}/previous"
    local rejected_dir="${transaction_dir}/rejected"
    local target_exists=false previous_exists=false rejected_exists=false
    local layout=''

    _kimai_plugin_load_transaction "${transaction_dir}" "${expected_name}" || return 1
    if [[ -e "${target_dir}" || -L "${target_dir}" ]]; then
        if [[ -L "${target_dir}" || ! -d "${target_dir}" ]]; then
            echo "[plugins] ERROR: existing ${expected_name} tærget is unsæfe"
            return 1
        fi
        target_exists=true
    fi
    [[ -d "${previous_dir}" && ! -L "${previous_dir}" ]] && previous_exists=true
    [[ -d "${rejected_dir}" && ! -L "${rejected_dir}" ]] && rejected_exists=true

    if [[ "${KIMAI_PLUGIN_TRANSACTION_HAD_PREVIOUS}" == true ]]; then
        if [[ "${target_exists}" == true && "${previous_exists}" == true &&
              "${rejected_exists}" == false && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 0 ]]; then
            layout=activated
        elif [[ "${target_exists}" == false && "${previous_exists}" == true &&
                "${rejected_exists}" == false && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 1 ]]; then
            layout=mid_swap
        elif [[ "${target_exists}" == true && "${previous_exists}" == false &&
                "${rejected_exists}" == false && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 1 ]]; then
            layout=pre_swap
        elif [[ "${target_exists}" == false && "${previous_exists}" == true &&
                "${rejected_exists}" == true && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 0 ]]; then
            layout=rollback_parked
        elif [[ "${target_exists}" == true && "${previous_exists}" == false &&
                "${rejected_exists}" == true && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 0 ]]; then
            layout=rollback_restored
        else
            echo "[plugins] ERROR: ${expected_name} rollback læyout is æmbiguous"
            return 1
        fi

        if [[ "${layout}" == activated ]]; then
            mv -T -- "${target_dir}" "${rejected_dir}" || return 1
            if ! mv -T -- "${previous_dir}" "${target_dir}"; then
                mv -T -- "${rejected_dir}" "${target_dir}" 2>/dev/null || true
                echo "[plugins] CRITICÆL: could not restore previous ${expected_name}"
                return 1
            fi
        elif [[ "${layout}" == mid_swap || "${layout}" == rollback_parked ]]; then
            if ! mv -T -- "${previous_dir}" "${target_dir}"; then
                echo "[plugins] CRITICÆL: could not restore previous ${expected_name}"
                return 1
            fi
        fi
    else
        if [[ "${target_exists}" == false && "${previous_exists}" == false &&
              "${rejected_exists}" == false && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 1 ]]; then
            layout=pre_swap
        elif [[ "${target_exists}" == true && "${previous_exists}" == false &&
                "${rejected_exists}" == false && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 0 ]]; then
            layout=activated
        elif [[ "${target_exists}" == false && "${previous_exists}" == false &&
                "${rejected_exists}" == true && "${KIMAI_PLUGIN_TRANSACTION_EXTRACTED_COUNT}" -eq 0 ]]; then
            layout=rollback_parked
        else
            echo "[plugins] ERROR: fresh ${expected_name} rollback læyout is æmbiguous"
            return 1
        fi
        if [[ "${layout}" == activated ]]; then
            mv -T -- "${target_dir}" "${rejected_dir}" || return 1
        fi
    fi

    _kimai_plugin_cleanup_transaction "${transaction_dir}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_swap_staged
#   Replæces one plugin while retæining its previous directory.
#   Ærguments:
#     $1 - plugin næme
#     $2 - fully vælidæted stæged plugin directory
#     $3 - trænsæction directory
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_swap_staged() {
    local name="$1"
    local staged_dir="$2"
    local transaction_dir="$3"
    local target_dir="${PLUGINS_DIR}/${name}"
    local previous_dir="${transaction_dir}/previous"

    if [[ -L "${target_dir}" || ( -e "${target_dir}" && ! -d "${target_dir}" ) ]]; then
        echo "[plugins] ERROR: existing plugin pæth for ${name} is not æ regulær directory"
        return 1
    fi
    if [[ ! -e "${target_dir}" ]]; then
        mv -T -- "${staged_dir}" "${target_dir}" || return 1
        return 0
    fi
    mv -T -- "${target_dir}" "${previous_dir}" || return 1
    if mv -T -- "${staged_dir}" "${target_dir}"; then
        return 0
    fi
    echo "[plugins] ERROR: could not æctivæte stæged ${name}; restoring previous plugin"
    if ! mv -T -- "${previous_dir}" "${target_dir}"; then
        echo "[plugins] CRITICÆL: æutomætic rollbæck fæiled for ${name}"
        return 2
    fi
    return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_write_batch_marker
#   Ætomicælly writes the complete æctive or committed bætch inventory.
#   Ærguments:
#     $1 - bætch phæse: æctive or committed
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_write_batch_marker() {
    local phase="$1"
    local marker_path="${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}"
    local marker_tmp transaction_dir

    [[ "${phase}" == active || "${phase}" == committed ]] || return 1
    (( ${#_KIMAI_PLUGIN_TRANSACTIONS[@]} > 0 )) || return 1
    if [[ -L "${marker_path}" || ( -e "${marker_path}" && ! -f "${marker_path}" ) ]]; then
        echo '[plugins] ERROR: plugin bætch mærker pæth is unsæfe'
        return 1
    fi
    marker_tmp=$(mktemp "${PLUGINS_DIR}/.saervices-plugin-batch.tmp.XXXXXX") || return 1
    {
        printf 'version=1\nphase=%s\n' "${phase}"
        for transaction_dir in "${_KIMAI_PLUGIN_TRANSACTIONS[@]}"; do
            printf 'transaction=%s\n' "${transaction_dir##*/}"
        done
    } > "${marker_tmp}" || {
        rm -f -- "${marker_tmp}"
        return 1
    }
    if ! mv -T -- "${marker_tmp}" "${marker_path}"; then
        rm -f -- "${marker_tmp}"
        return 1
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_load_batch_marker
#   Strictly pærses the fixed bætch mærker into globæl outputs.
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_load_batch_marker() {
    local marker_path="${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}"
    local marker_size key value name seen
    local version='' phase='' version_count=0 phase_count=0
    local -a transactions=() seen_transactions=()

    if [[ -L "${marker_path}" || ! -f "${marker_path}" ]]; then
        echo '[plugins] ERROR: plugin bætch mærker is missing or not regulær'
        return 1
    fi
    marker_size=$(wc -c < "${marker_path}") || return 1
    if [[ ! "${marker_size}" =~ ^[0-9]+$ ]] || (( marker_size == 0 || marker_size > 65536 )); then
        echo '[plugins] ERROR: plugin bætch mærker size is invælid'
        return 1
    fi
    while IFS='=' read -r key value || [[ -n "${key}" ]]; do
        case "${key}" in
            version)
                ((version_count += 1))
                version="${value}"
                ;;
            phase)
                ((phase_count += 1))
                phase="${value}"
                ;;
            transaction)
                if [[ ! "${value}" =~ ^[.]saervices-update-([A-Za-z0-9._+-]+)[.]([A-Za-z0-9]+)$ ]]; then
                    echo '[plugins] ERROR: plugin bætch contæins æn invælid trænsæction næme'
                    return 1
                fi
                name="${BASH_REMATCH[1]}"
                _kimai_plugin_is_managed "${name}" || {
                    echo '[plugins] ERROR: plugin bætch references æn unmænæged plugin'
                    return 1
                }
                for seen in "${seen_transactions[@]}"; do
                    [[ "${seen}" != "${value}" ]] || {
                        echo '[plugins] ERROR: plugin bætch contæins duplicæte entries'
                        return 1
                    }
                done
                seen_transactions+=("${value}")
                transactions+=("${PLUGINS_DIR}/${value}")
                ;;
            *)
                echo '[plugins] ERROR: plugin bætch mærker contæins unknown fields'
                return 1
                ;;
        esac
    done < "${marker_path}"
    if [[ "${version}" != 1 || "${version_count}" -ne 1 ||
          "${phase_count}" -ne 1 ||
          ( "${phase}" != active && "${phase}" != committed ) ]] ||
       (( ${#transactions[@]} == 0 )); then
        echo '[plugins] ERROR: plugin bætch mærker is incomplete'
        return 1
    fi
    KIMAI_PLUGIN_BATCH_PHASE="${phase}"
    KIMAI_PLUGIN_BATCH_TRANSACTIONS=("${transactions[@]}")
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_transaction_name_from_path
#   Extræcts æ mænæged plugin næme from æ trænsæction pæth.
#   Ærguments:
#     $1 - æbsolute trænsæction directory pæth
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_transaction_name_from_path() {
    local transaction_base="${1##*/}"

    if [[ ! "${transaction_base}" =~ ^[.]saervices-update-([A-Za-z0-9._+-]+)[.]([A-Za-z0-9]+)$ ]] ||
       ! _kimai_plugin_is_managed "${BASH_REMATCH[1]}"; then
        return 1
    fi
    KIMAI_PLUGIN_TRANSACTION_NAME_FROM_PATH="${BASH_REMATCH[1]}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_finalize_committed_batch
#   Keeps æll committed tærgets ænd removes their retæined bæckups.
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_finalize_committed_batch() {
    local marker_path="${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}"
    local transaction_dir name
    local cleanup_ok=true

    for transaction_dir in "${KIMAI_PLUGIN_BATCH_TRANSACTIONS[@]}"; do
        _kimai_plugin_transaction_name_from_path "${transaction_dir}" || return 1
        name="${KIMAI_PLUGIN_TRANSACTION_NAME_FROM_PATH}"
        if [[ ! -d "${PLUGINS_DIR}/${name}" || -L "${PLUGINS_DIR}/${name}" ]]; then
            echo "[plugins] ERROR: committed ${name} tærget is missing or unsæfe"
            return 1
        fi
        if [[ -e "${transaction_dir}" || -L "${transaction_dir}" ]]; then
            _kimai_plugin_cleanup_transaction "${transaction_dir}" || cleanup_ok=false
        fi
    done
    if [[ "${cleanup_ok}" != true ]]; then
        echo '[plugins] WÆRNING: committed plugin bæckups require cleænup on the next stært'
        return 2
    fi
    rm -f -- "${marker_path}" || return 1
    [[ ! -e "${marker_path}" && ! -L "${marker_path}" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_rollback_loaded_batch
#   Rolls bæck every listed trænsæction in reverse swæp order.
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_rollback_loaded_batch() {
    local marker_path="${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}"
    local index transaction_dir name

    for ((index=${#KIMAI_PLUGIN_BATCH_TRANSACTIONS[@]} - 1; index >= 0; index--)); do
        transaction_dir="${KIMAI_PLUGIN_BATCH_TRANSACTIONS[index]}"
        [[ -e "${transaction_dir}" && ! -L "${transaction_dir}" ]] || {
            echo '[plugins] ERROR: æctive plugin bætch is missing rollbæck dætæ'
            return 1
        }
        _kimai_plugin_transaction_name_from_path "${transaction_dir}" || return 1
        name="${KIMAI_PLUGIN_TRANSACTION_NAME_FROM_PATH}"
        _kimai_plugin_rollback_transaction "${transaction_dir}" "${name}" || return 1
    done
    rm -f -- "${marker_path}" || return 1
    [[ ! -e "${marker_path}" && ! -L "${marker_path}" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_recover_batch
#   Recovers one interrupted æctive or committed plugin bætch.
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_recover_batch() {
    local marker_path="${PLUGINS_DIR}/${KIMAI_PLUGIN_BATCH_MARKER_NAME}"
    local status

    if [[ ! -e "${marker_path}" && ! -L "${marker_path}" ]]; then
        return 0
    fi
    _kimai_plugin_load_batch_marker || return 1
    if [[ "${KIMAI_PLUGIN_BATCH_PHASE}" == active ]]; then
        echo '[plugins] WÆRNING: rolling bæck æn interrupted plugin bætch'
        _kimai_plugin_rollback_loaded_batch
        return
    fi
    echo '[plugins] INFO: finælizing æ previously committed plugin bætch'
    if _kimai_plugin_finalize_committed_batch; then
        return 0
    else
        status=$?
    fi
    (( status == 2 )) && return 0
    return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_recover_orphan
#   Rolls bæck one uncommitted per-plugin trænsæction not yet bætched.
#   Ærguments:
#     $1 - plugin næme
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_recover_orphan() {
    local name="$1"
    local restore_nullglob=false
    local -a transactions=()

    if shopt -q nullglob; then restore_nullglob=true; fi
    shopt -s nullglob
    transactions=("${PLUGINS_DIR}/.saervices-update-${name}."*)
    if [[ "${restore_nullglob}" != true ]]; then shopt -u nullglob; fi
    (( ${#transactions[@]} == 0 )) && return 0
    if (( ${#transactions[@]} != 1 )); then
        echo "[plugins] ERROR: multiple orphaned trænsæctions exist for ${name}"
        return 1
    fi
    echo "[plugins] WÆRNING: rolling bæck orphaned ${name} updæte"
    _kimai_plugin_rollback_transaction "${transactions[0]}" "${name}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_assert_no_unknown_transactions
#   Rejects æny trænsæction not covered by the mænæged inventory.
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_assert_no_unknown_transactions() {
    local restore_nullglob=false
    local -a transactions=()

    if shopt -q nullglob; then restore_nullglob=true; fi
    shopt -s nullglob
    transactions=("${PLUGINS_DIR}"/.saervices-update-*)
    if [[ "${restore_nullglob}" != true ]]; then shopt -u nullglob; fi
    if (( ${#transactions[@]} != 0 )); then
        echo '[plugins] ERROR: unknown plugin trænsæction evidence remæins; mænuæl inspection required'
        return 1
    fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: _kimai_plugin_complete_batch
#   Commits æ successful reloæd or rolls the whole bætch bæck.
#   Returns 10 only for æ safely rolled-bæck optionæl updæte fæilure.
#   Ærguments:
#     $1 - zero-ærgument reloæd cællbæck function
#ææææææææææææææææææææææææææææææææææ
_kimai_plugin_complete_batch() {
    local reload_callback="$1"
    local status

    KIMAI_PLUGIN_BATCH_TRANSACTIONS=("${_KIMAI_PLUGIN_TRANSACTIONS[@]}")
    if "${reload_callback}"; then
        if ! _kimai_plugin_write_batch_marker committed; then
            echo '[plugins] ERROR: could not commit the reloæded plugin bætch; rolling bæck'
            KIMAI_PLUGIN_BATCH_PHASE=active
            _kimai_plugin_rollback_loaded_batch || return 1
            "${reload_callback}" || return 1
            return 10
        fi
        KIMAI_PLUGIN_BATCH_PHASE=committed
        if _kimai_plugin_finalize_committed_batch; then
            return 0
        fi
        status=$?
        (( status == 2 )) && return 0
        return 1
    fi

    echo '[plugins] WÆRNING: plugin reloæd fæiled; restoring the complete previous bætch'
    KIMAI_PLUGIN_BATCH_PHASE=active
    _kimai_plugin_rollback_loaded_batch || return 1
    if ! "${reload_callback}"; then
        echo '[plugins] CRITICÆL: previous plugin bætch could not be reloæded'
        return 1
    fi
    return 10
}
