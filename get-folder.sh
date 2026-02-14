#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Constants & Defaults
# ──────────────────────────────────────────────────────────────────────────────
readonly REPO_URL="https://github.com/saervices/Docker.git"
readonly BRANCH="main"

# Get the directory of the script itself and the script name without .sh suffix
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_BASE="$(basename "${BASH_SOURCE[0]}" .sh)"

# ──────────────────────────────────────────────────────────────────────────────
# Logging Setup & Functions
# ──────────────────────────────────────────────────────────────────────────────

# Color codes for logging
# ───────────────────────────────────────
RESET='\033[0m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GREY='\033[1;30m'
MAGENTA='\033[0;35m'

# Function: log_ok
# ${GREEN}[OK]
# ───────────────────────────────────────
log_ok() {
  local msg="$*"
  echo -e "${GREEN}[OK]${RESET}    $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[OK]    $msg" >> "$LOGFILE"
  fi
}

# Function: log_info
# ${CYAN}[INFO]
# ───────────────────────────────────────
log_info() {
  local msg="$*"
  echo -e "${CYAN}[INFO]${RESET}  $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[INFO]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_warn
# ${YELLOW}[WARN]
# ───────────────────────────────────────
log_warn() {
  local msg="$*"
  echo -e "${YELLOW}[WARN]${RESET}  $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[WARN]  $msg" >> "$LOGFILE"
  fi
}

# Function: log_error
# ${RED}[ERROR]
# ───────────────────────────────────────
log_error() {
  local msg="$*"
  echo -e "${RED}[ERROR]${RESET} $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[ERROR] $msg" >> "$LOGFILE"
  fi
}

# Function: log_debug
# ${GREY}[DEBUG]
# ───────────────────────────────────────
log_debug() {
  local msg="$*"
  if [[ "${DEBUG:-false}" == true ]]; then
    echo -e "${GREY}[DEBUG]${RESET} $msg"
    if [[ -n "${LOGFILE:-}" ]]; then
      echo -e "[DEBUG] $msg" >> "$LOGFILE"
    fi
  fi
}

# Function: setup_logging
# Initializes logging file inside TARGET_DIR
# Keep only the latest $log_retention_count logs
# ───────────────────────────────────────
setup_logging() {
  local log_retention_count="${1:-2}"

  # Construct log dir path
  local log_dir="${SCRIPT_DIR}/.${SCRIPT_BASE}.conf/logs"

  # Ensure log dir exists and assign logfile
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S).log"
  ensure_dir_exists "$log_dir"

  # Symlink latest.log to current log
  touch "$LOGFILE" && sleep 0.2
  ln -sf "$LOGFILE" "$log_dir/latest.log"

  # Retain only the latest N logs
  local logs  
  mapfile -t logs < <(
  find "$log_dir" -maxdepth 1 -type f -name '*.log' -printf "%T@ %p\n" |
  sort -nr | cut -d' ' -f2- | tail -n +$((log_retention_count + 1))
  )

  for old_log in "${logs[@]}"; do
    rm -f "$old_log"
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# Usage Information
# ──────────────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $0 <folder-in-repo> [--debug] [--dry-run] [--force]

Downloads a specific folder from the GitHub repo:
  $REPO_URL (branch: $BRANCH)

Arguments:
  folder-in-repo   The folder path inside the repo to download. Must be relative and must not contain '..'.
  --debug          Enable debug output.
  --dry-run        Show what would be done without executing actions.
  --force          Force overwrite of existing 'run.sh' file in script directory.

Notes:
  - If the target directory already exists, the script exits with an error. Use --force to overwrite.
  - If 'run.sh' is part of the downloaded folder and doesn't already exist in the script directory, it will be moved and made executable.
    Use --force to overwrite it even if it already exists.

EOF
}

# ──────────────────────────────────────────────────────────────────────────────
# Global Function Helpers
# ──────────────────────────────────────────────────────────────────────────────

# Ensure a directory exists (create if missing)
# Arguments:
#   $1 - directory path
# ───────────────────────────────────────
ensure_dir_exists() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    log_error "ensure_dir_exists() called with empty path"
    return 1
  fi

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || {
      log_error "Failed to create directory: $dir"
      return 1
    }
    log_info "Created directory: $dir"
  else
    log_debug "Directory already exists: $dir"
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Function
# ──────────────────────────────────────────────────────────────────────────────

# Function: parse_args
# Parses command-line arguments, sets globals and logging
# ───────────────────────────────────────
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
          log_error "Multiple folder arguments are not supported."
          usage
          return 1
        fi
        ;;
    esac
  done

  log_debug "Debug mode enabled"
  if [[ "$DRY_RUN" = true ]]; then log_info "Dry-run mode enabled"; fi

  setup_logging "2"

  if [[ -n "$TARGET_DIR" ]]; then
    TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR}"
    log_debug "Repo folder: $REPO_SUBFOLDER and target directory: $TARGET_DIR"
  else
    log_error "Repo folder name not specified!"
    usage
    return 1
  fi
}

# Function: check_dependencies
# Verifies all required commands are available
# ───────────────────────────────────────
check_dependencies() {
  # Check git
  if ! command -v git &>/dev/null; then
    log_warn "git is not installed."
    if [[ "$DRY_RUN" = true ]]; then
      log_info "Dry-run: skipping git installation prompt."
      return 1
    fi
    read -r -p "Install git now? [y/N]: " install_git
    if [[ "$install_git" =~ ^[Yy]$ ]]; then
      if command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y git
      elif command -v yum &>/dev/null; then
        sudo yum install -y git
      else
        log_error "No supported package manager found to install git."
        return 1
      fi
      log_info "git installed successfully."
    else
      log_error "git is required. Aborting."
      return 1
    fi
  else
    log_debug "git is already installed."
  fi
}

# Function: clone_sparse_checkout
# Clone Repo with Sparse Checkout
# ───────────────────────────────────────
clone_sparse_checkout() {
  # Ensure required parameters are provided
  [[ -z "$REPO_URL" || -z "$REPO_SUBFOLDER" ]] && {
    log_error "Missing REPO_URL or REPO_SUBFOLDER."
    return 1
  }

  if [[ "$REPO_SUBFOLDER" == /* || "$REPO_SUBFOLDER" == *".."* ]]; then
    log_error "Invalid folder path: '$REPO_SUBFOLDER'"
    return 1
  fi

  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping git clone."
    return 0
  fi

  _TMPDIR=$(mktemp -d)
  trap 'rm -rf -- "$_TMPDIR"' EXIT
  log_debug "Created temp dir: $_TMPDIR"

  git clone --quiet --filter=blob:none --no-checkout "$REPO_URL" "$_TMPDIR" || {
    log_error "Failed to clone repo."
    return 1
  }

  if ! git -C "$_TMPDIR" ls-tree -d --name-only "$BRANCH":"$REPO_SUBFOLDER" &>/dev/null; then
    log_error "Folder '$REPO_SUBFOLDER' not found in branch '$BRANCH'."
    return 1
  fi

  git -C "$_TMPDIR" sparse-checkout init --cone &>/dev/null || {
    log_error "Sparse checkout init failed."
    return 1
  }

  git -C "$_TMPDIR" sparse-checkout set "$REPO_SUBFOLDER" &>/dev/null || {
    log_error "Sparse checkout set failed."
    return 1
  }

  git -C "$_TMPDIR" checkout "$BRANCH" &>/dev/null || {
    log_error "Failed to checkout branch '$BRANCH'."
    return 1
  }

  if [[ ! -d "$_TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' not found in '$_TMPDIR' directory."
  else
    log_debug "Checked out folder '$REPO_SUBFOLDER' successfully."
  fi
}

# Function: copy_files
# Copy Fetched Files to Local Folder (overwrite if exists)
# ───────────────────────────────────────
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
    log_error "Failed to copy folder."
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/run.sh" && -f "$_TMPDIR/run.sh" ]] || [[ "$FORCE" = true && -f "$_TMPDIR/run.sh" ]]; then
    cp --remove-destination "$_TMPDIR/run.sh" "$SCRIPT_DIR/run.sh"
    chmod +x "${SCRIPT_DIR}/run.sh"
    log_info "Copied and made 'run.sh' executable."
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Execution
# ──────────────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"  
  if [[ -n "$TARGET_DIR" ]]; then
    check_dependencies
    clone_sparse_checkout
    if [[ -d "$TARGET_DIR" && "$FORCE" = false ]]; then
      log_error "Folder '$TARGET_DIR' already exists. Use --force to override."
      return 1
    fi
    if [[ "$FORCE" = true || ! -d "$TARGET_DIR" ]]; then
      copy_files
    fi
  else
    return 1
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Script Entry Point
# ──────────────────────────────────────────────────────────────────────────────
main "$@" || {
  exit 1
}