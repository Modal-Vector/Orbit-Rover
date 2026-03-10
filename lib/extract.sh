#!/usr/bin/env bash
set -euo pipefail

# extract.sh — XML tag extraction from agent output

# Extract content between <tag> and </tag>, handling attributes and multiline.
# Usage: extract_tag "$content" "tag_name"
# Outputs each match on stdout, separated by newlines.
# Returns 1 if no match found.
extract_tag() {
  local content="$1"
  local tag="$2"

  local result
  result=$(echo "$content" | awk -v tag="$tag" '
    BEGIN { found=0; collecting=0; buf="" }
    {
      line = $0
      while (line != "") {
        if (collecting) {
          idx = index(line, "</" tag ">")
          if (idx > 0) {
            buf = buf (buf != "" ? "\n" : "") substr(line, 1, idx - 1)
            if (found > 0) printf "\n"
            printf "%s", buf
            found++
            collecting = 0
            buf = ""
            line = substr(line, idx + length("</" tag ">"))
          } else {
            buf = buf (buf != "" ? "\n" : "") line
            line = ""
          }
        } else {
          # Match <tag> or <tag attr="...">
          if (match(line, "<" tag "([ \t][^>]*)?>")) {
            start = RSTART + RLENGTH
            rest = substr(line, start)
            idx = index(rest, "</" tag ">")
            if (idx > 0) {
              content_str = substr(rest, 1, idx - 1)
              if (found > 0) printf "\n"
              printf "%s", content_str
              found++
              line = substr(rest, idx + length("</" tag ">"))
            } else {
              collecting = 1
              buf = rest
              line = ""
            }
          } else {
            line = ""
          }
        }
      }
    }
    END { if (found > 0) print ""; exit (found > 0 ? 0 : 1) }
  ')

  local rc=$?
  if [ $rc -eq 0 ]; then
    echo "$result"
    return 0
  fi
  return 1
}

# Extract a single attribute value from a tag's opening element.
# Usage: extract_tag_attr "$content" "tag_name" "attr_name"
extract_tag_attr() {
  local content="$1"
  local tag="$2"
  local attr="$3"

  echo "$content" | awk -v tag="$tag" -v attr="$attr" '
    {
      if (match($0, "<" tag "[ \t][^>]*" attr "=\"[^\"]*\"")) {
        s = substr($0, RSTART, RLENGTH)
        if (match(s, attr "=\"[^\"]*\"")) {
          val = substr(s, RSTART + length(attr) + 2)
          sub(/"$/, "", val)
          print val
        }
      }
    }
  '
}

# Extract checkpoint from agent output.
# If <checkpoint> tag exists, use its content. Otherwise last 500 words.
# Cap at 500 words either way.
extract_checkpoint() {
  local output="$1"

  local checkpoint
  if checkpoint=$(extract_tag "$output" "checkpoint"); then
    # Cap at 500 words
    echo "$checkpoint" | awk '
      { for (i=1; i<=NF; i++) { words[++n] = $i } }
      END {
        max = (n < 500) ? n : 500
        for (i=1; i<=max; i++) {
          if (i > 1) printf " "
          printf "%s", words[i]
        }
        if (max > 0) print ""
      }
    '
  else
    # Last 500 words of raw output
    echo "$output" | awk '
      { for (i=1; i<=NF; i++) { words[++n] = $i } }
      END {
        start = (n > 500) ? n - 499 : 1
        for (i=start; i<=n; i++) {
          if (i > start) printf " "
          printf "%s", words[i]
        }
        if (n > 0) print ""
      }
    '
  fi
}

# Extract insight tags as JSON lines.
# Each line: {"target":"...","content":"..."}
extract_insight_targets() {
  local output="$1"

  echo "$output" | awk '
    BEGIN { collecting=0; buf=""; target="" }
    {
      line = $0
      while (line != "") {
        if (collecting) {
          idx = index(line, "</insight>")
          if (idx > 0) {
            buf = buf (buf != "" ? "\\n" : "") substr(line, 1, idx - 1)
            gsub(/"/, "\\\"", buf)
            gsub(/\t/, "\\t", buf)
            printf "{\"target\":\"%s\",\"content\":\"%s\"}\n", target, buf
            collecting = 0
            buf = ""
            line = substr(line, idx + 10)
          } else {
            buf = buf (buf != "" ? "\\n" : "") line
            line = ""
          }
        } else {
          if (match(line, /<insight[ \t]+target="[^"]*">/)) {
            tag_start = RSTART
            tag_len = RLENGTH
            s = substr(line, tag_start, tag_len)
            match(s, /target="[^"]*"/)
            target = substr(s, RSTART + 8, RLENGTH - 9)
            rest = substr(line, tag_start + tag_len)
            idx = index(rest, "</insight>")
            if (idx > 0) {
              content = substr(rest, 1, idx - 1)
              gsub(/"/, "\\\"", content)
              gsub(/\t/, "\\t", content)
              printf "{\"target\":\"%s\",\"content\":\"%s\"}\n", target, content
              line = substr(rest, idx + 10)
            } else {
              collecting = 1
              buf = rest
              line = ""
            }
          } else {
            line = ""
          }
        }
      }
    }
  '
}

# Extract decision tags as JSON lines.
# Each line: {"title":"...","target":"...","supersedes":"...","content":"..."}
extract_decisions() {
  local output="$1"

  echo "$output" | awk '
    BEGIN { collecting=0; buf=""; title=""; target=""; supersedes="" }
    {
      line = $0
      while (line != "") {
        if (collecting) {
          idx = index(line, "</decision>")
          if (idx > 0) {
            buf = buf (buf != "" ? "\\n" : "") substr(line, 1, idx - 1)
            gsub(/"/, "\\\"", buf)
            gsub(/\t/, "\\t", buf)
            printf "{\"title\":\"%s\",\"target\":\"%s\",\"supersedes\":\"%s\",\"content\":\"%s\"}\n", title, target, supersedes, buf
            collecting = 0
            buf = ""
            line = substr(line, idx + 11)
          } else {
            buf = buf (buf != "" ? "\\n" : "") line
            line = ""
          }
        } else {
          if (match(line, /<decision[ \t][^>]*>/)) {
            tag_start = RSTART
            tag_len = RLENGTH
            s = substr(line, tag_start, tag_len)
            # extract title
            title = ""
            if (match(s, /title="[^"]*"/)) {
              title = substr(s, RSTART + 7, RLENGTH - 8)
            }
            # extract target
            target = ""
            if (match(s, /target="[^"]*"/)) {
              target = substr(s, RSTART + 8, RLENGTH - 9)
            }
            # extract supersedes
            supersedes = ""
            if (match(s, /supersedes="[^"]*"/)) {
              supersedes = substr(s, RSTART + 12, RLENGTH - 13)
            }
            rest = substr(line, tag_start + tag_len)
            idx = index(rest, "</decision>")
            if (idx > 0) {
              content = substr(rest, 1, idx - 1)
              gsub(/"/, "\\\"", content)
              gsub(/\t/, "\\t", content)
              printf "{\"title\":\"%s\",\"target\":\"%s\",\"supersedes\":\"%s\",\"content\":\"%s\"}\n", title, target, supersedes, content
              line = substr(rest, idx + 11)
            } else {
              collecting = 1
              buf = rest
              line = ""
            }
          } else {
            line = ""
          }
        }
      }
    }
  '
}

# Extract vote tags as JSON lines.
# Input: <vote id="fb-xxx" weight="N">comment</vote>
# Each line: {"id":"...","weight":N,"comment":"..."}
extract_votes() {
  local output="$1"

  echo "$output" | awk '
    BEGIN { collecting=0; buf=""; vid=""; weight=0 }
    {
      line = $0
      while (line != "") {
        if (collecting) {
          idx = index(line, "</vote>")
          if (idx > 0) {
            buf = buf (buf != "" ? "\\n" : "") substr(line, 1, idx - 1)
            gsub(/"/, "\\\"", buf)
            gsub(/\t/, "\\t", buf)
            printf "{\"id\":\"%s\",\"weight\":%d,\"comment\":\"%s\"}\n", vid, weight, buf
            collecting = 0
            buf = ""
            line = substr(line, idx + 7)
          } else {
            buf = buf (buf != "" ? "\\n" : "") line
            line = ""
          }
        } else {
          if (match(line, /<vote[ \t][^>]*>/)) {
            tag_start = RSTART
            tag_len = RLENGTH
            s = substr(line, tag_start, tag_len)
            # extract id
            vid = ""
            if (match(s, /id="[^"]*"/)) {
              vid = substr(s, RSTART + 4, RLENGTH - 5)
            }
            # extract weight
            weight = 1
            if (match(s, /weight="[^"]*"/)) {
              w = substr(s, RSTART + 8, RLENGTH - 9)
              weight = w + 0
            }
            rest = substr(line, tag_start + tag_len)
            idx = index(rest, "</vote>")
            if (idx > 0) {
              content = substr(rest, 1, idx - 1)
              gsub(/"/, "\\\"", content)
              gsub(/\t/, "\\t", content)
              printf "{\"id\":\"%s\",\"weight\":%d,\"comment\":\"%s\"}\n", vid, weight, content
              line = substr(rest, idx + 7)
            } else {
              collecting = 1
              buf = rest
              line = ""
            }
          } else {
            line = ""
          }
        }
      }
    }
  '
}

# Extract feedback tags as JSON lines.
# Each line: {"content":"..."}
extract_feedback() {
  local output="$1"

  local content
  if content=$(extract_tag "$output" "feedback"); then
    echo "$content" | while IFS= read -r line; do
      [ -z "$line" ] && continue
      # Escape for JSON
      local escaped
      escaped=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
      echo "{\"content\":\"$escaped\"}"
    done
  fi
}
