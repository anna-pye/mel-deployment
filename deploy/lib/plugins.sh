#!/usr/bin/env bash

mel_plugins_validate_contracts() {
  local plugin_dir="$1"

  python3 - "$plugin_dir" <<'PY'
import json
import os
import sys

plugin_dir = sys.argv[1]

SUPPORTED_TYPES = {"shared", "composer", "drush", "health", "switch_current"}


class PluginError(Exception):
    pass


def validate_contract(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            contract = json.load(handle)
    except json.JSONDecodeError as exc:
        raise PluginError(
            f"{os.path.basename(path)} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc

    if not isinstance(contract, dict):
        raise PluginError(f"{os.path.basename(path)} root must be an object")

    plugin_type = contract.get("type")
    if plugin_type not in SUPPORTED_TYPES:
        raise PluginError(f"unsupported plugin type: {plugin_type}")

    name = contract.get("name")
    if not isinstance(name, str) or not name.strip():
        raise PluginError(f"{os.path.basename(path)} name is required")

    executes = contract.get("executes")
    if executes is not False:
        raise PluginError(f"{name} must declare executes false")

    inputs = contract.get("inputs", [])
    outputs = contract.get("outputs", [])
    if not isinstance(inputs, list) or not all(isinstance(item, str) for item in inputs):
        raise PluginError(f"{name} inputs must be a list of strings")
    if not isinstance(outputs, list) or not all(isinstance(item, str) for item in outputs):
        raise PluginError(f"{name} outputs must be a list of strings")

    return {"name": name, "type": plugin_type, "status": "loaded"}


try:
    if not os.path.isdir(plugin_dir):
        raise PluginError(f"plugin directory not found: {plugin_dir}")

    files = sorted(
        os.path.join(plugin_dir, item)
        for item in os.listdir(plugin_dir)
        if item.endswith(".plugin.json")
    )
    if not files:
        raise PluginError("no plugin contract files found")

    plugins = [validate_contract(path) for path in files]
    print(json.dumps({"status": "passed", "plugins": plugins}, indent=2))
except PluginError as exc:
    print(json.dumps({"status": "failed", "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}
