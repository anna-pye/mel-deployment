#!/usr/bin/env bash

_mel_planner_python() {
  local mode="$1"
  local payload="$2"

  python3 - "$mode" "$payload" <<'PY'
import json
import re
import sys

mode = sys.argv[1]
payload = sys.argv[2]

PLAN_VERSION = 1
STEP_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
SUPPORTED_ACTIONS = {
    "validate",
    "prepare_release",
    "link_shared",
    "composer_install",
    "database_update",
    "cache_rebuild",
    "health_check",
    "switch_current",
}
CANONICAL_STEPS = [
    ("validate", 10, [], "validate"),
    ("prepare_release", 20, ["validate"], "prepare_release"),
    ("link_shared", 30, ["prepare_release"], "link_shared"),
    ("composer_install", 40, ["link_shared"], "composer_install"),
    ("database_update", 50, ["composer_install"], "database_update"),
    ("cache_rebuild", 60, ["database_update"], "cache_rebuild"),
    ("health_check", 70, ["cache_rebuild"], "health_check"),
    ("switch_current", 80, ["health_check"], "switch_current"),
]


class PlannerError(Exception):
    pass


def load_json(value, label):
    try:
        loaded = json.loads(value)
    except json.JSONDecodeError as exc:
        raise PlannerError(
            f"{label} JSON is malformed: {exc.msg} at line {exc.lineno}, column {exc.colno}"
        ) from exc

    if not isinstance(loaded, dict):
        raise PlannerError(f"{label} root must be an object")

    return loaded


def required_text(mapping, key, location):
    value = mapping.get(key)
    if not isinstance(value, str) or not value.strip():
        raise PlannerError(f"{location}.{key} is required")

    return value.strip()


def validate_step(step, index):
    if not isinstance(step, dict):
        raise PlannerError(f"plan.steps[{index}] must be an object")

    expected_keys = {"id", "order", "depends_on", "action"}
    unknown_keys = sorted(set(step) - expected_keys)
    missing_keys = sorted(expected_keys - set(step))

    if missing_keys:
        raise PlannerError(f"plan.steps[{index}] missing required keys: {', '.join(missing_keys)}")
    if unknown_keys:
        raise PlannerError(f"plan.steps[{index}] has unsupported keys: {', '.join(unknown_keys)}")

    step_id = step["id"]
    if not isinstance(step_id, str) or STEP_ID_PATTERN.fullmatch(step_id) is None:
        raise PlannerError(f"plan.steps[{index}].id is invalid")

    order = step["order"]
    if not isinstance(order, int) or order <= 0:
        raise PlannerError(f"plan.steps[{index}].order must be a positive integer")

    depends_on = step["depends_on"]
    if not isinstance(depends_on, list) or not all(isinstance(item, str) for item in depends_on):
        raise PlannerError(f"plan.steps[{index}].depends_on must be a list of step identifiers")

    action = step["action"]
    if action not in SUPPORTED_ACTIONS:
        raise PlannerError(f"unsupported planner action: {action}")

    return step_id, order


def detect_cycles(step_ids, dependency_map):
    visiting = set()
    visited = set()

    def visit(step_id, path):
        if step_id in visiting:
            cycle = " -> ".join(path + [step_id])
            raise PlannerError(f"circular dependency detected: {cycle}")
        if step_id in visited:
            return

        visiting.add(step_id)
        for dependency in dependency_map[step_id]:
            visit(dependency, path + [step_id])
        visiting.remove(step_id)
        visited.add(step_id)

    for step_id in step_ids:
        visit(step_id, [])


def validate_plan(plan):
    if not isinstance(plan.get("plan_version"), int) or plan["plan_version"] != PLAN_VERSION:
        raise PlannerError("plan.plan_version is unsupported")

    required_text(plan, "deployment_id", "plan")
    required_text(plan, "environment", "plan")

    steps = plan.get("steps")
    if not isinstance(steps, list) or not steps:
        raise PlannerError("plan.steps must be a non-empty list")

    step_ids = []
    step_orders = {}
    dependency_map = {}
    previous_order = 0

    for index, step in enumerate(steps):
        step_id, order = validate_step(step, index)

        if step_id in dependency_map:
            raise PlannerError(f"duplicate step identifier: {step_id}")
        if order <= previous_order:
            raise PlannerError("invalid execution order: step order must be strictly increasing")
        if order in step_orders:
            raise PlannerError(f"duplicate step order: {order}")

        step_ids.append(step_id)
        step_orders[order] = step_id
        dependency_map[step_id] = list(step["depends_on"])
        previous_order = order

    known_step_ids = set(step_ids)
    order_by_step_id = {step_id: steps[index]["order"] for index, step_id in enumerate(step_ids)}

    for step in steps:
        step_id = step["id"]
        for dependency in step["depends_on"]:
            if dependency not in known_step_ids:
                raise PlannerError(f"missing dependency for {step_id}: {dependency}")

    detect_cycles(step_ids, dependency_map)

    for step in steps:
        step_id = step["id"]
        for dependency in step["depends_on"]:
            if order_by_step_id[dependency] >= order_by_step_id[step_id]:
                raise PlannerError(f"invalid execution order: {step_id} depends on {dependency}")


def build_plan(resolved_model):
    deployment_id = required_text(resolved_model, "deployment_id", "resolved_model")
    environment = required_text(resolved_model, "environment", "resolved_model")

    plan = {
        "plan_version": PLAN_VERSION,
        "deployment_id": deployment_id,
        "environment": environment,
        "steps": [
            {
                "id": step_id,
                "order": order,
                "depends_on": depends_on,
                "action": action,
            }
            for step_id, order, depends_on, action in CANONICAL_STEPS
        ],
    }

    validate_plan(plan)
    return plan


try:
    if mode == "build":
        resolved_model = load_json(payload, "resolved model")
        print(json.dumps(build_plan(resolved_model), indent=2))
    elif mode == "validate":
        validate_plan(load_json(payload, "plan"))
    else:
        raise PlannerError(f"unsupported planner mode: {mode}")
except PlannerError as exc:
    print(str(exc))
    sys.exit(2)
PY
}

mel_planner_validate_plan() {
  local plan="$1"

  _mel_planner_python "validate" "$plan"
}

mel_planner_build_plan() {
  local resolved_model="$1"

  _mel_planner_python "build" "$resolved_model"
}
