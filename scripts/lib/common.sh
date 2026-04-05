#!/usr/bin/env bash
set -euo pipefail

feedback_resolve_script_path() {
  local script_path="$1"
  local resolved_path

  if command -v readlink >/dev/null 2>&1; then
    resolved_path="$(readlink -f "${script_path}" 2>/dev/null || true)"
    if [ -n "${resolved_path}" ]; then
      script_path="${resolved_path}"
    fi
  fi

  printf '%s\n' "${script_path}"
}

FEEDBACK_LIB_SELF="$(feedback_resolve_script_path "${BASH_SOURCE[0]}")"
FEEDBACK_LIB_DIR="$(cd "$(dirname "${FEEDBACK_LIB_SELF}")" && pwd)"
FEEDBACK_SCRIPT_DIR="$(cd "${FEEDBACK_LIB_DIR}/.." && pwd)"
FEEDBACK_REPO_ROOT="$(cd "${FEEDBACK_SCRIPT_DIR}/.." && pwd)"

feedback_abs_path() {
  local path="$1"
  (cd "${path}" && pwd)
}

feedback_abs_path_maybe_missing() {
  local path="$1"
  local parent_dir
  local base_name

  if [ -d "${path}" ] || [ -L "${path}" ]; then
    feedback_abs_path "${path}"
    return 0
  fi

  parent_dir="$(feedback_abs_path "$(dirname "${path}")")"
  base_name="$(basename "${path}")"
  printf '%s/%s\n' "${parent_dir}" "${base_name}"
}

feedback_derive_data_root_from_local_links() {
  local resolved_link

  resolved_link="$(readlink -f "${FEEDBACK_REPO_ROOT}/learnings" 2>/dev/null || true)"
  case "${resolved_link}" in
    */learnings)
      feedback_abs_path "${resolved_link}/.."
      return 0
      ;;
  esac

  resolved_link="$(readlink -f "${FEEDBACK_REPO_ROOT}/projects" 2>/dev/null || true)"
  case "${resolved_link}" in
    */projects)
      feedback_abs_path "${resolved_link}/.."
      return 0
      ;;
  esac

  resolved_link="$(readlink -f "${FEEDBACK_REPO_ROOT}/.state" 2>/dev/null || true)"
  case "${resolved_link}" in
    */.state)
      feedback_abs_path "${resolved_link}/.."
      return 0
      ;;
  esac

  resolved_link="$(readlink -f "${FEEDBACK_REPO_ROOT}/feedback" 2>/dev/null || true)"
  case "${resolved_link}" in
    */projects/*/feedback)
      feedback_abs_path "${resolved_link}/../../.."
      return 0
      ;;
  esac

  return 1
}

feedback_default_data_root() {
  local configured_root="${FEEDBACK_DATA_ROOT:-${FEEDBACK_RUNTIME_ROOT:-}}"
  local derived_root

  if [ -n "${configured_root}" ]; then
    feedback_abs_path_maybe_missing "${configured_root}"
    return 0
  fi

  derived_root="$(feedback_derive_data_root_from_local_links 2>/dev/null || true)"
  if [ -n "${derived_root}" ]; then
    printf '%s\n' "${derived_root}"
    return 0
  fi

  printf '%s\n' "${FEEDBACK_REPO_ROOT}"
}

FEEDBACK_DATA_ROOT="$(feedback_default_data_root)"

feedback_repo_root() {
  printf '%s\n' "${FEEDBACK_REPO_ROOT}"
}

feedback_data_root() {
  printf '%s\n' "${FEEDBACK_DATA_ROOT}"
}

feedback_script_dir() {
  printf '%s\n' "${FEEDBACK_SCRIPT_DIR}"
}

feedback_timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

feedback_stamp_utc() {
  date -u +"%Y%m%dT%H%M%SZ"
}

feedback_slugify() {
  local value="${1:-}"

  value="$(printf '%s' "${value}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"

  if [ -z "${value}" ]; then
    value="item"
  fi

  printf '%s\n' "${value}"
}

feedback_sha256_file() {
  local file_path="$1"
  sha256sum "${file_path}" | awk '{print $1}'
}

feedback_resolve_project_path() {
  local project_repo_path="${1:-$(pwd)}"

  if [ ! -d "${project_repo_path}" ]; then
    echo "Error: project_repo_path does not exist: ${project_repo_path}" >&2
    return 1
  fi

  feedback_abs_path "${project_repo_path}"
}

feedback_project_name_from_path() {
  local project_repo_path="$1"
  local project_name

  project_name="$(basename "${project_repo_path}")"
  if [[ ! "${project_name}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Error: inferred project name '${project_name}' must match [a-zA-Z0-9._-]+" >&2
    return 1
  fi

  printf '%s\n' "${project_name}"
}

feedback_project_feedback_dir() {
  local project_name="$1"
  printf '%s/projects/%s/feedback\n' "${FEEDBACK_DATA_ROOT}" "${project_name}"
}

feedback_project_feedback_subdir() {
  local project_name="$1"
  local kind="$2"
  printf '%s/projects/%s/feedback/%s\n' "${FEEDBACK_DATA_ROOT}" "${project_name}" "${kind}"
}

feedback_projects_dir() {
  printf '%s/projects\n' "${FEEDBACK_DATA_ROOT}"
}

feedback_learnings_dir() {
  printf '%s/learnings\n' "${FEEDBACK_DATA_ROOT}"
}

feedback_state_dir() {
  printf '%s/.state\n' "${FEEDBACK_DATA_ROOT}"
}

feedback_json_bool() {
  case "${1:-false}" in
    true|TRUE|1|yes|YES|on|ON) printf 'true\n' ;;
    *) printf 'false\n' ;;
  esac
}

feedback_git_branch() {
  local repo_path="$1"

  if git -C "${repo_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${repo_path}" symbolic-ref --quiet --short HEAD 2>/dev/null \
      || git -C "${repo_path}" rev-parse --abbrev-ref HEAD 2>/dev/null \
      || printf 'detached\n'
  else
    printf 'n/a\n'
  fi
}

feedback_git_commit() {
  local repo_path="$1"

  if git -C "${repo_path}" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "${repo_path}" rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
  else
    printf 'unknown\n'
  fi
}

feedback_readlink_real() {
  local path="$1"
  readlink -f "${path}" 2>/dev/null || true
}

feedback_file_mtime_utc() {
  local file_path="$1"
  date -u -r "${file_path}" +"%Y-%m-%dT%H:%M:%SZ"
}

feedback_lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

feedback_escape_sql() {
  printf '%s' "${1:-}" | sed "s/'/''/g"
}

feedback_trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

feedback_is_positive_integer() {
  local value="${1:-}"

  case "${value}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  [ "${value}" -gt 0 ]
}

feedback_require_positive_integer() {
  local value="${1:-}"
  local label="${2:-value}"

  if ! feedback_is_positive_integer "${value}"; then
    printf 'Error: %s must be a positive integer. Got: %s\n' "${label}" "${value:-<empty>}" >&2
    return 1
  fi
}

feedback_sql_real_or_default() {
  local value
  local default_value

  value="$(feedback_trim "${1:-}")"
  default_value="$(feedback_trim "${2:-0}")"

  if printf '%s\n' "${value}" | grep -Eq '^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+)$'; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${default_value}"
  fi
}

feedback_append_line_if_missing() {
  local file_path="$1"
  local line="$2"

  if [ -f "${file_path}" ] && grep -Fxq "${line}" "${file_path}"; then
    return 0
  fi

  if [ -s "${file_path}" ] && [ "$(tail -c1 "${file_path}")" != "" ]; then
    printf '\n' >> "${file_path}"
  fi

  printf '%s\n' "${line}" >> "${file_path}"
}

feedback_repo_contains_file() {
  local repo_path="$1"
  local pattern="$2"

  find "${repo_path}" \
    \( -name .git -o -name node_modules -o -name .venv -o -name feedback -o -name learnings \) -prune \
    -o -type f -name "${pattern}" -print -quit | grep -q .
}

feedback_repo_contains_text() {
  local repo_path="$1"
  local pattern="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -i -l --glob '!feedback/**' --glob '!learnings/**' --glob '!node_modules/**' --glob '!.git/**' \
      --glob '!.venv/**' "${pattern}" "${repo_path}" >/dev/null 2>&1
    return $?
  fi

  grep -R -I -i -m 1 --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv \
    --exclude-dir=feedback --exclude-dir=learnings "${pattern}" "${repo_path}" >/dev/null 2>&1
}

feedback_repo_contains_text_glob() {
  local repo_path="$1"
  local pattern="$2"
  shift 2

  if command -v rg >/dev/null 2>&1; then
    local cmd=("rg" "-i" "-l" "--glob" "!feedback/**" "--glob" "!learnings/**" "--glob" "!node_modules/**" "--glob" "!.git/**" "--glob" "!.venv/**")
    while [ "$#" -gt 0 ]; do
      cmd+=("--glob" "$1")
      shift
    done
    cmd+=("${pattern}" "${repo_path}")
    "${cmd[@]}" >/dev/null 2>&1
    return $?
  fi

  local find_expr=()
  while [ "$#" -gt 0 ]; do
    if [ "${#find_expr[@]}" -gt 0 ]; then
      find_expr+=("-o")
    fi
    find_expr+=("-name" "$1")
    shift
  done

  if [ "${#find_expr[@]}" -eq 0 ]; then
    return 1
  fi

  find "${repo_path}" \
    \( -name .git -o -name node_modules -o -name .venv -o -name feedback -o -name learnings \) -prune \
    -o -type f \( "${find_expr[@]}" \) -print0 \
    | xargs -0 grep -I -i -m 1 "${pattern}" >/dev/null 2>&1
}

feedback_collect_repo_files() {
  local repo_path="$1"

  find "${repo_path}" \
    \( -name .git -o -name node_modules -o -name .venv -o -name feedback -o -name learnings \) -prune \
    -o -type f -print
}

feedback_mkdir_if_missing() {
  local dir_path="$1"
  mkdir -p "${dir_path}"
}
