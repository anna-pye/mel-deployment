#!/usr/bin/env bash

mel_validate_path() {
  local label="$1"
  local path="$2"

  if [[ -z "$path" ]]; then
    printf '%s must not be empty\n' "$label"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ "$path" != /* ]]; then
    printf '%s must be an absolute path\n' "$label"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ "$path" == "/" ]]; then
    printf '%s must not be the root directory\n' "$label"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ "$path" == *"//"* ]]; then
    printf '%s must not contain duplicate separators\n' "$label"
    return "$MEL_EXIT_ERROR"
  fi

  if [[ "$path" =~ (^|/)\.\.(/|$) ]]; then
    printf '%s must not contain parent-directory traversal\n' "$label"
    return "$MEL_EXIT_ERROR"
  fi

  return "$MEL_EXIT_SUCCESS"
}
