#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required tool not found: $1" >&2
    exit 1
  fi
}

for tool in bash git jq sqlite3 cmp mktemp rg; do
  require_tool "${tool}"
done

echo "[1/6] shell syntax"
bash -n ./scripts/*.sh ./scripts/lib/*.sh

echo "[2/6] command help surfaces"
feedback_help="$(./scripts/feedback.sh --help)"
learnings_help="$(./scripts/learnings.sh --help)"
printf '%s\n' "${feedback_help}" >/dev/null
printf '%s\n' "${learnings_help}" >/dev/null

echo "[3/6] public support-tool leakage"
if printf '%s\n' "${feedback_help}" | rg -n 'hot-reload|hot reload' >/dev/null; then
  echo "Error: feedback help references internal support tooling." >&2
  exit 1
fi
if rg -n 'hot-reload|hot reload' README.md docs/operations.md scripts/install_feedback.sh >/dev/null; then
  echo "Error: public-facing surfaces reference internal support tooling." >&2
  exit 1
fi

echo "[4/6] architecture diagram freshness"
./scripts/render_architecture.sh --check >/dev/null

echo "[5/6] required public docs and guardrails"
for path in README.md AUTHORSHIP.md LICENSE CONTRIBUTING.md SECURITY.md CODEOWNERS CODE_OF_CONDUCT.md docs/architecture.md docs/architecture.diagram.json docs/architecture.svg docs/feedback-artifacts.md docs/governance.md docs/operations.md docs/adrs/README.md .githooks/pre-push; do
  if [ ! -f "${path}" ]; then
    echo "Error: required file missing: ${path}" >&2
    exit 1
  fi
done
if ! rg -n '^## Project Intent$' README.md >/dev/null; then
  echo "Error: README.md is missing the required Project Intent section." >&2
  exit 1
fi
if [ "$(find docs/adrs -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.md' | wc -l | tr -d '[:space:]')" -lt 1 ]; then
  echo "Error: at least one ADR is required under docs/adrs/." >&2
  exit 1
fi

echo "[6/6] smoke test"
tmp_root="$(mktemp -d)"
tmp_data_root="${tmp_root}/hub-data"
project_name="feedback-hub-verify-smoke"
project_repo="${tmp_root}/${project_name}"
hub_project_dir="${tmp_data_root}/projects/${project_name}"

cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT

mkdir -p "${tmp_data_root}"
mkdir -p "${project_repo}"
git -C "${project_repo}" init -q
printf '# %s\n' "${project_name}" > "${project_repo}/README.md"

FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/feedback.sh apply "${project_repo}" >/dev/null
FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/feedback.sh status "${project_repo}" --json >/dev/null
FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/feedback.sh capture \
  --kind lesson \
  --title "Use durable checkpoints for restart-safe retries" \
  --summary "Persist durable resume markers for restart-safe background retries." \
  --context "A long-running scheduled flow may outlive one process." \
  --action-taken "Moved retry checkpoints into durable local state." \
  --result "Retries resumed safely after restarts." \
  --reuse-guidance "Persist resume markers when retries can span restarts." \
  "${project_repo}" \
  --json >/dev/null
unsafe_artifact="$(find "${hub_project_dir}/feedback/lessons" -type f -name '*.json' | head -n1)"
if [ "$(find "${hub_project_dir}/feedback" -type f -name '*.json' | wc -l | tr -d '[:space:]')" -lt 1 ]; then
  echo "Error: feedback capture smoke test did not create a JSON artifact." >&2
  exit 1
fi
if find "${hub_project_dir}/feedback" -type f -name '*.md' | grep -q .; then
  echo "Error: feedback capture smoke test still produced Markdown artifacts." >&2
  exit 1
fi
unsafe_rel="${unsafe_artifact#${hub_project_dir}/feedback/}"
if FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/promote_feedback.sh "${project_name}" "${unsafe_rel}" patterns copy >/dev/null 2>&1; then
  echo "Error: promotion accepted unreviewed or non-public-safe feedback." >&2
  exit 1
fi
FEEDBACK_DATA_ROOT="${tmp_data_root}" \
FEEDBACK_WRITER_TYPE=agent \
FEEDBACK_WRITER_TOOL=codex \
FEEDBACK_WRITER_PROVIDER=openai \
FEEDBACK_WRITER_MODEL_NAME=GPT-5.4 \
FEEDBACK_WRITER_MODEL_ID=gpt-5.4 \
FEEDBACK_REVIEW_STATUS=reviewed \
FEEDBACK_ANONYMIZATION_REVIEWED=true \
FEEDBACK_PROMPT_INJECTION_REVIEWED=true \
FEEDBACK_DISTRIBUTION_SCOPE=generalized-shareable \
FEEDBACK_PUBLIC_SAFE=true \
FEEDBACK_EMBARGO_STATUS=none \
FEEDBACK_RIGHTS_STATUS=original-or-authorized \
./scripts/feedback.sh capture \
  --kind outgoing \
  --title "Use stable artifact identifiers for promotion" \
  --summary "Promotion decisions should use stable artifact identifiers rather than local paths." \
  --context "A local planner needed to choose reusable artifacts without exposing ownership paths." \
  --action-taken "The plan output referenced artifact identifiers and resolved paths locally." \
  --result "Promotion became less path-coupled and easier to interoperate with alternate stores." \
  --reuse-guidance "Use transport metadata for routing and keep payload schemas tolerant of future change." \
  --suggest patterns \
  "${project_repo}" \
  --json >/dev/null
safe_artifact="$(find "${hub_project_dir}/feedback/outgoing" -type f -name '*.json' | head -n1)"
safe_rel="${safe_artifact#${hub_project_dir}/feedback/}"
FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/promote_feedback.sh "${project_name}" "${safe_rel}" patterns copy >/dev/null
if [ "$(find "${tmp_data_root}/learnings/patterns" -type f -name '*.json' | wc -l | tr -d '[:space:]')" -lt 1 ]; then
  echo "Error: promotion smoke test did not create a learning JSON artifact." >&2
  exit 1
fi
find "${tmp_data_root}/learnings/patterns" -type f -name '*.json' -print0 \
  | xargs -0 -n1 jq -e '.schema.artifact_class == "learning" and .policy.public_safe == true' >/dev/null
FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/learnings.sh index --json >/dev/null
FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/learnings.sh recommend "${project_repo}" --json >/dev/null
FEEDBACK_DATA_ROOT="${tmp_data_root}" ./scripts/feedback.sh delete "${project_repo}" --purge --yes >/dev/null

echo "Verification passed."
