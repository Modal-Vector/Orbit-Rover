#!/usr/bin/env bash
set -euo pipefail

# insights.sh — Scoped insight JSONL with hierarchical assembly

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! declare -F orbit_info >/dev/null 2>&1; then
  source "$ORBIT_LIB_DIR/util.sh"
fi

# Map scope_kind + scope_name to filename (without .jsonl)
_insight_scope_to_file() {
  local scope_kind="$1"
  local scope_name="$2"

  case "$scope_kind" in
    project)    echo "project" ;;
    mission)    echo "mission.${scope_name}" ;;
    component)  echo "component.${scope_name}" ;;
    module)     echo "module.${scope_name}" ;;
    *)          echo "unknown"; orbit_warn "Unknown insight scope: $scope_kind" ;;
  esac
}

# --------------------------------------------------------------------------
# insight_append scope_kind scope_name content run_id orbit_n state_dir
# --------------------------------------------------------------------------
# Appends an insight entry. Run-scoped insights go to state/run-insights.tmp.
# Schema: {id, scope_kind, scope_name, content, created_at, run_id, orbit}
insight_append() {
  local scope_kind="$1"
  local scope_name="$2"
  local content="$3"
  local run_id="$4"
  local orbit_n="$5"
  local state_dir="$6"

  local id
  id=$(_orbit_gen_id "ins-" "$content")
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local entry
  entry=$(jq -nc \
    --arg id "$id" \
    --arg scope_kind "$scope_kind" \
    --arg scope_name "$scope_name" \
    --arg content "$content" \
    --arg created_at "$ts" \
    --arg run_id "$run_id" \
    --argjson orbit "${orbit_n:-0}" \
    '{id: $id, scope_kind: $scope_kind, scope_name: $scope_name, content: $content, created_at: $created_at, run_id: $run_id, orbit: $orbit}')

  if [ "$scope_kind" = "run" ]; then
    local target="${state_dir}/state/run-insights.tmp"
    _atomic_append_jsonl "$target" "$entry"
  else
    local file_base
    file_base=$(_insight_scope_to_file "$scope_kind" "$scope_name")
    local target="${state_dir}/learning/insights/${file_base}.jsonl"
    _atomic_append_jsonl "$target" "$entry"
  fi

  echo "$id"
}

# --------------------------------------------------------------------------
# insight_read scope_kind scope_name state_dir
# --------------------------------------------------------------------------
# Outputs raw JSONL for the given scope.
insight_read() {
  local scope_kind="$1"
  local scope_name="$2"
  local state_dir="$3"

  local file_base
  file_base=$(_insight_scope_to_file "$scope_kind" "$scope_name")
  local target="${state_dir}/learning/insights/${file_base}.jsonl"

  if [ -f "$target" ]; then
    cat "$target"
  fi
}

# --------------------------------------------------------------------------
# insight_assemble context_component context_mission limit state_dir
# --------------------------------------------------------------------------
# Hierarchical assembly: project → mission → component.
# Dedup by content, newest first, capped at limit (default 20).
insight_assemble() {
  local context_component="$1"
  local context_mission="$2"
  local limit="${3:-20}"
  local state_dir="$4"

  local insights_dir="${state_dir}/learning/insights"
  [ -d "$insights_dir" ] || return 0

  # Collect entries from all relevant scopes
  local all_entries=""

  # Project scope
  if [ -f "${insights_dir}/project.jsonl" ]; then
    all_entries+=$(cat "${insights_dir}/project.jsonl")
    all_entries+=$'\n'
  fi

  # Mission scope
  if [ -n "$context_mission" ] && [ -f "${insights_dir}/mission.${context_mission}.jsonl" ]; then
    all_entries+=$(cat "${insights_dir}/mission.${context_mission}.jsonl")
    all_entries+=$'\n'
  fi

  # Component scope
  if [ -n "$context_component" ] && [ -f "${insights_dir}/component.${context_component}.jsonl" ]; then
    all_entries+=$(cat "${insights_dir}/component.${context_component}.jsonl")
    all_entries+=$'\n'
  fi

  [ -z "$all_entries" ] && return 0

  # Dedup by content, sort newest first, cap at limit
  echo "$all_entries" | grep -v '^$' | jq -s '
    group_by(.content) | map(max_by(.created_at)) |
    sort_by(.created_at) | reverse |
    .[:'"$limit"'][] |
    "- [" + .scope_kind + "] " + .content
  ' -r 2>/dev/null || true
}

# --------------------------------------------------------------------------
# insight_clear scope_kind scope_name state_dir
# --------------------------------------------------------------------------
# Removes the insight JSONL file for the given scope.
insight_clear() {
  local scope_kind="$1"
  local scope_name="$2"
  local state_dir="$3"

  local file_base
  file_base=$(_insight_scope_to_file "$scope_kind" "$scope_name")
  local target="${state_dir}/learning/insights/${file_base}.jsonl"
  rm -f "$target"
}
