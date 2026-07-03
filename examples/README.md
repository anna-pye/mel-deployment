# Examples

The `examples/` directory contains local-only manifests, resolved canonical model artefacts, and execution plan artefacts.

- `hold-production.yml` is a validation and resolution example. The file uses JSON syntax so it can be consumed by the current JSON validation engine.
- `resolved/hold-production.json` is the deterministic canonical model produced from `hold-production.yml`.
- `plans/hold-production.plan.json` is the deterministic execution plan produced from the resolved model.

These examples do not define deployment behavior. They must not run SSH, rsync, Composer, Drush, server communication, release creation, rollback, or remote filesystem operations.
