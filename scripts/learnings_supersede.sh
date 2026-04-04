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
  learnings supersede <old_learning_id> <new_learning_id> [--json]
USAGE
}

JSON_OUTPUT="false"
declare -a POSITIONAL=()

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
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -ne 2 ]; then
  usage >&2
  exit 1
fi

OLD_ID="${POSITIONAL[0]}"
NEW_ID="${POSITIONAL[1]}"

if ! feedback_learnings_require_db >/dev/null 2>&1; then
  "${SCRIPT_DIR}/learnings_index.sh" --quiet >/dev/null
fi
feedback_learnings_prepare_db_writes

OLD_PATH="$(feedback_learnings_lookup_path_by_id "${OLD_ID}")"
NEW_PATH="$(feedback_learnings_lookup_path_by_id "${NEW_ID}")"

if [ -z "${OLD_PATH}" ]; then
  echo "Error: old learning not found: ${OLD_ID}" >&2
  exit 1
fi

if [ -z "${NEW_PATH}" ]; then
  echo "Error: new learning not found: ${NEW_ID}" >&2
  exit 1
fi

if ! LOG_PATH="$(feedback_learnings_append_supersession "${OLD_ID}" "${NEW_ID}")"; then
  echo "Error: unable to write supersession log. Unlock learnings first." >&2
  exit 1
fi

if [ -f "$(feedback_learnings_db_path)" ]; then
  feedback_learnings_sqlite_write_best_effort "supersession index update" <<SQL || true
UPDATE learning_entities
SET status = 'superseded',
    superseded_by = '$(feedback_escape_sql "${NEW_ID}")'
WHERE id = '$(feedback_escape_sql "${OLD_ID}")';

INSERT OR REPLACE INTO learning_links(from_learning_id, to_learning_id, relation_type)
VALUES (
  '$(feedback_escape_sql "${OLD_ID}")',
  '$(feedback_escape_sql "${NEW_ID}")',
  'superseded_by'
);
SQL
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg old_id "${OLD_ID}" \
    --arg new_id "${NEW_ID}" \
    --arg old_path "${OLD_PATH}" \
    --arg new_path "${NEW_PATH}" \
    --arg logged_to "${LOG_PATH}" \
    --arg timestamp "$(feedback_timestamp_utc)" \
    '{
      old_id: $old_id,
      new_id: $new_id,
      old_path: $old_path,
      new_path: $new_path,
      logged_to: $logged_to,
      timestamp: $timestamp
    }'
else
  echo "Superseded learning: ${OLD_ID} -> ${NEW_ID}"
  echo "Log: ${LOG_PATH}"
fi
