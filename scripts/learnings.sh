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
  learnings <command> [args]

Commands:
  profile [project_repo_path]      Infer the current project profile
  index [--full] [--json]          Rebuild the learnings index
  search "<query>" [path]          Search curated learnings
  recommend [project_repo_path]    Recommend learnings for a project
  usage [project_repo_path]        Show recent learnings consultation activity
  show <learning_id>               Show one indexed learning
  related <learning_id>            Show related learnings
  adopt <learning_id> [path]       Record adoption of a learning
  reject <learning_id> [path]      Record rejection of a learning
  defer <learning_id> [path]       Record deferral of a learning
  promote <args...>                Promote approved feedback into learnings
  lock                             Lock learnings as read-only
  unlock                           Unlock learnings for manager writes
  validate <learning_id>           Append a validation event
  supersede <old_id> <new_id>      Mark one learning as superseded by another
  help                             Show this help
USAGE
}

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "${COMMAND}" in
  profile)
    exec "${SCRIPT_DIR}/learnings_profile.sh" "$@"
    ;;
  index)
    exec "${SCRIPT_DIR}/learnings_index.sh" "$@"
    ;;
  search)
    exec "${SCRIPT_DIR}/learnings_search.sh" "$@"
    ;;
  recommend)
    exec "${SCRIPT_DIR}/learnings_recommend.sh" "$@"
    ;;
  usage)
    exec "${SCRIPT_DIR}/learnings_usage.sh" "$@"
    ;;
  show)
    exec "${SCRIPT_DIR}/learnings_show.sh" "$@"
    ;;
  related)
    exec "${SCRIPT_DIR}/learnings_related.sh" "$@"
    ;;
  adopt|reject|defer)
    exec "${SCRIPT_DIR}/learnings_interaction.sh" "${COMMAND}" "$@"
    ;;
  promote)
    exec "${SCRIPT_DIR}/learnings_promote.sh" "$@"
    ;;
  lock)
    exec "${SCRIPT_DIR}/learnings_lock.sh" "$@"
    ;;
  unlock)
    exec "${SCRIPT_DIR}/learnings_unlock.sh" "$@"
    ;;
  validate)
    exec "${SCRIPT_DIR}/learnings_validate.sh" "$@"
    ;;
  supersede)
    exec "${SCRIPT_DIR}/learnings_supersede.sh" "$@"
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
