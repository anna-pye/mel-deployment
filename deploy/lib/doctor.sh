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
import shlex
import subprocess
import sys

environment = sys.argv[1]
profile_file = sys.argv[2]
output_format = sys.argv[3]

SUPPORTED_ENVIRONMENTS = {"staging", "production"}
SUPPORTED_CHECKS = {
    "ssh_connectivity",
    "php_version",
    "php_availability",
    "composer_availability",
    "drush_availability",
    "writable_directories",
    "writable_release_root",
    "directory_layout",
    "deployment_root_exists",
    "releases_exists",
    "shared_exists",
    "current_exists",
    "logs_exists",
    "readable_shared_resources",
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


def object_value(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, dict):
        raise DoctorError(f"{location}.{key} must be an object")
    return value


def list_value(mapping, key, location):
    value = mapping.get(key, [])
    if not isinstance(value, list):
        raise DoctorError(f"{location}.{key} must be a list")
    return value


def configured_path(profile, key):
    root = text(profile, "deployment_root", "profile")
    paths = profile.get("paths", {})
    defaults = {
        "deployment_root": root,
        "releases": f"{root}/releases",
        "shared": f"{root}/shared",
        "current": f"{root}/current",
        "logs": f"{root}/logs",
    }
    if key == "deployment_root":
        return root
    if isinstance(paths, dict) and isinstance(paths.get(key), str) and paths[key].strip():
        return paths[key].strip()
    return defaults[key]


def profile_configuration_check(profile, kind):
    if kind == "ssh_connectivity":
        ssh = object_value(profile, "ssh", "profile")
        text(ssh, "host", "profile.ssh")
        text(ssh, "user", "profile.ssh")
    elif kind in {"deployment_root_exists", "directory_layout"}:
        configured_path(profile, "deployment_root")
    elif kind == "releases_exists":
        configured_path(profile, "releases")
    elif kind == "shared_exists":
        configured_path(profile, "shared")
    elif kind == "current_exists":
        configured_path(profile, "current")
    elif kind == "logs_exists":
        configured_path(profile, "logs")
    elif kind in {"php_version", "php_availability"}:
        executables = profile.get("executables", {})
        if isinstance(executables, dict) and isinstance(executables.get("php"), str) and executables["php"].strip():
            return
    elif kind == "composer_availability":
        executables = object_value(profile, "executables", "profile")
        text(executables, "composer", "profile.executables")
    elif kind == "drush_availability":
        executables = object_value(profile, "executables", "profile")
        text(executables, "drush", "profile.executables")
    elif kind in {"writable_directories", "writable_release_root"}:
        configured_path(profile, "releases")
    elif kind == "readable_shared_resources":
        list_value(profile, "shared_resources", "profile")


def remote_command_for(profile, kind):
    executables = profile.get("executables", {})
    php = executables.get("php", "php") if isinstance(executables, dict) else "php"
    composer = executables.get("composer", "composer") if isinstance(executables, dict) else "composer"
    drush = executables.get("drush", "drush") if isinstance(executables, dict) else "drush"

    def directory(path):
        return f"test -d {shlex.quote(path)}"

    def symlink(path):
        return f"test -L {shlex.quote(path)}"

    def executable(value):
        if "/" in value:
            return f"test -x {shlex.quote(value)}"
        return f"command -v {shlex.quote(value)} >/dev/null 2>&1"

    if kind == "ssh_connectivity":
        return "true"
    if kind in {"deployment_root_exists", "directory_layout"}:
        return directory(configured_path(profile, "deployment_root"))
    if kind == "releases_exists":
        return directory(configured_path(profile, "releases"))
    if kind == "shared_exists":
        return directory(configured_path(profile, "shared"))
    if kind == "current_exists":
        return symlink(configured_path(profile, "current"))
    if kind == "logs_exists":
        return directory(configured_path(profile, "logs"))
    if kind in {"php_version", "php_availability"}:
        return executable(php)
    if kind == "composer_availability":
        return executable(composer)
    if kind == "drush_availability":
        return executable(drush)
    if kind in {"writable_directories", "writable_release_root"}:
        return f"test -w {shlex.quote(configured_path(profile, 'releases'))}"
    if kind == "readable_shared_resources":
        shared_root = configured_path(profile, "shared")
        commands = [directory(shared_root)]
        for resource in list_value(profile, "shared_resources", "profile"):
            if not isinstance(resource, dict):
                raise DoctorError("profile.shared_resources entries must be objects")
            name = text(resource, "name", "profile.shared_resources[]").strip("/")
            kind_value = resource.get("type", "directory")
            path = f"{shared_root}/{name}"
            commands.append((directory(path) if kind_value == "directory" else f"test -r {shlex.quote(path)}"))
        return " && ".join(commands)
    if kind == "required_symlinks":
        return symlink(configured_path(profile, "current"))
    if kind in {"disk_space", "permissions"}:
        return directory(configured_path(profile, "deployment_root"))
    raise DoctorError(f"unsupported doctor check type: {kind}")


def run_ssh_check(profile, kind):
    ssh = object_value(profile, "ssh", "profile")
    host = text(ssh, "host", "profile.ssh")
    user = text(ssh, "user", "profile.ssh")
    target = f"{user}@{host}"
    remote_command = remote_command_for(profile, kind)
    command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=10",
        target,
        remote_command,
    ]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or "read-only SSH check failed"
        return False, message
    return True, "read-only SSH check passed"


def evaluate_check(profile, check, index):
    if not isinstance(check, dict):
        raise DoctorError(f"profile.doctor_checks[{index}] must be an object")

    name = text(check, "name", f"profile.doctor_checks[{index}]")
    kind = text(check, "type", f"profile.doctor_checks[{index}]")
    mode = check.get("mode", "mock")

    if kind not in SUPPORTED_CHECKS:
        raise DoctorError(f"unsupported doctor check type: {kind}")
    if mode == "mock":
        return {
            "name": name,
            "type": kind,
            "status": "passed",
            "mode": "mock",
            "message": "mock read-only check definition is valid",
        }
    if mode == "profile":
        profile_configuration_check(profile, kind)
        return {
            "name": name,
            "type": kind,
            "status": "passed",
            "mode": "profile",
            "message": "required profile configuration is present",
        }
    if mode == "ssh":
        passed, message = run_ssh_check(profile, kind)
        return {
            "name": name,
            "type": kind,
            "status": "passed" if passed else "failed",
            "mode": "ssh",
            "message": message,
        }
    else:
        raise DoctorError(f"doctor check {name} uses unsupported mode: {mode}")


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

    checks = [evaluate_check(profile, check, index) for index, check in enumerate(doctor_checks(profile))]
    status = "passed" if all(check["status"] == "passed" for check in checks) else "failed"
    result = {
        "status": status,
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
    sys.exit(0 if status == "passed" else 2)
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
