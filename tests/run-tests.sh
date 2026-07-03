#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATION_TEST_DIR="${ROOT_DIR}/tests/validation"
RESOLVER_TEST_DIR="${ROOT_DIR}/tests/resolver"
PLANNER_TEST_DIR="${ROOT_DIR}/tests/planner"
POLICY_TEST_DIR="${ROOT_DIR}/tests/policy"
DRYRUN_TEST_DIR="${ROOT_DIR}/tests/dryrun"
DOCTOR_TEST_DIR="${ROOT_DIR}/tests/doctor"
HEALTH_TEST_DIR="${ROOT_DIR}/tests/health"
READINESS_TEST_DIR="${ROOT_DIR}/tests/readiness"
PLUGIN_TEST_DIR="${ROOT_DIR}/tests/plugins"
PROFILE_TEST_DIR="${ROOT_DIR}/tests/profiles"
EXECUTOR_TEST_DIR="${ROOT_DIR}/tests/executor"
RELEASE_TEST_DIR="${ROOT_DIR}/tests/releases"
ROLLBACK_TEST_DIR="${ROOT_DIR}/tests/rollback"
MEL="${ROOT_DIR}/deploy/bin/mel"

export MEL_RELEASE_TIMESTAMP=20260703194512

# shellcheck source=../deploy/lib/planner.sh
. "${ROOT_DIR}/deploy/lib/planner.sh"
# shellcheck source=../deploy/lib/health.sh
. "${ROOT_DIR}/deploy/lib/health.sh"
# shellcheck source=../deploy/lib/plugins.sh
. "${ROOT_DIR}/deploy/lib/plugins.sh"
# shellcheck source=../deploy/lib/release_manifest.sh
. "${ROOT_DIR}/deploy/lib/release_manifest.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok - %s\n' "$1"
  printf '  %s\n' "$2"
}

assert_exit() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit ${expected}, got ${actual}"
  fi
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected output to contain: ${needle}"
  fi
}

assert_file_equals() {
  local name="$1"
  local expected_file="$2"
  local actual_file="$3"
  local expected
  local actual

  expected="$(<"$expected_file")"
  actual="$(<"$actual_file")"

  if [[ "$actual" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "resolved JSON did not match ${expected_file}"
  fi
}

assert_json_contains() {
  local name="$1"
  local file="$2"
  local key="$3"
  local expected="$4"
  local status

  python3 - "$file" "$key" "$expected" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    value = value[part]
if str(value) != sys.argv[3]:
    print(f"expected {sys.argv[2]} to be {sys.argv[3]}, got {value}")
    sys.exit(2)
PY
  status=$?

  assert_exit "$name" 0 "$status"
}

assert_symlink_target() {
  local name="$1"
  local link="$2"
  local expected="$3"
  local status

  python3 - "$link" "$expected" <<'PY'
import os
import sys

link, expected = sys.argv[1:3]
if not os.path.islink(link):
    print(f"{link} is not a symlink")
    sys.exit(2)
if os.path.realpath(link) != os.path.realpath(expected):
    print(f"{link} points to {os.path.realpath(link)}, expected {os.path.realpath(expected)}")
    sys.exit(2)
PY
  status=$?

  assert_exit "$name" 0 "$status"
}

run_command() {
  local output_file="$1"
  shift

  "$@" >"$output_file" 2>&1
}

executor_fixture() {
  local name="$1"
  local composer_status="${2:-passed}"
  local drush_status="${3:-passed}"
  local health_status="${4:-passed}"
  local doctor_mode="${5:-mock}"
  local require_shared="${6:-false}"
  local root="${EXECUTOR_TEST_DIR}/.tmp-${name}/staging"
  local manifest_file="${EXECUTOR_TEST_DIR}/.tmp-${name}/manifest.json"
  local profile_file="${EXECUTOR_TEST_DIR}/.tmp-${name}/profile.json"

  rm -rf "${EXECUTOR_TEST_DIR}/.tmp-${name}"
  mkdir -p "$root/repo" "$root/releases/previous" "$root/releases" "$root/shared" "$root/logs"
  printf 'runtime\n' >"$root/repo/index.php"
  ln -s "$root/releases/previous" "$root/current"

  if [[ "$require_shared" == "present" ]]; then
    mkdir -p "$root/shared/files"
  fi

  cat >"$manifest_file" <<EOF
{
  "schema": "mel-deployment.manifest.v1",
  "name": "mel-staging",
  "repository": {
    "name": "myeventlane-platform",
    "root": "$root",
    "url": "git@github.com:anna-pye/myeventlane-platform.git",
    "branch": "staging"
  },
  "environment": "staging",
  "release": {
    "strategy": "timestamp",
    "identifier": "20260703194512"
  },
  "paths": {},
  "validation_profile": "staging"
}
EOF

  local shared_resources="[]"
  if [[ "$require_shared" != "false" ]]; then
    shared_resources='[{"name":"files","target":"web/sites/default/files","type":"directory"}]'
  fi

  local http_status=200
  if [[ "$health_status" == "failed" ]]; then
    http_status=500
  fi

  cat >"$profile_file" <<EOF
{
  "profile": "staging",
  "environment": "staging",
  "validation_profile": "staging",
  "policy_profile": "staging",
  "deployment_root": "$root",
  "required_approvals": [],
  "shared_resources": $shared_resources,
  "plugins": {
    "composer": {"mode": "mock", "status": "$composer_status"},
    "drush": {"mode": "mock", "status": "$drush_status"},
    "health": {"mode": "mock", "status": "passed"},
    "shared": {"mode": "mock", "status": "passed"},
    "switch_current": {"mode": "mock", "status": "passed"}
  },
  "health_state": {
    "staging_http_response": $http_status
  },
  "health_checks": [
    {"name": "staging_http_response", "type": "http_response", "required": true},
    {"name": "staging_drupal_status", "type": "drupal_status_endpoint", "required": true}
  ],
  "doctor_checks": [
    {"name": "directory_layout", "type": "directory_layout", "mode": "$doctor_mode"}
  ]
}
EOF

  printf '%s\t%s\t%s\n' "$root" "$manifest_file" "$profile_file"
}

readiness_fixture() {
  local name="$1"
  local layout="${2:-valid}"
  local health_status="${3:-passed}"
  local doctor_mode="${4:-profile}"
  local root="${READINESS_TEST_DIR}/.tmp-${name}/staging"
  local profile_file="${READINESS_TEST_DIR}/.tmp-${name}/profile.json"

  rm -rf "${READINESS_TEST_DIR}/.tmp-${name}"
  mkdir -p "$root/releases/previous" "$root/shared/files" "$root/logs"
  ln -s "$root/releases/previous" "$root/current"

  if [[ "$layout" == "missing-releases" ]]; then
    rm -rf "$root/releases"
  elif [[ "$layout" == "missing-shared" ]]; then
    rm -rf "$root/shared/files"
  elif [[ "$layout" == "broken-current" ]]; then
    rm -f "$root/current"
    ln -s "$root/releases/missing" "$root/current"
  fi

  local http_status=200
  if [[ "$health_status" == "failed" ]]; then
    http_status=500
  fi

  cat >"$profile_file" <<EOF
{
  "profile": "staging",
  "profile_version": "1",
  "environment": "staging",
  "validation_profile": "staging",
  "policy_profile": "staging",
  "deployment_root": "$root",
  "repository": "git@github.com:anna-pye/myeventlane-platform.git",
  "ssh": {
    "host": "staging",
    "user": "mel"
  },
  "paths": {
    "releases": "$root/releases",
    "shared": "$root/shared",
    "current": "$root/current",
    "logs": "$root/logs"
  },
  "executables": {
    "php": "php",
    "composer": "composer",
    "drush": "drush"
  },
  "verification": {
    "mode": "local"
  },
  "required_approvals": [],
  "shared_resources": [
    {"name": "files", "target": "web/sites/default/files", "type": "directory"}
  ],
  "health_endpoints": [],
  "health_state": {
    "staging_http_response": $http_status
  },
  "health_checks": [
    {"name": "staging_http_response", "type": "http_response", "required": true},
    {"name": "staging_drupal_status", "type": "drupal_status_endpoint", "required": true},
    {"name": "staging_current", "type": "current_symlink", "link": "$root/current", "target": "$root/releases/previous", "required": true}
  ],
  "doctor_checks": [
    {"name": "ssh_connectivity", "type": "ssh_connectivity", "mode": "$doctor_mode"},
    {"name": "deployment_root", "type": "deployment_root_exists", "mode": "profile"},
    {"name": "releases", "type": "releases_exists", "mode": "profile"},
    {"name": "shared", "type": "shared_exists", "mode": "profile"},
    {"name": "current", "type": "current_exists", "mode": "profile"},
    {"name": "logs", "type": "logs_exists", "mode": "profile"},
    {"name": "composer_availability", "type": "composer_availability", "mode": "profile"},
    {"name": "drush_availability", "type": "drush_availability", "mode": "profile"},
    {"name": "writable_release_root", "type": "writable_release_root", "mode": "profile"},
    {"name": "readable_shared_resources", "type": "readable_shared_resources", "mode": "profile"}
  ]
}
EOF

  printf '%s\t%s\n' "$root" "$profile_file"
}

test_valid_manifest() {
  local output_file="${VALIDATION_TEST_DIR}/.valid.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${VALIDATION_TEST_DIR}/fixtures/valid-manifest.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "valid manifest exits success" 0 "$status"
  assert_contains "valid manifest reports success" "$output" "[success] MEL_OK: validation passed"
}

test_invalid_manifest() {
  local output_file="${VALIDATION_TEST_DIR}/.invalid-manifest.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${VALIDATION_TEST_DIR}/fixtures/invalid-manifest.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "invalid manifest exits error" 2 "$status"
  assert_contains "invalid manifest reports structured error" "$output" "[error] MEL_MANIFEST_INVALID:"
}

test_invalid_path() {
  local output_file="${VALIDATION_TEST_DIR}/.invalid-path.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${VALIDATION_TEST_DIR}/fixtures/invalid-path.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "invalid path exits error" 2 "$status"
  assert_contains "invalid path reports structured error" "$output" "[error] MEL_PATH_INVALID:"
}

test_malformed_schema() {
  local output_file="${VALIDATION_TEST_DIR}/.malformed-schema.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${VALIDATION_TEST_DIR}/fixtures/valid-manifest.json" --schema "${VALIDATION_TEST_DIR}/fixtures/malformed-schema.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "malformed schema exits error" 2 "$status"
  assert_contains "malformed schema reports structured error" "$output" "[error] MEL_SCHEMA_MALFORMED:"
}

test_cli_exit_codes() {
  local output_file="${VALIDATION_TEST_DIR}/.cli-exit.out"
  local status
  local output

  run_command "$output_file" "$MEL" unknown-command
  status=$?
  output="$(<"$output_file")"

  assert_exit "unknown command exits error" 2 "$status"
  assert_contains "unknown command reports argument error" "$output" "[error] MEL_ARGUMENT_ERROR:"
}

test_version() {
  local output_file="${VALIDATION_TEST_DIR}/.version.out"
  local status
  local output

  run_command "$output_file" "$MEL" version
  status=$?
  output="$(<"$output_file")"

  assert_exit "mel version exits success" 0 "$status"
  assert_contains "mel version reports repository version" "$output" "0.1.0-dev"
}

test_info() {
  local output_file="${VALIDATION_TEST_DIR}/.info.out"
  local status
  local output

  run_command "$output_file" "$MEL" info
  status=$?
  output="$(<"$output_file")"

  assert_exit "mel info exits success" 0 "$status"
  assert_contains "mel info reports engine" "$output" "mel validation, resolution, and planner engine"
  assert_contains "mel info reports repository" "$output" "repository:"
}

test_successful_resolution() {
  local output_file="${RESOLVER_TEST_DIR}/.success.out"
  local status

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/success-manifest.json"
  status=$?

  assert_exit "resolver exits success" 0 "$status"
  assert_file_equals "resolver produces stable JSON" "${RESOLVER_TEST_DIR}/fixtures/expected-success.json" "$output_file"
}

test_default_resolution() {
  local output_file="${RESOLVER_TEST_DIR}/.defaults.out"
  local status

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/defaults-manifest.json"
  status=$?

  assert_exit "resolver applies documented defaults" 0 "$status"
  assert_file_equals "resolver default output is canonical" "${RESOLVER_TEST_DIR}/fixtures/expected-success.json" "$output_file"
}

test_missing_required_values() {
  local output_file="${RESOLVER_TEST_DIR}/.missing-required.out"
  local status
  local output

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/missing-required.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "resolver rejects missing required values" 2 "$status"
  assert_contains "resolver reports missing repository URL" "$output" "[error] MEL_RESOLUTION_INVALID: manifest.repository.url is required"
}

test_conflicting_configuration() {
  local output_file="${RESOLVER_TEST_DIR}/.conflicting-paths.out"
  local status
  local output

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/conflicting-paths.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "resolver rejects conflicting configuration" 2 "$status"
  assert_contains "resolver reports conflicting paths" "$output" "[error] MEL_RESOLUTION_INVALID: conflicting path definitions"
}

test_duplicate_deployment_ids() {
  local output_file="${RESOLVER_TEST_DIR}/.duplicate-deployment-ids.out"
  local status
  local output

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/duplicate-deployment-ids.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "resolver rejects duplicate deployment IDs" 2 "$status"
  assert_contains "resolver reports duplicate deployment ID" "$output" "[error] MEL_RESOLUTION_INVALID: duplicate deployment identifier: hold-production"
}

test_unsupported_environment() {
  local output_file="${RESOLVER_TEST_DIR}/.unsupported-environment.out"
  local status
  local output

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/unsupported-environment.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "resolver rejects unsupported environments" 2 "$status"
  assert_contains "resolver reports unsupported environment" "$output" "[error] MEL_RESOLUTION_INVALID: unsupported environment: prod"
}

test_unsupported_release_strategy() {
  local output_file="${RESOLVER_TEST_DIR}/.unsupported-release-strategy.out"
  local status
  local output

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/unsupported-release-strategy.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "resolver rejects unsupported release strategies" 2 "$status"
  assert_contains "resolver reports unsupported release strategy" "$output" "[error] MEL_RESOLUTION_INVALID: unsupported release strategy: latest"
}

test_output_option() {
  local output_file="${RESOLVER_TEST_DIR}/.output-option.out"
  local resolved_file="${RESOLVER_TEST_DIR}/.resolved.json"
  local status
  local output

  run_command "$output_file" "$MEL" resolve --manifest "${RESOLVER_TEST_DIR}/fixtures/success-manifest.json" --output "$resolved_file"
  status=$?
  output="$(<"$output_file")"

  assert_exit "resolver output option exits success" 0 "$status"
  assert_contains "resolver output option reports success" "$output" "[success] MEL_OK: resolution written"
  assert_file_equals "resolver output file is stable JSON" "${RESOLVER_TEST_DIR}/fixtures/expected-success.json" "$resolved_file"
}

test_successful_plan_generation() {
  local output_file="${PLANNER_TEST_DIR}/.success.out"
  local status

  run_command "$output_file" "$MEL" plan --manifest "${ROOT_DIR}/examples/hold-production.yml"
  status=$?

  assert_exit "planner exits success" 0 "$status"
  assert_file_equals "planner produces stable JSON" "${ROOT_DIR}/examples/plans/hold-production.plan.json" "$output_file"
}

test_deterministic_plan_output() {
  local first_output_file="${PLANNER_TEST_DIR}/.deterministic-first.out"
  local second_output_file="${PLANNER_TEST_DIR}/.deterministic-second.out"
  local first_status
  local second_status

  run_command "$first_output_file" "$MEL" plan --manifest "${ROOT_DIR}/examples/hold-production.yml"
  first_status=$?
  run_command "$second_output_file" "$MEL" plan --manifest "${ROOT_DIR}/examples/hold-production.yml"
  second_status=$?

  assert_exit "first deterministic planner run exits success" 0 "$first_status"
  assert_exit "second deterministic planner run exits success" 0 "$second_status"
  assert_file_equals "planner output is deterministic" "$first_output_file" "$second_output_file"
}

test_dependency_ordering() {
  local output_file="${PLANNER_TEST_DIR}/.dependency-order.out"
  local check_file="${PLANNER_TEST_DIR}/.dependency-order-check.out"
  local status
  local check_status

  run_command "$output_file" "$MEL" plan --manifest "${ROOT_DIR}/examples/hold-production.yml"
  status=$?

  python3 - "$output_file" >"$check_file" 2>&1 <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    plan = json.load(handle)

orders = {step["id"]: step["order"] for step in plan["steps"]}

for step in plan["steps"]:
    for dependency in step["depends_on"]:
        if orders[dependency] >= step["order"]:
            print(f"{step['id']} depends on non-earlier step {dependency}")
            sys.exit(2)

sys.exit(0)
PY
  check_status=$?

  assert_exit "planner dependency test command exits success" 0 "$status"
  assert_exit "planner dependencies are ordered before dependent steps" 0 "$check_status"
}

test_duplicate_steps() {
  local plan
  local output
  local status

  plan="$(<"${PLANNER_TEST_DIR}/fixtures/duplicate-steps.plan.json")"
  output="$(mel_planner_validate_plan "$plan" 2>&1)"
  status=$?

  assert_exit "planner rejects duplicate steps" 2 "$status"
  assert_contains "planner reports duplicate step identifier" "$output" "duplicate step identifier: validate"
}

test_circular_dependencies() {
  local plan
  local output
  local status

  plan="$(<"${PLANNER_TEST_DIR}/fixtures/circular-dependencies.plan.json")"
  output="$(mel_planner_validate_plan "$plan" 2>&1)"
  status=$?

  assert_exit "planner rejects circular dependencies" 2 "$status"
  assert_contains "planner reports circular dependency" "$output" "circular dependency detected:"
}

test_invalid_actions() {
  local plan
  local output
  local status

  plan="$(<"${PLANNER_TEST_DIR}/fixtures/invalid-action.plan.json")"
  output="$(mel_planner_validate_plan "$plan" 2>&1)"
  status=$?

  assert_exit "planner rejects invalid actions" 2 "$status"
  assert_contains "planner reports unsupported action" "$output" "unsupported planner action: deploy_now"
}

test_missing_dependencies() {
  local plan
  local output
  local status

  plan="$(<"${PLANNER_TEST_DIR}/fixtures/missing-dependency.plan.json")"
  output="$(mel_planner_validate_plan "$plan" 2>&1)"
  status=$?

  assert_exit "planner rejects missing dependencies" 2 "$status"
  assert_contains "planner reports missing dependency" "$output" "missing dependency for prepare_release: validate"
}

test_invalid_execution_order() {
  local plan
  local output
  local status

  plan="$(<"${PLANNER_TEST_DIR}/fixtures/invalid-order.plan.json")"
  output="$(mel_planner_validate_plan "$plan" 2>&1)"
  status=$?

  assert_exit "planner rejects invalid execution order" 2 "$status"
  assert_contains "planner reports invalid execution order" "$output" "invalid execution order:"
}

test_malformed_resolved_model() {
  local resolved_model
  local output
  local status

  resolved_model="$(<"${PLANNER_TEST_DIR}/fixtures/malformed-resolved-model.json")"
  output="$(mel_planner_build_plan "$resolved_model" 2>&1)"
  status=$?

  assert_exit "planner rejects malformed resolved model" 2 "$status"
  assert_contains "planner reports missing resolved environment" "$output" "resolved_model.environment is required"
}

test_plan_output_option() {
  local output_file="${PLANNER_TEST_DIR}/.output-option.out"
  local plan_file="${PLANNER_TEST_DIR}/.planned.json"
  local status

  run_command "$output_file" "$MEL" plan --manifest "${ROOT_DIR}/examples/hold-production.yml" --output "$plan_file"
  status=$?

  assert_exit "planner output option exits success" 0 "$status"
  assert_file_equals "planner output file is stable JSON" "${ROOT_DIR}/examples/plans/hold-production.plan.json" "$plan_file"
}

test_policy_allowed() {
  local output_file="${POLICY_TEST_DIR}/.allowed.out"
  local status
  local output

  run_command "$output_file" "$MEL" policy --manifest "${ROOT_DIR}/examples/hold-production.yml" --repository-state clean --approval business --approval technical --approval release_manager
  status=$?
  output="$(<"$output_file")"

  assert_exit "policy exits success when allowed" 0 "$status"
  assert_contains "policy reports allowed decision" "$output" '"decision": "allowed"'
}

test_policy_missing_approval() {
  local output_file="${POLICY_TEST_DIR}/.missing-approval.out"
  local status
  local output

  run_command "$output_file" "$MEL" policy --manifest "${ROOT_DIR}/examples/hold-production.yml" --repository-state clean --approval technical
  status=$?
  output="$(<"$output_file")"

  assert_exit "policy blocks missing approvals" 2 "$status"
  assert_contains "policy reports missing approvals" "$output" '"decision": "blocked"'
  assert_contains "policy names missing approvals" "$output" "missing required approvals:"
}

test_dry_run_manifest() {
  local output_file="${DRYRUN_TEST_DIR}/.manifest.out"
  local status
  local output

  run_command "$output_file" "$MEL" dry-run --manifest "${ROOT_DIR}/examples/hold-production.yml"
  status=$?
  output="$(<"$output_file")"

  assert_exit "dry-run manifest exits success" 0 "$status"
  assert_contains "dry-run includes manifest validation" "$output" "✓ Validate manifest"
  assert_contains "dry-run includes policy validation" "$output" "✓ Validate policy"
  assert_contains "dry-run confirms no execution" "$output" "No deployment actions were executed."
}

test_dry_run_plan_file() {
  local output_file="${DRYRUN_TEST_DIR}/.plan.out"
  local status
  local output

  run_command "$output_file" "$MEL" dry-run --plan "${ROOT_DIR}/examples/plans/hold-production.plan.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "dry-run plan file exits success" 0 "$status"
  assert_contains "dry-run includes switch current simulation" "$output" "✓ Switch current"
}

test_doctor_staging() {
  local output_file="${DOCTOR_TEST_DIR}/.staging.out"
  local status
  local output

  run_command "$output_file" "$MEL" doctor staging
  status=$?
  output="$(<"$output_file")"

  assert_exit "doctor staging exits success" 0 "$status"
  assert_contains "doctor staging prints human output" "$output" "Server doctor"
  assert_contains "doctor staging prints JSON output" "$output" '"environment": "staging"'
}

test_doctor_production_json() {
  local output_file="${DOCTOR_TEST_DIR}/.production-json.out"
  local status
  local output

  run_command "$output_file" "$MEL" doctor production --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "doctor production JSON exits success" 0 "$status"
  assert_contains "doctor production reports passed" "$output" '"status": "passed"'
  assert_contains "doctor production uses mock checks" "$output" '"mode": "mock"'
}

test_health_success() {
  local output
  local status
  local checks
  local state

  checks='[{"name":"public_http","type":"http_response"},{"name":"drupal_status","type":"drupal_status_endpoint"},{"name":"shared","type":"directory_exists","path":"/app/shared"},{"name":"release","type":"release_exists","release":"20260703153045"},{"name":"current","type":"current_symlink","link":"/app/current","target":"/app/releases/20260703153045"}]'
  state='{"http_response":{"public_http":200},"drupal_status_endpoint":{"drupal_status":"ok"},"directory_exists":{"/app/shared":true},"release_exists":{"20260703153045":true},"current_symlink":{"/app/current":"/app/releases/20260703153045"}}'
  output="$(mel_health_evaluate_checks "$checks" "$state" 2>&1)"
  status=$?

  assert_exit "health checks pass with supplied state" 0 "$status"
  assert_contains "health reports passed" "$output" '"status": "passed"'
}

test_health_failure() {
  local output
  local status
  local checks
  local state

  checks='[{"name":"public_http","type":"http_response"}]'
  state='{"http_response":{"public_http":500}}'
  output="$(mel_health_evaluate_checks "$checks" "$state" 2>&1)"
  status=$?

  assert_exit "health checks fail closed" 2 "$status"
  assert_contains "health reports failed" "$output" '"status": "failed"'
}

test_plugin_contracts_load() {
  local output
  local status

  output="$(mel_plugins_validate_contracts "${ROOT_DIR}/deploy/plugins" 2>&1)"
  status=$?

  assert_exit "plugin contracts load" 0 "$status"
  assert_contains "plugin loader reports passed" "$output" '"status": "passed"'
  assert_contains "plugin loader includes switch current" "$output" "switch-current-contract"
}

test_profiles_are_non_secret_contracts() {
  local output_file="${PROFILE_TEST_DIR}/.profiles.out"
  local status
  local output

  python3 - "${ROOT_DIR}/profiles/staging.json" "${ROOT_DIR}/profiles/production.json" >"$output_file" 2>&1 <<'PY'
import json
import sys

common_required_keys = {
    "profile",
    "environment",
    "validation_profile",
    "policy_profile",
    "required_approvals",
    "health_checks",
    "doctor_checks",
}
staging_required_keys = common_required_keys | {
    "profile_version",
    "deployment_root",
    "repository",
    "ssh",
    "paths",
    "executables",
    "health_endpoints",
}
secret_words = ("password", "secret", "token", "credential", "private_key")

for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as handle:
        profile = json.load(handle)
    required_keys = staging_required_keys if profile.get("environment") == "staging" else common_required_keys
    missing = sorted(required_keys - set(profile))
    if missing:
        print(f"{path} missing keys: {', '.join(missing)}")
        sys.exit(2)
    encoded = json.dumps(profile).lower()
    if any(word in encoded for word in secret_words):
        print(f"{path} appears to contain secret material")
        sys.exit(2)
    if any(check.get("mode") not in {"mock", "profile"} for check in profile["doctor_checks"]):
        print(f"{path} contains unsupported doctor checks")
        sys.exit(2)

print("profiles ok")
PY
  status=$?
  output="$(<"$output_file")"

  assert_exit "profiles validate as non-secret contracts" 0 "$status"
  assert_contains "profiles report ok" "$output" "profiles ok"
}

test_verify_valid_profile() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.valid-profile.out"
  local status
  local output

  fixture="$(readiness_fixture "valid-profile")"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify valid profile exits success" 0 "$status"
  assert_contains "verify valid profile reports passed" "$output" '"status": "passed"'
}

test_verify_missing_profile_fields() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.missing-profile-fields.out"
  local status
  local output

  fixture="$(readiness_fixture "missing-profile-fields")"
  IFS=$'\t' read -r root profile_file <<<"$fixture"
  python3 - "$profile_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    profile = json.load(handle)
del profile["ssh"]
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(profile, handle, indent=2)
PY

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify rejects missing profile fields" 2 "$status"
  assert_contains "verify missing profile fields names ssh" "$output" "profile.ssh must be an object"
}

test_verify_invalid_layout() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.invalid-layout.out"
  local status
  local output

  fixture="$(readiness_fixture "invalid-layout")"
  IFS=$'\t' read -r root profile_file <<<"$fixture"
  rm -rf "$root/logs"

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --check layout --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify rejects invalid layout" 2 "$status"
  assert_contains "verify invalid layout reports logs" "$output" "logs directory is missing"
}

test_verify_broken_current_symlink() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.broken-current.out"
  local status
  local output

  fixture="$(readiness_fixture "broken-current" broken-current)"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --check layout --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify rejects broken current symlink" 2 "$status"
  assert_contains "verify broken current reports target" "$output" "current symlink target is missing"
}

test_verify_missing_shared() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.missing-shared.out"
  local status
  local output

  fixture="$(readiness_fixture "missing-shared" missing-shared)"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --check layout --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify rejects missing shared resource" 2 "$status"
  assert_contains "verify missing shared reports resource" "$output" "required shared directory is missing"
}

test_verify_missing_releases() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.missing-releases.out"
  local status
  local output

  fixture="$(readiness_fixture "missing-releases" missing-releases)"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --check layout --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify rejects missing releases" 2 "$status"
  assert_contains "verify missing releases reports directory" "$output" "releases directory is missing"
}

test_doctor_readiness_failure() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.doctor-failure.out"
  local status
  local output

  fixture="$(readiness_fixture "doctor-failure" valid passed live)"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" doctor staging --profile "$profile_file" --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "doctor fails unsupported readiness mode" 2 "$status"
  assert_contains "doctor readiness failure reports unsupported mode" "$output" "unsupported mode"
}

test_verify_health_failure() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.health-failure.out"
  local status
  local output

  fixture="$(readiness_fixture "health-failure" valid failed)"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" verify staging --profile "$profile_file" --check health --json
  status=$?
  output="$(<"$output_file")"

  assert_exit "verify fails health failure" 2 "$status"
  assert_contains "verify health failure reports HTTP" "$output" "HTTP status 500"
}

test_report_generation() {
  local fixture
  local root
  local profile_file
  local output_file="${READINESS_TEST_DIR}/.report.out"
  local status
  local output

  fixture="$(readiness_fixture "report")"
  IFS=$'\t' read -r root profile_file <<<"$fixture"

  run_command "$output_file" "$MEL" report staging --profile "$profile_file"
  status=$?
  output="$(<"$output_file")"

  assert_exit "report generation exits success" 0 "$status"
  assert_contains "report includes deployment ready" "$output" "Deployment Ready: READY"
  assert_contains "report includes profile version" "$output" "Profile Version: 1"
}

test_execute_dry_run_staging() {
  local output_file="${EXECUTOR_TEST_DIR}/.dry-run.out"
  local status
  local output

  run_command "$output_file" env MEL_RELEASE_TIMESTAMP=20260703194512 "$MEL" execute staging --dry-run
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor dry-run exits success" 0 "$status"
  assert_contains "executor dry-run reports staging" "$output" '"environment": "staging"'
  assert_contains "executor dry-run reports no mutation" "$output" '"dry_run": true'
}

test_execute_rejects_production() {
  local output_file="${EXECUTOR_TEST_DIR}/.production.out"
  local status
  local output

  run_command "$output_file" "$MEL" execute production
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor rejects production" 2 "$status"
  assert_contains "executor production rejection is structured" "$output" "MEL_EXECUTOR_PRODUCTION_FORBIDDEN"
}

test_successful_deployment() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.success.out"
  local status

  fixture="$(executor_fixture "success")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 MEL_RELEASE_TIMESTAMP=20260703194512 MEL_EXECUTOR_NOW=2026-07-03T09:45:12Z "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?

  assert_exit "executor successful deployment exits success" 0 "$status"
  assert_symlink_target "executor switches current to release" "$root/current" "$root/releases/20260703194512"
}

test_failed_validation() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-validation.out"
  local status
  local output

  fixture="$(executor_fixture "failed-validation")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"
  printf '{"schema":"mel-deployment.manifest.v1"}\n' >"$manifest_file"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails invalid validation" 2 "$status"
  assert_contains "executor validation failure is structured" "$output" "MEL_EXECUTOR_INVALID"
}

test_failed_policy() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-policy.out"
  local status
  local output

  fixture="$(executor_fixture "failed-policy")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state dirty
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails blocked policy" 2 "$status"
  assert_contains "executor reports policy failure" "$output" "MEL_POLICY_INVALID"
}

test_failed_doctor() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-doctor.out"
  local status
  local output

  fixture="$(executor_fixture "failed-doctor" passed passed passed live)"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails doctor failure" 2 "$status"
  assert_contains "executor reports doctor failure" "$output" "MEL_DOCTOR_INVALID"
}

test_failed_layout_verification() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-layout.out"
  local status
  local output

  fixture="$(executor_fixture "failed-layout")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"
  rm -rf "$root/logs"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails layout verification" 2 "$status"
  assert_contains "executor reports layout failure" "$output" "MEL_EXECUTOR_INVALID"
}

test_failed_shared_resource() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-shared.out"
  local status
  local output

  fixture="$(executor_fixture "failed-shared" passed passed passed mock missing)"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails missing shared resource" 2 "$status"
  assert_contains "executor reports shared resource failure" "$output" "shared resource linking failed"
}

test_failed_composer_plugin() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-composer.out"
  local status
  local output

  fixture="$(executor_fixture "failed-composer" failed)"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails Composer plugin" 2 "$status"
  assert_contains "executor reports Composer plugin failure" "$output" "composer plugin failed"
}

test_failed_drush_plugin() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-drush.out"
  local status
  local output

  fixture="$(executor_fixture "failed-drush" passed failed)"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails Drush plugin" 2 "$status"
  assert_contains "executor reports Drush plugin failure" "$output" "drush plugin failed"
}

test_failed_health() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.failed-health.out"
  local status
  local output

  fixture="$(executor_fixture "failed-health" passed passed failed)"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  output="$(<"$output_file")"

  assert_exit "executor fails health failure" 2 "$status"
  assert_contains "executor reports health failure" "$output" "MEL_HEALTH_INVALID"
}

test_successful_rollback() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${ROLLBACK_TEST_DIR}/.success.out"
  local status

  fixture="$(executor_fixture "rollback-success")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 MEL_EXECUTOR_FAIL_POST_SWITCH=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?

  assert_exit "executor exits failure after rollback" 2 "$status"
  assert_symlink_target "executor restores previous current on rollback" "$root/current" "$root/releases/previous"
  assert_json_contains "rollback event records success" "$root/logs/20260703194512.rollback.json" "status" "rolled_back"
}

test_failed_rollback() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${ROLLBACK_TEST_DIR}/.failed.out"
  local status

  fixture="$(executor_fixture "rollback-failed")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 MEL_EXECUTOR_FAIL_POST_SWITCH=1 MEL_ROLLBACK_FORCE_FAIL=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?

  assert_exit "executor exits failure when rollback fails" 2 "$status"
  assert_json_contains "rollback event records failure" "$root/logs/20260703194512.rollback.json" "status" "rollback_failed"
}

test_release_manifest_generation() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${RELEASE_TEST_DIR}/.manifest.out"
  local status
  local release_manifest

  fixture="$(executor_fixture "release-manifest")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 MEL_EXECUTOR_NOW=2026-07-03T09:45:12Z "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  release_manifest="$root/releases/20260703194512/release.json"

  assert_exit "release manifest deployment exits success" 0 "$status"
  assert_json_contains "release manifest records deployment id" "$release_manifest" "deployment_id" "mel-staging"
  assert_json_contains "release manifest records status" "$release_manifest" "status" "deployed"
}

test_execution_log_generation() {
  local fixture
  local root
  local manifest_file
  local profile_file
  local output_file="${EXECUTOR_TEST_DIR}/.log.out"
  local status
  local log_file

  fixture="$(executor_fixture "execution-log")"
  IFS=$'\t' read -r root manifest_file profile_file <<<"$fixture"

  run_command "$output_file" env MEL_EXECUTOR_TEST_MODE=1 "$MEL" execute staging --manifest "$manifest_file" --profile "$profile_file" --repository-state clean
  status=$?
  log_file="$root/logs/20260703194512.deployment.json"

  assert_exit "execution log deployment exits success" 0 "$status"
  assert_json_contains "execution log records status" "$log_file" "status" "passed"
  assert_json_contains "execution log records rollback status" "$log_file" "rollback.status" "not_required"
}

cleanup() {
  rm -f "${VALIDATION_TEST_DIR}"/.*.out
  rm -f "${RESOLVER_TEST_DIR}"/.*.out
  rm -f "${RESOLVER_TEST_DIR}"/.resolved.json
  rm -f "${PLANNER_TEST_DIR}"/.*.out
  rm -f "${PLANNER_TEST_DIR}"/.planned.json
  rm -f "${POLICY_TEST_DIR}"/.*.out
  rm -f "${DRYRUN_TEST_DIR}"/.*.out
  rm -f "${DOCTOR_TEST_DIR}"/.*.out
  rm -f "${HEALTH_TEST_DIR}"/.*.out
  rm -f "${READINESS_TEST_DIR}"/.*.out
  rm -rf "${READINESS_TEST_DIR}"/.tmp-*
  rm -f "${PLUGIN_TEST_DIR}"/.*.out
  rm -f "${PROFILE_TEST_DIR}"/.*.out
  rm -f "${EXECUTOR_TEST_DIR}"/.*.out
  rm -f "${RELEASE_TEST_DIR}"/.*.out
  rm -f "${ROLLBACK_TEST_DIR}"/.*.out
  rm -rf "${EXECUTOR_TEST_DIR}"/.tmp-*
}

cleanup
test_valid_manifest
test_invalid_manifest
test_invalid_path
test_malformed_schema
test_cli_exit_codes
test_version
test_info
test_successful_resolution
test_default_resolution
test_missing_required_values
test_conflicting_configuration
test_duplicate_deployment_ids
test_unsupported_environment
test_unsupported_release_strategy
test_output_option
test_successful_plan_generation
test_deterministic_plan_output
test_dependency_ordering
test_duplicate_steps
test_circular_dependencies
test_invalid_actions
test_missing_dependencies
test_invalid_execution_order
test_malformed_resolved_model
test_plan_output_option
test_policy_allowed
test_policy_missing_approval
test_dry_run_manifest
test_dry_run_plan_file
test_doctor_staging
test_doctor_production_json
test_health_success
test_health_failure
test_plugin_contracts_load
test_profiles_are_non_secret_contracts
test_verify_valid_profile
test_verify_missing_profile_fields
test_verify_invalid_layout
test_verify_broken_current_symlink
test_verify_missing_shared
test_verify_missing_releases
test_doctor_readiness_failure
test_verify_health_failure
test_report_generation
test_execute_dry_run_staging
test_execute_rejects_production
test_successful_deployment
test_failed_validation
test_failed_policy
test_failed_doctor
test_failed_layout_verification
test_failed_shared_resource
test_failed_composer_plugin
test_failed_drush_plugin
test_failed_health
test_successful_rollback
test_failed_rollback
test_release_manifest_generation
test_execution_log_generation
cleanup

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi

exit 0
