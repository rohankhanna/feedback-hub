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
  learnings show <learning_id> [--json]
USAGE
}

JSON_OUTPUT="false"
LEARNING_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      if [ -n "${LEARNING_ID}" ]; then
        echo "Error: only one learning_id may be provided." >&2
        usage >&2
        exit 1
      fi
      LEARNING_ID="$1"
      shift
      ;;
  esac
done

if [ -z "${LEARNING_ID}" ]; then
  echo "Error: learning_id is required." >&2
  usage >&2
  exit 1
fi

if ! feedback_learnings_require_db >/dev/null 2>&1; then
  "${SCRIPT_DIR}/learnings_index.sh" --quiet >/dev/null
fi

DB_SEPARATOR=$'\x1f'
QUERY_RESULT="$(sqlite3 -separator "${DB_SEPARATOR}" "$(feedback_learnings_db_path)" <<SQL
SELECT
  e.id,
  e.title,
  e.path,
  e.type,
  IFNULL(e.summary, ''),
  IFNULL(e.status, ''),
  IFNULL(e.superseded_by, ''),
  IFNULL(e.last_validated_at, ''),
  IFNULL(e.source_project, ''),
  IFNULL(e.source_artifact, ''),
  IFNULL((SELECT group_concat(tag, ' ') FROM learning_tags WHERE learning_id = e.id), ''),
  IFNULL((SELECT group_concat(facet_key || ':' || facet_value, ' ') FROM learning_facets WHERE learning_id = e.id), '')
FROM learning_entities e
WHERE e.id = '$(feedback_escape_sql "${LEARNING_ID}")'
LIMIT 1;
SQL
)"

if [ -z "${QUERY_RESULT}" ]; then
  echo "Error: learning not found: ${LEARNING_ID}" >&2
  exit 1
fi

IFS="${DB_SEPARATOR}" read -r id title path type summary status superseded_by last_validated_at source_project source_artifact tags_text facets_text <<< "${QUERY_RESULT}"
ABS_PATH="$(feedback_data_root)/${path}"
USAGE_PROJECT_PATH="$(feedback_infer_usage_project_path "$(pwd)" 2>/dev/null || true)"
if [ -n "${USAGE_PROJECT_PATH}" ]; then
  USAGE_PROJECT_NAME="$(feedback_project_name_from_path "${USAGE_PROJECT_PATH}")"
  SHOW_METADATA="$(jq -nc \
    --arg type "${type}" \
    --arg path "${path}" \
    --arg status "${status}" \
    '{type: $type, path: $path, status: $status}')"
  feedback_learnings_record_usage_event "${USAGE_PROJECT_NAME}" "learnings show" "show" "${id}" "" "${SHOW_METADATA}"
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg id "${id}" \
    --arg title "${title}" \
    --arg path "${ABS_PATH}" \
    --arg type "${type}" \
    --arg summary "${summary}" \
    --arg status "${status}" \
    --arg superseded_by "${superseded_by}" \
    --arg last_validated_at "${last_validated_at}" \
    --arg source_project "${source_project}" \
    --arg source_artifact "${source_artifact}" \
    --arg tags_text "${tags_text}" \
    --arg facets_text "${facets_text}" \
    --rawfile body "${ABS_PATH}" \
    '{
      id: $id,
      title: $title,
      path: $path,
      type: $type,
      summary: $summary,
      status: $status,
      superseded_by: $superseded_by,
      last_validated_at: $last_validated_at,
      source_project: $source_project,
      source_artifact: $source_artifact,
      tags_text: $tags_text,
      facets_text: $facets_text,
      body: $body
    }'
else
  echo "${title} (${id})"
  echo "Path: ${ABS_PATH}"
  echo "Type: ${type}"
  echo "Status: ${status}"
  [ -n "${superseded_by}" ] && echo "Superseded by: ${superseded_by}"
  [ -n "${last_validated_at}" ] && echo "Last validated: ${last_validated_at}"
  [ -n "${source_project}" ] && echo "Promoted from: ${source_project}"
  [ -n "${summary}" ] && echo "Summary: ${summary}"
  [ -n "${tags_text}" ] && echo "Tags: ${tags_text}"
  [ -n "${facets_text}" ] && echo "Facets: ${facets_text}"
  echo
  cat "${ABS_PATH}"
fi
