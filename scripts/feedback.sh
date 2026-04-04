#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  RESOLVED_PATH="$(readlink -f "${SCRIPT_PATH}" 2>/dev/null || true)"
  if [ -n "${RESOLVED_PATH}" ]; then
    SCRIPT_PATH="${RESOLVED_PATH}"
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  feedback <command> [args]

Commands:
  apply [project_repo_path]   Apply feedback-hub integration to a project repo
  apply-all [desktop_root]    Apply integration across repos under a root
  status [project_repo_path]  Show integration status for a project
  capture --kind ...          Capture a feedback artifact into project feedback
  lesson <title> [path]       Capture a lesson into feedback/lessons
  decision <title> [path]     Capture a decision into feedback/decisions
  incident <title> [path]     Capture an incident into feedback/incidents
  incoming <title> [path]     Capture adopted external guidance into feedback/incoming
  outgoing <title> [path]     Capture cross-project guidance into feedback/outgoing
  learn <title> [path]        Deprecated alias for `feedback lesson`
  delete [path] [--purge --yes]
                              Remove local links; optionally purge hub project feedback
  register <project_name>     Create hub feedback folders only
  lock                        Deprecated alias for `learnings lock`
  unlock                      Deprecated alias for `learnings unlock`
  promote <args...>           Deprecated alias for `learnings promote`
  help                        Show this help
USAGE
}

is_help_token() {
  case "${1:-}" in
    help|-h|--help) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "${COMMAND}" in
  apply)
    exec "${SCRIPT_DIR}/feedback_apply.sh" "$@"
    ;;
  apply-all)
    exec "${SCRIPT_DIR}/feedback_apply_all.sh" "$@"
    ;;
  init)
    exec "${SCRIPT_DIR}/feedback_init.sh" "$@"
    ;;
  update)
    exec "${SCRIPT_DIR}/feedback_update.sh" "$@"
    ;;
  update-all)
    exec "${SCRIPT_DIR}/feedback_update_all.sh" "$@"
    ;;
  status)
    exec "${SCRIPT_DIR}/feedback_status.sh" "$@"
    ;;
  capture)
    exec "${SCRIPT_DIR}/feedback_capture.sh" "$@"
    ;;
  lesson|decision|incident|incoming|outgoing)
    for arg in "$@"; do
      if is_help_token "${arg}"; then
        echo "Usage: feedback ${COMMAND} <title> [project_repo_path]"
        exit 0
      fi
    done
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
      echo "Usage: feedback ${COMMAND} <title> [project_repo_path]" >&2
      exit 1
    fi
    exec "${SCRIPT_DIR}/feedback_capture.sh" --kind "${COMMAND}" --title "$1" "${@:2}"
    ;;
  learn)
    for arg in "$@"; do
      if is_help_token "${arg}"; then
        echo "Usage: feedback learn <title> [project_repo_path]"
        exit 0
      fi
    done
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
      echo "Usage: feedback learn <title> [project_repo_path]" >&2
      exit 1
    fi
    echo "Notice: feedback learn is deprecated. Use 'feedback lesson'." >&2
    exec "${SCRIPT_DIR}/feedback_capture.sh" --kind lesson --title "$1" "${@:2}"
    ;;
  delete)
    exec "${SCRIPT_DIR}/feedback_delete.sh" "$@"
    ;;
  register)
    exec "${SCRIPT_DIR}/register_project.sh" "$@"
    ;;
  lock)
    echo "Notice: feedback lock is deprecated. Use 'learnings lock'." >&2
    exec "${SCRIPT_DIR}/lock_learnings.sh" "$@"
    ;;
  unlock)
    echo "Notice: feedback unlock is deprecated. Use 'learnings unlock'." >&2
    exec "${SCRIPT_DIR}/unlock_learnings.sh" "$@"
    ;;
  promote)
    echo "Notice: feedback promote is deprecated. Use 'learnings promote'." >&2
    exec "${SCRIPT_DIR}/promote_feedback.sh" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac
