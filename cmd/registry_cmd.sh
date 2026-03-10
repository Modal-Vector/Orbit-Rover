#!/usr/bin/env bash
set -euo pipefail

# registry_cmd.sh — orbit registry subcommand
# Builds and displays the component/mission registry.

cmd_registry() {
  local project_dir="$(pwd)"

  registry_build "$project_dir" 2>/dev/null || true

  local registry
  registry=$(registry_load "$project_dir") || {
    echo "No registry found. Run 'orbit init' first." >&2
    return 1
  }

  echo "Orbit Registry"
  echo "=============="
  echo ""

  # Components
  echo "Components:"
  local comp_count
  comp_count=$(echo "$registry" | jq '.components | length')
  if [[ "$comp_count" -eq 0 ]]; then
    echo "  (none)"
  else
    echo "$registry" | jq -r '.components | to_entries[] | "  \(.key)  [\(.value.status)]  \(.value.description // "")"'
  fi

  echo ""

  # Missions
  echo "Missions:"
  local mission_count
  mission_count=$(echo "$registry" | jq '.missions | length')
  if [[ "$mission_count" -eq 0 ]]; then
    echo "  (none)"
  else
    echo "$registry" | jq -r '.missions | to_entries[] | "  \(.key)  [\(.value.status)]"'
  fi
}
