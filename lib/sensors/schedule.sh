#!/usr/bin/env bash
set -euo pipefail

# schedule.sh — Interval and cron schedule sensors for Orbit Rover

# Parse a duration spec like "24h", "30m", "45s" into seconds
# Usage: _parse_duration "24h" → outputs 86400
_parse_duration() {
  local spec="$1"

  if [[ -z "$spec" ]]; then
    echo "0"
    return 0
  fi

  local num="${spec%[hHmMsS]}"
  local unit="${spec: -1}"

  # If no unit suffix, assume seconds
  if [[ "$num" == "$spec" ]]; then
    echo "$spec"
    return 0
  fi

  case "$unit" in
    h|H) echo $((num * 3600)) ;;
    m|M) echo $((num * 60)) ;;
    s|S) echo "$num" ;;
    *)   echo "$spec" ;;
  esac
}

# Start an interval sensor background loop
# Usage: sensor_interval_start component_name interval_spec state_dir
sensor_interval_start() {
  local component="$1"
  local interval_spec="$2"
  local state_dir="$3"

  local interval
  interval=$(_parse_duration "$interval_spec")

  if [[ "$interval" -le 0 ]]; then
    echo "[ORBIT WARN] Invalid interval for $component: $interval_spec" >&2
    return 1
  fi

  mkdir -p "${state_dir}/sensors" "${state_dir}/triggers"

  # Calculate remaining time based on last_run
  local last_run_file="${state_dir}/state/${component}/last_run"
  local remaining="$interval"

  if [[ -f "$last_run_file" ]]; then
    local last_epoch
    last_epoch=$(cat "$last_run_file")
    local now
    now=$(date +%s)
    local elapsed=$((now - last_epoch))
    remaining=$((interval - elapsed))
    if [[ "$remaining" -lt 0 ]]; then
      remaining=0
    fi
  fi

  # Background loop: sleep remaining, then trigger, then loop at full interval
  (
    if [[ "$remaining" -gt 0 ]]; then
      sleep "$remaining" || exit 0
    fi
    touch "${state_dir}/triggers/${component}-schedule"
    while true; do
      sleep "$interval" || exit 0
      touch "${state_dir}/triggers/${component}-schedule"
    done
  ) &

  echo "$!" > "${state_dir}/sensors/${component}-interval.pid"
}

# Stop an interval sensor
# Usage: sensor_interval_stop component_name state_dir
sensor_interval_stop() {
  local component="$1"
  local state_dir="$2"
  local pid_file="${state_dir}/sensors/${component}-interval.pid"

  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
}

# --- Cron Registration ---
# Tagged-comment strategy: each cron entry ends with "# orbit-rover:{name}"
# on the same line. This tag is the sole mechanism for identifying and
# cleaning up Rover-managed entries. Registration filters out any existing
# entry for this component (by tag), then appends the new entry.
# Unregistration removes lines matching the tag without disturbing
# user-owned crontab entries.
#
# Usage: sensor_cron_register component_name cron_expr project_dir state_dir
sensor_cron_register() {
  local component="$1"
  local cron_expr="$2"
  local project_dir="$3"
  local state_dir="$4"

  local tag="# orbit-rover:${component}"

  # Get existing crontab, filter out any existing entry for this component
  local existing
  existing=$(crontab -l 2>/dev/null || true)
  local filtered
  filtered=$(echo "$existing" | grep -v "${tag}$" || true)

  # Build new entry
  local entry="${cron_expr} ${project_dir}/orbit trigger ${component}  ${tag}"

  # Combine
  local new_crontab
  if [[ -n "$filtered" ]]; then
    new_crontab="${filtered}
${entry}"
  else
    new_crontab="$entry"
  fi

  # Install via temp file
  local tmp
  tmp=$(mktemp)
  echo "$new_crontab" > "$tmp"
  crontab "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  rm -f "$tmp"
}

# Unregister a specific component's cron entry
# Usage: sensor_cron_unregister component_name
sensor_cron_unregister() {
  local component="$1"
  local tag="# orbit-rover:${component}"

  local existing
  existing=$(crontab -l 2>/dev/null || true)

  if [[ -z "$existing" ]]; then
    return 0
  fi

  local filtered
  filtered=$(echo "$existing" | grep -v "${tag}$" || true)

  if [[ -z "$filtered" ]]; then
    crontab -r 2>/dev/null || true
  else
    local tmp
    tmp=$(mktemp)
    echo "$filtered" > "$tmp"
    crontab "$tmp"
    rm -f "$tmp"
  fi
}

# Unregister all orbit-rover cron entries
# Usage: sensor_cron_unregister_all
sensor_cron_unregister_all() {
  local existing
  existing=$(crontab -l 2>/dev/null || true)

  if [[ -z "$existing" ]]; then
    return 0
  fi

  local filtered
  filtered=$(echo "$existing" | grep -v "# orbit-rover:" || true)

  if [[ -z "$filtered" ]]; then
    crontab -r 2>/dev/null || true
  else
    local tmp
    tmp=$(mktemp)
    echo "$filtered" > "$tmp"
    crontab "$tmp"
    rm -f "$tmp"
  fi
}

# List all orbit-rover cron entries
# Usage: sensor_cron_list
sensor_cron_list() {
  crontab -l 2>/dev/null | grep "# orbit-rover:" || true
}
