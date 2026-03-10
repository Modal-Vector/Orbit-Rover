#!/usr/bin/env bash
set -euo pipefail

# retry.sh — Retry logic for orbit loop adapter failures
# Supports constant and exponential backoff.

# Determine if a retry should be attempted
# Returns 0 (should retry) or 1 (should not)
retry_should_retry() {
  local attempt="$1"
  local max_attempts="$2"
  local exit_code="$3"
  local on_timeout="${4:-false}"

  # Already at or past max attempts
  if [[ $attempt -ge $max_attempts ]]; then
    return 1
  fi

  # Exit code 0 = success, no retry needed
  if [[ $exit_code -eq 0 ]]; then
    return 1
  fi

  # Exit code 124 = timeout
  if [[ $exit_code -eq 124 ]]; then
    if [[ "$on_timeout" == "true" ]]; then
      return 0
    else
      return 1
    fi
  fi

  # Any other non-zero exit code: retry
  return 0
}

# Calculate delay for a retry attempt
# Outputs delay in seconds
retry_delay() {
  local attempt="$1"
  local backoff_type="${2:-exponential}"
  local initial_delay="${3:-5}"
  local max_delay="${4:-60}"

  local delay

  case "$backoff_type" in
    constant)
      delay="$initial_delay"
      ;;
    exponential|*)
      # delay = initial_delay * 2^(attempt-1)
      local power=$((attempt - 1))
      local multiplier=1
      local i
      for ((i = 0; i < power; i++)); do
        multiplier=$((multiplier * 2))
      done
      delay=$((initial_delay * multiplier))
      ;;
  esac

  # Cap at max_delay
  if [[ $delay -gt $max_delay ]]; then
    delay=$max_delay
  fi

  echo "$delay"
}

# Run a cleanup command if provided
retry_cleanup() {
  local cleanup_cmd="${1:-}"

  if [[ -n "$cleanup_cmd" ]]; then
    eval "$cleanup_cmd" 2>/dev/null || true
  fi
}

# Parse duration string (e.g. "5s", "500ms", "1m") to seconds (integer)
_retry_parse_delay() {
  local input="$1"

  if [[ "$input" =~ ^([0-9]+)ms$ ]]; then
    # Milliseconds — round up to at least 1 second
    local ms="${BASH_REMATCH[1]}"
    local secs=$(( (ms + 999) / 1000 ))
    [[ $secs -lt 1 ]] && secs=1
    echo "$secs"
  elif [[ "$input" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$input" =~ ^([0-9]+)m$ ]]; then
    echo $(( ${BASH_REMATCH[1]} * 60 ))
  elif [[ "$input" =~ ^([0-9]+)$ ]]; then
    echo "$input"
  else
    echo "5"  # default
  fi
}
