#!/usr/bin/env bash
set -euo pipefail

# validate-doc-structure.sh — Validate regulatory document structure
# Checks that generated documents follow the required section structure.

DOCS_DIR="regulatory-docs"
REPORT_FILE=".orbit/state/doc-validator/structure-check.json"

mkdir -p "$(dirname "$REPORT_FILE")"

if [ ! -d "$DOCS_DIR" ]; then
  echo "[ORBIT WARN] No regulatory-docs directory found" >&2
  echo '{"valid": true, "checked": 0, "errors": []}' > "$REPORT_FILE"
  exit 0
fi

ERRORS="[]"
CHECKED=0

for doc_file in "$DOCS_DIR"/*.md; do
  [ ! -f "$doc_file" ] && continue
  CHECKED=$((CHECKED + 1))

  BASENAME=$(basename "$doc_file")

  # Check for required sections (H1 title, at least one H2)
  if ! grep -q '^# ' "$doc_file" 2>/dev/null; then
    ERRORS=$(echo "$ERRORS" | jq --arg file "$BASENAME" \
      '. + [{"file": $file, "error": "missing H1 title"}]')
  fi

  if ! grep -q '^## ' "$doc_file" 2>/dev/null; then
    ERRORS=$(echo "$ERRORS" | jq --arg file "$BASENAME" \
      '. + [{"file": $file, "error": "missing H2 sections"}]')
  fi
done

VALID="true"
if [ "$(echo "$ERRORS" | jq 'length')" -gt 0 ]; then
  VALID="false"
fi

jq -n --argjson valid "$VALID" --argjson checked "$CHECKED" --argjson errors "$ERRORS" \
  '{valid: $valid, checked: $checked, errors: $errors}' > "$REPORT_FILE"

echo "[ORBIT INFO] Doc structure check: $CHECKED files, $(echo "$ERRORS" | jq 'length') errors"
