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
import os
import shlex
import subprocess
import sys

environment = sys.argv[1]
profile_file = sys.argv[2]
output_format = sys.argv[3]

SUPPORTED_ENVIRONMENTS = {"staging", "production"}
SUPPORTED_CHECKS = {
    "ssh_connectivity",
    "remote_hostname",
    "remote_user",
    "php_version",
    "php_availability",
    "composer_availability",
    "drush_availability",
    "writable_directories",
    "writable_release_root",
    "directory_layout",
    "deployment_root_exists",
    "repo_exists",
    "release_integrity",
    "drupal_bootstrap",
    "releases_exists",
    "shared_exists",
    "current_exists",
    "current_target_exists",
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
    repository_path = profile.get("repository_path")
    defaults = {
        "deployment_root": root,
        "repo": f"{root}/repo",
        "releases": f"{root}/releases",
        "shared": f"{root}/shared",
        "current": f"{root}/current",
        "logs": f"{root}/logs",
    }
    if key == "deployment_root":
        return root
    if key == "repo" and isinstance(repository_path, str) and repository_path.strip():
        return repository_path.strip()
    if isinstance(paths, dict) and isinstance(paths.get(key), str) and paths[key].strip():
        return paths[key].strip()
    return defaults[key]


def profile_configuration_check(profile, kind):
    if kind == "ssh_connectivity":
        ssh = object_value(profile, "ssh", "profile")
        text(ssh, "host", "profile.ssh")
        text(ssh, "user", "profile.ssh")
    elif kind in {"remote_hostname", "remote_user"}:
        ssh = object_value(profile, "ssh", "profile")
        text(ssh, "host", "profile.ssh")
        text(ssh, "user", "profile.ssh")
    elif kind in {"deployment_root_exists", "directory_layout"}:
        configured_path(profile, "deployment_root")
    elif kind == "repo_exists":
        configured_path(profile, "repo")
    elif kind in {"release_integrity", "drupal_bootstrap"}:
        configured_path(profile, "current")
    elif kind == "releases_exists":
        configured_path(profile, "releases")
    elif kind == "shared_exists":
        configured_path(profile, "shared")
    elif kind == "current_exists":
        configured_path(profile, "current")
    elif kind == "current_target_exists":
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

    def drush_executable():
        current_drush = f"{configured_path(profile, 'current')}/vendor/bin/drush"
        configured_drush = drush
        return (
            f"if [ -x {shlex.quote(current_drush)} ]; then exit 0; fi; "
            f"case {shlex.quote(configured_drush)} in /*) [ -x {shlex.quote(configured_drush)} ] && exit 0 ;; esac; "
            "command -v drush >/dev/null 2>&1"
        )

    if kind in {"ssh_connectivity", "remote_hostname", "remote_user"}:
        return "true"
    if kind in {"deployment_root_exists", "directory_layout"}:
        return directory(configured_path(profile, "deployment_root"))
    if kind == "repo_exists":
        return directory(configured_path(profile, "repo"))
    if kind in {"release_integrity", "drupal_bootstrap"}:
        return f"test -L {shlex.quote(configured_path(profile, 'current'))}"
    if kind == "releases_exists":
        return directory(configured_path(profile, "releases"))
    if kind == "shared_exists":
        return directory(configured_path(profile, "shared"))
    if kind == "current_exists":
        return symlink(configured_path(profile, "current"))
    if kind == "current_target_exists":
        current = configured_path(profile, "current")
        return f"test -L {shlex.quote(current)} && test -e \"$(readlink -f {shlex.quote(current)})\""
    if kind == "logs_exists":
        return directory(configured_path(profile, "logs"))
    if kind in {"php_version", "php_availability"}:
        return executable(php)
    if kind == "composer_availability":
        return executable(composer)
    if kind == "drush_availability":
        return drush_executable()
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


def parse_snapshot_lines(text):
    values = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        key, separator, value = line.partition("\t")
        if not separator:
            key, separator, value = line.partition("=")
        if separator:
            values[key.strip()] = value.strip()
    return values


def bool_value(values, key):
    return values.get(key, "").lower() == "true"


def int_value(values, key, default=0):
    try:
        return int(values.get(key, default))
    except (TypeError, ValueError):
        return default


def live_snapshot_script(profile):
    root = configured_path(profile, "deployment_root")
    repo = configured_path(profile, "repo")
    releases = configured_path(profile, "releases")
    shared = configured_path(profile, "shared")
    current = configured_path(profile, "current")
    logs = configured_path(profile, "logs")
    executables = profile.get("executables", {})
    php = executables.get("php", "php") if isinstance(executables, dict) else "php"
    composer = executables.get("composer", "composer") if isinstance(executables, dict) else "composer"
    drush = executables.get("drush", "drush") if isinstance(executables, dict) else "drush"
    shared_resources = []
    for resource in list_value(profile, "shared_resources", "profile"):
        if isinstance(resource, dict) and isinstance(resource.get("name"), str):
            shared_resources.append(resource["name"].strip().strip("/"))
    shared_resource_args = " ".join(shlex.quote(resource) for resource in shared_resources)

    return f"""set -u
say() {{ printf '%s\\t%s\\n' "$1" "$2"; }}
bool_path() {{ if [ "$1" "$2" ]; then say "$3" true; else say "$3" false; fi; }}
cmd_path() {{ command -v "$1" 2>/dev/null || true; }}
first_line() {{ "$@" 2>&1 | awk 'NR==1 {{ print; exit }}'; }}
resolve_drush() {{
  current_root="$1"
  if [ -n "$current_root" ] && [ -x "$current_root/vendor/bin/drush" ]; then
    printf '%s\\n' "$current_root/vendor/bin/drush"
    return
  fi
  case "$DRUSH_BIN" in
    /*)
      if [ -x "$DRUSH_BIN" ]; then
        printf '%s\\n' "$DRUSH_BIN"
        return
      fi
      ;;
  esac
  command -v drush 2>/dev/null || true
}}

DEPLOYMENT_ROOT={shlex.quote(root)}
REPO_DIR={shlex.quote(repo)}
RELEASES_DIR={shlex.quote(releases)}
SHARED_DIR={shlex.quote(shared)}
CURRENT_LINK={shlex.quote(current)}
LOGS_DIR={shlex.quote(logs)}
PHP_BIN={shlex.quote(php)}
COMPOSER_BIN={shlex.quote(composer)}
DRUSH_BIN={shlex.quote(drush)}

say hostname "$(hostname 2>/dev/null || true)"
say user "$(whoami 2>/dev/null || true)"
bool_path -d "$DEPLOYMENT_ROOT" deployment_root_exists
say repo "$REPO_DIR"
bool_path -d "$REPO_DIR" repo_exists
bool_path -d "$RELEASES_DIR" releases_exists
bool_path -d "$SHARED_DIR" shared_exists
bool_path -L "$CURRENT_LINK" current_symlink_exists
bool_path -d "$LOGS_DIR" logs_exists

CURRENT_TARGET=""
CURRENT_TARGET_RESOLVED=""
if [ -L "$CURRENT_LINK" ]; then
  CURRENT_TARGET="$(readlink "$CURRENT_LINK" 2>/dev/null || true)"
  CURRENT_TARGET_RESOLVED="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
fi
say current_target "$CURRENT_TARGET"
say current_target_resolved "$CURRENT_TARGET_RESOLVED"
if [ -n "$CURRENT_TARGET_RESOLVED" ] && [ -e "$CURRENT_TARGET_RESOLVED" ]; then
  say current_target_exists true
else
  say current_target_exists false
fi
if [ -n "$CURRENT_TARGET_RESOLVED" ]; then
  say current_release "$(basename "$CURRENT_TARGET_RESOLVED")"
else
  say current_release ""
fi

if [ -d "$RELEASES_DIR" ]; then
  say release_count "$(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
else
  say release_count 0
fi

PHP_PATH="$(cmd_path "$PHP_BIN")"
COMPOSER_PATH="$(cmd_path "$COMPOSER_BIN")"
DRUSH_ROOT="$CURRENT_TARGET_RESOLVED"
if [ -z "$DRUSH_ROOT" ]; then
  DRUSH_ROOT="$CURRENT_LINK"
fi
DRUSH_PATH="$(resolve_drush "$DRUSH_ROOT")"
say php_path "$PHP_PATH"
say composer_path "$COMPOSER_PATH"
say drush_path "$DRUSH_PATH"
if [ -n "$PHP_PATH" ]; then say php_version "$(first_line "$PHP_BIN" --version)"; else say php_version ""; fi
if [ -n "$COMPOSER_PATH" ]; then say composer_version "$(first_line "$COMPOSER_BIN" --version)"; else say composer_version ""; fi
if [ -n "$DRUSH_PATH" ]; then say drush_version "$(first_line "$DRUSH_PATH" --version)"; else say drush_version ""; fi

if [ -d "$DEPLOYMENT_ROOT" ]; then
  df -Pk "$DEPLOYMENT_ROOT" 2>/dev/null | awk 'NR==2 {{ printf "disk_available_kb\\t%s\\n", $4; printf "disk_usage\\t%s used, %s available, %s capacity on %s\\n", $3, $4, $5, $6 }}'
else
  say disk_available_kb 0
  say disk_usage ""
fi
bool_path -w "$RELEASES_DIR" writable_release_root
bool_path -r "$SHARED_DIR" readable_shared

SHARED_OK=true
for resource in {shared_resource_args}; do
  if [ -n "$resource" ] && [ ! -r "$SHARED_DIR/$resource" ]; then
    SHARED_OK=false
  fi
done
say shared_resources_readable "$SHARED_OK"

WEB_DOCROOT=""
if [ -n "$CURRENT_TARGET_RESOLVED" ] && [ -d "$CURRENT_TARGET_RESOLVED/web" ]; then
  WEB_DOCROOT="$CURRENT_TARGET_RESOLVED/web"
elif [ -d "$REPO_DIR/web" ]; then
  WEB_DOCROOT="$REPO_DIR/web"
fi
say web_docroot "$WEB_DOCROOT"

RELEASE_ROOT="$CURRENT_TARGET_RESOLVED"
RELEASE_INTEGRITY_STATUS="failed"
RELEASE_INTEGRITY_MESSAGE="current release target is missing"
RELEASE_INTEGRITY_MISSING=""
PROJECT_DRUSH_PATH=""
if [ -n "$RELEASE_ROOT" ] && [ -d "$RELEASE_ROOT" ]; then
  RELEASE_INTEGRITY_STATUS="passed"
  RELEASE_INTEGRITY_MESSAGE="release contains required Drupal 11 files"
  for required_file in composer.json vendor/autoload.php vendor/bin/drush web/core/lib/Drupal.php web/index.php; do
    if [ ! -f "$RELEASE_ROOT/$required_file" ]; then
      RELEASE_INTEGRITY_STATUS="failed"
      if [ -z "$RELEASE_INTEGRITY_MISSING" ]; then
        RELEASE_INTEGRITY_MISSING="$required_file"
      else
        RELEASE_INTEGRITY_MISSING="$RELEASE_INTEGRITY_MISSING,$required_file"
      fi
    fi
  done
  PROJECT_DRUSH_PATH="$RELEASE_ROOT/vendor/bin/drush"
  if [ "$RELEASE_INTEGRITY_STATUS" = "passed" ] && [ ! -x "$PROJECT_DRUSH_PATH" ]; then
    RELEASE_INTEGRITY_STATUS="failed"
    RELEASE_INTEGRITY_MISSING="vendor/bin/drush"
    RELEASE_INTEGRITY_MESSAGE="project-local Drush is not executable"
  elif [ "$RELEASE_INTEGRITY_STATUS" = "failed" ]; then
    RELEASE_INTEGRITY_MESSAGE="release is missing required Drupal 11 files"
  fi
fi
say release_integrity_status "$RELEASE_INTEGRITY_STATUS"
say release_integrity_message "$RELEASE_INTEGRITY_MESSAGE"
say release_integrity_missing "$RELEASE_INTEGRITY_MISSING"
say project_drush_path "$PROJECT_DRUSH_PATH"

DRUPAL_BOOTSTRAP_STATUS=""
DRUPAL_BOOTSTRAP_CAPABLE=false
DRUPAL_BOOTSTRAP_FAILURE_REASON=""
if [ "$RELEASE_INTEGRITY_STATUS" != "passed" ]; then
  DRUPAL_BOOTSTRAP_FAILURE_REASON="release_invalid"
elif [ -n "$PROJECT_DRUSH_PATH" ]; then
  DRUPAL_BOOTSTRAP_STATUS="$(cd "$RELEASE_ROOT" && "$PROJECT_DRUSH_PATH" status 2>&1)"
  DRUPAL_BOOTSTRAP_EXIT=$?
  if [ "$DRUPAL_BOOTSTRAP_EXIT" -eq 0 ]; then
    DRUPAL_BOOTSTRAP_CAPABLE=true
  else
    DRUPAL_BOOTSTRAP_FAILURE_REASON="bootstrap_failed"
  fi
  if [ -z "$DRUPAL_BOOTSTRAP_STATUS" ]; then
    DRUPAL_BOOTSTRAP_STATUS="drush status exited $DRUPAL_BOOTSTRAP_EXIT"
  else
    DRUPAL_BOOTSTRAP_STATUS="$(printf '%s\n' "$DRUPAL_BOOTSTRAP_STATUS" | awk 'BEGIN {{ separator="" }} {{ printf "%s%s", separator, $0; separator=" | " }} END {{ print "" }}')"
  fi
fi
say drupal_bootstrap_status "$DRUPAL_BOOTSTRAP_STATUS"
say drupal_bootstrap_capable "$DRUPAL_BOOTSTRAP_CAPABLE"
say drupal_bootstrap_failure_reason "$DRUPAL_BOOTSTRAP_FAILURE_REASON"
"""


def collect_live_snapshot(profile):
    ssh = object_value(profile, "ssh", "profile")
    host = text(ssh, "host", "profile.ssh")
    user = text(ssh, "user", "profile.ssh")
    target = f"{user}@{host}"
    mock_output = os.environ.get("MEL_DOCTOR_SSH_MOCK_OUTPUT", "")
    if mock_output:
        with open(mock_output, "r", encoding="utf-8") as handle:
            values = parse_snapshot_lines(handle.read())
        return snapshot_from_values(profile, values, "mock")

    command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=10",
        target,
        "sh -s",
    ]
    completed = subprocess.run(
        command,
        input=live_snapshot_script(profile),
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip() or "read-only SSH snapshot failed"
        return {
            "mode": "ssh",
            "connected": False,
            "error": message,
            "configured_host": host,
            "configured_user": user,
        }
    return snapshot_from_values(profile, parse_snapshot_lines(completed.stdout), "ssh")


def snapshot_from_values(profile, values, mode):
    ssh = object_value(profile, "ssh", "profile")
    host = text(ssh, "host", "profile.ssh")
    user = text(ssh, "user", "profile.ssh")
    disk_available_kb = int_value(values, "disk_available_kb")
    return {
        "mode": mode,
        "connected": True,
        "configured_host": host,
        "configured_user": user,
        "hostname": values.get("hostname", ""),
        "user": values.get("user", ""),
        "deployment_root": configured_path(profile, "deployment_root"),
        "repo": values.get("repo") or configured_path(profile, "repo"),
        "releases": configured_path(profile, "releases"),
        "shared": configured_path(profile, "shared"),
        "current": configured_path(profile, "current"),
        "logs": configured_path(profile, "logs"),
        "deployment_root_exists": bool_value(values, "deployment_root_exists"),
        "repo_exists": bool_value(values, "repo_exists"),
        "releases_exists": bool_value(values, "releases_exists"),
        "shared_exists": bool_value(values, "shared_exists"),
        "current_symlink_exists": bool_value(values, "current_symlink_exists"),
        "current_target": values.get("current_target", ""),
        "current_target_resolved": values.get("current_target_resolved", ""),
        "current_target_exists": bool_value(values, "current_target_exists"),
        "current_release": values.get("current_release", ""),
        "logs_exists": bool_value(values, "logs_exists"),
        "php_path": values.get("php_path", ""),
        "composer_path": values.get("composer_path", ""),
        "drush_path": values.get("drush_path", ""),
        "php_version": values.get("php_version", ""),
        "composer_version": values.get("composer_version", ""),
        "drush_version": values.get("drush_version", ""),
        "release_count": int_value(values, "release_count"),
        "disk_available_kb": disk_available_kb,
        "disk_usage": values.get("disk_usage", ""),
        "writable_release_root": bool_value(values, "writable_release_root"),
        "readable_shared": bool_value(values, "readable_shared"),
        "shared_resources_readable": bool_value(values, "shared_resources_readable"),
        "web_docroot": values.get("web_docroot", ""),
        "release_integrity_status": values.get("release_integrity_status", ""),
        "release_integrity_message": values.get("release_integrity_message", ""),
        "release_integrity_missing": values.get("release_integrity_missing", ""),
        "project_drush_path": values.get("project_drush_path", ""),
        "drupal_bootstrap_status": values.get("drupal_bootstrap_status", ""),
        "drupal_bootstrap_capable": bool_value(values, "drupal_bootstrap_capable"),
        "drupal_bootstrap_failure_reason": values.get("drupal_bootstrap_failure_reason", ""),
    }


def snapshot_check(snapshot, profile, kind):
    if not snapshot.get("connected"):
        return False, snapshot.get("error", "SSH connectivity failed")
    checks = {
        "ssh_connectivity": (True, "SSH connectivity passed"),
        "remote_hostname": (bool(snapshot.get("hostname")), f"remote hostname: {snapshot.get('hostname', 'unknown')}"),
        "remote_user": (
            snapshot.get("user") == snapshot.get("configured_user"),
            f"remote user: {snapshot.get('user', 'unknown')}",
        ),
        "deployment_root_exists": (snapshot.get("deployment_root_exists") is True, "deployment root exists"),
        "repo_exists": (
            snapshot.get("repo_exists") is True,
            "repository valid" if snapshot.get("repo_exists") is True else "repository invalid: repo directory missing",
        ),
        "release_integrity": (
            snapshot.get("release_integrity_status") == "passed",
            snapshot.get("release_integrity_message") or "release invalid",
        ),
        "drupal_bootstrap": (
            snapshot.get("drupal_bootstrap_capable") is True,
            snapshot.get("drupal_bootstrap_status")
            or snapshot.get("drupal_bootstrap_failure_reason")
            or "bootstrap failed",
        ),
        "releases_exists": (snapshot.get("releases_exists") is True, "releases directory exists"),
        "shared_exists": (snapshot.get("shared_exists") is True, "shared directory exists"),
        "current_exists": (snapshot.get("current_symlink_exists") is True, "current symlink exists"),
        "current_target_exists": (snapshot.get("current_target_exists") is True, "current target exists"),
        "logs_exists": (snapshot.get("logs_exists") is True, "logs directory exists"),
        "php_version": (bool(snapshot.get("php_path")), snapshot.get("php_version") or "PHP executable missing"),
        "php_availability": (bool(snapshot.get("php_path")), snapshot.get("php_path") or "PHP executable missing"),
        "composer_availability": (
            bool(snapshot.get("composer_path")),
            snapshot.get("composer_path") or "Composer executable missing",
        ),
        "drush_availability": (bool(snapshot.get("drush_path")), snapshot.get("drush_path") or "Drush executable missing"),
        "writable_directories": (snapshot.get("writable_release_root") is True, "release root is writable"),
        "writable_release_root": (snapshot.get("writable_release_root") is True, "release root is writable"),
        "directory_layout": (
            all(
                snapshot.get(key) is True
                for key in (
                    "deployment_root_exists",
                    "repo_exists",
                    "releases_exists",
                    "shared_exists",
                    "current_symlink_exists",
                    "current_target_exists",
                    "logs_exists",
                )
            ),
            "required deployment directories and current symlink are present",
        ),
        "readable_shared_resources": (
            snapshot.get("readable_shared") is True and snapshot.get("shared_resources_readable") is True,
            "shared directory and configured shared resources are readable",
        ),
        "required_symlinks": (snapshot.get("current_symlink_exists") is True, "current symlink exists"),
        "disk_space": (int(snapshot.get("disk_available_kb", 0)) > 0, snapshot.get("disk_usage") or "disk space unavailable"),
        "permissions": (snapshot.get("writable_release_root") is True, "release root is writable"),
    }
    passed, message = checks.get(kind, (False, f"unsupported doctor check type: {kind}"))
    return passed, message


def evaluate_check(profile, check, index, snapshot):
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
        passed, message = snapshot_check(snapshot, profile, kind)
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
    snapshot = result.get("server", {})
    if snapshot:
        print(f"Server Hostname: {snapshot.get('hostname', 'unknown') or 'unknown'}")
        print(f"Remote User: {snapshot.get('user', 'unknown') or 'unknown'}")
    print("")
    for check in result["checks"]:
        marker = "✓" if check["status"] == "passed" else "✗"
        print(f"{marker} {check['name']} ({check['type']}): {check['message']}")
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

    configured_checks = doctor_checks(profile)
    live_required = any(isinstance(check, dict) and check.get("mode") == "ssh" for check in configured_checks)
    snapshot = collect_live_snapshot(profile) if live_required else {}
    checks = [evaluate_check(profile, check, index, snapshot) for index, check in enumerate(configured_checks)]
    status = "passed" if all(check["status"] == "passed" for check in checks) else "failed"
    result = {
        "status": status,
        "environment": environment,
        "profile": profile_name,
        "checks": checks,
    }
    if snapshot:
        result["server"] = snapshot

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
