#!/usr/bin/env bash

mel_version() {
  local version_file="${MEL_ROOT}/VERSION"

  if [[ ! -r "$version_file" ]]; then
    printf 'unknown\n'
    return "$MEL_EXIT_WARNING"
  fi

  tr -d '\n' < "$version_file"
  printf '\n'
}

mel_usage() {
  cat <<'EOF'
Usage:
  mel validate [--manifest FILE] [--schema FILE]
  mel resolve [--manifest FILE] [--schema FILE] [--output FILE] [--pretty]
  mel plan [--manifest FILE] [--schema FILE] [--output FILE] [--pretty]
  mel policy [--manifest FILE] [--schema FILE] [--profile FILE] [--approval NAME]...
  mel dry-run [--manifest FILE] [--schema FILE] [--plan FILE]
  mel doctor ENVIRONMENT [--profile FILE] [--json]
  mel info
  mel version

Commands:
  validate  Validate manifest, schema, paths, and repository metadata.
  resolve   Convert a validated manifest into a canonical deployment model.
  plan      Convert a resolved deployment model into an execution plan.
  policy    Evaluate whether a planned deployment is allowed.
  dry-run   Print a read-only simulation for an execution plan.
  doctor    Run read-only deployment readiness checks for an environment.
  info      Print local engine metadata.
  version   Print the engine version.
EOF
}

mel_validate_repository_metadata() {
  if [[ ! -d "${MEL_ROOT}/.git" ]]; then
    mel_output_error "$MEL_CODE_REPOSITORY_INVALID" "repository metadata is missing"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ ! -r "${MEL_ROOT}/VERSION" ]]; then
    mel_output_error "$MEL_CODE_REPOSITORY_INVALID" "VERSION file is missing or unreadable"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ ! -d "${MEL_ROOT}/deploy/lib" || ! -d "${MEL_ROOT}/deploy/bin" ]]; then
    mel_output_error "$MEL_CODE_REPOSITORY_INVALID" "deploy library or binary directory is missing"
    return "$MEL_EXIT_ERROR"
  fi

  return "$MEL_EXIT_SUCCESS"
}
