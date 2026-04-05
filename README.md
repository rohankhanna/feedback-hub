# feedback-hub

## Purpose
`feedback-hub` is a local cross-project learning memory for software projects. Each project keeps its own raw feedback in a project-owned area. Reusable lessons, decisions, and patterns can be curated into a shared learnings corpus.

## Status
`feedback-hub` is a standalone, local-first CLI for feedback capture, curated learnings lookup, and optional automated curation.

## What It Provides
- repo-local project integration through `feedback`
- structured feedback capture for lessons, decisions, incidents, and cross-project guidance
- shared learnings lookup through `learnings`
- local indexing, search, and recommendation over curated learnings
- optional automated curation through a configurable backend adapter

## Quickstart

### Run directly from this repo
```bash
# integrate the current project repo
./scripts/feedback.sh apply

# check integration status
./scripts/feedback.sh status

# capture a lesson
./scripts/feedback.sh lesson "Keep decision records short and concrete"

# build the learnings index
./scripts/learnings.sh index

# inspect relevant learnings
./scripts/learnings.sh recommend
./scripts/learnings.sh search "architecture state recovery"
```

### Optional global install
```bash
./scripts/install_feedback.sh

feedback apply
feedback status
feedback lesson "Keep decision records short and concrete"
learnings index
learnings recommend
```

## Core Model
- each project writes only to its own feedback area
- curated learnings are shared read-only memory for projects
- projects do not write directly to the curated learnings corpus
- the feedback repository owns curation and promotion into shared learnings

## Typical Workflow
1. Apply integration to a project repo.
2. Capture lessons, decisions, and incidents during real work.
3. Rebuild the local learnings index.
4. Search or recommend learnings before substantive work.
5. Optionally curate reusable project feedback into shared learnings.

## Verification
Canonical verification path:

```bash
./scripts/verify.sh
```

If you install the global launchers, verify them too:

```bash
feedback --help
learnings --help
```

## Documentation
- operations: `docs/operations.md`
- architecture: `docs/architecture.md`
- governance: `docs/governance.md`
- backend setup: `docs/backend-setup.md`

Architecture is documented through three focused generated views under `docs/diagrams/`, with `docs/architecture.md` as the narrative source of truth.

## Current Scope
- local development environments
- project feedback capture
- curated learnings lookup
- optional automated curation through a configurable backend contract

## Help
- start with the command help surfaces
- review the docs listed above
- configure an automation backend only after the standalone shell is working locally

Backend setup is configurable by the user. This repo does not assume any specific LLM CLI or API is already installed or prewired.

## Project Policy Files
- license: `LICENSE`
- contributing: `CONTRIBUTING.md`
- security reporting: `SECURITY.md`
- code ownership: `CODEOWNERS`
- community conduct: `CODE_OF_CONDUCT.md`
