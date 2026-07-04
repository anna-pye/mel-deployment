#!/usr/bin/env bash

mel_output_result() {
  local status="$1"
  local code="$2"
  local message="$3"

  printf '[%s] %s: %s\n' "$status" "$code" "$message"
}

mel_output_detail() {
  local key="$1"
  local value="$2"

  printf '  %s: %s\n' "$key" "$value"
}

mel_output_success() {
  mel_output_result "$MEL_STATUS_SUCCESS" "$1" "$2"
}

mel_output_warning() {
  mel_output_result "$MEL_STATUS_WARNING" "$1" "$2"
}

mel_output_error() {
  mel_output_result "$MEL_STATUS_ERROR" "$1" "$2" >&2
}
