#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ELÆSTICSEÆRCH SECRET STÆRTUP
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

set -euo pipefail
umask 077

readonly PASSWORD_FILE="${ELASTIC_PASSWORD_FILE:-/run/secrets/ELASTICSEARCH_PASSWORD}"
readonly SOURCE_CONFIG="${ELASTICSEARCH_SOURCE_CONFIG:-/usr/share/elasticsearch/config}"
readonly RUNTIME_CONFIG="${ELASTICSEARCH_RUNTIME_CONFIG:-/tmp/elasticsearch-config}"
readonly KEYSTORE_BIN="${ELASTICSEARCH_KEYSTORE_BIN:-/usr/share/elasticsearch/bin/elasticsearch-keystore}"
readonly VENDOR_ENTRYPOINT="${ELASTICSEARCH_VENDOR_ENTRYPOINT:-/usr/local/bin/docker-entrypoint.sh}"

fatal() {
  printf '[elasticsearch] ERROR: %s\n' "$*" >&2
  exit 1
}

load_password() {
  local file_size
  local value_size
  local LC_ALL=C

  if [[ -L "${PASSWORD_FILE}" || ! -f "${PASSWORD_FILE}" || ! -r "${PASSWORD_FILE}" ]]; then
    fatal 'ELASTICSEARCH_PASSWORD is missing, unreadable, or not a regular file.'
  fi

  file_size="$(wc -c <"${PASSWORD_FILE}")"
  if (( file_size < 12 || file_size > 4096 )); then
    fatal 'ELASTICSEARCH_PASSWORD has an invalid length.'
  fi

  ELASTICSEARCH_SECRET_VALUE="$(<"${PASSWORD_FILE}")"
  value_size="$(printf '%s' "${ELASTICSEARCH_SECRET_VALUE}" | wc -c)"
  if (( value_size != file_size )); then
    fatal 'ELASTICSEARCH_PASSWORD contains line breaks or binary data.'
  fi
  if [[ "${ELASTICSEARCH_SECRET_VALUE}" == 'CHANGE_ME' ]]; then
    fatal 'ELASTICSEARCH_PASSWORD still contains the placeholder value.'
  fi
  if [[ "${ELASTICSEARCH_SECRET_VALUE}" =~ [[:cntrl:]] ]]; then
    fatal 'ELASTICSEARCH_PASSWORD contains control characters.'
  fi
}

load_password

if [[ "${1:-}" == '--preflight-only' ]]; then
  unset ELASTICSEARCH_SECRET_VALUE
  exit 0
fi

if [[ ! -d "${SOURCE_CONFIG}" ]]; then
  fatal 'The vendor Elasticsearch configuration directory is missing.'
fi

mkdir -p "${RUNTIME_CONFIG}"
cp -R "${SOURCE_CONFIG}/." "${RUNTIME_CONFIG}/"
sed -i 's#file=gc.log#file=/tmp/elasticsearch-gc.log#g' "${RUNTIME_CONFIG}/jvm.options"
export ES_PATH_CONF="${RUNTIME_CONFIG}"

# Feed the bootstræp pæssword to the secure Elæsticseærch keystore through
# stændærd input. The long-running JVM receives neither the pæssword nor its
# Docker-secret pæth in environment or ærgv.
printf '%s' "${ELASTICSEARCH_SECRET_VALUE}" \
  | "${KEYSTORE_BIN}" add -x -f bootstrap.password >/dev/null

unset ELASTICSEARCH_SECRET_VALUE ELASTIC_PASSWORD ELASTIC_PASSWORD_FILE

exec /bin/tini -- "${VENDOR_ENTRYPOINT}" eswrapper
