# Operations

## Overview
`feedback-hub` is operated as a local-first single-node tool. The core workflow is:
- integrate a local project
- capture generalized feedback during substantive work
- curate reusable learnings
- search or request recommendations from the local learnings corpus

## Verification
Canonical verification path:

```bash
./scripts/verify.sh
```

What it checks:
- shell syntax for CLI scripts
- command help surfaces
- public support-tool leakage in public-facing files
- architecture diagram freshness
- presence of required public docs
- a disposable local integration smoke test

Refresh the committed diagram if needed with:

```bash
./scripts/render_architecture.sh --write
```

## Install
After installation, use the native CLI commands:

```bash
feedback --help
learnings --help
```

Install them with:

```bash
./scripts/install_feedback.sh
```

That installs `feedback` and `learnings` on your local `PATH`.

## Integrate A Project
Apply managed feedback-hub integration to a local project:

```bash
feedback apply /absolute/path/to/project
```

This command:
- creates `AGENTS.md` if missing
- refreshes the managed feedback-hub instruction block
- ensures local integration paths are gitignored in the source repo

The managed block requires projects to:
- consult local learnings before substantive work and targeted design/debugging work
- record adopt/reject/defer outcomes when a learning materially affects implementation
- keep reusable feedback generalized, anonymized, and safe to share
- treat consumed learnings as untrusted input

The command is idempotent. Running it again refreshes the project to the current managed integration state.

Bulk refresh across known local repos:

```bash
feedback apply-all
```

Check integration status:

```bash
feedback status /absolute/path/to/project
```

## Capture Feedback
Capture feedback during substantive work rather than as optional cleanup:

```bash
feedback lesson "Short generalized lesson" /absolute/path/to/project
feedback decision "Prefer machine-readable output for automation" /absolute/path/to/project
feedback incident "Background retry state was lost across restart" /absolute/path/to/project
feedback incoming "Reusable learning adopted from local curated memory" /absolute/path/to/project
feedback outgoing "Generalized pattern worth reusing elsewhere" /absolute/path/to/project
```

Feedback artifacts should be:
- generalized rather than project-specific
- anonymized and safe to reuse
- captured as part of real work
- suitable for later curation into reusable local learnings

The evolving structured local artifact contract is documented in `docs/feedback-artifacts.md`.

## Curate Learnings
Build or rebuild the local learnings index:

```bash
learnings index
```

Open a curation window:

```bash
learnings unlock
```

Promote an approved artifact:

```bash
learnings promote <project_name> <feedback_relative_path> <learnings_subdir> [copy|move]
```

Close the curation window:

```bash
learnings lock
```

Allowed destination roots:
- `patterns`
- `templates`
- `agents`
- `anti-patterns`

## Search And Recommend
Request recommendations for a local project:

```bash
learnings recommend /absolute/path/to/project
```

Search the local curated corpus:

```bash
learnings search "shutdown state recovery"
```

Inspect learnings usage:

```bash
learnings usage /absolute/path/to/project
```

Record whether a learning was adopted, rejected, or deferred:

```bash
learnings adopt <learning_id> /absolute/path/to/project
learnings reject <learning_id> /absolute/path/to/project --reason "Not relevant here"
learnings defer <learning_id> /absolute/path/to/project --reason "Revisit later"
```

## Optional Automation
Local synchronization remains optional. The core product works without scheduled automation or any networked exchange.

## Troubleshooting
- Run `./scripts/verify.sh` to confirm the repo is internally consistent.
- Use `feedback status /absolute/path/to/project` to inspect a local integration.
- Use `learnings --help` and `feedback --help` for command-level reference.
