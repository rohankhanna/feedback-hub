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

for tool in bash git jq sqlite3 mktemp; do
  require_tool "${tool}"
done

echo "[1/5] shell syntax"
bash -n ./scripts/*.sh ./scripts/lib/*.sh

echo "[2/5] command help surfaces"
./scripts/feedback.sh --help >/dev/null
./scripts/learnings.sh --help >/dev/null

echo "[3/5] public architecture surface"
if [ ! -f docs/architecture.md ]; then
  echo "Error: required file missing: docs/architecture.md" >&2
  exit 1
fi
if [ -f docs/architecture.svg ] || [ -f docs/architecture.diagram.json ]; then
  echo "Error: public main should not ship the deprecated single-view architecture diagram surface." >&2
  exit 1
fi
./scripts/render_architecture.sh --check >/dev/null

echo "[4/5] required public docs"
for path in \
  README.md \
  LICENSE \
  CONTRIBUTING.md \
  CODEOWNERS \
  SECURITY.md \
  CODE_OF_CONDUCT.md \
  docs/architecture.md \
  docs/governance.md \
  docs/operations.md \
  docs/backend-setup.md \
  docs/diagrams/repo-local-integration.diagram.json \
  docs/diagrams/repo-local-integration.svg \
  docs/diagrams/canonical-artifacts-and-promotion-flow.diagram.json \
  docs/diagrams/canonical-artifacts-and-promotion-flow.svg \
  docs/diagrams/automation-and-rebuildable-state.diagram.json \
  docs/diagrams/automation-and-rebuildable-state.svg \
  scripts/render_architecture.sh; do
  if [ ! -f "${path}" ]; then
    echo "Error: required file missing: ${path}" >&2
    exit 1
  fi
done

echo "[5/5] smoke test"
tmp_root="$(mktemp -d)"
project_name="feedback-hub-verify-smoke"
project_repo="${tmp_root}/${project_name}"
hub_project_dir="${REPO_ROOT}/projects/${project_name}"

cleanup() {
  rm -rf "${tmp_root}"
  rm -rf "${hub_project_dir}"
}
trap cleanup EXIT

mkdir -p "${project_repo}"
git -C "${project_repo}" init -q
printf '# %s\n' "${project_name}" > "${project_repo}/README.md"

./scripts/feedback.sh apply "${project_repo}" >/dev/null
./scripts/feedback.sh status "${project_repo}" --json >/dev/null
./scripts/learnings.sh index --json >/dev/null
./scripts/learnings.sh recommend "${project_repo}" --json >/dev/null
./scripts/feedback.sh delete "${project_repo}" --purge --yes >/dev/null

echo "Verification passed."
