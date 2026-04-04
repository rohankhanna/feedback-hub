#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/project_context.sh"

usage() {
  cat <<'USAGE'
Usage:
  learnings search "<query>" [project_repo_path] [--facet key=value] [--limit N] [--json]
USAGE
}

build_facet_sql() {
  local facet_sql=""
  local facet_filter
  local facet_key
  local facet_value

  for facet_filter in "${FACET_FILTERS[@]}"; do
    facet_key="${facet_filter%%=*}"
    facet_value="${facet_filter#*=}"
    if [ -z "${facet_key}" ] || [ "${facet_key}" = "${facet_value}" ]; then
      echo "Error: invalid facet filter '${facet_filter}'. Expected key=value." >&2
      exit 1
    fi
    facet_sql="${facet_sql} AND EXISTS (SELECT 1 FROM learning_facets lf WHERE lf.learning_id = e.id AND lf.facet_key = '$(feedback_escape_sql "${facet_key}")' AND lf.facet_value = '$(feedback_escape_sql "${facet_value}")')"
  done

  printf '%s\n' "${facet_sql}"
}

normalized_query_terms() {
  local query="$1"
  local normalized
  local token

  normalized="$(printf '%s' "${query}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/ /g')"
  for token in ${normalized}; do
    [ "${#token}" -lt 2 ] && continue
    printf '%s\n' "${token}"
  done | awk 'NF' | feedback_unique_sorted_lines
}

expand_query_terms() {
  local query="$1"
  local token

  while IFS= read -r token; do
    [ -z "${token}" ] && continue
    printf '%s\n' "${token}"
    case "${token}" in
      state|states)
        printf '%s\n' persist persistence persistent checkpoint checkpoints resumable resume durable storage
        ;;
      persist|persistent|persistence)
        printf '%s\n' state checkpoint checkpoints resume resumable durable storage
        ;;
      shutdown|restart|reboot)
        printf '%s\n' shutdown restart reboot restore recovery resume
        ;;
      architecture|design|adr)
        printf '%s\n' architecture design adr adapter boundary boundaries
        ;;
      docs|doc|documentation|diagram|diagrams)
        printf '%s\n' docs documentation diagram diagrams architecture
        ;;
      incident|outage|regression|failure|failures)
        printf '%s\n' incident outage regression root cause debugging bug bugs
        ;;
      migration|migrate|rollback|compatibility)
        printf '%s\n' migration migrate rollback compatibility backward forward
        ;;
      git|repo|repository|repositories|commit|commits)
        printf '%s\n' git repository repositories version control commit commits
        ;;
      healthcheck|healthchecks|liveness|readiness|verify|verification)
        printf '%s\n' healthcheck healthchecks liveness readiness verify verification inference probe probes
        ;;
      inference|serving|serve|backend)
        printf '%s\n' inference serving serve backend healthcheck verification model models
        ;;
    esac
  done < <(normalized_query_terms "${query}") | awk 'NF' | feedback_unique_sorted_lines
}

build_exact_match_query() {
  local query="$1"
  local terms=()
  local term

  while IFS= read -r term; do
    [ -z "${term}" ] && continue
    terms+=("\"${term}\"")
  done < <(normalized_query_terms "${query}")

  if [ "${#terms[@]}" -eq 0 ]; then
    printf '\n'
    return 0
  fi

  local joined=""
  local item
  for item in "${terms[@]}"; do
    if [ -n "${joined}" ]; then
      joined="${joined} AND "
    fi
    joined="${joined}${item}"
  done

  printf '%s\n' "${joined}"
}

build_expanded_match_query() {
  local query="$1"
  local terms=()
  local term

  while IFS= read -r term; do
    [ -z "${term}" ] && continue
    terms+=("\"${term}\"")
    if [ "${#term}" -ge 4 ]; then
      terms+=("\"${term}\"*")
    fi
  done < <(expand_query_terms "${query}")

  if [ "${#terms[@]}" -eq 0 ]; then
    printf '%s\n' "${query}"
    return 0
  fi

  local joined=""
  local item
  for item in "${terms[@]}"; do
    if [ -n "${joined}" ]; then
      joined="${joined} OR "
    fi
    joined="${joined}${item}"
  done

  printf '%s\n' "${joined}"
}

run_fts_query() {
  local match_query="$1"
  local out_file="$2"
  local facet_sql="$3"

  sqlite3 -separator "${DB_SEPARATOR}" "${DB_PATH:-$(feedback_learnings_db_path)}" <<SQL > "${out_file}"
SELECT
  e.id,
  e.title,
  e.path,
  e.type,
  IFNULL(e.summary, ''),
  bm25(learning_fts, 10.0, 5.0, 1.0, 2.0, 1.0),
  IFNULL((SELECT group_concat(tag, ' ') FROM learning_tags WHERE learning_id = e.id), ''),
  IFNULL((SELECT group_concat(facet_key || ':' || facet_value, ' ') FROM learning_facets WHERE learning_id = e.id), '')
FROM learning_fts
JOIN learning_entities e ON e.id = learning_fts.id
WHERE learning_fts MATCH '$(feedback_escape_sql "${match_query}")'
  AND e.status = 'active'
  ${facet_sql}
ORDER BY bm25(learning_fts, 10.0, 5.0, 1.0, 2.0, 1.0) ASC
LIMIT 50;
SQL
}

score_results_file() {
  local input_file="$1"
  local output_file="$2"

  : > "${output_file}"
  while IFS="${DB_SEPARATOR}" read -r id title path type summary rank tags_text facets_text; do
    [ -z "${id}" ] && continue
    profile_boost="0"
    reasons=()

    if [ -n "${PROJECT_REPO_PATH}" ]; then
      text_blob="$(printf '%s %s %s' "${tags_text}" "${facets_text}" "${title}" | tr '[:upper:]' '[:lower:]')"
      matched_terms=()
      for term in "${!PROFILE_TERMS[@]}"; do
        if printf '%s\n' "${text_blob}" | grep -Fqi "${term}"; then
          matched_terms+=("${term}")
        fi
      done
      if [ "${#matched_terms[@]}" -gt 0 ]; then
        profile_boost="$(awk -v count="${#matched_terms[@]}" 'BEGIN { v = count * 0.05; if (v > 0.25) v = 0.25; printf "%.6f", v }')"
        reasons+=("profile_overlap:${matched_terms[*]}")
      fi
    fi

    base_score="$(awk -v rank="${rank}" 'BEGIN { if (rank < 0) rank = -rank; printf "%.6f", 1 / (1 + rank) }')"
    final_score="$(awk -v base="${base_score}" -v boost="${profile_boost}" 'BEGIN { printf "%.6f", base + boost }')"
    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
      "${final_score}" "${OUT_SEPARATOR}" "${id}" "${OUT_SEPARATOR}" "${title}" "${OUT_SEPARATOR}" \
      "${path}" "${OUT_SEPARATOR}" "${type}" "${OUT_SEPARATOR}" "${summary}" "${OUT_SEPARATOR}" \
      "${tags_text}" "${OUT_SEPARATOR}" "${facets_text}" "${OUT_SEPARATOR}" "${reasons[*]:-}" >> "${output_file}"
  done < "${input_file}"
}

QUERY=""
PROJECT_REPO_PATH=""
LIMIT=10
JSON_OUTPUT="false"
declare -a FACET_FILTERS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --facet)
      FACET_FILTERS+=("${2:-}")
      shift 2
      ;;
    --limit)
      LIMIT="${2:-10}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      if [ -z "${QUERY}" ]; then
        QUERY="$1"
      elif [ -z "${PROJECT_REPO_PATH}" ]; then
        PROJECT_REPO_PATH="$1"
      else
        echo "Error: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "${QUERY}" ]; then
  echo "Error: query is required." >&2
  usage >&2
  exit 1
fi

feedback_require_positive_integer "${LIMIT}" "limit" || exit 1

if ! feedback_learnings_require_db >/dev/null 2>&1; then
  "${SCRIPT_DIR}/learnings_index.sh" --quiet >/dev/null
fi

PROFILE_PATH=""
USAGE_PROJECT_PATH=""
USAGE_PROJECT_NAME=""
declare -A PROFILE_TERMS=()
if [ -n "${PROJECT_REPO_PATH}" ]; then
  PROJECT_REPO_PATH="$(feedback_resolve_project_path "${PROJECT_REPO_PATH}")"
  PROFILE_PATH="$(feedback_write_project_profile "${PROJECT_REPO_PATH}")"
  USAGE_PROJECT_PATH="${PROJECT_REPO_PATH}"
  USAGE_PROJECT_NAME="$(feedback_project_name_from_path "${PROJECT_REPO_PATH}")"
  while IFS= read -r term; do
    [ -z "${term}" ] && continue
    PROFILE_TERMS["${term}"]=1
  done < <(feedback_project_profile_terms "${PROFILE_PATH}")
else
  USAGE_PROJECT_PATH="$(feedback_infer_usage_project_path "$(pwd)" 2>/dev/null || true)"
  if [ -n "${USAGE_PROJECT_PATH}" ]; then
    USAGE_PROJECT_NAME="$(feedback_project_name_from_path "${USAGE_PROJECT_PATH}")"
  fi
fi

FACET_SQL="$(build_facet_sql)"
TMP_RESULTS="$(mktemp)"
DB_SEPARATOR=$'\x1f'
OUT_SEPARATOR=$'\x1e'
SEARCH_STRATEGY="fts_exact"
EXACT_MATCH_QUERY=""
EXPANDED_QUERY=""
FALLBACK_USED="false"
FALLBACK_REASON=""
RECOMMEND_RESULTS_FILE=""

EXACT_MATCH_QUERY="$(build_exact_match_query "${QUERY}")"
if [ -n "${EXACT_MATCH_QUERY}" ]; then
  if ! run_fts_query "${EXACT_MATCH_QUERY}" "${TMP_RESULTS}" "${FACET_SQL}" 2>/dev/null; then
    : > "${TMP_RESULTS}"
  fi
else
  : > "${TMP_RESULTS}"
fi

if [ ! -s "${TMP_RESULTS}" ]; then
  SEARCH_STRATEGY="fts_expanded"
  EXPANDED_QUERY="$(build_expanded_match_query "${QUERY}")"
  if ! run_fts_query "${EXPANDED_QUERY}" "${TMP_RESULTS}" "${FACET_SQL}" 2>/dev/null; then
    : > "${TMP_RESULTS}"
  fi
fi

SCORED_RESULTS="$(mktemp)"
score_results_file "${TMP_RESULTS}" "${SCORED_RESULTS}"

SORTED_RESULTS="$(mktemp)"
sort -t "${OUT_SEPARATOR}" -k1,1gr "${SCORED_RESULTS}" | sed -n "1,${LIMIT}p" > "${SORTED_RESULTS}"

RESULT_COUNT="$(wc -l < "${SORTED_RESULTS}" | tr -d '[:space:]')"
if [ "${RESULT_COUNT}" -eq 0 ]; then
  SEARCH_STRATEGY="recommend_fallback"
  FALLBACK_USED="true"
  FALLBACK_REASON="No direct lexical hits were found; returning profile-based recommendations."
  RECOMMEND_PROJECT_PATH="${PROJECT_REPO_PATH:-${USAGE_PROJECT_PATH:-$(pwd)}}"
  RECOMMEND_JSON="$(FEEDBACK_SUPPRESS_USAGE_LOG=true "${SCRIPT_DIR}/learnings_recommend.sh" "${RECOMMEND_PROJECT_PATH}" --limit "${LIMIT}" --json)"
  RECOMMEND_RESULTS_FILE="$(mktemp)"
  printf '%s\n' "${RECOMMEND_JSON}" | jq -r '
    .results[]
    | [
        (.score | tostring),
        .id,
        .title,
        .source,
        .type,
        .summary,
        (.why | join(" "))
      ]
    | @tsv
  ' | tr '\t' "${OUT_SEPARATOR}" > "${RECOMMEND_RESULTS_FILE}"
  RESULT_COUNT="$(wc -l < "${RECOMMEND_RESULTS_FILE}" | tr -d '[:space:]')"
fi

if [ -n "${USAGE_PROJECT_NAME}" ]; then
  SEARCH_METADATA="$(jq -nc \
    --argjson limit "${LIMIT}" \
    --argjson result_count "${RESULT_COUNT:-0}" \
    --arg strategy "${SEARCH_STRATEGY}" \
    --arg expanded_query "${EXPANDED_QUERY}" \
    --argjson fallback_used "$(feedback_json_bool "${FALLBACK_USED}")" \
    --argjson facet_filters "$(printf '%s\n' "${FACET_FILTERS[@]}" | awk 'NF' | feedback_json_array_from_lines)" \
    '{limit: $limit, result_count: $result_count, strategy: $strategy, expanded_query: $expanded_query, fallback_used: $fallback_used, facet_filters: $facet_filters}')"
  feedback_learnings_record_usage_event "${USAGE_PROJECT_NAME}" "learnings search" "search" "" "${QUERY}" "${SEARCH_METADATA}"
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  if [ "${FALLBACK_USED}" = "true" ]; then
    jq -Rn \
      --arg query "${QUERY}" \
      --arg project_repo_path "${PROJECT_REPO_PATH}" \
      --arg strategy "${SEARCH_STRATEGY}" \
      --arg expanded_query "${EXPANDED_QUERY}" \
      --arg fallback_reason "${FALLBACK_REASON}" \
      --arg sep "${OUT_SEPARATOR}" '
      [
        inputs
        | select(length > 0)
        | split($sep)
        | {
            score: (.[0] | tonumber),
            id: .[1],
            title: .[2],
            path: .[3],
            type: .[4],
            summary: .[5],
            why: (.[6] | if length == 0 then [] else split(" ") end),
            result_source: "recommend_fallback"
          }
      ]
      | {
          query: $query,
          project_repo_path: $project_repo_path,
          strategy: $strategy,
          expanded_query: $expanded_query,
          fallback_used: true,
          fallback_reason: $fallback_reason,
          results: .
        }
    ' < "${RECOMMEND_RESULTS_FILE}"
  else
    jq -Rn --arg query "${QUERY}" --arg project_repo_path "${PROJECT_REPO_PATH}" --arg strategy "${SEARCH_STRATEGY}" --arg expanded_query "${EXPANDED_QUERY}" --arg sep "${OUT_SEPARATOR}" '
    [
      inputs
      | select(length > 0)
      | split($sep)
      | {
          score: (.[0] | tonumber),
          id: .[1],
          title: .[2],
          path: .[3],
          type: .[4],
          summary: .[5],
          tags_text: .[6],
          facets_text: .[7],
          why: (.[8] | if length == 0 then [] else split(" ") end),
          result_source: $strategy
        }
    ]
    | {
        query: $query,
        project_repo_path: $project_repo_path,
        strategy: $strategy,
        expanded_query: $expanded_query,
        fallback_used: false,
        results: .
      }
    ' < "${SORTED_RESULTS}"
  fi
else
  echo "Search query: ${QUERY}"
  if [ -n "${PROJECT_REPO_PATH}" ]; then
    echo "Project context: ${PROJECT_REPO_PATH}"
  fi
  if [ -n "${EXPANDED_QUERY}" ] && [ "${SEARCH_STRATEGY}" = "fts_expanded" ]; then
    echo "Search strategy: expanded lexical fallback"
  fi
  if [ "${FALLBACK_USED}" = "true" ]; then
    echo "${FALLBACK_REASON}"
    while IFS="${OUT_SEPARATOR}" read -r score id title path type summary reasons; do
      [ -z "${id}" ] && continue
      echo
      echo "[${score}] ${title} (${id})"
      echo "Type: ${type}"
      echo "Source: ${path}"
      [ -n "${summary}" ] && echo "Summary: ${summary}"
      [ -n "${reasons}" ] && echo "Why: ${reasons}"
    done < "${RECOMMEND_RESULTS_FILE}"
  else
    while IFS="${OUT_SEPARATOR}" read -r score id title path type summary _tags_text _facets_text reasons; do
      [ -z "${id}" ] && continue
      echo
      echo "[${score}] ${title} (${id})"
      echo "Type: ${type}"
      echo "Path: ${path}"
      [ -n "${summary}" ] && echo "Summary: ${summary}"
      [ -n "${reasons}" ] && echo "Why: ${reasons}"
    done < "${SORTED_RESULTS}"
  fi
fi

rm -f "${TMP_RESULTS}" "${SCORED_RESULTS}" "${SORTED_RESULTS}" "${RECOMMEND_RESULTS_FILE:-}"
