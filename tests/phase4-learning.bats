#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMP="$(mktemp -d)"
  export ORBIT_LIB_DIR="$PROJECT_ROOT/lib"

  source "$PROJECT_ROOT/lib/util.sh"
  source "$PROJECT_ROOT/lib/extract.sh"
  source "$PROJECT_ROOT/lib/learning/feedback.sh"
  source "$PROJECT_ROOT/lib/learning/insights.sh"
  source "$PROJECT_ROOT/lib/learning/decisions.sh"
  source "$PROJECT_ROOT/lib/learning/parse_tags.sh"

  mkdir -p "$TEST_TMP/.orbit/learning/insights"
  mkdir -p "$TEST_TMP/.orbit/learning/decisions"
  mkdir -p "$TEST_TMP/.orbit/state"
  mkdir -p "$TEST_TMP/components"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ============================================================
# extract_votes tests
# ============================================================

@test "extract: vote tags parsed correctly" {
  local output='Some text <vote id="fb-abc123" weight="2">Still relevant</vote> more text'
  run extract_votes "$output"
  assert_success
  assert_output --partial '"id":"fb-abc123"'
  assert_output --partial '"weight":2'
  assert_output --partial '"comment":"Still relevant"'
}

@test "extract: multiple vote tags" {
  local input='<vote id="fb-001" weight="1">Good</vote> <vote id="fb-002" weight="3">Great</vote>'
  run extract_votes "$input"
  assert_success
  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

# ============================================================
# feedback.sh tests
# ============================================================

@test "feedback: append creates JSONL with correct schema" {
  local id
  id=$(feedback_append "doc-drafter" "Improve date validation" "$TEST_TMP")
  [[ "$id" == fb-* ]]

  local file="$TEST_TMP/components/doc-drafter/doc-drafter.feedback.jsonl"
  [ -f "$file" ]

  local entry
  entry=$(cat "$file")
  echo "$entry" | jq -e '.id' >/dev/null
  echo "$entry" | jq -e '.component == "doc-drafter"' >/dev/null
  echo "$entry" | jq -e '.content == "Improve date validation"' >/dev/null
  echo "$entry" | jq -e '.votes == 1' >/dev/null
  echo "$entry" | jq -e '.created_at' >/dev/null
}

@test "feedback: ID has fb- prefix" {
  local id
  id=$(feedback_append "worker" "test content" "$TEST_TMP")
  [[ "$id" == fb-* ]]
  [ ${#id} -eq 15 ]  # fb- + 12 chars
}

@test "feedback: append with run_id" {
  feedback_append "worker" "content" "$TEST_TMP" "run-123" >/dev/null
  local entry
  entry=$(cat "$TEST_TMP/components/worker/worker.feedback.jsonl")
  echo "$entry" | jq -e '.run_id == "run-123"' >/dev/null
}

@test "feedback: vote accumulation" {
  local id
  id=$(feedback_append "worker" "useful feedback" "$TEST_TMP")

  feedback_vote "$id" 2 "worker" "$TEST_TMP"

  local votes
  votes=$(jq -r '.votes' "$TEST_TMP/components/worker/worker.feedback.jsonl")
  [ "$votes" -eq 3 ]  # initial 1 + 2
}

@test "feedback: vote by prefix" {
  local id
  id=$(feedback_append "worker" "some feedback" "$TEST_TMP")
  local prefix="${id:0:8}"

  feedback_vote "$prefix" 1 "worker" "$TEST_TMP"

  local votes
  votes=$(jq -r '.votes' "$TEST_TMP/components/worker/worker.feedback.jsonl")
  [ "$votes" -eq 2 ]
}

@test "feedback: vote on nonexistent entry fails" {
  feedback_append "worker" "content" "$TEST_TMP" >/dev/null
  run feedback_vote "fb-nonexistent" 1 "worker" "$TEST_TMP"
  assert_failure
}

@test "feedback: read sorted by votes descending" {
  feedback_append "worker" "low priority" "$TEST_TMP" >/dev/null
  local id2
  id2=$(feedback_append "worker" "high priority" "$TEST_TMP")
  feedback_vote "$id2" 5 "worker" "$TEST_TMP"

  local first_content
  first_content=$(feedback_read "worker" "$TEST_TMP" | jq -s '.[0].content' -r)
  [ "$first_content" = "high priority" ]
}

@test "feedback: assemble markdown format" {
  feedback_append "worker" "First feedback" "$TEST_TMP" >/dev/null
  local id2
  id2=$(feedback_append "worker" "Second feedback" "$TEST_TMP")
  feedback_vote "$id2" 4 "worker" "$TEST_TMP"

  run feedback_assemble "worker" 10 "$TEST_TMP"
  assert_success
  assert_output --partial "## Feedback (top 2 by votes)"
  assert_output --partial "[5 votes] Second feedback"
  assert_output --partial "[1 votes] First feedback"
}

@test "feedback: assemble respects limit" {
  feedback_append "worker" "one" "$TEST_TMP" >/dev/null
  feedback_append "worker" "two" "$TEST_TMP" >/dev/null
  feedback_append "worker" "three" "$TEST_TMP" >/dev/null

  run feedback_assemble "worker" 2 "$TEST_TMP"
  assert_success
  assert_output --partial "top 2 by votes"
  # Should only have 2 content lines
  local content_lines
  content_lines=$(echo "$output" | grep -c '\[.*votes\]')
  [ "$content_lines" -eq 2 ]
}

@test "feedback: clear removes file" {
  feedback_append "worker" "content" "$TEST_TMP" >/dev/null
  [ -f "$TEST_TMP/components/worker/worker.feedback.jsonl" ]

  feedback_clear "worker" "$TEST_TMP"
  [ ! -f "$TEST_TMP/components/worker/worker.feedback.jsonl" ]
}

# ============================================================
# insights.sh tests
# ============================================================

@test "insights: append project scope" {
  local id
  id=$(insight_append "project" "" "Always check benchmarks" "run-1" 1 "$TEST_TMP/.orbit")
  [[ "$id" == ins-* ]]

  [ -f "$TEST_TMP/.orbit/learning/insights/project.jsonl" ]
  local entry
  entry=$(cat "$TEST_TMP/.orbit/learning/insights/project.jsonl")
  echo "$entry" | jq -e '.scope_kind == "project"' >/dev/null
  echo "$entry" | jq -e '.content == "Always check benchmarks"' >/dev/null
  echo "$entry" | jq -e '.orbit == 1' >/dev/null
}

@test "insights: append mission scope" {
  insight_append "mission" "implement" "Sprint boundaries are risky" "run-1" 2 "$TEST_TMP/.orbit" >/dev/null
  [ -f "$TEST_TMP/.orbit/learning/insights/mission.implement.jsonl" ]
}

@test "insights: append component scope" {
  insight_append "component" "doc-drafter" "SRS after risk-monitor is better" "run-1" 3 "$TEST_TMP/.orbit" >/dev/null
  [ -f "$TEST_TMP/.orbit/learning/insights/component.doc-drafter.jsonl" ]
}

@test "insights: run scope goes to tmp file" {
  insight_append "run" "" "Ephemeral note" "run-1" 1 "$TEST_TMP/.orbit" >/dev/null
  [ -f "$TEST_TMP/.orbit/state/run-insights.tmp" ]
  [ ! -f "$TEST_TMP/.orbit/learning/insights/run.jsonl" ]
}

@test "insights: read returns entries for scope" {
  insight_append "project" "" "Insight one" "run-1" 1 "$TEST_TMP/.orbit" >/dev/null
  insight_append "project" "" "Insight two" "run-1" 2 "$TEST_TMP/.orbit" >/dev/null

  run insight_read "project" "" "$TEST_TMP/.orbit"
  assert_success
  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

@test "insights: assemble hierarchy project+mission+component" {
  insight_append "project" "" "Project level" "run-1" 1 "$TEST_TMP/.orbit" >/dev/null
  insight_append "mission" "impl" "Mission level" "run-1" 2 "$TEST_TMP/.orbit" >/dev/null
  insight_append "component" "worker" "Component level" "run-1" 3 "$TEST_TMP/.orbit" >/dev/null

  run insight_assemble "worker" "impl" 20 "$TEST_TMP/.orbit"
  assert_success
  assert_output --partial "[project] Project level"
  assert_output --partial "[mission] Mission level"
  assert_output --partial "[component] Component level"
}

@test "insights: assemble deduplicates by content" {
  insight_append "project" "" "Same insight" "run-1" 1 "$TEST_TMP/.orbit" >/dev/null
  insight_append "project" "" "Same insight" "run-1" 2 "$TEST_TMP/.orbit" >/dev/null

  run insight_assemble "" "" 20 "$TEST_TMP/.orbit"
  assert_success
  local count
  count=$(echo "$output" | grep -c "Same insight")
  [ "$count" -eq 1 ]
}

@test "insights: assemble respects limit" {
  for i in $(seq 1 5); do
    insight_append "project" "" "Insight number $i" "run-1" "$i" "$TEST_TMP/.orbit" >/dev/null
  done

  run insight_assemble "" "" 3 "$TEST_TMP/.orbit"
  assert_success
  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$count" -le 3 ]
}

@test "insights: clear removes file" {
  insight_append "project" "" "content" "run-1" 1 "$TEST_TMP/.orbit" >/dev/null
  [ -f "$TEST_TMP/.orbit/learning/insights/project.jsonl" ]

  insight_clear "project" "" "$TEST_TMP/.orbit"
  [ ! -f "$TEST_TMP/.orbit/learning/insights/project.jsonl" ]
}

# ============================================================
# decisions.sh tests
# ============================================================

@test "decisions: append with proposed status" {
  local id
  id=$(decision_append "project" "" "Use IEC 62304" "Follow IEC standard" "" "project" "run-1" 1 "$TEST_TMP/.orbit")
  [[ "$id" == dec-* ]]

  [ -f "$TEST_TMP/.orbit/learning/decisions/project.jsonl" ]
  local entry
  entry=$(cat "$TEST_TMP/.orbit/learning/decisions/project.jsonl")
  echo "$entry" | jq -e '.status == "proposed"' >/dev/null
  echo "$entry" | jq -e '.title == "Use IEC 62304"' >/dev/null
  echo "$entry" | jq -e '.content == "Follow IEC standard"' >/dev/null
}

@test "decisions: accept lifecycle" {
  local id
  id=$(decision_append "project" "" "Test decision" "content" "" "project" "" 0 "$TEST_TMP/.orbit")

  decision_accept "$id" "$TEST_TMP/.orbit"

  local status
  status=$(jq -r '.status' "$TEST_TMP/.orbit/learning/decisions/project.jsonl")
  [ "$status" = "accepted" ]
}

@test "decisions: reject lifecycle" {
  local id
  id=$(decision_append "project" "" "Bad decision" "content" "" "project" "" 0 "$TEST_TMP/.orbit")

  decision_reject "$id" "$TEST_TMP/.orbit"

  local status
  status=$(jq -r '.status' "$TEST_TMP/.orbit/learning/decisions/project.jsonl")
  [ "$status" = "rejected" ]
}

@test "decisions: supersede marks old and creates new" {
  local old_id
  old_id=$(decision_append "project" "" "Old approach" "old content" "" "project" "" 0 "$TEST_TMP/.orbit")

  local new_id
  new_id=$(decision_supersede "$old_id" "New approach" "new content" "$TEST_TMP/.orbit")
  [[ "$new_id" == dec-* ]]

  # Old should be superseded
  local old_status
  old_status=$(head -1 "$TEST_TMP/.orbit/learning/decisions/project.jsonl" | jq -r '.status')
  [ "$old_status" = "superseded" ]

  # New should reference old
  local new_entry
  new_entry=$(tail -1 "$TEST_TMP/.orbit/learning/decisions/project.jsonl")
  echo "$new_entry" | jq -e '.status == "proposed"' >/dev/null
  echo "$new_entry" | jq -e --arg old "$old_id" '.supersedes == $old' >/dev/null
}

@test "decisions: read_active filters out rejected and superseded" {
  local id1 id2 id3
  id1=$(decision_append "project" "" "Active one" "c1" "" "project" "" 0 "$TEST_TMP/.orbit")
  id2=$(decision_append "project" "" "Rejected one" "c2" "" "project" "" 0 "$TEST_TMP/.orbit")
  id3=$(decision_append "project" "" "Accepted one" "c3" "" "project" "" 0 "$TEST_TMP/.orbit")

  decision_reject "$id2" "$TEST_TMP/.orbit"
  decision_accept "$id3" "$TEST_TMP/.orbit"

  run decision_read_active "project" "" "$TEST_TMP/.orbit"
  assert_success

  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]  # proposed + accepted

  [[ "$output" == *"Active one"* ]]
  [[ "$output" == *"Accepted one"* ]]
  [[ "$output" != *"Rejected one"* ]]
}

@test "decisions: assemble with status labels" {
  local id1
  id1=$(decision_append "project" "" "Decision A" "Content A" "" "project" "" 0 "$TEST_TMP/.orbit")
  decision_accept "$id1" "$TEST_TMP/.orbit"

  decision_append "project" "" "Decision B" "Content B" "" "project" "" 0 "$TEST_TMP/.orbit" >/dev/null

  run decision_assemble "" "" 20 "$TEST_TMP/.orbit"
  assert_success
  assert_output --partial "[accepted] Decision A"
  assert_output --partial "[proposed] Decision B"
}

@test "decisions: list by target" {
  decision_append "project" "" "D1" "c1" "" "project" "" 0 "$TEST_TMP/.orbit" >/dev/null
  decision_append "component" "worker" "D2" "c2" "" "component:worker" "" 0 "$TEST_TMP/.orbit" >/dev/null

  run decision_list "project" "$TEST_TMP/.orbit"
  assert_success
  [[ "$output" == *"D1"* ]]
  [[ "$output" != *"D2"* ]]

  run decision_list "component:worker" "$TEST_TMP/.orbit"
  assert_success
  [[ "$output" == *"D2"* ]]
}

@test "decisions: find by ID prefix" {
  local id
  id=$(decision_append "project" "" "Findable" "content" "" "project" "" 0 "$TEST_TMP/.orbit")
  local prefix="${id:0:8}"

  decision_accept "$prefix" "$TEST_TMP/.orbit"

  local status
  status=$(jq -r '.status' "$TEST_TMP/.orbit/learning/decisions/project.jsonl")
  [ "$status" = "accepted" ]
}

@test "decisions: mission scope file naming" {
  decision_append "mission" "implement" "Mission decision" "content" "" "mission:implement" "" 0 "$TEST_TMP/.orbit" >/dev/null
  [ -f "$TEST_TMP/.orbit/learning/decisions/mission.implement.jsonl" ]
}

# ============================================================
# parse_tags.sh tests
# ============================================================

@test "parse_tags: processes insight tags" {
  local output='<insight target="project">Test insight</insight>'
  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/.orbit/learning/insights/project.jsonl" ]
  local entry
  entry=$(cat "$TEST_TMP/.orbit/learning/insights/project.jsonl")
  echo "$entry" | jq -e '.content == "Test insight"' >/dev/null
  echo "$entry" | jq -e '.scope_kind == "project"' >/dev/null
}

@test "parse_tags: processes decision tags" {
  local output='<decision title="Use TDD" target="project">Always write tests first</decision>'
  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/.orbit/learning/decisions/project.jsonl" ]
  local entry
  entry=$(cat "$TEST_TMP/.orbit/learning/decisions/project.jsonl")
  echo "$entry" | jq -e '.title == "Use TDD"' >/dev/null
  echo "$entry" | jq -e '.content == "Always write tests first"' >/dev/null
}

@test "parse_tags: processes feedback tags" {
  local output='<feedback>Improve the validation logic</feedback>'
  parse_learning_tags "$output" "doc-drafter" "" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/components/doc-drafter/doc-drafter.feedback.jsonl" ]
  local entry
  entry=$(cat "$TEST_TMP/components/doc-drafter/doc-drafter.feedback.jsonl")
  echo "$entry" | jq -e '.content == "Improve the validation logic"' >/dev/null
  echo "$entry" | jq -e '.component == "doc-drafter"' >/dev/null
}

@test "parse_tags: processes vote tags" {
  # First create a feedback entry
  local fb_id
  fb_id=$(feedback_append "worker" "Original feedback" "$TEST_TMP")

  local output="<vote id=\"$fb_id\" weight=\"3\">Confirmed important</vote>"
  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  local votes
  votes=$(jq -r '.votes' "$TEST_TMP/components/worker/worker.feedback.jsonl")
  [ "$votes" -eq 4 ]  # initial 1 + 3
}

@test "parse_tags: mixed tags all processed" {
  local output='Some text
<insight target="project">Project insight</insight>
<feedback>Some feedback</feedback>
<decision title="Decision one" target="project">Decision content</decision>
More text'

  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/.orbit/learning/insights/project.jsonl" ]
  [ -f "$TEST_TMP/components/worker/worker.feedback.jsonl" ]
  [ -f "$TEST_TMP/.orbit/learning/decisions/project.jsonl" ]
}

@test "parse_tags: component insight routes correctly" {
  local output='<insight target="component:doc-drafter">Component-specific insight</insight>'
  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/.orbit/learning/insights/component.doc-drafter.jsonl" ]
  local entry
  entry=$(cat "$TEST_TMP/.orbit/learning/insights/component.doc-drafter.jsonl")
  echo "$entry" | jq -e '.scope_name == "doc-drafter"' >/dev/null
}

@test "parse_tags: mission insight routes correctly" {
  local output='<insight target="mission:implement">Mission insight</insight>'
  parse_learning_tags "$output" "worker" "implement" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/.orbit/learning/insights/mission.implement.jsonl" ]
}

@test "parse_tags: run-scoped insights not persisted to learning dir" {
  local output='<insight target="run">Ephemeral</insight>'
  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  [ -f "$TEST_TMP/.orbit/state/run-insights.tmp" ]
  [ ! -f "$TEST_TMP/.orbit/learning/insights/run.jsonl" ]
}

@test "parse_tags: registry validation warns on unknown component" {
  # Create a minimal registry
  mkdir -p "$TEST_TMP/project/.orbit"
  echo '{"built_at":"2024-01-01","components":{"real-worker":{}},"missions":{},"warnings":[]}' \
    > "$TEST_TMP/project/.orbit/registry.json"

  local output='<insight target="component:nonexistent">Bad target</insight>'
  run parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit" "$TEST_TMP/project"
  # Should still succeed but emit warning
  assert_success
  assert_output --partial "not found in registry"
}

@test "parse_tags: decision with supersedes attribute" {
  local old_id
  old_id=$(decision_append "project" "" "Old decision" "old content" "" "project" "" 0 "$TEST_TMP/.orbit")

  local output="<decision title=\"New decision\" target=\"project\" supersedes=\"$old_id\">New content</decision>"
  parse_learning_tags "$output" "worker" "" "" 1 "$TEST_TMP/.orbit"

  # Old should be superseded
  local old_status
  old_status=$(head -1 "$TEST_TMP/.orbit/learning/decisions/project.jsonl" | jq -r '.status')
  [ "$old_status" = "superseded" ]
}

# ============================================================
# util.sh tests
# ============================================================

@test "util: _orbit_gen_id generates prefixed IDs" {
  local id
  id=$(_orbit_gen_id "fb-" "test")
  [[ "$id" == fb-* ]]
  [ ${#id} -eq 15 ]
}

@test "util: _atomic_write creates file atomically" {
  _atomic_write "$TEST_TMP/test.txt" "hello world"
  [ -f "$TEST_TMP/test.txt" ]
  local content
  content=$(cat "$TEST_TMP/test.txt")
  [ "$content" = "hello world" ]
}

@test "util: _atomic_append_jsonl appends lines" {
  _atomic_append_jsonl "$TEST_TMP/test.jsonl" '{"a":1}'
  _atomic_append_jsonl "$TEST_TMP/test.jsonl" '{"b":2}'

  local count
  count=$(wc -l < "$TEST_TMP/test.jsonl" | tr -d ' ')
  [ "$count" -eq 2 ]
}
