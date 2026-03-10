#!/usr/bin/env bash
set -euo pipefail

# requests.sh — Tool request governance for Orbit Rover

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ORBIT_LIB_DIR/util.sh"
source "$ORBIT_LIB_DIR/extract.sh"
source "$ORBIT_LIB_DIR/tools/auth.sh"

# Append a tool request to pending.jsonl.
# Usage: tool_request_append component tool justification run_id state_dir
tool_request_append() {
  local component="$1"
  local tool="$2"
  local justification="$3"
  local run_id="$4"
  local state_dir="$5"

  local req_id
  req_id=$(_orbit_gen_id "req-" "${component}:${tool}:${run_id}")

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local json
  json=$(jq -nc \
    --arg id "$req_id" \
    --arg comp "$component" \
    --arg tool "$tool" \
    --arg just "$justification" \
    --arg run "$run_id" \
    --arg ts "$now" \
    --arg status "pending" \
    '{id: $id, component: $comp, tool: $tool, justification: $just, run_id: $run, status: $status, created_at: $ts}')

  local pending_file="${state_dir}/tool-requests/pending.jsonl"
  _atomic_append_jsonl "$pending_file" "$json"

  echo "$req_id"
}

# List pending tool requests in human-readable format.
# Usage: tool_request_list_pending state_dir
tool_request_list_pending() {
  local state_dir="$1"
  local pending_file="${state_dir}/tool-requests/pending.jsonl"

  if [ ! -f "$pending_file" ]; then
    echo "No pending tool requests."
    return 0
  fi

  local has_pending=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local status
    status=$(echo "$line" | jq -r '.status // "pending"')
    if [ "$status" != "pending" ]; then
      continue
    fi
    has_pending=true
    local id comp tool just ts
    id=$(echo "$line" | jq -r '.id')
    comp=$(echo "$line" | jq -r '.component')
    tool=$(echo "$line" | jq -r '.tool')
    just=$(echo "$line" | jq -r '.justification')
    ts=$(echo "$line" | jq -r '.created_at')
    echo "${id}  ${comp}  ${tool}  \"${just}\"  ${ts}"
  done < "$pending_file"

  if [ "$has_pending" = false ]; then
    echo "No pending tool requests."
  fi
}

# Grant a tool request. Updates pending.jsonl status, calls tool_auth_grant.
# Usage: tool_request_grant request_id_or_tool component state_dir [auth_key]
tool_request_grant() {
  local id_or_tool="$1"
  local component="$2"
  local state_dir="$3"
  local auth_key="${4:-}"

  local pending_file="${state_dir}/tool-requests/pending.jsonl"

  if [ ! -f "$pending_file" ]; then
    orbit_warn "No pending requests file found"
    return 1
  fi

  local matched=false
  local tool_name=""
  local tmp
  tmp=$(mktemp "${state_dir}/tool-requests/.orbit-tmp.XXXXXX")

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local lid lstatus ltool lcomp
    lid=$(echo "$line" | jq -r '.id')
    lstatus=$(echo "$line" | jq -r '.status // "pending"')
    ltool=$(echo "$line" | jq -r '.tool')
    lcomp=$(echo "$line" | jq -r '.component')

    if [ "$lstatus" = "pending" ] && { [ "$lid" = "$id_or_tool" ] || { [ "$ltool" = "$id_or_tool" ] && [ "$lcomp" = "$component" ]; }; }; then
      matched=true
      tool_name="$ltool"
      echo "$line" | jq -c '.status = "granted"' >> "$tmp"
    else
      echo "$line" >> "$tmp"
    fi
  done < "$pending_file"

  mv "$tmp" "$pending_file"

  if [ "$matched" = true ] && [ -n "$auth_key" ] && [ -n "$tool_name" ]; then
    tool_auth_grant "$component" "$tool_name" "$auth_key" "$state_dir"
  fi

  if [ "$matched" = false ]; then
    orbit_warn "No pending request found for '${id_or_tool}' (component: ${component})"
    return 1
  fi
}

# Deny a tool request. Updates pending.jsonl status, writes to denied.jsonl.
# Usage: tool_request_deny request_id_or_tool component reason state_dir
tool_request_deny() {
  local id_or_tool="$1"
  local component="$2"
  local reason="$3"
  local state_dir="$4"

  local pending_file="${state_dir}/tool-requests/pending.jsonl"
  local denied_file="${state_dir}/tool-requests/denied.jsonl"

  if [ ! -f "$pending_file" ]; then
    orbit_warn "No pending requests file found"
    return 1
  fi

  local matched=false
  local tmp
  tmp=$(mktemp "${state_dir}/tool-requests/.orbit-tmp.XXXXXX")

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local lid lstatus ltool lcomp
    lid=$(echo "$line" | jq -r '.id')
    lstatus=$(echo "$line" | jq -r '.status // "pending"')
    ltool=$(echo "$line" | jq -r '.tool')
    lcomp=$(echo "$line" | jq -r '.component')

    if [ "$lstatus" = "pending" ] && { [ "$lid" = "$id_or_tool" ] || { [ "$ltool" = "$id_or_tool" ] && [ "$lcomp" = "$component" ]; }; }; then
      matched=true
      local denied_entry
      denied_entry=$(echo "$line" | jq -c --arg reason "$reason" '.status = "denied" | .reason = $reason')
      echo "$denied_entry" >> "$tmp"
      _atomic_append_jsonl "$denied_file" "$denied_entry"
    else
      echo "$line" >> "$tmp"
    fi
  done < "$pending_file"

  mv "$tmp" "$pending_file"

  if [ "$matched" = false ]; then
    orbit_warn "No pending request found for '${id_or_tool}' (component: ${component})"
    return 1
  fi
}

# Parse <tool_request> tags from agent output and append requests.
# Usage: tool_request_parse_tags output component run_id state_dir
tool_request_parse_tags() {
  local output="$1"
  local component="$2"
  local run_id="$3"
  local state_dir="$4"

  local requests
  if ! requests=$(extract_tag "$output" "tool_request"); then
    echo "0"
    return 0
  fi

  # extract_tag returns each match on a separate line. Process each line.
  local count=0

  while IFS= read -r block; do
    [ -z "$block" ] && continue
    local tool just
    tool=$(extract_tag "$block" "tool") || true
    just=$(extract_tag "$block" "justification") || true
    if [ -n "$tool" ]; then
      tool_request_append "$component" "$tool" "${just:-no justification provided}" "$run_id" "$state_dir" >/dev/null
      count=$((count + 1))
    fi
  done <<< "$requests"

  echo "$count"
}
