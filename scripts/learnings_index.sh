#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/learnings_store.sh"

usage() {
  cat <<'USAGE'
Usage:
  learnings index [--full] [--json] [--quiet]
USAGE
}

FULL_REBUILD="false"
JSON_OUTPUT="false"
QUIET="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --full)
      FULL_REBUILD="true"
      shift
      ;;
    --json)
      JSON_OUTPUT="true"
      shift
      ;;
    --quiet)
      QUIET="true"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

feedback_learnings_ensure_db
DB_PATH="$(feedback_learnings_db_path)"
RUN_ID="index_$(feedback_stamp_utc)"
RUN_STARTED_AT="$(feedback_timestamp_utc)"
LOCK_DIR="$(feedback_learnings_state_dir)/.index.lock"

mkdir -p "$(feedback_learnings_state_dir)"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "learnings index is already running; skipping this run." >&2
  exit 0
fi

cleanup() {
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

sqlite3 "${DB_PATH}" <<SQL
INSERT INTO index_runs(id, mode, started_at, status, indexed_count)
VALUES ('$(feedback_escape_sql "${RUN_ID}")', '$( [ "${FULL_REBUILD}" = "true" ] && printf full || printf incremental )', '$(feedback_escape_sql "${RUN_STARTED_AT}")', 'running', 0);
SQL

declare -A PROMO_SOURCE_PROJECT=()
declare -A PROMO_SOURCE_ARTIFACT=()
declare -A LAST_VALIDATED_AT=()
declare -A SUPERSEDED_BY=()

PROMOTION_LOG="$(feedback_learnings_promotion_log_path)"
VALIDATION_LOG="$(feedback_learnings_validation_log_path)"
SUPERSESSION_LOG="$(feedback_learnings_supersession_log_path)"

if [ -f "${PROMOTION_LOG}" ]; then
  while IFS=$'\t' read -r _ts _action project source_artifact target_rel; do
    [ -z "${target_rel}" ] && continue
    PROMO_SOURCE_PROJECT["${target_rel}"]="${project}"
    PROMO_SOURCE_ARTIFACT["${target_rel}"]="${source_artifact}"
  done < "${PROMOTION_LOG}"
fi

if [ -f "${VALIDATION_LOG}" ]; then
  while IFS=$'\t' read -r ts learning_id _note; do
    [ -z "${learning_id}" ] && continue
    LAST_VALIDATED_AT["${learning_id}"]="${ts}"
  done < "${VALIDATION_LOG}"
fi

if [ -f "${SUPERSESSION_LOG}" ]; then
  while IFS=$'\t' read -r _ts old_id new_id; do
    if [ -z "${old_id}" ] || [ -z "${new_id}" ]; then
      continue
    fi
    SUPERSEDED_BY["${old_id}"]="${new_id}"
  done < "${SUPERSESSION_LOG}"
fi

SQL_FILE="$(mktemp)"
{
  printf 'BEGIN;\n'
  printf 'DELETE FROM learning_entities;\n'
  printf 'DELETE FROM learning_tags;\n'
  printf 'DELETE FROM learning_facets;\n'
  printf 'DELETE FROM learning_links;\n'
  printf 'DELETE FROM learning_fts;\n'
  printf 'DELETE FROM interactions;\n'
  printf 'DELETE FROM usage_events;\n'
} > "${SQL_FILE}"

INDEXED_COUNT=0

while IFS= read -r file_path; do
  [ -z "${file_path}" ] && continue

  rel_path="${file_path#${FEEDBACK_REPO_ROOT}/}"
  learning_type="$(printf '%s' "${rel_path}" | cut -d'/' -f2)"
  IFS=$'\t' read -r learning_id summary evidence_strength adoption_cost <<< "$(feedback_extract_frontmatter_fields_tsv "${file_path}" id summary evidence_strength adoption_cost)"
  learning_id="$(feedback_trim "${learning_id}")"
  [ -z "${learning_id}" ] && learning_id="$(feedback_learnings_entity_id_from_relpath "${rel_path}")"
  title="$(feedback_markdown_title "${file_path}")"
  summary="$(feedback_trim "${summary}")"
  [ -z "${summary}" ] && summary="$(feedback_markdown_summary "${file_path}")"
  body="$(cat "${file_path}")"
  file_hash="$(feedback_sha256_file "${file_path}")"
  updated_at="$(feedback_file_mtime_utc "${file_path}")"
  created_at="${updated_at}"
  evidence_strength="$(feedback_trim "${evidence_strength}")"
  [ -z "${evidence_strength}" ] && evidence_strength="$(feedback_learnings_default_evidence_strength "${learning_type}")"
  evidence_strength="$(feedback_sql_real_or_default "${evidence_strength}" "$(feedback_learnings_default_evidence_strength "${learning_type}")")"
  adoption_cost="$(feedback_trim "${adoption_cost}")"
  [ -z "${adoption_cost}" ] && adoption_cost="$(feedback_learnings_default_adoption_cost "${learning_type}")"
  source_project="${PROMO_SOURCE_PROJECT["${rel_path}"]:-}"
  source_artifact="${PROMO_SOURCE_ARTIFACT["${rel_path}"]:-}"
  superseded_by="${SUPERSEDED_BY["${learning_id}"]:-}"
  last_validated_at="${LAST_VALIDATED_AT["${learning_id}"]:-}"
  status="active"
  [ -n "${superseded_by}" ] && status="superseded"

  text_blob="$(feedback_learnings_text_blob "${file_path}")"
  facets_tsv="$(feedback_learnings_detect_facets "${file_path}" "${learning_type}" "${text_blob}")"
  tags_lines="$(feedback_learnings_detect_tags "${file_path}" "${learning_type}" "${rel_path}" "${facets_tsv}" "${text_blob}")"
  tags_text="$(printf '%s\n' "${tags_lines}" | paste -sd' ' -)"
  facets_text="$(printf '%s\n' "${facets_tsv}" | awk -F '\t' 'NF == 2 { print $1 ":" $2 }' | paste -sd' ' -)"

  cat >> "${SQL_FILE}" <<SQL
INSERT INTO learning_entities(
  id, path, type, title, summary, body, source_project, source_artifact,
  status, superseded_by, evidence_strength, adoption_cost, created_at, updated_at, last_validated_at, file_hash
) VALUES (
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${rel_path}")',
  '$(feedback_escape_sql "${learning_type}")',
  '$(feedback_escape_sql "${title}")',
  '$(feedback_escape_sql "${summary}")',
  '$(feedback_escape_sql "${body}")',
  '$(feedback_escape_sql "${source_project}")',
  '$(feedback_escape_sql "${source_artifact}")',
  '$(feedback_escape_sql "${status}")',
  '$(feedback_escape_sql "${superseded_by}")',
  $(feedback_escape_sql "${evidence_strength}"),
  '$(feedback_escape_sql "${adoption_cost}")',
  '$(feedback_escape_sql "${created_at}")',
  '$(feedback_escape_sql "${updated_at}")',
  '$(feedback_escape_sql "${last_validated_at}")',
  '$(feedback_escape_sql "${file_hash}")'
);
INSERT INTO learning_fts(id, title, summary, body, tags_text, facets_text)
VALUES (
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${title}")',
  '$(feedback_escape_sql "${summary}")',
  '$(feedback_escape_sql "${body}")',
  '$(feedback_escape_sql "${tags_text}")',
  '$(feedback_escape_sql "${facets_text}")'
);
SQL

  while IFS=$'\t' read -r facet_key facet_value; do
    if [ -z "${facet_key}" ] || [ -z "${facet_value}" ]; then
      continue
    fi
    cat >> "${SQL_FILE}" <<SQL
INSERT INTO learning_facets(learning_id, facet_key, facet_value)
VALUES (
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${facet_key}")',
  '$(feedback_escape_sql "${facet_value}")'
);
SQL
  done <<< "${facets_tsv}"

  while IFS= read -r tag; do
    [ -z "${tag}" ] && continue
    cat >> "${SQL_FILE}" <<SQL
INSERT INTO learning_tags(learning_id, tag)
VALUES (
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${tag}")'
);
SQL
  done <<< "${tags_lines}"

  if [ -n "${superseded_by}" ]; then
    cat >> "${SQL_FILE}" <<SQL
INSERT INTO learning_links(from_learning_id, to_learning_id, relation_type)
VALUES (
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${superseded_by}")',
  'superseded_by'
);
SQL
  fi

  INDEXED_COUNT=$((INDEXED_COUNT + 1))
done < <(find "$(feedback_learnings_dir)" -mindepth 2 -maxdepth 3 -type f -name '*.md' | sort)

while IFS= read -r interaction_file; do
  [ -z "${interaction_file}" ] && continue
  IFS=$'\t' read -r interaction_kind learning_id project_name recorded_at note interaction_id <<< "$(feedback_extract_frontmatter_fields_tsv "${interaction_file}" interaction_action learning_id project recorded_at note interaction_id)"
  interaction_kind="$(feedback_trim "${interaction_kind}")"
  learning_id="$(feedback_trim "${learning_id}")"
  project_name="$(feedback_trim "${project_name}")"
  recorded_at="$(feedback_trim "${recorded_at}")"
  note="$(feedback_trim "${note}")"
  interaction_id="$(feedback_trim "${interaction_id}")"

  [ -z "${interaction_kind}" ] && continue
  [ -z "${learning_id}" ] && continue
  [ -z "${project_name}" ] && continue
  [ -z "${recorded_at}" ] && recorded_at="$(feedback_file_mtime_utc "${interaction_file}")"
  [ -z "${interaction_id}" ] && interaction_id="interaction_$(feedback_slugify "${project_name}-${interaction_kind}-${learning_id}-$(basename "${interaction_file}")")"

  cat >> "${SQL_FILE}" <<SQL
INSERT INTO interactions(id, project_name, learning_id, action, note, created_at)
VALUES (
  '$(feedback_escape_sql "${interaction_id}")',
  '$(feedback_escape_sql "${project_name}")',
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${interaction_kind}")',
  '$(feedback_escape_sql "${note}")',
  '$(feedback_escape_sql "${recorded_at}")'
);
SQL
done < <(find "${FEEDBACK_REPO_ROOT}/projects" -type f -path '*/feedback/incoming/*.md' | sort)

while IFS= read -r usage_file; do
  [ -z "${usage_file}" ] && continue
  while IFS=$'\t' read -r event_id project_name command_name event_type learning_id query_text recorded_at metadata_json; do
    [ -z "${event_id}" ] && continue

    [ -z "${project_name}" ] && continue
    [ -z "${command_name}" ] && continue
    [ -z "${event_type}" ] && continue
    [ -z "${recorded_at}" ] && recorded_at="$(feedback_file_mtime_utc "${usage_file}")"

    cat >> "${SQL_FILE}" <<SQL
INSERT INTO usage_events(id, project_name, command_name, event_type, learning_id, query_text, metadata_json, created_at)
VALUES (
  '$(feedback_escape_sql "${event_id}")',
  '$(feedback_escape_sql "${project_name}")',
  '$(feedback_escape_sql "${command_name}")',
  '$(feedback_escape_sql "${event_type}")',
  '$(feedback_escape_sql "${learning_id}")',
  '$(feedback_escape_sql "${query_text}")',
  '$(feedback_escape_sql "${metadata_json}")',
  '$(feedback_escape_sql "${recorded_at}")'
);
SQL
  done < <(jq -r '
    [
      (.event_id // ""),
      (.project // ""),
      (.command_name // ""),
      (.event_type // ""),
      (.learning_id // ""),
      (.query_text // ""),
      (.recorded_at // ""),
      ((.metadata // {}) | tojson)
    ] | @tsv
  ' "${usage_file}" 2>/dev/null || true)
done < <(find "$(feedback_learnings_usage_dir)" -type f -name '*.jsonl' | sort 2>/dev/null || true)

printf 'COMMIT;\n' >> "${SQL_FILE}"

if sqlite3 "${DB_PATH}" < "${SQL_FILE}"; then
  sqlite3 "${DB_PATH}" <<SQL
UPDATE index_runs
SET finished_at = '$(feedback_escape_sql "$(feedback_timestamp_utc)")',
    status = 'success',
    indexed_count = ${INDEXED_COUNT},
    error_text = NULL
WHERE id = '$(feedback_escape_sql "${RUN_ID}")';
SQL
else
  sqlite3 "${DB_PATH}" <<SQL
UPDATE index_runs
SET finished_at = '$(feedback_escape_sql "$(feedback_timestamp_utc)")',
    status = 'failed',
    indexed_count = ${INDEXED_COUNT},
    error_text = 'sqlite apply failed'
WHERE id = '$(feedback_escape_sql "${RUN_ID}")';
SQL
  rm -f "${SQL_FILE}"
  echo "Error: failed to rebuild learnings index." >&2
  exit 1
fi

rm -f "${SQL_FILE}"

if [ "${JSON_OUTPUT}" = "true" ]; then
  jq -n \
    --arg run_id "${RUN_ID}" \
    --arg mode "$( [ "${FULL_REBUILD}" = "true" ] && printf full || printf incremental )" \
    --arg started_at "${RUN_STARTED_AT}" \
    --arg finished_at "$(feedback_timestamp_utc)" \
    --argjson indexed_count "${INDEXED_COUNT}" \
    --arg db_path "${DB_PATH}" \
    '{
      run_id: $run_id,
      mode: $mode,
      started_at: $started_at,
      finished_at: $finished_at,
      indexed_count: $indexed_count,
      db_path: $db_path
    }'
elif [ "${QUIET}" != "true" ]; then
  echo "Indexed learnings: ${INDEXED_COUNT}"
  echo "Database: ${DB_PATH}"
fi
