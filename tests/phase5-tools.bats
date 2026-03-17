#!/usr/bin/env bats

load helpers/bats-support/load
load helpers/bats-assert/load

setup() {
  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMP="$(mktemp -d)"
  export ORBIT_LIB_DIR="$PROJECT_ROOT/lib"

  source "$PROJECT_ROOT/lib/tools/auth.sh"
  source "$PROJECT_ROOT/lib/tools/policy.sh"
  source "$PROJECT_ROOT/lib/tools/requests.sh"

  mkdir -p "$TEST_TMP/.orbit/tool-auth"
  mkdir -p "$TEST_TMP/.orbit/tool-requests"
  STATE_DIR="$TEST_TMP/.orbit"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ============================================================
# Auth key generation
# ============================================================

@test "auth: generate is deterministic (same inputs = same output)" {
  local key1 key2
  key1=$(tool_auth_generate "worker" "build-mission" "run-001")
  key2=$(tool_auth_generate "worker" "build-mission" "run-001")
  assert_equal "$key1" "$key2"
}

@test "auth: generate produces different key for different run_id" {
  local key1 key2
  key1=$(tool_auth_generate "worker" "build-mission" "run-001")
  key2=$(tool_auth_generate "worker" "build-mission" "run-002")
  [ "$key1" != "$key2" ]
}

@test "auth: generate produces different key for different component" {
  local key1 key2
  key1=$(tool_auth_generate "worker" "build-mission" "run-001")
  key2=$(tool_auth_generate "reviewer" "build-mission" "run-001")
  [ "$key1" != "$key2" ]
}

@test "auth: generated key is 64 hex characters (sha256)" {
  local key
  key=$(tool_auth_generate "worker" "build-mission" "run-001")
  # sha256 produces 64 hex chars
  [[ ${#key} -eq 64 ]]
  [[ "$key" =~ ^[0-9a-f]+$ ]]
}

# ============================================================
# Auth grant and check
# ============================================================

@test "auth: grant creates auth file with correct structure" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"

  [ -f "$STATE_DIR/tool-auth/worker.json" ]

  local comp
  comp=$(jq -r '.component' "$STATE_DIR/tool-auth/worker.json")
  assert_equal "$comp" "worker"

  local auth
  auth=$(jq -r '.auth_key' "$STATE_DIR/tool-auth/worker.json")
  assert_equal "$auth" "$key"

  local tools
  tools=$(jq -r '.granted_tools[0]' "$STATE_DIR/tool-auth/worker.json")
  assert_equal "$tools" "read-file"
}

@test "auth: grant adds tools without duplicates" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"
  tool_auth_grant "worker" "write-file" "$key" "$STATE_DIR"
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"  # duplicate

  local count
  count=$(jq '.granted_tools | length' "$STATE_DIR/tool-auth/worker.json")
  assert_equal "$count" "2"
}

@test "auth: check passes with correct key" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"

  run tool_auth_check "worker" "$key" "$STATE_DIR"
  assert_success
}

@test "auth: check fails with wrong key" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"

  run tool_auth_check "worker" "wrong-key-value" "$STATE_DIR"
  assert_failure
}

@test "auth: check fails with missing auth file" {
  run tool_auth_check "nonexistent" "some-key" "$STATE_DIR"
  assert_failure
}

@test "auth: get_granted returns tool list" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"
  tool_auth_grant "worker" "write-file" "$key" "$STATE_DIR"
  tool_auth_grant "worker" "run-tests" "$key" "$STATE_DIR"

  run tool_auth_get_granted "worker" "$STATE_DIR"
  assert_success
  assert_line --index 0 "read-file"
  assert_line --index 1 "write-file"
  assert_line --index 2 "run-tests"
}

@test "auth: get_granted returns empty for missing component" {
  run tool_auth_get_granted "nonexistent" "$STATE_DIR"
  assert_success
  assert_output ""
}

# ============================================================
# Policy flag building
# ============================================================

@test "policy: claude-code restricted builds --allowedTools flag" {
  run tool_policy_build_flags "claude-code" "restricted" "read-file,write-file"
  assert_success
  assert_output "--allowedTools read-file,write-file"
}

@test "policy: opencode restricted builds --no-auto-tools --tools flag" {
  run tool_policy_build_flags "opencode" "restricted" "read-file,write-file"
  assert_success
  assert_output "--no-auto-tools --tools read-file,write-file"
}

@test "policy: claude-code standard returns empty" {
  run tool_policy_build_flags "claude-code" "standard" "read-file,write-file"
  assert_success
  assert_output ""
}

@test "policy: opencode standard returns empty" {
  run tool_policy_build_flags "opencode" "standard" "read-file,write-file"
  assert_success
  assert_output ""
}

@test "policy: restricted with empty tools returns empty" {
  run tool_policy_build_flags "claude-code" "restricted" ""
  assert_success
  assert_output ""
}

# ============================================================
# Tool request append and list
# ============================================================

@test "request: append creates JSONL with req- prefix ID" {
  local req_id
  req_id=$(tool_request_append "worker" "apply-patch" "Need to apply fix" "run-001" "$STATE_DIR")

  [[ "$req_id" =~ ^req- ]]
  [ -f "$STATE_DIR/tool-requests/pending.jsonl" ]

  local tool
  tool=$(jq -r '.tool' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$tool" "apply-patch"

  local status
  status=$(jq -r '.status' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$status" "pending"
}

@test "request: append generates unique IDs" {
  local id1 id2
  id1=$(tool_request_append "worker" "tool-a" "reason a" "run-001" "$STATE_DIR")
  id2=$(tool_request_append "worker" "tool-b" "reason b" "run-001" "$STATE_DIR")
  [ "$id1" != "$id2" ]
}

@test "request: list_pending shows human-readable output" {
  tool_request_append "worker" "apply-patch" "Need to apply fix" "run-001" "$STATE_DIR" >/dev/null
  tool_request_append "reviewer" "restart-service" "Service needs restart" "run-002" "$STATE_DIR" >/dev/null

  run tool_request_list_pending "$STATE_DIR"
  assert_success
  assert_output --partial "apply-patch"
  assert_output --partial "worker"
  assert_output --partial "restart-service"
  assert_output --partial "reviewer"
}

@test "request: list_pending shows message when no requests" {
  run tool_request_list_pending "$STATE_DIR"
  assert_success
  assert_output "No pending tool requests."
}

# ============================================================
# Tool request grant and deny
# ============================================================

@test "request: grant updates status and creates auth entry" {
  local req_id key
  req_id=$(tool_request_append "worker" "apply-patch" "Need it" "run-001" "$STATE_DIR")
  key=$(tool_auth_generate "worker" "my-mission" "run-001")

  run tool_request_grant "$req_id" "worker" "$STATE_DIR" "$key"
  assert_success

  # Check pending.jsonl updated
  local status
  status=$(jq -r '.status' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$status" "granted"

  # Check auth file created
  [ -f "$STATE_DIR/tool-auth/worker.json" ]
  local granted_tool
  granted_tool=$(jq -r '.granted_tools[0]' "$STATE_DIR/tool-auth/worker.json")
  assert_equal "$granted_tool" "apply-patch"
}

@test "request: grant by tool name matches component" {
  tool_request_append "worker" "apply-patch" "Need it" "run-001" "$STATE_DIR" >/dev/null
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")

  run tool_request_grant "apply-patch" "worker" "$STATE_DIR" "$key"
  assert_success

  local status
  status=$(jq -r '.status' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$status" "granted"
}

@test "request: deny updates status and writes denied.jsonl" {
  local req_id
  req_id=$(tool_request_append "worker" "apply-patch" "Need it" "run-001" "$STATE_DIR")

  run tool_request_deny "$req_id" "worker" "Not approved for this mission" "$STATE_DIR"
  assert_success

  # Check pending.jsonl updated
  local status
  status=$(jq -r '.status' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$status" "denied"

  # Check denied.jsonl exists and has entry
  [ -f "$STATE_DIR/tool-requests/denied.jsonl" ]
  local reason
  reason=$(jq -r '.reason' "$STATE_DIR/tool-requests/denied.jsonl")
  assert_equal "$reason" "Not approved for this mission"
}

@test "request: deny by tool name matches component" {
  tool_request_append "worker" "apply-patch" "Need it" "run-001" "$STATE_DIR" >/dev/null

  run tool_request_deny "apply-patch" "worker" "Denied" "$STATE_DIR"
  assert_success

  local status
  status=$(jq -r '.status' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$status" "denied"
}

@test "request: grant fails for nonexistent request" {
  run tool_request_grant "nonexistent" "worker" "$STATE_DIR"
  assert_failure
}

# ============================================================
# Tool request tag parsing
# ============================================================

@test "request: parse_tags extracts single tool request" {
  local output='Some output <tool_request><tool>apply-patch</tool><justification>Need to apply remediation</justification></tool_request> more output'

  run tool_request_parse_tags "$output" "worker" "run-001" "$STATE_DIR"
  assert_success
  assert_output "1"

  [ -f "$STATE_DIR/tool-requests/pending.jsonl" ]
  local tool
  tool=$(jq -r '.tool' "$STATE_DIR/tool-requests/pending.jsonl")
  assert_equal "$tool" "apply-patch"
}

@test "request: parse_tags extracts multiple tool requests" {
  local output='<tool_request><tool>apply-patch</tool><justification>Fix needed</justification></tool_request> text <tool_request><tool>restart-service</tool><justification>Service down</justification></tool_request>'

  run tool_request_parse_tags "$output" "worker" "run-001" "$STATE_DIR"
  assert_success
  assert_output "2"

  local count
  count=$(wc -l < "$STATE_DIR/tool-requests/pending.jsonl" | tr -d ' ')
  assert_equal "$count" "2"
}

@test "request: parse_tags returns 0 when no tags present" {
  local output='Just regular output with no tool requests'

  run tool_request_parse_tags "$output" "worker" "run-001" "$STATE_DIR"
  assert_success
  assert_output "0"
}

# ============================================================
# Standalone auth-check script
# ============================================================

@test "auth-check: passes with valid key" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"

  cd "$TEST_TMP"
  export ORBIT_TOOL_AUTH_KEY="$key"
  export ORBIT_COMPONENT="worker"
  run "$PROJECT_ROOT/scripts/_auth-check.sh"
  assert_success
}

@test "auth-check: fails with no auth key" {
  cd "$TEST_TMP"
  export ORBIT_TOOL_AUTH_KEY=""
  export ORBIT_COMPONENT="worker"
  run "$PROJECT_ROOT/scripts/_auth-check.sh"
  assert_failure
  assert_output --partial "DENIED"
}

@test "auth-check: fails with wrong key" {
  local key
  key=$(tool_auth_generate "worker" "my-mission" "run-001")
  tool_auth_grant "worker" "read-file" "$key" "$STATE_DIR"

  cd "$TEST_TMP"
  export ORBIT_TOOL_AUTH_KEY="wrong-key"
  export ORBIT_COMPONENT="worker"
  run "$PROJECT_ROOT/scripts/_auth-check.sh"
  assert_failure
  assert_output --partial "DENIED"
}

@test "auth-check: fails with no component" {
  cd "$TEST_TMP"
  export ORBIT_TOOL_AUTH_KEY="some-key"
  export ORBIT_COMPONENT=""
  run "$PROJECT_ROOT/scripts/_auth-check.sh"
  assert_failure
  assert_output --partial "DENIED"
}

@test "auth-check: fails with missing auth file" {
  cd "$TEST_TMP"
  export ORBIT_TOOL_AUTH_KEY="some-key"
  export ORBIT_COMPONENT="nonexistent"
  run "$PROJECT_ROOT/scripts/_auth-check.sh"
  assert_failure
  assert_output --partial "DENIED"
}
