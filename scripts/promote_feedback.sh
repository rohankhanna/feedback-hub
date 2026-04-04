#!/usr/bin/env bash
set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_PATH="${REPO_ROOT}/projects/${PROJECT_NAME}/feedback/${SOURCE_REL}"
DEST_DIR="${REPO_ROOT}/learnings/${DEST_SUBDIR}"

if [ ! -e "${SOURCE_PATH}" ]; then
  echo "Error: source artifact not found: ${SOURCE_PATH}" >&2
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

if [ "${ACTION}" = "copy" ]; then
  cp -a "${SOURCE_PATH}" "${TARGET_PATH}"
else
  mv "${SOURCE_PATH}" "${TARGET_PATH}"
fi

LOG_FILE="${REPO_ROOT}/learnings/promotion-log.tsv"
TARGET_REL="${TARGET_PATH#${REPO_ROOT}/}"

printf "%s\t%s\t%s\t%s\t%s\n" \
  "${TIMESTAMP}" \
  "${ACTION}" \
  "${PROJECT_NAME}" \
  "projects/${PROJECT_NAME}/feedback/${SOURCE_REL}" \
  "${TARGET_REL}" >> "${LOG_FILE}"

echo "Promotion complete: ${ACTION} ${SOURCE_PATH} -> ${TARGET_PATH}"
echo "Logged: ${LOG_FILE}"
