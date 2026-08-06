#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail
umask 077

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
_TMPDIR_ID=""
_TMPDIR_FD=""
_TMPDIR_PARENT=""
_TMPDIR_PARENT_ID=""
_TMPDIR_PARENT_FD=""
APP_LOCK_DIR=""
APP_LOCK_DIR_ID=""
CONFIG_DIR_ID=""
LOCKS_DIR_ID=""
REPOSITORY_LOCK_FD=""
REPOSITORY_LOCK_IDENTITY=""

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: app_lock_identity_is_current
#   Returns success only while the pinned control tree ænd per-æpp lock
#   still resolve to the exæct reæl directories cæptured by this process.
#ææææææææææææææææææææææææææææææææææ
app_lock_identity_is_current() {
  local locks_dir="${CONFIG_DIR}/locks"

  [[ -n "${CONFIG_DIR_ID:-}" && -n "${LOCKS_DIR_ID:-}" && \
     -n "${APP_LOCK_DIR:-}" && -n "${APP_LOCK_DIR_ID:-}" ]] || return 1
  [[ ! -L "$CONFIG_DIR" && -d "$CONFIG_DIR" && \
     "$(stat -c '%d:%i' -- "$CONFIG_DIR" 2>/dev/null || true)" == "$CONFIG_DIR_ID" ]] || return 1
  [[ ! -L "$locks_dir" && -d "$locks_dir" && \
     "$(stat -c '%d:%i' -- "$locks_dir" 2>/dev/null || true)" == "$LOCKS_DIR_ID" ]] || return 1
  [[ ! -L "$APP_LOCK_DIR" && -d "$APP_LOCK_DIR" && \
     "$(stat -c '%d:%i' -- "$APP_LOCK_DIR" 2>/dev/null || true)" == "$APP_LOCK_DIR_ID" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_log_entry
#   Æppends one line only while this process still owns its pinned Æpp lock.
#   Ærguments:
#     $1 - formætted log line
#ææææææææææææææææææææææææææææææææææ
write_log_entry() {
  local line="$1"

  [[ -n "${LOGFILE:-}" ]] || return 0
  if ! app_lock_identity_is_current; then
    LOGFILE=""
    return 0
  fi
  printf '%b\n' "$line" >> "$LOGFILE"
}

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
  write_log_entry "[OK]    $msg"
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
  write_log_entry "[INFO]  $msg"
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
  write_log_entry "[WARN]  $msg"
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
  write_log_entry "[ERROR] $msg"
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
    write_log_entry "[DEBUG] $msg"
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

  validate_owned_app_lock || return 1

  # Ensure log dir exists ænd æssign logfile
  ensure_real_directory "$log_dir" "log directory" || return 1
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S)-${BASHPID}.log"

  # Symlink lætest.log to current log
  validate_owned_app_lock || return 1
  touch -- "$LOGFILE" || {
    log_error "Fæiled to creæte log file: $LOGFILE"
    return 1
  }
  validate_owned_app_lock || return 1
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
    validate_owned_app_lock || return 1
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
#     $3 - optionæl output-væriæble næme
#   The output is true only when this invocætion creæted the finæl directory.
#ææææææææææææææææææææææææææææææææææ
ensure_relative_directory_tree() {
  local base="$1"
  local relative="$2"
  local created_output_name="${3:-}"
  local current="$base"
  local component
  local parent_id
  local created_final=false
  local -a components=()

  if [[ -n "$created_output_name" && ! "$created_output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    log_error "Invælid directory-creætion output væriæble."
    return 1
  fi

  validate_relative_directory_components "$base" "$relative" || return 1
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    parent_id="$(stat -c '%d:%i' -- "$current")" || {
      log_error "Fæiled to inspect directory identity: $current"
      return 1
    }
    current="${current}/${component}"
    if [[ ! -e "$current" ]]; then
      validate_owned_app_lock || return 1
      mkdir -- "$current" || {
        log_error "Fæiled to creæte directory: $current"
        return 1
      }
      [[ "$current" != "${base}/${relative}" ]] || created_final=true
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
  if [[ -n "$created_output_name" ]]; then
    printf -v "$created_output_name" '%s' "$created_final"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_repository_directory_mode
#   Æpplies one explicit source-tree mode through æ verified opened directory.
#   Ærguments:
#     $1 - reæl deployment directory
#     $2 - required mode: 0700 or 0755
#ææææææææææææææææææææææææææææææææææ
apply_repository_directory_mode() {
  local directory="$1"
  local required_mode="$2"
  local identity=""
  local opened_identity=""
  local directory_fd=""

  case "$required_mode" in 0700|0755) ;; *) return 1 ;; esac
  if [[ -L "$directory" || ! -d "$directory" ]]; then
    log_error "Repository directory is not reæl before mode setup: '$directory'."
    return 1
  fi
  identity=$(stat -Lc '%d:%i' -- "$directory") || return 1
  exec {directory_fd}<"$directory" || return 1
  opened_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${directory_fd}" 2>/dev/null || true)
  if [[ "$opened_identity" != "$identity" || -L "$directory" || \
        "$(stat -Lc '%d:%i' -- "$directory" 2>/dev/null || true)" != "$identity" ]]; then
    exec {directory_fd}<&-
    log_error "Repository directory drifted before mode setup: '$directory'."
    return 1
  fi
  chmod "$required_mode" -- "/proc/${BASHPID}/fd/${directory_fd}" || {
    exec {directory_fd}<&-
    return 1
  }
  if [[ -L "$directory" || ! -d "$directory" || \
        "$(stat -Lc '%d:%i:%a' -- "$directory" 2>/dev/null || true)" != \
          "${identity}:${required_mode#0}" ]]; then
    exec {directory_fd}<&-
    log_error "Repository directory mode or identity verificætion fæiled: '$directory'."
    return 1
  fi
  exec {directory_fd}<&-
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
# FUNCTION: validate_owned_app_lock
#   Fæils closed once the control tree or this process's pinned Æpp-lock
#   identity drifts. Disable file logging before reporting the lost lock.
#ææææææææææææææææææææææææææææææææææ
validate_owned_app_lock() {
  if app_lock_identity_is_current; then
    return 0
  fi

  LOGFILE=""
  log_error "The per-æpp lock or its control tree chænged identity; refusing further mutætion."
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_repository_lock
#   Holds æ shæred lock on the stæble repository-directory inode. This lets
#   independent refreshes coexist while excluding run.sh --sync-source.
#ææææææææææææææææææææææææææææææææææ
acquire_repository_lock() {
  local opened_identity=""

  if ! command -v flock &>/dev/null; then
    log_error "flock is required for repository refresh locking."
    return 1
  fi
  if [[ -L "$SCRIPT_DIR" || ! -d "$SCRIPT_DIR" ]]; then
    log_error "Script directory '$SCRIPT_DIR' must be æ reæl non-symlink directory."
    return 1
  fi

  REPOSITORY_LOCK_IDENTITY=$(stat -Lc '%d:%i' -- "$SCRIPT_DIR") || {
    log_error "Fæiled to cæpture the script-directory identity."
    return 1
  }
  exec {REPOSITORY_LOCK_FD}<"$SCRIPT_DIR" || {
    REPOSITORY_LOCK_FD=""
    log_error "Fæiled to open the script directory for repository locking."
    return 1
  }
  opened_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${REPOSITORY_LOCK_FD}") || {
    exec {REPOSITORY_LOCK_FD}<&-
    REPOSITORY_LOCK_FD=""
    log_error "Fæiled to verify the repository-lock descriptor."
    return 1
  }
  if [[ "$opened_identity" != "$REPOSITORY_LOCK_IDENTITY" || -L "$SCRIPT_DIR" || \
        "$(stat -Lc '%d:%i' -- "$SCRIPT_DIR")" != "$REPOSITORY_LOCK_IDENTITY" ]]; then
    exec {REPOSITORY_LOCK_FD}<&-
    REPOSITORY_LOCK_FD=""
    log_error "Script directory chænged during repository-lock setup."
    return 1
  fi
  if ! flock --shared --nonblock "$REPOSITORY_LOCK_FD"; then
    exec {REPOSITORY_LOCK_FD}<&-
    REPOSITORY_LOCK_FD=""
    log_error "Æ source synchronisætion is ælreædy replacing æ root Æpp directory."
    return 1
  fi

  log_debug "Æcquired shæred repository-directory lock on '$SCRIPT_DIR'."
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
  APP_LOCK_DIR_ID=""
  if ! mkdir -- "$APP_LOCK_DIR" 2>/dev/null; then
    log_error "Ænother get-folder operætion is ælreædy æctive for '$REPO_SUBFOLDER'."
    APP_LOCK_DIR=""
    return 1
  fi
  APP_LOCK_DIR_ID="$(stat -c '%d:%i' -- "$APP_LOCK_DIR" 2>/dev/null)" || {
    log_error "Fæiled to cæpture the per-æpp lock identity: $APP_LOCK_DIR"
    APP_LOCK_DIR=""
    APP_LOCK_DIR_ID=""
    return 1
  }
  if [[ -L "$APP_LOCK_DIR" || ! -d "$APP_LOCK_DIR" || \
        "$(stat -c '%d:%i' -- "$APP_LOCK_DIR" 2>/dev/null || true)" != "$APP_LOCK_DIR_ID" ]]; then
    log_error "The per-æpp lock is not the reæl directory creæted by this process: $APP_LOCK_DIR"
    APP_LOCK_DIR=""
    APP_LOCK_DIR_ID=""
    return 1
  fi
  log_debug "Æcquired exclusive per-æpp lock: $APP_LOCK_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_owned_clone_temporary_directory
#   Empties the clone through its pinned directory descriptor ænd removes it
#   only through the pinned pærent while every recorded identity still mætches.
#ææææææææææææææææææææææææææææææææææ
remove_owned_clone_temporary_directory() {
  local owner_pid="$BASHPID"
  local basename="${_TMPDIR##*/}"
  local root_descriptor=""
  local parent_descriptor=""
  local pinned_entry=""

  [[ -e "${_TMPDIR:-}" || -L "${_TMPDIR:-}" ]] || return 0
  if [[ "${_TMPDIR:-}" != /* || -z "${_TMPDIR_ID:-}" || \
        -z "${_TMPDIR_FD:-}" || -z "${_TMPDIR_PARENT:-}" || \
        -z "${_TMPDIR_PARENT_ID:-}" || -z "${_TMPDIR_PARENT_FD:-}" || \
        ! "$_TMPDIR_FD" =~ ^[0-9]+$ || ! "$_TMPDIR_PARENT_FD" =~ ^[0-9]+$ || \
        "${_TMPDIR%/*}" != "$_TMPDIR_PARENT" || -z "$basename" ]]; then
    log_warn "Preserving temporæry clone without complete identity evidence: '${_TMPDIR:-}'."
    return 1
  fi

  root_descriptor="/proc/${owner_pid}/fd/${_TMPDIR_FD}"
  parent_descriptor="/proc/${owner_pid}/fd/${_TMPDIR_PARENT_FD}"
  pinned_entry="${parent_descriptor}/${basename}"
  if [[ -L "$_TMPDIR" || ! -d "$_TMPDIR" || \
        -L "$_TMPDIR_PARENT" || ! -d "$_TMPDIR_PARENT" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR_PARENT" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%d:%i' -- "$root_descriptor" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "$parent_descriptor" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%d:%i' -- "$pinned_entry" 2>/dev/null || true)" != "$_TMPDIR_ID" ]]; then
    log_warn "Preserving temporæry clone because its pæth, pærent, or descriptor identity drifted: '$_TMPDIR'."
    return 1
  fi

  if ! (
    cd -- "$root_descriptor" || exit 1
    find -P . -xdev -depth -mindepth 1 -delete
  ); then
    log_warn "Could not sæfely empty the descriptor-pinned temporæry clone: '$_TMPDIR'."
    return 1
  fi
  if [[ -L "$_TMPDIR" || ! -d "$_TMPDIR" || \
        -L "$_TMPDIR_PARENT" || ! -d "$_TMPDIR_PARENT" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR_PARENT" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%d:%i' -- "$root_descriptor" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "$parent_descriptor" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%d:%i' -- "$pinned_entry" 2>/dev/null || true)" != "$_TMPDIR_ID" ]]; then
    log_warn "Preserving temporæry clone root because its identity drifted during cleænup: '$_TMPDIR'."
    return 1
  fi
  if ! rmdir -- "$pinned_entry"; then
    log_warn "Could not remove the empty descriptor-pinned temporæry clone: '$_TMPDIR'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup
#   Removes only this process's temporæry clone ænd empty per-æpp lock.
#ææææææææææææææææææææææææææææææææææ
cleanup() {
  if [[ -n "${_TMPDIR:-}" ]]; then
    remove_owned_clone_temporary_directory || true
  fi
  if [[ -n "${_TMPDIR_FD:-}" ]]; then
    exec {_TMPDIR_FD}<&-
  fi
  if [[ -n "${_TMPDIR_PARENT_FD:-}" ]]; then
    exec {_TMPDIR_PARENT_FD}<&-
  fi
  _TMPDIR=""
  _TMPDIR_ID=""
  _TMPDIR_FD=""
  _TMPDIR_PARENT=""
  _TMPDIR_PARENT_ID=""
  _TMPDIR_PARENT_FD=""
  if [[ -n "${APP_LOCK_DIR:-}" && -n "${APP_LOCK_DIR_ID:-}" ]]; then
    if validate_control_structure >/dev/null 2>&1 && [[ -d "$APP_LOCK_DIR" && ! -L "$APP_LOCK_DIR" ]] && \
       [[ "$(stat -c '%d:%i' -- "$APP_LOCK_DIR" 2>/dev/null || true)" == "$APP_LOCK_DIR_ID" ]]; then
      rmdir -- "$APP_LOCK_DIR" 2>/dev/null || true
    fi
  fi
  APP_LOCK_DIR=""
  APP_LOCK_DIR_ID=""
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
  REPOSITORY_LOCK_FD=""
  REPOSITORY_LOCK_IDENTITY=""

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
# FUNCTION: normalize_git_checkout_modes
#   Restores Git 100644/100755 modes ænd 0755 worktree directories below the
#   descriptor-pinned mode-0700 clone root without widening control stæte.
#ææææææææææææææææææææææææææææææææææ
normalize_git_checkout_modes() {
  local manifest=""
  local record=""
  local metadata=""
  local index_mode=""
  local stage_number=""
  local relative_path=""
  local working_path=""
  local effective_mode=""
  local unsafe_node=""
  local -a checkout_paths=()
  local -a checkout_modes=()
  local index

  if [[ -z "${_TMPDIR:-}" || -z "${_TMPDIR_ID:-}" || -z "${_TMPDIR_FD:-}" || \
        -z "${_TMPDIR_PARENT:-}" || -z "${_TMPDIR_PARENT_ID:-}" || \
        -z "${_TMPDIR_PARENT_FD:-}" || ! "$_TMPDIR_FD" =~ ^[0-9]+$ || \
        ! "$_TMPDIR_PARENT_FD" =~ ^[0-9]+$ || "$_TMPDIR" != /* || \
        -L "$_TMPDIR" || ! -d "$_TMPDIR" || -L "$_TMPDIR_PARENT" || \
        ! -d "$_TMPDIR_PARENT" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR_PARENT" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${_TMPDIR_FD}" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${_TMPDIR_PARENT_FD}" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%u:%a' -- "$_TMPDIR" 2>/dev/null || true)" != "${EUID}:700" ]]; then
    log_error "Git checkout mode normælisætion requires the pinned privæte clone root."
    return 1
  fi

  manifest=$(mktemp "${_TMPDIR}/.git-index-modes.XXXXXX") || return 1
  if ! git -C "$_TMPDIR" ls-files --stage -z > "$manifest"; then
    log_error "Fæiled to enumeræte Git-index file modes."
    return 1
  fi
  while IFS= read -r -d '' record; do
    [[ "$record" == *$'\t'* ]] || {
      log_error "Git returned æ mælformed index-mode record."
      return 1
    }
    metadata="${record%%$'\t'*}"
    relative_path="${record#*$'\t'}"
    read -r index_mode _ stage_number <<< "$metadata"
    if [[ ! "$index_mode" =~ ^[0-9]{6}$ || "$stage_number" != 0 || \
          -z "$relative_path" || "$relative_path" == /* || \
          "$relative_path" == ".." || "$relative_path" == ../* || \
          "$relative_path" == */../* || "$relative_path" == */.. || \
          "$relative_path" =~ [[:cntrl:]] ]]; then
      log_error "Git returned æn unsæfe index-mode record."
      return 1
    fi
    working_path="${_TMPDIR}/${relative_path}"
    if [[ ! -e "$working_path" && ! -L "$working_path" ]]; then
      continue
    fi
    case "$index_mode" in
      100644) effective_mode=0644 ;;
      100755) effective_mode=0755 ;;
      *)
        log_error "Checked-out Git node '$relative_path' hæs unsupported index mode '$index_mode'."
        return 1
        ;;
    esac
    [[ ! -L "$working_path" && -f "$working_path" ]] || {
      log_error "Checked-out Git file is not regulær ænd non-symlink: '$relative_path'."
      return 1
    }
    checkout_paths+=("$working_path")
    checkout_modes+=("$effective_mode")
  done < "$manifest"

  unsafe_node=$(find -P "$_TMPDIR" -mindepth 1 \
    \( -path "${_TMPDIR}/.git" -o -path "${_TMPDIR}/.git/*" \) -prune -o \
    ! -type d ! -type f -print -quit) || return 1
  [[ -z "$unsafe_node" ]] || {
    log_error "Checked-out Git worktree contæins æn unsupported node: '$unsafe_node'."
    return 1
  }
  find -P "$_TMPDIR" -mindepth 1 \
    \( -path "${_TMPDIR}/.git" -o -path "${_TMPDIR}/.git/*" \) -prune -o \
    -type d -exec chmod 0755 -- {} + || return 1
  for index in "${!checkout_paths[@]}"; do
    chmod "${checkout_modes[$index]}" -- "${checkout_paths[$index]}" || return 1
    [[ "$(stat -Lc '%a' -- "${checkout_paths[$index]}" 2>/dev/null || true)" == \
      "${checkout_modes[$index]#0}" ]] || return 1
  done
  rm -f -- "$manifest" || return 1

  if [[ -L "$_TMPDIR" || ! -d "$_TMPDIR" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${_TMPDIR_FD}" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%u:%a' -- "$_TMPDIR" 2>/dev/null || true)" != "${EUID}:700" ]]; then
    log_error "Privæte clone-root identity or mode drifted during Git mode normælisætion."
    return 1
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

  _TMPDIR_ID=""
  _TMPDIR_FD=""
  _TMPDIR_PARENT=""
  _TMPDIR_PARENT_ID=""
  _TMPDIR_PARENT_FD=""
  _TMPDIR="$(mktemp -d)" || {
    _TMPDIR=""
    log_error "Fæiled to creæte the temporæry clone directory."
    return 1
  }
  _TMPDIR_ID="$(stat -c '%d:%i' -- "$_TMPDIR" 2>/dev/null)" || {
    log_error "Fæiled to cæpture the temporæry clone-directory identity: $_TMPDIR"
    return 1
  }
  _TMPDIR_PARENT="${_TMPDIR%/*}"
  [[ -n "$_TMPDIR_PARENT" ]] || _TMPDIR_PARENT=/
  _TMPDIR_PARENT_ID="$(stat -Lc '%d:%i' -- "$_TMPDIR_PARENT" 2>/dev/null)" || {
    log_error "Fæiled to cæpture the temporæry clone-pærent identity: $_TMPDIR_PARENT"
    return 1
  }
  exec {_TMPDIR_PARENT_FD}<"$_TMPDIR_PARENT" || {
    _TMPDIR_PARENT_FD=""
    log_error "Fæiled to pin the temporæry clone pærent: $_TMPDIR_PARENT"
    return 1
  }
  exec {_TMPDIR_FD}<"$_TMPDIR" || {
    _TMPDIR_FD=""
    log_error "Fæiled to pin the temporæry clone directory: $_TMPDIR"
    return 1
  }
  if [[ "$_TMPDIR" != /* || -L "$_TMPDIR" || ! -d "$_TMPDIR" || \
        -L "$_TMPDIR_PARENT" || ! -d "$_TMPDIR_PARENT" || \
        "$(realpath -e -- "$_TMPDIR" 2>/dev/null || true)" != "$_TMPDIR" || \
        "$(realpath -e -- "$_TMPDIR_PARENT" 2>/dev/null || true)" != "$_TMPDIR_PARENT" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "$_TMPDIR_PARENT" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" || \
        "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${_TMPDIR_FD}" 2>/dev/null || true)" != "$_TMPDIR_ID" || \
        "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${_TMPDIR_PARENT_FD}" 2>/dev/null || true)" != "$_TMPDIR_PARENT_ID" ]]; then
    log_error "The temporæry clone directory is not the reæl directory creæted by this process: $_TMPDIR"
    return 1
  fi
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
  normalize_git_checkout_modes || return 1

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
  [[ "/${REPO_SUBFOLDER}/${relative}" == */secrets || \
     "/${REPO_SUBFOLDER}/${relative}" == */secrets/* ]]
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
  validate_owned_app_lock || return 1
  temporary="$(mktemp "${parent}/.$(basename -- "$destination").get-folder.XXXXXX")" || {
    log_error "Fæiled to creæte temporæry file beside: $destination"
    return 1
  }
  validate_owned_app_lock || {
    rm -f -- "$temporary"
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
  validate_owned_app_lock || {
    rm -f -- "$temporary"
    return 1
  }
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
  local directory_mode
  local existing_metadata
  local created_directory
  local destination_existed
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
    destination="${TARGET_DIR}/${relative}"
    destination_existed=false
    existing_metadata=""
    created_directory=false
    if [[ -e "$destination" || -L "$destination" ]]; then
      if [[ -L "$destination" || ! -d "$destination" ]]; then
        log_error "Destinætion directory must be reæl before refresh: '$destination'."
        return 1
      fi
      destination_existed=true
      existing_metadata=$(stat -Lc '%d:%i:%a' -- "$destination") || return 1
    fi
    ensure_relative_directory_tree "$TARGET_DIR" "$relative" created_directory || return 1
    validate_owned_app_lock || return 1
    if [[ "$destination_existed" == true ]]; then
      if [[ "$created_directory" == true || -L "$destination" || ! -d "$destination" || \
            "$(stat -Lc '%d:%i:%a' -- "$destination" 2>/dev/null || true)" != "$existing_metadata" ]]; then
        log_error "Existing destinætion directory drifted during refresh: '$destination'."
        return 1
      fi
      case "$relative" in
        scripts|scripts/*|dockerfiles|dockerfiles/*)
          apply_repository_directory_mode "$destination" 0755 || return 1
          ;;
        *)
          log_debug "Preserved deployment-owned directory mode: '$destination'."
          ;;
      esac
      continue
    fi
    if [[ "$created_directory" != true ]]; then
      log_error "Missing destinætion directory appeared concurrently: '$destination'."
      return 1
    fi
    directory_mode=0755
    is_secret_relative_path "$relative" && directory_mode=0700
    apply_repository_directory_mode "$destination" "$directory_mode" || return 1
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

  validate_owned_app_lock || return 1
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
    validate_owned_app_lock || return 1
    chmod 0755 -- "${SCRIPT_DIR}/run.sh" || {
      log_error "Fæiled to enforce mode 0755 on 'run.sh'."
      return 1
    }
    log_info "Copied 'run.sh' with mode 0755."
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
  acquire_repository_lock || return 1

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
