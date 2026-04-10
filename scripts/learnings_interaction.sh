#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/artifacts.sh"

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
    feedback/*.md|feedback/*/*.md|*/feedback/*.md|*/feedback/*/*.md|feedback/*.json|feedback/*/*.json|*/feedback/*.json|*/feedback/*/*.json)
      return 0
      ;;
  esac
  return 1
}

validate_generalized_note() {
  local note="$1"
  local project_name="$2"
  local project_repo_path="$3"

  [ -z "${note}" ] && return 0

  if [ -n "${project_name}" ] && printf '%s\n' "${note}" | grep -Fqi "${project_name}"; then
    echo "Error: interaction note must be generalized and must not include the local project name." >&2
    return 1
  fi

  if [ -n "${project_repo_path}" ] && printf '%s\n' "${note}" | grep -Fq "${project_repo_path}"; then
    echo "Error: interaction note must be generalized and must not include the local repo path." >&2
    return 1
  fi

  if printf '%s\n' "${note}" | grep -Eq 'file:///(home|tmp)|/home/|/tmp/|[A-Za-z]:\\\\'; then
    echo "Error: interaction note must not include concrete local paths." >&2
    return 1
  fi
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

validate_generalized_note "${NOTE}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"

INTERACTION_DIR="$(feedback_project_feedback_subdir "${PROJECT_NAME}" "incoming")"
feedback_mkdir_if_missing "${INTERACTION_DIR}"

STAMP="$(feedback_stamp_utc)"
TIMESTAMP_UTC="$(feedback_timestamp_utc)"
SLUG="$(feedback_slugify "${ACTION}-referenced-learning")"
INTERACTION_ID="$(feedback_artifact_new_id "learning-interaction")"
OUTPUT_FILE="${INTERACTION_DIR}/${STAMP}-${SLUG}.json"
INDEX=1

while [ -e "${OUTPUT_FILE}" ]; do
  INDEX=$((INDEX + 1))
  OUTPUT_FILE="${INTERACTION_DIR}/${STAMP}-${SLUG}-${INDEX}.json"
done

if [ -n "${FEEDBACK_WRITER_TYPE:-}" ]; then
  WRITER_TYPE="${FEEDBACK_WRITER_TYPE}"
elif [ -n "${FEEDBACK_WRITER_MODEL_NAME:-}${FEEDBACK_WRITER_MODEL_ID:-}" ]; then
  WRITER_TYPE="agent"
else
  WRITER_TYPE="human"
fi

WRITER_TOOL="${FEEDBACK_WRITER_TOOL:-feedback-hub}"
WRITER_PROVIDER="${FEEDBACK_WRITER_PROVIDER:-}"
WRITER_MODEL_NAME="${FEEDBACK_WRITER_MODEL_NAME:-}"
WRITER_MODEL_ID="${FEEDBACK_WRITER_MODEL_ID:-}"
REVIEW_STATUS="${FEEDBACK_REVIEW_STATUS:-unreviewed}"
ANONYMIZATION_REVIEWED="${FEEDBACK_ANONYMIZATION_REVIEWED:-false}"
PROMPT_INJECTION_REVIEWED="${FEEDBACK_PROMPT_INJECTION_REVIEWED:-false}"

ARTIFACT_JSON="$(
  feedback_artifact_base_json "learning_interaction" "${INTERACTION_ID}" "interaction" "${ACTION^} referenced learning" "${TIMESTAMP_UTC}" \
    | jq \
      --arg topic "$(feedback_slugify "${ACTION}-referenced-learning")" \
      --arg learning_id "${LEARNING_ID}" \
      --arg writer_type "${WRITER_TYPE}" \
      --arg writer_tool "${WRITER_TOOL}" \
      --arg writer_provider "${WRITER_PROVIDER}" \
      --arg writer_model_name "${WRITER_MODEL_NAME}" \
      --arg writer_model_id "${WRITER_MODEL_ID}" \
      --arg review_status "${REVIEW_STATUS}" \
      --argjson anonymization_reviewed "$(feedback_json_bool "${ANONYMIZATION_REVIEWED}")" \
      --argjson prompt_injection_reviewed "$(feedback_json_bool "${PROMPT_INJECTION_REVIEWED}")" \
      --arg action "${ACTION}" \
      --arg note "${NOTE}" \
      --arg summary "Recorded ${ACTION} for a referenced learning." \
      --arg result "Learning marked as ${ACTION}." \
      '
      .subject.topic = $topic
      | .writer.writer_type = $writer_type
      | .writer.tool = $writer_tool
      | .writer.provider = $writer_provider
      | .writer.model.display_name = $writer_model_name
      | .writer.model.id = $writer_model_id
      | .review.status = $review_status
      | .review.anonymization_reviewed = $anonymization_reviewed
      | .review.prompt_injection_reviewed = $prompt_injection_reviewed
      | .policy.distribution_scope = "project-private"
      | .policy.public_safe = false
      | .policy.embargo_status = "needs-review"
      | .policy.rights_status = "needs-review"
      | .content.summary = $summary
      | .content.context = $note
      | .content.result = $result
      | .links.related_artifacts = [$learning_id]
      | .extensions.interaction = {
          action: $action,
          note: $note
        }
      '
)"

printf '%s\n' "${ARTIFACT_JSON}" > "${OUTPUT_FILE}"

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
    --argjson artifact "${ARTIFACT_JSON}" \
    '{
      interaction_id: $interaction_id,
      project: $project,
      learning_id: $learning_id,
      action: $action,
      note: $note,
      recorded_at: $recorded_at,
      artifact_path: $artifact_path,
      artifact: $artifact
    }'
else
  echo "Recorded ${ACTION}: ${LEARNING_ID}"
  echo "Artifact: ${OUTPUT_FILE}"
fi
