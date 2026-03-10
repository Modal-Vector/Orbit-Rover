#!/usr/bin/env bash
set -euo pipefail

# launch.sh — orbit launch subcommand
# Launches a mission: loads config, validates, topological sort, executes stages.
# Phase 7: manual gates, flight rules, waypoints, metrics tracking.

cmd_launch() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit launch <mission> [--dry-run] [--resume]" >&2
    return 1
  fi

  local mission_name="$1"; shift
  local dry_run=false
  local resume=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)  dry_run=true; shift ;;
      --resume)   resume=true; shift ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  local project_dir="$(pwd)"
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  # Build registry
  registry_build "$project_dir" 2>/dev/null || true

  # Load mission config
  local mission_file="${project_dir}/missions/${mission_name}.yaml"
  if [[ ! -f "$mission_file" ]]; then
    mission_file="${project_dir}/missions/${mission_name}.yml"
  fi
  if [[ ! -f "$mission_file" ]]; then
    echo "Mission '${mission_name}' not found." >&2
    return 1
  fi

  config_load_mission "$mission_file"

  if [[ ${#ORBIT_MISSION_STAGES[@]} -eq 0 ]]; then
    echo "Mission '${mission_name}' has no stages." >&2
    return 1
  fi

  # Validate all stage components exist
  local validation_failed=false
  local i
  for ((i = 0; i < ${#ORBIT_MISSION_STAGES[@]}; i++)); do
    local stage_json="${ORBIT_MISSION_STAGES[$i]}"
    local comp
    comp=$(echo "$stage_json" | jq -r '.component // empty')
    local stage_type
    stage_type=$(echo "$stage_json" | jq -r '.type // empty')

    if [[ -n "$comp" ]]; then
      if ! registry_get_component "$comp" "$project_dir" >/dev/null 2>&1; then
        echo "Error: component '$comp' not found in registry." >&2
        validation_failed=true
      fi
    fi
  done

  if [[ "$validation_failed" == "true" ]]; then
    return 1
  fi

  # Topological sort
  local sorted_stages=()
  _topological_sort sorted_stages

  # Dry run — print plan and exit
  if [[ "$dry_run" == "true" ]]; then
    _print_execution_plan "$mission_name" sorted_stages
    return 0
  fi

  # Load flight rules from mission config (if any)
  local flight_rules_json="[]"
  if [[ -n "${ORBIT_MISSION[flight_rules]:-}" ]]; then
    flight_rules_json="${ORBIT_MISSION[flight_rules]}"
  else
    # Try loading from mission YAML directly
    local fr
    fr=$(yaml_get "$mission_file" ".flight_rules" 2>/dev/null) || fr=""
    if [[ -n "$fr" ]] && [[ "$fr" != "null" ]]; then
      flight_rules_json="$fr"
    fi
  fi

  # Resume — find last waypoint and restart from next stage
  local start_index=0
  if [[ "$resume" == "true" ]]; then
    start_index=$(_find_resume_point "$mission_name" "$state_dir" sorted_stages)
  fi

  # Create run state
  local run_id
  run_id=$(_orbit_gen_id "run-" "$mission_name")
  local run_dir="${state_dir}/runs/${run_id}"
  mkdir -p "${run_dir}/stages"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local start_epoch
  start_epoch=$(date -u +%s)
  local mission_state
  mission_state=$(jq -nc \
    --arg id "$run_id" \
    --arg mission "$mission_name" \
    --arg status "running" \
    --arg started "$now" \
    '{run_id: $id, mission: $mission, status: $status, started_at: $started}')
  _atomic_write "${run_dir}/mission.json" "$mission_state"

  # Initialize metrics
  metrics_update "$run_id" 0 "$start_epoch" "$state_dir"

  _orbit_log_event "info" "mission.start" "Mission '${mission_name}' started (run: ${run_id})"

  echo "Launching mission '${mission_name}' (run: ${run_id})"

  # Execute stages in sorted order
  local total_orbits=0
  for ((i = start_index; i < ${#sorted_stages[@]}; i++)); do
    local stage_idx="${sorted_stages[$i]}"
    local stage_json="${ORBIT_MISSION_STAGES[$stage_idx]}"
    local stage_name
    stage_name=$(echo "$stage_json" | jq -r '.name')

    local stage_type
    stage_type=$(echo "$stage_json" | jq -r '.type // empty')

    # Write stage state: running
    _write_stage_state "$run_dir" "$stage_name" "running" ""

    if [[ "$stage_type" == "manual" ]]; then
      # Manual gate — open and wait for response
      local gate_prompt gate_options_json gate_timeout gate_default
      gate_prompt=$(echo "$stage_json" | jq -r '.prompt // "Approval required."')
      gate_options_json=$(echo "$stage_json" | jq -c '.options // ["approve", "reject"]')
      gate_timeout=$(echo "$stage_json" | jq -r '.timeout // "72h"')
      gate_default=$(echo "$stage_json" | jq -r '.default // "reject"')

      # Parse timeout duration to hours
      local timeout_hours
      timeout_hours=$(_parse_timeout_hours "$gate_timeout")

      local gate_response
      gate_response=$(manual_gate_open "$stage_name" "$mission_name" "$run_id" \
        "$gate_prompt" "$gate_options_json" "$timeout_hours" "$gate_default" "$state_dir")

      if [[ "$gate_response" == "reject" ]]; then
        _write_stage_state "$run_dir" "$stage_name" "rejected" "Gate rejected"
        echo "Gate '$stage_name' rejected — aborting mission."
        _write_run_state "$run_dir" "rejected"
        return 1
      fi

      _write_stage_state "$run_dir" "$stage_name" "complete" "Gate: ${gate_response}"
      _orbit_log_event "info" "mission.gate" "Gate '${stage_name}' passed: ${gate_response}"
      continue
    fi

    local comp_name
    comp_name=$(echo "$stage_json" | jq -r '.component // empty')
    if [[ -z "$comp_name" ]]; then
      echo "Stage '$stage_name': no component — skipping"
      _write_stage_state "$run_dir" "$stage_name" "skipped" "no component"
      continue
    fi

    # Check for orbits_to loop
    local orbits_to
    orbits_to=$(echo "$stage_json" | jq -r '.orbits_to // empty')

    if [[ -n "$orbits_to" ]]; then
      _execute_orbits_to_loop "$stage_json" "$project_dir" "$state_dir" "$run_dir" total_orbits
    else
      echo "Executing stage '$stage_name' (component: $comp_name)"
      _execute_stage_component "$stage_json" "$project_dir" "$state_dir" || {
        _write_stage_state "$run_dir" "$stage_name" "failed" ""
        echo "Stage '$stage_name' failed." >&2
        _write_run_state "$run_dir" "failed"
        return 1
      }
    fi

    # Mark stage complete
    _write_stage_state "$run_dir" "$stage_name" "complete" ""

    # Save waypoint if applicable (saved BEFORE stage considered done per spec)
    local waypoint
    waypoint=$(echo "$stage_json" | jq -r '.waypoint // false')
    if [[ "$waypoint" == "true" ]]; then
      waypoint_save "$stage_name" "$mission_name" "$run_id" "$state_dir"
      _orbit_log_event "info" "mission.waypoint" "Waypoint saved: stage '${stage_name}'"
    fi

    # Update metrics after each stage
    total_orbits=$((total_orbits + 1))
    metrics_update "$run_id" "$total_orbits" "$start_epoch" "$state_dir"

    # Check flight rules after each stage
    if [[ "$flight_rules_json" != "[]" ]]; then
      local current_metrics
      current_metrics=$(metrics_read "$run_id" "$state_dir")
      flight_rules_check "$flight_rules_json" "$current_metrics" || {
        local fr_exit=$?
        if [[ $fr_exit -eq 2 ]]; then
          _write_stage_state "$run_dir" "$stage_name" "aborted" "flight rule violation"
          _write_run_state "$run_dir" "aborted"
          return 1
        fi
      }
    fi
  done

  _write_run_state "$run_dir" "complete"
  _orbit_log_event "info" "mission.complete" "Mission '${mission_name}' completed (run: ${run_id})"
  echo "Mission '${mission_name}' complete."
}

# Parse timeout string to hours (supports Nh, Nm, Ns)
_parse_timeout_hours() {
  local input="$1"
  if [[ "$input" =~ ^([0-9]+)h$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$input" =~ ^([0-9]+)m$ ]]; then
    echo "${BASH_REMATCH[1]}" | awk '{printf "%.4f", $1/60}'
  elif [[ "$input" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}" | awk '{printf "%.6f", $1/3600}'
  elif [[ "$input" =~ ^([0-9]+)$ ]]; then
    # Default: treat as hours
    echo "${BASH_REMATCH[1]}"
  else
    echo "72"
  fi
}

# --------------------------------------------------------------------------
# Topological sort — iterative, detects cycles
# --------------------------------------------------------------------------
_topological_sort() {
  local -n _sorted=$1
  _sorted=()

  local stage_count=${#ORBIT_MISSION_STAGES[@]}
  local -A completed=()
  local -A stage_name_to_idx=()

  # Build name→index map
  local i
  for ((i = 0; i < stage_count; i++)); do
    local name
    name=$(echo "${ORBIT_MISSION_STAGES[$i]}" | jq -r '.name')
    stage_name_to_idx["$name"]=$i
  done

  local passes=0
  while [[ ${#_sorted[@]} -lt $stage_count ]]; do
    passes=$((passes + 1))
    if [[ $passes -gt $((stage_count + 1)) ]]; then
      echo "Error: cycle detected in mission stages." >&2
      return 1
    fi

    local added_this_pass=false
    for ((i = 0; i < stage_count; i++)); do
      [[ -n "${completed[$i]:-}" ]] && continue

      local deps_json
      deps_json=$(echo "${ORBIT_MISSION_STAGES[$i]}" | jq -c '.depends_on // []')
      local deps_satisfied=true

      while IFS= read -r dep_name; do
        [[ -z "$dep_name" ]] && continue
        local dep_idx="${stage_name_to_idx[$dep_name]:-}"
        if [[ -z "$dep_idx" ]] || [[ -z "${completed[$dep_idx]:-}" ]]; then
          deps_satisfied=false
          break
        fi
      done < <(echo "$deps_json" | jq -r '.[]')

      if [[ "$deps_satisfied" == "true" ]]; then
        _sorted+=("$i")
        completed[$i]=1
        added_this_pass=true
      fi
    done

    if [[ "$added_this_pass" == "false" ]]; then
      echo "Error: cycle detected in mission stages." >&2
      return 1
    fi
  done
}

# --------------------------------------------------------------------------
# Print dry-run execution plan
# --------------------------------------------------------------------------
_print_execution_plan() {
  local mission_name="$1"
  local -n _plan_stages=$2

  echo "Execution Plan: ${mission_name}"
  echo "=============================="
  echo ""

  local i
  for ((i = 0; i < ${#_plan_stages[@]}; i++)); do
    local stage_idx="${_plan_stages[$i]}"
    local stage_json="${ORBIT_MISSION_STAGES[$stage_idx]}"
    local name comp stage_type deps_json waypoint orbits_to
    name=$(echo "$stage_json" | jq -r '.name')
    comp=$(echo "$stage_json" | jq -r '.component // "—"')
    stage_type=$(echo "$stage_json" | jq -r '.type // "component"')
    deps_json=$(echo "$stage_json" | jq -r '.depends_on // [] | join(", ")')
    waypoint=$(echo "$stage_json" | jq -r '.waypoint // false')
    orbits_to=$(echo "$stage_json" | jq -r '.orbits_to // "—"')

    echo "$((i + 1)). ${name}"
    echo "   type: ${stage_type}"
    [[ "$comp" != "—" ]] && echo "   component: ${comp}"
    [[ -n "$deps_json" ]] && echo "   depends_on: ${deps_json}"
    [[ "$waypoint" == "true" ]] && echo "   waypoint: true"
    [[ "$orbits_to" != "—" ]] && echo "   orbits_to: ${orbits_to}"
    echo ""
  done
}

# --------------------------------------------------------------------------
# Find resume point from latest waypoint
# --------------------------------------------------------------------------
_find_resume_point() {
  local mission_name="$1"
  local state_dir="$2"
  local -n _resume_stages=$3

  # Use waypoint_resume_from to find last waypointed stage
  local last_wp_stage
  last_wp_stage=$(waypoint_resume_from "$mission_name" "$state_dir")

  if [[ -z "$last_wp_stage" ]]; then
    echo 0
    return
  fi

  # Find index of last waypoint stage in sorted order, return next
  local i
  for ((i = 0; i < ${#_resume_stages[@]}; i++)); do
    local stage_idx="${_resume_stages[$i]}"
    local stage_json="${ORBIT_MISSION_STAGES[$stage_idx]}"
    local stage_name
    stage_name=$(echo "$stage_json" | jq -r '.name')
    if [[ "$stage_name" == "$last_wp_stage" ]]; then
      echo $((i + 1))
      return
    fi
  done

  echo 0
}

# --------------------------------------------------------------------------
# Execute orbits_to loop
# --------------------------------------------------------------------------
_execute_orbits_to_loop() {
  local stage_json="$1"
  local project_dir="$2"
  local state_dir="$3"
  local run_dir="$4"
  local -n _total_orbits=$5

  local stage_name orbits_to max_orbits
  stage_name=$(echo "$stage_json" | jq -r '.name')
  orbits_to=$(echo "$stage_json" | jq -r '.orbits_to')
  max_orbits=$(echo "$stage_json" | jq -r '.max_orbits // 100')

  local exit_when exit_condition
  exit_when=$(echo "$stage_json" | jq -r '.orbit_exit.when // "bash"')
  exit_condition=$(echo "$stage_json" | jq -r '.orbit_exit.condition // "false"')

  echo "Executing orbits_to loop: ${stage_name} → ${orbits_to} (max: ${max_orbits})"

  local loop_count=0
  while true; do
    loop_count=$((loop_count + 1))
    _total_orbits=$((_total_orbits + 1))

    if [[ $loop_count -gt $max_orbits ]]; then
      echo "orbits_to ceiling reached (${max_orbits}) for stage '${stage_name}'" >&2
      return 1
    fi

    # Execute the stage component
    _execute_stage_component "$stage_json" "$project_dir" "$state_dir" || true

    # Check exit condition
    if _check_orbit_exit "$exit_when" "$exit_condition"; then
      echo "orbits_to exit condition met for '${stage_name}' after ${loop_count} iterations"
      return 0
    fi
  done
}

_check_orbit_exit() {
  local when="$1"
  local condition="$2"

  case "$when" in
    file)  [ -f "$condition" ] ;;
    bash)  eval "$condition" 2>/dev/null ;;
    *)     return 1 ;;
  esac
}

# --------------------------------------------------------------------------
# Execute a single stage's component
# --------------------------------------------------------------------------
_execute_stage_component() {
  local stage_json="$1"
  local project_dir="$2"
  local state_dir="$3"

  local comp_name
  comp_name=$(echo "$stage_json" | jq -r '.component // empty')

  if [[ -z "$comp_name" ]]; then
    return 0
  fi

  local comp_file
  comp_file=$(registry_get_component "$comp_name" "$project_dir") || return 1

  config_load_component "${project_dir}/${comp_file}"

  if [[ -z "${ORBIT_COMPONENT[orbits.success.condition]:-}" ]]; then
    echo "Component '$comp_name' has no success condition — skipping." >&2
    return 0
  fi

  local args=()
  _build_component_args args "$comp_name" "$state_dir"
  orbit_run_component "${args[@]}"
}

# --------------------------------------------------------------------------
# State helpers
# --------------------------------------------------------------------------
_write_stage_state() {
  local run_dir="$1"
  local stage_name="$2"
  local status="$3"
  local note="$4"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local state
  state=$(jq -nc \
    --arg name "$stage_name" \
    --arg status "$status" \
    --arg ts "$now" \
    --arg note "$note" \
    '{name: $name, status: $status, updated_at: $ts, note: $note}')
  _atomic_write "${run_dir}/stages/${stage_name}.json" "$state"
}

_write_run_state() {
  local run_dir="$1"
  local status="$2"

  local mission_file="${run_dir}/mission.json"
  if [[ -f "$mission_file" ]]; then
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local updated
    updated=$(jq --arg status "$status" --arg ts "$now" \
      '.status = $status | .completed_at = $ts' "$mission_file")
    _atomic_write "$mission_file" "$updated"
  fi
}
