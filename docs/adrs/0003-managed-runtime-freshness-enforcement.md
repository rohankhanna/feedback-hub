# ADR 0003: Managed Runtime Freshness Enforcement

- Status: Accepted
- Date: 2026-04-12

## Context

`feedback-hub` integrates agent instruction surfaces into other repositories. Prose-only reminders to refresh instructions before tool use are too easy to bypass when the supported runtime can enforce freshness mechanically.

At the same time, the public `main` branch must remain usable without private support tooling.

## Decision

On `internal`, `feedback apply` refreshes:
- canonical `AGENTS.md` content
- watched-file freshness state
- executable runtime freshness enforcement for supported Claude and Gemini repo-local surfaces

This enforcement remains an internal operating feature. Public `main` must stay usable without requiring those runtime integrations or the private support tooling behind them.

## Consequences

Positive:
- supported runtimes can block stale instruction use mechanically
- `AGENTS.md` remains canonical while runtime mirrors stay exact replicas
- private operating workflows gain stronger guardrails without redefining the public product

Costs:
- verification needs a repo-local fallback for CI when the real `hot-reload` tool is intentionally absent there
- the internal branch must keep the runtime integrations and freshness checks maintained as first-class behavior
