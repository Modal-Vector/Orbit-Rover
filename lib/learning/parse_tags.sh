#!/usr/bin/env bash
set -euo pipefail

# parse_tags.sh — Route extracted XML learning tags to the appropriate stores

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

if ! declare -F orbit_info >/dev/null 2>&1; then
  source "$ORBIT_LIB_DIR/util.sh"
fi
source "$ORBIT_LIB_DIR/extract.sh"
source "$ORBIT_LIB_DIR/learning/feedback.sh"
source "$ORBIT_LIB_DIR/learning/insights.sh"
source "$ORBIT_LIB_DIR/learning/decisions.sh"

# Source registry if available (for target validation)
if [ -f "$ORBIT_LIB_DIR/registry.sh" ]; then
  source "$ORBIT_LIB_DIR/registry.sh" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# parse_learning_tags output component_name mission_name run_id orbit_n state_dir [project_dir]
# --------------------------------------------------------------------------
# Extracts all learning tags from agent output and routes them to stores.
parse_learning_tags() {
  local output="$1"
  local component="${2:-}"
  local mission_name="${3:-}"
  local run_id="${4:-}"
  local orbit_n="${5:-0}"
  local state_dir="$6"
  local project_dir="${7:-}"

  # --- Insights ---
  local insights
  insights=$(extract_insight_targets "$output") || true
  if [ -n "$insights" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local target content scope_kind scope_name
      target=$(echo "$line" | jq -r '.target')
      content=$(echo "$line" | jq -r '.content')

      # Parse target into scope_kind and scope_name
      case "$target" in
        project)
          scope_kind="project"
          scope_name=""
          ;;
        mission)
          scope_kind="mission"
          scope_name="$mission_name"
          ;;
        mission:*)
          scope_kind="mission"
          scope_name="${target#mission:}"
          ;;
        component:*)
          scope_kind="component"
          scope_name="${target#component:}"
          # Validate against registry
          if [ -n "$project_dir" ]; then
            registry_validate_target "$target" "$project_dir" 2>&1 || true
          fi
          ;;
        run)
          scope_kind="run"
          scope_name=""
          ;;
        *)
          orbit_warn "Unknown insight target: $target"
          continue
          ;;
      esac

      insight_append "$scope_kind" "$scope_name" "$content" "$run_id" "$orbit_n" "$state_dir" >/dev/null
    done <<< "$insights"
  fi

  # --- Decisions ---
  local decisions
  decisions=$(extract_decisions "$output") || true
  if [ -n "$decisions" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local target title content supersedes scope_kind scope_name
      target=$(echo "$line" | jq -r '.target')
      title=$(echo "$line" | jq -r '.title')
      content=$(echo "$line" | jq -r '.content')
      supersedes=$(echo "$line" | jq -r '.supersedes // empty')

      case "$target" in
        project)
          scope_kind="project"
          scope_name=""
          ;;
        mission)
          scope_kind="mission"
          scope_name="$mission_name"
          ;;
        mission:*)
          scope_kind="mission"
          scope_name="${target#mission:}"
          ;;
        component:*)
          scope_kind="component"
          scope_name="${target#component:}"
          if [ -n "$project_dir" ]; then
            registry_validate_target "$target" "$project_dir" 2>&1 || true
          fi
          ;;
        *)
          orbit_warn "Unknown decision target: $target"
          continue
          ;;
      esac

      decision_append "$scope_kind" "$scope_name" "$title" "$content" "$supersedes" "$target" "$run_id" "$orbit_n" "$state_dir" >/dev/null
    done <<< "$decisions"
  fi

  # --- Feedback ---
  local feedback
  feedback=$(extract_feedback "$output") || true
  if [ -n "$feedback" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local content
      content=$(echo "$line" | jq -r '.content')
      feedback_append "${component:-unknown}" "$content" "$state_dir" "$run_id" >/dev/null
    done <<< "$feedback"
  fi

  # --- Votes ---
  local votes
  votes=$(extract_votes "$output") || true
  if [ -n "$votes" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local vote_id weight
      vote_id=$(echo "$line" | jq -r '.id')
      weight=$(echo "$line" | jq -r '.weight')
      feedback_vote "$vote_id" "$weight" "${component:-unknown}" "$state_dir" 2>/dev/null || true
    done <<< "$votes"
  fi
}
