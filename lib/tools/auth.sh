#!/usr/bin/env bash
set -euo pipefail

# auth.sh — Auth key generation & validation for tool governance

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ORBIT_LIB_DIR/util.sh"

# Generate a deterministic auth key for a component/mission/run combo.
# Usage: tool_auth_generate component_name mission_name run_id
tool_auth_generate() {
  local component="$1"
  local mission="$2"
  local run_id="$3"
  echo -n "${component}:${mission}:${run_id}" | _sha256 | cut -d' ' -f1
}

# Grant a tool to a component by adding it to the auth file.
# Usage: tool_auth_grant component_name tool_name auth_key state_dir
tool_auth_grant() {
  local component="$1"
  local tool_name="$2"
  local auth_key="$3"
  local state_dir="$4"

  local auth_dir="${state_dir}/tool-auth"
  local auth_file="${auth_dir}/${component}.json"
  mkdir -p "$auth_dir"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [ -f "$auth_file" ]; then
    # Read existing, add tool (dedup), write atomically
    local updated
    updated=$(jq -c --arg tool "$tool_name" --arg key "$auth_key" --arg now "$now" '
      .auth_key = $key |
      .granted_at = $now |
      if (.granted_tools | index($tool)) then . else .granted_tools += [$tool] end
    ' "$auth_file")
    _atomic_write "$auth_file" "$updated"
  else
    # Create new auth file
    local json
    json=$(jq -nc --arg comp "$component" --arg tool "$tool_name" --arg key "$auth_key" --arg now "$now" '{
      component: $comp,
      granted_tools: [$tool],
      auth_key: $key,
      granted_at: $now
    }')
    _atomic_write "$auth_file" "$json"
  fi
}

# Check if an auth key is valid for a component.
# Usage: tool_auth_check component_name auth_key state_dir
# Returns 0 if valid, 1 if invalid or missing.
tool_auth_check() {
  local component="$1"
  local auth_key="$2"
  local state_dir="$3"

  local auth_file="${state_dir}/tool-auth/${component}.json"

  if [ ! -f "$auth_file" ]; then
    return 1
  fi

  local stored_key
  stored_key=$(jq -r '.auth_key // ""' "$auth_file")

  if [ "$stored_key" = "$auth_key" ]; then
    return 0
  fi
  return 1
}

# Get the list of granted tools for a component (newline-separated).
# Usage: tool_auth_get_granted component_name state_dir
tool_auth_get_granted() {
  local component="$1"
  local state_dir="$2"

  local auth_file="${state_dir}/tool-auth/${component}.json"

  if [ ! -f "$auth_file" ]; then
    return 0
  fi

  jq -r '.granted_tools[]' "$auth_file" 2>/dev/null || true
}
