#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
#
# Fæctorio server entrypoint
set -euo pipefail
umask 077

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Pæths
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
FACTORIO_BIN="${FACTORIO_BIN:-/opt/factorio/bin/x64/factorio}"
FACTORIO_VOL="${FACTORIO_VOL:-/factorio}"
CONFIG="${CONFIG:-${FACTORIO_VOL}/config}"
SAVES="${SAVES:-${FACTORIO_VOL}/saves}"
MODS="${MODS:-${FACTORIO_VOL}/mods}"
SCENARIOS="${SCENARIOS:-${FACTORIO_VOL}/scenarios}"
SCRIPTOUTPUT="${SCRIPTOUTPUT:-${FACTORIO_VOL}/script-output}"
RUNTIME_DIR="${RUNTIME_DIR:-/tmp/factorio-runtime}"

readonly FACTORIO_BIN
readonly FACTORIO_VOL
readonly CONFIG
readonly SAVES
readonly MODS
readonly SCENARIOS
readonly SCRIPTOUTPUT
readonly RUNTIME_DIR

readonly SERVER_SETTINGS_TEMPLATE="${CONFIG}/server-settings.json"
readonly MAP_GEN_SETTINGS="${CONFIG}/map-gen-settings.json"
readonly MAP_SETTINGS="${CONFIG}/map-settings.json"
readonly SERVER_ADMINLIST="${CONFIG}/server-adminlist.json"
readonly SERVER_BANLIST="${CONFIG}/server-banlist.json"
readonly SERVER_WHITELIST="${CONFIG}/server-whitelist.json"
readonly SERVER_ID="${CONFIG}/server-id.json"
readonly MOD_LIST="${MODS}/mod-list.json"
readonly RUNTIME_SERVER_SETTINGS="${RUNTIME_DIR}/server-settings.json"
readonly RUNTIME_RCON_PASSWORD_FILE="${RUNTIME_DIR}/rconpw"
readonly SPACE_AGE_MODS=("elevated-rails" "quality" "space-age")

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Configuræble Vælues
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
PORT="${PORT:-34197}"
RCON_PORT="${RCON_PORT:-27015}"
BIND="${BIND:-0.0.0.0}"
SAVE_NAME="${SAVE_NAME:-_autosave1}"
LOAD_LATEST_SAVE="${LOAD_LATEST_SAVE:-true}"
GENERATE_NEW_SAVE="${GENERATE_NEW_SAVE:-false}"
PRESET="${PRESET:-}"
USE_SERVER_WHITELIST="${USE_SERVER_WHITELIST:-false}"
UPDATE_MODS_ON_START="${UPDATE_MODS_ON_START:-true}"
UPDATE_IGNORE="${UPDATE_IGNORE:-}"
DLC_SPACE_AGE="${DLC_SPACE_AGE:-false}"
CONSOLE_LOG_LOCATION="${CONSOLE_LOG_LOCATION:-}"

FACTORIO_USERNAME_FILE="${FACTORIO_USERNAME_FILE:-/run/secrets/FACTORIO_USERNAME}"
FACTORIO_TOKEN_FILE="${FACTORIO_TOKEN_FILE:-/run/secrets/FACTORIO_TOKEN}"
FACTORIO_GAME_PASSWORD_FILE="${FACTORIO_GAME_PASSWORD_FILE:-/run/secrets/FACTORIO_GAME_PASSWORD}"
FACTORIO_RCON_PASSWORD_FILE="${FACTORIO_RCON_PASSWORD_FILE:-/run/secrets/FACTORIO_RCON_PASSWORD}"

export CONFIG
export MODS
export UPDATE_IGNORE
export DLC_SPACE_AGE

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Logging
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
log_info() {
  echo "[entrypoint] $*"
}

log_error() {
  echo "[entrypoint] ERROR: $*" >&2
}

log_fatal() {
  log_error "$*"
  exit 1
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Helpers
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
read_secret() {
  local name="$1"
  local file="$2"
  local required="${3:-true}"
  local value

  if [[ ! -f "$file" ]]; then
    [[ "$required" == true ]] && log_fatal "Missing required secret ${name} at ${file}"
    return 0
  fi

  value="$(tr -d '\r\n' < "$file")"
  if [[ -z "$value" || "$value" == "CHANGE_ME" ]]; then
    [[ "$required" == true ]] && log_fatal "Secret ${name} must be replaced before start"
    return 0
  fi

  printf '%s' "$value"
}

bool_true() {
  case "${1,,}" in
    true|1|yes|y|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_json_array_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    printf '[]\n' > "$file"
  fi
}

ensure_json_object_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    printf '{}\n' > "$file"
  fi
}

json_object_has_keys() {
  local file="$1"

  jq -e 'type == "object" and length > 0' "$file" >/dev/null
}

ensure_mod_entry() {
  local mod_name="$1"

  jq \
    --arg mod_name "$mod_name" \
    'if .mods | map(.name) | index($mod_name) then . else .mods += [{"name": $mod_name, "enabled": false}] end' \
    "$MOD_LIST" > "${MOD_LIST}.tmp"
  mv "${MOD_LIST}.tmp" "$MOD_LIST"
}

has_save_file() {
  find "$SAVES" -maxdepth 1 -type f -name '*.zip' -print -quit | grep -q .
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Bootstræp Filesystem
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
mkdir -p "$CONFIG" "$SAVES" "$MODS" "$SCENARIOS" "$SCRIPTOUTPUT" "$RUNTIME_DIR"

ensure_json_object_file "$MAP_GEN_SETTINGS"
ensure_json_object_file "$MAP_SETTINGS"
ensure_json_array_file "$SERVER_ADMINLIST"
ensure_json_array_file "$SERVER_BANLIST"
ensure_json_array_file "$SERVER_WHITELIST"

if [[ ! -f "$MOD_LIST" ]]; then
  cat > "$MOD_LIST" <<'JSON'
{
  "mods": [
    {
      "name": "base",
      "enabled": true
    },
    {
      "name": "elevated-rails",
      "enabled": false
    },
    {
      "name": "quality",
      "enabled": false
    },
    {
      "name": "space-age",
      "enabled": false
    }
  ]
}
JSON
fi

for space_age_mod in "${SPACE_AGE_MODS[@]}"; do
  ensure_mod_entry "$space_age_mod"
done

if [[ ! -f "$SERVER_SETTINGS_TEMPLATE" ]]; then
  cat > "$SERVER_SETTINGS_TEMPLATE" <<'JSON'
{
  "name": "Factorio Server",
  "description": "Dedicated Factorio server managed by Docker Compose.",
  "tags": [
    "game",
    "docker"
  ],
  "max_players": 0,
  "visibility": {
    "public": false,
    "lan": true
  },
  "username": "",
  "token": "",
  "game_password": "",
  "require_user_verification": true,
  "max_upload_in_kilobytes_per_second": 0,
  "max_upload_slots": 5,
  "minimum_latency_in_ticks": 0,
  "ignore_player_limit_for_returning_players": false,
  "allow_commands": "admins-only",
  "autosave_interval": 10,
  "autosave_slots": 5,
  "afk_autokick_interval": 0,
  "auto_pause": true,
  "only_admins_can_pause_the_game": true,
  "autosave_only_on_server": true,
  "non_blocking_saving": false
}
JSON
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Secrets
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
PUBLIC_VISIBILITY="$(jq -r '.visibility.public // false' "$SERVER_SETTINGS_TEMPLATE")"

USERNAME_REQUIRED=false
TOKEN_REQUIRED=false
if bool_true "$UPDATE_MODS_ON_START" || bool_true "$PUBLIC_VISIBILITY"; then
  USERNAME_REQUIRED=true
  TOKEN_REQUIRED=true
fi

USERNAME="$(read_secret "FACTORIO_USERNAME" "$FACTORIO_USERNAME_FILE" "$USERNAME_REQUIRED")"
TOKEN="$(read_secret "FACTORIO_TOKEN" "$FACTORIO_TOKEN_FILE" "$TOKEN_REQUIRED")"
GAME_PASSWORD="$(read_secret "FACTORIO_GAME_PASSWORD" "$FACTORIO_GAME_PASSWORD_FILE" true)"
RCON_PASSWORD="$(read_secret "FACTORIO_RCON_PASSWORD" "$FACTORIO_RCON_PASSWORD_FILE" true)"

export USERNAME
export TOKEN

printf '%s' "$RCON_PASSWORD" > "$RUNTIME_RCON_PASSWORD_FILE"

jq \
  --arg username "$USERNAME" \
  --arg token "$TOKEN" \
  --arg game_password "$GAME_PASSWORD" \
  '.username = $username | .token = $token | .game_password = $game_password' \
  "$SERVER_SETTINGS_TEMPLATE" > "$RUNTIME_SERVER_SETTINGS"

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Mods
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
if [[ -x /docker-dlc.sh ]]; then
  log_info "Reconciling built-in DLC mod toggles"
  /docker-dlc.sh
fi

if bool_true "$UPDATE_MODS_ON_START"; then
  [[ -x /docker-update-mods.sh ]] || log_fatal "Mod updater script is missing from the base image"
  log_info "Updating enabled mods from the Factorio mod portal"
  (cd / && /docker-update-mods.sh)
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- World
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
SAVE_FILE="${SAVES}/${SAVE_NAME%.zip}.zip"

if bool_true "$GENERATE_NEW_SAVE" || ! has_save_file; then
  if [[ ! -f "$SAVE_FILE" ]]; then
    create_args=(--create "$SAVE_FILE")

    if json_object_has_keys "$MAP_GEN_SETTINGS"; then
      create_args+=(--map-gen-settings "$MAP_GEN_SETTINGS")
    fi

    if json_object_has_keys "$MAP_SETTINGS"; then
      create_args+=(--map-settings "$MAP_SETTINGS")
    fi

    if [[ -n "$PRESET" ]]; then
      create_args+=(--preset "$PRESET")
    fi

    log_info "Creating initial Factorio save at ${SAVE_FILE}"
    "$FACTORIO_BIN" "${create_args[@]}"
  fi
fi

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- Stært Server
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
cmd=(
  "$FACTORIO_BIN"
  --port "$PORT"
  --server-settings "$RUNTIME_SERVER_SETTINGS"
  --server-banlist "$SERVER_BANLIST"
  --server-adminlist "$SERVER_ADMINLIST"
  --server-id "$SERVER_ID"
  --mod-directory "$MODS"
  --rcon-port "$RCON_PORT"
  --rcon-password "$RCON_PASSWORD"
)

if [[ -n "$BIND" ]]; then
  cmd+=(--bind "$BIND")
fi

if [[ -n "$CONSOLE_LOG_LOCATION" ]]; then
  cmd+=(--console-log "$CONSOLE_LOG_LOCATION")
fi

if bool_true "$USE_SERVER_WHITELIST"; then
  cmd+=(--server-whitelist "$SERVER_WHITELIST" --use-server-whitelist)
fi

if bool_true "$LOAD_LATEST_SAVE"; then
  cmd+=(--start-server-load-latest)
else
  cmd+=(--start-server "$SAVE_FILE")
fi

log_info "Starting Factorio on UDP ${PORT}"
exec "${cmd[@]}" "$@"
