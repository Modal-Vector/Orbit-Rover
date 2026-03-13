#!/usr/bin/env bash
set -euo pipefail

# stop.sh — Stop signal helpers for graceful mission termination
# Uses file-based signaling consistent with the "disk is the only memory" invariant.

# Write a stop signal for a running mission
stop_request() {
  local run_id="$1"
  local state_dir="$2"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local stop_json
  stop_json=$(jq -nc \
    --arg run_id "$run_id" \
    --arg requested_at "$now" \
    '{run_id: $run_id, requested_at: $requested_at}')

  _atomic_write "${state_dir}/runs/${run_id}/stop.json" "$stop_json"
}

# Check if a stop signal exists for a run
stop_is_requested() {
  local run_id="$1"
  local state_dir="$2"

  [[ -f "${state_dir}/runs/${run_id}/stop.json" ]]
}

# Find the run_id of a running mission by name
stop_find_running_run() {
  local mission_name="$1"
  local state_dir="$2"

  if [[ ! -d "${state_dir}/runs" ]]; then
    return 1
  fi

  for rdir in "${state_dir}/runs"/*/; do
    [[ -d "$rdir" ]] || continue
    local mission_file="${rdir}mission.json"
    [[ -f "$mission_file" ]] || continue

    local name status
    name=$(jq -r '.mission // ""' "$mission_file" 2>/dev/null)
    status=$(jq -r '.status // ""' "$mission_file" 2>/dev/null)

    if [[ "$name" == "$mission_name" ]] && [[ "$status" == "running" ]]; then
      basename "$rdir"
      return 0
    fi
  done

  return 1
}

# Remove the stop signal after acknowledgment
stop_clear() {
  local run_id="$1"
  local state_dir="$2"

  rm -f "${state_dir}/runs/${run_id}/stop.json"
}
