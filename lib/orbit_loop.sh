#!/usr/bin/env bash
set -euo pipefail

# orbit_loop.sh — Core orbit loop for Orbit Rover
# Integrates: template.sh, hash.sh, extract.sh, adapters

ORBIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$ORBIT_LIB_DIR/util.sh"
source "$ORBIT_LIB_DIR/extract.sh"
source "$ORBIT_LIB_DIR/template.sh"
source "$ORBIT_LIB_DIR/adapters/claude_code.sh"
source "$ORBIT_LIB_DIR/adapters/opencode.sh"
source "$ORBIT_LIB_DIR/learning/parse_tags.sh"

# Invoke the configured adapter
_invoke_adapter() {
  local adapter="$1"
  local prompt="$2"
  local model="$3"
  local max_turns="$4"
  local tools_policy="$5"
  local tools_assigned="$6"

  case "$adapter" in
    claude-code)
      adapter_claude_code "$prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned"
      ;;
    opencode)
      adapter_opencode "$prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned"
      ;;
    *)
      orbit_error "Unknown adapter: $adapter"
      return 1
      ;;
  esac
}

# Check success condition
_check_success() {
  local success_when="$1"
  local success_condition="$2"

  case "$success_when" in
    file)
      [ -f "$success_condition" ]
      ;;
    bash)
      eval "$success_condition"
      ;;
    *)
      orbit_error "Unknown success mode: $success_when"
      return 1
      ;;
  esac
}

# The perspective reframe prompt injected on deadlock
_perspective_prompt() {
  cat <<'EOF'
IMPORTANT: You appear to be stuck in a loop — your last several orbits produced
no changes to the output files. Take a different approach:

1. Re-read the task requirements carefully
2. Identify what specific obstacle is preventing progress
3. Try a fundamentally different strategy
4. If the task cannot be completed as specified, document why in your checkpoint

Do NOT repeat the same approach that has been failing.
EOF
}

# Main entry point: run a component through the orbit loop.
# All configuration via named flags (YAML parsing is Phase 2).
#
# Usage: orbit_run_component \
#   --component NAME \
#   --prompt TEMPLATE_PATH \
#   --adapter claude-code|opencode \
#   --model MODEL \
#   --max-turns N \
#   --orbits-max N \
#   --success-when file|bash \
#   --success-condition CONDITION \
#   --deadlock-threshold N \
#   --deadlock-action perspective|abort \
#   --delivers FILE1,FILE2,... \
#   --preflight SCRIPT1,SCRIPT2,... \
#   --postflight SCRIPT1,SCRIPT2,... \
#   --tools-policy standard|restricted \
#   --tools-assigned TOOL1,TOOL2,... \
#   --state-dir DIR
orbit_run_component() {
  # Parse named arguments
  local component="" prompt="" adapter="claude-code" model="sonnet"
  local max_turns=10 orbits_max=20
  local success_when="file" success_condition=""
  local deadlock_threshold=3 deadlock_action="abort"
  local delivers_str="" preflight_str="" postflight_str=""
  local tools_policy="standard" tools_assigned=""
  local state_dir=".orbit"
  local retry_max=1 retry_backoff="exponential" retry_initial_delay=5 retry_max_delay=60 retry_on_timeout="false"
  local run_id="" mission=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --component)        component="$2"; shift 2 ;;
      --prompt)           prompt="$2"; shift 2 ;;
      --adapter)          adapter="$2"; shift 2 ;;
      --model)            model="$2"; shift 2 ;;
      --max-turns)        max_turns="$2"; shift 2 ;;
      --orbits-max)       orbits_max="$2"; shift 2 ;;
      --success-when)     success_when="$2"; shift 2 ;;
      --success-condition) success_condition="$2"; shift 2 ;;
      --deadlock-threshold) deadlock_threshold="$2"; shift 2 ;;
      --deadlock-action)  deadlock_action="$2"; shift 2 ;;
      --delivers)         delivers_str="$2"; shift 2 ;;
      --preflight)        preflight_str="$2"; shift 2 ;;
      --postflight)       postflight_str="$2"; shift 2 ;;
      --tools-policy)     tools_policy="$2"; shift 2 ;;
      --tools-assigned)   tools_assigned="$2"; shift 2 ;;
      --state-dir)        state_dir="$2"; shift 2 ;;
      --retry-max)        retry_max="$2"; shift 2 ;;
      --retry-backoff)    retry_backoff="$2"; shift 2 ;;
      --retry-initial-delay) retry_initial_delay="$2"; shift 2 ;;
      --retry-max-delay)  retry_max_delay="$2"; shift 2 ;;
      --retry-on-timeout) retry_on_timeout="$2"; shift 2 ;;
      --run-id)           run_id="$2"; shift 2 ;;
      --mission)          mission="$2"; shift 2 ;;
      *)
        orbit_error "Unknown argument: $1"
        return 1
        ;;
    esac
  done

  # Validate required args
  if [ -z "$component" ]; then
    orbit_error "Missing required argument: --component"
    return 1
  fi
  if [ -z "$prompt" ]; then
    orbit_error "Missing required argument: --prompt"
    return 1
  fi
  if [ -z "$success_condition" ]; then
    orbit_error "Missing required argument: --success-condition"
    return 1
  fi

  # Parse comma-separated lists into arrays
  local delivers=()
  if [ -n "$delivers_str" ]; then
    IFS=',' read -ra delivers <<< "$delivers_str"
  fi

  local preflight=()
  if [ -n "$preflight_str" ]; then
    IFS=',' read -ra preflight <<< "$preflight_str"
  fi

  local postflight=()
  if [ -n "$postflight_str" ]; then
    IFS=',' read -ra postflight <<< "$postflight_str"
  fi

  # Setup state directory
  local comp_state_dir="${state_dir}/state/${component}"
  local checkpoint_file="${comp_state_dir}/checkpoint.md"
  mkdir -p "$comp_state_dir"
  mkdir -p "${state_dir}/learning/insights"
  mkdir -p "${state_dir}/learning/decisions"
  mkdir -p "${state_dir}/learning/feedback"

  # Orbit loop
  local orbit_count=0
  local deadlock_count=0
  local perspective_inject=""

  orbit_info "Starting component '$component' (adapter=$adapter, model=$model, max_orbits=$orbits_max)"

  while true; do
    orbit_count=$((orbit_count + 1))

    # Check ceiling
    if [ "$orbit_count" -gt "$orbits_max" ]; then
      orbit_error "Orbit ceiling reached ($orbits_max) for component '$component'"
      return 1
    fi

    orbit_info "Orbit $orbit_count/$orbits_max for '$component'"

    # Load checkpoint from previous orbit
    local checkpoint=""
    if [ -f "$checkpoint_file" ]; then
      checkpoint=$(cat "$checkpoint_file")
    fi

    # Render template
    local rendered_prompt
    rendered_prompt=$(render_template "$prompt" \
      "orbit.n=$orbit_count" \
      "orbit.checkpoint=$checkpoint" \
      "orbit.max=$orbits_max" \
      "component.name=$component")

    # Inject perspective prompt if deadlock was detected
    if [ -n "$perspective_inject" ]; then
      rendered_prompt="${perspective_inject}

${rendered_prompt}"
      perspective_inject=""
    fi

    # Run preflight hooks
    local preflight_failed=false
    for hook in "${preflight[@]}"; do
      if ! bash "$hook"; then
        orbit_error "Preflight failed: $hook"
        return 1
      fi
    done

    # Pre-hash delivers (deadlock detection)
    local pre_hash=""
    if [ ${#delivers[@]} -gt 0 ]; then
      pre_hash=$(hash_delivers "${delivers[@]}")
    fi

    # Invoke adapter
    local output=""
    local exit_code=0
    output=$(_invoke_adapter "$adapter" "$rendered_prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned") || exit_code=$?

    # Handle adapter error with retry logic
    if [ $exit_code -ne 0 ]; then
      orbit_warn "Adapter returned exit code $exit_code on orbit $orbit_count"

      # Retry logic
      local attempt=1
      while retry_should_retry "$attempt" "$retry_max" "$exit_code" "$retry_on_timeout"; do
        local delay
        delay=$(retry_delay "$attempt" "$retry_backoff" "$retry_initial_delay" "$retry_max_delay")
        orbit_info "Retrying in ${delay}s (attempt $((attempt + 1))/$retry_max)"
        sleep "$delay"
        attempt=$((attempt + 1))

        output=$(_invoke_adapter "$adapter" "$rendered_prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned") || exit_code=$?
        if [ $exit_code -eq 0 ]; then
          break
        fi
        orbit_warn "Retry attempt $attempt failed with exit code $exit_code"
      done

      if [ $exit_code -ne 0 ]; then
        continue
      fi
    fi

    # Extract and store learning tags
    parse_learning_tags "$output" "$component" "" "" "$orbit_count" "$state_dir"

    # Extract checkpoint for next orbit
    local new_checkpoint
    new_checkpoint=$(extract_checkpoint "$output")
    if [ -n "$new_checkpoint" ]; then
      _atomic_write "$checkpoint_file" "$new_checkpoint"
    fi

    # Run postflight hooks
    for hook in "${postflight[@]}"; do
      bash "$hook" || orbit_warn "Postflight hook failed: $hook"
    done

    # Deadlock detection (only if delivers are configured)
    if [ ${#delivers[@]} -gt 0 ]; then
      local post_hash
      post_hash=$(hash_delivers "${delivers[@]}")

      # Both empty = no files exist yet, not deadlock
      if [ -n "$pre_hash" ] || [ -n "$post_hash" ]; then
        if [ "$pre_hash" = "$post_hash" ]; then
          deadlock_count=$((deadlock_count + 1))
          orbit_warn "No output change detected ($deadlock_count/$deadlock_threshold)"

          if [ "$deadlock_count" -ge "$deadlock_threshold" ]; then
            if [ "$deadlock_action" = "perspective" ]; then
              orbit_warn "Deadlock threshold reached — injecting perspective prompt"
              perspective_inject=$(_perspective_prompt)
              deadlock_count=0
            else
              orbit_error "Deadlock detected: no output change after $deadlock_threshold orbits for '$component'"
              return 1
            fi
          fi
        else
          deadlock_count=0
        fi
      fi
    fi

    # Check success condition
    if _check_success "$success_when" "$success_condition"; then
      orbit_info "Success condition met for '$component' on orbit $orbit_count"
      return 0
    fi
  done
}
