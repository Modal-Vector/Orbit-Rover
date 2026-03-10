#!/usr/bin/env bash
# _auth-check.sh — Standalone auth gate for restricted tools
# Self-contained: does NOT source any lib files.
# Reads ORBIT_TOOL_AUTH_KEY and ORBIT_COMPONENT from environment.
# Validates against .orbit/tool-auth/${ORBIT_COMPONENT}.json
# Exits 0 on success, 1 on failure.

set -euo pipefail

if [ -z "${ORBIT_TOOL_AUTH_KEY:-}" ]; then
  echo "DENIED: No auth key" >&2
  exit 1
fi

if [ -z "${ORBIT_COMPONENT:-}" ]; then
  echo "DENIED: No component specified" >&2
  exit 1
fi

AUTH_FILE=".orbit/tool-auth/${ORBIT_COMPONENT}.json"

if [ ! -f "$AUTH_FILE" ]; then
  echo "DENIED: No auth file for component '${ORBIT_COMPONENT}'" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  STORED_KEY=$(jq -r '.auth_key // ""' "$AUTH_FILE")
else
  # Fallback: grep for the key value
  STORED_KEY=$(grep -o '"auth_key":"[^"]*"' "$AUTH_FILE" | cut -d'"' -f4)
fi

if [ "$STORED_KEY" != "$ORBIT_TOOL_AUTH_KEY" ]; then
  echo "DENIED: Key not authorised for this component" >&2
  exit 1
fi

exit 0
