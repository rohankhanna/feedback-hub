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
  learnings recommend [project_repo_path] [--limit N] [--json]
USAGE
}

PROJECT_REPO_PATH="$(pwd)"
LIMIT=10
JSON_OUTPUT="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
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
feedback_require_positive_integer "${LIMIT}" "limit" || exit 1
PROFILE_PATH="$(feedback_write_project_profile "${PROJECT_REPO_PATH}")"
PROJECT_NAME="$(jq -r '.project_name' "${PROFILE_PATH}")"

if ! feedback_learnings_require_db >/dev/null 2>&1; then
  "${SCRIPT_DIR}/learnings_index.sh" --quiet >/dev/null
fi

declare -A PROFILE_TERMS=()
declare -A RISK_FLAGS=()
while IFS= read -r term; do
  [ -z "${term}" ] && continue
  PROFILE_TERMS["${term}"]=1
done < <(feedback_project_profile_terms "${PROFILE_PATH}")

while IFS= read -r risk_flag; do
  [ -z "${risk_flag}" ] && continue
  RISK_FLAGS["${risk_flag}"]=1
done < <(jq -r '.risk_flags[]?' "${PROFILE_PATH}")

RAW_RESULTS="$(mktemp)"
DB_SEPARATOR=$'\x1f'
OUT_SEPARATOR=$'\x1e'
sqlite3 -separator "${DB_SEPARATOR}" "$(feedback_learnings_db_path)" <<'SQL' > "${RAW_RESULTS}"
SELECT
  e.id,
  e.title,
  e.path,
  e.type,
  IFNULL(e.summary, ''),
  IFNULL(e.updated_at, ''),
  IFNULL(e.last_validated_at, ''),
  IFNULL(e.evidence_strength, 0),
  IFNULL(e.adoption_cost, ''),
  IFNULL((SELECT group_concat(tag, ' ') FROM learning_tags WHERE learning_id = e.id), ''),
  IFNULL((SELECT group_concat(facet_key || ':' || facet_value, ' ') FROM learning_facets WHERE learning_id = e.id), ''),
  IFNULL(e.source_project, ''),
  IFNULL(e.source_artifact, '')
FROM learning_entities e
WHERE e.status = 'active'
ORDER BY e.type, e.updated_at DESC;
SQL

SCORED_RESULTS="$(mktemp)"

while IFS="${DB_SEPARATOR}" read -r id title path type summary updated_at last_validated_at evidence_strength adoption_cost tags_text facets_text source_project source_artifact; do
  [ -z "${id}" ] && continue

  text_blob="$(printf '%s %s %s %s' "${title}" "${summary}" "${tags_text}" "${facets_text}" | tr '[:upper:]' '[:lower:]')"
  matched_terms=()
  matched_facets=()

  for term in "${!PROFILE_TERMS[@]}"; do
    if printf '%s\n' "${text_blob}" | grep -Fqi "${term}"; then
      matched_terms+=("${term}")
    fi
    if printf '%s\n' "${facets_text}" | grep -Fqi "${term}"; then
      matched_facets+=("${term}")
    fi
  done

  lexical_score="$(awk -v count="${#matched_terms[@]}" 'BEGIN { v = count / 5.0; if (v > 1) v = 1; printf "%.6f", v }')"
  facet_score="$(awk -v count="${#matched_facets[@]}" 'BEGIN { v = count / 4.0; if (v > 1) v = 1; printf "%.6f", v }')"

  freshness_reference="${last_validated_at:-${updated_at}}"
  if [ -z "${freshness_reference}" ]; then
    freshness_score="0.50"
  else
    ref_epoch="$(date -u -d "${freshness_reference}" +%s 2>/dev/null || printf '0\n')"
    now_epoch="$(date -u +%s)"
    if [ "${ref_epoch}" -le 0 ]; then
      freshness_score="0.50"
    else
      age_days="$(( (now_epoch - ref_epoch) / 86400 ))"
      if [ "${age_days}" -le 30 ]; then
        freshness_score="1.000000"
      elif [ "${age_days}" -le 180 ]; then
        freshness_score="0.800000"
      elif [ "${age_days}" -le 365 ]; then
        freshness_score="0.600000"
      else
        freshness_score="0.400000"
      fi
    fi
  fi

  evidence_score="$(awk -v value="${evidence_strength}" 'BEGIN { if (value < 0) value = 0; if (value > 1) value = 1; printf "%.6f", value }')"
  risk_boost="0.000000"
  risk_reasons=()

  if { [ -n "${RISK_FLAGS[no_git]:-}" ] || [ -n "${RISK_FLAGS[no_commits]:-}" ] || [ -n "${RISK_FLAGS[no_remote]:-}" ]; } \
    && printf '%s\n' "${text_blob}" | grep -Eq 'version-control|git|repository'; then
    risk_boost="$(awk 'BEGIN { printf "%.6f", 0.30 }')"
    risk_reasons+=("bootstrap_git_hygiene")
  fi

  if { [ -n "${RISK_FLAGS[no_architecture_doc]:-}" ] || [ -n "${RISK_FLAGS[no_diagrams]:-}" ]; } \
    && printf '%s\n' "${text_blob}" | grep -Eq 'architecture|documentation|diagram'; then
    risk_boost="$(awk -v current="${risk_boost}" 'BEGIN { v = current + 0.20; if (v > 0.35) v = 0.35; printf "%.6f", v }')"
    risk_reasons+=("architecture_docs_gap")
  fi

  final_score="$(awk \
    -v facet="${facet_score}" \
    -v lexical="${lexical_score}" \
    -v freshness="${freshness_score}" \
    -v evidence="${evidence_score}" \
    -v boost="${risk_boost}" \
    'BEGIN { printf "%.6f", (0.40 * facet) + (0.35 * lexical) + (0.15 * freshness) + (0.10 * evidence) + boost }')"

  confidence="low"
  awk -v score="${final_score}" 'BEGIN { exit !(score >= 0.75) }' && confidence="high" || true
  if [ "${confidence}" = "low" ]; then
    awk -v score="${final_score}" 'BEGIN { exit !(score >= 0.45) }' && confidence="medium" || true
  fi

  action="Review this learning"
  case "${type}" in
    patterns) action="Consider adopting this pattern" ;;
    anti-patterns) action="Avoid this anti-pattern" ;;
    templates) action="Reuse this template" ;;
    agents) action="Review this agent guidance" ;;
  esac

  reasons=()
  [ "${#matched_facets[@]}" -gt 0 ] && reasons+=("facet_match:${matched_facets[*]}")
  [ "${#matched_terms[@]}" -gt 0 ] && reasons+=("lexical_match:${matched_terms[*]}")
  [ -n "${last_validated_at}" ] && reasons+=("validated:${last_validated_at}")
  [ "${#risk_reasons[@]}" -gt 0 ] && reasons+=("${risk_reasons[*]}")
  [ -n "${source_project}" ] && reasons+=("source_project:${source_project}")

  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "${final_score}" "${OUT_SEPARATOR}" "${id}" "${OUT_SEPARATOR}" "${title}" "${OUT_SEPARATOR}" \
    "${path}" "${OUT_SEPARATOR}" "${type}" "${OUT_SEPARATOR}" "${summary}" "${OUT_SEPARATOR}" \
    "${confidence}" "${OUT_SEPARATOR}" "${action}" "${OUT_SEPARATOR}" "${adoption_cost}" "${OUT_SEPARATOR}" \
    "${source_project}" "${OUT_SEPARATOR}" "${source_artifact}" "${OUT_SEPARATOR}" "${reasons[*]:-}" "${OUT_SEPARATOR}" \
    "${matched_terms[*]:-}" "${OUT_SEPARATOR}" "${matched_facets[*]:-}" >> "${SCORED_RESULTS}"
done < "${RAW_RESULTS}"

SORTED_RESULTS="$(mktemp)"
sort -t "${OUT_SEPARATOR}" -k1,1gr "${SCORED_RESULTS}" > "${SORTED_RESULTS}.all"

declare -A TYPE_COUNTS=()
SELECTED_RESULTS="$(mktemp)"
while IFS="${OUT_SEPARATOR}" read -r score id title path type summary confidence action adoption_cost source_project source_artifact reasons matched_terms matched_facets; do
  [ -z "${id}" ] && continue
  type_count="${TYPE_COUNTS["${type}"]:-0}"
  if [ "${type_count}" -ge 2 ]; then
    continue
  fi
  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
    "${score}" "${OUT_SEPARATOR}" "${id}" "${OUT_SEPARATOR}" "${title}" "${OUT_SEPARATOR}" \
    "${path}" "${OUT_SEPARATOR}" "${type}" "${OUT_SEPARATOR}" "${summary}" "${OUT_SEPARATOR}" \
    "${confidence}" "${OUT_SEPARATOR}" "${action}" "${OUT_SEPARATOR}" "${adoption_cost}" "${OUT_SEPARATOR}" \
    "${source_project}" "${OUT_SEPARATOR}" "${source_artifact}" "${OUT_SEPARATOR}" "${reasons}" >> "${SELECTED_RESULTS}"
  TYPE_COUNTS["${type}"]=$((type_count + 1))
  if [ "$(wc -l < "${SELECTED_RESULTS}")" -ge "${LIMIT}" ]; then
    break
  fi
done < "${SORTED_RESULTS}.all"

RESULT_COUNT="$(wc -l < "${SELECTED_RESULTS}" | tr -d '[:space:]')"
RECOMMEND_METADATA="$(jq -nc \
  --argjson limit "${LIMIT}" \
  --argjson result_count "${RESULT_COUNT:-0}" \
  '{limit: $limit, result_count: $result_count}')"
if [ "${FEEDBACK_SUPPRESS_USAGE_LOG:-false}" != "true" ]; then
  feedback_learnings_record_usage_event "${PROJECT_NAME}" "learnings recommend" "recommend" "" "" "${RECOMMEND_METADATA}"
fi

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -Rn \
    --arg project "${PROJECT_NAME}" \
    --slurpfile profile "${PROFILE_PATH}" \
    --arg sep "${OUT_SEPARATOR}" '
    [
      inputs
      | select(length > 0)
      | split($sep)
      | {
          score: (.[0] | tonumber),
          id: .[1],
          title: .[2],
          source: .[3],
          type: .[4],
          summary: .[5],
          confidence: .[6],
          action: .[7],
          adoption_cost: .[8],
          source_project: .[9],
          source_artifact: .[10],
          why: (.[11] | if length == 0 then [] else split(" ") end)
        }
    ]
    | {
        project: $project,
        profile: $profile[0],
        results: .
      }
  ' < "${SELECTED_RESULTS}"
else
  echo "Recommendations for: ${PROJECT_REPO_PATH}"
  while IFS="${OUT_SEPARATOR}" read -r score id title path type summary confidence action adoption_cost source_project source_artifact reasons; do
    [ -z "${id}" ] && continue
    echo
    echo "[${score}] ${title} (${id})"
    echo "Type: ${type}"
    echo "Confidence: ${confidence}"
    echo "Action: ${action}"
    echo "Adoption cost: ${adoption_cost}"
    echo "Source: ${path}"
    [ -n "${source_project}" ] && echo "Promoted from: ${source_project}"
    [ -n "${summary}" ] && echo "Summary: ${summary}"
    [ -n "${reasons}" ] && echo "Why: ${reasons}"
  done < "${SELECTED_RESULTS}"
fi

rm -f "${RAW_RESULTS}" "${SCORED_RESULTS}" "${SORTED_RESULTS}.all" "${SELECTED_RESULTS}"
