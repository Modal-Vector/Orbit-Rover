#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMP="$(mktemp -d)"
  export ORBIT_LIB_DIR="$PROJECT_ROOT/lib"
  export ORBIT_ROOT="$PROJECT_ROOT"

  # Source all lib files (same as orbit binary does)
  source "$PROJECT_ROOT/lib/util.sh"
  source "$PROJECT_ROOT/lib/extract.sh"
  source "$PROJECT_ROOT/lib/template.sh"
  source "$PROJECT_ROOT/lib/hash.sh"
  source "$PROJECT_ROOT/lib/yaml.sh"
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/registry.sh"
  source "$PROJECT_ROOT/lib/orbit_loop.sh"
  source "$PROJECT_ROOT/lib/sensors/cascade.sh"
  source "$PROJECT_ROOT/lib/sensors/schedule.sh"
  source "$PROJECT_ROOT/lib/sensors/file_watch.sh"
  source "$PROJECT_ROOT/lib/learning/feedback.sh"
  source "$PROJECT_ROOT/lib/learning/insights.sh"
  source "$PROJECT_ROOT/lib/learning/decisions.sh"
  source "$PROJECT_ROOT/lib/learning/parse_tags.sh"
  source "$PROJECT_ROOT/lib/tools/auth.sh"
  source "$PROJECT_ROOT/lib/tools/policy.sh"
  source "$PROJECT_ROOT/lib/tools/requests.sh"
  source "$PROJECT_ROOT/lib/manual_gate.sh"
  source "$PROJECT_ROOT/lib/flight_rules.sh"
  source "$PROJECT_ROOT/lib/waypoints.sh"
  source "$PROJECT_ROOT/lib/retry.sh"

  # Source all cmd files
  for cmd_file in "$PROJECT_ROOT"/cmd/*.sh; do
    [[ -f "$cmd_file" ]] && source "$cmd_file"
  done

  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# Helper: set up a test project with fixture files
_setup_fixture_project() {
  mkdir -p "$TEST_TMP/components" "$TEST_TMP/missions" "$TEST_TMP/.orbit"
  cp "$PROJECT_ROOT/tests/fixtures/orbit.yaml" "$TEST_TMP/orbit.yaml"
  cp "$PROJECT_ROOT/tests/fixtures/component-worker.yaml" "$TEST_TMP/components/worker.yaml"
  cp "$PROJECT_ROOT/tests/fixtures/component-minimal.yaml" "$TEST_TMP/components/minimal.yaml"
  cp "$PROJECT_ROOT/tests/fixtures/mission-implement.yaml" "$TEST_TMP/missions/implement.yaml"
  config_load_system "$TEST_TMP/orbit.yaml"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
}

# ============================================================
# Init
# ============================================================

@test "init: creates orbit.yaml" {
  cd "$TEST_TMP"
  cmd_init "test-project"
  [ -f "$TEST_TMP/orbit.yaml" ]
}

@test "init: creates .orbit state directories" {
  cd "$TEST_TMP"
  cmd_init "test-project"
  [ -d "$TEST_TMP/.orbit/state" ]
  [ -d "$TEST_TMP/.orbit/runs" ]
  [ -d "$TEST_TMP/.orbit/learning/insights" ]
  [ -d "$TEST_TMP/.orbit/learning/decisions" ]
  [ -d "$TEST_TMP/.orbit/manual" ]
  [ -d "$TEST_TMP/.orbit/tool-auth" ]
  [ -d "$TEST_TMP/.orbit/triggers" ]
  [ -d "$TEST_TMP/.orbit/logs" ]
}

@test "init: creates project directories" {
  cd "$TEST_TMP"
  cmd_init "test-project"
  [ -d "$TEST_TMP/components" ]
  [ -d "$TEST_TMP/missions" ]
  [ -d "$TEST_TMP/modules" ]
  [ -d "$TEST_TMP/tools" ]
}

@test "init: creates template files" {
  cd "$TEST_TMP"
  cmd_init "test-project"
  [ -f "$TEST_TMP/CLAUDE.md" ]
  [ -f "$TEST_TMP/RISK-REGISTRY.md" ]
  [ -f "$TEST_TMP/tools/INDEX.md" ]
}

@test "init: errors if orbit.yaml already exists" {
  cd "$TEST_TMP"
  echo "system: orbit" > "$TEST_TMP/orbit.yaml"
  run cmd_init "test-project"
  assert_failure
  assert_output --partial "already exists"
}

@test "init: uses project name in CLAUDE.md" {
  cd "$TEST_TMP"
  cmd_init "my-cool-project"
  run cat "$TEST_TMP/CLAUDE.md"
  assert_output --partial "my-cool-project"
}

# ============================================================
# Doctor
# ============================================================

@test "doctor: exits 0 with bash 4+ and jq" {
  run cmd_doctor
  assert_success
  assert_output --partial "[OK]"
}

@test "doctor: shows OK and WARN format" {
  run cmd_doctor
  assert_output --partial "[OK]"
  # At least one optional tool might be missing
  [[ "$output" == *"[OK]"* ]] || [[ "$output" == *"[WARN]"* ]]
}

@test "doctor: reports bash version" {
  run cmd_doctor
  assert_output --partial "bash"
}

# ============================================================
# Trigger
# ============================================================

@test "trigger: creates trigger file" {
  mkdir -p "$TEST_TMP/.orbit/triggers"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  cmd_trigger "my-component"
  [ -f "$TEST_TMP/.orbit/triggers/my-component-manual" ]
}

@test "trigger: errors on missing name" {
  run cmd_trigger
  assert_failure
  assert_output --partial "Usage"
}

# ============================================================
# Cron
# ============================================================

@test "cron: list with no cron entries" {
  # Use a mock crontab that returns empty
  export PATH="$PROJECT_ROOT/tests/fixtures:$PATH"
  run cmd_cron list
  assert_success
}

@test "cron: preview scans registry for cron schedules" {
  _setup_fixture_project
  cd "$TEST_TMP"
  registry_build "$TEST_TMP"
  run cmd_cron preview
  assert_success
  assert_output --partial "Planned cron entries"
}

@test "cron: errors on unknown subcommand" {
  run cmd_cron badcmd
  assert_failure
  assert_output --partial "Unknown subcommand"
}

# ============================================================
# Status
# ============================================================

@test "status: shows status with empty state" {
  mkdir -p "$TEST_TMP/.orbit"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_status
  assert_success
  assert_output --partial "Last run"
  assert_output --partial "Active sensors"
  assert_output --partial "Pending gates"
}

@test "status: shows populated state" {
  mkdir -p "$TEST_TMP/.orbit/runs/run-abc123/stages"
  echo '{"mission":"test","status":"complete"}' > "$TEST_TMP/.orbit/runs/run-abc123/mission.json"
  echo '{"name":"stage1","status":"complete"}' > "$TEST_TMP/.orbit/runs/run-abc123/stages/stage1.json"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_status
  assert_success
  assert_output --partial "run-abc123"
}

@test "status: mission-specific shows stages" {
  mkdir -p "$TEST_TMP/.orbit/runs/run-abc123/stages"
  echo '{"mission":"implement","status":"complete"}' > "$TEST_TMP/.orbit/runs/run-abc123/mission.json"
  echo '{"name":"decompose","status":"complete"}' > "$TEST_TMP/.orbit/runs/run-abc123/stages/decompose.json"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_status implement
  assert_success
  assert_output --partial "decompose"
  assert_output --partial "complete"
}

# ============================================================
# Registry
# ============================================================

@test "registry: shows components and missions" {
  _setup_fixture_project
  cd "$TEST_TMP"
  run cmd_registry
  assert_success
  assert_output --partial "worker"
  assert_output --partial "implement"
}

@test "registry: shows empty registry" {
  mkdir -p "$TEST_TMP/components" "$TEST_TMP/missions" "$TEST_TMP/.orbit"
  cp "$PROJECT_ROOT/tests/fixtures/orbit.yaml" "$TEST_TMP/orbit.yaml"
  # Remove component files to get empty registry
  rm -f "$TEST_TMP/components"/*
  rm -f "$TEST_TMP/missions"/*
  cd "$TEST_TMP"
  config_load_system "$TEST_TMP/orbit.yaml"
  run cmd_registry
  assert_success
  assert_output --partial "(none)"
}

# ============================================================
# Log
# ============================================================

@test "log: no logs shows message" {
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_log
  assert_success
  assert_output --partial "No log entries"
}

@test "log: formats JSONL entries" {
  mkdir -p "$TEST_TMP/.orbit/logs"
  echo '{"timestamp":"2026-03-10T12:00:00Z","level":"info","event":"test","message":"hello world"}' > "$TEST_TMP/.orbit/logs/2026-03-10.jsonl"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_log
  assert_success
  assert_output --partial "2026-03-10T12:00:00Z"
  assert_output --partial "info"
  assert_output --partial "hello world"
}

@test "log: --tail N limits output" {
  mkdir -p "$TEST_TMP/.orbit/logs"
  for i in 1 2 3 4 5; do
    echo "{\"timestamp\":\"2026-03-10T12:0${i}:00Z\",\"level\":\"info\",\"event\":\"test\",\"message\":\"msg ${i}\"}" >> "$TEST_TMP/.orbit/logs/2026-03-10.jsonl"
  done
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_log --tail 2
  assert_success
  assert_output --partial "msg 4"
  assert_output --partial "msg 5"
  refute_output --partial "msg 1"
}

# ============================================================
# Launch --dry-run
# ============================================================

@test "launch --dry-run: prints execution plan" {
  _setup_fixture_project
  cd "$TEST_TMP"
  # Need task-decomposer component for mission validation
  cat > "$TEST_TMP/components/task-decomposer.yaml" <<'EOF'
component: task-decomposer
status: active
prompt: prompts/decomposer.md
orbits:
  max: 5
  success:
    when: file
    condition: output/tasks.json
EOF
  registry_build "$TEST_TMP"
  run cmd_launch implement --dry-run
  assert_success
  assert_output --partial "Execution Plan"
  assert_output --partial "decompose"
  assert_output --partial "work"
}

@test "launch --dry-run: does not write state" {
  _setup_fixture_project
  cd "$TEST_TMP"
  cat > "$TEST_TMP/components/task-decomposer.yaml" <<'EOF'
component: task-decomposer
status: active
prompt: prompts/decomposer.md
orbits:
  max: 5
  success:
    when: file
    condition: output/tasks.json
EOF
  registry_build "$TEST_TMP"
  cmd_launch implement --dry-run
  # No runs directory should be populated
  if [[ -d "$TEST_TMP/.orbit/runs" ]]; then
    local run_count
    run_count=$(ls -1 "$TEST_TMP/.orbit/runs/" 2>/dev/null | wc -l | tr -d ' ')
    [ "$run_count" -eq 0 ]
  fi
}

@test "launch --dry-run: validates components exist" {
  _setup_fixture_project
  cd "$TEST_TMP"
  # Mission references task-decomposer which doesn't exist
  registry_build "$TEST_TMP"
  run cmd_launch implement --dry-run
  assert_failure
  assert_output --partial "not found in registry"
}

# ============================================================
# Argument parsing
# ============================================================

@test "args: --dry-run flag is parsed" {
  _setup_fixture_project
  cd "$TEST_TMP"
  cat > "$TEST_TMP/components/task-decomposer.yaml" <<'EOF'
component: task-decomposer
status: active
prompt: prompts/decomposer.md
orbits:
  max: 5
  success:
    when: file
    condition: output/tasks.json
EOF
  registry_build "$TEST_TMP"
  run cmd_launch implement --dry-run
  assert_success
  assert_output --partial "Execution Plan"
}

@test "args: --params flag is parsed by run" {
  # Just test the parsing, not execution (would need mock adapter)
  run cmd_run nonexistent-module --params '{"key":"val"}'
  assert_failure
  # It should fail on "not found", not on parsing
  assert_output --partial "not found"
}

@test "args: --tail flag is parsed by log" {
  mkdir -p "$TEST_TMP/.orbit/logs"
  echo '{"timestamp":"2026-03-10T12:00:00Z","level":"info","event":"test","message":"msg1"}' > "$TEST_TMP/.orbit/logs/2026-03-10.jsonl"
  echo '{"timestamp":"2026-03-10T12:01:00Z","level":"info","event":"test","message":"msg2"}' >> "$TEST_TMP/.orbit/logs/2026-03-10.jsonl"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_log --tail 1
  assert_success
  assert_output --partial "msg2"
  refute_output --partial "msg1"
}

@test "args: --target flag is parsed by decisions" {
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  mkdir -p "$TEST_TMP/.orbit/learning/decisions"
  run cmd_decisions list --target project
  assert_success
  assert_output --partial "No decisions"
}

# ============================================================
# Learning
# ============================================================

@test "decisions: list returns entries" {
  mkdir -p "$TEST_TMP/.orbit/learning/decisions"
  local entry
  entry=$(jq -nc '{id:"dec-abc","scope_kind":"project","scope_name":"","title":"Use TDD","content":"Test first","status":"proposed","created_at":"2026-03-10T00:00:00Z"}')
  echo "$entry" > "$TEST_TMP/.orbit/learning/decisions/project.jsonl"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_decisions list --target project
  assert_success
  assert_output --partial "Use TDD"
}

@test "insights: read shows entries" {
  mkdir -p "$TEST_TMP/.orbit/learning/insights"
  local entry
  entry=$(jq -nc '{id:"ins-abc","scope_kind":"project","scope_name":"","content":"important insight","created_at":"2026-03-10T00:00:00Z"}')
  echo "$entry" > "$TEST_TMP/.orbit/learning/insights/project.jsonl"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_insights project
  assert_success
  assert_output --partial "important insight"
}

@test "feedback: read shows entries" {
  mkdir -p "$TEST_TMP/components/worker"
  local entry
  entry=$(jq -nc '{id:"fb-abc","component":"worker","content":"great work","votes":3,"created_at":"2026-03-10T00:00:00Z"}')
  echo "$entry" > "$TEST_TMP/components/worker/worker.feedback.jsonl"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_feedback worker
  assert_success
  assert_output --partial "great work"
}

# ============================================================
# Tools
# ============================================================

@test "tools: pending with no requests" {
  mkdir -p "$TEST_TMP/.orbit/tool-requests"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_tools pending
  assert_success
  assert_output --partial "No pending"
}

@test "tools: pending shows requests" {
  mkdir -p "$TEST_TMP/.orbit/tool-requests"
  local entry
  entry=$(jq -nc '{id:"req-abc","component":"worker","tool":"apply-patch","status":"pending","requested_at":"2026-03-10T00:00:00Z","justification":"need it"}')
  echo "$entry" > "$TEST_TMP/.orbit/tool-requests/pending.jsonl"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_tools pending
  assert_success
  assert_output --partial "apply-patch"
}

# ============================================================
# Gates
# ============================================================

@test "pending: shows no gates when empty" {
  mkdir -p "$TEST_TMP/.orbit/manual"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  run cmd_pending
  assert_success
  assert_output --partial "No pending gates"
}

@test "approve: creates response.json" {
  mkdir -p "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate"
  echo '{"gate_id":"test-gate","prompt":"Review this"}' > "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate/prompt.json"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  cmd_approve test-gate
  [ -f "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate/response.json" ]
  run jq -r '.option' "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate/response.json"
  assert_output "approve"
}

@test "reject: creates rejection response.json" {
  mkdir -p "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate"
  echo '{"gate_id":"test-gate","prompt":"Review this"}' > "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate/prompt.json"
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  cmd_reject test-gate
  [ -f "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate/response.json" ]
  run jq -r '.option' "$TEST_TMP/.orbit/runs/run-cli/manual/test-gate/response.json"
  assert_output "reject"
}

# ============================================================
# Log event helper
# ============================================================

@test "log event: writes JSONL to logs directory" {
  export ORBIT_STATE_DIR="$TEST_TMP/.orbit"
  # Define _orbit_log_event inline (it's defined in orbit binary, not in lib/)
  _orbit_log_event() {
    local level="$1" event="$2" message="$3"
    local state_dir="${ORBIT_STATE_DIR:-.orbit}"
    local log_dir="${state_dir}/logs"
    mkdir -p "$log_dir"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local date_str; date_str=$(date -u +"%Y-%m-%d")
    local entry; entry=$(jq -nc --arg ts "$ts" --arg level "$level" --arg event "$event" --arg msg "$message" '{timestamp: $ts, level: $level, event: $event, message: $msg}')
    _atomic_append_jsonl "${log_dir}/${date_str}.jsonl" "$entry"
  }
  _orbit_log_event "info" "test.event" "hello from test"
  local log_file
  log_file=$(ls "$TEST_TMP/.orbit/logs/"*.jsonl 2>/dev/null | head -1)
  [ -f "$log_file" ]
  run jq -r '.message' "$log_file"
  assert_output "hello from test"
}
