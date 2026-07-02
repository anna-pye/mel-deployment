# Resolution Engine

The Resolution Engine converts a validated deployment manifest into a canonical deployment model.

It is a local-only phase. It does not deploy, roll back, create releases, create directories, inspect servers, inspect remote repositories, run SSH, run rsync, run Composer, run Drush, or communicate with remote systems.

## Flow

```text
Manifest
    ↓
Validation
    ↓
Resolution
    ↓
Canonical Deployment Model
```

`mel resolve` always runs the existing validation engine first. If validation fails, resolution stops.

## Command

```bash
deploy/bin/mel resolve --manifest examples/hold-production.yml
deploy/bin/mel resolve --manifest examples/hold-production.yml --output resolved.json
deploy/bin/mel resolve --manifest examples/hold-production.yml --pretty
```

When `--output` is omitted, the canonical deployment model is written to stdout as formatted JSON. When `--output` is provided, the model is written to that file and a structured success result is printed.

## Required Values

Resolution requires a manifest that has already passed `mel validate` and includes:

- `name`, used as the canonical `deployment_id`
- `repository.root`, used for documented path defaults
- `repository.url`, copied into the canonical repository model
- `environment`, one of `production`, `staging`, or `development`
- `release.identifier`, supplied by the manifest for deterministic output
- `paths`, which may be empty when documented path defaults are sufficient

The resolver does not generate release identifiers. A `timestamp` release strategy is a label only in this phase.

## Documented Defaults

Only these defaults are supported:

- `repository.branch` defaults to `main`
- `release.strategy` defaults to `timestamp`
- `validation_profile` defaults to the resolved `environment`
- `paths.release_root` defaults to `<repository.root>/releases`
- `paths.shared_root` defaults to `<repository.root>/shared`
- `paths.current_link` defaults to `<repository.root>/current`

If a value cannot be resolved from the manifest or these defaults, resolution fails closed with a structured error.

## Conflict Detection

The resolver rejects:

- duplicate deployment identifiers
- conflicting `name` and `deployment_id` values
- conflicting legacy and canonical path aliases, such as `paths.releases` and `paths.release_root`
- duplicate canonical path values
- unsupported path keys
- unsupported environments
- unsupported release strategies
- ambiguous multi-deployment manifests
- missing required resolution fields

## Canonical Model

The canonical deployment model is deterministic formatted JSON:

```json
{
  "deployment_id": "hold-production",
  "repository": {
    "url": "git@github.com:anna-pye/Mel_hold.git",
    "branch": "main"
  },
  "environment": "production",
  "release": {
    "strategy": "timestamp",
    "identifier": "20260703153045"
  },
  "paths": {
    "release_root": "/example/mel/hold-production/releases",
    "shared_root": "/example/mel/hold-production/shared",
    "current_link": "/example/mel/hold-production/current"
  },
  "validation_profile": "production"
}
```
