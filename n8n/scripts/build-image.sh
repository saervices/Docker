#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# n8n custom imæge build helper.

set -euo pipefail
umask 077

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly ENV_FILE_DEFAULT="${PROJECT_DIR}/.env"
readonly DOCKERFILE_DEFAULT="${PROJECT_DIR}/dockerfiles/Dockerfile"
readonly BUILD_CONTEXT_DEFAULT="${PROJECT_DIR}/dockerfiles"
readonly OIDC_REPO_URL="https://github.com/cweagans/n8n-oidc.git"
readonly DEFAULT_BASE_IMAGE="docker.n8n.io/n8nio/n8n:latest"
readonly DEFAULT_OIDC_REF="main"
readonly DEFAULT_BUILD_INFO_VERSION="1"
readonly DEFAULT_TARGET_IMAGE="n8n-oidc:latest"

readonly RESET=$'\033[0m'
readonly RED=$'\033[0;31m'
readonly YELLOW=$'\033[0;33m'
readonly GREEN=$'\033[0;32m'
readonly CYAN=$'\033[0;36m'

ENV_FILE="${ENV_FILE:-$ENV_FILE_DEFAULT}"
DOCKERFILE="${N8N_BUILD_DOCKERFILE:-$DOCKERFILE_DEFAULT}"
BUILD_CONTEXT="${N8N_BUILD_CONTEXT:-$BUILD_CONTEXT_DEFAULT}"
BUILD_PULL="${N8N_BUILD_PULL:-true}"
BUILD_NO_CACHE="${N8N_BUILD_NO_CACHE:-false}"
METADATA_ONLY=false

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_info() {
  printf '%b[INFO]%b %s\n' "$CYAN" "$RESET" "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$1"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ wærning messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$1" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æn error messæge.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_error() {
  printf '%b[ERROR]%b %s\n' "$RED" "$RESET" "$1" >&2
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_fatal
#   Logs æ fætæl error ænd exits.
#   Ærguments:
#     $1 - messæge
#ææææææææææææææææææææææææææææææææææ
log_fatal() {
  log_error "$1"
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: usage
#   Prints CLI help.
#ææææææææææææææææææææææææææææææææææ
usage() {
  cat <<'EOF'
Usage: scripts/build-image.sh [options]

Resolve moving upstream references, then build the custom n8n OIDC image.

Options:
  --metadata-only       Resolve and print exported build variables; do not build
  --env-file PATH       Env file to read (default: ./n8n/.env)
  --dockerfile PATH     Dockerfile to use (default: ./n8n/dockerfiles/Dockerfile)
  --context PATH        Docker build context (default: ./n8n/dockerfiles)
  --tag IMAGE           Target image tag (default: APP_IMAGE from env file)
  --no-cache            Add docker build --no-cache
  --no-pull             Do not add docker build --pull
  -h, --help            Show this help

Advanced shell-only overrides:
  APP_IMAGE=n8n-oidc:2.27.0-oidc-a1b2c3d
  N8N_BASE_IMAGE=docker.n8n.io/n8nio/n8n:latest
  N8N_OIDC_HOOKS_REF=main
EOF
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: require_command
#   Verifies thæt æ required commænd exists.
#   Ærguments:
#     $1 - commænd næme
#ææææææææææææææææææææææææææææææææææ
require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    log_fatal "Required command not found: ${command_name}"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_env_value
#   Reæds æ simple KEY=vælue from the selected env file.
#   Ærguments:
#     $1 - key næme
#     $2 - defæult vælue
#ææææææææææææææææææææææææææææææææææ
get_env_value() {
  local key_name="$1"
  local default_value="$2"
  local line=""
  local value=""

  if [[ -f "$ENV_FILE" ]]; then
    line="$(grep -E "^${key_name}=" "$ENV_FILE" | tail -n 1 || true)"
  fi

  if [[ -z "$line" ]]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  value="${line#*=}"
  value="${value%%#*}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: image_repo_without_tag
#   Extracts the registry/repository portion from æ Docker imæge reference.
#   Ærguments:
#     $1 - imæge reference
#ææææææææææææææææææææææææææææææææææ
image_repo_without_tag() {
  local image_reference="$1"
  local image_without_digest="${image_reference%@*}"
  local last_path_part="${image_without_digest##*/}"

  if [[ "$last_path_part" == *:* ]]; then
    image_without_digest="${image_without_digest%:*}"
  fi

  printf '%s\n' "$image_without_digest"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_base_image
#   Pulls the requested bæse imæge ænd returns its immutable RepoDigest.
#   Ærguments:
#     $1 - requested imæge reference
#ææææææææææææææææææææææææææææææææææ
resolve_base_image() {
  local requested_image="$1"
  local image_repo=""
  local repo_digest=""
  local all_digests=""
  local candidate=""

  docker pull "$requested_image" >/dev/null
  image_repo="$(image_repo_without_tag "$requested_image")"
  all_digests="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$requested_image" 2>/dev/null || true)"

  while IFS= read -r candidate; do
    if [[ "$candidate" == "${image_repo}@sha256:"* ]]; then
      repo_digest="$candidate"
      break
    fi
  done <<< "$all_digests"

  if [[ -z "$repo_digest" ]]; then
    repo_digest="$(printf '%s\n' "$all_digests" | sed -n '1p')"
  fi

  if [[ -z "$repo_digest" ]]; then
    log_fatal "Could not resolve RepoDigest for ${requested_image}"
  fi

  printf '%s\n' "$repo_digest"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_oidc_ref
#   Resolves æ cweagans/n8n-oidc branch, tæg, or commit to æ commit SHÆ.
#   Ærguments:
#     $1 - requested ref
#ææææææææææææææææææææææææææææææææææ
resolve_oidc_ref() {
  local requested_ref="$1"
  local resolved_ref=""

  if [[ "$requested_ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s\n' "${requested_ref,,}"
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    resolved_ref="$(
      git ls-remote "$OIDC_REPO_URL" \
        "$requested_ref" \
        "refs/heads/${requested_ref}" \
        "refs/tags/${requested_ref}" \
        "refs/tags/${requested_ref}^{}" \
        | awk '
          $2 ~ /\^\{\}$/ { peeled=$1 }
          $2 !~ /\^\{\}$/ && first == "" { first=$1 }
          END {
            if (peeled != "") print peeled
            else print first
          }
        '
    )"
  fi

  if [[ -z "$resolved_ref" ]] && command -v curl >/dev/null 2>&1; then
    resolved_ref="$(
      curl -fsSL "https://api.github.com/repos/cweagans/n8n-oidc/commits/${requested_ref}" \
        | sed -n 's/^[[:space:]]*"sha": "\([0-9a-f]\{40\}\)",$/\1/p' \
        | sed -n '1p'
    )"
  fi

  if [[ -z "$resolved_ref" ]]; then
    log_fatal "Could not resolve cweagans/n8n-oidc ref: ${requested_ref}"
  fi

  printf '%s\n' "$resolved_ref"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: print_metadata_exports
#   Prints shell exports for the resolved build metædætæ.
#   Ærguments:
#     $1 - tærget imæge
#     $2 - requested bæse imæge
#     $3 - resolved bæse imæge
#     $4 - requested OIDC ref
#     $5 - resolved OIDC ref
#     $6 - build dæte
#     $7 - build info version
#ææææææææææææææææææææææææææææææææææ
print_metadata_exports() {
  local target_image="$1"
  local base_image="$2"
  local resolved_base_image="$3"
  local oidc_ref="$4"
  local resolved_oidc_ref="$5"
  local build_date="$6"
  local build_info_version="$7"

  printf 'export APP_IMAGE=%q\n' "$target_image"
  printf 'export N8N_BASE_IMAGE=%q\n' "$base_image"
  printf 'export N8N_BASE_IMAGE_RESOLVED=%q\n' "$resolved_base_image"
  printf 'export N8N_OIDC_HOOKS_REF=%q\n' "$oidc_ref"
  printf 'export N8N_OIDC_HOOKS_RESOLVED_REF=%q\n' "$resolved_oidc_ref"
  printf 'export N8N_BUILD_DATE=%q\n' "$build_date"
  printf 'export N8N_BUILD_INFO_VERSION=%q\n' "$build_info_version"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: build_image
#   Runs docker build with resolved metædætæ.
#   Ærguments:
#     $1 - tærget imæge
#     $2 - requested bæse imæge
#     $3 - resolved bæse imæge
#     $4 - requested OIDC ref
#     $5 - resolved OIDC ref
#     $6 - build dæte
#     $7 - build info version
#ææææææææææææææææææææææææææææææææææ
build_image() {
  local target_image="$1"
  local base_image="$2"
  local resolved_base_image="$3"
  local oidc_ref="$4"
  local resolved_oidc_ref="$5"
  local build_date="$6"
  local build_info_version="$7"
  local build_command=(docker build -f "$DOCKERFILE" -t "$target_image")

  if [[ "$BUILD_PULL" == true ]]; then
    build_command+=(--pull)
  fi

  if [[ "$BUILD_NO_CACHE" == true ]]; then
    build_command+=(--no-cache)
  fi

  build_command+=(
    --build-arg "BASE_IMAGE=${resolved_base_image}"
    --build-arg "BASE_IMAGE_REQUESTED=${base_image}"
    --build-arg "OIDC_HOOKS_REF=${resolved_oidc_ref}"
    --build-arg "OIDC_HOOKS_REQUESTED_REF=${oidc_ref}"
    --build-arg "BUILD_DATE=${build_date}"
    --build-arg "BUILD_INFO_VERSION=${build_info_version}"
    "$BUILD_CONTEXT"
  )

  "${build_command[@]}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Resolves moving refs ænd builds the custom imæge.
#   Ærguments:
#     $@ - CLI ærguments
#ææææææææææææææææææææææææææææææææææ
main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --metadata-only|--print-env)
        METADATA_ONLY=true
        shift
        ;;
      --env-file)
        [[ $# -ge 2 ]] || log_fatal "--env-file requires a path"
        ENV_FILE="$2"
        shift 2
        ;;
      --dockerfile)
        [[ $# -ge 2 ]] || log_fatal "--dockerfile requires a path"
        DOCKERFILE="$2"
        shift 2
        ;;
      --context)
        [[ $# -ge 2 ]] || log_fatal "--context requires a path"
        BUILD_CONTEXT="$2"
        shift 2
        ;;
      --tag)
        [[ $# -ge 2 ]] || log_fatal "--tag requires an image reference"
        APP_IMAGE="$2"
        shift 2
        ;;
      --no-cache)
        BUILD_NO_CACHE=true
        shift
        ;;
      --no-pull)
        BUILD_PULL=false
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_fatal "Unknown option: $1"
        ;;
    esac
  done

  [[ -n "$ENV_FILE" ]] || log_fatal "--env-file requires a path"
  [[ -n "$DOCKERFILE" ]] || log_fatal "--dockerfile requires a path"
  [[ -n "$BUILD_CONTEXT" ]] || log_fatal "--context requires a path"

  require_command docker

  local target_image="${APP_IMAGE:-$(get_env_value APP_IMAGE "$DEFAULT_TARGET_IMAGE")}"
  local base_image="${N8N_BASE_IMAGE:-$DEFAULT_BASE_IMAGE}"
  local oidc_ref="${N8N_OIDC_HOOKS_REF:-$DEFAULT_OIDC_REF}"
  local build_info_version="${N8N_BUILD_INFO_VERSION:-$DEFAULT_BUILD_INFO_VERSION}"
  local build_date="${N8N_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  local resolved_base_image=""
  local resolved_oidc_ref=""

  log_info "Requested n8n base image: ${base_image}"
  resolved_base_image="$(resolve_base_image "$base_image")"
  log_ok "Resolved n8n base image: ${resolved_base_image}"

  log_info "Requested OIDC hooks ref: ${oidc_ref}"
  resolved_oidc_ref="$(resolve_oidc_ref "$oidc_ref")"
  log_ok "Resolved OIDC hooks ref: ${resolved_oidc_ref}"

  log_info "Build date: ${build_date}"
  print_metadata_exports "$target_image" "$base_image" "$resolved_base_image" "$oidc_ref" "$resolved_oidc_ref" "$build_date" "$build_info_version"

  if [[ "$METADATA_ONLY" == true ]]; then
    return 0
  fi

  if [[ -n "${APP_IMAGE:-}" ]]; then
    log_info "Target image override: ${target_image}"
  else
    log_warn "Using APP_IMAGE from ${ENV_FILE}: ${target_image}. Set APP_IMAGE=... or --tag before running this script when promoting a new immutable image tag."
  fi

  build_image "$target_image" "$base_image" "$resolved_base_image" "$oidc_ref" "$resolved_oidc_ref" "$build_date" "$build_info_version"
  log_ok "Custom n8n image build completed."
}

main "$@"
