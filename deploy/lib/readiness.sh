#!/usr/bin/env bash

mel_readiness_default_profile_file() {
  local environment="$1"

  printf '%s\n' "${MEL_ROOT}/profiles/${environment}.json"
}

mel_readiness_verify() {
  local environment="$1"
  local profile_file="$2"
  local check="${3:-all}"

  python3 - "$environment" "$profile_file" "$check" <<'PY'
import json
import os
import sys

environment, profile_file, requested_check = sys.argv[1:4]

SUPPORTED_CHECKS = {"all", "profile", "layout", "health"}
SUPPORTED_HEALTH = {"http_response", "drupal_status_endpoint", "directory_exists", "current_symlink"}


class ReadinessError(Exception):
    pass


def load_profile(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except FileNotFoundError as exc:
        raise ReadinessError(f"profile file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ReadinessError(
            f"profile JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc
    if not isinstance(loaded, dict):
        raise ReadinessError("profile root must be an object")
    return loaded


def text(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ReadinessError(f"{location}.{key} is required")
    return value.strip()


def object_value(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, dict):
        raise ReadinessError(f"{location}.{key} must be an object")
    return value


def list_value(mapping, key, location):
    value = mapping.get(key, [])
    if not isinstance(value, list):
        raise ReadinessError(f"{location}.{key} must be a list")
    return value


def configured_path(profile, key):
    paths = profile.get("paths", {})
    root = text(profile, "deployment_root", "profile")
    defaults = {
        "deployment_root": root,
        "releases": os.path.join(root, "releases"),
        "shared": os.path.join(root, "shared"),
        "current": os.path.join(root, "current"),
        "logs": os.path.join(root, "logs"),
    }
    if key == "deployment_root":
        return root
    if isinstance(paths, dict) and isinstance(paths.get(key), str) and paths[key].strip():
        return paths[key].strip()
    return defaults[key]


def add_failure(failures, check, message):
    failures.append({"check": check, "message": message})


def validate_profile(profile):
    failures = []
    required_text = [
        ("profile", "profile"),
        ("profile_version", "profile"),
        ("environment", "profile"),
        ("validation_profile", "profile"),
        ("policy_profile", "profile"),
        ("deployment_root", "profile"),
        ("repository", "profile"),
    ]
    for key, location in required_text:
        try:
            text(profile, key, location)
        except ReadinessError as exc:
            add_failure(failures, key, str(exc))

    if profile.get("environment") != environment:
        add_failure(
            failures,
            "environment",
            f"profile environment {profile.get('environment')} does not match requested environment {environment}",
        )

    try:
        ssh = object_value(profile, "ssh", "profile")
        text(ssh, "host", "profile.ssh")
        text(ssh, "user", "profile.ssh")
    except ReadinessError as exc:
        add_failure(failures, "ssh", str(exc))

    try:
        paths = object_value(profile, "paths", "profile")
        for key in ("releases", "shared", "current", "logs"):
            text(paths, key, "profile.paths")
    except ReadinessError as exc:
        add_failure(failures, "paths", str(exc))

    try:
        executables = object_value(profile, "executables", "profile")
        text(executables, "composer", "profile.executables")
        text(executables, "drush", "profile.executables")
    except ReadinessError as exc:
        add_failure(failures, "executables", str(exc))

    for key in ("shared_resources", "health_checks", "doctor_checks"):
        try:
            list_value(profile, key, "profile")
        except ReadinessError as exc:
            add_failure(failures, key, str(exc))

    health_endpoints = profile.get("health_endpoints", [])
    if not isinstance(health_endpoints, list):
        add_failure(failures, "health_endpoints", "profile.health_endpoints must be a list")

    return {
        "status": "passed" if not failures else "failed",
        "failures": failures,
    }


def verification_mode(profile):
    verification = profile.get("verification", {})
    if not isinstance(verification, dict):
        return "profile"
    mode = verification.get("mode", "profile")
    if mode not in {"profile", "local"}:
        raise ReadinessError(f"unsupported verification mode: {mode}")
    return mode


def evaluate_layout(profile):
    mode = verification_mode(profile)
    paths = {
        "deployment_root": configured_path(profile, "deployment_root"),
        "releases": configured_path(profile, "releases"),
        "shared": configured_path(profile, "shared"),
        "current": configured_path(profile, "current"),
        "logs": configured_path(profile, "logs"),
    }
    failures = []

    if mode == "local":
        for label in ("deployment_root", "releases", "shared", "logs"):
            if not os.path.isdir(paths[label]):
                add_failure(failures, label, f"{label} directory is missing: {paths[label]}")
        if not os.path.islink(paths["current"]):
            add_failure(failures, "current", f"current symlink is missing or not a symlink: {paths['current']}")
        elif not os.path.exists(os.path.realpath(paths["current"])):
            add_failure(failures, "current", f"current symlink target is missing: {paths['current']}")

        shared_root = paths["shared"]
        for index, resource in enumerate(list_value(profile, "shared_resources", "profile")):
            if not isinstance(resource, dict):
                add_failure(failures, "shared_resources", f"profile.shared_resources[{index}] must be an object")
                continue
            name = resource.get("name")
            kind = resource.get("type", "directory")
            if not isinstance(name, str) or not name.strip():
                add_failure(failures, "shared_resources", f"profile.shared_resources[{index}].name is required")
                continue
            resource_path = os.path.join(shared_root, name.strip().strip("/"))
            if kind == "directory" and not os.path.isdir(resource_path):
                add_failure(failures, "shared_resources", f"required shared directory is missing: {name}")
            elif kind == "file" and not os.path.isfile(resource_path):
                add_failure(failures, "shared_resources", f"required shared file is missing: {name}")
            elif kind not in {"directory", "file"}:
                add_failure(failures, "shared_resources", f"unsupported shared resource type: {kind}")

    return {
        "status": "passed" if not failures else "failed",
        "mode": mode,
        "paths": paths,
        "failures": failures,
    }


def health_state(profile):
    state = {
        "http_response": {},
        "drupal_status_endpoint": {},
        "directory_exists": {},
        "current_symlink": {},
    }
    configured = profile.get("health_state", {})
    if not isinstance(configured, dict):
        configured = {}
    paths = {
        "deployment_root": configured_path(profile, "deployment_root"),
        "shared": configured_path(profile, "shared"),
        "current": configured_path(profile, "current"),
    }
    mode = verification_mode(profile)
    for check in list_value(profile, "health_checks", "profile"):
        if not isinstance(check, dict):
            continue
        name = check.get("name")
        kind = check.get("type")
        if not isinstance(name, str):
            continue
        if kind == "http_response":
            state["http_response"][name] = int(configured.get(name, 200))
        elif kind == "drupal_status_endpoint":
            state["drupal_status_endpoint"][name] = str(configured.get(name, "ok"))
        elif kind == "directory_exists":
            path = check.get("path") or paths["deployment_root"]
            state["directory_exists"][path] = bool(configured.get(path, True if mode == "profile" else os.path.isdir(path)))
        elif kind == "current_symlink":
            link = check.get("link") or paths["current"]
            target = check.get("target")
            if not isinstance(target, str) or not target.strip():
                target = os.path.realpath(link) if mode == "local" and os.path.islink(link) else link
            state["current_symlink"][link] = configured.get(link, target)
    return state


def evaluate_health(profile):
    checks = list_value(profile, "health_checks", "profile")
    state = health_state(profile)
    results = []
    failures = []

    for index, check in enumerate(checks):
        if not isinstance(check, dict):
            add_failure(failures, "health", f"profile.health_checks[{index}] must be an object")
            continue
        name = check.get("name")
        kind = check.get("type")
        if not isinstance(name, str) or not name.strip():
            add_failure(failures, "health", f"profile.health_checks[{index}].name is required")
            continue
        if kind not in SUPPORTED_HEALTH:
            add_failure(failures, "health", f"unsupported health check type: {kind}")
            continue

        if kind == "http_response":
            status = state["http_response"].get(name)
            passed = isinstance(status, int) and 200 <= status < 400
            message = f"HTTP status {status}" if isinstance(status, int) else "HTTP status missing"
        elif kind == "drupal_status_endpoint":
            status = state["drupal_status_endpoint"].get(name)
            passed = status == "ok"
            message = f"Drupal status {status}" if isinstance(status, str) else "Drupal status missing"
        elif kind == "directory_exists":
            path = check.get("path") or configured_path(profile, "deployment_root")
            passed = state["directory_exists"].get(path) is True
            message = f"directory {path} exists" if passed else f"directory {path} missing"
        else:
            link = check.get("link") or configured_path(profile, "current")
            target = check.get("target") or state["current_symlink"].get(link)
            passed = state["current_symlink"].get(link) == target
            message = f"{link} points to {target}" if passed else f"{link} does not point to {target}"

        result = {"name": name, "type": kind, "status": "passed" if passed else "failed", "message": message}
        results.append(result)
        if not passed:
            add_failure(failures, name, message)

    return {
        "status": "passed" if not failures else "failed",
        "checks": results,
        "failures": failures,
    }


try:
    if environment != "staging":
        raise ReadinessError("readiness verification supports staging only")
    if requested_check not in SUPPORTED_CHECKS:
        raise ReadinessError(f"unsupported verification check: {requested_check}")

    profile = load_profile(profile_file)
    result = {
        "status": "passed",
        "environment": environment,
        "profile": profile.get("profile", "unknown"),
        "profile_version": profile.get("profile_version", "unknown"),
        "checks": {},
        "failures": [],
    }

    checks_to_run = ["profile", "layout", "health"] if requested_check == "all" else [requested_check]
    for name in checks_to_run:
        if name == "profile":
            check_result = validate_profile(profile)
        elif name == "layout":
            check_result = evaluate_layout(profile)
        else:
            check_result = evaluate_health(profile)
        result["checks"][name] = check_result
        result["failures"].extend(check_result.get("failures", []))

    if result["failures"]:
        result["status"] = "failed"

    print(json.dumps(result, indent=2))
    sys.exit(0 if result["status"] == "passed" else 2)
except ReadinessError as exc:
    print(json.dumps({"status": "failed", "environment": environment, "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}

mel_readiness_report() {
  local environment="$1"
  local profile_file="$2"
  local manifest_file="$3"
  local schema_file="$4"
  local repository_state="$5"
  local approvals_csv="$6"

  python3 - "$environment" "$profile_file" "$manifest_file" "$schema_file" "$repository_state" "$approvals_csv" "$MEL_ROOT" <<'PY'
import json
import subprocess
import sys

environment, profile_file, manifest_file, schema_file, repository_state, approvals_csv, mel_root = sys.argv[1:8]
mel = f"{mel_root}/deploy/bin/mel"


def run(args):
    completed = subprocess.run(args, cwd=mel_root, text=True, capture_output=True, check=False)
    return completed.returncode, completed.stdout.strip(), completed.stderr.strip()


def load_json(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {}


def status_from_json(value, key="status"):
    if not isinstance(value, dict):
        return "failed"
    return value.get(key, "failed")


def collect_blockers(label, value):
    blockers = []
    if not isinstance(value, dict):
        return [f"{label} did not return structured JSON"]
    for failure in value.get("failures", []):
        if isinstance(failure, dict):
            blockers.append(f"{label}: {failure.get('message', failure)}")
    if value.get("error"):
        blockers.append(f"{label}: {value['error']}")
    return blockers


with open(profile_file, "r", encoding="utf-8") as handle:
    profile = json.load(handle)
with open(f"{mel_root}/VERSION", "r", encoding="utf-8") as handle:
    framework_version = handle.read().strip()

validation_code, _, validation_error = run([mel, "validate", "--manifest", manifest_file, "--schema", schema_file])
resolve_code, resolved_text, resolve_error = run([mel, "resolve", "--manifest", manifest_file, "--schema", schema_file])
plan_code, plan_text, plan_error = run([mel, "plan", "--manifest", manifest_file, "--schema", schema_file])

policy_json = {}
if plan_code == 0:
    policy_args = [mel, "policy", "--manifest", manifest_file, "--schema", schema_file, "--profile", profile_file, "--repository-state", repository_state]
    for approval in [item for item in approvals_csv.split(",") if item]:
        policy_args.extend(["--approval", approval])
    policy_code, policy_text, _ = run(policy_args)
    policy_json = load_json(policy_text)
else:
    policy_code = 2
    policy_json = {"decision": "blocked", "error": plan_error or "planner failed"}

doctor_code, doctor_text, _ = run([mel, "doctor", environment, "--profile", profile_file, "--json"])
verify_code, verify_text, _ = run([mel, "verify", environment, "--profile", profile_file, "--json"])

doctor_json = load_json(doctor_text)
verify_json = load_json(verify_text)
layout_json = verify_json.get("checks", {}).get("layout", {}) if isinstance(verify_json, dict) else {}
health_json = verify_json.get("checks", {}).get("health", {}) if isinstance(verify_json, dict) else {}

blockers = []
if validation_code != 0:
    blockers.append(f"validation: {validation_error or 'manifest validation failed'}")
if resolve_code != 0:
    blockers.append(f"resolution: {resolve_error or 'resolution failed'}")
if plan_code != 0:
    blockers.append(f"planner: {plan_error or 'planner failed'}")
if policy_code != 0:
    blockers.append(f"policy: {policy_json.get('error', policy_json.get('decision', 'blocked'))}")
if doctor_code != 0:
    blockers.extend(collect_blockers("doctor", doctor_json))
if verify_code != 0:
    blockers.extend(collect_blockers("verify", verify_json))
if status_from_json(layout_json) != "passed":
    blockers.extend(collect_blockers("layout", layout_json))
if status_from_json(health_json) != "passed":
    blockers.extend(collect_blockers("health", health_json))

ready = not blockers
report = {
    "environment": environment,
    "repository": profile.get("repository", "unknown"),
    "framework_version": framework_version,
    "profile_version": profile.get("profile_version", "unknown"),
    "doctor_status": status_from_json(doctor_json),
    "health_status": status_from_json(health_json),
    "layout_status": status_from_json(layout_json),
    "policy_status": policy_json.get("decision", "blocked"),
    "deployment_ready": "READY" if ready else "NOT READY",
    "blocking_reasons": blockers,
}

print("Deployment report")
print(f"Environment: {report['environment']}")
print(f"Repository: {report['repository']}")
print(f"Framework Version: {report['framework_version']}")
print(f"Profile Version: {report['profile_version']}")
print(f"Doctor Status: {report['doctor_status']}")
print(f"Health Status: {report['health_status']}")
print(f"Layout Status: {report['layout_status']}")
print(f"Policy Status: {report['policy_status']}")
print(f"Deployment Ready: {report['deployment_ready']}")
if blockers:
    print("Blocking Reasons:")
    for blocker in blockers:
        print(f"- {blocker}")
print("")
print(json.dumps(report, indent=2))
sys.exit(0)
PY
}
