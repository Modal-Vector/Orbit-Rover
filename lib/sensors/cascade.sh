#!/usr/bin/env bash
set -euo pipefail

# cascade.sh — Cascade control for sensor self-trigger prevention

# Mark a component as actively running (cascade block check)
# Usage: cascade_mark_active component_name run_id state_dir
cascade_mark_active() {
  local component="$1"
  local run_id="$2"
  local state_dir="$3"
  local cascade_dir="${state_dir}/cascade"
  local active_file="${cascade_dir}/active.json"

  mkdir -p "$cascade_dir"

  local current="{}"
  if [[ -f "$active_file" ]] && jq empty "$active_file" 2>/dev/null; then
    current=$(cat "$active_file")
  fi

  local updated
  updated=$(echo "$current" | jq --arg name "$component" --arg rid "$run_id" \
    '.[$name] = $rid')

  # Atomic write
  local tmp
  tmp=$(mktemp "${cascade_dir}/.orbit-tmp.XXXXXX")
  echo "$updated" > "$tmp"
  mv "$tmp" "$active_file"
}

# Remove a component from the active list
# Usage: cascade_mark_done component_name run_id state_dir
cascade_mark_done() {
  local component="$1"
  local run_id="$2"
  local state_dir="$3"
  local active_file="${state_dir}/cascade/active.json"

  if [[ ! -f "$active_file" ]]; then
    return 0
  fi

  local current="{}"
  if jq empty "$active_file" 2>/dev/null; then
    current=$(cat "$active_file")
  fi

  local updated
  updated=$(echo "$current" | jq --arg name "$component" 'del(.[$name])')

  local tmp
  tmp=$(mktemp "${state_dir}/cascade/.orbit-tmp.XXXXXX")
  echo "$updated" > "$tmp"
  mv "$tmp" "$active_file"
}

# Check if a component is currently active (for cascade block)
# Returns 0 if active, 1 if not
# Usage: cascade_is_active component_name state_dir
cascade_is_active() {
  local component="$1"
  local state_dir="$2"
  local active_file="${state_dir}/cascade/active.json"

  if [[ ! -f "$active_file" ]]; then
    return 1
  fi

  if ! jq empty "$active_file" 2>/dev/null; then
    return 1
  fi

  local has_key
  has_key=$(jq -r --arg name "$component" 'has($name)' "$active_file")
  [[ "$has_key" == "true" ]]
}
