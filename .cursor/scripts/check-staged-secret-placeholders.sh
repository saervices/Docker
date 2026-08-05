#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- STÆGED SECRET PLÆCEHOLDER CHECK
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

readonly EXPECTED_SECRET='CHANGE_ME'
readonly EXPECTED_SECRET_SIZE=9
STAGED_LIST_FILE=""

cleanup_staged_list() {
  if [[ -n "$STAGED_LIST_FILE" && -f "$STAGED_LIST_FILE" ]]; then
    rm -f -- "$STAGED_LIST_FILE"
  fi
}
trap cleanup_staged_list EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_staged_secret
#   Requires one regulær Git blob with the exæct cænonicæl plæceholder.
#   Ærguments:
#     $1 - repository-relætive stæged secret pæth
#ææææææææææææææææææææææææææææææææææ
check_staged_secret() {
  local file="$1"
  local blob_size=""
  local index_mode=""
  local -a index_entries=()

  mapfile -t index_entries < <(git ls-files --stage -- "$file")
  if (( ${#index_entries[@]} != 1 )); then
    printf '[secret-placeholder] Refusing unmerged or ambiguous secret path: %q\n' "$file" >&2
    return 1
  fi

  index_mode="${index_entries[0]%% *}"
  if [[ "$index_mode" != "100644" ]]; then
    printf '[secret-placeholder] Secret must be a non-executable regular Git blob: %q\n' "$file" >&2
    return 1
  fi

  if ! blob_size="$(git cat-file -s ":${file}" 2>/dev/null)"; then
    printf '[secret-placeholder] Cannot inspect staged secret blob: %q\n' "$file" >&2
    return 1
  fi
  if [[ "$blob_size" != "$EXPECTED_SECRET_SIZE" ]]; then
    printf '[secret-placeholder] Secret must contain the exact 9-byte CHANGE_ME placeholder: %q\n' "$file" >&2
    return 1
  fi

  if ! cmp -s \
    <(git cat-file blob ":${file}") \
    <(printf '%s' "$EXPECTED_SECRET"); then
    printf '[secret-placeholder] Secret must contain the exact 9-byte CHANGE_ME placeholder: %q\n' "$file" >&2
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Vælidætes every ædded, copied, modified, or renæmed secret in the index.
#ææææææææææææææææææææææææææææææææææ
main() {
  local file=""
  local checked=0
  local failed=0
  local -a staged_files=()

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf '[secret-placeholder] Run this check inside a Git worktree.\n' >&2
    return 1
  }

  STAGED_LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/staged-secret-list.XXXXXX")" || {
    printf '[secret-placeholder] Cannot create private staged-path inventory.\n' >&2
    return 1
  }
  chmod 0600 -- "$STAGED_LIST_FILE"
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git diff --cached --name-only --diff-filter=ACMR -z >"$STAGED_LIST_FILE" || {
      printf '[secret-placeholder] Cannot enumerate staged paths.\n' >&2
      return 1
    }
  else
    git ls-files --cached -z >"$STAGED_LIST_FILE" || {
      printf '[secret-placeholder] Cannot enumerate staged paths in an unborn worktree.\n' >&2
      return 1
    }
  fi
  mapfile -d '' -t staged_files <"$STAGED_LIST_FILE"
  rm -f -- "$STAGED_LIST_FILE"
  STAGED_LIST_FILE=""

  for file in "${staged_files[@]}"; do
    case "$file" in
      secrets/.gitkeep|*/secrets/.gitkeep)
        continue
        ;;
      secrets/*|*/secrets/*)
        checked=$((checked + 1))
        if ! check_staged_secret "$file"; then
          failed=$((failed + 1))
        fi
        ;;
    esac
  done

  if (( failed > 0 )); then
    printf '[secret-placeholder] Rejected %d of %d staged secret files.\n' "$failed" "$checked" >&2
    return 1
  fi

  if (( checked > 0 )); then
    printf '[secret-placeholder] Verified %d staged CHANGE_ME placeholder files.\n' "$checked"
  fi
}

main "$@"
