#!/usr/bin/env bash
set -euo pipefail

FEEDBACK_ARTIFACTS_LIB_SELF="${BASH_SOURCE[0]}"
FEEDBACK_ARTIFACTS_LIB_DIR="$(cd "$(dirname "${FEEDBACK_ARTIFACTS_LIB_SELF}")" && pwd)"
# shellcheck disable=SC1091
source "${FEEDBACK_ARTIFACTS_LIB_DIR}/common.sh"
# shellcheck disable=SC1091
source "${FEEDBACK_ARTIFACTS_LIB_DIR}/json.sh"

feedback_artifact_schema_family() {
  printf 'feedback-hub.artifact\n'
}

feedback_artifact_schema_version() {
  printf '1\n'
}

feedback_artifact_supports_class() {
  case "${1:-}" in
    project_feedback|learning|learning_interaction)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

feedback_artifact_class_version() {
  local artifact_class="${1:-}"

  if ! feedback_artifact_supports_class "${artifact_class}"; then
    printf 'Error: unsupported artifact class: %s\n' "${artifact_class:-<empty>}" >&2
    return 1
  fi

  printf '1\n'
}

feedback_artifact_new_id() {
  local prefix="${1:-artifact}"
  local token=""

  if command -v openssl >/dev/null 2>&1; then
    token="$(openssl rand -hex 12)"
  else
    token="$(od -An -N 12 -tx1 /dev/urandom | tr -d ' \n')"
  fi

  printf '%s_%s\n' "$(feedback_slugify "${prefix}")" "${token}"
}

feedback_artifact_json_array_from_csv() {
  printf '%s' "${1:-}" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk 'NF { print }' \
    | feedback_json_array_from_lines
}

feedback_artifact_require_nonempty() {
  local label="${1:-value}"
  local value="${2:-}"

  if [ -z "${value}" ]; then
    printf 'Error: %s must not be empty.\n' "${label}" >&2
    return 1
  fi
}

feedback_artifact_publication_block_reason() {
  local artifact_path="${1:-}"

  if [ -z "${artifact_path}" ] || [ ! -f "${artifact_path}" ]; then
    printf 'artifact file is missing\n'
    return 0
  fi

  jq -r '
    def norm: tostring | ascii_downcase | gsub("[ _]"; "-");
    def oneof($xs): . as $v | any($xs[]; . == $v);

    [
      (if (.schema.artifact_class // "") != "project_feedback" then
        "schema.artifact_class must be project_feedback"
      else empty end),
      (if (.review.anonymization_reviewed // false) != true then
        "review.anonymization_reviewed must be true"
      else empty end),
      (if (.review.prompt_injection_reviewed // false) != true then
        "review.prompt_injection_reviewed must be true"
      else empty end),
      (if (.policy.public_safe // false) != true then
        "policy.public_safe must be true"
      else empty end),
      (if ((.policy.distribution_scope // "" | norm) | oneof(["generalized-shareable", "public", "public-shareable", "open", "network-shareable"]) | not) then
        "policy.distribution_scope must be generalized-shareable, public, public-shareable, open, or network-shareable"
      else empty end),
      (if ((.policy.embargo_status // "" | norm) | oneof(["none", "not-embargoed", "public", "cleared"]) | not) then
        "policy.embargo_status must be none, not-embargoed, public, or cleared"
      else empty end),
      (if ((.policy.rights_status // "" | norm) | oneof([
        "original-or-authorized",
        "authorized",
        "cleared",
        "open-source-compatible",
        "public-domain",
        "permissive",
        "permissively-licensed"
      ]) | not) then
        "policy.rights_status must be original, authorized, open-compatible, or public-domain"
      else empty end)
    ] | join("; ")
  ' "${artifact_path}" 2>/dev/null || printf 'artifact is not valid JSON\n'
}

feedback_artifact_is_publication_ready() {
  local artifact_path="${1:-}"
  local block_reason

  block_reason="$(feedback_artifact_publication_block_reason "${artifact_path}")"
  [ -z "${block_reason}" ]
}

feedback_artifact_base_json() {
  local artifact_class="${1:-}"
  local artifact_id="${2:-}"
  local kind="${3:-}"
  local title="${4:-}"
  local captured_at="${5:-}"

  feedback_artifact_supports_class "${artifact_class}" || return 1
  feedback_artifact_require_nonempty "artifact id" "${artifact_id}" || return 1
  feedback_artifact_require_nonempty "artifact kind" "${kind}" || return 1
  feedback_artifact_require_nonempty "artifact title" "${title}" || return 1
  feedback_artifact_require_nonempty "captured_at" "${captured_at}" || return 1

  feedback_json_object \
    --arg family "$(feedback_artifact_schema_family)" \
    --argjson version "$(feedback_artifact_schema_version)" \
    --arg artifact_class "${artifact_class}" \
    --argjson artifact_class_version "$(feedback_artifact_class_version "${artifact_class}")" \
    --arg id "${artifact_id}" \
    --arg kind "${kind}" \
    --arg title "${title}" \
    --arg captured_at "${captured_at}" \
    '{
      schema: {
        family: $family,
        version: $version,
        artifact_class: $artifact_class,
        artifact_class_version: $artifact_class_version
      },
      artifact: {
        id: $id,
        kind: $kind,
        title: $title,
        captured_at: $captured_at
      },
      subject: {
        topic: "",
        generic_exemplars: [],
        notes: ""
      },
      facets: {
        workload_shape: [],
        change_facets: [],
        risk_facets: []
      },
      writer: {
        writer_type: "",
        tool: "",
        provider: "",
        model: {
          display_name: "",
          id: ""
        }
      },
      review: {
        status: "",
        anonymization_reviewed: false,
        prompt_injection_reviewed: false
      },
      policy: {
        distribution_scope: "",
        public_safe: false,
        embargo_status: "",
        rights_status: ""
      },
      content: {
        summary: "",
        body_markdown: "",
        sections: [],
        context: "",
        action_taken: "",
        result: "",
        reuse_guidance: ""
      },
      links: {
        related_artifacts: [],
        supersedes: null
      },
      extensions: {}
    }'
}
