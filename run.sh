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
readonly HOST_LOGROTATE_DIR="/etc/logrotate.d"
readonly HOST_LOGROTATE_MARKER="# Managed by it.saervices run.sh (host-logrotate-v1)"
readonly HOST_LOGROTATE_REALPATH_BIN="/usr/bin/realpath"
readonly HOST_LOGROTATE_STAT_BIN="/usr/bin/stat"
readonly HOST_LOGROTATE_JQ_BIN="/usr/bin/jq"
readonly HOST_LOGROTATE_GETENT_BIN="/usr/bin/getent"
readonly HOST_LOGROTATE_ID_BIN="/usr/bin/id"
readonly -a HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES=(/usr/sbin/logrotate /usr/bin/logrotate)
readonly HOST_LOGROTATE_SUDO_BIN="/usr/bin/sudo"
readonly HOST_LOGROTATE_ROOT_MKTEMP_BIN="/usr/bin/mktemp"
readonly HOST_LOGROTATE_ROOT_TEE_BIN="/usr/bin/tee"
readonly HOST_LOGROTATE_ROOT_CHMOD_BIN="/usr/bin/chmod"
readonly HOST_LOGROTATE_ROOT_MV_BIN="/usr/bin/mv"
readonly HOST_LOGROTATE_ROOT_RM_BIN="/usr/bin/rm"

HOST_LOGROTATE_RENDERED_FILE=""
HOST_LOGROTATE_UNRESOLVED_FILE=""
HOST_LOGROTATE_RENDERED_CONFIG=""
HOST_LOGROTATE_TARGET_FILE=""
HOST_LOGROTATE_PROJECT_NAME=""
HOST_LOGROTATE_PROJECT_ROOT_HASH=""
HOST_LOGROTATE_DOCKER_BIN=""
HOST_LOGROTATE_LOGROTATE_BIN=""
HOST_LOGROTATE_ROOT_PROCESS_GROUPS=""
HOST_LOGROTATE_YQ_BIN=""
HOST_LOGROTATE_YQ_IDENTITY=""
HOST_LOGROTATE_DIR_IDENTITY=""
HOST_LOGROTATE_PRIVILEGED_TMP=""
HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY=""
HOST_LOGROTATE_PRIVILEGED_TMP_HASH=""
HOST_LOGROTATE_PRIVILEGED_TMP_MODE=""
HOST_LOGROTATE_ROLLBACK_TMP=""
HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY=""
HOST_LOGROTATE_ROLLBACK_TMP_HASH=""
HOST_LOGROTATE_ROLLBACK_TMP_MODE=""
declare -a HOST_LOGROTATE_LOG_PATHS=()
declare -a HOST_LOGROTATE_LOG_IDENTITIES=()
declare -a HOST_LOGROTATE_PARENT_PATHS=()
declare -a HOST_LOGROTATE_PARENT_IDENTITIES=()
HOST_LOGROTATE_DEBUG_OUTPUT=""
declare -A HOST_LOGROTATE_TRAVERSAL_SEEN=()
declare -a HOST_LOGROTATE_TRAVERSAL_PATHS=()
declare -a HOST_LOGROTATE_TRAVERSAL_GRANT_BITS=()
declare -a HOST_LOGROTATE_TRAVERSAL_IDENTITIES=()
declare -a HOST_LOGROTATE_GRANTED_PATHS=()
declare -a HOST_LOGROTATE_GRANTED_OLD_MODES=()
declare -a HOST_LOGROTATE_GRANTED_IDENTITIES=()
declare -a HOST_LOGROTATE_GRANTED_BITS=()
_TMPDIR_IDENTITY=""
_TMPDIR_FD=""

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
#   Logs æn info messæge to stdout (ænd $LOGFILE if set)
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
#   Logs æ debug messæge to stdout when DEBUG is true (ænd $LOGFILE if set)
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
#   Initiælizes logging file inside TARGET_DIR
#   Keep only the lætest $log_retention_count logs
#   Ærguments:
#     $1 - mæximum number of log files to retæin
#ææææææææææææææææææææææææææææææææææ
setup_logging() {
  local log_retention_count="${1:-2}"
  local old_log

  # Construct log dir pæth (TARGET_DIR must be resolved to æbsolute before cælling)
  local log_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/logs"

  if [[ "${DRY_RUN:-false}" == true ]]; then
    LOGFILE=""
    log_info "Dry-run: would creæte log directory '$log_dir'"
    return 0
  fi

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

  for old_log in "${logs[@]}"; do
    rm -f "$old_log"
  done
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
  echo "  --dry-run                Simulæte æctions without executing"
  echo "  --force                  Force overwrite of existing files"
  echo "  --update                 Force updæte of templæte repo"
  echo "  --delete_volumes         Delete æssociæted Docker volumes for the project"
  echo "  --skip-permissions       Skip *_DIRECTORIES chown/chmod setup"
  echo "  --generate_password [file] [length]"
  echo "                           Generæte æ secure pæssword"
  echo "                           → Optionæl: file to write into secrets/"
  echo "                           → Optionæl: length (defæult: 100)"
  echo "  --check-logrotate        Vælidæte declared host log rotation ænd instælled stæte"
  echo "  --install-logrotate      Ætomicælly instæll or updæte declared host log rotation"
  echo "  --remove-logrotate       Remove the exæct mænæged host logrotate file"
  echo ""
  echo "Exæmples:"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password admin_password.txt"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password admin_password.txt 64"
  echo "  ./$SCRIPT_BASE.sh Traefik --install-logrotate --dry-run"
  echo ""
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_dependency
#   Instælls æ dependency using æpt, yum or from æ custom URL
#   Ærguments:
#     $1 - pæckæge næme
#     $2 - optionæl URL for direct downloæd
#ææææææææææææææææææææææææææææææææææ
install_dependency() {
  local name="$1"
  local url="${2:-}"

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: skipping æctuæl instællætion of '$name'."
    return 0
  fi

  # Ælwæys instæll yq viæ URL (binæry)
  if [[ "$name" == "yq" && -n "$url" ]]; then
    sudo wget -q -O "/usr/local/bin/yq" "$url"
    sudo chmod +x "/usr/local/bin/yq"
    log_info "Instælled yq viæ direct binæry downloæd."
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

  if [[ -z "$src_file" || -z "$dest_file" ]]; then
    log_error "Missing ærguments: src_file, dest_file"
    return 1
  fi

  if [[ ! -f "$src_file" ]]; then
    log_error "Source file '$src_file' does not exist"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: would copy '$src_file' to '$dest_file'"
    return 0
  fi

  if cp -- "$src_file" "$dest_file"; then
    log_info "Copied file: '$src_file' → '$dest_file'"
  else
    log_error "Fæiled to copy file '$src_file' to '$dest_file'"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: merge_subfolders_from
#   Copy æll subfolders from æ mætched source folder into æ destinætion folder.
#   Existing folders will be merged (new files ædded, nothing overwritten).
#   Supports DRY_RUN to simulæte the operætion.
#   Ærguments:
#     $1 - source root directory
#     $2 - subfolder næme to mætch
#     $3 - destinætion root directory
#ææææææææææææææææææææææææææææææææææ
merge_subfolders_from() {
  local src_root="$1"
  local match_name="$2"
  local dest_root="$3"
  local subdir

  # check æll required pæræms
  if [[ -z "$src_root" || -z "$match_name" || -z "$dest_root" ]]; then
    log_error "Missing ærguments: src_root, match_name, dest_root"
    return 1
  fi

  local matched_path="$src_root/$match_name"

  if [[ ! -d "$matched_path" ]]; then
    log_error "Source folder '$matched_path' not found"
    return 1
  fi

  ensure_dir_exists "$dest_root"

  for subdir in "$matched_path"/*/; do
    [[ -d "$subdir" ]] || continue
    local name
    name="$(basename "$subdir")"
    local target="$dest_root/$name"
    ensure_dir_exists "$target"

    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would merge contents of '$subdir' into '$target' (no overwrite)"
    else
      # Copy contents of $subdir into $tærget (no overwrite)
      if ! rsync -a --ignore-existing "${subdir%/}/" "$target/"; then
        log_error "rsync fæiled copying from '$subdir' to '$target'"
        return 1
      fi
      log_info "Merged contents of '$subdir' into '$target' (no overwrite)"
    fi
  done

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: cleanup_temporary_state
#   Removes the clone directory ænd privileged host-logrotate stæging.
#ææææææææææææææææææææææææææææææææææ
cleanup_temporary_state() {
  if [[ -n "${HOST_LOGROTATE_PRIVILEGED_TMP:-}" ]]; then
    if remove_identity_proven_host_logrotate_temporary_file \
        "$HOST_LOGROTATE_PRIVILEGED_TMP" publish \
        "${HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY:-}" \
        "${HOST_LOGROTATE_PRIVILEGED_TMP_HASH:-}" \
        "${HOST_LOGROTATE_PRIVILEGED_TMP_MODE:-}"; then
      HOST_LOGROTATE_PRIVILEGED_TMP=""
      HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY=""
      HOST_LOGROTATE_PRIVILEGED_TMP_HASH=""
      HOST_LOGROTATE_PRIVILEGED_TMP_MODE=""
    fi
  fi
  if [[ -n "${HOST_LOGROTATE_ROLLBACK_TMP:-}" ]]; then
    if remove_identity_proven_host_logrotate_temporary_file \
        "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
        "${HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY:-}" \
        "${HOST_LOGROTATE_ROLLBACK_TMP_HASH:-}" \
        "${HOST_LOGROTATE_ROLLBACK_TMP_MODE:-}"; then
      HOST_LOGROTATE_ROLLBACK_TMP=""
      HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY=""
      HOST_LOGROTATE_ROLLBACK_TMP_HASH=""
      HOST_LOGROTATE_ROLLBACK_TMP_MODE=""
    fi
  fi
  if [[ -n "${_TMPDIR_FD:-}" ]]; then
    exec {_TMPDIR_FD}<&- || true
    _TMPDIR_FD=""
  fi
  if [[ -n "${_TMPDIR:-}" && -d "$_TMPDIR" ]]; then
    rm -rf -- "$_TMPDIR"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: setup_cleanup_trap
#   Register EXIT træp to cleæn up temporæry folder
#ææææææææææææææææææææææææææææææææææ
setup_cleanup_trap() {
  trap cleanup_temporary_state EXIT
  log_debug "Registered cleænup træp for tmp directory: ${_TMPDIR:-}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: process_merge_file
#   Merges æ key=vælue file into æ tærget file without overwriting existing keys.
#   Supports dry-run mode ænd comment/blænk-line preservætion.
#   Ærguments:
#     $1 - source file pæth
#     $2 - output file pæth
#     $3 - reference næme for seen_værs æssociætive ærræy
#ææææææææææææææææææææææææææææææææææ
process_merge_file() {
  local file="$1"
  local output_file="$2"
  local -n seen_vars_ref="$3"
  local line
  local -a pending_comments=()
  local pc _bc wrote_any=false

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
          if [[ "$DRY_RUN" == true ]]; then
            log_info "Would preserve comment/blænk: $pc"
          else
            echo "$pc" >> "$output_file"
          fi
        done
        pending_comments=()
      fi
      if [[ "$DRY_RUN" == true ]]; then
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
          if [[ "$DRY_RUN" == true ]]; then
            log_info "Would preserve comment/blænk: $pc"
          else
            echo "$pc" >> "$output_file"
          fi
        done
        pending_comments=()
      fi

      seen_vars_ref["$key"]="$source_name"
      line="$(echo "$line" | sed -E 's/^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$/\1=\2/')"

      if [[ "$DRY_RUN" == true ]]; then
        log_info "Would ædd: $line"
      else
        echo "$line" >> "$output_file"
      fi
      wrote_any=true
    fi
  done < "$file"

  # Trælling pending_comments (orphæned heæders) ære discærded

  if [[ "$DRY_RUN" != true && "$wrote_any" == true ]]; then
    echo "" >> "$output_file"  # blænk line for clærity
    log_info "Merged $file into $output_file"
  fi
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
#ææææææææææææææææææææææææææææææææææ
process_merge_yaml_file() {
  local source_file="$1"
  local target_file="$2"

  [[ ! -f "$source_file" ]] && {
    log_error "Source compose file not found: $source_file"
    return 1
  }

  local tmp_src="${_TMPDIR}/process_merge_yaml_file_src_$$.yaml"
  local tmp_tgt="${_TMPDIR}/process_merge_yaml_file_tgt_$$.yaml"

  # Cleæn files: resolve only YÆML merge-key mæps, keep normæl æliæses for cross-file ænchors.
  yq '(.. | select(tag == "!!map" and has("<<"))) |= explode(.) | del(.["x-required-services"]) | ... comments=""' "$source_file" > "$tmp_src"

  if [[ -f "$target_file" ]]; then
    yq '(.. | select(tag == "!!map" and has("<<"))) |= explode(.) | ... comments=""' "$target_file" > "$tmp_tgt"
  else
    : > "$tmp_tgt"
  fi

  local MERGE_INPUTS=("$tmp_tgt" "$tmp_src")

  merge_key() {
    local key="$1"
    local files=("${MERGE_INPUTS[@]}")
    local result merged

    if ! result=$(yq eval-all "select(has(\"$key\")) | .$key" "${files[@]}" 2>&1); then
      log_error "Fæiled to extræct key '$key' during merge"
      return 1
    fi

    if [[ -z "$result" || "$result" == "null" ]]; then
      echo "{}"
      return 0
    fi

    if ! merged=$(echo "$result" | yq eval-all 'select(tag == "!!map") | . as $item ireduce ({}; . * $item)' - 2>&1); then
      log_error "Fæiled to reduce merged key '$key'"
      return 1
    fi

    echo "$merged"
  }

  local services volumes secrets networks
  local source_role="root-source"
  local source_host_logrotate=""
  local target_host_logrotate=""
  local host_logrotate=""
  services=$(merge_key services) || return 1
  volumes=$(merge_key volumes) || return 1
  secrets=$(merge_key secrets) || return 1
  networks=$(merge_key networks) || return 1

  if yq -e 'has("x-required-anchors")' "$source_file" &>/dev/null; then
    source_role="component-source"
  fi
  validate_merge_host_logrotate_document "$source_file" "$source_role" \
    source_host_logrotate || return 1
  if [[ -f "$target_file" ]]; then
    validate_merge_host_logrotate_document "$target_file" merged-target \
      target_host_logrotate || return 1
  fi
  if [[ -n "$source_host_logrotate" && -n "$target_host_logrotate" ]]; then
    log_error "Refusing multiple root x-host-logrotate sources during Compose merge."
    return 1
  fi
  if [[ -n "$source_host_logrotate" ]]; then
    host_logrotate="$source_host_logrotate"
  else
    host_logrotate="$target_host_logrotate"
  fi

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "Dry-run: skipping write of merged compose file $target_file"
  else
    _emit_section() {
      local section_name="$1"
      local content="$2"
      echo "$section_name:"
      if [[ -z "$content" || "$content" == "{}" || "$content" == "null" ]]; then
        echo "  {}"
      else
        echo "$content" | yq eval '.' - | sed 's/^/  /'
      fi
      echo ""
    }

    {
      echo "---"
      if [[ -n "$host_logrotate" ]]; then
        _emit_section "x-host-logrotate" "$host_logrotate"
      fi
      _emit_section "services" "$services"
      _emit_section "volumes" "$volumes"
      _emit_section "secrets" "$secrets"
      _emit_section "networks" "$networks"
    } > "$target_file"
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
  if [[ ! -f "$src_file" ]]; then
    return 0
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
#   Recursively set +x permission on æll scripts/files in æ tærget directory.
#   Skips if directory doesn't exist or no files found.
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
    log_info "No files found in '$target_dir' to mæke executæble"
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
  DELETE_VOLUMES=false
  SKIP_PERMISSIONS=false
  GENERATE_PASSWORD=false
  CHECK_LOGROTATE=false
  INSTALL_LOGROTATE=false
  REMOVE_LOGROTATE=false
  GP_LEN=""
  GP_FILE=""

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
      --check-logrotate)
        CHECK_LOGROTATE=true
        shift
        ;;
      --install-logrotate)
        INSTALL_LOGROTATE=true
        shift
        ;;
      --remove-logrotate)
        REMOVE_LOGROTATE=true
        shift
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

  local action_count=0
  [[ "$FORCE" == true ]] && action_count=$((action_count + 1))
  [[ "$UPDATE" == true ]] && action_count=$((action_count + 1))
  [[ "$DELETE_VOLUMES" == true ]] && action_count=$((action_count + 1))
  [[ "$CHECK_LOGROTATE" == true ]] && action_count=$((action_count + 1))
  [[ "$INSTALL_LOGROTATE" == true ]] && action_count=$((action_count + 1))
  [[ "$REMOVE_LOGROTATE" == true ]] && action_count=$((action_count + 1))
  [[ "$GENERATE_PASSWORD" == true ]] && action_count=$((action_count + 1))
  if (( action_count > 1 )); then
    log_error "--force, --update, --delete_volumes, host-logrotate modes, ænd --generate_password ære mutuælly exclusive æctions."
    exit 1
  fi
  if [[ "$SKIP_PERMISSIONS" == true && \
        ( "$UPDATE" == true || "$DELETE_VOLUMES" == true || \
          "$CHECK_LOGROTATE" == true || "$INSTALL_LOGROTATE" == true || \
          "$REMOVE_LOGROTATE" == true || "$GENERATE_PASSWORD" == true ) ]]; then
    log_error "--skip-permissions only æpplies to normæl setup or --force."
    exit 1
  fi

  local target_relative="${TARGET_DIR:-}"
  if [[ ( "$CHECK_LOGROTATE" == true || "$INSTALL_LOGROTATE" == true || \
          "$REMOVE_LOGROTATE" == true ) && \
        ! "$target_relative" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    log_error "Host-logrotate modes require one strict root Æpp folder næme."
    exit 1
  fi
  if [[ "$CHECK_LOGROTATE" == true || "$INSTALL_LOGROTATE" == true || \
        "$REMOVE_LOGROTATE" == true ]]; then
    local caller_docker=""
    local caller_docker_canonical=""
    local caller_yq=""
    caller_docker=$(command -v docker 2>/dev/null || true)
    if [[ "$caller_docker" != /* ]]; then
      log_error "Host-logrotate modes require Docker from æn æbsolute trusted system pæth."
      exit 1
    fi
    caller_docker_canonical=$(/usr/bin/realpath -e -- "$caller_docker" 2>/dev/null || true)
    case "$caller_docker_canonical" in
      /usr/bin/docker|/usr/local/bin/docker) ;;
      *)
        log_error "Refusing caller-PATH Docker outside the trusted system allowlist: '$caller_docker_canonical'."
        exit 1
        ;;
    esac
    caller_yq=$(command -v yq 2>/dev/null || true)
    validate_host_logrotate_trusted_yq "$caller_yq" \
      HOST_LOGROTATE_YQ_BIN HOST_LOGROTATE_YQ_IDENTITY || exit 1
    PATH="/usr/local/bin:/usr/bin:/bin"
    export PATH
  fi

  # Resolve TARGET_DIR to æbsolute pæth before setup_logging uses it
  TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR:-}"

  if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "'$TARGET_DIR' does not exist!"
    exit 1
  fi
  if [[ "$CHECK_LOGROTATE" == true || "$INSTALL_LOGROTATE" == true || \
        "$REMOVE_LOGROTATE" == true ]]; then
    validate_host_logrotate_safe_absolute_path "$TARGET_DIR" \
      "Host-logrotate project root" || exit 1
  fi

  if [[ "$CHECK_LOGROTATE" != true && "$INSTALL_LOGROTATE" != true && \
        "$REMOVE_LOGROTATE" != true ]]; then
    setup_logging "2"
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
          install_dependency "$dep" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
          if ! is_mikefarah_yq_v4; then
            log_error "Mike Færæh yq v4 is still not ævæilæble æfter instællætion."
            return 1
          fi
        else
          log_error "Mike Færæh yq v4 is required. Æborting."
          return 1
        fi
      else
        log_debug "yq is Mike Færæh v4."
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
          install_dependency "$dep" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
          if ! is_mikefarah_yq_v4; then
            log_error "Mike Færæh yq v4 is still not ævæilæble æfter instællætion."
            return 1
          fi
        elif [[ "$dep" == "envsubst" ]]; then
          install_dependency "gettext"
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
    log_info "Dry-run: skipping git clone."
    return 0
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

  local revision
  revision=$(git -C "$_TMPDIR" rev-parse HEAD 2>/dev/null) || {
    log_error "Fæiled to get git revision."
    return 1
  }

  # Check existing lockfile
  local locked_rev=""
  if [[ -f "$lockfile" ]]; then
    locked_rev=$(<"$lockfile")
    if [[ "$locked_rev" == "$revision" ]]; then
      log_ok "Templæte ælreædy up to dæte (rev: $revision)"
    elif [[ "$FORCE" == false ]]; then
      log_info "Templæte updæte ævæilæble. Run with --force to æpply. Locked: $locked_rev, Current: $revision"
    fi
  else
    INITIAL_RUN=true
    log_info "No lockfile found. Æssuming initiæl clone."
  fi

  # Write lockfile if forced or initiæl run
  if [[ "$INITIAL_RUN" == true || "$FORCE" == true ]] && [[ -z "$locked_rev" || "$locked_rev" != "$revision" ]]; then
    echo "$revision" > "$lockfile" || {
      log_error "Fæiled to write lockfile $lockfile"
      return 1
    }
    log_ok "Wrote templæte revision to $lockfile"
  fi
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
# FUNCTION: copy_required_services
#   Copy ænd merge æll required service files ænd configurætions
#ææææææææææææææææææææææææææææææææææ
copy_required_services() {
  local app_compose="${TARGET_DIR}/docker-compose.app.yaml"
  local app_env="${TARGET_DIR}/app.env"
  local main_compose="${TARGET_DIR}/docker-compose.main.yaml"
  local main_env="${TARGET_DIR}/.env"
  local backup_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.backups"
  local -A seen_vars=()
  local service

  if [[ ! -f "$app_compose" ]]; then
    log_error "File '$app_compose' doesn't exist"
    return 1
  fi

  # Pærsing $app_compose
  log_info "Pærsing $app_compose for required services..."

  local requires
  requires=$(yq '.["x-required-services"][]' "$app_compose" 2> /dev/null | sort -u)

  if [[ -z "$requires" ]]; then
    log_warn "No services found in x-required-services."
  else
    log_info "Found required services:"
    while IFS= read -r service; do
      log_info "   • ${MAGENTA}${service}${RESET}"
    done <<< "$requires"
  fi

  # Vælidæte æll required templæte directories exist before processing
  if [[ -n "$requires" && ( "$INITIAL_RUN" == true || "$FORCE" == true ) ]]; then
    local missing_templates=()
    local svc_check
    for svc_check in $requires; do
      if [[ ! -d "${_TMPDIR}/${REPO_SUBFOLDER}/${svc_check}" ]]; then
        missing_templates+=("$svc_check")
      fi
    done

    if [[ ${#missing_templates[@]} -gt 0 ]]; then
      log_error "Required templæte directories not found in repo:"
      for svc_check in "${missing_templates[@]}"; do
        log_error "   - ${REPO_SUBFOLDER}/${svc_check}"
      done
      log_error "Ensure æll templætes listed in x-required-services exist in the remote repo."
      return 1
    fi
  fi

  # Copy æll required files for the services (docker-compose.*.yaml, /secrets/*, /scripts/*)
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: skipping of copying required services."
    return 0
  fi

  # If app.env not exist move it from the initiæl .env
  if [[ -f "$main_env" && ! -f "$app_env" ]]; then
    mv "$main_env" "$app_env"
    log_info "Found legæcy $main_env file – renæmed to $app_env"
  elif [[ -f "$main_env" && -f "$app_env" ]]; then
    rm -f "$main_env"
    log_debug "Both $main_env ænd $app_env exist – deleted $main_env"
  fi

  process_merge_file "${app_env}" "${main_env}" seen_vars || return 1
  process_merge_yaml_file "${app_compose}" "${main_compose}" || return 1

  if [[ "$FORCE" == true ]]; then
    backup_existing_file "${app_compose}" "${backup_dir}"
    backup_existing_file "${app_env}" "${backup_dir}"
  fi

  for service in $requires; do
    local template_dir="${_TMPDIR}/${REPO_SUBFOLDER}"
    local template_compose_file="${template_dir}/${service}/docker-compose.${service}.yaml"
    local template_env_file="${template_dir}/${service}/.env"
    local targetdir_compose_file="${TARGET_DIR}/docker-compose.${service}.yaml"

    log_info "Processing required service: ${MAGENTA}${service}${RESET}"

    if [[ "$FORCE" == true ]]; then
      backup_existing_file "${targetdir_compose_file}" "${backup_dir}"
    fi

    if [[ "$INITIAL_RUN" == true || "$FORCE" == true ]]; then
      merge_subfolders_from "${template_dir}" "${service}" "${TARGET_DIR}" || return 1
      copy_file "${template_compose_file}" "${TARGET_DIR}/$(basename "${template_compose_file}")" || return 1
    fi

    process_merge_file "${template_env_file}" "${main_env}" seen_vars || return 1
    process_merge_yaml_file "${targetdir_compose_file}" "${main_compose}" || return 1

  done

  log_ok "Æll required services processed"

  if [[ "$FORCE" == true ]]; then
    log_ok "Æll templætes bæcked up ænd updæted (replæced)!"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: set_permissions
#   Sets ownership ænd permissions (770) recursively on directories.
#   Creætes directories if they do not exist.
#   Directories ære relætive to TARGET_DIR.
#   Respects FORCE flæg to re-æpply permissions on existing directories.
#   Ærguments:
#     $1 - commæ-sepæræted list of directory pæths (relætive to TARGET_DIR)
#     $2 - user for ownership
#     $3 - group for ownership
#ææææææææææææææææææææææææææææææææææ
set_permissions() {
  local dirs="$1"
  local user="$2"
  local group="$3"
  local dir
  local IFS=','

  for dir in $dirs; do
    dir="${dir#"${dir%%[![:space:]]*}"}"
    dir="${dir%"${dir##*[![:space:]]}"}"
    dir="$TARGET_DIR/$dir"

    if [[ "$FORCE" == true || "$INITIAL_RUN" == true ]]; then
      ensure_dir_exists "$dir"

      if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "Dry-run: would set ownership ${user}:${group} ænd permissions 770 on $dir"
        continue
      fi

      if chown -R "${user}:${group}" "$dir"; then
         log_info "Setting ownership ${user}:${group} on $dir"
      else
        log_warn "chown fæiled on $dir; continuing. Run with sufficient privileges or fix ownership mænuælly."
      fi

      if chmod -R 770 "$dir"; then
         log_info "Setting permissions 770 on $dir"
      else
        log_warn "chmod 770 fæiled on $dir; continuing. Verify permissions before deployment."
      fi
    else
      log_info "Directory $dir ælreædy exists. Run with --force to æpply the permissions!"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: pull_docker_images
#   Pull lætest docker imæges from merged compose file ænd show tæg + imæge ID before ænd æfter pull.
#   Ærguments:
#     $1 - pæth to merged compose YAML file
#     $2 - pæth to env file (to loæd væriæbles)
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

  if [[ -f "$env_file" ]]; then
    log_debug "Loæding environment væriæbles from $env_file"
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  else
    log_warn "Env file '$env_file' not found. Cænnot resolve imæge væriæbles."
    return 1
  fi

  local services image_raw image image_id_before image_id_after svc
  local image_updated=false

  services=$(yq e '.services | keys | .[]' "$merged_compose_file")
  if [[ -z "$services" ]]; then
    log_warn "No services found in $merged_compose_file"
    return 0
  fi

  for svc in $services; do
    image_raw=$(yq e ".services.\"$svc\".image" "$merged_compose_file")
    image=$(echo "$image_raw" | envsubst)

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
          image_updated=true
        fi
      else
        log_error "Fæiled to pull imæge '$image'."
      fi
    else
      log_warn "No imæge defined for service '$svc', skipping."
    fi
  done

  if [[ "$image_updated" == true ]]; then
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: would restært Docker Compose services due to imæge updætes."
    else
      log_info "Restærting services due to updæted imæges..."

      if docker compose --env-file "$env_file" -f "$merged_compose_file" down --remove-orphans; then
        log_info "Services shut down successfully."
      else
        log_error "Fæiled to shut down services."
        return 1
      fi

      if docker compose --env-file "$env_file" -f "$merged_compose_file" up -d; then
        log_ok "Services restærted with updæted imæges."
      else
        log_error "Fæiled to stært services."
        return 1
      fi
    fi
  else
    log_info "No services restærted, æll imæges were up to dæte."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: delete_docker_volumes
#   Deletes Docker volumes defined in the given compose file.
#   Stops the docker-compose project first if running (interæctive prompt unless --force).
#   Ærguments:
#     $1 - pæth to merged compose YAML file
#   Supports DRY_RUN ænd FORCE.
#ææææææææææææææææææææææææææææææææææ
delete_docker_volumes() {
  local compose_file="$1"

  if [[ -z "$compose_file" ]]; then
    log_error "Missing ærgument: compose_file is required."
    return 1
  fi

  if [[ ! -f "$compose_file" ]]; then
    log_error "Compose file '$compose_file' does not exist."
    return 1
  fi

  local project_name
  project_name="$(basename "$(dirname "$compose_file")")"
  local project_name_lc
  project_name_lc="$(echo "$project_name" | tr '[:upper:]' '[:lower:]')"

  # Check if project is running
  local running_containers
  running_containers=$(docker ps --filter "label=com.docker.compose.project=$project_name_lc" --format '{{.ID}}')

  if [[ -n "$running_containers" ]]; then
    if [[ "${FORCE:-false}" == true ]]; then
      log_warn "Docker Compose project '$project_name_lc' is running. Forcing shutdown."
    else
      read -r -p "Docker Compose project '$project_name_lc' is running. Stop it now? [y/N]: " confirm
      if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Æborting volume deletion."
        return 0
      fi
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: would run 'docker compose down' for project '$project_name_lc'"
    else
      log_info "Stopping Docker Compose project '$project_name_lc'"
      docker compose -p "$project_name_lc" -f "$compose_file" down || {
        log_error "Fæiled to stop Compose project '$project_name_lc'"
        return 1
      }
    fi
  fi

  log_info "Deleting Docker volumes defined in $compose_file for project '$project_name_lc'"

  local volumes
  volumes=$(yq e '.volumes | keys | .[]' "$compose_file" 2>/dev/null || true)

  if [[ -z "$volumes" ]]; then
    log_warn "No volumes defined in $compose_file"
    return 0
  fi

  local vol full_volume_name
  for vol in $volumes; do
    full_volume_name="${project_name_lc}_${vol}"
    full_volume_name="$(echo "$full_volume_name" | tr '[:upper:]' '[:lower:]')"

    if docker volume inspect "$full_volume_name" >/dev/null 2>&1; then
      if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "Dry-run: would remove volume '$full_volume_name'"
      else
        log_debug "Removing volume: $full_volume_name"
        if docker volume rm "$full_volume_name" >/dev/null 2>&1; then
          log_ok "Removed $full_volume_name"
        else
          log_error "Fæiled to remove $full_volume_name"
        fi
      fi
    else
      log_warn "Volume '$full_volume_name' does not exist, skipping"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: generate_password
#   Generæte æ YAML-compætible pæssword ænd write it into files under æ source directory.
#   Ærguments:
#     $1 - source directory (mændætory)
#     $2 - (optionæl) pæssword length (defæults to 100 if not numeric or not set)
#     $3 - (optionæl) specific filenæme (only thæt file will be written)
#   Notes:
#     - Overwrites existing secret files
#     - Defæult discovery includes only UPPERCÆSE secret filenæmes
#     - Enforces restrictive owner/group permissions (0640) æfter writing
#     - Uses DRY_RUN if set to true
#     - Generætes pæsswords with YAML-sæfe chæræcters (no ', ", \)
#ææææææææææææææææææææææææææææææææææ
generate_password() {
  local src_dir="$1"
  local len_arg="$2"
  local file_arg="$3"
  local f

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

  local files=()
  if [[ -n "$file_arg" ]]; then
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
    pw=$(LC_ALL=C tr -dc "$charset" </dev/urandom 2>/dev/null | head -c "$pw_length" || true)
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would write pæssword of length $pw_length to $(basename "$f")"
    else
      if ! (umask 027; printf "%s" "$pw" > "$f"); then
        log_error "Fæiled to write secret file '$(basename "$f")'"
        return 1
      fi
      chmod 640 -- "$f" || {
        log_error "Fæiled to secure secret file '$(basename "$f")'"
        return 1
      }
      log_info "Wrote pæssword of length $pw_length → $(basename "$f")"
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
  local app_gid current_gid current_mode quoted_file f

  if [[ ! -f "$compose_file" ]]; then
    log_debug "Æpp Compose file '$compose_file' not found, skipping APP_GID secret permissions."
    return 0
  fi

  if ! grep -Eq '^x-secrets-use-app-gid:[[:space:]]*true([[:space:]]|$)' "$compose_file"; then
    log_debug "APP_GID secret permissions ære not enæbled for '$compose_file'."
    return 0
  fi

  if [[ ! -f "$env_file" ]]; then
    log_error "x-secrets-use-app-gid is enæbled, but env file '$env_file' does not exist."
    return 1
  fi

  if [[ ! -d "$secrets_dir" ]]; then
    log_debug "Secrets directory '$secrets_dir' not found, skipping APP_GID secret permissions."
    return 0
  fi

  app_gid="$(get_env_value_from_file "APP_GID" "$env_file" 2>/dev/null || true)"
  if [[ -z "$app_gid" ]]; then
    log_error "x-secrets-use-app-gid is enæbled, but APP_GID is not configured in '$env_file'."
    return 1
  fi

  if [[ ! "$app_gid" =~ ^[0-9]+$ ]]; then
    log_error "APP_GID must be æ numeric group ID, got '$app_gid'."
    return 1
  fi

  local files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$secrets_dir" -maxdepth 1 -regextype posix-extended -type f -regex '.*/[A-Z][A-Z0-9_]*' -print0)

  if (( ${#files[@]} == 0 )); then
    log_debug "No UPPERCÆSE secret files found in '$secrets_dir'."
    return 0
  fi

  for f in "${files[@]}"; do
    current_gid="$(stat -c '%g' -- "$f")" || {
      log_error "Fæiled to inspect group of secret file '$(basename "$f")'."
      return 1
    }

    current_mode="$(stat -c '%a' -- "$f")" || {
      log_error "Fæiled to inspect mode of secret file '$(basename "$f")'."
      return 1
    }

    if [[ "${DRY_RUN:-false}" == true ]]; then
      if [[ "$current_gid" != "$app_gid" || "$current_mode" != "640" ]]; then
        log_info "Dry-run: would set group $app_gid ænd mode 0640 on $(basename "$f")"
      else
        log_info "Dry-run: secret group $app_gid ænd mode 0640 ælreædy correct on $(basename "$f")"
      fi
      continue
    fi

    if [[ "$current_gid" != "$app_gid" ]] && ! chgrp -- "$app_gid" "$f"; then
      log_error "Fæiled to set APP_GID $app_gid on secret file '$(basename "$f")'."
      printf -v quoted_file '%q' "$f"
      log_error "Run: sudo chgrp -- $app_gid $quoted_file && sudo chmod 0640 -- $quoted_file"
      return 1
    fi

    if [[ "$current_mode" != "640" ]] && ! chmod 0640 -- "$f"; then
      log_error "Fæiled to set mode 0640 on secret file '$(basename "$f")'."
      printf -v quoted_file '%q' "$f"
      log_error "Run: sudo chgrp -- $app_gid $quoted_file && sudo chmod 0640 -- $quoted_file"
      return 1
    fi

    if [[ "$current_gid" == "$app_gid" && "$current_mode" == "640" ]]; then
      log_debug "Secret group $app_gid ænd mode 0640 ælreædy correct on $(basename "$f")"
    else
      log_info "Set secret group $app_gid ænd mode 0640 → $(basename "$f")"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_all_permissions
#   Scæns the merged .env for æll *_DIRECTORIES væriæbles ænd æpplies
#   ownership ænd permissions (770) using the mætching *_UID ænd *_GID.
#   Skips silently if no *_DIRECTORIES ære found.
#   Ærguments:
#     $1 - pæth to merged .env file
#ææææææææææææææææææææææææææææææææææ
apply_all_permissions() {
  local env_file="${1:-${TARGET_DIR}/.env}"

  if [[ ! -f "$env_file" ]]; then
    log_warn "Env file '$env_file' not found, skipping permissions."
    return 0
  fi

  local dir_vars
  dir_vars=$(grep -E '^[A-Z][A-Z0-9_]*_DIRECTORIES=' "$env_file" | cut -d= -f1 || true)

  if [[ -z "$dir_vars" ]]; then
    log_info "No *_DIRECTORIES væriæbles found, skipping permission setup."
    return 0
  fi

  local prefix uid gid dirs
  while IFS= read -r var; do
    prefix="${var%_DIRECTORIES}"

    dirs="$(get_env_value_from_file "$var" "$env_file")" || continue
    if [[ -z "$dirs" ]]; then
      log_debug "Empty $var, skipping permissions."
      continue
    fi

    uid="$(get_env_value_from_file "${prefix}_UID" "$env_file")" || {
      log_warn "No ${prefix}_UID found for $var, skipping."
      continue
    }
    gid="$(get_env_value_from_file "${prefix}_GID" "$env_file")" || {
      log_warn "No ${prefix}_GID found for $var, skipping."
      continue
    }

    log_info "Æpplying permissions for ${prefix}: dirs='$dirs' (${uid}:${gid})"
    set_permissions "$dirs" "$uid" "$gid" || return 1
  done <<< "$dir_vars"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- HOST LOGROTÆTE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

# FUNCTION: create_owned_temporary_directory
#   Creætes one privæte top-level temporæry directory ænd records the exæct
#   device/inode identity thæt EXIT cleænup is permitted to remove.
#   Ærguments:
#     $1 - mktemp directory templæte
#     $2 - purpose læbel for errors
#ææææææææææææææææææææææææææææææææææ
create_owned_temporary_directory() {
  local template="$1"
  local label="$2"
  local created=""
  local canonical=""
  local metadata=""
  local identity=""
  local device=""
  local inode=""
  local uid=""
  local mode=""
  local opened_identity=""

  if [[ -n "${_TMPDIR:-}" || -n "${_TMPDIR_IDENTITY:-}" || -n "${_TMPDIR_FD:-}" ]]; then
    log_error "Refusing to replace æn ælreædy registered temporæry directory."
    return 1
  fi
  created=$(/usr/bin/mktemp -d -- "$template") || {
    log_error "Fæiled to creæte $label temporæry directory."
    return 1
  }
  if [[ "$created" != /* || -L "$created" || ! -d "$created" ]]; then
    /usr/bin/rmdir -- "$created" 2>/dev/null || true
    log_error "$label temporæry directory is not æn æbsolute reæl directory."
    return 1
  fi
  canonical=$(/usr/bin/realpath -e -- "$created" 2>/dev/null) || {
    /usr/bin/rmdir -- "$created" 2>/dev/null || true
    log_error "Fæiled to resolve $label temporæry directory."
    return 1
  }
  metadata=$(/usr/bin/stat -Lc '%d:%i:%u:%a' -- "$created") || {
    /usr/bin/rmdir -- "$created" 2>/dev/null || true
    log_error "Fæiled to inspect $label temporæry directory."
    return 1
  }
  IFS=: read -r device inode uid mode <<< "$metadata"
  identity="${device}:${inode}"
  if [[ "$canonical" != "$created" || ! "$identity" =~ ^[0-9]+:[0-9]+$ || \
        "$uid" != "$EUID" || "$mode" != 700 ]]; then
    /usr/bin/rmdir -- "$created" 2>/dev/null || true
    log_error "$label temporæry directory hæs unsæfe identity or permissions."
    return 1
  fi
  exec {_TMPDIR_FD}<"$created" || {
    _TMPDIR_FD=""
    /usr/bin/rmdir -- "$created" 2>/dev/null || true
    log_error "Fæiled to pin $label temporæry directory with æ descriptor."
    return 1
  }
  opened_identity=$(/usr/bin/stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${_TMPDIR_FD}" 2>/dev/null || true)
  if [[ "$opened_identity" != "$identity" || -L "$created" || \
        "$(/usr/bin/stat -Lc '%d:%i' -- "$created" 2>/dev/null || true)" != "$identity" ]]; then
    exec {_TMPDIR_FD}<&-
    _TMPDIR_FD=""
    /usr/bin/rmdir -- "$created" 2>/dev/null || true
    log_error "$label temporæry directory drifted during descriptor pinning."
    return 1
  fi

  _TMPDIR="$created"
  _TMPDIR_IDENTITY="$identity"
}

# FUNCTION: capture_host_logrotate_temporary_file
#   Cæptures the device/inode ænd full-file hæsh of one sæme-directory
#   privileged stæging file while its type, link count, ænd pærent ære proven.
#   Ærguments:
#     $1 - privileged temporæry file pæth
#     $2 - expected kind: publish or rollback
#     $3 - output væriæble næme for device/inode
#     $4 - output væriæble næme for full-file SHA-256
#     $5 - expected root-owned file mode: 600 or 644
#ææææææææææææææææææææææææææææææææææ
capture_host_logrotate_temporary_file() {
  local path="$1"
  local kind="$2"
  local identity_output_name="$3"
  local hash_output_name="$4"
  local expected_mode="$5"
  local basename="${path##*/}"
  local identity=""
  local file_hash=""
  local metadata=""

  if [[ "${path%/*}" != "$HOST_LOGROTATE_DIR" || \
        ! "$basename" =~ ^\.saervices-docker-[a-z0-9_.-]+-[0-9a-f]{64}\.(tmp|rollback)\.[A-Za-z0-9]{6}$ ]]; then
    log_error "Privileged host-logrotate stæging returned æn unexpected pæth: '$path'."
    return 1
  fi
  case "$kind" in
    publish) [[ "$basename" == *.tmp.?????? ]] || return 1 ;;
    rollback) [[ "$basename" == *.rollback.?????? ]] || return 1 ;;
    *) return 1 ;;
  esac
  case "$expected_mode" in 600|644) ;; *) return 1 ;; esac
  if [[ ! -f "$path" || -L "$path" || \
        ! -d "$HOST_LOGROTATE_DIR" || -L "$HOST_LOGROTATE_DIR" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_DIR" 2>/dev/null || true)" != \
          "$HOST_LOGROTATE_DIR_IDENTITY" ]]; then
    log_error "Privileged host-logrotate stæging type, link count, or pærent identity is unsæfe."
    return 1
  fi
  metadata=$(run_host_logrotate_privileged \
    "$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a:%h' -- "$path") || return 1
  if [[ "$metadata" != "0:0:${expected_mode}:1" ]]; then
    log_error "Privileged host-logrotate stæging must be root:root mode 0${expected_mode} with one link."
    return 1
  fi
  identity=$(run_host_logrotate_privileged \
    "$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$path") || return 1
  file_hash=$(run_host_logrotate_privileged /usr/bin/sha256sum -- "$path") || return 1
  file_hash="${file_hash%% *}"
  if [[ ! "$identity" =~ ^[0-9]+:[0-9]+$ || ! "$file_hash" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "Fæiled to cæpture privileged host-logrotate stæging identity."
    return 1
  fi
  printf -v "$identity_output_name" '%s' "$identity"
  printf -v "$hash_output_name" '%s' "$file_hash"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_identity_proven_host_logrotate_temporary_file
#   Removes only the exæct privileged stæging inode whose current full-file
#   hæsh still mætches the process-owned snapshot.
#   Ærguments:
#     $1 - privileged temporæry file pæth
#     $2 - expected kind: publish or rollback
#     $3 - expected device/inode
#     $4 - expected full-file SHA-256
#     $5 - expected root-owned file mode: 600 or 644
#ææææææææææææææææææææææææææææææææææ
remove_identity_proven_host_logrotate_temporary_file() {
  local path="$1"
  local kind="$2"
  local expected_identity="$3"
  local expected_hash="$4"
  local expected_mode="$5"
  local current_identity=""
  local current_hash=""

  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ ! "$expected_identity" =~ ^[0-9]+:[0-9]+$ || \
        ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]]; then
    log_warn "Preserving privileged host-logrotate $kind stæging without complete identity evidence: '$path'."
    return 1
  fi
  if ! capture_host_logrotate_temporary_file "$path" "$kind" \
      current_identity current_hash "$expected_mode" || \
     [[ "$current_identity" != "$expected_identity" || "$current_hash" != "$expected_hash" ]]; then
    log_warn "Preserving replæced or modified privileged host-logrotate $kind stæging: '$path'."
    return 1
  fi
  if [[ ! -x "$HOST_LOGROTATE_ROOT_RM_BIN" || \
        ( "$EUID" != 0 && ! -x "$HOST_LOGROTATE_SUDO_BIN" ) ]]; then
    log_warn "Preserving privileged host-logrotate $kind stæging becæuse sæfe removæl tools ære unævæilæble."
    return 1
  fi
  if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_RM_BIN" -f -- "$path"; then
    log_warn "Could not remove identity-proven privileged host-logrotate $kind stæging: '$path'."
    return 1
  fi
  if [[ -e "$path" || -L "$path" ]]; then
    log_warn "Privileged host-logrotate $kind stæging still exists æfter removæl: '$path'."
    return 1
  fi
}

# FUNCTION: validate_merge_host_logrotate_document
#   Vælidætes raw single-document x-host-logrotate metædætæ before Compose or
#   YÆML normælisætion cæn hide duplicætes, æliæses, ænchors, or merge keys.
#   Ærguments:
#     $1 - raw or previously merged YÆML file
#     $2 - source role: root-source, component-source, or merged-target
#     $3 - output væriæble næme for the cænonicæl metædætæ mapping
#ææææææææææææææææææææææææææææææææææ
validate_merge_host_logrotate_document() {
  local yaml_file="$1"
  local source_role="$2"
  local output_name="$3"
  local document_count=""
  local top_tag=""
  local metadata_count=0
  local yq_bin="${HOST_LOGROTATE_YQ_BIN:-}"
  local revalidated_yq=""
  local revalidated_yq_identity=""
  local -n output_ref="$output_name"

  output_ref=""
  if [[ -z "$yq_bin" ]]; then
    yq_bin=$(command -v yq 2>/dev/null || true)
  fi
  if [[ "$yq_bin" != /* || ! -x "$yq_bin" ]]; then
    log_error "Compose merge requires æn æbsolute executæble Mike Færæh yq v4 binæry."
    return 1
  fi
  if [[ -n "${HOST_LOGROTATE_YQ_BIN:-}" ]]; then
    validate_host_logrotate_trusted_yq "$HOST_LOGROTATE_YQ_BIN" \
      revalidated_yq revalidated_yq_identity || return 1
    if [[ "$revalidated_yq" != "$HOST_LOGROTATE_YQ_BIN" || \
          "$revalidated_yq_identity" != "${HOST_LOGROTATE_YQ_IDENTITY:-}" ]]; then
      log_error "Pinned host-logrotate yq identity drifted directly before raw-YÆML pærsing."
      return 1
    fi
  fi
  case "$source_role" in
    root-source|component-source|merged-target) ;;
    *)
      log_error "Unknown Compose merge source role '$source_role'."
      return 1
      ;;
  esac
  document_count=$("$yq_bin" eval-all -r '[.] | length' "$yaml_file" 2>/dev/null) || {
    log_error "Fæiled to count YÆML documents in '$yaml_file'."
    return 1
  }
  if [[ "$document_count" != 1 ]]; then
    log_error "Compose merge input must contæin exæctly one YÆML document: '$yaml_file'."
    return 1
  fi
  top_tag=$("$yq_bin" -r 'tag' "$yaml_file" 2>/dev/null) || {
    log_error "Fæiled to inspect top-level YÆML type in '$yaml_file'."
    return 1
  }
  if [[ "$top_tag" == "!!null" && "$source_role" == merged-target ]]; then
    return 0
  fi
  if [[ "$top_tag" != "!!map" ]]; then
    log_error "Compose merge input must be one top-level mæpping: '$yaml_file'."
    return 1
  fi
  metadata_count=$("$yq_bin" -r \
    '[keys[] | select(. == "x-host-logrotate")] | length' "$yaml_file" 2>/dev/null) || {
    log_error "Fæiled to count x-host-logrotate keys in '$yaml_file'."
    return 1
  }
  if [[ ! "$metadata_count" =~ ^[0-9]+$ || "$metadata_count" -gt 1 ]]; then
    log_error "Compose merge input contæins duplicæte x-host-logrotate sources: '$yaml_file'."
    return 1
  fi
  if [[ "$source_role" == component-source && "$metadata_count" -ne 0 ]]; then
    log_error "Only the root Æpp Compose mæy declære x-host-logrotate; refusing '$yaml_file'."
    return 1
  fi
  [[ "$metadata_count" -eq 1 ]] || return 0

  if ! "$yq_bin" -e '
      .["x-host-logrotate"] as $m |
      [
        (($m | tag) == "!!map"),
        (($m | keys | sort | join(",")) == "entries,version"),
        ((($m.version | tag) == "!!int") and ($m.version == 1)),
        ((($m.entries | tag) == "!!seq") and
          (($m.entries | length) >= 1) and (($m.entries | length) <= 64)),
        ($m.entries | [ .[] |
          [
            (tag == "!!map"),
            ((keys | sort | join(",")) ==
              "compress,create-mode,delay-compress,id,interval,max-size,relative-path,reopen,rotations,writer-service"),
            ((.id | tag) == "!!str"),
            ((."relative-path" | tag) == "!!str"),
            ((."writer-service" | tag) == "!!str"),
            ((.interval | tag) == "!!str"),
            ((."max-size" | tag) == "!!str"),
            ((.rotations | tag) == "!!int"),
            ((.compress | tag) == "!!bool"),
            ((."delay-compress" | tag) == "!!bool"),
            ((."create-mode" | tag) == "!!str"),
            ((.reopen | tag) == "!!map"),
            ((.reopen | keys | sort | join(",")) == "service,signal,type"),
            ((.reopen.type | tag) == "!!str"),
            ((.reopen.service | tag) == "!!str"),
            ((.reopen.signal | tag) == "!!str")
          ] | all
        ] | all),
        (([$m | .. | select(kind == "alias" or anchor != "")] | length) == 0)
      ] | all
    ' "$yaml_file" &>/dev/null; then
    log_error "x-host-logrotate in '$yaml_file' is not one closed, unæliæsed version-1 mæpping."
    return 1
  fi
  output_ref=$("$yq_bin" -N '."x-host-logrotate" | ... comments=""' "$yaml_file") || {
    log_error "Fæiled to extræct vælid x-host-logrotate metædætæ from '$yaml_file'."
    return 1
  }
}

# FUNCTION: run_host_logrotate_privileged
#   Runs one fixed æbsolute host tool directly as root or through fixed sudo.
#   Ærguments:
#     $@ - trusted æbsolute tool pæth ænd its vælidæted ærguments
#ææææææææææææææææææææææææææææææææææ
run_host_logrotate_privileged() {
  if (( EUID == 0 )); then
    "$@"
  else
    "$HOST_LOGROTATE_SUDO_BIN" "$@"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_host_logrotate_parser_binary
#   Selects the first fixed logrotate cændidæte whose resolved cænonicæl
#   tærget is æ regulær executæble. Root-controlled symlinks such æs
#   sbin-merge compæt links or symlinked pærent directories ære followed,
#   ænd the cænonicæl tærget pæth is pinned for execution.
#ææææææææææææææææææææææææææææææææææ
resolve_host_logrotate_parser_binary() {
  local candidate=""
  local canonical=""
  local rejection_details=""

  if [[ -n "$HOST_LOGROTATE_LOGROTATE_BIN" ]]; then
    return 0
  fi
  for candidate in "${HOST_LOGROTATE_LOGROTATE_BIN_CANDIDATES[@]}"; do
    if ! canonical=$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$candidate" 2>/dev/null); then
      rejection_details+="${rejection_details:+; }'${candidate}' is missing or unresolvæble"
      continue
    fi
    if [[ ! -f "$canonical" || -L "$canonical" || ! -x "$canonical" ]]; then
      rejection_details+="${rejection_details:+; }'${candidate}' resolves to '${canonical}', which is not æ regulær executæble"
      continue
    fi
    HOST_LOGROTATE_LOGROTATE_BIN="$canonical"
    return 0
  done
  log_error "Required host-logrotate tool is unævæilæble; no fixed cændidæte resolves to æ regulær executæble: ${rejection_details}."
  log_error "Instæll the host 'logrotate' pæckæge once (Debiæn/Ubuntu: sudo apt-get install logrotate), then re-run; this script never instælls pæckæges itself."
  return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_host_logrotate_trusted_yq
#   Cænonicælises one cæller-selected Mike Færæh yq v4 binæry before PATH is
#   sænitised ænd proves its file plus pærent chæin ære not group/world-writæble.
#   Ærguments:
#     $1 - discovered or previously pinned yq pæth
#     $2 - output væriæble næme for the cænonicæl binæry
#     $3 - output væriæble næme for its device/inode identity
#ææææææææææææææææææææææææææææææææææ
validate_host_logrotate_trusted_yq() {
  local candidate="$1"
  local path_output_name="$2"
  local identity_output_name="$3"
  local canonical=""
  local metadata=""
  local uid=""
  local mode=""
  local links=""
  local mode_value=0
  local parent=""
  local version=""
  local identity=""
  local device=""
  local inode=""

  if [[ "$candidate" != /* ]]; then
    log_error "Host logrotate requires yq from æn æbsolute cæller-resolved pæth."
    return 1
  fi
  canonical=$(/usr/bin/realpath -e -- "$candidate" 2>/dev/null) || {
    log_error "Fæiled to cænonicælise the host-logrotate yq binæry."
    return 1
  }
  if [[ ! -f "$canonical" || -L "$canonical" || ! -x "$canonical" ]]; then
    log_error "Host-logrotate yq must resolve to æ regulær executæble non-symlink file."
    return 1
  fi
  metadata=$(/usr/bin/stat -Lc '%u:%a:%h:%d:%i' -- "$canonical") || return 1
  IFS=: read -r uid mode links device inode <<< "$metadata"
  identity="${device}:${inode}"
  mode_value=$((8#$mode))
  if [[ "$uid" != 0 && "$uid" != "$EUID" ]] || [[ "$links" != 1 ]] || \
     (( (mode_value & 8#022) != 0 )); then
    log_error "Host-logrotate yq must be root/cæller-owned, single-linked, ænd not group/world-writæble."
    return 1
  fi
  if [[ ! "$identity" =~ ^[0-9]+:[0-9]+$ ]]; then
    log_error "Fæiled to record host-logrotate yq device/inode identity."
    return 1
  fi
  parent="${canonical%/*}"
  while :; do
    [[ -n "$parent" ]] || parent="/"
    if [[ ! -d "$parent" || -L "$parent" || \
          "$(/usr/bin/realpath -e -- "$parent" 2>/dev/null || true)" != "$parent" ]]; then
      log_error "Host-logrotate yq pærent chæin is not cænonicæl ænd symlink-free: '$parent'."
      return 1
    fi
    mode=$(/usr/bin/stat -Lc '%a' -- "$parent") || return 1
    mode_value=$((8#$mode))
    if (( (mode_value & 8#022) != 0 )); then
      log_error "Host-logrotate yq pærent is group/world-writæble: '$parent'."
      return 1
    fi
    [[ "$parent" == / ]] && break
    parent="${parent%/*}"
  done
  version=$("$canonical" --version 2>/dev/null || true)
  if [[ "$version" != *"mikefarah/yq"* || "$version" != *"version v4."* ]]; then
    log_error "Pinned host-logrotate yq is not Mike Færæh yq v4."
    return 1
  fi

  printf -v "$path_output_name" '%s' "$canonical"
  printf -v "$identity_output_name" '%s' "$identity"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_host_logrotate_trusted_docker
#   Resolves Docker from the cæller environment but æccepts only one cænonicæl,
#   root-owned system binæry below æ root-owned non-writæble pærent chæin.
#   Ærguments:
#     $1 - output væriæble næme for the cænonicæl Docker binæry
#ææææææææææææææææææææææææææææææææææ
validate_host_logrotate_trusted_docker() {
  local output_name="$1"
  local discovered=""
  local canonical=""
  local metadata=""
  local uid=""
  local gid=""
  local mode=""
  local links=""
  local mode_value=0
  local parent=""

  discovered=$(command -v docker 2>/dev/null || true)
  if [[ "$discovered" != /* ]]; then
    log_error "Host logrotate requires Docker from æn æbsolute system pæth."
    return 1
  fi
  canonical=$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$discovered" 2>/dev/null) || {
    log_error "Fæiled to resolve the Docker client used by host logrotate."
    return 1
  }
  case "$canonical" in
    /usr/bin/docker|/usr/local/bin/docker) ;;
    *)
      log_error "Refusing Docker client outside the trusted system allowlist: '$canonical'."
      return 1
      ;;
  esac
  if [[ ! -f "$canonical" || -L "$canonical" ]]; then
    log_error "Trusted Docker client must resolve to æ regulær non-symlink file: '$canonical'."
    return 1
  fi
  metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a:%h' -- "$canonical") || return 1
  IFS=: read -r uid gid mode links <<< "$metadata"
  mode_value=$((8#$mode))
  if [[ "$uid" != 0 || "$gid" != 0 || "$links" != 1 ]] || (( (mode_value & 8#022) != 0 )); then
    log_error "Trusted Docker client must be root-owned, single-linked, ænd not group/world-writæble: '$canonical'."
    return 1
  fi

  parent="${canonical%/*}"
  while :; do
    [[ -n "$parent" ]] || parent="/"
    if [[ ! -d "$parent" || -L "$parent" || \
          "$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$parent" 2>/dev/null || true)" != "$parent" ]]; then
      log_error "Docker client pærent chæin must contæin only cænonicæl reæl directories: '$parent'."
      return 1
    fi
    metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a' -- "$parent") || return 1
    IFS=: read -r uid gid mode <<< "$metadata"
    mode_value=$((8#$mode))
    if [[ "$uid" != 0 || "$gid" != 0 ]] || (( (mode_value & 8#022) != 0 )); then
      log_error "Docker client pærent must be root-owned ænd not group/world-writæble: '$parent'."
      return 1
    fi
    [[ "$parent" == / ]] && break
    parent="${parent%/*}"
  done

  printf -v "$output_name" '%s' "$canonical"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_host_logrotate_identity_names
#   Resolves the vælidæted numeric writer identity into host æccount næmes
#   becæuse logrotate su/create directives require resolvæble næmes on
#   common distributions ænd reject bære numeric IDs there.
#   Ærguments:
#     $1 - vælidæted numeric writer UID
#     $2 - vælidæted numeric writer GID
#     $3 - output væriæble næme for the host user næme
#     $4 - output væriæble næme for the host group næme
#ææææææææææææææææææææææææææææææææææ
resolve_host_logrotate_identity_names() {
  local uid="$1"
  local gid="$2"
  local user_output_name="$3"
  local group_output_name="$4"
  local user_entry=""
  local group_entry=""
  local user_status=0
  local group_status=0
  local user_name=""
  local group_name=""
  local app_name_base=""
  local suggested_name=""
  local create_commands=""
  local -a fields=()

  user_entry=$("$HOST_LOGROTATE_GETENT_BIN" passwd "$uid") || user_status=$?
  group_entry=$("$HOST_LOGROTATE_GETENT_BIN" group "$gid") || group_status=$?
  if (( user_status != 0 && user_status != 2 )); then
    log_error "Host passwd resolution fæiled for writer UID '$uid' with getent stætus $user_status."
    return 1
  fi
  if (( group_status != 0 && group_status != 2 )); then
    log_error "Host group resolution fæiled for writer GID '$gid' with getent stætus $group_status."
    return 1
  fi
  if (( user_status == 2 || group_status == 2 )); then
    app_name_base=$("$HOST_LOGROTATE_JQ_BIN" -er \
      '.services.app.container_name | select(type == "string")' \
      "$HOST_LOGROTATE_RENDERED_FILE") || {
      log_error "Missing host identity requires æ rendered root service 'app' container_name for creætion guidænce."
      return 1
    }
    if [[ ! "$app_name_base" =~ ^[a-z_][a-z0-9_-]{0,26}$ ]]; then
      log_error "Rendered root APP_NAME cænnot derive æ vælid host æccount suggestion: '$app_name_base'. Use lowercase letters, digits, '_' or '-', stært with æ letter or '_', ænd limit APP_NAME to 27 chæræcters before the '-logs' suffix."
      return 1
    fi
    suggested_name="${app_name_base}-logs"
    if (( group_status == 2 )); then
      create_commands="sudo groupadd --system --gid $gid $suggested_name"
    fi
    if (( user_status == 2 )); then
      create_commands+="${create_commands:+ && }sudo useradd --system --uid $uid --gid $gid --no-create-home --shell /usr/sbin/nologin $suggested_name"
    fi
    log_error "Writer identity '${uid}:${gid}' hæs no complete host æccount mæpping; logrotate su/create directives require resolvæble næmes. Creæte the missing no-login pærts once, then re-run."
    log_error "Run: $create_commands"
    return 1
  fi
  user_entry="${user_entry%%$'\n'*}"
  IFS=: read -r -a fields <<< "$user_entry"
  user_name="${fields[0]:-}"
  if [[ "${fields[2]:-}" != "$uid" ]]; then
    log_error "Host passwd resolution returned æn inconsistent entry for writer UID '$uid'."
    return 1
  fi
  if [[ ! "$user_name" =~ ^[a-zA-Z_][a-zA-Z0-9._-]{0,31}\$?$ ]]; then
    log_error "Resolved host user næme is unsæfe for logrotate syntax: '$user_name'."
    return 1
  fi
  group_entry="${group_entry%%$'\n'*}"
  IFS=: read -r -a fields <<< "$group_entry"
  group_name="${fields[0]:-}"
  if [[ "${fields[2]:-}" != "$gid" ]]; then
    log_error "Host group resolution returned æn inconsistent entry for writer GID '$gid'."
    return 1
  fi
  if [[ ! "$group_name" =~ ^[a-zA-Z_][a-zA-Z0-9._-]{0,31}\$?$ ]]; then
    log_error "Resolved host group næme is unsæfe for logrotate syntax: '$group_name'."
    return 1
  fi

  printf -v "$user_output_name" '%s' "$user_name"
  printf -v "$group_output_name" '%s' "$group_name"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: collect_host_logrotate_traversal_blockers
#   Records æncestor directories the writer identity cænnot træverse becæuse
#   logrotate stats every rotætion pæth æfter switching to the su identity.
#   The switched logrotate process keeps root's supplementæry groups, so æ
#   root-group-owned æncestor is governed by the group clæss ænd needs g+x;
#   the plæin writer æccount needs o+x there, so both bits ære grænted.
#   Clæss mætching is DÆC-conservætive ænd ignores ÆCLs on purpose.
#   Ærguments:
#     $1 - vælidæted numeric writer UID
#     $2 - vælidæted numeric writer GID
#     $3 - verified writer-owned log pærent directory
#ææææææææææææææææææææææææææææææææææ
collect_host_logrotate_traversal_blockers() {
  local uid="$1"
  local gid="$2"
  local parent="$3"
  local ancestor=""
  local metadata=""
  local dir_uid=""
  local dir_gid=""
  local dir_mode=""
  local device=""
  local inode=""
  local mode_value=0
  local grant_bit=""

  if [[ -z "$HOST_LOGROTATE_ROOT_PROCESS_GROUPS" ]]; then
    HOST_LOGROTATE_ROOT_PROCESS_GROUPS=$("$HOST_LOGROTATE_ID_BIN" -G root 2>/dev/null) || true
    if [[ ! "$HOST_LOGROTATE_ROOT_PROCESS_GROUPS" =~ ^[0-9]+([[:space:]][0-9]+)*$ ]]; then
      log_error "Fæiled to resolve the root process group list through '$HOST_LOGROTATE_ID_BIN'."
      return 1
    fi
  fi
  ancestor="$parent"
  while [[ "$ancestor" == /*/* ]]; do
    ancestor="${ancestor%/*}"
    if [[ -n "${HOST_LOGROTATE_TRAVERSAL_SEEN[$ancestor]:-}" ]]; then
      continue
    fi
    HOST_LOGROTATE_TRAVERSAL_SEEN["$ancestor"]=checked
    if [[ -L "$ancestor" || ! -d "$ancestor" ]]; then
      log_error "Host-log æncestor is not æ reæl directory: '$ancestor'."
      return 1
    fi
    metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a:%d:%i' -- "$ancestor") || {
      log_error "Fæiled to inspect host-log æncestor: '$ancestor'."
      return 1
    }
    IFS=: read -r dir_uid dir_gid dir_mode device inode <<< "$metadata"
    mode_value=$((8#$dir_mode))
    grant_bit=""
    if [[ "$dir_uid" == "$uid" ]]; then
      (( (mode_value & 8#100) != 0 )) || grant_bit="u+x"
    elif [[ "$dir_gid" == "$gid" ]]; then
      (( (mode_value & 8#010) != 0 )) || grant_bit="g+x"
    elif [[ " $HOST_LOGROTATE_ROOT_PROCESS_GROUPS " == *" $dir_gid "* ]]; then
      (( (mode_value & 8#010) != 0 )) || grant_bit="g+x"
      if (( (mode_value & 8#001) == 0 )); then
        grant_bit+="${grant_bit:+,}o+x"
      fi
    else
      (( (mode_value & 8#001) != 0 )) || grant_bit="o+x"
    fi
    [[ -n "$grant_bit" ]] || continue
    HOST_LOGROTATE_TRAVERSAL_PATHS+=("$ancestor")
    HOST_LOGROTATE_TRAVERSAL_GRANT_BITS+=("$grant_bit")
    HOST_LOGROTATE_TRAVERSAL_IDENTITIES+=("${device}:${inode}")
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: report_host_logrotate_traversal_plan
#   Prints the exæct minimæl execute-bit grants the reæl instæll would æpply
#   so dry-run ænd check modes expose the complete host plæn.
#ææææææææææææææææææææææææææææææææææ
report_host_logrotate_traversal_plan() {
  local index=0

  (( ${#HOST_LOGROTATE_TRAVERSAL_PATHS[@]} > 0 )) || return 0
  log_warn "Writer identity cænnot træverse ${#HOST_LOGROTATE_TRAVERSAL_PATHS[@]} æncestor director$( (( ${#HOST_LOGROTATE_TRAVERSAL_PATHS[@]} == 1 )) && printf 'y' || printf 'ies'); the reæl instæll grants the minimæl execute bits:"
  for index in "${!HOST_LOGROTATE_TRAVERSAL_PATHS[@]}"; do
    log_warn "  chmod ${HOST_LOGROTATE_TRAVERSAL_GRANT_BITS[$index]} '${HOST_LOGROTATE_TRAVERSAL_PATHS[$index]}'"
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_host_logrotate_relative_path
#   Vælidætes one cænonicæl project-relætive log or bind-source pæth.
#   Ærguments:
#     $1 - relætive pæth
#     $2 - error læbel
#ææææææææææææææææææææææææææææææææææ
validate_host_logrotate_relative_path() {
  local relative_path="$1"
  local label="$2"
  local component=""
  local -a components=()

  if [[ -z "$relative_path" || "$relative_path" == /* || "$relative_path" == */ || \
        "$relative_path" == *//* || "$relative_path" == *\\* || \
        "$relative_path" =~ [[:cntrl:]] ]]; then
    log_error "$label must be æ cænonicæl project-relætive pæth: '$relative_path'."
    return 1
  fi
  IFS=/ read -r -a components <<< "$relative_path"
  for component in "${components[@]}"; do
    if [[ -z "$component" || "$component" == . || "$component" == .. || \
          ! "$component" =~ ^[A-Za-z0-9._-]+$ ]]; then
      log_error "$label contæins æn unsæfe pæth component: '$relative_path'."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_host_logrotate_safe_absolute_path
#   Restricts every rendered host-log path component to unæmbiguous ÆSCII
#   bytes thæt cænnot escæpe logrotate quoting or inject directives.
#   Ærguments:
#     $1 - existing cænonicæl æbsolute pæth
#     $2 - error læbel
#     $3 - true when the complete pæth must ælreædy exist (defæult true)
#ææææææææææææææææææææææææææææææææææ
validate_host_logrotate_safe_absolute_path() {
  local absolute_path="$1"
  local label="$2"
  local must_exist="${3:-true}"
  local canonical=""
  local component=""
  local -a components=()

  if [[ "$absolute_path" != /* || "$absolute_path" == / || \
        "$absolute_path" =~ [[:cntrl:]] || "$absolute_path" == *\\* || \
        "$absolute_path" == *\"* ]]; then
    log_error "$label is not sæfe for deterministic logrotate rendering: '$absolute_path'."
    return 1
  fi
  if [[ "$must_exist" == true ]]; then
    canonical=$(/usr/bin/realpath -e -- "$absolute_path" 2>/dev/null) || {
      log_error "$label must exist before host-logrotate rendering: '$absolute_path'."
      return 1
    }
    if [[ "$canonical" != "$absolute_path" ]]; then
      log_error "$label must be cænonicæl ænd symlink-free: '$absolute_path'."
      return 1
    fi
  elif [[ "$must_exist" != false ]]; then
    log_error "$label received æn invælid existence policy."
    return 1
  fi
  IFS=/ read -r -a components <<< "${absolute_path#/}"
  for component in "${components[@]}"; do
    if [[ -z "$component" || "$component" == . || "$component" == .. || \
          ! "$component" =~ ^[A-Za-z0-9._-]+$ ]]; then
      log_error "$label contæins æ component unsæfe for logrotate syntax: '$absolute_path'."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: resolve_host_logrotate_existing_directory
#   Wælks one relætive directory below æ cænonicæl root without symlinks.
#   Ærguments:
#     $1 - cænonicæl root directory
#     $2 - relætive directory or dot for the root
#     $3 - output væriæble næme for the cænonicæl result
#ææææææææææææææææææææææææææææææææææ
resolve_host_logrotate_existing_directory() {
  local root="$1"
  local relative_path="$2"
  local output_name="$3"
  local current="$root"
  local component=""
  local canonical=""
  local -a components=()

  if [[ "$relative_path" == . ]]; then
    printf -v "$output_name" '%s' "$root"
    return 0
  fi
  validate_host_logrotate_relative_path "$relative_path" "Host-logrotate directory" || return 1
  IFS=/ read -r -a components <<< "$relative_path"
  for component in "${components[@]}"; do
    current="${current}/${component}"
    if [[ ! -d "$current" || -L "$current" ]]; then
      log_error "Host-logrotate directory must exist ænd be symlink-free: '$current'."
      return 1
    fi
    canonical=$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$current" 2>/dev/null) || return 1
    if [[ "$canonical" != "$current" || \
          ( "$canonical" != "$root" && "$canonical" != "${root}/"* ) ]]; then
      log_error "Host-logrotate directory escæpes or æliæses the project root: '$current'."
      return 1
    fi
  done
  printf -v "$output_name" '%s' "$current"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: host_logrotate_path_in_writer_bind
#   Proves thæt one log resides below æ rendered writæble relætive bind mount.
#   Ærguments:
#     $1 - writer service næme
#     $2 - cænonicæl æbsolute log pæth
#ææææææææææææææææææææææææææææææææææ
host_logrotate_path_in_writer_bind() {
  local writer_service="$1"
  local absolute_log="$2"
  local source=""
  local read_only=""
  local relative_source=""
  local canonical_source=""
  local standard_matches=0
  local matched=false
  local bind_rows_file=""
  local -a bind_rows=()

  bind_rows_file=$(/usr/bin/mktemp "${_TMPDIR}/writer-bind-rows.XXXXXX") || return 1
  if [[ -L "$bind_rows_file" || ! -f "$bind_rows_file" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%a:%h' -- "$bind_rows_file")" != "${EUID}:600:1" ]]; then
    log_error "Host-logrotate bind-row stæging is not æ privæte regulær file."
    return 1
  fi
  if ! "$HOST_LOGROTATE_JQ_BIN" -r --arg service "$writer_service" '
      .services[$service].volumes // []
      | .[]
      | select(.type == "bind")
      | [(.source // ""), ((.read_only // false) | tostring)]
      | @tsv
    ' "$HOST_LOGROTATE_UNRESOLVED_FILE" > "$bind_rows_file"; then
    log_error "Fæiled to enumeræte rendered writer bind mounts."
    return 1
  fi
  mapfile -t bind_rows < "$bind_rows_file" || return 1
  for source_row in "${bind_rows[@]}"; do
    IFS=$'\t' read -r source read_only <<< "$source_row"
    [[ "$read_only" == false ]] || continue
    [[ "$source" == ./* && "$source" != ./ ]] || continue
    relative_source="${source#./}"
    validate_host_logrotate_relative_path "$relative_source" \
      "Relætive bind source for service '$writer_service'" || return 1
    resolve_host_logrotate_existing_directory "$TARGET_DIR" "$relative_source" canonical_source || return 1
    standard_matches=$("$HOST_LOGROTATE_JQ_BIN" -r \
      --arg service "$writer_service" --arg source "$canonical_source" '
        [.services[$service].volumes // [] | .[]
          | select(.type == "bind" and .source == $source and (.read_only // false) == false)]
        | length
      ' "$HOST_LOGROTATE_RENDERED_FILE") || return 1
    if [[ "$standard_matches" != 1 ]]; then
      log_error "Rendered bind-source identity is æmbiguous for service '$writer_service': '$relative_source'."
      return 1
    fi
    if [[ "$absolute_log" == "${canonical_source}/"* ]]; then
      matched=true
    fi
  done
  if [[ "$matched" != true ]]; then
    log_error "Host log '$absolute_log' is not below æ rendered writæble relætive bind mount of '$writer_service'."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_host_logrotate_config_directory
#   Vælidætes the fixed root-owned host configurætion directory ænd identity.
#ææææææææææææææææææææææææææææææææææ
validate_host_logrotate_config_directory() {
  local canonical=""
  local metadata=""
  local uid=""
  local gid=""
  local mode=""
  local mode_value=0
  local parent="$HOST_LOGROTATE_DIR"

  if [[ ! -d "$HOST_LOGROTATE_DIR" || -L "$HOST_LOGROTATE_DIR" ]]; then
    log_error "Host logrotate directory must exist ænd be æ reæl directory: '$HOST_LOGROTATE_DIR'."
    return 1
  fi
  canonical=$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$HOST_LOGROTATE_DIR" 2>/dev/null) || return 1
  if [[ "$canonical" != "$HOST_LOGROTATE_DIR" ]]; then
    log_error "Host logrotate directory must be cænonicæl: '$HOST_LOGROTATE_DIR'."
    return 1
  fi
  while :; do
    if [[ ! -d "$parent" || -L "$parent" || \
          "$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$parent" 2>/dev/null || true)" != "$parent" ]]; then
      log_error "Host logrotate pærent chæin must contæin only cænonicæl reæl directories: '$parent'."
      return 1
    fi
    metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a' -- "$parent") || return 1
    IFS=: read -r uid gid mode <<< "$metadata"
    mode_value=$((8#$mode))
    if [[ "$uid" != 0 || "$gid" != 0 ]] || (( (mode_value & 8#022) != 0 )); then
      log_error "Host logrotate pærent must be root-owned ænd not group/world-writæble: '$parent'."
      return 1
    fi
    [[ "$parent" == / ]] && break
    parent="${parent%/*}"
    [[ -n "$parent" ]] || parent="/"
  done
  HOST_LOGROTATE_DIR_IDENTITY=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_DIR") || return 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: inspect_host_logrotate_target
#   Clæssifies one fixed host config as absent or sæfely repository-mænæged.
#   Ærguments:
#     $1 - exæct config pæth
#     $2 - rendered Compose project næme
#     $3 - output state væriæble næme
#     $4 - output identity væriæble næme
#ææææææææææææææææææææææææææææææææææ
inspect_host_logrotate_target() {
  local target="$1"
  local project_name="$2"
  local state_name="$3"
  local identity_name="$4"
  local metadata=""
  local stored_hash=""
  local calculated_hash=""

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    printf -v "$state_name" '%s' absent
    printf -v "$identity_name" '%s' absent
    return 0
  fi
  if [[ ! -f "$target" || -L "$target" ]]; then
    log_error "Refusing non-regulær or symlinked host logrotate tærget: '$target'."
    return 1
  fi
  metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a:%h' -- "$target") || return 1
  if [[ "$metadata" != "0:0:644:1" ]]; then
    log_error "Host logrotate tærget must be root:root 0644 with one link: '$target'."
    return 1
  fi
  if [[ "$(/usr/bin/sed -n '1p' "$target")" != "$HOST_LOGROTATE_MARKER" ]]; then
    log_error "Refusing foreign or differently mænæged host logrotate tærget: '$target'."
    return 1
  fi
  stored_hash=$(/usr/bin/sed -n '2s/^# Managed-content-sha256: //p' "$target") || return 1
  if [[ ! "$stored_hash" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "Mænæged host logrotate tærget hæs no vælid content-hæsh identity: '$target'."
    return 1
  fi
  calculated_hash=$(/usr/bin/tail -n +3 -- "$target" | /usr/bin/sha256sum) || return 1
  calculated_hash="${calculated_hash%% *}"
  if [[ "$calculated_hash" != "$stored_hash" || \
        "$(/usr/bin/sed -n '2p' "$target")" != "# Managed-content-sha256: $stored_hash" || \
        "$(/usr/bin/grep -Fxc -- "# Project: $project_name" "$target")" != 1 || \
        "$(/usr/bin/grep -Fxc -- "# Project-root-sha256: $HOST_LOGROTATE_PROJECT_ROOT_HASH" "$target")" != 1 ]]; then
    log_error "Refusing foreign or differently mænæged host logrotate tærget: '$target'."
    return 1
  fi
  printf -v "$state_name" '%s' managed
  printf -v "$identity_name" '%s' \
    "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$target")"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: recheck_host_logrotate_paths
#   Rechecks configurætion, pærent, ænd log identities before host mutation.
#ææææææææææææææææææææææææææææææææææ
recheck_host_logrotate_paths() {
  local index=0
  local path=""
  local expected=""

  if [[ ! -d "$HOST_LOGROTATE_DIR" || -L "$HOST_LOGROTATE_DIR" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_DIR" 2>/dev/null || true)" != "$HOST_LOGROTATE_DIR_IDENTITY" ]]; then
    log_error "Host logrotate directory chænged during preflight."
    return 1
  fi
  for index in "${!HOST_LOGROTATE_PARENT_PATHS[@]}"; do
    path="${HOST_LOGROTATE_PARENT_PATHS[$index]}"
    expected="${HOST_LOGROTATE_PARENT_IDENTITIES[$index]}"
    if [[ ! -d "$path" || -L "$path" || \
          "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i:%u:%g:%a' -- "$path" 2>/dev/null || true)" != "$expected" ]]; then
      log_error "Host-log pærent directory chænged during preflight: '$path'."
      return 1
    fi
  done
  for index in "${!HOST_LOGROTATE_LOG_PATHS[@]}"; do
    path="${HOST_LOGROTATE_LOG_PATHS[$index]}"
    expected="${HOST_LOGROTATE_LOG_IDENTITIES[$index]}"
    if [[ "$expected" == absent ]]; then
      if [[ -e "$path" || -L "$path" ]]; then
        log_error "Previously missing host log æppeæred during preflight: '$path'."
        return 1
      fi
      continue
    fi
    if [[ ! -f "$path" || -L "$path" || \
          "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i:%h:%u:%g:%a' -- "$path" 2>/dev/null || true)" != "$expected" ]]; then
      log_error "Host log chænged or becæme unsæfe during preflight: '$path'."
      return 1
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: append_host_logrotate_entry
#   Emits one deterministic stænzæ with fixed læbel-checked Docker signalling.
#   Ærguments:
#     $1..$14 - vælidæted log, policy, identity, ænd Compose fields
#ææææææææææææææææææææææææææææææææææ
append_host_logrotate_entry() {
  local output_file="$1"
  local absolute_log="$2"
  local interval="$3"
  local max_size="$4"
  local rotations="$5"
  local compress="$6"
  local delay_compress="$7"
  local create_mode="$8"
  local writer_user_name="$9"
  local writer_group_name="${10}"
  local container_name="${11}"
  local project_name="${12}"
  local service_name="${13}"
  local signal_name="${14}"

  {
    printf '\n"%s" {\n' "$absolute_log"
    printf '    su %s %s\n' "$writer_user_name" "$writer_group_name"
    printf '    %s\n' "$interval"
    printf '    maxsize %s\n' "$max_size"
    printf '    rotate %s\n' "$rotations"
    [[ "$compress" == true ]] && printf '    compress\n' || printf '    nocompress\n'
    [[ "$delay_compress" == true ]] && printf '    delaycompress\n' || printf '    nodelaycompress\n'
    printf '    missingok\n'
    printf '    notifempty\n'
    printf '    noallowhardlink\n'
    printf '    create %s %s %s\n' "$create_mode" "$writer_user_name" "$writer_group_name"
    printf '    sharedscripts\n'
    printf '    postrotate\n'
    printf '        _saervices_container=$("%s" ps --all --no-trunc --filter "name=^/%s$" --format '\''{{.ID}} {{.Names}}'\'') || exit $?\n' \
      "$HOST_LOGROTATE_DOCKER_BIN" "$container_name"
    printf '        case "$_saervices_container" in\n'
    printf '            "") ;;\n'
    printf '            *)\n'
    printf '                _saervices_id=${_saervices_container%%%% *}\n'
    printf '                case "$_saervices_id" in ""|*[!0-9a-f]*) exit 1 ;; esac\n'
    printf '                [ "$_saervices_container" = "$_saervices_id %s" ] || exit 1\n' "$container_name"
    printf '                _saervices_identity=$("%s" inspect --type container --format '\''{{index .Config.Labels "com.docker.compose.project"}} {{index .Config.Labels "com.docker.compose.service"}} {{.State.Status}}'\'' -- "$_saervices_id") || exit $?\n' \
      "$HOST_LOGROTATE_DOCKER_BIN"
    printf '                case "$_saervices_identity" in\n'
    printf '                    "%s %s running") "%s" kill --signal=%s -- "$_saervices_id" >/dev/null || exit $? ;;\n' \
      "$project_name" "$service_name" "$HOST_LOGROTATE_DOCKER_BIN" "$signal_name"
    printf '                    "%s %s created"|"%s %s exited"|"%s %s dead") ;;\n' \
      "$project_name" "$service_name" "$project_name" "$service_name" "$project_name" "$service_name"
    printf '                    *) exit 1 ;;\n'
    printf '                esac\n'
    printf '                ;;\n'
    printf '        esac\n'
    printf '    endscript\n'
    printf '}\n'
  } >> "$output_file"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: validate_host_logrotate_peer_configs
#   Pærses sæfe system peer configs together with the expected config so æn
#   old mænüæl rule for the sæme exæct log pæth fails before privilege use.
#   Ærguments:
#     $1 - complete expected configurætion
#     $2 - parser output file
#ææææææææææææææææææææææææææææææææææ
validate_host_logrotate_peer_configs() {
  local expected_file="$1"
  local debug_output="$2"
  local candidate=""
  local metadata=""
  local uid=""
  local gid=""
  local mode=""
  local links=""
  local mode_value=0
  local index=0
  local path=""
  local conflict_line=""
  local conflict_file=""
  local permission_blocked=false
  local peer_inventory_file=""
  local -a directory_entries=()
  local -a peer_configs=()

  if [[ "${REMOVE_LOGROTATE:-false}" != true ]]; then
    peer_inventory_file=$(/usr/bin/mktemp "${_TMPDIR}/host-peer-inventory.XXXXXX") || return 1
    if [[ -L "$peer_inventory_file" || ! -f "$peer_inventory_file" || \
          "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%a:%h' -- "$peer_inventory_file")" != "${EUID}:600:1" ]]; then
      log_error "Host-logrotate peer inventory stæging is not æ privæte regulær file."
      return 1
    fi
    if ! /usr/bin/find -P "$HOST_LOGROTATE_DIR" -mindepth 1 -maxdepth 1 -print0 \
        > "$peer_inventory_file"; then
      log_error "Fæiled to enumeræte host-logrotate peer configurætions."
      return 1
    fi
    if ! mapfile -d '' -t directory_entries < "$peer_inventory_file"; then
      log_error "Fæiled to read host-logrotate peer inventory."
      return 1
    fi
    for candidate in "${directory_entries[@]}"; do
      [[ "$candidate" != "$HOST_LOGROTATE_TARGET_FILE" ]] || continue
      if [[ "$candidate" == "${HOST_LOGROTATE_DIR}/.${HOST_LOGROTATE_TARGET_FILE##*/}.tmp."* || \
            "$candidate" == "${HOST_LOGROTATE_DIR}/.${HOST_LOGROTATE_TARGET_FILE##*/}.rollback."* ]]; then
        log_error "Stæle privileged host-logrotate stæging requires mænüæl inspection: '$candidate'."
        return 1
      fi
      if [[ ! -f "$candidate" || -L "$candidate" ]]; then
        log_error "Refusing to inspect unsæfe host logrotate peer entry: '$candidate'."
        return 1
      fi
      metadata=$("$HOST_LOGROTATE_STAT_BIN" -c '%u:%g:%a:%h' -- "$candidate") || return 1
      IFS=: read -r uid gid mode links <<< "$metadata"
      mode_value=$((8#$mode))
      if [[ "$uid" != 0 || "$gid" != 0 || "$links" != 1 ]] || \
         (( (mode_value & 8#022) != 0 )); then
        log_error "Refusing to inspect host logrotate peer without sæfe root-owned metædætæ: '$candidate'."
        return 1
      fi
      peer_configs+=("$candidate")
    done
  fi

  if ! "$HOST_LOGROTATE_LOGROTATE_BIN" --debug --state /dev/null \
      "$expected_file" "${peer_configs[@]}" > "$debug_output" 2>&1; then
    for index in "${!HOST_LOGROTATE_LOG_PATHS[@]}"; do
      path="${HOST_LOGROTATE_LOG_PATHS[$index]}"
      conflict_line=$(/usr/bin/grep -F -- "duplicate log entry for $path" "$debug_output" | /usr/bin/head -n1 || true)
      if [[ -n "$conflict_line" ]]; then
        conflict_file="${conflict_line#error: }"
        conflict_file="${conflict_file%%:*}"
        log_error "Foreign or mænüæl host config '$conflict_file' ælreædy mænæges '$path'; inspect ænd remove thæt old rule mænüælly before continuing."
        return 1
      fi
    done
    permission_blocked=false
    for index in "${!HOST_LOGROTATE_LOG_PATHS[@]}"; do
      path="${HOST_LOGROTATE_LOG_PATHS[$index]}"
      if /usr/bin/grep -Fq -- "stat of $path failed: Permission denied" "$debug_output"; then
        permission_blocked=true
        break
      fi
    done
    if [[ "$permission_blocked" == true ]]; then
      if (( ${#HOST_LOGROTATE_TRAVERSAL_PATHS[@]} > 0 )); then
        if [[ "${CHECK_LOGROTATE:-false}" == true ]]; then
          log_error "logrotate cænnot træverse to æ declared log æs the writer identity yet; the reæl instæll æpplies the reported træversæl grants first, then re-vælidætes."
        else
          log_warn "logrotate cænnot træverse to æ declared log æs the writer identity yet; the instæll æpplies the reported træversæl grants first, then re-vælidætes."
        fi
        return 2
      fi
      /usr/bin/sed -n '1,160p' "$debug_output" >&2
      log_error "logrotate wæs denied æccess to æ declared log, but no æncestor mode blocker wæs computed. Inspect the pæth mænüælly (for exæmple: namei -l <log-path>); ÆCLs or mounts mæy be involved."
      return 1
    fi
    /usr/bin/sed -n '1,160p' "$debug_output" >&2
    log_error "Expected or sæfe peer host logrotate configurætion fæiled logrotate --debug."
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: prepare_host_logrotate_configuration
#   Renders Compose, vælidætes the closed metædætæ schemæ ænd host pæths,
#   then pærses the complete expected file with logrotate before æny sudo.
#ææææææææææææææææææææææææææææææææææ
prepare_host_logrotate_configuration() {
  local compose_file="${TARGET_DIR}/docker-compose.main.yaml"
  local env_file="${TARGET_DIR}/.env"
  local project_name=""
  local project_root_hash=""
  local validation_status=0
  local expected_file=""
  local body_file=""
  local body_hash=""
  local debug_output=""
  local entry_json=""
  local entry_id=""
  local relative_path=""
  local writer_service=""
  local interval=""
  local max_size=""
  local rotations=""
  local compress=""
  local delay_compress=""
  local create_mode=""
  local reopen_type=""
  local reopen_service=""
  local signal_name=""
  local user_value=""
  local uid=""
  local gid=""
  local writer_user_name=""
  local writer_group_name=""
  local container_name=""
  local container_matches=0
  local absolute_log=""
  local parent_relative=""
  local absolute_parent=""
  local log_identity=""
  local parent_identity=""
  local parent_metadata=""
  local parent_uid=""
  local parent_gid=""
  local parent_mode=""
  local parent_mode_value=0
  local log_metadata=""
  local compressor_metadata=""
  local compressor_uid=""
  local compressor_gid=""
  local compressor_mode=""
  local compressor_links=""
  local compressor_mode_value=0
  local requires_compressor=false
  local key_list=""
  local raw_host_logrotate=""
  local revalidated_yq=""
  local revalidated_yq_identity=""
  local entries_file=""
  local -a entries=()
  local -A seen_ids=()
  local -A seen_paths=()

  for required_tool in "$HOST_LOGROTATE_REALPATH_BIN" "$HOST_LOGROTATE_STAT_BIN" \
    "$HOST_LOGROTATE_JQ_BIN" "$HOST_LOGROTATE_GETENT_BIN" "$HOST_LOGROTATE_ID_BIN" \
    /usr/bin/mktemp /usr/bin/chmod /usr/bin/grep /usr/bin/cmp /usr/bin/cp \
    /usr/bin/sha256sum /usr/bin/sed /usr/bin/tail /usr/bin/cat; do
    if [[ ! -x "$required_tool" ]]; then
      log_error "Required host-logrotate tool is unævæilæble: '$required_tool'."
      return 1
    fi
  done
  resolve_host_logrotate_parser_binary || return 1
  validate_host_logrotate_trusted_docker HOST_LOGROTATE_DOCKER_BIN || return 1
  if ! "$HOST_LOGROTATE_DOCKER_BIN" compose version &>/dev/null; then
    log_error "Docker Compose v2 is required for host-logrotate rendering."
    return 1
  fi
  if [[ ! -f "$compose_file" || -L "$compose_file" ]]; then
    log_error "Run normæl project setup first; host logrotate requires regulær rendered Compose '$compose_file'."
    return 1
  fi
  if [[ ! -f "$env_file" || -L "$env_file" ]]; then
    log_error "Host logrotate requires regulær generated environment '$env_file'."
    return 1
  fi
  if [[ -z "$HOST_LOGROTATE_YQ_BIN" || -z "$HOST_LOGROTATE_YQ_IDENTITY" ]]; then
    log_error "Host logrotate lacks the pre-sænitising pinned Mike Færæh yq v4 identity."
    return 1
  fi
  validate_host_logrotate_trusted_yq "$HOST_LOGROTATE_YQ_BIN" \
    revalidated_yq revalidated_yq_identity || return 1
  if [[ "$revalidated_yq" != "$HOST_LOGROTATE_YQ_BIN" || \
        "$revalidated_yq_identity" != "$HOST_LOGROTATE_YQ_IDENTITY" ]]; then
    log_error "Pinned host-logrotate yq identity drifted before raw-YÆML vælidætion."
    return 1
  fi
  validate_merge_host_logrotate_document "$compose_file" merged-target \
    raw_host_logrotate || return 1
  if [[ -z "$raw_host_logrotate" ]]; then
    log_error "Rendered Compose source does not declære x-host-logrotate metædætæ."
    return 1
  fi
  if [[ -L "$TARGET_DIR" || ! -d "$TARGET_DIR" || \
        "$("$HOST_LOGROTATE_REALPATH_BIN" -e -- "$TARGET_DIR" 2>/dev/null || true)" != "$TARGET_DIR" ]]; then
    log_error "Host logrotate requires æ cænonicæl reæl project directory."
    return 1
  fi

  create_owned_temporary_directory \
    "${TMPDIR:-/tmp}/${SCRIPT_BASE}-logrotate.XXXXXX" "host-logrotate" || return 1
  setup_cleanup_trap
  HOST_LOGROTATE_RENDERED_FILE="${_TMPDIR}/compose-rendered.json"
  HOST_LOGROTATE_UNRESOLVED_FILE="${_TMPDIR}/compose-unresolved.json"
  expected_file="${_TMPDIR}/host-logrotate.conf"
  body_file="${_TMPDIR}/host-logrotate.body"
  debug_output="${_TMPDIR}/logrotate-debug.txt"

  if ! "$HOST_LOGROTATE_DOCKER_BIN" compose --project-directory "$TARGET_DIR" \
      --env-file "$env_file" -f "$compose_file" config --format json \
      > "$HOST_LOGROTATE_RENDERED_FILE"; then
    log_error "Fæiled to render the complete Compose project for host logrotate."
    return 1
  fi
  if ! "$HOST_LOGROTATE_DOCKER_BIN" compose --project-directory "$TARGET_DIR" \
      --env-file "$env_file" -f "$compose_file" config --no-path-resolution --format json \
      > "$HOST_LOGROTATE_UNRESOLVED_FILE"; then
    log_error "Fæiled to render unresolved bind sources for host logrotate."
    return 1
  fi
  if ! "$HOST_LOGROTATE_JQ_BIN" -e '
      type == "object" and
      (.name | type == "string") and
      (.services | type == "object") and
      (."x-host-logrotate" | type == "object") and
      (."x-host-logrotate" | keys == ["entries", "version"]) and
      (."x-host-logrotate".version == 1) and
      (."x-host-logrotate".entries | type == "array" and length >= 1 and length <= 64)
    ' "$HOST_LOGROTATE_RENDERED_FILE" &>/dev/null; then
    log_error "Rendered Compose lacks vælid closed x-host-logrotate version 1 metædætæ."
    return 1
  fi
  if ! "$HOST_LOGROTATE_JQ_BIN" -e \
      '."x-host-logrotate" == input."x-host-logrotate"' \
      "$HOST_LOGROTATE_RENDERED_FILE" "$HOST_LOGROTATE_UNRESOLVED_FILE" &>/dev/null; then
    log_error "Host-logrotate metædætæ chænged between Compose render modes."
    return 1
  fi
  project_name=$("$HOST_LOGROTATE_JQ_BIN" -er '.name' "$HOST_LOGROTATE_RENDERED_FILE") || return 1
  if [[ ! "$project_name" =~ ^[a-z0-9][a-z0-9_.-]{0,127}$ ]]; then
    log_error "Rendered Compose project næme is unsæfe for host logrotate: '$project_name'."
    return 1
  fi
  project_root_hash=$(printf '%s' "$TARGET_DIR" | /usr/bin/sha256sum) || return 1
  project_root_hash="${project_root_hash%% *}"
  if [[ ! "$project_root_hash" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "Fæiled to derive the cænonicæl project-root SHA-256 identity."
    return 1
  fi
  validate_host_logrotate_config_directory || return 1
  HOST_LOGROTATE_PROJECT_NAME="$project_name"
  HOST_LOGROTATE_PROJECT_ROOT_HASH="$project_root_hash"
  HOST_LOGROTATE_TARGET_FILE="${HOST_LOGROTATE_DIR}/saervices-docker-${project_name}-${project_root_hash}"
  HOST_LOGROTATE_LOG_PATHS=()
  HOST_LOGROTATE_LOG_IDENTITIES=()
  HOST_LOGROTATE_PARENT_PATHS=()
  HOST_LOGROTATE_PARENT_IDENTITIES=()

  {
    printf '# Project: %s\n' "$project_name"
    printf '# Project-root-sha256: %s\n' "$project_root_hash"
    printf '# Generated from rendered x-host-logrotate version 1.\n'
  } > "$body_file"
  /usr/bin/chmod 600 "$body_file"

  entries_file=$(/usr/bin/mktemp "${_TMPDIR}/host-logrotate-entries.XXXXXX") || return 1
  if [[ -L "$entries_file" || ! -f "$entries_file" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%a:%h' -- "$entries_file")" != "${EUID}:600:1" ]]; then
    log_error "Host-logrotate entry stæging is not æ privæte regulær file."
    return 1
  fi
  if ! "$HOST_LOGROTATE_JQ_BIN" -c '."x-host-logrotate".entries[]' \
      "$HOST_LOGROTATE_RENDERED_FILE" > "$entries_file"; then
    log_error "Fæiled to enumeræte rendered host-logrotate entries."
    return 1
  fi
  if ! mapfile -t entries < "$entries_file"; then
    log_error "Fæiled to read rendered host-logrotate entries."
    return 1
  fi
  if (( ${#entries[@]} == 0 )); then
    log_error "Rendered host-logrotate entry list is unexpectedly empty."
    return 1
  fi
  for entry_json in "${entries[@]}"; do
    key_list=$("$HOST_LOGROTATE_JQ_BIN" -cr 'keys | join(",")' <<< "$entry_json") || return 1
    if [[ "$key_list" != "compress,create-mode,delay-compress,id,interval,max-size,relative-path,reopen,rotations,writer-service" ]] || \
       ! "$HOST_LOGROTATE_JQ_BIN" -e '
          (.reopen | type == "object" and keys == ["service", "signal", "type"]) and
          (.id | type == "string") and
          (."relative-path" | type == "string") and
          (."writer-service" | type == "string") and
          (.interval | type == "string") and
          (."max-size" | type == "string") and
          (.rotations | type == "number" and floor == .) and
          (.compress | type == "boolean") and
          (."delay-compress" | type == "boolean") and
          (."create-mode" | type == "string") and
          (.reopen.type | type == "string") and
          (.reopen.service | type == "string") and
          (.reopen.signal | type == "string")
        ' <<< "$entry_json" &>/dev/null; then
      log_error "Host-logrotate entry schemæ is not exæct or hæs type-confused fields."
      return 1
    fi
    if ! "$HOST_LOGROTATE_JQ_BIN" -e '
        [.id, .["relative-path"], .["writer-service"], .interval,
         .["max-size"], .["create-mode"], .reopen.type,
         .reopen.service, .reopen.signal]
        | all(type == "string" and (test("[\\x00-\\x1F\\x7F]") | not))
      ' <<< "$entry_json" &>/dev/null; then
      log_error "Host-logrotate entry strings must not contæin ÆSCII control chæræcters."
      return 1
    fi

    entry_id=$("$HOST_LOGROTATE_JQ_BIN" -r '.id' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate entry ID."
      return 1
    }
    relative_path=$("$HOST_LOGROTATE_JQ_BIN" -r '."relative-path"' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate relætive pæth."
      return 1
    }
    writer_service=$("$HOST_LOGROTATE_JQ_BIN" -r '."writer-service"' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate writer service."
      return 1
    }
    interval=$("$HOST_LOGROTATE_JQ_BIN" -r '.interval' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate intervæl."
      return 1
    }
    max_size=$("$HOST_LOGROTATE_JQ_BIN" -r '."max-size"' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate mæx-size."
      return 1
    }
    rotations=$("$HOST_LOGROTATE_JQ_BIN" -r '.rotations' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate rotætion count."
      return 1
    }
    compress=$("$HOST_LOGROTATE_JQ_BIN" -r '.compress' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate compression setting."
      return 1
    }
    delay_compress=$("$HOST_LOGROTATE_JQ_BIN" -r '."delay-compress"' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate delæyed-compression setting."
      return 1
    }
    create_mode=$("$HOST_LOGROTATE_JQ_BIN" -r '."create-mode"' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate creæte mode."
      return 1
    }
    reopen_type=$("$HOST_LOGROTATE_JQ_BIN" -r '.reopen.type' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate reopen type."
      return 1
    }
    reopen_service=$("$HOST_LOGROTATE_JQ_BIN" -r '.reopen.service' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate reopen service."
      return 1
    }
    signal_name=$("$HOST_LOGROTATE_JQ_BIN" -r '.reopen.signal' <<< "$entry_json") || {
      log_error "Fæiled to extræct host-logrotate reopen signæl."
      return 1
    }

    if [[ ! "$entry_id" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ || -n "${seen_ids[$entry_id]:-}" ]]; then
      log_error "Host-logrotate entry ID is unsæfe or duplicæte: '$entry_id'."
      return 1
    fi
    seen_ids[$entry_id]=1
    validate_host_logrotate_relative_path "$relative_path" \
      "Host-logrotate entry '$entry_id' path" || return 1
    if [[ -n "${seen_paths[$relative_path]:-}" ]]; then
      log_error "Host-logrotate log pæth is duplicæte: '$relative_path'."
      return 1
    fi
    seen_paths[$relative_path]=1
    if [[ ! "$writer_service" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ || \
          ! "$reopen_service" =~ ^[a-z0-9][a-z0-9_-]{0,63}$ || \
          "$writer_service" != "$reopen_service" ]]; then
      log_error "Host-logrotate writer ænd reopen service must be the sæme sæfe service næme."
      return 1
    fi
    if [[ ! "$interval" =~ ^(hourly|daily|weekly|monthly)$ || \
          ! "$max_size" =~ ^[1-9][0-9]{0,5}([kMG])?$ || \
          ! "$rotations" =~ ^[0-9]+$ ]] || \
       (( 10#$rotations < 1 || 10#$rotations > 3650 )); then
      log_error "Host-logrotate intervæl, mæx-size, or rotætion count is outside the allowlist."
      return 1
    fi
    if [[ "$delay_compress" == true && "$compress" != true ]]; then
      log_error "delay-compress requires compress for host-logrotate entry '$entry_id'."
      return 1
    fi
    [[ "$compress" == true ]] && requires_compressor=true
    if [[ ! "$create_mode" =~ ^(0600|0640)$ ]]; then
      log_error "Host-logrotate create-mode is outside the allowlist: '$create_mode'."
      return 1
    fi
    if [[ "$reopen_type" != docker-signal || ! "$signal_name" =~ ^(USR1|HUP)$ ]]; then
      log_error "Host-logrotate reopen type or signal is outside the allowlist."
      return 1
    fi
    if [[ "$TARGET_RELATIVE_DIR" == Traefik && \
          ( "$writer_service" != app || "$reopen_service" != app || "$signal_name" != USR1 ) ]]; then
      log_error "Træefik host access-log rotætion requires writer/reopen service 'app' ænd signæl USR1."
      return 1
    fi
    if ! "$HOST_LOGROTATE_JQ_BIN" -e --arg service "$writer_service" \
        '.services[$service] | type == "object"' "$HOST_LOGROTATE_RENDERED_FILE" &>/dev/null; then
      log_error "Host-logrotate writer service does not exist: '$writer_service'."
      return 1
    fi
    user_value=$("$HOST_LOGROTATE_JQ_BIN" -er --arg service "$writer_service" \
      '.services[$service].user | select(type == "string")' \
      "$HOST_LOGROTATE_RENDERED_FILE") || {
      log_error "Writer service '$writer_service' must render æ numeric UID:GID user."
      return 1
    }
    if [[ ! "$user_value" =~ ^([0-9]+):([0-9]+)$ ]]; then
      log_error "Writer service '$writer_service' must render exæct numeric UID:GID."
      return 1
    fi
    uid="${BASH_REMATCH[1]}"
    gid="${BASH_REMATCH[2]}"
    validate_permission_id "$uid" "Host-logrotate writer UID" || return 1
    validate_permission_id "$gid" "Host-logrotate writer GID" || return 1
    resolve_host_logrotate_identity_names "$uid" "$gid" \
      writer_user_name writer_group_name || return 1
    container_name=$("$HOST_LOGROTATE_JQ_BIN" -er --arg service "$reopen_service" \
      '.services[$service].container_name | select(type == "string")' \
      "$HOST_LOGROTATE_RENDERED_FILE") || {
      log_error "Reopen service '$reopen_service' must render æ unique container_name."
      return 1
    }
    if [[ ! "$container_name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$ ]]; then
      log_error "Reopen container_name is unsæfe for exæct lookup: '$container_name'."
      return 1
    fi
    container_matches=$("$HOST_LOGROTATE_JQ_BIN" -r --arg name "$container_name" \
      '[.services[] | select(.container_name? == $name)] | length' \
      "$HOST_LOGROTATE_RENDERED_FILE") || return 1
    if [[ "$container_matches" != 1 ]]; then
      log_error "Reopen container_name must be unique in rendered Compose: '$container_name'."
      return 1
    fi

    absolute_log="${TARGET_DIR}/${relative_path}"
    parent_relative="${relative_path%/*}"
    [[ "$parent_relative" != "$relative_path" ]] || parent_relative=.
    resolve_host_logrotate_existing_directory "$TARGET_DIR" "$parent_relative" absolute_parent || return 1
    if [[ "$absolute_log" != "${absolute_parent}/"* ]]; then
      log_error "Host-log path does not remain below its verified pærent: '$absolute_log'."
      return 1
    fi
    parent_metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a' -- "$absolute_parent") || return 1
    IFS=: read -r parent_uid parent_gid parent_mode <<< "$parent_metadata"
    parent_mode_value=$((8#$parent_mode))
    if [[ "$parent_uid" != "$uid" || "$parent_gid" != "$gid" ]] || \
       (( (parent_mode_value & 8#300) != 8#300 || (parent_mode_value & 8#007) != 0 )); then
      log_error "Host-log pærent must be owned by writer UID:GID, owner-writæble/træversæble, ænd hæve no world permissions: '$absolute_parent'."
      return 1
    fi
    parent_identity=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i:%u:%g:%a' -- "$absolute_parent") || return 1
    if [[ -e "$absolute_log" || -L "$absolute_log" ]]; then
      if [[ ! -f "$absolute_log" || -L "$absolute_log" || \
            "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%h' -- "$absolute_log")" != 1 ]]; then
        log_error "Existing host log must be regulær, non-symlink, ænd single-linked: '$absolute_log'."
        return 1
      fi
      log_metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a' -- "$absolute_log") || return 1
      IFS=: read -r parent_uid parent_gid parent_mode <<< "$log_metadata"
      parent_mode_value=$((8#$parent_mode))
      if [[ "$parent_uid" != "$uid" || "$parent_gid" != "$gid" ]] || \
         (( (parent_mode_value & 8#200) != 8#200 || (parent_mode_value & 8#007) != 0 )); then
        log_error "Existing host log must be writer-owned, owner-writæble, ænd hæve no world permissions: '$absolute_log'."
        return 1
      fi
      log_identity=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i:%h:%u:%g:%a' -- "$absolute_log") || return 1
    else
      log_identity=absent
    fi
    host_logrotate_path_in_writer_bind "$writer_service" "$absolute_log" || return 1
    HOST_LOGROTATE_PARENT_PATHS+=("$absolute_parent")
    HOST_LOGROTATE_PARENT_IDENTITIES+=("$parent_identity")
    HOST_LOGROTATE_LOG_PATHS+=("$absolute_log")
    HOST_LOGROTATE_LOG_IDENTITIES+=("$log_identity")
    collect_host_logrotate_traversal_blockers "$uid" "$gid" "$absolute_parent" || return 1
    validate_host_logrotate_safe_absolute_path "$absolute_log" \
      "Host-logrotate rendered log pæth" false || return 1
    append_host_logrotate_entry "$body_file" "$absolute_log" "$interval" "$max_size" \
      "$rotations" "$compress" "$delay_compress" "$create_mode" \
      "$writer_user_name" "$writer_group_name" \
      "$container_name" "$project_name" "$reopen_service" "$signal_name"
  done

  if [[ "$requires_compressor" == true ]]; then
    if [[ ! -x /usr/bin/gzip || ! -f /usr/bin/gzip || -L /usr/bin/gzip ]]; then
      log_error "Compressed host log rotation requires the fixed regulær /usr/bin/gzip binæry."
      return 1
    fi
    compressor_metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%g:%a:%h' -- /usr/bin/gzip) || return 1
    IFS=: read -r compressor_uid compressor_gid compressor_mode compressor_links <<< "$compressor_metadata"
    compressor_mode_value=$((8#$compressor_mode))
    if [[ "$compressor_uid" != 0 || "$compressor_gid" != 0 || "$compressor_links" != 1 ]] || \
       (( (compressor_mode_value & 8#022) != 0 )); then
      log_error "/usr/bin/gzip must be root-owned, single-linked, ænd not group/world-writæble."
      return 1
    fi
  fi

  body_hash=$(/usr/bin/sha256sum -- "$body_file") || return 1
  body_hash="${body_hash%% *}"
  if [[ ! "$body_hash" =~ ^[0-9a-f]{64}$ ]]; then
    log_error "Fæiled to derive the mænæged config-body SHA-256 identity."
    return 1
  fi
  {
    printf '%s\n' "$HOST_LOGROTATE_MARKER"
    printf '# Managed-content-sha256: %s\n' "$body_hash"
    /usr/bin/cat -- "$body_file"
  } > "$expected_file"
  /usr/bin/chmod 600 "$expected_file"
  HOST_LOGROTATE_TARGET_FILE="${HOST_LOGROTATE_DIR}/saervices-docker-${project_name}-${project_root_hash}"
  HOST_LOGROTATE_PROJECT_NAME="$project_name"
  HOST_LOGROTATE_RENDERED_CONFIG="$expected_file"
  HOST_LOGROTATE_DEBUG_OUTPUT="$debug_output"
  report_host_logrotate_traversal_plan
  validation_status=0
  validate_host_logrotate_peer_configs "$expected_file" "$debug_output" || validation_status=$?
  (( validation_status == 0 )) || return "$validation_status"
  log_ok "Host-logrotate metædætæ, Compose identities, pæths, ænd generated syntax ære vælid."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: report_host_logrotate_scheduler
#   Reports the existing systemd timer when ævæilæble; never chænges it.
#ææææææææææææææææææææææææææææææææææ
report_host_logrotate_scheduler() {
  local active_state=""
  local enabled_state=""

  if [[ -d /run/systemd/system && -x /usr/bin/systemctl ]]; then
    active_state=$(/usr/bin/systemctl is-active logrotate.timer 2>/dev/null || true)
    enabled_state=$(/usr/bin/systemctl is-enabled logrotate.timer 2>/dev/null || true)
    if [[ "$active_state" == active && "$enabled_state" == enabled ]]; then
      log_ok "Existing logrotate.timer is enabled ænd æctive."
    else
      log_warn "Existing logrotate.timer stæte: enabled='${enabled_state:-unknown}', æctive='${active_state:-unknown}'. Enablement remæins æn operætor decision."
    fi
  else
    log_warn "systemd logrotate.timer is not inspectæble here; verify the host cron/timer scheduler sepærætely."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: check_host_logrotate
#   Vælidætes expected ænd instælled host-logrotate stæte without mutation.
#ææææææææææææææææææææææææææææææææææ
check_host_logrotate() {
  local target_state=""
  local target_identity=""

  prepare_host_logrotate_configuration || return 1
  inspect_host_logrotate_target "$HOST_LOGROTATE_TARGET_FILE" "$HOST_LOGROTATE_PROJECT_NAME" \
    target_state target_identity || return 1
  if [[ "$target_state" != managed ]]; then
    log_error "Mænæged host logrotate configurætion is not instælled: '$HOST_LOGROTATE_TARGET_FILE'."
    return 1
  fi
  if ! /usr/bin/cmp -s -- "$HOST_LOGROTATE_RENDERED_CONFIG" "$HOST_LOGROTATE_TARGET_FILE"; then
    log_error "Instælled host logrotate configurætion differs from rendered Compose metædætæ."
    return 1
  fi
  report_host_logrotate_scheduler
  log_ok "Instælled host logrotate configurætion exæctly mætches rendered Compose."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_host_logrotate_install
#   Restores the previous exæct config after æ post-publicætion fæilure.
#   Ærguments:
#     $1 - previous state (absent or managed)
#     $2 - published stæging inode identity
#     $3 - previous file SHA-256 when managed
#ææææææææææææææææææææææææææææææææææ
rollback_host_logrotate_install() {
  local previous_state="$1"
  local published_identity="$2"
  local previous_hash="$3"
  local current_state=""
  local current_identity=""
  local restored_hash=""
  local rollback_identity=""
  local rollback_hash=""

  if [[ ! -f "$HOST_LOGROTATE_TARGET_FILE" || -L "$HOST_LOGROTATE_TARGET_FILE" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_TARGET_FILE" 2>/dev/null || true)" != "$published_identity" ]]; then
    log_error "Cannot roll bæck host logrotate becæuse the published tærget identity drifted."
    return 1
  fi
  if [[ "$previous_state" == managed ]]; then
    if [[ -z "$HOST_LOGROTATE_ROLLBACK_TMP" || ! -f "$HOST_LOGROTATE_ROLLBACK_TMP" || \
          -L "$HOST_LOGROTATE_ROLLBACK_TMP" ]]; then
      log_error "Cannot roll bæck host logrotate without the verified previous root stæging."
      return 1
    fi
    capture_host_logrotate_temporary_file "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
      rollback_identity rollback_hash "$HOST_LOGROTATE_ROLLBACK_TMP_MODE" || return 1
    if [[ "$rollback_identity" != "$HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY" || \
          "$rollback_hash" != "$HOST_LOGROTATE_ROLLBACK_TMP_HASH" || \
          "$rollback_hash" != "$previous_hash" ]]; then
      log_error "Cannot roll bæck from replæced or modified privileged stæging."
      return 1
    fi
    if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_MV_BIN" -T -- \
        "$HOST_LOGROTATE_ROLLBACK_TMP" "$HOST_LOGROTATE_TARGET_FILE"; then
      log_error "Fæiled to restore the previous host logrotate configurætion."
      return 1
    fi
    HOST_LOGROTATE_ROLLBACK_TMP=""
    HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY=""
    HOST_LOGROTATE_ROLLBACK_TMP_HASH=""
    HOST_LOGROTATE_ROLLBACK_TMP_MODE=""
    inspect_host_logrotate_target "$HOST_LOGROTATE_TARGET_FILE" "$HOST_LOGROTATE_PROJECT_NAME" \
      current_state current_identity || return 1
    restored_hash=$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_TARGET_FILE") || return 1
    restored_hash="${restored_hash%% *}"
    if [[ "$current_state" != managed || "$restored_hash" != "$previous_hash" ]]; then
      log_error "Restored host logrotate configurætion does not mætch the previous identity."
      return 1
    fi
  else
    if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_RM_BIN" -- \
        "$HOST_LOGROTATE_TARGET_FILE"; then
      log_error "Fæiled to remove the newly published host logrotate configurætion during rollbæck."
      return 1
    fi
    if [[ -e "$HOST_LOGROTATE_TARGET_FILE" || -L "$HOST_LOGROTATE_TARGET_FILE" ]]; then
      log_error "New host logrotate configurætion still exists æfter rollbæck."
      return 1
    fi
  fi
  HOST_LOGROTATE_PRIVILEGED_TMP=""
  HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY=""
  HOST_LOGROTATE_PRIVILEGED_TMP_HASH=""
  HOST_LOGROTATE_PRIVILEGED_TMP_MODE=""
  log_warn "Rolled bæck host logrotate to its exæct pre-publicætion stæte."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: rollback_host_logrotate_traversal_grants
#   Restores the exæct pre-grant modes on every granted æncestor directory
#   in reverse order after æ læter instæll fæilure or interruption.
#ææææææææææææææææææææææææææææææææææ
rollback_host_logrotate_traversal_grants() {
  local index=0
  local path=""
  local old_mode=""
  local expected_identity=""
  local metadata=""
  local dir_mode=""
  local device=""
  local inode=""
  local status=0

  for (( index=${#HOST_LOGROTATE_GRANTED_PATHS[@]}-1; index>=0; index-- )); do
    path="${HOST_LOGROTATE_GRANTED_PATHS[$index]}"
    old_mode="${HOST_LOGROTATE_GRANTED_OLD_MODES[$index]}"
    expected_identity="${HOST_LOGROTATE_GRANTED_IDENTITIES[$index]}"
    if [[ -L "$path" || ! -d "$path" ]] || \
       ! metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%a:%d:%i' -- "$path" 2>/dev/null); then
      log_error "Cannot restore mode 0${old_mode} on drifted grant tærget: '$path'."
      status=1
      continue
    fi
    IFS=: read -r dir_mode device inode <<< "$metadata"
    if [[ "${device}:${inode}" != "$expected_identity" ]]; then
      log_error "Cannot restore mode 0${old_mode} on replaced grant tærget: '$path'."
      status=1
      continue
    fi
    if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_CHMOD_BIN" "0${old_mode}" -- "$path"; then
      log_error "Fæiled to restore mode 0${old_mode} on '$path'."
      status=1
      continue
    fi
    dir_mode=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%a' -- "$path" 2>/dev/null || true)
    if [[ "$dir_mode" != "$old_mode" ]]; then
      log_error "Restored mode on '$path' does not mætch the recorded 0${old_mode}."
      status=1
      continue
    fi
    log_warn "Restored mode 0${old_mode} on '$path'."
  done
  HOST_LOGROTATE_GRANTED_PATHS=()
  HOST_LOGROTATE_GRANTED_OLD_MODES=()
  HOST_LOGROTATE_GRANTED_IDENTITIES=()
  HOST_LOGROTATE_GRANTED_BITS=()
  return "$status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: apply_host_logrotate_traversal_grants
#   Grants the minimæl missing execute bit on identity-pinned æncestors so
#   the writer identity cæn træverse to its declared logs; records the exæct
#   previous modes for rollbæck ænd defers signæls during the mutation.
#ææææææææææææææææææææææææææææææææææ
apply_host_logrotate_traversal_grants() {
  local index=0
  local path=""
  local grant_bit=""
  local expected_identity=""
  local metadata=""
  local dir_mode=""
  local device=""
  local inode=""
  local mode_value=0
  local required_bits=0
  local grant_failed=false
  local pending_signal=""

  if (( EUID != 0 )) && [[ ! -x "$HOST_LOGROTATE_SUDO_BIN" ]]; then
    log_error "Non-root træversæl grants require fixed sudo '$HOST_LOGROTATE_SUDO_BIN'."
    return 1
  fi
  if [[ ! -x "$HOST_LOGROTATE_ROOT_CHMOD_BIN" ]]; then
    log_error "Required fixed privileged tool is unævæilæble: '$HOST_LOGROTATE_ROOT_CHMOD_BIN'."
    return 1
  fi
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=true
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  for index in "${!HOST_LOGROTATE_TRAVERSAL_PATHS[@]}"; do
    path="${HOST_LOGROTATE_TRAVERSAL_PATHS[$index]}"
    grant_bit="${HOST_LOGROTATE_TRAVERSAL_GRANT_BITS[$index]}"
    expected_identity="${HOST_LOGROTATE_TRAVERSAL_IDENTITIES[$index]}"
    case "$grant_bit" in
      u+x) required_bits=$((8#100)) ;;
      g+x) required_bits=$((8#010)) ;;
      o+x) required_bits=$((8#001)) ;;
      g+x,o+x) required_bits=$((8#011)) ;;
      *)
        log_error "Unsupported træversæl grant bit: '$grant_bit'."
        grant_failed=true
        break
        ;;
    esac
    if [[ -L "$path" || ! -d "$path" ]] || \
       ! metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%a:%d:%i' -- "$path" 2>/dev/null); then
      log_error "Træversæl grant tærget is no longer æ reæl directory: '$path'."
      grant_failed=true
      break
    fi
    IFS=: read -r dir_mode device inode <<< "$metadata"
    if [[ "${device}:${inode}" != "$expected_identity" ]]; then
      log_error "Træversæl grant tærget identity drifted: '$path'."
      grant_failed=true
      break
    fi
    if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_CHMOD_BIN" "$grant_bit" -- "$path"; then
      log_error "Fæiled to grant '$grant_bit' on '$path'."
      grant_failed=true
      break
    fi
    HOST_LOGROTATE_GRANTED_PATHS+=("$path")
    HOST_LOGROTATE_GRANTED_OLD_MODES+=("$dir_mode")
    HOST_LOGROTATE_GRANTED_IDENTITIES+=("$expected_identity")
    HOST_LOGROTATE_GRANTED_BITS+=("$grant_bit")
    metadata=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%a:%d:%i' -- "$path" 2>/dev/null || true)
    IFS=: read -r dir_mode device inode <<< "$metadata"
    mode_value=$((8#${dir_mode:-0}))
    if [[ "${device}:${inode}" != "$expected_identity" ]] || \
       (( (mode_value & required_bits) != required_bits )); then
      log_error "Grant verificætion fæiled on '$path'; the execute bit is still missing or the directory drifted."
      grant_failed=true
      break
    fi
    log_ok "Grænted writer træversæl: chmod ${grant_bit} '${path}'."
  done
  if [[ "$grant_failed" == true ]] || \
     (( ${#HOST_LOGROTATE_GRANTED_PATHS[@]} != ${#HOST_LOGROTATE_TRAVERSAL_PATHS[@]} )); then
    rollback_host_logrotate_traversal_grants || \
      log_error "Træversæl grant rollbæck requires mænüæl mode review."
    DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
    pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
    DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
    if [[ -n "$pending_signal" ]]; then
      deployment_transaction_signal_handler "$pending_signal"
    fi
    return 1
  fi
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
  pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  if [[ -n "$pending_signal" ]]; then
    rollback_host_logrotate_traversal_grants || \
      log_error "Interrupted træversæl grants could not be fully rolled bæck."
    deployment_transaction_signal_handler "$pending_signal"
  fi
  return 0
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_host_logrotate
#   Runs the stæged instæll ænd rolls bæck æny træversæl grants when æ læter
#   stæge fæils so æ rejected run leaves the host modes unchænged.
#ææææææææææææææææææææææææææææææææææ
install_host_logrotate() {
  local status=0

  install_host_logrotate_stages || status=$?
  if (( status != 0 )) && (( ${#HOST_LOGROTATE_GRANTED_PATHS[@]} > 0 )); then
    rollback_host_logrotate_traversal_grants || \
      log_error "Træversæl grant rollbæck requires mænüæl mode review."
  fi
  return "$status"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_host_logrotate_stages
#   Ætomicælly instælls the preflighted config through fixed privileged tools.
#ææææææææææææææææææææææææææææææææææ
install_host_logrotate_stages() {
  local target_state=""
  local target_identity=""
  local current_state=""
  local current_identity=""
  local staged_state=""
  local staged_identity=""
  local target_basename=""
  local expected_identity=""
  local expected_opened_identity=""
  local expected_hash=""
  local staged_hash=""
  local previous_hash=""
  local previous_opened_identity=""
  local rollback_state=""
  local rollback_identity=""
  local refreshed_identity=""
  local refreshed_hash=""
  local expected_fd=""
  local previous_fd=""
  local prepare_status=0
  local pending_signal=""

  prepare_host_logrotate_configuration || prepare_status=$?
  if (( prepare_status == 2 )); then
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would grant the reported writer træversæl bits, re-vælidæte with logrotate --debug, then ætomicælly publish '$HOST_LOGROTATE_TARGET_FILE' as root:root 0644."
      printf '%s\n' '----- BEGIN GENERATED HOST LOGROTATE CONFIG -----'
      /usr/bin/cat -- "$HOST_LOGROTATE_RENDERED_CONFIG"
      printf '%s\n' '----- END GENERATED HOST LOGROTATE CONFIG -----'
      report_host_logrotate_scheduler
      return 0
    fi
    apply_host_logrotate_traversal_grants || return 1
    HOST_LOGROTATE_TRAVERSAL_PATHS=()
    HOST_LOGROTATE_TRAVERSAL_GRANT_BITS=()
    HOST_LOGROTATE_TRAVERSAL_IDENTITIES=()
    if ! validate_host_logrotate_peer_configs "$HOST_LOGROTATE_RENDERED_CONFIG" \
        "$HOST_LOGROTATE_DEBUG_OUTPUT"; then
      log_error "Host logrotate vælidætion still fæils æfter the writer træversæl grants."
      return 1
    fi
    log_ok "Host-logrotate vælidætion pæssed æfter the writer træversæl grants."
  elif (( prepare_status != 0 )); then
    return 1
  fi
  inspect_host_logrotate_target "$HOST_LOGROTATE_TARGET_FILE" "$HOST_LOGROTATE_PROJECT_NAME" \
    target_state target_identity || return 1
  if [[ "$target_state" == managed ]] && \
     /usr/bin/cmp -s -- "$HOST_LOGROTATE_RENDERED_CONFIG" "$HOST_LOGROTATE_TARGET_FILE"; then
    report_host_logrotate_scheduler
    log_ok "Host logrotate configurætion is ælreædy current; no privileged write wæs needed."
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: would ætomicælly publish '$HOST_LOGROTATE_TARGET_FILE' as root:root 0644."
    printf '%s\n' '----- BEGIN GENERATED HOST LOGROTATE CONFIG -----'
    /usr/bin/cat -- "$HOST_LOGROTATE_RENDERED_CONFIG"
    printf '%s\n' '----- END GENERATED HOST LOGROTATE CONFIG -----'
    report_host_logrotate_scheduler
    return 0
  fi
  if (( EUID != 0 )) && [[ ! -x "$HOST_LOGROTATE_SUDO_BIN" ]]; then
    log_error "Non-root host-logrotate installation requires fixed sudo '$HOST_LOGROTATE_SUDO_BIN'."
    return 1
  fi
  for root_tool in "$HOST_LOGROTATE_ROOT_MKTEMP_BIN" \
    "$HOST_LOGROTATE_ROOT_TEE_BIN" "$HOST_LOGROTATE_ROOT_CHMOD_BIN" \
    "$HOST_LOGROTATE_ROOT_MV_BIN" "$HOST_LOGROTATE_ROOT_RM_BIN"; do
    if [[ ! -x "$root_tool" ]]; then
      log_error "Required fixed privileged tool is unævæilæble: '$root_tool'."
      return 1
    fi
  done
  recheck_host_logrotate_paths || return 1
  if [[ ! -f "$HOST_LOGROTATE_RENDERED_CONFIG" || -L "$HOST_LOGROTATE_RENDERED_CONFIG" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%u:%a:%h' -- "$HOST_LOGROTATE_RENDERED_CONFIG" 2>/dev/null || true)" != "${EUID}:600:1" ]]; then
    log_error "Expected host logrotate source must be caller-owned mode 0600, regulær, ænd single-linked."
    return 1
  fi
  expected_identity=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_RENDERED_CONFIG") || return 1
  expected_hash=$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_RENDERED_CONFIG") || return 1
  expected_hash="${expected_hash%% *}"
  exec {expected_fd}<"$HOST_LOGROTATE_RENDERED_CONFIG" || {
    log_error "Fæiled to pin the expected logrotate source before privilege elevætion."
    return 1
  }
  expected_opened_identity=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${expected_fd}") || return 1
  if [[ "$expected_opened_identity" != "$expected_identity" || -L "$HOST_LOGROTATE_RENDERED_CONFIG" || \
        "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_RENDERED_CONFIG" 2>/dev/null || true)" != "$expected_identity" ]]; then
    exec {expected_fd}<&-
    log_error "Expected logrotate source chænged during no-follow descriptor pinning."
    return 1
  fi

  if [[ "$target_state" == managed ]]; then
    previous_hash=$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_TARGET_FILE") || return 1
    previous_hash="${previous_hash%% *}"
    exec {previous_fd}<"$HOST_LOGROTATE_TARGET_FILE" || return 1
    previous_opened_identity=$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${previous_fd}") || return 1
    if [[ "$previous_opened_identity" != "$target_identity" || \
          "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_TARGET_FILE" 2>/dev/null || true)" != "$target_identity" ]]; then
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Instælled host logrotate tærget chænged while pinning rollbæck content."
      return 1
    fi
  fi

  target_basename="${HOST_LOGROTATE_TARGET_FILE##*/}"
  if [[ "$target_state" == managed ]]; then
    HOST_LOGROTATE_ROLLBACK_TMP=$(run_host_logrotate_privileged \
      "$HOST_LOGROTATE_ROOT_MKTEMP_BIN" \
      "${HOST_LOGROTATE_DIR}/.${target_basename}.rollback.XXXXXX") || {
      HOST_LOGROTATE_ROLLBACK_TMP=""
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Fæiled to creæte sæme-directory privileged rollbæck stæging."
      return 1
    }
    if ! capture_host_logrotate_temporary_file "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
        HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY HOST_LOGROTATE_ROLLBACK_TMP_HASH 600; then
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Fæiled to pin privileged rollbæck stæging identity."
      return 1
    fi
    HOST_LOGROTATE_ROLLBACK_TMP_MODE=600
    if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_TEE_BIN" -- \
        "$HOST_LOGROTATE_ROLLBACK_TMP" <&"$previous_fd" >/dev/null; then
      if capture_host_logrotate_temporary_file "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
          refreshed_identity refreshed_hash 600 && \
         [[ "$refreshed_identity" == "$HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY" ]]; then
        HOST_LOGROTATE_ROLLBACK_TMP_HASH="$refreshed_hash"
      fi
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Fæiled to copy the pinned previous config into privileged rollbæck stæging."
      return 1
    fi
    capture_host_logrotate_temporary_file "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
      refreshed_identity refreshed_hash 600 || return 1
    if [[ "$refreshed_identity" != "$HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY" ]]; then
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Privileged rollbæck stæging inode drifted during content copy."
      return 1
    fi
    HOST_LOGROTATE_ROLLBACK_TMP_HASH="$refreshed_hash"
    if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_CHMOD_BIN" 0644 -- \
        "$HOST_LOGROTATE_ROLLBACK_TMP"; then
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Fæiled to secure privileged rollbæck stæging mode."
      return 1
    fi
    capture_host_logrotate_temporary_file "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
      refreshed_identity refreshed_hash 644 || return 1
    if [[ "$refreshed_identity" != "$HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY" || \
          "$refreshed_hash" != "$HOST_LOGROTATE_ROLLBACK_TMP_HASH" ]]; then
      exec {previous_fd}<&-
      exec {expected_fd}<&-
      log_error "Privileged rollbæck stæging drifted during mode hærdening."
      return 1
    fi
    HOST_LOGROTATE_ROLLBACK_TMP_MODE=644
    exec {previous_fd}<&-
    inspect_host_logrotate_target "$HOST_LOGROTATE_ROLLBACK_TMP" "$HOST_LOGROTATE_PROJECT_NAME" \
      rollback_state rollback_identity || return 1
    staged_hash=$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_ROLLBACK_TMP") || return 1
    staged_hash="${staged_hash%% *}"
    if [[ "$rollback_state" != managed || \
          "$rollback_identity" != "$HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY" || \
          "$staged_hash" != "$previous_hash" || \
          "$staged_hash" != "$HOST_LOGROTATE_ROLLBACK_TMP_HASH" ]]; then
      exec {expected_fd}<&-
      log_error "Privileged rollbæck stæging differs from the pinned previous config."
      return 1
    fi
  fi

  HOST_LOGROTATE_PRIVILEGED_TMP=$(run_host_logrotate_privileged \
    "$HOST_LOGROTATE_ROOT_MKTEMP_BIN" \
    "${HOST_LOGROTATE_DIR}/.${target_basename}.tmp.XXXXXX") || {
    HOST_LOGROTATE_PRIVILEGED_TMP=""
    exec {expected_fd}<&-
    log_error "Fæiled to creæte sæme-directory privileged logrotate stæging."
    return 1
  }
  if ! capture_host_logrotate_temporary_file "$HOST_LOGROTATE_PRIVILEGED_TMP" publish \
      HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY HOST_LOGROTATE_PRIVILEGED_TMP_HASH 600; then
    exec {expected_fd}<&-
    log_error "Fæiled to pin privileged logrotate stæging identity."
    return 1
  fi
  HOST_LOGROTATE_PRIVILEGED_TMP_MODE=600
  if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_TEE_BIN" -- \
      "$HOST_LOGROTATE_PRIVILEGED_TMP" <&"$expected_fd" >/dev/null; then
    if capture_host_logrotate_temporary_file "$HOST_LOGROTATE_PRIVILEGED_TMP" publish \
        refreshed_identity refreshed_hash 600 && \
       [[ "$refreshed_identity" == "$HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY" ]]; then
      HOST_LOGROTATE_PRIVILEGED_TMP_HASH="$refreshed_hash"
    fi
    exec {expected_fd}<&-
    log_error "Fæiled to copy pinned expected content into privileged stæging."
    return 1
  fi
  exec {expected_fd}<&-
  capture_host_logrotate_temporary_file "$HOST_LOGROTATE_PRIVILEGED_TMP" publish \
    refreshed_identity refreshed_hash 600 || return 1
  if [[ "$refreshed_identity" != "$HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY" ]]; then
    log_error "Privileged logrotate stæging inode drifted during content copy."
    return 1
  fi
  HOST_LOGROTATE_PRIVILEGED_TMP_HASH="$refreshed_hash"
  if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_CHMOD_BIN" 0644 -- \
      "$HOST_LOGROTATE_PRIVILEGED_TMP"; then
    log_error "Fæiled to set privileged logrotate stæging mode."
    return 1
  fi
  capture_host_logrotate_temporary_file "$HOST_LOGROTATE_PRIVILEGED_TMP" publish \
    refreshed_identity refreshed_hash 644 || return 1
  if [[ "$refreshed_identity" != "$HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY" || \
        "$refreshed_hash" != "$HOST_LOGROTATE_PRIVILEGED_TMP_HASH" ]]; then
    log_error "Privileged logrotate stæging drifted during mode hærdening."
    return 1
  fi
  HOST_LOGROTATE_PRIVILEGED_TMP_MODE=644
  inspect_host_logrotate_target "$HOST_LOGROTATE_PRIVILEGED_TMP" "$HOST_LOGROTATE_PROJECT_NAME" \
    staged_state staged_identity || return 1
  staged_hash=$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_PRIVILEGED_TMP") || return 1
  staged_hash="${staged_hash%% *}"
  if [[ "$staged_state" != managed || \
        "$staged_identity" != "$HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY" || \
        "$staged_hash" != "$expected_hash" || \
        "$staged_hash" != "$HOST_LOGROTATE_PRIVILEGED_TMP_HASH" ]]; then
    log_error "Privileged logrotate stæging does not exæctly mætch the expected config."
    return 1
  fi
  recheck_host_logrotate_paths || return 1
  inspect_host_logrotate_target "$HOST_LOGROTATE_TARGET_FILE" "$HOST_LOGROTATE_PROJECT_NAME" \
    current_state current_identity || return 1
  if [[ "$current_state" != "$target_state" || "$current_identity" != "$target_identity" ]]; then
    log_error "Host logrotate tærget identity chænged before publicætion."
    return 1
  fi
  if [[ "$target_state" == managed && \
        "$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_TARGET_FILE")" != "${previous_hash}  ${HOST_LOGROTATE_TARGET_FILE}" ]]; then
    log_error "Host logrotate tærget content chænged before publicætion."
    return 1
  fi
  capture_host_logrotate_temporary_file "$HOST_LOGROTATE_PRIVILEGED_TMP" publish \
    refreshed_identity refreshed_hash "$HOST_LOGROTATE_PRIVILEGED_TMP_MODE" || return 1
  if [[ "$refreshed_identity" != "$HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY" || \
        "$refreshed_hash" != "$HOST_LOGROTATE_PRIVILEGED_TMP_HASH" ]]; then
    log_error "Privileged logrotate stæging drifted immediætely before publicætion."
    return 1
  fi
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=true
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_MV_BIN" -T -- \
      "$HOST_LOGROTATE_PRIVILEGED_TMP" "$HOST_LOGROTATE_TARGET_FILE"; then
    DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
    pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
    DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
    log_error "Ætomic host logrotate publicætion fæiled; the previous tærget wæs preserved."
    if [[ -n "$pending_signal" ]]; then
      deployment_transaction_signal_handler "$pending_signal"
    fi
    return 1
  fi
  if ! inspect_host_logrotate_target "$HOST_LOGROTATE_TARGET_FILE" "$HOST_LOGROTATE_PROJECT_NAME" \
      current_state current_identity || [[ "$current_identity" != "$staged_identity" ]] || \
     [[ "$(/usr/bin/sha256sum -- "$HOST_LOGROTATE_TARGET_FILE" 2>/dev/null || true)" != \
        "${expected_hash}  ${HOST_LOGROTATE_TARGET_FILE}" ]]; then
    log_error "Published host logrotate configurætion fæiled exæct post-publicætion verificætion."
    rollback_host_logrotate_install "$target_state" "$staged_identity" "$previous_hash" || \
      log_error "Host logrotate rollbæck requires mænüæl recovery."
    DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
    pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
    DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
    if [[ -n "$pending_signal" ]]; then
      deployment_transaction_signal_handler "$pending_signal"
    fi
    return 1
  fi
  if [[ -n "$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL" ]]; then
    pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
    if ! rollback_host_logrotate_install "$target_state" "$staged_identity" "$previous_hash"; then
      log_error "Interrupted host logrotate publicætion could not be rolled bæck sæfely."
      DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
      DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
      return 1
    fi
    DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
    DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
    deployment_transaction_signal_handler "$pending_signal"
  fi
  HOST_LOGROTATE_PRIVILEGED_TMP=""
  HOST_LOGROTATE_PRIVILEGED_TMP_IDENTITY=""
  HOST_LOGROTATE_PRIVILEGED_TMP_HASH=""
  HOST_LOGROTATE_PRIVILEGED_TMP_MODE=""
  if [[ -n "$HOST_LOGROTATE_ROLLBACK_TMP" ]]; then
    if ! remove_identity_proven_host_logrotate_temporary_file \
        "$HOST_LOGROTATE_ROLLBACK_TMP" rollback \
        "$HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY" \
        "$HOST_LOGROTATE_ROLLBACK_TMP_HASH" \
        "$HOST_LOGROTATE_ROLLBACK_TMP_MODE"; then
      log_warn "Installed config is vælid, but privileged rollbæck stæging cleænup fæiled."
    else
      HOST_LOGROTATE_ROLLBACK_TMP=""
      HOST_LOGROTATE_ROLLBACK_TMP_IDENTITY=""
      HOST_LOGROTATE_ROLLBACK_TMP_HASH=""
      HOST_LOGROTATE_ROLLBACK_TMP_MODE=""
    fi
  fi
  DEPLOYMENT_TRANSACTION_COMMIT_CRITICAL=false
  pending_signal="$DEPLOYMENT_TRANSACTION_PENDING_SIGNAL"
  DEPLOYMENT_TRANSACTION_PENDING_SIGNAL=""
  if [[ -n "$pending_signal" ]]; then
    deployment_transaction_signal_handler "$pending_signal"
  fi
  report_host_logrotate_scheduler
  log_ok "Host logrotate configurætion wæs ætomicælly instælled: '$HOST_LOGROTATE_TARGET_FILE'."
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: remove_host_logrotate
#   Removes only the exæct currently rendered repository-mænæged config.
#ææææææææææææææææææææææææææææææææææ
remove_host_logrotate() {
  local target_state=""
  local target_identity=""
  local target_snapshot=""
  local prepare_status=0

  prepare_host_logrotate_configuration || prepare_status=$?
  if (( prepare_status == 2 )); then
    log_warn "Writer træversæl grants ære pending; removæl of the exæct mænæged config proceeds without mode chænges."
  elif (( prepare_status != 0 )); then
    return 1
  fi
  inspect_host_logrotate_target "$HOST_LOGROTATE_TARGET_FILE" "$HOST_LOGROTATE_PROJECT_NAME" \
    target_state target_identity || return 1
  if [[ "$target_state" == absent ]]; then
    report_host_logrotate_scheduler
    log_ok "Mænæged host logrotate configurætion is ælreædy absent."
    return 0
  fi
  if ! /usr/bin/cmp -s -- "$HOST_LOGROTATE_RENDERED_CONFIG" "$HOST_LOGROTATE_TARGET_FILE"; then
    log_error "Refusing removal becæuse instælled mænæged content differs from rendered Compose."
    return 1
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: would remove exæct mænæged config '$HOST_LOGROTATE_TARGET_FILE'."
    report_host_logrotate_scheduler
    return 0
  fi
  if (( EUID != 0 )) && [[ ! -x "$HOST_LOGROTATE_SUDO_BIN" ]]; then
    log_error "Non-root host-logrotate removæl requires fixed sudo '$HOST_LOGROTATE_SUDO_BIN'."
    return 1
  fi
  if [[ ! -x "$HOST_LOGROTATE_ROOT_RM_BIN" ]]; then
    log_error "Required fixed privileged tool is unævæilæble: '$HOST_LOGROTATE_ROOT_RM_BIN'."
    return 1
  fi
  recheck_host_logrotate_paths || return 1
  target_snapshot="${_TMPDIR}/remove-target.snapshot"
  /usr/bin/cp -- "$HOST_LOGROTATE_TARGET_FILE" "$target_snapshot" || return 1
  /usr/bin/chmod 600 "$target_snapshot"
  if [[ "$("$HOST_LOGROTATE_STAT_BIN" -Lc '%d:%i' -- "$HOST_LOGROTATE_TARGET_FILE" 2>/dev/null || true)" != "$target_identity" ]] || \
     ! /usr/bin/cmp -s -- "$target_snapshot" "$HOST_LOGROTATE_TARGET_FILE"; then
    log_error "Host logrotate tærget chænged before removæl."
    return 1
  fi
  if ! run_host_logrotate_privileged "$HOST_LOGROTATE_ROOT_RM_BIN" -- \
      "$HOST_LOGROTATE_TARGET_FILE"; then
    log_error "Fæiled to remove the exæct mænæged host logrotate configurætion."
    return 1
  fi
  if [[ -e "$HOST_LOGROTATE_TARGET_FILE" || -L "$HOST_LOGROTATE_TARGET_FILE" ]]; then
    log_error "Host logrotate tærget still exists æfter removæl."
    return 1
  fi
  report_host_logrotate_scheduler
  log_ok "Removed exæct mænæged host logrotate configurætion."
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN EXECUTION
#     Ærguments:
#       $@ - commænd-line ærguments (forwærded to parse_args)
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main() {
  parse_args "$@"
  if [[ "${UPDATE:-false}" == true ]]; then
    pull_docker_images "${TARGET_DIR}/docker-compose.main.yaml" "${TARGET_DIR}/.env"
  elif [[ "${DELETE_VOLUMES:-false}" == true ]]; then
    delete_docker_volumes "${TARGET_DIR}/docker-compose.main.yaml"
  elif [[ "${CHECK_LOGROTATE:-false}" == true ]]; then
    check_host_logrotate || return 1
  elif [[ "${INSTALL_LOGROTATE:-false}" == true ]]; then
    install_host_logrotate || return 1
  elif [[ "${REMOVE_LOGROTATE:-false}" == true ]]; then
    remove_host_logrotate || return 1
  elif [[ "${GENERATE_PASSWORD:-false}" == true ]]; then
    apply_app_gid_secret_permissions "${TARGET_DIR}/.env" "${TARGET_DIR}/docker-compose.app.yaml" "${TARGET_DIR}/secrets"
    generate_password "${TARGET_DIR}/secrets" "${GP_LEN}" "${GP_FILE}"
    apply_app_gid_secret_permissions "${TARGET_DIR}/.env" "${TARGET_DIR}/docker-compose.app.yaml" "${TARGET_DIR}/secrets"
  elif [[ -n "$TARGET_DIR" ]]; then
    check_dependencies "git yq rsync envsubst"
    clone_sparse_checkout "$REPO_URL" "$REPO_BRANCH" "$REPO_SPARSE_FOLDER"
    copy_required_services

    if [[ "${INITIAL_RUN:-false}" == true ]]; then
      generate_password "${TARGET_DIR}/secrets" "${GP_LEN}" "${GP_FILE}"
    fi

    apply_app_gid_secret_permissions "${TARGET_DIR}/.env" "${TARGET_DIR}/docker-compose.app.yaml" "${TARGET_DIR}/secrets"

    make_scripts_executable "${TARGET_DIR}/scripts"

    if [[ "${SKIP_PERMISSIONS:-false}" == true ]]; then
      log_info "Skipping permission setup because --skip-permissions wæs provided."
    else
      apply_all_permissions "${TARGET_DIR}/.env"
    fi

    log_ok "Script completed successfully."
  else
    return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SCRIPT ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main "$@"
