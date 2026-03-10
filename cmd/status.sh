#!/usr/bin/env bash
set -euo pipefail

# status.sh — orbit status subcommand
# Shows overall or mission-specific status.

cmd_status() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  if [[ $# -gt 0 ]]; then
    _status_mission "$1" "$state_dir"
  else
    _status_overall "$state_dir"
  fi
}

_status_overall() {
  local state_dir="$1"

  echo "Orbit Rover — Status"
  echo "===================="

  # Last run
  local last_run="none"
  if [[ -d "${state_dir}/runs" ]]; then
    local latest_run
    latest_run=$(ls -1t "${state_dir}/runs/" 2>/dev/null | head -1)
    if [[ -n "$latest_run" ]]; then
      last_run="$latest_run"
    fi
  fi
  echo "Last run: ${last_run}"

  # Active sensors
  local sensor_count=0
  if [[ -d "${state_dir}/sensors" ]]; then
    sensor_count=$(ls -1 "${state_dir}/sensors/" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "Active sensors: ${sensor_count}"

  # Pending gates
  local gate_count=0
  if [[ -d "${state_dir}/manual" ]]; then
    for gate_dir in "${state_dir}/manual"/*/; do
      [[ -d "$gate_dir" ]] || continue
      if [[ -f "${gate_dir}prompt.json" ]] && [[ ! -f "${gate_dir}response.json" ]]; then
        gate_count=$((gate_count + 1))
      fi
    done
  fi
  echo "Pending gates: ${gate_count}"

  # Pending tool requests
  local request_count=0
  local pending_file="${state_dir}/tool-requests/pending.jsonl"
  if [[ -f "$pending_file" ]]; then
    request_count=$(jq -c 'select(.status == "pending")' "$pending_file" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "Pending tool requests: ${request_count}"
}

_status_mission() {
  local mission="$1"
  local state_dir="$2"

  echo "Mission: ${mission}"
  echo "=========================="

  # Find the latest run for this mission
  local run_dir=""
  if [[ -d "${state_dir}/runs" ]]; then
    for rdir in "${state_dir}/runs"/*/; do
      [[ -d "$rdir" ]] || continue
      if [[ -f "${rdir}mission.json" ]]; then
        local run_mission
        run_mission=$(jq -r '.mission // ""' "${rdir}mission.json" 2>/dev/null)
        if [[ "$run_mission" == "$mission" ]]; then
          run_dir="$rdir"
        fi
      fi
    done
  fi

  if [[ -z "$run_dir" ]]; then
    echo "No runs found for mission '${mission}'."
    return 0
  fi

  local stages_dir="${run_dir}stages"
  if [[ ! -d "$stages_dir" ]]; then
    echo "No stage data found."
    return 0
  fi

  echo "Stages:"
  for stage_file in "$stages_dir"/*.json; do
    [[ -f "$stage_file" ]] || continue
    local name status
    name=$(jq -r '.name // "unknown"' "$stage_file")
    status=$(jq -r '.status // "unknown"' "$stage_file")
    echo "  ${name}: ${status}"
  done
}
