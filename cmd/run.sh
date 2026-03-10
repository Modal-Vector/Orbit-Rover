#!/usr/bin/env bash
set -euo pipefail

# run.sh — orbit run subcommand
# Runs a single component or module.

cmd_run() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit run <target> [--params '{...}']" >&2
    return 1
  fi

  local target="$1"; shift
  local params_json="{}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --params)
        params_json="$2"; shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  local project_dir="$(pwd)"
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  # Build registry if not built
  registry_build "$project_dir" 2>/dev/null || true

  # Try as component first
  local comp_file
  comp_file=$(registry_get_component "$target" "$project_dir" 2>/dev/null) || comp_file=""

  if [[ -n "$comp_file" ]]; then
    _run_component "$target" "$comp_file" "$project_dir" "$state_dir"
    return $?
  fi

  # Try as module
  local module_file="${project_dir}/modules/${target}.yaml"
  if [[ ! -f "$module_file" ]]; then
    module_file="${project_dir}/modules/${target}.yml"
  fi

  if [[ -f "$module_file" ]]; then
    _run_module "$target" "$module_file" "$params_json" "$project_dir" "$state_dir"
    return $?
  fi

  echo "Target '$target' not found as component or module." >&2
  return 1
}

_run_component() {
  local name="$1"
  local comp_file="$2"
  local project_dir="$3"
  local state_dir="$4"

  local full_path="${project_dir}/${comp_file}"
  config_load_component "$full_path"

  if [[ -z "${ORBIT_COMPONENT[orbits.success.condition]:-}" ]]; then
    echo "Component '$name' has no success condition — cannot run orbit loop." >&2
    return 1
  fi

  local args=()
  _build_component_args args "$name" "$state_dir"

  orbit_run_component "${args[@]}"
}

# Build orbit_run_component flags from ORBIT_COMPONENT
# Same pattern as _watch_dispatch in lib/watch.sh
_build_component_args() {
  local -n _args=$1
  local name="$2"
  local state_dir="$3"

  _args=(
    --component "$name"
    --prompt "${ORBIT_COMPONENT[prompt]:-prompts/default.md}"
    --adapter "${ORBIT_COMPONENT[agent]:-claude-code}"
    --model "${ORBIT_COMPONENT[model]:-sonnet}"
    --state-dir "$state_dir"
  )

  [[ -n "${ORBIT_COMPONENT[max_turns]:-}" ]] && _args+=(--max-turns "${ORBIT_COMPONENT[max_turns]}")
  [[ -n "${ORBIT_COMPONENT[orbits.max]:-}" ]] && _args+=(--orbits-max "${ORBIT_COMPONENT[orbits.max]}")
  [[ -n "${ORBIT_COMPONENT[orbits.success.when]:-}" ]] && _args+=(--success-when "${ORBIT_COMPONENT[orbits.success.when]}")
  [[ -n "${ORBIT_COMPONENT[orbits.success.condition]:-}" ]] && _args+=(--success-condition "${ORBIT_COMPONENT[orbits.success.condition]}")
  [[ -n "${ORBIT_COMPONENT[orbits.deadlock.threshold]:-}" ]] && _args+=(--deadlock-threshold "${ORBIT_COMPONENT[orbits.deadlock.threshold]}")
  [[ -n "${ORBIT_COMPONENT[orbits.deadlock.action]:-}" ]] && _args+=(--deadlock-action "${ORBIT_COMPONENT[orbits.deadlock.action]}")
  [[ -n "${ORBIT_COMPONENT[delivers]:-}" ]] && _args+=(--delivers "${ORBIT_COMPONENT[delivers]}")
  [[ -n "${ORBIT_COMPONENT[preflight]:-}" ]] && _args+=(--preflight "${ORBIT_COMPONENT[preflight]}")
  [[ -n "${ORBIT_COMPONENT[postflight]:-}" ]] && _args+=(--postflight "${ORBIT_COMPONENT[postflight]}")
  [[ -n "${ORBIT_COMPONENT[tools.policy]:-}" ]] && _args+=(--tools-policy "${ORBIT_COMPONENT[tools.policy]}")
  [[ -n "${ORBIT_COMPONENT[tools.assigned]:-}" ]] && _args+=(--tools-assigned "${ORBIT_COMPONENT[tools.assigned]}")

  # Retry flags
  if [[ -n "${ORBIT_COMPONENT[retry.max_attempts]:-}" ]]; then
    _args+=(--retry-max "${ORBIT_COMPONENT[retry.max_attempts]}")
  fi
  if [[ -n "${ORBIT_COMPONENT[retry.backoff]:-}" ]]; then
    _args+=(--retry-backoff "${ORBIT_COMPONENT[retry.backoff]}")
  fi
  if [[ -n "${ORBIT_COMPONENT[retry.initial_delay]:-}" ]]; then
    local parsed_delay
    parsed_delay=$(_retry_parse_delay "${ORBIT_COMPONENT[retry.initial_delay]}")
    _args+=(--retry-initial-delay "$parsed_delay")
  fi
  if [[ -n "${ORBIT_COMPONENT[retry.max_delay]:-}" ]]; then
    local parsed_max
    parsed_max=$(_retry_parse_delay "${ORBIT_COMPONENT[retry.max_delay]}")
    _args+=(--retry-max-delay "$parsed_max")
  fi
  if [[ -n "${ORBIT_COMPONENT[retry.on_timeout]:-}" ]]; then
    _args+=(--retry-on-timeout "${ORBIT_COMPONENT[retry.on_timeout]}")
  fi
}

_run_module() {
  local name="$1"
  local module_file="$2"
  local params_json="$3"
  local project_dir="$4"
  local state_dir="$5"

  # Parse params JSON into key=value pairs
  local params_args=()
  local keys
  keys=$(echo "$params_json" | jq -r 'keys[]' 2>/dev/null || true)
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    local val
    val=$(echo "$params_json" | jq -r --arg k "$key" '.[$k]')
    params_args+=("${key}=${val}")
  done <<< "$keys"

  config_load_module "$module_file" "${params_args[@]}"

  echo "Running module '$name' with ${#ORBIT_MODULE_STAGES[@]} stages"

  local i
  for ((i = 0; i < ${#ORBIT_MODULE_STAGES[@]}; i++)); do
    local stage_json="${ORBIT_MODULE_STAGES[$i]}"
    _run_stage_component "$stage_json" "$project_dir" "$state_dir"
  done

  echo "Module '$name' complete."
}

# Run a single stage's component
_run_stage_component() {
  local stage_json="$1"
  local project_dir="$2"
  local state_dir="$3"

  local stage_name comp_name
  stage_name=$(echo "$stage_json" | jq -r '.name // "unknown"')
  comp_name=$(echo "$stage_json" | jq -r '.component // empty')

  if [[ -z "$comp_name" ]]; then
    echo "Stage '$stage_name' has no component — skipping." >&2
    return 0
  fi

  local comp_file
  comp_file=$(registry_get_component "$comp_name" "$project_dir") || {
    echo "Component '$comp_name' not found in registry for stage '$stage_name'." >&2
    return 1
  }

  config_load_component "${project_dir}/${comp_file}"

  if [[ -z "${ORBIT_COMPONENT[orbits.success.condition]:-}" ]]; then
    echo "Stage '$stage_name': component '$comp_name' has no success condition — skipping." >&2
    return 0
  fi

  echo "Running stage '$stage_name' (component: $comp_name)"

  local args=()
  _build_component_args args "$comp_name" "$state_dir"
  orbit_run_component "${args[@]}"
}
