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
  feedback status [project_repo_path] [--json]
USAGE
}

PROJECT_REPO_PATH="$(pwd)"
JSON_OUTPUT="false"

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
HUB_FEEDBACK="$(feedback_project_feedback_dir "${PROJECT_NAME}")"
HUB_LEARNINGS="$(feedback_learnings_dir)"
PROJECT_FEEDBACK_LINK="${PROJECT_REPO_PATH}/feedback"
PROJECT_LEARNINGS_LINK="${PROJECT_REPO_PATH}/learnings"
AGENTS_FILE="${PROJECT_REPO_PATH}/AGENTS.md"
GITIGNORE_FILE="${PROJECT_REPO_PATH}/.gitignore"

feedback_link_ok="false"
learnings_link_ok="false"
managed_block_present="false"
gitignore_feedback="false"
gitignore_learnings="false"

if [ -L "${PROJECT_FEEDBACK_LINK}" ] && [ "$(feedback_readlink_real "${PROJECT_FEEDBACK_LINK}")" = "$(feedback_readlink_real "${HUB_FEEDBACK}")" ]; then
  feedback_link_ok="true"
fi

if [ "${PROJECT_REPO_PATH}" = "${FEEDBACK_REPO_ROOT}" ]; then
  learnings_link_ok="true"
elif [ -L "${PROJECT_LEARNINGS_LINK}" ] && [ "$(feedback_readlink_real "${PROJECT_LEARNINGS_LINK}")" = "$(feedback_readlink_real "${HUB_LEARNINGS}")" ]; then
  learnings_link_ok="true"
fi

if [ -f "${AGENTS_FILE}" ] && grep -Fq '<!-- feedback-hub:managed:start -->' "${AGENTS_FILE}" && grep -Fq '<!-- feedback-hub:managed:end -->' "${AGENTS_FILE}"; then
  managed_block_present="true"
fi

if [ -f "${GITIGNORE_FILE}" ] && grep -Fxq 'feedback' "${GITIGNORE_FILE}"; then
  gitignore_feedback="true"
fi

if [ "${PROJECT_REPO_PATH}" = "${FEEDBACK_REPO_ROOT}" ]; then
  gitignore_learnings="n/a"
elif [ -f "${GITIGNORE_FILE}" ] && grep -Fxq 'learnings' "${GITIGNORE_FILE}"; then
  gitignore_learnings="true"
else
  gitignore_learnings="false"
fi

USAGE_SUMMARY_JSON="$(feedback_learnings_usage_summary_json "${PROJECT_NAME}")"
last_learnings_consulted_at="$(printf '%s\n' "${USAGE_SUMMARY_JSON}" | jq -r '.last_consulted_at')"
learnings_consult_count_7d="$(printf '%s\n' "${USAGE_SUMMARY_JSON}" | jq -r '.total_consults_in_window')"
soft_reminder_due="$(printf '%s\n' "${USAGE_SUMMARY_JSON}" | jq -r '.soft_reminder_due')"
soft_reminder_message="$(printf '%s\n' "${USAGE_SUMMARY_JSON}" | jq -r '.soft_reminder_message')"

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg project "${PROJECT_NAME}" \
    --arg project_repo_path "${PROJECT_REPO_PATH}" \
    --arg hub_feedback "${HUB_FEEDBACK}" \
    --arg hub_learnings "${HUB_LEARNINGS}" \
    --arg agents_file "${AGENTS_FILE}" \
    --argjson feedback_link_ok "$(feedback_json_bool "${feedback_link_ok}")" \
    --argjson learnings_link_ok "$(feedback_json_bool "${learnings_link_ok}")" \
    --argjson managed_block_present "$(feedback_json_bool "${managed_block_present}")" \
    --argjson gitignore_feedback "$(feedback_json_bool "${gitignore_feedback}")" \
    --arg last_learnings_consulted_at "${last_learnings_consulted_at}" \
    --argjson learnings_consult_count_7d "${learnings_consult_count_7d}" \
    --argjson soft_reminder_due "$(feedback_json_bool "${soft_reminder_due}")" \
    --arg soft_reminder_message "${soft_reminder_message}" \
    --arg gitignore_learnings "${gitignore_learnings}" \
    '{
      project: $project,
      project_repo_path: $project_repo_path,
      hub_feedback: $hub_feedback,
      hub_learnings: $hub_learnings,
      agents_file: $agents_file,
      feedback_link_ok: $feedback_link_ok,
      learnings_link_ok: $learnings_link_ok,
      managed_block_present: $managed_block_present,
      gitignore_feedback: $gitignore_feedback,
      last_learnings_consulted_at: $last_learnings_consulted_at,
      learnings_consult_count_7d: $learnings_consult_count_7d,
      soft_reminder_due: $soft_reminder_due,
      soft_reminder_message: $soft_reminder_message,
      gitignore_learnings: $gitignore_learnings
    }'
else
  echo "Project: ${PROJECT_NAME}"
  echo "Project repo: ${PROJECT_REPO_PATH}"
  echo "Feedback link ok: ${feedback_link_ok}"
  echo "Learnings link ok: ${learnings_link_ok}"
  echo "Managed AGENTS block present: ${managed_block_present}"
  echo "Git ignore has feedback: ${gitignore_feedback}"
  echo "Git ignore has learnings: ${gitignore_learnings}"
  echo "Last learnings consultation: ${last_learnings_consulted_at:-never recorded}"
  echo "Learnings consult count (7d): ${learnings_consult_count_7d}"
  if [ "${soft_reminder_due}" = "true" ]; then
    echo "Reminder: ${soft_reminder_message}"
  fi
fi
