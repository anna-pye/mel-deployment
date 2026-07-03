#!/usr/bin/env bash

mel_health_evaluate_checks() {
  local checks_json="$1"
  local state_json="$2"

  python3 - "$checks_json" "$state_json" <<'PY'
import json
import sys

checks_text = sys.argv[1]
state_text = sys.argv[2]

SUPPORTED_CHECKS = {
    "http_response",
    "drupal_status_endpoint",
    "directory_exists",
    "release_exists",
    "current_symlink",
}


class HealthError(Exception):
    pass


def load_json(value, label):
    try:
        loaded = json.loads(value)
    except json.JSONDecodeError as exc:
        raise HealthError(
            f"{label} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc
    return loaded


def check_name(check, index):
    name = check.get("name")
    if not isinstance(name, str) or not name.strip():
        raise HealthError(f"health_checks[{index}].name is required")
    return name.strip()


def check_type(check, index):
    value = check.get("type")
    if value not in SUPPORTED_CHECKS:
        raise HealthError(f"unsupported health check type: {value}")
    return value


def state_mapping(state, key):
    value = state.get(key, {})
    if not isinstance(value, dict):
        raise HealthError(f"state.{key} must be an object")
    return value


def evaluate(check, state, index):
    name = check_name(check, index)
    kind = check_type(check, index)

    if kind == "http_response":
        statuses = state_mapping(state, "http_response")
        status = statuses.get(name)
        passed = isinstance(status, int) and 200 <= status < 400
        return name, kind, passed, f"HTTP status {status}" if isinstance(status, int) else "HTTP status missing"

    if kind == "drupal_status_endpoint":
        statuses = state_mapping(state, "drupal_status_endpoint")
        status = statuses.get(name)
        passed = status == "ok"
        return name, kind, passed, f"Drupal status {status}" if isinstance(status, str) else "Drupal status missing"

    if kind == "directory_exists":
        directories = state_mapping(state, "directory_exists")
        path = check.get("path")
        if not isinstance(path, str) or not path.strip():
            raise HealthError(f"health_checks[{index}].path is required")
        passed = directories.get(path) is True
        return name, kind, passed, f"directory {path} exists" if passed else f"directory {path} missing"

    if kind == "release_exists":
        releases = state_mapping(state, "release_exists")
        release = check.get("release")
        if not isinstance(release, str) or not release.strip():
            raise HealthError(f"health_checks[{index}].release is required")
        passed = releases.get(release) is True
        return name, kind, passed, f"release {release} exists" if passed else f"release {release} missing"

    symlinks = state_mapping(state, "current_symlink")
    link = check.get("link")
    target = check.get("target")
    if not isinstance(link, str) or not link.strip():
        raise HealthError(f"health_checks[{index}].link is required")
    if not isinstance(target, str) or not target.strip():
        raise HealthError(f"health_checks[{index}].target is required")
    passed = symlinks.get(link) == target
    return name, kind, passed, f"{link} points to {target}" if passed else f"{link} does not point to {target}"


try:
    checks = load_json(checks_text, "health checks")
    state = load_json(state_text, "health state")
    if not isinstance(checks, list):
        raise HealthError("health checks root must be a list")
    if not isinstance(state, dict):
        raise HealthError("health state root must be an object")

    results = []
    for index, check in enumerate(checks):
        if not isinstance(check, dict):
            raise HealthError(f"health_checks[{index}] must be an object")
        name, kind, passed, message = evaluate(check, state, index)
        results.append({"name": name, "type": kind, "status": "passed" if passed else "failed", "message": message})

    overall = "passed" if all(result["status"] == "passed" for result in results) else "failed"
    print(json.dumps({"status": overall, "checks": results}, indent=2))
    sys.exit(0 if overall == "passed" else 2)
except HealthError as exc:
    print(json.dumps({"status": "failed", "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}
