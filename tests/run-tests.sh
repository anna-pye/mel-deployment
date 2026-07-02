#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${ROOT_DIR}/tests/validation"
MEL="${ROOT_DIR}/deploy/bin/mel"

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

run_command() {
  local output_file="$1"
  shift

  "$@" >"$output_file" 2>&1
}

test_valid_manifest() {
  local output_file="${TEST_DIR}/.valid.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${TEST_DIR}/fixtures/valid-manifest.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "valid manifest exits success" 0 "$status"
  assert_contains "valid manifest reports success" "$output" "[success] MEL_OK: validation passed"
}

test_invalid_manifest() {
  local output_file="${TEST_DIR}/.invalid-manifest.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${TEST_DIR}/fixtures/invalid-manifest.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "invalid manifest exits error" 2 "$status"
  assert_contains "invalid manifest reports structured error" "$output" "[error] MEL_MANIFEST_INVALID:"
}

test_invalid_path() {
  local output_file="${TEST_DIR}/.invalid-path.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${TEST_DIR}/fixtures/invalid-path.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "invalid path exits error" 2 "$status"
  assert_contains "invalid path reports structured error" "$output" "[error] MEL_PATH_INVALID:"
}

test_malformed_schema() {
  local output_file="${TEST_DIR}/.malformed-schema.out"
  local status
  local output

  run_command "$output_file" "$MEL" validate --manifest "${TEST_DIR}/fixtures/valid-manifest.json" --schema "${TEST_DIR}/fixtures/malformed-schema.json"
  status=$?
  output="$(<"$output_file")"

  assert_exit "malformed schema exits error" 2 "$status"
  assert_contains "malformed schema reports structured error" "$output" "[error] MEL_SCHEMA_MALFORMED:"
}

test_cli_exit_codes() {
  local output_file="${TEST_DIR}/.cli-exit.out"
  local status
  local output

  run_command "$output_file" "$MEL" unknown-command
  status=$?
  output="$(<"$output_file")"

  assert_exit "unknown command exits error" 2 "$status"
  assert_contains "unknown command reports argument error" "$output" "[error] MEL_ARGUMENT_ERROR:"
}

test_version() {
  local output_file="${TEST_DIR}/.version.out"
  local status
  local output

  run_command "$output_file" "$MEL" version
  status=$?
  output="$(<"$output_file")"

  assert_exit "mel version exits success" 0 "$status"
  assert_contains "mel version reports repository version" "$output" "0.1.0-dev"
}

test_info() {
  local output_file="${TEST_DIR}/.info.out"
  local status
  local output

  run_command "$output_file" "$MEL" info
  status=$?
  output="$(<"$output_file")"

  assert_exit "mel info exits success" 0 "$status"
  assert_contains "mel info reports validation engine" "$output" "mel validation engine"
  assert_contains "mel info reports repository" "$output" "repository:"
}

cleanup() {
  rm -f "${TEST_DIR}"/.*.out
}

cleanup
test_valid_manifest
test_invalid_manifest
test_invalid_path
test_malformed_schema
test_cli_exit_codes
test_version
test_info
cleanup

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"

if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi

exit 0
