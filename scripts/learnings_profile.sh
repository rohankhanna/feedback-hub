#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/project_context.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"

usage() {
  cat <<'USAGE'
Usage:
  learnings profile [project_repo_path] [--json]
USAGE
}

PROJECT_REPO_PATH="$(pwd)"
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      if [ "${PROJECT_REPO_PATH}" != "$(pwd)" ]; then
        echo "Error: only one project_repo_path may be provided." >&2
        usage >&2
        exit 1
      fi
      PROJECT_REPO_PATH="$1"
      shift
      ;;
  esac
done

PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
PROFILE_PATH="$(feedback_write_project_profile "${PROJECT_REPO_PATH}")"
PROFILE_HASH="$(feedback_sha256_file "${PROFILE_PATH}")"
feedback_learnings_ensure_db
feedback_learnings_prepare_db_writes

feedback_learnings_sqlite_write_best_effort "project profile cache update" <<SQL || true
INSERT OR REPLACE INTO project_profiles(
  project_name,
  repo_path,
  languages_json,
  frameworks_json,
  repo_kind,
  runtime_traits_json,
  state_profile,
  profile_hash,
  updated_at
)
VALUES (
  '$(feedback_escape_sql "$(jq -r '.project_name' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "$(jq -r '.repo_path' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "$(jq -c '.tech.languages' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "$(jq -c '.tech.frameworks' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "$(jq -r '.tech.repo_kind' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "$(jq -c '.ops.runtime_traits' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "$(jq -r '.ops.state_profile' "${PROFILE_PATH}")")',
  '$(feedback_escape_sql "${PROFILE_HASH}")',
  '$(feedback_escape_sql "$(jq -r '.generated_at' "${PROFILE_PATH}")")'
);
SQL

if [ "${JSON_OUTPUT}" = "true" ]; then
  cat "${PROFILE_PATH}"
else
  echo "Profile written: ${PROFILE_PATH}"
  jq -r '
    "Project: \(.project_name)\n" +
    "Repo path: \(.repo_path)\n" +
    "Git: present=\(.git.present) commits=\(.git.commit_count) remote=\(.git.has_remote) dirty=\(.git.dirty_worktree)\n" +
    "Languages: \(.tech.languages | join(", "))\n" +
    "Frameworks: \(.tech.frameworks | join(", "))\n" +
    "Repo kind: \(.tech.repo_kind)\n" +
    "State profile: \(.ops.state_profile)\n" +
    "Runtime traits: \(.ops.runtime_traits | join(", "))\n" +
    "Risk flags: \(.risk_flags | join(", "))"
  ' "${PROFILE_PATH}"
fi
