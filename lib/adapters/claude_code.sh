#!/usr/bin/env bash
set -euo pipefail

# claude_code.sh — claude-code adapter for Orbit Rover

# Map Rover model aliases to claude-code model strings
_claude_model_map() {
  local alias="$1"
  case "$alias" in
    sonnet)  echo "claude-sonnet-4-6" ;;
    opus)    echo "claude-opus-4-6" ;;
    haiku)   echo "claude-haiku-4-5-20251001" ;;
    *)       echo "$alias" ;;  # pass through unknown models
  esac
}

# Build the claude command arguments array.
# Usage: _claude_build_args "$prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned"
# Outputs args one per line for consumption by mapfile.
_claude_build_args() {
  local prompt="$1"
  local model="$2"
  local max_turns="$3"
  local tools_policy="$4"
  local tools_assigned="$5"

  local mapped_model
  mapped_model=$(_claude_model_map "$model")

  echo "-p"
  echo "--dangerously-skip-permissions"
  echo "--output-format"
  echo "json"
  echo "--model"
  echo "$mapped_model"
  echo "--max-turns"
  echo "$max_turns"

  if [ "$tools_policy" = "restricted" ] && [ -n "$tools_assigned" ]; then
    echo "--allowedTools"
    echo "$tools_assigned"
  fi
}

# Invoke claude-code adapter.
# Usage: adapter_claude_code "$prompt" "$model" "$max_turns" "$tools_policy" "$tools_assigned"
# Returns: agent output on stdout, exit code passed through
adapter_claude_code() {
  local prompt="$1"
  local model="${2:-sonnet}"
  local max_turns="${3:-10}"
  local tools_policy="${4:-standard}"
  local tools_assigned="${5:-}"

  local args=()
  local mapped_model
  mapped_model=$(_claude_model_map "$model")

  args+=("-p" "--dangerously-skip-permissions" "--output-format" "json" "--model" "$mapped_model" "--max-turns" "$max_turns")

  if [ "$tools_policy" = "restricted" ] && [ -n "$tools_assigned" ]; then
    args+=("--allowedTools" "$tools_assigned")
  fi

  local output
  local exit_code=0
  output=$(claude "${args[@]}" "$prompt" 2>/dev/null) || exit_code=$?

  if [ $exit_code -eq 0 ] && [ -n "$output" ]; then
    # Extract text result from JSON output
    local text
    text=$(echo "$output" | jq -r '.result // .text // .content // empty' 2>/dev/null) || text="$output"
    if [ -n "$text" ]; then
      echo "$text"
    else
      echo "$output"
    fi
  else
    echo "$output"
  fi

  return $exit_code
}
