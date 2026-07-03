#!/usr/bin/env bash

mel_release_manifest_write() {
  local output_file="$1"
  local deployment_id="$2"
  local repository="$3"
  local branch="$4"
  local commit="$5"
  local release_id="$6"
  local framework_version="$7"
  local planner_version="$8"
  local policy_version="$9"
  local deployment_profile="${10}"
  local created_at="${11}"
  local status="${12}"

  python3 - "$output_file" "$deployment_id" "$repository" "$branch" "$commit" "$release_id" "$framework_version" "$planner_version" "$policy_version" "$deployment_profile" "$created_at" "$status" <<'PY'
import json
import os
import sys

(
    output_file,
    deployment_id,
    repository,
    branch,
    commit,
    release_id,
    framework_version,
    planner_version,
    policy_version,
    deployment_profile,
    created_at,
    status,
) = sys.argv[1:13]

os.makedirs(os.path.dirname(output_file), exist_ok=True)
manifest = {
    "deployment_id": deployment_id,
    "repository": repository,
    "branch": branch,
    "commit": commit,
    "release_id": release_id,
    "framework_version": framework_version,
    "planner_version": planner_version,
    "policy_version": policy_version,
    "deployment_profile": deployment_profile,
    "created_at": created_at,
    "status": status,
}

with open(output_file, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
}

mel_execution_log_write() {
  local output_file="$1"
  local deployment_id="$2"
  local release_id="$3"
  local started_at="$4"
  local finished_at="$5"
  local duration_seconds="$6"
  local status="$7"
  local steps_json="$8"
  local errors_json="$9"
  local rollback_json="${10}"

  python3 - "$output_file" "$deployment_id" "$release_id" "$started_at" "$finished_at" "$duration_seconds" "$status" "$steps_json" "$errors_json" "$rollback_json" <<'PY'
import json
import os
import sys

(
    output_file,
    deployment_id,
    release_id,
    started_at,
    finished_at,
    duration_seconds,
    status,
    steps_text,
    errors_text,
    rollback_text,
) = sys.argv[1:11]

os.makedirs(os.path.dirname(output_file), exist_ok=True)
log = {
    "deployment_id": deployment_id,
    "release_id": release_id,
    "start": started_at,
    "finish": finished_at,
    "duration": int(duration_seconds),
    "status": status,
    "steps": json.loads(steps_text),
    "errors": json.loads(errors_text),
    "rollback": json.loads(rollback_text),
}

with open(output_file, "w", encoding="utf-8") as handle:
    json.dump(log, handle, indent=2)
    handle.write("\n")
PY
}
