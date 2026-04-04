#!/usr/bin/env bash
set -euo pipefail

FEEDBACK_JSON_LIB_SELF="${BASH_SOURCE[0]}"
FEEDBACK_JSON_LIB_DIR="$(cd "$(dirname "${FEEDBACK_JSON_LIB_SELF}")" && pwd)"
# shellcheck disable=SC1091
source "${FEEDBACK_JSON_LIB_DIR}/common.sh"

feedback_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed." >&2
    return 1
  fi
}

feedback_json_array_from_lines() {
  feedback_require_jq
  jq -Rsc 'split("\n") | map(select(length > 0))'
}

feedback_json_object() {
  feedback_require_jq
  jq -n "$@"
}

feedback_unique_sorted_lines() {
  awk 'NF { print }' | sort -u
}
