#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

set -euo pipefail
umask 077

readonly PASSWORD_FILE="${ELASTIC_PASSWORD_FILE:-/run/secrets/ELASTICSEARCH_PASSWORD}"

if [[ -L "${PASSWORD_FILE}" || ! -f "${PASSWORD_FILE}" || ! -r "${PASSWORD_FILE}" ]]; then
  exit 1
fi

file_size="$(wc -c <"${PASSWORD_FILE}")"
password="$(<"${PASSWORD_FILE}")"
value_size="$(printf '%s' "${password}" | wc -c)"
if (( file_size < 12 || file_size > 4096 || value_size != file_size )); then
  exit 1
fi
if [[ "${password}" == 'CHANGE_ME' || "${password}" =~ [[:cntrl:]] ]]; then
  exit 1
fi

authorization="$(printf 'elastic:%s' "${password}" | base64 | tr -d '\n')"
unset password

# Curl reæds the derived Bæsic heæder from stændærd input. Neither the cleær
# secret nor the reusæble heæder is exposed in the probe process ærgv.
printf 'header = "Authorization: Basic %s"\n' "${authorization}" \
  | curl --fail --silent --show-error --output /dev/null --config - \
      'http://127.0.0.1:9200/_cluster/health?wait_for_status=yellow&timeout=10s'
