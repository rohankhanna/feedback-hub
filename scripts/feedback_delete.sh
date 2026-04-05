#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  feedback delete [project_repo_path] [--purge] [--yes]

Behavior:
  - Always removes local project symlinks if they point to feedback-hub.
  - With --purge, also deletes projects/<project_name>/feedback from feedback-hub.
  - --yes is required with --purge to avoid accidental data deletion.
USAGE
}

PROJECT_REPO_PATH="$(pwd)"
PURGE_HUB_PROJECT="false"
CONFIRMED="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --purge)
      PURGE_HUB_PROJECT="true"
      shift
      ;;
    --yes)
      CONFIRMED="true"
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

if [ ! -d "${PROJECT_REPO_PATH}" ]; then
  echo "Error: project_repo_path does not exist: ${PROJECT_REPO_PATH}" >&2
  exit 1
fi

PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
PROJECT_NAME="$(feedback_project_name_from_path "${PROJECT_REPO_PATH}")"

if [ "${PURGE_HUB_PROJECT}" = "true" ] && [ "${CONFIRMED}" != "true" ]; then
  echo "Error: --purge requires --yes." >&2
  usage >&2
  exit 1
fi

HUB_FEEDBACK="$(feedback_project_feedback_dir "${PROJECT_NAME}")"
HUB_LEARNINGS="$(feedback_learnings_dir)"
PROJECT_FEEDBACK_LINK="${PROJECT_REPO_PATH}/feedback"
PROJECT_LEARNINGS_LINK="${PROJECT_REPO_PATH}/learnings"

resolve_path() {
  local path="$1"
  readlink -f "${path}" 2>/dev/null || true
}

remove_link_if_matches() {
  local link_path="$1"
  local expected_target="$2"
  local label="$3"

  if [ -L "${link_path}" ]; then
    local resolved_link
    local resolved_expected
    resolved_link="$(resolve_path "${link_path}")"
    resolved_expected="$(resolve_path "${expected_target}")"
    if [ -n "${resolved_link}" ] && [ -n "${resolved_expected}" ] && [ "${resolved_link}" = "${resolved_expected}" ]; then
      rm -f "${link_path}"
      echo "Removed ${label} symlink: ${link_path}"
    else
      echo "Skipped ${label}: ${link_path} points elsewhere."
    fi
  elif [ -e "${link_path}" ]; then
    echo "Skipped ${label}: ${link_path} exists but is not a symlink."
  else
    echo "No ${label} symlink found at ${link_path}."
  fi
}

remove_link_if_matches "${PROJECT_FEEDBACK_LINK}" "${HUB_FEEDBACK}" "feedback"
remove_link_if_matches "${PROJECT_LEARNINGS_LINK}" "${HUB_LEARNINGS}" "learnings"

if [ "${PURGE_HUB_PROJECT}" = "true" ]; then
  if [ -d "${HUB_FEEDBACK}" ]; then
    rm -rf "${HUB_FEEDBACK}"
    rmdir "$(feedback_projects_dir)/${PROJECT_NAME}" 2>/dev/null || true
    echo "Purged hub feedback directory: ${HUB_FEEDBACK}"
  else
    echo "No hub feedback directory found for ${PROJECT_NAME}."
  fi
fi

echo "Delete operation complete for project '${PROJECT_NAME}'."
