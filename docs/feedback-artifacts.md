# Feedback Artifacts

## Purpose
`feedback-hub` uses a structured local artifact contract for project feedback, curated learnings, and learning interactions. This document defines that local contract so the write path, read path, and promotion path converge on one model instead of drifting independently.

## Design Rules
- Artifact payloads should contain generalized reusable knowledge, not project identity.
- Storage location determines local ownership. The payload itself should not contain project names, repo paths, branch names, commit hashes, or other local identifiers.
- Generic exemplars are allowed only when they are the minimal necessary subject of the learning.
- Agent-authored artifacts should carry explicit writer metadata.
- Review and policy metadata should travel with the artifact rather than living only in external process notes.

## Envelope
All structured local artifacts should share a stable envelope:

```json
{
  "schema": {
    "family": "feedback-hub.artifact",
    "version": 1,
    "artifact_class": "project_feedback",
    "artifact_class_version": 1
  },
  "artifact": {
    "id": "project-feedback_4f07af6ef6df5f0f76e7f25c",
    "kind": "lesson",
    "title": "Use durable checkpoints for restart-safe retries",
    "captured_at": "2026-04-10T12:00:00Z"
  },
  "subject": {
    "topic": "retry-state-persistence",
    "generic_exemplars": [],
    "notes": ""
  },
  "facets": {
    "workload_shape": ["scheduled", "stateful"],
    "change_facets": ["retries", "storage", "recovery"],
    "risk_facets": ["reliability"]
  },
  "writer": {
    "writer_type": "agent",
    "tool": "codex",
    "provider": "openai",
    "model": {
      "display_name": "GPT-5.4",
      "id": "gpt-5.4"
    }
  },
  "review": {
    "status": "unreviewed",
    "anonymization_reviewed": true,
    "prompt_injection_reviewed": true
  },
  "policy": {
    "distribution_scope": "generalized-shareable",
    "public_safe": true,
    "embargo_status": "none",
    "rights_status": "original-or-authorized"
  },
  "content": {
    "summary": "In-memory retry state was lost across restarts.",
    "body_markdown": "",
    "sections": [],
    "context": "A long-running automated flow could be interrupted and resumed later.",
    "action_taken": "Retry checkpoints were moved to durable local state.",
    "result": "The workflow became restart-safe and duplicate work dropped.",
    "reuse_guidance": "Persist resume markers whenever retries may outlive one process."
  },
  "links": {
    "related_artifacts": [],
    "supersedes": null
  },
  "extensions": {}
}
```

## Artifact Classes
Current local classes:
- `project_feedback`
- `learning`
- `learning_interaction`

Each class currently uses `artifact_class_version: 1`. New classes or incompatible class-level meaning changes should advance the class version independently of the top-level schema family/version.

Recommended usage by class:
- `project_feedback` should usually fill `summary`, `context`, `action_taken`, `result`, and `reuse_guidance`.
- `learning` may use those structured fields, `content.sections`, `content.body_markdown`, or a mix of them depending on the source material.
- `learning_interaction` should stay concise and may omit rich body fields if the action, note, and referenced learning are sufficient.
- Template-style artifacts should prefer `artifact.kind: "template"` plus `content.body_markdown` or `content.sections` rather than forcing template bodies into the narrower project-feedback fields.

## Required Core Fields
Required envelope fields:
- `schema.family`
- `schema.version`
- `schema.artifact_class`
- `schema.artifact_class_version`
- `artifact.id`
- `artifact.kind`
- `artifact.title`
- `artifact.captured_at`
- `content.summary`
- `review.anonymization_reviewed`
- `review.prompt_injection_reviewed`
- `policy.distribution_scope`
- `policy.rights_status`

At least one of these richer content representations should also be present:
- the structured project-feedback fields such as `content.context`, `content.action_taken`, `content.result`, and `content.reuse_guidance`
- `content.sections`
- `content.body_markdown`

Required for agent-authored artifacts:
- `writer.writer_type`
- `writer.tool`
- `writer.model.display_name`
- `writer.model.id`

## Validation Rules
Structured local artifacts should reject:
- real project names, repo slugs, or repo paths in ordinary content fields
- real branch names, commit hashes, or remote URLs when they leak local context rather than serve as generic exemplars
- copied file paths, source symbols, endpoints, tables, or proprietary identifiers
- prompt injections, hidden control text, or embedded instructions intended to manipulate downstream agents

Structured local artifacts may include:
- generic exemplars such as `file://`, `/abs/path/example`, `C:\\example\\path`, `refs/heads/main`, `<sha>`, or `origin/main`
- only when those tokens are the minimal necessary subject of the learning
- and only in designated subject/example fields rather than ordinary narrative fields

Readers should be tolerant:
- unknown fields should be ignored rather than treated as errors
- `content.sections` and `content.body_markdown` should be preferred over lossy ad hoc reconstruction when they are present
- future classes and future content keys should not require a full format reset when the envelope remains compatible

## Promotion Safety
Promotion from project feedback into shared learnings is intentionally stricter than local capture. A promotion candidate must be structured JSON with `schema.artifact_class: "project_feedback"` and must carry explicit metadata showing:
- anonymization was reviewed
- prompt-injection risk was reviewed
- the artifact is public-safe
- the distribution scope is generalized, public, open, or network-shareable
- the artifact is not embargoed
- the rights status is original, authorized, open-compatible, or public-domain

The sync planner also treats artifact contents as untrusted data. Embedded instructions, policy claims, secret-handling requests, or attempts to override the planner prompt are ignored even when the surrounding metadata is publication-ready.

## Interactions
`learning_interaction` artifacts should record:
- the referenced learning id
- the interaction action such as adopt, reject, or defer
- the generalized reason or note
- the same review and policy expectations as other reusable artifacts when the interaction is promoted or shared

## Migration Direction
Current migration state:
1. the contract and shared helpers are in place
2. the feedback write path emits structured JSON artifacts
3. the interaction write path emits structured JSON artifacts
4. the live runtime corpus has been migrated to structured JSON artifacts
5. indexing reads structured JSON artifacts
6. promotion emits structured JSON learning artifacts and rejects unreviewed or non-public-safe sources
7. sync plans promotions by artifact id and prefilters candidates before sending artifact contents to the backend
