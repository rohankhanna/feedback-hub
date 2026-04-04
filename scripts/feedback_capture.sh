#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"

usage() {
  cat <<'USAGE'
Usage:
  feedback capture --kind lesson|decision|incident|incoming|outgoing --title "<title>" [project_repo_path]
                   [--summary "..."] [--body-file path] [--tags a,b] [--suggest patterns|anti-patterns|agents|templates]
                   [--json]
USAGE
}

KIND=""
TITLE=""
SUMMARY=""
BODY_FILE=""
TAGS_RAW=""
SUGGESTED_PROMOTION=""
PROJECT_REPO_PATH="$(pwd)"
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kind)
      KIND="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --summary)
      SUMMARY="${2:-}"
      shift 2
      ;;
    --body-file)
      BODY_FILE="${2:-}"
      shift 2
      ;;
    --tags)
      TAGS_RAW="${2:-}"
      shift 2
      ;;
    --suggest)
      SUGGESTED_PROMOTION="${2:-}"
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

case "${KIND}" in
  lesson) TARGET_SUBDIR="lessons" ;;
  decision) TARGET_SUBDIR="decisions" ;;
  incident) TARGET_SUBDIR="incidents" ;;
  incoming) TARGET_SUBDIR="incoming" ;;
  outgoing) TARGET_SUBDIR="outgoing" ;;
  *)
    echo "Error: --kind must be one of lesson|decision|incident|incoming|outgoing" >&2
    usage >&2
    exit 1
    ;;
esac

if [ -z "${TITLE}" ]; then
  echo "Error: --title is required." >&2
  usage >&2
  exit 1
fi

if [ -n "${BODY_FILE}" ] && [ ! -f "${BODY_FILE}" ]; then
  echo "Error: body file not found: ${BODY_FILE}" >&2
  exit 1
fi

case "${SUGGESTED_PROMOTION}" in
  ""|patterns|templates|agents|anti-patterns) ;;
  *)
    echo "Error: --suggest must be one of patterns|templates|agents|anti-patterns" >&2
    exit 1
    ;;
esac

PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
PROJECT_NAME="$(feedback_project_name_from_path "${PROJECT_REPO_PATH}")"
"${SCRIPT_DIR}/register_project.sh" "${PROJECT_NAME}" >/dev/null

SOFT_REMINDER=""
case "${KIND}" in
  lesson|decision|incident|outgoing)
    USAGE_SUMMARY_JSON="$(feedback_learnings_usage_summary_json "${PROJECT_NAME}")"
    if [ "$(printf '%s\n' "${USAGE_SUMMARY_JSON}" | jq -r '.soft_reminder_due')" = "true" ]; then
      SOFT_REMINDER="Reminder: no recent learnings consultation is recorded for ${PROJECT_NAME}. Before the next substantive task, run 'learnings recommend --json' or 'learnings search \"<query>\" --json'."
    fi
    ;;
esac

OUTPUT_DIR="$(feedback_project_feedback_subdir "${PROJECT_NAME}" "${TARGET_SUBDIR}")"
feedback_mkdir_if_missing "${OUTPUT_DIR}"

TIMESTAMP_UTC="$(feedback_timestamp_utc)"
STAMP="$(feedback_stamp_utc)"
SLUG="$(feedback_slugify "${TITLE}")"
OUTPUT_FILE="${OUTPUT_DIR}/${STAMP}-${SLUG}.md"
INDEX=1

while [ -e "${OUTPUT_FILE}" ]; do
  INDEX=$((INDEX + 1))
  OUTPUT_FILE="${OUTPUT_DIR}/${STAMP}-${SLUG}-${INDEX}.md"
done

ENTRY_ID="fb_${STAMP}_$(feedback_slugify "${PROJECT_NAME}-${KIND}-${TITLE}")"
REPO_BRANCH="$(feedback_git_branch "${PROJECT_REPO_PATH}")"
REPO_COMMIT="$(feedback_git_commit "${PROJECT_REPO_PATH}")"
TAGS_JSON="$(printf '%s' "${TAGS_RAW}" | tr ',' '\n' | awk 'NF { print }' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | feedback_json_array_from_lines)"

{
  printf -- '---\n'
  printf 'schema_version: 1\n'
  printf 'id: %s\n' "${ENTRY_ID}"
  printf 'project: %s\n' "${PROJECT_NAME}"
  printf 'kind: %s\n' "${KIND}"
  printf 'title: %s\n' "${TITLE}"
  printf 'captured_at: %s\n' "${TIMESTAMP_UTC}"
  printf 'source_repo: %s\n' "${PROJECT_REPO_PATH}"
  printf 'source_branch: %s\n' "${REPO_BRANCH}"
  printf 'source_commit: %s\n' "${REPO_COMMIT}"
  if [ -n "${SUGGESTED_PROMOTION}" ]; then
    printf 'suggested_promotion: %s\n' "${SUGGESTED_PROMOTION}"
  fi
  if [ -n "${TAGS_RAW}" ]; then
    printf 'tags: [%s]\n' "$(printf '%s' "${TAGS_RAW}" | tr ',' '\n' | awk 'NF { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); printf "%s%s", sep, $0; sep=", " }')"
  fi
  printf -- '---\n\n'
  printf '# %s: %s\n\n' "$(printf '%s' "${KIND}" | tr '[:lower:]' '[:upper:]' | sed 's/^./&/')" "${TITLE}"
  printf '## Summary\n'
  if [ -n "${SUMMARY}" ]; then
    printf '%s\n\n' "${SUMMARY}"
  else
    printf 'Summarize the important change or lesson here.\n\n'
  fi
  printf '## Context\nDescribe what changed, failed, or was decided.\n\n'
  printf '## Action Taken\nDescribe the action taken.\n\n'
  printf '## Result\nDescribe the result or observed outcome.\n\n'
  printf '## Reuse Guidance\nDescribe how other projects should apply or avoid this.\n'
  if [ -n "${BODY_FILE}" ]; then
    printf '\n\n## Additional Notes\n\n'
    cat "${BODY_FILE}"
    printf '\n'
  fi
} > "${OUTPUT_FILE}"

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg id "${ENTRY_ID}" \
    --arg project "${PROJECT_NAME}" \
    --arg kind "${KIND}" \
    --arg title "${TITLE}" \
    --arg path "${OUTPUT_FILE}" \
    --arg captured_at "${TIMESTAMP_UTC}" \
    --arg suggested_promotion "${SUGGESTED_PROMOTION}" \
    --arg soft_reminder "${SOFT_REMINDER}" \
    --argjson tags "${TAGS_JSON}" \
    '{
      id: $id,
      project: $project,
      kind: $kind,
      title: $title,
      path: $path,
      captured_at: $captured_at,
      suggested_promotion: $suggested_promotion,
      soft_reminder: $soft_reminder,
      tags: $tags
    }'
else
  if [ -n "${SOFT_REMINDER}" ]; then
    echo "${SOFT_REMINDER}" >&2
  fi
  echo "Captured ${KIND}: ${OUTPUT_FILE}"
  if [ -n "${SUGGESTED_PROMOTION}" ]; then
    echo "Suggested promotion target: ${SUGGESTED_PROMOTION}"
  fi
fi
