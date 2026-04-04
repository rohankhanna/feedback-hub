#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [desktop_root]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESKTOP_ROOT="${1:-${FEEDBACK_DESKTOP_ROOT:-${HOME}/Desktop}}"
LOCK_ROOT="${REPO_ROOT}/.state/update-all"
LOCK_DIR="${LOCK_ROOT}/.lock"

if [ ! -d "${DESKTOP_ROOT}" ]; then
  echo "Error: desktop root does not exist: ${DESKTOP_ROOT}" >&2
  exit 1
fi

mkdir -p "${LOCK_ROOT}"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "feedback apply-all is already running; skipping this run."
  exit 0
fi

release_lock() {
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap release_lock EXIT

TMP_LIST="$(mktemp)"
{
  find "${REPO_ROOT}/projects" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
    | while IFS= read -r project_name; do
        repo_dir="${DESKTOP_ROOT}/${project_name}"
        if [ -d "${repo_dir}" ]; then
          printf "%s\n" "${repo_dir}"
        fi
      done
  find "${DESKTOP_ROOT}" -mindepth 1 -maxdepth 2 -type d -name .git -print \
    | sed 's#/\.git$##'
} | sort -u > "${TMP_LIST}"

TOTAL=0
UPDATED=0
FAILED=0

while IFS= read -r repo_dir; do
  [ -z "${repo_dir}" ] && continue
  TOTAL=$((TOTAL + 1))

  echo "=== feedback apply ${repo_dir} ==="
  if "${SCRIPT_DIR}/feedback_apply.sh" "${repo_dir}"; then
    UPDATED=$((UPDATED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done < "${TMP_LIST}"

rm -f "${TMP_LIST}"

echo
echo "Apply-all summary: total=${TOTAL}, updated=${UPDATED}, failed=${FAILED}"
if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
