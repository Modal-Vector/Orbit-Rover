#!/usr/bin/env bash
set -euo pipefail

# log.sh — orbit log subcommand
# Reads and formats .orbit/logs/*.jsonl.

cmd_log() {
  local tail_n=0
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tail)
        tail_n="$2"; shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done

  local log_dir="${state_dir}/logs"

  if [[ ! -d "$log_dir" ]] || ! ls "$log_dir"/*.jsonl >/dev/null 2>&1; then
    echo "No log entries found."
    return 0
  fi

  local output=""
  for log_file in "$log_dir"/*.jsonl; do
    [[ -f "$log_file" ]] || continue
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local ts level msg
      ts=$(echo "$line" | jq -r '.timestamp // ""')
      level=$(echo "$line" | jq -r '.level // ""')
      msg=$(echo "$line" | jq -r '.message // ""')
      output+="[${ts}] [${level}] ${msg}"$'\n'
    done < "$log_file"
  done

  if [[ -z "$output" ]]; then
    echo "No log entries found."
    return 0
  fi

  if [[ "$tail_n" -gt 0 ]]; then
    echo -n "$output" | tail -n "$tail_n"
  else
    echo -n "$output"
  fi
}
