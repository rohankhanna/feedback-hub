# ADR 0001: Qualified Dual-Branch Operating Model

- Status: Accepted
- Date: 2026-04-12

## Context

`feedback-hub` needs two different surfaces at the same time:
- a public branch that is safe to publish and evaluate as a standalone tool
- a richer private operating branch that can carry repo-local governance, operator guardrails, and private workflow glue

Trying to keep both concerns on one branch would either weaken the private operating posture or leak internal control surfaces onto the public branch.

## Decision

Adopt the qualified dual-branch model for this repo:
- `main` is the public branch
- `internal` is the private operating branch
- `origin` is the private canonical remote
- `public` is the public display remote
- separate worktrees are the preferred local operating mode for `main` and `internal`

Public `main` must stay safe to publish from its root commit forward. Internal-only control surfaces stay on `internal`, and public-safe improvements are promoted deliberately rather than copied blindly across branches.

## Consequences

Positive:
- public evaluation and private day-to-day operation can both stay coherent
- internal guardrails can be stronger without contaminating public history
- the public repo can remain a generalized, adoptable shell

Costs:
- drift control is ongoing work
- shared-path docs require deliberate sanitization review
- promotion from `internal` to `main` must stay routine enough that divergence does not become expensive
