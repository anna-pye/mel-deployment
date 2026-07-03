# Staging Deployment

Staging is the only executable deployment environment in this phase.

Run a non-mutating pipeline check:

```bash
deploy/bin/mel execute staging --dry-run
```

Run a staging deployment only from a prepared staging root:

```bash
deploy/bin/mel execute staging
```

## Required Root

The canonical root is:

```text
/home/mel/staging
```

It must contain:

```text
repo/
releases/
shared/
current
logs/
```

The staging profile owns shared resource declarations. The executor validates every required shared resource before linking it into a release.

## Current Switch

The executor switches `current` only after:

- validation succeeds
- resolution succeeds
- planning succeeds
- policy allows execution
- doctor checks pass
- pre-deployment health passes
- layout verification passes
- release preparation succeeds
- shared resources link successfully
- Composer plugin succeeds
- Drush plugin succeeds
- release health succeeds

The switch is atomic. Post-switch validation runs immediately after the switch. If it fails, rollback restores the previous `current` symlink.

## Forbidden Behaviour

This phase does not support production deployment, production rollback, real SSH, real Composer, real Drush, hardcoded credentials, or hardcoded SSH keys.
