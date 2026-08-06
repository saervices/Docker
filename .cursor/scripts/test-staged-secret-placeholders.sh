#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS ÆND TEST HÆRNESS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

readonly TEST_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly CHECKER="${TEST_SCRIPT_DIR}/check-staged-secret-placeholders.sh"
readonly BRANDING_CHECKER="${TEST_SCRIPT_DIR}/enforce-branding.py"
readonly PRE_COMMIT_HOOK="${TEST_SCRIPT_DIR}/../../.githooks/pre-commit"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/staged-secret-placeholders.XXXXXX")"
readonly -a REQUIRED_PYTHON_STUBS=(
  ".cursor/scripts/check-hardening.py"
  ".cursor/scripts/test-build-contexts.py"
  ".cursor/scripts/test-volume-deletion.py"
  ".cursor/scripts/test-hardening.py"
  ".cursor/scripts/test-compliance-branding.py"
  ".cursor/scripts/enforce-app-template-compliance.py"
  ".cursor/scripts/verify-anchors.py"
)
readonly -a REQUIRED_SHELL_STUBS=(
  ".cursor/scripts/test-crowdsec-agent-wrapper.sh"
  ".cursor/scripts/test-crowdsec-parser-whitelists.sh"
  ".cursor/scripts/test-collabora-wrapper.sh"
  ".cursor/scripts/test-kimai-wrapper.sh"
  ".cursor/scripts/test-redis-secret-runtime.sh"
  ".cursor/scripts/test-get-folder-safety.sh"
  ".cursor/scripts/test-run-transaction.sh"
  ".cursor/scripts/test-run-source-sync.sh"
  ".cursor/scripts/test-run-update.sh"
  ".cursor/scripts/test-run-logrotate.sh"
  ".cursor/scripts/test-run-permissions.sh"
  ".cursor/scripts/test-mariadb-maintenance-safety.sh"
  ".cursor/scripts/test-postgresql-maintenance-safety.sh"
  ".cursor/scripts/test-secret-preflights.sh"
  ".cursor/scripts/test-staged-secret-placeholders.sh"
)

PASS=0
FAIL=0

cleanup_test_root() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup_test_root EXIT

pass() {
  PASS=$((PASS + 1))
  printf 'PASS %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL %s\n' "$1" >&2
  sed -n '1,40p' "${TEST_ROOT}/$1.out" >&2 || true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_case_repo
#   Creætes one disposæble repository without creæting æ commit.
#   Ærguments:
#     $1 - cæse næme
#ææææææææææææææææææææææææææææææææææ
create_case_repo() {
  local name="$1"
  local root="${TEST_ROOT}/${name}"

  mkdir -p -- "$root/secrets"
  git -C "$root" init --quiet
  printf '%s\n' "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_python_stub
#   Writes one deterministic Python checker stub.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - repository-relætive checker pæth
#     $3 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
write_python_stub() {
  local root="$1"
  local relative_path="$2"
  local exit_status="$3"

  mkdir -p -- "$(dirname -- "${root}/${relative_path}")"
  printf '#!/usr/bin/env python3\nraise SystemExit(%s)\n' "$exit_status" >"${root}/${relative_path}"
  chmod 0755 -- "${root}/${relative_path}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_build_context_trace_stub
#   Writes æ build-context stub thæt records the visible root æpp subset.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
write_build_context_trace_stub() {
  local root="$1"
  local target="${root}/.cursor/scripts/test-build-contexts.py"

  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import argparse' \
    'import os' \
    'from pathlib import Path' \
    '' \
    'def main():' \
    '    parser = argparse.ArgumentParser()' \
    '    parser.add_argument("--app", action="append", default=None)' \
    '    parser.add_argument("--synthetic-only", action="store_true")' \
    '    args = parser.parse_args()' \
    '    names = [] if args.synthetic_only else sorted(args.app or [])' \
    '    Path(os.environ["BUILD_CONTEXT_TRACE"]).write_text(f"{len(names)}:{'"'"','"'"'.join(names)}", encoding="utf-8")' \
    '' \
    'if __name__ == "__main__":' \
    '    main()' >"$target"
  chmod 0755 -- "$target"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_shell_stub
#   Writes one deterministic shell checker stub.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - repository-relætive checker pæth
#     $3 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
write_shell_stub() {
  local root="$1"
  local relative_path="$2"
  local exit_status="$3"

  mkdir -p -- "$(dirname -- "${root}/${relative_path}")"
  printf '#!/usr/bin/env bash\nexit %s\n' "$exit_status" >"${root}/${relative_path}"
  chmod 0755 -- "${root}/${relative_path}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_shellcheck_stub
#   Writes æ strict host ShellCheck stub for hook orchestrætion tests.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - stub exit stætus
#ææææææææææææææææææææææææææææææææææ
write_shellcheck_stub() {
  local root="$1"
  local exit_status="$2"
  local stub="${root}/tool-bin/shellcheck"

  mkdir -p -- "$(dirname -- "$stub")"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[[ "${1:-}" == "--severity=error" && "${2:-}" == "--" ]] || exit 97' \
    'shift' \
    'shift' \
    'IFS=: read -r -a expected <<<"${EXPECTED_SHELLCHECK_FILES:?}"' \
    'actual=("$@")' \
    '(( $# == ${#expected[@]} )) || exit 98' \
    'for index in "${!expected[@]}"; do' \
    '  [[ "${actual[index]}" == "${expected[index]}" ]] || exit 99' \
    'done' \
    "exit ${exit_status}" >"$stub"
  chmod 0755 -- "$stub"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_docker_shellcheck_stub
#   Writes æ strict Docker fællbæck stub without contæiner or network æccess.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - stub exit stætus
#ææææææææææææææææææææææææææææææææææ
write_docker_shellcheck_stub() {
  local root="$1"
  local exit_status="$2"
  local stub="${root}/isolated-bin/docker"

  mkdir -p -- "$(dirname -- "$stub")"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '(( $# >= 12 )) || exit 91' \
    '[[ "$1" == run && "$2" == --rm ]] || exit 92' \
    '[[ "$3" == --network && "$4" == none ]] || exit 93' \
    '[[ "$5" == --volume && "$6" == *:/workspace:ro ]] || exit 94' \
    '[[ "$7" == --workdir && "$8" == /workspace ]] || exit 95' \
    '[[ "$9" == koalaman/shellcheck:stable ]] || exit 96' \
    '[[ "${10}" == --severity=error && "${11}" == -- ]] || exit 97' \
    'shift 11' \
    'IFS=: read -r -a expected <<<"${EXPECTED_SHELLCHECK_FILES:?}"' \
    'actual=("$@")' \
    '(( $# == ${#expected[@]} )) || exit 98' \
    'for index in "${!expected[@]}"; do' \
    '  [[ "${actual[index]}" == "${expected[index]}" ]] || exit 99' \
    'done' \
    "exit ${exit_status}" >"$stub"
  chmod 0755 -- "$stub"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_isolated_tool_path
#   Creætes æ minimæl hook PATH without host ShellCheck or implicit network.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - docker stub mode: success, failure, or missing
#ææææææææææææææææææææææææææææææææææ
create_isolated_tool_path() {
  local root="$1"
  local docker_mode="$2"
  local command_name=""
  local command_path=""
  local tool_dir="${root}/isolated-bin"

  mkdir -p -- "$tool_dir"
  for command_name in bash chmod cmp git mktemp python3 realpath rm; do
    command_path="$(command -v "$command_name")"
    ln -s -- "$command_path" "${tool_dir}/${command_name}"
  done
  case "$docker_mode" in
    success)
      write_docker_shellcheck_stub "$root" 0
      ;;
    failure)
      write_docker_shellcheck_stub "$root" 29
      ;;
    missing)
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s\n' "$tool_dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_shell_fixture
#   Stæges one brænded shell file to trigger stæged-scope ShellCheck.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
stage_shell_fixture() {
  local root="$1"

  printf '#!/usr/bin/env bash\n# Æctuæl fixture comment\nexit 0\n' >"$root/fixture.sh"
  chmod 0755 -- "$root/fixture.sh"
  git -C "$root" add -- fixture.sh
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_pre_commit_tools
#   Instælls the reæl hook/index checkers ænd deterministic stubs.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - optionæl checker pæth to omit
#ææææææææææææææææææææææææææææææææææ
install_pre_commit_tools() {
  local root="$1"
  local omitted_path="${2:-}"
  local checker=""

  mkdir -p -- "$root/.cursor/scripts" "$root/.githooks"
  cp -- "$CHECKER" "$root/.cursor/scripts/check-staged-secret-placeholders.sh"
  cp -- "$BRANDING_CHECKER" "$root/.cursor/scripts/enforce-branding.py"
  cp -- "$PRE_COMMIT_HOOK" "$root/.githooks/pre-commit"
  chmod 0755 -- \
    "$root/.cursor/scripts/check-staged-secret-placeholders.sh" \
    "$root/.cursor/scripts/enforce-branding.py" \
    "$root/.githooks/pre-commit"

  for checker in "${REQUIRED_PYTHON_STUBS[@]}"; do
    [[ "$checker" == "$omitted_path" ]] && continue
    write_python_stub "$root" "$checker" 0
  done
  for checker in "${REQUIRED_SHELL_STUBS[@]}"; do
    [[ "$checker" == "$omitted_path" ]] && continue
    write_shell_stub "$root" "$checker" 0
  done
  git -C "$root" add -- .cursor .githooks
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: commit_fixture_baseline
#   Commits only inside one disposæble fixture repository.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
commit_fixture_baseline() {
  local root="$1"

  GIT_AUTHOR_NAME=Fixture \
    GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=Fixture \
    GIT_COMMITTER_EMAIL=fixture@example.invalid \
    git -C "$root" commit --quiet -m baseline
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_pre_commit_repo
#   Creætes æ committed checker bæseline inside one fixture.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - optionæl checker pæth to omit from the bæseline
#ææææææææææææææææææææææææææææææææææ
prepare_pre_commit_repo() {
  local root="$1"
  local omitted_path="${2:-}"

  install_pre_commit_tools "$root" "$omitted_path"
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_build_context_repo
#   Creætes æ two-æpp fixture with one consumed PostgreSQL templæte.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
prepare_build_context_repo() {
  local root="$1"

  install_pre_commit_tools "$root"
  write_build_context_trace_stub "$root"
  mkdir -p -- \
    "$root/AppOne/dockerfiles" \
    "$root/AppTwo/dockerfiles" \
    "$root/templates/postgresql/dockerfiles"
  printf '%s\n' \
    'x-required-services:' \
    '  - postgresql' \
    'services: {}' >"$root/AppOne/docker-compose.app.yaml"
  printf '%s\n' \
    'x-required-services: []' \
    'services: {}' >"$root/AppTwo/docker-compose.app.yaml"
  printf '%s\n' \
    'services:' \
    '  postgresql:' \
    '    image: postgres:18' >"$root/templates/postgresql/docker-compose.postgresql.yaml"
  printf 'FROM scratch\n' >"$root/templates/postgresql/dockerfiles/dockerfile.postgresql"
  git -C "$root" add --all --force
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_success
#   Runs one cæse ænd expects the stæged checker to succeed.
#   Ærguments:
#     $1 - cæse næme
#     $@ - fixture commænd
#ææææææææææææææææææææææææææææææææææ
expect_success() {
  local name="$1"
  local status=0
  shift

  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status == 0 )); then
    pass "$name"
  else
    fail "$name"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: expect_failure
#   Runs one cæse ænd expects the stæged checker to fæil closed.
#   Ærguments:
#     $1 - cæse næme
#     $@ - fixture commænd
#ææææææææææææææææææææææææææææææææææ
expect_failure() {
  local name="$1"
  local status=0
  shift

  set +e
  ( set -e; "$@" ) >"${TEST_ROOT}/${name}.out" 2>&1
  status=$?
  set -e
  if (( status != 0 )); then
    pass "$name"
  else
    fail "$name"
  fi
}

case_exact_placeholder() {
  local root=""
  root="$(create_case_repo exact-placeholder)"
  printf 'CHANGE_ME' >"$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash "$CHECKER")
}

case_nested_placeholders() {
  local root=""
  root="$(create_case_repo nested-placeholders)"
  mkdir -p -- "$root/templates/demo/secrets"
  printf 'CHANGE_ME' >"$root/secrets/APP_PASSWORD"
  printf 'CHANGE_ME' >"$root/templates/demo/secrets/DB_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD templates/demo/secrets/DB_PASSWORD
  (cd -- "$root" && bash "$CHECKER")
}

case_gitkeep_and_unrelated() {
  local root=""
  root="$(create_case_repo gitkeep-and-unrelated)"
  : >"$root/secrets/.gitkeep"
  printf 'ordinary content\n' >"$root/README.md"
  git -C "$root" add -- secrets/.gitkeep README.md
  (cd -- "$root" && bash "$CHECKER")
}

case_real_secret() {
  local root=""
  root="$(create_case_repo real-secret)"
  printf 'production-password' >"$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash "$CHECKER")
}

case_trailing_newline() {
  local root=""
  root="$(create_case_repo trailing-newline)"
  printf 'CHANGE_ME\n' >"$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash "$CHECKER")
}

case_executable_secret() {
  local root=""
  root="$(create_case_repo executable-secret)"
  printf 'CHANGE_ME' >"$root/secrets/APP_PASSWORD"
  chmod 0700 -- "$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash "$CHECKER")
}

case_symlink_secret() {
  local root=""
  root="$(create_case_repo symlink-secret)"
  printf 'CHANGE_ME' >"$root/outside"
  ln -s -- ../outside "$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash "$CHECKER")
}

case_pre_commit_accepts_placeholder() {
  local root=""
  root="$(create_case_repo pre-commit-accepts-placeholder)"
  prepare_pre_commit_repo "$root"
  printf 'CHANGE_ME' >"$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_rejects_real_secret() {
  local root=""
  root="$(create_case_repo pre-commit-rejects-real-secret)"
  prepare_pre_commit_repo "$root"
  printf 'production-password' >"$root/secrets/APP_PASSWORD"
  git -C "$root" add -- secrets/APP_PASSWORD
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_rejects_bad_staged_good_worktree() {
  local root=""
  root="$(create_case_repo pre-commit-rejects-bad-staged-good-worktree)"
  prepare_pre_commit_repo "$root"
  printf '# Actual alpha documentation\n' >"$root/README.md"
  git -C "$root" add -- README.md
  printf '# Æctuæl ælphæ documentætion\n' >"$root/README.md"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_accepts_good_staged_bad_worktree() {
  local root=""
  root="$(create_case_repo pre-commit-accepts-good-staged-bad-worktree)"
  prepare_pre_commit_repo "$root"
  printf '# Æctuæl ælphæ documentætion\n' >"$root/README.md"
  git -C "$root" add -- README.md
  printf '# Actual alpha documentation\n' >"$root/README.md"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_uses_staged_new_checker() {
  local checker_path=".cursor/scripts/test-hardening.py"
  local root=""
  root="$(create_case_repo pre-commit-uses-staged-new-checker)"
  prepare_pre_commit_repo "$root" "$checker_path"
  write_python_stub "$root" "$checker_path" 0
  git -C "$root" add -- "$checker_path"
  rm -f -- "$root/$checker_path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_uses_staged_changed_checker() {
  local checker_path=".cursor/scripts/test-hardening.py"
  local root=""
  root="$(create_case_repo pre-commit-uses-staged-changed-checker)"
  prepare_pre_commit_repo "$root"
  write_python_stub "$root" "$checker_path" 23
  git -C "$root" add -- "$checker_path"
  write_python_stub "$root" "$checker_path" 0
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_rejects_missing_staged_checker() {
  local checker_path=".cursor/scripts/check-hardening.py"
  local root=""
  root="$(create_case_repo pre-commit-rejects-missing-staged-checker)"
  prepare_pre_commit_repo "$root"
  git -C "$root" rm --quiet --cached -- "$checker_path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_cleans_success_snapshot() {
  local hook_tmp=""
  local root=""
  local -a leftovers=()
  root="$(create_case_repo pre-commit-cleans-success-snapshot)"
  prepare_pre_commit_repo "$root"
  printf '# Æctuæl ælphæ documentætion\n' >"$root/README.md"
  git -C "$root" add -- README.md
  hook_tmp="$root/hook-tmp"
  mkdir -p -- "$hook_tmp"
  (cd -- "$root" && TMPDIR="$hook_tmp" bash .githooks/pre-commit)
  shopt -s nullglob
  leftovers=("$hook_tmp"/pre-commit-index.*)
  shopt -u nullglob
  (( ${#leftovers[@]} == 0 ))
}

case_pre_commit_cleans_failed_snapshot() {
  local checker_path=".cursor/scripts/check-hardening.py"
  local hook_status=0
  local hook_tmp=""
  local root=""
  local -a leftovers=()
  root="$(create_case_repo pre-commit-cleans-failed-snapshot)"
  prepare_pre_commit_repo "$root"
  git -C "$root" rm --quiet --cached -- "$checker_path"
  hook_tmp="$root/hook-tmp"
  mkdir -p -- "$hook_tmp"
  set +e
  (cd -- "$root" && TMPDIR="$hook_tmp" bash .githooks/pre-commit)
  hook_status=$?
  set -e
  (( hook_status != 0 )) || return 1
  shopt -s nullglob
  leftovers=("$hook_tmp"/pre-commit-index.*)
  shopt -u nullglob
  (( ${#leftovers[@]} == 0 ))
}

case_pre_commit_rejects_staged_alternate_hook() {
  local root=""
  root="$(create_case_repo pre-commit-rejects-staged-alternate-hook)"
  prepare_pre_commit_repo "$root"
  printf '\n# Stæged ælternæte hook bytes\n' >>"$root/.githooks/pre-commit"
  git -C "$root" add -- .githooks/pre-commit
  cp -- "$PRE_COMMIT_HOOK" "$root/.githooks/pre-commit"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_rejects_unstaged_hook_tail() {
  local root=""
  root="$(create_case_repo pre-commit-rejects-unstaged-hook-tail)"
  prepare_pre_commit_repo "$root"
  printf '\n# Fully stæged hook bytes\n' >>"$root/.githooks/pre-commit"
  git -C "$root" add -- .githooks/pre-commit
  printf '# Extræ unstæged hook bytes\n' >>"$root/.githooks/pre-commit"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_accepts_identical_staged_hook() {
  local root=""
  root="$(create_case_repo pre-commit-accepts-identical-staged-hook)"
  prepare_pre_commit_repo "$root"
  printf '\n# Fully stæged hook bytes\n' >>"$root/.githooks/pre-commit"
  git -C "$root" add -- .githooks/pre-commit
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=.githooks/pre-commit PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_shellcheck_host_success() {
  local root=""
  root="$(create_case_repo pre-commit-shellcheck-host-success)"
  prepare_pre_commit_repo "$root"
  stage_shell_fixture "$root"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=fixture.sh PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_shellcheck_host_failure() {
  local root=""
  root="$(create_case_repo pre-commit-shellcheck-host-failure)"
  prepare_pre_commit_repo "$root"
  stage_shell_fixture "$root"
  write_shellcheck_stub "$root" 23
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=fixture.sh PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_shellcheck_container_success() {
  local isolated_path=""
  local root=""
  root="$(create_case_repo pre-commit-shellcheck-container-success)"
  prepare_pre_commit_repo "$root"
  stage_shell_fixture "$root"
  isolated_path="$(create_isolated_tool_path "$root" success)"
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=fixture.sh PATH="$isolated_path" bash .githooks/pre-commit)
}

case_pre_commit_shellcheck_container_failure() {
  local isolated_path=""
  local root=""
  root="$(create_case_repo pre-commit-shellcheck-container-failure)"
  prepare_pre_commit_repo "$root"
  stage_shell_fixture "$root"
  isolated_path="$(create_isolated_tool_path "$root" failure)"
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=fixture.sh PATH="$isolated_path" bash .githooks/pre-commit)
}

case_pre_commit_shellcheck_tools_missing() {
  local isolated_path=""
  local root=""
  root="$(create_case_repo pre-commit-shellcheck-tools-missing)"
  prepare_pre_commit_repo "$root"
  stage_shell_fixture "$root"
  isolated_path="$(create_isolated_tool_path "$root" missing)"
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=fixture.sh PATH="$isolated_path" bash .githooks/pre-commit)
}

case_pre_commit_ignores_unstaged_shell() {
  local root=""
  root="$(create_case_repo pre-commit-ignores-unstaged-shell)"
  prepare_pre_commit_repo "$root"
  printf '# Æctuæl fixture\n' >"$root/README.md"
  git -C "$root" add -- README.md
  write_shellcheck_stub "$root" 47
  (cd -- "$root" && PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_clears_parent_git_environment() {
  local checker=".cursor/scripts/test-hardening.py"
  local root=""
  root="$(create_case_repo pre-commit-clears-parent-git-environment)"
  prepare_pre_commit_repo "$root"
  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import os' \
    'raise SystemExit(1 if os.environ.get("GIT_CONFIG_PARAMETERS") else 0)' >"$root/$checker"
  chmod 0755 -- "$root/$checker"
  git -C "$root" add -- "$checker"
  (cd -- "$root" && GIT_CONFIG_PARAMETERS="'core.hooksPath'='.githooks'" bash .githooks/pre-commit)
}

case_pre_commit_build_tooling_runs_synthetics_only() {
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-build-tooling-runs-synthetics-only)"
  prepare_build_context_repo "$root"
  printf '\n' >>"$root/.cursor/scripts/test-build-contexts.py"
  git -C "$root" add -- .cursor/scripts/test-build-contexts.py
  trace="$root/build-context.trace"
  (cd -- "$root" && BUILD_CONTEXT_TRACE="$trace" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == '0:' ]]
}

case_pre_commit_build_topology_targets_direct_app() {
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-build-topology-targets-direct-app)"
  prepare_build_context_repo "$root"
  printf '*\n!.dockerignore\n' >"$root/AppOne/dockerfiles/.dockerignore"
  git -C "$root" add -- AppOne/dockerfiles/.dockerignore
  trace="$root/build-context.trace"
  (cd -- "$root" && BUILD_CONTEXT_TRACE="$trace" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == '1:AppOne' ]]
}

case_pre_commit_template_topology_runs_synthetics_only() {
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-template-topology-runs-synthetics-only)"
  prepare_build_context_repo "$root"
  printf 'FROM scratch\nRUN true\n' >"$root/templates/postgresql/dockerfiles/dockerfile.postgresql"
  git -C "$root" add -- templates/postgresql/dockerfiles/dockerfile.postgresql
  trace="$root/build-context.trace"
  (cd -- "$root" && BUILD_CONTEXT_TRACE="$trace" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == '0:' ]]
}

case_pre_commit_build_helper_does_not_trigger_context_suite() {
  local root=""
  local trace=""
  local helper="templates/postgresql/dockerfiles/helper.postgresql.sh"
  root="$(create_case_repo pre-commit-build-helper-does-not-trigger-context-suite)"
  prepare_build_context_repo "$root"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/$helper"
  git -C "$root" add -- "$helper"
  write_shellcheck_stub "$root" 0
  trace="$root/build-context.trace"
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES="$helper" BUILD_CONTEXT_TRACE="$trace" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
  [[ ! -e "$trace" ]]
}

case_pre_commit_run_runs_synthetic_context_suite() {
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-run-does-not-trigger-context-suite)"
  prepare_build_context_repo "$root"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/run.sh"
  git -C "$root" add -- run.sh
  write_shellcheck_stub "$root" 0
  trace="$root/build-context.trace"
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES=run.sh BUILD_CONTEXT_TRACE="$trace" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == '0:' ]]
}

case_pre_commit_rules_do_not_trigger_integration_suites() {
  local root=""
  local checker=""
  root="$(create_case_repo pre-commit-rules-do-not-trigger-integration-suites)"
  install_pre_commit_tools "$root"
  for checker in \
    .cursor/scripts/test-crowdsec-agent-wrapper.sh \
    .cursor/scripts/test-crowdsec-parser-whitelists.sh \
    .cursor/scripts/test-collabora-wrapper.sh \
    .cursor/scripts/test-kimai-wrapper.sh \
    .cursor/scripts/test-redis-secret-runtime.sh \
    .cursor/scripts/test-mariadb-maintenance-safety.sh \
    .cursor/scripts/test-postgresql-maintenance-safety.sh \
    .cursor/scripts/test-run-logrotate.sh \
    .cursor/scripts/test-secret-preflights.sh; do
    write_shell_stub "$root" "$checker" 71
  done
  git -C "$root" add --all --force
  commit_fixture_baseline "$root"
  mkdir -p -- "$root/.cursor/rules"
  printf '# Æudit fixture\n' >"$root/.cursor/rules/project-audit.mdc"
  printf '# Host logrotæte fixture\n' >"$root/.cursor/rules/host-logrotate.mdc"
  printf '# Dætæbæse fixture\n' >"$root/.cursor/rules/database-maintenance.mdc"
  git -C "$root" add -- .cursor/rules/project-audit.mdc .cursor/rules/database-maintenance.mdc .cursor/rules/host-logrotate.mdc
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_run_test_does_not_self_trigger() {
  local checker=".cursor/scripts/test-run-transaction.sh"
  local root=""
  root="$(create_case_repo pre-commit-run-test-does-not-self-trigger)"
  prepare_pre_commit_repo "$root"
  write_shell_stub "$root" "$checker" 71
  git -C "$root" add -- "$checker"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES="$checker" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_source_sync_test_does_not_self_trigger() {
  local checker=".cursor/scripts/test-run-source-sync.sh"
  local root=""
  root="$(create_case_repo pre-commit-source-sync-test-does-not-self-trigger)"
  prepare_pre_commit_repo "$root"
  write_shell_stub "$root" "$checker" 71
  git -C "$root" add -- "$checker"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES="$checker" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_run_triggers_logrotate_suite() {
  local checker=".cursor/scripts/test-run-logrotate.sh"
  local root=""
  root="$(create_case_repo pre-commit-run-triggers-logrotate-suite)"
  prepare_pre_commit_repo "$root"
  write_shell_stub "$root" "$checker" 71
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/run.sh"
  git -C "$root" add -- run.sh "$checker"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES="run.sh,$checker" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_logrotate_test_does_not_self_trigger() {
  local checker=".cursor/scripts/test-run-logrotate.sh"
  local root=""
  root="$(create_case_repo pre-commit-logrotate-test-does-not-self-trigger)"
  prepare_pre_commit_repo "$root"
  write_shell_stub "$root" "$checker" 71
  git -C "$root" add -- "$checker"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES="$checker" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_integration_test_does_not_self_trigger() {
  local checker=".cursor/scripts/test-kimai-wrapper.sh"
  local root=""
  root="$(create_case_repo pre-commit-integration-test-does-not-self-trigger)"
  prepare_pre_commit_repo "$root"
  write_shell_stub "$root" "$checker" 71
  git -C "$root" add -- "$checker"
  write_shellcheck_stub "$root" 0
  (cd -- "$root" && EXPECTED_SHELLCHECK_FILES="$checker" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
}

case_pre_commit_honors_alternate_index() {
  local alternate_hash=""
  local default_hash=""
  local root=""
  local worktree_hash=""
  root="$(create_case_repo pre-commit-honors-alternate-index)"
  prepare_pre_commit_repo "$root"
  cp -- "$root/.git/index" "$root/alternate-index"
  printf '# Æctuæl stæged documentætion\n' >"$root/README.md"
  (cd -- "$root" && GIT_INDEX_FILE=alternate-index git add -- README.md)
  printf '# Actual unstaged documentation\n' >"$root/README.md"
  default_hash="$(git hash-object "$root/.git/index")"
  alternate_hash="$(git hash-object "$root/alternate-index")"
  worktree_hash="$(git hash-object "$root/README.md")"

  (cd -- "$root" && GIT_INDEX_FILE=alternate-index bash .githooks/pre-commit)

  [[ "$(git hash-object "$root/.git/index")" == "$default_hash" ]]
  [[ "$(git hash-object "$root/alternate-index")" == "$alternate_hash" ]]
  [[ "$(git hash-object "$root/README.md")" == "$worktree_hash" ]]
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- TEST MÆTRIX
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

expect_success exact-placeholder case_exact_placeholder
expect_success nested-placeholders case_nested_placeholders
expect_success gitkeep-and-unrelated case_gitkeep_and_unrelated
expect_failure real-secret case_real_secret
expect_failure trailing-newline case_trailing_newline
expect_failure executable-secret case_executable_secret
expect_failure symlink-secret case_symlink_secret
expect_success pre-commit-accepts-placeholder case_pre_commit_accepts_placeholder
expect_failure pre-commit-rejects-real-secret case_pre_commit_rejects_real_secret
expect_failure pre-commit-rejects-bad-staged-good-worktree case_pre_commit_rejects_bad_staged_good_worktree
expect_success pre-commit-accepts-good-staged-bad-worktree case_pre_commit_accepts_good_staged_bad_worktree
expect_success pre-commit-uses-staged-new-checker case_pre_commit_uses_staged_new_checker
expect_failure pre-commit-uses-staged-changed-checker case_pre_commit_uses_staged_changed_checker
expect_failure pre-commit-rejects-missing-staged-checker case_pre_commit_rejects_missing_staged_checker
expect_success pre-commit-cleans-success-snapshot case_pre_commit_cleans_success_snapshot
expect_success pre-commit-cleans-failed-snapshot case_pre_commit_cleans_failed_snapshot
expect_failure pre-commit-rejects-staged-alternate-hook case_pre_commit_rejects_staged_alternate_hook
expect_failure pre-commit-rejects-unstaged-hook-tail case_pre_commit_rejects_unstaged_hook_tail
expect_success pre-commit-accepts-identical-staged-hook case_pre_commit_accepts_identical_staged_hook
expect_success pre-commit-shellcheck-host-success case_pre_commit_shellcheck_host_success
expect_failure pre-commit-shellcheck-host-failure case_pre_commit_shellcheck_host_failure
expect_success pre-commit-shellcheck-container-success case_pre_commit_shellcheck_container_success
expect_failure pre-commit-shellcheck-container-failure case_pre_commit_shellcheck_container_failure
expect_failure pre-commit-shellcheck-tools-missing case_pre_commit_shellcheck_tools_missing
expect_success pre-commit-ignores-unstaged-shell case_pre_commit_ignores_unstaged_shell
expect_success pre-commit-clears-parent-git-environment case_pre_commit_clears_parent_git_environment
expect_success pre-commit-build-tooling-runs-synthetics-only case_pre_commit_build_tooling_runs_synthetics_only
expect_success pre-commit-build-topology-targets-direct-app case_pre_commit_build_topology_targets_direct_app
expect_success pre-commit-template-topology-runs-synthetics-only case_pre_commit_template_topology_runs_synthetics_only
expect_success pre-commit-build-helper-does-not-trigger-context-suite case_pre_commit_build_helper_does_not_trigger_context_suite
expect_success pre-commit-run-runs-synthetic-context-suite case_pre_commit_run_runs_synthetic_context_suite
expect_success pre-commit-rules-do-not-trigger-integration-suites case_pre_commit_rules_do_not_trigger_integration_suites
expect_success pre-commit-run-test-does-not-self-trigger case_pre_commit_run_test_does_not_self_trigger
expect_success pre-commit-source-sync-test-does-not-self-trigger case_pre_commit_source_sync_test_does_not_self_trigger
expect_failure pre-commit-run-triggers-logrotate-suite case_pre_commit_run_triggers_logrotate_suite
expect_success pre-commit-logrotate-test-does-not-self-trigger case_pre_commit_logrotate_test_does_not_self_trigger
expect_success pre-commit-integration-test-does-not-self-trigger case_pre_commit_integration_test_does_not_self_trigger
expect_success pre-commit-honors-alternate-index case_pre_commit_honors_alternate_index

printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
