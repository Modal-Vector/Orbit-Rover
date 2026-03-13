#!/usr/bin/env bash
set -euo pipefail

# decisions.sh — Decision JSONL with lifecycle management
#
# Decision lifecycle state machine:
#   proposed → accepted    (decision_accept)
#   proposed → rejected    (decision_reject)
#   proposed → superseded  (decision_supersede — creates a new decision referencing the old)
#   accepted → superseded  (decision_supersede)
#
# Scope-based file routing: decisions are stored per-scope in JSONL files:
#   project       → project.jsonl
#   mission:NAME  → mission.NAME.jsonl
#   component:NAME → component.NAME.jsonl
#   module:NAME   → module.NAME.jsonl
#
# Hierarchical assembly (decision_assemble) merges project + mission + component
# scopes with newest-first ordering, capped at a configurable limit.

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! declare -F orbit_info >/dev/null 2>&1; then
  source "$ORBIT_LIB_DIR/util.sh"
fi

# Map scope_kind + scope_name to filename (without .jsonl)
_decision_scope_to_file() {
  local scope_kind="$1"
  local scope_name="$2"

  case "$scope_kind" in
    project)    echo "project" ;;
    mission)    echo "mission.${scope_name}" ;;
    component)  echo "component.${scope_name}" ;;
    module)     echo "module.${scope_name}" ;;
    *)          echo "unknown"; orbit_warn "Unknown decision scope: $scope_kind" ;;
  esac
}

# --------------------------------------------------------------------------
# _decision_find_by_prefix id_prefix state_dir
# --------------------------------------------------------------------------
# Searches all decision JSONL files for an entry matching the ID prefix.
# Outputs: file_path\tjson_line
_decision_find_by_prefix() {
  local id_prefix="$1"
  local state_dir="$2"

  local decisions_dir="${state_dir}/learning/decisions"
  [ -d "$decisions_dir" ] || return 1

  local f
  for f in "$decisions_dir"/*.jsonl; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local line_id
      line_id=$(echo "$line" | jq -r '.id')
      if [[ "$line_id" == "$id_prefix"* ]]; then
        printf '%s\t%s\n' "$f" "$line"
        return 0
      fi
    done < "$f"
  done

  return 1
}

# --------------------------------------------------------------------------
# _decision_update_status id_prefix new_status state_dir
# --------------------------------------------------------------------------
# Updates the status of a decision found by ID prefix.
_decision_update_status() {
  local id_prefix="$1"
  local new_status="$2"
  local state_dir="$3"

  local result
  result=$(_decision_find_by_prefix "$id_prefix" "$state_dir") || {
    orbit_warn "Decision '$id_prefix' not found"
    return 1
  }

  local file_path
  file_path=$(echo "$result" | cut -f1)

  local tmp
  tmp=$(mktemp "$(dirname "$file_path")/.orbit-tmp.XXXXXX")

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local line_id
    line_id=$(echo "$line" | jq -r '.id')
    if [[ "$line_id" == "$id_prefix"* ]]; then
      line=$(echo "$line" | jq -c --arg s "$new_status" '.status = $s')
    fi
    echo "$line" >> "$tmp"
  done < "$file_path"

  mv "$tmp" "$file_path"
}

# --------------------------------------------------------------------------
# decision_append scope_kind scope_name title content supersedes target run_id orbit_n state_dir
# --------------------------------------------------------------------------
# Appends a decision entry. If supersedes is set, marks old as "superseded".
# Schema: {id, title, content, target, scope_kind, scope_name, status, supersedes, created_at, run_id, orbit}
decision_append() {
  local scope_kind="$1"
  local scope_name="$2"
  local title="$3"
  local content="$4"
  local supersedes="$5"
  local target="$6"
  local run_id="$7"
  local orbit_n="$8"
  local state_dir="$9"

  # If supersedes is set, mark the old decision
  if [ -n "$supersedes" ]; then
    _decision_update_status "$supersedes" "superseded" "$state_dir" || true
  fi

  local id
  id=$(_orbit_gen_id "dec-" "$title")
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local file_base
  file_base=$(_decision_scope_to_file "$scope_kind" "$scope_name")
  local target_file="${state_dir}/learning/decisions/${file_base}.jsonl"

  local entry
  entry=$(jq -nc \
    --arg id "$id" \
    --arg title "$title" \
    --arg content "$content" \
    --arg target "$target" \
    --arg scope_kind "$scope_kind" \
    --arg scope_name "$scope_name" \
    --arg status "proposed" \
    --arg supersedes "$supersedes" \
    --arg created_at "$ts" \
    --arg run_id "$run_id" \
    --argjson orbit "${orbit_n:-0}" \
    '{id: $id, title: $title, content: $content, target: $target, scope_kind: $scope_kind, scope_name: $scope_name, status: $status, supersedes: $supersedes, created_at: $created_at, run_id: $run_id, orbit: $orbit}')

  _atomic_append_jsonl "$target_file" "$entry"
  echo "$id"
}

# --------------------------------------------------------------------------
# decision_accept id_prefix state_dir
# --------------------------------------------------------------------------
decision_accept() {
  _decision_update_status "$1" "accepted" "$2"
}

# --------------------------------------------------------------------------
# decision_reject id_prefix state_dir
# --------------------------------------------------------------------------
decision_reject() {
  _decision_update_status "$1" "rejected" "$2"
}

# --------------------------------------------------------------------------
# decision_supersede id_prefix new_title new_content state_dir
# --------------------------------------------------------------------------
# Marks old decision as superseded, appends new one referencing it.
decision_supersede() {
  local id_prefix="$1"
  local new_title="$2"
  local new_content="$3"
  local state_dir="$4"

  # Find old decision to get its scope info
  local result
  result=$(_decision_find_by_prefix "$id_prefix" "$state_dir") || {
    orbit_warn "Decision '$id_prefix' not found for supersede"
    return 1
  }

  local old_json
  old_json=$(echo "$result" | cut -f2-)
  local old_id scope_kind scope_name target
  old_id=$(echo "$old_json" | jq -r '.id')
  scope_kind=$(echo "$old_json" | jq -r '.scope_kind')
  scope_name=$(echo "$old_json" | jq -r '.scope_name')
  target=$(echo "$old_json" | jq -r '.target')

  decision_append "$scope_kind" "$scope_name" "$new_title" "$new_content" "$old_id" "$target" "" "0" "$state_dir"
}

# --------------------------------------------------------------------------
# decision_read_active scope_kind scope_name state_dir
# --------------------------------------------------------------------------
# Returns active decisions (proposed or accepted) for a scope.
decision_read_active() {
  local scope_kind="$1"
  local scope_name="$2"
  local state_dir="$3"

  local file_base
  file_base=$(_decision_scope_to_file "$scope_kind" "$scope_name")
  local target="${state_dir}/learning/decisions/${file_base}.jsonl"

  if [ ! -f "$target" ]; then
    return 0
  fi

  jq -c 'select(.status == "proposed" or .status == "accepted")' "$target"
}

# --------------------------------------------------------------------------
# decision_assemble context_component context_mission limit state_dir
# --------------------------------------------------------------------------
# Hierarchical scope assembly: collects active decisions (proposed/accepted)
# from project → mission → component scopes (broadest to narrowest), sorts
# by newest first, and caps at limit. This gives agents a combined view of
# all applicable decisions for their current execution context.
decision_assemble() {
  local context_component="$1"
  local context_mission="$2"
  local limit="${3:-20}"
  local state_dir="$4"

  local decisions_dir="${state_dir}/learning/decisions"
  [ -d "$decisions_dir" ] || return 0

  local all_entries=""

  # Project scope
  if [ -f "${decisions_dir}/project.jsonl" ]; then
    all_entries+=$(jq -c 'select(.status == "proposed" or .status == "accepted")' "${decisions_dir}/project.jsonl" 2>/dev/null || true)
    all_entries+=$'\n'
  fi

  # Mission scope
  if [ -n "$context_mission" ] && [ -f "${decisions_dir}/mission.${context_mission}.jsonl" ]; then
    all_entries+=$(jq -c 'select(.status == "proposed" or .status == "accepted")' "${decisions_dir}/mission.${context_mission}.jsonl" 2>/dev/null || true)
    all_entries+=$'\n'
  fi

  # Component scope
  if [ -n "$context_component" ] && [ -f "${decisions_dir}/component.${context_component}.jsonl" ]; then
    all_entries+=$(jq -c 'select(.status == "proposed" or .status == "accepted")' "${decisions_dir}/component.${context_component}.jsonl" 2>/dev/null || true)
    all_entries+=$'\n'
  fi

  [ -z "$all_entries" ] && return 0

  echo "$all_entries" | grep -v '^$' | jq -s '
    sort_by(.created_at) | reverse |
    .[:'"$limit"'][] |
    "- [" + .status + "] " + .title + ": " + .content
  ' -r 2>/dev/null || true
}

# --------------------------------------------------------------------------
# decision_list scope_target state_dir
# --------------------------------------------------------------------------
# Parse a target string (e.g. "project", "component:doc-drafter") and
# return all entries for that scope.
decision_list() {
  local scope_target="$1"
  local state_dir="$2"

  local scope_kind scope_name
  case "$scope_target" in
    project)
      scope_kind="project"
      scope_name=""
      ;;
    mission:*)
      scope_kind="mission"
      scope_name="${scope_target#mission:}"
      ;;
    component:*)
      scope_kind="component"
      scope_name="${scope_target#component:}"
      ;;
    *)
      scope_kind="$scope_target"
      scope_name=""
      ;;
  esac

  local file_base
  file_base=$(_decision_scope_to_file "$scope_kind" "$scope_name")
  local target="${state_dir}/learning/decisions/${file_base}.jsonl"

  if [ -f "$target" ]; then
    cat "$target"
  fi
}
