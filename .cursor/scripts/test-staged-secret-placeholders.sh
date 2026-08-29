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
readonly HARDENING_CHECKER="${TEST_SCRIPT_DIR}/check-hardening.py"
readonly PRE_COMMIT_HOOK="${TEST_SCRIPT_DIR}/../../.githooks/pre-commit"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/staged-secret-placeholders.XXXXXX")"
readonly -a REQUIRED_PYTHON_STUBS=(
  ".cursor/scripts/check-hardening.py"
  ".cursor/scripts/test-build-contexts.py"
  ".cursor/scripts/test-go-builder-contracts.py"
  ".cursor/scripts/test-erpnext-stack.py"
  ".cursor/scripts/test-gitea-vaultwarden-recovery.py"
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
  ".cursor/scripts/test-espocrm-bootstrap.sh"
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
# FUNCTION: write_hardening_trace_stub
#   Writes æ checker stub thæt records the exæct Compose tærgets from the hook.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
write_hardening_trace_stub() {
  local root="$1"
  local target="${root}/.cursor/scripts/check-hardening.py"

  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import os' \
    'from pathlib import Path' \
    'import sys' \
    '' \
    'Path(os.environ["HARDENING_TRACE"]).write_text("\n".join(sys.argv[1:]) + "\n", encoding="utf-8")' \
    >"$target"
  chmod 0755 -- "$target"
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
# FUNCTION: write_go_builder_contract_trace_stub
#   Writes æ Go-builder stub thæt records exæct tærgets ænd snæpshot bytes.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
write_go_builder_contract_trace_stub() {
  local root="$1"
  local exit_status="$2"
  local target="${root}/.cursor/scripts/test-go-builder-contracts.py"

  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import argparse' \
    'import os' \
    'from pathlib import Path' \
    '' \
    'parser = argparse.ArgumentParser()' \
    'parser.add_argument("--target", action="append", default=None)' \
    'parser.add_argument("--synthetic-only", action="store_true")' \
    'args = parser.parse_args()' \
    'trace = os.environ.get("GO_BUILDER_CONTRACT_TRACE")' \
    'if trace:' \
    '    payload = "synthetic-only" if args.synthetic_only else ",".join(args.target or [])' \
    '    Path(trace).write_text(payload, encoding="utf-8")' \
    'expected_path = os.environ.get("GO_BUILDER_EXPECTED_PATH")' \
    'expected_text = os.environ.get("GO_BUILDER_EXPECTED_TEXT")' \
    'if expected_path and Path(expected_path).read_text(encoding="utf-8") != f"{expected_text}\n":' \
    '    raise SystemExit(86)' \
    "raise SystemExit(${exit_status})" >"$target"
  chmod 0755 -- "$target"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_erpnext_trace_stub
#   Writes æn ERPNext checker stub thæt records exæct hook invocætion.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
write_erpnext_trace_stub() {
  local root="$1"
  local exit_status="$2"
  local target="${root}/.cursor/scripts/test-erpnext-stack.py"

  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import os' \
    'from pathlib import Path' \
    '' \
    'trace = os.environ.get("ERPNEXT_REGRESSION_TRACE")' \
    'if trace:' \
    '    Path(trace).write_text("called\n", encoding="utf-8")' \
    "raise SystemExit(${exit_status})" >"$target"
  chmod 0755 -- "$target"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_espocrm_bootstrap_trace_stub
#   Writes æn EspoCRM checker stub thæt records exæct hook invocætion.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
write_espocrm_bootstrap_trace_stub() {
  local root="$1"
  local exit_status="$2"
  local target="${root}/.cursor/scripts/test-espocrm-bootstrap.sh"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ -n "${ESPOCRM_BOOTSTRAP_TRACE:-}" ]]; then' \
    '  printf "called\\n" >>"$ESPOCRM_BOOTSTRAP_TRACE"' \
    'fi' \
    "exit ${exit_status}" >"$target"
  chmod 0755 -- "$target"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_gitea_vaultwarden_recovery_trace_stub
#   Writes æ recovery checker stub thæt records exæct hook invocætion.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
write_gitea_vaultwarden_recovery_trace_stub() {
  local root="$1"
  local exit_status="$2"
  local target="${root}/.cursor/scripts/test-gitea-vaultwarden-recovery.py"

  printf '%s\n' \
    '#!/usr/bin/env python3' \
    'import os' \
    'from pathlib import Path' \
    '' \
    'trace = os.environ.get("GITEA_VAULTWARDEN_RECOVERY_TRACE")' \
    'if trace:' \
    '    with Path(trace).open("a", encoding="utf-8") as stream:' \
    '        stream.write("called\n")' \
    "raise SystemExit(${exit_status})" >"$target"
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
# FUNCTION: prepare_hardening_hook_repo
#   Creætes æ committed Giteæ closure with æ træceæble hærdening checker.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
prepare_hardening_hook_repo() {
  local root="$1"

  install_pre_commit_tools "$root"
  write_hardening_trace_stub "$root"
  mkdir -p -- \
    "$root/Gitea" \
    "$root/templates/gitea-oidc" \
    "$root/templates/observer"
  printf '%s\n' \
    'x-required-services:' \
    '  - gitea-oidc' \
    '  - observer' \
    'services:' \
    '  app:' \
    '    image: local/gitea:1' >"$root/Gitea/docker-compose.app.yaml"
  printf '%s\n' \
    'services:' \
    '  gitea-oidc:' \
    '    image: local/gitea:1' \
    '    restart: "no"' \
    '    labels:' \
    '      de.saervices.run.completion-timeout-seconds: "600"' \
    '    depends_on:' \
    '      app:' \
    '        condition: service_healthy' >"$root/templates/gitea-oidc/docker-compose.gitea-oidc.yaml"
  printf '%s\n' \
    'services:' \
    '  observer:' \
    '    image: local/observer:1' \
    '    user: "1000:1000"' \
    '    read_only: true' \
    '    tmpfs:' \
    '      - /tmp:rw,nosuid,nodev,noexec,size=16m' \
    '    cap_drop:' \
    '      - ALL' \
    '    security_opt:' \
    '      - no-new-privileges:true' >"$root/templates/observer/docker-compose.observer.yaml"
  git -C "$root" add -- \
    .cursor/scripts/check-hardening.py \
    Gitea \
    templates/gitea-oidc \
    templates/observer
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_real_hardening_hook_repo
#   Creætes æ minimæl vælid Giteæ closure with the reæl stæged checker.
#   Ærguments:
#     $1 - fixture repository root
#ææææææææææææææææææææææææææææææææææ
prepare_real_hardening_hook_repo() {
  local root="$1"

  install_pre_commit_tools "$root"
  cp -- "$HARDENING_CHECKER" "$root/.cursor/scripts/check-hardening.py"
  chmod 0755 -- "$root/.cursor/scripts/check-hardening.py"
  mkdir -p -- "$root/Gitea" "$root/templates/gitea-oidc"
  printf '%s\n' \
    'x-required-services:' \
    '  - gitea-oidc' \
    'services:' \
    '  app:' \
    '    image: local/gitea:1' \
    '    user: "1000:1000"' \
    '    read_only: true' \
    '    tmpfs:' \
    '      - /tmp:rw,nosuid,nodev,noexec,size=16m' \
    '    cap_drop:' \
    '      - ALL' \
    '    security_opt:' \
    '      - no-new-privileges:true' >"$root/Gitea/docker-compose.app.yaml"
  printf '%s\n' \
    'services:' \
    '  gitea-oidc:' \
    '    image: local/gitea:1' \
    '    user: "1000:1000"' \
    '    restart: "no"' \
    '    read_only: true' \
    '    tmpfs:' \
    '      - /tmp:rw,nosuid,nodev,noexec,size=16m' \
    '    cap_drop:' \
    '      - ALL' \
    '    security_opt:' \
    '      - no-new-privileges:true' \
    '    labels:' \
    '      de.saervices.run.completion-timeout-seconds: "600"' \
    '    depends_on:' \
    '      app:' \
    '        condition: service_healthy' >"$root/templates/gitea-oidc/docker-compose.gitea-oidc.yaml"
  git -C "$root" add -- .cursor/scripts/check-hardening.py Gitea templates/gitea-oidc
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_erpnext_hook_repo
#   Creætes æ committed hook fixture with æ traceæble ERPNext checker.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
prepare_erpnext_hook_repo() {
  local root="$1"
  local exit_status="$2"

  install_pre_commit_tools "$root"
  write_erpnext_trace_stub "$root" "$exit_status"
  git -C "$root" add -- .cursor/scripts/test-erpnext-stack.py
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_espocrm_bootstrap_hook_repo
#   Creætes æ committed hook fixture with æ træceæble EspoCRM checker.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
prepare_espocrm_bootstrap_hook_repo() {
  local root="$1"
  local exit_status="$2"

  install_pre_commit_tools "$root"
  write_espocrm_bootstrap_trace_stub "$root" "$exit_status"
  git -C "$root" add -- .cursor/scripts/test-espocrm-bootstrap.sh
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_gitea_vaultwarden_recovery_hook_repo
#   Creætes æ committed hook fixture with æ træceæble recovery checker.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
prepare_gitea_vaultwarden_recovery_hook_repo() {
  local root="$1"
  local exit_status="$2"

  install_pre_commit_tools "$root"
  write_gitea_vaultwarden_recovery_trace_stub "$root" "$exit_status"
  git -C "$root" add -- .cursor/scripts/test-gitea-vaultwarden-recovery.py
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_go_builder_contract_hook_repo
#   Creætes æ committed hook fixture with æ traceæble Go-builder checker.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - checker exit stætus
#ææææææææææææææææææææææææææææææææææ
prepare_go_builder_contract_hook_repo() {
  local root="$1"
  local exit_status="$2"

  install_pre_commit_tools "$root"
  write_go_builder_contract_trace_stub "$root" "$exit_status"
  git -C "$root" add -- .cursor/scripts/test-go-builder-contracts.py
  commit_fixture_baseline "$root"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_go_builder_production_fixture
#   Writes one minimæl branded production-pæth fixture for hook selection.
#   Ærguments:
#     $1 - fixture repository root
#     $2 - repository-relætive production pæth
#ææææææææææææææææææææææææææææææææææ
write_go_builder_production_fixture() {
  local root="$1"
  local relative_path="$2"

  mkdir -p -- "$(dirname -- "${root}/${relative_path}")"
  case "$relative_path" in
    *.env)
      printf 'FIXTURE_VALUE=reviewed\n' >"${root}/${relative_path}"
      ;;
    *.yaml|*.yml)
      printf 'services: {}\n' >"${root}/${relative_path}"
      ;;
    *.go)
      printf '%s\n' \
        '// SPDX-License-Identifier: MIT' \
        'package main' >"${root}/${relative_path}"
      ;;
    */Dockerfile|*/dockerfile.*)
      printf '%s\n' \
        '# SPDX-License-Identifier: MIT' \
        'FROM scratch' >"${root}/${relative_path}"
      ;;
    *)
      return 1
      ;;
  esac
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

case_pre_commit_hardening_targets_each_gitea_closure_compose() {
  local path=""
  local root=""
  local trace=""
  local index=0
  local -a paths=(
    "Gitea/docker-compose.app.yaml"
    "templates/gitea-oidc/docker-compose.gitea-oidc.yaml"
  )

  for path in "${paths[@]}"; do
    root="$(create_case_repo "pre-commit-hardening-target-${index}")"
    prepare_hardening_hook_repo "$root"
    printf '\n' >>"$root/$path"
    git -C "$root" add -- "$path"
    trace="$root/hardening.trace"
    (cd -- "$root" && HARDENING_TRACE="$trace" bash .githooks/pre-commit)
    [[ "$(<"$trace")" == $'--quiet\n'"$path" ]]
    index=$((index + 1))
  done
}

case_pre_commit_hardening_does_not_skip_deleted_gitea_compose() {
  local path=""
  local root=""
  local trace=""
  local index=0
  local -a paths=(
    "Gitea/docker-compose.app.yaml"
    "templates/gitea-oidc/docker-compose.gitea-oidc.yaml"
  )

  for path in "${paths[@]}"; do
    root="$(create_case_repo "pre-commit-hardening-deleted-${index}")"
    prepare_hardening_hook_repo "$root"
    git -C "$root" rm --quiet -- "$path"
    trace="$root/hardening.trace"
    (cd -- "$root" && HARDENING_TRACE="$trace" bash .githooks/pre-commit)
    [[ "$(<"$trace")" == $'--quiet\n'"$path" ]]
    index=$((index + 1))
  done
}

case_pre_commit_real_hardening_accepts_valid_template_only_change() {
  local path="templates/gitea-oidc/docker-compose.gitea-oidc.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-valid-template)"
  prepare_real_hardening_hook_repo "$root"
  printf '    stop_grace_period: 30s\n' >>"$root/$path"
  git -C "$root" add -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_duplicate_template_service() {
  local path="templates/gitea-oidc/docker-compose.gitea-oidc.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-duplicate-template)"
  prepare_real_hardening_hook_repo "$root"
  sed -i '/^  gitea-oidc:$/i\  gitea-oidc:\n    image: local/ignored:1' "$root/$path"
  git -C "$root" add -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_interpolated_app_reference() {
  local path="Gitea/docker-compose.app.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-interpolated-app)"
  prepare_real_hardening_hook_repo "$root"
  printf '    network_mode: ${OIDC_MODE:-service:gitea-oidc}\n' >>"$root/$path"
  git -C "$root" add -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_app_include() {
  local path="Gitea/docker-compose.app.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-app-include)"
  prepare_real_hardening_hook_repo "$root"
  sed -i '1iinclude:\n  - observer.yaml' "$root/$path"
  git -C "$root" add -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_app_extends() {
  local path="Gitea/docker-compose.app.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-app-extends)"
  prepare_real_hardening_hook_repo "$root"
  printf '    extends:\n      file: observer.yaml\n      service: observer\n' >>"$root/$path"
  git -C "$root" add -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_required_template_consumer() {
  local path="templates/observer/docker-compose.observer.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-required-consumer)"
  prepare_real_hardening_hook_repo "$root"
  printf '    network_mode: service:gitea-oidc\n' >>"$root/$path"
  git -C "$root" add -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_deleted_required_template() {
  local path="templates/observer/docker-compose.observer.yaml"
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-deleted-required)"
  prepare_real_hardening_hook_repo "$root"
  git -C "$root" rm --quiet -- "$path"
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_real_hardening_rejects_symlinked_required_template_parent() {
  local root=""

  root="$(create_case_repo pre-commit-real-hardening-symlinked-required-parent)"
  prepare_real_hardening_hook_repo "$root"
  mkdir -p -- "$root/templates/observer-target"
  mv -- \
    "$root/templates/observer/docker-compose.observer.yaml" \
    "$root/templates/observer-target/docker-compose.observer.yaml"
  rmdir -- "$root/templates/observer"
  ln -s -- observer-target "$root/templates/observer"
  git -C "$root" add --all --force -- templates/observer templates/observer-target
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_rejects_missing_erpnext_checker() {
  local checker_path=".cursor/scripts/test-erpnext-stack.py"
  local root=""
  root="$(create_case_repo pre-commit-rejects-missing-erpnext-checker)"
  prepare_pre_commit_repo "$root" "$checker_path"
  printf '# Æctuæl ERPNext fixture\n' >"$root/README.md"
  git -C "$root" add -- README.md
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_uses_staged_new_erpnext_checker() {
  local checker_path=".cursor/scripts/test-erpnext-stack.py"
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-uses-staged-new-erpnext-checker)"
  prepare_pre_commit_repo "$root" "$checker_path"
  write_erpnext_trace_stub "$root" 0
  mkdir -p -- "$root/ERPNext/config"
  printf 'server { listen 8080; }\n' >"$root/ERPNext/config/nginx-frappe.conf.template"
  git -C "$root" add -- "$checker_path" ERPNext/config/nginx-frappe.conf.template
  rm -f -- "$root/$checker_path"
  trace="$root/erpnext.trace"
  (cd -- "$root" && ERPNEXT_REGRESSION_TRACE="$trace" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == called ]]
}

case_pre_commit_uses_staged_changed_erpnext_checker() {
  local checker_path=".cursor/scripts/test-erpnext-stack.py"
  local root=""
  root="$(create_case_repo pre-commit-uses-staged-changed-erpnext-checker)"
  prepare_pre_commit_repo "$root"
  write_erpnext_trace_stub "$root" 23
  mkdir -p -- "$root/ERPNext/config"
  printf 'server { listen 8080; }\n' >"$root/ERPNext/config/nginx-frappe.conf.template"
  git -C "$root" add -- "$checker_path" ERPNext/config/nginx-frappe.conf.template
  write_erpnext_trace_stub "$root" 0
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_erpnext_production_paths_trigger() {
  local index=0
  local path=""
  local root=""
  local trace=""
  local -a paths=(
    "ERPNext/config/nginx-frappe.conf.template"
    "templates/erpnext-backend/.env"
    "templates/mariadb/.env"
    "templates/mariadb_maintenance/.env"
  )
  local -a payloads=(
    "server { listen 8080; }"
    "ERPNEXT_BACKEND_MEM_LIMIT=1g"
    "MARIADB_IMAGE=mariadb:12"
    "MARIADB_MEM_LIMIT=1g"
  )

  for index in "${!paths[@]}"; do
    path="${paths[index]}"
    root="$(create_case_repo "pre-commit-erpnext-path-${index}")"
    prepare_erpnext_hook_repo "$root" 0
    mkdir -p -- "$(dirname -- "$root/$path")"
    printf '%s\n' "${payloads[index]}" >"$root/$path"
    git -C "$root" add -- "$path"
    trace="$root/erpnext.trace"
    (cd -- "$root" && ERPNEXT_REGRESSION_TRACE="$trace" bash .githooks/pre-commit)
    [[ "$(<"$trace")" == called ]]
  done
}

case_pre_commit_erpnext_metadata_does_not_self_trigger() {
  local checker_path=".cursor/scripts/test-erpnext-stack.py"
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-erpnext-metadata-does-not-self-trigger)"
  prepare_pre_commit_repo "$root"
  write_erpnext_trace_stub "$root" 71
  mkdir -p -- "$root/.cursor/rules"
  printf '# ERPNext æpplicætion mæintenænce fixture\n' >"$root/.cursor/rules/application-maintenance.mdc"
  printf '# ERPNext dætæbæse fixture\n' >"$root/.cursor/rules/database-maintenance.mdc"
  printf '# ERPNext æudit fixture\n' >"$root/.cursor/rules/project-audit.mdc"
  git -C "$root" add -- \
    "$checker_path" \
    .cursor/rules/application-maintenance.mdc \
    .cursor/rules/database-maintenance.mdc \
    .cursor/rules/project-audit.mdc
  trace="$root/erpnext.trace"
  (cd -- "$root" && ERPNEXT_REGRESSION_TRACE="$trace" bash .githooks/pre-commit)
  [[ ! -e "$trace" ]]
}

case_pre_commit_rejects_missing_go_builder_contract_checker() {
  local checker_path=".cursor/scripts/test-go-builder-contracts.py"
  local root=""
  root="$(create_case_repo pre-commit-rejects-missing-go-builder-contract-checker)"
  prepare_pre_commit_repo "$root" "$checker_path"
  printf '# Æctuæl Go-builder documentætion fixture\n' >"$root/README.md"
  git -C "$root" add -- README.md
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_go_builder_production_paths_trigger_exact_targets() {
  local index=0
  local path=""
  local root=""
  local trace=""
  local -a paths=(
    "Traefik/.env"
    "Traefik/docker-compose.app.yaml"
    "Traefik/dockerfiles/Dockerfile"
    "templates/traefik_certs-dumper/.env"
    "templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml"
    "templates/traefik_certs-dumper/dockerfiles/dockerfile.traefik-certs-dumper.scp"
    "Grafana/.env"
    "Grafana/docker-compose.app.yaml"
    "Grafana/dockerfiles/Dockerfile"
    "Grafana/dockerfiles/grafana-entrypoint.go"
    "Grafana/dockerfiles/grafana-entrypoint_test.go"
    "templates/grafana-sso-policy/.env"
    "templates/grafana-sso-policy/docker-compose.grafana-sso-policy.yaml"
    "templates/grafana-sso-policy/dockerfiles/dockerfile.grafana-sso-policy"
    "templates/grafana-sso-policy/dockerfiles/grafana-entrypoint.grafana-sso-policy.go"
    "templates/grafana-sso-policy/dockerfiles/grafana-entrypoint.grafana-sso-policy_test.go"
    "Gitea/.env"
    "Gitea/docker-compose.app.yaml"
    "Gitea/dockerfiles/Dockerfile"
    "Gitea/dockerfiles/gitea-secret-reader.go"
    "Gitea/dockerfiles/gitea-secret-reader_test.go"
  )
  local -a targets=(
    "traefik-reader"
    "traefik-reader"
    "traefik-reader"
    "traefik-certs-dumper"
    "traefik-certs-dumper"
    "traefik-certs-dumper"
    "grafana-helper"
    "grafana-helper"
    "grafana-helper"
    "grafana-helper"
    "grafana-helper"
    "grafana-sso-policy"
    "grafana-sso-policy"
    "grafana-sso-policy"
    "grafana-sso-policy"
    "grafana-sso-policy"
    "gitea-secret-reader"
    "gitea-secret-reader"
    "gitea-secret-reader"
    "gitea-secret-reader"
    "gitea-secret-reader"
  )

  for index in "${!paths[@]}"; do
    path="${paths[index]}"
    root="$(create_case_repo "pre-commit-go-builder-path-${index}")"
    prepare_go_builder_contract_hook_repo "$root" 0
    write_go_builder_production_fixture "$root" "$path"
    git -C "$root" add -- "$path"
    trace="$root/go-builder-contract.trace"
    (cd -- "$root" && GO_BUILDER_CONTRACT_TRACE="$trace" bash .githooks/pre-commit)
    [[ "$(<"$trace")" == "${targets[index]}" ]]
  done
}

case_pre_commit_go_builder_combines_sorted_unique_targets() {
  local root=""
  local trace=""
  local path=""
  local -a paths=(
    "Traefik/.env"
    "Traefik/dockerfiles/Dockerfile"
    "templates/traefik_certs-dumper/.env"
    "Grafana/.env"
    "Grafana/dockerfiles/grafana-entrypoint.go"
    "templates/grafana-sso-policy/.env"
    "Gitea/.env"
    "Gitea/dockerfiles/gitea-secret-reader.go"
  )
  root="$(create_case_repo pre-commit-go-builder-combines-sorted-unique-targets)"
  prepare_go_builder_contract_hook_repo "$root" 0
  for path in "${paths[@]}"; do
    write_go_builder_production_fixture "$root" "$path"
  done
  git -C "$root" add -- "${paths[@]}"
  trace="$root/go-builder-contract.trace"
  (cd -- "$root" && GO_BUILDER_CONTRACT_TRACE="$trace" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == 'gitea-secret-reader,grafana-helper,grafana-sso-policy,traefik-certs-dumper,traefik-reader' ]]
}

case_pre_commit_go_builder_checker_self_stage_runs_synthetics_only() {
  local checker_path=".cursor/scripts/test-go-builder-contracts.py"
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-go-builder-checker-self-stage-runs-synthetics-only)"
  prepare_pre_commit_repo "$root"
  write_go_builder_contract_trace_stub "$root" 0
  git -C "$root" add -- "$checker_path"
  write_python_stub "$root" "$checker_path" 71
  trace="$root/go-builder-contract.trace"
  (cd -- "$root" && GO_BUILDER_CONTRACT_TRACE="$trace" bash .githooks/pre-commit)
  [[ "$(<"$trace")" == synthetic-only ]]
}

case_pre_commit_go_builder_foreign_and_metadata_paths_do_not_trigger() {
  local root=""
  local trace=""
  local path=""
  local -a paths=(
    "templates/collabora/.env"
    "RustDesk/.env"
    "templates/matrix-livekit-jwt/.env"
  )
  root="$(create_case_repo pre-commit-go-builder-foreign-and-metadata-paths-do-not-trigger)"
  prepare_go_builder_contract_hook_repo "$root" 71
  for path in "${paths[@]}"; do
    write_go_builder_production_fixture "$root" "$path"
  done
  mkdir -p -- "$root/.cursor/rules"
  printf '# Æctuæl Go-builder rule fixture\n' >"$root/.cursor/rules/validation.mdc"
  printf '# Æctuæl Go-builder documentætion fixture\n' >"$root/.cursor/README.md"
  git -C "$root" add -- "${paths[@]}" .cursor/rules/validation.mdc .cursor/README.md
  trace="$root/go-builder-contract.trace"
  (cd -- "$root" && GO_BUILDER_CONTRACT_TRACE="$trace" bash .githooks/pre-commit)
  [[ ! -e "$trace" ]]
}

case_pre_commit_go_builder_failure_propagates() {
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-go-builder-failure-propagates)"
  prepare_go_builder_contract_hook_repo "$root" 29
  write_go_builder_production_fixture "$root" "Traefik/.env"
  git -C "$root" add -- Traefik/.env
  trace="$root/go-builder-contract.trace"
  (cd -- "$root" && GO_BUILDER_CONTRACT_TRACE="$trace" bash .githooks/pre-commit)
}

case_pre_commit_go_builder_reads_staged_product_bytes() {
  local root=""
  local trace=""
  root="$(create_case_repo pre-commit-go-builder-reads-staged-product-bytes)"
  prepare_go_builder_contract_hook_repo "$root" 0
  mkdir -p -- "$root/Traefik"
  printf 'TRAEFIK_GO_IMAGE=golang:alpine\n' >"$root/Traefik/.env"
  git -C "$root" add -- Traefik/.env
  printf 'TRAEFIK_GO_IMAGE=golang:1-alpine\n' >"$root/Traefik/.env"
  trace="$root/go-builder-contract.trace"
  (
    cd -- "$root"
    GO_BUILDER_CONTRACT_TRACE="$trace" \
      GO_BUILDER_EXPECTED_PATH="Traefik/.env" \
      GO_BUILDER_EXPECTED_TEXT="TRAEFIK_GO_IMAGE=golang:alpine" \
      bash .githooks/pre-commit
  )
  [[ "$(<"$trace")" == traefik-reader ]]
  [[ "$(<"$root/Traefik/.env")" == 'TRAEFIK_GO_IMAGE=golang:1-alpine' ]]
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

case_pre_commit_espocrm_production_paths_trigger() {
  local -a paths=(
    "EspoCRM/.env"
    "EspoCRM/docker-compose.app.yaml"
    "EspoCRM/scripts/config-override-internal.php"
    "EspoCRM/scripts/espocrm-runtime-lock.sh"
    "EspoCRM/scripts/espocrm-secret-reader.pl"
    "EspoCRM/scripts/espocrm-start.sh"
    "templates/espocrm-bootstrap/.env"
    "templates/espocrm-bootstrap/docker-compose.espocrm-bootstrap.yaml"
    "templates/espocrm-daemon/.env"
    "templates/espocrm-daemon/docker-compose.espocrm-daemon.yaml"
    "templates/espocrm-daemon/scripts/espocrm-daemon-start.sh"
    "templates/espocrm-websocket/.env"
    "templates/espocrm-websocket/docker-compose.espocrm-websocket.yaml"
    "templates/espocrm-websocket/scripts/espocrm-websocket-healthcheck.php"
    "templates/espocrm-websocket/scripts/espocrm-websocket-start.sh"
  )
  local index=0
  local path=""
  local root=""
  local trace=""

  for path in "${paths[@]}"; do
    root="$(create_case_repo "pre-commit-espocrm-production-${index}")"
    prepare_espocrm_bootstrap_hook_repo "$root" 0
    mkdir -p -- "$(dirname -- "${root}/${path}")"
    case "$path" in
      *.sh)
        printf '#!/usr/bin/env bash\n# Æctuæl EspoCRM fixture\nexit 0\n' >"${root}/${path}"
        write_shellcheck_stub "$root" 0
        ;;
      *.php)
        printf '<?php\n// Æctuæl EspoCRM fixture\n' >"${root}/${path}"
        ;;
      *.pl)
        printf '#!/usr/bin/env perl\n# Æctuæl EspoCRM fixture\nexit 0;\n' >"${root}/${path}"
        ;;
      *)
        printf '# Æctuæl EspoCRM fixture\n' >"${root}/${path}"
        ;;
    esac
    git -C "$root" add -- "$path"
    trace="${root}/espocrm-bootstrap.trace"
    if [[ "$path" == *.sh ]]; then
      (cd -- "$root" && ESPOCRM_BOOTSTRAP_TRACE="$trace" EXPECTED_SHELLCHECK_FILES="$path" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
    else
      (cd -- "$root" && ESPOCRM_BOOTSTRAP_TRACE="$trace" bash .githooks/pre-commit)
    fi
    [[ -f "$trace" && "$(wc -l <"$trace")" == 1 ]]
    index=$((index + 1))
  done
}

case_pre_commit_espocrm_metadata_does_not_trigger() {
  local -a paths=(
    "EspoCRM/README.md"
    "templates/espocrm-bootstrap/README.md"
    ".cursor/README.md"
    ".cursor/commands/audit.md"
    ".cursor/rules/project-audit.mdc"
    ".cursor/scripts/test-espocrm-bootstrap.sh"
    ".githooks/pre-commit"
  )
  local index=0
  local path=""
  local root=""
  local trace=""

  for path in "${paths[@]}"; do
    root="$(create_case_repo "pre-commit-espocrm-metadata-${index}")"
    prepare_espocrm_bootstrap_hook_repo "$root" 0
    if [[ "$path" == .githooks/pre-commit || "$path" == .cursor/scripts/test-espocrm-bootstrap.sh ]]; then
      printf '\n# Æctuæl EspoCRM orchestrætion fixture\n' >>"${root}/${path}"
    else
      mkdir -p -- "$(dirname -- "${root}/${path}")"
      printf '# Æctuæl EspoCRM documentætion fixture\n' >"${root}/${path}"
    fi
    git -C "$root" add -- "$path"
    trace="${root}/espocrm-bootstrap.trace"
    if [[ "$path" == *.sh || "$path" == .githooks/pre-commit ]]; then
      write_shellcheck_stub "$root" 0
      (cd -- "$root" && ESPOCRM_BOOTSTRAP_TRACE="$trace" EXPECTED_SHELLCHECK_FILES="$path" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
    else
      (cd -- "$root" && ESPOCRM_BOOTSTRAP_TRACE="$trace" bash .githooks/pre-commit)
    fi
    [[ ! -e "$trace" ]]
    index=$((index + 1))
  done
}

case_pre_commit_rejects_missing_gitea_vaultwarden_recovery_checker() {
  local checker_path=".cursor/scripts/test-gitea-vaultwarden-recovery.py"
  local root=""

  root="$(create_case_repo pre-commit-rejects-missing-gitea-vaultwarden-recovery-checker)"
  prepare_pre_commit_repo "$root" "$checker_path"
  printf '# Æctuæl recovery documentætion fixture\n' >"$root/README.md"
  git -C "$root" add -- README.md
  (cd -- "$root" && bash .githooks/pre-commit)
}

case_pre_commit_gitea_vaultwarden_recovery_production_paths_trigger() {
  local -a paths=(
    "Gitea/scripts/strict-recovery.py"
    "Vaultwarden/scripts/strict-recovery.py"
  )
  local index=0
  local path=""
  local root=""
  local trace=""

  for path in "${paths[@]}"; do
    root="$(create_case_repo "pre-commit-recovery-production-${index}")"
    prepare_gitea_vaultwarden_recovery_hook_repo "$root" 0
    mkdir -p -- "$(dirname -- "${root}/${path}")"
    printf '%s\n' \
      '#!/usr/bin/env python3' \
      '# SPDX-License-Identifier: MIT' \
      '"""Æctuæl strict-recovery fixture."""' >"${root}/${path}"
    git -C "$root" add -- "$path"
    trace="${root}/gitea-vaultwarden-recovery.trace"
    (cd -- "$root" && GITEA_VAULTWARDEN_RECOVERY_TRACE="$trace" bash .githooks/pre-commit)
    [[ -f "$trace" && "$(wc -l <"$trace")" == 1 ]]
    index=$((index + 1))
  done
}

case_pre_commit_gitea_vaultwarden_recovery_combination_deduplicates() {
  local root=""
  local trace=""

  root="$(create_case_repo pre-commit-recovery-combination-deduplicates)"
  prepare_gitea_vaultwarden_recovery_hook_repo "$root" 0
  mkdir -p -- "$root/Gitea/scripts" "$root/Vaultwarden/scripts"
  printf '%s\n' \
    '#!/usr/bin/env python3' \
    '# SPDX-License-Identifier: MIT' \
    '"""Æctuæl Giteæ strict-recovery fixture."""' >"$root/Gitea/scripts/strict-recovery.py"
  printf '%s\n' \
    '#!/usr/bin/env python3' \
    '# SPDX-License-Identifier: MIT' \
    '"""Æctuæl Væultwærden strict-recovery fixture."""' >"$root/Vaultwarden/scripts/strict-recovery.py"
  git -C "$root" add -- Gitea/scripts/strict-recovery.py Vaultwarden/scripts/strict-recovery.py
  trace="${root}/gitea-vaultwarden-recovery.trace"
  (cd -- "$root" && GITEA_VAULTWARDEN_RECOVERY_TRACE="$trace" bash .githooks/pre-commit)
  [[ -f "$trace" && "$(wc -l <"$trace")" == 1 ]]
}

case_pre_commit_gitea_vaultwarden_recovery_metadata_does_not_trigger() {
  local -a paths=(
    "Gitea/README.md"
    "Vaultwarden/README.md"
    "Gitea/scripts/gitea-start.sh"
    "Vaultwarden/scripts/vaultwarden.d/10-database-url.sh"
    "Gitea/scripts/strict-recovery.py.bak"
    ".cursor/README.md"
    ".cursor/commands/audit.md"
    ".cursor/rules/project-audit.mdc"
    ".cursor/scripts/test-gitea-vaultwarden-recovery.py"
    ".githooks/pre-commit"
  )
  local index=0
  local path=""
  local root=""
  local trace=""

  for path in "${paths[@]}"; do
    root="$(create_case_repo "pre-commit-recovery-metadata-${index}")"
    prepare_gitea_vaultwarden_recovery_hook_repo "$root" 0
    if [[ "$path" == .githooks/pre-commit || "$path" == .cursor/scripts/test-gitea-vaultwarden-recovery.py ]]; then
      printf '\n# Æctuæl recovery orchestrætion fixture\n' >>"${root}/${path}"
    else
      mkdir -p -- "$(dirname -- "${root}/${path}")"
      case "$path" in
        *.sh)
          printf '#!/usr/bin/env bash\n# Æctuæl recovery fixture\nexit 0\n' >"${root}/${path}"
          ;;
        *)
          printf '# Æctuæl recovery documentætion fixture\n' >"${root}/${path}"
          ;;
      esac
    fi
    git -C "$root" add -- "$path"
    trace="${root}/gitea-vaultwarden-recovery.trace"
    if [[ "$path" == *.sh || "$path" == .githooks/pre-commit ]]; then
      write_shellcheck_stub "$root" 0
      (cd -- "$root" && GITEA_VAULTWARDEN_RECOVERY_TRACE="$trace" EXPECTED_SHELLCHECK_FILES="$path" PATH="$root/tool-bin:$PATH" bash .githooks/pre-commit)
    else
      (cd -- "$root" && GITEA_VAULTWARDEN_RECOVERY_TRACE="$trace" bash .githooks/pre-commit)
    fi
    [[ ! -e "$trace" ]]
    index=$((index + 1))
  done
}

case_pre_commit_gitea_vaultwarden_recovery_failure_propagates() {
  local root=""
  local trace=""

  root="$(create_case_repo pre-commit-recovery-failure-propagates)"
  prepare_gitea_vaultwarden_recovery_hook_repo "$root" 29
  mkdir -p -- "$root/Gitea/scripts"
  printf '%s\n' \
    '#!/usr/bin/env python3' \
    '# SPDX-License-Identifier: MIT' \
    '"""Æctuæl strict-recovery fixture."""' >"$root/Gitea/scripts/strict-recovery.py"
  git -C "$root" add -- Gitea/scripts/strict-recovery.py
  trace="${root}/gitea-vaultwarden-recovery.trace"
  if (cd -- "$root" && GITEA_VAULTWARDEN_RECOVERY_TRACE="$trace" bash .githooks/pre-commit); then
    return 1
  fi
  [[ -f "$trace" && "$(wc -l <"$trace")" == 1 ]]
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

case_pre_commit_kimai_dockerignore_does_not_trigger_wrapper() {
  local checker=".cursor/scripts/test-kimai-wrapper.sh"
  local compliance_checker=".cursor/scripts/enforce-app-template-compliance.py"
  local anchor_checker=".cursor/scripts/verify-anchors.py"
  local root=""
  root="$(create_case_repo pre-commit-kimai-dockerignore-does-not-trigger-wrapper)"
  install_pre_commit_tools "$root"
  write_shell_stub "$root" "$checker" 71
  write_python_stub "$root" "$compliance_checker" 72
  write_python_stub "$root" "$anchor_checker" 73
  mkdir -p -- "$root/Kimai/dockerfiles"
  printf 'services: {}\n' >"$root/Kimai/docker-compose.app.yaml"
  git -C "$root" add -- "$checker" "$compliance_checker" "$anchor_checker" Kimai/docker-compose.app.yaml
  commit_fixture_baseline "$root"
  printf '*\n!.dockerignore\n' >"$root/Kimai/dockerfiles/.dockerignore"
  git -C "$root" add -- Kimai/dockerfiles/.dockerignore
  (cd -- "$root" && bash .githooks/pre-commit)
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
expect_success pre-commit-hardening-targets-each-gitea-closure-compose case_pre_commit_hardening_targets_each_gitea_closure_compose
expect_success pre-commit-hardening-does-not-skip-deleted-gitea-compose case_pre_commit_hardening_does_not_skip_deleted_gitea_compose
expect_success pre-commit-real-hardening-accepts-valid-template-only-change case_pre_commit_real_hardening_accepts_valid_template_only_change
expect_failure pre-commit-real-hardening-rejects-duplicate-template-service case_pre_commit_real_hardening_rejects_duplicate_template_service
expect_failure pre-commit-real-hardening-rejects-interpolated-app-reference case_pre_commit_real_hardening_rejects_interpolated_app_reference
expect_failure pre-commit-real-hardening-rejects-app-include case_pre_commit_real_hardening_rejects_app_include
expect_failure pre-commit-real-hardening-rejects-app-extends case_pre_commit_real_hardening_rejects_app_extends
expect_failure pre-commit-real-hardening-rejects-required-template-consumer case_pre_commit_real_hardening_rejects_required_template_consumer
expect_failure pre-commit-real-hardening-rejects-deleted-required-template case_pre_commit_real_hardening_rejects_deleted_required_template
expect_failure pre-commit-real-hardening-rejects-symlinked-required-template-parent case_pre_commit_real_hardening_rejects_symlinked_required_template_parent
expect_failure pre-commit-rejects-missing-erpnext-checker case_pre_commit_rejects_missing_erpnext_checker
expect_success pre-commit-uses-staged-new-erpnext-checker case_pre_commit_uses_staged_new_erpnext_checker
expect_failure pre-commit-uses-staged-changed-erpnext-checker case_pre_commit_uses_staged_changed_erpnext_checker
expect_success pre-commit-erpnext-production-paths-trigger case_pre_commit_erpnext_production_paths_trigger
expect_success pre-commit-erpnext-metadata-does-not-self-trigger case_pre_commit_erpnext_metadata_does_not_self_trigger
expect_failure pre-commit-rejects-missing-go-builder-contract-checker case_pre_commit_rejects_missing_go_builder_contract_checker
expect_success pre-commit-go-builder-production-paths-trigger-exact-targets case_pre_commit_go_builder_production_paths_trigger_exact_targets
expect_success pre-commit-go-builder-combines-sorted-unique-targets case_pre_commit_go_builder_combines_sorted_unique_targets
expect_success pre-commit-go-builder-checker-self-stage-runs-synthetics-only case_pre_commit_go_builder_checker_self_stage_runs_synthetics_only
expect_success pre-commit-go-builder-foreign-and-metadata-paths-do-not-trigger case_pre_commit_go_builder_foreign_and_metadata_paths_do_not_trigger
expect_failure pre-commit-go-builder-failure-propagates case_pre_commit_go_builder_failure_propagates
expect_success pre-commit-go-builder-reads-staged-product-bytes case_pre_commit_go_builder_reads_staged_product_bytes
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
expect_success pre-commit-espocrm-production-paths-trigger case_pre_commit_espocrm_production_paths_trigger
expect_success pre-commit-espocrm-metadata-does-not-trigger case_pre_commit_espocrm_metadata_does_not_trigger
expect_failure pre-commit-rejects-missing-gitea-vaultwarden-recovery-checker case_pre_commit_rejects_missing_gitea_vaultwarden_recovery_checker
expect_success pre-commit-gitea-vaultwarden-recovery-production-paths-trigger case_pre_commit_gitea_vaultwarden_recovery_production_paths_trigger
expect_success pre-commit-gitea-vaultwarden-recovery-combination-deduplicates case_pre_commit_gitea_vaultwarden_recovery_combination_deduplicates
expect_success pre-commit-gitea-vaultwarden-recovery-metadata-does-not-trigger case_pre_commit_gitea_vaultwarden_recovery_metadata_does_not_trigger
expect_success pre-commit-gitea-vaultwarden-recovery-failure-propagates case_pre_commit_gitea_vaultwarden_recovery_failure_propagates
expect_success pre-commit-rules-do-not-trigger-integration-suites case_pre_commit_rules_do_not_trigger_integration_suites
expect_success pre-commit-run-test-does-not-self-trigger case_pre_commit_run_test_does_not_self_trigger
expect_success pre-commit-source-sync-test-does-not-self-trigger case_pre_commit_source_sync_test_does_not_self_trigger
expect_failure pre-commit-run-triggers-logrotate-suite case_pre_commit_run_triggers_logrotate_suite
expect_success pre-commit-logrotate-test-does-not-self-trigger case_pre_commit_logrotate_test_does_not_self_trigger
expect_success pre-commit-integration-test-does-not-self-trigger case_pre_commit_integration_test_does_not_self_trigger
expect_success pre-commit-kimai-dockerignore-does-not-trigger-wrapper case_pre_commit_kimai_dockerignore_does_not_trigger_wrapper
expect_success pre-commit-honors-alternate-index case_pre_commit_honors_alternate_index

printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
