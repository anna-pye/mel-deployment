#!/usr/bin/env bash

mel_executor_default_profile_file() {
  local environment="$1"

  printf '%s/profiles/%s.json\n' "$MEL_ROOT" "$environment"
}

mel_executor_json_value() {
  local json_text="$1"
  local dotted_key="$2"
  local default_value="${3:-}"

  python3 - "$json_text" "$dotted_key" "$default_value" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
for part in sys.argv[2].split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        print(sys.argv[3])
        sys.exit(0)
print(value if isinstance(value, str) else json.dumps(value))
PY
}

mel_executor_profile_value() {
  local profile_file="$1"
  local dotted_key="$2"
  local default_value="${3:-}"

  python3 - "$profile_file" "$dotted_key" "$default_value" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        print(sys.argv[3])
        sys.exit(0)
print(value if isinstance(value, str) else json.dumps(value))
PY
}

mel_executor_profile_required_value() {
  local profile_file="$1"
  local dotted_key="$2"
  local value

  value="$(mel_executor_profile_value "$profile_file" "$dotted_key" "")" || return "$?"
  if [[ -z "$value" ]]; then
    printf 'profile.%s is required\n' "$dotted_key"
    return "$MEL_EXIT_ERROR"
  fi

  printf '%s\n' "$value"
}

mel_executor_now() {
  if [[ -n "${MEL_EXECUTOR_NOW:-}" ]]; then
    printf '%s\n' "$MEL_EXECUTOR_NOW"
    return "$MEL_EXIT_SUCCESS"
  fi

  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

mel_executor_git_commit() {
  if command -v git >/dev/null 2>&1 && git -C "$MEL_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$MEL_ROOT" rev-parse HEAD
    return "$MEL_EXIT_SUCCESS"
  fi

  printf 'unknown\n'
}

mel_executor_json_array_append() {
  local array_json="$1"
  local item_json="$2"

  python3 - "$array_json" "$item_json" <<'PY'
import json
import sys

items = json.loads(sys.argv[1])
item = json.loads(sys.argv[2])
items.append(item)
print(json.dumps(items))
PY
}

mel_executor_step() {
  local name="$1"
  local status="$2"
  local message="$3"

  python3 - "$name" "$status" "$message" <<'PY'
import json
import sys

print(json.dumps({"name": sys.argv[1], "status": sys.argv[2], "message": sys.argv[3]}))
PY
}

mel_executor_error() {
  local name="$1"
  local message="$2"

  python3 - "$name" "$message" <<'PY'
import json
import sys

print(json.dumps({"name": sys.argv[1], "message": sys.argv[2]}))
PY
}

mel_executor_health_payload() {
  local profile_file="$1"
  local staging_root="$2"
  local releases_path="$3"
  local current_link="$4"
  local release_id="$5"
  local current_target="$6"
  local dry_run="$7"
  local health_scope="$8"

  python3 - "$profile_file" "$staging_root" "$releases_path" "$current_link" "$release_id" "$current_target" "$dry_run" "$health_scope" <<'PY'
import json
import os
import sys

profile_file, staging_root, releases_path, current_link, release_id, current_target, dry_run, health_scope = sys.argv[1:9]
dry_run = dry_run == "true"

with open(profile_file, "r", encoding="utf-8") as handle:
    profile = json.load(handle)

configured_checks = list(profile.get("health_checks", []))
if health_scope in {"release", "post"}:
    configured_checks.append({
        "name": "executor_release_exists",
        "type": "release_exists",
        "release": release_id,
        "required": True,
    })
if health_scope == "post":
    configured_checks.append({
        "name": "executor_current_symlink",
        "type": "current_symlink",
        "link": current_link,
        "target": current_target,
        "required": True,
    })

state = {
    "http_response": {},
    "drupal_status_endpoint": {},
    "directory_exists": {},
    "release_exists": {},
    "current_symlink": {},
}
configured_state = profile.get("health_state", {})
if not isinstance(configured_state, dict):
    configured_state = {}

checks = []
for check in configured_checks:
    resolved = dict(check)
    name = resolved.get("name")
    kind = resolved.get("type")
    if kind == "http_response":
        state["http_response"][name] = int(configured_state.get(name, 200))
    elif kind == "drupal_status_endpoint":
        state["drupal_status_endpoint"][name] = str(configured_state.get(name, "ok"))
    elif kind == "directory_exists":
        path = resolved.get("path") or staging_root
        resolved["path"] = path
        state["directory_exists"][path] = True if dry_run else os.path.isdir(path)
    elif kind == "release_exists":
        resolved["release"] = release_id
        release_path = os.path.join(releases_path, release_id)
        state["release_exists"][release_id] = True if dry_run else os.path.isdir(release_path)
    elif kind == "current_symlink":
        link = resolved.get("link") or current_link
        target = resolved.get("target") or current_target
        resolved["link"] = link
        resolved["target"] = target
        actual = target if dry_run else os.path.realpath(link) if os.path.islink(link) else ""
        state["current_symlink"][link] = actual
    checks.append(resolved)

print(json.dumps({"checks": checks, "state": state}, indent=2))
PY
}

mel_executor_switch_current() {
  local current_link="$1"
  local release_root="$2"

  python3 - "$current_link" "$release_root" <<'PY'
import os
import sys
import tempfile

current_link, release_root = sys.argv[1:3]
link_dir = os.path.dirname(current_link)

try:
    if not os.path.isdir(release_root):
        raise OSError(f"release root is missing: {release_root}")
    os.makedirs(link_dir, exist_ok=True)
    fd, temp_link = tempfile.mkstemp(prefix=".current.", dir=link_dir)
    os.close(fd)
    os.unlink(temp_link)
    os.symlink(release_root, temp_link)
    os.replace(temp_link, current_link)
except OSError as exc:
    print(str(exc))
    sys.exit(2)
PY
}

mel_executor_run_health() {
  local profile_file="$1"
  local staging_root="$2"
  local releases_path="$3"
  local current_link="$4"
  local release_id="$5"
  local current_target="$6"
  local dry_run="$7"
  local health_scope="$8"
  local payload
  local checks
  local state

  payload="$(mel_executor_health_payload "$profile_file" "$staging_root" "$releases_path" "$current_link" "$release_id" "$current_target" "$dry_run" "$health_scope")" || return "$?"
  checks="$(mel_executor_json_value "$payload" "checks")"
  state="$(mel_executor_json_value "$payload" "state")"
  mel_plugins_invoke_mock "${MEL_ROOT}/deploy/plugins" "$profile_file" "health" "{\"release_id\":\"${release_id}\"}" >/dev/null || return "$?"
  mel_health_evaluate_checks "$checks" "$state" >/dev/null
}

mel_executor_finish_log() {
  local log_file="$1"
  local deployment_id="$2"
  local release_id="$3"
  local started_at="$4"
  local started_epoch="$5"
  local status="$6"
  local steps_json="$7"
  local errors_json="$8"
  local rollback_json="$9"
  local finished_at
  local finished_epoch

  finished_at="$(mel_executor_now)"
  finished_epoch="$(date -u '+%s')"
  mel_execution_log_write "$log_file" "$deployment_id" "$release_id" "$started_at" "$finished_at" "$((finished_epoch - started_epoch))" "$status" "$steps_json" "$errors_json" "$rollback_json"
}

mel_executor_run() {
  local environment="$1"
  local manifest_file="$2"
  local schema_file="$3"
  local profile_file="$4"
  local dry_run="$5"
  local repository_state="$6"
  local approvals_csv="$7"
  local release_id="${8:-}"
  local started_at
  local started_epoch
  local steps_json="[]"
  local errors_json="[]"
  local rollback_json='{"status":"not_required"}'
  local resolved_model
  local execution_plan
  local policy_result
  local staging_root
  local releases_path
  local shared_path
  local logs_path
  local release_root
  local current_link
  local previous_current=""
  local deployment_id="unknown"
  local repository
  local profile_repository
  local branch
  local commit
  local version
  local log_file
  local manifest_output
  local step_json
  local error_json

  if [[ "$environment" == "production" ]]; then
    printf '{\n  "status": "failed",\n  "code": "MEL_EXECUTOR_PRODUCTION_FORBIDDEN",\n  "error": "production execution is forbidden"\n}\n'
    return "$MEL_EXIT_ERROR"
  fi
  if [[ "$environment" != "staging" ]]; then
    printf '{\n  "status": "failed",\n  "code": "MEL_EXECUTOR_INVALID_ENVIRONMENT",\n  "error": "execute supports staging only"\n}\n'
    return "$MEL_EXIT_ERROR"
  fi

  started_at="$(mel_executor_now)"
  started_epoch="$(date -u '+%s')"
  if ! staging_root="$(mel_executor_profile_required_value "$profile_file" "deployment_root")"; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "$staging_root"
    return "$MEL_EXIT_ERROR"
  fi
  releases_path="$(mel_executor_profile_value "$profile_file" "paths.releases" "${staging_root}/releases")"
  shared_path="$(mel_executor_profile_value "$profile_file" "paths.shared" "${staging_root}/shared")"
  current_link="$(mel_executor_profile_value "$profile_file" "paths.current" "${staging_root}/current")"
  logs_path="$(mel_executor_profile_value "$profile_file" "paths.logs" "${staging_root}/logs")"
  profile_repository="$(mel_executor_profile_value "$profile_file" "repository" "")"
  if [[ -z "$release_id" ]]; then
    release_id="$(mel_release_generate_id)"
  fi
  log_file="${logs_path}/${release_id}.deployment.json"

  if ! mel_release_validate_id "$release_id" >/dev/null; then
    error_json="$(mel_executor_error "release_id" "release_id must use YYYYMMDDHHMMSS format")"
    errors_json="$(mel_executor_json_array_append "$errors_json" "$error_json")"
    printf '{\n  "status": "failed",\n  "code": "MEL_EXECUTOR_INVALID",\n  "error": "release_id must use YYYYMMDDHHMMSS format"\n}\n'
    return "$MEL_EXIT_ERROR"
  fi

  if ! mel_validate_repository_metadata >/dev/null 2>&1 || ! mel_manifest_validate "$manifest_file" "$schema_file" >/dev/null 2>&1; then
    step_json="$(mel_executor_step "validation" "failed" "validation failed")"
    steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"
    error_json="$(mel_executor_error "validation" "validation failed")"
    errors_json="$(mel_executor_json_array_append "$errors_json" "$error_json")"
    [[ "$dry_run" == "true" ]] || mel_executor_finish_log "$log_file" "$deployment_id" "$release_id" "$started_at" "$started_epoch" "failed" "$steps_json" "$errors_json" "$rollback_json" >/dev/null
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "validation failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "validation" "passed" "validation passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! resolved_model="$(mel_resolver_build_model "$manifest_file")"; then
    error_json="$(mel_executor_error "resolution" "$resolved_model")"
    errors_json="$(mel_executor_json_array_append "$errors_json" "$error_json")"
    mel_output_error "$MEL_CODE_RESOLUTION_INVALID" "$resolved_model"
    return "$MEL_EXIT_ERROR"
  fi
  deployment_id="$(mel_executor_json_value "$resolved_model" "deployment_id" "unknown")"
  repository="$(mel_executor_json_value "$resolved_model" "repository.url" "")"
  branch="$(mel_executor_json_value "$resolved_model" "repository.branch" "")"
  if [[ "$(mel_executor_json_value "$resolved_model" "environment" "")" != "staging" ]]; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "resolved deployment environment must be staging"
    return "$MEL_EXIT_ERROR"
  fi
  if [[ -n "$profile_repository" ]]; then
    if [[ "$repository" != "$profile_repository" ]]; then
      mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "resolved repository must match the staging profile"
      return "$MEL_EXIT_ERROR"
    fi
  elif [[ "$repository" != "git@github.com:anna-pye/myeventlane-platform.git" && "$repository" != "https://github.com/anna-pye/myeventlane-platform.git" ]]; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "resolved repository must be anna-pye/myeventlane-platform"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "resolution" "passed" "resolution passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! execution_plan="$(mel_planner_build_plan "$resolved_model")"; then
    mel_output_error "$MEL_CODE_PLAN_INVALID" "$execution_plan"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "planner" "passed" "planner passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if [[ -z "$repository_state" ]]; then
    if [[ "$dry_run" == "true" ]]; then
      repository_state="clean"
    else
      repository_state="$(mel_policy_repository_state)"
    fi
  fi
  if ! policy_result="$(mel_policy_evaluate "$execution_plan" "$profile_file" "$repository_state" "true" "true" "$approvals_csv")"; then
    error_json="$(mel_executor_error "policy" "$policy_result")"
    errors_json="$(mel_executor_json_array_append "$errors_json" "$error_json")"
    mel_output_error "$MEL_CODE_POLICY_INVALID" "policy blocked execution"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "policy" "passed" "policy allowed execution")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_doctor_run "staging" "$profile_file" "json" >/dev/null; then
    mel_output_error "$MEL_CODE_DOCTOR_INVALID" "doctor checks failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "doctor" "passed" "doctor checks passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_executor_run_health "$profile_file" "$staging_root" "$releases_path" "$current_link" "$release_id" "$current_link" "$dry_run" "pre"; then
    mel_output_error "$MEL_CODE_HEALTH_INVALID" "pre-deployment health failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "pre_health" "passed" "pre-deployment health passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_release_verify_layout "$profile_file" "$staging_root" "$dry_run" >/dev/null; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "layout verification failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "layout" "passed" "layout verification passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  release_root="${releases_path}/${release_id}"
  if [[ "$dry_run" == "true" ]]; then
    printf '{\n  "status": "passed",\n  "dry_run": true,\n  "environment": "staging",\n  "release_id": "%s",\n  "staging_root": "%s"\n}\n' "$release_id" "$staging_root"
    return "$MEL_EXIT_SUCCESS"
  fi

  if [[ -L "$current_link" ]]; then
    previous_current="$(readlink "$current_link")"
  fi

  if ! mel_release_prepare "${staging_root}/repo" "$release_root" >/dev/null; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "release preparation failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "prepare_release" "passed" "release prepared")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_plugins_invoke_mock "${MEL_ROOT}/deploy/plugins" "$profile_file" "shared" "{\"release_id\":\"${release_id}\"}" >/dev/null || ! mel_release_link_shared_resources "$profile_file" "$staging_root" "$shared_path" "$release_root" >/dev/null; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "shared resource linking failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "shared" "passed" "shared resources linked")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_plugins_invoke_mock "${MEL_ROOT}/deploy/plugins" "$profile_file" "composer" "{\"release_id\":\"${release_id}\"}" >/dev/null; then
    mel_output_error "$MEL_CODE_PLUGIN_INVALID" "composer plugin failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "composer" "passed" "composer plugin passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_plugins_invoke_mock "${MEL_ROOT}/deploy/plugins" "$profile_file" "drush" "{\"release_id\":\"${release_id}\"}" >/dev/null; then
    mel_output_error "$MEL_CODE_PLUGIN_INVALID" "drush plugin failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "drush" "passed" "drush plugin passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_executor_run_health "$profile_file" "$staging_root" "$releases_path" "$current_link" "$release_id" "$release_root" "false" "release"; then
    mel_output_error "$MEL_CODE_HEALTH_INVALID" "release health failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "release_health" "passed" "release health passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if ! mel_plugins_invoke_mock "${MEL_ROOT}/deploy/plugins" "$profile_file" "switch_current" "{\"release_id\":\"${release_id}\"}" >/dev/null || ! mel_executor_switch_current "$current_link" "$release_root"; then
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "current switch failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "switch_current" "passed" "current switched")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  if [[ "${MEL_EXECUTOR_FAIL_POST_SWITCH:-}" == "1" ]]; then
    rollback_json="$(mel_rollback_restore_current "$current_link" "$previous_current" "${logs_path}/${release_id}.rollback.json" 2>/dev/null || true)"
    error_json="$(mel_executor_error "post_switch_validation" "forced post-switch validation failure")"
    errors_json="$(mel_executor_json_array_append "$errors_json" "$error_json")"
    mel_executor_finish_log "$log_file" "$deployment_id" "$release_id" "$started_at" "$started_epoch" "failed" "$steps_json" "$errors_json" "$rollback_json" >/dev/null
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "post-switch validation failed"
    return "$MEL_EXIT_ERROR"
  fi

  if ! mel_executor_run_health "$profile_file" "$staging_root" "$releases_path" "$current_link" "$release_id" "$release_root" "false" "post" || ! mel_release_verify_layout "$profile_file" "$staging_root" "false" >/dev/null; then
    rollback_json="$(mel_rollback_restore_current "$current_link" "$previous_current" "${logs_path}/${release_id}.rollback.json" 2>/dev/null || true)"
    error_json="$(mel_executor_error "post_switch_validation" "post-switch validation failed")"
    errors_json="$(mel_executor_json_array_append "$errors_json" "$error_json")"
    mel_executor_finish_log "$log_file" "$deployment_id" "$release_id" "$started_at" "$started_epoch" "failed" "$steps_json" "$errors_json" "$rollback_json" >/dev/null
    mel_output_error "$MEL_CODE_EXECUTOR_INVALID" "post-switch validation failed"
    return "$MEL_EXIT_ERROR"
  fi
  step_json="$(mel_executor_step "post_health" "passed" "post-deployment health passed")"
  steps_json="$(mel_executor_json_array_append "$steps_json" "$step_json")"

  version="$(mel_version)"
  commit="$(mel_executor_git_commit)"
  manifest_output="${release_root}/release.json"
  mel_release_manifest_write "$manifest_output" "$deployment_id" "$repository" "$branch" "$commit" "$release_id" "$version" "1" "1" "staging" "$started_at" "deployed"
  mel_executor_finish_log "$log_file" "$deployment_id" "$release_id" "$started_at" "$started_epoch" "passed" "$steps_json" "$errors_json" "$rollback_json" >/dev/null

  printf '{\n  "status": "passed",\n  "environment": "staging",\n  "release_id": "%s",\n  "current": "%s",\n  "release_manifest": "%s",\n  "deployment_log": "%s"\n}\n' "$release_id" "$current_link" "$manifest_output" "$log_file"
}
