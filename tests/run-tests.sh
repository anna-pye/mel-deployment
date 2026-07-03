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
PLUGIN_TEST_DIR="${ROOT_DIR}/tests/plugins"
PROFILE_TEST_DIR="${ROOT_DIR}/tests/profiles"
MEL="${ROOT_DIR}/deploy/bin/mel"

# shellcheck source=../deploy/lib/planner.sh
. "${ROOT_DIR}/deploy/lib/planner.sh"
# shellcheck source=../deploy/lib/health.sh
. "${ROOT_DIR}/deploy/lib/health.sh"
# shellcheck source=../deploy/lib/plugins.sh
. "${ROOT_DIR}/deploy/lib/plugins.sh"

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

run_command() {
  local output_file="$1"
  shift

  "$@" >"$output_file" 2>&1
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

required_keys = {
    "profile",
    "environment",
    "validation_profile",
    "policy_profile",
    "required_approvals",
    "health_checks",
    "doctor_checks",
}
secret_words = ("password", "secret", "token", "credential", "private_key")

for path in sys.argv[1:]:
    with open(path, "r", encoding="utf-8") as handle:
        profile = json.load(handle)
    missing = sorted(required_keys - set(profile))
    if missing:
        print(f"{path} missing keys: {', '.join(missing)}")
        sys.exit(2)
    encoded = json.dumps(profile).lower()
    if any(word in encoded for word in secret_words):
        print(f"{path} appears to contain secret material")
        sys.exit(2)
    if any(check.get("mode") != "mock" for check in profile["doctor_checks"]):
        print(f"{path} contains non-mock doctor checks")
        sys.exit(2)

print("profiles ok")
PY
  status=$?
  output="$(<"$output_file")"

  assert_exit "profiles validate as non-secret contracts" 0 "$status"
  assert_contains "profiles report ok" "$output" "profiles ok"
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
  rm -f "${PLUGIN_TEST_DIR}"/.*.out
  rm -f "${PROFILE_TEST_DIR}"/.*.out
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
cleanup

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi

exit 0
