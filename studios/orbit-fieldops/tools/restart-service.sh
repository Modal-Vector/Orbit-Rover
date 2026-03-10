#!/usr/bin/env bash
set -euo pipefail

# restart-service.sh — Restart a system service
# Usage: restart-service.sh <service-name>
# Classification: restricted (requires auth)

# Auth gate
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! bash "${SCRIPT_DIR}/_auth-check.sh"; then
  echo "DENIED: Auth check failed for restart-service" >&2
  exit 1
fi

SERVICE="${1:-}"

if [ -z "$SERVICE" ]; then
  echo "Usage: restart-service.sh <service-name>" >&2
  exit 1
fi

echo "[RESTART] Restarting service: $SERVICE"

# Attempt restart via systemctl, then fallback to service command
if command -v systemctl >/dev/null 2>&1; then
  if systemctl restart "$SERVICE" 2>/dev/null; then
    echo "[RESTART] $SERVICE restarted via systemctl"
  else
    echo "[RESTART] systemctl restart failed for $SERVICE" >&2
    exit 1
  fi
elif command -v service >/dev/null 2>&1; then
  if service "$SERVICE" restart 2>/dev/null; then
    echo "[RESTART] $SERVICE restarted via service command"
  else
    echo "[RESTART] service restart failed for $SERVICE" >&2
    exit 1
  fi
else
  echo "[RESTART] No service management tool available" >&2
  exit 1
fi
