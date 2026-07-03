# Planner Engine

The Planner Engine converts a resolved deployment model into a deterministic execution plan.

It is a local-only planning phase. It does not execute commands, deploy, roll back, create releases, create directories, inspect servers, inspect repositories, run SSH, run rsync, run Composer, run Drush, communicate with remote systems, or modify filesystems except when the caller explicitly writes a local plan output file.

## Flow

```text
Manifest
    ↓
Validation
    ↓
Resolution
    ↓
Planner
    ↓
Execution Plan
```

`mel plan` always runs the existing validation engine and resolution engine first. If either phase fails, planning stops.

## Command

```bash
deploy/bin/mel plan --manifest examples/hold-production.yml
deploy/bin/mel plan --manifest examples/hold-production.yml --output examples/plans/hold-production.plan.json
deploy/bin/mel plan --manifest examples/hold-production.yml --pretty
```

When `--output` is omitted, the execution plan is written to stdout as formatted JSON. When `--output` is provided, the plan is written to that file and no deployment action is taken.

## Determinism

The planner does not generate timestamps, random values, host-specific values, or values derived from filesystem inspection. The same resolved deployment model produces the same execution plan.

## Canonical Steps

The current plan version supports this fixed action graph:

1. `validate`
2. `prepare_release`
3. `link_shared`
4. `composer_install`
5. `database_update`
6. `cache_rebuild`
7. `health_check`
8. `switch_current`

These names are plan actions only. They are not execution implementations.

## Conflict Detection

The planner rejects:

- malformed resolved models
- duplicate step identifiers
- duplicate step orders
- circular dependencies
- missing dependencies
- unsupported actions
- unsupported plan versions
- invalid or non-increasing execution order
- plan steps with missing or unsupported keys

Failures are returned as structured `MEL_PLAN_INVALID` errors through the CLI.

## Execution Plan

The canonical execution plan is deterministic formatted JSON:

```json
{
  "plan_version": 1,
  "deployment_id": "hold-production",
  "environment": "production",
  "steps": [
    {
      "id": "validate",
      "order": 10,
      "depends_on": [],
      "action": "validate"
    },
    {
      "id": "prepare_release",
      "order": 20,
      "depends_on": [
        "validate"
      ],
      "action": "prepare_release"
    },
    {
      "id": "link_shared",
      "order": 30,
      "depends_on": [
        "prepare_release"
      ],
      "action": "link_shared"
    },
    {
      "id": "composer_install",
      "order": 40,
      "depends_on": [
        "link_shared"
      ],
      "action": "composer_install"
    },
    {
      "id": "database_update",
      "order": 50,
      "depends_on": [
        "composer_install"
      ],
      "action": "database_update"
    },
    {
      "id": "cache_rebuild",
      "order": 60,
      "depends_on": [
        "database_update"
      ],
      "action": "cache_rebuild"
    },
    {
      "id": "health_check",
      "order": 70,
      "depends_on": [
        "cache_rebuild"
      ],
      "action": "health_check"
    },
    {
      "id": "switch_current",
      "order": 80,
      "depends_on": [
        "health_check"
      ],
      "action": "switch_current"
    }
  ]
}
```
