#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <project_name> <project_repo_path>" >&2
  exit 1
fi

PROJECT_NAME="$1"
PROJECT_REPO_PATH="$2"

if [ ! -d "${PROJECT_REPO_PATH}" ]; then
  echo "Error: project_repo_path does not exist: ${PROJECT_REPO_PATH}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_REPO_PATH="$(cd "${PROJECT_REPO_PATH}" && pwd)"

AGENT_CONFIG_FILE="${REPO_ROOT}/config/agents.env"
if [ -f "${AGENT_CONFIG_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${AGENT_CONFIG_FILE}"
fi

START_MARKER="<!-- feedback-hub:managed:start -->"
END_MARKER="<!-- feedback-hub:managed:end -->"
CANONICAL_FILE="${PROJECT_REPO_PATH}/AGENTS.md"
MIRROR_FILES="${FEEDBACK_AGENT_MIRROR_FILES:-CLAUDE.md,CURSOR.md,GEMINI.md,COPILOT.md}"
MIRROR_EXISTING_ONLY="${FEEDBACK_AGENT_MIRROR_EXISTING_ONLY:-true}"

to_bool() {
  case "$1" in
    true|TRUE|1|yes|YES|on|ON) echo "true" ;;
    *) echo "false" ;;
  esac
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "${value}"
}

ensure_file() {
  local path="$1"
  local default_heading="$2"
  if [ ! -f "${path}" ]; then
    printf "# %s\n" "${default_heading}" > "${path}"
  fi
}

upsert_managed_block() {
  local target_file="$1"
  local tmp_file
  local normalized_file

  tmp_file="$(mktemp)"
  awk -v start="${START_MARKER}" -v end="${END_MARKER}" '
    BEGIN { in_block = 0 }
    $0 == start { in_block = 1; next }
    $0 == end { in_block = 0; next }
    !in_block { print }
  ' "${target_file}" > "${tmp_file}"

  cat >> "${tmp_file}" <<EOF_BLOCK

${START_MARKER}
## Feedback Hub Integration (Managed)

- Treat \`feedback/\` as this project's local feedback area managed through the feedback-hub workflow.
- Write project artifacts only under \`feedback/{incoming,outgoing,decisions,incidents,lessons}\`.
- Treat \`learnings/\` as shared cross-project memory that is read-only for projects.
- Do not write directly to \`learnings/\`.
- Keep local \`feedback/\` and \`learnings/\` paths out of the project repo's own version control.
- Initialize Git early and keep substantive work under version control.
- Before substantive work, run \`learnings recommend --json\`.
- Before targeted design, debugging, or architecture changes, run \`learnings search "<query>" --json\`.
- If a learning materially affects implementation, record the outcome with \`learnings adopt\`, \`learnings reject\`, or \`learnings defer\`.
- During substantive work, write feedback artifacts as part of task execution, not as optional cleanup.
- Use \`feedback/lessons/\` for reusable implementation or workflow learnings.
- Use \`feedback/decisions/\` for material architectural or design decisions.
- Use \`feedback/incidents/\` for failures, regressions, debugging outcomes, and root-cause notes.
- Use \`feedback/outgoing/\` for cross-project guidance, and \`feedback/incoming/\` for external guidance adopted here.
- Use \`feedback capture\` or \`feedback lesson|decision|incident|incoming|outgoing\` to record those artifacts.
- Keep each feedback artifact short and concrete.
- In final responses for substantive work, explicitly list any feedback artifacts created or updated.
${END_MARKER}
EOF_BLOCK

  normalized_file="$(mktemp)"
  awk '
    BEGIN { started = 0; pending_blank = 0 }
    /^[[:space:]]*$/ {
      if (started) {
        pending_blank = 1
      }
      next
    }
    {
      if (started && pending_blank) {
        print ""
      }
      print
      started = 1
      pending_blank = 0
    }
  ' "${tmp_file}" > "${normalized_file}"

  mv "${normalized_file}" "${target_file}"
  rm -f "${tmp_file}"
}

mirror_if_enabled() {
  local mirror_list="$1"
  local mirror_existing_only="$2"
  local raw_name
  local file_name
  local target_file
  local heading

  IFS=',' read -r -a MIRROR_ARRAY <<< "${mirror_list}"
  for raw_name in "${MIRROR_ARRAY[@]}"; do
    file_name="$(trim "${raw_name}")"
    [ -z "${file_name}" ] && continue

    target_file="${PROJECT_REPO_PATH}/${file_name}"
    [ "${target_file}" = "${CANONICAL_FILE}" ] && continue

    if [ "${mirror_existing_only}" = "true" ] && [ ! -f "${target_file}" ]; then
      continue
    fi

    heading="$(basename "${file_name}")"
    heading="${heading%.*}"
    heading="${heading^^}"
    ensure_file "${target_file}" "${heading}"
    upsert_managed_block "${target_file}"
  done
}

ensure_file "${CANONICAL_FILE}" "AGENTS"
upsert_managed_block "${CANONICAL_FILE}"
mirror_if_enabled "${MIRROR_FILES}" "$(to_bool "${MIRROR_EXISTING_ONLY}")"

echo "${CANONICAL_FILE}"
