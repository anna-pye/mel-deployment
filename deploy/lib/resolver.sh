#!/usr/bin/env bash

mel_resolver_build_model() {
  local manifest_file="$1"

  python3 - "$manifest_file" <<'PY'
import json
import re
import sys

manifest_file = sys.argv[1]

SUPPORTED_ENVIRONMENTS = {"production", "staging", "development"}
SUPPORTED_RELEASE_STRATEGIES = {"timestamp"}
DEPLOYMENT_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
PATH_ALIASES = {
    "release_root": ("release_root", "releases", "releases"),
    "shared_root": ("shared_root", "shared", "shared"),
    "current_link": ("current_link", "current", "current"),
}
KNOWN_PATH_KEYS = {
    "release_root",
    "releases",
    "shared_root",
    "shared",
    "current_link",
    "current",
}


class ResolutionError(Exception):
    pass


def reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ResolutionError(f"duplicate manifest key: {key}")
        result[key] = value
    return result


def load_manifest(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle, object_pairs_hook=reject_duplicate_keys)
    except FileNotFoundError as exc:
        raise ResolutionError(f"manifest file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ResolutionError(
            f"manifest JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc


def text(value, location):
    if not isinstance(value, str):
        raise ResolutionError(f"{location} must be a string")

    resolved = value.strip()
    if not resolved:
        raise ResolutionError(f"{location} is required")

    return resolved


def optional_text(mapping, key, location):
    if key not in mapping:
        return None

    return text(mapping[key], location)


def normalise_path(value, location):
    path = text(value, location)

    while len(path) > 1 and path.endswith("/"):
        path = path[:-1]

    return path


def required_mapping(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, dict):
        raise ResolutionError(f"{location}.{key} is required")

    return value


def deployment_id(manifest):
    name = optional_text(manifest, "name", "manifest.name")
    explicit = optional_text(manifest, "deployment_id", "manifest.deployment_id")

    if name is None and explicit is None:
        raise ResolutionError("manifest.name is required")

    if name is not None and explicit is not None and name != explicit:
        raise ResolutionError("manifest.name and manifest.deployment_id conflict")

    resolved = explicit or name
    if DEPLOYMENT_ID_PATTERN.fullmatch(resolved) is None:
        raise ResolutionError("manifest.name must be a lowercase deployment identifier")

    return resolved


def reject_duplicate_deployment_ids(manifest):
    deployments = manifest.get("deployments")
    if deployments is None:
        return

    if not isinstance(deployments, list):
        raise ResolutionError("manifest.deployments must be a list when provided")

    seen = set()
    for index, deployment in enumerate(deployments):
        if not isinstance(deployment, dict):
            raise ResolutionError(f"manifest.deployments[{index}] must be an object")

        identifier = deployment.get("deployment_id", deployment.get("name"))
        identifier = text(identifier, f"manifest.deployments[{index}].name")

        if identifier in seen:
            raise ResolutionError(f"duplicate deployment identifier: {identifier}")
        seen.add(identifier)

    if deployments:
        raise ResolutionError("manifest.deployments is ambiguous for single-model resolution")


def repository_model(manifest):
    repository = required_mapping(manifest, "repository", "manifest")

    url = optional_text(repository, "url", "manifest.repository.url")
    if url is None:
        raise ResolutionError("manifest.repository.url is required")

    branch = optional_text(repository, "branch", "manifest.repository.branch") or "main"

    return {
        "url": url,
        "branch": branch,
    }


def environment(manifest):
    resolved = optional_text(manifest, "environment", "manifest.environment")
    if resolved is None:
        raise ResolutionError("manifest.environment is required")

    if resolved not in SUPPORTED_ENVIRONMENTS:
        raise ResolutionError(f"unsupported environment: {resolved}")

    return resolved


def release_model(manifest):
    release = manifest.get("release", {})
    if not isinstance(release, dict):
        raise ResolutionError("manifest.release must be an object")

    strategy = optional_text(release, "strategy", "manifest.release.strategy") or "timestamp"
    if strategy not in SUPPORTED_RELEASE_STRATEGIES:
        raise ResolutionError(f"unsupported release strategy: {strategy}")

    identifier = optional_text(release, "identifier", "manifest.release.identifier")
    if identifier is None:
        raise ResolutionError("manifest.release.identifier is required")

    return {
        "strategy": strategy,
        "identifier": identifier,
    }


def paths_model(manifest):
    repository = required_mapping(manifest, "repository", "manifest")
    root = normalise_path(repository.get("root"), "manifest.repository.root")

    paths = manifest.get("paths", {})
    if not isinstance(paths, dict):
        raise ResolutionError("manifest.paths must be an object")

    unknown_keys = sorted(set(paths) - KNOWN_PATH_KEYS)
    if unknown_keys:
        raise ResolutionError(f"unsupported path keys: {', '.join(unknown_keys)}")

    resolved = {}
    for canonical_key, (canonical_name, legacy_name, default_segment) in PATH_ALIASES.items():
        canonical_value = None
        legacy_value = None

        if canonical_name in paths:
            canonical_value = normalise_path(paths[canonical_name], f"manifest.paths.{canonical_name}")
        if legacy_name in paths:
            legacy_value = normalise_path(paths[legacy_name], f"manifest.paths.{legacy_name}")

        if canonical_value is not None and legacy_value is not None and canonical_value != legacy_value:
            raise ResolutionError(
                f"conflicting path definitions for {canonical_name} and {legacy_name}"
            )

        resolved[canonical_key] = canonical_value or legacy_value or f"{root}/{default_segment}"

    path_values = {}
    for key, value in resolved.items():
        if value in path_values:
            raise ResolutionError(f"conflicting path definitions for {path_values[value]} and {key}")
        path_values[value] = key

    return resolved


def validation_profile(manifest, resolved_environment):
    return optional_text(manifest, "validation_profile", "manifest.validation_profile") or resolved_environment


try:
    manifest = load_manifest(manifest_file)
    if not isinstance(manifest, dict):
        raise ResolutionError("manifest root must be an object")

    reject_duplicate_deployment_ids(manifest)
    resolved_environment = environment(manifest)

    model = {
        "deployment_id": deployment_id(manifest),
        "repository": repository_model(manifest),
        "environment": resolved_environment,
        "release": release_model(manifest),
        "paths": paths_model(manifest),
        "validation_profile": validation_profile(manifest, resolved_environment),
    }

    print(json.dumps(model, indent=2))
except ResolutionError as exc:
    print(str(exc))
    sys.exit(2)
PY
}

mel_resolver_write_output() {
  local output_file="$1"
  local resolved_model="$2"
  local parent_dir="."

  if [[ -z "$output_file" ]]; then
    mel_output_error "$MEL_CODE_ARGUMENT_ERROR" "--output requires a file path"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ "$output_file" == *".."* ]]; then
    mel_output_error "$MEL_CODE_ARGUMENT_ERROR" "--output must not contain parent-directory traversal"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ -d "$output_file" ]]; then
    mel_output_error "$MEL_CODE_ARGUMENT_ERROR" "--output must be a file path"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ "$output_file" == */* ]]; then
    parent_dir="${output_file%/*}"
  fi

  if [[ -z "$parent_dir" ]]; then
    parent_dir="/"
  fi

  if [[ ! -d "$parent_dir" ]]; then
    mel_output_error "$MEL_CODE_ARGUMENT_ERROR" "--output parent directory does not exist"
    return "$MEL_EXIT_ERROR"
  fi

  printf '%s\n' "$resolved_model" >"$output_file"
  return "$MEL_EXIT_SUCCESS"
}
