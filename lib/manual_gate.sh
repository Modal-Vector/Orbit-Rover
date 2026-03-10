#!/usr/bin/env bash
set -euo pipefail

# manual_gate.sh — Manual approval gates for mission safety
# File-based polling mechanism: write prompt.json, poll for response.json

# Sleep helper with sub-second fallback
_sleep_poll() {
  sleep 0.5 2>/dev/null || sleep 1
}

# Cross-platform ISO-8601 date parsing to epoch seconds
_iso_to_epoch() {
  local iso="$1"
  # Try GNU date first
  date -d "$iso" +%s 2>/dev/null && return 0
  # macOS date
  # Strip timezone suffix for -j -f parsing
  local cleaned
  cleaned=$(echo "$iso" | sed 's/Z$//' | sed 's/+00:00$//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//')
  date -j -f "%Y-%m-%dT%H:%M:%S" "$cleaned" +%s 2>/dev/null && return 0
  # Python fallback
  python3 -c "
import datetime, sys
dt = datetime.datetime.fromisoformat('$iso'.replace('Z','+00:00'))
print(int(dt.timestamp()))
" 2>/dev/null && return 0
  return 1
}

# Open a manual gate — write prompt.json and poll for response
# Returns the chosen option on stdout
manual_gate_open() {
  local gate_id="$1"
  local mission="$2"
  local run_id="$3"
  local prompt="$4"
  local options_json="$5"   # JSON array string, e.g. '["approve","reject"]'
  local timeout_hours="$6"
  local default_option="$7"
  local state_dir="$8"

  local gate_dir="${state_dir}/manual/${gate_id}"
  mkdir -p "$gate_dir"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Compute timeout_at
  local timeout_seconds
  timeout_seconds=$(echo "$timeout_hours" | awk '{printf "%d", $1 * 3600}')
  local now_epoch
  now_epoch=$(date -u +%s)
  local timeout_epoch=$((now_epoch + timeout_seconds))
  local timeout_at
  # GNU date
  timeout_at=$(date -u -d "@${timeout_epoch}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
    timeout_at=$(date -u -r "${timeout_epoch}" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
    timeout_at=$(python3 -c "import datetime; print(datetime.datetime.utcfromtimestamp(${timeout_epoch}).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null) || \
    timeout_at="$now"

  local prompt_json
  prompt_json=$(jq -nc \
    --arg gate_id "$gate_id" \
    --arg mission "$mission" \
    --arg run_id "$run_id" \
    --arg prompt "$prompt" \
    --argjson options "$options_json" \
    --arg timeout_at "$timeout_at" \
    --arg default "$default_option" \
    --arg created_at "$now" \
    '{gate_id: $gate_id, mission: $mission, run_id: $run_id, prompt: $prompt, options: $options, timeout_at: $timeout_at, default: $default, created_at: $created_at}')
  _atomic_write "${gate_dir}/prompt.json" "$prompt_json"

  orbit_info "Gate '${gate_id}' is pending. Run: orbit pending"

  # Poll for response
  while true; do
    # Check for response file
    if [[ -f "${gate_dir}/response.json" ]]; then
      local option
      option=$(jq -r '.option // empty' "${gate_dir}/response.json" 2>/dev/null)
      if [[ -n "$option" ]]; then
        orbit_info "Gate '${gate_id}' responded: ${option}"
        echo "$option"
        return 0
      fi
    fi

    # Check timeout
    local current_epoch
    current_epoch=$(date -u +%s)
    if [[ $current_epoch -ge $timeout_epoch ]]; then
      orbit_warn "Gate '${gate_id}' timed out — applying default: ${default_option}"
      # Write timeout response
      manual_gate_respond "$gate_id" "$default_option" "$state_dir"
      echo "$default_option"
      return 0
    fi

    _sleep_poll
  done
}

# Write response.json for a gate
manual_gate_respond() {
  local gate_id="$1"
  local option="$2"
  local state_dir="$3"

  local gate_dir="${state_dir}/manual/${gate_id}"

  if [[ ! -d "$gate_dir" ]] || [[ ! -f "${gate_dir}/prompt.json" ]]; then
    orbit_error "Gate '${gate_id}' not found."
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local response
  response=$(jq -nc \
    --arg gate_id "$gate_id" \
    --arg option "$option" \
    --arg responded_at "$now" \
    '{gate_id: $gate_id, option: $option, responded_at: $responded_at}')
  _atomic_write "${gate_dir}/response.json" "$response"
}

# List all pending gates (prompt.json exists, no response.json)
manual_gate_list_pending() {
  local state_dir="$1"
  local manual_dir="${state_dir}/manual"

  if [[ ! -d "$manual_dir" ]]; then
    echo "No pending gates."
    return 0
  fi

  local found=false
  for gate_dir in "$manual_dir"/*/; do
    [[ -d "$gate_dir" ]] || continue
    if [[ -f "${gate_dir}prompt.json" ]] && [[ ! -f "${gate_dir}response.json" ]]; then
      local gate_id mission options timeout_at created_at
      gate_id=$(jq -r '.gate_id // ""' "${gate_dir}prompt.json" 2>/dev/null)
      mission=$(jq -r '.mission // ""' "${gate_dir}prompt.json" 2>/dev/null)
      options=$(jq -r '.options // [] | join(", ")' "${gate_dir}prompt.json" 2>/dev/null)
      timeout_at=$(jq -r '.timeout_at // ""' "${gate_dir}prompt.json" 2>/dev/null)
      created_at=$(jq -r '.created_at // ""' "${gate_dir}prompt.json" 2>/dev/null)

      echo "Gate: ${gate_id}"
      echo "  Mission: ${mission}"
      echo "  Options: ${options}"
      echo "  Timeout: ${timeout_at}"
      echo "  Created: ${created_at}"
      echo ""
      found=true
    fi
  done

  if [[ "$found" == "false" ]]; then
    echo "No pending gates."
  fi
}

# Approve a gate (convenience wrapper)
manual_gate_approve() {
  local gate_id="$1"
  local option="${2:-approve}"
  local state_dir="$3"

  manual_gate_respond "$gate_id" "$option" "$state_dir"
}

# Reject a gate (convenience wrapper)
manual_gate_reject() {
  local gate_id="$1"
  local state_dir="$2"

  manual_gate_respond "$gate_id" "reject" "$state_dir"
}
