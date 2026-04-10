#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/artifacts.sh"

usage() {
  cat <<'USAGE'
Usage:
  feedback capture --kind lesson|decision|incident|incoming|outgoing --title "<title>" [project_repo_path]
                   [--summary "..."] [--context "..."] [--action-taken "..."] [--result "..."]
                   [--reuse-guidance "..."] [--body-file path] [--tags a,b]
                   [--suggest patterns|anti-patterns|agents|templates] [--json]
USAGE
}

validate_generalized_field() {
  local label="$1"
  local value="$2"
  local project_name="$3"
  local project_repo_path="$4"

  [ -z "${value}" ] && return 0

  if [ -n "${project_name}" ] && printf '%s\n' "${value}" | grep -Fqi "${project_name}"; then
    printf 'Error: %s must be generalized and must not include the local project name.\n' "${label}" >&2
    return 1
  fi

  if [ -n "${project_repo_path}" ] && printf '%s\n' "${value}" | grep -Fq "${project_repo_path}"; then
    printf 'Error: %s must be generalized and must not include the local repo path.\n' "${label}" >&2
    return 1
  fi

  if printf '%s\n' "${value}" | grep -Eq 'file:///(home|tmp)|/home/|/tmp/|[A-Za-z]:\\\\'; then
    printf 'Error: %s must not include concrete local paths.\n' "${label}" >&2
    return 1
  fi
}

KIND=""
TITLE=""
SUMMARY=""
CONTEXT=""
ACTION_TAKEN=""
RESULT=""
REUSE_GUIDANCE=""
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
    --context)
      CONTEXT="${2:-}"
      shift 2
      ;;
    --action-taken)
      ACTION_TAKEN="${2:-}"
      shift 2
      ;;
    --result)
      RESULT="${2:-}"
      shift 2
      ;;
    --reuse-guidance)
      REUSE_GUIDANCE="${2:-}"
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

BODY_MARKDOWN=""
if [ -n "${BODY_FILE}" ]; then
  BODY_MARKDOWN="$(cat "${BODY_FILE}")"
fi

SUMMARY_TEXT="${SUMMARY:-${TITLE}}"

validate_generalized_field "title" "${TITLE}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"
validate_generalized_field "summary" "${SUMMARY_TEXT}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"
validate_generalized_field "context" "${CONTEXT}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"
validate_generalized_field "action_taken" "${ACTION_TAKEN}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"
validate_generalized_field "result" "${RESULT}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"
validate_generalized_field "reuse_guidance" "${REUSE_GUIDANCE}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"
validate_generalized_field "body_markdown" "${BODY_MARKDOWN}" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}"

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
OUTPUT_FILE="${OUTPUT_DIR}/${STAMP}-${SLUG}.json"
INDEX=1

while [ -e "${OUTPUT_FILE}" ]; do
  INDEX=$((INDEX + 1))
  OUTPUT_FILE="${OUTPUT_DIR}/${STAMP}-${SLUG}-${INDEX}.json"
done

ARTIFACT_ID="$(feedback_artifact_new_id "project-feedback")"
TAGS_JSON="$(feedback_artifact_json_array_from_csv "${TAGS_RAW}")"

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

case "${KIND}" in
  outgoing) DEFAULT_DISTRIBUTION_SCOPE="restricted-shareable" ;;
  *) DEFAULT_DISTRIBUTION_SCOPE="project-private" ;;
esac

DISTRIBUTION_SCOPE="${FEEDBACK_DISTRIBUTION_SCOPE:-${DEFAULT_DISTRIBUTION_SCOPE}}"
PUBLIC_SAFE="${FEEDBACK_PUBLIC_SAFE:-false}"
EMBARGO_STATUS="${FEEDBACK_EMBARGO_STATUS:-needs-review}"
RIGHTS_STATUS="${FEEDBACK_RIGHTS_STATUS:-needs-review}"

ARTIFACT_JSON="$(
  feedback_artifact_base_json "project_feedback" "${ARTIFACT_ID}" "${KIND}" "${TITLE}" "${TIMESTAMP_UTC}" \
    | jq \
      --arg topic "$(feedback_slugify "${TITLE}")" \
      --arg writer_type "${WRITER_TYPE}" \
      --arg writer_tool "${WRITER_TOOL}" \
      --arg writer_provider "${WRITER_PROVIDER}" \
      --arg writer_model_name "${WRITER_MODEL_NAME}" \
      --arg writer_model_id "${WRITER_MODEL_ID}" \
      --arg review_status "${REVIEW_STATUS}" \
      --argjson anonymization_reviewed "$(feedback_json_bool "${ANONYMIZATION_REVIEWED}")" \
      --argjson prompt_injection_reviewed "$(feedback_json_bool "${PROMPT_INJECTION_REVIEWED}")" \
      --arg distribution_scope "${DISTRIBUTION_SCOPE}" \
      --argjson public_safe "$(feedback_json_bool "${PUBLIC_SAFE}")" \
      --arg embargo_status "${EMBARGO_STATUS}" \
      --arg rights_status "${RIGHTS_STATUS}" \
      --arg summary "${SUMMARY_TEXT}" \
      --arg body_markdown "${BODY_MARKDOWN}" \
      --arg context "${CONTEXT}" \
      --arg action_taken "${ACTION_TAKEN}" \
      --arg result "${RESULT}" \
      --arg reuse_guidance "${REUSE_GUIDANCE}" \
      --arg feedback_bucket "${TARGET_SUBDIR}" \
      --arg suggested_promotion "${SUGGESTED_PROMOTION}" \
      --argjson tags "${TAGS_JSON}" \
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
      | .policy.distribution_scope = $distribution_scope
      | .policy.public_safe = $public_safe
      | .policy.embargo_status = $embargo_status
      | .policy.rights_status = $rights_status
      | .content.summary = $summary
      | .content.body_markdown = $body_markdown
      | .content.context = $context
      | .content.action_taken = $action_taken
      | .content.result = $result
      | .content.reuse_guidance = $reuse_guidance
      | .extensions.feedback = {
          bucket: $feedback_bucket,
          suggested_promotion: $suggested_promotion,
          tags: $tags
        }
      '
)"

printf '%s\n' "${ARTIFACT_JSON}" > "${OUTPUT_FILE}"

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg id "${ARTIFACT_ID}" \
    --arg kind "${KIND}" \
    --arg title "${TITLE}" \
    --arg path "${OUTPUT_FILE}" \
    --arg captured_at "${TIMESTAMP_UTC}" \
    --arg suggested_promotion "${SUGGESTED_PROMOTION}" \
    --arg soft_reminder "${SOFT_REMINDER}" \
    --argjson tags "${TAGS_JSON}" \
    --argjson artifact "${ARTIFACT_JSON}" \
    '{
      id: $id,
      kind: $kind,
      title: $title,
      path: $path,
      captured_at: $captured_at,
      suggested_promotion: $suggested_promotion,
      soft_reminder: $soft_reminder,
      tags: $tags,
      artifact: $artifact
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
