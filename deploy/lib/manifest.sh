#!/usr/bin/env bash

mel_manifest_default_file() {
  printf '%s\n' "${MEL_ROOT}/manifests/manifest.json"
}

mel_manifest_default_schema() {
  printf '%s\n' "${MEL_ROOT}/schemas/manifest.schema.json"
}

mel_manifest_validate() {
  local manifest_file="$1"
  local schema_file="$2"
  local schema_error
  local manifest_error
  local path_error

  if ! schema_error="$(mel_schema_validate_schema_file "$schema_file")"; then
    mel_output_error "$MEL_CODE_SCHEMA_MALFORMED" "$schema_error"
    return "$MEL_EXIT_ERROR"
  fi

  if ! manifest_error="$(mel_schema_validate_manifest_file "$manifest_file" "$schema_file")"; then
    mel_output_error "$MEL_CODE_MANIFEST_INVALID" "$manifest_error"
    return "$MEL_EXIT_ERROR"
  fi

  while IFS=$'\t' read -r label path; do
    if ! path_error="$(mel_validate_path "$label" "$path")"; then
      mel_output_error "$MEL_CODE_PATH_INVALID" "$path_error"
      return "$MEL_EXIT_ERROR"
    fi
  done < <(mel_manifest_paths "$manifest_file")

  return "$MEL_EXIT_SUCCESS"
}

mel_manifest_paths() {
  local manifest_file="$1"

  python3 - "$manifest_file" <<'PY'
import json
import sys

manifest_file = sys.argv[1]

with open(manifest_file, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

repository = manifest.get("repository", {})
if "root" in repository:
    print(f"manifest.repository.root\t{repository['root']}")

for key, value in sorted(manifest.get("paths", {}).items()):
    print(f"manifest.paths.{key}\t{value}")
PY
}
