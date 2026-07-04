#!/usr/bin/env bash

mel_policy_default_profile_file() {
  local environment="$1"

  printf '%s\n' "${MEL_ROOT}/profiles/${environment}.json"
}

mel_policy_repository_state() {
  if ! command -v git >/dev/null 2>&1; then
    printf 'unknown\n'
    return "$MEL_EXIT_WARNING"
  fi

  if ! git -C "$MEL_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'unknown\n'
    return "$MEL_EXIT_WARNING"
  fi

  if [[ -n "$(git -C "$MEL_ROOT" status --short)" ]]; then
    printf 'dirty\n'
    return "$MEL_EXIT_WARNING"
  fi

  printf 'clean\n'
  return "$MEL_EXIT_SUCCESS"
}

mel_policy_evaluate() {
  local execution_plan="$1"
  local profile_file="$2"
  local repository_state="$3"
  local validation_success="$4"
  local planner_success="$5"
  local approvals_csv="$6"

  python3 - "$execution_plan" "$profile_file" "$repository_state" "$validation_success" "$planner_success" "$approvals_csv" <<'PY'
import json
import sys

execution_plan_text = sys.argv[1]
profile_file = sys.argv[2]
repository_state = sys.argv[3]
validation_success = sys.argv[4] == "true"
planner_success = sys.argv[5] == "true"
approvals = {item for item in sys.argv[6].split(",") if item}

SUPPORTED_DECISIONS = {"allowed", "warning", "blocked"}
SUPPORTED_ENVIRONMENTS = {"production", "staging", "development"}
SUPPORTED_REPOSITORY_STATES = {"clean", "dirty", "unknown"}


class PolicyError(Exception):
    pass


def load_json_text(value, label):
    try:
        loaded = json.loads(value)
    except json.JSONDecodeError as exc:
        raise PolicyError(
            f"{label} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc

    if not isinstance(loaded, dict):
        raise PolicyError(f"{label} root must be an object")

    return loaded


def load_json_file(path, label):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except FileNotFoundError as exc:
        raise PolicyError(f"{label} file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise PolicyError(
            f"{label} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc

    if not isinstance(loaded, dict):
        raise PolicyError(f"{label} root must be an object")

    return loaded


def text(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise PolicyError(f"{location}.{key} is required")
    return value.strip()


def text_list(mapping, key, location):
    value = mapping.get(key, [])
    if not isinstance(value, list) or not all(isinstance(item, str) and item.strip() for item in value):
        raise PolicyError(f"{location}.{key} must be a list of strings")
    return [item.strip() for item in value]


def add_check(checks, name, decision, message):
    if decision not in SUPPORTED_DECISIONS:
        raise PolicyError(f"unsupported policy decision: {decision}")
    checks.append({"name": name, "decision": decision, "message": message})


def final_decision(checks):
    if any(check["decision"] == "blocked" for check in checks):
        return "blocked"
    if any(check["decision"] == "warning" for check in checks):
        return "warning"
    return "allowed"


try:
    plan = load_json_text(execution_plan_text, "execution plan")
    profile = load_json_file(profile_file, "profile")

    deployment_id = text(plan, "deployment_id", "plan")
    environment = text(plan, "environment", "plan")
    profile_environment = text(profile, "environment", "profile")
    policy_profile = text(profile, "policy_profile", "profile")
    required_approvals = text_list(profile, "required_approvals", "profile")

    checks = []

    if environment not in SUPPORTED_ENVIRONMENTS:
        add_check(checks, "environment", "blocked", f"unsupported deployment environment: {environment}")
    elif environment != profile_environment:
        add_check(
            checks,
            "environment",
            "blocked",
            f"plan environment {environment} does not match profile environment {profile_environment}",
        )
    else:
        add_check(checks, "environment", "allowed", f"environment {environment} matches profile")

    if repository_state not in SUPPORTED_REPOSITORY_STATES:
        add_check(checks, "repository_state", "blocked", f"unsupported repository state: {repository_state}")
    elif repository_state == "dirty":
        add_check(checks, "repository_state", "blocked", "repository has uncommitted changes")
    elif repository_state == "unknown":
        add_check(checks, "repository_state", "warning", "repository state could not be confirmed")
    else:
        add_check(checks, "repository_state", "allowed", "repository state is clean")

    add_check(
        checks,
        "deployment_profile",
        "allowed",
        f"policy profile {policy_profile} is configured",
    )

    missing_approvals = sorted(set(required_approvals) - approvals)
    if missing_approvals:
        add_check(
            checks,
            "required_approvals",
            "blocked",
            f"missing required approvals: {', '.join(missing_approvals)}",
        )
    else:
        add_check(checks, "required_approvals", "allowed", "required approvals are satisfied")

    add_check(
        checks,
        "validation_success",
        "allowed" if validation_success else "blocked",
        "validation completed successfully" if validation_success else "validation did not complete successfully",
    )
    add_check(
        checks,
        "planner_success",
        "allowed" if planner_success else "blocked",
        "planner completed successfully" if planner_success else "planner did not complete successfully",
    )

    decision = final_decision(checks)
    result = {
        "decision": decision,
        "deployment_id": deployment_id,
        "environment": environment,
        "policy_profile": policy_profile,
        "checks": checks,
    }
    print(json.dumps(result, indent=2))
    sys.exit(0 if decision == "allowed" else 1 if decision == "warning" else 2)
except PolicyError as exc:
    print(json.dumps({"decision": "blocked", "error": str(exc)}, indent=2))
    sys.exit(2)
PY
}
