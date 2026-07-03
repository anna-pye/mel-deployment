# Plugin Interface

The plugin framework defines read-only contracts for future deployment phases.

This repository does not implement deployment plugins. Contract files in `deploy/plugins/` describe supported plugin types, expected inputs, and expected outputs. They must not execute commands, modify filesystems, contact servers, run Composer, run Drush, switch symlinks, or create releases.

## Supported Types

- `shared`
- `composer`
- `drush`
- `health`
- `switch_current`

## Contract Rules

Each plugin contract is a JSON file ending in `.plugin.json` with:

- `name`: stable contract name.
- `type`: one of the supported plugin types.
- `executes`: always `false`.
- `inputs`: list of named input contracts.
- `outputs`: list of named output contracts.

The loader in `deploy/lib/plugins.sh` validates contract shape only. It never loads executable code.
