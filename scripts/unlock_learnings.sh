#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LEARNINGS_DIR="${REPO_ROOT}/learnings"

usage() {
  cat <<'USAGE'
Usage:
  learnings unlock
USAGE
}

case "${1:-}" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [ ! -d "${LEARNINGS_DIR}" ]; then
  echo "Error: learnings directory not found at ${LEARNINGS_DIR}" >&2
  exit 1
fi

# Manager (owner) can write during a curation window.
chmod -R u+w "${LEARNINGS_DIR}"

echo "Unlocked learnings tree for manager writes: ${LEARNINGS_DIR}"
