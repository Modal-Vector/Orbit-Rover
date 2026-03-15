#!/usr/bin/env bash
set -euo pipefail

# watch.sh — Watch mode main loop for Orbit Rover
# Starts sensors, polls for triggers, dispatches component runs.

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

source "$ORBIT_LIB_DIR/config.sh"
source "$ORBIT_LIB_DIR/registry.sh"
source "$ORBIT_LIB_DIR/orbit_loop.sh"
source "$ORBIT_LIB_DIR/sensors/cascade.sh"
source "$ORBIT_LIB_DIR/sensors/schedule.sh"
source "$ORBIT_LIB_DIR/sensors/file_watch.sh"

# Arrays tracking started sensors for cleanup
_WATCH_FILE_COMPONENTS=()
_WATCH_INTERVAL_COMPONENTS=()
_WATCH_CRON_COMPONENTS=()

# Cleanup all sensors on exit
_watch_cleanup() {
  orbit_info "Watch mode shutting down — cleaning up sensors"

  for comp in "${_WATCH_FILE_COMPONENTS[@]}"; do
    sensor_file_watch_stop "$comp" "$_WATCH_STATE_DIR" 2>/dev/null || true
  done

  for comp in "${_WATCH_INTERVAL_COMPONENTS[@]}"; do
    sensor_interval_stop "$comp" "$_WATCH_STATE_DIR" 2>/dev/null || true
  done

  if [[ ${#_WATCH_CRON_COMPONENTS[@]} -gt 0 ]]; then
    sensor_cron_unregister_all 2>/dev/null || true
  fi

  # Clean trigger files
  rm -f "${_WATCH_STATE_DIR}/triggers/"* 2>/dev/null || true

  orbit_info "Watch mode cleanup complete"
}

# Dispatch a triggered component
_watch_dispatch() {
  local name="$1"
  local project_dir="$2"
  local state_dir="$3"

  # Look up component in registry
  local comp_file
  comp_file=$(registry_get_component "$name" "$project_dir") || {
    # Check if it's a mission
    local registry_file="${project_dir}/.orbit/registry.json"
    if [[ -f "$registry_file" ]]; then
      local mission_file
      mission_file=$(jq -r --arg name "$name" '.missions[$name].file // empty' "$registry_file")
      if [[ -n "$mission_file" ]]; then
        orbit_info "Mission '$name' triggered — full mission execution deferred to Phase 7"
        return 0
      fi
    fi
    orbit_warn "Triggered target '$name' not found in registry"
    return 1
  }

  local full_path="${project_dir}/${comp_file}"
  config_load_component "$full_path"

  # Update last_run timestamp
  local comp_state="${state_dir}/state/${name}"
  mkdir -p "$comp_state"
  date +%s > "${comp_state}/last_run"

  orbit_info "Dispatching component '$name'"

  # Build orbit_run_component flags from ORBIT_COMPONENT
  local args=(
    --component "$name"
    --prompt "${ORBIT_COMPONENT[prompt]:-prompts/default.md}"
    --adapter "${ORBIT_COMPONENT[agent]:-claude-code}"
    --model "${ORBIT_COMPONENT[model]:-sonnet}"
    --state-dir "$state_dir"
  )

  [[ -n "${ORBIT_COMPONENT[max_turns]:-}" ]] && args+=(--max-turns "${ORBIT_COMPONENT[max_turns]}")
  [[ -n "${ORBIT_COMPONENT[orbits.max]:-}" ]] && args+=(--orbits-max "${ORBIT_COMPONENT[orbits.max]}")
  [[ -n "${ORBIT_COMPONENT[orbits.success.when]:-}" ]] && args+=(--success-when "${ORBIT_COMPONENT[orbits.success.when]}")
  [[ -n "${ORBIT_COMPONENT[orbits.success.condition]:-}" ]] && args+=(--success-condition "${ORBIT_COMPONENT[orbits.success.condition]}")
  [[ -n "${ORBIT_COMPONENT[orbits.deadlock.threshold]:-}" ]] && args+=(--deadlock-threshold "${ORBIT_COMPONENT[orbits.deadlock.threshold]}")
  [[ -n "${ORBIT_COMPONENT[orbits.deadlock.action]:-}" ]] && args+=(--deadlock-action "${ORBIT_COMPONENT[orbits.deadlock.action]}")
  [[ -n "${ORBIT_COMPONENT[delivers]:-}" ]] && args+=(--delivers "${ORBIT_COMPONENT[delivers]}")
  [[ -n "${ORBIT_COMPONENT[preflight]:-}" ]] && args+=(--preflight "${ORBIT_COMPONENT[preflight]}")
  [[ -n "${ORBIT_COMPONENT[postflight]:-}" ]] && args+=(--postflight "${ORBIT_COMPONENT[postflight]}")
  [[ -n "${ORBIT_COMPONENT[tools.policy]:-}" ]] && args+=(--tools-policy "${ORBIT_COMPONENT[tools.policy]}")
  [[ -n "${ORBIT_COMPONENT[tools.assigned]:-}" ]] && args+=(--tools-assigned "${ORBIT_COMPONENT[tools.assigned]}")

  # Only run if we have a success condition
  if [[ -n "${ORBIT_COMPONENT[orbits.success.condition]:-}" ]]; then
    orbit_run_component "${args[@]}" || {
      orbit_warn "Component '$name' run completed with error"
    }
  else
    orbit_info "Component '$name' triggered but no success condition — skipping orbit loop"
  fi
}

# Main watch entry point
# Usage: watch_start project_dir
watch_start() {
  local project_dir="$1"

  # Load system config
  local system_config="${project_dir}/orbit.yaml"
  if [[ -f "$system_config" ]]; then
    config_load_system "$system_config"
  fi

  local state_dir="${project_dir}/${ORBIT_SYSTEM[settings.state_dir]:-.orbit}"
  _WATCH_STATE_DIR="$state_dir"

  # Build registry
  registry_build "$project_dir"

  # Create required directories
  mkdir -p "${state_dir}/triggers" "${state_dir}/sensors" "${state_dir}/cascade"

  # Initialize active.json
  if [[ ! -f "${state_dir}/cascade/active.json" ]]; then
    echo '{}' > "${state_dir}/cascade/active.json"
  fi

  # Set cleanup trap
  trap '_watch_cleanup' INT TERM EXIT

  # Load registry
  local registry
  registry=$(registry_load "$project_dir")

  # Get list of components with sensors
  local component_names
  component_names=$(echo "$registry" | jq -r '.components | to_entries[] | select(.value.status == "active" and .value.has_sensors == true) | .key')

  orbit_info "Watch mode starting — scanning for sensor-enabled components"

  # Start sensors for each active component with sensors
  while IFS= read -r comp_name; do
    [[ -z "$comp_name" ]] && continue

    local comp_file
    comp_file=$(registry_get_component "$comp_name" "$project_dir") || continue
    config_load_component "${project_dir}/${comp_file}"

    orbit_info "Configuring sensors for component '$comp_name'"

    # File watch sensor
    if [[ -n "${ORBIT_COMPONENT[sensors.paths]:-}" ]]; then
      local debounce="${ORBIT_COMPONENT[sensors.debounce]:-${ORBIT_SYSTEM[sensors.debounce_default]:-5s}}"
      local cascade="${ORBIT_COMPONENT[sensors.cascade]:-allow}"
      local events="${ORBIT_COMPONENT[sensors.events]:-}"

      sensor_file_watch_start "$comp_name" \
        "${ORBIT_COMPONENT[sensors.paths]}" \
        "$events" \
        "$debounce" \
        "$cascade" \
        "$state_dir" \
        "$project_dir"

      _WATCH_FILE_COMPONENTS+=("$comp_name")
      orbit_info "  File watch started for '$comp_name'"
    fi

    # Interval schedule sensor
    if [[ -n "${ORBIT_COMPONENT[sensors.schedule.every]:-}" ]]; then
      sensor_interval_start "$comp_name" \
        "${ORBIT_COMPONENT[sensors.schedule.every]}" \
        "$state_dir"

      _WATCH_INTERVAL_COMPONENTS+=("$comp_name")
      orbit_info "  Interval sensor started for '$comp_name' (every ${ORBIT_COMPONENT[sensors.schedule.every]})"
    fi

    # Cron schedule sensor
    if [[ -n "${ORBIT_COMPONENT[sensors.schedule.cron]:-}" ]]; then
      sensor_cron_register "$comp_name" \
        "${ORBIT_COMPONENT[sensors.schedule.cron]}" \
        "$project_dir" \
        "$state_dir"

      _WATCH_CRON_COMPONENTS+=("$comp_name")
      orbit_info "  Cron sensor registered for '$comp_name' (${ORBIT_COMPONENT[sensors.schedule.cron]})"
    fi
  done <<< "$component_names"

  orbit_info "Watch mode active — polling for triggers"

  # --- Trigger Polling Loop ---
  # Sensors write trigger files (e.g. state_dir/triggers/mycomp-filewatch)
  # asynchronously. This loop polls every second, picks up any trigger files,
  # extracts the component name by stripping the known suffix (-filewatch,
  # -schedule, -cron), removes the file to prevent re-dispatch, then hands
  # off to _watch_dispatch. Cascade active/done markers bracket the dispatch
  # so file sensors with cascade=block can detect self-triggered changes.
  while true; do
    for trigger_file in "${state_dir}/triggers/"*; do
      [[ -f "$trigger_file" ]] || continue

      local basename
      basename=$(basename "$trigger_file")
      local name="${basename%-filewatch}"
      name="${name%-schedule}"
      name="${name%-cron}"

      rm -f "$trigger_file"

      orbit_info "Trigger fired for '$name' (source: $basename)"

      local run_id
      run_id="$(_orbit_gen_id "run-" "$name")-$(date -u +%Y%m%d-%H:%M)"
      cascade_mark_active "$name" "$run_id" "$state_dir"

      _watch_dispatch "$name" "$project_dir" "$state_dir" || true

      cascade_mark_done "$name" "$run_id" "$state_dir"
    done

    sleep 1
  done
}
