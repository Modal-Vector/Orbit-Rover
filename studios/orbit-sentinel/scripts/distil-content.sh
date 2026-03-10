#!/usr/bin/env bash
set -euo pipefail

# distil-content.sh — Strip HTML and distil content to a manageable size
# Reads raw.html from the current task's source directory, strips tags,
# and caps output at 8KB.

TASKS_FILE=".orbit/plans/sentinel/tasks.json"

if [ ! -f "$TASKS_FILE" ]; then
  echo "[ORBIT WARN] No tasks file found at $TASKS_FILE" >&2
  exit 0
fi

# Find the first incomplete task
TASK_ID=$(jq -r '[.tasks[] | select(.done == false)] | first | .id // empty' "$TASKS_FILE")

if [ -z "$TASK_ID" ]; then
  echo "[ORBIT INFO] All tasks complete" >&2
  exit 0
fi

RAW_FILE="sources/${TASK_ID}/raw.html"
OUTPUT_FILE="sources/${TASK_ID}/distilled.md"

if [ ! -f "$RAW_FILE" ]; then
  echo "[ORBIT WARN] No raw content at $RAW_FILE" >&2
  echo "No content available for this source." > "$OUTPUT_FILE"
  exit 0
fi

# Strip HTML tags using python3
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import sys, re, html
raw = open('$RAW_FILE', 'r', errors='replace').read()
# Remove script and style blocks
raw = re.sub(r'<(script|style)[^>]*>.*?</\1>', '', raw, flags=re.DOTALL|re.IGNORECASE)
# Remove HTML tags
text = re.sub(r'<[^>]+>', ' ', raw)
# Decode HTML entities
text = html.unescape(text)
# Collapse whitespace
text = re.sub(r'\s+', ' ', text).strip()
# Cap at 8KB
text = text[:8192]
print(text)
" > "$OUTPUT_FILE"
else
  # Fallback: basic tag stripping with sed
  sed 's/<[^>]*>/ /g' "$RAW_FILE" | tr -s ' \n' ' ' | head -c 8192 > "$OUTPUT_FILE"
fi

echo "[ORBIT INFO] Distilled content written to $OUTPUT_FILE ($(wc -c < "$OUTPUT_FILE") bytes)"
