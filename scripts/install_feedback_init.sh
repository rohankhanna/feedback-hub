#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Notice: install_feedback_init.sh is deprecated. Use install_feedback.sh."
exec "${SCRIPT_DIR}/install_feedback.sh" "$@"
