#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
LEARNINGS_DIR="$(feedback_learnings_dir)"

usage() {
  cat <<'USAGE'
Usage:
  learnings lock
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

# Read-only for all users; directories stay traversable.
find "${LEARNINGS_DIR}" -type d -exec chmod a-w {} +
find "${LEARNINGS_DIR}" -type d -exec chmod a+rx {} +
find "${LEARNINGS_DIR}" -type f -exec chmod a-w {} +
find "${LEARNINGS_DIR}" -type f -exec chmod a+r {} +

echo "Locked learnings tree (read-only): ${LEARNINGS_DIR}"
