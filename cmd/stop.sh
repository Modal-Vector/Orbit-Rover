#!/usr/bin/env bash
set -euo pipefail

# stop.sh — orbit stop subcommand
# Requests graceful stop of a running mission.

cmd_stop() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: orbit stop <mission-name|run-id>" >&2
    return 1
  fi

  local target="$1"
  local state_dir="${ORBIT_STATE_DIR:-.orbit}"

  local run_id

  if [[ "$target" == run-* ]]; then
    # Direct run-id
    run_id="$target"
    if [[ ! -d "${state_dir}/runs/${run_id}" ]]; then
      echo "Run '${run_id}' not found." >&2
      return 1
    fi
  else
    # Resolve mission name to running run_id
    run_id=$(stop_find_running_run "$target" "$state_dir") || {
      echo "No running mission '${target}' found." >&2
      return 1
    }
  fi

  stop_request "$run_id" "$state_dir"
  echo "Stop requested for run '${run_id}'."
}
