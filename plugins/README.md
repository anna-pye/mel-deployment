# Plugin Interface

The plugin framework defines mock-only contracts for deployment phases.

Contract files in `deploy/plugins/` describe supported plugin types, expected inputs, and expected outputs. They must not execute commands, contact servers, run Composer, run Drush, or carry secrets. The staging executor invokes these contracts as profile-driven mock plugins.

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

The loader in `deploy/lib/plugins.sh` validates contract shape and supports mock invocation from deployment profiles. It never loads executable plugin code.
