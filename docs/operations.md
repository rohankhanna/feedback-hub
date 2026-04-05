# Operations

## Overview
`feedback-hub` manages two user-facing command surfaces:
- `feedback` for project integration and project-owned feedback capture
- `learnings` for indexing, search, recommendation, and curated learnings operations

This document describes standalone operation of this repository without assuming any private support stack.

## Prerequisites
- `bash`
- `git`
- `jq`
- `sqlite3`
- standard local shell tools available on a typical Linux or macOS workstation

Optional:
- an LLM CLI or API-backed adapter if you want automated curation

## Repo-Local Usage
Apply integration to the current project:

```bash
./scripts/feedback.sh apply
```

Apply integration to a specific project path:

```bash
./scripts/feedback.sh apply <project_repo_path>
```

Apply integration across a root directory of repos:

```bash
./scripts/feedback.sh apply-all <desktop_root>
```

Check status:

```bash
./scripts/feedback.sh status [project_repo_path]
```

Capture feedback:

```bash
./scripts/feedback.sh lesson "<title>"
./scripts/feedback.sh decision "<title>"
./scripts/feedback.sh incident "<title>"
./scripts/feedback.sh incoming "<title>"
./scripts/feedback.sh outgoing "<title>"
```

## Learnings Commands
Build or rebuild the local index:

```bash
./scripts/learnings.sh index
```

Inspect project profile:

```bash
./scripts/learnings.sh profile [project_repo_path]
```

Search curated learnings:

```bash
./scripts/learnings.sh search "<query>" [project_repo_path]
```

Get profile-based recommendations:

```bash
./scripts/learnings.sh recommend [project_repo_path]
```

Record use of a learning:

```bash
./scripts/learnings.sh adopt <learning_id> [project_repo_path]
./scripts/learnings.sh reject <learning_id> [project_repo_path]
./scripts/learnings.sh defer <learning_id> [project_repo_path]
```

## Global Install
Optional launcher install:

```bash
./scripts/install_feedback.sh
```

After that, the same commands can be run as:

```bash
feedback apply
feedback status
learnings index
learnings recommend
```

## Optional Automated Curation
Automated curation requires user-supplied backend configuration.

The public shell documents only the generic rule:
- the sync runner expects a backend adapter script
- the adapter is responsible for talking to any chosen LLM CLI or API

Provider-specific setup is intentionally left to user configuration rather than public default wiring.

See `docs/backend-setup.md` for the public backend contract and setup model.

## Data Model
- runtime data root defaults to the live feedback-hub instance rather than the committed repo tree
- project-owned feedback lives under `<data_root>/projects/<project_name>/feedback`
- curated shared learnings live under `<data_root>/learnings/`
- derived local state lives under `<data_root>/.state/`
- local `feedback`, `projects`, `learnings`, and `.state` paths may exist as convenience symlinks, but they are local-only and not version-controlled content
- commands can be pointed at an isolated disposable data root with:

```bash
FEEDBACK_DATA_ROOT=/tmp/feedback-hub-data ./scripts/feedback.sh status .
```

## Verification
Canonical verification path:

```bash
./scripts/verify.sh
```

What it checks:
- shell syntax for the CLI scripts
- command help surfaces
- public architecture documentation presence
- presence of the required public docs
- a repo-local integration smoke test against a disposable temporary repo

## Deletion
Remove only local integration links:

```bash
./scripts/feedback.sh delete [project_repo_path]
```

Optional destructive cleanup of hub-owned project feedback:

```bash
./scripts/feedback.sh delete [project_repo_path] --purge --yes
```
