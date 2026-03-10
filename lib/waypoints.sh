#!/usr/bin/env bash
set -euo pipefail

# waypoints.sh — Waypoint checkpoint/resume for mission safety
# Saves stage completion markers to enable mission resumption.

# Save a waypoint for a completed stage
waypoint_save() {
  local stage_name="$1"
  local mission_name="$2"
  local run_id="$3"
  local state_dir="$4"

  local wp_dir="${state_dir}/runs/${run_id}/waypoints"
  mkdir -p "$wp_dir"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local wp_json
  wp_json=$(jq -nc \
    --arg stage "$stage_name" \
    --arg mission "$mission_name" \
    --arg saved_at "$now" \
    --arg status "completed" \
    '{stage: $stage, mission: $mission, saved_at: $saved_at, status: $status}')
  _atomic_write "${wp_dir}/${stage_name}.json" "$wp_json"
}

# Get the last saved waypoint stage name for a run
waypoint_get_last() {
  local mission_name="$1"
  local run_id="$2"
  local state_dir="$3"

  local wp_dir="${state_dir}/runs/${run_id}/waypoints"
  if [[ ! -d "$wp_dir" ]]; then
    echo ""
    return 0
  fi

  # Find most recent by saved_at
  local latest_stage="" latest_time=""
  for wp_file in "$wp_dir"/*.json; do
    [[ -f "$wp_file" ]] || continue
    local stage saved_at
    stage=$(jq -r '.stage // ""' "$wp_file" 2>/dev/null)
    saved_at=$(jq -r '.saved_at // ""' "$wp_file" 2>/dev/null)

    if [[ -z "$latest_time" ]] || [[ "$saved_at" > "$latest_time" ]]; then
      latest_time="$saved_at"
      latest_stage="$stage"
    fi
  done

  echo "$latest_stage"
}

# Find the resume point for a mission — returns stage name to resume FROM
# (the stage AFTER the last waypoint)
waypoint_resume_from() {
  local mission_name="$1"
  local state_dir="$2"

  # Find most recent run for this mission
  local latest_run_id=""
  local latest_started=""
  if [[ -d "${state_dir}/runs" ]]; then
    for rdir in "${state_dir}/runs"/*/; do
      [[ -d "$rdir" ]] || continue
      local mission_file="${rdir}mission.json"
      [[ -f "$mission_file" ]] || continue
      local rm started
      rm=$(jq -r '.mission // ""' "$mission_file" 2>/dev/null)
      started=$(jq -r '.started_at // ""' "$mission_file" 2>/dev/null)
      if [[ "$rm" == "$mission_name" ]]; then
        if [[ -z "$latest_started" ]] || [[ "$started" > "$latest_started" ]]; then
          latest_started="$started"
          latest_run_id=$(basename "$rdir")
        fi
      fi
    done
  fi

  if [[ -z "$latest_run_id" ]]; then
    echo ""
    return 0
  fi

  local last_stage
  last_stage=$(waypoint_get_last "$mission_name" "$latest_run_id" "$state_dir")
  echo "$last_stage"
}

# List all waypoints for a run
waypoint_list() {
  local mission_name="$1"
  local run_id="$2"
  local state_dir="$3"

  local wp_dir="${state_dir}/runs/${run_id}/waypoints"
  if [[ ! -d "$wp_dir" ]]; then
    echo "No waypoints."
    return 0
  fi

  for wp_file in "$wp_dir"/*.json; do
    [[ -f "$wp_file" ]] || continue
    local stage saved_at status
    stage=$(jq -r '.stage // ""' "$wp_file" 2>/dev/null)
    saved_at=$(jq -r '.saved_at // ""' "$wp_file" 2>/dev/null)
    status=$(jq -r '.status // ""' "$wp_file" 2>/dev/null)
    echo "${stage}: ${status} (${saved_at})"
  done
}
