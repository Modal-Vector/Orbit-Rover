#!/usr/bin/env bash
set -euo pipefail

# cron_cli.sh — orbit cron subcommand
# Cron management CLI.

cmd_cron() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit cron <list|clear|preview>" >&2
    return 1
  fi

  local subcmd="$1"; shift

  case "$subcmd" in
    list)
      local output
      output=$(sensor_cron_list 2>/dev/null)
      if [[ -z "$output" ]]; then
        echo "No Orbit cron entries found."
      else
        echo "$output"
      fi
      ;;
    clear)
      sensor_cron_unregister_all
      echo "All Orbit cron entries removed."
      ;;
    preview)
      local project_dir="$(pwd)"
      registry_build "$project_dir" 2>/dev/null || true
      local registry
      registry=$(registry_load "$project_dir" 2>/dev/null) || {
        echo "No registry found." >&2
        return 1
      }

      echo "Planned cron entries:"
      local found=false
      local comp_names
      comp_names=$(echo "$registry" | jq -r '.components | to_entries[] | select(.value.status == "active") | .key')
      while IFS= read -r comp_name; do
        [[ -z "$comp_name" ]] && continue
        local comp_file
        comp_file=$(registry_get_component "$comp_name" "$project_dir" 2>/dev/null) || continue
        config_load_component "${project_dir}/${comp_file}" 2>/dev/null || continue

        if [[ -n "${ORBIT_COMPONENT[sensors.schedule.cron]:-}" ]]; then
          echo "  ${ORBIT_COMPONENT[sensors.schedule.cron]}  →  ${comp_name}"
          found=true
        fi
      done <<< "$comp_names"

      if [[ "$found" == "false" ]]; then
        echo "  (none)"
      fi
      ;;
    *)
      echo "Unknown subcommand: $subcmd" >&2
      return 1
      ;;
  esac
}
