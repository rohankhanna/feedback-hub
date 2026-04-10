# Governance

## What this does for you
- Keeps shared knowledge trustworthy by requiring explicit curation.
- Separates raw project feedback from validated cross-project learnings.
- Maintains traceability for what was promoted and when.

## Roles
- Each integrated project owns writes in its sovereign feedback area.
- Only the local manager workflow promotes artifacts into curated learnings.
- Source repositories outside `feedback-hub` should keep local integration paths gitignored.
- `feedback-hub` owns version-control decisions for the actual feedback and learning artifacts.

## Feedback Capture Rules
- During substantive agent-driven work, projects should create or update feedback artifacts as part of task execution.
- Artifacts should be generalized and anonymized before they are treated as reusable knowledge.
- Reusable learnings, decisions, incidents, incoming guidance, and outgoing recommendations should be recorded intentionally rather than as miscellaneous notes.
- Artifacts intended for reuse should avoid project-specific names, paths, and identifiers except as generic exemplars when those are the minimal necessary subject of the learning.
- The structured local artifact contract is documented in `docs/feedback-artifacts.md`.

## Promotion Safety
Before promotion into curated learnings, an artifact should be:
- clear about context, action, and result
- useful beyond a single project
- generalized enough to reuse safely
- reviewed for prompt-injection and other embedded control-text risks
- reviewed for sharing, rights, and public-safety constraints

## Auditability
- `scripts/promote_feedback.sh` appends a timestamped entry to `learnings/promotion-log.tsv`.
- `learnings validate` appends to `learnings/validation-log.tsv`.
- `learnings supersede` appends to `learnings/supersession-log.tsv`.

## Operating Default
- Keep curated learnings read-only outside active curation windows.
