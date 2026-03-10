#!/usr/bin/env bash
set -euo pipefail

# hash.sh — SHA256 hashing for deadlock detection

# Cross-platform SHA256: tries sha256sum, falls back to shasum -a 256
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256
  else
    echo "[ORBIT ERROR] No SHA256 tool found (need sha256sum or shasum)" >&2
    return 1
  fi
}

# Hash the content of delivers files. Returns combined hash.
# Empty string if no args or no files exist.
# Usage: hash_delivers file1 file2 ...
hash_delivers() {
  if [ $# -eq 0 ]; then
    echo ""
    return 0
  fi

  local has_content=false
  local combined=""

  for f in "$@"; do
    if [ -f "$f" ]; then
      has_content=true
      combined+="$(cat "$f")"
    fi
  done

  if [ "$has_content" = false ]; then
    echo ""
    return 0
  fi

  echo -n "$combined" | _sha256 | awk '{print $1}'
}
