#!/usr/bin/env bash
set -euo pipefail

FEEDBACK_PROJECT_CONTEXT_LIB_SELF="${BASH_SOURCE[0]}"
FEEDBACK_PROJECT_CONTEXT_LIB_DIR="$(cd "$(dirname "${FEEDBACK_PROJECT_CONTEXT_LIB_SELF}")" && pwd)"
# shellcheck disable=SC1091
source "${FEEDBACK_PROJECT_CONTEXT_LIB_DIR}/common.sh"
# shellcheck disable=SC1091
source "${FEEDBACK_PROJECT_CONTEXT_LIB_DIR}/json.sh"

feedback_profile_state_dir() {
  printf '%s/learnings/profiles\n' "$(feedback_state_dir)"
}

feedback_profile_output_path() {
  local project_name="$1"
  printf '%s/%s.json\n' "$(feedback_profile_state_dir)" "${project_name}"
}

feedback_detect_languages() {
  local repo_path="$1"

  {
    feedback_repo_contains_file "${repo_path}" "pyproject.toml" && echo "python"
    feedback_repo_contains_file "${repo_path}" "requirements.txt" && echo "python"
    feedback_repo_contains_file "${repo_path}" "*.py" && echo "python"

    feedback_repo_contains_file "${repo_path}" "package.json" && echo "javascript"
    feedback_repo_contains_file "${repo_path}" "*.js" && echo "javascript"

    feedback_repo_contains_file "${repo_path}" "tsconfig.json" && echo "typescript"
    feedback_repo_contains_file "${repo_path}" "*.ts" && echo "typescript"
    feedback_repo_contains_file "${repo_path}" "*.tsx" && echo "typescript"

    feedback_repo_contains_file "${repo_path}" "Cargo.toml" && echo "rust"
    feedback_repo_contains_file "${repo_path}" "*.rs" && echo "rust"

    feedback_repo_contains_file "${repo_path}" "go.mod" && echo "go"
    feedback_repo_contains_file "${repo_path}" "*.go" && echo "go"

    feedback_repo_contains_file "${repo_path}" "*.sh" && echo "shell"
  } | feedback_unique_sorted_lines || true
}

feedback_detect_frameworks() {
  local repo_path="$1"

  {
    feedback_repo_contains_text_glob "${repo_path}" '\bfastapi\b' '*.py' 'pyproject.toml' 'requirements*.txt' && echo "fastapi"
    feedback_repo_contains_text_glob "${repo_path}" '\bdjango\b' '*.py' 'pyproject.toml' 'requirements*.txt' && echo "django"
    feedback_repo_contains_text_glob "${repo_path}" '\bflask\b' '*.py' 'pyproject.toml' 'requirements*.txt' && echo "flask"
    feedback_repo_contains_text_glob "${repo_path}" '\breact\b' '*.js' '*.jsx' '*.ts' '*.tsx' 'package.json' && echo "react"
    feedback_repo_contains_text_glob "${repo_path}" '\bnext\b' '*.js' '*.jsx' '*.ts' '*.tsx' 'package.json' && echo "nextjs"
    feedback_repo_contains_text_glob "${repo_path}" '\bexpress\b' '*.js' '*.jsx' '*.ts' '*.tsx' 'package.json' && echo "express"
    feedback_repo_contains_text_glob "${repo_path}" '@nestjs' '*.js' '*.jsx' '*.ts' '*.tsx' 'package.json' && echo "nestjs"
    feedback_repo_contains_file "${repo_path}" "*.cu" && echo "cuda"
    feedback_repo_contains_text_glob "${repo_path}" '\bcuda\b' '*.cu' '*.cuh' '*.cpp' '*.py' 'CMakeLists.txt' && echo "cuda"
  } | feedback_unique_sorted_lines || true
}

feedback_detect_package_managers() {
  local repo_path="$1"

  {
    feedback_repo_contains_file "${repo_path}" "pyproject.toml" && echo "pip"
    feedback_repo_contains_text_glob "${repo_path}" '\bpoetry\b' 'pyproject.toml' && echo "poetry"
    feedback_repo_contains_file "${repo_path}" "package-lock.json" && echo "npm"
    feedback_repo_contains_file "${repo_path}" "package.json" && echo "npm"
    feedback_repo_contains_file "${repo_path}" "pnpm-lock.yaml" && echo "pnpm"
    feedback_repo_contains_file "${repo_path}" "yarn.lock" && echo "yarn"
    feedback_repo_contains_file "${repo_path}" "Cargo.lock" && echo "cargo"
    feedback_repo_contains_file "${repo_path}" "Cargo.toml" && echo "cargo"
    feedback_repo_contains_file "${repo_path}" "go.mod" && echo "gomod"
  } | feedback_unique_sorted_lines || true
}

feedback_detect_repo_kind() {
  local repo_path="$1"
  local frameworks
  local repo_name

  frameworks="$(feedback_detect_frameworks "${repo_path}")"
  repo_name="$(basename "${repo_path}" | tr '[:upper:]' '[:lower:]')"

  if printf '%s\n' "${frameworks}" | grep -Eq 'fastapi|django|flask|express|nextjs|nestjs'; then
    printf 'service\n'
    return 0
  fi

  if [[ "${repo_name}" =~ bench|benchmark|perf|tests ]]; then
    printf 'benchmark\n'
    return 0
  fi

  if feedback_repo_contains_text_glob "${repo_path}" '\b(click|typer|argparse|clap|cobra)\b' '*.py' '*.rs' '*.go' '*.sh'; then
    printf 'cli\n'
    return 0
  fi

  if feedback_repo_contains_file "${repo_path}" "Dockerfile"; then
    printf 'service\n'
    return 0
  fi

  if feedback_repo_contains_file "${repo_path}" "Cargo.toml" || feedback_repo_contains_file "${repo_path}" "pyproject.toml" || feedback_repo_contains_file "${repo_path}" "package.json"; then
    printf 'application\n'
    return 0
  fi

  printf 'unknown\n'
}

feedback_detect_runtime_traits() {
  local repo_path="$1"
  local repo_kind
  local frameworks

  repo_kind="$(feedback_detect_repo_kind "${repo_path}")"
  frameworks="$(feedback_detect_frameworks "${repo_path}")"

  {
    if [ "${repo_kind}" = "service" ]; then
      echo "long_running"
      echo "local_server"
    fi

    if [ "${repo_kind}" = "cli" ]; then
      echo "local_cli"
    fi

    if feedback_repo_contains_text_glob "${repo_path}" 'cron|crontab|systemd\.timer|schedule' '*.service' '*.timer' '*.sh' '*.py' '*.ts' '*.js' 'crontab' '.github/workflows/*.yml' '.github/workflows/*.yaml'; then
      echo "scheduled"
    fi

    if printf '%s\n' "${frameworks}" | grep -Eq 'cuda'; then
      echo "gpu"
    fi

    if feedback_repo_contains_text_glob "${repo_path}" '\b(torch|tensorrt|cuda|nvidia)\b' '*.py' '*.cu' '*.cpp' 'requirements*.txt' 'pyproject.toml'; then
      echo "gpu"
    fi
  } | feedback_unique_sorted_lines || true
}

feedback_detect_state_profile() {
  local repo_path="$1"
  local repo_kind

  repo_kind="$(feedback_detect_repo_kind "${repo_path}")"

  if feedback_repo_contains_text_glob "${repo_path}" '\b(sqlite|postgres|postgresql|mysql|redis|database|checkpoint|persist|state_dir|state file)\b' '*.py' '*.ts' '*.js' '*.rs' '*.go' '*.sh' '*.sql' '*.toml' '*.yaml' '*.yml' '*.json'; then
    printf 'stateful\n'
    return 0
  fi

  if [ "${repo_kind}" = "service" ]; then
    printf 'stateless\n'
    return 0
  fi

  printf 'unknown\n'
}

feedback_detect_risk_flags() {
  local repo_path="$1"
  local commit_count="0"

  {
    if ! git -C "${repo_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf 'no_git\n'
    else
      commit_count="$(git -C "${repo_path}" rev-list --count HEAD 2>/dev/null || printf '0\n')"
      if [ "${commit_count}" = "0" ]; then
        printf 'no_commits\n'
      fi

      if [ -z "$(git -C "${repo_path}" remote 2>/dev/null || true)" ]; then
        printf 'no_remote\n'
      fi

      if [ -n "$(git -C "${repo_path}" status --porcelain 2>/dev/null || true)" ]; then
        printf 'dirty_worktree\n'
      fi
    fi

    [ ! -f "${repo_path}/AGENTS.md" ] && printf 'no_agents_md\n'
    [ ! -f "${repo_path}/docs/architecture.md" ] && [ ! -f "${repo_path}/architecture.md" ] && printf 'no_architecture_doc\n'
    if ! find "${repo_path}/docs" -type f \( -name '*.drawio' -o -name '*.mmd' -o -name '*.mermaid' -o -name '*.puml' -o -name '*.svg' \) -print -quit 2>/dev/null | grep -q .; then
      printf 'no_diagrams\n'
    fi
  } | feedback_unique_sorted_lines || true
}

feedback_project_profile_json() {
  local repo_path="$1"
  local project_name
  local git_present="false"
  local commit_count="0"
  local has_remote="false"
  local default_branch="n/a"
  local dirty_worktree="false"
  local languages_json
  local frameworks_json
  local package_managers_json
  local runtime_traits_json
  local risk_flags_json
  local repo_kind
  local state_profile
  local has_agents_md="false"
  local has_architecture_doc="false"
  local has_diagrams="false"

  project_name="$(feedback_project_name_from_path "${repo_path}")"

  if git -C "${repo_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_present="true"
    commit_count="$(git -C "${repo_path}" rev-list --count HEAD 2>/dev/null || printf '0\n')"
    if [ -n "$(git -C "${repo_path}" remote 2>/dev/null || true)" ]; then
      has_remote="true"
    fi
    default_branch="$(feedback_git_branch "${repo_path}")"
    if [ -n "$(git -C "${repo_path}" status --porcelain 2>/dev/null || true)" ]; then
      dirty_worktree="true"
    fi
  fi

  [ -f "${repo_path}/AGENTS.md" ] && has_agents_md="true"
  if [ -f "${repo_path}/docs/architecture.md" ] || [ -f "${repo_path}/architecture.md" ]; then
    has_architecture_doc="true"
  fi
  if find "${repo_path}/docs" -type f \( -name '*.drawio' -o -name '*.mmd' -o -name '*.mermaid' -o -name '*.puml' -o -name '*.svg' \) -print -quit 2>/dev/null | grep -q .; then
    has_diagrams="true"
  fi

  languages_json="$(feedback_detect_languages "${repo_path}" | feedback_json_array_from_lines)"
  frameworks_json="$(feedback_detect_frameworks "${repo_path}" | feedback_json_array_from_lines)"
  package_managers_json="$(feedback_detect_package_managers "${repo_path}" | feedback_json_array_from_lines)"
  runtime_traits_json="$(feedback_detect_runtime_traits "${repo_path}" | feedback_json_array_from_lines)"
  risk_flags_json="$(feedback_detect_risk_flags "${repo_path}" | feedback_json_array_from_lines)"
  repo_kind="$(feedback_detect_repo_kind "${repo_path}")"
  state_profile="$(feedback_detect_state_profile "${repo_path}")"

  jq -n \
    --arg schema_version "1" \
    --arg project_name "${project_name}" \
    --arg repo_path "${repo_path}" \
    --arg generated_at "$(feedback_timestamp_utc)" \
    --argjson git_present "$(feedback_json_bool "${git_present}")" \
    --argjson commit_count "${commit_count}" \
    --argjson has_remote "$(feedback_json_bool "${has_remote}")" \
    --arg default_branch "${default_branch}" \
    --argjson dirty_worktree "$(feedback_json_bool "${dirty_worktree}")" \
    --argjson languages "${languages_json}" \
    --argjson frameworks "${frameworks_json}" \
    --argjson package_managers "${package_managers_json}" \
    --arg repo_kind "${repo_kind}" \
    --arg state_profile "${state_profile}" \
    --argjson runtime_traits "${runtime_traits_json}" \
    --argjson has_agents_md "$(feedback_json_bool "${has_agents_md}")" \
    --argjson has_architecture_doc "$(feedback_json_bool "${has_architecture_doc}")" \
    --argjson has_diagrams "$(feedback_json_bool "${has_diagrams}")" \
    --argjson risk_flags "${risk_flags_json}" \
    '{
      schema_version: ($schema_version | tonumber),
      project_name: $project_name,
      repo_path: $repo_path,
      generated_at: $generated_at,
      git: {
        present: $git_present,
        commit_count: $commit_count,
        has_remote: $has_remote,
        default_branch: $default_branch,
        dirty_worktree: $dirty_worktree
      },
      tech: {
        languages: $languages,
        frameworks: $frameworks,
        package_managers: $package_managers,
        repo_kind: $repo_kind
      },
      ops: {
        state_profile: $state_profile,
        runtime_traits: $runtime_traits
      },
      docs: {
        has_agents_md: $has_agents_md,
        has_architecture_doc: $has_architecture_doc,
        has_diagrams: $has_diagrams
      },
      risk_flags: $risk_flags
    }'
}

feedback_write_project_profile() {
  local repo_path="$1"
  local project_name
  local profile_path

  project_name="$(feedback_project_name_from_path "${repo_path}")"
  profile_path="$(feedback_profile_output_path "${project_name}")"
  feedback_mkdir_if_missing "$(dirname "${profile_path}")"
  feedback_project_profile_json "${repo_path}" > "${profile_path}"
  printf '%s\n' "${profile_path}"
}

feedback_project_profile_terms() {
  local profile_json="$1"

  jq -r '
    [
      .tech.languages[],
      .tech.frameworks[],
      .tech.package_managers[],
      .tech.repo_kind,
      .ops.state_profile,
      .ops.runtime_traits[],
      .risk_flags[]
    ]
    | map(select(length > 0))
    | .[]
  ' "${profile_json}" | feedback_unique_sorted_lines
}
