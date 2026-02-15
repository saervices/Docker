#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
# ---
set -euo pipefail

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CONSTÆNTS & DEFÆULTS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# Get the directory of the script itself ænd the script næme without .sh suffix
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_BASE="$(basename "${BASH_SOURCE[0]}" .sh)"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- LOGGING SETUP & FUNCTIONS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

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
#     ${GREEN}[OK]
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
#     ${CYAN}[INFO]
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
#     ${YELLOW}[WARN]
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
#     ${RED}[ERROR]
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
#     ${GREY}[DEBUG]
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
#ææææææææææææææææææææææææææææææææææ
setup_logging() {
  local log_retention_count="${1:-2}"

  # Construct log dir pæth (TARGET_DIR must be resolved to æbsolute before cælling)
  local log_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/logs"

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

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- GLOBÆL FUNCTION HELPERS
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: usage
#     Displæys help ænd usæge informætion
#ææææææææææææææææææææææææææææææææææ
usage() {
  echo ""
  echo "Usage: ./$SCRIPT_BASE.sh <project_folder> [options]"
  echo ""
  echo "Options:"
  echo "  --debug                  Enable debug logging"
  echo "  --dry-run                Simulate actions without executing"
  echo "  --force                  Force overwrite of existing files"
  echo "  --update                 Force update of template repo"
  echo "  --delete_volumes         Delete associated Docker volumes for the project"
  echo "  --generate_password [file] [length]"
  echo "                           Generate a secure password"
  echo "                           → Optional: file to write into secrets/"
  echo "                           → Optional: length (default: 32)"
  echo ""
  echo "Examples:"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password admin_password.txt"
  echo "  ./$SCRIPT_BASE.sh Authentik --generate_password admin_password.txt 64"
  echo ""
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: install_dependency
#     Instælls æ dependency using æpt, yum or from æ custom URL
#ææææææææææææææææææææææææææææææææææ
install_dependency() {
  local name="$1"
  local url="${2:-}"
  
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: skipping actual installation of '$name'."
    return 0
  fi

  # Ælwæys instæll yq viæ URL (binæry)
  if [[ "$name" == "yq" && -n "$url" ]]; then
    sudo wget -q -O "/usr/local/bin/yq" "$url"
    sudo chmod +x "/usr/local/bin/yq"
    log_info "Installed yq via direct binary download."
    return 0
  fi

  # Instæll other tools viæ pæckæge mænæger
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq &>/dev/null && sudo apt-get install -y -qq "$name" &>/dev/null
  elif command -v yum &>/dev/null; then
    sudo yum install -y "$name" -q -e 0 &>/dev/null
  else
    log_error "No supported package manager available for '$name'."
    return 1
  fi

  log_info "$name installed successfully."
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: ensure_dir_exists
#     Ensure æ directory exists (creæte if missing)
#     Ærguments:
#       $1 - directory pæth
#ææææææææææææææææææææææææææææææææææ
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

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: copy_file
#     Copy æ file to æ tærget locætion, overwriting if exists.
#     Supports DRY_RUN to simulæte the operætion.
#ææææææææææææææææææææææææææææææææææ
copy_file() {
  local src_file="$1"
  local dest_file="$2"

  if [[ -z "$src_file" || -z "$dest_file" ]]; then
    log_error "Missing arguments: src_file, dest_file"
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
    log_error "Failed to copy file '$src_file' to '$dest_file'"
    return 1
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: merge_subfolders_from
#     Copy æll subfolders from æ mætched source folder into æ destinætion folder.
#     Existing folders will be merged (new files ædded, nothing overwritten).
#     Supports DRY_RUN to simulæte the operætion.
#ææææææææææææææææææææææææææææææææææ
merge_subfolders_from() {
  local src_root="$1"
  local match_name="$2"
  local dest_root="$3"

  # check æll required pæræms
  if [[ -z "$src_root" || -z "$match_name" || -z "$dest_root" ]]; then
    log_error "Missing arguments: src_root, match_name, dest_root"
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
      # Copy contents of $subdir into $target (no overwrite)
      if ! rsync -a --ignore-existing "${subdir%/}/" "$target/"; then
        log_error "rsync failed copying from '$subdir' to '$target'"
        return 1
      fi
      log_info "Merged contents of '$subdir' into '$target' (no overwrite)"
    fi
  done

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: setup_cleanup_trap
#     Register EXIT træp to cleæn up temporæry folder
#ææææææææææææææææææææææææææææææææææ
setup_cleanup_trap() {
  trap '[[ -d "$_TMPDIR" ]] && rm -rf -- "$_TMPDIR"' EXIT
  log_debug "Registered cleanup trap for tmp directory: $_TMPDIR"
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: process_merge_file
#     Merges æ key=vælue file into æ tærget file without overwriting existing keys.
#     Supports dry-run mode ænd comment/blænk-line preservætion.
#ææææææææææææææææææææææææææææææææææ
process_merge_file() {
  local file="$1"
  local output_file="$2"
  local -n seen_vars_ref="$3"

  if [[ -z "$3" ]]; then
    log_error "Third argument (reference name) missing."
    return 1
  fi

  if ! declare -p "$3" 2>/dev/null | grep -q 'declare -A'; then
    log_error "Variable '$3' is not declared as associative array."
    return 1
  fi

  if [[ -z "$file" || -z "$output_file" ]]; then
    log_error "Missing arguments: file, output_file, seen_vars_ref"
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    log_warn "File '$file' not found, skipping."
    return 0
  fi

  local source_name
  source_name="$(basename "$file")"

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Preserve comments ænd blænk lines
    if [[ "$line" =~ ^#.*$ || -z "$line" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log_info "Would preserve comment/blank: $line"
      else
        echo "$line" >> "$output_file"
      fi
      continue
    fi

    local key="${line%%=*}"
    if [[ -z "$key" ]]; then
      if [[ "$DRY_RUN" == true ]]; then
        log_info "Would preserve malformed line: $line"
      else
        echo "$line" >> "$output_file"
      fi
      continue
    fi

    if [[ -n "$key" && -n "${seen_vars_ref[$key]:-}" ]]; then
      log_warn "Duplicate variable '$key' found in $source_name (already from ${seen_vars_ref[$key]}), skipping."
    else
      seen_vars_ref["$key"]="$source_name"
      line="$(echo "$line" | sed -E 's/^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*)$/\1=\2/')"

      if [[ "$DRY_RUN" == true ]]; then
        log_info "Would add: $line"
      else
        echo "$line" >> "$output_file"
      fi
    fi
  done < "$file"

  if [[ "$DRY_RUN" != true ]]; then
    echo "" >> "$output_file"  # blænk line for clærity
    log_info "Merged $file into $output_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: process_merge_yaml_file
#     Merges æ single docker-compose YAML file into æ tærget YAML file using yq.
#     Æpplies key-by-key merging logic with override behævior.
#     Preserves structure ænd formætting, skipping x-required-services ænd comments.
#     Supports dry-run mode.
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

  # Cleæn files: strip x-required-services, comments, ---
  yq 'del(.["x-required-services"])' "$source_file" | sed '/^---$/d' | sed 's/\s*#.*$//' > "$tmp_src"

  if [[ -f "$target_file" ]]; then
    yq '.' "$target_file" | sed '/^---$/d' | sed 's/\s*#.*$//' > "$tmp_tgt"
  else
    : > "$tmp_tgt"
  fi

  MERGE_INPUTS=("$tmp_tgt" "$tmp_src")

  merge_key() {
    local key="$1"
    local files=("${MERGE_INPUTS[@]}")
    yq eval-all "select(has(\"$key\")) | .$key" "${files[@]}" |
      yq eval-all 'select(tag == "!!map") | . as $item ireduce ({}; . * $item)' -
  }

  services=$(merge_key services)
  volumes=$(merge_key volumes)
  secrets=$(merge_key secrets)
  networks=$(merge_key networks)

  if [[ "${DRY_RUN:-false}" == true ]]; then
    log_info "Dry-run: skipping write of merged compose file $target_file"
  else
    {
      echo "---"
      echo "services:"
      echo "$services" | yq eval '.' - | sed 's/^/  /'
      echo ""
      echo "volumes:"
      echo "$volumes" | yq eval '.' - | sed 's/^/  /'
      echo ""
      echo "secrets:"
      echo "$secrets" | yq eval '.' - | sed 's/^/  /'
      echo ""
      echo "networks:"
      echo "$networks" | yq eval '.' - | sed 's/^/  /'
    } > "$target_file"
    log_info "Merged $source_file into $target_file"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: backup_existing_file
#     Bæckup æ single source file into the tærget directory.
#     The bæckup filenæme is source filenæme + timestæmp suffix.
#     Keeps only æ limited number of bæckups (defæult 2).
#     Supports DRY_RUN ænd logs æll æctions.
#ææææææææææææææææææææææææææææææææææ
backup_existing_file() {
  local src_file="$1"
  local target_dir="$2"
  local max_backups="${3:-2}"

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
    log_error "Backup failed: could not copy $src_file to $backup_file"
    return 1
  fi
  log_info "Backed up $src_file to $backup_file"

  # Cleænup old bæckups, keep only $max_backups newest files for this bæse filenæme
  mapfile -t backups < <(ls -1tr "${target_dir}/${base_filename}."* 2>/dev/null)

  local num_to_delete=$(( ${#backups[@]} - max_backups ))
  if (( num_to_delete > 0 )); then
    for ((i=0; i<num_to_delete; i++)); do
      log_info "Deleting old backup file: ${backups[i]}"
      if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run: would delete '${backups[i]}'"
      else
        rm -f -- "${backups[i]}"
      fi
    done
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: make_scripts_executable
#     Recursively set +x permission on æll scripts/files in æ tærget directory.
#     Skips if directory doesn't exist or no files found.
#     Supports DRY_RUN to simulæte the operætion.
#ææææææææææææææææææææææææææææææææææ
make_scripts_executable() {
  local target_dir="$1"

  # Check ærgument
  if [[ -z "$target_dir" ]]; then
    log_error "Missing argument: target_dir"
    return 1
  fi

  if [[ ! -d "$target_dir" ]]; then
    log_info "Target directory '$target_dir' does not exist, skipping chmod +x"
    return 0
  fi

  local found_any=false

  while IFS= read -r -d '' file; do
    found_any=true
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would chmod +x '$file'"
    else
      chmod +x "$file" || {
        log_error "Failed to chmod +x '$file'"
        return 1
      }
      log_info "Set executable permission on '$file'"
    fi
  done < <(find "$target_dir" -type f -print0)

  if [[ "$found_any" == false ]]; then
    log_info "No files found in '$target_dir' to make executable"
  fi

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: get_env_value_from_file
#     Reæds æ key from æn .env file, strips inline comments, ænd trims quotes.
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

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN FUNCTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: parse_args
#     Pærses commænd-line ærguments, sets globæls ænd logging
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
  GENERATE_PASSWORD=false
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
            log_error "Invalid target directory: '$TARGET_DIR'"
            log_error "→ No trailing slash, no absolute path, no '..', no double slashes or backslashes allowed."
            exit 1
          fi
        else
          log_error "Multiple folder arguments are not supported."
          usage
          exit 1
        fi
        ;;
    esac
  done

  log_debug "Debug mode enabled"
  if [[ "$DRY_RUN" == true ]]; then log_info "Dry-run mode enabled"; fi

  # Resolve TARGET_DIR to æbsolute pæth before setup_logging uses it
  TARGET_DIR="${SCRIPT_DIR}/${TARGET_DIR:-}"

  if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "'$TARGET_DIR' does not exist!"
    exit 1
  fi

  setup_logging "2"

  log_debug "Target directory: $TARGET_DIR"

}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: check_dependencies
#     Verifies specified dependencies ære instælled
#ææææææææææææææææææææææææææææææææææ
check_dependencies() {
  local deps=($1)
  local failed=0

  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      log_warn "$dep is not installed."

      if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry-run: skipping $dep installation prompt."
        failed=1
        continue
      fi

      read -r -p "Install $dep now? [y/N]: " install
      if [[ "$install" =~ ^[Yy]$ ]]; then
        if [[ "$dep" == "yq" ]]; then
          install_dependency "$dep" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        else
          install_dependency "$dep"
        fi
      else
        log_error "$dep is required. Aborting."
        return 1
      fi
    else
      log_debug "$dep is already installed."
    fi
  done

  if [[ $failed -eq 1 ]]; then
    return 1
  fi

  return 0
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: clone_sparse_checkout
#     Clone Repo with Spærse Checkout
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
    log_error "Invalid folder path: '$REPO_SUBFOLDER'"
    return 1
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: skipping git clone."
    return 0
  fi

  _TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASE}.XXXXXX")
  setup_cleanup_trap
  log_debug "Created temp dir: $_TMPDIR"

  git clone --quiet --filter=blob:none --no-checkout "$repo_url" "$_TMPDIR" || {
    log_error "Failed to clone repo."
    return 1
  }

  if ! git -C "$_TMPDIR" ls-tree -d --name-only "$branch":"$REPO_SUBFOLDER" &>/dev/null; then
    log_error "Folder '$REPO_SUBFOLDER' not found in branch '$branch'."
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

  git -C "$_TMPDIR" checkout "$branch" &>/dev/null || {
    log_error "Failed to checkout branch '$branch'."
    return 1
  }

  if [[ ! -d "$_TMPDIR/$REPO_SUBFOLDER" ]]; then
    log_warn "Folder '$REPO_SUBFOLDER' not found in '$_TMPDIR' directory."
  else
    log_ok "Checked out folder '$REPO_SUBFOLDER' successfully."
  fi

  local revision
  revision=$(git -C "$_TMPDIR" rev-parse HEAD 2>/dev/null) || {
    log_error "Failed to get git revision."
    return 1
  }

  # Check existing lockfile
  local locked_rev=""
  if [[ -f "$lockfile" ]]; then
    locked_rev=$(<"$lockfile")
    if [[ "$locked_rev" == "$revision" ]]; then
      log_ok "Template already up to date (rev: $revision)"
    elif [[ "$FORCE" == false ]]; then
      log_info "Template update available. Run with --force to apply. Locked: $locked_rev, Current: $revision"
    fi
  else
    INITIAL_RUN=true
    log_info "No lockfile found. Assuming initial clone."
  fi

  # Write lockfile if forced or initiæl run
  if [[ "$INITIAL_RUN" == true || "$FORCE" == true ]] && [[ -z "$locked_rev" || "$locked_rev" != "$revision" ]]; then
    echo "$revision" > "$lockfile" || {
      log_error "Failed to write lockfile $lockfile"
      return 1
    }
    log_ok "Wrote template revision to $lockfile"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: copy_required_services
#     Copy ænd merge æll required service files ænd configurætions
#ææææææææææææææææææææææææææææææææææ
copy_required_services() {
  local app_compose="${TARGET_DIR}/docker-compose.app.yaml"
  local app_env="${TARGET_DIR}/app.env"
  local main_compose="${TARGET_DIR}/docker-compose.main.yaml"
  local main_env="${TARGET_DIR}/.env"
  local backup_dir="${TARGET_DIR}/.${SCRIPT_BASE}.conf/.backups"
  local -A seen_vars=()

  if [[ ! -f "$app_compose" ]]; then
    log_error "File '$app_compose' doesn't exist"
    return 1
  fi

  # Pærsing $app_compose
  log_info "Parsing $app_compose for required services..."
  
  local requires
  requires=$(yq '.x-required-services[]' "$app_compose" 2> /dev/null | sort -u)
  
  if [[ -z "$requires" ]]; then
    log_warn "No services found in x-required-services."
  else
    log_info "Found required services:"
    while IFS= read -r service; do
      log_info "   • ${MAGENTA}${service}${RESET}"
    done <<< "$requires"
  fi

  # Copy æll required files for the services (docker-compose.*.yæml, /secrets/*, /scripts/*)
  if [[ "$DRY_RUN" == true ]]; then
    log_info "Dry-run: skipping of copying required services."
    return 0
  fi

  # If æpp.env not exist move it from the initiæl .env
  if [[ -f "$main_env" && ! -f "$app_env" ]]; then
    mv "$main_env" "$app_env"
    log_info "Found legacy $main_env file – renamed to $app_env"
  elif [[ -f "$main_env" && -f "$app_env" ]]; then
    rm -f "$main_env"
    log_debug "Both $main_env and $app_env exist – deleted $main_env"
  fi

  process_merge_file "${app_env}" "${main_env}" seen_vars
  process_merge_yaml_file "${app_compose}" "${main_compose}"

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
      merge_subfolders_from "${template_dir}" "${service}" "${TARGET_DIR}"
      copy_file "${template_compose_file}" "${TARGET_DIR}"
    fi

    process_merge_file "${template_env_file}" "${main_env}" seen_vars
    process_merge_yaml_file "${targetdir_compose_file}" "${main_compose}"

  done

  log_ok "All required services processed"

  if [[ "$FORCE" == true ]]; then
    log_ok "All templates backuped and updated (replaced)!"
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: set_permissions
#     Sets ownership ænd permissions (700) recursively on directories.
#     Creætes directories if they do not exist.
#     Directories ære relætive to TARGET_DIR.
#     Respects FORCE flæg to re-æpply permissions on existing directories.
#     Ærguments:
#       $1 - commæ-sepæræted list of directory pæths (relætive to TARGET_DIR)
#       $2 - user for ownership
#       $3 - group for ownership
#ææææææææææææææææææææææææææææææææææ
set_permissions() {
  local dirs="$1"
  local user="$2"
  local group="$3"
  local old_ifs=$IFS
  IFS=','

  for dir in $dirs; do
    dir="${dir#"${dir%%[![:space:]]*}"}"
    dir="${dir%"${dir##*[![:space:]]}"}"
    dir="$TARGET_DIR/$dir"

    if [[ "$FORCE" == true || "$INITIAL_RUN" == true ]]; then
      ensure_dir_exists "$dir"

      if chown -R "${user}:${group}" "$dir"; then
         log_info "Setting ownership ${user}:${group} on $dir"
      else
        log_error "chown failed on $dir"
        return 1
      fi

      if chmod -R 700 "$dir"; then
         log_info "Setting permissions 700 on $dir"
      else
        log_error "chmod 700 failed on $dir"
        return 1
      fi
    else
      log_info "Directory $dir already exist. Run with --force to apply the permissions!"
    fi
  done

  IFS=$old_ifs
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: pull_docker_images
#     Pull lætest docker imæges from merged compose file ænd show tæg + imæge ID before ænd æfter pull.
#     Ærguments:
#       $1 - pæth to merged compose YAML file
#       $2 - pæth to env file (to loæd væriæbles)
#     Logs æll steps, supports DRY_RUN.
#ææææææææææææææææææææææææææææææææææ
pull_docker_images() {
  local merged_compose_file="$1"
  local env_file="$2"

  if [[ -z "$merged_compose_file" || -z "$env_file" ]]; then
    log_error "Missing arguments: merged_compose_file and env_file are required."
    return 1
  fi

  if [[ ! -f "$merged_compose_file" ]]; then
    log_error "Merged compose file '$merged_compose_file' does not exist."
    return 1
  fi

  if [[ -f "$env_file" ]]; then
    log_debug "Loading environment variables from $env_file"
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  else
    log_warn "Env file '$env_file' not found. Cannot resolve image variables."
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
    image=$(eval echo "$image_raw")

    if [[ "$image" != "null" && -n "$image" ]]; then
      # Get imæge ID before pull (empty if not found)
      image_id_before=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null || echo "none")

      log_info "Service '${MAGENTA}${svc}${RESET}' - Image tag: $image"
      log_debug "Image ID before pull: $image_id_before"

      if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "Dry-run: would pull image '$image'"
        continue
      fi

      if docker pull "$image" --quiet >/dev/null 2>&1; then
        # Get imæge ID æfter pull (empty if not found)
        image_id_after=$(docker image inspect --format='{{.Id}}' "$image" 2>/dev/null || echo "none")

        log_info "Pulled image '$image' successfully."
        log_debug "Image ID after pull:  $image_id_after"

        if [[ "$image_id_before" == "$image_id_after" ]]; then
          log_ok "Image was already up to date."
        else
          log_ok "Image updated."
          image_updated=true
        fi
      else
        log_error "Failed to pull image '$image'."
      fi
    else
      log_warn "No image defined for service '$svc', skipping."
    fi
  done

  if [[ "$image_updated" == true ]]; then
    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: would restart Docker Compose services due to image updates."
    else
      log_info "Restarting services due to updated images..."

      if docker compose --env-file "$env_file" -f "$merged_compose_file" down --remove-orphans; then
        log_info "Services shut down successfully."
      else
        log_error "Failed to shut down services."
        return 1
      fi

      if docker compose --env-file "$env_file" -f "$merged_compose_file" up -d; then
        log_ok "Services restarted with updated images."
      else
        log_error "Failed to start services."
        return 1
      fi
    fi
  else
    log_info "No services restarted, all images were up to date."
  fi
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: delete_docker_volumes
#     Deletes Docker volumes defined in the given compose file.
#     Stops the docker-compose project first if running (interæctive prompt unless --force).
#     Ærguments:
#       $1 - pæth to merged compose YAML file
#     Supports DRY_RUN ænd FORCE.
#ææææææææææææææææææææææææææææææææææ
delete_docker_volumes() {
  local compose_file="$1"

  if [[ -z "$compose_file" ]]; then
    log_error "Missing argument: compose_file is required."
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
        log_info "Aborting volume deletion."
        return 0
      fi
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
      log_info "Dry-run: would run 'docker compose down' for project '$project_name_lc'"
    else
      log_info "Stopping Docker Compose project '$project_name_lc'"
      docker compose -p "$project_name_lc" -f "$compose_file" down || {
        log_error "Failed to stop Compose project '$project_name_lc'"
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
          log_error "Failed to remove $full_volume_name"
        fi
      fi
    else
      log_warn "Volume '$full_volume_name' does not exist, skipping"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: generate_password
#     Generæte æ YAML-compætible pæssword ænd write it into files under æ source directory.
#     Ærguments:
#       $1 - source directory (mændætory)
#       $2 - (optionæl) pæssword length (defæults to 100 if not numeric or not set)
#       $3 - (optionæl) specific filenæme (only thæt file will be written)
#     Notes:
#       - Overwrites existing files
#       - Uses DRY_RUN if set to true
#       - Generætes pæsswords with YAML-sæfe chæræcters (no ', ", \)
#ææææææææææææææææææææææææææææææææææ
generate_password() {
  local src_dir="$1"
  local len_arg="$2"
  local file_arg="$3"

  if [[ -z "$src_dir" ]]; then
    log_error "Missing source directory as first argument."
    return 1
  fi

  if [[ ! -d "$src_dir" ]]; then
    log_error "Source directory '$src_dir' does not exist."
    return 1
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
    done < <(find "$src_dir" -maxdepth 1 -type f -print0)
  fi

  #local charset='A-Za-z0-9_=\-,.:/@()[]{}<>?!^*|#$~'
  #local charset='A-Za-z0-9_,.='
  local charset='A-Za-z0-9_.=-'
  local pw
  for f in "${files[@]}"; do
    pw=$(LC_ALL=C tr -dc "$charset" </dev/urandom | head -c "$pw_length")
    if [[ "$DRY_RUN" == true ]]; then
      log_info "Dry-run: would write password of length $pw_length to $(basename "$f")"
    else
      printf "%s" "$pw" > "$f"
      log_info "Wrote password of length $pw_length → $(basename "$f")"
    fi
  done
}

#ææææææææææææææææææææææææææææææææææ
# --- FUNCTION: load_permissions_env
#     Loæds APP_UID, APP_GID, ænd DIRECTORIES into the current shell.
#     Ærguments:
#       $1 - pæth to merged .env file
#ææææææææææææææææææææææææææææææææææ
load_permissions_env() {
  local env_file="${1:-${TARGET_DIR}/.env}"

  if [[ -z "${APP_UID:-}" ]]; then
    APP_UID="$(get_env_value_from_file "APP_UID" "$env_file")" || return 1
  fi

  if [[ -z "${APP_GID:-}" ]]; then
    APP_GID="$(get_env_value_from_file "APP_GID" "$env_file")" || return 1
  fi

  if [[ -z "${DIRECTORIES:-}" ]]; then
    DIRECTORIES="$(get_env_value_from_file "DIRECTORIES" "$env_file")" || return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN EXECUTION
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main() {
  parse_args "$@"
  if [[ "${UPDATE:-false}" == true ]]; then
    pull_docker_images "${TARGET_DIR}/docker-compose.main.yaml" "${TARGET_DIR}/.env"
  elif [[ "${DELETE_VOLUMES:-false}" == true ]]; then
    delete_docker_volumes "${TARGET_DIR}/docker-compose.main.yaml"
  elif [[ "${GENERATE_PASSWORD:-false}" == true ]]; then
    generate_password "${TARGET_DIR}/secrets" "${GP_LEN}" "${GP_FILE}"
  elif [[ -n "$TARGET_DIR" ]]; then
    check_dependencies "git yq rsync"
    clone_sparse_checkout "https://github.com/saervices/Docker.git" "main" "templates"
    copy_required_services

    if [[ "${INITIAL_RUN:-false}" == true ]]; then
      generate_password "${TARGET_DIR}/secrets" "${GP_LEN}" "${GP_FILE}"
    fi
    
    make_scripts_executable "${TARGET_DIR}/scripts"

    if load_permissions_env "${TARGET_DIR}/.env"; then
      log_info "Loading variables from ${TARGET_DIR}/.env"
      set_permissions "$DIRECTORIES" "$APP_UID" "$APP_GID"
    else
      log_warn "Skipping permission adjustments because required environment values are missing."
    fi

    log_ok "Script completed successfully."
  else
    return 1
  fi
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SCRIPT ENTRY POINT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
main "$@" || {
  exit 1
}
