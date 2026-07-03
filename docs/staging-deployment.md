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

## Configured Root

The staging profile owns the canonical root. The default profile currently uses:

```text
/home/mel/staging
```

It must contain:

```text
deployment_root/
  current
  releases/
  shared/
  logs/
```

The staging source repository is intentionally external to `deployment_root`. The canonical repository path is `repository_path` in `profiles/staging.json`; the default staging profile sets it to `/home/mel/staging-repo`. Components must read that profile value instead of hardcoding either `/home/mel/staging/repo` or `/home/mel/staging-repo`.

The staging profile owns shared resource declarations. The executor validates every required shared resource before linking it into a release.

## Release Requirements

A release is deployable only when these Drupal 11 project files are present under the release root:

- `composer.json`
- `vendor/autoload.php`
- `vendor/bin/drush`
- `web/core/lib/Drupal.php`
- `web/index.php`

The release must also pass `vendor/bin/drush status` from the release root. Legacy Drupal 7 bootstrap files are not part of the deployment contract.

Releases are immutable once prepared. If a release is missing required files or cannot bootstrap through project-local Drush, the framework rejects it and a corrected release must replace it. Broken releases are not repaired in place because mutable release directories make rollback, audit logs, and `current` symlink state harder to trust.

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
- release integrity and project-local Drupal bootstrap pass
- release health succeeds

The switch is atomic. Post-switch validation runs immediately after the switch. If it fails, rollback restores the previous `current` symlink.

## Forbidden Behaviour

This phase does not support production deployment, production rollback, real Composer install/update operations, Drush update/cache-rebuild operations, hardcoded credentials, or hardcoded SSH keys.
