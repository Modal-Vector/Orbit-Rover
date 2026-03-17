#!/usr/bin/env bash
set -euo pipefail

# distil-sources.sh — Distil raw sources to structured text for the researcher
# Handles HTML stripping and PDF text extraction, caps output at 8KB.

ATOMIC_FILE="${ORBIT_RUN_DIR:-.orbit}/plans/research/atomic/current.json"

if [ ! -f "$ATOMIC_FILE" ]; then
  echo "[ORBIT WARN] No atomic tasks file at $ATOMIC_FILE" >&2
  exit 0
fi

# Find current atomic task
TASK=$(jq -r '[.atomic_tasks[] | select(.done == false)] | first // empty' "$ATOMIC_FILE")

if [ -z "$TASK" ]; then
  echo "[ORBIT INFO] All atomic tasks complete" >&2
  exit 0
fi

TASK_ID=$(echo "$TASK" | jq -r '.id')
SOURCE_URL=$(echo "$TASK" | jq -r '.source_url // empty')

OUTPUT_DIR="sources/${TASK_ID}"
mkdir -p "$OUTPUT_DIR"

if [ -z "$SOURCE_URL" ]; then
  echo "No source URL provided for this task. Work from existing knowledge." > "${OUTPUT_DIR}/distilled.md"
  exit 0
fi

# Fetch the source
RAW_FILE="${OUTPUT_DIR}/raw"
echo "[ORBIT INFO] Fetching $SOURCE_URL for task $TASK_ID"
if ! curl -sL --max-time 30 --max-filesize 5242880 -o "$RAW_FILE" "$SOURCE_URL" 2>/dev/null; then
  echo "Source fetch failed for $SOURCE_URL. Work from existing knowledge." > "${OUTPUT_DIR}/distilled.md"
  exit 0
fi

# Detect content type and distil
MIME_TYPE=$(file --mime-type -b "$RAW_FILE" 2>/dev/null || echo "text/html")

case "$MIME_TYPE" in
  application/pdf)
    # Try pdftotext, fall back to python3
    if command -v pdftotext >/dev/null 2>&1; then
      pdftotext "$RAW_FILE" - 2>/dev/null | head -c 8192 > "${OUTPUT_DIR}/distilled.md"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c "
import subprocess, sys
try:
    result = subprocess.run(['pdftotext', '$RAW_FILE', '-'], capture_output=True, text=True, timeout=30)
    print(result.stdout[:8192])
except Exception:
    print('PDF extraction failed. Source requires manual review.')
" > "${OUTPUT_DIR}/distilled.md"
    else
      echo "PDF source — extraction tools unavailable." > "${OUTPUT_DIR}/distilled.md"
    fi
    ;;
  text/html|application/xhtml*)
    # Strip HTML using python3
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import re, html
raw = open('$RAW_FILE', 'r', errors='replace').read()
raw = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', raw, flags=re.DOTALL|re.IGNORECASE)
text = re.sub(r'<[^>]+>', ' ', raw)
text = html.unescape(text)
text = re.sub(r'\s+', ' ', text).strip()
print(text[:8192])
" > "${OUTPUT_DIR}/distilled.md"
    else
      sed 's/<[^>]*>/ /g' "$RAW_FILE" | tr -s ' \n' ' ' | head -c 8192 > "${OUTPUT_DIR}/distilled.md"
    fi
    ;;
  *)
    # Plain text or unknown — just cap it
    head -c 8192 "$RAW_FILE" > "${OUTPUT_DIR}/distilled.md"
    ;;
esac

echo "[ORBIT INFO] Distilled to ${OUTPUT_DIR}/distilled.md ($(wc -c < "${OUTPUT_DIR}/distilled.md") bytes)"
