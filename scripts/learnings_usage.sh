#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"

usage() {
  cat <<'USAGE'
Usage:
  learnings usage [project_repo_path] [--days N] [--json]
USAGE
}

PROJECT_REPO_PATH="$(pwd)"
DAYS=7
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --days)
      DAYS="${2:-7}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      if [ "${PROJECT_REPO_PATH}" != "$(pwd)" ]; then
        echo "Error: only one project_repo_path may be provided." >&2
        usage >&2
        exit 1
      fi
      PROJECT_REPO_PATH="$1"
      shift
      ;;
  esac
done

PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
PROJECT_NAME="$(feedback_project_name_from_path "${PROJECT_REPO_PATH}")"
SUMMARY_JSON="$(feedback_learnings_usage_summary_json "${PROJECT_NAME}" "${DAYS}")"

if [ "${JSON_OUTPUT}" = "true" ]; then
  printf '%s\n' "${SUMMARY_JSON}"
else
  echo "Learnings usage for: ${PROJECT_NAME}"
  echo "Project repo: ${PROJECT_REPO_PATH}"
  echo "Window: ${DAYS} day(s)"
  echo "Last consulted: $(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.last_consulted_at // "" | if . == "" then "never recorded" else . end')"
  echo "Recommend calls: $(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.consult_counts.recommend')"
  echo "Search calls: $(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.consult_counts.search')"
  echo "Show calls: $(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.consult_counts.show')"
  echo "Related calls: $(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.consult_counts.related')"
  echo "Consults in window: $(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.total_consults_in_window')"
  if [ "$(printf '%s\n' "${SUMMARY_JSON}" | jq -r '.soft_reminder_due')" = "true" ]; then
    echo "Reminder: consider running 'learnings recommend --json' or 'learnings search \"<query>\" --json' before the next substantive change."
  fi
fi
