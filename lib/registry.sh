#!/usr/bin/env bash
set -euo pipefail

# registry.sh — Component/mission registry for Orbit Rover
# Scans component and mission YAML files, builds .orbit/registry.json

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$ORBIT_LIB_DIR/config.sh"

# --------------------------------------------------------------------------
# registry_build project_dir
# --------------------------------------------------------------------------
# Scan-and-assemble pattern: walks components/*.yaml and missions/*.yaml,
# extracts metadata (name, status, description, delivers, has_sensors) from
# each file, and assembles a single registry.json. Offline components/missions
# are excluded. Unsupported Station-tier field warnings are collected and
# stored in the registry's "warnings" array for later display by `orbit doctor`.
registry_build() {
  local project_dir="$1"
  local state_dir="${project_dir}/.orbit"
  local comp_dir="${project_dir}/components"
  local mission_dir="${project_dir}/missions"

  mkdir -p "$state_dir"

  local built_at
  built_at=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")

  local components_json="{}"
  local missions_json="{}"
  local all_warnings=()

  # Scan components
  if [[ -d "$comp_dir" ]]; then
    for yaml_file in "$comp_dir"/*.yaml "$comp_dir"/*.yml "$comp_dir"/*/*.yaml "$comp_dir"/*/*.yml; do
      [[ -f "$yaml_file" ]] || continue

      local name status description delivers has_sensors rel_path
      name=$(yaml_get "$yaml_file" "component")
      [[ -z "$name" ]] && continue

      status=$(yaml_get "$yaml_file" "status")
      [[ -z "$status" ]] && status="active"
      [[ "$status" == "offline" ]] && continue
      description=$(yaml_get "$yaml_file" "description")

      # Get delivers as JSON array
      local delivers_json="[]"
      if yaml_exists "$yaml_file" "delivers" 2>/dev/null; then
        local comp_json
        comp_json=$(yaml_to_json "$yaml_file")
        delivers_json=$(echo "$comp_json" | jq -c '.delivers // []')
      fi

      # Check for sensors
      has_sensors="false"
      if yaml_exists "$yaml_file" "sensors.paths" 2>/dev/null || \
         yaml_exists "$yaml_file" "sensors.schedule" 2>/dev/null; then
        has_sensors="true"
      fi

      rel_path="${yaml_file#"$project_dir"/}"

      # Collect warnings
      local warnings
      warnings=$(config_warn_unsupported "$yaml_file" 2>/dev/null || true)
      if [[ -n "$warnings" ]]; then
        while IFS= read -r w; do
          [[ -n "$w" ]] && all_warnings+=("$w")
        done <<< "$warnings"
      fi

      # Build component entry
      components_json=$(echo "$components_json" | jq \
        --arg name "$name" \
        --arg file "$rel_path" \
        --arg status "$status" \
        --arg desc "$description" \
        --argjson delivers "$delivers_json" \
        --argjson has_sensors "$has_sensors" \
        '.[$name] = {file: $file, status: $status, description: $desc, delivers: $delivers, has_sensors: $has_sensors}')
    done
  fi

  # Scan missions
  if [[ -d "$mission_dir" ]]; then
    for yaml_file in "$mission_dir"/*.yaml "$mission_dir"/*.yml; do
      [[ -f "$yaml_file" ]] || continue

      local name status rel_path
      name=$(yaml_get "$yaml_file" "mission")
      [[ -z "$name" ]] && continue

      status=$(yaml_get "$yaml_file" "status")
      [[ -z "$status" ]] && status="active"
      [[ "$status" == "offline" ]] && continue

      rel_path="missions/$(basename "$yaml_file")"

      # Collect warnings
      local warnings
      warnings=$(config_warn_unsupported "$yaml_file" 2>/dev/null || true)
      if [[ -n "$warnings" ]]; then
        while IFS= read -r w; do
          [[ -n "$w" ]] && all_warnings+=("$w")
        done <<< "$warnings"
      fi

      missions_json=$(echo "$missions_json" | jq \
        --arg name "$name" \
        --arg file "$rel_path" \
        --arg status "$status" \
        '.[$name] = {file: $file, status: $status}')
    done
  fi

  # Build warnings JSON array
  local warnings_json="[]"
  if [[ ${#all_warnings[@]} -gt 0 ]]; then
    warnings_json=$(printf '%s\n' "${all_warnings[@]}" | jq -R . | jq -s .)
  fi

  # Assemble final registry
  local registry_json
  registry_json=$(jq -n \
    --arg built_at "$built_at" \
    --argjson components "$components_json" \
    --argjson missions "$missions_json" \
    --argjson warnings "$warnings_json" \
    '{built_at: $built_at, components: $components, missions: $missions, warnings: $warnings}')

  # Atomic write
  local tmp_file
  tmp_file=$(mktemp "${state_dir}/registry.json.XXXXXX")
  echo "$registry_json" > "$tmp_file"
  mv "$tmp_file" "${state_dir}/registry.json"
}

# --------------------------------------------------------------------------
# registry_load project_dir
# --------------------------------------------------------------------------
# Reads .orbit/registry.json, outputs its contents to stdout.
registry_load() {
  local project_dir="$1"
  local registry_file="${project_dir}/.orbit/registry.json"

  if [[ ! -f "$registry_file" ]]; then
    echo "[ROVER ERROR] Registry not found: $registry_file — run registry_build first" >&2
    return 1
  fi

  cat "$registry_file"
}

# --------------------------------------------------------------------------
# registry_get_component name [project_dir]
# --------------------------------------------------------------------------
# Returns the component config file path from registry.
registry_get_component() {
  local name="$1"
  local project_dir="${2:-.}"
  local registry_file="${project_dir}/.orbit/registry.json"

  if [[ ! -f "$registry_file" ]]; then
    echo "[ROVER ERROR] Registry not found" >&2
    return 1
  fi

  local file_path
  file_path=$(jq -r --arg name "$name" '.components[$name].file // empty' "$registry_file")

  if [[ -z "$file_path" ]]; then
    echo "[ROVER WARN] Component '$name' not found in registry" >&2
    return 1
  fi

  echo "$file_path"
}

# --------------------------------------------------------------------------
# registry_validate_target target [project_dir]
# --------------------------------------------------------------------------
# Validates a learning tag target (e.g. "component:doc-drafter") against registry.
# Returns 0 if valid, 1 with warning if not found.
registry_validate_target() {
  local target="$1"
  local project_dir="${2:-.}"
  local registry_file="${project_dir}/.orbit/registry.json"

  if [[ ! -f "$registry_file" ]]; then
    echo "[ROVER WARN] Cannot validate target '$target' — registry not built" >&2
    return 1
  fi

  # Parse target format: "scope:name"
  local scope="${target%%:*}"
  local name="${target#*:}"

  case "$scope" in
    component)
      local exists
      exists=$(jq -r --arg name "$name" '.components[$name] // empty' "$registry_file")
      if [[ -z "$exists" ]]; then
        echo "[ROVER WARN] insight target '${target}' not found in registry" >&2
        return 1
      fi
      ;;
    mission)
      local exists
      exists=$(jq -r --arg name "$name" '.missions[$name] // empty' "$registry_file")
      if [[ -z "$exists" ]]; then
        echo "[ROVER WARN] insight target '${target}' not found in registry" >&2
        return 1
      fi
      ;;
    project|module|run|stage)
      # These scopes don't require registry validation
      ;;
    *)
      echo "[ROVER WARN] Unknown target scope '${scope}' in '${target}'" >&2
      return 1
      ;;
  esac

  return 0
}
