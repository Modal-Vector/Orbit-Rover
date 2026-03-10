#!/usr/bin/env bash
set -euo pipefail

# tools_cli.sh — orbit tools subcommand
# Tool governance CLI.

cmd_tools() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit tools <pending|grant|deny|log>" >&2
    return 1
  fi

  local subcmd="$1"; shift

  case "$subcmd" in
    pending)
      local output
      output=$(tool_request_list_pending "$state_dir" 2>/dev/null)
      if [[ -z "$output" ]]; then
        echo "No pending tool requests."
      else
        echo "$output"
      fi
      ;;
    grant)
      if [[ $# -lt 2 ]]; then
        echo "Usage: orbit tools grant <tool> <component>" >&2
        return 1
      fi
      local tool="$1" component="$2"
      tool_request_grant "$tool" "$component" "$state_dir"
      echo "Tool '${tool}' granted to '${component}'."
      ;;
    deny)
      if [[ $# -lt 2 ]]; then
        echo "Usage: orbit tools deny <tool> <component>" >&2
        return 1
      fi
      local tool="$1" component="$2"
      tool_request_deny "$tool" "$component" "denied via CLI" "$state_dir"
      echo "Tool '${tool}' denied for '${component}'."
      ;;
    log)
      local log_output=""
      local pending_file="${state_dir}/tool-requests/pending.jsonl"
      local denied_file="${state_dir}/tool-requests/denied.jsonl"

      if [[ -f "$pending_file" ]]; then
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local ts tool comp status
          ts=$(echo "$line" | jq -r '.requested_at // .timestamp // ""')
          tool=$(echo "$line" | jq -r '.tool // ""')
          comp=$(echo "$line" | jq -r '.component // ""')
          status=$(echo "$line" | jq -r '.status // ""')
          log_output+="[${ts}] ${tool} (${comp}): ${status}"$'\n'
        done < "$pending_file"
      fi

      if [[ -f "$denied_file" ]]; then
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          local ts tool comp
          ts=$(echo "$line" | jq -r '.denied_at // .timestamp // ""')
          tool=$(echo "$line" | jq -r '.tool // ""')
          comp=$(echo "$line" | jq -r '.component // ""')
          log_output+="[${ts}] ${tool} (${comp}): denied"$'\n'
        done < "$denied_file"
      fi

      if [[ -z "$log_output" ]]; then
        echo "No tool request history."
      else
        echo -n "$log_output" | sort
      fi
      ;;
    *)
      echo "Unknown subcommand: $subcmd" >&2
      return 1
      ;;
  esac
}
