#!/usr/bin/env bash
set -euo pipefail

# config.sh — YAML configuration loading for Orbit Rover
# Handles system, component, mission, and module configs.

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$ORBIT_LIB_DIR/yaml.sh"

# --------------------------------------------------------------------------
# Unsupported Station fields (explicit list, not dynamic detection)
# --------------------------------------------------------------------------

_UNSUPPORTED_FIELDS=(
  "resource_pool"
  "inflight"
  "streams"
  "streams.backend"
  "webhooks"
  "serve"
  "serve.enabled"
  "serve.port"
  "deployment"
  "resources.pools"
)

# Unsupported field → suggested alternative (if any)
declare -A _UNSUPPORTED_MESSAGES=(
  ["resource_pool"]="Ignored."
  ["inflight"]="Ignored."
  ["streams"]="Ignored."
  ["streams.backend"]="Redis streaming not available."
  ["webhooks"]="Use file sensors as an alternative."
  ["serve"]="Serve mode not available."
  ["serve.enabled"]="Serve mode not available."
  ["serve.port"]="Serve mode not available."
  ["deployment"]="Ignored."
  ["resources.pools"]="Sequential execution in Rover."
)

# Deployment values that are unsupported
_UNSUPPORTED_DEPLOYMENT_VALUES=("contained" "c2")

# --------------------------------------------------------------------------
# config_warn_unsupported file
# --------------------------------------------------------------------------
# Scans a YAML file for any unsupported Station-tier fields and prints warnings.
# Also checks state.backend: postgres (warns and falls back to file).
config_warn_unsupported() {
  local file="$1"
  local basename
  basename=$(basename "$file")
  local warnings=()

  for field in "${_UNSUPPORTED_FIELDS[@]}"; do
    if yaml_exists "$file" "$field" 2>/dev/null; then
      # Special handling for deployment — only warn on specific values
      if [[ "$field" == "deployment" ]]; then
        local dep_val
        dep_val=$(yaml_get "$file" "deployment")
        local is_unsupported=false
        for uval in "${_UNSUPPORTED_DEPLOYMENT_VALUES[@]}"; do
          if [[ "$dep_val" == "$uval" ]]; then
            is_unsupported=true
            break
          fi
        done
        if [[ "$is_unsupported" == "true" ]]; then
          local msg="[ROVER WARN] ${basename}: 'deployment: ${dep_val}' not supported in Rover (Station feature). Ignored."
          echo "$msg" >&2
          warnings+=("$msg")
        fi
        continue
      fi
      local detail="${_UNSUPPORTED_MESSAGES[$field]:-Ignored.}"
      local msg="[ROVER WARN] ${basename}: '${field}' not supported in Rover (Station feature). ${detail}"
      echo "$msg" >&2
      warnings+=("$msg")
    fi
  done

  # Check state.backend: postgres
  if yaml_exists "$file" "state.backend" 2>/dev/null; then
    local backend
    backend=$(yaml_get "$file" "state.backend")
    if [[ "$backend" == "postgres" ]]; then
      local msg="[ROVER WARN] ${basename}: 'state.backend: postgres' not supported in Rover. Falling back to file."
      echo "$msg" >&2
      warnings+=("$msg")
    fi
  fi

  # Return warnings as newline-separated for registry collection
  if [[ ${#warnings[@]} -gt 0 ]]; then
    printf '%s\n' "${warnings[@]}"
  fi
}

# --------------------------------------------------------------------------
# config_load_system path
# --------------------------------------------------------------------------
# Parses orbit.yaml into global associative array ORBIT_SYSTEM.
config_load_system() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "[ROVER ERROR] System config not found: $file" >&2
    return 1
  fi

  # Declare global associative array
  declare -gA ORBIT_SYSTEM=()

  ORBIT_SYSTEM[system]=$(yaml_get "$file" "system")
  ORBIT_SYSTEM[version]=$(yaml_get "$file" "version")

  # Defaults — with fallback values
  ORBIT_SYSTEM[defaults.agent]=$(yaml_get "$file" "defaults.agent")
  [[ -z "${ORBIT_SYSTEM[defaults.agent]}" ]] && ORBIT_SYSTEM[defaults.agent]="claude-code"

  ORBIT_SYSTEM[defaults.model]=$(yaml_get "$file" "defaults.model")
  [[ -z "${ORBIT_SYSTEM[defaults.model]}" ]] && ORBIT_SYSTEM[defaults.model]="sonnet"

  ORBIT_SYSTEM[defaults.timeout]=$(yaml_get "$file" "defaults.timeout")
  [[ -z "${ORBIT_SYSTEM[defaults.timeout]}" ]] && ORBIT_SYSTEM[defaults.timeout]="300"

  ORBIT_SYSTEM[defaults.max_turns]=$(yaml_get "$file" "defaults.max_turns")
  [[ -z "${ORBIT_SYSTEM[defaults.max_turns]}" ]] && ORBIT_SYSTEM[defaults.max_turns]="10"

  # Settings
  ORBIT_SYSTEM[settings.log_level]=$(yaml_get "$file" "settings.log_level")
  [[ -z "${ORBIT_SYSTEM[settings.log_level]}" ]] && ORBIT_SYSTEM[settings.log_level]="info"

  ORBIT_SYSTEM[settings.workspace]=$(yaml_get "$file" "settings.workspace")
  [[ -z "${ORBIT_SYSTEM[settings.workspace]}" ]] && ORBIT_SYSTEM[settings.workspace]="."

  ORBIT_SYSTEM[settings.state_dir]=$(yaml_get "$file" "settings.state_dir")
  [[ -z "${ORBIT_SYSTEM[settings.state_dir]}" ]] && ORBIT_SYSTEM[settings.state_dir]=".orbit"

  # Orbits
  ORBIT_SYSTEM[orbits.default_max]=$(yaml_get "$file" "orbits.default_max")
  [[ -z "${ORBIT_SYSTEM[orbits.default_max]}" ]] && ORBIT_SYSTEM[orbits.default_max]="20"

  ORBIT_SYSTEM[orbits.deadlock_threshold]=$(yaml_get "$file" "orbits.deadlock_threshold")
  [[ -z "${ORBIT_SYSTEM[orbits.deadlock_threshold]}" ]] && ORBIT_SYSTEM[orbits.deadlock_threshold]="3"

  # Sensors defaults
  ORBIT_SYSTEM[sensors.debounce_default]=$(yaml_get "$file" "sensors.debounce_default")
  [[ -z "${ORBIT_SYSTEM[sensors.debounce_default]}" ]] && ORBIT_SYSTEM[sensors.debounce_default]="5s"

  # Warn on unsupported fields (discard output, just for stderr)
  config_warn_unsupported "$file" >/dev/null
}

# --------------------------------------------------------------------------
# config_load_component path [system_config_path]
# --------------------------------------------------------------------------
# Parses a component YAML file. Returns values via global ORBIT_COMPONENT.
# Merge strategy: component values override system defaults. For each field
# (agent, model, timeout, max_turns), the component's value is used if set;
# otherwise the corresponding ORBIT_SYSTEM[defaults.*] value applies.
config_load_component() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "[ROVER ERROR] Component config not found: $file" >&2
    return 1
  fi

  declare -gA ORBIT_COMPONENT=()

  ORBIT_COMPONENT[component]=$(yaml_get "$file" "component")
  ORBIT_COMPONENT[status]=$(yaml_get "$file" "status")
  [[ -z "${ORBIT_COMPONENT[status]}" ]] && ORBIT_COMPONENT[status]="active"

  ORBIT_COMPONENT[description]=$(yaml_get "$file" "description")
  ORBIT_COMPONENT[prompt]=$(yaml_get "$file" "prompt")

  # Agent — component override or system default
  ORBIT_COMPONENT[agent]=$(yaml_get "$file" "agent")
  if [[ -z "${ORBIT_COMPONENT[agent]}" ]] && [[ -n "${ORBIT_SYSTEM[defaults.agent]+x}" ]]; then
    ORBIT_COMPONENT[agent]="${ORBIT_SYSTEM[defaults.agent]}"
  fi

  # Model
  ORBIT_COMPONENT[model]=$(yaml_get "$file" "model")
  if [[ -z "${ORBIT_COMPONENT[model]}" ]] && [[ -n "${ORBIT_SYSTEM[defaults.model]+x}" ]]; then
    ORBIT_COMPONENT[model]="${ORBIT_SYSTEM[defaults.model]}"
  fi

  # Timeout
  ORBIT_COMPONENT[timeout]=$(yaml_get "$file" "timeout")
  if [[ -z "${ORBIT_COMPONENT[timeout]}" ]] && [[ -n "${ORBIT_SYSTEM[defaults.timeout]+x}" ]]; then
    ORBIT_COMPONENT[timeout]="${ORBIT_SYSTEM[defaults.timeout]}"
  fi

  # Max turns
  ORBIT_COMPONENT[max_turns]=$(yaml_get "$file" "max_turns")
  if [[ -z "${ORBIT_COMPONENT[max_turns]}" ]] && [[ -n "${ORBIT_SYSTEM[defaults.max_turns]+x}" ]]; then
    ORBIT_COMPONENT[max_turns]="${ORBIT_SYSTEM[defaults.max_turns]}"
  fi

  # Sensors
  ORBIT_COMPONENT[sensors.paths]=$(yaml_get_array "$file" "sensors.paths" | paste -sd',' -)
  ORBIT_COMPONENT[sensors.events]=$(yaml_get_array "$file" "sensors.events" | paste -sd',' -)
  ORBIT_COMPONENT[sensors.debounce]=$(yaml_get "$file" "sensors.debounce")
  ORBIT_COMPONENT[sensors.cascade]=$(yaml_get "$file" "sensors.cascade")
  [[ -z "${ORBIT_COMPONENT[sensors.cascade]}" ]] && ORBIT_COMPONENT[sensors.cascade]="allow"
  ORBIT_COMPONENT[sensors.schedule.every]=$(yaml_get "$file" "sensors.schedule.every")
  ORBIT_COMPONENT[sensors.schedule.cron]=$(yaml_get "$file" "sensors.schedule.cron")

  # Sensor detection: a component has sensors if any trigger source is configured
  # (file paths for file_watch, interval for schedule, or cron expression)
  if [[ -n "${ORBIT_COMPONENT[sensors.paths]}" || -n "${ORBIT_COMPONENT[sensors.schedule.every]}" || -n "${ORBIT_COMPONENT[sensors.schedule.cron]}" ]]; then
    ORBIT_COMPONENT[has_sensors]="true"
  else
    ORBIT_COMPONENT[has_sensors]="false"
  fi

  # Delivers
  ORBIT_COMPONENT[delivers]=$(yaml_get_array "$file" "delivers" | paste -sd',' -)

  # Preflight/postflight hooks
  ORBIT_COMPONENT[preflight]=$(yaml_get_array "$file" "preflight" | paste -sd',' -)
  ORBIT_COMPONENT[postflight]=$(yaml_get_array "$file" "postflight" | paste -sd',' -)

  # Orbits
  ORBIT_COMPONENT[orbits.max]=$(yaml_get "$file" "orbits.max")
  ORBIT_COMPONENT[orbits.success.when]=$(yaml_get "$file" "orbits.success.when")
  ORBIT_COMPONENT[orbits.success.condition]=$(yaml_get "$file" "orbits.success.condition")
  ORBIT_COMPONENT[orbits.deadlock.threshold]=$(yaml_get "$file" "orbits.deadlock.threshold")
  ORBIT_COMPONENT[orbits.deadlock.action]=$(yaml_get "$file" "orbits.deadlock.action")

  # Retry
  ORBIT_COMPONENT[retry.max_attempts]=$(yaml_get "$file" "retry.max_attempts")
  ORBIT_COMPONENT[retry.backoff]=$(yaml_get "$file" "retry.backoff")
  ORBIT_COMPONENT[retry.initial_delay]=$(yaml_get "$file" "retry.initial_delay")
  ORBIT_COMPONENT[retry.max_delay]=$(yaml_get "$file" "retry.max_delay")
  ORBIT_COMPONENT[retry.on_timeout]=$(yaml_get "$file" "retry.on_timeout")

  # Tools
  ORBIT_COMPONENT[tools.assigned]=$(yaml_get_array "$file" "tools.assigned" | paste -sd',' -)
  ORBIT_COMPONENT[tools.policy]=$(yaml_get "$file" "tools.policy")
  [[ -z "${ORBIT_COMPONENT[tools.policy]}" ]] && ORBIT_COMPONENT[tools.policy]="standard"

  # Warn on unsupported fields
  config_warn_unsupported "$file" >/dev/null
}

# --------------------------------------------------------------------------
# config_load_mission path
# --------------------------------------------------------------------------
# Parses a mission YAML. Stages returned as ORBIT_MISSION_STAGES array.
config_load_mission() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "[ROVER ERROR] Mission config not found: $file" >&2
    return 1
  fi

  declare -gA ORBIT_MISSION=()
  ORBIT_MISSION[mission]=$(yaml_get "$file" "mission")
  ORBIT_MISSION[status]=$(yaml_get "$file" "status")
  [[ -z "${ORBIT_MISSION[status]}" ]] && ORBIT_MISSION[status]="active"
  ORBIT_MISSION[description]=$(yaml_get "$file" "description")

  # Mission sensors
  ORBIT_MISSION[sensors.paths]=$(yaml_get_array "$file" "sensors.paths" | paste -sd',' -)
  ORBIT_MISSION[sensors.events]=$(yaml_get_array "$file" "sensors.events" | paste -sd',' -)
  ORBIT_MISSION[sensors.debounce]=$(yaml_get "$file" "sensors.debounce")
  ORBIT_MISSION[sensors.schedule.cron]=$(yaml_get "$file" "sensors.schedule.cron")
  ORBIT_MISSION[sensors.schedule.every]=$(yaml_get "$file" "sensors.schedule.every")

  # Parse stages into JSON array for ordered access
  # Each stage is a JSON object with all its properties
  declare -ga ORBIT_MISSION_STAGES=()

  local full_json
  full_json=$(yaml_to_json "$file")

  local stage_count
  stage_count=$(echo "$full_json" | jq '.stages | length // 0')

  local i
  for ((i = 0; i < stage_count; i++)); do
    local stage_json
    stage_json=$(echo "$full_json" | jq -c ".stages[$i]")
    ORBIT_MISSION_STAGES+=("$stage_json")
  done

  # Flight rules (stored as JSON array)
  ORBIT_MISSION[flight_rules]=$(echo "$full_json" | jq -c '.flight_rules // []')

  # Warn on unsupported fields
  config_warn_unsupported "$file" >/dev/null
}

# --------------------------------------------------------------------------
# config_load_module path params...
# --------------------------------------------------------------------------
# Parses a module YAML. Expands {param} placeholders using provided parameters.
# params are key=value pairs.
config_load_module() {
  local file="$1"; shift

  if [[ ! -f "$file" ]]; then
    echo "[ROVER ERROR] Module config not found: $file" >&2
    return 1
  fi

  declare -gA ORBIT_MODULE=()
  ORBIT_MODULE[module]=$(yaml_get "$file" "module")
  ORBIT_MODULE[status]=$(yaml_get "$file" "status")
  [[ -z "${ORBIT_MODULE[status]}" ]] && ORBIT_MODULE[status]="active"
  ORBIT_MODULE[description]=$(yaml_get "$file" "description")
  ORBIT_MODULE[delivers]=$(yaml_get_array "$file" "delivers" | paste -sd',' -)

  # Collect parameters
  declare -A params=()
  for arg in "$@"; do
    local key="${arg%%=*}"
    local val="${arg#*=}"
    params["$key"]="$val"
  done

  # Parse and expand stages
  declare -ga ORBIT_MODULE_STAGES=()

  local full_json
  full_json=$(yaml_to_json "$file")

  local stage_count
  stage_count=$(echo "$full_json" | jq '.stages | length // 0')

  local i
  for ((i = 0; i < stage_count; i++)); do
    local stage_json
    stage_json=$(echo "$full_json" | jq -c ".stages[$i]")

    # Expand {param} placeholders in stage JSON
    for key in "${!params[@]}"; do
      stage_json="${stage_json//\{$key\}/${params[$key]}}"
    done

    ORBIT_MODULE_STAGES+=("$stage_json")
  done

  # Expand delivers placeholders too
  local expanded_delivers="${ORBIT_MODULE[delivers]}"
  for key in "${!params[@]}"; do
    expanded_delivers="${expanded_delivers//\{$key\}/${params[$key]}}"
  done
  ORBIT_MODULE[delivers]="$expanded_delivers"
}
