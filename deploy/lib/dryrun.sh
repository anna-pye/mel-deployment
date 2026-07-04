#!/usr/bin/env bash

mel_dryrun_render_plan() {
  local execution_plan="$1"

  python3 - "$execution_plan" <<'PY'
import json
import sys

plan_text = sys.argv[1]

LABELS = {
    "validate": "Validate manifest",
    "prepare_release": "Prepare release",
    "link_shared": "Link shared directories",
    "composer_install": "Composer install",
    "database_update": "Database updates",
    "cache_rebuild": "Cache rebuild",
    "health_check": "Health checks",
    "switch_current": "Switch current",
}


class DryRunError(Exception):
    pass


try:
    try:
        plan = json.loads(plan_text)
    except json.JSONDecodeError as exc:
        raise DryRunError(
            f"execution plan JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc

    if not isinstance(plan, dict):
        raise DryRunError("execution plan root must be an object")

    steps = plan.get("steps")
    if not isinstance(steps, list) or not steps:
        raise DryRunError("execution plan steps must be a non-empty list")

    print("Deployment dry run")
    print(f"Deployment: {plan.get('deployment_id', 'unknown')}")
    print(f"Environment: {plan.get('environment', 'unknown')}")
    print("")

    policy_printed = False
    for step in steps:
        if not isinstance(step, dict):
            raise DryRunError("execution plan steps must be objects")

        action = step.get("action")
        if action not in LABELS:
            raise DryRunError(f"unsupported dry-run action: {action}")

        print(f"✓ {LABELS[action]}")
        if action == "validate" and not policy_printed:
            print("✓ Validate policy")
            policy_printed = True

    print("")
    print("No deployment actions were executed.")
except DryRunError as exc:
    print(str(exc))
    sys.exit(2)
PY
}
