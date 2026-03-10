#!/usr/bin/env bash
set -euo pipefail

# opencode.sh — opencode adapter for Orbit Rover

# Invoke opencode adapter.
# Usage: adapter_opencode "$prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned"
# Model is passed through directly (no mapping).
# Returns: agent output on stdout, exit code passed through.
adapter_opencode() {
  local prompt="$1"
  local model="${2:-}"
  local max_turns="${3:-10}"
  local tools_policy="${4:-standard}"
  local tools_assigned="${5:-}"

  local args=()
  args+=("run" "-p" "$prompt" "-f" "json" "-q")

  if [ -n "$model" ]; then
    args+=("--model" "$model")
  fi

  if [ "$tools_policy" = "restricted" ] && [ -n "$tools_assigned" ]; then
    args+=("--no-auto-tools" "--tools" "$tools_assigned")
  fi

  local output
  local exit_code=0
  output=$(opencode "${args[@]}" 2>/dev/null) || exit_code=$?

  echo "$output"
  return $exit_code
}
