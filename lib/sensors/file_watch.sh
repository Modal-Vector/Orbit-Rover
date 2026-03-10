#!/usr/bin/env bash
set -euo pipefail

# file_watch.sh — File change detection sensor for Orbit Rover

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ORBIT_LIB_DIR/sensors/cascade.sh"
source "$ORBIT_LIB_DIR/sensors/schedule.sh"  # for _parse_duration

# Cross-platform MD5 helper (for polling fallback)
_md5_cross_platform() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256
  else
    # Last resort: use sha256 from hash.sh if loaded
    if declare -f _sha256 >/dev/null 2>&1; then
      _sha256
    else
      cat  # No hashing available — content comparison as-is
    fi
  fi
}

# Hash all files matching glob patterns for polling
# Usage: _hash_watched_paths "pattern1,pattern2" base_dir
_hash_watched_paths() {
  local paths_csv="$1"
  local base_dir="$2"
  local combined=""

  # Split on commas and expand each glob pattern
  local saved_ifs="${IFS:-}"
  IFS=','
  local patterns_array
  read -ra patterns_array <<< "$paths_csv"
  IFS="$saved_ifs"

  local prev_nullglob
  prev_nullglob=$(shopt -p nullglob 2>/dev/null) || prev_nullglob="shopt -u nullglob"
  shopt -s nullglob

  local pattern
  for pattern in "${patterns_array[@]}"; do
    # Trim whitespace
    pattern="${pattern#"${pattern%%[![:space:]]*}"}"
    pattern="${pattern%"${pattern##*[![:space:]]}"}"
    [[ -z "$pattern" ]] && continue

    # Expand glob relative to base_dir
    local full_pattern="${base_dir}/${pattern}"
    local file
    for file in $full_pattern; do
      [[ -f "$file" ]] || continue
      combined+=$(cat "$file")
    done
  done

  eval "$prev_nullglob" 2>/dev/null || true

  if [[ -z "$combined" ]]; then
    echo ""
    return 0
  fi

  echo -n "$combined" | _md5_cross_platform | awk '{print $1}'
}

# Start file watch sensor
# Usage: sensor_file_watch_start component_name paths events debounce cascade state_dir project_dir
sensor_file_watch_start() {
  local component="$1"
  local paths="$2"           # comma-separated glob patterns
  local events="${3:-}"       # comma-separated event types (unused in polling mode)
  local debounce="${4:-5s}"   # debounce duration
  local cascade="${5:-allow}" # allow | block
  local state_dir="$6"
  local project_dir="$7"

  local debounce_secs
  debounce_secs=$(_parse_duration "$debounce")
  [[ "$debounce_secs" -le 0 ]] && debounce_secs=5

  mkdir -p "${state_dir}/sensors" "${state_dir}/triggers"

  local pid_file="${state_dir}/sensors/${component}-filewatch.pid"
  local hash_file="${state_dir}/sensors/${component}-poll-hash"

  # Check for inotifywait
  if command -v inotifywait >/dev/null 2>&1; then
    # Build directory list from glob patterns
    local dirs=()
    local saved_ifs="${IFS:-}"
    IFS=','
    for pattern in $paths; do
      IFS="$saved_ifs"
      pattern="${pattern#"${pattern%%[![:space:]]*}"}"
      local dir="${project_dir}/$(dirname "$pattern")"
      [[ -d "$dir" ]] && dirs+=("$dir")
    done
    IFS="$saved_ifs"

    if [[ ${#dirs[@]} -eq 0 ]]; then
      dirs=("$project_dir")
    fi

    # Map events to inotifywait format
    local inotify_events="modify,create,delete"
    if [[ -n "$events" ]]; then
      inotify_events="$events"
    fi

    # Start inotifywait in background with proper quiet-period debounce
    local last_event_file="${state_dir}/sensors/${component}-last-event"
    (
      # Reader: inotifywait writes timestamps on change
      inotifywait -m -r -e "$inotify_events" --format '%w%f' "${dirs[@]}" 2>/dev/null | while IFS= read -r changed_file; do
        date +%s > "$last_event_file"
      done
    ) &
    local reader_pid=$!

    (
      # Debounce loop: check if quiet period has elapsed since last event
      while true; do
        sleep 1
        [[ -f "$last_event_file" ]] || continue
        local last_epoch
        last_epoch=$(cat "$last_event_file")
        local now
        now=$(date +%s)
        local elapsed=$((now - last_epoch))

        if [[ "$elapsed" -ge "$debounce_secs" ]]; then
          # Quiet period elapsed — consume the event
          rm -f "$last_event_file"

          # Cascade block check
          if [[ "$cascade" == "block" ]]; then
            if cascade_is_active "$component" "$state_dir"; then
              continue
            fi
          fi

          touch "${state_dir}/triggers/${component}-filewatch"
        fi
      done
    ) &
    local debounce_pid=$!

    # Write both PIDs — store parent wrapper PID for cleanup
    (
      # Wait for either to exit, then clean up the other
      wait "$reader_pid" 2>/dev/null || true
      kill "$debounce_pid" 2>/dev/null || true
    ) &

    echo "$reader_pid $debounce_pid" > "$pid_file"

    echo "$!" > "$pid_file"
  else
    # Polling fallback
    local initial_hash
    initial_hash=$(_hash_watched_paths "$paths" "$project_dir")
    echo "$initial_hash" > "$hash_file"

    (
      local last_change=0
      local pending=false

      while true; do
        sleep 1

        local current_hash
        current_hash=$(_hash_watched_paths "$paths" "$project_dir")
        local stored_hash=""
        [[ -f "$hash_file" ]] && stored_hash=$(cat "$hash_file")

        if [[ "$current_hash" != "$stored_hash" ]]; then
          # Change detected — start/reset debounce
          echo "$current_hash" > "$hash_file"
          last_change=$(date +%s)
          pending=true
        fi

        if [[ "$pending" == "true" ]]; then
          local now
          now=$(date +%s)
          local elapsed=$((now - last_change))

          if [[ "$elapsed" -ge "$debounce_secs" ]]; then
            # Debounce period passed
            pending=false

            # Cascade block check
            if [[ "$cascade" == "block" ]]; then
              if cascade_is_active "$component" "$state_dir"; then
                continue
              fi
            fi

            touch "${state_dir}/triggers/${component}-filewatch"
          fi
        fi
      done
    ) &

    echo "$!" > "$pid_file"
  fi
}

# Stop file watch sensor
# Usage: sensor_file_watch_stop component_name state_dir
sensor_file_watch_stop() {
  local component="$1"
  local state_dir="$2"
  local pid_file="${state_dir}/sensors/${component}-filewatch.pid"

  if [[ -f "$pid_file" ]]; then
    local pids
    pids=$(cat "$pid_file")
    # Kill all tracked PIDs (may be space-separated for inotifywait mode)
    local pid
    for pid in $pids; do
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    done
    rm -f "$pid_file"
    rm -f "${state_dir}/sensors/${component}-poll-hash"
    rm -f "${state_dir}/sensors/${component}-last-event"
  fi
}
