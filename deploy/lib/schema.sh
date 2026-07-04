#!/usr/bin/env bash

mel_schema_validate_schema_file() {
  local schema_file="$1"

  python3 - "$schema_file" <<'PY'
import json
import sys

schema_file = sys.argv[1]

try:
    with open(schema_file, "r", encoding="utf-8") as handle:
        schema = json.load(handle)
except FileNotFoundError:
    print(f"schema file not found: {schema_file}")
    sys.exit(2)
except json.JSONDecodeError as exc:
    print(f"schema JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}")
    sys.exit(2)

if not isinstance(schema, dict):
    print("schema root must be an object")
    sys.exit(2)

if schema.get("type") != "object":
    print("schema root type must be object")
    sys.exit(2)

if not isinstance(schema.get("required"), list):
    print("schema required field must be a list")
    sys.exit(2)

if not isinstance(schema.get("properties"), dict):
    print("schema properties field must be an object")
    sys.exit(2)

sys.exit(0)
PY
}

mel_schema_validate_manifest_file() {
  local manifest_file="$1"
  local schema_file="$2"

  python3 - "$manifest_file" "$schema_file" <<'PY'
import json
import sys

manifest_file = sys.argv[1]
schema_file = sys.argv[2]


def load_json(path, label):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        print(f"{label} file not found: {path}")
        sys.exit(2)
    except json.JSONDecodeError as exc:
        print(f"{label} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}")
        sys.exit(2)


def validate_object(value, schema, location):
    if schema.get("type") == "object":
        if not isinstance(value, dict):
            print(f"{location} must be an object")
            sys.exit(2)

        for key in schema.get("required", []):
            if key not in value:
                print(f"{location}.{key} is required")
                sys.exit(2)

        for key, child_schema in schema.get("properties", {}).items():
            if key in value:
                validate_object(value[key], child_schema, f"{location}.{key}")
        return

    if schema.get("type") == "string" and not isinstance(value, str):
        print(f"{location} must be a string")
        sys.exit(2)


manifest = load_json(manifest_file, "manifest")
schema = load_json(schema_file, "schema")

validate_object(manifest, schema, "manifest")

paths = manifest.get("paths", {})
if not isinstance(paths, dict):
    print("manifest.paths must be an object")
    sys.exit(2)

for key, value in paths.items():
    if not isinstance(value, str):
        print(f"manifest.paths.{key} must be a string")
        sys.exit(2)

sys.exit(0)
PY
}
