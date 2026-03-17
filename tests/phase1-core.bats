#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

# Common setup
setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMP="$(mktemp -d)"

  source "$PROJECT_ROOT/lib/hash.sh"
  source "$PROJECT_ROOT/lib/extract.sh"
  source "$PROJECT_ROOT/lib/template.sh"
  source "$PROJECT_ROOT/lib/adapters/claude_code.sh"
  source "$PROJECT_ROOT/lib/adapters/opencode.sh"

  # Make mock binaries available
  chmod +x "$PROJECT_ROOT/tests/fixtures/mock-claude"
  chmod +x "$PROJECT_ROOT/tests/fixtures/mock-opencode"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ============================================================
# hash.sh tests
# ============================================================

@test "hash: consistent hash for same content" {
  echo "hello world" > "$TEST_TMP/a.txt"
  local hash1
  hash1=$(hash_delivers "$TEST_TMP/a.txt")
  local hash2
  hash2=$(hash_delivers "$TEST_TMP/a.txt")
  assert_equal "$hash1" "$hash2"
}

@test "hash: detects content change" {
  echo "version 1" > "$TEST_TMP/a.txt"
  local hash1
  hash1=$(hash_delivers "$TEST_TMP/a.txt")
  echo "version 2" > "$TEST_TMP/a.txt"
  local hash2
  hash2=$(hash_delivers "$TEST_TMP/a.txt")
  [ "$hash1" != "$hash2" ]
}

@test "hash: no args returns empty string" {
  run hash_delivers
  assert_success
  assert_output ""
}

@test "hash: nonexistent files returns empty string" {
  run hash_delivers "$TEST_TMP/nonexistent1.txt" "$TEST_TMP/nonexistent2.txt"
  assert_success
  assert_output ""
}

@test "hash: hashes content not metadata" {
  echo "same content" > "$TEST_TMP/a.txt"
  local hash1
  hash1=$(hash_delivers "$TEST_TMP/a.txt")
  sleep 1
  # Touch to change mtime, same content
  touch "$TEST_TMP/a.txt"
  local hash2
  hash2=$(hash_delivers "$TEST_TMP/a.txt")
  assert_equal "$hash1" "$hash2"
}

@test "hash: multiple files combined" {
  echo "file1" > "$TEST_TMP/a.txt"
  echo "file2" > "$TEST_TMP/b.txt"
  local hash1
  hash1=$(hash_delivers "$TEST_TMP/a.txt" "$TEST_TMP/b.txt")
  [ -n "$hash1" ]
  # Change one file
  echo "file2-changed" > "$TEST_TMP/b.txt"
  local hash2
  hash2=$(hash_delivers "$TEST_TMP/a.txt" "$TEST_TMP/b.txt")
  [ "$hash1" != "$hash2" ]
}

# ============================================================
# extract.sh tests
# ============================================================

@test "extract: single tag" {
  local content="before <result>hello world</result> after"
  run extract_tag "$content" "result"
  assert_success
  assert_output "hello world"
}

@test "extract: multiline tag content" {
  local content="<result>
line 1
line 2
line 3
</result>"
  run extract_tag "$content" "result"
  assert_success
  assert_output --partial "line 1"
  assert_output --partial "line 2"
  assert_output --partial "line 3"
}

@test "extract: tag with attributes" {
  local content='Some text <insight target="project">This is an insight</insight> more text'
  run extract_tag "$content" "insight"
  assert_success
  assert_output "This is an insight"
}

@test "extract: missing tag returns failure" {
  local content="no tags here"
  run extract_tag "$content" "result"
  assert_failure
}

@test "extract: multiple occurrences" {
  local content='<feedback>first</feedback> middle <feedback>second</feedback>'
  run extract_tag "$content" "feedback"
  assert_success
  assert_line --index 0 "first"
  assert_line --index 1 "second"
}

@test "extract: checkpoint from tag" {
  local output="Some output <checkpoint>Progress: completed step 1 and 2</checkpoint> more output"
  run extract_checkpoint "$output"
  assert_success
  assert_output "Progress: completed step 1 and 2"
}

@test "extract: checkpoint without tag uses last 500 words" {
  local output="This is the agent output without any checkpoint tags"
  run extract_checkpoint "$output"
  assert_success
  assert_output "This is the agent output without any checkpoint tags"
}

@test "extract: checkpoint capped at 500 words" {
  # Generate 600 words
  local words=""
  for i in $(seq 1 600); do
    words+="word${i} "
  done
  local output="<checkpoint>${words}</checkpoint>"
  run extract_checkpoint "$output"
  assert_success
  # Count words in output
  local wc
  wc=$(echo "$output" | wc -w | tr -d ' ')
  # The checkpoint output should be <= 500 words
  local out_wc
  out_wc=$(echo "${lines[0]}" | wc -w | tr -d ' ')
  [ "$out_wc" -le 500 ]
}

@test "extract: checkpoint without tag capped at 500 words from end" {
  # Generate 600 words with no checkpoint tag
  local words=""
  for i in $(seq 1 600); do
    words+="word${i} "
  done
  run extract_checkpoint "$words"
  assert_success
  # Should contain word600 (from end) but not word1
  local output_text="${lines[0]}"
  [[ "$output_text" == *"word600"* ]]
  [[ "$output_text" != *"word1 "* ]]
}

@test "extract: insight targets parsed to JSON" {
  local output='Text <insight target="project">Project insight here</insight> more <insight target="component:drafter">Component insight</insight>'
  run extract_insight_targets "$output"
  assert_success
  assert_line --index 0 --partial '"target":"project"'
  assert_line --index 0 --partial '"content":"Project insight here"'
  assert_line --index 1 --partial '"target":"component:drafter"'
}

@test "extract: decisions parsed to JSON with attributes" {
  local output='<decision title="Use X" target="project" supersedes="dec-001">Decision content here</decision>'
  run extract_decisions "$output"
  assert_success
  assert_line --index 0 --partial '"title":"Use X"'
  assert_line --index 0 --partial '"target":"project"'
  assert_line --index 0 --partial '"supersedes":"dec-001"'
  assert_line --index 0 --partial '"content":"Decision content here"'
}

@test "extract: feedback parsed to JSON" {
  local output='<feedback>Improve validation logic</feedback>'
  run extract_feedback "$output"
  assert_success
  assert_line --index 0 --partial '"content":"Improve validation logic"'
}

# ============================================================
# template.sh tests
# ============================================================

@test "template: basic substitution" {
  echo "Hello {name}, orbit {orbit.n}" > "$TEST_TMP/tpl.md"
  run render_template "$TEST_TMP/tpl.md" "name=World" "orbit.n=5"
  assert_success
  assert_output "Hello World, orbit 5"
}

@test "template: missing vars preserved" {
  echo "Hello {name}, {unknown} var" > "$TEST_TMP/tpl.md"
  run render_template "$TEST_TMP/tpl.md" "name=World"
  assert_success
  assert_output "Hello World, {unknown} var"
}

@test "template: empty value replaces with empty" {
  echo "Value: [{value}]" > "$TEST_TMP/tpl.md"
  run render_template "$TEST_TMP/tpl.md" "value="
  assert_success
  assert_output "Value: []"
}

@test "template: multiple variables" {
  echo "{a} and {b} and {c}" > "$TEST_TMP/tpl.md"
  run render_template "$TEST_TMP/tpl.md" "a=1" "b=2" "c=3"
  assert_success
  assert_output "1 and 2 and 3"
}

@test "template: file not found returns error" {
  run render_template "$TEST_TMP/nonexistent.md"
  assert_failure
}

# ============================================================
# claude_code.sh adapter tests
# ============================================================

@test "adapter: claude model mapping - sonnet" {
  run _claude_model_map "sonnet"
  assert_output "claude-sonnet-4-6"
}

@test "adapter: claude model mapping - opus" {
  run _claude_model_map "opus"
  assert_output "claude-opus-4-6"
}

@test "adapter: claude model mapping - haiku" {
  run _claude_model_map "haiku"
  assert_output "claude-haiku-4-5-20251001"
}

@test "adapter: claude --allowedTools present when restricted" {
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  export MOCK_LOG_FILE="$TEST_TMP/claude-args.log"
  export MOCK_OUTPUT='{"result":"test output"}'
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true

  run adapter_claude_code "test prompt" "sonnet" "10" "restricted" "read-file,write-file"
  assert_success

  # Check logged args contain --allowedTools
  local args
  args=$(cat "$TEST_TMP/claude-args.log")
  [[ "$args" == *"--allowedTools"* ]]
  [[ "$args" == *"read-file,write-file"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "adapter: claude no --allowedTools when standard policy" {
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  export MOCK_LOG_FILE="$TEST_TMP/claude-args.log"
  export MOCK_OUTPUT='{"result":"test output"}'
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true

  run adapter_claude_code "test prompt" "sonnet" "10" "standard" ""
  assert_success

  local args
  args=$(cat "$TEST_TMP/claude-args.log")
  [[ "$args" != *"--allowedTools"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "adapter: claude --max-turns passed" {
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  export MOCK_LOG_FILE="$TEST_TMP/claude-args.log"
  export MOCK_OUTPUT='{"result":"ok"}'
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true

  run adapter_claude_code "prompt" "sonnet" "5" "standard" ""
  assert_success

  local args
  args=$(cat "$TEST_TMP/claude-args.log")
  [[ "$args" == *"--max-turns 5"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

# ============================================================
# opencode.sh adapter tests
# ============================================================

@test "adapter: opencode model pass-through" {
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  export MOCK_LOG_FILE="$TEST_TMP/opencode-args.log"
  export MOCK_OUTPUT="test output"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-opencode" "$PROJECT_ROOT/tests/fixtures/opencode" 2>/dev/null || true

  run adapter_opencode "test prompt" "ollama/llama3.2" "10" "standard" ""
  assert_success

  local args
  args=$(cat "$TEST_TMP/opencode-args.log")
  [[ "$args" == *"ollama/llama3.2"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/opencode"
}

@test "adapter: opencode --no-auto-tools when restricted" {
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  export MOCK_LOG_FILE="$TEST_TMP/opencode-args.log"
  export MOCK_OUTPUT="test output"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-opencode" "$PROJECT_ROOT/tests/fixtures/opencode" 2>/dev/null || true

  run adapter_opencode "prompt" "model" "10" "restricted" "tool1,tool2"
  assert_success

  local args
  args=$(cat "$TEST_TMP/opencode-args.log")
  [[ "$args" == *"--no-auto-tools"* ]]
  [[ "$args" == *"--tools"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/opencode"
}

# ============================================================
# orbit_loop.sh integration tests
# ============================================================

@test "orbit: success on first orbit" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  # Setup mock adapter
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="Task completed successfully"

  # Create prompt template
  echo "Do the work. Orbit {orbit.n}" > "$TEST_TMP/prompt.md"

  # Pre-create the success flag (simulates agent writing it)
  local flag="$TEST_TMP/done.flag"
  touch "$flag"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$flag" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success
  assert_output --partial "Success condition met"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: success on Nth orbit" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_COUNTER_FILE="$TEST_TMP/counter"

  # Mock creates the flag on 3rd call
  local flag="$TEST_TMP/done.flag"
  export MOCK_OUTPUT="Working..."
  export MOCK_OUTPUT_3="Done! <checkpoint>Completed all tasks</checkpoint>"

  # Create a preflight that creates the flag on 3rd orbit
  cat > "$TEST_TMP/create-flag.sh" <<SCRIPT
#!/bin/bash
count=\$(cat "$TEST_TMP/counter" 2>/dev/null || echo 0)
if [ "\$count" -ge 3 ]; then
  touch "$flag"
fi
SCRIPT
  chmod +x "$TEST_TMP/create-flag.sh"

  echo "Work on orbit {orbit.n}" > "$TEST_TMP/prompt.md"

  # We need the flag to appear — use postflight to create it on orbit 3
  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 10 \
    --success-when "file" \
    --success-condition "$flag" \
    --postflight "$TEST_TMP/create-flag.sh" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success
  assert_output --partial "Success condition met"
  assert_output --partial "orbit 3"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: ceiling abort" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="Still working"

  echo "Orbit {orbit.n}" > "$TEST_TMP/prompt.md"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 3 \
    --success-when "file" \
    --success-condition "$TEST_TMP/never-created.flag" \
    --state-dir "$TEST_TMP/.orbit"

  assert_failure
  assert_output --partial "Orbit ceiling reached"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: deadlock detection with abort" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="Same output every time"

  echo "Orbit {orbit.n}" > "$TEST_TMP/prompt.md"

  # Create a delivers file that never changes
  echo "static content" > "$TEST_TMP/output.txt"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 10 \
    --success-when "file" \
    --success-condition "$TEST_TMP/never.flag" \
    --deadlock-threshold 3 \
    --deadlock-action "abort" \
    --delivers "$TEST_TMP/output.txt" \
    --state-dir "$TEST_TMP/.orbit"

  assert_failure
  assert_output --partial "Deadlock detected"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: deadlock with perspective resets counter" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_LOG_FILE="$TEST_TMP/claude-args.log"
  export MOCK_OUTPUT="Same output"

  echo "Orbit {orbit.n}" > "$TEST_TMP/prompt.md"
  echo "static" > "$TEST_TMP/output.txt"

  # Use perspective action with max orbits = 5
  # Deadlock at 2, perspective resets, deadlock at 2 again on orbit 4
  # Then perspective again, orbit 5 hits, orbit 6 > max → ceiling
  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/never.flag" \
    --deadlock-threshold 2 \
    --deadlock-action "perspective" \
    --delivers "$TEST_TMP/output.txt" \
    --state-dir "$TEST_TMP/.orbit"

  assert_failure
  # Should eventually hit ceiling, not deadlock abort
  assert_output --partial "Orbit ceiling reached"
  assert_output --partial "perspective"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: preflight failure aborts" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="output"

  echo "Prompt" > "$TEST_TMP/prompt.md"

  # Failing preflight script
  cat > "$TEST_TMP/fail-preflight.sh" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
  chmod +x "$TEST_TMP/fail-preflight.sh"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --preflight "$TEST_TMP/fail-preflight.sh" \
    --state-dir "$TEST_TMP/.orbit"

  assert_failure
  assert_output --partial "Preflight failed"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: checkpoint written to state dir" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="Result text <checkpoint>Completed step 1 of 3</checkpoint>"

  echo "Prompt" > "$TEST_TMP/prompt.md"
  touch "$TEST_TMP/done.flag"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success

  # Checkpoint should be written
  [ -f "$TEST_TMP/.orbit/state/test-worker/checkpoint.md" ]
  local checkpoint
  checkpoint=$(cat "$TEST_TMP/.orbit/state/test-worker/checkpoint.md")
  [[ "$checkpoint" == *"Completed step 1 of 3"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: rendered prompt saved per orbit" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true

  # Two orbits: first fails success check, second succeeds
  export MOCK_OUTPUT="orbit 1 result <checkpoint>step 1</checkpoint>"
  export MOCK_OUTPUT_2="orbit 2 result"

  echo "Task: do the thing. Orbit {orbit.n}" > "$TEST_TMP/prompt.md"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --state-dir "$TEST_TMP/.orbit"

  # Both orbit prompts should be saved
  [ -f "$TEST_TMP/.orbit/state/test-worker/prompts/orbit-1.md" ]
  [ -f "$TEST_TMP/.orbit/state/test-worker/prompts/orbit-2.md" ]

  # Prompts should contain rendered template variables
  local prompt1
  prompt1=$(cat "$TEST_TMP/.orbit/state/test-worker/prompts/orbit-1.md")
  [[ "$prompt1" == *"Orbit 1"* ]]

  local prompt2
  prompt2=$(cat "$TEST_TMP/.orbit/state/test-worker/prompts/orbit-2.md")
  [[ "$prompt2" == *"Orbit 2"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: rendered prompts scoped to run directory when run-id set" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="result"

  echo "Prompt" > "$TEST_TMP/prompt.md"
  touch "$TEST_TMP/done.flag"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --state-dir "$TEST_TMP/.orbit" \
    --run-id "run-456"

  assert_success

  [ -f "$TEST_TMP/.orbit/runs/run-456/state/test-worker/prompts/orbit-1.md" ]
  [ ! -d "$TEST_TMP/.orbit/state/test-worker/prompts" ]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: postflight hooks executed" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="output"

  echo "Prompt" > "$TEST_TMP/prompt.md"
  touch "$TEST_TMP/done.flag"

  # Postflight writes a marker file
  cat > "$TEST_TMP/postflight.sh" <<SCRIPT
#!/bin/bash
echo "postflight ran" > "$TEST_TMP/postflight-marker.txt"
SCRIPT
  chmod +x "$TEST_TMP/postflight.sh"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --postflight "$TEST_TMP/postflight.sh" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success
  [ -f "$TEST_TMP/postflight-marker.txt" ]
  local marker
  marker=$(cat "$TEST_TMP/postflight-marker.txt")
  [[ "$marker" == *"postflight ran"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: learning storage writes JSONL" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT='Output with <insight target="project">Test insight content</insight> and <feedback>Improve prompts</feedback>'

  echo "Prompt" > "$TEST_TMP/prompt.md"
  touch "$TEST_TMP/done.flag"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success

  # Check insights JSONL was written
  [ -f "$TEST_TMP/.orbit/learning/insights/project.jsonl" ]
  local insight_line
  insight_line=$(cat "$TEST_TMP/.orbit/learning/insights/project.jsonl")
  [[ "$insight_line" == *"Test insight content"* ]]

  # Check feedback JSONL was written
  [ -f "$TEST_TMP/components/test-worker/test-worker.feedback.jsonl" ]
  local feedback_line
  feedback_line=$(cat "$TEST_TMP/components/test-worker/test-worker.feedback.jsonl")
  [[ "$feedback_line" == *"Improve prompts"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: bash success condition" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="output"

  echo "Prompt" > "$TEST_TMP/prompt.md"

  # Create a file that the bash condition checks
  echo "complete" > "$TEST_TMP/status.txt"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "bash" \
    --success-condition "grep -q complete $TEST_TMP/status.txt" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success
  assert_output --partial "Success condition met"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: no delivers means no deadlock detection" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="Same output every time"

  echo "Prompt" > "$TEST_TMP/prompt.md"

  # With no --delivers, deadlock detection is disabled
  # Should hit ceiling, not deadlock
  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 3 \
    --success-when "file" \
    --success-condition "$TEST_TMP/never.flag" \
    --deadlock-threshold 2 \
    --deadlock-action "abort" \
    --state-dir "$TEST_TMP/.orbit"

  assert_failure
  assert_output --partial "Orbit ceiling reached"
  refute_output --partial "Deadlock"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: both empty hashes not treated as deadlock" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="output"

  echo "Prompt" > "$TEST_TMP/prompt.md"

  # delivers points to nonexistent file — both pre and post hash are empty
  # Should NOT trigger deadlock
  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 3 \
    --success-when "file" \
    --success-condition "$TEST_TMP/never.flag" \
    --deadlock-threshold 2 \
    --deadlock-action "abort" \
    --delivers "$TEST_TMP/nonexistent-file.txt" \
    --state-dir "$TEST_TMP/.orbit"

  assert_failure
  assert_output --partial "Orbit ceiling reached"
  refute_output --partial "Deadlock detected"

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "extract: multiline insight" {
  local output='<insight target="project">
Line one of the insight.
Line two of the insight.
</insight>'
  run extract_insight_targets "$output"
  assert_success
  assert_line --index 0 --partial '"target":"project"'
  assert_line --index 0 --partial "Line one"
}

@test "extract: decision without supersedes" {
  local output='<decision title="My Decision" target="mission">Some rationale</decision>'
  run extract_decisions "$output"
  assert_success
  assert_line --index 0 --partial '"title":"My Decision"'
  assert_line --index 0 --partial '"supersedes":""'
}

# ============================================================
# extract_progress tests
# ============================================================

@test "extract: progress returns content from progress tag" {
  local output="Some output <progress>- Done: analysed source A
- Skipped: source B unavailable</progress> more output"
  run extract_progress "$output"
  assert_success
  assert_output --partial "Done: analysed source A"
  assert_output --partial "Skipped: source B unavailable"
}

@test "extract: progress returns empty when no tag" {
  local output="No progress tags here at all"
  run extract_progress "$output"
  assert_success
  assert_output ""
}

# ============================================================
# orbit loop progress integration tests
# ============================================================

@test "orbit: progress appended across orbits" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_COUNTER_FILE="$TEST_TMP/counter"

  # Mock emits progress tags on each orbit
  export MOCK_OUTPUT="Working <progress>- Done: task A</progress> <checkpoint>did A</checkpoint>"
  export MOCK_OUTPUT_2="Working <progress>- Done: task B</progress> <checkpoint>did B</checkpoint>"
  export MOCK_OUTPUT_3="Working <progress>- Done: task C</progress> <checkpoint>did C</checkpoint>"

  echo "Orbit {orbit.n}" > "$TEST_TMP/prompt.md"

  # Create a postflight that creates flag on orbit 3
  local flag="$TEST_TMP/done.flag"
  cat > "$TEST_TMP/create-flag.sh" <<SCRIPT
#!/bin/bash
count=\$(cat "$TEST_TMP/counter" 2>/dev/null || echo 0)
if [ "\$count" -ge 3 ]; then
  touch "$flag"
fi
SCRIPT
  chmod +x "$TEST_TMP/create-flag.sh"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 10 \
    --success-when "file" \
    --success-condition "$flag" \
    --postflight "$TEST_TMP/create-flag.sh" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success

  # Progress file should have entries from all 3 orbits
  local progress_content
  progress_content=$(cat "$TEST_TMP/.orbit/state/test-worker/progress.md")
  [[ "$progress_content" == *"## Orbit 1"* ]]
  [[ "$progress_content" == *"Done: task A"* ]]
  [[ "$progress_content" == *"## Orbit 2"* ]]
  [[ "$progress_content" == *"Done: task B"* ]]
  [[ "$progress_content" == *"## Orbit 3"* ]]
  [[ "$progress_content" == *"Done: task C"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: progress file cleared on start" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="output <progress>- Done: fresh start</progress>"

  echo "Prompt" > "$TEST_TMP/prompt.md"
  touch "$TEST_TMP/done.flag"

  # Pre-populate progress file with old content
  mkdir -p "$TEST_TMP/.orbit/state/test-worker"
  echo "## Orbit 1

- Done: old stale content from previous run" > "$TEST_TMP/.orbit/state/test-worker/progress.md"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success

  # Progress should NOT contain old content
  local progress_content
  progress_content=$(cat "$TEST_TMP/.orbit/state/test-worker/progress.md")
  [[ "$progress_content" != *"old stale content"* ]]
  [[ "$progress_content" == *"Done: fresh start"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: orbit.progress template variable is injected" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_LOG_FILE="$TEST_TMP/claude-args.log"
  export MOCK_COUNTER_FILE="$TEST_TMP/counter"

  # First orbit emits progress, second orbit should see it in the prompt
  export MOCK_OUTPUT="result <progress>- Done: initial work</progress>"
  export MOCK_OUTPUT_2="result"

  echo "Progress: {orbit.progress}" > "$TEST_TMP/prompt.md"

  # Create flag on orbit 2
  local flag="$TEST_TMP/done.flag"
  cat > "$TEST_TMP/create-flag.sh" <<SCRIPT
#!/bin/bash
count=\$(cat "$TEST_TMP/counter" 2>/dev/null || echo 0)
if [ "\$count" -ge 2 ]; then
  touch "$flag"
fi
SCRIPT
  chmod +x "$TEST_TMP/create-flag.sh"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$flag" \
    --postflight "$TEST_TMP/create-flag.sh" \
    --state-dir "$TEST_TMP/.orbit"

  assert_success

  # The second prompt should contain the progress from orbit 1
  local args
  args=$(cat "$TEST_TMP/claude-args.log")
  [[ "$args" == *"Done: initial work"* ]]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "orbit: checkpoint and progress scoped to run directory when run-id set" {
  source "$PROJECT_ROOT/lib/orbit_loop.sh"

  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  ln -sf "$PROJECT_ROOT/tests/fixtures/mock-claude" "$PROJECT_ROOT/tests/fixtures/claude" 2>/dev/null || true
  export MOCK_OUTPUT="Result <checkpoint>Run-scoped checkpoint</checkpoint> <progress>- Done: run-scoped work</progress>"

  echo "Prompt" > "$TEST_TMP/prompt.md"
  touch "$TEST_TMP/done.flag"

  run orbit_run_component \
    --component "test-worker" \
    --prompt "$TEST_TMP/prompt.md" \
    --adapter "claude-code" \
    --model "sonnet" \
    --orbits-max 5 \
    --success-when "file" \
    --success-condition "$TEST_TMP/done.flag" \
    --state-dir "$TEST_TMP/.orbit" \
    --run-id "run-123"

  assert_success

  # Checkpoint and progress should be under runs/run-123/state/
  [ -f "$TEST_TMP/.orbit/runs/run-123/state/test-worker/checkpoint.md" ]
  local checkpoint
  checkpoint=$(cat "$TEST_TMP/.orbit/runs/run-123/state/test-worker/checkpoint.md")
  [[ "$checkpoint" == *"Run-scoped checkpoint"* ]]

  [ -f "$TEST_TMP/.orbit/runs/run-123/state/test-worker/progress.md" ]
  local progress
  progress=$(cat "$TEST_TMP/.orbit/runs/run-123/state/test-worker/progress.md")
  [[ "$progress" == *"run-scoped work"* ]]

  # Should NOT exist at the global state path
  [ ! -f "$TEST_TMP/.orbit/state/test-worker/checkpoint.md" ]
  [ ! -f "$TEST_TMP/.orbit/state/test-worker/progress.md" ]

  rm -f "$PROJECT_ROOT/tests/fixtures/claude"
}

@test "hash: single file hash is valid hex" {
  echo "test" > "$TEST_TMP/f.txt"
  local h
  h=$(hash_delivers "$TEST_TMP/f.txt")
  [[ "$h" =~ ^[0-9a-f]{64}$ ]]
}
