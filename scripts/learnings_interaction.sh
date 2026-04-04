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
  learnings adopt <learning_id> [project_repo_path] [--note "..."] [--json]
  learnings reject <learning_id> [project_repo_path] [--reason "..."] [--json]
  learnings defer <learning_id> [project_repo_path] [--reason "..."] [--json]
USAGE
}

looks_like_feedback_artifact_path() {
  local candidate="${1:-}"
  case "${candidate}" in
    feedback/*.md|feedback/*/*.md|*/feedback/*.md|*/feedback/*/*.md)
      return 0
      ;;
  esac
  return 1
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 1
fi

ACTION="$1"
shift

case "${ACTION}" in
  adopt|reject|defer) ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "Error: action must be adopt|reject|defer" >&2
    exit 1
    ;;
esac

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 1
fi

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

LEARNING_ID="$1"
shift

PROJECT_REPO_PATH="$(pwd)"
NOTE=""
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --note|--reason)
      NOTE="${2:-}"
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

if ! feedback_learnings_require_db >/dev/null 2>&1; then
  "${SCRIPT_DIR}/learnings_index.sh" --quiet >/dev/null
fi
feedback_learnings_prepare_db_writes

LEARNING_PATH="$(feedback_learnings_lookup_path_by_id "${LEARNING_ID}")"
LEARNING_TITLE="$(feedback_learnings_lookup_title_by_id "${LEARNING_ID}")"

if [ -z "${LEARNING_PATH}" ] || [ -z "${LEARNING_TITLE}" ]; then
  echo "Error: learning not found: ${LEARNING_ID}" >&2
  exit 1
fi

if [ ! -d "${PROJECT_REPO_PATH}" ] && looks_like_feedback_artifact_path "${PROJECT_REPO_PATH}"; then
  echo "Error: learnings ${ACTION} expects an optional project repo path, not a feedback artifact path: ${PROJECT_REPO_PATH}" >&2
  echo "Pass the repository root instead, for example: learnings ${ACTION} ${LEARNING_ID} /absolute/path/to/project" >&2
  exit 1
fi

PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
PROJECT_NAME="$(feedback_project_name_from_path "${PROJECT_REPO_PATH}")"
"${SCRIPT_DIR}/register_project.sh" "${PROJECT_NAME}" >/dev/null

INTERACTION_DIR="$(feedback_project_feedback_subdir "${PROJECT_NAME}" "incoming")"
feedback_mkdir_if_missing "${INTERACTION_DIR}"

STAMP="$(feedback_stamp_utc)"
TIMESTAMP_UTC="$(feedback_timestamp_utc)"
SLUG="$(feedback_slugify "${ACTION}-${LEARNING_TITLE}")"
INTERACTION_ID="interaction_${STAMP}_$(feedback_slugify "${PROJECT_NAME}-${ACTION}-${LEARNING_ID}")"
OUTPUT_FILE="${INTERACTION_DIR}/${STAMP}-${SLUG}.md"
INDEX=1

while [ -e "${OUTPUT_FILE}" ]; do
  INDEX=$((INDEX + 1))
  OUTPUT_FILE="${INTERACTION_DIR}/${STAMP}-${SLUG}-${INDEX}.md"
done

{
  printf -- '---\n'
  printf 'schema_version: 1\n'
  printf 'interaction_id: %s\n' "${INTERACTION_ID}"
  printf 'project: %s\n' "${PROJECT_NAME}"
  printf 'kind: incoming\n'
  printf 'interaction_action: %s\n' "${ACTION}"
  printf 'learning_id: %s\n' "${LEARNING_ID}"
  printf 'learning_title: %s\n' "${LEARNING_TITLE}"
  printf 'recorded_at: %s\n' "${TIMESTAMP_UTC}"
  printf 'source_repo: %s\n' "${PROJECT_REPO_PATH}"
  if [ -n "${NOTE}" ]; then
    printf 'note: %s\n' "${NOTE}"
  fi
  printf -- '---\n\n'
  printf '# Learning Interaction: %s %s\n\n' "$(printf '%s' "${ACTION}" | tr '[:lower:]' '[:upper:]' | sed 's/^./&/')" "${LEARNING_TITLE}"
  printf '## Learning\n'
  printf -- '- id: %s\n' "${LEARNING_ID}"
  printf -- '- title: %s\n' "${LEARNING_TITLE}"
  printf -- '- source_path: %s\n\n' "${LEARNING_PATH}"
  printf '## Decision\n'
  printf -- '- action: %s\n' "${ACTION}"
  if [ -n "${NOTE}" ]; then
    printf -- '- note: %s\n' "${NOTE}"
  fi
  printf '\n## Context\nDescribe why this learning was %s for this project.\n' "${ACTION}"
} > "${OUTPUT_FILE}"

JSONL_PATH="$(feedback_learnings_interactions_dir)/${PROJECT_NAME}.jsonl"
feedback_mkdir_if_missing "$(dirname "${JSONL_PATH}")"
jq -nc \
  --arg interaction_id "${INTERACTION_ID}" \
  --arg project "${PROJECT_NAME}" \
  --arg learning_id "${LEARNING_ID}" \
  --arg learning_title "${LEARNING_TITLE}" \
  --arg action "${ACTION}" \
  --arg note "${NOTE}" \
  --arg recorded_at "${TIMESTAMP_UTC}" \
  --arg artifact_path "${OUTPUT_FILE}" \
  '{
    interaction_id: $interaction_id,
    project: $project,
    learning_id: $learning_id,
    learning_title: $learning_title,
    action: $action,
    note: $note,
    recorded_at: $recorded_at,
    artifact_path: $artifact_path
  }' >> "${JSONL_PATH}"
printf '\n' >> "${JSONL_PATH}"

if [ -f "$(feedback_learnings_db_path)" ]; then
  feedback_learnings_sqlite_write_best_effort "interaction index update" <<SQL || true
INSERT OR REPLACE INTO interactions(id, project_name, learning_id, action, note, created_at)
VALUES (
  '$(feedback_escape_sql "${INTERACTION_ID}")',
  '$(feedback_escape_sql "${PROJECT_NAME}")',
  '$(feedback_escape_sql "${LEARNING_ID}")',
  '$(feedback_escape_sql "${ACTION}")',
  '$(feedback_escape_sql "${NOTE}")',
  '$(feedback_escape_sql "${TIMESTAMP_UTC}")'
);
SQL
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg interaction_id "${INTERACTION_ID}" \
    --arg project "${PROJECT_NAME}" \
    --arg learning_id "${LEARNING_ID}" \
    --arg action "${ACTION}" \
    --arg note "${NOTE}" \
    --arg recorded_at "${TIMESTAMP_UTC}" \
    --arg artifact_path "${OUTPUT_FILE}" \
    '{
      interaction_id: $interaction_id,
      project: $project,
      learning_id: $learning_id,
      action: $action,
      note: $note,
      recorded_at: $recorded_at,
      artifact_path: $artifact_path
    }'
else
  echo "Recorded ${ACTION}: ${LEARNING_ID}"
  echo "Artifact: ${OUTPUT_FILE}"
fi
