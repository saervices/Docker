#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -eu

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: uri_encode
#   Percent-encodes secret vælues for PostgreSQL URLs.
#   Ærguments:
#     $1 - ræw vælue
#ææææææææææææææææææææææææææææææææææ
uri_encode() {
  printf '%s' "$1" | od -An -tx1 -v | tr ' ' '\n' | while IFS= read -r hex; do
    [ -n "$hex" ] || continue
    case "$hex" in
      2d) printf '-' ;;
      2e) printf '.' ;;
      30) printf '0' ;;
      31) printf '1' ;;
      32) printf '2' ;;
      33) printf '3' ;;
      34) printf '4' ;;
      35) printf '5' ;;
      36) printf '6' ;;
      37) printf '7' ;;
      38) printf '8' ;;
      39) printf '9' ;;
      41) printf 'A' ;;
      42) printf 'B' ;;
      43) printf 'C' ;;
      44) printf 'D' ;;
      45) printf 'E' ;;
      46) printf 'F' ;;
      47) printf 'G' ;;
      48) printf 'H' ;;
      49) printf 'I' ;;
      4a) printf 'J' ;;
      4b) printf 'K' ;;
      4c) printf 'L' ;;
      4d) printf 'M' ;;
      4e) printf 'N' ;;
      4f) printf 'O' ;;
      50) printf 'P' ;;
      51) printf 'Q' ;;
      52) printf 'R' ;;
      53) printf 'S' ;;
      54) printf 'T' ;;
      55) printf 'U' ;;
      56) printf 'V' ;;
      57) printf 'W' ;;
      58) printf 'X' ;;
      59) printf 'Y' ;;
      5a) printf 'Z' ;;
      5f) printf '_' ;;
      61) printf 'a' ;;
      62) printf 'b' ;;
      63) printf 'c' ;;
      64) printf 'd' ;;
      65) printf 'e' ;;
      66) printf 'f' ;;
      67) printf 'g' ;;
      68) printf 'h' ;;
      69) printf 'i' ;;
      6a) printf 'j' ;;
      6b) printf 'k' ;;
      6c) printf 'l' ;;
      6d) printf 'm' ;;
      6e) printf 'n' ;;
      6f) printf 'o' ;;
      70) printf 'p' ;;
      71) printf 'q' ;;
      72) printf 'r' ;;
      73) printf 's' ;;
      74) printf 't' ;;
      75) printf 'u' ;;
      76) printf 'v' ;;
      77) printf 'w' ;;
      78) printf 'x' ;;
      79) printf 'y' ;;
      7a) printf 'z' ;;
      7e) printf '~' ;;
      *) printf '%%%s' "$(printf '%s' "$hex" | tr '[:lower:]' '[:upper:]')" ;;
    esac
  done
}

postgres_password_file=/run/secrets/POSTGRES_PASSWORD

if [ ! -r "$postgres_password_file" ]; then
  echo "[vaultwarden] missing readable PostgreSQL secret: $postgres_password_file" >&2
  exit 1
fi

if [ -z "${APP_NAME:-}" ]; then
  echo "[vaultwarden] APP_NAME is required to build DATABASE_URL" >&2
  exit 1
fi

postgres_password="$(tr -d '\n\r' < "$postgres_password_file")"
postgres_user="$(uri_encode "$APP_NAME")"
postgres_db="$(uri_encode "$APP_NAME")"
postgres_password="$(uri_encode "$postgres_password")"

export DATABASE_URL="postgresql://${postgres_user}:${postgres_password}@${APP_NAME}-postgresql:5432/${postgres_db}"

unset postgres_password postgres_user postgres_db postgres_password_file
