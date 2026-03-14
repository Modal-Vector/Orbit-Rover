#!/usr/bin/env bash
set -euo pipefail

# feedback.sh — Per-component feedback JSONL with vote support

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! declare -F orbit_info >/dev/null 2>&1; then
  source "$ORBIT_LIB_DIR/util.sh"
fi

# --------------------------------------------------------------------------
# feedback_append component_name content project_dir [run_id]
# --------------------------------------------------------------------------
# Appends a feedback entry to the component's JSONL file.
# Schema: {id, component, content, votes, created_at, run_id}
feedback_append() {
  local component="$1"
  local content="$2"
  local project_dir="$3"
  local run_id="${4:-}"

  local target="${project_dir}/components/${component}/${component}.feedback.jsonl"
  mkdir -p "$(dirname "$target")"
  local id
  id=$(_orbit_gen_id "fb-" "$content")
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local entry
  entry=$(jq -nc \
    --arg id "$id" \
    --arg component "$component" \
    --arg content "$content" \
    --arg created_at "$ts" \
    --arg run_id "$run_id" \
    '{id: $id, component: $component, content: $content, votes: 1, created_at: $created_at, run_id: $run_id}')

  _atomic_append_jsonl "$target" "$entry"
  echo "$id"
}

# --------------------------------------------------------------------------
# feedback_vote entry_id weight component_name project_dir
# --------------------------------------------------------------------------
# Finds entry by ID prefix and adds weight to its votes field.
feedback_vote() {
  local entry_id="$1"
  local weight="$2"
  local component="$3"
  local project_dir="$4"

  local target="${project_dir}/components/${component}/${component}.feedback.jsonl"
  if [ ! -f "$target" ]; then
    orbit_warn "No feedback file for component '$component'"
    return 1
  fi

  local tmp
  tmp=$(mktemp "$(dirname "$target")/.orbit-tmp.XXXXXX")
  local found=false

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local line_id
    line_id=$(echo "$line" | jq -r '.id')
    if [[ "$line_id" == "$entry_id"* ]]; then
      line=$(echo "$line" | jq -c --argjson w "$weight" '.votes = (.votes + $w)')
      found=true
    fi
    echo "$line" >> "$tmp"
  done < "$target"

  if [ "$found" = true ]; then
    mv "$tmp" "$target"
  else
    rm -f "$tmp"
    orbit_warn "Feedback entry '$entry_id' not found in component '$component'"
    return 1
  fi
}

# --------------------------------------------------------------------------
# feedback_read component_name project_dir
# --------------------------------------------------------------------------
# Outputs all feedback for a component, sorted by votes descending.
feedback_read() {
  local component="$1"
  local project_dir="$2"

  local target="${project_dir}/components/${component}/${component}.feedback.jsonl"
  if [ ! -f "$target" ]; then
    return 0
  fi

  jq -s 'sort_by(-.votes)[]' "$target"
}

# --------------------------------------------------------------------------
# feedback_assemble component_name limit project_dir
# --------------------------------------------------------------------------
# Assembles feedback as markdown for template injection.
# Format: ## Feedback (top N by votes)\n[V votes] content
feedback_assemble() {
  local component="$1"
  local limit="${2:-10}"
  local project_dir="$3"

  local target="${project_dir}/components/${component}/${component}.feedback.jsonl"
  if [ ! -f "$target" ]; then
    return 0
  fi

  local sorted
  sorted=$(jq -s 'sort_by(-.votes)' "$target")
  local count
  count=$(echo "$sorted" | jq 'length')

  if [ "$count" -eq 0 ]; then
    return 0
  fi

  local actual_limit=$((count < limit ? count : limit))

  echo "## Feedback (top $actual_limit by votes)"
  echo ""

  local i
  for ((i = 0; i < actual_limit; i++)); do
    local votes content
    votes=$(echo "$sorted" | jq -r ".[$i].votes")
    content=$(echo "$sorted" | jq -r ".[$i].content")
    echo "[$votes votes] $content"
  done
}

# --------------------------------------------------------------------------
# feedback_clear component_name project_dir
# --------------------------------------------------------------------------
# Removes the feedback JSONL file for a component.
feedback_clear() {
  local component="$1"
  local project_dir="$2"

  local target="${project_dir}/components/${component}/${component}.feedback.jsonl"
  rm -f "$target"
}
