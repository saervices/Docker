#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# First-run initiælizætion hook executed by the officiæl PostgreSQL
# docker-entrypoint. Creætes the dedicæted Mætrix Æuthenticætion Service
# role ænd dætæbæse next to the Synæpse dætæbæse creæted by initdb.
# The cluster is initiælized with --locale=C --encoding=UTF8, so both
# dætæbæses inherit the collætion thæt Synæpse requires.
set -euo pipefail
umask 077

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æn error messæge ænd æborts initiælizætion
#   Ærguments:
#     $1 - messæge text
#ææææææææææææææææææææææææææææææææææ
log_fatal() { printf '[FATAL] matrix-postgres-init: %s\n' "$1" >&2; exit 1; }

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: open_staged_secret
#   Opens one wræpper-vælidæted privæte snæpshot on inherited FD 9
#   Ærguments:
#     $1 - secret file pæth
#ææææææææææææææææææææææææææææææææææ
open_staged_secret() {
  local secret_path="$1" path_identity path_identity_after fd_identity fd_type fd_metadata expected_metadata
  [[ ! -L "${secret_path}" && -f "${secret_path}" && -r "${secret_path}" ]] || log_fatal "staged MÆS database secret is missing or has an unsafe type"
  exec 9< "${secret_path}" || log_fatal "cannot open the staged MÆS database secret"
  path_identity="$(LC_ALL=C stat -Lc '%d:%i:%h' -- "${secret_path}")" || { exec 9<&-; log_fatal "cannot inspect the staged MÆS database secret"; }
  fd_identity="$(LC_ALL=C stat -Lc '%d:%i:%h' -- /proc/self/fd/9)" || { exec 9<&-; log_fatal "cannot inspect the staged MÆS database secret descriptor"; }
  fd_type="$(LC_ALL=C stat -Lc '%F' -- /proc/self/fd/9)" || { exec 9<&-; log_fatal "cannot inspect the staged MÆS database secret type"; }
  [[ "${fd_type}" == "regular file" && "${fd_identity}" == "${path_identity}" && "${fd_identity}" == *:1 ]] || { exec 9<&-; log_fatal "staged MÆS database secret identity mismatch"; }
  fd_metadata="$(LC_ALL=C stat -Lc '%a:%u:%g:%s' -- /proc/self/fd/9)" || { exec 9<&-; log_fatal "cannot inspect the staged MÆS database secret metadata"; }
  expected_metadata="400:$(id -u):$(id -g):"
  [[ "${fd_metadata}" == "${expected_metadata}"* ]] || { exec 9<&-; log_fatal "staged MÆS database secret mode or ownership mismatch"; }
  [[ "${fd_metadata##*:}" -ge 1 && "${fd_metadata##*:}" -le 4096 ]] || { exec 9<&-; log_fatal "staged MÆS database secret size is outside the validated bound"; }
  path_identity_after="$(LC_ALL=C stat -Lc '%d:%i:%h' -- "${secret_path}")" || { exec 9<&-; log_fatal "staged MÆS database secret disappeared"; }
  [[ ! -L "${secret_path}" && "${path_identity_after}" == "${path_identity}" ]] || { exec 9<&-; log_fatal "staged MÆS database secret path drifted"; }
}

# The root-phæse wræpper stæged æ postgres-reædæble copy of the Docker
# secret; the /run/secrets originæl is not reædæble æfter the gosu drop.
staged_secret="/tmp/matrix-postgres-init/MATRIX_MAS_POSTGRES_PASSWORD"
open_staged_secret "${staged_secret}"

if ! psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<'EOSQL'
CREATE TEMP TABLE matrix_mas_secret (password text NOT NULL);
\copy matrix_mas_secret (password) FROM '/proc/self/fd/9' WITH (FORMAT csv, DELIMITER E'\003', QUOTE E'\001', ESCAPE E'\002')
DO $matrix_mas_role$
DECLARE
  mas_password text;
BEGIN
  SELECT password INTO STRICT mas_password FROM matrix_mas_secret;
  EXECUTE format('CREATE ROLE mas LOGIN PASSWORD %L', mas_password);
END
$matrix_mas_role$;
CREATE DATABASE mas OWNER mas;
EOSQL
then
  exec 9<&-
  log_fatal "cannot create the MÆS role and database from the pinned secret descriptor"
fi
exec 9<&-

rm -f "${staged_secret}" /tmp/matrix-postgres-init/MATRIX_POSTGRES_PASSWORD
rmdir /tmp/matrix-postgres-init 2>/dev/null || true

printf '[OK]    matrix-postgres-init: mas role and database created\n'
