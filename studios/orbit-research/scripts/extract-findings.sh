#!/usr/bin/env bash
set -euo pipefail

# extract-findings.sh — Build a findings index from completed research topics
# Scans findings/ directory and creates a consolidated index.

FINDINGS_DIR="findings"
INDEX_FILE="${FINDINGS_DIR}/index.md"

mkdir -p "$FINDINGS_DIR"

if [ ! -d "$FINDINGS_DIR" ] || [ -z "$(ls -A "$FINDINGS_DIR" 2>/dev/null | grep -v index.md)" ]; then
  echo "# Research Findings Index" > "$INDEX_FILE"
  echo "" >> "$INDEX_FILE"
  echo "No findings yet." >> "$INDEX_FILE"
  exit 0
fi

# Build the index
{
  echo "# Research Findings Index"
  echo ""
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  for finding in "$FINDINGS_DIR"/*.md; do
    [ "$finding" = "$INDEX_FILE" ] && continue
    [ ! -f "$finding" ] && continue

    BASENAME=$(basename "$finding" .md)
    echo "## ${BASENAME}"
    echo ""
    # Extract first 5 lines as summary
    head -20 "$finding" | sed 's/^/> /'
    echo ""
    echo "---"
    echo ""
  done
} > "${INDEX_FILE}.tmp"

mv "${INDEX_FILE}.tmp" "$INDEX_FILE"

echo "[ORBIT INFO] Findings index updated: $(grep -c '##' "$INDEX_FILE") entries"
