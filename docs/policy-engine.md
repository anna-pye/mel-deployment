# Policy Engine

The Policy Engine evaluates whether a planned deployment is allowed to continue.

It is read-only and local-only. It never contacts servers, deploys code, creates releases, switches symlinks, runs Composer, runs Drush, or modifies files.

## Decisions

Policy returns one of:

- `allowed`
- `warning`
- `blocked`

The engine emits structured JSON only.

## Evaluation Scope

The policy engine evaluates only:

- deployment environment
- local repository state
- deployment profile
- required approvals
- validation success
- planner success

It does not inspect Drupal, Commerce, staging, production, or remote repositories.

## Command

```bash
deploy/bin/mel policy --manifest examples/hold-production.yml --approval business --approval technical --approval release_manager
```

The command validates and plans the manifest locally before policy evaluation. The default profile is selected from `profiles/<environment>.json`.

For deterministic tests, the repository state can be supplied explicitly:

```bash
deploy/bin/mel policy --manifest examples/hold-production.yml --repository-state clean
```

## Exit Codes

- `0`: `allowed`
- `1`: `warning`
- `2`: `blocked`

## Fail Closed

Unknown environments, dirty repository state, missing approvals, validation failure, planner failure, malformed plans, and malformed profiles are blocked.
