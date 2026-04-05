#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [project_repo_path]" >&2
  exit 1
fi

PROJECT_REPO_PATH="${1:-$(pwd)}"

if [ ! -d "${PROJECT_REPO_PATH}" ]; then
  echo "Error: project_repo_path does not exist: ${PROJECT_REPO_PATH}" >&2
  exit 1
fi

PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
PROJECT_NAME="$(feedback_project_name_from_path "${PROJECT_REPO_PATH}")"
LOCK_ROOT="$(feedback_state_dir)/update/locks"
LOCK_DIR="${LOCK_ROOT}/${PROJECT_NAME}.lock"
COMPAT_MODE="${FEEDBACK_APPLY_COMPAT_MODE:-auto}"

mkdir -p "${LOCK_ROOT}"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "Apply/update already in progress for '${PROJECT_NAME}'; skipping this run."
  exit 0
fi

release_lock() {
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap release_lock EXIT

"${SCRIPT_DIR}/register_project.sh" "${PROJECT_NAME}" >/dev/null

HUB_FEEDBACK="$(feedback_project_feedback_dir "${PROJECT_NAME}")"
HUB_LEARNINGS="$(feedback_learnings_dir)"
PROJECT_FEEDBACK_LINK="${PROJECT_REPO_PATH}/feedback"
PROJECT_LEARNINGS_LINK="${PROJECT_REPO_PATH}/learnings"
HUB_FEEDBACK_REAL="$(readlink -f "${HUB_FEEDBACK}" 2>/dev/null || true)"
HUB_LEARNINGS_REAL="$(readlink -f "${HUB_LEARNINGS}" 2>/dev/null || true)"

ALREADY_INTEGRATED="false"
if [ -L "${PROJECT_FEEDBACK_LINK}" ] && [ -n "${HUB_FEEDBACK_REAL}" ]; then
  PROJECT_FEEDBACK_REAL="$(readlink -f "${PROJECT_FEEDBACK_LINK}" 2>/dev/null || true)"
  PROJECT_LEARNINGS_REAL="$(readlink -f "${PROJECT_LEARNINGS_LINK}" 2>/dev/null || true)"
  if [ "${PROJECT_FEEDBACK_REAL}" = "${HUB_FEEDBACK_REAL}" ] && [ -n "${HUB_LEARNINGS_REAL}" ] && [ "${PROJECT_LEARNINGS_REAL}" = "${HUB_LEARNINGS_REAL}" ]; then
    ALREADY_INTEGRATED="true"
  fi
fi

if [ -e "${PROJECT_FEEDBACK_LINK}" ] && [ ! -L "${PROJECT_FEEDBACK_LINK}" ]; then
  echo "Error: ${PROJECT_FEEDBACK_LINK} exists and is not a symlink." >&2
  echo "Move/remove it first, then rerun this command." >&2
  exit 1
fi

ln -sfn "${HUB_FEEDBACK}" "${PROJECT_FEEDBACK_LINK}"

if [ -L "${PROJECT_LEARNINGS_LINK}" ]; then
  ln -sfn "${HUB_LEARNINGS}" "${PROJECT_LEARNINGS_LINK}"
elif [ -e "${PROJECT_LEARNINGS_LINK}" ]; then
  EXISTING_LEARNINGS_REAL="$(readlink -f "${PROJECT_LEARNINGS_LINK}" 2>/dev/null || true)"
  if [ -z "${HUB_LEARNINGS_REAL}" ] || [ "${EXISTING_LEARNINGS_REAL}" != "${HUB_LEARNINGS_REAL}" ]; then
    echo "Error: ${PROJECT_LEARNINGS_LINK} exists and does not match hub learnings path." >&2
    echo "Expected: ${HUB_LEARNINGS}" >&2
    exit 1
  fi
else
  ln -sfn "${HUB_LEARNINGS}" "${PROJECT_LEARNINGS_LINK}"
fi

GITIGNORE_TARGET="$("${SCRIPT_DIR}/feedback_ensure_gitignore.sh" "${PROJECT_REPO_PATH}")"
INSTRUCTIONS_TARGET="$("${SCRIPT_DIR}/feedback_upsert_agent_instructions.sh" "${PROJECT_NAME}" "${PROJECT_REPO_PATH}")"

ACTION_LABEL="Applied integration for"
ACTION_DETAIL="refreshed"
case "${COMPAT_MODE}" in
  init)
    ACTION_LABEL="Initialized project"
    ACTION_DETAIL="initialized"
    ;;
  update)
    ACTION_LABEL="Updated project"
    ACTION_DETAIL="refreshed"
    ;;
  auto)
    if [ "${ALREADY_INTEGRATED}" = "false" ]; then
      ACTION_DETAIL="initialized"
    fi
    ;;
  *)
    echo "Error: unsupported FEEDBACK_APPLY_COMPAT_MODE: ${COMPAT_MODE}" >&2
    exit 1
    ;;
esac

if [ "${COMPAT_MODE}" = "auto" ]; then
  echo "${ACTION_LABEL} '${PROJECT_NAME}' (${ACTION_DETAIL})"
else
  echo "${ACTION_LABEL} '${PROJECT_NAME}'"
fi
echo "Project repo: ${PROJECT_REPO_PATH}"
echo "Hub feedback: ${HUB_FEEDBACK}"
echo "Linked: ${PROJECT_FEEDBACK_LINK} -> ${HUB_FEEDBACK}"
echo "Linked: ${PROJECT_LEARNINGS_LINK} -> ${HUB_LEARNINGS}"
echo "Git ignore ensured in: ${GITIGNORE_TARGET}"
echo "Agent instructions updated in: ${INSTRUCTIONS_TARGET}"
