#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEEDBACK_SOURCE_SCRIPT="${SCRIPT_DIR}/feedback.sh"
LEARNINGS_SOURCE_SCRIPT="${SCRIPT_DIR}/learnings.sh"
BIN_DIR="${HOME}/.local/bin"
FEEDBACK_BIN_PATH="${BIN_DIR}/feedback"
LEARNINGS_BIN_PATH="${BIN_DIR}/learnings"

mkdir -p "${BIN_DIR}"
ln -sfn "${FEEDBACK_SOURCE_SCRIPT}" "${FEEDBACK_BIN_PATH}"
ln -sfn "${LEARNINGS_SOURCE_SCRIPT}" "${LEARNINGS_BIN_PATH}"
chmod +x "${FEEDBACK_SOURCE_SCRIPT}" "${LEARNINGS_SOURCE_SCRIPT}" "${FEEDBACK_BIN_PATH}" "${LEARNINGS_BIN_PATH}"

echo "Installed command: ${FEEDBACK_BIN_PATH} -> ${FEEDBACK_SOURCE_SCRIPT}"
echo "Installed command: ${LEARNINGS_BIN_PATH} -> ${LEARNINGS_SOURCE_SCRIPT}"

case ":${PATH}:" in
  *":${BIN_DIR}:"*)
    echo "PATH check: ${BIN_DIR} is already on PATH."
    ;;
  *)
    echo "PATH check: ${BIN_DIR} is not on PATH."
    echo "Add this line to your shell profile (~/.bashrc or ~/.zshrc):"
    echo "export PATH=\"${HOME}/.local/bin:\$PATH\""
    ;;
esac

echo "Use it from any project directory:"
echo "feedback apply"
echo "feedback apply-all"
echo "feedback status"
echo "feedback lesson \"<lesson title>\""
echo "learnings profile"
echo "learnings recommend"
echo "learnings search \"<query>\""
echo "Or from anywhere:"
echo "feedback apply /absolute/path/to/project"
echo "feedback apply-all /absolute/path/to/desktop"
echo "feedback lesson \"<lesson title>\" /absolute/path/to/project"
echo "learnings recommend /absolute/path/to/project"
