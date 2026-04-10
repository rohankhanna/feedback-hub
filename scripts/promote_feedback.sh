#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/artifacts.sh"

usage() {
  cat <<'USAGE'
Usage:
  learnings promote <project_name> <feedback_relative_path> <learnings_subdir> [copy|move]
USAGE
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  usage >&2
  exit 1
fi

PROJECT_NAME="$1"
SOURCE_REL="$2"
DEST_SUBDIR="$3"
ACTION="${4:-copy}"

case "${ACTION}" in
  copy|move) ;;
  *)
    echo "Error: action must be 'copy' or 'move'" >&2
    exit 1
    ;;
esac

case "${DEST_SUBDIR}" in
  patterns|templates|agents|anti-patterns|patterns/*|templates/*|agents/*|anti-patterns/*) ;;
  *)
    echo "Error: learnings_subdir must be under patterns|templates|agents|anti-patterns" >&2
    exit 1
    ;;
esac

SOURCE_PATH="$(feedback_project_feedback_dir "${PROJECT_NAME}")/${SOURCE_REL}"
DEST_DIR="$(feedback_learnings_dir)/${DEST_SUBDIR}"

if [ ! -e "${SOURCE_PATH}" ]; then
  echo "Error: source artifact not found: ${SOURCE_PATH}" >&2
  exit 1
fi

if [ "${SOURCE_PATH##*.}" != "json" ]; then
  echo "Error: promotion source must be a structured JSON artifact: ${SOURCE_PATH}" >&2
  exit 1
fi

SOURCE_CLASS="$(jq -r '.schema.artifact_class // ""' "${SOURCE_PATH}")"
if [ "${SOURCE_CLASS}" != "project_feedback" ]; then
  echo "Error: promotion source must have schema.artifact_class=project_feedback: ${SOURCE_PATH}" >&2
  exit 1
fi

PUBLICATION_BLOCK_REASON="$(feedback_artifact_publication_block_reason "${SOURCE_PATH}")"
if [ -n "${PUBLICATION_BLOCK_REASON}" ]; then
  echo "Error: promotion source is not public-learning safe: ${PUBLICATION_BLOCK_REASON}" >&2
  exit 1
fi

if [ ! -d "${DEST_DIR}" ]; then
  mkdir -p "${DEST_DIR}"
fi

if [ ! -w "${DEST_DIR}" ]; then
  echo "Error: destination is not writable: ${DEST_DIR}" >&2
  echo "Run scripts/unlock_learnings.sh before promoting." >&2
  exit 1
fi

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SOURCE_NAME="$(basename "${SOURCE_PATH}")"
TARGET_PATH="${DEST_DIR}/${SOURCE_NAME}"

if [ -e "${TARGET_PATH}" ]; then
  TARGET_PATH="${DEST_DIR}/${TIMESTAMP}_${SOURCE_NAME}"
fi

LEARNING_ID="$(feedback_artifact_new_id "learning")"
SOURCE_ID="$(jq -r '.artifact.id // ""' "${SOURCE_PATH}")"
LEARNING_KIND="$(printf '%s\n' "${DEST_SUBDIR}" | cut -d'/' -f1)"
case "${LEARNING_KIND}" in
  patterns) LEARNING_KIND="pattern" ;;
  anti-patterns) LEARNING_KIND="anti-pattern" ;;
  templates) LEARNING_KIND="template" ;;
  agents) LEARNING_KIND="agent" ;;
esac

jq \
  --arg family "$(feedback_artifact_schema_family)" \
  --argjson version "$(feedback_artifact_schema_version)" \
  --arg artifact_class "learning" \
  --argjson artifact_class_version "$(feedback_artifact_class_version "learning")" \
  --arg learning_id "${LEARNING_ID}" \
  --arg learning_kind "${LEARNING_KIND}" \
  --arg dest_subdir "${DEST_SUBDIR}" \
  --arg source_id "${SOURCE_ID}" \
  --arg promoted_at "${TIMESTAMP}" \
  '
  .schema.family = $family
  | .schema.version = $version
  | .schema.artifact_class = $artifact_class
  | .schema.artifact_class_version = $artifact_class_version
  | .artifact.id = $learning_id
  | .artifact.kind = $learning_kind
  | .policy.distribution_scope = "generalized-shareable"
  | .extensions.feedback = (.extensions.feedback // {})
  | .extensions.learning = {
      bucket: $dest_subdir,
      promoted_at: $promoted_at,
      source_artifact_id: $source_id
    }
  | .links.related_artifacts = (
      if $source_id == "" then (.links.related_artifacts // [])
      else ((.links.related_artifacts // []) + [$source_id] | unique)
      end
    )
  ' "${SOURCE_PATH}" > "${TARGET_PATH}"

if [ "${ACTION}" = "move" ]; then
  rm -f "${SOURCE_PATH}"
fi

LOG_FILE="$(feedback_learnings_dir)/promotion-log.tsv"
TARGET_REL="${TARGET_PATH#$(feedback_data_root)/}"

printf "%s\t%s\t%s\t%s\t%s\n" \
  "${TIMESTAMP}" \
  "${ACTION}" \
  "${PROJECT_NAME}" \
  "projects/${PROJECT_NAME}/feedback/${SOURCE_REL}" \
  "${TARGET_REL}" >> "${LOG_FILE}"

echo "Promotion complete: ${ACTION} ${SOURCE_PATH} -> ${TARGET_PATH}"
echo "Logged: ${LOG_FILE}"
