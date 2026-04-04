#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FEEDBACK_APPLY_COMPAT_MODE=update
exec "${SCRIPT_DIR}/feedback_apply.sh" "$@"
