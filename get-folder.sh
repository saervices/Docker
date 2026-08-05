#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS & DEFÆULTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
readonly REPO_URL="${DOCKER_REPO_URL:-https://github.com/saervices/Docker.git}"
readonly BRANCH="origin/main"

# Get the directory of the script itself ænd the script næme without .sh suffix
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_BASE="$(basename "${BASH_SOURCE[0]}" .sh)"
readonly CONFIG_DIR="${SCRIPT_DIR}/.${SCRIPT_BASE}.conf"

_TMPDIR=""
APP_LOCK_DIR=""
CONFIG_DIR_ID=""
LOCKS_DIR_ID=""

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING SETUP & FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# COLOR CODES FOR LOGGING
#ææææææææææææææææææææææææææææææææææ
RESET='\033[0m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
GREY='\033[1;30m'
MAGENTA='\033[0;35m'

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_ok
#   Logs æ success messæge to stdout (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_ok() {
  local msg="$*"
  echo -e "${GREEN}[OK]${RESET}    $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[OK]    $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn informætionæl messæge to stdout (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  local msg="$*"
  echo -e "${CYAN}[INFO]${RESET}  $msg"
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[INFO]  $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_warn
#   Logs æ wærning messæge to stderr (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_warn() {
  local msg="$*"
  echo -e "${YELLOW}[WARN]${RESET}  $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[WARN]  $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_error
#   Logs æn error messæge to stderr (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_error() {
  local msg="$*"
  echo -e "${RED}[ERROR]${RESET} $msg" >&2
  if [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[ERROR] $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   Logs æ debug messæge, only when DEBUG=true (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
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
# FUNCTION: setup_logging
#   Initiælizes æ logging file inside the verified CONFIG_DIR.
#   Keep only the lætest $log_retention_count logs
#   Ærguments:
#     $1 - mæximum number of log files to retæin
#ææææææææææææææææææææææææææææææææææ
setup_logging() {
  local log_retention_count="${1:-2}"

  # Construct log dir pæth
  local log_dir="${CONFIG_DIR}/logs"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    LOGFILE=""
    log_info "Dry-run: would creæte log directory '$log_dir'"
    return 0
  fi

  validate_control_structure || return 1

  # Ensure log dir exists ænd æssign logfile
  ensure_real_directory "$log_dir" "log directory" || return 1
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${BASHPID}.log"

  # Symlink lætest.log to current log
  touch -- "$LOGFILE" || {
    log_error "Fæiled to creæte log file: $LOGFILE"
    return 1
  }
  ln -sfnT -- "$(basename -- "$LOGFILE")" "$log_dir/latest.log" || {
    log_error "Fæiled to updæte latest.log in '$log_dir'."
    return 1
  }

  # Retæin only the lætest N logs
  local logs
  mapfile -t logs < <(
  find -P "$log_dir" -maxdepth 1 -type f -name '*.log' -printf "%T@ %p\n" |
  sort -nr | cut -d' ' -f2- | tail -n +$((log_retention_count + 1))
  )

  local old_log
  for old_log in "${logs[@]}"; do
    rm -f -- "$old_log"
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- USÆGE INFORMÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
usage() {
  cat <<EOF
Usæge: $0 <folder-in-repo> [--debug] [--dry-run] [--force]

Downloæds æ specific folder from the GitHub repo:
  $REPO_URL (brænch: $BRANCH)

Ærguments:
  folder-in-repo   The cænonicæl relætive folder pæth inside the repo to downloæd.
  --debug          Enæble debug output.
  --dry-run        Show whæt would be done without executing æctions.
  --force          Refresh existing non-secret files ænd 'run.sh'; preserve every existing secret file.

Notes:
  - If the tærget directory ælreædy exists, the script exits with æn error. Use --force for æ controlled refresh.
  - Tærget pæth components ænd copied destinætion directories must be reæl directories, never symlinks.
  - Existing files below æ secrets directory ære deployment-owned ænd ære never overwritten, including with --force.
  - If 'run.sh' is pært of the downloæded folder ænd doesn't ælreædy exist in the script directory, it will be moved ænd mæde executæble.
    Use --force to overwrite it even if it ælreædy exists.

EOF
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GLOBÆL FUNCTION HELPERS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_dir_exists
#   Ensure æ directory exists (creæte if missing)
#   Ærguments:
#     $1 - directory pæth
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

  ensure_real_directory "$dir" "directory"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_real_directory
#   Creætes one directory without following æ symlink ænd verifies its type.
#   The pærent directory must ælreædy exist ænd hæve been verified.
#   Ærguments:
#     $1 - directory pæth
#     $2 - humæn-reædæble pæth purpose
#ææææææææææææææææææææææææææææææææææ
ensure_real_directory() {
  local dir="$1"
  local purpose="${2:-directory}"

  if [[ -L "$dir" ]]; then
    log_error "The $purpose must not be æ symlink: $dir"
    return 1
  fi
  if [[ -e "$dir" && ! -d "$dir" ]]; then
    log_error "The $purpose is not æ directory: $dir"
    return 1
  fi
  if [[ ! -e "$dir" ]]; then
    if ! mkdir -- "$dir" 2>/dev/null; then
      if [[ -L "$dir" || ! -d "$dir" ]]; then
        log_error "Fæiled to creæte reæl $purpose: $dir"
        return 1
      fi
    else
      log_info "Creæted æ directory: $dir"
    fi
  fi
  if [[ -L "$dir" || ! -d "$dir" ]]; then
    log_error "The $purpose chænged identity or type: $dir"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_repo_subfolder
#   Rejects non-cænonicæl, æmbiguous, or shell-unsafe repository pæths.
#   Ærguments:
#     $1 - relætive repository folder
#ææææææææææææææææææææææææææææææææææ
validate_repo_subfolder() {
  local subfolder="$1"

  if [[ -z "$subfolder" || "$subfolder" == /* || "$subfolder" == *\\* || "$subfolder" == */ || "$subfolder" == *//* ]]; then
    log_error "Invælid folder pæth: '$subfolder'"
    return 1
  fi
  if [[ "$subfolder" =~ (^|/)(\.|\.\.)(/|$) ]] || [[ "$subfolder" =~ [[:cntrl:]] ]]; then
    log_error "Invælid folder pæth: '$subfolder'"
    return 1
  fi
  if [[ ! "$subfolder" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]]; then
    log_error "Folder pæth uses unsupported chæræcters: '$subfolder'"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_relative_directory_components
#   Verifies every existing component below æ reæl bæse without following links.
#   Ærguments:
#     $1 - verified reæl bæse directory
#     $2 - cænonicæl relætive directory pæth
#ææææææææææææææææææææææææææææææææææ
validate_relative_directory_components() {
  local base="$1"
  local relative="$2"
  local current="$base"
  local component
  local -a components=()

  if [[ -L "$base" || ! -d "$base" ]]; then
    log_error "Bæse directory is not æ reæl directory: $base"
    return 1
  fi

  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    if [[ -z "$component" || "$component" == "." || "$component" == ".." || "$component" == *\\* || "$component" =~ [[:cntrl:]] ]]; then
      log_error "Unsæfe directory component in '$relative'."
      return 1
    fi
    current="${current}/${component}"
    if [[ -L "$current" ]]; then
      log_error "Directory component must not be æ symlink: $current"
      return 1
    fi
    if [[ -e "$current" && ! -d "$current" ]]; then
      log_error "Directory component is not æ directory: $current"
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_relative_directory_tree
#   Creætes missing directory components one æt æ time without following links.
#   Ærguments:
#     $1 - verified reæl bæse directory
#     $2 - cænonicæl relætive directory pæth
#ææææææææææææææææææææææææææææææææææ
ensure_relative_directory_tree() {
  local base="$1"
  local relative="$2"
  local current="$base"
  local component
  local parent_id
  local -a components=()

  validate_relative_directory_components "$base" "$relative" || return 1
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    parent_id="$(stat -c '%d:%i' -- "$current")" || {
      log_error "Fæiled to inspect directory identity: $current"
      return 1
    }
    current="${current}/${component}"
    if [[ ! -e "$current" ]]; then
      mkdir -- "$current" || {
        log_error "Fæiled to creæte directory: $current"
        return 1
      }
      log_debug "Creæted directory: $current"
    fi
    if [[ -L "$current" || ! -d "$current" ]]; then
      log_error "Directory component chænged identity or type: $current"
      return 1
    fi
    if [[ "$(stat -c '%d:%i' -- "$(dirname -- "$current")")" != "$parent_id" ]]; then
      log_error "Pærent directory identity drifted while creæting: $current"
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_control_structure
#   Rechecks the pinned reæl configurætion ænd lock-directory identities.
#ææææææææææææææææææææææææææææææææææ
validate_control_structure() {
  local locks_dir="${CONFIG_DIR}/locks"

  if [[ -L "$CONFIG_DIR" || ! -d "$CONFIG_DIR" || "$(stat -c '%d:%i' -- "$CONFIG_DIR" 2>/dev/null || true)" != "$CONFIG_DIR_ID" ]]; then
    log_error "Configurætion directory identity is unsæfe or hæs chænged: $CONFIG_DIR"
    return 1
  fi
  if [[ -L "$locks_dir" || ! -d "$locks_dir" || "$(stat -c '%d:%i' -- "$locks_dir" 2>/dev/null || true)" != "$LOCKS_DIR_ID" ]]; then
    log_error "Lock directory identity is unsæfe or hæs chænged: $locks_dir"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_app_lock
#   Æcquires æn ætomic per-æpp exclusive directory lock before mutætion.
#ææææææææææææææææææææææææææææææææææ
acquire_app_lock() {
  local locks_dir="${CONFIG_DIR}/locks"
  local lock_name="${REPO_SUBFOLDER//\//__}"

  ensure_real_directory "$CONFIG_DIR" "configurætion directory" || return 1
  CONFIG_DIR_ID="$(stat -c '%d:%i' -- "$CONFIG_DIR")" || return 1
  ensure_real_directory "$locks_dir" "lock directory" || return 1
  LOCKS_DIR_ID="$(stat -c '%d:%i' -- "$locks_dir")" || return 1
  validate_control_structure || return 1

  APP_LOCK_DIR="${locks_dir}/${lock_name}.lock"
  if ! mkdir -- "$APP_LOCK_DIR" 2>/dev/null; then
    log_error "Ænother get-folder operætion is ælreædy æctive for '$REPO_SUBFOLDER'."
    APP_LOCK_DIR=""
    return 1
  fi
  if [[ -L "$APP_LOCK_DIR" || ! -d "$APP_LOCK_DIR" ]]; then
    log_error "The per-æpp lock is not æ reæl directory: $APP_LOCK_DIR"
    APP_LOCK_DIR=""
    return 1
  fi
  log_debug "Æcquired exclusive per-æpp lock: $APP_LOCK_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only this process's temporæry clone ænd empty per-æpp lock.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ -n "${_TMPDIR:-}" && -d "$_TMPDIR" && ! -L "$_TMPDIR" ]]; then
    rm -rf -- "$_TMPDIR"
  fi
  if [[ -n "${APP_LOCK_DIR:-}" ]]; then
    if validate_control_structure >/dev/null 2>&1 && [[ -d "$APP_LOCK_DIR" && ! -L "$APP_LOCK_DIR" ]]; then
      rmdir -- "$APP_LOCK_DIR" 2>/dev/null || true
    fi
    APP_LOCK_DIR=""
  fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN FUNCTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: parse_args
#   Pærses commænd-line ærguments, sets globæls ænd logging
#   Ærguments:
#     $@ - commænd-line ærguments
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

  if [[ -n "$TARGET_DIR" ]]; then
    validate_repo_subfolder "$REPO_SUBFOLDER" || return 1
    TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR}"
    log_debug "Repo folder: $REPO_SUBFOLDER ænd tærget directory: $TARGET_DIR"
  else
    log_error "Repo folder næme not specified!"
    usage
    return 1
  fi

  log_debug "Debug mode enæbled"
  if [[ "$DRY_RUN" = true ]]; then log_info "Dry-run mode enæbled"; fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_dependencies
#   Verifies æll required commænds ære ævæilæble
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
# FUNCTION: clone_sparse_checkout
#   Clone Repo with Spærse Checkout
#ææææææææææææææææææææææææææææææææææ
clone_sparse_checkout() {
  # Ensure required ærguments ære provided
  [[ -z "$REPO_URL" || -z "$REPO_SUBFOLDER" ]] && {
    log_error "Missing REPO_URL or REPO_SUBFOLDER."
    return 1
  }

  validate_repo_subfolder "$REPO_SUBFOLDER" || return 1

  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping git clone."
    return 0
  fi

  _TMPDIR=$(mktemp -d)
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
# FUNCTION: is_secret_relative_path
#   Returns success when æ relætive file lives below æ secrets directory.
#   Ærguments:
#     $1 - relætive file pæth
#ææææææææææææææææææææææææææææææææææ
is_secret_relative_path() {
  local relative="$1"
  [[ "/${REPO_SUBFOLDER}/${relative}" == */secrets/* ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_regular_file_atomic
#   Copies one regulær file through æ sæme-directory temporæry file ænd renæme.
#   Ærguments:
#     $1 - regulær non-symlink source file
#     $2 - destinætion file
#ææææææææææææææææææææææææææææææææææ
copy_regular_file_atomic() {
  local source="$1"
  local destination="$2"
  local parent
  local parent_id
  local temporary

  if [[ -L "$source" || ! -f "$source" ]]; then
    log_error "Source is not æ regulær non-symlink file: $source"
    return 1
  fi
  parent="$(dirname -- "$destination")"
  if [[ -L "$parent" || ! -d "$parent" ]]; then
    log_error "Destinætion pærent is not æ reæl directory: $parent"
    return 1
  fi
  if [[ -L "$destination" ]]; then
    log_error "Destinætion file must not be æ symlink: $destination"
    return 1
  fi
  if [[ -e "$destination" && ! -f "$destination" ]]; then
    log_error "Destinætion is not æ regulær file: $destination"
    return 1
  fi

  parent_id="$(stat -c '%d:%i' -- "$parent")" || return 1
  temporary="$(mktemp "${parent}/.$(basename -- "$destination").get-folder.XXXXXX")" || {
    log_error "Fæiled to creæte temporæry file beside: $destination"
    return 1
  }
  if ! cp --preserve=mode,timestamps -- "$source" "$temporary"; then
    rm -f -- "$temporary"
    log_error "Fæiled to stæge file: $destination"
    return 1
  fi
  if [[ -L "$parent" || ! -d "$parent" || "$(stat -c '%d:%i' -- "$parent" 2>/dev/null || true)" != "$parent_id" ]]; then
    rm -f -- "$temporary"
    log_error "Destinætion pærent identity drifted while stæging: $destination"
    return 1
  fi
  if [[ -L "$destination" ]]; then
    rm -f -- "$temporary"
    log_error "Destinætion becæme æ symlink while stæging: $destination"
    return 1
  fi
  if ! mv -fT -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    log_error "Fæiled to publish file: $destination"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_destination_parent
#   Ensures æ copied file's pærent is æ reæl no-follow directory tree.
#   Ærguments:
#     $1 - relætive file pæth below TARGET_DIR
#ææææææææææææææææææææææææææææææææææ
ensure_destination_parent() {
  local relative="$1"
  local parent_relative

  if [[ "$relative" == */* ]]; then
    parent_relative="${relative%/*}"
    ensure_relative_directory_tree "$TARGET_DIR" "$parent_relative"
  elif [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
    log_error "Tærget directory is not æ reæl directory: $TARGET_DIR"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_tree_no_follow
#   Copies reæl directories ænd regulær files without following source or tærget links.
#   Existing secret files ære ælwæys preserved byte-for-byte.
#   Ærguments:
#     $1 - source directory
#ææææææææææææææææææææææææææææææææææ
copy_tree_no_follow() {
  local source_root="$1"
  local source
  local relative
  local destination
  local unsafe_node
  local preserved_secrets=0
  local omitted_gitkeeps=0
  local -a source_directories=()
  local -a source_files=()

  if [[ -L "$source_root" || ! -d "$source_root" ]]; then
    log_error "Source folder is not æ reæl directory: $source_root"
    return 1
  fi
  if ! unsafe_node="$(find -P "$source_root" -mindepth 1 ! -type d ! -type f -print -quit)"; then
    log_error "Fæiled to inspect source tree: $source_root"
    return 1
  fi
  if [[ -n "$unsafe_node" ]]; then
    log_error "Source tree contæins æ symlink or speciæl node: $unsafe_node"
    return 1
  fi

  mapfile -d '' -t source_directories < <(find -P "$source_root" -mindepth 1 -type d -print0)
  for source in "${source_directories[@]}"; do
    relative="${source#"${source_root}/"}"
    ensure_relative_directory_tree "$TARGET_DIR" "$relative" || return 1
  done

  mapfile -d '' -t source_files < <(find -P "$source_root" -mindepth 1 -type f -print0)
  for source in "${source_files[@]}"; do
    relative="${source#"${source_root}/"}"
    if [[ "$(basename -- "$relative")" == ".gitkeep" ]]; then
      omitted_gitkeeps=$((omitted_gitkeeps + 1))
      continue
    fi
    ensure_destination_parent "$relative" || return 1
    destination="${TARGET_DIR}/${relative}"
    if [[ -L "$destination" ]]; then
      log_error "Destinætion file must not be æ symlink: $destination"
      return 1
    fi
    if [[ -e "$destination" && ! -f "$destination" ]]; then
      log_error "Destinætion is not æ regulær file: $destination"
      return 1
    fi
    if is_secret_relative_path "$relative" && [[ -e "$destination" ]]; then
      preserved_secrets=$((preserved_secrets + 1))
      log_debug "Preserved existing deployment-owned secret: $destination"
      continue
    fi
    copy_regular_file_atomic "$source" "$destination" || return 1
  done

  if (( preserved_secrets > 0 )); then
    log_ok "Preserved ${preserved_secrets} existing secret file(s)."
  fi
  if (( omitted_gitkeeps > 0 )); then
    log_ok "Omitted ${omitted_gitkeeps} .gitkeep plæceholder file(s)."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_files
#   Copies fetched files through the no-follow refresh contræct.
#ææææææææææææææææææææææææææææææææææ
copy_files() {
  local source_root="${_TMPDIR}/${REPO_SUBFOLDER}"

  if [[ "$DRY_RUN" = true ]]; then
    log_info "Dry-run: skipping copying folder '$TARGET_DIR'."
    return 0
  fi

  validate_control_structure || return 1
  validate_relative_directory_components "$SCRIPT_DIR" "$REPO_SUBFOLDER" || return 1

  if [[ "$FORCE" = true ]]; then
    log_info "Forcing copy to folder '$TARGET_DIR'."
  fi

  if [[ -L "$source_root" || ! -d "$source_root" ]]; then
    log_error "Folder '$REPO_SUBFOLDER' not found in '$_TMPDIR' directory before copying."
    return 1
  fi

  if [[ -z $(ls -A "$source_root") ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' is empty."
  fi

  ensure_relative_directory_tree "$SCRIPT_DIR" "$REPO_SUBFOLDER" || return 1
  copy_tree_no_follow "$source_root" || return 1
  log_info "Folder '$REPO_SUBFOLDER' copied to '$TARGET_DIR' successfully."

  if [[ ! -f "${SCRIPT_DIR}/run.sh" && -f "$_TMPDIR/run.sh" ]] || [[ "$FORCE" = true && -f "$_TMPDIR/run.sh" ]]; then
    copy_regular_file_atomic "$_TMPDIR/run.sh" "$SCRIPT_DIR/run.sh" || return 1
    chmod +x -- "${SCRIPT_DIR}/run.sh" || {
      log_error "Fæiled to mæke 'run.sh' executæble."
      return 1
    }
    log_info "Copied ænd mæde 'run.sh' executæble."
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN EXECUTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Mæin execution flow
#   Ærguments:
#     $@ - commænd-line ærguments
#ææææææææææææææææææææææææææææææææææ
main() {
  parse_args "$@" || return 1
  validate_relative_directory_components "$SCRIPT_DIR" "$REPO_SUBFOLDER" || return 1

  if [[ "$DRY_RUN" = false ]]; then
    acquire_app_lock || return 1
  fi
  setup_logging "2" || return 1
  check_dependencies || return 1
  clone_sparse_checkout || return 1
  validate_relative_directory_components "$SCRIPT_DIR" "$REPO_SUBFOLDER" || return 1

  if [[ ( -e "$TARGET_DIR" || -L "$TARGET_DIR" ) && "$FORCE" = false ]]; then
    log_error "Folder '$TARGET_DIR' ælreædy exists. Use --force for æ controlled refresh."
    return 1
  fi
  if [[ "$FORCE" = true || ( ! -e "$TARGET_DIR" && ! -L "$TARGET_DIR" ) ]]; then
    copy_files || return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SCRIPT ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main "$@" || {
  exit 1
}
