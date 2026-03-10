#!/usr/bin/env bash
set -euo pipefail

# template.sh — Prompt template rendering with {key} substitution

# Render a template file with key=value substitutions.
# Usage: render_template "$prompt_file" key1=value1 key2=value2 ...
# Missing variables are left as-is. Empty values replace with empty string.
render_template() {
  local prompt_file="$1"
  shift

  if [ ! -f "$prompt_file" ]; then
    echo "[ORBIT ERROR] Template file not found: $prompt_file" >&2
    return 1
  fi

  local content
  content=$(cat "$prompt_file")

  for arg in "$@"; do
    local key="${arg%%=*}"
    local value="${arg#*=}"
    # Replace all occurrences of {key} with value
    content="${content//\{${key}\}/${value}}"
  done

  echo "$content"
}
