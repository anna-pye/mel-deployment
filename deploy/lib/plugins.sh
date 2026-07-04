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

mel_plugins_invoke_mock() {
  local plugin_dir="$1"
  local profile_file="$2"
  local plugin_type="$3"
  local context_json="$4"

  python3 - "$plugin_dir" "$profile_file" "$plugin_type" "$context_json" <<'PY'
import json
import os
import sys

plugin_dir, profile_file, plugin_type, context_text = sys.argv[1:5]
supported_types = {"shared", "composer", "drush", "health", "switch_current"}


class PluginInvokeError(Exception):
    pass


def load_json_file(path, label):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except FileNotFoundError as exc:
        raise PluginInvokeError(f"{label} file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise PluginInvokeError(
            f"{label} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc
    if not isinstance(loaded, dict):
        raise PluginInvokeError(f"{label} root must be an object")
    return loaded


def load_context(value):
    try:
        loaded = json.loads(value)
    except json.JSONDecodeError as exc:
        raise PluginInvokeError(
            f"plugin context JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc
    if not isinstance(loaded, dict):
        raise PluginInvokeError("plugin context root must be an object")
    return loaded


try:
    if plugin_type not in supported_types:
        raise PluginInvokeError(f"unsupported plugin type: {plugin_type}")

    contract_file = os.path.join(plugin_dir, f"{plugin_type}.plugin.json")
    contract = load_json_file(contract_file, "plugin contract")
    profile = load_json_file(profile_file, "profile")
    context = load_context(context_text)

    if contract.get("type") != plugin_type:
        raise PluginInvokeError(f"plugin contract type mismatch for {plugin_type}")
    if contract.get("executes") is not False:
        raise PluginInvokeError(f"plugin {plugin_type} must remain mock-only in this phase")

    plugins = profile.get("plugins", {})
    if not isinstance(plugins, dict):
        raise PluginInvokeError("profile.plugins must be an object")
    config = plugins.get(plugin_type, {})
    if not isinstance(config, dict):
        raise PluginInvokeError(f"profile.plugins.{plugin_type} must be an object")

    mode = config.get("mode", "mock")
    status = config.get("status", "passed")
    if mode != "mock":
        raise PluginInvokeError(f"plugin {plugin_type} uses unsupported mode: {mode}")
    if status not in {"passed", "failed"}:
        raise PluginInvokeError(f"plugin {plugin_type} uses unsupported status: {status}")

    result = {
        "plugin": contract.get("name"),
        "type": plugin_type,
        "mode": "mock",
        "status": status,
        "context": context,
    }
    message = config.get("message")
    if isinstance(message, str) and message:
        result["message"] = message

    print(json.dumps(result, indent=2))
    sys.exit(0 if status == "passed" else 2)
except PluginInvokeError as exc:
    print(json.dumps({"status": "failed", "type": plugin_type, "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}
