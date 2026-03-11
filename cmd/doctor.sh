#!/usr/bin/env bash
set -euo pipefail

# doctor.sh — orbit doctor subcommand
# Checks system dependencies, reports status.

cmd_doctor() {
  local has_critical_failure=false

  echo "Orbit Rover — System Check"
  echo "=========================="

  # Check bash version (critical)
  local bash_ver="${BASH_VERSINFO[0]}"
  if [[ "$bash_ver" -ge 4 ]]; then
    echo "[OK]   bash ${BASH_VERSION}"
  else
    echo "[FAIL] bash ${BASH_VERSION} — version 4+ required"
    has_critical_failure=true
  fi

  # Check jq (critical)
  if command -v jq >/dev/null 2>&1; then
    local jq_ver
    jq_ver=$(jq --version 2>/dev/null || echo "unknown")
    echo "[OK]   jq ${jq_ver}"
  else
    echo "[FAIL] jq — not found (required)"
    has_critical_failure=true
  fi

  # Optional dependencies
  local optionals=(python3 yq cron claude opencode ollama inotifywait gum)
  for tool in "${optionals[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      local ver=""
      case "$tool" in
        python3)    ver=$($tool --version 2>&1 | head -1) ;;
        yq)         ver=$($tool --version 2>&1 | head -1) ;;
        claude)     ver="installed" ;;
        opencode)   ver="installed" ;;
        ollama)     ver="installed" ;;
        cron)       ver="available" ;;
        inotifywait) ver=$($tool --help 2>&1 | head -1 || echo "installed") ;;
        gum)        ver=$($tool --version 2>&1 | head -1 || echo "installed") ;;
      esac
      echo "[OK]   ${tool} ${ver}"
    else
      echo "[WARN] ${tool} — not found (optional)"
    fi
  done

  if [[ "$has_critical_failure" == "true" ]]; then
    echo ""
    echo "CRITICAL: Missing required dependencies."
    return 1
  fi

  echo ""
  echo "All critical dependencies satisfied."
  return 0
}
