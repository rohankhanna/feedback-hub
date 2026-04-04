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
  learnings related <learning_id> [--limit N] [--json]
USAGE
}

LEARNING_ID=""
LIMIT=10
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --limit)
      LIMIT="${2:-10}"
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

feedback_require_positive_integer "${LIMIT}" "limit" || exit 1

if ! feedback_learnings_require_db >/dev/null 2>&1; then
  "${SCRIPT_DIR}/learnings_index.sh" --quiet >/dev/null
fi

DB_SEPARATOR=$'\x1f'
RESULTS="$(sqlite3 -separator "${DB_SEPARATOR}" "$(feedback_learnings_db_path)" <<SQL
WITH base AS (
  SELECT id, type FROM learning_entities WHERE id = '$(feedback_escape_sql "${LEARNING_ID}")'
),
base_tags AS (
  SELECT tag FROM learning_tags WHERE learning_id = '$(feedback_escape_sql "${LEARNING_ID}")'
),
base_facets AS (
  SELECT facet_key, facet_value FROM learning_facets WHERE learning_id = '$(feedback_escape_sql "${LEARNING_ID}")'
),
scores AS (
  SELECT
    e.id,
    e.title,
    e.path,
    e.type,
    (
      CASE WHEN e.type = (SELECT type FROM base) THEN 1 ELSE 0 END +
      (SELECT COUNT(*) FROM learning_tags t JOIN base_tags bt ON t.tag = bt.tag WHERE t.learning_id = e.id) +
      (SELECT COUNT(*) FROM learning_facets f JOIN base_facets bf ON f.facet_key = bf.facet_key AND f.facet_value = bf.facet_value WHERE f.learning_id = e.id)
    ) AS score
  FROM learning_entities e
  WHERE e.id != '$(feedback_escape_sql "${LEARNING_ID}")'
    AND e.status = 'active'
)
SELECT id, title, path, type, score
FROM scores
WHERE score > 0
ORDER BY score DESC, title ASC
LIMIT ${LIMIT};
SQL
)"

USAGE_PROJECT_PATH="$(feedback_infer_usage_project_path "$(pwd)" 2>/dev/null || true)"
if [ -n "${USAGE_PROJECT_PATH}" ]; then
  USAGE_PROJECT_NAME="$(feedback_project_name_from_path "${USAGE_PROJECT_PATH}")"
  RESULT_COUNT="$(printf '%s\n' "${RESULTS}" | awk 'NF { count += 1 } END { print count + 0 }')"
  RELATED_METADATA="$(jq -nc \
    --argjson limit "${LIMIT}" \
    --argjson result_count "${RESULT_COUNT:-0}" \
    '{limit: $limit, result_count: $result_count}')"
  feedback_learnings_record_usage_event "${USAGE_PROJECT_NAME}" "learnings related" "related" "${LEARNING_ID}" "" "${RELATED_METADATA}"
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  printf '%s\n' "${RESULTS}" | jq -Rn --arg learning_id "${LEARNING_ID}" --arg sep "${DB_SEPARATOR}" '
    [
      inputs
      | select(length > 0)
      | split($sep)
      | {
          id: .[0],
          title: .[1],
          path: .[2],
          type: .[3],
          score: (.[4] | tonumber)
        }
    ]
    | {
        learning_id: $learning_id,
        results: .
      }
  '
else
  echo "Related learnings for: ${LEARNING_ID}"
  while IFS="${DB_SEPARATOR}" read -r id title path type score; do
    [ -z "${id}" ] && continue
    echo
    echo "[${score}] ${title} (${id})"
    echo "Type: ${type}"
    echo "Path: ${path}"
  done <<< "${RESULTS}"
fi
