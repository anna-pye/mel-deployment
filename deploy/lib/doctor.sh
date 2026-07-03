#!/usr/bin/env bash

mel_doctor_default_profile_file() {
  local environment="$1"

  printf '%s\n' "${MEL_ROOT}/profiles/${environment}.json"
}

mel_doctor_run() {
  local environment="$1"
  local profile_file="$2"
  local output_format="$3"

  python3 - "$environment" "$profile_file" "$output_format" <<'PY'
import json
import sys

environment = sys.argv[1]
profile_file = sys.argv[2]
output_format = sys.argv[3]

SUPPORTED_ENVIRONMENTS = {"staging", "production"}
SUPPORTED_CHECKS = {
    "ssh_connectivity",
    "php_version",
    "composer_availability",
    "drush_availability",
    "writable_directories",
    "directory_layout",
    "required_symlinks",
    "disk_space",
    "permissions",
}


class DoctorError(Exception):
    pass


def load_profile(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except FileNotFoundError as exc:
        raise DoctorError(f"profile file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise DoctorError(
            f"profile JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc

    if not isinstance(loaded, dict):
        raise DoctorError("profile root must be an object")
    return loaded


def text(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise DoctorError(f"{location}.{key} is required")
    return value.strip()


def doctor_checks(profile):
    checks = profile.get("doctor_checks", [])
    if not isinstance(checks, list):
        raise DoctorError("profile.doctor_checks must be a list")
    return checks


def evaluate_check(check, index):
    if not isinstance(check, dict):
        raise DoctorError(f"profile.doctor_checks[{index}] must be an object")

    name = text(check, "name", f"profile.doctor_checks[{index}]")
    kind = text(check, "type", f"profile.doctor_checks[{index}]")
    mode = check.get("mode", "mock")

    if kind not in SUPPORTED_CHECKS:
        raise DoctorError(f"unsupported doctor check type: {kind}")
    if mode != "mock":
        raise DoctorError(f"doctor check {name} uses unsupported mode: {mode}")

    return {
        "name": name,
        "type": kind,
        "status": "passed",
        "mode": "mock",
        "message": "mock read-only check definition is valid",
    }


def print_human(result):
    print("Server doctor")
    print(f"Environment: {result['environment']}")
    print(f"Profile: {result['profile']}")
    print("")
    for check in result["checks"]:
        print(f"✓ {check['name']} ({check['type']})")
    print("")
    print("No server state was modified.")


try:
    if environment not in SUPPORTED_ENVIRONMENTS:
        raise DoctorError(f"unsupported doctor environment: {environment}")
    if output_format not in {"human", "json", "both"}:
        raise DoctorError(f"unsupported doctor output format: {output_format}")

    profile = load_profile(profile_file)
    profile_environment = text(profile, "environment", "profile")
    profile_name = text(profile, "profile", "profile")
    if profile_environment != environment:
        raise DoctorError(
            f"profile environment {profile_environment} does not match requested environment {environment}"
        )

    checks = [evaluate_check(check, index) for index, check in enumerate(doctor_checks(profile))]
    result = {
        "status": "passed",
        "environment": environment,
        "profile": profile_name,
        "checks": checks,
    }

    if output_format in {"human", "both"}:
        print_human(result)
    if output_format == "both":
        print("")
    if output_format in {"json", "both"}:
        print(json.dumps(result, indent=2))
    sys.exit(0)
except DoctorError as exc:
    result = {"status": "failed", "environment": environment, "error": str(exc)}
    if output_format in {"human", "both"}:
        print("Server doctor")
        print(f"Environment: {environment}")
        print(f"Error: {exc}")
    if output_format == "both":
        print("")
    if output_format in {"json", "both"}:
        print(json.dumps(result, indent=2))
    sys.exit(2)
PY
}
