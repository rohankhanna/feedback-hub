# ADR 0002: Structured JSON Artifacts And Externalized Runtime Data

- Status: Accepted
- Date: 2026-04-12

## Context

The repo needs a stable artifact contract for project feedback, curated learnings, and interactions. Raw runtime data also changes continuously and should not live in version-controlled source history.

Earlier markdown-heavy storage made promotion and indexing less strict, while repo-local mutable data increased the risk of mixing maintained source with generated runtime state.

## Decision

Use structured JSON as the canonical artifact format for:
- project feedback
- curated learnings
- learning interactions
- promotion outputs

Keep runtime data outside the version-controlled repo tree under the resolved feedback-hub data root. The repo may expose local convenience symlinks into that runtime tree, but those symlinks are operator surfaces rather than the maintained source of truth.

Version-controlled content remains limited to maintained source artifacts such as scripts, docs, schemas, configs, ADRs, and architecture sources.

## Consequences

Positive:
- capture, promotion, indexing, and retrieval share one stable envelope
- policy and review metadata can travel with the artifact itself
- runtime mutation stays outside Git history

Costs:
- migration and compatibility work is required for legacy markdown artifacts
- tooling must remain tolerant of old artifacts during the transition window
