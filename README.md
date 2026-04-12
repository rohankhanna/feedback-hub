# feedback-hub

## Project Intent
`feedback-hub` is a local-first feedback and learning system for software projects. It helps a developer or agent capture generalized project feedback, curate reusable learnings, and retrieve relevant guidance during future work, all from one local machine.

## What It Does
- Integrates local projects with managed feedback instructions.
- Captures generalized lessons, decisions, incidents, and adopted guidance during substantive work.
- Curates reusable learnings into a local shared memory.
- Recommends and searches relevant learnings during future work.

## Quickstart
```bash
# 1) Optional: install shell shims
./scripts/install_feedback.sh

# 2) Integrate a local project
./scripts/feedback.sh apply /absolute/path/to/project

# 3) Capture generalized feedback
./scripts/feedback.sh lesson "Short generalized lesson" /absolute/path/to/project

# 4) Build the local learnings index
./scripts/learnings.sh index

# 5) Search or request recommendations
./scripts/learnings.sh recommend /absolute/path/to/project
./scripts/learnings.sh search "shutdown state recovery"
```

The repo-local scripts are the canonical public interface. The installed `feedback` and `learnings` shims are optional convenience wrappers.

## Verification
Canonical verification path:

```bash
./scripts/verify.sh
```

If the generated architecture diagram drifts, refresh it with:

```bash
./scripts/render_architecture.sh --write
```

## How It Works
1. Each integrated project writes feedback into its own sovereign feedback area.
2. Projects do not write directly to curated learnings.
3. Reusable artifacts can be promoted into a local curated learnings layer.
4. Future work can search or request recommendations from that local corpus.

Managed integration encourages agents to consult local learnings during substantive work and to keep reusable feedback generalized, anonymized, and safe to share.

## Current Status
`feedback-hub` is currently a local-first single-node tool. The public product surface focuses on local integration, capture, curation, and retrieval. Cross-node exchange and decentralized recommendation remain future work and are not part of the current public shell.

## Architecture
- Architecture overview: `docs/architecture.md`
- Architecture decision records: `docs/adrs/README.md`
- Local artifact contract: `docs/feedback-artifacts.md`
- Governance and curation rules: `docs/governance.md`
- Operational guide: `docs/operations.md`

## Help
```bash
./scripts/feedback.sh --help
./scripts/learnings.sh --help
```
