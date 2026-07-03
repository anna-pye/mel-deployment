#!/usr/bin/env bash

mel_release_generate_id() {
  if [[ -n "${MEL_RELEASE_TIMESTAMP:-}" ]]; then
    printf '%s\n' "$MEL_RELEASE_TIMESTAMP"
    return "$MEL_EXIT_SUCCESS"
  fi

  date -u '+%Y%m%d%H%M%S'
}

mel_release_validate_id() {
  local release_id="$1"

  if [[ "$release_id" =~ ^[0-9]{14}$ ]]; then
    return "$MEL_EXIT_SUCCESS"
  fi

  printf 'release_id must use YYYYMMDDHHMMSS format\n'
  return "$MEL_EXIT_ERROR"
}

mel_release_prepare() {
  local source_root="$1"
  local release_root="$2"

  python3 - "$source_root" "$release_root" <<'PY'
import os
import shutil
import sys

source_root = os.path.abspath(sys.argv[1])
release_root = os.path.abspath(sys.argv[2])

EXCLUDED_NAMES = {
    ".git",
    ".github",
    "tests",
    "docs",
    "documentation",
    "examples",
    ".DS_Store",
}
EXCLUDED_SUFFIXES = (".tmp", ".swp", "~")


class ReleaseError(Exception):
    pass


def ignore(directory, names):
    ignored = set()
    for name in names:
        if name in EXCLUDED_NAMES or name.endswith(EXCLUDED_SUFFIXES):
            ignored.add(name)
    return ignored


try:
    if not os.path.isdir(source_root):
        raise ReleaseError(f"source repository root is missing: {source_root}")
    if os.path.exists(release_root):
        raise ReleaseError(f"release already exists: {release_root}")

    os.makedirs(os.path.dirname(release_root), exist_ok=True)
    shutil.copytree(source_root, release_root, ignore=ignore, symlinks=True)
except ReleaseError as exc:
    print(str(exc))
    sys.exit(2)
except OSError as exc:
    print(str(exc))
    sys.exit(2)
PY
}

mel_release_link_shared_resources() {
  local profile_file="$1"
  local staging_root="$2"
  local shared_path="$3"
  local release_root="$4"

  python3 - "$profile_file" "$staging_root" "$shared_path" "$release_root" <<'PY'
import json
import os
import sys

profile_file, staging_root, shared_path, release_root = sys.argv[1:5]
staging_root = os.path.abspath(staging_root)
shared_root = os.path.abspath(shared_path)
release_root = os.path.abspath(release_root)


class SharedResourceError(Exception):
    pass


def load_profile(path):
    with open(path, "r", encoding="utf-8") as handle:
        loaded = json.load(handle)
    if not isinstance(loaded, dict):
        raise SharedResourceError("profile root must be an object")
    return loaded


def clean_relative_path(value, location):
    if not isinstance(value, str) or not value.strip():
        raise SharedResourceError(f"{location} is required")
    cleaned = value.strip().strip("/")
    if cleaned in {"", ".", ".."} or cleaned.startswith("../") or "/../" in cleaned:
        raise SharedResourceError(f"{location} must be a safe relative path")
    return cleaned


try:
    profile = load_profile(profile_file)
    resources = profile.get("shared_resources", [])
    if not isinstance(resources, list):
        raise SharedResourceError("profile.shared_resources must be a list")

    for index, resource in enumerate(resources):
        if not isinstance(resource, dict):
            raise SharedResourceError(f"profile.shared_resources[{index}] must be an object")

        name = clean_relative_path(resource.get("name"), f"profile.shared_resources[{index}].name")
        target = clean_relative_path(resource.get("target"), f"profile.shared_resources[{index}].target")
        kind = resource.get("type", "directory")
        if kind not in {"directory", "file"}:
            raise SharedResourceError(f"profile.shared_resources[{index}].type is unsupported")

        source_path = os.path.abspath(os.path.join(shared_root, name))
        target_path = os.path.abspath(os.path.join(release_root, target))

        if os.path.commonpath([shared_root, source_path]) != shared_root:
            raise SharedResourceError(f"shared resource escapes shared root: {name}")
        if os.path.commonpath([release_root, target_path]) != release_root:
            raise SharedResourceError(f"shared target escapes release root: {target}")
        if kind == "directory" and not os.path.isdir(source_path):
            raise SharedResourceError(f"required shared directory is missing: {name}")
        if kind == "file" and not os.path.isfile(source_path):
            raise SharedResourceError(f"required shared file is missing: {name}")

        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        if os.path.lexists(target_path):
            if os.path.isdir(target_path) and not os.path.islink(target_path):
                os.rmdir(target_path)
            else:
                os.unlink(target_path)
        os.symlink(source_path, target_path)

    print(json.dumps({"status": "passed", "resources": len(resources)}, indent=2))
except (OSError, json.JSONDecodeError, SharedResourceError) as exc:
    print(json.dumps({"status": "failed", "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}

mel_release_verify_layout() {
  local profile_file="$1"
  local staging_root="$2"
  local dry_run="$3"

  python3 - "$profile_file" "$staging_root" "$dry_run" <<'PY'
import json
import os
import sys

profile_file, staging_root, dry_run = sys.argv[1:4]
dry_run = dry_run == "true"


class LayoutError(Exception):
    pass


def text(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise LayoutError(f"{location}.{key} is required")
    return value.strip()


def configured_path(profile, key):
    root = text(profile, "deployment_root", "profile")
    paths = profile.get("paths", {})
    defaults = {
        "deployment_root": root,
        "repo": os.path.join(root, "repo"),
        "releases": os.path.join(root, "releases"),
        "shared": os.path.join(root, "shared"),
        "current": os.path.join(root, "current"),
        "logs": os.path.join(root, "logs"),
    }
    if key in {"deployment_root", "repo"}:
        return defaults[key]
    if isinstance(paths, dict) and isinstance(paths.get(key), str) and paths[key].strip():
        return paths[key].strip()
    return defaults[key]


try:
    with open(profile_file, "r", encoding="utf-8") as handle:
        profile = json.load(handle)

    if profile.get("environment") != "staging":
        raise LayoutError("executor supports only the staging profile")
    expected_root = configured_path(profile, "deployment_root")
    if os.path.abspath(staging_root) != os.path.abspath(expected_root):
        raise LayoutError("staging root must match profile.deployment_root")

    required = {
        "repo": configured_path(profile, "repo"),
        "releases": configured_path(profile, "releases"),
        "shared": configured_path(profile, "shared"),
        "current": configured_path(profile, "current"),
        "logs": configured_path(profile, "logs"),
    }

    if not dry_run:
        for label, path in required.items():
            if label == "current":
                if not os.path.islink(path):
                    raise LayoutError("current must be a symlink")
            elif not os.path.isdir(path):
                raise LayoutError(f"{label} directory is missing")

    print(json.dumps({"status": "passed", "root": staging_root, "required": required}, indent=2))
except (OSError, json.JSONDecodeError, LayoutError) as exc:
    print(json.dumps({"status": "failed", "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}
