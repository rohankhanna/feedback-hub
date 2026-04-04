#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <project_repo_path>" >&2
  exit 1
fi

PROJECT_REPO_PATH="$1"

if [ ! -d "${PROJECT_REPO_PATH}" ]; then
  echo "Error: project_repo_path does not exist: ${PROJECT_REPO_PATH}" >&2
  exit 1
fi

PROJECT_REPO_PATH="$(cd "${PROJECT_REPO_PATH}" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GITIGNORE_PATH="${PROJECT_REPO_PATH}/.gitignore"

ensure_trailing_newline() {
  local target_file="$1"

  if [ -s "${target_file}" ] && [ "$(tail -c1 "${target_file}")" != "" ]; then
    printf '\n' >> "${target_file}"
  fi
}

append_if_missing() {
  local target_file="$1"
  local line="$2"

  if [ -f "${target_file}" ] && grep -Fxq "${line}" "${target_file}"; then
    return
  fi

  ensure_trailing_newline "${target_file}"
  printf '%s\n' "${line}" >> "${target_file}"
}

touch "${GITIGNORE_PATH}"
append_if_missing "${GITIGNORE_PATH}" "# feedback-hub integration"
append_if_missing "${GITIGNORE_PATH}" "feedback"

if [ "${PROJECT_REPO_PATH}" != "${REPO_ROOT}" ]; then
  append_if_missing "${GITIGNORE_PATH}" "learnings"
fi

echo "${GITIGNORE_PATH}"
