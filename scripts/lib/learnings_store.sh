#!/usr/bin/env bash
set -euo pipefail

FEEDBACK_LEARNINGS_STORE_LIB_SELF="${BASH_SOURCE[0]}"
FEEDBACK_LEARNINGS_STORE_LIB_DIR="$(cd "$(dirname "${FEEDBACK_LEARNINGS_STORE_LIB_SELF}")" && pwd)"
# shellcheck disable=SC1091
source "${FEEDBACK_LEARNINGS_STORE_LIB_DIR}/common.sh"
# shellcheck disable=SC1091
source "${FEEDBACK_LEARNINGS_STORE_LIB_DIR}/json.sh"
# shellcheck disable=SC1091
source "${FEEDBACK_LEARNINGS_STORE_LIB_DIR}/project_context.sh"

feedback_learnings_state_dir() {
  printf '%s/learnings\n' "$(feedback_state_dir)"
}

feedback_learnings_db_path() {
  printf '%s/index.sqlite\n' "$(feedback_learnings_state_dir)"
}

feedback_learnings_profiles_dir() {
  printf '%s/profiles\n' "$(feedback_learnings_state_dir)"
}

feedback_learnings_interactions_dir() {
  printf '%s/interactions\n' "$(feedback_learnings_state_dir)"
}

feedback_learnings_usage_dir() {
  printf '%s/usage\n' "$(feedback_learnings_state_dir)"
}

feedback_learnings_runs_dir() {
  printf '%s/runs\n' "$(feedback_learnings_state_dir)"
}

feedback_learnings_promotion_log_path() {
  printf '%s/promotion-log.tsv\n' "$(feedback_learnings_dir)"
}

feedback_learnings_validation_log_path() {
  printf '%s/validation-log.tsv\n' "$(feedback_learnings_dir)"
}

feedback_learnings_supersession_log_path() {
  printf '%s/supersession-log.tsv\n' "$(feedback_learnings_dir)"
}

feedback_learnings_ensure_state_dirs() {
  feedback_mkdir_if_missing "$(feedback_learnings_dir)"
  feedback_mkdir_if_missing "$(feedback_learnings_state_dir)"
  feedback_mkdir_if_missing "$(feedback_learnings_profiles_dir)"
  feedback_mkdir_if_missing "$(feedback_learnings_interactions_dir)"
  feedback_mkdir_if_missing "$(feedback_learnings_usage_dir)"
  feedback_mkdir_if_missing "$(feedback_learnings_runs_dir)"
}

feedback_learnings_prepare_db_writes() {
  local db_path
  local db_dir
  local candidate

  db_path="$(feedback_learnings_db_path)"
  db_dir="$(dirname "${db_path}")"

  feedback_learnings_ensure_state_dirs

  if [ ! -w "${db_dir}" ]; then
    printf 'Error: learnings state directory is not writable: %s\n' "${db_dir}" >&2
    return 1
  fi

  for candidate in "${db_path}" "${db_path}-wal" "${db_path}-shm"; do
    if [ -e "${candidate}" ] && [ ! -w "${candidate}" ]; then
      chmod u+w "${candidate}" 2>/dev/null || {
        printf 'Error: learnings database path is not writable: %s\n' "${candidate}" >&2
        return 1
      }
    fi
  done
}

feedback_learnings_sqlite_write_best_effort() {
  local write_label="${1:-learnings database write}"
  local db_path
  local tmp_sql
  local tmp_err
  local status=0

  db_path="$(feedback_learnings_db_path)"
  if [ ! -f "${db_path}" ]; then
    cat >/dev/null
    return 0
  fi

  tmp_sql="$(mktemp)"
  tmp_err="$(mktemp)"
  {
    printf 'PRAGMA busy_timeout = 5000;\n'
    cat
  } > "${tmp_sql}"

  if ! sqlite3 "${db_path}" >/dev/null 2>"${tmp_err}" < "${tmp_sql}"; then
    status=$?
    printf 'Warning: %s skipped: %s\n' "${write_label}" "$(tr '\n' ' ' < "${tmp_err}" | sed 's/[[:space:]]\+/ /g; s/[[:space:]]*$//')" >&2
  fi

  rm -f "${tmp_sql}" "${tmp_err}"
  return "${status}"
}

feedback_learnings_ensure_db() {
  local db_path

  db_path="$(feedback_learnings_db_path)"
  feedback_learnings_prepare_db_writes

  sqlite3 "${db_path}" >/dev/null <<'SQL'
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=OFF;

CREATE TABLE IF NOT EXISTS schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS learning_entities (
  id TEXT PRIMARY KEY,
  path TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT,
  body TEXT NOT NULL,
  source_project TEXT,
  source_artifact TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  superseded_by TEXT,
  evidence_strength REAL NOT NULL DEFAULT 0,
  adoption_cost TEXT,
  created_at TEXT,
  updated_at TEXT,
  last_validated_at TEXT,
  file_hash TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS learning_tags (
  learning_id TEXT NOT NULL,
  tag TEXT NOT NULL,
  PRIMARY KEY (learning_id, tag)
);

CREATE TABLE IF NOT EXISTS learning_facets (
  learning_id TEXT NOT NULL,
  facet_key TEXT NOT NULL,
  facet_value TEXT NOT NULL,
  PRIMARY KEY (learning_id, facet_key, facet_value)
);

CREATE TABLE IF NOT EXISTS learning_links (
  from_learning_id TEXT NOT NULL,
  to_learning_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,
  PRIMARY KEY (from_learning_id, to_learning_id, relation_type)
);

CREATE TABLE IF NOT EXISTS project_profiles (
  project_name TEXT PRIMARY KEY,
  repo_path TEXT NOT NULL,
  languages_json TEXT NOT NULL,
  frameworks_json TEXT NOT NULL,
  repo_kind TEXT,
  runtime_traits_json TEXT NOT NULL,
  state_profile TEXT,
  profile_hash TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS interactions (
  id TEXT PRIMARY KEY,
  project_name TEXT NOT NULL,
  learning_id TEXT NOT NULL,
  action TEXT NOT NULL,
  note TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS usage_events (
  id TEXT PRIMARY KEY,
  project_name TEXT NOT NULL,
  command_name TEXT NOT NULL,
  event_type TEXT NOT NULL,
  learning_id TEXT,
  query_text TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS index_runs (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  status TEXT NOT NULL,
  indexed_count INTEGER NOT NULL DEFAULT 0,
  error_text TEXT
);

CREATE VIRTUAL TABLE IF NOT EXISTS learning_fts USING fts5(
  id UNINDEXED,
  title,
  summary,
  body,
  tags_text,
  facets_text
);

INSERT INTO schema_meta(key, value)
VALUES ('schema_version', '2')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;
SQL
}

feedback_learnings_require_db() {
  local db_path

  db_path="$(feedback_learnings_db_path)"
  if [ ! -f "${db_path}" ]; then
    echo "Error: learnings index not found. Run 'learnings index' first." >&2
    return 1
  fi
}

feedback_learnings_default_evidence_strength() {
  case "${1:-}" in
    anti-patterns) printf '0.80\n' ;;
    patterns) printf '0.70\n' ;;
    templates) printf '0.60\n' ;;
    agents) printf '0.55\n' ;;
    *) printf '0.50\n' ;;
  esac
}

feedback_learnings_default_adoption_cost() {
  case "${1:-}" in
    templates) printf 'low\n' ;;
    patterns) printf 'medium\n' ;;
    anti-patterns) printf 'low\n' ;;
    agents) printf 'medium\n' ;;
    *) printf 'medium\n' ;;
  esac
}

feedback_learnings_entity_id_from_relpath() {
  local rel_path="$1"
  printf 'learning_%s\n' "$(feedback_slugify "${rel_path//\//-}")"
}

feedback_extract_frontmatter_value() {
  local file_path="$1"
  local key="$2"

  awk -v wanted="${key}" '
    NR == 1 && $0 == "---" { in_block = 1; next }
    in_block && $0 == "---" { exit }
    in_block && $0 ~ "^[[:space:]]*" wanted ":" {
      sub("^[[:space:]]*" wanted ":[[:space:]]*", "", $0)
      print $0
      exit
    }
  ' "${file_path}"
}

feedback_extract_frontmatter_fields_tsv() {
  local file_path="$1"
  shift

  if [ "$#" -eq 0 ]; then
    printf '\n'
    return 0
  fi

  local keys_csv
  keys_csv="$(printf '%s\n' "$@" | paste -sd',' -)"

  awk -v keys_csv="${keys_csv}" '
    BEGIN {
      key_count = split(keys_csv, keys, ",")
    }
    NR == 1 && $0 == "---" { in_block = 1; next }
    in_block && $0 == "---" { exit }
    in_block {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (match(line, /^([^:]+):[[:space:]]*(.*)$/, fields)) {
        values[fields[1]] = fields[2]
      }
    }
    END {
      for (i = 1; i <= key_count; i++) {
        key = keys[i]
        value = values[key]
        sub(/\r$/, "", value)
        printf "%s", value
        if (i < key_count) {
          printf "\t"
        } else {
          printf "\n"
        }
      }
    }
  ' "${file_path}"
}

feedback_markdown_title() {
  local file_path="$1"
  local title

  title="$(awk '
    NR == 1 && $0 == "---" { in_block = 1; next }
    in_block && $0 == "---" { in_block = 0; next }
    !in_block && /^# / {
      sub(/^# /, "", $0)
      print
      exit
    }
  ' "${file_path}")"

  if [ -z "${title}" ]; then
    title="$(basename "${file_path}" .md)"
  fi

  printf '%s\n' "${title}"
}

feedback_markdown_summary() {
  local file_path="$1"

  awk '
    NR == 1 && $0 == "---" { in_block = 1; next }
    in_block && $0 == "---" { in_block = 0; next }
    !in_block && /^# / { seen_title = 1; next }
    seen_title && /^## / { next }
    seen_title && NF {
      print
      exit
    }
  ' "${file_path}"
}

feedback_learnings_text_blob() {
  local file_path="$1"
  (
    printf '%s\n' "$(basename "${file_path}")"
    cat "${file_path}"
  ) | tr '[:upper:]' '[:lower:]'
}

feedback_learnings_detect_facets() {
  local file_path="$1"
  local learning_type="$2"
  local blob="${3:-}"

  if [ -z "${blob}" ]; then
    blob="$(feedback_learnings_text_blob "${file_path}")"
  fi

  {
    printf 'type\t%s\n' "${learning_type}"

    printf '%s\n' "${blob}" | grep -Eq '\bpython\b|pyproject\.toml|requirements\.txt' && printf 'language\tpython\n'
    printf '%s\n' "${blob}" | grep -Eq '\bjavascript\b|package\.json|\.js\b' && printf 'language\tjavascript\n'
    printf '%s\n' "${blob}" | grep -Eq '\btypescript\b|tsconfig\.json|\.tsx?\b' && printf 'language\ttypescript\n'
    printf '%s\n' "${blob}" | grep -Eq '\brust\b|cargo\.toml|\.rs\b' && printf 'language\trust\n'
    printf '%s\n' "${blob}" | grep -Eq '\bgo\b|go\.mod|\.go\b' && printf 'language\tgo\n'
    printf '%s\n' "${blob}" | grep -Eq '\bshell\b|\.sh\b|bash' && printf 'language\tshell\n'

    printf '%s\n' "${blob}" | grep -Eq '\bfastapi\b' && printf 'framework\tfastapi\n'
    printf '%s\n' "${blob}" | grep -Eq '\bdjango\b' && printf 'framework\tdjango\n'
    printf '%s\n' "${blob}" | grep -Eq '\bflask\b' && printf 'framework\tflask\n'
    printf '%s\n' "${blob}" | grep -Eq '\breact\b' && printf 'framework\treact\n'
    printf '%s\n' "${blob}" | grep -Eq '\bnext\b' && printf 'framework\tnextjs\n'
    printf '%s\n' "${blob}" | grep -Eq '\bexpress\b' && printf 'framework\texpress\n'
    printf '%s\n' "${blob}" | grep -Eq '@nestjs' && printf 'framework\tnestjs\n'

    printf '%s\n' "${blob}" | grep -Eq '\bgit\b|version control|repository' && printf 'topic\tversion-control\n'
    printf '%s\n' "${blob}" | grep -Eq '\bshutdown\b|restart|reboot' && printf 'topic\tshutdown\n'
    printf '%s\n' "${blob}" | grep -Eq '\barchitecture\b|adr|design' && printf 'topic\tarchitecture\n'
    printf '%s\n' "${blob}" | grep -Eq '\btest\b|pytest|unittest|jest|integration test' && printf 'topic\ttesting\n'
    printf '%s\n' "${blob}" | grep -Eq '\bdiagram\b|documentation|docs/' && printf 'topic\tdocumentation\n'
    printf '%s\n' "${blob}" | grep -Eq '\bmigration\b|migrate|backward compat' && printf 'topic\tmigration\n'
    printf '%s\n' "${blob}" | grep -Eq '\bincident\b|outage|regression|root cause' && printf 'topic\tincident\n'
    printf '%s\n' "${blob}" | grep -Eq '\bcron\b|schedule|systemd' && printf 'topic\tscheduling\n'
    printf '%s\n' "${blob}" | grep -Eq '\bsecurity\b|auth|authentication|authorization' && printf 'topic\tsecurity\n'
    printf '%s\n' "${blob}" | grep -Eq '\bstate\b|checkpoint|persist|database|sqlite|postgres|redis' && printf 'topic\tstate\n'

    printf '%s\n' "${blob}" | grep -Eq '\bgit\b' && printf 'tool\tgit\n'
    printf '%s\n' "${blob}" | grep -Eq '\bsqlite\b' && printf 'tool\tsqlite\n'
    printf '%s\n' "${blob}" | grep -Eq '\bpostgres\b|postgresql' && printf 'tool\tpostgres\n'
    printf '%s\n' "${blob}" | grep -Eq '\bredis\b' && printf 'tool\tredis\n'
    printf '%s\n' "${blob}" | grep -Eq '\bcuda\b|gpu|nvidia|tensorrt' && printf 'runtime_trait\tgpu\n'
    printf '%s\n' "${blob}" | grep -Eq '\bcron\b|schedule|systemd' && printf 'runtime_trait\tscheduled\n'
    printf '%s\n' "${blob}" | grep -Eq '\bservice\b|server|daemon|worker' && printf 'repo_kind\tservice\n'
    printf '%s\n' "${blob}" | grep -Eq '\bcli\b|command line|terminal' && printf 'repo_kind\tcli\n'
    printf '%s\n' "${blob}" | grep -Eq '\bstateful\b|checkpoint|persist|database|sqlite|postgres|redis' && printf 'state_profile\tstateful\n'
  } | sort -u || true
}

feedback_learnings_detect_tags() {
  local file_path="$1"
  local learning_type="$2"
  local rel_path="$3"
  local facets_tsv="${4:-}"
  local blob="${5:-}"

  if [ -z "${blob}" ]; then
    blob="$(feedback_learnings_text_blob "${file_path}")"
  fi
  if [ -z "${facets_tsv}" ]; then
    facets_tsv="$(feedback_learnings_detect_facets "${file_path}" "${learning_type}" "${blob}")"
  fi

  {
    printf '%s\n' "${learning_type}"
    printf '%s\n' "$(basename "${rel_path}" .md | tr '-' '\n')"
    printf '%s\n' "${facets_tsv}" | awk -F '\t' '{ print $2 }'
    printf '%s\n' "${blob}" | grep -Eq '\bbest practice\b|pattern\b' && printf 'pattern\n'
    printf '%s\n' "${blob}" | grep -Eq '\banti-pattern\b|avoid\b' && printf 'anti-pattern\n'
    printf '%s\n' "${blob}" | grep -Eq '\breliability\b|resilience\b' && printf 'reliability\n'
  } | awk 'length($0) > 2 { print }' | feedback_unique_sorted_lines || true
}

feedback_learnings_lookup_path_by_id() {
  local learning_id="$1"
  local db_path

  db_path="$(feedback_learnings_db_path)"
  sqlite3 -noheader "${db_path}" \
    "SELECT path FROM learning_entities WHERE id = '$(feedback_escape_sql "${learning_id}")' LIMIT 1;"
}

feedback_learnings_lookup_title_by_id() {
  local learning_id="$1"
  local db_path

  db_path="$(feedback_learnings_db_path)"
  sqlite3 -noheader "${db_path}" \
    "SELECT title FROM learning_entities WHERE id = '$(feedback_escape_sql "${learning_id}")' LIMIT 1;"
}

feedback_learnings_usage_log_path() {
  local project_name="$1"
  printf '%s/%s.jsonl\n' "$(feedback_learnings_usage_dir)" "${project_name}"
}

feedback_learnings_soft_reminder_hours() {
  printf '%s\n' "${FEEDBACK_LEARNINGS_SOFT_REMINDER_HOURS:-24}"
}

feedback_infer_usage_project_path() {
  local candidate_path="${1:-$(pwd)}"
  local resolved_path

  resolved_path="$(feedback_resolve_project_path "${candidate_path}")" || return 1

  if [ "${resolved_path}" = "${FEEDBACK_REPO_ROOT}" ]; then
    printf '%s\n' "${resolved_path}"
    return 0
  fi

  if [ -L "${resolved_path}/feedback" ] || [ -f "${resolved_path}/AGENTS.md" ]; then
    printf '%s\n' "${resolved_path}"
    return 0
  fi

  if git -C "${resolved_path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "${resolved_path}"
    return 0
  fi

  return 1
}

feedback_learnings_record_usage_event() {
  local project_name="$1"
  local command_name="$2"
  local event_type="$3"
  local learning_id="${4:-}"
  local query_text="${5:-}"
  local metadata_json="${6-}"
  local recorded_at event_id log_path event_nonce
  local db_path db_dir
  local json_payload

  if [ -z "${metadata_json}" ]; then
    metadata_json='{}'
  fi

  recorded_at="$(feedback_timestamp_utc)"
  event_nonce="$(date -u +%s%N 2>/dev/null || printf '%s' "${RANDOM}")"
  event_id="usage_${event_nonce}_$(feedback_slugify "${project_name}-${event_type}-${learning_id:-${query_text}}")"
  log_path="$(feedback_learnings_usage_log_path "${project_name}")"
  json_payload="$(jq -nc \
    --arg event_id "${event_id}" \
    --arg project "${project_name}" \
    --arg command_name "${command_name}" \
    --arg event_type "${event_type}" \
    --arg learning_id "${learning_id}" \
    --arg query_text "${query_text}" \
    --arg recorded_at "${recorded_at}" \
    --argjson metadata "${metadata_json}" \
    '{
      event_id: $event_id,
      project: $project,
      command_name: $command_name,
      event_type: $event_type,
      learning_id: $learning_id,
      query_text: $query_text,
      recorded_at: $recorded_at,
      metadata: $metadata
    }' 2>/dev/null || true)"
  if [ -n "${json_payload}" ]; then
    if feedback_mkdir_if_missing "$(dirname "${log_path}")" 2>/dev/null; then
      {
        printf '%s\n' "${json_payload}"
      } >> "${log_path}" 2>/dev/null || true
    fi
  fi

  db_path="$(feedback_learnings_db_path)"
  if [ -f "${db_path}" ]; then
    db_dir="$(dirname "${db_path}")"
    if [ -w "${db_path}" ] && [ -w "${db_dir}" ]; then
      sqlite3 "${db_path}" >/dev/null 2>&1 <<SQL || true
INSERT OR REPLACE INTO usage_events(id, project_name, command_name, event_type, learning_id, query_text, metadata_json, created_at)
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
    fi
  fi

  return 0
}

feedback_learnings_usage_summary_json() {
  local project_name="$1"
  local days="${2:-7}"
  local reminder_hours reminder_cutoff cutoff_epoch log_path

  reminder_hours="$(feedback_learnings_soft_reminder_hours)"
  reminder_cutoff="$(( $(date -u +%s) - (reminder_hours * 3600) ))"
  cutoff_epoch="$(( $(date -u +%s) - (days * 86400) ))"
  log_path="$(feedback_learnings_usage_log_path "${project_name}")"

  if [ ! -f "${log_path}" ]; then
    jq -n \
      --arg project "${project_name}" \
      --argjson days "${days}" \
      --argjson reminder_hours "${reminder_hours}" \
      '{
        project: $project,
        window_days: $days,
        reminder_hours: $reminder_hours,
        last_consulted_at: "",
        consult_counts: {
          recommend: 0,
          search: 0,
          show: 0,
          related: 0
        },
        total_consults_in_window: 0,
        total_usage_events_in_window: 0,
        soft_reminder_due: true,
        soft_reminder_message: "No recent learnings consultation recorded."
      }'
    return 0
  fi

  jq -n \
    --arg project "${project_name}" \
    --argjson days "${days}" \
    --argjson reminder_hours "${reminder_hours}" \
    --argjson cutoff_epoch "${cutoff_epoch}" \
    --argjson reminder_cutoff "${reminder_cutoff}" '
    reduce inputs as $event (
      {
        project: $project,
        window_days: $days,
        reminder_hours: $reminder_hours,
        last_consulted_at: "",
        consult_counts: {
          recommend: 0,
          search: 0,
          show: 0,
          related: 0
        },
        total_consults_in_window: 0,
        total_usage_events_in_window: 0
      };
      if $event.project != $project then
        .
      else
        .total_usage_events_in_window += (
          if (($event.recorded_at | fromdateiso8601? // 0) >= $cutoff_epoch) then 1 else 0 end
        )
        | if ($event.event_type == "recommend" or $event.event_type == "search" or $event.event_type == "show" or $event.event_type == "related") then
            .last_consulted_at =
              (if .last_consulted_at == "" or $event.recorded_at > .last_consulted_at then $event.recorded_at else .last_consulted_at end)
            | if (($event.recorded_at | fromdateiso8601? // 0) >= $cutoff_epoch) then
                .consult_counts[$event.event_type] += 1
                | .total_consults_in_window += 1
              else
                .
              end
          else
            .
          end
      end
    )
    | .soft_reminder_due = (
        .last_consulted_at == ""
        or ((.last_consulted_at | fromdateiso8601? // 0) < $reminder_cutoff)
      )
    | .soft_reminder_message = (
        if .soft_reminder_due then
          "No recent learnings consultation recorded within the reminder window."
        else
          ""
        end
      )' < "${log_path}"
}

feedback_learnings_soft_reminder_due() {
  local project_name="$1"
  feedback_learnings_usage_summary_json "${project_name}" | jq -r '.soft_reminder_due'
}

feedback_learnings_last_consulted_at() {
  local project_name="$1"
  feedback_learnings_usage_summary_json "${project_name}" | jq -r '.last_consulted_at'
}

feedback_learnings_append_validation() {
  local learning_id="$1"
  local note="${2:-}"
  local log_path

  log_path="$(feedback_learnings_validation_log_path)"
  touch "${log_path}" || return 1
  printf '%s\t%s\t%s\n' "$(feedback_timestamp_utc)" "${learning_id}" "${note}" >> "${log_path}" || return 1
  printf '%s\n' "${log_path}"
}

feedback_learnings_append_supersession() {
  local old_id="$1"
  local new_id="$2"
  local log_path

  log_path="$(feedback_learnings_supersession_log_path)"
  touch "${log_path}" || return 1
  printf '%s\t%s\t%s\n' "$(feedback_timestamp_utc)" "${old_id}" "${new_id}" >> "${log_path}" || return 1
  printf '%s\n' "${log_path}"
}
