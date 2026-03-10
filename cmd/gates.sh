#!/usr/bin/env bash
set -euo pipefail

# gates.sh — orbit pending/approve/reject subcommands
# Delegates to lib/manual_gate.sh functions.

cmd_pending() {
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"
  manual_gate_list_pending "$state_dir"
}

cmd_approve() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit approve <gate-id> [--option <value>]" >&2
    return 1
  fi

  local gate_id="$1"; shift
  local option="approve"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --option) option="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done

  local state_dir="${ORBIT_STATE_DIR:-.orbit}"
  manual_gate_approve "$gate_id" "$option" "$state_dir"
  echo "Gate '${gate_id}' approved."
}

cmd_reject() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit reject <gate-id>" >&2
    return 1
  fi

  local gate_id="$1"
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"
  manual_gate_reject "$gate_id" "$state_dir"
  echo "Gate '${gate_id}' rejected."
}
