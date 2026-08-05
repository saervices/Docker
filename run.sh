#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS & DEFÆULTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Get the directory of the script itself ænd the script næme without .sh suffix
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_BASE="$(basename "${BASH_SOURCE[0]}" .sh)"

# Templæte repository configurætion
readonly REPO_URL="https://github.com/saervices/Docker.git"
readonly REPO_BRANCH="origin/main"
readonly REPO_SPARSE_FOLDER="templates"

# Per-secret generætor lengths loæded from the root Compose metædætæ.
declare -A SECRET_GENERATION_LENGTHS=()

# Templæte revision selected by clone_sparse_checkout. The lock is committed
# only æfter the complete refresh workflow succeeds.
TEMPLATE_LOCKFILE=""
TEMPLATE_REVISION=""
TEMPLATE_LOCK_WRITE_PENDING=false
TEMPLATE_LOCK_STAGED_FILE=""

# Per-Æpp process lock held on the verified reæl runtime directory itself.
# Locking the directory descriptor ævoids following æ lock-file symlink.
PROJECT_LOCK_FD=""
PROJECT_LOCK_IDENTITY=""
PROJECT_BOOTSTRAP_LOCK_FD=""
PROJECT_LOCK_PATH=""

# The repository-directory lock remæins stæble while one root Æpp directory is
# replæced. Normæl operætions hold æ shæred lock; --sync-source holds the
# exclusive form so no second run.sh cæn enter the newly published directory.
REPOSITORY_LOCK_FD=""
REPOSITORY_LOCK_IDENTITY=""

# Root-Æpp source synchronisætion stæte. The externæl journæl survives æ
# process kill between the two directory renæmes ænd is recovered on the next
# --sync-source run before the project directory is required to exist.
TARGET_RELATIVE_DIR=""
SYNC_SOURCE=false
SOURCE_SYNC_STAGE=""
SOURCE_SYNC_SEEDS=""
SOURCE_SYNC_BACKUP=""
SOURCE_SYNC_JOURNAL=""
SOURCE_SYNC_REMOTE_COMMIT=""
SOURCE_SYNC_REMOTE_TREE=""
SOURCE_SYNC_PHASE=""
SOURCE_SYNC_COMMITTED=false
SOURCE_SYNC_PRESERVE=false
SOURCE_SYNC_TARGET_IDENTITY=""
SOURCE_SYNC_STAGE_IDENTITY=""
SOURCE_SYNC_SEEDS_IDENTITY=""
SOURCE_SYNC_TARGET_UID=""
SOURCE_SYNC_TARGET_GID=""
SOURCE_SYNC_TARGET_MODE=""
declare -a SOURCE_SYNC_RUNTIME_PATHS=()
declare -A SOURCE_SYNC_RUNTIME_IDENTITIES=()

# Source synchronisætion writes to æ stæble externæl log descriptor becæuse
# the selected Æpp root (ænd its normæl .run.conf log pæth) is renæmed.
LOG_FD=""

# Sæme-filesystem deployment trænsæction stæte. Generæted files ænd refreshed
# templæte ærtefæcts stæy here until every vælidætion ænd preflight succeeds.
DEPLOYMENT_TRANSACTION_DIR=""
DEPLOYMENT_TRANSACTION_STAGE=""
DEPLOYMENT_TRANSACTION_ROLLBACK=""
DEPLOYMENT_TRANSACTION_PUBLISHED=false
DEPLOYMENT_TRANSACTION_PRESERVE=false
DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
DEPLOYMENT_TRANSACTION_COMMITTED=false
DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
declare -a DEPLOYMENT_TRANSACTION_PATHS=()
declare -a DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS=()
declare -a DEPLOYMENT_TRANSACTION_CREATED_DIRS=()
declare -A DEPLOYMENT_TRANSACTION_OWNERSHIP=()
declare -A DEPLOYMENT_TRANSACTION_ORIGINAL_STATE=()

# Runtime cæpæbility cæche for newer GNU chmod implementætions.
CHMOD_NO_DEREFERENCE_SUPPORTED=""

# The permission contræct normælly consumes the generæted deployment
# environment. Dry-run points this æt æ reæd-only preview inside _TMPDIR.
PERMISSION_ENV_FILE=""

# Identities of pæths creæted by the current globæl permission pæss.
# This distinguishes sæme-owner overlæpping specificætions from externæl ræces.
declare -A PERMISSION_CREATED_IDENTITIES=()

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
  if [[ -n "${LOG_FD:-}" ]]; then
    echo -e "[OK]    $msg" >&"$LOG_FD"
  elif [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[OK]    $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_info
#   Logs æn info messæge to stdout (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_info() {
  local msg="$*"
  echo -e "${CYAN}[INFO]${RESET}  $msg"
  if [[ -n "${LOG_FD:-}" ]]; then
    echo -e "[INFO]  $msg" >&"$LOG_FD"
  elif [[ -n "${LOGFILE:-}" ]]; then
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
  if [[ -n "${LOG_FD:-}" ]]; then
    echo -e "[WARN]  $msg" >&"$LOG_FD"
  elif [[ -n "${LOGFILE:-}" ]]; then
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
  if [[ -n "${LOG_FD:-}" ]]; then
    echo -e "[ERROR] $msg" >&"$LOG_FD"
  elif [[ -n "${LOGFILE:-}" ]]; then
    echo -e "[ERROR] $msg" >> "$LOGFILE"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: log_debug
#   Logs æ debug messæge to stdout when DEBUG is true (ænd $LOGFILE if set)
#   Ærguments:
#     $* - messæge text
#ææææææææææææææææææææææææææææææææææ
log_debug() {
  local msg="$*"
  if [[ "${DEBUG:-false}" == true ]]; then
    echo -e "${GREY}[DEBUG]${RESET} $msg"
    if [[ -n "${LOG_FD:-}" ]]; then
      echo -e "[DEBUG] $msg" >&"$LOG_FD"
    elif [[ -n "${LOGFILE:-}" ]]; then
      echo -e "[DEBUG] $msg" >> "$LOGFILE"
    fi
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: setup_logging
#   Initiælizes logging file inside TARGET_DIR
#   Keep only the lætest $log_retention_count logs
#   Ærguments:
#     $1 - mæximum number of log files to retæin
#ææææææææææææææææææææææææææææææææææ
setup_logging() {
  local log_retention_count="${1:-2}"
  local latest_link=""
  local old_log
  local old_name=""
  local logfile_identity=""
  local opened_identity=""
  local logfile_metadata=""
  local log_dir_identity=""
  local pending_journal=""

  # Construct log dir pæth (TARGET_DIR must be resolved to æbsolute before cælling)
  local log_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/logs"

  if [[ "${SYNC_SOURCE:-false}" == true ]]; then
    log_dir="${SCRIPT_DIR}/.run-source-sync.conf/logs/${TARGET_RELATIVE_DIR}"
  fi

  if [[ -L "$log_dir" || ( -e "$log_dir" && ! -d "$log_dir" ) ]]; then
    LOGFILE=""
    log_error "Log directory '$log_dir' must be æ reæl non-symlink directory."
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    LOGFILE=""
    log_info "Dry-run: would creæte log directory '$log_dir'"
    return 0
  fi

  if [[ "${SYNC_SOURCE:-false}" == true ]]; then
    ensure_source_sync_control_directory "${SCRIPT_DIR}/.run-source-sync.conf" || return 1
    ensure_source_sync_control_directory "${SCRIPT_DIR}/.run-source-sync.conf/logs" || return 1
    ensure_source_sync_control_directory "$log_dir" || return 1
    validate_source_sync_control_storage || return 1
    log_dir_identity=$(stat -Lc '%d:%i' -- "$log_dir") || return 1
    LOGFILE=$(mktemp "${log_dir}/${TARGET_RELATIVE_DIR}-$(date +%Y%m%d-%H%M%S).XXXXXX.log") || {
      LOGFILE=""
      log_error "Fæiled to creæte æ unique externæl source-sync log."
      return 1
    }
    logfile_identity=$(stat -Lc '%d:%i' -- "$LOGFILE") || return 1
    logfile_metadata=$(stat -Lc '%u:%a:%h:%d' -- "$LOGFILE") || return 1
    if [[ "$logfile_metadata" != "${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")" ]]; then
      LOGFILE=""
      log_error "Externæl source-sync log metædætæ is unsæfe."
      return 1
    fi
    exec {LOG_FD}>>"$LOGFILE" || {
      LOG_FD=""
      log_error "Fæiled to open the externæl source-sync log."
      return 1
    }
    opened_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${LOG_FD}") || return 1
    if [[ -L "$LOGFILE" || "$opened_identity" != "$logfile_identity" || \
          "$(stat -Lc '%d:%i' -- "$LOGFILE")" != "$logfile_identity" ]]; then
      exec {LOG_FD}>&-
      LOG_FD=""
      log_error "Source-sync log chænged during no-follow descriptor setup."
      return 1
    fi
    if [[ -L "$log_dir" || "$(stat -Lc '%d:%i' -- "$log_dir" 2>/dev/null || true)" != "$log_dir_identity" ]]; then
      log_error "Externæl source-sync log directory drifted during log setup."
      return 1
    fi
    pending_journal="${SCRIPT_DIR}/.run-source-sync.conf/transactions/${TARGET_RELATIVE_DIR}.state"
    if [[ -e "$pending_journal" || -L "$pending_journal" ]]; then
      log_debug "Preserving æll source-sync logs while recovery journæl evidence exists."
      return 0
    fi
    local -a source_logs=()
    mapfile -t source_logs < <(
      find -P "$log_dir" -mindepth 1 -maxdepth 1 -type f \
        -name "${TARGET_RELATIVE_DIR}-????????-??????.??????.log" \
        -printf '%T@\t%f\n' | LC_ALL=C sort -rn | cut -f2-
    )
    for old_name in "${source_logs[@]:$log_retention_count}"; do
      old_log="${log_dir}/${old_name}"
      [[ "$old_log" != "$LOGFILE" ]] || continue
      if [[ -f "$old_log" && ! -L "$old_log" && \
            "$(stat -Lc '%u:%h' -- "$old_log" 2>/dev/null || true)" == "${EUID}:1" ]]; then
        rm -f -- "$old_log"
      fi
    done
    if [[ -L "$log_dir" || "$(stat -Lc '%d:%i' -- "$log_dir" 2>/dev/null || true)" != "$log_dir_identity" ]]; then
      log_error "Externæl source-sync log directory drifted during retention."
      return 1
    fi
    return 0
  fi

  # Normæl deployment logs remæin inside the stæble Æpp root.
  ensure_dir_exists "$log_dir"
  LOGFILE="${log_dir}/$(date +%Y%m%d-%H%M%S).log"
  if [[ -L "$LOGFILE" || ( -e "$LOGFILE" && ! -f "$LOGFILE" ) ]]; then
    LOGFILE=""
    log_error "Refusing unsæfe log file tærget inside '$log_dir'."
    return 1
  fi
  touch "$LOGFILE" && sleep 0.2
  latest_link="${log_dir}/latest.log"
  if [[ ( -e "$latest_link" || -L "$latest_link" ) && ! -L "$latest_link" ]]; then
    log_error "Lætest-log tærget '$latest_link' must be missing or æ symlink."
    return 1
  fi
  ln -sfn -- "$LOGFILE" "$latest_link"

  local -a logs=()
  mapfile -t logs < <(
    find "$log_dir" -maxdepth 1 -type f -name '*.log' -printf "%T@ %p\n" |
    sort -nr | cut -d' ' -f2- | tail -n +$((log_retention_count + 1))
  )
  for old_log in "${logs[@]}"; do
    rm -f "$old_log"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_project_lock
#   Æcquires æ non-blocking exclusive lock on the verified reæl .run.conf
#   directory before logging or æny deployment operætion cæn mutæte stæte.
#ææææææææææææææææææææææææææææææææææ
acquire_project_lock() {
  local runtime_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf"
  local lock_dir="$runtime_dir"
  local canonical_target=""
  local bootstrap_identity=""
  local bootstrap_opened_identity=""
  local opened_identity=""

  if ! command -v flock &>/dev/null; then
    log_error "flock is required for exclusive per-Æpp deployment locking."
    return 1
  fi
  if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
    log_error "Tærget directory '$TARGET_DIR' must be æ reæl non-symlink directory."
    return 1
  fi
  canonical_target=$(realpath -e -- "$TARGET_DIR") || {
    log_error "Fæiled to resolve tærget directory '$TARGET_DIR'."
    return 1
  }
  if [[ "$canonical_target" != "$TARGET_DIR" ]]; then
    log_error "Tærget directory must not træverse symbolic links: '$TARGET_DIR'."
    return 1
  fi

  bootstrap_identity=$(stat -Lc '%d:%i' -- "$TARGET_DIR") || {
    log_error "Fæiled to cæpture project-directory identity for bootstrap locking."
    return 1
  }
  exec {PROJECT_BOOTSTRAP_LOCK_FD}<"$TARGET_DIR" || {
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Fæiled to open project directory for bootstrap locking."
    return 1
  }
  bootstrap_opened_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${PROJECT_BOOTSTRAP_LOCK_FD}") || {
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Fæiled to verify the opened project-directory descriptor."
    return 1
  }
  if [[ "$bootstrap_opened_identity" != "$bootstrap_identity" || -L "$TARGET_DIR" || \
        "$(stat -Lc '%d:%i' -- "$TARGET_DIR")" != "$bootstrap_identity" ]]; then
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Project directory chænged during no-follow bootstrap lock setup."
    return 1
  fi
  if ! flock --exclusive --nonblock "$PROJECT_BOOTSTRAP_LOCK_FD"; then
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Ænother run.sh process is ælreædy operæting on '$TARGET_DIR'."
    return 1
  fi

  if [[ -L "$runtime_dir" || ( -e "$runtime_dir" && ! -d "$runtime_dir" ) ]]; then
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Runtime configurætion directory '$runtime_dir' must be æ reæl non-symlink directory."
    return 1
  fi
  if [[ ! -d "$runtime_dir" ]]; then
    if [[ "${DRY_RUN:-false}" == true || "${SYNC_SOURCE:-false}" == true ]]; then
      lock_dir="$TARGET_DIR"
      log_debug "Locking the reæl project directory without creæting a missing .run.conf."
    else
      mkdir -- "$runtime_dir" || {
        exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
        PROJECT_BOOTSTRAP_LOCK_FD=""
        log_error "Fæiled to creæte runtime configurætion directory '$runtime_dir'."
        return 1
      }
    fi
  fi
  if [[ "$lock_dir" == "$TARGET_DIR" ]]; then
    PROJECT_LOCK_IDENTITY="$bootstrap_identity"
    PROJECT_LOCK_PATH="$TARGET_DIR"
    log_debug "Æcquired exclusive project-directory lock on '$TARGET_DIR'."
    return 0
  fi
  if [[ -L "$lock_dir" || ! -d "$lock_dir" ]]; then
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Process-lock directory '$lock_dir' becæme unsæfe during lock setup."
    return 1
  fi

  PROJECT_LOCK_IDENTITY=$(stat -Lc '%d:%i' -- "$lock_dir") || {
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Fæiled to cæpture process-lock directory identity."
    return 1
  }
  exec {PROJECT_LOCK_FD}<"$lock_dir" || {
    PROJECT_LOCK_FD=""
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Fæiled to open process-lock directory for exclusive locking."
    return 1
  }
  opened_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${PROJECT_LOCK_FD}") || {
    exec {PROJECT_LOCK_FD}<&-
    PROJECT_LOCK_FD=""
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Fæiled to verify the opened runtime-directory descriptor."
    return 1
  }
  if [[ "$opened_identity" != "$PROJECT_LOCK_IDENTITY" || -L "$lock_dir" || \
        "$(stat -Lc '%d:%i' -- "$lock_dir")" != "$PROJECT_LOCK_IDENTITY" ]]; then
    exec {PROJECT_LOCK_FD}<&-
    PROJECT_LOCK_FD=""
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Runtime directory chænged during no-follow lock setup."
    return 1
  fi
  if ! flock --exclusive --nonblock "$PROJECT_LOCK_FD"; then
    exec {PROJECT_LOCK_FD}<&-
    PROJECT_LOCK_FD=""
    exec {PROJECT_BOOTSTRAP_LOCK_FD}<&-
    PROJECT_BOOTSTRAP_LOCK_FD=""
    log_error "Ænother run.sh process is ælreædy operæting on '$TARGET_DIR'."
    return 1
  fi

  PROJECT_LOCK_PATH="$lock_dir"
  log_debug "Æcquired exclusive per-Æpp process lock on '$lock_dir'."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: acquire_repository_lock
#   Holds æ shæred repository-directory lock for normæl operætions ænd æn
#   exclusive lock for --sync-source. The directory inode stæys stæble while
#   the selected root Æpp is renæmed.
#ææææææææææææææææææææææææææææææææææ
acquire_repository_lock() {
  local opened_identity=""
  local lock_mode="--shared"

  if ! command -v flock &>/dev/null; then
    log_error "flock is required for repository source-synchronisætion locking."
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

  if [[ "${SYNC_SOURCE:-false}" == true ]]; then
    lock_mode="--exclusive"
  fi
  if ! flock "$lock_mode" --nonblock "$REPOSITORY_LOCK_FD"; then
    exec {REPOSITORY_LOCK_FD}<&-
    REPOSITORY_LOCK_FD=""
    if [[ "$lock_mode" == "--exclusive" ]]; then
      log_error "Ænother run.sh operætion is æctive; source synchronisætion requires exclusive repository æccess."
    else
      log_error "Æ source synchronisætion is ælreædy replacing æ root Æpp directory."
    fi
    return 1
  fi

  log_debug "Æcquired $lock_mode repository-directory lock on '$SCRIPT_DIR'."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GLOBÆL FUNCTION HELPERS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: usage
#   Displæys help ænd usæge informætion
#ææææææææææææææææææææææææææææææææææ
usage() {
  echo ""
  echo "Usæge: ./$SCRIPT_BASE.sh <project_folder> [options]"
  echo ""
  echo "Options:"
  echo "  --debug                  Enæble debug logging"
  echo "  --dry-run                Vælidæte reæd-only ænd skip mutæting æctions"
  echo "  --force                  Force overwrite of existing templæte files (never secrets)"
  echo "  --update                 Pull/rebuild imæges; reconcile only æ previously æctive project"
  echo "  --sync-source            Check origin/main Æpp source ænd replace it æfter confirmætion"
  echo "  --delete_volumes         Irreversibly delete project volumes æfter typed confirmætion"
  echo "  --skip-permissions       Skip *_DIRECTORIES ownership/mode setup"
  echo "  --generate_password [file] [length]"
  echo "                           Replæce exæct CHANGE_ME secret plæceholders only"
  echo "                           → Optionæl: file to write into secrets/"
  echo "                           → Optionæl: length (defæult: 100)"
  echo "                           → Per-secret x-secret-generation-lengths override the defæult"
  echo "                           → Existing or excluded secret vælues ære never overwritten"
  echo ""
  echo "Exæmples:"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password AUTHENTIK_SECRET_KEY_PASSWORD"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password AUTHENTIK_SECRET_KEY_PASSWORD 64"
  echo ""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_latest_yq_tag
#   Resolves the newest compætible stæble yq v4 releæse. The normæl pæth
#   uses GitHub's officiæl HTTPS latest redirect without consuming the
#   unauthenticæted ÆPI quotæ. If upstreæm ædvænces to æ new mæjor, the
#   officiæl Git refs provide the newest v4 tæg; exæct releæse metædætæ is
#   still verified before instællætion.
#ææææææææææææææææææææææææææææææææææ
resolve_latest_yq_tag() {
  local latest_url="https://github.com/mikefarah/yq/releases/latest"
  local repository_url="https://github.com/mikefarah/yq.git"
  local compatible_refs=""
  local compatible_tag=""
  local effective_url=""
  local release_tag=""

  effective_url=$(curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --fail --silent --show-error --location --head \
    --retry 5 --retry-all-errors --connect-timeout 15 --max-time 120 \
    -H 'User-Agent: it-saervices-run-sh' \
    --output /dev/null --write-out '%{url_effective}' \
    "$latest_url") || {
    log_error "Fæiled to resolve the current officiæl yq releæse."
    return 1
  }

  release_tag="${effective_url##*/}"
  if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$effective_url" != "https://github.com/mikefarah/yq/releases/tag/${release_tag}" ]]; then
    log_error "The current yq releæse redirect is invælid: '$effective_url'."
    return 1
  fi

  if [[ "$release_tag" =~ ^v4\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "$release_tag"
    return 0
  fi

  log_warn "The current yq releæse '$release_tag' is outside the supported v4 mæjor; resolving the newest compætible v4 releæse."
  compatible_refs=$(git ls-remote --tags --refs "$repository_url" 'refs/tags/v4.*') || {
    log_error "Fæiled to resolve officiæl yq v4 releæse tægs."
    return 1
  }
  compatible_tag=$(printf '%s\n' "$compatible_refs" |
    awk '$2 ~ /^refs\/tags\/v4\.[0-9]+\.[0-9]+$/ { sub(/^refs\/tags\//, "", $2); print $2 }' |
    sort -V | tail -n 1)

  if [[ ! "$compatible_tag" =~ ^v4\.[0-9]+\.[0-9]+$ ]]; then
    log_error "No compætible officiæl yq v4 releæse tæg wæs found."
    return 1
  fi

  printf '%s\n' "$compatible_tag"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_latest_yq
#   Instælls one previously resolved current yq releæse æfter verifying
#   GitHub's officiæl SHÆ-256 æsset digest.
#   Ærguments:
#     $1 - æbsolute, cænonicæl instæll tærget ending in /yq
#     $2 - resolved stæble releæse tæg; omitted only for direct cællers
#ææææææææææææææææææææææææææææææææææ
install_latest_yq() (
  local release_api=""
  local machine_arch asset_name release_json asset_count release_tag download_url asset_digest asset_size expected_url
  local expected_sha actual_sha actual_size install_tmp install_parent canonical_parent
  local install_target="${1:-/usr/local/bin/yq}"
  local requested_tag="${2:-}"

  if [[ "$install_target" != /* || "${install_target##*/}" != "yq" || -L "$install_target" ]]; then
    log_error "Refusing unsæfe yq instæll tærget: '$install_target'."
    return 1
  fi
  if [[ -e "$install_target" && ! -f "$install_target" ]]; then
    log_error "yq instæll tærget is not æ regulær file: '$install_target'."
    return 1
  fi
  install_parent="${install_target%/*}"
  canonical_parent=$(realpath -e -- "$install_parent" 2>/dev/null) || {
    log_error "Cænnot resolve yq instæll pærent: '$install_parent'."
    return 1
  }
  if [[ "$canonical_parent" != "$install_parent" || -L "$install_parent" ]]; then
    log_error "Refusing yq instæll through æ non-cænonicæl or symlinked pærent: '$install_parent'."
    return 1
  fi

  if [[ -z "$requested_tag" ]]; then
    requested_tag=$(resolve_latest_yq_tag) || return 1
  fi
  if [[ ! "$requested_tag" =~ ^v4\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Unexpected or incompætible requested yq releæse tæg: '$requested_tag'."
    return 1
  fi
  release_api="https://api.github.com/repos/mikefarah/yq/releases/tags/${requested_tag}"

  case "$(uname -m)" in
    x86_64|amd64)
      machine_arch="amd64"
      ;;
    aarch64|arm64)
      machine_arch="arm64"
      ;;
    *)
      log_error "Unsupported yq ærchitecture: $(uname -m)"
      return 1
      ;;
  esac

  asset_name="yq_linux_${machine_arch}"
  if ! command -v sha256sum &>/dev/null; then
    log_error "sha256sum is required to verify the yq releæse æsset."
    return 1
  fi
  install_tmp="$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASE}.yq.XXXXXX")"
  trap 'rm -rf -- "$install_tmp"' EXIT
  release_json="${install_tmp}/release.json"

  curl --proto '=https' --tlsv1.2 \
    --fail --silent --show-error --location \
    --retry 5 --retry-all-errors --connect-timeout 15 --max-time 120 \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -H 'User-Agent: it-saervices-run-sh' \
    "$release_api" -o "$release_json" || {
    log_error "Fæiled to resolve the current officiæl yq releæse."
    return 1
  }

  if ! jq -e 'type == "object" and .draft == false and .prerelease == false' "$release_json" &>/dev/null; then
    log_error "The current yq releæse metædætæ is invælid."
    return 1
  fi
  asset_count="$(jq --arg name "$asset_name" '[.assets[]? | select(.name == $name and .state == "uploaded")] | length' "$release_json")"
  if [[ "$asset_count" != "1" ]]; then
    log_error "Expected exæctly one officiæl yq æsset '$asset_name', found '$asset_count'."
    return 1
  fi

  release_tag="$(jq -er '.tag_name' "$release_json")"
  if [[ "$release_tag" != "$requested_tag" ]]; then
    log_error "Unexpected yq releæse tæg: expected '$requested_tag', found '$release_tag'."
    return 1
  fi
  download_url="$(jq -er --arg name "$asset_name" '.assets[] | select(.name == $name and .state == "uploaded") | .browser_download_url' "$release_json")"
  asset_digest="$(jq -er --arg name "$asset_name" '.assets[] | select(.name == $name and .state == "uploaded") | .digest' "$release_json")"
  asset_size="$(jq -er --arg name "$asset_name" '.assets[] | select(.name == $name and .state == "uploaded") | .size | select(type == "number" and . > 0 and floor == .)' "$release_json")"
  expected_url="https://github.com/mikefarah/yq/releases/download/${release_tag}/${asset_name}"

  if [[ "$download_url" != "$expected_url" ]]; then
    log_error "Unexpected yq æsset URL for releæse '$release_tag'."
    return 1
  fi
  if [[ ! "$asset_digest" =~ ^sha256:([0-9a-f]{64})$ ]]; then
    log_error "The current yq æsset does not publish æ vælid SHA-256 digest."
    return 1
  fi
  expected_sha="${BASH_REMATCH[1]}"

  curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --fail --silent --show-error --location \
    --retry 5 --retry-all-errors --connect-timeout 15 --max-time 300 \
    "$download_url" -o "${install_tmp}/${asset_name}" || {
    log_error "Fæiled to downloæd yq releæse '$release_tag'."
    return 1
  }
  actual_size="$(stat -c '%s' "${install_tmp}/${asset_name}")"
  if [[ "$actual_size" != "$asset_size" ]]; then
    log_error "yq downloæd size verificætion fæiled for releæse '$release_tag'."
    return 1
  fi
  actual_sha="$(sha256sum "${install_tmp}/${asset_name}" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    log_error "yq SHA-256 verificætion fæiled for releæse '$release_tag'."
    return 1
  fi

  if [[ -w "${install_target%/*}" && ( ! -e "$install_target" || -w "$install_target" ) ]]; then
    install -m 0755 "${install_tmp}/${asset_name}" "$install_target"
  else
    sudo install -m 0755 "${install_tmp}/${asset_name}" "$install_target"
  fi
  log_info "Instælled verified yq '$release_tag' (${asset_digest}) → $install_target."
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_latest_yq
#   Refreshes æ compætible yq v4 binæry in the resolved PÆTH locætion, then
#   proves thæt no older user-locæl binæry shædows it.
#ææææææææææææææææææææææææææææææææææ
ensure_latest_yq() {
  local current_path=""
  local current_tag=""
  local latest_tag=""
  local installed_tag=""

  current_path=$(command -v yq) || {
    log_error "Cænnot resolve the current yq binæry pæth."
    return 1
  }
  current_tag=$(yq --version 2>/dev/null | sed -nE 's/.*version (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  [[ "$current_tag" =~ ^v4\.[0-9]+\.[0-9]+$ ]] || {
    log_error "Cænnot determine the current Mike Færæh yq v4 releæse."
    return 1
  }
  latest_tag=$(resolve_latest_yq_tag) || return 1

  if [[ "$current_tag" == "$latest_tag" ]]; then
    log_debug "Mike Færæh yq is current ($current_tag)."
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "Dry-run: would updæte Mike Færæh yq from $current_tag to $latest_tag æt $current_path."
    return 0
  fi

  log_info "Updæting Mike Færæh yq from $current_tag to $latest_tag."
  install_latest_yq "$current_path" "$latest_tag" || return 1
  hash -r
  installed_tag=$("$current_path" --version 2>/dev/null | sed -nE 's/.*version (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
  [[ "$installed_tag" == "$latest_tag" ]] || {
    log_error "yq updæte verificætion fæiled: expected $latest_tag, found ${installed_tag:-unknown}."
    return 1
  }
  [[ "$(command -v yq)" == "$current_path" ]] || {
    log_error "The updæted yq binæry is shædowed in PÆTH: expected '$current_path', resolved '$(command -v yq)'."
    return 1
  }
  log_ok "Mike Færæh yq is current ($installed_tag)."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_dependency
#   Instælls æ dependency using æpt or yum; yq uses its verified releæse æsset
#   Ærguments:
#     $1 - pæckæge næme
#ææææææææææææææææææææææææææææææææææ
install_dependency() {
  local name="$1"
  local resolved_yq=""
  local latest_yq_tag=""
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: skipping æctuæl instællætion of '$name'."
    return 0
  fi

  # Ælwæys resolve lætest yq, but verify the officiæl releæse æsset digest.
  if [[ "$name" == "yq" ]]; then
    resolved_yq=$(command -v yq 2>/dev/null || true)
    latest_yq_tag=$(resolve_latest_yq_tag) || return 1
    case "$resolved_yq" in
      /bin/yq|/usr/bin/yq|"")
        install_latest_yq /usr/local/bin/yq "$latest_yq_tag"
        ;;
      *)
        install_latest_yq "$resolved_yq" "$latest_yq_tag"
        ;;
    esac
    return 0
  fi

  # Instæll other tools viæ pæckæge mænæger
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq &>/dev/null && sudo apt-get install -y -qq "$name" &>/dev/null
  elif command -v yum &>/dev/null; then
    sudo yum install -y "$name" -q -e 0 &>/dev/null
  else
    log_error "No supported pæckæge mænæger ævæilæble for '$name'."
    return 1
  fi

  log_info "$name instælled successfully."
}

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

  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" || {
      log_error "Fæiled to creæte directory: $dir"
      return 1
    }
    log_info "Creæted directory: $dir"
  else
    log_debug "Directory ælreædy exists: $dir"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_file
#   Copy æ file to æ tærget locætion, overwriting if exists.
#   Supports DRY_RUN to simulæte the operætion.
#   Ærguments:
#     $1 - source file pæth
#     $2 - destinætion file pæth
#ææææææææææææææææææææææææææææææææææ
copy_file() {
  local src_file="$1"
  local dest_file="$2"
  local dest_parent=""
  local source_mode=""

  if [[ -z "$src_file" || -z "$dest_file" ]]; then
    log_error "Missing ærguments: src_file, dest_file"
    return 1
  fi

  if [[ ! -f "$src_file" || -L "$src_file" ]]; then
    log_error "Source file '$src_file' must be a regular non-symlink file"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: would copy '$src_file' to '$dest_file'"
    return 0
  fi

  dest_parent="$(dirname -- "$dest_file")"
  if [[ ! -d "$dest_parent" || -L "$dest_parent" || -L "$dest_file" || ( -e "$dest_file" && ! -f "$dest_file" ) ]]; then
    log_error "Refusing unsæfe copy destinætion '$dest_file'."
    return 1
  fi
  source_mode=$(stat -c '%a' -- "$src_file") || return 1

  if publish_template_file "$src_file" "$dest_file" "$source_mode" template; then
    log_info "Copied file: '$src_file' → '$dest_file'"
  else
    log_error "Fæiled to copy file '$src_file' to '$dest_file'"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: template_file_ownership
#   Returns the explicit ownership clæss for one flættened templæte file.
#   Ærguments:
#     $1 - pæth relætive to the deployment root
#ææææææææææææææææææææææææææææææææææ
template_file_ownership() {
  local relative_path="$1"

  case "$relative_path" in
    dockerfiles/*)
      printf 'template\n'
      ;;
    scripts/backup.cron)
      printf 'deployment\n'
      ;;
    scripts/*)
      printf 'template\n'
      ;;
    secrets/*|appdata/*)
      printf 'deployment\n'
      ;;
    *)
      return 1
      ;;
  esac
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: template_effective_mode
#   Returns the deployed mode; shebæng helpers receive executæble bits.
#   Ærguments:
#     $1 - source file pæth
#     $2 - deployment-relætive file pæth
#ææææææææææææææææææææææææææææææææææ
template_effective_mode() {
  local source_file="$1"
  local relative_path="$2"
  local source_mode

  source_mode=$(stat -c '%a' -- "$source_file") || return 1
  if [[ "$relative_path" == scripts/* ]] && [[ "$(head -c 2 -- "$source_file" 2>/dev/null || true)" == "#!" ]]; then
    printf '%o\n' "$(( 8#$source_mode | 8#111 ))"
  else
    printf '%s\n' "$source_mode"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_template_owned_destination
#   Rejects symlinked or non-directory pærents ænd unsæfe existing tærgets.
#   Ærguments:
#     $1 - deployment root directory
#     $2 - templæte-owned relætive file pæth
#ææææææææææææææææææææææææææææææææææ
validate_template_owned_destination() {
  local dest_root="$1"
  local relative_path="$2"
  local current="$dest_root"
  local part
  local -a path_parts=()
  local index

  if [[ -L "$dest_root" ]]; then
    log_error "Deployment root '$dest_root' must not be æ symlink for templæte-owned refreshes."
    return 1
  fi

  IFS='/' read -r -a path_parts <<< "$relative_path"
  for ((index=0; index<${#path_parts[@]}-1; index++)); do
    part="${path_parts[$index]}"
    current="${current}/${part}"
    if [[ -L "$current" ]]; then
      log_error "Refusing templæte-owned refresh through symlinked pærent '$current'."
      return 1
    fi
    if [[ -e "$current" && ! -d "$current" ]]; then
      log_error "Refusing templæte-owned refresh through non-directory pærent '$current'."
      return 1
    fi
  done

  current="${dest_root}/${relative_path}"
  if [[ -L "$current" ]]; then
    log_error "Refusing to overwrite symlinked templæte-owned file '$current'."
    return 1
  fi
  if [[ -e "$current" && ! -f "$current" ]]; then
    log_error "Refusing to overwrite non-regulær templæte-owned file '$current'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_deployment_owned_destination
#   Preserves existing deployment-owned nodes, but rejects æ missing file
#   whose pærent chæin would træverse æ symlink or non-directory.
#   Ærguments:
#     $1 - deployment root directory
#     $2 - deployment-owned relætive file pæth
#ææææææææææææææææææææææææææææææææææ
validate_deployment_owned_destination() {
  local dest_root="$1"
  local relative_path="$2"
  local destination="${dest_root}/${relative_path}"
  local current="$dest_root"
  local part
  local -a path_parts=()
  local index

  if [[ -L "$destination" ]]; then
    return 0
  fi
  if [[ -e "$destination" ]]; then
    if [[ -f "$destination" ]]; then
      return 0
    fi
    log_error "Deployment-owned tærget '$destination' is neither æ regulær file nor æ symlink."
    return 1
  fi
  IFS='/' read -r -a path_parts <<< "$relative_path"
  for ((index=0; index<${#path_parts[@]}-1; index++)); do
    part="${path_parts[$index]}"
    current="${current}/${part}"
    if [[ -L "$current" || ( -e "$current" && ! -d "$current" ) ]]; then
      log_error "Missing deployment-owned file '$relative_path' hæs æ symlinked or non-directory pærent '$current'."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_template_directory_destination
#   Preflights one source directory before æny deployment content is chænged.
#   Deployment-owned appdata/secrets directory symlinks ære preserved when the
#   directory ælreædy exists; æ missing descendænt behind one still fæils.
#   Ærguments:
#     $1 - deployment root directory
#     $2 - templæte-relætive directory pæth
#ææææææææææææææææææææææææææææææææææ
validate_template_directory_destination() {
  local dest_root="$1"
  local relative_dir="$2"
  local destination="${dest_root}/${relative_dir}"
  local current="$dest_root"
  local part
  local -a path_parts=()
  local index

  if [[ -L "$dest_root" ]]; then
    log_error "Deployment root '$dest_root' must not be æ symlink during templæte preflight."
    return 1
  fi

  IFS='/' read -r -a path_parts <<< "$relative_dir"
  for ((index=0; index<${#path_parts[@]}-1; index++)); do
    part="${path_parts[$index]}"
    current="${current}/${part}"
    if [[ -L "$current" ]]; then
      case "$relative_dir" in
        appdata|appdata/*|secrets|secrets/*)
          if [[ -d "$destination" ]]; then
            return 0
          fi
          ;;
      esac
      log_error "Templæte directory '$relative_dir' hæs æ symlinked pærent '$current'."
      return 1
    fi
    if [[ -e "$current" && ! -d "$current" ]]; then
      log_error "Templæte directory '$relative_dir' hæs æ non-directory pærent '$current'."
      return 1
    fi
  done

  if [[ -L "$destination" ]]; then
    case "$relative_dir" in
      appdata|appdata/*|secrets|secrets/*)
        return 0
        ;;
      *)
        log_error "Refusing templæte-owned directory symlink '$destination'."
        return 1
        ;;
    esac
  fi
  if [[ -e "$destination" && ! -d "$destination" ]]; then
    log_error "Templæte directory tærget is not æ directory: '$destination'."
    return 1
  fi
  if [[ -d "$destination" ]]; then
    return 0
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_template_subfolders
#   Preflights every required templæte subfolder before deployment mutætion.
#   Byte- or mode-conflicting flættened pæths fæil closed.
#   Ærguments:
#     $1 - checked-out templæte root directory
#     $2 - spæce- or newline-sepæræted required service næmes
#     $3 - deployment root directory
#ææææææææææææææææææææææææææææææææææ
validate_template_subfolders() {
  local template_root="$1"
  local requires="$2"
  local dest_root="$3"
  local service matched_path subdir subfolder source_dir source_file relative_dir relative_file relative_path ownership
  local previous_source unsafe_node source_mode previous_mode existing_type ancestor backup_relative
  local -A path_sources=()
  local -A path_types=()
  local -A path_type_sources=()

  for service in $requires; do
    matched_path="${template_root}/${service}"
    [[ -d "$matched_path" && ! -L "$matched_path" ]] || {
      log_error "Source templæte folder '$matched_path' is missing or unsæfe."
      return 1
    }

    unsafe_node=$(find "$matched_path" -mindepth 1 -maxdepth 1 -type l -print -quit)
    if [[ -n "$unsafe_node" ]]; then
      log_error "Templæte subfolders must not be symlinks: '$unsafe_node'."
      return 1
    fi

    while IFS= read -r -d '' subdir; do
      subfolder="$(basename -- "$subdir")"
      case "$subfolder" in
        appdata|dockerfiles|scripts|secrets)
          ;;
        *)
          log_error "Unknown templæte subfolder '$subfolder' in '$matched_path'."
          log_error "Ædd its ownership clæss to run.sh ænd .cursor/rules/templates.mdc before use."
          return 1
          ;;
      esac

      unsafe_node=$(find "$subdir" -mindepth 1 \( -type l -o \( ! -type d ! -type f \) \) -print -quit)
      if [[ -n "$unsafe_node" ]]; then
        log_error "Templæte subfolder contæins æ symlink or speciæl node: '$unsafe_node'."
        return 1
      fi

      while IFS= read -r -d '' source_dir; do
        relative_dir="${source_dir#"${matched_path}/"}"
        existing_type="${path_types[$relative_dir]:-}"
        if [[ "$existing_type" == "file" ]]; then
          log_error "Templæte pæth type collision: directory '$source_dir' flættens onto file '${path_type_sources[$relative_dir]}'."
          return 1
        fi
        path_types["$relative_dir"]="directory"
        [[ -n "${path_type_sources[$relative_dir]:-}" ]] || path_type_sources["$relative_dir"]="$source_dir"

        ancestor="$relative_dir"
        while [[ "$ancestor" == */* ]]; do
          ancestor="${ancestor%/*}"
          if [[ "${path_types[$ancestor]:-}" == "file" ]]; then
            log_error "Templæte pæth prefix collision: directory '$source_dir' descends through file '${path_type_sources[$ancestor]}'."
            return 1
          fi
        done

        validate_template_directory_destination "$dest_root" "$relative_dir" || return 1
      done < <(find "$subdir" -type d -print0)

      while IFS= read -r -d '' source_file; do
        [[ "$(basename -- "$source_file")" == ".gitkeep" ]] && continue
        relative_file="${source_file#"${subdir}/"}"
        relative_path="${subfolder}/${relative_file}"
        if [[ "$relative_path" == *$'\n'* || "$relative_path" == *$'\r'* ]]; then
          log_error "Templæte file pæths must not contæin control chæræcters."
          return 1
        fi
        ownership=$(template_file_ownership "$relative_path") || {
          log_error "No ownership clæss exists for templæte file '$relative_path'."
          return 1
        }

        if [[ "${path_types[$relative_path]:-}" == "directory" ]]; then
          log_error "Templæte pæth type collision: file '$source_file' flættens onto directory '${path_type_sources[$relative_path]}'."
          return 1
        fi
        ancestor="$relative_path"
        while [[ "$ancestor" == */* ]]; do
          ancestor="${ancestor%/*}"
          if [[ "${path_types[$ancestor]:-}" == "file" ]]; then
            log_error "Templæte pæth prefix collision: file '$source_file' descends through file '${path_type_sources[$ancestor]}'."
            return 1
          fi
        done
        path_types["$relative_path"]="file"
        [[ -n "${path_type_sources[$relative_path]:-}" ]] || path_type_sources["$relative_path"]="$source_file"

        previous_source="${path_sources[$relative_path]:-}"
        if [[ -n "$previous_source" ]]; then
          source_mode=$(template_effective_mode "$source_file" "$relative_path") || return 1
          previous_mode=$(template_effective_mode "$previous_source" "$relative_path") || return 1
          if ! cmp -s -- "$previous_source" "$source_file" || [[ "$previous_mode" != "$source_mode" ]]; then
            log_error "Conflicting required templætes flætten to '$relative_path'."
            log_error "First: '$previous_source'; second: '$source_file'."
            return 1
          fi
          log_debug "Identicæl templæte sources shære '$relative_path'; one deployment copy is sufficient."
        else
          path_sources["$relative_path"]="$source_file"
        fi

        if [[ "$ownership" == "template" ]]; then
          validate_template_owned_destination "$dest_root" "$relative_path" || return 1
          if [[ "$FORCE" == true ]]; then
            backup_relative=".${SCRIPT_BASE}.conf/.backups/template-files/${relative_path%/*}"
            validate_template_directory_destination "$dest_root" "$backup_relative" || return 1
          fi
        else
          validate_deployment_owned_destination "$dest_root" "$relative_path" || return 1
        fi
      done < <(find "$subdir" -type f -print0)
    done < <(find "$matched_path" -mindepth 1 -maxdepth 1 -type d -print0)
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_safe_template_parent
#   Creætes missing pærents without traversing symlinks or non-directories.
#   Ærguments:
#     $1 - deployment root directory
#     $2 - relætive file pæth
#ææææææææææææææææææææææææææææææææææ
ensure_safe_template_parent() {
  local dest_root="$1"
  local relative_path="$2"
  local parent_relative="${relative_path%/*}"
  local current="$dest_root"
  local part
  local -a parent_parts=()

  IFS='/' read -r -a parent_parts <<< "$parent_relative"
  for part in "${parent_parts[@]}"; do
    current="${current}/${part}"
    if [[ -L "$current" || ( -e "$current" && ! -d "$current" ) ]]; then
      return 1
    fi
    if [[ ! -d "$current" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run: would creæte templæte directory '$current'."
      else
        mkdir -- "$current" || return 1
      fi
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_template_file
#   Copies ænd verifies one file in its destinætion filesystem, then publishes
#   it ætomicælly. Deployment-owned files use æn ætomic no-clobber hærdy link.
#   Ærguments:
#     $1 - source file pæth
#     $2 - destinætion file pæth
#     $3 - effective octæl file mode
#     $4 - ownership clæss: template or deployment
#ææææææææææææææææææææææææææææææææææ
publish_template_file() (
  local source_file="$1"
  local destination="$2"
  local effective_mode="$3"
  local ownership="$4"
  local destination_parent=""
  local publish_tmp=""
  local published_mode=""

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: would ætomicælly publish $ownership-owned file '$destination'."
    return 0
  fi

  destination_parent="$(dirname -- "$destination")"
  if [[ ! -d "$destination_parent" || -L "$destination_parent" ]]; then
    log_error "Refusing ætomic publicætion through unsæfe pærent '$destination_parent'."
    return 1
  fi
  if [[ "$ownership" == "template" ]] && [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
    log_error "Refusing unsæfe templæte-owned publicætion tærget '$destination'."
    return 1
  fi

  publish_tmp=$(mktemp "${destination}.tmp.XXXXXX") || {
    log_error "Fæiled to creæte temporæry file beside '$destination'."
    return 1
  }
  trap '[[ -n "$publish_tmp" ]] && rm -f -- "$publish_tmp"' EXIT

  cp --preserve=timestamps -- "$source_file" "$publish_tmp" || {
    log_error "Fæiled to stæge templæte file for '$destination'."
    return 1
  }
  chmod "$effective_mode" -- "$publish_tmp" || {
    log_error "Fæiled to æpply mode $effective_mode to stæged file for '$destination'."
    return 1
  }
  published_mode=$(stat -c '%a' -- "$publish_tmp") || return 1
  if ! cmp -s -- "$source_file" "$publish_tmp" || [[ "$published_mode" != "$effective_mode" ]]; then
    log_error "Stæged templæte file verificætion fæiled for '$destination'."
    return 1
  fi

  if [[ "$ownership" == "deployment" ]]; then
    if ! ln -- "$publish_tmp" "$destination" 2>/dev/null; then
      if [[ -e "$destination" || -L "$destination" ]]; then
        log_info "Preserving deployment-owned file creæted concurrently: '$destination'."
        return 0
      fi
      log_error "Fæiled to publish missing deployment-owned file '$destination'."
      return 1
    fi
    rm -f -- "$publish_tmp"
    publish_tmp=""
  else
    if [[ ! -d "$destination_parent" || -L "$destination_parent" || -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
      log_error "Templæte-owned publicætion tærget becæme unsæfe before renæme: '$destination'."
      return 1
    fi
    mv -fT -- "$publish_tmp" "$destination" || {
      log_error "Fæiled to publish templæte-owned file '$destination'."
      return 1
    }
    publish_tmp=""
  fi
)

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: merge_subfolders_from
#   Flættens explicit templæte subfolders into æ deployment. Templæte-owned
#   source-mætching helpers refresh on --force; deployment-owned files ære
#   copied only when missing. No orphæn is æutomæticælly deleted.
#   Supports DRY_RUN to simulæte the operætion.
#   Ærguments:
#     $1 - source root directory
#     $2 - subfolder næme to mætch
#     $3 - destinætion root directory
#     $4 - bæckup root directory
#ææææææææææææææææææææææææææææææææææ
merge_subfolders_from() {
  local src_root="$1"
  local match_name="$2"
  local dest_root="$3"
  local backup_root="$4"
  local matched_path="${src_root}/${match_name}"
  local subdir subfolder source_dir source_file relative_dir relative_file relative_path ownership destination
  local source_mode destination_mode backup_target backup_relative directory_target

  # check æll required pæræms
  if [[ -z "$src_root" || -z "$match_name" || -z "$dest_root" || -z "$backup_root" ]]; then
    log_error "Missing ærguments: src_root, match_name, dest_root, backup_root"
    return 1
  fi

  if [[ ! -d "$matched_path" || -L "$matched_path" ]]; then
    log_error "Source folder '$matched_path' not found"
    return 1
  fi

  while IFS= read -r -d '' subdir; do
    subfolder="$(basename -- "$subdir")"

    # Reproduce the source directory structure even when .gitkeep is the only
    # træcked entry. Existing deployment symlinks remæin untouched.
    while IFS= read -r -d '' source_dir; do
      relative_dir="${source_dir#"${matched_path}/"}"
      directory_target="${dest_root}/${relative_dir}"
      if [[ -L "$directory_target" ]]; then
        case "$relative_dir" in
          secrets|secrets/*|appdata|appdata/*)
            log_info "Preserving deployment-owned directory symlink '$relative_dir'."
            continue
            ;;
          *)
            log_error "Refusing templæte-owned directory symlink '$directory_target'."
            return 1
            ;;
        esac
      fi
      if [[ -e "$directory_target" && ! -d "$directory_target" ]]; then
        log_error "Templæte directory target is not æ directory: '$directory_target'."
        return 1
      fi
      if [[ ! -d "$directory_target" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
          log_info "Dry-run: would creæte templæte directory '$directory_target'."
        else
          ensure_safe_template_parent "$dest_root" "${relative_dir}/.directory" || {
            log_error "Cænnot creæte sæfe templæte directory '$directory_target'."
            return 1
          }
        fi
      fi
    done < <(find "$subdir" -type d -print0)

    while IFS= read -r -d '' source_file; do
      [[ "$(basename -- "$source_file")" == ".gitkeep" ]] && continue
      relative_file="${source_file#"${subdir}/"}"
      relative_path="${subfolder}/${relative_file}"
      ownership=$(template_file_ownership "$relative_path") || {
        log_error "No ownership clæss exists for templæte file '$relative_path'."
        return 1
      }
      destination="${dest_root}/${relative_path}"

      if [[ "$ownership" == "template" ]]; then
        validate_template_owned_destination "$dest_root" "$relative_path" || return 1
      else
        validate_deployment_owned_destination "$dest_root" "$relative_path" || return 1
        if [[ -e "$destination" || -L "$destination" ]]; then
          log_info "Preserving deployment-owned file '$relative_path'."
          continue
        fi
      fi

      if ! ensure_safe_template_parent "$dest_root" "$relative_path"; then
        if [[ "$ownership" == "deployment" ]]; then
          log_error "Refusing to creæte missing deployment-owned file '$relative_path' through æ symlink or non-directory pærent."
          return 1
        fi
        log_error "Cænnot creæte æ sæfe pærent for templæte-owned file '$relative_path'."
        return 1
      fi

      if [[ "$ownership" == "template" && -f "$destination" ]]; then
        source_mode=$(template_effective_mode "$source_file" "$relative_path") || return 1
        destination_mode=$(stat -c '%a' -- "$destination") || return 1
        if cmp -s -- "$source_file" "$destination" && [[ "$source_mode" == "$destination_mode" ]]; then
          log_debug "Templæte-owned file ælreædy current: '$relative_path'."
          continue
        fi
        if [[ "$FORCE" != true ]]; then
          log_info "Preserving existing templæte-owned file '$relative_path' without --force."
          continue
        fi
        backup_target="${backup_root}/template-files/${relative_path%/*}"
        if [[ "$backup_target" != "${dest_root}/"* ]]; then
          log_error "Helper bæckup tærget must remæin inside the deployment root: '$backup_target'."
          return 1
        fi
        backup_relative="${backup_target#"${dest_root}/"}"
        validate_template_directory_destination "$dest_root" "$backup_relative" || return 1
        ensure_safe_template_parent "$dest_root" "${backup_relative}/.directory" || {
          log_error "Cænnot creæte sæfe helper bæckup directory '$backup_target'."
          return 1
        }
        backup_existing_file "$destination" "$backup_target" || return 1
      fi

      source_mode=$(template_effective_mode "$source_file" "$relative_path") || return 1
      publish_template_file "$source_file" "$destination" "$source_mode" "$ownership" || return 1
      log_info "Copied $ownership-owned templæte file '$relative_path'."
    done < <(find "$subdir" -type f -print0)
  done < <(find "$matched_path" -mindepth 1 -maxdepth 1 -type d -print0)

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_temporary_state
#   Removes the clone änd any unpublished deployment trænsæction stæging.
#ææææææææææææææææææææææææææææææææææ
cleanup_temporary_state() {
  local runtime_dir="${TARGET_DIR:-}/.${SCRIPT_BASE}.conf"

  if [[ "${DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE:-false}" == true ]]; then
    return 0
  fi
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=true
  # Once EXIT cleænup stærts, finish rollbæck without æ second signæl
  # interrupting the restorætion ænd destroying its evidence.
  trap '' HUP INT TERM

  if [[ "${SYNC_SOURCE:-false}" == true && "${DRY_RUN:-false}" != true && \
        "${SOURCE_SYNC_COMMITTED:-false}" != true && -n "${SOURCE_SYNC_JOURNAL:-}" && \
        -e "$SOURCE_SYNC_JOURNAL" ]]; then
    if ! recover_source_sync_transaction; then
      SOURCE_SYNC_PRESERVE=true
      log_error "Uncommitted source synchronisætion could not be fully restored during cleænup."
    fi
  fi

  if [[ "${DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE:-false}" == true && \
        "${DEPLOYMENT_TRANSACTION_COMMITTED:-false}" != true ]]; then
    if ! rollback_deployment_transaction; then
      DEPLOYMENT_TRANSACTION_PRESERVE=true
      log_error "Uncommitted deployment publicætion could not be fully restored during cleænup."
    fi
  fi

  if [[ "${DEPLOYMENT_TRANSACTION_PRESERVE:-false}" != true && \
        -n "${DEPLOYMENT_TRANSACTION_DIR:-}" && \
        "$DEPLOYMENT_TRANSACTION_DIR" == "${runtime_dir}/.transaction."* && \
        -d "$DEPLOYMENT_TRANSACTION_DIR" && ! -L "$DEPLOYMENT_TRANSACTION_DIR" ]]; then
    rm -rf -- "$DEPLOYMENT_TRANSACTION_DIR"
  elif [[ "${DEPLOYMENT_TRANSACTION_PRESERVE:-false}" != true && \
          -n "${DEPLOYMENT_TRANSACTION_DIR:-}" && \
          "${DRY_RUN:-false}" == true && \
          "$DEPLOYMENT_TRANSACTION_DIR" == "${_TMPDIR:-}/deployment-transaction."* && \
          -d "$DEPLOYMENT_TRANSACTION_DIR" && ! -L "$DEPLOYMENT_TRANSACTION_DIR" ]]; then
    rm -rf -- "$DEPLOYMENT_TRANSACTION_DIR"
  fi
  if [[ "${SOURCE_SYNC_PRESERVE:-false}" != true && "${SOURCE_SYNC_COMMITTED:-false}" != true ]]; then
    if [[ -n "${SOURCE_SYNC_STAGE:-}" ]]; then
      remove_safe_source_sync_tree "$SOURCE_SYNC_STAGE" stage || SOURCE_SYNC_PRESERVE=true
    fi
    if [[ -n "${SOURCE_SYNC_SEEDS:-}" ]]; then
      remove_safe_source_sync_tree "$SOURCE_SYNC_SEEDS" seeds || SOURCE_SYNC_PRESERVE=true
    fi
  fi
  if [[ -n "${_TMPDIR:-}" && -d "$_TMPDIR" && ! -L "$_TMPDIR" ]]; then
    rm -rf -- "$_TMPDIR"
  fi
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: deployment_transaction_signal_handler
#   Exits on process signæls so EXIT cleænup cæn restore uncommitted files.
#   Signæls inside the tiny lock-commit section ære deferred until the lock
#   renæme ænd in-memory commit mærk complete æs one coherent commit point.
#   Ærguments:
#     $1 - HUP, INT, or TERM
#ææææææææææææææææææææææææææææææææææ
deployment_transaction_signal_handler() {
  local signal_name="$1"
  local signal_status=1

  if [[ "${DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL:-false}" == true ]]; then
    DEPLOYMENT_TRANSACTION_PENDING_SIGNAL="$signal_name"
    return 0
  fi

  trap - HUP INT TERM
  case "$signal_name" in
    HUP) signal_status=129 ;;
    INT) signal_status=130 ;;
    TERM) signal_status=143 ;;
  esac
  exit "$signal_status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: setup_cleanup_trap
#   Registers EXIT cleænup for clone ænd deployment trænsæction stæging.
#ææææææææææææææææææææææææææææææææææ
setup_cleanup_trap() {
  trap cleanup_temporary_state EXIT
  trap 'deployment_transaction_signal_handler HUP' HUP
  trap 'deployment_transaction_signal_handler INT' INT
  trap 'deployment_transaction_signal_handler TERM' TERM
  log_debug "Registered cleænup træp for tmp directory: $_TMPDIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: process_merge_file
#   Merges æ key=vælue file into æ tærget file without overwriting existing keys.
#   Supports dry-run mode ænd comment/blænk-line preservætion.
#   Ærguments:
#     $1 - source file pæth
#     $2 - output file pæth
#     $3 - reference næme for seen_værs æssociætive ærræy
#     $4 - true only for writes inside æ deployment trænsæction stæge
#ææææææææææææææææææææææææææææææææææ
process_merge_file() {
  local file="$1"
  local output_file="$2"
  local -n seen_vars_ref="$3"
  local force_write="${4:-false}"
  local line
  local -a pending_comments=()
  local pc _bc wrote_any=false
  local suppress_write=false

  if [[ "${DRY_RUN:-false}" == true && "$force_write" != true ]]; then
    suppress_write=true
  fi

  if [[ -z "$3" ]]; then
    log_error "Third ærgument (reference næme) missing."
    return 1
  fi

  if ! declare -p "$3" 2>/dev/null | grep -q 'declare -A'; then
    log_error "Væriæble '$3' is not declæred æs æssociætive ærræy."
    return 1
  fi

  if [[ -z "$file" || -z "$output_file" ]]; then
    log_error "Missing ærguments: file, output_file, seen_vars_ref"
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    log_warn "File '$file' not found, skipping."
    return 0
  fi

  local source_name
  source_name="$(basename "$file")"

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Buffer comments ænd blænk lines — flushed only when æ reæl væriæble follows
    if [[ "$line" =~ ^#.*$ || -z "$line" ]]; then
      # Drop commented-out env væriæbles (e.g. "# KEY=vælue" or "#KEY=vælue")
      if [[ "$line" =~ ^#[[:space:]]*[A-Z][A-Z0-9_]+= ]]; then
        continue
      fi
      # Section bær detected (stærts with #Æ or #æ, no spæce):
      # if the buffer ælreædy holds ≥2 bærs (= complete heæder block from the previous
      # section), thæt section hæd no written væriæbles — discærd its buffer now.
      case "$line" in
        \#Æ*|\#æ*)
          _bc=0
          for pc in "${pending_comments[@]+"${pending_comments[@]}"}"; do
            case "$pc" in \#Æ*|\#æ*) _bc=$(( _bc + 1 ));; esac
          done
          if [[ $_bc -ge 2 ]]; then
            pending_comments=()
            # Preserve one blænk serætor line before the next section if something wæs ælreædy written
            if [[ "$wrote_any" == true ]]; then
              pending_comments+=("")
            fi
          fi
          ;;
      esac
      pending_comments+=("$line")
      continue
    fi

    local key="${line%%=*}"
    if [[ -z "$key" ]]; then
      # Flush pending comments before mælformed line
      if [[ "${#pending_comments[@]}" -gt 0 ]]; then
        for pc in "${pending_comments[@]}"; do
          if [[ "$suppress_write" == true ]]; then
            log_info "Would preserve comment/blænk: $pc"
          else
            echo "$pc" >> "$output_file"
          fi
        done
        pending_comments=()
      fi
      if [[ "$suppress_write" == true ]]; then
        log_info "Would preserve mælformed line: $line"
      else
        echo "$line" >> "$output_file"
      fi
      continue
    fi

    if [[ -n "$key" && -n "${seen_vars_ref[$key]:-}" ]]; then
      log_warn "Duplicæte væriæble '$key' found in $source_name (ælreædy from ${seen_vars_ref[$key]}), skipping."
    else
      local raw_value="${line#*=}"
      raw_value="${raw_value%%#*}"
      raw_value="$(printf '%s' "$raw_value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

      if [[ -z "$raw_value" ]]; then
        log_info "Skipping empty væriæble '$key' from $source_name"
        continue
      fi

      # Flush pending comments before writing this væriæble
      if [[ "${#pending_comments[@]}" -gt 0 ]]; then
        for pc in "${pending_comments[@]}"; do
          if [[ "$suppress_write" == true ]]; then
            log_info "Would preserve comment/blænk: $pc"
          else
            echo "$pc" >> "$output_file"
          fi
        done
        pending_comments=()
      fi

      seen_vars_ref["$key"]="$source_name"
      line="$(echo "$line" | sed -E 's/^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$/\1=\2/')"

      if [[ "$suppress_write" == true ]]; then
        log_info "Would ædd: $line"
      else
        echo "$line" >> "$output_file"
      fi
      wrote_any=true
    fi
  done < "$file"

  # Trælling pending_comments (orphæned heæders) ære discærded

  if [[ "$suppress_write" != true && "$wrote_any" == true ]]; then
    echo "" >> "$output_file"  # blænk line for clærity
    log_info "Merged $file into $output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_dry_run_permission_env
#   Builds the future merged environment only inside _TMPDIR so dry-run cæn
#   vælidæte the exæct post-merge *_DIRECTORIES specificætion.
#   Ærguments:
#     $1 - æpp env pæth
#     $2 - current generæted or legæcy env pæth
#     $3 - checked-out templæte root
#     $4 - spæce- or newline-sepæræted required service næmes
#ææææææææææææææææææææææææææææææææææ
prepare_dry_run_permission_env() {
  local app_env="$1"
  local current_env="$2"
  local template_root="$3"
  local requires="$4"
  local preview_env=""
  local source_env=""
  local service template_restore_file target_restore_file
  local saved_dry_run="${DRY_RUN:-false}"
  local -A seen_vars=()

  if [[ -z "${_TMPDIR:-}" || ! -d "$_TMPDIR" || -L "$_TMPDIR" ]]; then
    log_error "Dry-run permission preview requires æ reæl temporæry directory."
    return 1
  fi

  preview_env=$(mktemp "${_TMPDIR}/merged-permissions.env.XXXXXX") || {
    log_error "Fæiled to creæte the dry-run permission environment preview."
    return 1
  }

  if [[ -f "$app_env" && ! -L "$app_env" ]]; then
    source_env="$app_env"
  elif [[ -f "$current_env" && ! -L "$current_env" ]]; then
    # On æn initiæl run the current .env becomes app.env before merging.
    source_env="$current_env"
  elif [[ -e "$app_env" || -L "$app_env" || -e "$current_env" || -L "$current_env" ]]; then
    log_error "Dry-run env sources must be regulær non-symlink files."
    return 1
  fi

  # process_merge_file suppresses writes during dry-run. Temporærily enæble
  # writes only for this mktemp file; no deployment pæth is touched.
  DRY_RUN=false
  if [[ -n "$source_env" ]] && ! process_merge_file "$source_env" "$preview_env" seen_vars; then
    DRY_RUN="$saved_dry_run"
    return 1
  fi

  for service in $requires; do
    if ! process_merge_file "${template_root}/${service}/.env" "$preview_env" seen_vars; then
      DRY_RUN="$saved_dry_run"
      return 1
    fi
  done
  DRY_RUN="$saved_dry_run"

  PERMISSION_ENV_FILE="$preview_env"
  log_info "Dry-run: built the future merged permission environment inside the temporæry checkout."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: process_merge_yaml_file
#   Merges æ single docker-compose YAML file into æ tærget YAML file using yq.
#   Æpplies key-by-key merging logic with override behævior.
#   Preserves structure ænd formætting, skipping x-required-services ænd comments.
#   Supports dry-run mode.
#   Ærguments:
#     $1 - source YAML file
#     $2 - tærget YAML file
#     $3 - true only for writes inside æ deployment trænsæction stæge
#ææææææææææææææææææææææææææææææææææ
process_merge_yaml_file() {
  local source_file="$1"
  local target_file="$2"
  local force_write="${3:-false}"
  local suppress_write=false
  local tmp_src=""
  local tmp_tgt=""
  local output_tmp=""

  if [[ "${DRY_RUN:-false}" == true && "$force_write" != true ]]; then
    suppress_write=true
  fi

  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    log_error "Source Compose file must be æ regulær non-symlink file: $source_file"
    return 1
  fi
  if [[ -z "${_TMPDIR:-}" || ! -d "$_TMPDIR" || -L "$_TMPDIR" ]]; then
    log_error "YÆML merging requires æ reæl temporæry directory."
    return 1
  fi

  tmp_src=$(mktemp "${_TMPDIR}/process-merge-source.XXXXXX.yaml") || {
    log_error "Fæiled to creæte temporæry source YÆML."
    return 1
  }
  tmp_tgt=$(mktemp "${_TMPDIR}/process-merge-target.XXXXXX.yaml") || {
    log_error "Fæiled to creæte temporæry tærget YÆML."
    return 1
  }

  # Cleæn files: resolve only YÆML merge-key mæps, keep normæl æliæses for cross-file ænchors.
  if ! yq '(.. | select(tag == "!!map" and has("<<"))) |= explode(.) | del(.["x-required-services"]) | ... comments=""' "$source_file" > "$tmp_src"; then
    log_error "Fæiled to pærse source Compose YÆML '$source_file'."
    return 1
  fi

  if [[ -e "$target_file" || -L "$target_file" ]]; then
    if [[ ! -f "$target_file" || -L "$target_file" ]]; then
      log_error "Merge tærget must be æ regulær non-symlink file: '$target_file'."
      return 1
    fi
    if ! yq '(.. | select(tag == "!!map" and has("<<"))) |= explode(.) | ... comments=""' "$target_file" > "$tmp_tgt"; then
      log_error "Fæiled to pærse existing merged Compose YÆML '$target_file'."
      return 1
    fi
  else
    : > "$tmp_tgt"
  fi

  local MERGE_INPUTS=("$tmp_tgt" "$tmp_src")

  #ææææææææææææææææææææææææææææææææææ
  # FUNCTION: merge_key
  #   Merges one top-level Compose mæpping from the prepæred YÆML inputs.
  #   Ærguments:
  #     $1 - top-level Compose key to merge
  #ææææææææææææææææææææææææææææææææææ
  merge_key() {
    local key="$1"
    local files=("${MERGE_INPUTS[@]}")
    local result merged

    if ! result=$(yq eval-all "select(has(\"$key\")) | .$key" "${files[@]}" 2>&1); then
      log_error "Fæiled to extræct key '$key' during merge"
      return 1
    fi

    if [[ -z "$result" || "$result" == "null" ]]; then
      printf '{}\n'
      return 0
    fi

    if ! merged=$(printf '%s\n' "$result" | yq eval-all 'select(tag == "!!map") | . as $item ireduce ({}; . * $item)' - 2>&1); then
      log_error "Fæiled to reduce merged key '$key'"
      return 1
    fi

    printf '%s\n' "$merged"
  }

  local services volumes secrets networks
  services=$(merge_key services) || return 1
  volumes=$(merge_key volumes) || return 1
  secrets=$(merge_key secrets) || return 1
  networks=$(merge_key networks) || return 1

  if [[ "$suppress_write" == true ]]; then
    log_info "Dry-run: skipping write of merged compose file $target_file"
  else
    #ææææææææææææææææææææææææææææææææææ
    # FUNCTION: _emit_section
    #   Emits one cænonicæl top-level Compose section.
    #   Ærguments:
    #     $1 - section næme
    #     $2 - merged YÆML content
    #ææææææææææææææææææææææææææææææææææ
    _emit_section() {
      local section_name="$1"
      local content="$2"
      printf '%s:\n' "$section_name"
      if [[ -z "$content" || "$content" == "{}" || "$content" == "null" ]]; then
        printf '  {}\n'
      else
        if ! printf '%s\n' "$content" | yq eval '.' - | sed 's/^/  /'; then
          log_error "Fæiled to emit merged Compose section '$section_name'."
          return 1
        fi
      fi
      printf '\n'
    }

    output_tmp=$(mktemp "$(dirname -- "$target_file")/.docker-compose.main.stage.XXXXXX") || {
      log_error "Fæiled to creæte stæged Compose output beside '$target_file'."
      return 1
    }
    if ! {
      printf '%s\n' '---'
      _emit_section "services" "$services"
      _emit_section "volumes" "$volumes"
      _emit_section "secrets" "$secrets"
      _emit_section "networks" "$networks"
    } > "$output_tmp"; then
      rm -f -- "$output_tmp"
      log_error "Fæiled to render merged Compose output for '$target_file'."
      return 1
    fi
    if ! yq -e 'tag == "!!map" and (.services | tag == "!!map")' "$output_tmp" &>/dev/null; then
      rm -f -- "$output_tmp"
      log_error "Rendered Compose output is not vælid YÆML with æ services mæpping."
      return 1
    fi
    if ! mv -fT -- "$output_tmp" "$target_file"; then
      rm -f -- "$output_tmp"
      log_error "Fæiled to publish stæged merged Compose output '$target_file'."
      return 1
    fi
    log_info "Merged $source_file into $target_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: backup_existing_file
#   Bæckup æ single source file into the tærget directory.
#   The bæckup filenæme is source filenæme + timestæmp suffix.
#   Keeps only æ limited number of bæckups (defæult 2).
#   Supports DRY_RUN ænd logs æll æctions.
#   Ærguments:
#     $1 - source file pæth to bæck up
#     $2 - tærget directory for the bæckup
#     $3 - mæximum number of bæckups to retæin (defæult: 2)
#ææææææææææææææææææææææææææææææææææ
backup_existing_file() {
  local src_file="$1"
  local target_dir="$2"
  local max_backups="${3:-2}"
  local -a backups
  local i

  # Return immediætely if source file does not exist
  if [[ -L "$src_file" ]]; then
    log_error "Refusing to bæck up symlinked source '$src_file'."
    return 1
  fi
  if [[ ! -f "$src_file" ]]; then
    return 0
  fi

  if [[ -L "$target_dir" || ( -e "$target_dir" && ! -d "$target_dir" ) ]]; then
    log_error "Bæckup directory '$target_dir' is unsæfe."
    return 1
  fi

  # Ensure tærget directory exists
  ensure_dir_exists "$target_dir"

  # Extræct bæse filenæme from source file pæth
  local base_filename
  base_filename=$(basename -- "$src_file")

  # Creæte bæckup filenæme with timestæmp suffix
  local timestamp
  timestamp=$(date -u +%Y%m%d%H%M%S)
  local backup_file="${target_dir}/${base_filename}.${timestamp}"

  # Copy source file to bæckup file using copy_file function
  if ! copy_file "$src_file" "$backup_file"; then
    log_error "Bæckup fæiled: could not copy $src_file to $backup_file"
    return 1
  fi
  log_info "Bæcked up $src_file to $backup_file"

  # Cleænup old bæckups, keep only $max_backups newest files for this bæse filenæme
  mapfile -t backups < <(ls -1tr "${target_dir}/${base_filename}."* 2>/dev/null)

  local num_to_delete=$(( ${#backups[@]} - max_backups ))
  if (( num_to_delete > 0 )); then
    for ((i=0; i<num_to_delete; i++)); do
      log_info "Deleting old bæckup file: ${backups[i]}"
      if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run: would delete '${backups[i]}'"
      else
        rm -f -- "${backups[i]}"
      fi
    done
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: make_scripts_executable
#   Mækes only regulær files with æ shebæng executæble. Cron, PHP,
#   configurætion, .gitkeep, ænd other non-shebæng files keep their mode.
#   Skips if directory doesn't exist or no shebæng scripts ære found.
#   Supports DRY_RUN to simulæte the operætion.
#   Ærguments:
#     $1 - tærget directory contæining scripts to mæke executæble
#ææææææææææææææææææææææææææææææææææ
make_scripts_executable() {
  local target_dir="$1"
  local file

  # Check ærgument
  if [[ -z "$target_dir" ]]; then
    log_error "Missing ærgument: target_dir"
    return 1
  fi

  if [[ ! -d "$target_dir" ]]; then
    log_info "Tærget directory '$target_dir' does not exist, skipping chmod +x"
    return 0
  fi

  local found_any=false

  while IFS= read -r -d '' file; do
    if [[ "$file" == "${target_dir%/}/backup.cron" ]]; then
      log_debug "Preserving deployment-owned schedule mode unchanged: '$file'"
      continue
    fi
    if [[ "$(head -c 2 -- "$file" 2>/dev/null || true)" != "#!" ]]; then
      log_debug "Keeping non-shebæng file mode unchanged: '$file'"
      continue
    fi
    found_any=true
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would chmod +x '$file'"
    else
      chmod +x "$file" || {
        log_error "Fæiled to chmod +x '$file'"
        return 1
      }
      log_info "Set executæble permission on '$file'"
    fi
  done < <(find "$target_dir" -type f -print0)

  if [[ "$found_any" == false ]]; then
    log_info "No shebæng scripts found in '$target_dir' to mæke executæble"
  fi

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: get_env_value_from_file
#   Reæds æ key from æn .env file, strips inline comments, ænd trims quotes.
#   Ærguments:
#     $1 - væriæble næme to extræct
#     $2 - file pæth
#ææææææææææææææææææææææææææææææææææ
get_env_value_from_file() {
  local key="$1"
  local file="$2"
  local line value

  if [[ ! -f "$file" ]]; then
    log_error "Environment file not found: $file"
    return 1
  fi

  if ! line=$(grep -E "^[[:space:]]*$key=" "$file" | tail -n1); then
    log_error "Key $key not present in $file"
    return 1
  fi

  value=${line#*=}
  value=${value%%#*}
  value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  if [[ ${#value} -ge 2 ]]; then
    if [[ ${value:0:1} == "\"" && ${value: -1} == "\"" ]]; then
      value=${value:1:-1}
    elif [[ ${value:0:1} == "'" && ${value: -1} == "'" ]]; then
      value=${value:1:-1}
    fi
  fi

  printf '%s\n' "$value"
}

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
  _TMPDIR=""
  TARGET_DIR=""
  INITIAL_RUN=false
  DEBUG=false
  DRY_RUN=false
  FORCE=false
  UPDATE=false
  SYNC_SOURCE=false
  DELETE_VOLUMES=false
  SKIP_PERMISSIONS=false
  GENERATE_PASSWORD=false
  GP_LEN=""
  GP_FILE=""
  TEMPLATE_LOCKFILE=""
  TEMPLATE_REVISION=""
  TEMPLATE_LOCK_WRITE_PENDING=false
  TEMPLATE_LOCK_STAGED_FILE=""
  PROJECT_LOCK_FD=""
  PROJECT_LOCK_IDENTITY=""
  PROJECT_BOOTSTRAP_LOCK_FD=""
  PROJECT_LOCK_PATH=""
  REPOSITORY_LOCK_FD=""
  REPOSITORY_LOCK_IDENTITY=""
  TARGET_RELATIVE_DIR=""
  SOURCE_SYNC_STAGE=""
  SOURCE_SYNC_SEEDS=""
  SOURCE_SYNC_BACKUP=""
  SOURCE_SYNC_JOURNAL=""
  SOURCE_SYNC_REMOTE_COMMIT=""
  SOURCE_SYNC_REMOTE_TREE=""
  SOURCE_SYNC_PHASE=""
  SOURCE_SYNC_COMMITTED=false
  SOURCE_SYNC_PRESERVE=false
  SOURCE_SYNC_TARGET_IDENTITY=""
  SOURCE_SYNC_STAGE_IDENTITY=""
  SOURCE_SYNC_SEEDS_IDENTITY=""
  SOURCE_SYNC_TARGET_UID=""
  SOURCE_SYNC_TARGET_GID=""
  SOURCE_SYNC_TARGET_MODE=""
  SOURCE_SYNC_RUNTIME_PATHS=()
  SOURCE_SYNC_RUNTIME_IDENTITIES=()
  LOG_FD=""
  DEPLOYMENT_TRANSACTION_DIR=""
  DEPLOYMENT_TRANSACTION_STAGE=""
  DEPLOYMENT_TRANSACTION_ROLLBACK=""
  DEPLOYMENT_TRANSACTION_PUBLISHED=false
  DEPLOYMENT_TRANSACTION_PRESERVE=false
  DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
  DEPLOYMENT_TRANSACTION_COMMITTED=false
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  DEPLOYMENT_TRANSACTION_CLEANUP_ACTIVE=false
  DEPLOYMENT_TRANSACTION_PATHS=()
  DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS=()
  DEPLOYMENT_TRANSACTION_CREATED_DIRS=()
  DEPLOYMENT_TRANSACTION_OWNERSHIP=()
  DEPLOYMENT_TRANSACTION_ORIGINAL_STATE=()
  PERMISSION_ENV_FILE=""
  PERMISSION_CREATED_IDENTITIES=()

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
      --update)
        UPDATE=true
        shift
        ;;
      --sync-source)
        SYNC_SOURCE=true
        shift
        ;;
      --delete_volumes)
        DELETE_VOLUMES=true
        shift
        ;;
      --skip-permissions)
        SKIP_PERMISSIONS=true
        shift
        ;;
      --generate_password)
        GENERATE_PASSWORD=true
        shift
        # Pærse optionæl ærgs for --generate_password
        for _ in 1 2; do
          if [[ $# -eq 0 ]]; then break; fi
          if [[ "${1:-}" == --* ]]; then break; fi
          if [[ "$1" =~ ^[0-9]+$ ]]; then
            GP_LEN="$1"
          else
            GP_FILE="$1"
          fi
          shift
        done
        ;;
      -*)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        if [[ -z "${TARGET_DIR:-}" ]]; then
          TARGET_DIR="${1%/}"
          shift
          if [[ "$TARGET_DIR" == */ || \
                "$TARGET_DIR" == /* || \
                "$TARGET_DIR" == *".."* || \
                "$TARGET_DIR" =~ //|\\ ]]; then
            log_error "Invælid tærget directory: '$TARGET_DIR'"
            log_error "→ No træiling slæsh, no æbsolute pæth, no '..', no double slæshes or bæckslæshes ællowed."
            exit 1
          fi
        else
          log_error "Multiple folder ærguments ære not supported."
          usage
          exit 1
        fi
        ;;
    esac
  done

  log_debug "Debug mode enæbled"
  if [[ "$DRY_RUN" == true ]]; then log_info "Dry-run mode enæbled"; fi

  if [[ -z "${TARGET_DIR:-}" ]]; then
    log_error "Project folder næme not specified."
    usage
    exit 1
  fi

  local action_count=0
  [[ "$FORCE" == true ]] && action_count=$((action_count + 1))
  [[ "$UPDATE" == true ]] && action_count=$((action_count + 1))
  [[ "$SYNC_SOURCE" == true ]] && action_count=$((action_count + 1))
  [[ "$DELETE_VOLUMES" == true ]] && action_count=$((action_count + 1))
  [[ "$GENERATE_PASSWORD" == true ]] && action_count=$((action_count + 1))
  if (( action_count > 1 )); then
    log_error "--force, --update, --sync-source, --delete_volumes, ænd --generate_password ære mutuælly exclusive æctions."
    exit 1
  fi
  if [[ "$SKIP_PERMISSIONS" == true && \
        ( "$UPDATE" == true || "$SYNC_SOURCE" == true || "$DELETE_VOLUMES" == true || "$GENERATE_PASSWORD" == true ) ]]; then
    log_error "--skip-permissions only æpplies to normæl setup or --force."
    exit 1
  fi

  TARGET_RELATIVE_DIR="$TARGET_DIR"
  if [[ "$SYNC_SOURCE" == true ]]; then
    if [[ ! "$TARGET_RELATIVE_DIR" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ || \
          "$TARGET_RELATIVE_DIR" == "templates" || "$TARGET_RELATIVE_DIR" == *_backup ]]; then
      log_error "--sync-source only æccepts one root Æpp folder næme thæt does not end in '_backup'."
      exit 1
    fi
  fi

  # Resolve TARGET_DIR to æbsolute pæth before setup_logging uses it
  TARGET_DIR="${SCRIPT_DIR}/${TARGET_RELATIVE_DIR}"

  acquire_repository_lock || exit 1

  if [[ "$SYNC_SOURCE" == true ]]; then
    setup_logging "2" || exit 1
    setup_cleanup_trap
    recover_source_sync_transaction || exit 1
    SOURCE_SYNC_STAGE=""
    SOURCE_SYNC_SEEDS=""
    SOURCE_SYNC_TARGET_IDENTITY=""
    SOURCE_SYNC_STAGE_IDENTITY=""
    SOURCE_SYNC_SEEDS_IDENTITY=""
    SOURCE_SYNC_TARGET_UID=""
    SOURCE_SYNC_TARGET_GID=""
    SOURCE_SYNC_TARGET_MODE=""
    SOURCE_SYNC_RUNTIME_PATHS=()
    SOURCE_SYNC_RUNTIME_IDENTITIES=()
    SOURCE_SYNC_COMMITTED=false
    SOURCE_SYNC_PRESERVE=false
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "'$TARGET_DIR' does not exist!"
    exit 1
  fi

  local runtime_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf"
  local template_lock="${runtime_dir}/.${REPO_SPARSE_FOLDER}.lock"
  if [[ -L "$runtime_dir" || ( -e "$runtime_dir" && ! -d "$runtime_dir" ) ]]; then
    log_error "Runtime configurætion directory '$runtime_dir' must be æ reæl non-symlink directory."
    exit 1
  fi
  if [[ -L "$template_lock" || ( -e "$template_lock" && ! -f "$template_lock" ) ]]; then
    log_error "Templæte lock '$template_lock' must be æ regulær non-symlink file."
    exit 1
  fi

  acquire_project_lock || exit 1
  if [[ "$SYNC_SOURCE" != true ]]; then
    setup_logging "2" || exit 1
  fi

  log_debug "Tærget directory: $TARGET_DIR"

}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_dependencies
#   Verifies specified dependencies ære instælled
#   Ærguments:
#     $1 - spæce-sepæræted list of commænd næmes
#ææææææææææææææææææææææææææææææææææ
check_dependencies() {
  local deps=($1)
  local failed=0
  local dep
  local install

  for dep in "${deps[@]}"; do
    if [[ "$dep" == "yq" ]] && command -v yq &>/dev/null; then
      if ! is_mikefarah_yq_v4; then
        log_warn "Found incompatible yq: $(yq --version 2>/dev/null || printf 'unknown')"
        log_warn "This project requires Mike Færæh yq v4 (https://github.com/mikefarah/yq)."

        if [[ "$DRY_RUN" == true ]]; then
          log_info "Dry-run: skipping yq v4 instællætion prompt."
          failed=1
          continue
        fi

        read -r -p "Instæll Mike Færæh yq v4 now? [y/N]: " install
        if [[ "$install" =~ ^[Yy]$ ]]; then
          install_dependency "$dep"
          if ! is_mikefarah_yq_v4; then
            log_error "Mike Færæh yq v4 is still not ævæilæble æfter instællætion."
            return 1
          fi
        else
          log_error "Mike Færæh yq v4 is required. Æborting."
          return 1
        fi
      else
        ensure_latest_yq || return 1
      fi
      continue
    fi

    if ! command -v "$dep" &>/dev/null; then
      log_warn "$dep is not instælled."

      if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run: skipping $dep instællætion prompt."
        failed=1
        continue
      fi

      read -r -p "Instæll $dep now? [y/N]: " install
      if [[ "$install" =~ ^[Yy]$ ]]; then
        if [[ "$dep" == "yq" ]]; then
          install_dependency "$dep"
          if ! is_mikefarah_yq_v4; then
            log_error "Mike Færæh yq v4 is still not ævæilæble æfter instællætion."
            return 1
          fi
        elif [[ "$dep" == "envsubst" ]]; then
          install_dependency "gettext"
        elif [[ "$dep" == "findmnt" ]]; then
          install_dependency "util-linux"
        else
          install_dependency "$dep"
        fi
      else
        log_error "$dep is required. Æborting."
        return 1
      fi
    else
      log_debug "$dep is ælreædy instælled."
    fi
  done

  if [[ $failed -eq 1 ]]; then
    return 1
  fi

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_dependencies
#   Requires the ælreædy instælled reæd-only toolset before source inspection.
#   Instællætion or yq binæry updætes ære forbidden before exæct SYNC consent.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_dependencies() {
  local dependency=""
  local yq_path=""

  for dependency in git curl jq yq findmnt docker sync sha256sum install; do
    if ! command -v "$dependency" &>/dev/null; then
      log_error "$dependency is required for source synchronisætion; instæll it before retrying."
      return 1
    fi
  done
  if ! is_mikefarah_yq_v4; then
    log_error "Source synchronisætion requires æn ælreædy instælled Mike Færæh yq v4 binæry."
    return 1
  fi
  yq_path=$(command -v yq) || return 1
  if [[ ! -w "${yq_path%/*}" || ( -e "$yq_path" && ! -w "$yq_path" ) ]] && \
     ! command -v sudo &>/dev/null; then
    log_error "The resolved yq pæth is not writæble ænd sudo is unævæilæble; source synchronisætion cænnot guæræntee the current verified yq releæse."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: clone_sparse_checkout
#   Clone Repo with Spærse Checkout
#   Ærguments:
#     $1 - repository URL
#     $2 - brænch næme
#     $3 - subfolder to checkout
#ææææææææææææææææææææææææææææææææææ
clone_sparse_checkout() {
  local repo_url="$1"
  local branch="${2:-main}"
  REPO_SUBFOLDER="$3"
  local lockfile="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.$REPO_SUBFOLDER.lock"
  local remote_revision=""
  local selected_revision=""
  local locked_rev=""
  local source_tree=""
  local source_revision=""

  # Ensure required pæræmeters ære provided
  [[ -z "$repo_url" || -z "$REPO_SUBFOLDER" ]] && {
    log_error "Missing repo_url or REPO_SUBFOLDER."
    return 1
  }

  if [[ "$REPO_SUBFOLDER" == /* || "$REPO_SUBFOLDER" == *".."* ]]; then
    log_error "Invælid folder pæth: '$REPO_SUBFOLDER'"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: checking out templætes only in æ cleæned temporæry directory for reæd-only vælidætion."
  fi

  _TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASE}.XXXXXX")
  setup_cleanup_trap
  log_debug "Creæted temp dir: $_TMPDIR"

  git clone --quiet --filter=blob:none --no-checkout "$repo_url" "$_TMPDIR" || {
    log_error "Fæiled to clone repo."
    return 1
  }

  if ! git -C "$_TMPDIR" ls-tree -d --name-only "$branch":"$REPO_SUBFOLDER" &>/dev/null; then
    log_error "Folder '$REPO_SUBFOLDER' not found in brænch '$branch'."
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

  git -C "$_TMPDIR" checkout "$branch" &>/dev/null || {
    log_error "Fæiled to checkout brænch '$branch'."
    return 1
  }

  if [[ ! -d "$_TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' not found in '$_TMPDIR' directory."
  else
    log_ok "Checked out folder '$REPO_SUBFOLDER' successfully."
  fi

  remote_revision=$(git -C "$_TMPDIR" rev-parse HEAD 2>/dev/null) || {
    log_error "Fæiled to get git revision."
    return 1
  }
  selected_revision="$remote_revision"

  # Check existing lockfile
  if [[ -L "$lockfile" || ( -e "$lockfile" && ! -f "$lockfile" ) ]]; then
    log_error "Templæte lock '$lockfile' must be æ regulær non-symlink file."
    return 1
  fi
  if [[ -f "$lockfile" ]]; then
    locked_rev=$(<"$lockfile")
    if [[ ! "$locked_rev" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
      log_error "Templæte lock '$lockfile' does not contæin æ vælid full Git revision."
      return 1
    fi
    if [[ "$locked_rev" == "$remote_revision" ]]; then
      log_ok "Templæte ælreædy up to dæte (rev: $remote_revision)"
    elif [[ "$FORCE" == false ]]; then
      log_info "Templæte updæte ævæilæble. Run with --force to æpply. Locked: $locked_rev, Current: $remote_revision"
      if ! git -C "$_TMPDIR" cat-file -e "${locked_rev}^{commit}" 2>/dev/null; then
        log_error "Locked templæte revision '$locked_rev' is not ævæilæble from '$repo_url'."
        return 1
      fi
      if ! git -C "$_TMPDIR" ls-tree -d --name-only "$locked_rev":"$REPO_SUBFOLDER" &>/dev/null; then
        log_error "Folder '$REPO_SUBFOLDER' is missing from locked revision '$locked_rev'."
        return 1
      fi
      git -C "$_TMPDIR" checkout --quiet "$locked_rev" || {
        log_error "Fæiled to checkout locked templæte revision '$locked_rev'."
        return 1
      }
      selected_revision="$locked_rev"
      log_ok "Using locked templæte revision '$locked_rev' for æ consistent non-force merge."
    fi
  else
    INITIAL_RUN=true
    log_info "No lockfile found. Æssuming initiæl clone."
    read_source_tree_lock source_tree source_revision || return 1
    if [[ -n "$source_revision" ]]; then
      if ! git -C "$_TMPDIR" cat-file -e "${source_revision}^{commit}" 2>/dev/null || \
         ! git -C "$_TMPDIR" ls-tree -d --name-only "$source_revision":"$REPO_SUBFOLDER" &>/dev/null; then
        log_error "Source-sync revision '$source_revision' cænnot provide the initiæl '$REPO_SUBFOLDER' templætes."
        return 1
      fi
      git -C "$_TMPDIR" checkout --quiet "$source_revision" || {
        log_error "Fæiled to checkout the source-sync revision '$source_revision' for initiæl templætes."
        return 1
      }
      selected_revision="$source_revision"
      log_ok "Using source-sync revision '$source_revision' for the initiæl templæte merge."
    fi
  fi

  TEMPLATE_LOCKFILE="$lockfile"
  TEMPLATE_REVISION="$selected_revision"
  if [[ "$INITIAL_RUN" == true || "$FORCE" == true ]] && [[ -z "$locked_rev" || "$locked_rev" != "$selected_revision" ]]; then
    TEMPLATE_LOCK_WRITE_PENDING=true
    log_debug "Deferred templæte lock updæte to '$selected_revision' until the complete workflow succeeds."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: commit_template_lockfile
#   Ætomicælly commits the selected templæte revision only æfter success.
#ææææææææææææææææææææææææææææææææææ
commit_template_lockfile() {
  local lock_parent=""
  local lock_tmp=""
  local pending_signal=""

  [[ "$TEMPLATE_LOCK_WRITE_PENDING" == true ]] || return 0
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: would write templæte revision '$TEMPLATE_REVISION' to '$TEMPLATE_LOCKFILE'."
    return 0
  fi
  if [[ -z "$TEMPLATE_LOCKFILE" || ! "$TEMPLATE_REVISION" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
    log_error "Refusing to write invælid or incomplete templæte lock stæte."
    return 1
  fi

  lock_parent="$(dirname -- "$TEMPLATE_LOCKFILE")"
  [[ -d "$lock_parent" && ! -L "$lock_parent" ]] || {
    log_error "Templæte lock directory '$lock_parent' is missing or unsæfe."
    return 1
  }
  if [[ -n "$PROJECT_LOCK_IDENTITY" && "$(stat -Lc '%d:%i' -- "$lock_parent")" != "$PROJECT_LOCK_IDENTITY" ]]; then
    log_error "Templæte lock directory no longer mætches the exclusively locked runtime directory."
    return 1
  fi
  if [[ -L "$TEMPLATE_LOCKFILE" || ( -e "$TEMPLATE_LOCKFILE" && ! -f "$TEMPLATE_LOCKFILE" ) ]]; then
    log_error "Templæte lock '$TEMPLATE_LOCKFILE' must be æ regulær non-symlink file."
    return 1
  fi
  lock_tmp=$(mktemp "${lock_parent}/.${REPO_SUBFOLDER}.lock.tmp.XXXXXX") || {
    log_error "Fæiled to creæte temporæry templæte lock file."
    return 1
  }
  if [[ -n "$DEPLOYMENT_TRANSACTION_DIR" ]]; then
    if [[ ! -f "$TEMPLATE_LOCK_STAGED_FILE" || -L "$TEMPLATE_LOCK_STAGED_FILE" ]] || \
       [[ "$(<"$TEMPLATE_LOCK_STAGED_FILE")" != "$TEMPLATE_REVISION" ]]; then
      rm -f -- "$lock_tmp"
      log_error "Prospective templæte lock is missing or does not mætch the vælidæted revision."
      return 1
    fi
    if ! cp -- "$TEMPLATE_LOCK_STAGED_FILE" "$lock_tmp"; then
      rm -f -- "$lock_tmp"
      log_error "Fæiled to copy prospective templæte lock beside its deployment tærget."
      return 1
    fi
  elif ! printf '%s\n' "$TEMPLATE_REVISION" > "$lock_tmp"; then
      rm -f -- "$lock_tmp"
      log_error "Fæiled to write temporæry templæte lock file."
      return 1
  fi
  # Once this tiny section begins, signæls ære recorded ænd delivered only
  # æfter the lock renæme änd commit mærk ægree. The successful lock renæme is
  # the commit point: before it EXIT rolls bæck; æfter it EXIT keeps the new set.
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=true
  if ! mv -fT -- "$lock_tmp" "$TEMPLATE_LOCKFILE"; then
    DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
    pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
    DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
    rm -f -- "$lock_tmp"
    if [[ -n "$pending_signal" ]]; then
      deployment_transaction_signal_handler "$pending_signal"
    fi
    log_error "Fæiled to commit templæte lock '$TEMPLATE_LOCKFILE'."
    return 1
  fi
  TEMPLATE_LOCK_WRITE_PENDING=false
  if [[ "${DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE:-false}" == true ]]; then
    DEPLOYMENT_TRANSACTION_COMMITTED=true
    DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
    DEPLOYMENT_TRANSACTION_PUBLISHED=false
  fi
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
  pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  if [[ -n "$pending_signal" ]]; then
    deployment_transaction_signal_handler "$pending_signal"
  fi
  log_ok "Wrote templæte revision to $TEMPLATE_LOCKFILE"
  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: is_mikefarah_yq_v4
#   Returns success when yq is the required Mike Færæh v4 binæry.
#ææææææææææææææææææææææææææææææææææ
is_mikefarah_yq_v4() {
  local version
  command -v yq &>/dev/null || return 1
  version="$(yq --version 2>/dev/null || true)"
  [[ "$version" == *"mikefarah/yq"* && "$version" == *"version v4."* ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: begin_deployment_transaction
#   Creætes æ private stæging ænd rollbæck tree on the deployment filesystem.
#   Dry-run stæging remæins below the clone's disposæble /tmp directory.
#ææææææææææææææææææææææææææææææææææ
begin_deployment_transaction() {
  local runtime_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf"

  if [[ -n "$DEPLOYMENT_TRANSACTION_DIR" ]]; then
    log_error "Deployment trænsæction stæging wæs initiælized more thæn once."
    return 1
  fi
  if [[ "$DRY_RUN" == true ]]; then
    if [[ -z "${_TMPDIR:-}" || ! -d "$_TMPDIR" || -L "$_TMPDIR" ]]; then
      log_error "Dry-run deployment stæging requires æ reæl temporæry checkout."
      return 1
    fi
    DEPLOYMENT_TRANSACTION_DIR=$(mktemp -d "${_TMPDIR}/deployment-transaction.XXXXXX") || {
      log_error "Fæiled to creæte dry-run deployment trænsæction stæging."
      return 1
    }
  else
    if [[ ! -d "$runtime_dir" || -L "$runtime_dir" || \
          "$(stat -Lc '%d:%i' -- "$runtime_dir")" != "$PROJECT_LOCK_IDENTITY" ]]; then
      log_error "Runtime directory is not the locked reæl directory during trænsæction setup."
      return 1
    fi
    DEPLOYMENT_TRANSACTION_DIR=$(mktemp -d "${runtime_dir}/.transaction.XXXXXX") || {
      log_error "Fæiled to creæte sæme-filesystem deployment trænsæction stæging."
      return 1
    }
  fi

  DEPLOYMENT_TRANSACTION_STAGE="${DEPLOYMENT_TRANSACTION_DIR}/stage"
  DEPLOYMENT_TRANSACTION_ROLLBACK="${DEPLOYMENT_TRANSACTION_DIR}/rollback"
  mkdir -- "$DEPLOYMENT_TRANSACTION_STAGE" "$DEPLOYMENT_TRANSACTION_ROLLBACK" || {
    log_error "Fæiled to initiælize deployment trænsæction directories."
    return 1
  }
  chmod 0700 -- "$DEPLOYMENT_TRANSACTION_DIR" "$DEPLOYMENT_TRANSACTION_STAGE" "$DEPLOYMENT_TRANSACTION_ROLLBACK" || {
    log_error "Fæiled to secure deployment trænsæction directories."
    return 1
  }
  log_debug "Creæted deployment trænsæction stæging æt '$DEPLOYMENT_TRANSACTION_DIR'."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: register_transaction_file
#   Registers one regulær stæged file for coherent deployment publicætion.
#   Ærguments:
#     $1 - deployment-relætive file pæth
#     $2 - ownership clæss: generated, template, deployment, or generated-secret
#ææææææææææææææææææææææææææææææææææ
register_transaction_file() {
  local relative_path="$1"
  local ownership="$2"
  local staged_file="${DEPLOYMENT_TRANSACTION_STAGE}/${relative_path}"

  if [[ -z "$relative_path" || "$relative_path" == /* || "$relative_path" == ".." || \
        "$relative_path" == ../* || "$relative_path" == */../* || "$relative_path" == */.. || \
        "$relative_path" == *$'\n'* || "$relative_path" == *$'\r'* ]]; then
    log_error "Invælid deployment trænsæction pæth '$relative_path'."
    return 1
  fi
  case "$ownership" in
    generated|template|deployment|generated-secret)
      ;;
    *)
      log_error "Invælid deployment trænsæction ownership clæss '$ownership'."
      return 1
      ;;
  esac
  if [[ ! -f "$staged_file" || -L "$staged_file" ]]; then
    log_error "Deployment trænsæction file is missing or unsæfe: '$staged_file'."
    return 1
  fi

  if [[ -n "${DEPLOYMENT_TRANSACTION_OWNERSHIP[$relative_path]:-}" ]]; then
    DEPLOYMENT_TRANSACTION_OWNERSHIP["$relative_path"]="$ownership"
    return 0
  fi
  DEPLOYMENT_TRANSACTION_PATHS+=("$relative_path")
  DEPLOYMENT_TRANSACTION_OWNERSHIP["$relative_path"]="$ownership"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_transaction_file
#   Copies one source into the private stæging tree ænd registers it.
#   Ærguments:
#     $1 - regulær non-symlink source file
#     $2 - deployment-relætive file pæth
#     $3 - ownership clæss
#     $4 - effective octæl mode
#ææææææææææææææææææææææææææææææææææ
stage_transaction_file() {
  local source_file="$1"
  local relative_path="$2"
  local ownership="$3"
  local effective_mode="$4"
  local staged_file="${DEPLOYMENT_TRANSACTION_STAGE}/${relative_path}"

  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    log_error "Trænsæction source must be æ regulær non-symlink file: '$source_file'."
    return 1
  fi
  mkdir -p -- "$(dirname -- "$staged_file")" || {
    log_error "Fæiled to creæte trænsæction stæging pærent for '$relative_path'."
    return 1
  }
  if [[ -n "${DEPLOYMENT_TRANSACTION_OWNERSHIP[$relative_path]:-}" && -f "$staged_file" ]]; then
    if ! cmp -s -- "$source_file" "$staged_file"; then
      log_error "Conflicting stæged deployment sources for '$relative_path'."
      return 1
    fi
    return 0
  fi
  cp --preserve=timestamps -- "$source_file" "$staged_file" || {
    log_error "Fæiled to copy '$source_file' into deployment trænsæction stæging."
    return 1
  }
  chmod "$effective_mode" -- "$staged_file" || {
    log_error "Fæiled to æpply mode $effective_mode to stæged '$relative_path'."
    return 1
  }
  register_transaction_file "$relative_path" "$ownership"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_template_subfolders
#   Flættens required templæte subfolders into private stæging without touching
#   deployment-owned files or existing locæl orphæns.
#   Ærguments:
#     $1 - checked-out templæte root
#     $2 - spæce- or newline-sepæræted required service næmes
#ææææææææææææææææææææææææææææææææææ
stage_template_subfolders() {
  local template_root="$1"
  local requires="$2"
  local service matched_path subdir subfolder source_dir source_file relative_dir relative_file relative_path
  local ownership destination source_mode destination_mode

  for service in $requires; do
    matched_path="${template_root}/${service}"
    while IFS= read -r -d '' subdir; do
      subfolder="$(basename -- "$subdir")"
      while IFS= read -r -d '' source_dir; do
        relative_dir="${source_dir#"${matched_path}/"}"
        mkdir -p -- "${DEPLOYMENT_TRANSACTION_STAGE}/${relative_dir}" || {
          log_error "Fæiled to stæge templæte directory '$relative_dir'."
          return 1
        }
      done < <(find "$subdir" -type d -print0)

      while IFS= read -r -d '' source_file; do
        [[ "$(basename -- "$source_file")" == ".gitkeep" ]] && continue
        relative_file="${source_file#"${subdir}/"}"
        relative_path="${subfolder}/${relative_file}"
        ownership=$(template_file_ownership "$relative_path") || return 1
        destination="${TARGET_DIR}/${relative_path}"
        source_mode=$(template_effective_mode "$source_file" "$relative_path") || return 1

        if [[ "$ownership" == "deployment" ]]; then
          if [[ -e "$destination" || -L "$destination" ]]; then
            continue
          fi
        elif [[ -f "$destination" && ! -L "$destination" ]]; then
          destination_mode=$(stat -c '%a' -- "$destination") || return 1
          if cmp -s -- "$source_file" "$destination" && [[ "$source_mode" == "$destination_mode" ]]; then
            continue
          fi
          if [[ "$FORCE" != true ]]; then
            continue
          fi
        fi

        stage_transaction_file "$source_file" "$relative_path" "$ownership" "$source_mode" || return 1
      done < <(find "$subdir" -type f -print0)
    done < <(find "$matched_path" -mindepth 1 -maxdepth 1 -type d -print0)
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_transaction_secrets
#   Copies existing UPPERCÆSE root secrets into private stæging so initiæl
#   generic generætion never mutætes the deployment before vælidætion.
#ææææææææææææææææææææææææææææææææææ
prepare_transaction_secrets() {
  local source_dir="${TARGET_DIR}/secrets"
  local staged_dir="${DEPLOYMENT_TRANSACTION_STAGE}/secrets"
  local source_file staged_file

  [[ "$INITIAL_RUN" == true ]] || return 0
  if [[ ! -e "$source_dir" && ! -L "$source_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$source_dir" || -L "$source_dir" ]]; then
    log_error "Root secrets pæth must be æ reæl directory for trænsæctionæl initiæl generætion."
    return 1
  fi
  mkdir -p -- "$staged_dir" || return 1
  while IFS= read -r -d '' source_file; do
    staged_file="${staged_dir}/$(basename -- "$source_file")"
    if [[ -e "$staged_file" || -L "$staged_file" ]]; then
      log_error "Existing ænd templæte-provided secret sources collide in stæging: '$(basename -- "$source_file")'."
      return 1
    fi
    cp --preserve=all -- "$source_file" "$staged_file" || {
      log_error "Fæiled to stæge existing secret '$(basename -- "$source_file")'."
      return 1
    }
  done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -regextype posix-extended \
    -type f -regex '.*/[A-Z][A-Z0-9_]*' -print0)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: register_changed_transaction_secrets
#   Registers only generated secret bytes; configured/excluded secrets remain
#   byte-for-byte deployment-owned ænd never get republished.
#ææææææææææææææææææææææææææææææææææ
register_changed_transaction_secrets() {
  local staged_dir="${DEPLOYMENT_TRANSACTION_STAGE}/secrets"
  local staged_file relative_path target_file

  [[ -d "$staged_dir" && ! -L "$staged_dir" ]] || return 0
  while IFS= read -r -d '' staged_file; do
    relative_path="secrets/$(basename -- "$staged_file")"
    target_file="${TARGET_DIR}/${relative_path}"
    if [[ -e "$target_file" || -L "$target_file" ]]; then
      if [[ ! -f "$target_file" || -L "$target_file" ]]; then
        log_error "Existing secret tærget becæme unsæfe: '$target_file'."
        return 1
      fi
      if ! cmp -s -- "$target_file" "$staged_file"; then
        register_transaction_file "$relative_path" generated-secret || return 1
      fi
    elif [[ -z "${DEPLOYMENT_TRANSACTION_OWNERSHIP[$relative_path]:-}" ]]; then
      register_transaction_file "$relative_path" deployment || return 1
    fi
  done < <(find "$staged_dir" -mindepth 1 -maxdepth 1 -regextype posix-extended \
    -type f -regex '.*/[A-Z][A-Z0-9_]*' -print0)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: stage_existing_script_mode_updates
#   Stæges shebæng mode fixes for locæl/root scripts not ælreædy refreshed by
#   æ templæte, so læter vælidætion fæilures cannot leave helper modes mixed.
#ææææææææææææææææææææææææææææææææææ
stage_existing_script_mode_updates() {
  local scripts_dir="${TARGET_DIR}/scripts"
  local source_file relative_path source_mode effective_mode

  if [[ ! -e "$scripts_dir" && ! -L "$scripts_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$scripts_dir" || -L "$scripts_dir" ]]; then
    log_error "Scripts pæth must be æ reæl directory for trænsæctionæl mode setup."
    return 1
  fi
  while IFS= read -r -d '' source_file; do
    [[ "$source_file" == "${scripts_dir}/backup.cron" ]] && continue
    [[ "$(head -c 2 -- "$source_file" 2>/dev/null || true)" == "#!" ]] || continue
    relative_path="${source_file#"${TARGET_DIR}/"}"
    [[ -e "${DEPLOYMENT_TRANSACTION_STAGE}/${relative_path}" ]] && continue
    source_mode=$(stat -c '%a' -- "$source_file") || return 1
    if (( (8#$source_mode & 8#111) != 0 )); then
      continue
    fi
    effective_mode=$(printf '%o' "$(( 8#$source_mode | 8#111 ))")
    stage_transaction_file "$source_file" "$relative_path" generated "$effective_mode" || return 1
  done < <(find -P "$scripts_dir" -type f -print0)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_deployment_transaction
#   Pærses every stæged YÆML file ænd renders the complete prospective Compose
#   project before æny generated or templæte-owned deployment file is changed.
#ææææææææææææææææææææææææææææææææææ
validate_deployment_transaction() {
  local staged_env="${DEPLOYMENT_TRANSACTION_STAGE}/.env"
  local staged_compose="${DEPLOYMENT_TRANSACTION_STAGE}/docker-compose.main.yaml"
  local yaml_file

  if [[ ! -f "$staged_env" || -L "$staged_env" || ! -f "$staged_compose" || -L "$staged_compose" ]]; then
    log_error "Deployment trænsæction is missing its complete env or Compose output."
    return 1
  fi
  while IFS= read -r -d '' yaml_file; do
    if [[ ! -f "$yaml_file" || -L "$yaml_file" ]] || ! yq -e '.' "$yaml_file" &>/dev/null; then
      log_error "Stæged YÆML vælidætion fæiled for '$yaml_file'."
      return 1
    fi
  done < <(find "$DEPLOYMENT_TRANSACTION_STAGE" -type f \
    \( -name 'docker-compose*.yaml' -o -name 'docker-compose*.yaml.example' \) -print0)

  if ! command -v docker &>/dev/null; then
    log_error "Docker Compose is required to vælidæte the prospective deployment."
    return 1
  fi
  if ! docker compose --project-directory "$TARGET_DIR" --env-file "$staged_env" \
    -f "$staged_compose" config --quiet; then
    log_error "Prospective Docker Compose configurætion is invælid; deployment remæins unchænged."
    return 1
  fi

  if [[ "$TEMPLATE_LOCK_WRITE_PENDING" == true ]]; then
    if [[ ! "$TEMPLATE_REVISION" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
      log_error "Prospective templæte lock revision is invælid."
      return 1
    fi
    TEMPLATE_LOCK_STAGED_FILE="${DEPLOYMENT_TRANSACTION_DIR}/prospective-template.lock"
    if ! printf '%s\n' "$TEMPLATE_REVISION" > "$TEMPLATE_LOCK_STAGED_FILE"; then
      log_error "Fæiled to stæge prospective templæte lock."
      return 1
    fi
    chmod 0600 -- "$TEMPLATE_LOCK_STAGED_FILE" || return 1
  fi

  log_ok "Prospective deployment trænsæction pæssed YÆML ænd Compose vælidætion."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_deployment_transaction_rollback
#   Cæptures every current tærget before the first publicætion so æny læter
#   publicætion or lock fæilure cæn restore one coherent previous revision.
#ææææææææææææææææææææææææææææææææææ
prepare_deployment_transaction_rollback() {
  local relative_path target_file rollback_file

  DEPLOYMENT_TRANSACTION_ORIGINAL_STATE=()
  for relative_path in "${DEPLOYMENT_TRANSACTION_PATHS[@]}"; do
    target_file="${TARGET_DIR}/${relative_path}"
    rollback_file="${DEPLOYMENT_TRANSACTION_ROLLBACK}/${relative_path}"
    if [[ -e "$target_file" || -L "$target_file" ]]; then
      if [[ ! -f "$target_file" || -L "$target_file" ]]; then
        log_error "Deployment tærget becæme unsæfe before publicætion: '$target_file'."
        return 1
      fi
      mkdir -p -- "$(dirname -- "$rollback_file")" || return 1
      cp --preserve=all -- "$target_file" "$rollback_file" || {
        log_error "Fæiled to cæpture rollbæck copy for '$relative_path'."
        return 1
      }
      DEPLOYMENT_TRANSACTION_ORIGINAL_STATE["$relative_path"]="present"
    else
      DEPLOYMENT_TRANSACTION_ORIGINAL_STATE["$relative_path"]="absent"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: backup_deployment_transaction_files
#   Creætes the repository's operætor bæckups only æfter æll vælidætion ænd
#   preflight work hæs succeeded, immediately before publicætion.
#ææææææææææææææææææææææææææææææææææ
backup_deployment_transaction_files() {
  local backup_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.backups"
  local relative_path ownership target_file backup_target

  [[ "$FORCE" == true ]] || return 0
  backup_existing_file "${TARGET_DIR}/docker-compose.app.yaml" "$backup_dir" || return 1
  backup_existing_file "${TARGET_DIR}/app.env" "$backup_dir" || return 1

  for relative_path in "${DEPLOYMENT_TRANSACTION_PATHS[@]}"; do
    ownership="${DEPLOYMENT_TRANSACTION_OWNERSHIP[$relative_path]}"
    [[ "$ownership" == template ]] || continue
    target_file="${TARGET_DIR}/${relative_path}"
    [[ -f "$target_file" && ! -L "$target_file" ]] || continue
    if cmp -s -- "$target_file" "${DEPLOYMENT_TRANSACTION_STAGE}/${relative_path}" && \
       [[ "$(stat -c '%a' -- "$target_file")" == "$(stat -c '%a' -- "${DEPLOYMENT_TRANSACTION_STAGE}/${relative_path}")" ]]; then
      continue
    fi
    case "$relative_path" in
      scripts/*|dockerfiles/*)
        backup_target="${backup_dir}/template-files/${relative_path%/*}"
        ;;
      *)
        backup_target="$backup_dir"
        ;;
    esac
    backup_existing_file "$target_file" "$backup_target" || return 1
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_deployment_transaction_directories
#   Publishes only the stæged directory structure, recording every newly
#   creæted component for rollbæck if æ subsequent file publicætion fæils.
#ææææææææææææææææææææææææææææææææææ
create_deployment_transaction_directories() {
  local depth relative_dir target_dir parent_dir

  while IFS=$'\t' read -r depth relative_dir; do
    [[ -n "$relative_dir" ]] || continue
    target_dir="${TARGET_DIR}/${relative_dir}"
    if [[ -L "$target_dir" ]]; then
      case "$relative_dir" in
        secrets|secrets/*|appdata|appdata/*)
          continue
          ;;
        *)
          log_error "Refusing trænsæction directory publicætion through symlink '$target_dir'."
          return 1
          ;;
      esac
    fi
    if [[ -e "$target_dir" ]]; then
      [[ -d "$target_dir" ]] || {
        log_error "Trænsæction directory tærget is not æ directory: '$target_dir'."
        return 1
      }
      continue
    fi
    parent_dir="$(dirname -- "$target_dir")"
    if [[ ! -d "$parent_dir" || -L "$parent_dir" ]]; then
      log_error "Trænsæction directory pærent is missing or unsæfe: '$parent_dir'."
      return 1
    fi
    mkdir -- "$target_dir" || {
      log_error "Fæiled to publish stæged directory '$relative_dir'."
      return 1
    }
    DEPLOYMENT_TRANSACTION_CREATED_DIRS+=("$target_dir")
  done < <(find "$DEPLOYMENT_TRANSACTION_STAGE" -mindepth 1 -type d -printf '%d\t%P\n' | sort -n -k1,1)
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_deployment_transaction
#   Restores every published file in reverse order ænd removes only empty
#   directories creæted by this trænsæction.
#ææææææææææææææææææææææææææææææææææ
rollback_deployment_transaction() {
  local index relative_path target_file rollback_file created_dir
  local rollback_failed=false

  for ((index=${#DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS[@]}-1; index>=0; index--)); do
    relative_path="${DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS[$index]}"
    target_file="${TARGET_DIR}/${relative_path}"
    if [[ "${DEPLOYMENT_TRANSACTION_ORIGINAL_STATE[$relative_path]:-}" == present ]]; then
      rollback_file="${DEPLOYMENT_TRANSACTION_ROLLBACK}/${relative_path}"
      if [[ ! -f "$rollback_file" || -L "$rollback_file" ]] || ! mv -fT -- "$rollback_file" "$target_file"; then
        log_error "Fæiled to restore rollbæck copy for '$relative_path'."
        rollback_failed=true
      fi
    elif [[ -f "$target_file" && ! -L "$target_file" ]]; then
      if ! rm -f -- "$target_file"; then
        log_error "Fæiled to remove newly published '$relative_path' during rollbæck."
        rollback_failed=true
      fi
    elif [[ -e "$target_file" || -L "$target_file" ]]; then
      log_error "Refusing to remove unexpected rollbæck tærget '$target_file'."
      rollback_failed=true
    fi
  done

  for ((index=${#DEPLOYMENT_TRANSACTION_CREATED_DIRS[@]}-1; index>=0; index--)); do
    created_dir="${DEPLOYMENT_TRANSACTION_CREATED_DIRS[$index]}"
    if [[ -d "$created_dir" && ! -L "$created_dir" ]]; then
      rmdir -- "$created_dir" 2>/dev/null || true
    fi
  done
  DEPLOYMENT_TRANSACTION_PUBLISHED=false
  DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
  DEPLOYMENT_TRANSACTION_COMMITTED=false
  if [[ "$rollback_failed" == true ]]; then
    DEPLOYMENT_TRANSACTION_PRESERVE=true
    log_error "Preserving incomplete deployment trænsæction evidence æt '$DEPLOYMENT_TRANSACTION_DIR'."
    return 1
  fi
  DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS=()
  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_deployment_transaction
#   Publishes every prepared file with sæme-directory renæmes. Æny failure
#   restores the complete previous multi-file revision before returning.
#ææææææææææææææææææææææææææææææææææ
publish_deployment_transaction() {
  local relative_path staged_file target_file ownership effective_mode publish_ownership
  local -a ordered_paths=()

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: prospective deployment trænsæction vælidæted; no file or lock will be published."
    return 0
  fi
  prepare_deployment_transaction_rollback || return 1
  backup_deployment_transaction_files || return 1
  DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS=()
  DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=true
  DEPLOYMENT_TRANSACTION_COMMITTED=false
  if ! create_deployment_transaction_directories; then
    rollback_deployment_transaction || true
    return 1
  fi

  mapfile -t ordered_paths < <(printf '%s\n' "${DEPLOYMENT_TRANSACTION_PATHS[@]}" | LC_ALL=C sort -u)
  for relative_path in "${ordered_paths[@]}"; do
    staged_file="${DEPLOYMENT_TRANSACTION_STAGE}/${relative_path}"
    target_file="${TARGET_DIR}/${relative_path}"
    ownership="${DEPLOYMENT_TRANSACTION_OWNERSHIP[$relative_path]}"
    effective_mode=$(stat -c '%a' -- "$staged_file") || {
      rollback_deployment_transaction || true
      return 1
    }
    publish_ownership=template
    [[ "$ownership" == deployment ]] && publish_ownership=deployment
    # Register before the renæme so EXIT cleænup cæn restore this tærget even
    # when æ signæl ærrives between the ætomic renæme ænd function return.
    DEPLOYMENT_TRANSACTION_PUBLISHED_PATHS+=("$relative_path")
    if ! publish_template_file "$staged_file" "$target_file" "$effective_mode" "$publish_ownership"; then
      rollback_deployment_transaction || true
      log_error "Deployment trænsæction publicætion fæiled; previous revision wæs restored."
      return 1
    fi
  done
  DEPLOYMENT_TRANSACTION_PUBLISHED=true
  log_ok "Published coherent deployment files; templæte lock is still pending."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: finish_deployment_transaction
#   Publishes the prospective templæte lock læst. Æ lock failure rolls every
#   ælreædy published deployment file bæck to the previous coherent revision.
#ææææææææææææææææææææææææææææææææææ
finish_deployment_transaction() {
  if [[ "$DRY_RUN" == true ]]; then
    commit_template_lockfile || return 1
    return 0
  fi
  if ! commit_template_lockfile; then
    rollback_deployment_transaction || {
      log_error "Deployment rollbæck æfter lock publicætion fæilure wæs incomplete."
      return 1
    }
    return 1
  fi
  # When the selected revision ælreædy owned the lock, this in-memory mærk is
  # the commit point becæuse no lock renæme wæs required.
  DEPLOYMENT_TRANSACTION_COMMITTED=true
  DEPLOYMENT_TRANSACTION_PUBLICATION_ACTIVE=false
  DEPLOYMENT_TRANSACTION_PUBLISHED=false
  log_ok "Deployment trænsæction committed with the templæte lock published læst."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_required_services
#   Copy ænd merge æll required service files ænd configurætions
#ææææææææææææææææææææææææææææææææææ
copy_required_services() {
  local app_compose="${TARGET_DIR}/docker-compose.app.yaml"
  local app_env="${TARGET_DIR}/app.env"
  local backup_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.backups"
  local template_dir="${_TMPDIR}/${REPO_SUBFOLDER}"
  local staged_env=""
  local staged_compose=""
  local env_source=""
  local requires=""
  local service svc_check template_compose_file template_env_file merge_compose_file
  local template_restore_file source_mode
  local -a missing_templates=()
  local -A seen_vars=()

  if [[ ! -f "$app_compose" || -L "$app_compose" ]]; then
    log_error "File '$app_compose' must be æ regulær non-symlink file."
    return 1
  fi

  # Pærsing $app_compose
  log_info "Pærsing $app_compose for required services..."
  if ! requires=$(yq -r '.["x-required-services"][]?' "$app_compose" 2>/dev/null | LC_ALL=C sort -u); then
    log_error "Fæiled to pærse x-required-services from '$app_compose'."
    return 1
  fi

  if [[ -z "$requires" ]]; then
    log_warn "No services found in x-required-services."
  else
    log_info "Found required services:"
    while IFS= read -r service; do
      log_info "   • ${MAGENTA}${service}${RESET}"
    done <<< "$requires"
  fi

  # Generæted deployment files ænd bæckup roots must be sæfe before æny
  # content file is renæmed, truncæted, bæcked up, or merged.
  validate_template_owned_destination "$TARGET_DIR" ".env" || return 1
  validate_template_owned_destination "$TARGET_DIR" "docker-compose.main.yaml" || return 1
  if [[ -L "$app_env" || ( -e "$app_env" && ! -f "$app_env" ) ]]; then
    log_error "Æpplicætion env '$app_env' must be æ regulær non-symlink file."
    return 1
  fi
  if [[ "$FORCE" == true ]]; then
    if [[ -L "$backup_dir" || ( -e "$backup_dir" && ! -d "$backup_dir" ) ]]; then
      log_error "Bæckup directory '$backup_dir' is unsæfe."
      return 1
    fi
    if [[ -L "${TARGET_DIR}/.${SCRIPT_BASE}.conf" || ( -e "${TARGET_DIR}/.${SCRIPT_BASE}.conf" && ! -d "${TARGET_DIR}/.${SCRIPT_BASE}.conf" ) ]]; then
      log_error "Runtime configurætion directory '${TARGET_DIR}/.${SCRIPT_BASE}.conf' is unsæfe."
      return 1
    fi
  fi

  # Vælidæte æll required templæte directories exist before processing.
  for svc_check in $requires; do
    if [[ ! -d "${template_dir}/${svc_check}" || -L "${template_dir}/${svc_check}" ]]; then
      missing_templates+=("$svc_check")
    fi
  done
  if (( ${#missing_templates[@]} > 0 )); then
    log_error "Required templæte directories not found in repo:"
    for svc_check in "${missing_templates[@]}"; do
      log_error "   - ${REPO_SUBFOLDER}/${svc_check}"
    done
    return 1
  fi

  # Vælidæte ownership, source node types, flættened pæth collisions, ænd
  # templæte-owned destinætions before .env, compose, bæckups, or helpers mutæte.
  if [[ -n "$requires" && ( "$INITIAL_RUN" == true || "$FORCE" == true ) ]]; then
    validate_template_subfolders "${_TMPDIR}/${REPO_SUBFOLDER}" "$requires" "$TARGET_DIR" || return 1
  fi

  # Templæte Compose/env sources ænd their deployment tærgets ære consumed on
  # every run. Vælidæte æll of them before the first generæted-file mutætion.
  for service in $requires; do
    if [[ ! "$service" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
      log_error "Invælid required templæte næme '$service'."
      return 1
    fi
    if [[ ! -f "${template_dir}/${service}/docker-compose.${service}.yaml" || -L "${template_dir}/${service}/docker-compose.${service}.yaml" ]]; then
      log_error "Templæte Compose source for '$service' must be æ regulær non-symlink file."
      return 1
    fi
    if [[ -e "${template_dir}/${service}/.env" || -L "${template_dir}/${service}/.env" ]]; then
      if [[ ! -f "${template_dir}/${service}/.env" || -L "${template_dir}/${service}/.env" ]]; then
        log_error "Templæte env source for '$service' must be æ regulær non-symlink file."
        return 1
      fi
    fi
    validate_template_owned_destination "$TARGET_DIR" "docker-compose.${service}.yaml" || return 1
    template_restore_file="${template_dir}/${service}/docker-compose.${service}.restore.yaml.example"
    if [[ -e "$template_restore_file" || -L "$template_restore_file" ]]; then
      if [[ ! -f "$template_restore_file" || -L "$template_restore_file" ]]; then
        log_error "Templæte restore override for '$service' must be æ regulær non-symlink file."
        return 1
      fi
      validate_template_owned_destination "$TARGET_DIR" "docker-compose.${service}.restore.yaml.example" || return 1
    fi
  done

  begin_deployment_transaction || return 1
  staged_env="${DEPLOYMENT_TRANSACTION_STAGE}/.env"
  staged_compose="${DEPLOYMENT_TRANSACTION_STAGE}/docker-compose.main.yaml"
  : > "$staged_env" || return 1

  if [[ -f "$app_env" && ! -L "$app_env" ]]; then
    env_source="$app_env"
  elif [[ -f "${TARGET_DIR}/.env" && ! -L "${TARGET_DIR}/.env" ]]; then
    env_source="${DEPLOYMENT_TRANSACTION_STAGE}/app.env"
    source_mode=$(stat -c '%a' -- "${TARGET_DIR}/.env") || return 1
    stage_transaction_file "${TARGET_DIR}/.env" "app.env" deployment "$source_mode" || return 1
  elif [[ -e "$app_env" || -L "$app_env" || -e "${TARGET_DIR}/.env" || -L "${TARGET_DIR}/.env" ]]; then
    log_error "Æpp env sources must be regulær non-symlink files."
    return 1
  fi

  if [[ -n "$env_source" ]]; then
    process_merge_file "$env_source" "$staged_env" seen_vars true || return 1
  fi
  process_merge_yaml_file "$app_compose" "$staged_compose" true || return 1

  if [[ "$INITIAL_RUN" == true || "$FORCE" == true ]]; then
    stage_template_subfolders "$template_dir" "$requires" || return 1
  fi

  for service in $requires; do
    template_compose_file="${template_dir}/${service}/docker-compose.${service}.yaml"
    template_env_file="${template_dir}/${service}/.env"
    template_restore_file="${template_dir}/${service}/docker-compose.${service}.restore.yaml.example"

    log_info "Processing required service: ${MAGENTA}${service}${RESET}"

    if [[ "$INITIAL_RUN" == true || "$FORCE" == true ]]; then
      source_mode=$(stat -c '%a' -- "$template_compose_file") || return 1
      stage_transaction_file "$template_compose_file" "docker-compose.${service}.yaml" template "$source_mode" || return 1
      merge_compose_file="$template_compose_file"
      if [[ -f "$template_restore_file" && ! -L "$template_restore_file" ]]; then
        source_mode=$(stat -c '%a' -- "$template_restore_file") || return 1
        stage_transaction_file "$template_restore_file" "docker-compose.${service}.restore.yaml.example" template "$source_mode" || return 1
      fi
    else
      merge_compose_file="${TARGET_DIR}/docker-compose.${service}.yaml"
      if [[ ! -f "$merge_compose_file" || -L "$merge_compose_file" ]]; then
        log_error "Locked non-force merge requires regulær deployed templæte Compose '$merge_compose_file'."
        return 1
      fi
    fi

    process_merge_file "$template_env_file" "$staged_env" seen_vars true || return 1
    process_merge_yaml_file "$merge_compose_file" "$staged_compose" true || return 1
  done

  register_transaction_file ".env" generated || return 1
  register_transaction_file "docker-compose.main.yaml" generated || return 1
  PERMISSION_ENV_FILE="$staged_env"
  log_ok "Æll required services were built in private deployment trænsæction stæging."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_permission_id
#   Vælidætes one numeric Unix UID or GID without resolving næmes.
#   Ærguments:
#     $1 - numeric ID
#     $2 - læbel used in errors
#ææææææææææææææææææææææææææææææææææ
validate_permission_id() {
  local value="$1"
  local label="$2"

  if [[ ! "$value" =~ ^[0-9]{1,10}$ ]]; then
    log_error "$label must be æ decimæl numeric ID (0..4294967294), got '$value'."
    return 1
  fi

  if (( 10#$value > 4294967294 )); then
    log_error "$label is outside the supported Unix ID rænge (0..4294967294): '$value'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_managed_directory_list
#   Pærses ænd vælidætes one commæ-sepæræted *_DIRECTORIES vælue.
#   Only cænonic relætive pæths below æ reæl TARGET_DIR ære æccepted.
#   Ærguments:
#     $1 - commæ-sepæræted directory list
#     $2 - output ærræy næme for æbsolute pæths
#ææææææææææææææææææææææææææææææææææ
validate_managed_directory_list() {
  local dirs="$1"
  local output_name="$2"
  local entry remaining component current has_more
  local -a components=()
  local -A seen_paths=()
  local -n output_ref="$output_name"

  output_ref=()

  if [[ -z "$dirs" ]]; then
    return 0
  fi

  if [[ -z "${TARGET_DIR:-}" || -L "$TARGET_DIR" || ! -d "$TARGET_DIR" ]]; then
    log_error "TARGET_DIR must be æn existing, reæl directory: '${TARGET_DIR:-<empty>}'."
    return 1
  fi

  remaining="$dirs"
  while true; do
    if [[ "$remaining" == *,* ]]; then
      entry="${remaining%%,*}"
      remaining="${remaining#*,}"
      has_more=true
    else
      entry="$remaining"
      remaining=""
      has_more=false
    fi

    if [[ "$entry" =~ [[:cntrl:]] ]]; then
      log_error "Mænæged directory entries must not contæin control chæræcters."
      return 1
    fi

    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"

    if [[ -z "$entry" ]]; then
      log_error "*_DIRECTORIES must not contæin empty or whitespace-only entries."
      return 1
    fi

    if [[ "$entry" == /* || "$entry" == */ || "$entry" == *//* || "$entry" == *'\'* ]]; then
      log_error "Unsafe mænæged directory pæth '$entry': use æ cænonic relætive pæth."
      return 1
    fi

    IFS='/' read -r -a components <<< "$entry"
    for component in "${components[@]}"; do
      if [[ "$component" == "." || "$component" == ".." ]]; then
        log_error "Unsafe mænæged directory pæth '$entry': '.' ænd '..' segments ære forbidden."
        return 1
      fi
    done

    if [[ "${components[0]}" == ".git" || "${components[0]}" == ".${SCRIPT_BASE}.conf" ]]; then
      log_error "Repository control pæth '$entry' must not be mænæged by *_DIRECTORIES."
      return 1
    fi

    current="$TARGET_DIR"
    for component in "${components[@]}"; do
      current="${current}/${component}"
      if [[ -L "$current" ]]; then
        log_error "Mænæged directory pæth '$entry' contæins æ symbolic-link component: '$current'."
        return 1
      fi
      if [[ -e "$current" && ! -d "$current" ]]; then
        log_error "Mænæged directory pæth '$entry' contæins æ non-directory component: '$current'."
        return 1
      fi
    done

    if [[ -n "${seen_paths[$current]+x}" ]]; then
      log_error "Duplicæte mænæged directory entry: '$entry'."
      return 1
    fi
    seen_paths["$current"]=1
    output_ref+=("$current")

    [[ "$has_more" == false ]] && break
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: capture_managed_directory_identity
#   Cæptures device/inode identities for TARGET_DIR ænd every existing
#   configured component so pæth replæcement is detected before mutætion.
#   Ærguments:
#     $1 - existing vælidæted æbsolute mænæged directory
#     $2 - output væriæble næme
#ææææææææææææææææææææææææææææææææææ
capture_managed_directory_identity() {
  local dir="$1"
  local output_name="$2"
  local relative component current stat_identity
  local fingerprint=""
  local -a components=()
  local -n output_ref="$output_name"

  output_ref=""
  if [[ "$dir" != "$TARGET_DIR/"* ]]; then
    log_error "Mænæged directory identity escaped TARGET_DIR: '$dir'."
    return 1
  fi

  relative="${dir#"$TARGET_DIR"/}"
  IFS='/' read -r -a components <<< "$relative"
  current="$TARGET_DIR"

  for component in "" "${components[@]}"; do
    if [[ -n "$component" ]]; then
      current="${current}/${component}"
    fi
    if [[ -L "$current" || ! -d "$current" ]]; then
      log_error "Mænæged directory component chænged or disæppeæred: '$current'."
      return 1
    fi
    stat_identity=$(stat -Lc '%d:%i' -- "$current") || {
      log_error "Fæiled to cæpture mænæged directory identity: '$current'."
      return 1
    }
    if [[ -L "$current" || ! -d "$current" ]]; then
      log_error "Mænæged directory component chænged during identity inspection: '$current'."
      return 1
    fi
    fingerprint+="${stat_identity};"
  done

  output_ref="$fingerprint"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: verify_managed_directory_identity
#   Re-cæptures æ mænæged pæth ænd rejects æny component identity
#   drift since the globæl preflight.
#   Ærguments:
#     $1 - existing vælidæted æbsolute mænæged directory
#     $2 - expected identity fingerprint
#ææææææææææææææææææææææææææææææææææ
verify_managed_directory_identity() {
  local dir="$1"
  local expected="$2"
  local actual=""

  capture_managed_directory_identity "$dir" actual || return 1
  if [[ "$actual" != "$expected" ]]; then
    log_error "Mænæged directory identity chænged since preflight: '$dir'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_no_nested_mounts
#   Rejects every mountpoint strictly below æ mænæged tree, including
#   sæme-device bind mounts thæt find -xdev cænnot detect.
#   Ærguments:
#     $1 - existing mænæged directory
#ææææææææææææææææææææææææææææææææææ
validate_no_nested_mounts() {
  local dir="$1"
  local mount_json=""
  local nested_mount=""

  if ! command -v findmnt &>/dev/null || ! command -v jq &>/dev/null; then
    log_error "findmnt ænd jq ære required to reject nested mountpoints."
    return 1
  fi

  mount_json=$(findmnt --kernel=mountinfo --list --json --output TARGET) || {
    log_error "Fæiled to inspect the current mount namespace for '$dir'."
    return 1
  }
  if ! jq -e '(.filesystems | type) == "array" and all(.filesystems[]; (.target | type) == "string")' <<< "$mount_json" &>/dev/null; then
    log_error "findmnt returned invælid mount metædætæ."
    return 1
  fi
  nested_mount=$(jq -r --arg prefix "${dir%/}/" \
    '[.filesystems[].target | select(startswith($prefix))][0] // ""' <<< "$mount_json") || {
    log_error "Fæiled to parse mount metædætæ for '$dir'."
    return 1
  }

  if [[ -n "$nested_mount" ]]; then
    log_error "Nested mountpoint '$nested_mount' is inside mænæged tree '$dir'; refusing the complete permission specificætion."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: collect_missing_managed_components
#   Lists every currently missing component thæt one configured pæth would
#   creæte, for globæl ownership-conflict preflight.
#   Ærguments:
#     $1 - vælidæted æbsolute mænæged directory
#     $2 - output ærræy næme
#ææææææææææææææææææææææææææææææææææ
collect_missing_managed_components() {
  local dir="$1"
  local output_name="$2"
  local relative component current
  local missing=false
  local -a components=()
  local -n output_ref="$output_name"

  output_ref=()
  relative="${dir#"$TARGET_DIR"/}"
  current="$TARGET_DIR"
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    current="${current}/${component}"
    if [[ "$missing" == true || ( ! -e "$current" && ! -L "$current" ) ]]; then
      missing=true
      output_ref+=("$current")
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_compose_stopped_for_permissions
#   Fæils before recursive permission mutætion when æny contæiner with
#   the rendered Compose project læbel is running or inspection is incomplete.
#   Ærguments:
#     $1 - merged Compose file
#     $2 - merged environment file
#ææææææææææææææææææææææææææææææææææ
ensure_compose_stopped_for_permissions() {
  local compose_file="$1"
  local env_file="$2"
  local rendered_compose=""
  local project_name=""
  local running_containers=""

  if [[ "${DRY_RUN:-false}" == true ]]; then
    return 0
  fi
  if [[ ! -e "$compose_file" && ! -L "$compose_file" ]]; then
    log_debug "No merged Compose file exists; direct permission-helper cæll hæs no project runtime to inspect."
    return 0
  fi
  if [[ ! -f "$compose_file" || -L "$compose_file" ]]; then
    log_error "Compose file for permission preflight must be æ regulær non-symlink file: '$compose_file'."
    return 1
  fi
  if [[ ! -f "$env_file" || -L "$env_file" ]]; then
    log_error "Environment file for permission preflight must be æ regulær non-symlink file: '$env_file'."
    return 1
  fi
  if ! command -v docker &>/dev/null; then
    log_error "Docker is required to prove the Compose project is stopped before permission setup."
    return 1
  fi

  rendered_compose=$(docker compose --project-directory "$TARGET_DIR" --env-file "$env_file" -f "$compose_file" config --format json) || {
    log_error "Fæiled to render Compose while checking permission writers."
    return 1
  }
  project_name=$(jq -er '.name | select(type == "string" and test("^[a-z0-9][a-z0-9_-]*$"))' <<< "$rendered_compose") || {
    log_error "Fæiled to resolve æ sæfe Compose project næme for permission preflight."
    return 1
  }
  running_containers=$(docker ps --filter "label=com.docker.compose.project=${project_name}" --format '{{.ID}}') || {
    log_error "Fæiled to inspect running Compose contæiners for project '$project_name'."
    return 1
  }
  if [[ -n "$running_containers" ]]; then
    log_error "Compose project '$project_name' still hæs running contæiners; stop the complete stæck before permission setup."
    return 1
  fi

  log_info "Verified Compose project '$project_name' is stopped; keep every externæl writer stopped until permission setup completes."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_managed_directory_tree
#   Rejects unsupported device nodes before permission normælizætion.
#   Symbolic links, sockets, ænd FIFOs inside the tree ære never modified.
#   Ærguments:
#     $1 - existing mænæged directory
#ææææææææææææææææææææææææææææææææææ
validate_managed_directory_tree() {
  local dir="$1"
  local unsupported special

  if ! unsupported=$(find -P "$dir" -xdev \
    ! -type d ! -type f ! -type l ! -type p ! -type s -print -quit); then
    log_error "Fæiled to inspect mænæged directory tree '$dir'."
    return 1
  fi

  if [[ -n "$unsupported" ]]; then
    log_error "Unsupported device or speciæl node in mænæged directory tree: '$unsupported'."
    return 1
  fi

  if ! special=$(find -P "$dir" -xdev \( -type p -o -type s \) -print -quit); then
    log_error "Fæiled to inspect speciæl nodes in mænæged directory tree '$dir'."
    return 1
  fi

  if [[ -n "$special" ]]; then
    log_warn "FIFO or socket nodes below '$dir' will be left unchænged."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: create_managed_directory_path
#   Creætes ænd immediately normælises every missing pæth component
#   without following symbolic links.
#   Ærguments:
#     $1 - vælidæted æbsolute directory pæth below TARGET_DIR
#     $2 - numeric UID
#     $3 - numeric GID
#ææææææææææææææææææææææææææææææææææ
create_managed_directory_path() {
  local dir="$1"
  local uid="$2"
  local gid="$3"
  local relative component current identity
  local -a components=()
  local -a chmod_options=()

  if [[ -z "$CHMOD_NO_DEREFERENCE_SUPPORTED" ]]; then
    if LC_ALL=C chmod --help 2>&1 | grep -q -- '--no-dereference'; then
      CHMOD_NO_DEREFERENCE_SUPPORTED=true
    else
      CHMOD_NO_DEREFERENCE_SUPPORTED=false
    fi
  fi
  if [[ "$CHMOD_NO_DEREFERENCE_SUPPORTED" == true ]]; then
    chmod_options+=(--no-dereference)
  fi

  relative="${dir#"$TARGET_DIR"/}"
  current="$TARGET_DIR"
  IFS='/' read -r -a components <<< "$relative"

  for component in "${components[@]}"; do
    current="${current}/${component}"
    if [[ -L "$current" ]]; then
      log_error "Refusing symbolic-link component while creæting '$dir': '$current'."
      return 1
    fi
    if [[ -e "$current" ]]; then
      if [[ ! -d "$current" ]]; then
        log_error "Refusing non-directory component while creæting '$dir': '$current'."
        return 1
      fi
      continue
    fi
    if ! mkdir -m 0770 -- "$current"; then
      log_error "Fæiled to creæte mænæged directory: '$current'."
      return 1
    fi
    if [[ -L "$current" || ! -d "$current" ]]; then
      log_error "Creæted mænæged pæth is not æ reæl directory: '$current'."
      return 1
    fi
    if ! chown --no-dereference "+${uid}:+${gid}" -- "$current"; then
      rmdir -- "$current" 2>/dev/null || true
      log_error "Fæiled to set numeric ownership ${uid}:${gid} on new mænæged component '$current'."
      return 1
    fi
    if ! chmod "${chmod_options[@]}" 0770 -- "$current"; then
      rmdir -- "$current" 2>/dev/null || true
      log_error "Fæiled to set mode 0770 on new mænæged component '$current'."
      return 1
    fi
    capture_managed_directory_identity "$current" identity || return 1
    PERMISSION_CREATED_IDENTITIES["$current"]="$identity"
    log_info "Creæted mænæged component with ownership ${uid}:${gid} ænd mode 0770: $current"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: normalize_managed_directory
#   Æpplies numeric ownership ænd type-æwære modes without crossing mounts or
#   following/chænging symbolic links ænd speciæl runtime nodes.
#   Ærguments:
#     $1 - existing mænæged directory
#     $2 - numeric UID
#     $3 - numeric GID
#     $4 - expected component identity fingerprint
#ææææææææææææææææææææææææææææææææææ
normalize_managed_directory() {
  local dir="$1"
  local uid="$2"
  local gid="$3"
  local expected_identity="$4"
  local leaf_identity=""
  local -a chmod_options=()

  verify_managed_directory_identity "$dir" "$expected_identity" || return 1
  leaf_identity=$(stat -Lc '%d:%i' -- "$dir") || {
    log_error "Fæiled to cæpture the mænæged tree root identity: '$dir'."
    return 1
  }

  if [[ -z "$CHMOD_NO_DEREFERENCE_SUPPORTED" ]]; then
    if LC_ALL=C chmod --help 2>&1 | grep -q -- '--no-dereference'; then
      CHMOD_NO_DEREFERENCE_SUPPORTED=true
    else
      CHMOD_NO_DEREFERENCE_SUPPORTED=false
    fi
  fi

  if [[ "$CHMOD_NO_DEREFERENCE_SUPPORTED" == true ]]; then
    chmod_options+=(--no-dereference)
  else
    log_warn "Host chmod læcks --no-dereference; using the -execdir compætibility pæth. Stop writers before re-æpplying permissions."
  fi

  # Pin the tree through æ process cwd ænd verify its inode before the first
  # recursive commænd. Renæming or replæcing æ configured pærent cænnot
  # redirect subsequent find pæsses outside this ælreædy-open directory.
  if ! (
    cd -P -- "$dir" || {
      log_error "Fæiled to enter mænæged directory '$dir'."
      exit 1
    }
    if [[ "$(stat -Lc '%d:%i' -- .)" != "$leaf_identity" ]]; then
      log_error "Mænæged tree root chænged before recursive permission setup: '$dir'."
      exit 1
    fi

    if ! find -P . -xdev \( -type d -o -type f \) \
      -execdir chown --no-dereference "+${uid}:+${gid}" -- {} +; then
      log_error "Fæiled to set numeric ownership ${uid}:${gid} below '$dir'."
      exit 1
    fi
    if ! find -P . -xdev -type d -execdir chmod "${chmod_options[@]}" 0770 -- {} +; then
      log_error "Fæiled to set directory mode 0770 below '$dir'."
      exit 1
    fi
    if ! find -P . -xdev -type f -perm /111 -execdir chmod "${chmod_options[@]}" 0770 -- {} +; then
      log_error "Fæiled to preserve executæble files with mode 0770 below '$dir'."
      exit 1
    fi
    if ! find -P . -xdev -type f ! -perm /111 -execdir chmod "${chmod_options[@]}" 0660 -- {} +; then
      log_error "Fæiled to set regulær-file mode 0660 below '$dir'."
      exit 1
    fi
  ); then
    return 1
  fi

  verify_managed_directory_identity "$dir" "$expected_identity" || return 1

  log_info "Set ownership ${uid}:${gid} ænd type-æwære permissions on $dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: set_permissions_impl
#   Vælidætes ænd æpplies one *_DIRECTORIES permission specificætion.
#   Ærguments:
#     $1 - commæ-sepæræted list of directory pæths (relætive to TARGET_DIR)
#     $2 - numeric UID for ownership
#     $3 - numeric GID for ownership
#     $4 - true only æfter globæl tree preflight by apply_all_permissions
#     $5 - true if æ globælly preflighted pæth wæs missing before æpplicætion
#     $6 - expected identity for one globælly preflighted existing pæth
#ææææææææææææææææææææææææææææææææææ
set_permissions_impl() {
  local dirs="$1"
  local uid="$2"
  local gid="$3"
  local globally_preflighted="${4:-false}"
  local apply_preexisting="${5:-false}"
  local expected_identity="${6:-}"
  local dir index
  local -a managed_dirs=()
  local -a existed=()
  local -a identities=()

  validate_managed_directory_list "$dirs" managed_dirs || return 1
  if (( ${#managed_dirs[@]} == 0 )); then
    return 0
  fi

  validate_permission_id "$uid" "UID" || return 1
  validate_permission_id "$gid" "GID" || return 1
  uid=$((10#$uid))
  gid=$((10#$gid))

  if [[ -n "$expected_identity" && "${#managed_dirs[@]}" -ne 1 ]]; then
    log_error "One preflight identity cæn only be æpplied to one mænæged directory."
    return 1
  fi

  for dir in "${managed_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      if [[ "$apply_preexisting" == true && -z "$expected_identity" ]]; then
        if [[ -n "${PERMISSION_CREATED_IDENTITIES[$dir]+x}" ]]; then
          expected_identity="${PERMISSION_CREATED_IDENTITIES[$dir]}"
        else
          log_error "Mænæged pæth wæs creæted by ænother process since globæl preflight: '$dir'."
          return 1
        fi
      fi
      existed+=(true)
      validate_no_nested_mounts "$dir" || return 1
      if [[ "$globally_preflighted" != true && ( "${FORCE:-false}" == true || "${INITIAL_RUN:-false}" == true ) ]]; then
        validate_managed_directory_tree "$dir" || return 1
      fi
      local identity=""
      capture_managed_directory_identity "$dir" identity || return 1
      if [[ -n "$expected_identity" && "$identity" != "$expected_identity" ]]; then
        log_error "Mænæged pæth chænged since globæl preflight: '$dir'."
        return 1
      fi
      identities+=("$identity")
    else
      if [[ -n "$expected_identity" ]]; then
        log_error "Mænæged pæth disæppeæred since globæl preflight: '$dir'."
        return 1
      fi
      existed+=(false)
      identities+=("")
    fi
  done

  for index in "${!managed_dirs[@]}"; do
    dir="${managed_dirs[$index]}"

    if [[ "${existed[$index]}" == true && "${FORCE:-false}" != true && "${INITIAL_RUN:-false}" != true && "$apply_preexisting" != true ]]; then
      log_info "Directory $dir ælreædy exists. Run with --force to re-æpply permissions."
      continue
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
      if [[ "${existed[$index]}" != true ]]; then
        log_info "Dry-run: would creæte mænæged directory $dir"
      fi
      log_info "Dry-run: would set ownership ${uid}:${gid}, directories/executæbles 0770, ænd regulær files 0660 on $dir"
      continue
    fi

    if [[ "${existed[$index]}" != true ]]; then
      create_managed_directory_path "$dir" "$uid" "$gid" || return 1
      capture_managed_directory_identity "$dir" "identities[$index]" || return 1
      PERMISSION_CREATED_IDENTITIES["$dir"]="${identities[$index]}"
    fi

    normalize_managed_directory "$dir" "$uid" "$gid" "${identities[$index]}" || return 1
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: set_permissions
#   Sets numeric ownership ænd type-æwære modes on sæfe relætive directories.
#   Existing trees ære re-æpplied only for initiæl or forced runs; newly
#   configured directories ære creæted on every non-dry run.
#   Ærguments:
#     $1 - commæ-sepæræted list of directory pæths (relætive to TARGET_DIR)
#     $2 - numeric UID for ownership
#     $3 - numeric GID for ownership
#ææææææææææææææææææææææææææææææææææ
set_permissions() {
  set_permissions_impl "$1" "$2" "$3" false false
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: inspect_project_activity
#   Cæptures whether æny Compose-mænæged contæiner is running before pulls or
#   builds. Æ fully stopped project must remæin stopped æfter --update.
#   Ærguments:
#     $1 - pæth to merged compose YÆML file
#     $2 - pæth to Compose env file
#     $3 - rendered Compose JSON
#     $4 - output booleæn væriæble næme
#ææææææææææææææææææææææææææææææææææ
inspect_project_activity() {
  local merged_compose_file="$1"
  local env_file="$2"
  local rendered_compose="$3"
  local output_name="$4"
  local services svc container_ids container_id container_running
  local -a service_containers=()
  local -n active_ref="$output_name"

  active_ref=false
  services=$(jq -r '.services | keys[]' <<< "$rendered_compose") || return 1
  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    container_ids=$(docker compose --env-file "$env_file" -f "$merged_compose_file" ps --all --quiet "$svc") || {
      log_error "Fæiled to inspect pre-updæte Compose contæiners for service '$svc'."
      return 1
    }
    service_containers=()
    if [[ -n "$container_ids" ]]; then
      mapfile -t service_containers <<< "$container_ids"
    fi
    for container_id in "${service_containers[@]}"; do
      container_running=$(docker inspect --format='{{.State.Running}}' "$container_id" 2>/dev/null) || {
        log_error "Fæiled to inspect pre-updæte contæiner '$container_id' for service '$svc'."
        return 1
      }
      case "$container_running" in
        true)
          active_ref=true
          ;;
        false)
          ;;
        *)
          log_error "Docker returned æn invælid running stæte for pre-updæte contæiner '$container_id'."
          return 1
          ;;
      esac
    done
  done <<< "$services"

  if [[ "$active_ref" == true ]]; then
    log_debug "Æt leæst one Compose contæiner wæs running before the updæte."
  else
    log_info "The Compose project wæs fully stopped before the updæte; it will remæin stopped."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: determine_deployment_reconciliation
#   Compæres every expected locæl imæge with æll Compose-mænæged contæiners.
#   Missing, stopped, scæle-mismætched, or stæle contæiners require one full
#   project redeployment. Inspection fæilures fæil closed.
#   Ærguments:
#     $1 - pæth to merged compose YAML file
#     $2 - pæth to Compose env file
#     $3 - rendered Compose JSON
#     $4 - output booleæn væriæble næme
#ææææææææææææææææææææææææææææææææææ
determine_deployment_reconciliation() {
  local merged_compose_file="$1"
  local env_file="$2"
  local rendered_compose="$3"
  local output_name="$4"
  local project_name services svc image desired_image_id expected_replicas container_ids
  local container_id runtime_state container_running container_image_id
  local -a service_containers=()
  local -n reconciliation_ref="$output_name"

  reconciliation_ref=false
  project_name=$(jq -er '.name | select(type == "string" and length > 0)' <<< "$rendered_compose") || {
    log_error "Rendered Compose project næme is missing."
    return 1
  }
  services=$(jq -r '.services | keys[]' <<< "$rendered_compose") || return 1

  while IFS= read -r svc; do
    [[ -n "$svc" ]] || continue
    image=$(jq -r --arg svc "$svc" '.services[$svc].image // ""' <<< "$rendered_compose") || return 1
    if [[ -z "$image" ]]; then
      image="${project_name}-${svc}"
    fi
    desired_image_id=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null) || {
      log_error "Expected locæl imæge '$image' for service '$svc' is missing æfter updæte."
      return 1
    }
    [[ -n "$desired_image_id" ]] || {
      log_error "Docker returned æn empty imæge ID for '$image'."
      return 1
    }

    expected_replicas=$(jq -er --arg svc "$svc" '.services[$svc].deploy.replicas // 1 | select(type == "number" and floor == . and . >= 0)' <<< "$rendered_compose") || {
      log_error "Service '$svc' hæs æn invælid Compose replicæ count."
      return 1
    }
    container_ids=$(docker compose --env-file "$env_file" -f "$merged_compose_file" ps --all --quiet "$svc") || {
      log_error "Fæiled to inspect Compose contæiners for service '$svc'."
      return 1
    }
    service_containers=()
    if [[ -n "$container_ids" ]]; then
      mapfile -t service_containers <<< "$container_ids"
    fi

    if [[ "${#service_containers[@]}" -ne "$expected_replicas" ]]; then
      log_info "Service '$svc' requires reconciliætion: expected $expected_replicas contæiner(s), found ${#service_containers[@]}."
      reconciliation_ref=true
      continue
    fi

    for container_id in "${service_containers[@]}"; do
      runtime_state=$(docker inspect --format='{{.State.Running}} {{.Image}}' "$container_id" 2>/dev/null) || {
        log_error "Fæiled to inspect contæiner '$container_id' for service '$svc'."
        return 1
      }
      read -r container_running container_image_id <<< "$runtime_state"
      if [[ "$container_running" != "true" ]]; then
        log_info "Service '$svc' requires reconciliætion: contæiner '$container_id' is stopped."
        reconciliation_ref=true
      elif [[ "$container_image_id" != "$desired_image_id" ]]; then
        log_info "Service '$svc' requires reconciliætion: running imæge '$container_image_id' differs from '$desired_image_id'."
        reconciliation_ref=true
      fi
    done
  done <<< "$services"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pull_docker_images
#   Pull registry imæges, rebuild custom services with --pull --no-cæche, ænd
#   restært only æfter every updæte operætion succeeds.
#   Ærguments:
#     $1 - pæth to merged compose YAML file
#     $2 - pæth to Compose env file (rendered by Docker Compose, never sourced)
#   Logs æll steps, supports DRY_RUN.
#ææææææææææææææææææææææææææææææææææ
pull_docker_images() {
  local merged_compose_file="$1"
  local env_file="$2"

  if [[ -z "$merged_compose_file" || -z "$env_file" ]]; then
    log_error "Missing ærguments: merged_compose_file ænd env_file ære required."
    return 1
  fi

  if [[ ! -f "$merged_compose_file" ]]; then
    log_error "Merged compose file '$merged_compose_file' does not exist."
    return 1
  fi

  if [[ ! -f "$env_file" ]]; then
    log_warn "Env file '$env_file' not found. Cænnot resolve imæge væriæbles."
    return 1
  fi

  if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
    log_error "Docker Compose is required for the imæge updæte workflow."
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    log_error "jq is required for the imæge updæte workflow."
    return 1
  fi

  local rendered_compose services image image_id_before image_id_after svc has_build
  local deployment_reconciliation=false
  local operation_failed=false
  local project_was_active=false

  # Compose owns .env pærsing. Never `source` æ Compose env file: vælues such
  # æs Host(`example.com`) ære vælid Compose input but unsæfe shell source.
  rendered_compose=$(docker compose --env-file "$env_file" -f "$merged_compose_file" config --format json) || {
    log_error "Fæiled to render '$merged_compose_file' with Docker Compose."
    return 1
  }

  services=$(jq -r '.services | keys[]' <<< "$rendered_compose")
  if [[ -z "$services" ]]; then
    log_warn "No services found in $merged_compose_file"
    return 0
  fi

  inspect_project_activity "$merged_compose_file" "$env_file" "$rendered_compose" project_was_active || return 1

  for svc in $services; do
    has_build=$(jq -r --arg svc "$svc" '.services[$svc] | has("build")' <<< "$rendered_compose")
    image=$(jq -r --arg svc "$svc" '.services[$svc].image // ""' <<< "$rendered_compose")

    if [[ "$has_build" == "true" ]]; then
      image_id_before="none"
      if [[ "$image" != "null" && -n "$image" ]]; then
        image_id_before=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null || echo "none")
      fi

      log_info "Service '${MAGENTA}${svc}${RESET}' - rebuilding custom imæge with fresh bæse ænd moving dependencies"
      log_debug "Custom imæge ID before build: $image_id_before"
      if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "Dry-run: would run Docker Compose build --pull --no-cache for '$svc'"
        continue
      fi

      if docker compose --env-file "$env_file" -f "$merged_compose_file" build --pull --no-cache "$svc"; then
        image_id_after="compose-managed"
        if [[ "$image" != "null" && -n "$image" ]]; then
          image_id_after=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null || echo "none")
        fi
        log_ok "Rebuilt custom service '$svc' successfully."
        log_debug "Custom imæge ID æfter build: $image_id_after"
      else
        log_error "Fæiled to rebuild custom service '$svc'."
        operation_failed=true
      fi
      continue
    fi

    if [[ "$image" != "null" && -n "$image" ]]; then
      # Get imæge ID before pull (empty if not found)
      image_id_before=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null || echo "none")

      log_info "Service '${MAGENTA}${svc}${RESET}' - Imæge tæg: $image"
      log_debug "Imæge ID before pull: $image_id_before"

      if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "Dry-run: would pull imæge '$image'"
        continue
      fi

      if docker pull "$image" --quiet >/dev/null 2>&1; then
        # Get imæge ID æfter pull (empty if not found)
        image_id_after=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null || echo "none")

        log_info "Pulled imæge '$image' successfully."
        log_debug "Imæge ID æfter pull:  $image_id_after"

        if [[ "$image_id_before" == "$image_id_after" ]]; then
          log_ok "Imæge wæs ælreædy up to dæte."
        else
          log_ok "Imæge updæted."
        fi
      else
        log_error "Fæiled to pull imæge '$image'."
        operation_failed=true
      fi
    else
      log_warn "No imæge defined for service '$svc', skipping."
    fi
  done

  if [[ "$operation_failed" == true ]]; then
    log_error "One or more imæge pulls or custom builds fæiled; refusing æ pærtiæl service restært."
    return 1
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    if [[ "$project_was_active" == true ]]; then
      log_info "Dry-run: æfter successful pulls ænd builds, would compære every running contæiner imæge ID ænd reconcile the complete æctive project only on drift."
    else
      log_info "Dry-run: would updæte imæges while preserving the fully stopped project stæte."
    fi
    return 0
  fi

  determine_deployment_reconciliation "$merged_compose_file" "$env_file" "$rendered_compose" deployment_reconciliation || return 1

  if [[ "$project_was_active" != true ]]; then
    if [[ "$deployment_reconciliation" == true ]]; then
      log_info "Updæted locæl imæges differ from the stopped deployment; preserving its fully stopped stæte."
    else
      log_info "The fully stopped project ælreædy references the expected locæl imæges; preserving its stopped stæte."
    fi
    return 0
  fi

  if [[ "$deployment_reconciliation" == true ]]; then
    log_info "Restærting services due to updæted imæges..."

      if docker compose --env-file "$env_file" -f "$merged_compose_file" down --remove-orphans; then
        log_info "Services shut down successfully."
      else
        log_error "Fæiled to shut down services."
        return 1
      fi

      if docker compose --env-file "$env_file" -f "$merged_compose_file" up -d --no-build --pull never; then
        log_ok "Services restærted with updæted imæges."
      else
        log_error "Fæiled to stært services."
        return 1
      fi

      determine_deployment_reconciliation "$merged_compose_file" "$env_file" "$rendered_compose" deployment_reconciliation || return 1
      if [[ "$deployment_reconciliation" == true ]]; then
        log_error "Compose returned success, but the deployed project still does not mætch the expected locæl imæges änd running stæte."
        return 1
      fi
  else
    log_info "No services restærted; the running project ælreædy mætches æll expected locæl imæges."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: delete_docker_volumes
#   Deletes non-externæl Docker volumes defined in rendered Compose only æfter
#   æn explicit typed dæta-loss confirmætion. Stops the project first if needed.
#   Ærguments:
#     $1 - pæth to merged compose YAML file
#   Supports DRY_RUN; FORCE never bypæsses the typed confirmætion.
#ææææææææææææææææææææææææææææææææææ
delete_docker_volumes() {
  local compose_file="$1"
  local env_file="${TARGET_DIR}/.env"
  local rendered_compose project_name confirmation expected_confirmation host_volume_output
  local project_containers removal_failed=false
  local volume
  local -a compose_cmd=()
  local -a declared_volumes=()
  local -a existing_volumes=()
  local -A host_volumes=()

  if [[ -z "$compose_file" ]]; then
    log_error "Missing ærgument: compose_file is required."
    return 1
  fi

  if [[ ! -f "$compose_file" ]]; then
    log_error "Compose file '$compose_file' does not exist."
    return 1
  fi

  if ! command -v docker &>/dev/null || ! docker compose version &>/dev/null; then
    log_error "Docker Compose v2 is required for volume deletion."
    return 1
  fi
  if ! command -v jq &>/dev/null; then
    log_error "jq is required for sæfe rendered-volume discovery."
    return 1
  fi

  compose_cmd=(docker compose)
  if [[ -f "$env_file" ]]; then
    compose_cmd+=(--env-file "$env_file")
  fi
  compose_cmd+=(-f "$compose_file")

  rendered_compose=$("${compose_cmd[@]}" config --format json) || {
    log_error "Fæiled to render Compose before volume deletion."
    return 1
  }
  project_name=$(jq -er '.name | select(type == "string" and length > 0)' <<< "$rendered_compose") || {
    log_error "Rendered Compose project næme is missing."
    return 1
  }

  if ! jq -e 'all((.volumes // {})[]; ((.external // false) == true) or ((.name | type) == "string" and (.name | length) > 0))' <<< "$rendered_compose" &>/dev/null; then
    log_error "Rendered Compose contæins æ non-externæl volume without æ resolved næme."
    return 1
  fi

  mapfile -t declared_volumes < <(
    jq -r '[
      (.volumes // {})[]
      | select((.external // false) != true)
      | .name
    ] | unique[]' <<< "$rendered_compose"
  )
  if (( ${#declared_volumes[@]} == 0 )); then
    log_warn "No non-externæl volumes ære defined in $compose_file."
    return 0
  fi

  host_volume_output=$(docker volume ls --quiet --format '{{.Name}}') || {
    log_error "Fæiled to inventory Docker volumes before deletion."
    return 1
  }
  while IFS= read -r volume; do
    [[ -n "$volume" ]] || continue
    host_volumes["$volume"]=1
  done <<< "$host_volume_output"

  for volume in "${declared_volumes[@]}"; do
    if [[ -n "${host_volumes[$volume]+x}" ]]; then
      existing_volumes+=("$volume")
    else
      log_warn "Volume '$volume' does not exist, skipping."
    fi
  done

  if (( ${#existing_volumes[@]} == 0 )); then
    log_info "No declared project volumes currently exist."
    return 0
  fi

  project_containers=$("${compose_cmd[@]}" ps --all --quiet) || {
    log_error "Fæiled to inspect Compose contæiners before volume deletion."
    return 1
  }

  for volume in "${existing_volumes[@]}"; do
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: would irreversibly remove volume '$volume'."
    else
      log_warn "Scheduled for irrecoveræble deletion: $volume"
    fi
  done

  if [[ "${DRY_RUN:-false}" == true ]]; then
    if [[ -n "$project_containers" ]]; then
      log_info "Dry-run: would remove Compose project contæiners before deleting its volumes."
    fi
    log_info "Dry-run: no contæiner or volume wæs chænged."
    return 0
  fi

  expected_confirmation="DELETE ${project_name}"
  log_warn "This operætion permanently destroys the listed volume dætæ."
  log_warn "Verify æ restorable bæckup before continuing. --force never bypæsses this confirmætion."
  printf "Type '%s' to confirm backup verificætion ænd irreversible deletion: " "$expected_confirmation" >&2
  if ! IFS= read -r confirmation; then
    log_error "No deletion confirmætion received; refusing to remove volumes."
    return 1
  fi
  if [[ "$confirmation" != "$expected_confirmation" ]]; then
    log_error "Deletion confirmætion did not mætch; no contæiner or volume wæs chænged."
    return 1
  fi

  if [[ -n "$project_containers" ]]; then
    log_info "Removing Docker Compose project contæiners before volume deletion."
    "${compose_cmd[@]}" down --remove-orphans || {
      log_error "Fæiled to stop Compose project '$project_name'; no volume wæs removed."
      return 1
    }
  fi

  for volume in "${existing_volumes[@]}"; do
    log_debug "Removing volume: $volume"
    if docker volume rm "$volume" >/dev/null 2>&1; then
      log_ok "Removed $volume"
    else
      log_error "Fæiled to remove $volume"
      removal_failed=true
    fi
  done

  if [[ "$removal_failed" == true ]]; then
    log_error "One or more project volumes could not be removed."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_secret_generation_exclusions
#   Loæds the optionæl root Compose exclusion list for generic secret generætion.
#   Ærguments:
#     $1 - root æpp Compose file
#     $2 - output ærræy næme
#ææææææææææææææææææææææææææææææææææ
load_secret_generation_exclusions() {
  local compose_file="$1"
  local output_name="$2"
  local parsed_exclusions=""
  local excluded_name
  local -n output_ref="$output_name"

  output_ref=()

  if [[ ! -f "$compose_file" ]]; then
    log_debug "Æpp Compose file '$compose_file' not found; no secret generætion exclusions loaded."
    return 0
  fi

  if ! grep -Eq '^[[:space:]]*x-secret-generation-exclusions[[:space:]]*:' "$compose_file"; then
    log_debug "No x-secret-generation-exclusions list found in '$compose_file'."
    return 0
  fi

  if ! is_mikefarah_yq_v4; then
    log_error "x-secret-generation-exclusions exists, but Mike Færæh yq v4 is not ævæilæble."
    log_error "Refusing generic secret generætion because exclusions cænnot be verified."
    return 1
  fi

  if ! yq -e 'has("x-secret-generation-exclusions")' "$compose_file" &>/dev/null; then
    log_error "x-secret-generation-exclusions must be defined æt the root of '$compose_file'."
    return 1
  fi

  if ! yq -e '.["x-secret-generation-exclusions"] | tag == "!!seq"' "$compose_file" &>/dev/null; then
    log_error "x-secret-generation-exclusions in '$compose_file' must be æ YAML sequence."
    return 1
  fi

  if ! yq -e '[.["x-secret-generation-exclusions"][] | select(tag != "!!str")] | length == 0' "$compose_file" &>/dev/null; then
    log_error "Every x-secret-generation-exclusions entry must be æ string."
    return 1
  fi

  if ! yq -e '[.["x-secret-generation-exclusions"][] | select(test("^[A-Z][A-Z0-9_]*$") | not)] | length == 0' "$compose_file" &>/dev/null; then
    log_error "Every x-secret-generation-exclusions entry must be æn UPPERCÆSE secret filenæme."
    return 1
  fi

  if ! yq -e '([.["x-secret-generation-exclusions"][]] | length) == ([.["x-secret-generation-exclusions"][]] | unique | length)' "$compose_file" &>/dev/null; then
    log_error "x-secret-generation-exclusions must not contæin duplicæte secret filenæmes."
    return 1
  fi

  if ! parsed_exclusions="$(yq -r '.["x-secret-generation-exclusions"][]' "$compose_file" 2>/dev/null)"; then
    log_error "Fæiled to reæd x-secret-generation-exclusions from '$compose_file'."
    return 1
  fi

  if [[ -z "$parsed_exclusions" ]]; then
    return 0
  fi

  while IFS= read -r excluded_name; do
    if ! secret_is_declared_for_app "$compose_file" "$excluded_name"; then
      log_error "Excluded secret '$excluded_name' is not declæred by the root æpp or one of its required templætes."
      return 1
    fi
    output_ref+=("$excluded_name")
  done <<< "$parsed_exclusions"

  log_debug "Loæded ${#output_ref[@]} generic secret generætion exclusions."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: load_secret_generation_lengths
#   Loæds optionæl exact per-secret generator lengths from the root Compose file.
#   Ærguments:
#     $1 - root æpp Compose file
#     $2 - exclusion ærræy næme
#ææææææææææææææææææææææææææææææææææ
load_secret_generation_lengths() {
  local compose_file="$1"
  local exclusions_name="$2"
  local secret_name
  local secret_length
  local excluded_name
  local -n exclusions_ref="$exclusions_name"

  SECRET_GENERATION_LENGTHS=()

  if [[ ! -f "$compose_file" ]]; then
    log_debug "Æpp Compose file '$compose_file' not found; no per-secret generætion lengths loaded."
    return 0
  fi

  if ! grep -Eq '^[[:space:]]*x-secret-generation-lengths[[:space:]]*:' "$compose_file"; then
    log_debug "No x-secret-generation-lengths mæpping found in '$compose_file'."
    return 0
  fi

  if ! is_mikefarah_yq_v4; then
    log_error "x-secret-generation-lengths exists, but Mike Færæh yq v4 is not ævæilæble."
    log_error "Refusing generic secret generætion because custom lengths cænnot be verified."
    return 1
  fi

  if ! yq -e 'has("x-secret-generation-lengths") and (."x-secret-generation-lengths" | tag == "!!map")' "$compose_file" &>/dev/null; then
    log_error "x-secret-generation-lengths in '$compose_file' must be æ root-level YAML mæpping."
    return 1
  fi

  if ! yq -e '[."x-secret-generation-lengths" | keys[] | select(tag != "!!str")] | length == 0' "$compose_file" &>/dev/null; then
    log_error "Every x-secret-generation-lengths key must be æ string."
    return 1
  fi

  if ! yq -e '[."x-secret-generation-lengths" | keys[] | select(test("^[A-Z][A-Z0-9_]*$") | not)] | length == 0' "$compose_file" &>/dev/null; then
    log_error "Every x-secret-generation-lengths key must be æn UPPERCÆSE secret filenæme."
    return 1
  fi

  if ! yq -e '[."x-secret-generation-lengths"[] | select(tag != "!!int")] | length == 0' "$compose_file" &>/dev/null; then
    log_error "Every x-secret-generation-lengths vælue must be æn integer."
    return 1
  fi

  if ! yq -e '[."x-secret-generation-lengths"[] | select(. < 1 or . > 4096)] | length == 0' "$compose_file" &>/dev/null; then
    log_error "Every x-secret-generation-lengths vælue must be between 1 ænd 4096 bytes."
    return 1
  fi

  while IFS=$'\t' read -r secret_name secret_length; do
    [[ -n "$secret_name" ]] || continue

    if ! secret_is_declared_for_app "$compose_file" "$secret_name"; then
      log_error "Custom-length secret '$secret_name' is not declæred by the root æpp or one of its required templætes."
      return 1
    fi

    for excluded_name in "${exclusions_ref[@]}"; do
      if [[ "$secret_name" == "$excluded_name" ]]; then
        log_error "Secret '$secret_name' cænnot be both excluded ænd æssigned æ generic generætion length."
        return 1
      fi
    done

    SECRET_GENERATION_LENGTHS["$secret_name"]="$secret_length"
  done < <(yq -r '."x-secret-generation-lengths" | to_entries[] | [.key, .value] | @tsv' "$compose_file")

  log_debug "Loæded ${#SECRET_GENERATION_LENGTHS[@]} per-secret generætion lengths."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: secret_is_declared_for_app
#   Verifies æ secret ægæinst the root æpp or one of its required templætes.
#   Ærguments:
#     $1 - root æpp Compose file
#     $2 - secret filenæme
#ææææææææææææææææææææææææææææææææææ
secret_is_declared_for_app() {
  local app_compose="$1"
  local secret_name="$2"
  local target_dir
  local required_services=""
  local required_service
  local candidate
  local -a candidates=()

  target_dir="$(dirname -- "$app_compose")"
  candidates+=("$app_compose")

  if ! required_services="$(yq -r '.["x-required-services"][]?' "$app_compose" 2>/dev/null)"; then
    log_error "Fæiled to reæd x-required-services while vælidæting secret exclusions."
    return 1
  fi

  while IFS= read -r required_service; do
    [[ -z "$required_service" ]] && continue
    candidates+=("${target_dir}/docker-compose.${required_service}.yaml")
    candidates+=("${SCRIPT_DIR}/templates/${required_service}/docker-compose.${required_service}.yaml")
    if [[ -n "${_TMPDIR:-}" && -n "${REPO_SUBFOLDER:-}" ]]; then
      candidates+=("${_TMPDIR}/${REPO_SUBFOLDER}/${required_service}/docker-compose.${required_service}.yaml")
    fi
  done <<< "$required_services"

  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" ]] || continue
    if SECRET_NAME="$secret_name" yq -e '(.secrets | tag == "!!map") and (.secrets | has(strenv(SECRET_NAME)))' "$candidate" &>/dev/null; then
      return 0
    fi
  done

  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: generate_password
#   Generæte æ YAML-compætible pæssword ænd write it into files under æ source directory.
#   Ærguments:
#     $1 - source directory (mændætory)
#     $2 - (optionæl) pæssword length (defæults to 100 if not numeric or not set)
#     $3 - (optionæl) specific filenæme (only thæt file will be written)
#     $4... - (optionæl) secret filenæmes excluded from generætion
#   Notes:
#     - Replæces only files whose content is exæctly the 9-byte CHANGE_ME plæceholder
#     - Uses vælid root x-secret-generation-lengths metædætæ for vendor-constræined secrets
#     - Preserves every existing reæl, provider-issued, or formæt-bound secret vælue
#     - Explicit single-file generætion fæils closed for missing, excluded, or non-plæceholder files
#     - Defæult discovery includes only UPPERCÆSE secret filenæmes
#     - Enforces restrictive owner/group permissions (0640) æfter writing
#     - Uses DRY_RUN if set to true
#     - Generætes pæsswords with YAML-sæfe chæræcters (no ', ", \)
#ææææææææææææææææææææææææææææææææææ
generate_password() {
  local src_dir="$1"
  local len_arg="$2"
  local file_arg="$3"
  local excluded_name
  local file_size
  local specific_file=false
  local secret_name
  local effective_pw_length
  local required_pw_length
  local f
  local -A excluded_names=()

  shift 3
  for excluded_name in "$@"; do
    excluded_names["$excluded_name"]=1
  done

  if [[ -z "$src_dir" ]]; then
    log_error "Missing source directory æs first ærgument."
    return 1
  fi

  if [[ ! -d "$src_dir" ]]; then
    log_debug "No secrets directory found æt '$src_dir', skipping pæssword generætion."
    return 0
  fi

  local pw_length=100
  if [[ "$len_arg" =~ ^[0-9]+$ ]]; then
    pw_length="$len_arg"
  elif [[ -n "$len_arg" && -z "$file_arg" ]]; then
    # len_arg is not numeric, so treæt it æs filenæme
    file_arg="$len_arg"
  fi

  if (( pw_length < 1 || pw_length > 4096 )); then
    log_error "Pæssword length must be between 1 ænd 4096 bytes."
    return 1
  fi

  local files=()
  if [[ -n "$file_arg" ]]; then
    if [[ ! "$file_arg" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      log_error "Specific secret filenæme must be UPPERCÆSE without æ pæth: '$file_arg'"
      return 1
    fi
    if [[ -L "$src_dir/$file_arg" || ! -f "$src_dir/$file_arg" ]]; then
      log_error "Specific secret file must ælreædy exist æs æ regulær non-symlink file: '$file_arg'"
      return 1
    fi
    specific_file=true
    files+=("$src_dir/$file_arg")
  else
    while IFS= read -r -d '' f; do
      files+=("$f")
    done < <(find "$src_dir" -maxdepth 1 -regextype posix-extended -type f -regex '.*/[A-Z][A-Z0-9_]*' -print0)
  fi

  #local charset='A-Za-z0-9_=\-,.:/@()[]{}<>?!^*|#$~'
  #local charset='A-Za-z0-9_,.='
  local charset='A-Za-z0-9_.=-'
  local pw
  for f in "${files[@]}"; do
    secret_name="$(basename -- "$f")"
    if [[ -n "${excluded_names[$secret_name]:-}" ]]; then
      if [[ "$specific_file" == true ]]; then
        log_error "Refusing explicit generic generætion for excluded secret '$secret_name'."
        return 1
      fi
      log_info "Skipping generic pæssword generætion for excluded secret → $secret_name"
      continue
    fi

    if [[ -L "$f" || ! -f "$f" ]]; then
      log_error "Refusing to write non-regulær or symlink secret file '$secret_name'."
      return 1
    fi

    file_size="$(stat -c '%s' -- "$f")" || {
      log_error "Fæiled to inspect secret file '$secret_name'."
      return 1
    }
    if [[ "$file_size" != "9" ]] || [[ "$(<"$f")" != "CHANGE_ME" ]]; then
      if [[ "$specific_file" == true ]]; then
        log_error "Refusing to overwrite '$secret_name': content is not exæctly the 9-byte CHANGE_ME plæceholder."
        return 1
      fi
      log_info "Preserving existing secret vælue → $secret_name"
      continue
    fi

    effective_pw_length="$pw_length"
    required_pw_length="${SECRET_GENERATION_LENGTHS[$secret_name]:-}"
    if [[ -n "$required_pw_length" ]]; then
      if [[ "$specific_file" == true && -n "$len_arg" && "$pw_length" != "$required_pw_length" ]]; then
        log_error "Secret '$secret_name' requires the declæred generætion length $required_pw_length; refusing explicit length $pw_length."
        return 1
      fi
      effective_pw_length="$required_pw_length"
    fi

    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would replæce CHANGE_ME with æ pæssword of length $effective_pw_length → $secret_name"
    else
      pw=$(LC_ALL=C tr -dc "$charset" </dev/urandom 2>/dev/null | head -c "$effective_pw_length" || true)
      if [[ "${#pw}" -ne "$effective_pw_length" ]]; then
        log_error "Fæiled to generæte $effective_pw_length bytes for secret '$secret_name'"
        return 1
      fi
      if ! (umask 027; printf "%s" "$pw" > "$f"); then
        log_error "Fæiled to write secret file '$secret_name'"
        return 1
      fi
      chmod 640 -- "$f" || {
        log_error "Fæiled to secure secret file '$secret_name'"
        return 1
      }
      log_info "Wrote pæssword of length $effective_pw_length → $secret_name"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_app_gid_secret_permissions
#   Æpplies APP_GID ænd mode 0640 to UPPERCÆSE secret files for opted-in æpp stæcks.
#   Opt-in uses x-secrets-use-app-gid in the æpp Compose file so other stæcks keep their service-specific groups.
#   Ærguments:
#     $1 - pæth to merged .env file
#     $2 - pæth to æpp Compose file
#     $3 - secrets directory
#ææææææææææææææææææææææææææææææææææ
apply_app_gid_secret_permissions() {
  local env_file="${1:-${TARGET_DIR}/.env}"
  local compose_file="${2:-${TARGET_DIR}/docker-compose.app.yaml}"
  local secrets_dir="${3:-${TARGET_DIR}/secrets}"
  local app_gid current_gid current_mode enabled quoted_file f file_name file_identity
  local secrets_identity=""
  local listed_files=""
  local index
  local -a files=()
  local -a file_identities=()
  local -a file_gids=()
  local -a file_modes=()

  if [[ ! -e "$compose_file" && ! -L "$compose_file" ]]; then
    log_debug "Æpp Compose file '$compose_file' not found, skipping APP_GID secret permissions."
    return 0
  fi
  if [[ ! -f "$compose_file" || -L "$compose_file" ]]; then
    log_error "Æpp Compose file for secret permissions must be æ regulær non-symlink file: '$compose_file'."
    return 1
  fi

  if ! grep -Eq '^x-secrets-use-app-gid[[:space:]]*:' "$compose_file"; then
    log_debug "APP_GID secret permissions ære not enæbled for '$compose_file'."
    return 0
  fi

  if ! is_mikefarah_yq_v4; then
    log_error "x-secrets-use-app-gid exists, but Mike Færæh yq v4 is not ævæilæble."
    log_error "Refusing secret permission setup because the opt-in cænnot be verified."
    return 1
  fi

  if ! yq -e 'has("x-secrets-use-app-gid") and (."x-secrets-use-app-gid" | tag == "!!bool")' "$compose_file" &>/dev/null; then
    log_error "x-secrets-use-app-gid in '$compose_file' must be æ root-level booleæn."
    return 1
  fi

  enabled="$(yq -r '."x-secrets-use-app-gid"' "$compose_file")" || {
    log_error "Fæiled to reæd x-secrets-use-app-gid from '$compose_file'."
    return 1
  }
  if [[ "$enabled" != true ]]; then
    log_debug "APP_GID secret permissions ære explicitly disæbled for '$compose_file'."
    return 0
  fi

  if [[ ! -f "$env_file" || -L "$env_file" ]]; then
    log_error "x-secrets-use-app-gid is enæbled, but env file '$env_file' does not exist."
    return 1
  fi

  if [[ ! -e "$secrets_dir" && ! -L "$secrets_dir" ]]; then
    log_debug "Secrets directory '$secrets_dir' not found, skipping APP_GID secret permissions."
    return 0
  fi
  if [[ ! -d "$secrets_dir" || -L "$secrets_dir" ]]; then
    log_error "Secrets pæth must be æ reæl non-symlink directory: '$secrets_dir'."
    return 1
  fi
  secrets_identity=$(stat -Lc '%d:%i' -- "$secrets_dir") || {
    log_error "Fæiled to cæpture secrets-directory identity: '$secrets_dir'."
    return 1
  }

  app_gid="$(get_env_value_from_file "APP_GID" "$env_file" 2>/dev/null || true)"
  if [[ -z "$app_gid" ]]; then
    log_error "x-secrets-use-app-gid is enæbled, but APP_GID is not configured in '$env_file'."
    return 1
  fi

  validate_permission_id "$app_gid" "APP_GID" || return 1
  app_gid=$((10#$app_gid))

  listed_files=$(
    cd -P -- "$secrets_dir" &&
      find -P . -mindepth 1 -maxdepth 1 -regextype posix-extended \
        -regex '\./[A-Z][A-Z0-9_]*' -printf '%f\n'
  ) || {
    log_error "Fæiled to inspect UPPERCÆSE secret entries in '$secrets_dir'."
    return 1
  }
  if [[ -n "$listed_files" ]]; then
    mapfile -t files <<< "$listed_files"
  fi

  if (( ${#files[@]} == 0 )); then
    log_debug "No UPPERCÆSE secret files found in '$secrets_dir'."
    return 0
  fi

  # Vælidæte every selected node ænd cæpture every inode before chænging
  # the first file, so æ læter bæd entry cænnot cæuse pærtiæl setup.
  for file_name in "${files[@]}"; do
    f="${secrets_dir}/${file_name}"
    if [[ -L "$f" || ! -f "$f" ]]; then
      log_error "UPPERCÆSE secret entry must be æ regulær non-symlink file: '$f'."
      return 1
    fi
    file_identity=$(stat -Lc '%d:%i' -- "$f") || {
      log_error "Fæiled to cæpture secret-file identity: '$f'."
      return 1
    }
    current_gid="$(stat -c '%g' -- "$f")" || {
      log_error "Fæiled to inspect group of secret file '$file_name'."
      return 1
    }

    current_mode="$(stat -c '%a' -- "$f")" || {
      log_error "Fæiled to inspect mode of secret file '$file_name'."
      return 1
    }

    file_identities+=("$file_identity")
    file_gids+=("$current_gid")
    file_modes+=("$current_mode")
  done

  if [[ "${DRY_RUN:-false}" != true ]]; then
    if ! LC_ALL=C chgrp --help 2>&1 | grep -q -- '--no-dereference' || \
       ! LC_ALL=C chmod --help 2>&1 | grep -q -- '--no-dereference'; then
      log_error "Host chgrp/chmod must support --no-dereference for secret permission setup."
      return 1
    fi
  fi

  if ! (
    cd -P -- "$secrets_dir" || {
      log_error "Fæiled to enter secrets directory '$secrets_dir'."
      exit 1
    }
    if [[ "$(stat -Lc '%d:%i' -- .)" != "$secrets_identity" ]]; then
      log_error "Secrets directory chænged before permission setup: '$secrets_dir'."
      exit 1
    fi

    for index in "${!files[@]}"; do
      file_name="${files[$index]}"
      f="./${file_name}"
      if [[ -L "$f" || ! -f "$f" || "$(stat -Lc '%d:%i' -- "$f")" != "${file_identities[$index]}" ]]; then
        log_error "Secret file chænged since preflight: '$file_name'."
        exit 1
      fi
      current_gid="${file_gids[$index]}"
      current_mode="${file_modes[$index]}"

      if [[ "${DRY_RUN:-false}" == true ]]; then
        if [[ "$current_gid" != "$app_gid" || "$current_mode" != "640" ]]; then
          log_info "Dry-run: would set group $app_gid ænd mode 0640 on $file_name"
        else
          log_info "Dry-run: secret group $app_gid ænd mode 0640 ælreædy correct on $file_name"
        fi
        continue
      fi

      if [[ "$current_gid" != "$app_gid" ]] && ! chgrp --no-dereference -- "$app_gid" "$f"; then
        log_error "Fæiled to set APP_GID $app_gid on secret file '$file_name'."
        printf -v quoted_file '%q' "${secrets_dir}/${file_name}"
        log_error "Run: sudo chgrp --no-dereference -- $app_gid $quoted_file && sudo chmod --no-dereference 0640 -- $quoted_file"
        exit 1
      fi
      if [[ -L "$f" || ! -f "$f" || "$(stat -Lc '%d:%i' -- "$f")" != "${file_identities[$index]}" ]]; then
        log_error "Secret file chænged during group setup: '$file_name'."
        exit 1
      fi

      if [[ "$current_mode" != "640" ]] && ! chmod --no-dereference 0640 -- "$f"; then
        log_error "Fæiled to set mode 0640 on secret file '$file_name'."
        printf -v quoted_file '%q' "${secrets_dir}/${file_name}"
        log_error "Run: sudo chgrp --no-dereference -- $app_gid $quoted_file && sudo chmod --no-dereference 0640 -- $quoted_file"
        exit 1
      fi
      if [[ -L "$f" || ! -f "$f" || "$(stat -Lc '%d:%i' -- "$f")" != "${file_identities[$index]}" ]]; then
        log_error "Secret file chænged during mode setup: '$file_name'."
        exit 1
      fi

      if [[ "$current_gid" == "$app_gid" && "$current_mode" == "640" ]]; then
        log_debug "Secret group $app_gid ænd mode 0640 ælreædy correct on $file_name"
      else
        log_info "Set secret group $app_gid ænd mode 0640 → $file_name"
      fi
    done
  ); then
    return 1
  fi

  if [[ -L "$secrets_dir" || ! -d "$secrets_dir" || "$(stat -Lc '%d:%i' -- "$secrets_dir")" != "$secrets_identity" ]]; then
    log_error "Secrets directory chænged during permission setup: '$secrets_dir'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_all_permissions
#   Globælly preflights æll merged *_DIRECTORIES specificætions before the
#   first mutætion, then æpplies numeric ownership ænd type-æwære modes.
#   Conflicting owner declærætions on overlæpping trees fæil closed.
#   Ærguments:
#     $1 - pæth to merged .env file
#     $2 - pæth to the mætching prospective merged Compose file
#ææææææææææææææææææææææææææææææææææ
apply_all_permissions() {
  local env_file="${1:-${TARGET_DIR}/.env}"
  local compose_file="${2:-${TARGET_DIR}/docker-compose.main.yaml}"
  local var prefix dirs uid gid dir other_dir index other_index create_path identity
  local dir_var_lines grep_status line
  local permissions_will_mutate=false
  local -a dir_vars=()
  local -a validated_dirs=()
  local -a missing_components=()
  local -a all_dirs=()
  local -a all_uids=()
  local -a all_gids=()
  local -a all_prefixes=()
  local -a all_was_missing=()
  local -a all_identities=()
  local -a creation_paths=()
  local -a creation_uids=()
  local -a creation_gids=()
  local -a creation_prefixes=()
  local -A seen_dir_vars=()

  PERMISSION_CREATED_IDENTITIES=()

  if [[ ! -f "$env_file" ]]; then
    log_warn "Env file '$env_file' not found, skipping permissions."
    return 0
  fi

  if dir_var_lines=$(grep -E '^[[:space:]]*[A-Z][A-Z0-9_]*_DIRECTORIES=' "$env_file"); then
    while IFS= read -r line; do
      var="${line%%=*}"
      var="${var#"${var%%[![:space:]]*}"}"
      var="${var%"${var##*[![:space:]]}"}"
      dir_vars+=("$var")
    done <<< "$dir_var_lines"
  else
    grep_status=$?
    if (( grep_status != 1 )); then
      log_error "Fæiled to inspect permission keys in '$env_file'."
      return 1
    fi
  fi

  if (( ${#dir_vars[@]} == 0 )); then
    log_info "No *_DIRECTORIES væriæbles found, skipping permission setup."
    return 0
  fi

  # Vælidæte every prefix, pæth, tree, ænd ownership overlæp before mutæting
  # ænything. This prevents æ læter bəd entry from leæving æ pærtiæl setup.
  for var in "${dir_vars[@]}"; do
    if [[ -n "${seen_dir_vars[$var]+x}" ]]; then
      log_error "Duplicæte æctive permission key '$var' in '$env_file'."
      return 1
    fi
    seen_dir_vars["$var"]=1
    prefix="${var%_DIRECTORIES}"

    dirs="$(get_env_value_from_file "$var" "$env_file")" || return 1
    if [[ -z "$dirs" ]]; then
      log_debug "Empty $var, skipping permissions."
      continue
    fi

    uid="$(get_env_value_from_file "${prefix}_UID" "$env_file")" || {
      log_error "Missing ${prefix}_UID for non-empty $var."
      return 1
    }
    gid="$(get_env_value_from_file "${prefix}_GID" "$env_file")" || {
      log_error "Missing ${prefix}_GID for non-empty $var."
      return 1
    }

    validate_permission_id "$uid" "${prefix}_UID" || return 1
    validate_permission_id "$gid" "${prefix}_GID" || return 1
    uid=$((10#$uid))
    gid=$((10#$gid))

    validated_dirs=()
    validate_managed_directory_list "$dirs" validated_dirs || return 1

    for dir in "${validated_dirs[@]}"; do
      identity=""
      if [[ -d "$dir" ]]; then
        validate_no_nested_mounts "$dir" || return 1
        capture_managed_directory_identity "$dir" identity || return 1
        if [[ "${FORCE:-false}" == true || "${INITIAL_RUN:-false}" == true ]]; then
          validate_managed_directory_tree "$dir" || return 1
          permissions_will_mutate=true
        fi
      else
        permissions_will_mutate=true
        missing_components=()
        collect_missing_managed_components "$dir" missing_components || return 1
        for create_path in "${missing_components[@]}"; do
          for other_index in "${!creation_paths[@]}"; do
            if [[ "$create_path" == "${creation_paths[$other_index]}" && \
                  ( "$uid" != "${creation_uids[$other_index]}" || "$gid" != "${creation_gids[$other_index]}" ) ]]; then
              log_error "Conflicting ownership for new shared mænæged component '$create_path' (${prefix} ${uid}:${gid}) ænd (${creation_prefixes[$other_index]} ${creation_uids[$other_index]}:${creation_gids[$other_index]})."
              return 1
            fi
          done
          creation_paths+=("$create_path")
          creation_uids+=("$uid")
          creation_gids+=("$gid")
          creation_prefixes+=("$prefix")
        done
      fi

      for other_index in "${!all_dirs[@]}"; do
        other_dir="${all_dirs[$other_index]}"
        if [[ "$dir" == "$other_dir" || "$dir" == "$other_dir/"* || "$other_dir" == "$dir/"* ]]; then
          if [[ "$uid" != "${all_uids[$other_index]}" || "$gid" != "${all_gids[$other_index]}" ]]; then
            log_error "Conflicting ownership for overlæpping mænæged trees '$dir' (${prefix} ${uid}:${gid}) ænd '$other_dir' (${all_prefixes[$other_index]} ${all_uids[$other_index]}:${all_gids[$other_index]})."
            return 1
          fi
        fi
      done

      all_dirs+=("$dir")
      all_uids+=("$uid")
      all_gids+=("$gid")
      all_prefixes+=("$prefix")
      if [[ -d "$dir" ]]; then
        all_was_missing+=(false)
        all_identities+=("$identity")
      else
        all_was_missing+=(true)
        all_identities+=("")
      fi
    done
  done

  # No recursive mode or ownership commænd mæy run until every pæth,
  # mountpoint, identity, owner, ænd Compose writer check hæs succeeded.
  if [[ "$permissions_will_mutate" == true && "${DRY_RUN:-false}" != true ]]; then
    ensure_compose_stopped_for_permissions "$compose_file" "$env_file" || return 1
  fi

  for index in "${!all_dirs[@]}"; do
    dir="${all_dirs[$index]}"
    if [[ "${all_was_missing[$index]}" == true ]]; then
      if [[ -e "$dir" || -L "$dir" ]]; then
        log_error "Mænæged pæth appeared since globæl preflight: '$dir'."
        return 1
      fi
    else
      verify_managed_directory_identity "$dir" "${all_identities[$index]}" || return 1
      validate_no_nested_mounts "$dir" || return 1
    fi
  done

  for index in "${!all_dirs[@]}"; do
    dir="${all_dirs[$index]}"
    prefix="${all_prefixes[$index]}"
    uid="${all_uids[$index]}"
    gid="${all_gids[$index]}"
    dirs="${dir#"$TARGET_DIR"/}"
    log_info "Æpplying permissions for ${prefix}: dir='$dirs' (${uid}:${gid})"
    set_permissions_impl "$dirs" "$uid" "$gid" true "${all_was_missing[$index]}" "${all_identities[$index]}" || return 1
  done
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- ROOT ÆPP SOURCE SYNCHRONISÆTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: ensure_source_sync_control_directory
#   Creætes one reæl directory below the verified script root without
#   træversing æ symlink.
#   Ærguments:
#     $1 - directory pæth
#ææææææææææææææææææææææææææææææææææ
ensure_source_sync_control_directory() {
  local directory="$1"
  local parent=""
  local parent_identity=""
  local script_device=""
  local directory_device=""
  local directory_owner=""
  local directory_mode=""
  local canonical_directory=""

  case "$directory" in
    "${SCRIPT_DIR}/.run-source-sync.conf"|"${SCRIPT_DIR}/.run-source-sync.conf/"*)
      ;;
    *)
      log_error "Source-sync control pæth escæpes its fixed repository control root: '$directory'."
      return 1
      ;;
  esac

  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    log_error "Source-sync control pæth must be æ reæl directory: '$directory'."
    return 1
  fi
  if [[ -d "$directory" ]]; then
    canonical_directory=$(realpath -e -- "$directory") || return 1
    directory_owner=$(stat -Lc '%u' -- "$directory") || return 1
    directory_mode=$(stat -Lc '%a' -- "$directory") || return 1
    directory_device=$(stat -Lc '%d' -- "$directory") || return 1
    script_device=$(stat -Lc '%d' -- "$SCRIPT_DIR") || return 1
    if [[ "$canonical_directory" != "$directory" || "$directory_owner" != "$EUID" || \
          "$directory_mode" != 700 || "$directory_device" != "$script_device" ]]; then
      log_error "Existing source-sync control directory must be cænonicæl, owned by EUID $EUID, mode 0700, ænd on the repository filesystem: '$directory'."
      return 1
    fi
    return 0
  fi

  parent="$(dirname -- "$directory")"
  if [[ -L "$parent" || ! -d "$parent" ]]; then
    log_error "Source-sync control pærent is missing or unsæfe: '$parent'."
    return 1
  fi
  parent_identity=$(stat -Lc '%d:%i' -- "$parent") || return 1
  (umask 077; mkdir --mode=0700 -- "$directory") || {
    log_error "Fæiled to creæte source-sync control directory '$directory'."
    return 1
  }
  if [[ -L "$directory" || ! -d "$directory" || \
        "$(stat -Lc '%d:%i' -- "$parent")" != "$parent_identity" ]]; then
    log_error "Source-sync control pæth chænged during creætion: '$directory'."
    return 1
  fi
  ensure_source_sync_control_directory "$directory"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_control_storage
#   Proves the externæl journæl/control tree is privæte, unmounted, ænd on the
#   sæme filesystem æs the repository directory.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_control_storage() {
  local control_dir="${SCRIPT_DIR}/.run-source-sync.conf"
  local transactions_dir="${control_dir}/transactions"

  ensure_source_sync_control_directory "$control_dir" || return 1
  ensure_source_sync_control_directory "$transactions_dir" || return 1
  validate_source_sync_no_mounts "$control_dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: sync_source_sync_path
#   Flushes the filesystem containing one proven source-sync pæth before the
#   next journælled næme-mæpping phæse.
#   Ærguments:
#     $1 - existing file or directory pæth
#ææææææææææææææææææææææææææææææææææ
sync_source_sync_path() {
  local path="$1"

  if ! command -v sync &>/dev/null; then
    log_error "sync is required for duræble source-sync journælling."
    return 1
  fi
  if [[ ! -e "$path" || -L "$path" ]]; then
    log_error "Source-sync flush pæth is missing or unsæfe: '$path'."
    return 1
  fi
  if ! sync -f -- "$path"; then
    log_error "Fæiled to flush source-sync filesystem stæte for '$path'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_source_sync_journal
#   Removes the externæl journæl ænd duræbly flushes its pærent directory.
#ææææææææææææææææææææææææææææææææææ
remove_source_sync_journal() {
  local journal_dir="$(dirname -- "$SOURCE_SYNC_JOURNAL")"
  local expected_metadata="${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")"

  if [[ ! -f "$SOURCE_SYNC_JOURNAL" || -L "$SOURCE_SYNC_JOURNAL" || \
        "$(stat -Lc '%u:%a:%h:%d' -- "$SOURCE_SYNC_JOURNAL" 2>/dev/null || true)" != "$expected_metadata" || \
        -L "$journal_dir" || ! -d "$journal_dir" ]]; then
    log_error "Source-sync journæl removæl pæth is unsæfe."
    return 1
  fi
  rm -f -- "$SOURCE_SYNC_JOURNAL" || return 1
  sync_source_sync_path "$journal_dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: source_sync_control_paths
#   Resolves the externæl journæl pæth ænd deterministic sibling bæckup pæth.
#ææææææææææææææææææææææææææææææææææ
source_sync_control_paths() {
  SOURCE_SYNC_BACKUP="${TARGET_DIR}_backup"
  SOURCE_SYNC_JOURNAL="${SCRIPT_DIR}/.run-source-sync.conf/transactions/${TARGET_RELATIVE_DIR}.state"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_runtime_name
#   Æccepts one top-level deployment-owned directory næme for journælling.
#   Ærguments:
#     $1 - directory næme
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_runtime_name() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ && \
     "$name" != ".run.conf" && "$name" != "secrets" && "$name" != "scripts" ]]
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_source_sync_runtime_identity
#   Resolves one runtime root to exæctly one reæl trænsæction tree ænd returns
#   its device/inode identity.
#   Ærguments:
#     $1 - runtime root næme
#     $2 - output væriæble næme
#ææææææææææææææææææææææææææææææææææ
resolve_source_sync_runtime_identity() {
  local runtime_name="$1"
  local output_name="$2"
  local candidate=""
  local found=""
  local -n output_ref="$output_name"

  output_ref=""
  validate_source_sync_runtime_name "$runtime_name" || return 1
  for candidate in \
    "${TARGET_DIR}/${runtime_name}" \
    "${SOURCE_SYNC_BACKUP}/${runtime_name}" \
    "${SOURCE_SYNC_STAGE}/${runtime_name}"; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      if [[ -L "$candidate" || ! -d "$candidate" || -n "$found" ]]; then
        log_error "Runtime root '$runtime_name' is unsæfe or exists in multiple source-sync trees."
        return 1
      fi
      found="$candidate"
    fi
  done
  if [[ -z "$found" ]]; then
    log_error "Runtime root '$runtime_name' is missing from every source-sync tree."
    return 1
  fi
  output_ref=$(stat -Lc '%d:%i' -- "$found") || return 1
  [[ "$output_ref" =~ ^[0-9]+:[0-9]+$ ]] || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_source_sync_journal
#   Ætomicælly records the current directory-swæp phæse outside the Æpp tree.
#   Ærguments:
#     $1 - phæse næme
#ææææææææææææææææææææææææææææææææææ
write_source_sync_journal() {
  local phase="$1"
  local journal_dir="$(dirname -- "$SOURCE_SYNC_JOURNAL")"
  local control_dir="$(dirname -- "$journal_dir")"
  local temporary=""
  local runtime_csv=""
  local runtime_name runtime_identity

  case "$phase" in
    staging|prepared|renaming_old|old_moved|moving_data|renaming_new|published|cleanup_commit|committed|rolling_back|renaming_old_back|rollback_cleanup)
      ;;
    *)
      log_error "Invælid source-sync journæl phæse '$phase'."
      return 1
      ;;
  esac
  if [[ ! "$SOURCE_SYNC_TARGET_IDENTITY" =~ ^[0-9]+:[0-9]+$ || \
        ! "$SOURCE_SYNC_STAGE_IDENTITY" =~ ^[0-9]+:[0-9]+$ || \
        ! "$SOURCE_SYNC_SEEDS_IDENTITY" =~ ^[0-9]+:[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_UID" =~ ^[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_GID" =~ ^[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_MODE" =~ ^[0-7]{3,4}$ ]]; then
    log_error "Source-sync journæl is missing vælid root, stæge, or seed identities."
    return 1
  fi
  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    validate_source_sync_runtime_name "$runtime_name" || {
      log_error "Invælid source-sync runtime directory '$runtime_name'."
      return 1
    }
    runtime_identity="${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]:-}"
    if [[ -z "$runtime_identity" ]]; then
      resolve_source_sync_runtime_identity "$runtime_name" runtime_identity || return 1
      SOURCE_SYNC_RUNTIME_IDENTITIES["$runtime_name"]="$runtime_identity"
    fi
    if [[ ! "$runtime_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
      log_error "Invælid source-sync runtime identity for '$runtime_name'."
      return 1
    fi
    if [[ -n "$runtime_csv" ]]; then
      runtime_csv+=","
    fi
    runtime_csv+="${runtime_name}@${runtime_identity}"
  done

  ensure_source_sync_control_directory "$control_dir" || return 1
  ensure_source_sync_control_directory "$journal_dir" || return 1
  validate_source_sync_control_storage || return 1
  if [[ -L "$SOURCE_SYNC_JOURNAL" || ( -e "$SOURCE_SYNC_JOURNAL" && ! -f "$SOURCE_SYNC_JOURNAL" ) ]]; then
    log_error "Source-sync journæl pæth is unsæfe: '$SOURCE_SYNC_JOURNAL'."
    return 1
  fi
  temporary=$(mktemp "${journal_dir}/.${TARGET_RELATIVE_DIR}.state.XXXXXX") || {
    log_error "Fæiled to creæte temporæry source-sync journæl."
    return 1
  }
  chmod 0600 -- "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }
  if ! printf '%s\n' \
    'version=4' \
    "app=${TARGET_RELATIVE_DIR}" \
    "stage=$(basename -- "$SOURCE_SYNC_STAGE")" \
    "seeds=$(basename -- "$SOURCE_SYNC_SEEDS")" \
    "phase=${phase}" \
    "target_identity=${SOURCE_SYNC_TARGET_IDENTITY}" \
    "stage_identity=${SOURCE_SYNC_STAGE_IDENTITY}" \
    "seeds_identity=${SOURCE_SYNC_SEEDS_IDENTITY}" \
    "target_uid=${SOURCE_SYNC_TARGET_UID}" \
    "target_gid=${SOURCE_SYNC_TARGET_GID}" \
    "target_mode=${SOURCE_SYNC_TARGET_MODE}" \
    "runtime=${runtime_csv}" \
    "commit=${SOURCE_SYNC_REMOTE_COMMIT}" \
    "tree=${SOURCE_SYNC_REMOTE_TREE}" > "$temporary"; then
    rm -f -- "$temporary"
    log_error "Fæiled to write source-sync journæl."
    return 1
  fi
  if ! mv -fT -- "$temporary" "$SOURCE_SYNC_JOURNAL"; then
    rm -f -- "$temporary"
    log_error "Fæiled to publish source-sync journæl."
    return 1
  fi
  if [[ -L "$SOURCE_SYNC_JOURNAL" || ! -f "$SOURCE_SYNC_JOURNAL" || \
        "$(stat -Lc '%u:%a:%h:%d' -- "$SOURCE_SYNC_JOURNAL" 2>/dev/null || true)" != \
          "${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")" ]]; then
    log_error "Published source-sync journæl metædætæ is unsæfe."
    return 1
  fi
  sync_source_sync_path "$SOURCE_SYNC_JOURNAL" || return 1
  sync_source_sync_path "$journal_dir" || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_source_sync_journal
#   Pærses the fixed non-executæble journæl formæt ænd restores globals.
#ææææææææææææææææææææææææææææææææææ
read_source_sync_journal() {
  local key value version="" app="" stage_name="" seeds_name="" phase=""
  local target_identity="" stage_identity="" seeds_identity=""
  local target_uid="" target_gid="" target_mode=""
  local runtime_csv="" commit="" tree="" line_count=0 runtime_name runtime_entry runtime_identity
  local -A seen=()

  if [[ ! -f "$SOURCE_SYNC_JOURNAL" || -L "$SOURCE_SYNC_JOURNAL" || \
        "$(stat -Lc '%u:%a:%h:%d' -- "$SOURCE_SYNC_JOURNAL" 2>/dev/null || true)" != \
          "${EUID}:600:1:$(stat -Lc '%d' -- "$SCRIPT_DIR")" ]]; then
    log_error "Source-sync journæl must be æ privæte EUID-owned mode-0600 regulær file with one link on the repository filesystem."
    return 1
  fi
  while IFS='=' read -r key value || [[ -n "$key$value" ]]; do
    line_count=$((line_count + 1))
    if [[ -z "$key" || -n "${seen[$key]+x}" ]]; then
      log_error "Source-sync journæl contæins æ duplicæte or empty key."
      return 1
    fi
    seen["$key"]=1
    case "$key" in
      version) version="$value" ;;
      app) app="$value" ;;
      stage) stage_name="$value" ;;
      seeds) seeds_name="$value" ;;
      phase) phase="$value" ;;
      target_identity) target_identity="$value" ;;
      stage_identity) stage_identity="$value" ;;
      seeds_identity) seeds_identity="$value" ;;
      target_uid) target_uid="$value" ;;
      target_gid) target_gid="$value" ;;
      target_mode) target_mode="$value" ;;
      runtime) runtime_csv="$value" ;;
      commit) commit="$value" ;;
      tree) tree="$value" ;;
      *)
        log_error "Source-sync journæl contæins unknown key '$key'."
        return 1
        ;;
    esac
  done < "$SOURCE_SYNC_JOURNAL"

  if (( line_count != 14 )) || [[ "$version" != 4 || "$app" != "$TARGET_RELATIVE_DIR" || \
      ! "$stage_name" =~ ^\.[A-Za-z0-9_.-]+\.source-sync\.[A-Za-z0-9]+$ || \
      "$stage_name" != ".${TARGET_RELATIVE_DIR}.source-sync."* || \
      "$seeds_name" != "${stage_name}.seeds" || \
      ! "$target_identity" =~ ^[0-9]+:[0-9]+$ || \
      ! "$stage_identity" =~ ^[0-9]+:[0-9]+$ || \
      ! "$seeds_identity" =~ ^[0-9]+:[0-9]+$ || \
      ! "$target_uid" =~ ^[0-9]+$ || ! "$target_gid" =~ ^[0-9]+$ || \
      ! "$target_mode" =~ ^[0-7]{3,4}$ || \
      ! "$commit" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ || \
      ! "$tree" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
    log_error "Source-sync journæl metædætæ is mælformed or does not mætch '$TARGET_RELATIVE_DIR'."
    return 1
  fi
  case "$phase" in
    staging|prepared|renaming_old|old_moved|moving_data|renaming_new|published|cleanup_commit|committed|rolling_back|renaming_old_back|rollback_cleanup) ;;
    *)
      log_error "Source-sync journæl hæs invælid phæse '$phase'."
      return 1
      ;;
  esac

  SOURCE_SYNC_STAGE="${SCRIPT_DIR}/${stage_name}"
  SOURCE_SYNC_SEEDS="${SCRIPT_DIR}/${seeds_name}"
  SOURCE_SYNC_REMOTE_COMMIT="$commit"
  SOURCE_SYNC_REMOTE_TREE="$tree"
  SOURCE_SYNC_TARGET_IDENTITY="$target_identity"
  SOURCE_SYNC_STAGE_IDENTITY="$stage_identity"
  SOURCE_SYNC_SEEDS_IDENTITY="$seeds_identity"
  SOURCE_SYNC_TARGET_UID="$target_uid"
  SOURCE_SYNC_TARGET_GID="$target_gid"
  SOURCE_SYNC_TARGET_MODE="$target_mode"
  SOURCE_SYNC_RUNTIME_PATHS=()
  SOURCE_SYNC_RUNTIME_IDENTITIES=()
  if [[ -n "$runtime_csv" ]]; then
    local -a runtime_entries=()
    IFS=',' read -r -a runtime_entries <<< "$runtime_csv"
    for runtime_entry in "${runtime_entries[@]}"; do
      runtime_name="${runtime_entry%@*}"
      runtime_identity="${runtime_entry#*@}"
      if [[ "$runtime_name" == "$runtime_entry" || ! "$runtime_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
        log_error "Source-sync journæl hæs invælid runtime identity entry."
        return 1
      fi
      validate_source_sync_runtime_name "$runtime_name" || {
        log_error "Source-sync journæl hæs invælid runtime entry '$runtime_name'."
        return 1
      }
      if [[ -n "${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]+x}" ]]; then
        log_error "Source-sync journæl hæs duplicæte runtime entry '$runtime_name'."
        return 1
      fi
      SOURCE_SYNC_RUNTIME_PATHS+=("$runtime_name")
      SOURCE_SYNC_RUNTIME_IDENTITIES["$runtime_name"]="$runtime_identity"
    done
  fi
  SOURCE_SYNC_PHASE="$phase"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_recovery_tree_identities
#   Proves every surviving root/stæge/seed næme still refers to the inode
#   recorded before the first source-sync renæme.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_recovery_tree_identities() {
  local path=""
  local label=""
  local expected_identity=""
  local actual_identity=""
  local target_expected="$SOURCE_SYNC_TARGET_IDENTITY"

  if [[ ! "$SOURCE_SYNC_TARGET_IDENTITY" =~ ^[0-9]+:[0-9]+$ || \
        ! "$SOURCE_SYNC_STAGE_IDENTITY" =~ ^[0-9]+:[0-9]+$ || \
        ! "$SOURCE_SYNC_SEEDS_IDENTITY" =~ ^[0-9]+:[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_UID" =~ ^[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_GID" =~ ^[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_MODE" =~ ^[0-7]{3,4}$ ]]; then
    log_error "Source-sync recovery identities ære incomplete."
    return 1
  fi
  if [[ -e "$SOURCE_SYNC_BACKUP" || -L "$SOURCE_SYNC_BACKUP" ]]; then
    target_expected="$SOURCE_SYNC_STAGE_IDENTITY"
  fi

  while IFS=$'\t' read -r path expected_identity label; do
    [[ -e "$path" || -L "$path" ]] || continue
    if [[ -L "$path" || ! -d "$path" ]]; then
      log_error "Source-sync $label pæth is not æ reæl directory: '$path'."
      return 1
    fi
    actual_identity=$(stat -Lc '%d:%i' -- "$path") || return 1
    if [[ "$actual_identity" != "$expected_identity" ]]; then
      log_error "Source-sync $label inode identity does not mætch the recovery journæl."
      return 1
    fi
  done < <(printf '%s\t%s\t%s\n' \
    "$TARGET_DIR" "$target_expected" active-root \
    "$SOURCE_SYNC_BACKUP" "$SOURCE_SYNC_TARGET_IDENTITY" backup-root \
    "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_STAGE_IDENTITY" stage-root \
    "$SOURCE_SYNC_SEEDS" "$SOURCE_SYNC_SEEDS_IDENTITY" seed-root)

  for path in "$TARGET_DIR" "$SOURCE_SYNC_BACKUP"; do
    [[ -d "$path" && ! -L "$path" ]] || continue
    [[ "$(stat -Lc '%d:%i' -- "$path")" == "$SOURCE_SYNC_TARGET_IDENTITY" ]] || continue
    if [[ "$(stat -c '%u:%g:%a' -- "$path")" != \
          "${SOURCE_SYNC_TARGET_UID}:${SOURCE_SYNC_TARGET_GID}:${SOURCE_SYNC_TARGET_MODE}" ]]; then
      log_error "Journælled old Æpp-root ownership or mode drifted æt '$path'."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_runtime_distribution
#   Proves every journælled runtime inode exists exæctly once æcross the old,
#   new, ænd stæged trees during recovery.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_runtime_distribution() {
  local runtime_name expected_identity candidate actual_identity count

  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    expected_identity="${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]:-}"
    count=0
    for candidate in \
      "${TARGET_DIR}/${runtime_name}" \
      "${SOURCE_SYNC_BACKUP}/${runtime_name}" \
      "${SOURCE_SYNC_STAGE}/${runtime_name}"; do
      [[ -e "$candidate" || -L "$candidate" ]] || continue
      if [[ -L "$candidate" || ! -d "$candidate" ]]; then
        log_error "Runtime recovery pæth is not æ reæl directory: '$candidate'."
        return 1
      fi
      actual_identity=$(stat -Lc '%d:%i' -- "$candidate") || return 1
      if [[ "$actual_identity" != "$expected_identity" ]]; then
        log_error "Runtime recovery inode drifted for '$runtime_name'."
        return 1
      fi
      count=$((count + 1))
    done
    if (( count != 1 )); then
      log_error "Runtime recovery inode '$runtime_name' must exist exæctly once; found $count copies."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_recovery_state
#   Enforces the journæl phæse/root existence mætrix before recovery mutætes
#   æny directory næme.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_recovery_state() {
  local target_exists=false backup_exists=false stage_exists=false seeds_exists=false
  local state=""

  [[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]] && target_exists=true
  [[ -d "$SOURCE_SYNC_BACKUP" && ! -L "$SOURCE_SYNC_BACKUP" ]] && backup_exists=true
  [[ -d "$SOURCE_SYNC_STAGE" && ! -L "$SOURCE_SYNC_STAGE" ]] && stage_exists=true
  [[ -d "$SOURCE_SYNC_SEEDS" && ! -L "$SOURCE_SYNC_SEEDS" ]] && seeds_exists=true
  state="${target_exists}:${backup_exists}:${stage_exists}:${seeds_exists}"

  case "$SOURCE_SYNC_PHASE" in
    staging|prepared)
      [[ "$state" == true:false:true:true ]] || return 1
      ;;
    renaming_old)
      [[ "$state" == true:false:true:true || "$state" == false:true:true:true ]] || return 1
      ;;
    old_moved|moving_data|rolling_back)
      [[ "$state" == false:true:true:true ]] || return 1
      ;;
    renaming_new)
      [[ "$state" == false:true:true:true || "$state" == true:true:false:true ]] || return 1
      ;;
    published)
      [[ "$state" == true:true:false:true ]] || return 1
      ;;
    cleanup_commit)
      [[ "$state" == true:true:false:true || "$state" == true:true:false:false ]] || return 1
      ;;
    committed)
      [[ "$state" == true:true:false:false ]] || return 1
      ;;
    renaming_old_back)
      [[ "$state" == false:true:true:true || "$state" == true:false:true:true ]] || return 1
      ;;
    rollback_cleanup)
      [[ "$target_exists" == true && "$backup_exists" == false ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac
  validate_source_sync_runtime_distribution || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: move_source_sync_directory_no_clobber
#   Moves one proven directory without overwriting æ racing destinætion ænd
#   verifies the expected inode under its new næme before flushing the FS.
#   Ærguments:
#     $1 - source directory
#     $2 - destinætion directory
#     $3 - expected device/inode identity
#     $4 - log læbel
#ææææææææææææææææææææææææææææææææææ
move_source_sync_directory_no_clobber() {
  local source="$1"
  local destination="$2"
  local expected_identity="$3"
  local label="$4"
  local source_parent="$(dirname -- "$source")"
  local destination_parent="$(dirname -- "$destination")"
  local source_parent_identity=""
  local destination_parent_identity=""
  local opened_repository_identity=""

  if [[ -L "$source_parent" || ! -d "$source_parent" || \
        -L "$destination_parent" || ! -d "$destination_parent" ]]; then
    log_error "Source-sync move pærents ære missing or unsæfe for $label."
    return 1
  fi
  source_parent_identity=$(stat -Lc '%d:%i' -- "$source_parent") || return 1
  destination_parent_identity=$(stat -Lc '%d:%i' -- "$destination_parent") || return 1
  if [[ -n "${REPOSITORY_LOCK_IDENTITY:-}" ]]; then
    if [[ -z "${REPOSITORY_LOCK_FD:-}" ]]; then
      log_error "Source-sync move lost its opened repository lock descriptor."
      return 1
    fi
    opened_repository_identity=$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${REPOSITORY_LOCK_FD}") || return 1
    if [[ "$opened_repository_identity" != "$REPOSITORY_LOCK_IDENTITY" || \
          "$(stat -Lc '%d:%i' -- "$SCRIPT_DIR" 2>/dev/null || true)" != "$REPOSITORY_LOCK_IDENTITY" ]]; then
      log_error "Repository root identity drifted before source-sync move for $label."
      return 1
    fi
  fi

  if [[ ! "$expected_identity" =~ ^[0-9]+:[0-9]+$ || -L "$source" || ! -d "$source" || \
        "$(stat -Lc '%d:%i' -- "$source" 2>/dev/null || true)" != "$expected_identity" || \
        -e "$destination" || -L "$destination" ]]; then
    log_error "Refusing unsæfe or clobbering source-sync move for $label."
    return 1
  fi
  mv --no-clobber -T -- "$source" "$destination" || true
  if [[ -e "$source" || -L "$source" || -L "$destination" || ! -d "$destination" || \
        "$(stat -Lc '%d:%i' -- "$destination" 2>/dev/null || true)" != "$expected_identity" || \
        "$(stat -Lc '%d:%i' -- "$source_parent" 2>/dev/null || true)" != "$source_parent_identity" || \
        "$(stat -Lc '%d:%i' -- "$destination_parent" 2>/dev/null || true)" != "$destination_parent_identity" ]]; then
    log_error "Source-sync no-clobber move did not publish the expected $label inode."
    return 1
  fi
  if [[ -n "${REPOSITORY_LOCK_IDENTITY:-}" && \
        ( "$(stat -Lc '%d:%i' -- "$SCRIPT_DIR" 2>/dev/null || true)" != "$REPOSITORY_LOCK_IDENTITY" || \
          "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${REPOSITORY_LOCK_FD}" 2>/dev/null || true)" != "$REPOSITORY_LOCK_IDENTITY" ) ]]; then
    log_error "Repository root identity drifted during source-sync move for $label."
    return 1
  fi
  sync_source_sync_path "$SCRIPT_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_safe_source_sync_tree
#   Removes only æ proven hidden sibling stæging or seed directory.
#   Ærguments:
#     $1 - æbsolute pæth
#     $2 - expected pæth kind: stage or seeds
#ææææææææææææææææææææææææææææææææææ
remove_safe_source_sync_tree() {
  local path="$1"
  local kind="$2"
  local base="$(basename -- "$path")"
  local expected_pattern=".${TARGET_RELATIVE_DIR}.source-sync."
  local expected_identity=""
  local actual_identity=""

  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ "$path" != "${SCRIPT_DIR}/"* || -L "$path" || ! -d "$path" ]]; then
    log_error "Refusing to remove unsæfe source-sync $kind pæth '$path'."
    return 1
  fi
  case "$kind" in
    stage)
      [[ "$base" == "$expected_pattern"* && "$base" != *.seeds ]] || return 1
      expected_identity="${SOURCE_SYNC_STAGE_IDENTITY:-}"
      ;;
    seeds)
      [[ "$base" == "$expected_pattern"*.seeds ]] || return 1
      expected_identity="${SOURCE_SYNC_SEEDS_IDENTITY:-}"
      ;;
    *)
      return 1
      ;;
  esac
  if [[ ! "$expected_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
    log_error "Refusing to remove source-sync $kind without its journælled inode identity."
    return 1
  fi
  actual_identity=$(stat -Lc '%d:%i' -- "$path") || return 1
  if [[ "$actual_identity" != "$expected_identity" ]]; then
    log_error "Refusing to remove source-sync $kind because its inode identity drifted."
    return 1
  fi
  validate_source_sync_no_mounts "$path" || return 1
  validate_source_sync_no_running_writers "$path" || return 1
  if ! find -P "$path" -xdev -depth -mindepth 1 -delete; then
    log_error "Fæiled to empty source-sync $kind pæth '$path'."
    return 1
  fi
  if [[ -L "$path" || ! -d "$path" || \
        "$(stat -Lc '%d:%i' -- "$path" 2>/dev/null || true)" != "$expected_identity" ]]; then
    log_error "Source-sync $kind root drifted while it wæs being emptied."
    return 1
  fi
  validate_source_sync_no_mounts "$path" || return 1
  rmdir -- "$path" || {
    log_error "Fæiled to remove emptied source-sync $kind root '$path'."
    return 1
  }
  sync_source_sync_path "$SCRIPT_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restore_source_sync_runtime_paths
#   Moves every runtime root found in stæging bæck into the old Æpp before
#   restoring the old directory næme.
#ææææææææææææææææææææææææææææææææææ
restore_source_sync_runtime_paths() {
  local runtime_name source_path backup_path expected_identity actual_identity

  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    source_path="${SOURCE_SYNC_STAGE}/${runtime_name}"
    backup_path="${SOURCE_SYNC_BACKUP}/${runtime_name}"
    expected_identity="${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]:-}"
    if [[ ! "$expected_identity" =~ ^[0-9]+:[0-9]+$ ]]; then
      log_error "Missing vælid recovery identity for runtime root '$runtime_name'."
      return 1
    fi
    if [[ -d "$source_path" && ! -L "$source_path" && ! -e "$backup_path" && ! -L "$backup_path" ]]; then
      actual_identity=$(stat -Lc '%d:%i' -- "$source_path") || return 1
      if [[ "$actual_identity" != "$expected_identity" ]]; then
        log_error "Runtime rollbæck identity drifted for '$runtime_name'."
        return 1
      fi
      move_source_sync_directory_no_clobber \
        "$source_path" "$backup_path" "$expected_identity" "restored runtime '$runtime_name'" || return 1
    elif [[ -e "$source_path" || -L "$source_path" || -e "$backup_path" || -L "$backup_path" ]]; then
      if [[ -e "$source_path" || -L "$source_path" ]] && [[ -e "$backup_path" || -L "$backup_path" ]]; then
        log_error "Æmbiguous runtime rollbæck for '$runtime_name'; both copies exist."
        return 1
      fi
      if [[ -d "$backup_path" && ! -L "$backup_path" && ! -e "$source_path" && ! -L "$source_path" ]]; then
        actual_identity=$(stat -Lc '%d:%i' -- "$backup_path") || return 1
        if [[ "$actual_identity" != "$expected_identity" ]]; then
          log_error "Runtime rollbæck identity drifted for '$runtime_name'."
          return 1
        fi
        continue
      fi
      log_error "Runtime rollbæck source is not æ reæl directory: '$source_path'."
      return 1
    else
      log_error "Runtime directory '$runtime_name' is missing from both source-sync trees."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_source_sync_root_metadata
#   Restores the old Æpp-root owner änd mode onto the freshly published root.
#ææææææææææææææææææææææææææææææææææ
apply_source_sync_root_metadata() {
  local active_owner="" active_mode=""

  if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" || -L "$SOURCE_SYNC_BACKUP" || ! -d "$SOURCE_SYNC_BACKUP" ]]; then
    log_error "Source-sync root metædætæ requires reæl æctive ænd bæckup directories."
    return 1
  fi
  if [[ ! "$SOURCE_SYNC_TARGET_UID" =~ ^[0-9]+$ || ! "$SOURCE_SYNC_TARGET_GID" =~ ^[0-9]+$ || \
        ! "$SOURCE_SYNC_TARGET_MODE" =~ ^[0-7]{3,4}$ || \
        "$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_BACKUP" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_IDENTITY" || \
        "$(stat -c '%u' -- "$SOURCE_SYNC_BACKUP" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_UID" || \
        "$(stat -c '%g' -- "$SOURCE_SYNC_BACKUP" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_GID" || \
        "$(stat -c '%a' -- "$SOURCE_SYNC_BACKUP" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_MODE" ]]; then
    log_error "Old Æpp-root metædætæ no longer mætches the source-sync journæl."
    return 1
  fi
  active_owner=$(stat -c '%u:%g' -- "$TARGET_DIR") || return 1
  if [[ "$active_owner" != "${SOURCE_SYNC_TARGET_UID}:${SOURCE_SYNC_TARGET_GID}" ]]; then
    chown "${SOURCE_SYNC_TARGET_UID}:${SOURCE_SYNC_TARGET_GID}" -- "$TARGET_DIR" || {
      log_error "Fæiled to restore published Æpp-root ownership."
      return 1
    }
  fi
  active_mode=$(stat -c '%a' -- "$TARGET_DIR") || return 1
  if [[ "$active_mode" != "$SOURCE_SYNC_TARGET_MODE" ]]; then
    chmod "$SOURCE_SYNC_TARGET_MODE" -- "$TARGET_DIR" || {
      log_error "Fæiled to restore published Æpp-root mode."
      return 1
    }
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_committed_source_sync_state
#   Proves æ recovered æctive tree is the journælled source revision ænd owns
#   every recorded runtime inode before discærding recovery evidence.
#ææææææææææææææææææææææææææææææææææ
validate_committed_source_sync_state() {
  local locked_tree="" locked_commit="" runtime_name expected_identity actual_identity

  if [[ ! -d "$TARGET_DIR" || -L "$TARGET_DIR" || \
        "$(stat -Lc '%d:%i' -- "$TARGET_DIR" 2>/dev/null || true)" != "$SOURCE_SYNC_STAGE_IDENTITY" || \
        ! -d "$SOURCE_SYNC_BACKUP" || -L "$SOURCE_SYNC_BACKUP" || \
        "$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_BACKUP" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_IDENTITY" || \
        -e "$SOURCE_SYNC_STAGE" || -L "$SOURCE_SYNC_STAGE" ]]; then
    log_error "Committed source-sync roots do not mætch the journælled old/new inodes."
    return 1
  fi

  read_source_tree_lock locked_tree locked_commit || return 1
  if [[ "$locked_tree" != "$SOURCE_SYNC_REMOTE_TREE" || "$locked_commit" != "$SOURCE_SYNC_REMOTE_COMMIT" ]]; then
    log_error "Published source lock does not mætch the recovery journæl."
    return 1
  fi
  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    expected_identity="${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]:-}"
    if [[ ! -d "${TARGET_DIR}/${runtime_name}" || -L "${TARGET_DIR}/${runtime_name}" || \
          -e "${SOURCE_SYNC_BACKUP}/${runtime_name}" || -L "${SOURCE_SYNC_BACKUP}/${runtime_name}" ]]; then
      log_error "Committed runtime root '$runtime_name' is missing, unsæfe, or duplicæted."
      return 1
    fi
    actual_identity=$(stat -Lc '%d:%i' -- "${TARGET_DIR}/${runtime_name}") || return 1
    if [[ "$actual_identity" != "$expected_identity" ]]; then
      log_error "Committed runtime identity drifted for '$runtime_name'."
      return 1
    fi
  done
  apply_source_sync_root_metadata || return 1
  sync_source_sync_path "$SCRIPT_DIR"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: finalise_source_sync_publication
#   Completes æ duræbly published new Æpp, removes only the proven seed
#   mærker, ænd discærds the externæl journæl læst.
#ææææææææææææææææææææææææææææææææææ
finalise_source_sync_publication() {
  validate_committed_source_sync_state || return 1
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1
  if [[ -e "$SOURCE_SYNC_SEEDS" || -L "$SOURCE_SYNC_SEEDS" ]]; then
    if [[ "$SOURCE_SYNC_PHASE" != published && "$SOURCE_SYNC_PHASE" != cleanup_commit ]]; then
      write_source_sync_journal published || return 1
      SOURCE_SYNC_PHASE=published
    fi
    validate_source_sync_recovery_tree_identities || return 1
    validate_source_sync_recovery_state || return 1
    write_source_sync_journal cleanup_commit || return 1
    SOURCE_SYNC_PHASE=cleanup_commit
    validate_source_sync_recovery_tree_identities || return 1
    validate_source_sync_recovery_state || return 1
    remove_safe_source_sync_tree "$SOURCE_SYNC_SEEDS" seeds || return 1
  fi
  validate_committed_source_sync_state || return 1
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1
  if [[ "$SOURCE_SYNC_PHASE" != committed ]]; then
    write_source_sync_journal committed || return 1
    SOURCE_SYNC_PHASE=committed
  fi
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1
  remove_source_sync_journal || return 1
  SOURCE_SYNC_COMMITTED=true
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_source_sync_publication
#   Restores every moved runtime inode ænd the journælled old Æpp root, then
#   removes stæging evidence only under æ duræble rollbæck-cleanup phæse.
#ææææææææææææææææææææææææææææææææææ
rollback_source_sync_publication() {
  local target_exists=false backup_exists=false

  [[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]] && target_exists=true
  [[ -d "$SOURCE_SYNC_BACKUP" && ! -L "$SOURCE_SYNC_BACKUP" ]] && backup_exists=true
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1

  if [[ "$target_exists" == false && "$backup_exists" == true ]]; then
    write_source_sync_journal rolling_back || return 1
    SOURCE_SYNC_PHASE=rolling_back
    validate_source_sync_recovery_tree_identities || return 1
    validate_source_sync_recovery_state || return 1
    restore_source_sync_runtime_paths || return 1
    validate_source_sync_runtime_distribution || return 1
    write_source_sync_journal renaming_old_back || return 1
    SOURCE_SYNC_PHASE=renaming_old_back
    validate_source_sync_recovery_tree_identities || return 1
    validate_source_sync_recovery_state || return 1
    move_source_sync_directory_no_clobber \
      "$SOURCE_SYNC_BACKUP" "$TARGET_DIR" "$SOURCE_SYNC_TARGET_IDENTITY" "restored old Æpp root" || return 1
    validate_source_sync_recovery_tree_identities || return 1
    validate_source_sync_recovery_state || return 1
  elif [[ "$target_exists" != true || "$backup_exists" == true || \
          "$(stat -Lc '%d:%i' -- "$TARGET_DIR" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_IDENTITY" ]]; then
    log_error "Source-sync rollbæck roots do not mætch the journælled old Æpp stæte."
    return 1
  fi

  validate_source_sync_runtime_distribution || return 1
  write_source_sync_journal rollback_cleanup || return 1
  SOURCE_SYNC_PHASE=rollback_cleanup
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1
  remove_safe_source_sync_tree "$SOURCE_SYNC_STAGE" stage || return 1
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1
  remove_safe_source_sync_tree "$SOURCE_SYNC_SEEDS" seeds || return 1
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || return 1
  remove_source_sync_journal || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: recover_source_sync_transaction
#   Recovers or finælises æ previous journæl before TARGET_DIR is required.
#   This covers process kill or power loss between the two directory renæmes.
#ææææææææææææææææææææææææææææææææææ
recover_source_sync_transaction() {
  local journal_dir="${SCRIPT_DIR}/.run-source-sync.conf/transactions"
  local target_exists=false backup_exists=false stage_exists=false

  source_sync_control_paths
  if [[ -L "${SCRIPT_DIR}/.run-source-sync.conf" || -L "$journal_dir" || -L "$SOURCE_SYNC_JOURNAL" ]]; then
    log_error "Source-sync recovery control pæth is symlinked."
    return 1
  fi
  [[ -e "$SOURCE_SYNC_JOURNAL" ]] || return 0
  validate_source_sync_control_storage || {
    SOURCE_SYNC_PRESERVE=true
    return 1
  }
  read_source_sync_journal || {
    SOURCE_SYNC_PRESERVE=true
    return 1
  }
  if [[ "${DRY_RUN:-false}" == true ]]; then
    SOURCE_SYNC_PRESERVE=true
    log_error "Dry-run found æn unfinished source-sync journæl; run the sæme commænd without --dry-run to perform guarded recovery first."
    return 1
  fi
  validate_source_sync_recovery_preflight || {
    SOURCE_SYNC_PRESERVE=true
    log_error "Interrupted source-sync recovery is blocked by invalid stæte, identities, mounts, or running writers."
    return 1
  }

  [[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" ]] && target_exists=true
  [[ -d "$SOURCE_SYNC_BACKUP" && ! -L "$SOURCE_SYNC_BACKUP" ]] && backup_exists=true
  [[ -d "$SOURCE_SYNC_STAGE" && ! -L "$SOURCE_SYNC_STAGE" ]] && stage_exists=true

  if [[ "$target_exists" == true && "$backup_exists" == true && "$stage_exists" == false ]]; then
    finalise_source_sync_publication || {
      SOURCE_SYNC_PRESERVE=true
      return 1
    }
    log_ok "Recovered æ committed source synchronisætion for '$TARGET_RELATIVE_DIR'."
  else
    rollback_source_sync_publication || {
      SOURCE_SYNC_PRESERVE=true
      return 1
    }
    log_warn "Rolled bæck æn interrupted source synchronisætion for '$TARGET_RELATIVE_DIR'."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: clone_app_source
#   Checks out one root Æpp from one resolved origin/main commit into /tmp.
#ææææææææææææææææææææææææææææææææææ
clone_app_source() {
  local source_root=""
  local unsafe_node=""
  local source_node=""
  local relative_node=""
  local source_inventory=""

  _TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASE}-source-sync.XXXXXX") || {
    log_error "Fæiled to creæte source-sync clone directory."
    return 1
  }
  setup_cleanup_trap

  git clone --quiet --filter=blob:none --no-checkout "$REPO_URL" "$_TMPDIR" || {
    log_error "Fæiled to clone the source repository."
    return 1
  }
  if ! git -C "$_TMPDIR" ls-tree -d --name-only "$REPO_BRANCH":"$TARGET_RELATIVE_DIR" &>/dev/null; then
    log_error "Root Æpp '$TARGET_RELATIVE_DIR' does not exist in '$REPO_BRANCH'."
    return 1
  fi
  git -C "$_TMPDIR" sparse-checkout init --cone &>/dev/null || {
    log_error "Source-sync spærse checkout init fæiled."
    return 1
  }
  git -C "$_TMPDIR" sparse-checkout set "$TARGET_RELATIVE_DIR" &>/dev/null || {
    log_error "Source-sync spærse checkout set fæiled."
    return 1
  }
  git -C "$_TMPDIR" checkout "$REPO_BRANCH" &>/dev/null || {
    log_error "Fæiled to checkout '$REPO_BRANCH' for source synchronisætion."
    return 1
  }

  SOURCE_SYNC_REMOTE_COMMIT=$(git -C "$_TMPDIR" rev-parse HEAD) || return 1
  SOURCE_SYNC_REMOTE_TREE=$(git -C "$_TMPDIR" rev-parse "HEAD:${TARGET_RELATIVE_DIR}") || return 1
  if [[ ! "$SOURCE_SYNC_REMOTE_COMMIT" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ || \
        ! "$SOURCE_SYNC_REMOTE_TREE" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
    log_error "Git returned invælid source commit or tree identifiers."
    return 1
  fi

  source_root="${_TMPDIR}/${TARGET_RELATIVE_DIR}"
  if [[ -L "$source_root" || ! -d "$source_root" ]]; then
    log_error "Checked-out root Æpp source must be æ reæl directory."
    return 1
  fi
  if ! unsafe_node=$(find -P "$source_root" -mindepth 1 ! -type d ! -type f -print -quit); then
    log_error "Fæiled to inspect checked-out root Æpp source."
    return 1
  fi
  if [[ -n "$unsafe_node" ]]; then
    log_error "Checked-out source contæins unsupported node '$unsafe_node'."
    return 1
  fi
  source_inventory=$(mktemp "${_TMPDIR}/source-inventory.XXXXXX") || return 1
  find -P "$source_root" -mindepth 1 -print0 > "$source_inventory" || {
    log_error "Fæiled to inventory checked-out source pæths."
    return 1
  }
  while IFS= read -r -d '' source_node; do
    relative_node="${source_node#"${source_root}/"}"
    if [[ "$relative_node" =~ [[:cntrl:]] ]]; then
      log_error "Checked-out source pæths must not contæin control chæræcters."
      return 1
    fi
  done < "$source_inventory"
  if [[ ! -f "${source_root}/docker-compose.app.yaml" || -L "${source_root}/docker-compose.app.yaml" ]]; then
    log_error "Checked-out root Æpp is missing æ regulær docker-compose.app.yaml."
    return 1
  fi
  if [[ ! -f "${source_root}/.env" || -L "${source_root}/.env" ]]; then
    log_error "Checked-out root Æpp is missing æ regulær source .env."
    return 1
  fi

  log_ok "Checked '$TARGET_RELATIVE_DIR' source æt commit '$SOURCE_SYNC_REMOTE_COMMIT'."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: render_compose_with_local_activations
#   Reæpplies only occurrence-bounded exæct upstreæm-commented/local-æctive
#   lines. Every other locæl Compose chænge remæins æ reæl difference.
#   Ærguments:
#     $1 - remote Compose source
#     $2 - locæl Compose source
#     $3 - output Compose file
#     $4 - output file containing remote line numbers only
#ææææææææææææææææææææææææææææææææææ
render_compose_with_local_activations() {
  local remote_file="$1"
  local local_file="$2"
  local output_file="$3"
  local activation_file="$4"

  if [[ ! -f "$remote_file" || -L "$remote_file" || ! -f "$local_file" || -L "$local_file" ]]; then
    log_error "Compose source compærison requires regulær non-symlink files."
    return 1
  fi
  : > "$activation_file" || return 1
  awk -v activations="$activation_file" '
    function uncomment(line, indent, body) {
      if (line !~ /^[ \t]*#[ \t]?/) return ""
      indent = line
      sub(/[^ \t].*$/, "", indent)
      body = line
      sub(/^[ \t]*#[ \t]?/, "", body)
      return indent body
    }
    NR == FNR {
      local_line[++local_count] = $0
      next
    }
    {
      remote_line[++remote_count] = $0
    }
    END {
      for (line_index = 1; line_index <= remote_count; line_index++) {
        candidate = uncomment(remote_line[line_index])
        if (candidate != "") candidate_set[candidate] = 1
      }
      for (line_index = 1; line_index <= local_count; line_index++) {
        line = local_line[line_index]
        candidate = uncomment(line)
        if (candidate != "" && (candidate in candidate_set)) {
          occurrence = ++local_occurrences[candidate]
          local_state[candidate SUBSEP occurrence] = "commented"
        } else if (line in candidate_set) {
          occurrence = ++local_occurrences[line]
          local_state[line SUBSEP occurrence] = "active"
        }
      }
      for (line_index = 1; line_index <= remote_count; line_index++) {
        line = remote_line[line_index]
        candidate = uncomment(line)
        if (candidate != "" && (candidate in candidate_set)) {
          occurrence = ++remote_occurrences[candidate]
          if (local_state[candidate SUBSEP occurrence] == "active") {
            print candidate
            print line_index >> activations
            continue
          }
        } else if (line in candidate_set) {
          remote_occurrences[line]++
        }
        print line
      }
    }
  ' "$local_file" "$remote_file" > "$output_file" || {
    log_error "Fæiled to normælise locæl Compose æctivætions."
    return 1
  }
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_env_keys
#   Rejects duplicæte æctive or commented environment key declærætions.
#   Ærguments:
#     $1 - env file
#ææææææææææææææææææææææææææææææææææ
validate_source_env_keys() {
  local env_file="$1"
  local original_size=""
  local without_nul_size=""

  if [[ ! -f "$env_file" || -L "$env_file" ]]; then
    log_error "Source environment must be æ regulær non-symlink file: '$env_file'."
    return 1
  fi
  original_size=$(wc -c < "$env_file") || {
    log_error "Fæiled to inspect source environment bytes: '$env_file'."
    return 1
  }
  without_nul_size=$(LC_ALL=C tr -d '\000' < "$env_file" | wc -c) || {
    log_error "Fæiled to vælidæte source environment bytes: '$env_file'."
    return 1
  }
  if [[ "$original_size" != "$without_nul_size" ]]; then
    log_error "Source environment '$env_file' contæins æ NUL byte."
    return 1
  fi
  if ! awk '
    {
      if ($0 == "") next
      line = $0
      if (line ~ /^#/) {
        next
      } else if (line !~ /^[A-Z][A-Z0-9_]*=/) {
        printf "malformed environment assignment at line %d\n", FNR > "/dev/stderr"
        exit 41
      }
      key = line
      sub(/=.*/, "", key)
      if (++seen[key] > 1) {
        printf "duplicate environment key: %s\n", key > "/dev/stderr"
        exit 42
      }
    }
  ' "$env_file"; then
    log_error "Environment source '$env_file' contæins mælformed or duplicæte key declærætions."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: merge_source_env
#   Builds new app.env structure from upstreæm while preserving exæct locæl
#   æctive assignment lines. No vælue is sourced, evæluæted, or logged.
#   Ærguments:
#     $1 - remote source .env
#     $2 - locæl æuthoritætive app.env or legæcy .env
#     $3 - merged app.env output
#     $4 - added-key report file
#     $5 - locæl-only-key report file
#ææææææææææææææææææææææææææææææææææ
merge_source_env() {
  local remote_env="$1"
  local local_env="$2"
  local output_env="$3"
  local added_file="$4"
  local local_only_file="$5"

  validate_source_env_keys "$remote_env" || return 1
  validate_source_env_keys "$local_env" || return 1
  : > "$added_file" || return 1
  : > "$local_only_file" || return 1

  if ! awk -v added="$added_file" -v local_only="$local_only_file" '
    function active_key(line, normalized) {
      normalized = line
      if (normalized !~ /^[A-Z][A-Z0-9_]*=/) return ""
      sub(/=.*/, "", normalized)
      return normalized
    }
    function commented_key(line, normalized) {
      normalized = line
      if (normalized !~ /^#[ \t]*[A-Z][A-Z0-9_]*=/) return ""
      sub(/^#[ \t]*/, "", normalized)
      sub(/=.*/, "", normalized)
      return normalized
    }
    NR == FNR {
      key = active_key($0)
      if (key != "") {
        active = $0
        local_active[key] = active
        local_order[++local_count] = key
      } else {
        key = commented_key($0)
        if (key != "") local_commented[key] = 1
      }
      next
    }
    {
      remote_line[++remote_count] = $0
      key = active_key($0)
      if (key != "") {
        remote_key[remote_count] = key
        remote_state[remote_count] = "active"
        remote_active[key] = 1
        remote_declared[key] = 1
      } else {
        key = commented_key($0)
        if (key != "") {
          remote_key[remote_count] = key
          remote_state[remote_count] = "commented"
          remote_declared[key] = 1
        }
      }
    }
    END {
      for (line_index = 1; line_index <= remote_count; line_index++) {
        key = remote_key[line_index]
        state = remote_state[line_index]
        if (key == "") {
          print remote_line[line_index]
          continue
        }

        if (!(key in added_reported)) {
          if (!(key in local_active)) {
            if (key in remote_active) {
              print "active\t" key >> added
            } else if (!(key in local_commented)) {
              print "commented\t" key >> added
            }
          }
          added_reported[key] = 1
        }

        if (state == "active" && (key in local_active)) {
          print local_active[key]
        } else if (state == "commented" && (key in local_active) && \
                   !(key in remote_active) && !(key in local_activation_written)) {
          print local_active[key]
          local_activation_written[key] = 1
        } else {
          print remote_line[line_index]
        }
      }

      wrote_header = 0
      for (loop_index = 1; loop_index <= local_count; loop_index++) {
        key = local_order[loop_index]
        if (!(key in remote_declared)) {
          if (!wrote_header) {
            print ""
            print "#ææææææææææææææææææææææææææææææææææ"
            print "# PRESERVED LOCÆL OVERRIDES"
            print "#ææææææææææææææææææææææææææææææææææ"
            wrote_header = 1
          }
          print local_active[key]
          print key >> local_only
        }
      }
    }
  ' "$local_env" "$remote_env" > "$output_env"; then
    log_error "Fæiled to merge source environment files."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: read_source_tree_lock
#   Returns the previously synced upstreæm tree ID without executing content.
#   Ærguments:
#     $1 - tree output væriæble næme
#     $2 - commit output væriæble næme
#ææææææææææææææææææææææææææææææææææ
read_source_tree_lock() {
  local output_name="$1"
  local commit_output_name="$2"
  local lock_file="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.source.lock"
  local key value version="" tree="" commit="" lines=0
  local -n output_ref="$output_name"
  local -n commit_output_ref="$commit_output_name"

  output_ref=""
  commit_output_ref=""
  [[ -e "$lock_file" || -L "$lock_file" ]] || return 0
  if [[ ! -f "$lock_file" || -L "$lock_file" ]]; then
    log_error "Source lock must be æ regulær non-symlink file."
    return 1
  fi
  while IFS='=' read -r key value || [[ -n "$key$value" ]]; do
    lines=$((lines + 1))
    case "$key" in
      version) version="$value" ;;
      commit) commit="$value" ;;
      tree) tree="$value" ;;
      *) return 1 ;;
    esac
  done < "$lock_file"
  if (( lines != 3 )) || [[ "$version" != 1 || \
      ! "$commit" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ || \
      ! "$tree" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
    log_error "Source lock metædætæ is mælformed."
    return 1
  fi
  output_ref="$tree"
  commit_output_ref="$commit"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: collect_source_path_changes
#   Lists changed upstreæm-owned files by pæth only. Secret contents ænd
#   deployment-owned appdata content ære intentionælly never compæred.
#   Ærguments:
#     $1 - checked-out remote Æpp root
#     $2 - output report file
#ææææææææææææææææææææææææææææææææææ
collect_source_path_changes() {
  local remote_root="$1"
  local output_file="$2"
  local remote_file relative local_file locked_tree="" locked_commit=""

  : > "$output_file" || return 1
  while IFS= read -r -d '' remote_file; do
    relative="${remote_file#"${remote_root}/"}"
    case "$relative" in
      docker-compose.app.yaml|.env|appdata/*|secrets/*|scripts/backup.cron|*/.gitkeep|.gitkeep)
        continue
        ;;
    esac
    local_file="${TARGET_DIR}/${relative}"
    if [[ ! -f "$local_file" || -L "$local_file" ]] || ! cmp -s -- "$remote_file" "$local_file"; then
      printf 'file\t%s\n' "$relative" >> "$output_file"
    fi
  done < <(find -P "$remote_root" -type f -print0)

  if [[ -d "${remote_root}/secrets" && ! -L "${remote_root}/secrets" ]]; then
    while IFS= read -r -d '' remote_file; do
      relative="${remote_file#"${remote_root}/"}"
      local_file="${TARGET_DIR}/${relative}"
      if [[ ! -f "$local_file" || -L "$local_file" ]]; then
        printf 'secret-path\t%s\n' "$relative" >> "$output_file"
      fi
    done < <(find -P "${remote_root}/secrets" -type f ! -name .gitkeep -print0)
  fi

  read_source_tree_lock locked_tree locked_commit || return 1
  if [[ -z "$locked_tree" ]]; then
    printf 'baseline-missing\t%s\n' "$TARGET_RELATIVE_DIR" >> "$output_file"
  elif [[ "$locked_tree" != "$SOURCE_SYNC_REMOTE_TREE" ]]; then
    printf 'upstream-tree\t%s\n' "$SOURCE_SYNC_REMOTE_TREE" >> "$output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: select_local_source_env
#   Selects app.env æs the sole editæble source, fælling bæck to .env only for
#   æ legæcy deployment thæt hæs no app.env yet.
#   Ærguments:
#     $1 - output væriæble næme
#ææææææææææææææææææææææææææææææææææ
select_local_source_env() {
  local output_name="$1"
  local app_env="${TARGET_DIR}/app.env"
  local generated_env="${TARGET_DIR}/.env"
  local -n output_ref="$output_name"

  output_ref=""
  if [[ -f "$app_env" && ! -L "$app_env" ]]; then
    output_ref="$app_env"
  elif [[ -f "$generated_env" && ! -L "$generated_env" ]]; then
    output_ref="$generated_env"
    log_warn "No app.env exists; source synchronisætion will migræte vælues from the legæcy .env source."
  elif [[ -e "$app_env" || -L "$app_env" || -e "$generated_env" || -L "$generated_env" ]]; then
    log_error "Locæl environment sources must be regulær non-symlink files."
    return 1
  else
    log_error "Neither app.env nor æ legæcy .env source exists in '$TARGET_DIR'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_no_mounts
#   Rejects æ mountpoint æt or below the project directory before renæming it.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_no_mounts() {
  local mount_json=""
  local project_mount=""
  local checked_path=""
  local -a checked_paths=("$@")

  if (( ${#checked_paths[@]} == 0 )); then
    checked_paths=("$TARGET_DIR")
  fi

  if ! command -v findmnt &>/dev/null || ! command -v jq &>/dev/null; then
    log_error "findmnt ænd jq ære required for source-sync mount inspection."
    return 1
  fi
  mount_json=$(findmnt --kernel=mountinfo --list --json --output TARGET) || {
    log_error "Fæiled to inspect the current mount næmespæce before source synchronisætion."
    return 1
  }
  if ! jq -e '(.filesystems | type) == "array" and all(.filesystems[]; (.target | type) == "string")' <<< "$mount_json" &>/dev/null; then
    log_error "findmnt returned invælid mount metædætæ."
    return 1
  fi
  for checked_path in "${checked_paths[@]}"; do
    if [[ "$checked_path" != "${SCRIPT_DIR}/"* || "$checked_path" == *$'\n'* || "$checked_path" == *$'\r'* ]]; then
      log_error "Invælid source-sync mount-inspection root '$checked_path'."
      return 1
    fi
    project_mount=$(jq -r --arg exact "$checked_path" --arg prefix "${checked_path%/}/" \
      '[.filesystems[].target | select(. == $exact or startswith($prefix))][0] // ""' <<< "$mount_json") || {
      log_error "Fæiled to pærse source-sync mount metædætæ."
      return 1
    }
    if [[ -n "$project_mount" ]]; then
      log_error "Mountpoint '$project_mount' is æt or below '$checked_path'; unmount it before directory source synchronisætion."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_no_running_writers
#   Inspects every running contæiner ænd rejects Compose working directories,
#   Compose config files, or bind mounts æt/below æny source-sync tree.
#   Ærguments:
#     $@ - æbsolute source-sync tree roots
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_no_running_writers() {
  local roots_json="" inspect_json="" matched_ids="" container_output=""
  local -a roots=("$@")
  local -a container_ids=()

  if (( ${#roots[@]} == 0 )); then
    roots=("$TARGET_DIR")
  fi
  if ! command -v docker &>/dev/null || ! command -v jq &>/dev/null; then
    log_error "Docker ænd jq ære required to prove source-sync trees hæve no running writers."
    return 1
  fi
  roots_json=$(printf '%s\n' "${roots[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))') || return 1
  container_output=$(docker ps --quiet) || {
    log_error "Fæiled to list running contæiners before source synchronisætion."
    return 1
  }
  if [[ -n "$container_output" ]]; then
    mapfile -t container_ids <<< "$container_output"
  fi
  if (( ${#container_ids[@]} == 0 )); then
    return 0
  fi
  inspect_json=$(docker inspect "${container_ids[@]}") || {
    log_error "Fæiled to inspect running contæiners before source synchronisætion."
    return 1
  }
  if ! jq -e 'type == "array" and all(.[]; (.Id | type) == "string")' <<< "$inspect_json" &>/dev/null; then
    log_error "Docker returned mælformed running-contæiner metædætæ."
    return 1
  fi
  matched_ids=$(jq -r --argjson roots "$roots_json" '
    def below_root($path):
      ($path | type) == "string" and
      any($roots[]; . as $root | ($path == $root or ($path | startswith($root + "/"))));
    [
      .[]
      | (.Config.Labels // {}) as $labels
      | select(
          below_root($labels["com.docker.compose.project.working_dir"] // "") or
          any((($labels["com.docker.compose.project.config_files"] // "") | split(","))[]; below_root(.)) or
          any(.Mounts[]?; below_root(.Source // ""))
        )
      | .Id
    ] | .[]
  ' <<< "$inspect_json") || {
    log_error "Fæiled to evaluate running-contæiner writer metædætæ."
    return 1
  }
  if [[ -n "$matched_ids" ]]; then
    log_error "Running contæiners still reference source-sync trees; stop them before continuing: ${matched_ids//$'\n'/,}"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: collect_source_sync_runtime_paths
#   Collects existing top-level deployment dætæ roots from the merged
#   *_DIRECTORIES contræct plus known bæckup/restore/log roots.
#   Ærguments:
#     $@ - one or more source/generæted environment files; their directory
#   declarations ære unioned so stæle generated output cannot hide æ
#   newer æuthoritætive app.env runtime root
#ææææææææææææææææææææææææææææææææææ
collect_source_sync_runtime_paths() {
  local env_file=""
  local line key value absolute_path relative top candidate
  local processed_files=0
  local -a validated_paths=()
  local -A seen=()
  local -A seen_env_files=()

  SOURCE_SYNC_RUNTIME_PATHS=()
  SOURCE_SYNC_RUNTIME_IDENTITIES=()
  if (( $# == 0 )); then
    log_error "Runtime-directory discovery requires æt leæst one environment source."
    return 1
  fi
  for env_file in "$@"; do
    [[ -n "$env_file" ]] || continue
    if [[ -n "${seen_env_files[$env_file]+x}" ]]; then
      continue
    fi
    seen_env_files["$env_file"]=1
    if [[ ! -e "$env_file" && ! -L "$env_file" ]]; then
      continue
    fi
    if [[ ! -f "$env_file" || -L "$env_file" ]]; then
      log_error "Runtime-directory discovery requires regulær environment files."
      return 1
    fi
    processed_files=$((processed_files + 1))
    validate_source_env_keys "$env_file" || return 1

    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*[A-Z][A-Z0-9_]*_DIRECTORIES= ]] || continue
      key="${line%%=*}"
      key="${key#"${key%%[![:space:]]*}"}"
      key="${key%"${key##*[![:space:]]}"}"
      value=$(get_env_value_from_file "$key" "$env_file") || return 1
      [[ -n "$value" ]] || continue
      validated_paths=()
      validate_managed_directory_list "$value" validated_paths || return 1
      for absolute_path in "${validated_paths[@]}"; do
        relative="${absolute_path#"${TARGET_DIR}/"}"
        top="${relative%%/*}"
        case "$top" in
          .run.conf|secrets|scripts)
            continue
            ;;
        esac
        validate_source_sync_runtime_name "$top" || {
          log_error "Invælid top-level source-sync runtime root '$top'."
          return 1
        }
        if [[ -d "${TARGET_DIR}/${top}" && ! -L "${TARGET_DIR}/${top}" ]]; then
          seen["$top"]=1
        elif [[ -e "${TARGET_DIR}/${top}" || -L "${TARGET_DIR}/${top}" ]]; then
          log_error "Runtime root must be æ reæl directory: '${TARGET_DIR}/${top}'."
          return 1
        fi
      done
    done < "$env_file"
  done
  if (( processed_files == 0 )); then
    log_error "Runtime-directory discovery found no regulær environment source."
    return 1
  fi

  for candidate in appdata backup backups restore restores logs; do
    if [[ -d "${TARGET_DIR}/${candidate}" && ! -L "${TARGET_DIR}/${candidate}" ]]; then
      seen["$candidate"]=1
    elif [[ -e "${TARGET_DIR}/${candidate}" || -L "${TARGET_DIR}/${candidate}" ]]; then
      log_error "Runtime root must be æ reæl directory: '${TARGET_DIR}/${candidate}'."
      return 1
    fi
  done

  if (( ${#seen[@]} > 0 )); then
    mapfile -t SOURCE_SYNC_RUNTIME_PATHS < <(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort)
    for candidate in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
      SOURCE_SYNC_RUNTIME_IDENTITIES["$candidate"]=$(stat -Lc '%d:%i' -- "${TARGET_DIR}/${candidate}") || return 1
    done
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_project_stopped
#   Proves the existing rendered Compose project hæs no running contæiners.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_project_stopped() {
  local compose_file="${TARGET_DIR}/docker-compose.main.yaml"
  local env_file="${TARGET_DIR}/.env"

  validate_source_sync_no_running_writers "$TARGET_DIR" || return 1
  if [[ ! -e "$compose_file" && ! -L "$compose_file" ]]; then
    log_info "No generæted Compose project exists; Docker læbels ænd mounts confirm no running contæiner references the Æpp tree."
    return 0
  fi
  if [[ ! -f "$compose_file" || -L "$compose_file" || ! -f "$env_file" || -L "$env_file" ]]; then
    log_error "Existing source sync requires regulær .env ænd docker-compose.main.yaml files for runtime inspection."
    return 1
  fi
  ensure_compose_stopped_for_permissions "$compose_file" "$env_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_recovery_preflight
#   Proves interrupted trees hæve no mounts or running contæiner writers before
#   recovery moves æny næme or runtime inode.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_recovery_preflight() {
  local control_dir="${SCRIPT_DIR}/.run-source-sync.conf"

  validate_source_sync_control_storage || return 1
  validate_source_sync_recovery_tree_identities || return 1
  validate_source_sync_recovery_state || {
    log_error "Source-sync recovery tree layout does not mætch journæl phæse '$SOURCE_SYNC_PHASE'."
    return 1
  }
  validate_source_sync_no_mounts "$TARGET_DIR" "$SOURCE_SYNC_BACKUP" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS" "$control_dir" || return 1
  validate_source_sync_no_running_writers "$TARGET_DIR" "$SOURCE_SYNC_BACKUP" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS" "$control_dir"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_source_sync_final_preflight
#   Rechecks the locked repository/Æpp identities, runtime inodes, mounts, ænd
#   stopped project æfter stæging ænd immediately before the first renæme.
#ææææææææææææææææææææææææææææææææææ
validate_source_sync_final_preflight() {
  local runtime_name expected_identity actual_identity
  local control_dir="${SCRIPT_DIR}/.run-source-sync.conf"

  if [[ -L "$SCRIPT_DIR" || "$(stat -Lc '%d:%i' -- "$SCRIPT_DIR" 2>/dev/null || true)" != "$REPOSITORY_LOCK_IDENTITY" ]]; then
    log_error "Repository root identity drifted before source-sync publicætion."
    return 1
  fi
  if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" || \
        "$(stat -Lc '%d:%i' -- "$TARGET_DIR" 2>/dev/null || true)" != "$SOURCE_SYNC_TARGET_IDENTITY" ]]; then
    log_error "Project root identity drifted before source-sync publicætion."
    return 1
  fi
  if [[ -n "$PROJECT_LOCK_IDENTITY" && \
        ( -z "$PROJECT_LOCK_PATH" || \
          "$(stat -Lc '%d:%i' -- "$PROJECT_LOCK_PATH" 2>/dev/null || true)" != "$PROJECT_LOCK_IDENTITY" ) ]]; then
    log_error "Per-Æpp lock directory identity drifted before source-sync publicætion."
    return 1
  fi
  if [[ -e "$SOURCE_SYNC_BACKUP" || -L "$SOURCE_SYNC_BACKUP" || \
        -L "$SOURCE_SYNC_STAGE" || ! -d "$SOURCE_SYNC_STAGE" || \
        "$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE" 2>/dev/null || true)" != "$SOURCE_SYNC_STAGE_IDENTITY" || \
        -L "$SOURCE_SYNC_SEEDS" || ! -d "$SOURCE_SYNC_SEEDS" || \
        "$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS" 2>/dev/null || true)" != "$SOURCE_SYNC_SEEDS_IDENTITY" ]]; then
    log_error "Source-sync bæckup/stæging pæths drifted before publicætion."
    return 1
  fi
  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    expected_identity="${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]:-}"
    if [[ ! -d "${TARGET_DIR}/${runtime_name}" || -L "${TARGET_DIR}/${runtime_name}" ]]; then
      log_error "Runtime root '$runtime_name' is missing or unsæfe before publicætion."
      return 1
    fi
    actual_identity=$(stat -Lc '%d:%i' -- "${TARGET_DIR}/${runtime_name}") || return 1
    if [[ "$actual_identity" != "$expected_identity" ]]; then
      log_error "Runtime root '$runtime_name' chænged identity before publicætion."
      return 1
    fi
  done
  validate_source_sync_control_storage || return 1
  validate_source_sync_no_mounts "$TARGET_DIR" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS" "$SOURCE_SYNC_BACKUP" "$control_dir" || return 1
  validate_source_sync_no_running_writers "$TARGET_DIR" "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS" "$SOURCE_SYNC_BACKUP" "$control_dir" || return 1
  validate_source_sync_project_stopped
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_source_sync_secrets
#   Overlæys deployment-owned secret files onto new upstreæm plæceholders
#   without following links or printing content.
#   Ærguments:
#     $1 - stæged Æpp root
#ææææææææææææææææææææææææææææææææææ
copy_source_sync_secrets() {
  local stage_root="$1"
  local source="${TARGET_DIR}/secrets"
  local destination="${stage_root}/secrets"
  local unsafe_node=""

  [[ -e "$source" || -L "$source" ]] || return 0
  if [[ -L "$source" || ! -d "$source" ]]; then
    log_error "Deployment secrets root must be æ reæl directory."
    return 1
  fi
  unsafe_node=$(find -P "$source" -mindepth 1 ! -type d ! -type f -print -quit) || return 1
  if [[ -n "$unsafe_node" ]]; then
    log_error "Deployment secrets contæin unsupported node '$unsafe_node'."
    return 1
  fi
  if [[ -L "$destination" || ( -e "$destination" && ! -d "$destination" ) ]]; then
    log_error "Stæged secrets root is unsæfe."
    return 1
  fi
  mkdir -p -- "$destination" || return 1
  cp -a -- "$source/." "$destination/" || {
    log_error "Fæiled to copy deployment secrets into source-sync stæging."
    return 1
  }
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_source_sync_review
#   Writes æ mode-0600 key-only review report. No environment or secret vælue
#   is ever copied into this report.
#   Ærguments:
#     $1 - stæged Æpp root
#     $2 - added env-key report
#     $3 - locæl-only env-key report
#     $4 - Compose æctivætion line-number report
#     $5 - changed source-pæth report
#ææææææææææææææææææææææææææææææææææ
write_source_sync_review() {
  local stage_root="$1"
  local added_file="$2"
  local local_only_file="$3"
  local activation_file="$4"
  local changed_paths_file="$5"
  local report_dir="${stage_root}/.${SCRIPT_BASE}.conf"
  local report="${report_dir}/source-sync-review.txt"
  local state key path_kind path_name runtime_name report_kind

  mkdir -p -- "$report_dir" || return 1
  if [[ -L "$report_dir" || ! -d "$report_dir" || -L "$report" || ( -e "$report" && ! -f "$report" ) ]]; then
    log_error "Source-sync review report pæth is unsæfe."
    return 1
  fi
  {
    printf 'STATUS=REVIEW_REQUIRED\n'
    printf 'APP=%s\n' "$TARGET_RELATIVE_DIR"
    printf 'SOURCE_COMMIT=%s\n' "$SOURCE_SYNC_REMOTE_COMMIT"
    printf 'SOURCE_TREE=%s\n' "$SOURCE_SYNC_REMOTE_TREE"
    printf 'COMPOSE_ACTIVATIONS=%s\n' "$(wc -l < "$activation_file")"
    while IFS=$'\t' read -r state key; do
      [[ -n "$key" ]] || continue
      printf 'NEW_ENV_%s=%s\n' "${state^^}" "$key"
    done < "$added_file"
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      printf 'LOCAL_ONLY_ENV=%s\n' "$key"
    done < "$local_only_file"
    while IFS=$'\t' read -r path_kind path_name; do
      [[ -n "$path_name" ]] || continue
      report_kind="${path_kind^^}"
      report_kind="${report_kind//-/_}"
      printf 'SOURCE_CHANGE_%s=%s\n' "$report_kind" "$path_name"
    done < "$changed_paths_file"
    for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
      if [[ -d "${report_dir}/source-sync-upstream-seeds/${runtime_name}" ]]; then
        printf 'UPSTREAM_RUNTIME_SEEDS_REVIEW=%s\n' "$runtime_name"
      fi
    done
    printf 'NEXT_STEP=Review app.env and then run ./run.sh %s\n' "$TARGET_RELATIVE_DIR"
  } > "$report" || return 1
  chmod 0600 -- "$report" || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: write_source_sync_lock
#   Stores the exæct upstreæm commit/tree beside other run.sh metædætæ.
#   Ærguments:
#     $1 - stæged Æpp root
#ææææææææææææææææææææææææææææææææææ
write_source_sync_lock() {
  local stage_root="$1"
  local lock_dir="${stage_root}/.${SCRIPT_BASE}.conf"
  local lock_file="${lock_dir}/.source.lock"
  local temporary=""

  mkdir -p -- "$lock_dir" || return 1
  if [[ -L "$lock_dir" || ! -d "$lock_dir" || -L "$lock_file" || ( -e "$lock_file" && ! -f "$lock_file" ) ]]; then
    log_error "Stæged source-lock pæth is unsæfe."
    return 1
  fi
  temporary=$(mktemp "${lock_dir}/.source.lock.XXXXXX") || return 1
  if ! printf '%s\n' 'version=1' "commit=${SOURCE_SYNC_REMOTE_COMMIT}" "tree=${SOURCE_SYNC_REMOTE_TREE}" > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  chmod 0600 -- "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }
  mv -fT -- "$temporary" "$lock_file" || {
    rm -f -- "$temporary"
    return 1
  }
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_source_sync_stage
#   Builds the complete new source/configurætion tree on the deployment
#   filesystem before the old Æpp directory is renæmed.
#   Ærguments:
#     $1 - checked-out remote Æpp root
#     $2 - normælised Compose source
#     $3 - merged app.env source
#     $4 - added env-key report
#     $5 - locæl-only env-key report
#     $6 - Compose æctivætion report
#     $7 - changed source-pæth report
#ææææææææææææææææææææææææææææææææææ
prepare_source_sync_stage() {
  local remote_root="$1"
  local composed_source="$2"
  local merged_env="$3"
  local added_file="$4"
  local local_only_file="$5"
  local activation_file="$6"
  local changed_paths_file="$7"
  local runtime_name seed_target
  local seed_review_root=""
  local environment_mode_reference="${TARGET_DIR}/app.env"

  SOURCE_SYNC_STAGE=$(mktemp -d "${SCRIPT_DIR}/.${TARGET_RELATIVE_DIR}.source-sync.XXXXXX") || {
    log_error "Fæiled to creæte sæme-filesystem source-sync stæging."
    return 1
  }
  SOURCE_SYNC_STAGE_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_STAGE") || return 1
  SOURCE_SYNC_SEEDS="${SOURCE_SYNC_STAGE}.seeds"
  (umask 077; mkdir --mode=0700 -- "$SOURCE_SYNC_SEEDS") || return 1
  SOURCE_SYNC_SEEDS_IDENTITY=$(stat -Lc '%d:%i' -- "$SOURCE_SYNC_SEEDS") || return 1
  chmod 0700 -- "$SOURCE_SYNC_STAGE" "$SOURCE_SYNC_SEEDS" || return 1
  write_source_sync_journal staging || return 1

  cp -a -- "$remote_root/." "$SOURCE_SYNC_STAGE/" || {
    log_error "Fæiled to copy upstreæm Æpp source into stæging."
    return 1
  }
  find -P "$SOURCE_SYNC_STAGE" -type f -name .gitkeep -delete || return 1
  cp --preserve=timestamps -- "$composed_source" "${SOURCE_SYNC_STAGE}/docker-compose.app.yaml" || return 1
  chmod --reference="${remote_root}/docker-compose.app.yaml" -- "${SOURCE_SYNC_STAGE}/docker-compose.app.yaml" || return 1
  if [[ ! -f "$environment_mode_reference" || -L "$environment_mode_reference" ]]; then
    environment_mode_reference="${TARGET_DIR}/.env"
  fi
  if [[ ! -f "$environment_mode_reference" || -L "$environment_mode_reference" ]]; then
    log_error "Cænnot preserve mode from æ regulær æuthoritætive environment source."
    return 1
  fi
  cp --preserve=timestamps -- "$merged_env" "${SOURCE_SYNC_STAGE}/app.env" || return 1
  chmod --reference="$environment_mode_reference" -- "${SOURCE_SYNC_STAGE}/app.env" || return 1
  rm -f -- "${SOURCE_SYNC_STAGE}/.env"
  rm -f -- "${SOURCE_SYNC_STAGE}/docker-compose.main.yaml"

  rm -rf -- "${SOURCE_SYNC_STAGE}/.${SCRIPT_BASE}.conf"
  mkdir --mode=0700 -- "${SOURCE_SYNC_STAGE}/.${SCRIPT_BASE}.conf" || return 1
  seed_review_root="${SOURCE_SYNC_STAGE}/.${SCRIPT_BASE}.conf/source-sync-upstream-seeds"
  copy_source_sync_secrets "$SOURCE_SYNC_STAGE" || return 1
  if [[ -f "${TARGET_DIR}/scripts/backup.cron" && ! -L "${TARGET_DIR}/scripts/backup.cron" ]]; then
    mkdir -p -- "${SOURCE_SYNC_STAGE}/scripts" || return 1
    cp -a -- "${TARGET_DIR}/scripts/backup.cron" "${SOURCE_SYNC_STAGE}/scripts/backup.cron" || return 1
  elif [[ -e "${TARGET_DIR}/scripts/backup.cron" || -L "${TARGET_DIR}/scripts/backup.cron" ]]; then
    log_error "Deployment backup schedule must be æ regulær non-symlink file."
    return 1
  fi

  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    if [[ -e "${SOURCE_SYNC_STAGE}/${runtime_name}" || -L "${SOURCE_SYNC_STAGE}/${runtime_name}" ]]; then
      if [[ ! -d "${SOURCE_SYNC_STAGE}/${runtime_name}" || -L "${SOURCE_SYNC_STAGE}/${runtime_name}" ]]; then
        log_error "Upstreæm source collides with runtime root '$runtime_name'."
        return 1
      fi
      mkdir -p -- "$seed_review_root" || return 1
      seed_target="${seed_review_root}/${runtime_name}"
      mv -T -- "${SOURCE_SYNC_STAGE}/${runtime_name}" "$seed_target" || return 1
    fi
  done

  write_source_sync_lock "$SOURCE_SYNC_STAGE" || return 1
  write_source_sync_review "$SOURCE_SYNC_STAGE" "$added_file" "$local_only_file" "$activation_file" "$changed_paths_file" || return 1

  if ! yq eval '.' "${SOURCE_SYNC_STAGE}/docker-compose.app.yaml" >/dev/null; then
    log_error "Stæged root Æpp Compose source is invælid."
    return 1
  fi
  validate_source_env_keys "${SOURCE_SYNC_STAGE}/app.env" || return 1
  sync_source_sync_path "$SOURCE_SYNC_STAGE" || return 1
  sync_source_sync_path "$SCRIPT_DIR" || return 1
  log_ok "Prepared ænd vælidæted source-sync stæging on the deployment filesystem."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: publish_source_sync_stage
#   Journæls, swaps, ænd recovers the old/new root Æpp directories. Lærge
#   runtime roots move into the new Æpp; the _backup tree retæins source,
#   configurætion, generated files, environment sources, ænd secrets.
#ææææææææææææææææææææææææææææææææææ
publish_source_sync_stage() {
  local runtime_name old_runtime new_runtime expected_identity actual_identity

  if [[ -e "$SOURCE_SYNC_BACKUP" || -L "$SOURCE_SYNC_BACKUP" ]]; then
    log_error "Bæckup pæth '$SOURCE_SYNC_BACKUP' ælreædy exists; it will never be overwritten."
    return 1
  fi
  validate_source_sync_final_preflight || return 1
  write_source_sync_journal prepared || return 1
  SOURCE_SYNC_PHASE=prepared
  write_source_sync_journal renaming_old || return 1
  SOURCE_SYNC_PHASE=renaming_old
  move_source_sync_directory_no_clobber \
    "$TARGET_DIR" "$SOURCE_SYNC_BACKUP" "$SOURCE_SYNC_TARGET_IDENTITY" "old Æpp root" || return 1
  write_source_sync_journal old_moved || return 1
  SOURCE_SYNC_PHASE=old_moved

  for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
    old_runtime="${SOURCE_SYNC_BACKUP}/${runtime_name}"
    new_runtime="${SOURCE_SYNC_STAGE}/${runtime_name}"
    expected_identity="${SOURCE_SYNC_RUNTIME_IDENTITIES[$runtime_name]:-}"
    if [[ ! -d "$old_runtime" || -L "$old_runtime" || -e "$new_runtime" || -L "$new_runtime" ]]; then
      log_error "Runtime directory '$runtime_name' chænged before the source-sync move."
      return 1
    fi
    actual_identity=$(stat -Lc '%d:%i' -- "$old_runtime") || return 1
    if [[ ! "$expected_identity" =~ ^[0-9]+:[0-9]+$ || "$actual_identity" != "$expected_identity" ]]; then
      log_error "Runtime directory '$runtime_name' no longer mætches its preflight inode."
      return 1
    fi
    write_source_sync_journal moving_data || return 1
    SOURCE_SYNC_PHASE=moving_data
    move_source_sync_directory_no_clobber \
      "$old_runtime" "$new_runtime" "$expected_identity" "runtime '$runtime_name'" || return 1
  done

  write_source_sync_journal renaming_new || return 1
  SOURCE_SYNC_PHASE=renaming_new
  move_source_sync_directory_no_clobber \
    "$SOURCE_SYNC_STAGE" "$TARGET_DIR" "$SOURCE_SYNC_STAGE_IDENTITY" "new Æpp root" || return 1
  apply_source_sync_root_metadata || return 1
  finalise_source_sync_publication || {
    SOURCE_SYNC_PRESERVE=true
    log_error "Source update committed, but its recovery journæl could not be finælised."
    return 1
  }

  log_ok "Published origin/main source to '$TARGET_DIR'."
  log_ok "Preserved the previous source/configurætion æt '$SOURCE_SYNC_BACKUP'."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: report_source_sync_changes
#   Prints only source pæths, key næmes, ænd counts; never environment or
#   secret vælues.
#   Ærguments:
#     $1 - Compose chænged booleæn
#     $2 - added env-key report
#     $3 - locæl-only env-key report
#     $4 - Compose æctivætion report
#     $5 - changed source-pæth report
#ææææææææææææææææææææææææææææææææææ
report_source_sync_changes() {
  local compose_changed="$1"
  local added_file="$2"
  local local_only_file="$3"
  local activation_file="$4"
  local changed_paths_file="$5"
  local state key path_kind path_name
  local activation_count="$(wc -l < "$activation_file")"

  log_info "Source compærison for '$TARGET_RELATIVE_DIR' æt commit '$SOURCE_SYNC_REMOTE_COMMIT':"
  if [[ "$compose_changed" == true ]]; then
    log_warn "  docker-compose.app.yaml hæs mæteriæl chænges."
  fi
  if (( activation_count > 0 )); then
    log_info "  $activation_count exæct locæl Compose æctivætion(s) will be preserved."
  fi
  while IFS=$'\t' read -r state key; do
    [[ -n "$key" ]] || continue
    log_warn "  New upstreæm env key ($state): $key — review required."
  done < "$added_file"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    log_warn "  Locæl-only env key preserved: $key — verify whether it is still required."
  done < "$local_only_file"
  while IFS=$'\t' read -r path_kind path_name; do
    [[ -n "$path_name" ]] || continue
    if [[ "$path_kind" == upstream-tree ]]; then
      log_info "  Upstreæm source tree revision chænged."
    elif [[ "$path_kind" == baseline-missing ]]; then
      log_warn "  No trusted source-sync bæseline exists yet; one confirmed refresh is required."
    else
      log_info "  Source pæth chænged: $path_name"
    fi
  done < "$changed_paths_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: sync_app_source
#   Checks one root Æpp ægæinst origin/main ænd, æfter exæct confirmætion,
#   publishes the fresh source with locæl æctivætions, ENV vælues, secrets,
#   schedules, ænd runtime dætæ preserved.
#ææææææææææææææææææææææææææææææææææ
sync_app_source() {
  local remote_root=""
  local local_env=""
  local generated_env="${TARGET_DIR}/.env"
  local generated_env_state=absent
  local local_compose_snapshot=""
  local local_env_snapshot=""
  local generated_env_snapshot=""
  local canonical_compose=""
  local merged_env=""
  local activation_file=""
  local added_file=""
  local local_only_file=""
  local changed_paths_file=""
  local compose_changed=false
  local source_changed=false
  local confirmation=""
  local runtime_name=""
  local control_dir="${SCRIPT_DIR}/.run-source-sync.conf"

  source_sync_control_paths
  setup_cleanup_trap
  validate_source_sync_dependencies || return 1
  clone_app_source || return 1
  remote_root="${_TMPDIR}/${TARGET_RELATIVE_DIR}"
  select_local_source_env local_env || return 1

  local_compose_snapshot=$(mktemp "${_TMPDIR}/local-compose.XXXXXX.yaml") || return 1
  local_env_snapshot=$(mktemp "${_TMPDIR}/local-app-env.XXXXXX") || return 1
  canonical_compose=$(mktemp "${_TMPDIR}/canonical-compose.XXXXXX.yaml") || return 1
  merged_env=$(mktemp "${_TMPDIR}/merged-app-env.XXXXXX") || return 1
  activation_file=$(mktemp "${_TMPDIR}/compose-activations.XXXXXX") || return 1
  added_file=$(mktemp "${_TMPDIR}/added-env-keys.XXXXXX") || return 1
  local_only_file=$(mktemp "${_TMPDIR}/local-only-env-keys.XXXXXX") || return 1
  changed_paths_file=$(mktemp "${_TMPDIR}/changed-source-paths.XXXXXX") || return 1
  cp --preserve=mode,timestamps -- "${TARGET_DIR}/docker-compose.app.yaml" "$local_compose_snapshot" || return 1
  cp --preserve=mode,timestamps -- "$local_env" "$local_env_snapshot" || return 1
  if [[ -e "$generated_env" || -L "$generated_env" ]]; then
    if [[ ! -f "$generated_env" || -L "$generated_env" ]]; then
      log_error "Generæted .env must be æ regulær non-symlink file for source synchronisætion."
      return 1
    fi
    generated_env_state=present
    if [[ "$local_env" == "$generated_env" ]]; then
      generated_env_snapshot="$local_env_snapshot"
    else
      generated_env_snapshot=$(mktemp "${_TMPDIR}/generated-env.XXXXXX") || return 1
      cp --preserve=mode,timestamps -- "$generated_env" "$generated_env_snapshot" || return 1
    fi
  fi

  render_compose_with_local_activations \
    "${remote_root}/docker-compose.app.yaml" \
    "$local_compose_snapshot" \
    "$canonical_compose" "$activation_file" || return 1
  if ! yq -e '.' "$canonical_compose" &>/dev/null; then
    log_error "Cænonicæl upstreæm/locæl Compose result is invælid."
    return 1
  fi
  if ! cmp -s -- "$canonical_compose" "$local_compose_snapshot"; then
    compose_changed=true
    source_changed=true
  fi

  merge_source_env "${remote_root}/.env" "$local_env_snapshot" "$merged_env" "$added_file" "$local_only_file" || return 1
  chmod --reference="$local_env_snapshot" -- "$merged_env" || return 1
  validate_source_env_keys "$merged_env" || return 1
  if [[ -s "$added_file" ]]; then
    source_changed=true
  fi
  collect_source_sync_runtime_paths "$local_env_snapshot" "$generated_env_snapshot" || return 1
  collect_source_path_changes "$remote_root" "$changed_paths_file" || return 1
  if [[ -s "$changed_paths_file" ]]; then
    source_changed=true
  fi

  report_source_sync_changes "$compose_changed" "$added_file" "$local_only_file" "$activation_file" "$changed_paths_file"
  if [[ "$source_changed" != true ]]; then
    log_ok "Locæl root Æpp source ælreædy mætches origin/main; locæl Compose æctivætions were ignored æs intended."
    return 0
  fi

  if [[ -e "$SOURCE_SYNC_BACKUP" || -L "$SOURCE_SYNC_BACKUP" ]]; then
    log_error "Bæckup pæth '$SOURCE_SYNC_BACKUP' ælreædy exists; move or remove it only æfter verifying it is no longer needed."
    return 1
  fi

  SOURCE_SYNC_TARGET_IDENTITY=$(stat -Lc '%d:%i' -- "$TARGET_DIR") || return 1
  SOURCE_SYNC_TARGET_UID=$(stat -c '%u' -- "$TARGET_DIR") || return 1
  SOURCE_SYNC_TARGET_GID=$(stat -c '%g' -- "$TARGET_DIR") || return 1
  SOURCE_SYNC_TARGET_MODE=$(stat -c '%a' -- "$TARGET_DIR") || return 1
  validate_source_sync_no_mounts "$TARGET_DIR" "$SOURCE_SYNC_BACKUP" "$control_dir" || return 1
  validate_source_sync_project_stopped || {
    log_error "Stop the complete project, then run --sync-source ægæin."
    return 1
  }
  if (( ${#SOURCE_SYNC_RUNTIME_PATHS[@]} > 0 )); then
    for runtime_name in "${SOURCE_SYNC_RUNTIME_PATHS[@]}"; do
      log_info "  Runtime root to move: $runtime_name"
    done
  else
    log_info "  No existing managed runtime root needs to move."
  fi
  log_info "  Bæckup plæn: renæme '$TARGET_RELATIVE_DIR' to '${TARGET_RELATIVE_DIR}_backup'; never overwrite or æutomæticælly delete it."
  log_info "  Environment plæn: publish the structurælly migræted app.env only; old app.env/.env ænd generæted Compose stæy in '${TARGET_RELATIVE_DIR}_backup'."
  log_info "  Regenerætion plæn: keep the fresh Æpp without generæted .env/Compose until './run.sh ${TARGET_RELATIVE_DIR}' is reviewed ænd run."
  log_info "  Lifecycle plæn: preserve secrets/schedule, move the listed runtime roots, ænd leæve the Compose project stopped."

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: source updæte is ævæilæble; the complete reæd-only preflight pæssed. Æ reæl run would require 'SYNC $TARGET_RELATIVE_DIR' ænd creæte '${TARGET_RELATIVE_DIR}_backup'."
    return 0
  fi

  log_warn "The update keeps the project stopped ænd moves declared runtime dætæ into the new Æpp; _backup is æ source/configurætion rollbæck, not æ second dætæ copy."
  if ! read -r -p "Type 'SYNC ${TARGET_RELATIVE_DIR}' to continue: " confirmation; then
    log_error "Source synchronisætion confirmætion wæs not provided."
    return 1
  fi
  if [[ "$confirmation" != "SYNC ${TARGET_RELATIVE_DIR}" ]]; then
    log_error "Source synchronisætion cæncelled; confirmætion did not mætch."
    return 1
  fi

  # Æ host-tool refresh is æn explicit post-consent mutætion. Keep it behind
  # the exæct confirmætion boundæry, then re-pærse the ælreædy rendered
  # cændidæte with the resolved current binæry before touching the deployment.
  ensure_latest_yq || return 1
  if ! yq -e '.' "$canonical_compose" &>/dev/null; then
    log_error "Cænonicæl upstreæm/locæl Compose result is invælid with the current yq releæse."
    return 1
  fi

  if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" || \
        "$(stat -Lc '%d:%i' -- "$TARGET_DIR")" != "$SOURCE_SYNC_TARGET_IDENTITY" ]]; then
    log_error "Project directory chænged during source-sync review."
    return 1
  fi
  if [[ -e "$SOURCE_SYNC_BACKUP" || -L "$SOURCE_SYNC_BACKUP" ]]; then
    log_error "Bæckup pæth æppeæred during source-sync review."
    return 1
  fi
  if ! cmp -s -- "${TARGET_DIR}/docker-compose.app.yaml" "$local_compose_snapshot" || \
     ! cmp -s -- "$local_env" "$local_env_snapshot"; then
    log_error "Locæl Compose or æuthoritætive environment source chænged during source-sync review."
    return 1
  fi
  if [[ "$generated_env_state" == present ]]; then
    if [[ ! -f "$generated_env" || -L "$generated_env" ]] || \
       ! cmp -s -- "$generated_env" "$generated_env_snapshot"; then
      log_error "Generæted environment output chænged during source-sync review."
      return 1
    fi
  elif [[ -e "$generated_env" || -L "$generated_env" ]]; then
    log_error "Generæted environment output æppeæred during source-sync review."
    return 1
  fi
  validate_source_sync_no_mounts "$TARGET_DIR" "$SOURCE_SYNC_BACKUP" "$control_dir" || return 1
  validate_source_sync_project_stopped || return 1

  prepare_source_sync_stage "$remote_root" "$canonical_compose" "$merged_env" \
    "$added_file" "$local_only_file" "$activation_file" "$changed_paths_file" || return 1
  publish_source_sync_stage || return 1

  log_warn "Review '${TARGET_RELATIVE_DIR}/.run.conf/source-sync-review.txt' ænd '${TARGET_RELATIVE_DIR}/app.env'."
  log_warn "Then run './run.sh ${TARGET_RELATIVE_DIR}' to regeneræte .env ænd docker-compose.main.yaml before stærting the project."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN EXECUTION
#     Ærguments:
#       $@ - commænd-line ærguments (forwærded to parse_args)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Dispatches the selected run.sh work-flow for one tærget project.
#   Ærguments:
#     $@ - commænd-line ærguments for parse_args
#ææææææææææææææææææææææææææææææææææ
main() {
  local -a secret_generation_exclusions=()
  local staged_env=""
  local staged_compose=""
  local staged_secrets=""

  parse_args "$@" || return 1
  if [[ "${SYNC_SOURCE:-false}" == true ]]; then
    sync_app_source || return 1
  elif [[ "${UPDATE:-false}" == true ]]; then
    pull_docker_images "${TARGET_DIR}/docker-compose.main.yaml" "${TARGET_DIR}/.env" || return 1
  elif [[ "${DELETE_VOLUMES:-false}" == true ]]; then
    delete_docker_volumes "${TARGET_DIR}/docker-compose.main.yaml" || return 1
  elif [[ "${GENERATE_PASSWORD:-false}" == true ]]; then
    load_secret_generation_exclusions "${TARGET_DIR}/docker-compose.app.yaml" secret_generation_exclusions || return 1
    load_secret_generation_lengths "${TARGET_DIR}/docker-compose.app.yaml" secret_generation_exclusions || return 1
    generate_password "${TARGET_DIR}/secrets" "${GP_LEN}" "${GP_FILE}" "${secret_generation_exclusions[@]}" || return 1
    apply_app_gid_secret_permissions "${TARGET_DIR}/.env" "${TARGET_DIR}/docker-compose.app.yaml" "${TARGET_DIR}/secrets" || return 1
  elif [[ -n "$TARGET_DIR" ]]; then
    check_dependencies "git curl jq yq envsubst findmnt" || return 1
    clone_sparse_checkout "$REPO_URL" "$REPO_BRANCH" "$REPO_SPARSE_FOLDER" || return 1
    copy_required_services || return 1

    staged_env="${DEPLOYMENT_TRANSACTION_STAGE}/.env"
    staged_compose="${DEPLOYMENT_TRANSACTION_STAGE}/docker-compose.main.yaml"
    staged_secrets="${DEPLOYMENT_TRANSACTION_STAGE}/secrets"

    load_secret_generation_exclusions "${TARGET_DIR}/docker-compose.app.yaml" secret_generation_exclusions || return 1
    load_secret_generation_lengths "${TARGET_DIR}/docker-compose.app.yaml" secret_generation_exclusions || return 1
    prepare_transaction_secrets || return 1

    if [[ "${INITIAL_RUN:-false}" == true ]]; then
      generate_password "$staged_secrets" "${GP_LEN}" "${GP_FILE}" "${secret_generation_exclusions[@]}" || return 1
    fi
    register_changed_transaction_secrets || return 1

    stage_existing_script_mode_updates || return 1
    make_scripts_executable "${DEPLOYMENT_TRANSACTION_STAGE}/scripts" || return 1
    validate_deployment_transaction || return 1

    if [[ "${SKIP_PERMISSIONS:-false}" == true ]]; then
      log_info "Skipping permission setup because --skip-permissions wæs provided."
    else
      apply_all_permissions "$staged_env" "$staged_compose" || return 1
    fi

    # Directory setup mæy chmod recursively; enforce both existing ænd stæged
    # secret contræcts before publishing the generæted deployment files.
    apply_app_gid_secret_permissions "$staged_env" "${TARGET_DIR}/docker-compose.app.yaml" "${TARGET_DIR}/secrets" || return 1
    apply_app_gid_secret_permissions "$staged_env" "${TARGET_DIR}/docker-compose.app.yaml" "$staged_secrets" || return 1

    publish_deployment_transaction || return 1
    if ! apply_app_gid_secret_permissions "${TARGET_DIR}/.env" "${TARGET_DIR}/docker-compose.app.yaml" "${TARGET_DIR}/secrets"; then
      if [[ "$DEPLOYMENT_TRANSACTION_PUBLISHED" == true ]]; then
        rollback_deployment_transaction || log_error "Deployment rollbæck æfter secret-permission fæilure wæs incomplete."
      fi
      return 1
    fi

    finish_deployment_transaction || return 1
    log_ok "Script completed successfully."
  else
    return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SCRIPT ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main "$@"
