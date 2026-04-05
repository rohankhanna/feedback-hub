#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <project_name>" >&2
  exit 1
fi

PROJECT_NAME="$1"

if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: project_name must match [a-zA-Z0-9._-]+" >&2
  exit 1
fi

FEEDBACK_DIR="$(feedback_project_feedback_dir "${PROJECT_NAME}")"
LEARNINGS_DIR="$(feedback_learnings_dir)"

feedback_mkdir_if_missing "${LEARNINGS_DIR}"
mkdir -p \
  "${FEEDBACK_DIR}/incoming" \
  "${FEEDBACK_DIR}/outgoing" \
  "${FEEDBACK_DIR}/decisions" \
  "${FEEDBACK_DIR}/incidents" \
  "${FEEDBACK_DIR}/lessons"

echo "Project registered: ${PROJECT_NAME}"
echo "Created: ${FEEDBACK_DIR}/{incoming,outgoing,decisions,incidents,lessons}"
echo
echo "Run feedback apply inside the target project repo to link:"
echo "  feedback -> ${FEEDBACK_DIR}"
echo "  learnings -> ${LEARNINGS_DIR}"
