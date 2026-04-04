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
  learnings validate <learning_id> [--note "..."] [--json]
USAGE
}

LEARNING_ID=""
NOTE=""
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --note)
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
feedback_learnings_prepare_db_writes

LEARNING_PATH="$(feedback_learnings_lookup_path_by_id "${LEARNING_ID}")"
if [ -z "${LEARNING_PATH}" ]; then
  echo "Error: learning not found: ${LEARNING_ID}" >&2
  exit 1
fi

if ! LOG_PATH="$(feedback_learnings_append_validation "${LEARNING_ID}" "${NOTE}")"; then
  echo "Error: unable to write validation log. Unlock learnings first." >&2
  exit 1
fi

if [ -f "$(feedback_learnings_db_path)" ]; then
  feedback_learnings_sqlite_write_best_effort "validation index update" <<SQL || true
UPDATE learning_entities
SET last_validated_at = '$(feedback_escape_sql "$(feedback_timestamp_utc)")'
WHERE id = '$(feedback_escape_sql "${LEARNING_ID}")';
SQL
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg learning_id "${LEARNING_ID}" \
    --arg learning_path "${LEARNING_PATH}" \
    --arg note "${NOTE}" \
    --arg logged_to "${LOG_PATH}" \
    --arg validated_at "$(feedback_timestamp_utc)" \
    '{
      learning_id: $learning_id,
      learning_path: $learning_path,
      note: $note,
      logged_to: $logged_to,
      validated_at: $validated_at
    }'
else
  echo "Validated learning: ${LEARNING_ID}"
  echo "Log: ${LOG_PATH}"
fi
