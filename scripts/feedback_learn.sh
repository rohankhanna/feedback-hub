#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Notice: feedback_learn.sh is deprecated. Use feedback_capture.sh or 'feedback lesson'." >&2
exec "${SCRIPT_DIR}/feedback_capture.sh" --kind lesson --title "${1:-}" "${@:2}"
