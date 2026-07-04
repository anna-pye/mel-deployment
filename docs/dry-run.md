# Dry Run Engine

The Dry Run Engine renders an execution plan as a human-readable simulation.

It never executes plan steps. It does not deploy, create releases, link shared directories, run Composer, run Drush, run database updates, rebuild caches, run health checks, switch symlinks, contact servers, or modify filesystems.

## Command

```bash
deploy/bin/mel dry-run --manifest examples/hold-production.yml
deploy/bin/mel dry-run --plan examples/plans/hold-production.plan.json
```

When `--manifest` is used, the existing validation, resolution, and planner engines run locally to produce the execution plan. When `--plan` is used, the supplied plan is validated before rendering.

## Output

The output is human-readable simulation text:

```text
✓ Validate manifest
✓ Validate policy
✓ Prepare release
✓ Link shared directories
✓ Composer install
✓ Database updates
✓ Cache rebuild
✓ Health checks
✓ Switch current
```

These lines are labels only. They do not represent executed operations.
