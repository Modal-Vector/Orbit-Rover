#!/usr/bin/env bash
set -euo pipefail

# learning.sh — orbit decisions/insights/feedback subcommands
# Thin wrappers around lib/learning/ functions.

cmd_decisions() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit decisions <list|accept|reject|supersede> [options]" >&2
    return 1
  fi

  local subcmd="$1"; shift

  case "$subcmd" in
    list)
      local target="project"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --target) target="$2"; shift 2 ;;
          *) echo "Unknown option: $1" >&2; return 1 ;;
        esac
      done
      local output
      output=$(decision_list "$target" "$state_dir" 2>/dev/null)
      if [[ -z "$output" ]]; then
        echo "No decisions found for target '${target}'."
      else
        echo "$output"
      fi
      ;;
    accept)
      if [[ $# -eq 0 ]]; then
        echo "Usage: orbit decisions accept <id>" >&2
        return 1
      fi
      decision_accept "$1" "$state_dir"
      echo "Decision '$1' accepted."
      ;;
    reject)
      if [[ $# -eq 0 ]]; then
        echo "Usage: orbit decisions reject <id>" >&2
        return 1
      fi
      decision_reject "$1" "$state_dir"
      echo "Decision '$1' rejected."
      ;;
    supersede)
      if [[ $# -lt 2 ]]; then
        echo "Usage: orbit decisions supersede <id> --title \"T\" \"rationale\"" >&2
        return 1
      fi
      local id="$1"; shift
      local title="" rationale=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --title) title="$2"; shift 2 ;;
          *) rationale="$1"; shift ;;
        esac
      done
      decision_supersede "$id" "$title" "$rationale" "$state_dir"
      echo "Decision '$id' superseded."
      ;;
    *)
      echo "Unknown subcommand: $subcmd" >&2
      return 1
      ;;
  esac
}

cmd_insights() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit insights <scope> | orbit insights clear <scope>" >&2
    return 1
  fi

  if [[ "$1" == "clear" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      echo "Usage: orbit insights clear <scope>" >&2
      return 1
    fi
    local scope="$1"
    local scope_kind scope_name
    _parse_scope "$scope" scope_kind scope_name
    insight_clear "$scope_kind" "$scope_name" "$state_dir"
    echo "Insights cleared for '${scope}'."
    return 0
  fi

  local scope="$1"
  local scope_kind scope_name
  _parse_scope "$scope" scope_kind scope_name

  local output
  output=$(insight_read "$scope_kind" "$scope_name" "$state_dir" 2>/dev/null)
  if [[ -z "$output" ]]; then
    echo "No insights found for '${scope}'."
  else
    # Format as readable output
    echo "$output" | jq -r '"- " + .content' 2>/dev/null || echo "$output"
  fi
}

cmd_feedback() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit feedback <component> | orbit feedback clear <component>" >&2
    return 1
  fi

  if [[ "$1" == "clear" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      echo "Usage: orbit feedback clear <component>" >&2
      return 1
    fi
    feedback_clear "$1" "$state_dir"
    echo "Feedback cleared for '${1}'."
    return 0
  fi

  local component="$1"
  local output
  output=$(feedback_assemble "$component" "10" "$state_dir" 2>/dev/null)
  if [[ -z "$output" ]]; then
    echo "No feedback found for '${component}'."
  else
    echo "$output"
  fi
}

# Parse a scope string like "project", "mission:implement", "component:worker"
_parse_scope() {
  local scope="$1"
  local -n _kind=$2
  local -n _name=$3

  case "$scope" in
    project)
      _kind="project"
      _name=""
      ;;
    mission:*)
      _kind="mission"
      _name="${scope#mission:}"
      ;;
    component:*)
      _kind="component"
      _name="${scope#component:}"
      ;;
    module:*)
      _kind="module"
      _name="${scope#module:}"
      ;;
    *)
      _kind="$scope"
      _name=""
      ;;
  esac
}
