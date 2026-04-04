#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <project_name>" >&2
  exit 1
fi

PROJECT_NAME="$1"

if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "Error: project_name must match [a-zA-Z0-9._-]+" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FEEDBACK_DIR="${REPO_ROOT}/projects/${PROJECT_NAME}/feedback"

mkdir -p \
  "${FEEDBACK_DIR}/incoming" \
  "${FEEDBACK_DIR}/outgoing" \
  "${FEEDBACK_DIR}/decisions" \
  "${FEEDBACK_DIR}/incidents" \
  "${FEEDBACK_DIR}/lessons"

echo "Project registered: ${PROJECT_NAME}"
echo "Created: ${FEEDBACK_DIR}/{incoming,outgoing,decisions,incidents,lessons}"
echo
echo "To link a project repo manually:"
echo "  ln -sfn <feedback_hub_repo>/projects/${PROJECT_NAME}/feedback <project_repo>/feedback"
echo "  ln -sfn <feedback_hub_repo>/learnings <project_repo>/learnings"
