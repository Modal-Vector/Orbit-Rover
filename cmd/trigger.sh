#!/usr/bin/env bash
set -euo pipefail

# trigger.sh — orbit trigger subcommand
# Writes a manual trigger file.

cmd_trigger() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit trigger <name>" >&2
    return 1
  fi

  local name="$1"
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  mkdir -p "${state_dir}/triggers"
  _atomic_write "${state_dir}/triggers/${name}-manual" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "Trigger written for '${name}'"
}
