#!/usr/bin/env bash
set -euo pipefail

# util.sh — Shared helpers for Orbit Rover
# Extracted from orbit_loop.sh to avoid circular dependencies.

ORBIT_LIB_DIR="${ORBIT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source hash.sh for _sha256 (needed by _orbit_gen_id)
source "$ORBIT_LIB_DIR/hash.sh"

# Logging helpers
orbit_log() {
  local level="$1"; shift
  echo "[ORBIT ${level}] $*" >&2
}

orbit_info()  { orbit_log "INFO" "$@"; }
orbit_warn()  { orbit_log "WARN" "$@"; }
orbit_error() { orbit_log "ERROR" "$@"; }

# Generate an ID (type-prefixed, 12-char hash)
_orbit_gen_id() {
  local prefix="$1"
  local content="$2"
  local ts
  ts=$(date +%s)
  local hash
  hash=$(echo -n "${ts}${content}${RANDOM}" | _sha256 | awk '{print $1}' | head -c 12)
  echo "${prefix}${hash}"
}

# Atomic write: write to temp file then mv
_atomic_write() {
  local target="$1"
  local content="$2"
  local dir
  dir=$(dirname "$target")
  mkdir -p "$dir"
  local tmp
  tmp=$(mktemp "$dir/.orbit-tmp.XXXXXX")
  echo "$content" > "$tmp"
  mv "$tmp" "$target"
}

# Atomic append to JSONL
_atomic_append_jsonl() {
  local target="$1"
  local json_line="$2"
  local dir
  dir=$(dirname "$target")
  mkdir -p "$dir"
  local tmp
  tmp=$(mktemp "$dir/.orbit-tmp.XXXXXX")
  if [ -f "$target" ]; then
    cat "$target" > "$tmp"
  fi
  echo "$json_line" >> "$tmp"
  mv "$tmp" "$target"
}
