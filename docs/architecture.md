# Architecture

## Overview
`feedback-hub` separates repo-local project integration from hub-owned text artifacts and from rebuildable fast-lookup state.

The architecture has three explicit zones:
- the project-facing shell used inside integrated repos
- the hub-owned canonical text artifacts
- optional automation plus rebuildable derived state

## Public Diagram Status
The public branch intentionally does not publish a single overview SVG.

Reason:
- the previous single-view diagram was not coherent enough to carry the public architecture story cleanly
- this system is easier to explain through multiple focused views than through one overloaded summary diagram

Current public rule:
- this document is the narrative architecture source of truth
- the diagram set complements this document with three generated focused views
- the public verifier checks that those generated views are current

Published public views:
1. `docs/diagrams/repo-local-integration.svg`
2. `docs/diagrams/canonical-artifacts-and-promotion-flow.svg`
3. `docs/diagrams/automation-and-rebuildable-state.svg`

## Zones

### 1. Project-Facing Shell
Each integrated project gets repo-local entrypoints:
- `feedback/` as the project-owned raw write surface
- `learnings/` as the shared read-only memory surface
- the `feedback` CLI for integration and capture
- the `learnings` CLI for indexing, search, recommendation, and recorded adoption outcomes

This shell is where normal project work happens. It should feel local to the project repo even though the shared memory is hub-managed.

### 2. Hub-Owned Canonical Text Artifacts
The hub owns two canonical text layers:
- project feedback
- curated learnings

Project feedback is the raw ingestion surface for:
- lessons
- decisions
- incidents
- incoming guidance
- outgoing guidance

Curated learnings hold reusable cross-project material promoted from that raw surface.

The key boundary is:
- projects write only project feedback
- projects do not write curated learnings directly
- promotion review is the only path from raw project feedback into curated learnings

### 3. Automation And Rebuildable Derived State
Automation is optional. A scheduler and user-configured backend adapter may review changed feedback batches and emit promotion decisions.

Lookup performance uses rebuildable derived state:
- SQLite index
- profiles
- usage logs
- recommendation inputs

This state exists to make the text corpus usable quickly. It is not the source of truth.

## Public Diagram Set
The public diagram set is intentionally split into focused views rather than one flattened overview.

Published views:
1. repo-local integration view
2. canonical artifact and promotion-flow view
3. automation and rebuildable-state view

## Design Rules
- keep canonical knowledge as text artifacts
- keep derived state rebuildable
- keep project writes isolated from shared curated memory
- require explicit promotion for cross-project learnings
- keep backend integrations replaceable
- keep optional automation separate from the base shell so manual local use still works

## Integration Model
Project integration gives a repo:
- a local feedback path
- a local learnings path
- command surfaces for capture, indexing, search, and recommendation

The public shell documents this generically and does not assume any private workstation layout.
