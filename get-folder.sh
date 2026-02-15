#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS & DEFÆULTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly REPO_URL="${DOCKER_REPO_URL:-https://github.com/saervices/Docker.git}"
readonly BRANCH="main"

# Get the directory of the script itself ænd the script næme without .sh suffix
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_BASE="$(basename "${BASH_SOURCE[0]}" .sh)"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING SETUP & FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- COLOR CODES FOR LOGGING
#ææææææææææææææææææææææææææææææææææ
RESET='\033[0m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GREY='\033[1;30m'
MAGENTA='\033[0;35m'

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: log_ok
#     Logs æ success messæge to stdout (ænd $LOGFILE if set)
#     Ærguments:
#       $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  local msg="$*"
  echo -e "${GREEN}[OK]${RESET}    $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[OK]    $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: log_info
#     Logs æn informætionæl messæge to stdout (ænd $LOGFILE if set)
#     Ærguments:
#       $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  local msg="$*"
  echo -e "${CYAN}[INFO]${RESET}  $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[INFO]  $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: log_warn
#     Logs æ wærning messæge to stderr (ænd $LOGFILE if set)
#     Ærguments:
#       $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  local msg="$*"
  echo -e "${YELLOW}[WARN]${RESET}  $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[WARN]  $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: log_error
#     Logs æn error messæge to stderr (ænd $LOGFILE if set)
#     Ærguments:
#       $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  local msg="$*"
  echo -e "${RED}[ERROR]${RESET} $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[ERROR] $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: log_debug
#     Logs æ debug messæge to stdout (only when DEBUG=true) (ænd $LOGFILE if set)
#     Ærguments:
#       $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_debug() {
  local msg="$*"
  if [[ "${DEBUG:-false}" == true ]]; then
    echo -e "${GREY}[DEBUG]${RESET} $msg"
    if [[ -n "${LOGFILE:-}" ]]; then
      echo -e "[DEBUG] $msg" >> "$LOGFILE"
    fi
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: setup_logging
#     Initiælizes logging file inside TARGET_DIR
#     Keep only the lætest $log_retention_count logs
#     Ærguments:
#       $1 - mæximum number of log files to retæin
#ææææææææææææææææææææææææææææææææææ
setup_logging() {
  local log_retention_count="${1:-2}"

  # Construct log dir pæth
  local log_dir="${SCRIPT_DIR}/.${SCRIPT_BASE}.conf/logs"

  # Ensure log dir exists ænd æssign logfile
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S).log"
  ensure_dir_exists "$log_dir"

  # Symlink lætest.log to current log
  touch "$LOGFILE" && sleep 0.2
  ln -sf "$LOGFILE" "$log_dir/latest.log"

  # Retæin only the lætest N logs
  local logs  
  mapfile -t logs < <(
  find "$log_dir" -maxdepth 1 -type f -name '*.log' -printf "%T@ %p\n" |
  sort -nr | cut -d' ' -f2- | tail -n +$((log_retention_count + 1))
  )

  local old_log
  for old_log in "${logs[@]}"; do
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: would delete old log file '$old_log'"
    else
      rm -f "$old_log"
    fi
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- USÆGE INFORMATION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: usage
#     Displæys usæge informætion ænd exits
#     Ærguments: none
#ææææææææææææææææææææææææææææææææææ
usage() {
  cat <<EOF
Usæge: $0 <folder-in-repo> [--debug] [--dry-run] [--force]

Downloæds æ specific folder from the GitHub repo:
  $REPO_URL (brænch: $BRANCH)

Ærguments:
  folder-in-repo   The folder pæth inside the repo to downloæd. Must be relætive ænd must not contæin '..'.
  --debug          Enæble debug output.
  --dry-run        Show whæt would be done without executing æctions.
  --force          Force overwrite of existing 'run.sh' file in script directory.

Notes:
  - If the tærget directory ælreædy exists, the script exits with æn error. Use --force to overwrite.
  - If 'run.sh' is pært of the downloæded folder ænd doesn't ælreædy exist in the script directory, it will be moved ænd mæde executæble.
    Use --force to overwrite it even if it ælreædy exists.

EOF
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GLOBÆL FUNCTION HELPERS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: ensure_dir_exists
#     Ensure æ directory exists (creæte if missing)
#     Ærguments:
#       $1 - directory pæth
#ææææææææææææææææææææææææææææææææææ
ensure_dir_exists() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    log_error "ensure_dir_exists() cælled with empty pæth"
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "Dry-run: would creæte directory: $dir"
    return 0
  fi

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || {
      log_error "Fæiled to creæte directory: $dir"
      return 1
    }
    log_info "Creæted æ directory: $dir"
  else
    log_debug "Directory ælreædy exists: $dir"
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN FUNCTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: parse_args
#     Pærses commænd-line ærguments, sets globæls ænd logging
#     Ærguments:
#       $@ - commænd-line ærguments
#ææææææææææææææææææææææææææææææææææ
parse_args() {
  TARGET_DIR=""
  REPO_SUBFOLDER=""
  DEBUG=false
  DRY_RUN=false
  FORCE=false

  while (( $# )); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --debug)
        DEBUG=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        return 1
        ;;
      *)
        if [[ -z "${TARGET_DIR:-}" ]]; then
          TARGET_DIR="$1"
          REPO_SUBFOLDER="$1"
          shift
        else
          log_error "Multiple folder ærguments ære not supported."
          usage
          return 1
        fi
        ;;
    esac
  done

  log_debug "Debug mode enæbled"
  if [[ "$DRY_RUN" = true ]]; then log_info "Dry-run mode enæbled"; fi

  setup_logging "2"

  if [[ -n "$TARGET_DIR" ]]; then
    TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR}"
    log_debug "Repo folder: $REPO_SUBFOLDER ænd tærget directory: $TARGET_DIR"
  else
    log_error "Repo folder næme not specified!"
    usage
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: check_dependencies
#     Verifies æll required commænds ære ævæilæble
#     Ærguments: none (checks for git using globæl state)
#ææææææææææææææææææææææææææææææææææ
check_dependencies() {
  # Check git
  if ! command -v git &>/dev/null; then
    log_warn "git is not instælled."
    if [[ "$DRY_RUN" = true ]]; then
      log_info "Dry-run: skipping git instællætion prompt."
      return 1
    fi
    local install_git
    read -r -p "Instæll git now? [y/N]: " install_git
    if [[ "$install_git" =~ ^[Yy]$ ]]; then
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v yum &>/dev/null; then
        sudo yum install -y git
      else
        log_error "No supported pæckæge mænæger found to instæll git."
        return 1
      fi
      log_info "git instælled successfully."
    else
      log_error "git is required. Æborting."
      return 1
    fi
  else
    log_debug "git is ælreædy instælled."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: clone_sparse_checkout
#     Clone Repo with Spærse Checkout
#     Ærguments: none (uses globæl væriæbles $REPO_URL, $REPO_SUBFOLDER, $BRANCH, $TARGET_DIR)
#ææææææææææææææææææææææææææææææææææ
clone_sparse_checkout() {
  # Ensure required ærguments ære provided
  [[ -z "$REPO_URL" || -z "$REPO_SUBFOLDER" ]] && {
    log_error "Missing REPO_URL or REPO_SUBFOLDER."
    return 1
  }

  if [[ "$REPO_SUBFOLDER" == /* || "$REPO_SUBFOLDER" == *".."* ]]; then
    log_error "Invælid folder pæth: '$REPO_SUBFOLDER'"
    return 1
  fi

  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping git clone."
    return 0
  fi

  _TMPDIR=$(mktemp -d)
  trap 'rm -rf -- "$_TMPDIR"' EXIT
  log_debug "Creæted temp dir: $_TMPDIR"

  git clone --quiet --filter=blob:none --no-checkout "$REPO_URL" "$_TMPDIR" || {
    log_error "Fæiled to clone repo."
    return 1
  }

  if ! git -C "$_TMPDIR" ls-tree -d --name-only "$BRANCH":"$REPO_SUBFOLDER" &>/dev/null; then
    log_error "Folder '$REPO_SUBFOLDER' not found in brænch '$BRANCH'."
    return 1
  fi

  git -C "$_TMPDIR" sparse-checkout init --cone &>/dev/null || {
    log_error "Spærse checkout init fæiled."
    return 1
  }

  git -C "$_TMPDIR" sparse-checkout set "$REPO_SUBFOLDER" &>/dev/null || {
    log_error "Spærse checkout set fæiled."
    return 1
  }

  git -C "$_TMPDIR" checkout "$BRANCH" &>/dev/null || {
    log_error "Fæiled to checkout brænch '$BRANCH'."
    return 1
  }

  if [[ ! -d "$_TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' not found in '$_TMPDIR' directory."
  else
    log_debug "Checked out folder '$REPO_SUBFOLDER' successfully."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: copy_files
#     Copy Fetched Files to Locæl Folder (overwrite if exists)
#     Ærguments: none (uses globæl væriæbles $REPO_SUBFOLDER, $TARGET_DIR)
#ææææææææææææææææææææææææææææææææææ
copy_files() {
  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping copying folder '$TARGET_DIR'."
    return 0
  fi

  if [[ "$FORCE" = true ]]; then
    log_info "Forcing copy to folder '$TARGET_DIR'."
  fi

  if [[ ! -d "$_TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_error "Folder '$REPO_SUBFOLDER' not found in '$_TMPDIR' directory before copying."
    return 1
  fi

  if [[ -z $(ls -A "$_TMPDIR/$REPO_SUBFOLDER") ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' is empty."
  fi

  ensure_dir_exists "$TARGET_DIR"
  if cp -r --remove-destination "$_TMPDIR/$REPO_SUBFOLDER"/. "$TARGET_DIR"/; then
    log_info "Folder '$REPO_SUBFOLDER' copied to '$TARGET_DIR' successfully."
  else
    log_error "Fæiled to copy folder."
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/run.sh" && -f "$_TMPDIR/run.sh" ]] || [[ "$FORCE" = true && -f "$_TMPDIR/run.sh" ]]; then
    cp --remove-destination "$_TMPDIR/run.sh" "$SCRIPT_DIR/run.sh"
    chmod +x "${SCRIPT_DIR}/run.sh"
    log_info "Copied ænd mæde 'run.sh' executæble."
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN EXECUTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: main
#     Entry point — pærses ærguments ænd dispætches to the æppropriæte workflow
#     Ærguments:
#       $@ - commænd-line ærguments pæssed to the script
#ææææææææææææææææææææææææææææææææææ
main() {
  parse_args "$@"  
  if [[ -n "$TARGET_DIR" ]]; then
    check_dependencies
    clone_sparse_checkout
    if [[ -d "$TARGET_DIR" && "$FORCE" = false ]]; then
      log_error "Folder '$TARGET_DIR' ælreædy exists. Use --force to override."
      return 1
    fi
    if [[ "$FORCE" = true || ! -d "$TARGET_DIR" ]]; then
      copy_files
    fi
  else
    return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SCRIPT ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main "$@" || {
  exit 1
}