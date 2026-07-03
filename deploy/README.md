# Deploy Directory

The `deploy/` directory contains the local validation, resolution, and planner engine code.

- `deploy/bin/` contains the single `mel` command entrypoint.
- `deploy/lib/` contains shared engine library code.

No deployment execution, rollback, server communication, SSH, rsync, Composer, Drush, release creation, or remote filesystem logic is implemented here.
