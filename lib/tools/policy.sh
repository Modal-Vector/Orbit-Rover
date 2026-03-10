#!/usr/bin/env bash
set -euo pipefail

# policy.sh — Adapter flag building & tool validation for Orbit Rover

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ORBIT_LIB_DIR/util.sh"

# Build adapter-specific tool restriction flags.
# Usage: tool_policy_build_flags adapter policy assigned_tools
# Output: flag string for the adapter, or empty for standard policy.
tool_policy_build_flags() {
  local adapter="$1"
  local policy="$2"
  local assigned_tools="$3"

  if [ "$policy" != "restricted" ] || [ -z "$assigned_tools" ]; then
    echo ""
    return 0
  fi

  case "$adapter" in
    claude-code)
      echo "--allowedTools ${assigned_tools}"
      ;;
    opencode)
      echo "--no-auto-tools --tools ${assigned_tools}"
      ;;
    *)
      orbit_warn "Unknown adapter '$adapter' for tool policy flags"
      echo ""
      ;;
  esac
}

# Validate that assigned tools exist in tools/INDEX.md or as files in tools/.
# Usage: tool_policy_validate component_config state_dir
# component_config: path to component YAML
# state_dir: project root (to find tools/ directory)
tool_policy_validate() {
  local component_config="$1"
  local project_dir="$2"

  local tools_dir="${project_dir}/tools"
  local index_file="${tools_dir}/INDEX.md"

  # Get assigned tools from config
  local assigned
  assigned=$(yq -r '.tools.assigned[]? // empty' "$component_config" 2>/dev/null) || true

  if [ -z "$assigned" ]; then
    return 0
  fi

  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    local found=false

    # Check INDEX.md
    if [ -f "$index_file" ] && grep -q "$tool" "$index_file" 2>/dev/null; then
      found=true
    fi

    # Check as file in tools/
    if [ "$found" = false ] && [ -f "${tools_dir}/${tool}" ] || [ -f "${tools_dir}/${tool}.sh" ]; then
      found=true
    fi

    if [ "$found" = false ]; then
      orbit_warn "Tool '${tool}' assigned in $(basename "$component_config") not found in tools/"
    fi
  done <<< "$assigned"
}
